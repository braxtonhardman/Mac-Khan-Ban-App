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
    @State private var title: String
    @State private var details: String
    @State private var status: TaskStatus
    @State private var priority: TaskPriority
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var tags: String
    @State private var checklist: [ChecklistItem]
    @State private var newItem = ""
    @State private var error: String?

    init(project: Project, task: BoardTask?, initialStatus: TaskStatus) {
        self.project = project
        self.task = task
        _title = State(initialValue: task?.title ?? "")
        _details = State(initialValue: task?.details ?? "")
        _status = State(initialValue: task?.status ?? initialStatus)
        _priority = State(initialValue: task?.priority ?? .normal)
        _hasDueDate = State(initialValue: task?.dueDate != nil)
        _dueDate = State(initialValue: task?.dueDate ?? Date())
        _tags = State(initialValue: task?.tags.joined(separator: ", ") ?? "")
        _checklist = State(initialValue: task?.checklist ?? [])
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(task == nil ? "New Task" : "Edit Task").font(.title2.bold())
                Spacer()
                Text(project.name).foregroundStyle(.secondary).lineLimit(1)
            }.padding(20)
            Divider()
            Form {
                Section("Task") {
                    TextField("Title", text: $title)
                    Picker("Status", selection: $status) {
                        ForEach(TaskStatus.allCases) { Text(appearance.title(for: $0)).tag($0) }
                    }
                    Picker("Priority", selection: $priority) {
                        ForEach(TaskPriority.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section("Description") {
                    TextEditor(text: $details)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 85)
                        .accessibilityLabel("Task description")
                }
                Section("Details") {
                    Toggle("Due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                        Text("After saving, right-click or long-press the card and choose Add or Update Deadline in Calendar.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    TextField("Tags, separated by commas", text: $tags)
                }
                Section("Checklist") {
                    ForEach($checklist) { $item in
                        HStack {
                            Toggle("Complete", isOn: $item.isComplete).labelsHidden()
                                .accessibilityLabel("Complete \(item.title)")
                            TextField("Subtask", text: $item.title)
                            Button {
                                checklist.removeAll { $0.id == item.id }
                            } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless).help("Remove subtask")
                        }
                    }
                    HStack {
                        TextField("Add a subtask", text: $newItem).onSubmit(addItem)
                        Button("Add", action: addItem)
                            .disabled(newItem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }.formStyle(.grouped)
            if let error { Text(error).foregroundStyle(.red).padding(.horizontal) }
            Divider()
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save Task", action: save).keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(20)
        }.modifier(EditorSizing(width: 560, height: 690))
    }
    private func addItem() {
        let text = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        checklist.append(ChecklistItem(title: text))
        newItem = ""
    }
    private func save() {
        addItem()
        let item = task ?? BoardTask(title: "", project: project)
        if task == nil { context.insert(item) }
        item.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        item.details = details
        item.status = status
        item.priority = priority
        item.dueDate = hasDueDate ? dueDate : nil
        item.tags = BoardRules.tags(from: tags)
        item.checklist = checklist.compactMap {
            var copy = $0
            copy.title = copy.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return copy.title.isEmpty ? nil : copy
        }
        item.updatedAt = Date()
        do { try StoreWriter.save(context); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
