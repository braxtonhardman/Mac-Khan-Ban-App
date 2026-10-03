import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
#if SWIFT_PACKAGE
import BoardCore
#endif

struct ContentView: View {
    var isFullScreen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.createdAt) private var projects: [Project]
    @Query(sort: \ProjectArea.createdAt) private var areas: [ProjectArea]
    @AppStorage("collapsedAreas") private var collapsedAreas = ""
    @State private var linkedTask: BoardTask?
    @State private var showingProfile = false
    @State private var areaEditor: AreaEditRequest?
    @State private var removingArea: ProjectArea?
    @State private var selection: UUID?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var projectEditor: ProjectEditRequest?
    @State private var deleting: Project?
    @State private var error: String?

    private let projectIndent: CGFloat = 28
    #if os(iOS)
    private let areaHeaderSpacing: CGFloat = 11
    #else
    private let areaHeaderSpacing: CGFloat = 7
    #endif

    private var selected: Project? { projects.first { $0.id == selection } }
    private var hasUnassignedProjects: Bool { projects.contains { $0.area == nil } }
    private var navigationColumnVisibility: Binding<NavigationSplitViewVisibility> {
        #if os(macOS)
        Binding(get: { .all }, set: { _ in })
        #else
        $columnVisibility
        #endif
    }
    var body: some View {
        NavigationSplitView(columnVisibility: navigationColumnVisibility) {
            workspaceSidebar
                .navigationSplitViewColumnWidth(min: 230, ideal: 230)

        } detail: {
            Group {
                if let selected {
                    ProjectBoardView(project: selected, editProject: { projectEditor = .init(project: selected) }, deleteProject: { deleting = selected })
                        .id(selected.id)
                } else {
                    ContentUnavailableView {
                        Label("A little structure for your next idea", systemImage: "rectangle.split.3x1")
                    } description: {
                        Text("Create a project, capture tasks, and move them toward done.")
                    } actions: {
                        Button("Create Project") { projectEditor = .init(project: nil) }
                            .appGlassButton(shape: .rectangle, accent: true)
                    }
                }
            }
            #if os(macOS)
            .padding(.top, isFullScreen ? 32 : 0)
            #endif
        }
        #if os(macOS)
        .toolbarBackground(Color(nsColor: .windowBackgroundColor), for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .overlay(alignment: .topTrailing) {
            profileButton
            .padding(.horizontal, 20)
            .padding(.top, 20 + (isFullScreen ? 32 : 0))
        }
        #endif
        .modifier(MainWindowSizing())
        .onAppear {
            #if os(macOS)
            if selection == nil { selection = projects.first?.id }
            #endif
        }
        .sheet(item: $projectEditor) { request in
            ProjectEditor(project: request.project, initialArea: request.area) { selection = $0 }
        }
        .onOpenURL { url in
            guard url.scheme == "projectboard", url.host == "task", let id = UUID(uuidString: url.lastPathComponent),
                  let task = projects.flatMap(\.taskList).first(where: { $0.id == id }) else { return }
            selection = task.project?.id
            linkedTask = task
        }
        .sheet(item: $linkedTask) { task in
            if let project = task.project {
                TaskEditor(project: project, task: task, initialStatus: task.status, parentTask: task.parentTask)
            }
        }
        .sheet(isPresented: $showingProfile) { ProfileSettingsView() }
        .sheet(item: $areaEditor) { AreaEditor(area: $0.area) }
        .confirmationDialog("Delete \(removingArea?.name ?? "area")?", isPresented: Binding(get: { removingArea != nil }, set: { if !$0 { removingArea = nil } })) {
            Button("Delete Area", role: .destructive) {
                guard let area = removingArea else { return }
                for project in area.projectList { project.area = nil }
                context.delete(area)
                saveChanges()
                removingArea = nil
            }
        } message: { Text("Projects and their tasks will be kept in Unassigned.") }
        .confirmationDialog("Delete \(deleting?.name ?? "project") and all its tasks?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete Project", role: .destructive) {
                guard let project = deleting else { return }
                let id = project.id
                context.delete(project)
                do {
                    try StoreWriter.save(context)
                    if selection == id { selection = projects.first { $0.id != id }?.id }
                } catch { self.error = error.localizedDescription }
                deleting = nil
            }
        } message: { Text("This cannot be undone.") }
        .alert("Couldn’t save changes", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    @ViewBuilder
    private var workspaceSidebar: some View {
        #if os(macOS)
        MacWorkspaceSidebar(
            isFullScreen: isFullScreen,
            newArea: { areaEditor = .init(area: nil) },
            newProject: { projectEditor = .init(project: nil) },
            content: { workspaceGroups },
            creationControl: { creationMenu }
        )
        #else
        IOSWorkspaceSidebar(
            selection: $selection,
            newArea: { areaEditor = .init(area: nil) },
            newProject: { projectEditor = .init(project: nil) },
            content: { workspaceGroups },
            creationControl: { creationMenu },
            profileControl: { profileButton }
        )
        #endif
    }

    @ViewBuilder
    private var workspaceGroups: some View {
        ForEach(areas) { area in areaGroup(area) }
        if hasUnassignedProjects { areaGroup(nil) }
    }

    private var profileButton: some View {
        Button { showingProfile = true } label: {
            Label("Profile & Settings", systemImage: "person.crop.circle")
                .font(AppTypography.controlIcon)
        }
        .labelStyle(.iconOnly)
        .appGlassButton(size: .large, shape: .circle)
        .help("Profile & Settings")
        .accessibilityLabel("Profile & Settings")
    }

    private var creationMenu: some View {
        Menu {
            Button("New Project…") { projectEditor = .init(project: nil) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New Area…") { areaEditor = .init(area: nil) }
        } label: {
            Label("Create Project or Area", systemImage: "plus.rectangle.on.folder")
                .font(AppTypography.controlIcon)
        }
        .labelStyle(.iconOnly)
        .appGlassButton(size: .extraLarge, shape: .circle)
        .help("Create Project or Area")
    }

    @ViewBuilder
    private func areaGroup(_ area: ProjectArea?) -> some View {
        #if os(iOS)
        Section {
            areaContents(area)
        }
        #else
        VStack(spacing: 0) {
            areaContents(area)
        }
        #endif
    }

    @ViewBuilder
    private func areaContents(_ area: ProjectArea?) -> some View {
        let key = area?.id.uuidString ?? "unassigned"
        let children = projects.filter { $0.area?.id == area?.id }
        areaHeader(area?.name ?? "Unassigned", key: key)
            .contextMenu {
                if let area {
                    Button("New Project in Area…") { projectEditor = .init(project: nil, area: area) }
                    Button("Edit Area…", systemImage: "pencil") { areaEditor = .init(area: area) }
                    Button("Delete Area…", systemImage: "trash", role: .destructive) { removingArea = area }
                    Divider()
                    Button("New Area…") { areaEditor = .init(area: nil) }
                }
            }
        if !isCollapsed(key) {
            ForEach(children) { projectRow($0) }
            if children.isEmpty && area != nil {
                Text("No projects yet").font(AppTypography.caption).foregroundStyle(.secondary)
                    .padding(.leading, projectIndent)
                    #if os(macOS)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .listRowBackground(Color.clear)
                    #else
                    .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
                    #endif
                    .listRowInsets(.init(top: 2, leading: 16, bottom: 2, trailing: 12))
                    .listRowSeparator(.hidden)
            }
        }
    }

    private func isCollapsed(_ key: String) -> Bool { collapsedAreas.split(separator: ",").contains(Substring(key)) }
    private func toggle(_ key: String, in value: inout String) {
        var keys = Set(value.split(separator: ",").map(String.init))
        if keys.contains(key) { keys.remove(key) } else { keys.insert(key) }
        value = keys.sorted().joined(separator: ",")
    }
    private func areaHeader(_ name: String, key: String) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                toggle(key, in: &collapsedAreas)
            }
        } label: {
            HStack(spacing: areaHeaderSpacing) {
                Image(systemName: isCollapsed(key) ? "chevron.right" : "chevron.down")
                    .font(AppTypography.sidebarDisclosureIcon)
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                Image(systemName: "folder")
                    .font(AppTypography.sidebarAreaIcon)
                    .foregroundStyle(.tint)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Text(name)
                    .font(AppTypography.sidebarAreaTitle)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            #if os(macOS)
            .padding(.horizontal, 6)
            #endif
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(.init(top: 2, leading: 14, bottom: 2, trailing: 12))
        #if os(iOS)
        .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
        #else
        .listRowBackground(Color.clear)
        #endif
        .listRowSeparator(.hidden)
        .accessibilityLabel("\(isCollapsed(key) ? "Expand" : "Collapse") \(name)")
    }
    @ViewBuilder
    private func projectRow(_ project: Project) -> some View {
        Group {
            #if os(iOS)
            NavigationLink(value: project.id) {
                projectRowLabel(project)
            }
            .tag(project.id)
            #else
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                    selection = project.id
                }
            } label: {
                projectRowLabel(project)
            }
            #endif
        }
        .buttonStyle(.plain)
        #if os(iOS)
        .listRowInsets(.init(top: 1, leading: 8, bottom: 1, trailing: 18))
        #else
        .listRowInsets(.init(top: 1, leading: 8, bottom: 1, trailing: 8))
        #endif
        #if os(iOS)
        .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
        #else
        .listRowBackground(Color.clear)
        #endif
        .listRowSeparator(.hidden)
        .accessibilityAddTraits(selection == project.id ? .isSelected : [])
        .contextMenu {
            Button("Edit Project…") { projectEditor = .init(project: project) }
            Menu("Move to Area") {
                Button("Unassigned") { project.area = nil; saveChanges() }
                ForEach(areas) { area in
                    Button(area.name) { project.area = area; saveChanges() }
                }
            }
            Button("New Area…") { areaEditor = .init(area: nil) }
            Button("Delete Project…", role: .destructive) { deleting = project }
        }
    }

    private func projectRowLabel(_ project: Project) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.3.group")
                .font(AppTypography.smallIcon)
                .foregroundStyle(selection == project.id ? Color.accentColor : Color.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(project.name)
                .font(AppTypography.body)
                #if os(iOS)
                .foregroundStyle(selection == project.id ? Color.accentColor : Color.primary)
                #else
                .foregroundStyle(selection == project.id ? .primary : .secondary)
                #endif
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, projectIndent)
        .padding(.vertical, 6)
        .padding(.trailing, 8)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selection == project.id ? Color.accentColor.opacity(0.14) : Color.clear)
        )
    }

    private func saveChanges() {
        do { try StoreWriter.save(context) }
        catch { self.error = error.localizedDescription }
    }

}

