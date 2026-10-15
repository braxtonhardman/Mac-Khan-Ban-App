import SwiftUI
import SwiftData
import EventKit
#if SWIFT_PACKAGE
import BoardCore
#endif

private struct BoardAppearanceKey: EnvironmentKey {
    static let defaultValue = BoardAppearance()
}
extension EnvironmentValues {
    var boardAppearance: BoardAppearance {
        get { self[BoardAppearanceKey.self] }
        set { self[BoardAppearanceKey.self] = newValue }
    }
}
extension AccentChoice {
    var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .teal: return .teal
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        }
    }
}

extension AppearanceMode {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct AppRootView: View {
    @Environment(\.modelContext) private var calendarContext
    @StateObject private var calendarIntegration = CalendarIntegration.shared
    @Query private var calendarTasks: [BoardTask]
    private var calendarRevision: [String] {
        calendarTasks.map { "\($0.id)|\($0.status.rawValue)|\($0.title)|\($0.details)|\($0.dueDate?.timeIntervalSince1970 ?? 0)|\($0.project?.name ?? "")" }.sorted()
    }
    private func configureCalendar() {
        let profile = AppProfile.current(in: profiles)
        calendarIntegration.configure(context: calendarContext,
            accountID: profile?.appleUserIdentifier ?? profile?.id.uuidString ?? "local",
            active: appleSessionActive && profile?.hasCompletedOnboarding == true && scenePhase != .background)
    }

    @StateObject private var purchases = PurchaseStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var titlebarClearance: CGFloat = 0
    @Query private var profiles: [AppProfile]
    @AppStorage("appleSessionActive") private var appleSessionActive = false
    var body: some View {
        let appearance = AppProfile.current(in: profiles)?.appearance ?? BoardAppearance()
        Group {
            if appleSessionActive, AppProfile.current(in: profiles)?.hasCompletedOnboarding == true {
                ContentView(isFullScreen: titlebarClearance > 0)
            } else {
                OnboardingFlowView()
            }
        }
            #if os(macOS)
            .background(Color(nsColor: .windowBackgroundColor))
            .background(SolidTitlebarBackground { titlebarClearance = $0 })
            #endif
            .environmentObject(purchases)
            .task {
                configureCalendar()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(30)) } catch { break }
                    calendarIntegration.schedule()
                }
            }
            .onChange(of: appleSessionActive) { _, _ in configureCalendar() }
            .onChange(of: AppProfile.current(in: profiles)?.appleUserIdentifier) { _, _ in configureCalendar() }
            .onChange(of: AppProfile.current(in: profiles)?.hasCompletedOnboarding) { _, _ in configureCalendar() }
            .onChange(of: calendarRevision) { _, _ in calendarIntegration.schedule() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TierinStoreDidSave"))) { _ in
                calendarIntegration.schedule()
            }
            .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
                calendarIntegration.schedule()
            }
            .task {
                // Also notice expiration while a window remains open without navigation.
                while !Task.isCancelled {
                    await purchases.refreshEntitlements()
                    do { try await Task.sleep(for: .seconds(60)) } catch { break }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await purchases.refreshEntitlements() } }
                configureCalendar()
            }
            .font(AppTypography.body)
            .environment(\.boardAppearance, appearance)
            .tint(appearance.accent.color)
            .accentColor(appearance.accent.color)
            .preferredColorScheme(appearance.mode.colorScheme)
    }
}

