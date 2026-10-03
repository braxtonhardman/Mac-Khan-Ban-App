import SwiftUI
import SwiftData
#if SWIFT_PACKAGE
import BoardCore
#endif

struct TaskEditor: View {
    @Environment(\.boardAppearance) private var appearance
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let project: Project
    let task: BoardTask?
    let parentTask: BoardTask?
    @State private var title: String
    @State private var details: String
    @State private var status: TaskStatus
    @State private var priority: TaskPriority
    @State private var dueDate: Date?
    @State private var showingDatePicker = false
    @State private var proposedDate = Date()
    @Query private var profiles: [AppProfile]
    @Query private var allTasks: [BoardTask]
    @State private var tags: [String]
    @State private var draftTask: BoardTask?
    @State private var subtaskEditor: TaskEditRequest?
    @State private var error: String?
    @State private var confirmingDeletion = false

    init(project: Project, task: BoardTask?, initialStatus: TaskStatus, parentTask: BoardTask? = nil) {
        self.project = project
        self.task = task
        self.parentTask = task?.parentTask ?? parentTask
        _title = State(initialValue: task?.title ?? "")
        _details = State(initialValue: task?.details ?? "")
        _status = State(initialValue: task?.status ?? initialStatus)
        _priority = State(initialValue: task?.priority ?? .normal)
        _dueDate = State(initialValue: task?.dueDate)
        _tags = State(initialValue: TagRules.normalized(task?.tags ?? []))
        _draftTask = State(initialValue: nil)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(editorTitle).font(AppTypography.pageTitle)
                    if let parentTask {
                        Label("Subtask of “\(parentDisplayTitle(parentTask))”", systemImage: "arrow.turn.up.left")
                            .font(AppTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(project.name).font(AppTypography.contextTitle).foregroundStyle(.secondary).lineLimit(1)
                if let task {
                    Button("Delete Task", systemImage: "trash", role: .destructive) {
                        confirmingDeletion = true
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Delete Task")
                    .accessibilityLabel("Delete Task")
                    .confirmationDialog("Delete “\(task.title)”?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
                        Button("Delete Task", role: .destructive, action: deleteTask)
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This permanently deletes the task and any subtasks beneath it. This cannot be undone.")
                    }
                }
            }.padding(20)
            Divider()
            Form {
                AppSection("Task") {
                    TextField("Title", text: $title)
                    Picker("Status", selection: $status) {
                        ForEach(TaskStatus.allCases) { Text(appearance.title(for: $0)).tag($0) }
                    }
                    Picker("Priority", selection: $priority) {
                        ForEach(TaskPriority.allCases) { Text($0.title).tag($0) }
                    }
                }
                AppSection("Description") {
                    TextEditor(text: $details)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 85)
                        .accessibilityLabel("Task description")
                }
                AppSection("Details") {
                    dueDateField
                    if dueDate != nil {
                        Text("After saving, right-click or long-press the card and choose Add or Update Deadline in Calendar.")
                            .font(AppTypography.caption).foregroundStyle(.secondary)
                    }
                }
                AppSection("Tags") {
                    TagSelector(selection: $tags, available: profiles.flatMap(\.tagNames) + allTasks.flatMap(\.tags))
                }
                subtasksSection
            }.formStyle(.grouped)
            if let error { Text(error).foregroundStyle(.red).padding(.horizontal) }
            Divider()
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(saveButtonTitle, action: save).keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(20)
        }
        .modifier(EditorSizing(width: 560, height: 690))
        .sheet(item: $subtaskEditor) { request in
            TaskEditor(
                project: project,
                task: request.task,
                initialStatus: request.status,
                parentTask: request.parentTask
            )
        }
    }

    private var editorTitle: String {
        if parentTask != nil { return task == nil ? "New Subtask" : "Edit Subtask" }
        return task == nil ? "New Task" : "Edit Task"
    }

    private var saveButtonTitle: String { parentTask == nil ? "Save Task" : "Save Subtask" }

