import SwiftUI

#if os(iOS)
struct IOSWorkspaceSidebar<Content: View, CreationControl: View, ProfileControl: View>: View {
    @Binding var selection: UUID?
    let newArea: () -> Void
    let newProject: () -> Void
    @ViewBuilder let content: () -> Content
    @ViewBuilder let creationControl: () -> CreationControl
    @ViewBuilder let profileControl: () -> ProfileControl

    var body: some View {
        List(selection: $selection) {
            content()
        }
        .contextMenu {
            Button("New Area…", action: newArea)
            Button("New Project…", action: newProject)
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        .navigationTitle("Workspace")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.plain)
        .listSectionSpacing(0)
        .contentMargins(.top, 16, for: .scrollContent)
        .contentMargins(.bottom, 88, for: .scrollContent)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Workspace")
                    .font(AppTypography.workspaceTitle)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
            }
            profileToolbarItem
        }
        .overlay(alignment: .bottomTrailing) {
            creationControl()
                .padding(.trailing, 12)
                .padding(.bottom, 8)
        }
    }

    @ToolbarContentBuilder
    private var profileToolbarItem: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarTrailing) { profileControl() }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarTrailing) { profileControl() }
        }
    }
}

struct IOSProjectHeader<Actions: View>: View {
    let name: String
    let notes: String
    let progress: Double
    let completedCount: Int
    let taskCount: Int
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !notes.isEmpty {
                Text(notes)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            progressRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
        .toolbar { projectToolbar }
    }

    @ToolbarContentBuilder
    private var projectToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text(name)
                .font(AppTypography.sectionTitle)
                .lineLimit(1)
        }

        ToolbarItem(placement: .topBarTrailing) { actions() }
    }

    private var progressRow: some View {
        HStack(spacing: 8) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(minWidth: 52, maxWidth: .infinity)
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(AppTypography.itemTitle)
                .fixedSize(horizontal: true, vertical: false)
            Text("· \(completedCount) of \(taskCount) tasks complete")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct IOSWorkspaceItemEditorShell<Fields: View>: View {
    let title: String
    let confirmationTitle: String
    let canConfirm: Bool
    let cancel: () -> Void
    let confirm: () -> Void
    @ViewBuilder let fields: () -> Fields

    var body: some View {
        NavigationStack {
            ScrollView {
                fields()
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
            }
            .font(AppTypography.body)
            .background(Color(uiColor: .systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                EditorToolbarActions(
                    confirmationTitle: confirmationTitle,
                    canConfirm: canConfirm,
                    cancel: cancel,
                    confirm: confirm
                )
            }
        }
        .modifier(DismissSheetOnOutsideTap())
    }
}
#endif

#if os(macOS)
struct MacInWindowModal<Content: View>: View {
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Button(action: onDismiss) {
                Color.black.opacity(0.34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .ignoresSafeArea()
            .accessibilityLabel("Dismiss popup")

            content()
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .onTapGesture { } // Empty space inside the popup must not dismiss it.
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.75)
                        .allowsHitTesting(false)
                }
                .shadow(color: .black.opacity(0.32), radius: 32, y: 14)
                .padding(28)
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isModal)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .zIndex(100)
    }
}

