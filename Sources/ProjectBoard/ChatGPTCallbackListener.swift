import Foundation
import Network

// Only binds IPv4 loopback; mismatched state never consumes the pending sign-in.
@MainActor
final class ChatGPTCallbackListener {
    private var listener: NWListener?
    private var ready: CheckedContinuation<URL, Error>?
    private var callback: CheckedContinuation<URL, Error>?
    private var timeout: Task<Void, Never>?
    private var stopped = false
    private var pendingURL: URL?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var expectedState = ""
    private var callbackURL: URL?
    func start(state: String) async throws -> URL {
        expectedState = state
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.receive(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let port = self.listener?.port,
                          let url = URL(string: "http://127.0.0.1:\(port.rawValue)/auth/callback") else { self.cancel(); return }
                    self.callbackURL = url
                    self.ready?.resume(returning: url); self.ready = nil
                case .failed: self.cancel()
                default: break
                }
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            ready = continuation
            listener.start(queue: .main)
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(180))
                if !Task.isCancelled { self?.cancel() }
            }
        }
    }
    func wait() async throws -> URL {
        if let pendingURL { self.pendingURL = nil; return pendingURL }
        guard !stopped, listener != nil, callback == nil else { throw ChatGPTConnectionError.message("Sign-in was cancelled or timed out. Try again.") }
        return try await withCheckedThrowingContinuation { callback = $0 }
    }
    private func receive(_ connection: NWConnection) {
        guard !stopped, connections.count < 16 else { connection.cancel(); return }
        connections[ObjectIdentifier(connection)] = connection
        connection.start(queue: .main)
        read(connection, buffer: Data())
    }
    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, !self.stopped else { connection.cancel(); return }
                var buffer = buffer
                if let data { buffer.append(data) }
                guard buffer.count <= 16384, error == nil else { self.close(connection); return }
                if let text = String(data: buffer, encoding: .utf8), text.contains("\r\n\r\n") {
                    let line = text.components(separatedBy: "\r\n")[0].components(separatedBy: " ")
                    guard line.count == 3, line[0] == "GET", line[1].hasPrefix("/auth/callback?"),
                          let expected = self.callbackURL,
                          let url = URL(string: "http://127.0.0.1:\(expected.port!)" + line[1]),
                          let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                          items.filter({ $0.name == "state" }).count == 1,
                          items.first(where: { $0.name == "state" })?.value == self.expectedState else {
                        self.respond(connection, status: "400 Bad Request", message: "Invalid sign-in callback."); return
                    }
                    let callback = self.callback
                    self.callback = nil
                    self.stopped = true
                    if callback == nil { self.pendingURL = url }
                    for other in self.connections.values where other !== connection { other.cancel() }
                    self.connections = [ObjectIdentifier(connection): connection]
                    self.respond(connection, status: "200 OK", message: "Return to Tierin to finish connecting ChatGPT.")
                    self.listener?.cancel(); self.listener = nil
                    self.timeout?.cancel()
                    callback?.resume(returning: url)
                } else if complete { self.close(connection) }
                else { self.read(connection, buffer: buffer) }
            }
        }
    }
    private func respond(_ connection: NWConnection, status: String, message: String) {
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\nContent-Length: \(message.utf8.count)\r\nConnection: close\r\n\r\n\(message)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] _ in
            connection.cancel()
            Task { @MainActor in self?.connections.removeValue(forKey: ObjectIdentifier(connection)) }
        })
    }
    private func close(_ connection: NWConnection) {
        connection.cancel()
        connections.removeValue(forKey: ObjectIdentifier(connection))
    }
    func cancel() {
        stopped = true
        pendingURL = nil
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
        listener?.cancel(); listener = nil
        timeout?.cancel(); timeout = nil
        let error = ChatGPTConnectionError.message("Sign-in was cancelled or timed out. Try again.")
        ready?.resume(throwing: error); ready = nil
        callback?.resume(throwing: error); callback = nil
    }
}