struct ProfileSettingsView: View {
    @EnvironmentObject private var purchases: PurchaseStore
    @State private var showingUnlimited = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.boardAppearance) private var appearance
    @Query private var profiles: [AppProfile]
    @Query private var allTasks: [BoardTask]
    @State private var tagNames: [String] = []
    @State private var draft = BoardAppearance()
    @State private var loaded = false
    @State private var error: String?
    @State private var page: ProfilePage?
    @State private var confirmingSignOut = false
    @AppStorage("appleSessionActive") private var appleSessionActive = false
    let onClose: (() -> Void)?

    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            settingsHeader
            Group {
                if let page {
                    switch page {
                    case .account:
                        AppleAccountSettingsPage(
                            displayName: AppProfile.current(in: profiles)?.displayName,
                            isCloudEnabled: SyncStatus.isCloudBuild,
                            signOut: { confirmingSignOut = true }
                        )
                    case .sync:
                        ScrollView { SyncStatusView() }
                    case .calendar:
                        CalendarSettingsView()
                    case .appearance:
                        AppearanceSettingsPage(draft: $draft)
                    case .stages:
                        BoardStageSettingsPage(stageNames: $draft.stageNames)
                    case .tags:
                        TagLibrarySettingsPage(tagNames: $tagNames, available: profiles.flatMap(\.tagNames) + allTasks.flatMap(\.tags))
                    }
                } else {
                    mainMenu
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            if let error { Text(error).foregroundStyle(.red).padding(.horizontal) }
        }
        .modifier(EditorSizing(width: 560, height: 720))
        .modifier(TagCreationHost(backToParent: true))
        .onAppear {
            guard !loaded else { return }
            draft = BoardAppearance(stageNames: TaskStatus.allCases.map { appearance.title(for: $0) }, accent: appearance.accent, mode: appearance.mode)
            tagNames = TagRules.normalized(profiles.flatMap(\.tagNames) + allTasks.flatMap(\.tags))
            loaded = true
        }
        .unlimitedPaywall(isPresented: $showingUnlimited, backToSettings: true)
        .confirmationDialog("Sign out of Tierin?", isPresented: $confirmingSignOut) {
            Button("Sign Out", role: .destructive, action: signOut)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your projects will remain in iCloud and on this device. You can sign back in with Apple at any time.")
        }
    }

    private var mainMenu: some View {
        Form {
            Section {
                Button { page = .account } label: {
                    profileHeader
                }
            }
            Section {
                Button { page = .sync } label: { syncSummaryCard }
                    .buttonStyle(.plain)
            }
            AppSection("Plan") {
                Button { showingUnlimited = true } label: {
                    SettingsRowLabel(
                        icon: "sparkles",
                        title: purchases.hasUnlimited ? "Tierin Unlimited" : "Free plan",
                        subtitle: purchases.hasUnlimited ? "Unlimited projects and areas" : "5 projects · 2 areas · Unlimited tasks",
                        value: purchases.hasUnlimited ? "Manage" : "Upgrade"
                    )
                }
                .buttonStyle(.plain)
            }
            AppSection("Calendar") {
                Button { page = .calendar } label: {
                    SettingsRowLabel(icon: "calendar", title: "Apple Calendar",
                        subtitle: "Choose a calendar and sync task deadlines", value: "Configure")
                }.buttonStyle(.plain)
            }
            AppSection("General") {
                Button { page = .appearance } label: {
                    SettingsRowLabel(
                        icon: "paintpalette",
                        title: "Appearance",
                        subtitle: "Theme and accent color",
                        value: draft.mode.title
                    )
                }
                Button { page = .stages } label: {
                    SettingsRowLabel(
                        icon: AppSymbols.project,
                        title: "Board stages",
                        subtitle: "Names used across every project",
                        value: "\(draft.stageNames.count) stages"
                    )
                }
                Button { page = .tags } label: {
                    SettingsRowLabel(
                        icon: "tag",
                        title: "Tags",
                        subtitle: "Reusable task labels",
                        value: "\(tagNames.count)"
                    )
                }
            }
        }
        .formStyle(.grouped)
        .buttonStyle(.plain)
    }

    private var settingsHeader: some View {
        ZStack {
            Text(page?.title ?? "Settings").font(AppTypography.pageTitle)
            HStack {
                AppGlassActionButton(
                    symbol: page == nil ? .cancel : .back,
                    accessibilityLabel: page == nil ? "Cancel" : "Back to Settings",
                    action: {
                        if page != nil { page = nil } else { close() }
                    }
                )
                .keyboardShortcut(.cancelAction)
                Spacer()
                AppGlassActionButton(
                    symbol: .confirm,
                    accessibilityLabel: "Save",
                    accent: true,
                    action: save
                )
                .keyboardShortcut(.defaultAction)
                .disabled(draft.validationError != nil)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var profileHeader: some View {
        let profile = AppProfile.current(in: profiles)
        return HStack(spacing: 14) {
            ProfileInitial(displayName: profile?.displayName)
                .foregroundStyle(.tint)
                .frame(width: 58, height: 58)
                .background(Color.accentColor.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(profile?.displayName ?? "Tierin Profile").font(AppTypography.sectionTitle)
                Text(profile?.appleUserIdentifier == nil ? "Apple account not connected" : "Signed in with Apple")
                    .font(AppTypography.supporting)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(AppTypography.controlIcon)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private var syncSummaryCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Current storage").font(AppTypography.caption).foregroundStyle(.secondary)
                Text(SyncStatus.isCloudBuild ? "iCloud Sync" : "On This Device")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(.tint)
                Text(SyncStatus.isCloudBuild ? "Projects and profile preferences sync between devices." : "Projects and preferences remain on this device.")
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Text("Manage")
                .font(AppTypography.metadataEmphasis)
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.quaternary, in: Capsule())
        }
        .contentShape(Rectangle())
        .padding(.vertical, 8)
    }
    private func save() {
        guard draft.validationError == nil else { return }
        let names = draft.stageNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let profile = AppProfile.current(in: profiles) ?? AppProfile(stageNames: names, accent: draft.accent)
        if profile.modelContext == nil { context.insert(profile) }
        profile.stageNames = names
        profile.accentName = draft.accent.rawValue
        profile.appearanceMode = draft.mode.rawValue
        profile.tagNames = TagRules.normalized(profiles.flatMap(\.tagNames) + allTasks.flatMap(\.tags) + tagNames)
        profile.updatedAt = Date()
        do { try StoreWriter.save(context); close() }
        catch { self.error = error.localizedDescription }
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    private func signOut() {
        appleSessionActive = false
        close()
    }
}

private enum ProfilePage {
    case account, sync, calendar, appearance, stages, tags
    var title: String {
        switch self {
        case .account: "Apple Account"
        case .sync: "Storage & Sync"
        case .calendar: "Apple Calendar"
        case .appearance: "Appearance"
        case .stages: "Board Stages"
        case .tags: "Tags"
        }
    }
}

private struct AppleAccountSettingsPage: View {
    let displayName: String?
    let isCloudEnabled: Bool
    let signOut: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 10) {
                        ProfileInitial(displayName: displayName)
                            .foregroundStyle(.tint)
                            .frame(width: 72, height: 72)
                            .background(Color.accentColor.opacity(0.12), in: Circle())
                        Text(displayName ?? "Apple Account")
                            .font(AppTypography.pageTitle)
                        Label("Signed in with Apple", systemImage: "apple.logo")
                            .font(AppTypography.supporting)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(22)
                    .appCardSurface()

                    VStack(alignment: .leading, spacing: 12) {
                        Label(
                            isCloudEnabled ? "Projects sync privately through iCloud." : "Projects are stored on this device.",
                            systemImage: isCloudEnabled ? "icloud.fill" : "internaldrive.fill"
                        )
                        Label("Signing out does not delete your projects.", systemImage: "checkmark.shield.fill")
                    }
                    .font(AppTypography.supporting)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .appCardSurface()
                }
                .padding(20)
            }

            Button(action: signOut) {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    .foregroundStyle(.red)
            }
            .appGlassButton(size: .large, shape: .rectangle)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

private struct SettingsRowLabel: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var value: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(AppTypography.itemTitle)
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppTypography.body).foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle).font(AppTypography.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 10)
            if let value {
                Text(value).font(AppTypography.caption).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 7)
    }
}

