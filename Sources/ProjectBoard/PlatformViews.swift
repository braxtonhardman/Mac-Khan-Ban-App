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
        .listStyle(.insetGrouped)
        .listSectionSpacing(14)
        .contentMargins(.top, 24, for: .scrollContent)
        .contentMargins(.bottom, 88, for: .scrollContent)
        .toolbar { profileToolbarItem }
        .overlay(alignment: .bottomTrailing) {
            creationControl()
                .padding(20)
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
            HStack(alignment: .top, spacing: 16) {
                Text(name)
                    .font(AppTypography.boardTitle)
                    .lineLimit(2)
                    .textSelection(.enabled)
                Spacer()
                actions()
            }
            if !notes.isEmpty {
                Text(notes)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            progressRow
        }
        .padding(20)
    }

    private var progressRow: some View {
        HStack {
            ProgressView(value: progress).frame(width: 65)
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(AppTypography.itemTitle)
            Text("· \(completedCount) of \(taskCount) tasks complete")
                .foregroundStyle(.secondary)
            Spacer()
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
    }
}
#endif

#if os(macOS)
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
                    .font(AppTypography.pageTitle)
                    .lineLimit(1)
                Spacer()
                creationControl()
            }
            .padding(.horizontal, 16)
            .padding(.top, isFullScreen ? 20 : 10)
            .padding(.bottom, 16)
        }
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
            HStack(alignment: .top, spacing: 16) {
                Text(name)
                    .font(AppTypography.boardTitle)
                    .lineLimit(2)
                    .textSelection(.enabled)
                Spacer()
                actions()
            }
            .buttonStyle(.borderless)
            .padding(.trailing, 68)

            if !notes.isEmpty {
                Text(notes)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            progressRow
        }
        .padding(20)
    }

    private var progressRow: some View {
        HStack {
            ProgressView(value: progress).frame(width: 160)
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(AppTypography.itemTitle)
            Text("· \(completedCount) of \(taskCount) tasks complete")
                .foregroundStyle(.secondary)
            Spacer()
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
                    Button(action: cancel) { Image(systemName: "xmark") }
                        .appGlassButton(shape: .circle)
                        .keyboardShortcut(.cancelAction)
                        .accessibilityLabel("Cancel")
                    Spacer()
                    Button(confirmationTitle, action: confirm)
                        .appGlassButton(size: .small, shape: .rectangle, accent: true)
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
