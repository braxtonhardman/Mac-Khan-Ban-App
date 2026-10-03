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
            let openedContainer = try ModelContainer(for: schema, configurations: [configuration])
            openedContainer.mainContext.autosaveEnabled = false
            try LegacyChecklistMigrator.run(in: openedContainer.mainContext)
            container = openedContainer
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
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 850)
        .commands { CommandGroup(replacing: .newItem) {} }
        #endif
    }
}

#if os(macOS)
/// AppKit moves the native buttons into a separate title-bar host in full screen.
/// Follow that host so its background remains opaque during the reveal animation.
struct SolidTitlebarBackground: NSViewRepresentable {
    var onClearanceChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        view.onClearanceChange = onClearanceChange
        return view
    }
    func updateNSView(_ view: AttachmentView, context: Context) {
        view.onClearanceChange = onClearanceChange
        view.installBackground()
    }

    final class AttachmentView: NSView {
        var onClearanceChange: ((CGFloat) -> Void)?
        private var lastClearance: CGFloat = -1
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
            guard let window else { return }
            // The revealed full-screen title bar overlays content instead of adding a safe area.
            let height = window.standardWindowButton(.closeButton)?.superview?.bounds.height ?? 32
            let clearance = window.styleMask.contains(.fullScreen) ? min(max(height, 32), 80) : 0
            if clearance != lastClearance {
                lastClearance = clearance
                DispatchQueue.main.async { [weak self] in self?.onClearanceChange?(clearance) }
            }
            guard
                  let close = window.standardWindowButton(.closeButton),
                  let host = close.superview,
                  host.bounds.height > 0 else { return }
            background.appearance = window.effectiveAppearance
            let needsInstall = background.superview !== host
            let barHeight: CGFloat = min(host.bounds.height, 32)
            let frame = NSRect(
                x: host.bounds.minX,
                y: host.isFlipped ? host.bounds.minY : host.bounds.maxY - barHeight,
                width: host.bounds.width,
                height: barHeight
            )
            if background.frame != frame { background.frame = frame }
            background.clipsToBounds = true
            // The native host can grow to the full window during restoration.
            // Keep the opaque backing confined to the title bar.
            background.autoresizingMask = host.isFlipped ? [.width, .maxYMargin] : [.width, .minYMargin]
            guard needsInstall else { return }
            background.removeFromSuperview()
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
            bounds.fill()
        }
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            needsDisplay = true
        }
    }
}
#endif
