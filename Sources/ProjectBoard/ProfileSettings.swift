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
            .environment(\.boardAppearance, appearance)
            .tint(appearance.accent.color)
            .accentColor(appearance.accent.color)
    }
}

struct ProfileSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.boardAppearance) private var appearance
    @Query private var profiles: [AppProfile]
    @State private var draft = BoardAppearance()
    @State private var loaded = false
    @State private var error: String?
    @State private var showingSync = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Profile & Settings", systemImage: "person.crop.circle").font(.title2.bold())
                Spacer()
            }.padding(20)
            Form {
                Section("Board stages") {
                    ForEach(Array(TaskStatus.allCases.enumerated()), id: \.element.id) { index, status in
                        TextField(status.title, text: $draft.stageNames[index])
                    }
                    Text("These names apply to every project. The fifth stage always counts as completed work.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let validation = draft.validationError { Text(validation).foregroundStyle(.red) }
                }
                Section("Accent color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                        ForEach(AccentChoice.allCases) { choice in
                            Button { draft.accent = choice } label: {
                                VStack(spacing: 4) {
                                    Circle().fill(choice.color).frame(width: 30, height: 30)
                                        .overlay {
                                            if draft.accent == choice {
                                                Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.black)
                                            }
                                        }
                                    Text(choice.title).font(.caption).foregroundStyle(.primary)
                                }.frame(maxWidth: .infinity).padding(4)
                            }.buttonStyle(.plain)
                                .accessibilityLabel(choice.title)
                                .accessibilityAddTraits(draft.accent == choice ? .isSelected : [])
                        }
                    }
                }
                Section("iCloud") {
                    Text("Your stage names and accent color sync between Mac and iPhone when both use an iCloud build. Area collapse stays specific to each device.")
                        .font(.caption).foregroundStyle(.secondary)
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
            draft = BoardAppearance(stageNames: TaskStatus.allCases.map { appearance.title(for: $0) }, accent: appearance.accent)
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
        profile.updatedAt = Date()
        do { try StoreWriter.save(context); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
