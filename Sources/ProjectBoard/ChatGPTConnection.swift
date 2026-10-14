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
    private var saved = ChatGPTSavedConnections()
    var selectedClientID = ""
    var registrations: [ChatGPTRegistration] { saved.registrations }
    private var registration: ChatGPTRegistration? {
        saved.registrations.first { $0.clientID == selectedClientID }
    }
    private var awaitingBrowser = false
    private var listener: ChatGPTCallbackListener?
    func load() {
        do {
            if let data = try ChatGPTKeychain.read("connections") {
                saved = try JSONDecoder().decode(ChatGPTSavedConnections.self, from: data)
            } else {
                if let data = try ChatGPTKeychain.read("registration") {
                    saved.registrations = [try JSONDecoder().decode(ChatGPTRegistration.self, from: data)]
                }
                if let data = try ChatGPTKeychain.read("account") {
                    saved.connect(try JSONDecoder().decode(ChatGPTAccount.self, from: data))
                }
                try ChatGPTKeychain.write(JSONEncoder().encode(saved), name: "connections")
            }
            account = saved.account
            selectedClientID = account?.clientID ?? saved.registrations.first?.clientID ?? ""
            // Remove legacy copies only after the atomic record has been saved successfully.
            try ChatGPTKeychain.remove("account")
            try ChatGPTKeychain.remove("registration")
        } catch { self.error = "Couldn’t load the saved ChatGPT connection." }
    }
    func connect(planUsage: Bool, returnPage: ChatGPTReturnPage = .init()) async {
        guard !isBusy else { return }
        isBusy = true; error = nil
        let attempt = UUID(); attemptID = attempt
        let selectedAccount = account, selectedRegistration = registration
        defer { attemptID = nil; isBusy = false; awaitingBrowser = false; browserURL = nil; listener?.cancel(); listener = nil }
        do {
            let state = try ChatGPTOAuth.random(), nonce = try ChatGPTOAuth.random(), verifier = try ChatGPTOAuth.random()
            let listener = ChatGPTCallbackListener()
            self.listener = listener
            let callback = try await listener.start(state: state, returnPage: returnPage)
            guard attemptID == attempt else { throw CancellationError() }
            let authorization = ChatGPTOAuth.authorizationURL(host: try ChatGPTOAuth.hostID(), callback: callback, state: state, nonce: nonce, verifier: verifier, account: selectedAccount, registration: selectedRegistration, planUsage: planUsage)
            awaitingBrowser = true
            #if os(iOS)
            browserURL = authorization
            #else
            guard NSWorkspace.shared.open(authorization) else { throw ChatGPTConnectionError.message("Couldn’t open your browser.") }
            #endif
            let url = try await listener.wait()
            awaitingBrowser = false; browserURL = nil
            let values = try ChatGPTOAuth.callbackValues(url, expectedURL: callback, state: state, clientID: selectedAccount?.clientID ?? selectedRegistration?.clientID)
            let connected = try await ChatGPTOAuth.exchange(code: values.code, client: values.client, verifier: verifier, callback: callback, nonce: nonce)
            guard attemptID == attempt else { throw CancellationError() }
            if let subject = selectedAccount?.subject ?? selectedRegistration?.subject, connected.subject != subject {
                throw ChatGPTConnectionError.message("Sign in with the selected account. To switch, disconnect and choose another account.")
            }
            var updated = saved
            updated.connect(connected)
            try ChatGPTKeychain.write(JSONEncoder().encode(updated), name: "connections")
            saved = updated
            selectedClientID = connected.clientID
            account = connected
        } catch {
            if attemptID == attempt {
                self.error = (error as? ChatGPTConnectionError)?.localizedDescription ?? "Couldn’t connect ChatGPT. Check your connection and try again."
            }
        }
    }
    func browserDismissed() { if awaitingBrowser { listener?.cancel() } }
    func cancel() { attemptID = nil; awaitingBrowser = false; browserURL = nil; listener?.cancel() }
    func disconnect() async {
        guard !isBusy, let account else { return }
        isBusy = true; error = nil
        defer { isBusy = false }
        var revoked = true
        do { try await ChatGPTOAuth.revoke(account) } catch { revoked = false }
        do {
            var updated = saved
            updated.account = nil
            try ChatGPTKeychain.write(JSONEncoder().encode(updated), name: "connections")
            saved = updated
            self.account = nil
            if !revoked { error = "Disconnected on this device. Remote sign-out wasn’t confirmed; remove Tierin in ChatGPT Settings to finish." }
        } catch { self.error = error.localizedDescription }
    }
}

struct ChatGPTProfileView: View {
    @Bindable var connection: ChatGPTConnection
    @State private var allowPlanUsage = false
    @Environment(\.boardAppearance) private var appearance
    @Environment(\.self) private var environment
    private var returnPage: ChatGPTReturnPage {
        let accent = appearance.accent.color.resolve(in: environment)
        func channel(_ value: Float) -> UInt8 { UInt8(min(255, max(0, (value * 255).rounded()))) }
        return ChatGPTReturnPage(appearance: .init(rawValue: appearance.mode.rawValue) ?? .system,
                                accentRed: channel(accent.red), accentGreen: channel(accent.green), accentBlue: channel(accent.blue))
    }
    var body: some View {
        Form {
                AppSection("ChatGPT account") {
                    if let account = connection.account {
                        Label(account.email ?? "ChatGPT account", systemImage: "checkmark.circle")
                        Text(account.allowsPlanUsage ? "ChatGPT plan usage is enabled." : "Connected. ChatGPT plan usage is not enabled.")
                            .font(AppTypography.supporting).foregroundStyle(.secondary)
                        Button("Reconnect") { Task { await connection.connect(planUsage: allowPlanUsage, returnPage: returnPage) } }
                            .appGlassButton()
                        Button("Disconnect", role: .destructive) { Task { await connection.disconnect() } }
                            .appGlassButton()
                    } else {
                        Text("Connect your ChatGPT account to Tierin.").font(AppTypography.body)
                        if !connection.registrations.isEmpty {
                            Picker("Account", selection: $connection.selectedClientID) {
                                Text("Use another ChatGPT account").tag("")
                                ForEach(connection.registrations) { registration in
                                    Text("\(registration.email ?? "ChatGPT account") · \(registration.clientID.suffix(6))")
                                        .tag(registration.clientID)
                                }
                            }
                        }
                        Button("Continue with ChatGPT") { Task { await connection.connect(planUsage: allowPlanUsage, returnPage: returnPage) } }
                            .appGlassButton(accent: true)
                    }
                    Toggle("Request ChatGPT plan usage", isOn: $allowPlanUsage)
                    Text("This connects your account for future AI features. Tierin does not send tasks or read ChatGPT conversations. Plan usage is optional and does not run AI requests yet.")
                        .font(AppTypography.caption).foregroundStyle(.secondary)
                }
                .disabled(connection.isBusy)
                if connection.isBusy {
                    HStack { ProgressView(); Text("Connecting…").font(AppTypography.supporting) }
                    AppGlassActionButton(symbol: .cancel, accessibilityLabel: "Cancel sign-in", action: connection.cancel)
                }
                if let error = connection.error {
                    Text(error).font(AppTypography.supporting).foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
        .onAppear { allowPlanUsage = connection.account?.allowsPlanUsage ?? false }
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
