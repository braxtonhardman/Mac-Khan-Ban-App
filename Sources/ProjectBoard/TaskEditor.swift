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

struct TaskEditor: View {
    @Environment(\.boardAppearance) private var appearance
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let project: Project
    let task: BoardTask?
    let parentTask: BoardTask?
    let onDelete: () -> Void
    let onClose: (() -> Void)?
    @State private var title: String
    @State private var details: String
    @State private var isDescriptionEditing = false
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

    init(
        project: Project,
        task: BoardTask?,
        initialStatus: TaskStatus,
        parentTask: BoardTask? = nil,
        onDelete: @escaping () -> Void = {},
        onClose: (() -> Void)? = nil
    ) {
        self.project = project
        self.task = task
        self.parentTask = task?.parentTask ?? parentTask
        self.onDelete = onDelete
        self.onClose = onClose
        _title = State(initialValue: task?.title ?? "")
        _details = State(initialValue: task?.details ?? "")
        _status = State(initialValue: task?.status ?? initialStatus)
        _priority = State(initialValue: task?.priority ?? .normal)
        _dueDate = State(initialValue: task?.dueDate)
        _tags = State(initialValue: TagRules.normalized(task?.tags ?? []))
        _draftTask = State(initialValue: nil)
    }
    var body: some View {
        Group {
            #if os(iOS)
            editorLayout.presentationDetents([.large])
            #else
            editorLayout
            #endif
        }
        .modifier(EditorSizing(width: 560, height: 690))
        .modifier(TagCreationHost())
        .confirmationDialog("Delete “\(task?.title ?? "task")”?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
            Button("Delete Task", role: .destructive, action: deleteTask)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the task and any subtasks beneath it. This cannot be undone.")
        }
        #if os(iOS)
        .sheet(item: $subtaskEditor) { request in
            TaskEditor(
                project: project,
                task: request.task,
                initialStatus: request.status,
                parentTask: request.parentTask
            )
        }
        #else
        .overlay {
            if let request = subtaskEditor {
                MacInWindowModal(onDismiss: { subtaskEditor = nil }) {
                    TaskEditor(
                        project: project,
                        task: request.task,
                        initialStatus: request.status,
                        parentTask: request.parentTask,
                        onClose: { subtaskEditor = nil }
                    )
                }
            }
        }
        #endif
    }

