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
    @Binding var selectedModel: String
    @State private var models: [TaskGPTModel] = []
    @State private var loadingModels = false
    @State private var modelError: String?
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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                IntegrationSettingsCard(title: "Account connection") {
                    IntegrationAccountHeader(service: "ChatGPT",
                        identity: connection.account?.email ?? "Connect your ChatGPT account to Tierin",
                        connected: connection.account != nil)
                    Divider()
                    if connection.account == nil && !connection.registrations.isEmpty {
                        Picker("Account", selection: $connection.selectedClientID) {
                            Text("Use another ChatGPT account").tag("")
                            ForEach(connection.registrations) { registration in
                                Text("\(registration.email ?? "ChatGPT account") · \(registration.clientID.suffix(6))")
                                    .tag(registration.clientID)
                            }
                        }
                    }
                    Toggle("Request ChatGPT plan usage", isOn: $allowPlanUsage)
                    Text("The GPT button sends a task’s description and ordered subtasks using your ChatGPT plan. Tierin does not read your ChatGPT conversations.")
                        .font(AppTypography.supporting).foregroundStyle(.secondary)
                    if let account = connection.account {
                        Text(account.allowsPlanUsage ? "Plan usage is enabled." : "Plan usage is not enabled.")
                            .font(AppTypography.caption).foregroundStyle(.secondary)
                        if allowPlanUsage != account.allowsPlanUsage {
                            Text("Reconnect to apply the permission change.")
                                .font(AppTypography.caption).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    ViewThatFits(in: .horizontal) {
                        HStack { connectionActions }
                        VStack(alignment: .leading, spacing: 12) { connectionActions }
                    }
                }
                .disabled(connection.isBusy)
                if connection.account?.allowsPlanUsage == true {
                    IntegrationSettingsCard(title: "Task model") {
                        if loadingModels {
                            ProgressView("Loading models…").font(AppTypography.supporting)
                        } else {
                            Picker("Model", selection: $selectedModel) {
                                Text("Choose a model").tag("")
                                if !selectedModel.isEmpty && !models.contains(where: { $0.slug == selectedModel }) {
                                    Text("\(selectedModel) · unavailable").tag(selectedModel)
                                }
                                ForEach(models) { model in Text(model.display_name).tag(model.slug) }
                            }
                            Text("Used for the GPT action in every task. Save your settings to apply your selection.")
                                .font(AppTypography.supporting).foregroundStyle(.secondary)
                        }
                        if let modelError {
                            Text(modelError).font(AppTypography.supporting).foregroundStyle(.red)
                            Button("Reload models") { Task { await loadModels() } }.appGlassButton()
                        }
                    }
                    .disabled(connection.isBusy)
                }
                ChatGPTHistoryStorageView()
                if connection.isBusy {
                    HStack {
                        ProgressView()
                        Text("Connecting…").font(AppTypography.supporting)
                        Spacer()
                        AppGlassActionButton(symbol: .cancel, accessibilityLabel: "Cancel sign-in", action: connection.cancel)
                    }
                }
                if let error = connection.error {
                    Text(error).font(AppTypography.supporting).foregroundStyle(.red)
                }
            }
            .padding(24)
        }
        .onAppear { allowPlanUsage = connection.account?.allowsPlanUsage ?? false }
        .task(id: connection.account?.expiresAt) { await loadModels() }
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
    @ViewBuilder private var connectionActions: some View {
        if connection.account != nil {
            Button("Reconnect") { Task { await connection.connect(planUsage: allowPlanUsage, returnPage: returnPage) } }
                .appGlassButton()
            Button("Disconnect", role: .destructive) { Task { await connection.disconnect() } }
                .appGlassButton()
        } else {
            Button("Continue with ChatGPT") { Task { await connection.connect(planUsage: allowPlanUsage, returnPage: returnPage) } }
                .appGlassButton(accent: true)
        }
    }

    private func loadModels() async {
        models = []; modelError = nil
        guard connection.account?.allowsPlanUsage == true else { return }
        loadingModels = true
        defer { loadingModels = false }
        do { models = try await TaskGPTClient.models() }
        catch {
            guard !Task.isCancelled else { return }
            modelError = (error as? ChatGPTConnectionError)?.localizedDescription ?? "Couldn’t load models. Please try again."
        }
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

private struct ChatGPTHistoryStorageView: View {
    @State private var history = TaskGPTRuns.shared
    @State private var confirmClear = false
    @State private var clearError: String?

    var body: some View {
        IntegrationSettingsCard(title: "GPT history storage") {
            HStack {
                Text("On this device").font(AppTypography.body)
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: history.historySizeBytes, countStyle: .file))
                    .font(AppTypography.itemTitle).monospacedDigit()
            }
            Text("Saved prompts and responses remain available after restarting Tierin. History is stored separately on each device.")
                .font(AppTypography.supporting).foregroundStyle(.secondary)
            if let error = clearError ?? history.persistenceError {
                Text(error).font(AppTypography.supporting).foregroundStyle(.red)
            }
            if history.hasActiveRuns {
                Text("Stop running GPT requests before clearing history.")
                    .font(AppTypography.supporting).foregroundStyle(.secondary)
            }
            Button("Clear GPT history", role: .destructive) { confirmClear = true }
                .appGlassButton()
                .disabled(history.hasActiveRuns || (history.historySizeBytes == 0 && history.runs.isEmpty))
        }
        .onAppear { history.flushHistory() }
        .confirmationDialog("Clear GPT history on this device?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear history", role: .destructive) {
                do { try history.clearHistory(); clearError = nil }
                catch { clearError = "Couldn’t clear GPT history. Please try again." }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently removes saved GPT prompts, responses and review history from this device. Your projects, tasks, completed status and ChatGPT connection stay unchanged.")
        }
    }
}