private struct ProjectEditRequest: Identifiable {
    let id = UUID()
    let project: Project?
    var area: ProjectArea? = nil
}

struct ProjectEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let project: Project?
    @Query(sort: \ProjectArea.createdAt) private var areas: [ProjectArea]
    @State private var areaID: UUID?
    let onSave: (UUID) -> Void
    @State private var name: String
    @State private var notes: String
    @State private var error: String?

    init(project: Project?, initialArea: ProjectArea? = nil, onSave: @escaping (UUID) -> Void) {
        self.project = project
        _areaID = State(initialValue: project?.area?.id ?? initialArea?.id)
        self.onSave = onSave
        _name = State(initialValue: project?.name ?? "")
        _notes = State(initialValue: project?.notes ?? "")
    }
    var body: some View {
        WorkspaceItemEditor(kind: "Project", icon: "rectangle.3.group", isNew: project == nil, name: $name,
                            guidance: "Give the project a clear home and enough context to get started.",
                            error: error, save: save) {
            WorkspaceEditorCard("Project details") {
                HStack(spacing: 12) {
                    Label("Area", systemImage: "folder")
                        .font(AppTypography.body)
                    Spacer(minLength: 12)
                    areaPicker
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Label("Description", systemImage: "text.alignleft")
                        .font(AppTypography.body)
                    ZStack(alignment: .topLeading) {
                        if notes.isEmpty {
                            Text("What is this project about?")
                                .font(AppTypography.body)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                        descriptionEditor
                    }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.large])
        #endif
    }

    @ViewBuilder private var areaPicker: some View {
        #if os(macOS)
        Menu {
            Button {
                areaID = nil
            } label: {
                if areaID == nil {
                    Label("Unassigned", systemImage: "checkmark")
                } else {
                    Text("Unassigned")
                }
            }
            ForEach(areas) { area in
                Button {
                    areaID = area.id
                } label: {
                    if areaID == area.id {
                        Label(area.name, systemImage: "checkmark")
                    } else {
                        Text(area.name)
                    }
                }
            }
        } label: {
            Text("\(selectedAreaName)  \(Image(systemName: "chevron.up.chevron.down"))")
                .font(AppTypography.body)
                .foregroundStyle(Color.accentColor)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Area")
        #else
        Picker("Area", selection: $areaID) {
            Text("Unassigned").tag(nil as UUID?)
            ForEach(areas) { Text($0.name).tag(Optional($0.id)) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .tint(Color.accentColor)
        #endif
    }

    private var selectedAreaName: String {
        areas.first { $0.id == areaID }?.name ?? "Unassigned"
    }

    private var descriptionEditor: some View {
        #if os(macOS)
        MacDescriptionEditor(text: $notes)
            .frame(height: 100)
        #else
        TextEditor(text: $notes)
            .scrollContentBackground(.hidden)
            .accessibilityLabel("Project description")
            .frame(minHeight: 140)
        #endif
    }

    private func save() {
        do {
            let item = try StoreWriter.saveItem(project, name: name, in: context,
                                                create: { Project(name: "") }) { item in
                item.notes = notes
                item.area = areas.first { $0.id == areaID }
            }
            onSave(item.id)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }

}

#if os(macOS)
/// Uses an overlay scroller so short descriptions stay visually clean while long text still scrolls.
private struct MacDescriptionEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.textContainerInset = NSSize(width: 5, height: 8)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.setAccessibilityLabel("Project description")
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String

        init(text: Binding<String>) { _text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}
#endif

struct TaskEditRequest: Identifiable {
    let id = UUID()
    var task: BoardTask?
    var status: TaskStatus = .backlog
    var parentTask: BoardTask? = nil
}

struct ProjectBoardView: View {
    @Environment(\.boardAppearance) private var appearance
    @Environment(\.modelContext) private var context
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    private var compactLayout: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }
    @Bindable var project: Project
    let editProject: () -> Void
    let deleteProject: () -> Void
    @State private var editor: TaskEditRequest?
    @State private var calendarTask: BoardTask?
    @State private var deleting: BoardTask?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            projectHeader
            #if os(macOS)
            Divider()
            #endif
            GeometryReader { geometry in
                let statuses = TaskStatus.allCases
                let spacing: CGFloat = 14
                let horizontalPadding: CGFloat = 20
                let availableWidth = max(0, geometry.size.width - horizontalPadding * 2)
                let gaps = spacing * CGFloat(statuses.count - 1)
                let columnWidth = compactLayout
                    ? availableWidth
                    : max(180, (availableWidth - gaps) / CGFloat(statuses.count))
                let columnHeight = max(0, geometry.size.height)

                ScrollView(.horizontal) {
                    boardColumns(
                        statuses: statuses,
                        spacing: spacing,
                        columnWidth: columnWidth,
                        columnHeight: columnHeight,
                        horizontalPadding: horizontalPadding
                    )
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            }
        }
        #if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
        #endif
        #if os(iOS)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $calendarTask) { CalendarDeadlineSheet(task: $0) }
        .sheet(item: $editor) {
            TaskEditor(project: project, task: $0.task, initialStatus: $0.status, parentTask: $0.parentTask)
        }
        .confirmationDialog("Delete task?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete Task", role: .destructive) {
                if let deleting { context.delete(deleting); save() }
                deleting = nil
            }
        } message: { Text("This cannot be undone.") }
        .alert("Couldn’t save changes", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    @ViewBuilder
    private var projectHeader: some View {
        #if os(macOS)
        MacProjectHeader(
            name: project.name,
            notes: project.notes,
            progress: project.progress,
            completedCount: completedTaskCount,
            taskCount: project.topLevelTasks.count,
            actions: { projectOptions }
        )
        #else
        IOSProjectHeader(
            name: project.name,
            notes: project.notes,
            progress: project.progress,
            completedCount: completedTaskCount,
            taskCount: project.topLevelTasks.count,
            actions: { projectOptions }
        )
        #endif
    }

    private var completedTaskCount: Int {
        project.topLevelTasks.filter { $0.status == .done }.count
    }

    private func boardColumns(
        statuses: [TaskStatus],
        spacing: CGFloat,
        columnWidth: CGFloat,
        columnHeight: CGFloat,
        horizontalPadding: CGFloat
    ) -> some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(statuses) { status in
                column(status, width: columnWidth, height: columnHeight)
            }
        }
        .padding(.horizontal, horizontalPadding)
    }

    private var projectOptions: some View {
        Menu {
            Button("New Task") { editor = .init() }
                .keyboardShortcut("n", modifiers: .command)
            Divider()
            Button("Edit Project", action: editProject)
            Button("Delete Project…", role: .destructive, action: deleteProject)
        } label: { Label("Create Task or Manage Project", systemImage: "plus") }
            .labelStyle(.iconOnly)
            .appGlassButton(size: .large, shape: .circle)
            .help("Create Task or Manage Project")
            .accessibilityLabel("Create Task or Manage Project")
            #if os(macOS)
            .padding(.leading, 18)
            .padding(.bottom, 8)
            #endif
    }

    private func column(_ status: TaskStatus, width: CGFloat, height: CGFloat) -> some View {
        let tasks = project.topLevelTasks.filter { $0.status == status }.sorted { $0.createdAt < $1.createdAt }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(appearance.title(for: status), systemImage: status.symbol)
                    .font(AppTypography.sectionTitle).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(appearance.title(for: status))
                Text("\(tasks.count)").foregroundStyle(.secondary)
                Spacer()
            }.frame(minHeight: 36, alignment: .top)
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(tasks) { task in
                        Button { editor = .init(task: task) } label: { TaskCard(task: task) }
                            .buttonStyle(.plain)
                            .draggable(task.id.uuidString)
                            .contextMenu {
                                Button("Edit Task") { editor = .init(task: task) }
                                Button("Add or Update Deadline in Calendar…") { calendarTask = task }
                                    .disabled(task.dueDate == nil)
                                Menu("Move To") {
                                    ForEach(TaskStatus.allCases) { target in
                                        Button(appearance.title(for: target)) { move(task, to: target) }.disabled(task.status == target)
                                    }
                                }
                                Button("Delete Task…", role: .destructive) { deleting = task }
                            }
                    }
                    if tasks.isEmpty {
                        Text("Drop a task here").font(AppTypography.caption).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity).padding(.vertical, 28)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(12)
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { values, _ in
            let ids = Set(values.compactMap(UUID.init(uuidString:)))
            let matches = project.topLevelTasks.filter { ids.contains($0.id) }
            guard !matches.isEmpty else { return false }
            for task in matches { task.status = status; task.updatedAt = Date() }
            return save()
        }
    }
    private func move(_ task: BoardTask, to status: TaskStatus) {
        task.status = status
        task.updatedAt = Date()
        save()
    }
    @discardableResult private func save() -> Bool {
        do { try StoreWriter.save(context); return true }
        catch { self.error = error.localizedDescription; return false }
    }
}

struct TaskCard: View {
    let task: BoardTask
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(task.title).font(AppTypography.itemTitle).fixedSize(horizontal: false, vertical: true)
            if !task.details.isEmpty { Text(task.details).font(AppTypography.supporting).foregroundStyle(.secondary).lineLimit(2) }
            HStack {
                Text(task.priority.title).font(AppTypography.metadataEmphasis)
                    .foregroundStyle(task.priority.rawValue >= 2 ? Color.orange : Color.secondary)
                Spacer()
                if let date = task.dueDate {
                    Label(date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        .font(AppTypography.caption)
                        .foregroundStyle(date < Calendar.current.startOfDay(for: Date()) && task.status != .done ? Color.red : Color.secondary)
                }
            }
            if !task.tags.isEmpty {
                Text(task.tags.map { "#\($0)" }.joined(separator: "  ")).font(AppTypography.caption).foregroundStyle(.tint).lineLimit(2)
            }
            if !task.subtaskList.isEmpty {
                Label("\(task.subtaskList.filter { $0.status == .done }.count)/\(task.subtaskList.count) subtasks", systemImage: "list.bullet.indent")
                    .font(AppTypography.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
        .accessibilityElement(children: .combine)
    }
}

private struct AreaEditRequest: Identifiable {
    let id = UUID()
    let area: ProjectArea?
}

private struct AreaEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var areas: [ProjectArea]
    let area: ProjectArea?
    @State private var name: String
    @State private var error: String?

    init(area: ProjectArea?) {
        self.area = area
        _name = State(initialValue: area?.name ?? "")
    }
    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var duplicate: Bool {
        areas.contains { $0.id != area?.id && $0.name.localizedCaseInsensitiveCompare(cleanName) == .orderedSame }
            || cleanName.localizedCaseInsensitiveCompare("Unassigned") == .orderedSame
    }
    var body: some View {
        WorkspaceItemEditor(kind: "Area", icon: "folder", isNew: area == nil, name: $name,
                            guidance: "Group related projects, such as Work, Personal, or Learning.",
                            validation: duplicate ? "Choose a different area name." : nil,
                            error: error, save: save) {
            EmptyView()
        }
        #if os(iOS)
        .presentationDetents([.medium])
        #endif
    }

    private func save() {
        guard !duplicate else { return }
        do {
            _ = try StoreWriter.saveItem(area, name: name, in: context,
                                        create: { ProjectArea(name: "") })
            dismiss()
        } catch { self.error = error.localizedDescription }
    }

}

struct MainWindowSizing: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        content.frame(minWidth: 900, minHeight: 600)
        #else
        content
        #endif
    }
}