    private var editorLayout: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                ZStack {
                    Text(editorTitle).font(AppTypography.pageTitle)
                    HStack {
                        if parentTask == nil {
                            AppGlassActionButton(symbol: .cancel, accessibilityLabel: "Cancel", action: close)
                                .keyboardShortcut(.cancelAction)
                        } else {
                            Button(action: close) { Image(systemName: "chevron.left") }
                                .appGlassButton(size: .medium, shape: .circle)
                                .keyboardShortcut(.cancelAction)
                                .accessibilityLabel("Back to parent task")
                        }
                        Spacer()
                        if task == nil {
                            AppGlassActionButton(
                                symbol: .confirm,
                                accessibilityLabel: parentTask == nil ? "Create Task" : "Create Subtask",
                                accent: true,
                                action: save
                            )
                                .keyboardShortcut(.defaultAction)
                                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        } else {
                            AppGlassActionButton(
                                symbol: .confirm,
                                accessibilityLabel: parentTask == nil ? "Save Task" : "Save Subtask",
                                accent: true,
                                action: save
                            )
                                .keyboardShortcut(.defaultAction)
                                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                HStack(spacing: 12) {
                    if let parentTask {
                        Label("Subtask of “\(parentDisplayTitle(parentTask))”", systemImage: "arrow.turn.up.left")
                            .font(AppTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(project.name).font(AppTypography.contextTitle).foregroundStyle(.secondary).lineLimit(1)
                    if task != nil {
                        Button {
                            confirmingDeletion = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .appGlassButton(size: .small, shape: .circle)
                        .help("Delete Task")
                        .accessibilityLabel("Delete Task")
                    }
                }
            }
            .padding(20)
            Divider()
            Form {
                AppSection("Task", headingColor: .white) {
                    TextField("Title", text: $title)
                    Picker("Status", selection: $status) {
                        ForEach(TaskStatus.allCases) { Text(appearance.title(for: $0)).tag($0) }
                    }
                    Picker("Priority", selection: $priority) {
                        ForEach(TaskPriority.allCases) { Text($0.title).tag($0) }
                    }
                }
                AppSection("Description", headingColor: .white) {
                    HStack {
                        Spacer()
                        Button(isDescriptionEditing ? "Preview" : "Edit") {
                            isDescriptionEditing.toggle()
                        }
                        .appGlassButton(size: .small, shape: .rectangle)
                        .accessibilityLabel(isDescriptionEditing ? "Preview task description" : "Edit task description")
                    }
                    if isDescriptionEditing {
                        AdaptiveTaskDescriptionEditor(text: $details)
                            .frame(minHeight: 85)
                            .accessibilityLabel("Task description Markdown")
                    } else {
                        MarkdownDescriptionPreview(markdown: details)
                            .frame(maxWidth: .infinity, minHeight: 85, alignment: .topLeading)
                    }
                }
                AppSection("Details", headingColor: .white) {
                    dueDateField
                    if dueDate != nil {
                        Text("Connect Apple Calendar in Profile to automatically sync task deadlines to your chosen calendar.")
                            .font(AppTypography.caption).foregroundStyle(.secondary)
                    }
                }
                AppSection("Tags", headingColor: .white) {
                    TagSelector(selection: $tags, available: profiles.flatMap(\.tagNames) + allTasks.flatMap(\.tags))
                }
                subtasksSection
            }.formStyle(.grouped)
            if let error { Text(error).foregroundStyle(.red).padding(.horizontal) }
        }
    }

    private var editorTitle: String {
        if parentTask != nil { return task == nil ? "New Subtask" : "Edit Subtask" }
        return task == nil ? "New Task" : "Edit Task"
    }

    @ViewBuilder
    private var subtasksSection: some View {
        if parentTask == nil {
            let owner = task ?? draftTask
            let subtasks = (owner?.subtaskList ?? []).sorted { $0.createdAt < $1.createdAt }
            let completed = subtasks.filter { $0.status == .done }.count
            AppSection("Subtasks \(completed)/\(subtasks.count)", headingColor: .white) {
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
                .appGlassButton(accent: true)
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
            .appGlassButton(size: .small, shape: .rectangle)
            .accessibilityLabel("Due date")
            .accessibilityValue(dueDate?.formatted(date: .abbreviated, time: .omitted) ?? "No due date")
            .popover(isPresented: $showingDatePicker) {
                VStack(spacing: 16) {
                    DatePicker("Due date", selection: $proposedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                    HStack {
                        AppGlassActionButton(
                            symbol: .cancel,
                            accessibilityLabel: "Cancel",
                            action: { showingDatePicker = false }
                        )
                        Spacer()
                        AppGlassActionButton(
                            symbol: .confirm,
                            accessibilityLabel: "Set Date",
                            accent: true,
                            action: {
                                dueDate = proposedDate
                                showingDatePicker = false
                            }
                        )
                    }
                }.padding().frame(width: 320)
                #if os(iOS)
                .modifier(DismissSheetOnOutsideTap())
                #endif
            }
            if dueDate != nil {
                Button { dueDate = nil } label: {
                    AppActionGlyph(symbol: .cancel, size: .small)
                }
                .appGlassButton(size: .small, shape: .circle)
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
            onDelete()
            close()
            return
        }
        context.delete(task)
        do {
            try StoreWriter.save(context)
            onDelete()
            close()
        }
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
            close()
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
        do { try StoreWriter.save(context); close() }
        catch { self.error = error.localizedDescription }
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
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

/// Keeps the task description visually still while its text fits, then enables an overlay scrollbar.
#if os(macOS)
private struct AdaptiveTaskDescriptionEditor: NSViewRepresentable {
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
        textView.setAccessibilityLabel("Task description")
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
#else
private struct AdaptiveTaskDescriptionEditor: UIViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.text = text
        textView.backgroundColor = .clear
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.textColor = .label
        textView.tintColor = .tintColor
        textView.adjustsFontForContentSizeCategory = true
        textView.alwaysBounceVertical = false
        textView.showsVerticalScrollIndicator = true
        textView.showsHorizontalScrollIndicator = false
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 5, bottom: 8, right: 5)
        textView.textContainer.lineFragmentPadding = 0
        textView.accessibilityLabel = "Task description"
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        guard textView.text != text else { return }
        textView.text = text
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding private var text: String

        init(text: Binding<String>) { _text = text }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
        }
    }
}
#endif

/// Search and create controls shared by task editing and the profile tag library.
struct TagSelector: View {
    @Binding var selection: [String]
    @Environment(\.createTag) private var createTag
    @Query private var tagProfiles: [AppProfile]
    @Environment(\.boardAppearance) private var tagAppearance
    let available: [String]
    var allowsRemoval = true
    var tagsBelowSearch = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var showingSuggestions = false
    @FocusState private var searchFocused: Bool

    private var library: [String] { TagRules.normalized(available + selection) }
    private var search: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var matches: [String] { TagRules.matches(library, query: query) }
    private var canCreate: Bool { TagRules.isValidNewName(search) && TagRules.existing(search, in: library) == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !tagsBelowSearch { selectedTags }
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

            if tagsBelowSearch { selectedTags }

            if showingSuggestions {
                VStack(alignment: .leading, spacing: 10) {
                    if search.count > TagRules.maximumNameLength {
                        Text("Tag names can have up to \(TagRules.maximumNameLength) characters.")
                            .font(AppTypography.supporting).foregroundStyle(.secondary)
                    } else if matches.isEmpty {
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
                                            Circle().fill(tagColor(tag)).frame(width: 8, height: 8)
                                            Text(tag).foregroundStyle(.primary).lineLimit(1)
                                            Spacer()
                                            if selected { AppActionGlyph(symbol: .confirm, size: .small) }
                                        }.padding(.vertical, 6).contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain).disabled(selected)
                                    .accessibilityLabel(selected ? tag + ", already added" : "Add tag " + tag)
                                }
                            }
                        }.frame(height: min(CGFloat(matches.count) * 34, 170))
                    }
                    if canCreate {
                        AppGlassActionButton(
                            symbol: .confirm,
                            accessibilityLabel: "Create tag \(search)",
                            accent: true,
                            action: {
                                searchFocused = false
                                createTag(search) { select($0) }
                            }
                        )
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
    @ViewBuilder private var selectedTags: some View {
        if !selection.isEmpty {
            TagFlowLayout {
                ForEach(TagRules.normalized(selection), id: \.self) { tag in
                    HStack(spacing: 6) {
                        EditableTagChip(name: tag, color: tagColor(tag)) {
                            selection.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
                        }
                        if allowsRemoval {
                            Button {
                                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                                    selection.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
                                }
                            } label: { AppActionGlyph(symbol: .cancel, size: .small) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove tag " + tag + " from this task")
                        }
                    }
                }
            }
        }
    }
    private func tagColor(_ name: String) -> Color {
        (AppProfile.current(in: tagProfiles)?.color(forTag: name) ?? tagAppearance.accent).color
    }
    private func select(_ name: String) {
        let canonical = TagRules.existing(name, in: library) ?? name
        selection = TagRules.normalized(selection + [canonical])
        query = ""
        searchFocused = false
        showingSuggestions = false
    }
}


private struct CreateTagKey: EnvironmentKey {
    static let defaultValue: (String, @escaping (String) -> Void) -> Void = { _, _ in }
}
private struct EditTagKey: EnvironmentKey {
    static let defaultValue: (String, @escaping () -> Void) -> Void = { _, _ in }
}
private extension EnvironmentValues {
    var editTag: (String, @escaping () -> Void) -> Void {
        get { self[EditTagKey.self] }
        set { self[EditTagKey.self] = newValue }
    }
    var createTag: (String, @escaping (String) -> Void) -> Void {
        get { self[CreateTagKey.self] }
        set { self[CreateTagKey.self] = newValue }
    }
}
private struct TagCreationRequest: Identifiable {
    let id = UUID()
    let name: String
    let onCreate: (String) -> Void
    var isNew = true
    var onDelete: (() -> Void)?
}

/// Install at the editor boundary so the Mac popup covers the editor, not the tag field.
struct TagCreationHost: ViewModifier {
    var backToParent = false
    @State private var request: TagCreationRequest?
    func body(content: Content) -> some View {
        content
            .environment(\.createTag, { name, onCreate in
                request = TagCreationRequest(name: name, onCreate: onCreate)
            })
            .environment(\.editTag, { name, onDelete in
                request = TagCreationRequest(name: name, onCreate: { _ in }, isNew: false, onDelete: onDelete)
            })
            #if os(iOS)
            .sheet(item: $request) { item in
                TagCreationView(name: item.name, isNew: item.isNew, backToParent: backToParent, onCreate: item.onCreate, onDelete: item.onDelete, onClose: { request = nil })
                    .presentationDetents([.medium, .large])
                    .modifier(DismissSheetOnOutsideTap())
            }
            #else
            .overlay {
                if let item = request {
                    MacInWindowModal(onDismiss: { request = nil }) {
                        TagCreationView(name: item.name, isNew: item.isNew, backToParent: backToParent, onCreate: item.onCreate, onDelete: item.onDelete, onClose: { request = nil })
                            .frame(width: 410)
                    }
                }
            }
            #endif
    }
}

private struct TagCreationView: View {
    let name: String
    let isNew: Bool
    let backToParent: Bool
    let onCreate: (String) -> Void
    let onDelete: (() -> Void)?
    let onClose: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.boardAppearance) private var appearance
    @Query private var profiles: [AppProfile]
    @State private var color: AccentChoice?
    @State private var error: String?
    @State private var confirmingDeletion = false
    private var selectedColor: AccentChoice {
        color ?? AppProfile.current(in: profiles)?.color(forTag: name) ?? appearance.accent
    }

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Text(isNew ? "New Tag" : "Edit Tag").font(AppTypography.pageTitle)
                HStack {
                    AppGlassActionButton(symbol: backToParent ? .back : .cancel, accessibilityLabel: backToParent ? "Back to Tags" : "Cancel tag changes", action: onClose)
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    AppGlassActionButton(symbol: .confirm, accessibilityLabel: isNew ? "Create tag" : "Save tag", action: save)
                        .keyboardShortcut(.defaultAction)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    AppSection("Tag") {
                        TagChip(name: name, color: selectedColor.color)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    AppSection("Color") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 12) {
                            ForEach(AccentChoice.allCases) { choice in
                                Button { color = choice } label: {
                                    ZStack {
                                        Circle().fill(choice.color.opacity(0.18))
                                        Circle().fill(choice.color).padding(10)
                                        if selectedColor == choice {
                                            Image(systemName: "checkmark")
                                                .font(AppTypography.body.weight(.bold))
                                                .foregroundStyle(choice == .yellow ? Color.black : Color.white)
                                        }
                                    }
                                    .frame(width: 48, height: 48)
                                    .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(choice.title)
                                .accessibilityAddTraits(selectedColor == choice ? [.isSelected] : [])
                            }
                        }
                    }
                    Text("This color is used wherever this tag appears.")
                        .font(AppTypography.caption).foregroundStyle(.secondary)
                    if !isNew {
                        Button(role: .destructive) { confirmingDeletion = true } label: {
                            Label("Delete Tag", systemImage: "trash")
                        }
                        .appGlassButton(size: .medium, shape: .rectangle)
                    }
                    if let error { Text(error).font(AppTypography.supporting).foregroundStyle(.red) }
                }
            }
            .frame(maxHeight: 300)
        }
        .padding(24)
        .confirmationDialog("Delete “\(name)”?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
            Button("Delete Tag", role: .destructive, action: delete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the tag from your library and every task and subtask. Your tasks will remain.")
        }
    }
    private func delete() {
        do {
            try StoreWriter.deleteTag(name, in: context)
            onDelete?()
            onClose()
        } catch { self.error = error.localizedDescription }
    }
    private func save() {
        guard !isNew || TagRules.isValidNewName(name) else {
            error = "Use a tag name with 1–\(TagRules.maximumNameLength) characters on one line."
            return
        }
        let profile = AppProfile.current(in: profiles) ?? AppProfile(stageNames: appearance.stageNames, accent: appearance.accent)
        if profile.modelContext == nil {
            profile.appearanceMode = appearance.mode.rawValue
            context.insert(profile)
        }
        let canonical = TagRules.existing(name, in: profiles.flatMap(\.tagNames)) ?? name
        profile.tagNames = TagRules.normalized(profiles.flatMap(\.tagNames) + [canonical])
        profile.setColor(selectedColor, forTag: canonical)
        profile.updatedAt = Date()
        do {
            // A confirmed tag is a reusable library item even if its task draft is later cancelled.
            try StoreWriter.save(context)
            onCreate(canonical)
            onClose()
        } catch { self.error = error.localizedDescription }
    }
}

/// Wrap whole chips, measuring their natural width instead of forcing equal grid cells.
struct TagFlowLayout: Layout {
    var spacing: CGFloat = 8

