import Foundation
import Network
import CryptoKit

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
    private var returnPage = ChatGPTReturnPage()
    func start(state: String, returnPage: ChatGPTReturnPage = .init()) async throws -> URL {
        expectedState = state
        self.returnPage = returnPage
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
                        self.respond(connection, status: "400 Bad Request", kind: .invalid); return
                    }
                    let callback = self.callback
                    self.callback = nil
                    self.stopped = true
                    if callback == nil { self.pendingURL = url }
                    for other in self.connections.values where other !== connection { other.cancel() }
                    self.connections = [ObjectIdentifier(connection): connection]
                    self.respond(connection, status: "200 OK", kind: items.contains(where: { $0.name == "error" }) ? .declined : .received)
                    self.listener?.cancel(); self.listener = nil
                    self.timeout?.cancel()
                    callback?.resume(returning: url)
                } else if complete { self.close(connection) }
                else { self.read(connection, buffer: buffer) }
            }
        }
    }
    private func respond(_ connection: NWConnection, status: String, kind: ChatGPTReturnPage.Kind) {
        let body = returnPage.html(kind: kind)
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nX-Content-Type-Options: nosniff\r\nContent-Security-Policy: \(ChatGPTReturnPage.contentSecurityPolicy)\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
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


/// Self-contained callback UI. No callback parameters or account information enter the HTML.
struct ChatGPTReturnPage {
    enum Kind { case received, declined, invalid }
    enum Appearance: String { case system, light, dark }
    var appearance: Appearance = .system
    var accentRed: UInt8 = 36
    var accentGreen: UInt8 = 150
    var accentBlue: UInt8 = 237

    // Replace this history entry so the one-time code is no longer visible in the address bar.
    private static let script = "history.replaceState(null, '', '/auth/complete');"
    private static let style = """
    * { box-sizing: border-box; }
    body { margin: 0; min-height: 100vh; min-height: 100svh; display: grid; place-items: center;
      padding: 32px 20px; background: Canvas; color: CanvasText;
      font: 16px/1.6 -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; }
    main { width: 100%; max-width: 480px; text-align: center; padding: 44px 36px 32px;
      background: color-mix(in srgb, CanvasText 3%, Canvas); border: 1px solid color-mix(in srgb, CanvasText 9%, transparent);
      border-radius: 32px; box-shadow: 0 16px 60px color-mix(in srgb, CanvasText 6%, transparent); }
    .brand { display: inline-flex; align-items: center; gap: 7px; font-size: 19px; font-weight: 650; letter-spacing: -.5px; }
    .brand svg { width: 36px; height: 36px; }
    .mark { margin: 30px auto 22px; width: 100px; height: 100px; display: grid; place-items: center;
      color: var(--accent); background: color-mix(in srgb, var(--accent) 10%, Canvas); border-radius: 27px; }
    .eyebrow { font-size: 11px; font-weight: 650; letter-spacing: .14em; text-transform: uppercase; color: color-mix(in srgb, CanvasText 60%, Canvas); }
    h1 { font-size: clamp(28px, 5vw, 34px); line-height: 1.18; letter-spacing: -1px; margin: 12px 0 16px; font-weight: 650; }
    p { margin: 0 auto; max-width: 350px; color: color-mix(in srgb, CanvasText 68%, Canvas); }
    .action { display: inline-flex; align-items: center; justify-content: center; gap: 12px; min-height: 50px;
      margin: 28px 0 26px; padding: 12px 24px; border-radius: 16px; font-weight: 600; text-decoration: none;
      color: CanvasText; background: color-mix(in srgb, var(--accent) 18%, Canvas);
      border: 1px solid color-mix(in srgb, var(--accent) 30%, Canvas); transition: background .16s ease; }
    .action:hover { background: color-mix(in srgb, var(--accent) 27%, Canvas); }
    .action:focus-visible { outline: 3px solid var(--accent); outline-offset: 4px; }
    .action svg { width: 18px; height: 18px; }
    footer { border-top: 1px solid color-mix(in srgb, CanvasText 8%, transparent); padding-top: 22px;
      color: color-mix(in srgb, CanvasText 52%, Canvas); font-size: 12px; }
    @media (max-width: 420px) { main { padding: 32px 22px 26px; border-radius: 26px; } }
    @media (prefers-reduced-motion: reduce) { .action { transition: none; } }
    """
    private static func hash(_ value: String) -> String {
        Data(SHA256.hash(data: Data(value.utf8))).base64EncodedString()
    }
    static var contentSecurityPolicy: String {
        "default-src 'none'; script-src 'sha256-\(hash(script))'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
    }
    func html(kind: Kind) -> String {
        let heading: String
        let detail: String
        let eyebrow: String
        switch kind {
        case .received:
            heading = "Return to Tierin"
            eyebrow = "Sign-in received"
            detail = "Continue in Tierin to finish verifying your ChatGPT connection and get back to your workspace."
        case .declined:
            heading = "Connection not completed"
            eyebrow = "ChatGPT connection"
            detail = "Return to Tierin to review the result. You can try connecting again whenever you’re ready."
        case .invalid:
            heading = "Let’s try that again"
            eyebrow = "Sign-in link not recognized"
            detail = "Open Tierin and start a new sign-in from Settings. This link couldn’t be matched to your request."
        }
        let scheme = appearance == .system ? "light dark" : appearance.rawValue
        return #"""
        <!doctype html>
        <html lang="en" style="color-scheme: \#(scheme); --accent: rgb(\#(accentRed) \#(accentGreen) \#(accentBlue))">
        <head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="\#(scheme)"><meta name="referrer" content="no-referrer">
        <title>\#(heading) · Tierin</title><style>\#(Self.style)</style></head>
        <body><main>
        <div class="brand">Tierin</div>
        <div class="mark"><svg xmlns="http://www.w3.org/2000/svg" width="88" height="88" viewBox="0 0 1024 1024" role="img" aria-label="Tierin"><g fill="currentColor"><path d="M440 208Q440 176 472 176H776Q808 176 808 208V504Q808 536 776 536H752V288Q752 232 696 232H440Z"/>
        <path d="M312 336Q312 304 344 304H648Q680 304 680 336V632Q680 664 648 664H624V416Q624 360 568 360H312Z"/>
        <path fill-rule="evenodd" d="M216 432H520Q552 432 552 464V776Q552 808 520 808H216Q184 808 184 776V464Q184 432 216 432Z
        M256 504Q244 504 244 516V736Q244 748 256 748H296Q308 748 308 736V516Q308 504 296 504Z
        M364 504Q352 504 352 516V580Q352 592 364 592H480Q492 592 492 580V516Q492 504 480 504Z
        M364 632Q352 632 352 644V736Q352 748 364 748H480Q492 748 492 736V644Q492 632 480 632Z"/></g></svg></div>
        <div class="eyebrow">\#(eyebrow)</div>
        <h1>\#(heading)</h1><p>\#(detail)</p>
        <a class="action" href="tierin://auth/return">Open Tierin
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12h14m-6-6 6 6-6 6"/></svg></a>
        <footer>You can close this tab after returning to the app.</footer>
        </main><script>\#(Self.script)</script></body></html>
        """#
    }
}
