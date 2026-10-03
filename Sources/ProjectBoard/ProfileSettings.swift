import SwiftUI
import SwiftData
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
    @State private var titlebarClearance: CGFloat = 0
    @Query private var profiles: [AppProfile]
    var body: some View {
        let appearance = AppProfile.current(in: profiles)?.appearance ?? BoardAppearance()
        ContentView(isFullScreen: titlebarClearance > 0)
            #if os(macOS)
            .background(Color(nsColor: .windowBackgroundColor))
            .background(SolidTitlebarBackground { titlebarClearance = $0 })
            #endif
            .font(AppTypography.body)
            .environment(\.boardAppearance, appearance)
            .tint(appearance.accent.color)
            .accentColor(appearance.accent.color)
            .preferredColorScheme(appearance.mode.colorScheme)
    }
}

struct ProfileSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.boardAppearance) private var appearance
    @Query private var profiles: [AppProfile]
    @Query private var allTasks: [BoardTask]
    @State private var tagNames: [String] = []
    @State private var draft = BoardAppearance()
    @State private var loaded = false
    @State private var error: String?
    @State private var showingSync = false
    @State private var selectedIntegration: AccountIntegration?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                settingsHeader
                Form {
                    Section { profileHeader }
                    Section {
                        Button { showingSync = true } label: { syncSummaryCard }
                            .buttonStyle(.plain)
                    }
                    AppSection("Accounts") {
                        ForEach(AccountIntegration.allCases) { integration in
                            Button { selectedIntegration = integration } label: {
                                SettingsRowLabel(
                                    icon: integration.icon,
                                    title: integration.title,
                                    subtitle: "Not connected",
                                    value: "Set up later"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    AppSection("General") {
                        NavigationLink {
                            AppearanceSettingsPage(draft: $draft)
                        } label: {
                            SettingsRowLabel(
                                icon: "paintpalette",
                                title: "Appearance",
                                subtitle: "Theme and accent color",
                                value: draft.mode.title
                            )
                        }
                        NavigationLink {
                            BoardStageSettingsPage(stageNames: $draft.stageNames)
                        } label: {
                            SettingsRowLabel(
                                icon: "rectangle.3.group",
                                title: "Board stages",
                                subtitle: "Names used across every project",
                                value: "\(draft.stageNames.count) stages"
                            )
                        }
                        NavigationLink {
                            TagLibrarySettingsPage(
                                tagNames: $tagNames,
                                available: profiles.flatMap(\.tagNames) + allTasks.flatMap(\.tags)
                            )
                        } label: {
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
                if let error { Text(error).foregroundStyle(.red).padding(.horizontal) }
                HStack {
                    Button("Cancel") { dismiss() }
                        .appGlassButton()
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Save") { save() }
                        .appGlassButton(accent: true)
                        .keyboardShortcut(.defaultAction)
                        .disabled(draft.validationError != nil)
                }.padding(20)
            }
        }
        .modifier(EditorSizing(width: 560, height: 720))
        .onAppear {
            guard !loaded else { return }
            draft = BoardAppearance(stageNames: TaskStatus.allCases.map { appearance.title(for: $0) }, accent: appearance.accent, mode: appearance.mode)
            tagNames = TagRules.normalized(profiles.flatMap(\.tagNames) + allTasks.flatMap(\.tags))
            loaded = true
        }
        .sheet(isPresented: $showingSync) { SyncStatusView() }
        .sheet(item: $selectedIntegration) { AccountIntegrationView(integration: $0) }
    }

    private var settingsHeader: some View {
        ZStack {
            Text("Settings").font(AppTypography.pageTitle)
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(AppTypography.smallIcon)
                }
                .appGlassButton(shape: .circle)
                .accessibilityLabel("Close Settings")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var profileHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 58))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Workspace Profile").font(AppTypography.sectionTitle)
                Text(SyncStatus.isCloudBuild ? "Private iCloud profile" : "Local profile")
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
        do { try StoreWriter.save(context); dismiss() }
        catch { self.error = error.localizedDescription }
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

private enum AccountIntegration: String, CaseIterable, Identifiable {
    case github
    case openAI

    var id: String { rawValue }
    var title: String { self == .github ? "GitHub" : "OpenAI / ChatGPT" }
    var icon: String { self == .github ? "chevron.left.forwardslash.chevron.right" : "sparkles" }
    var summary: String {
        switch self {
        case .github:
            return "A future GitHub connection will attach issues and pull requests to tasks."
        case .openAI:
            return "A future OpenAI connection will support task planning and project assistance."
        }
    }
}

private struct AccountIntegrationView: View {
    @Environment(\.dismiss) private var dismiss
    let integration: AccountIntegration

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text(integration.title).font(AppTypography.pageTitle)
                Spacer()
                Button("Done") { dismiss() }
                    .appGlassButton(accent: true)
                    .keyboardShortcut(.cancelAction)
            }
            Image(systemName: integration.icon)
                .font(.system(size: 46))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Not connected").font(AppTypography.sectionTitle)
            Text(integration.summary)
                .font(AppTypography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Label("Connection setup is planned for a later integration release.", systemImage: "clock")
                .font(AppTypography.supporting)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Connect \(integration.title)") {}
                .appGlassButton(accent: true)
                .disabled(true)
        }
        .padding(24)
        .modifier(EditorSizing(width: 430, height: 360))
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
                                            Image(systemName: "checkmark")
                                                .font(AppTypography.smallIcon)
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
        .navigationTitle("Appearance")
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
                Text("These names apply to every project. The fifth stage always counts as completed work.")
                    .font(AppTypography.caption).foregroundStyle(.secondary)
                let draft = BoardAppearance(stageNames: stageNames)
                if let validation = draft.validationError { Text(validation).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Board Stages")
    }
}

private struct TagLibrarySettingsPage: View {
    @Binding var tagNames: [String]
    let available: [String]

    var body: some View {
        Form {
            AppSection("Tags") {
                TagSelector(selection: $tagNames, available: available, allowsRemoval: false)
                Text("Create reusable tags here or while editing a task. Tags already used on tasks are available automatically.")
                    .font(AppTypography.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Tags")
    }
}