    private func arrangement(width: CGFloat, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for subview in subviews {
            let natural = subview.sizeThatFits(.unspecified)
            let size = subview.sizeThatFits(ProposedViewSize(width: min(natural.width, width), height: nil))
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            usedWidth = max(usedWidth, x + size.width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: usedWidth, height: y + rowHeight), frames)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(width: max(0, proposal.width ?? .infinity), subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangement(width: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, result.frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }
}

struct TagChip: View {
    static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 4, style: .continuous) }
    let name: String
    let color: Color
    var compact = false
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(name).lineLimit(1).truncationMode(.tail)
        }
        .font(compact ? AppTypography.caption : AppTypography.supporting)
        .foregroundStyle(.primary)
        .padding(.horizontal, compact ? 7 : 10)
        .padding(.vertical, compact ? 3 : 6)
        .background(color.opacity(0.15), in: Self.shape)
    }
}

/// Selects the longest alphabetical prefix that fits; hidden tags are absent from accessibility too.
struct TaskCardTags: View {
    let tags: [String]
    @Query private var profiles: [AppProfile]
    @Environment(\.boardAppearance) private var appearance
    var body: some View {
        let ordered = TagRules.normalized(tags)
        ViewThatFits(in: .horizontal) {
            ForEach((1...max(1, ordered.count)).reversed(), id: \.self) { count in
                HStack(spacing: 5) {
                    ForEach(Array(ordered.prefix(count)), id: \.self) { tag in
                        TagChip(name: tag, color: (AppProfile.current(in: profiles)?.color(forTag: tag) ?? appearance.accent).color, compact: true)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


/// The full rounded tag is the edit target, with no extra edit icon.
struct EditableTagChip: View {
    let name: String
    let color: Color
    var onDelete: () -> Void = {}
    @Environment(\.editTag) private var editTag
    var body: some View {
        Button { editTag(name, onDelete) } label: {
            TagChip(name: name, color: color)
                .contentShape(TagChip.shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit tag " + name)
    }
}

/// Renders a practical subset of Markdown while keeping the stored description as plain text.
struct MarkdownDescriptionPreview: View {
    let markdown: String

    var body: some View {
        if markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("No description")
                .font(AppTypography.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(blocks) { block in
                    blockView(block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .tint(Color.accentColor)
        }
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block.kind {
        case .paragraph:
            inlineText(block.content)
                .font(AppTypography.body)
                .fixedSize(horizontal: false, vertical: true)
        case .heading(let level):
            inlineText(block.content)
                .font(level == 1 ? AppTypography.pageTitle : level == 2 ? AppTypography.sectionTitle : AppTypography.itemTitle)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                inlineText(block.content)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(AppTypography.body)
        case .number(let marker):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker)
                inlineText(block.content)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(AppTypography.body)
        case .quote:
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: 3)
                inlineText(block.content)
                    .font(AppTypography.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .code:
            Text(block.content)
                .font(AppTypography.supporting.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .textSelection(.enabled)
        }
    }

    private func inlineText(_ source: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let attributed = try? AttributedString(markdown: source, options: options) else {
            return Text(source)
        }
        return Text(attributed)
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var paragraph: [String] = []
        var paragraphStart = 0
        var code: [String] = []
        var codeStart = 0
        var inCode = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            result.append(Block(id: paragraphStart, kind: .paragraph, content: paragraph.joined(separator: "\n")))
            paragraph.removeAll()
        }

        for (lineNumber, line) in markdown.components(separatedBy: "\n").enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                flushParagraph()
                if inCode {
                    result.append(Block(id: codeStart, kind: .code, content: code.joined(separator: "\n")))
                    code.removeAll()
                } else {
                    codeStart = lineNumber
                }
                inCode.toggle()
                continue
            }
            if inCode {
                code.append(line)
                continue
            }
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }
            let hashes = trimmed.prefix(while: { $0 == "#" }).count
            if (1...3).contains(hashes), trimmed.dropFirst(hashes).first == " " {
                flushParagraph()
                result.append(Block(id: lineNumber, kind: .heading(hashes), content: String(trimmed.dropFirst(hashes + 1))))
            } else if ["- ", "* ", "+ "].contains(where: { trimmed.hasPrefix($0) }) {
                flushParagraph()
                result.append(Block(id: lineNumber, kind: .bullet, content: String(trimmed.dropFirst(2))))
            } else if let dot = trimmed.firstIndex(of: "."), !trimmed[..<dot].isEmpty,
                      trimmed[..<dot].allSatisfy({ $0.isNumber }),
                      trimmed[trimmed.index(after: dot)...].first == " " {
                flushParagraph()
                let marker = String(trimmed[...dot])
                result.append(Block(id: lineNumber, kind: .number(marker), content: String(trimmed.dropFirst(marker.count + 1))))
            } else if trimmed.hasPrefix("> ") {
                flushParagraph()
                result.append(Block(id: lineNumber, kind: .quote, content: String(trimmed.dropFirst(2))))
            } else {
                if paragraph.isEmpty { paragraphStart = lineNumber }
                paragraph.append(line)
            }
        }
        if inCode {
            result.append(Block(id: codeStart, kind: .code, content: code.joined(separator: "\n")))
        }
        flushParagraph()
        return result
    }

    private struct Block: Identifiable {
        enum Kind {
            case paragraph, heading(Int), bullet, number(String), quote, code
        }

        let id: Int
        let kind: Kind
        let content: String
    }
}
