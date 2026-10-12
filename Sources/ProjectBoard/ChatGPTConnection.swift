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
            guard attemptID == attempt else { throw CancellationError() }
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
                    Toggle("Request ChatGPT plan usage", isOn: $allowPlanUsage)
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
            if let url = connection.browserURL {
                ChatGPTSignInBrowser(url: url) {
                    connection.browserDismissed()
                    connection.browserURL = nil
                }
            }
        }
        #endif
    }
}

#if os(iOS)
private struct ChatGPTSignInBrowser: UIViewControllerRepresentable {
    let url: URL
    let onFinish: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) { onFinish() }
    }
}
#endif
