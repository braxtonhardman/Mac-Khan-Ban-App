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

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Profile & Settings", systemImage: "person.crop.circle").font(AppTypography.pageTitle)
                Spacer()
            }.padding(20)
            Form {
                AppSection("Appearance") {
                    Picker("Theme", selection: $draft.mode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }.pickerStyle(.segmented)
                    Text("System follows your device. Light or Dark overrides it for this app.")
                        .font(AppTypography.caption).foregroundStyle(.secondary)
                }
                AppSection("Board stages") {
                    ForEach(Array(TaskStatus.allCases.enumerated()), id: \.element.id) { index, status in
                        TextField(status.title, text: $draft.stageNames[index])
                    }
                    Text("These names apply to every project. The fifth stage always counts as completed work.")
                        .font(AppTypography.caption).foregroundStyle(.secondary)
                    if let validation = draft.validationError { Text(validation).foregroundStyle(.red) }
                }
                AppSection("Accent color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                        ForEach(AccentChoice.allCases) { choice in
                            Button { draft.accent = choice } label: {
                                VStack(spacing: 4) {
                                    Circle().fill(choice.color).frame(width: 30, height: 30)
                                        .overlay {
                                            if draft.accent == choice {
                                                Image(systemName: "checkmark").font(AppTypography.smallIcon).foregroundStyle(.black)
                                            }
                                        }
                                    Text(choice.title).font(AppTypography.caption).foregroundStyle(.primary)
                                }.frame(maxWidth: .infinity).padding(4)
                            }.buttonStyle(.plain)
                                .accessibilityLabel(choice.title)
                                .accessibilityAddTraits(draft.accent == choice ? .isSelected : [])
                        }
                    }
                }
                AppSection("Tags") {
                    TagSelector(selection: $tagNames, available: profiles.flatMap(\.tagNames) + allTasks.flatMap(\.tags), allowsRemoval: false)
                    Text("Create reusable tags here or while editing a task. Tags already used on tasks are available automatically.")
                        .font(AppTypography.caption).foregroundStyle(.secondary)
                }
                AppSection("iCloud") {
                    Text("Your appearance, stage names, accent color, and tags sync between Mac and iPhone when both use an iCloud build. Area collapse stays specific to each device.")
                        .font(AppTypography.caption).foregroundStyle(.secondary)
                    Button("Storage & Sync…") { showingSync = true }
                }
            }.formStyle(.grouped)
            if let error { Text(error).foregroundStyle(.red).padding(.horizontal) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent).disabled(draft.validationError != nil)
            }.padding(20)
        }
        .modifier(EditorSizing(width: 520, height: 660))
        .onAppear {
            guard !loaded else { return }
            draft = BoardAppearance(stageNames: TaskStatus.allCases.map { appearance.title(for: $0) }, accent: appearance.accent, mode: appearance.mode)
            tagNames = TagRules.normalized(profiles.flatMap(\.tagNames) + allTasks.flatMap(\.tags))
            loaded = true
        }
        .sheet(isPresented: $showingSync) { SyncStatusView() }
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
