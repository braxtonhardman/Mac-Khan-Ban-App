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
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
        .listSectionSpacing(14)
        .contentMargins(.top, 24, for: .scrollContent)
        .contentMargins(.bottom, 88, for: .scrollContent)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Text("Workspace")
                    .font(AppTypography.boardTitle)
                    .lineLimit(1)
            }
            profileToolbarItem
        }
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
    }
}
#endif

#if os(macOS)
struct MacInWindowModal<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()

            content()
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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
                    .font(AppTypography.boardTitle)
                    .lineLimit(1)
                Spacer()
                creationControl()
            }
            .padding(.horizontal, 16)
            .padding(.top, isFullScreen ? 20 : 10)
            .padding(.bottom, 16)
        }
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
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 10) {
                Text(name)
                    .font(AppTypography.boardTitle)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .padding(.trailing, 136)

                if !notes.isEmpty {
                    Text(notes)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                progressRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actions()
                .buttonStyle(.borderless)
                .padding(.trailing, 68)
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
