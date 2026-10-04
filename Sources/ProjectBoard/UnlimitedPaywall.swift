import SwiftUI
#if SWIFT_PACKAGE
import BoardCore
#endif

struct UnlimitedPaywall: View {
    @EnvironmentObject private var purchases: PurchaseStore
    let reason: WorkspaceResource?
    let close: () -> Void
    var backToSettings = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                AppGlassActionButton(symbol: backToSettings ? .back : .cancel, accessibilityLabel: backToSettings ? "Back to Settings" : "Close", action: close)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Text("Tierin Unlimited").font(AppTypography.pageTitle)
                Spacer()
                Color.clear.frame(width: AppGlassButtonSize.medium.dimension, height: 1)
            }
            .padding(20)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    WorkspaceMark(size: 72)
                        .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(purchases.hasUnlimited ? "Room for every project" : "Make room for your next idea")
                            .font(AppTypography.boardTitle)
                        Text(purchases.hasUnlimited ? "Your subscription includes unlimited projects and areas on Mac and iPhone." : (reason?.limitMessage ?? "Start free with 3 projects and 1 area. Unlock unlimited space as your plans grow."))
                            .font(AppTypography.supporting)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Unlimited projects", systemImage: AppSymbols.project)
                        Label("Unlimited areas", systemImage: "folder")
                        Label("Monthly subscription. Cancel anytime.", systemImage: "checkmark.seal")
                        Label("Tasks and subtasks stay free", systemImage: "checklist")
                        Label("Use on Mac and iPhone", systemImage: "desktopcomputer")
                    }
                    .font(AppTypography.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .appCardSurface()

                    VStack(spacing: 14) {
                        if !purchases.hasCheckedEntitlements || purchases.isLoadingOffer {
                            ProgressView("Checking purchases…")
                        } else if purchases.hasUnlimited {
                            Label("Unlimited is unlocked", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.tint)
                        } else if !purchases.checkoutEnabled {
                            Text("Unlimited purchasing is not available yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            Button {
                                Task { await purchases.purchase() }
                            } label: {
                                Text(purchases.price.map { "Subscribe · \($0) / month" } ?? "Purchase unavailable")
                            }
                            .appGlassButton(size: .large, shape: .rectangle, accent: true)
                            .disabled(!purchases.canPurchase)
                            if purchases.price == nil {
                                Button("Try Again") { Task { await purchases.prepare() } }
                                    .appGlassButton(size: .medium, shape: .rectangle)
                                    .disabled(purchases.isBusy)
                            }
                        }
                        Button("Restore Purchases") { Task { await purchases.restore() } }
                            .appGlassButton(size: .medium, shape: .rectangle)
                            .disabled(purchases.isBusy)
                        if purchases.isBusy { ProgressView() }
                        if let message = purchases.message {
                            Text(message).font(AppTypography.supporting)
                                .multilineTextAlignment(.center)
                                .accessibilityLabel(message)
                        }
                        Text("Renews automatically each month until cancelled. Payment is charged to your Apple Account. Manage or cancel in App Store account settings. Any applicable tax is shown at checkout.")
                            .font(AppTypography.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Link("Manage Subscription", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                            .font(AppTypography.supporting)
                        Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                            .font(AppTypography.caption)
                        DisclosureGroup("Privacy Policy") {
                            Text("Tierin stores projects, tasks, profile details, and onboarding preferences on your device and, in iCloud builds, in your private iCloud database. Sign in with Apple provides your account identifier and any name or email you choose to share. Apple processes subscriptions; Tierin uses verified purchase records to determine access and does not receive your card details. Calendar access is used only when you choose to export a task deadline. Tierin contains no advertising or analytics SDK. GitHub and ChatGPT connections are not active. You can delete workspace items in the app; signing out does not delete saved data.")
                                .font(AppTypography.caption)
                                .foregroundStyle(.secondary)
                        }
                        .font(AppTypography.caption)
                        Text("Purchases belong to your App Store account. Use the same account on both devices to restore access.")
                            .font(AppTypography.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
        .modifier(EditorSizing(width: 480, height: 620))
        .task { await purchases.prepare() }
        .onChange(of: purchases.hasUnlimited) { _, unlocked in
            if unlocked { close() }
        }
        #if os(iOS)
        .presentationDetents([.large])
        #endif
    }
}

private struct UnlimitedPaywallPresentation: ViewModifier {
    @Binding var isPresented: Bool
    let reason: WorkspaceResource?
    let inlineOnMac: Bool
    let backToSettings: Bool
    func body(content: Content) -> some View {
        #if os(macOS)
        if inlineOnMac && isPresented {
            // The enclosing editor already supplies the in-window glass modal.
            // Replace its contents so a short Area editor cannot clip this taller view.
            UnlimitedPaywall(reason: reason, close: { isPresented = false }, backToSettings: backToSettings)
        } else {
            content.overlay {
                if isPresented {
                    MacInWindowModal(onDismiss: { isPresented = false }) {
                        UnlimitedPaywall(reason: reason, close: { isPresented = false }, backToSettings: backToSettings)
                    }
                }
            }
        }
        #else
        content.sheet(isPresented: $isPresented) {
            UnlimitedPaywall(reason: reason, close: { isPresented = false }, backToSettings: backToSettings)
        }
        #endif
    }
}

extension View {
    func unlimitedPaywall(isPresented: Binding<Bool>, reason: WorkspaceResource? = nil, inlineOnMac: Bool = false, backToSettings: Bool = false) -> some View {
        modifier(UnlimitedPaywallPresentation(isPresented: isPresented, reason: reason, inlineOnMac: inlineOnMac, backToSettings: backToSettings))
    }
}