private struct AppearanceSettingsPage: View {
    @Binding var draft: BoardAppearance

    var body: some View {
        Form {
            AppSection("Theme") {
                Picker("Theme", selection: $draft.mode) {
                    ForEach(AppearanceMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .pickerStyle(.segmented)
                Text("System follows your device. Light or Dark overrides it for this app.")
                    .font(AppTypography.caption).foregroundStyle(.secondary)
            }
            AppSection("Accent color") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                    ForEach(AccentChoice.allCases) { choice in
                        Button { draft.accent = choice } label: {
                            VStack(spacing: 5) {
                                Circle().fill(choice.color).frame(width: 32, height: 32)
                                    .overlay {
                                        if draft.accent == choice {
                                            AppActionGlyph(symbol: .confirm, size: .small)
                                                .foregroundStyle(.black)
                                        }
                                    }
                                Text(choice.title).font(AppTypography.caption).foregroundStyle(.primary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(choice.title)
                        .accessibilityAddTraits(draft.accent == choice ? .isSelected : [])
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct BoardStageSettingsPage: View {
    @Binding var stageNames: [String]

    var body: some View {
        Form {
            AppSection("Board stages") {
                ForEach(Array(TaskStatus.allCases.enumerated()), id: \.element.id) { index, status in
                    TextField(status.title, text: $stageNames[index])
                }
                Text("These names apply to every project. The fourth stage always counts as completed work.")
                    .font(AppTypography.caption).foregroundStyle(.secondary)
                let draft = BoardAppearance(stageNames: stageNames)
                if let validation = draft.validationError { Text(validation).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
    }
}

private struct TagLibrarySettingsPage: View {
    @Binding var tagNames: [String]
    let available: [String]

    var body: some View {
        ScrollView {
            TagSelector(selection: $tagNames, available: available, allowsRemoval: false, tagsBelowSearch: true)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
        }
    }
}