struct EditorSizing: ViewModifier {
    var width: CGFloat
    var height: CGFloat? = nil
    func body(content: Content) -> some View {
        #if os(macOS)
        content.font(AppTypography.body).frame(width: width, height: height)
        #else
        content.font(AppTypography.body).frame(maxWidth: .infinity)
        #endif
    }
}

/// Shared create/edit shell; each item supplies its own fields and validation rules.
private struct WorkspaceItemEditor<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let kind: String
    let icon: String
    let isNew: Bool
    @Binding var name: String
    var guidance: String? = nil
    var validation: String? = nil
    let error: String?
    let save: () -> Void
    @ViewBuilder var content: () -> Content
    @FocusState private var nameIsFocused: Bool

    private var title: String { "\(isNew ? "New" : "Edit") \(kind)" }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && validation == nil
    }
    private var nameField: some View {
        TextField("\(kind) name", text: $name, prompt: Text("Enter \(kind.lowercased()) name"))
            .accessibilityLabel("\(kind) name")
            .font(AppTypography.itemTitle)
            .textFieldStyle(.plain)
            .focused($nameIsFocused)
            .onSubmit { if canSave { save() } }
            #if os(iOS)
            .textInputAutocapitalization(.sentences)
            .submitLabel(.done)
            #endif
    }
    @ViewBuilder private var messages: some View {
        if let validation { Text(validation).foregroundStyle(.red) }
        if let error { Text(error).foregroundStyle(.red) }
    }

    private var editorFields: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 44, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(height: 76)
                    .accessibilityHidden(true)
                if let guidance {
                    Text(guidance)
                        .font(AppTypography.supporting)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                Text("\(kind) name")
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(AppTypography.itemTitle)
                        .foregroundStyle(.tint)
                        .frame(width: 22)
                        .accessibilityHidden(true)
                    nameField
                    if !name.isEmpty {
                        Button {
                            name = ""
                            nameIsFocused = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear \(kind.lowercased()) name")
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
                .background(.background, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(nameIsFocused ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.08), lineWidth: 1)
                }
            }

            content()
            messages
                .font(AppTypography.supporting)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var body: some View {
        Group {
        #if os(iOS)
        IOSWorkspaceItemEditorShell(
            title: title,
            confirmationTitle: isNew ? "Create" : "Save",
            canConfirm: canSave,
            cancel: { dismiss() },
            confirm: save,
            fields: { editorFields }
        )
        #else
        MacWorkspaceItemEditorShell(
            title: title,
            confirmationTitle: isNew ? "Create" : "Save",
            canConfirm: canSave,
            height: kind == "Area" ? 440 : 650,
            cancel: { dismiss() },
            confirm: save,
            fields: { editorFields }
        )
        #endif
        }
        .task {
            if isNew { nameIsFocused = true }
        }
    }
}
