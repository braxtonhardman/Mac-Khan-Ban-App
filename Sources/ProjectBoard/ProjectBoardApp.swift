import SwiftUI
import SwiftData

@main
struct ProjectBoardApp: App {
    private let container: ModelContainer?
    private let startupError: String?

    init() {
        do {
            container = try ModelContainer(for: Project.self, BoardTask.self)
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
                ContentView().modelContainer(container)
            } else {
                ContentUnavailableView {
                    Label("Couldn’t open your projects", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(startupError ?? "Unknown storage error")
                    Text("Your data has not been reset. Close the app and check available disk space and permissions before trying again.")
                }
                .padding().frame(width: 600, height: 300)
            }
        }
        .defaultSize(width: 1440, height: 850)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