struct MacWorkspaceSidebar<Content: View, CreationControl: View>: View {
    let isFullScreen: Bool
    let newArea: () -> Void
    let newProject: () -> Void
    @ViewBuilder let content: () -> Content
    @ViewBuilder let creationControl: () -> CreationControl

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .contextMenu {
            Button("New Area…", action: newArea)
            Button("New Project…", action: newProject)
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        .toolbar(removing: .sidebarToggle)
        .toolbarBackground(Color(nsColor: .windowBackgroundColor), for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 12) {
                Text("Workspace")
                    .font(AppTypography.workspaceTitle)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer()
                creationControl()
            }
            .padding(.horizontal, 16)
            .padding(.top, isFullScreen ? 20 : 10)
            .padding(.bottom, 16)
        }
        .appCardSurface(cornerRadius: 18)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct MacProjectHeader<Actions: View>: View {
    let name: String
    let notes: String
    let progress: Double
    let completedCount: Int
    let taskCount: Int
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(name)
                        .font(AppTypography.boardTitle)
                        .lineLimit(2)
                        .textSelection(.enabled)

                    if !notes.isEmpty {
                        Text(notes)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.trailing, 136)
                .frame(maxWidth: .infinity, minHeight: AppGlassButtonSize.large.dimension, alignment: .topLeading)

                actions()
                    .buttonStyle(.borderless)
                    .padding(.trailing, 68)
            }
            progressRow
        }
        .padding(20)
    }

    private var progressRow: some View {
        HStack(spacing: 8) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .containerRelativeFrame(.horizontal) { width, _ in
                    max(52, (width - 40) * 0.6)
                }
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(AppTypography.itemTitle)
                .fixedSize(horizontal: true, vertical: false)
            Text("· \(completedCount) of \(taskCount) tasks complete")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

struct MacWorkspaceItemEditorShell<Fields: View>: View {
    let title: String
    let confirmationTitle: String
    let canConfirm: Bool
    let height: CGFloat
    let cancel: () -> Void
    let confirm: () -> Void
    @ViewBuilder let fields: () -> Fields

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title).font(AppTypography.pageTitle)
                HStack {
                    AppGlassActionButton(symbol: .cancel, accessibilityLabel: "Cancel", action: cancel)
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    AppGlassActionButton(
                        symbol: .confirm,
                        accessibilityLabel: confirmationTitle,
                        accent: true,
                        action: confirm
                    )
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canConfirm)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            Divider()
            ScrollView {
                fields()
                    .padding(24)
            }
        }
        .background(.background)
        .modifier(EditorSizing(width: 540, height: height))
    }
}
#endif


#if os(iOS)
import UIKit

/// Keep native sheets and their swipe gesture, adding dismissal only to the exposed backdrop.
struct DismissSheetOnOutsideTap: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    func body(content: Content) -> some View {
        content.background {
            OutsideSheetTapObserver(onDismiss: { dismiss() })
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
    }
}

private struct OutsideSheetTapObserver: UIViewControllerRepresentable {
    let onDismiss: () -> Void
    func makeUIViewController(context: Context) -> ObserverController {
        ObserverController(onDismiss: onDismiss)
    }
    func updateUIViewController(_ controller: ObserverController, context: Context) {
        controller.onDismiss = onDismiss
        controller.attachIfNeeded()
    }
    static func dismantleUIViewController(_ controller: ObserverController, coordinator: ()) {
        controller.detach()
    }

    final class ObserverController: UIViewController, UIGestureRecognizerDelegate {
        var onDismiss: () -> Void
        private weak var sheetController: UIViewController?
        private var backdropTap: UITapGestureRecognizer?

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func loadView() { view = UIView(); view.backgroundColor = .clear }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            attachIfNeeded()
        }
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            attachIfNeeded()
        }
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            detach()
        }
        func attachIfNeeded() {
            guard isViewLoaded, view.window != nil else { return }
            var candidate: UIViewController? = self
            while let current = candidate {
                if current.presentingViewController != nil,
                   let container = current.presentationController?.containerView {
                    guard backdropTap?.view !== container else { return }
                    detach()
                    sheetController = current
                    let tap = UITapGestureRecognizer(target: self, action: #selector(tappedBackdrop))
                    tap.cancelsTouchesInView = false
                    tap.delegate = self
                    container.addGestureRecognizer(tap)
                    backdropTap = tap
                    return
                }
                candidate = current.parent
            }
        }
        func detach() {
            if let backdropTap { backdropTap.view?.removeGestureRecognizer(backdropTap) }
            backdropTap = nil
            sheetController = nil
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let sheetController,
                  sheetController.presentedViewController == nil,
                  !sheetController.isBeingDismissed,
                  let surface = sheetController.presentationController?.presentedView else { return false }
            // Use the actual presented surface, not the SwiftUI content's frame. This excludes
            // headers, padding, text fields, and the keyboard from the dismiss target.
            return !surface.bounds.contains(touch.location(in: surface))
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
        @objc private func tappedBackdrop() { onDismiss() }
    }
}
#endif
