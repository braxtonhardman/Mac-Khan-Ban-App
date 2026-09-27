import SwiftUI
import SwiftData

@main
struct ProjectBoardApp: App {
    private let container: ModelContainer?
    private let startupError: String?

    init() {
        _ = SyncStatus.shared
        do {
            let schema = Schema([Project.self, BoardTask.self, ProjectArea.self, AppProfile.self])
            let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: SyncStatus.isCloudBuild ? .private(SyncStatus.containerIdentifier) : .none)
            container = try ModelContainer(for: schema, configurations: [configuration])
            container?.mainContext.autosaveEnabled = false
            startupError = nil
        } catch {
            container = nil
            startupError = error.localizedDescription
        }
    }
    var body: some Scene {
        WindowGroup {
            if let container {
                AppRootView().modelContainer(container).environmentObject(SyncStatus.shared)
            } else {
                ContentUnavailableView {
                    Label("Couldn’t open your projects", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(startupError ?? "Unknown storage error")
                    Text("Your data has not been reset. Close the app and check available disk space and permissions before trying again.")
                }
                .padding().modifier(EditorSizing(width: 600, height: 300))
            }
        }
        #if os(macOS)
        .defaultSize(width: 1440, height: 850)
        .commands { CommandGroup(replacing: .newItem) {} }
        #endif
    }
}
