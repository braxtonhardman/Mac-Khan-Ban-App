import SwiftUI
import SwiftData
#if SWIFT_PACKAGE
import BoardCore
#endif

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.createdAt) private var projects: [Project]
    @Query(sort: \ProjectArea.createdAt) private var areas: [ProjectArea]
    @AppStorage("collapsedAreas") private var collapsedAreas = ""
    @AppStorage("projectRowOverrides") private var projectRowOverrides = ""
    @State private var linkedTask: BoardTask?
    @State private var showingProfile = false
    @State private var areaEditor: AreaEditRequest?
    @State private var removingArea: ProjectArea?
    @State private var selection: UUID?
    @State private var projectEditor: ProjectEditRequest?
    @State private var deleting: Project?
    @State private var error: String?

    private var selected: Project? { projects.first { $0.id == selection } }
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    if !isCollapsed("unassigned") {
                        ForEach(projects.filter { $0.area == nil }) { projectRow($0) }
                    }
                } header: { areaHeader("Unassigned", key: "unassigned") }
                ForEach(areas) { area in
                    Section {
                        if !isCollapsed(area.id.uuidString) {
                            ForEach(projects.filter { $0.area?.id == area.id }) { projectRow($0) }
                            if area.projectList.isEmpty {
                                Text("No projects yet").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        areaHeader(area.name, key: area.id.uuidString)
                            .contextMenu {
                                Button("New Project in Area…") { projectEditor = .init(project: nil, area: area) }
                                Button("Rename Area…") { areaEditor = .init(area: area) }
                                Button("Remove Area…") { removingArea = area }
                                Divider()
                                Button("New Area…") { areaEditor = .init(area: nil) }
                            }
                    }
                }
            }
            .contextMenu {
                Button("New Area…") { areaEditor = .init(area: nil) }
                Button("New Project…") { projectEditor = .init(project: nil) }.keyboardShortcut("n", modifiers: [.command, .shift])
            }
            .navigationTitle("ProjectBoard")
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button("New Project…") { projectEditor = .init(project: nil) }
                            .keyboardShortcut("n", modifiers: [.command, .shift])
                        Button("New Area…") { areaEditor = .init(area: nil) }
                    } label: { Label("Create Project or Area", systemImage: "plus.rectangle.on.folder") }
                        .help("Create Project or Area")
                }
            }

        } detail: {
            if let selected {
                ProjectBoardView(project: selected, editProject: { projectEditor = .init(project: selected) }, deleteProject: { deleting = selected })
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingProfile = true } label: { Label("Profile & Settings", systemImage: "person.crop.circle") }
                    .help("Profile & Settings")
            }
        }
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
        .confirmationDialog("Remove \(removingArea?.name ?? "area")?", isPresented: Binding(get: { removingArea != nil }, set: { if !$0 { removingArea = nil } })) {
            Button("Remove Area") {
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
    private func isCollapsed(_ key: String) -> Bool { collapsedAreas.split(separator: ",").contains(Substring(key)) }
    private func toggle(_ key: String, in value: inout String) {
        var keys = Set(value.split(separator: ",").map(String.init))
        if keys.contains(key) { keys.remove(key) } else { keys.insert(key) }
        value = keys.sorted().joined(separator: ",")
    }
    private func areaHeader(_ name: String, key: String) -> some View {
        Button { toggle(key, in: &collapsedAreas) } label: {
            HStack {
                Image(systemName: isCollapsed(key) ? "chevron.right" : "chevron.down")
                Text(name)
                Spacer()
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel("\(isCollapsed(key) ? "Expand" : "Collapse") \(name)")
    }
    private func isCompact(_ project: Project) -> Bool {
        let overridden = projectRowOverrides.split(separator: ",").contains(Substring(project.id.uuidString))
        #if os(iOS)
        return !overridden
        #else
        return overridden
        #endif
    }
    private func projectRow(_ project: Project) -> some View {
        NavigationLink(value: project.id) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(project.name).font(isCompact(project) ? .body : .headline)
                    Spacer()
                    Button { toggle(project.id.uuidString, in: &projectRowOverrides) } label: {
                        Image(systemName: isCompact(project) ? "chevron.down" : "chevron.up").font(.caption)
                    }.buttonStyle(.borderless)
                        .accessibilityLabel(isCompact(project) ? "Show project progress" : "Hide project progress")
                }
                if !isCompact(project) {
                    HStack {
                        ProgressView(value: project.progress).frame(width: 90)
                        Text(project.progress, format: .percent.precision(.fractionLength(0)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.padding(.vertical, isCompact(project) ? 0 : 5)
        }
        .tag(project.id)
        .contextMenu {
            Button(isCompact(project) ? "Show Project Progress" : "Compact Project Row") { toggle(project.id.uuidString, in: &projectRowOverrides) }
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
        VStack(alignment: .leading, spacing: 16) {
            Text(project == nil ? "New Project" : "Edit Project").font(.title2.bold())
            TextField("Project name", text: $name)
            Picker("Area", selection: $areaID) {
                Text("Unassigned").tag(nil as UUID?)
                ForEach(areas) { Text($0.name).tag(Optional($0.id)) }
            }
            Text("Description").font(.headline)
            TextEditor(text: $notes).frame(height: 100).border(.quaternary)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    let item = project ?? Project(name: "")
                    if project == nil { context.insert(item) }
                    item.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    item.notes = notes
                    item.area = areas.first { $0.id == areaID }
                    do { try StoreWriter.save(context); onSave(item.id); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).modifier(EditorSizing(width: 440))
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
    @State private var editor: TaskEditRequest?
    @State private var calendarTask: BoardTask?
    @State private var deleting: BoardTask?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                if !project.notes.isEmpty { Text(project.notes).foregroundStyle(.secondary).lineLimit(2) }
                HStack {
                    ProgressView(value: project.progress).frame(width: compactLayout ? 65 : 160)
                    Text(project.progress, format: .percent.precision(.fractionLength(0))).font(.headline)
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
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(compactLayout ? [mobileStatus] : TaskStatus.allCases) { status in
                        column(status)
                    }
                }.padding(20)
            }
        }
        .navigationTitle(project.name)
        .toolbar {
            Button { editor = .init() } label: { Label("New Task", systemImage: "plus") }
                .keyboardShortcut("n", modifiers: .command)
            Menu {
                Button("Edit Project", action: editProject)
                Button("Delete Project…", role: .destructive, action: deleteProject)
            } label: { Label("Project Options", systemImage: "ellipsis.circle") }
        }
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
    private func column(_ status: TaskStatus) -> some View {
        let tasks = project.taskList.filter { $0.status == status }.sorted { $0.createdAt < $1.createdAt }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(appearance.title(for: status), systemImage: status.symbol).font(.headline)
                Text("\(tasks.count)").foregroundStyle(.secondary)
                Spacer()
                Button { editor = .init(status: status) } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless).help("Add task to \(appearance.title(for: status))")
            }
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
                        Text("Drop a task here").font(.caption).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity).padding(.vertical, 28)
                    }
                }.padding(2)
            }
        }
        .padding(12).frame(width: compactLayout ? 285 : 245)
        .frame(maxHeight: .infinity)
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
            Text(task.title).font(.headline).fixedSize(horizontal: false, vertical: true)
            if !task.details.isEmpty { Text(task.details).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            HStack {
                Text(task.priority.title).font(.caption.weight(.medium))
                    .foregroundStyle(task.priority.rawValue >= 2 ? Color.orange : Color.secondary)
                Spacer()
                if let date = task.dueDate {
                    Label(date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        .font(.caption2)
                        .foregroundStyle(date < Calendar.current.startOfDay(for: Date()) && task.status != .done ? Color.red : Color.secondary)
                }
            }
            if !task.tags.isEmpty {
                Text(task.tags.map { "#\($0)" }.joined(separator: "  ")).font(.caption).foregroundStyle(.tint).lineLimit(2)
            }
            if !task.checklist.isEmpty {
                Label("\(task.checklist.filter(\.isComplete).count)/\(task.checklist.count)", systemImage: "checklist")
                    .font(.caption).foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 16) {
            Text(area == nil ? "New Area" : "Rename Area").font(.title2.bold())
            TextField("Area name", text: $name)
            Text("Group related projects, such as Work, Personal, or Learning.")
                .font(.caption).foregroundStyle(.secondary)
            if duplicate { Text("Choose a different area name.").foregroundStyle(.red) }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    let item = area ?? ProjectArea(name: cleanName)
                    if area == nil { context.insert(item) }
                    item.name = cleanName
                    do { try StoreWriter.save(context); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).disabled(cleanName.isEmpty || duplicate)
            }
        }.padding(24).modifier(EditorSizing(width: 440))
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
        content.frame(width: width, height: height)
        #else
        content.frame(maxWidth: .infinity)
        #endif
    }
}
