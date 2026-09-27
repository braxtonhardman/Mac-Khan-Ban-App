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
                    #if os(macOS)
                    .background(SolidTitlebarBackground())
                    #endif

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
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 850)
        .commands { CommandGroup(replacing: .newItem) {} }
        #endif
    }
}

#if os(macOS)
/// AppKit moves the native buttons into a separate title-bar host in full screen.
/// Follow that host so its background remains opaque during the reveal animation.
private struct SolidTitlebarBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> AttachmentView { AttachmentView() }
    func updateNSView(_ view: AttachmentView, context: Context) { view.installBackground() }

    final class AttachmentView: NSView {
        private let background = BackgroundView()
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard window != nil else {
                background.removeFromSuperview()
                return
            }
            installBackground()
            observer = NotificationCenter.default.addObserver(
                forName: NSApplication.didUpdateNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.installBackground() }
        }

        func installBackground() {
            guard let window,
                  let close = window.standardWindowButton(.closeButton),
                  let host = close.superview,
                  host.bounds.height > 0, host.bounds.height < 120,
                  background.superview !== host else { return }
            background.removeFromSuperview()
            background.frame = host.bounds
            background.autoresizingMask = [.width, .height]
            host.addSubview(background, positioned: .above, relativeTo: nil)
            for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                if let button = window.standardWindowButton(kind), button.superview === host {
                    host.addSubview(button, positioned: .above, relativeTo: background)
                }
            }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }

    final class BackgroundView: NSView {
        override var isOpaque: Bool { true }
        override var allowsVibrancy: Bool { false }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.windowBackgroundColor.setFill()
            dirtyRect.fill()
        }
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            needsDisplay = true
        }
    }
}
#endif
