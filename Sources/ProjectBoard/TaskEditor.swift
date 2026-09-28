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
    @State private var dueDate: Date?
    @State private var showingDatePicker = false
    @State private var proposedDate = Date()
    @Query private var profiles: [AppProfile]
    @Query private var allTasks: [BoardTask]
    @State private var tags: [String]
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
        _dueDate = State(initialValue: task?.dueDate)
        _tags = State(initialValue: TagRules.normalized(task?.tags ?? []))
        _checklist = State(initialValue: task?.checklist ?? [])
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(task == nil ? "New Task" : "Edit Task").font(.title2.bold())
                Spacer()
                Text(project.name).font(.title3).foregroundStyle(.secondary).lineLimit(1)
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
                    dueDateField
                    if dueDate != nil {
                        Text("After saving, right-click or long-press the card and choose Add or Update Deadline in Calendar.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Tags") {
                    TagSelector(selection: $tags, available: profiles.flatMap(\.tagNames) + allTasks.flatMap(\.tags))
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
        item.dueDate = dueDate
        item.tags = TagRules.normalized(tags)
        if !tags.isEmpty {
            let profile = AppProfile.current(in: profiles) ?? AppProfile(stageNames: appearance.stageNames, accent: appearance.accent)
            if profile.modelContext == nil {
                profile.appearanceMode = appearance.mode.rawValue
                context.insert(profile)
            }
            profile.tagNames = TagRules.normalized(profiles.flatMap(\.tagNames) + allTasks.flatMap(\.tags) + tags)
        }
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
                                } label: { Image(systemName: "xmark").font(.caption) }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove tag " + tag)
                            }
                        }
                        .font(.callout)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search or create a tag…", text: $query)
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
                            .font(.callout).foregroundStyle(.secondary)
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