    @ViewBuilder
    private var subtasksSection: some View {
        if parentTask == nil {
            let owner = task ?? draftTask
            let subtasks = (owner?.subtaskList ?? []).sorted { $0.createdAt < $1.createdAt }
            let completed = subtasks.filter { $0.status == .done }.count
            AppSection("Subtasks \(completed)/\(subtasks.count)") {
                ForEach(subtasks) { subtask in
                    HStack(spacing: 10) {
                        Button {
                            toggleCompletion(subtask)
                        } label: {
                            Image(systemName: subtask.status == .done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(subtask.status == .done ? Color.accentColor : Color.secondary)
                                .font(AppTypography.sectionTitle)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(subtask.status == .done ? "Mark \(subtask.title) incomplete" : "Mark \(subtask.title) complete")

                        Button {
                            subtaskEditor = .init(task: subtask, status: subtask.status, parentTask: owner)
                        } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(subtask.title)
                                        .font(AppTypography.itemTitle)
                                        .foregroundStyle(.primary)
                                        .strikethrough(subtask.status == .done)
                                    HStack(spacing: 8) {
                                        Text(appearance.title(for: subtask.status))
                                        Text(subtask.priority.title)
                                        if let dueDate = subtask.dueDate {
                                            Label(dueDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                                        }
                                    }
                                    .font(AppTypography.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(AppTypography.smallIcon)
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open subtask \(subtask.title)")
                    }
                    .padding(.vertical, 3)
                }

                Button {
                    let parent = owner ?? makeDraftParent()
                    subtaskEditor = .init(task: nil, status: .backlog, parentTask: parent)
                } label: {
                    Label("Add Subtask", systemImage: "plus")
                }
            }
        }
    }
    private var dueDateField: some View {
        HStack {
            Text("Due date")
            Spacer()
            Button {
                proposedDate = dueDate ?? Date()
                showingDatePicker = true
            } label: {
                HStack(spacing: 6) {
                    if let dueDate {
                        Text(dueDate, format: .dateTime.month(.abbreviated).day().year())
                    } else {
                        Text("Select date…").foregroundStyle(.secondary)
                    }
                    Image(systemName: "calendar")
                }
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Due date")
            .accessibilityValue(dueDate?.formatted(date: .abbreviated, time: .omitted) ?? "No due date")
            .popover(isPresented: $showingDatePicker) {
                VStack(spacing: 16) {
                    DatePicker("Due date", selection: $proposedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                    HStack {
                        Button("Cancel") { showingDatePicker = false }
                        Spacer()
                        Button("Set Date") {
                            dueDate = proposedDate
                            showingDatePicker = false
                        }.buttonStyle(.borderedProminent)
                    }
                }.padding().frame(width: 320)
            }
            if dueDate != nil {
                Button { dueDate = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Clear due date")
            }
        }
    }

    private func toggleCompletion(_ subtask: BoardTask) {
        subtask.status = subtask.status == .done ? .backlog : .done
        subtask.updatedAt = Date()
        do { try StoreWriter.save(context) }
        catch { self.error = error.localizedDescription }
    }
    private func deleteTask() {
        guard let task else { return }
        if task.modelContext == nil {
            task.parentTask = nil
            dismiss()
            return
        }
        context.delete(task)
        do { try StoreWriter.save(context); dismiss() }
        catch { self.error = error.localizedDescription }
    }

    private func save() {
        let defersPersistence = parentTask?.modelContext == nil
        let item = task ?? draftTask ?? BoardTask(title: "", project: defersPersistence ? nil : project)
        item.parentTask = parentTask
        applyEditorValues(to: item)

        // A child of an unsaved parent stays in memory until the parent task is saved.
        // This keeps Cancel on the higher-level New Task sheet free of persistence side effects.
        if let parentTask, defersPersistence {
            if !(parentTask.subtasks ?? []).contains(where: { $0 === item }) {
                parentTask.subtasks = (parentTask.subtasks ?? []) + [item]
            }
            dismiss()
            return
        }

        item.project = project
        for child in item.subtaskList { child.project = project }
        if item.modelContext == nil { context.insert(item) }
        if !tags.isEmpty {
            let profile = AppProfile.current(in: profiles) ?? AppProfile(stageNames: appearance.stageNames, accent: appearance.accent)
            if profile.modelContext == nil {
                profile.appearanceMode = appearance.mode.rawValue
                context.insert(profile)
            }
            profile.tagNames = TagRules.normalized(profiles.flatMap(\.tagNames) + allTasks.flatMap(\.tags) + tags)
        }
        item.updatedAt = Date()
        do { try StoreWriter.save(context); dismiss() }
        catch { self.error = error.localizedDescription }
    }

    private func makeDraftParent() -> BoardTask {
        let parent = BoardTask(title: "", status: status)
        applyEditorValues(to: parent)
        draftTask = parent
        return parent
    }

    private func parentDisplayTitle(_ parent: BoardTask) -> String {
        let cleanTitle = parent.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanTitle.isEmpty ? "New Task" : cleanTitle
    }

    private func applyEditorValues(to item: BoardTask) {
        item.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        item.details = details
        item.status = status
        item.priority = priority
        item.dueDate = dueDate
        item.tags = TagRules.normalized(tags)
        item.updatedAt = Date()
    }
}

/// Search and create controls shared by task editing and the profile tag library.
struct TagSelector: View {
    @Binding var selection: [String]
    let available: [String]
    var allowsRemoval = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var showingSuggestions = false
    @FocusState private var searchFocused: Bool

    private var library: [String] { TagRules.normalized(available + selection) }
    private var search: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var matches: [String] { TagRules.matches(library, query: query) }
    private var canCreate: Bool { !search.isEmpty && TagRules.existing(search, in: library) == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !selection.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(TagRules.normalized(selection), id: \.self) { tag in
                        HStack(spacing: 6) {
                            Text("#" + tag).lineLimit(2)
                            if allowsRemoval {
                                Button {
                                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                                        selection.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
                                    }
                                } label: { Image(systemName: "xmark").font(AppTypography.caption) }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove tag " + tag)
                            }
                        }
                        .font(AppTypography.supporting)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search or create a tag", text: $query, prompt: Text("Search or create a tag…"))
                    .labelsHidden()
                    .accessibilityLabel("Search or create a tag")
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit {
                        if let existing = TagRules.existing(search, in: library) { select(existing) }
                    }
                    .submitScope()
                Button {
                    showingSuggestions.toggle()
                    searchFocused = showingSuggestions
                } label: { Image(systemName: showingSuggestions ? "chevron.up" : "chevron.down") }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showingSuggestions ? "Hide tag suggestions" : "Show tag suggestions")
            }
            .padding(10)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))

            if showingSuggestions {
                VStack(alignment: .leading, spacing: 10) {
                    if matches.isEmpty {
                        Text(search.isEmpty ? "No tags yet. Type a name to create one." : "No tags currently exist for “\(search)”. Create it below.")
                            .font(AppTypography.supporting).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(matches, id: \.self) { tag in
                                    let selected = TagRules.existing(tag, in: selection) != nil
                                    Button { select(tag) } label: {
                                        HStack {
                                            Text("#" + tag).foregroundStyle(.primary)
                                            Spacer()
                                            if selected { Image(systemName: "checkmark") }
                                        }.padding(.vertical, 6).contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain).disabled(selected)
                                    .accessibilityLabel(selected ? tag + ", already added" : "Add tag " + tag)
                                }
                            }
                        }.frame(height: min(CGFloat(matches.count) * 34, 170))
                    }
                    if canCreate {
                        Button { select(search) } label: {
                            Label("Create “\(search)”", systemImage: "plus.circle")
                                .lineLimit(2)
                        }.buttonStyle(.borderless)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: showingSuggestions)
        .onChange(of: searchFocused) { _, focused in showingSuggestions = focused }
        .onChange(of: query) { _, _ in
            if searchFocused { showingSuggestions = true }
        }
    }
    private func select(_ name: String) {
        let canonical = TagRules.existing(name, in: library) ?? name
        selection = TagRules.normalized(selection + [canonical])
        query = ""
        searchFocused = false
        showingSuggestions = false
    }
}
