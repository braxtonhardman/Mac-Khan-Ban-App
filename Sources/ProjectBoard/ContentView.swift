import SwiftUI
import SwiftData
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

    private var selected: Project? { projects.first { $0.id == selection } }
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                areaHeader("Unassigned", key: "unassigned")
                if !isCollapsed("unassigned") {
                    #if os(iOS)
                    addProjectRow(in: nil)
                    #endif
                    ForEach(projects.filter { $0.area == nil }) { projectRow($0) }
                }
                ForEach(areas) { area in
                    areaHeader(area.name, key: area.id.uuidString)
                        .contextMenu {
                            Button("New Project in Area…") { projectEditor = .init(project: nil, area: area) }
                            Button("Edit Area…", systemImage: "pencil") { areaEditor = .init(area: area) }
                            Button("Delete Area…", systemImage: "trash", role: .destructive) { removingArea = area }
                            Divider()
                            Button("New Area…") { areaEditor = .init(area: nil) }
                        }
                    if !isCollapsed(area.id.uuidString) {
                        #if os(iOS)
                        addProjectRow(in: area)
                        #endif
                        ForEach(projects.filter { $0.area?.id == area.id }) { projectRow($0) }
                        if area.projectList.isEmpty {
                            Text("No projects yet").font(AppTypography.caption).foregroundStyle(.secondary)
                                .padding(.leading, projectIndent)
                        }
                    }
                }
            }
            .contextMenu {
                Button("New Area…") { areaEditor = .init(area: nil) }
                Button("New Project…") { projectEditor = .init(project: nil) }.keyboardShortcut("n", modifiers: [.command, .shift])
            }
            #if os(iOS)
            .navigationTitle("ProjectBoard")
            #endif
            #if os(macOS)
            .toolbar(removing: .sidebarToggle)
            .toolbarBackground(Color(nsColor: .windowBackgroundColor), for: .windowToolbar)
            .toolbarBackground(.visible, for: .windowToolbar)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 12) {
                    Text("Workspace").font(AppTypography.pageTitle).lineLimit(1)
                    Spacer()
                    creationMenu
                    Button {
                        withAnimation { columnVisibility = .detailOnly }
                    } label: { Image(systemName: "sidebar.left") }
                        .help("Hide Sidebar")
                        .accessibilityLabel("Hide Sidebar")
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 16)
                .padding(.top, isFullScreen ? 20 : 10)
                .padding(.bottom, 16)
            }
            #else
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { creationMenu }
                ToolbarItem(placement: .topBarTrailing) { profileButton }
            }
            #endif
            .navigationSplitViewColumnWidth(min: 230, ideal: 230)

        } detail: {
            Group {
                if let selected {
                    ProjectBoardView(project: selected, editProject: { projectEditor = .init(project: selected) }, deleteProject: { deleting = selected }, showSidebar: columnVisibility == .detailOnly ? { withAnimation { columnVisibility = .all } } : nil)
                        .id(selected.id)
                } else {
                    ContentUnavailableView {
                        Label("A little structure for your next idea", systemImage: "rectangle.split.3x1")
                    } description: {
                        Text("Create a project, capture tasks, and move them toward done.")
                    } actions: {
                        Button("Create Project") { projectEditor = .init(project: nil) }.buttonStyle(.borderedProminent)
                    }
                }
            }
            #if os(macOS)
            .padding(.top, isFullScreen ? 32 : 0)
            #else
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { profileButton }
            }
            #endif
        }
        #if os(macOS)
        .toolbarBackground(Color(nsColor: .windowBackgroundColor), for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 16) {
                if selected == nil && columnVisibility == .detailOnly {
                    Button { withAnimation { columnVisibility = .all } } label: {
                        Label("Show Sidebar", systemImage: "sidebar.left")
                    }
                }
                profileButton
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
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
            if let project = task.project { TaskEditor(project: project, task: task, initialStatus: task.status) }
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
    private var profileButton: some View {
        Button { showingProfile = true } label: {
            Label("Profile & Settings", systemImage: "person.crop.circle")
                .font(AppTypography.controlIcon)
        }
        .labelStyle(.iconOnly)
        .help("Profile & Settings")
        .accessibilityLabel("Profile & Settings")
    }

    private var creationMenu: some View {
        Menu {
            Button("New Project…") { projectEditor = .init(project: nil) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New Area…") { areaEditor = .init(area: nil) }
        } label: { Label("Create Project or Area", systemImage: "plus.rectangle.on.folder") }
            .labelStyle(.iconOnly)
            .help("Create Project or Area")
    }

    #if os(iOS)
    private func addProjectRow(in area: ProjectArea?) -> some View {
        Button {
            projectEditor = .init(project: nil, area: area)
        } label: {
            Image(systemName: "plus")
                .font(AppTypography.itemTitle)
                .padding(.leading, projectIndent)
                .foregroundStyle(.tint)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .accessibilityLabel("New project in " + (area?.name ?? "Unassigned"))
    }
    #endif

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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: isCollapsed(key) ? "chevron.right" : "chevron.down")
                    .font(AppTypography.smallIcon)
                    .foregroundStyle(.secondary)
                Text(name)
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(.primary)
                    .padding(.bottom, 7)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(.secondary.opacity(0.18))
                            .frame(height: 0.5)
                            .accessibilityHidden(true)
                    }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .accessibilityLabel("\(isCollapsed(key) ? "Expand" : "Collapse") \(name)")
    }
    private func projectRow(_ project: Project) -> some View {
        NavigationLink(value: project.id) {
            Text(project.name).font(AppTypography.body).padding(.vertical, 4)
                .padding(.leading, projectIndent)
        }
        .tag(project.id)
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
        WorkspaceItemEditor(kind: "Project", isNew: project == nil, name: $name,
                            error: error, save: save) {
            #if os(iOS)
            AppSection("Area") { areaPicker.pickerStyle(.menu) }
            AppSection("Description") { descriptionEditor }
            #else
            areaPicker
            Text("Description").font(AppTypography.sectionTitle)
            descriptionEditor
            #endif
        }
    }

    private var areaPicker: some View {
        Picker("Area", selection: $areaID) {
            Text("Unassigned").tag(nil as UUID?)
            ForEach(areas) { Text($0.name).tag(Optional($0.id)) }
        }
    }

    private var descriptionEditor: some View {
        TextEditor(text: $notes)
            .scrollContentBackground(.hidden)
            .accessibilityLabel("Project description")
            #if os(iOS)
            .frame(minHeight: 140)
            #else
            .frame(height: 100).border(.quaternary)
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

struct TaskEditRequest: Identifiable {
    let id = UUID()
    var task: BoardTask?
    var status: TaskStatus = .backlog
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
    @State private var mobileStatus: TaskStatus = .backlog
    @Bindable var project: Project
    let editProject: () -> Void
    let deleteProject: () -> Void
    let showSidebar: (() -> Void)?
    @State private var editor: TaskEditRequest?
    @State private var calendarTask: BoardTask?
    @State private var deleting: BoardTask?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                #if os(macOS)
                HStack(alignment: .top, spacing: 16) {
                    Text(project.name)
                        .font(AppTypography.boardTitle)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Spacer()
                    if let showSidebar {
                        Button(action: showSidebar) { Image(systemName: "sidebar.left") }
                            .help("Show Sidebar").accessibilityLabel("Show Sidebar")
                    }
                    projectOptions
                }.buttonStyle(.borderless)
                    .padding(.trailing, 46) // Reserve the fixed Profile control at the window edge.
                #endif
                if !project.notes.isEmpty { Text(project.notes).foregroundStyle(.secondary).lineLimit(2) }
                HStack {
                    ProgressView(value: project.progress).frame(width: compactLayout ? 65 : 160)
                    Text(project.progress, format: .percent.precision(.fractionLength(0))).font(AppTypography.itemTitle)
                    Text("· \(project.taskList.filter { $0.status == .done }.count) of \(project.taskList.count) tasks complete")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }.padding(20)
            if compactLayout {
                Picker("Column", selection: $mobileStatus) {
                    ForEach(TaskStatus.allCases) { Text(appearance.title(for: $0)).tag($0) }
                }.pickerStyle(.menu).padding(.horizontal, 20)
            }
            Divider()
            GeometryReader { geometry in
                let statuses = compactLayout ? [mobileStatus] : TaskStatus.allCases
                let spacing: CGFloat = 14
                let horizontalPadding: CGFloat = 20
                let availableWidth = max(0, geometry.size.width - horizontalPadding * 2)
                let gaps = spacing * CGFloat(statuses.count - 1)
                let columnWidth = compactLayout
                    ? availableWidth
                    : max(180, (availableWidth - gaps) / CGFloat(statuses.count))
                let columnHeight = max(0, geometry.size.height - 40)

                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(statuses) { status in
                            column(status, width: columnWidth, height: columnHeight)
                        }
                    }
                    .padding(horizontalPadding)
                }
            }
        }
        #if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
        #endif
        #if os(iOS)
        .navigationTitle(project.name)
        #endif
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { projectOptions }
        }
        #endif
        .sheet(item: $calendarTask) { CalendarDeadlineSheet(task: $0) }
        .sheet(item: $editor) { TaskEditor(project: project, task: $0.task, initialStatus: $0.status) }
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
    private var projectOptions: some View {
        Menu {
            Button("New Task") { editor = .init() }
                .keyboardShortcut("n", modifiers: .command)
            Divider()
            Button("Edit Project", action: editProject)
            Button("Delete Project…", role: .destructive, action: deleteProject)
        } label: { Label("Project Options", systemImage: "ellipsis.circle") }
            .labelStyle(.iconOnly)
            #if os(macOS)
            .scaleEffect(1.6, anchor: .topTrailing)
            .padding(.leading, 18)
            .padding(.bottom, 8)
            #else
            .font(AppTypography.controlIcon)
            #endif
    }

    private func column(_ status: TaskStatus, width: CGFloat, height: CGFloat) -> some View {
        let tasks = project.taskList.filter { $0.status == status }.sorted { $0.createdAt < $1.createdAt }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(appearance.title(for: status), systemImage: status.symbol)
                    .font(AppTypography.sectionTitle).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(appearance.title(for: status))
                Text("\(tasks.count)").foregroundStyle(.secondary)
                Spacer()
                Button { editor = .init(status: status) } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless).help("Add task to \(appearance.title(for: status))")
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
                }.padding(2)
            }
        }
        .padding(12)
        .frame(width: width, height: height)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { values, _ in
            let ids = Set(values.compactMap(UUID.init(uuidString:)))
            let matches = project.taskList.filter { ids.contains($0.id) }
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
            if !task.checklist.isEmpty {
                Label("\(task.checklist.filter(\.isComplete).count)/\(task.checklist.count)", systemImage: "checklist")
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
        WorkspaceItemEditor(kind: "Area", isNew: area == nil, name: $name,
                            validation: duplicate ? "Choose a different area name." : nil,
                            error: error, save: save) {
            Text("Group related projects, such as Work, Personal, or Learning.")
                #if os(iOS)
                .font(AppTypography.supporting)
                .listRowBackground(Color.clear)
                #else
                .font(AppTypography.caption)
                #endif
                .foregroundStyle(.secondary)
        }
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
    let isNew: Bool
    @Binding var name: String
    var validation: String? = nil
    let error: String?
    let save: () -> Void
    @ViewBuilder var content: () -> Content

    private var title: String { "\(isNew ? "New" : "Edit") \(kind)" }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && validation == nil
    }
    private var nameField: some View {
        TextField("\(kind) name", text: $name, prompt: Text("Enter \(kind.lowercased()) name"))
            .accessibilityLabel("\(kind) name")
            #if os(iOS)
            .textInputAutocapitalization(.sentences)
            #endif
    }
    @ViewBuilder private var messages: some View {
        if let validation { Text(validation).foregroundStyle(.red) }
        if let error { Text(error).foregroundStyle(.red) }
    }
    var body: some View {
        #if os(iOS)
        NavigationStack {
            Form {
                AppSection("\(kind) name") { nameField }
                content()
                messages
            }
            .font(AppTypography.body)
            .formStyle(.grouped)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Create" : "Save", action: save).disabled(!canSave)
                }
            }
        }
        #else
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(AppTypography.pageTitle)
            nameField
            content()
            messages
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save", action: save).keyboardShortcut(.defaultAction).disabled(!canSave)
            }
        }.padding(24).modifier(EditorSizing(width: 440))
        #endif
    }
}
