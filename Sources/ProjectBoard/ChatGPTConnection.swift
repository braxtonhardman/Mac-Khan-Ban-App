import SwiftUI
import Observation
import CryptoKit
import Security
import Network
#if os(iOS)
import SafariServices
#else
import AppKit
#endif

// Only binds IPv4 loopback; mismatched state never consumes the pending sign-in.
@MainActor
final class ChatGPTCallbackListener {
    private var listener: NWListener?
    private var ready: CheckedContinuation<URL, Error>?
    private var callback: CheckedContinuation<URL, Error>?
    private var timeout: Task<Void, Never>?
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
        try await withCheckedThrowingContinuation { callback = $0 }
    }
    private func receive(_ connection: NWConnection) {
        connection.start(queue: .main)
        read(connection, buffer: Data())
    }
    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self else { connection.cancel(); return }
                var buffer = buffer
                if let data { buffer.append(data) }
                guard buffer.count <= 16384, error == nil else { connection.cancel(); return }
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
                    guard let callback = self.callback else { connection.cancel(); return }
                    self.callback = nil
                    self.respond(connection, status: "200 OK", message: "Return to Tierin to finish connecting ChatGPT.")
                    self.listener?.cancel(); self.listener = nil
                    self.timeout?.cancel()
                    callback.resume(returning: url)
                } else if complete { connection.cancel() }
                else { self.read(connection, buffer: buffer) }
            }
        }
    }
    private func respond(_ connection: NWConnection, status: String, message: String) {
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\nContent-Length: \(message.utf8.count)\r\nConnection: close\r\n\r\n\(message)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }
    func cancel() {
        listener?.cancel(); listener = nil
        timeout?.cancel(); timeout = nil
        let error = ChatGPTConnectionError.message("Sign-in was cancelled or timed out. Try again.")
        ready?.resume(throwing: error); ready = nil
        callback?.resume(throwing: error); callback = nil
    }
}

@MainActor @Observable
final class ChatGPTConnection {
    private(set) var account: ChatGPTAccount?
    private(set) var isBusy = false
    var error: String?
    var browserURL: URL?
    private var attemptID: UUID?
    private var registration: ChatGPTRegistration?
    private var awaitingBrowser = false
    private var listener: ChatGPTCallbackListener?
    func load() {
        do {
            if let data = try ChatGPTKeychain.read("registration") { registration = try JSONDecoder().decode(ChatGPTRegistration.self, from: data) }
            if let data = try ChatGPTKeychain.read("account") { account = try JSONDecoder().decode(ChatGPTAccount.self, from: data) }
        } catch { self.error = "Couldn’t load the saved ChatGPT connection." }
    }
    func connect(planUsage: Bool) async {
        guard !isBusy else { return }
        isBusy = true; error = nil
        let attempt = UUID(); attemptID = attempt
        defer { attemptID = nil; isBusy = false; awaitingBrowser = false; browserURL = nil; listener?.cancel(); listener = nil }
        do {
            let state = try ChatGPTOAuth.random(), nonce = try ChatGPTOAuth.random(), verifier = try ChatGPTOAuth.random()
            let listener = ChatGPTCallbackListener()
            self.listener = listener
            let callback = try await listener.start(state: state)
            let authorization = ChatGPTOAuth.authorizationURL(host: try ChatGPTOAuth.hostID(), callback: callback, state: state, nonce: nonce, verifier: verifier, account: account, registration: registration, planUsage: planUsage)
            awaitingBrowser = true
            #if os(iOS)
            browserURL = authorization
            #else
            guard NSWorkspace.shared.open(authorization) else { throw ChatGPTConnectionError.message("Couldn’t open your browser.") }
            #endif
            let url = try await listener.wait()
            awaitingBrowser = false; browserURL = nil
            let values = try ChatGPTOAuth.callbackValues(url, expectedURL: callback, state: state, clientID: account?.clientID ?? registration?.clientID)
            let connected = try await ChatGPTOAuth.exchange(code: values.code, client: values.client, verifier: verifier, callback: callback, nonce: nonce)
            guard attemptID == attempt else { throw CancellationError() }
            if let subject = account?.subject ?? registration?.subject, connected.subject != subject { throw ChatGPTConnectionError.message("Sign in with the connected account, or disconnect it first.") }
            let mapping = ChatGPTRegistration(subject: connected.subject, email: connected.email, clientID: connected.clientID)
            try ChatGPTKeychain.write(JSONEncoder().encode(mapping), name: "registration")
            try ChatGPTKeychain.write(JSONEncoder().encode(connected), name: "account")
            registration = mapping
            account = connected
        } catch { self.error = (error as? ChatGPTConnectionError)?.localizedDescription ?? "Couldn’t connect ChatGPT. Check your connection and try again." }
    }
    func browserDismissed() { if awaitingBrowser { listener?.cancel() } }
    func cancel() { attemptID = nil; listener?.cancel() }
    func disconnect() async {
        guard !isBusy, let account else { return }
        isBusy = true; error = nil
        defer { isBusy = false }
        var revoked = true
        do { try await ChatGPTOAuth.revoke(account) } catch { revoked = false }
        do {
            try ChatGPTKeychain.remove("account")
            self.account = nil
            if !revoked { error = "Disconnected on this device. Remote sign-out wasn’t confirmed; remove Tierin in ChatGPT Settings to finish." }
        } catch { self.error = error.localizedDescription }
    }
}

struct ChatGPTProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var connection: ChatGPTConnection
    @State private var allowPlanUsage = true
    var body: some View {
        NavigationStack {
            Form {
                AppSection("ChatGPT account") {
                    if let account = connection.account {
                        Label(account.email ?? "ChatGPT account", systemImage: "checkmark.circle")
                        Text(account.allowsPlanUsage ? "ChatGPT plan usage is enabled." : "Connected. ChatGPT plan usage is not enabled.")
                            .font(AppTypography.supporting).foregroundStyle(.secondary)
                        Button("Reconnect") { Task { await connection.connect(planUsage: allowPlanUsage) } }
                            .appGlassButton()
                        Button("Disconnect", role: .destructive) { Task { await connection.disconnect() } }
                            .appGlassButton()
                    } else {
                        Text("Connect your ChatGPT account to Tierin.").font(AppTypography.body)
                        Button("Continue with ChatGPT") { Task { await connection.connect(planUsage: allowPlanUsage) } }
                            .appGlassButton(accent: true)
                    }
                    Toggle("Allow ChatGPT plan usage", isOn: $allowPlanUsage)
                    Text("Eligible accounts can approve plan usage during sign-in. Connecting does not give Tierin access to your ChatGPT conversations.")
                        .font(AppTypography.caption).foregroundStyle(.secondary)
                }
                .disabled(connection.isBusy)
                if connection.isBusy {
                    HStack { ProgressView(); Text("Connecting…").font(AppTypography.supporting) }
                    Button("Cancel") { connection.cancel() }.appGlassButton()
                }
                if let error = connection.error {
                    Text(error).font(AppTypography.supporting).foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("ChatGPT")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { connection.cancel(); dismiss() } } }
        }
        .modifier(EditorSizing(width: 500, height: 560))
        .onDisappear { connection.cancel() }
        #if os(iOS)
        .sheet(isPresented: Binding(get: { connection.browserURL != nil }, set: { if !$0 { connection.browserURL = nil } }), onDismiss: connection.browserDismissed) {
            if let url = connection.browserURL { ChatGPTSignInBrowser(url: url) }
        }
        #endif
    }
}

#if os(iOS)
private struct ChatGPTSignInBrowser: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
#endif
