import SwiftUI
import SwiftData
#if SWIFT_PACKAGE
import BoardCore
#endif

/// Read-only presentation for an existing task. Editing stays behind an explicit action.
struct TaskDetailView: View {
    @Environment(\.boardAppearance) private var appearance
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let project: Project
    @Bindable var task: BoardTask
    let onClose: (() -> Void)?
    @Query private var profiles: [AppProfile]
    @State private var showingEditor = false
    @State private var selectedSubtask: BoardTask?
    @State private var taskWasDeleted = false
    @State private var error: String?

    var body: some View {
        Group {
            #if os(iOS)
            detailLayout.presentationDetents([.large])
            #else
            detailLayout
            #endif
        }
        .modifier(EditorSizing(width: 620, height: 700))
        .modifier(TagCreationHost())
        #if os(iOS)
        .sheet(isPresented: $showingEditor, onDismiss: finishEditing) {
            TaskEditor(
                project: project,
                task: task,
                initialStatus: task.status,
                parentTask: task.parentTask,
                onDelete: { taskWasDeleted = true }
            )
        }
        .sheet(item: $selectedSubtask) { subtask in
            TaskDetailView(project: project, task: subtask, onClose: nil)
        }
        #else
        .overlay {
            if showingEditor {
                MacInWindowModal(onDismiss: { showingEditor = false; finishEditing() }) {
                    TaskEditor(
                        project: project,
                        task: task,
                        initialStatus: task.status,
                        parentTask: task.parentTask,
                        onDelete: { taskWasDeleted = true },
                        onClose: {
                            showingEditor = false
                            finishEditing()
                        }
                    )
                }
            } else if let selectedSubtask {
                MacInWindowModal(onDismiss: { self.selectedSubtask = nil }) {
                    TaskDetailView(
                        project: project,
                        task: selectedSubtask,
                        onClose: { self.selectedSubtask = nil }
                    )
                }
            }
        }
        #endif
        .alert("Couldn’t update subtask", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private var detailLayout: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(task.parentTask == nil ? "Task Details" : "Subtask Details")
                    .font(AppTypography.pageTitle)
                HStack {
                    if task.parentTask == nil {
                        AppGlassActionButton(symbol: .cancel, accessibilityLabel: "Close", action: close)
                            .keyboardShortcut(.cancelAction)
                    } else {
                        Button(action: close) { Image(systemName: "chevron.left") }
                            .appGlassButton(size: .medium, shape: .circle)
                            .keyboardShortcut(.cancelAction)
                            .accessibilityLabel("Back to parent task")
                    }
                    Spacer()
                    Button { showingEditor = true } label: { Image(systemName: "pencil") }
                        .appGlassButton(size: .medium, shape: .circle)
                        .keyboardShortcut("e", modifiers: .command)
                        .help("Edit Task")
                        .accessibilityLabel("Edit Task")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            Divider()
            detailContent
        }
    }

    private var detailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                titleBlock
                metadataGrid
                descriptionSection
                if !task.tags.isEmpty { tagsSection }
                subtasksSection
            }
            .padding(24)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(task.title)
                .font(AppTypography.boardTitle)
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Label(project.name, systemImage: AppSymbols.project)
                    .font(AppTypography.contextTitle)
                    .foregroundStyle(.secondary)

                if let parent = task.parentTask {
                    Label("Subtask of \(parent.title)", systemImage: "arrow.turn.up.left")
                        .font(AppTypography.supporting)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .taskDetailCardSurface()
        }
    }

    private var metadataGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 145), spacing: 12)],
            alignment: .leading,
            spacing: 12
        ) {
            TaskMetadataCard(
                label: "Status",
                value: appearance.title(for: task.status),
                symbol: task.status.symbol
            )
            TaskMetadataCard(
                label: "Priority",
                value: task.priority.title,
                symbol: prioritySymbol
            )
            TaskMetadataCard(
                label: "Due date",
                value: task.dueDate?.formatted(date: .abbreviated, time: .omitted) ?? "No due date",
                symbol: "calendar"
            )
        }
    }

    private var descriptionSection: some View {
        TaskDetailSection(title: "Description") {
            MarkdownDescriptionPreview(markdown: task.details)
        }
    }

    private var tagsSection: some View {
        TaskDetailSection(title: "Tags") {
            TagFlowLayout {
                ForEach(TagRules.normalized(task.tags), id: \.self) { tag in
                    EditableTagChip(name: tag, color: (AppProfile.current(in: profiles)?.color(forTag: tag) ?? appearance.accent).color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var subtasksSection: some View {
        let subtasks = task.subtaskList.sorted { $0.createdAt < $1.createdAt }
        let completed = subtasks.filter { $0.status == .done }.count
        return TaskDetailSection(title: "Subtasks \(completed)/\(subtasks.count)") {
            if subtasks.isEmpty {
                Text("No subtasks")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(subtasks.enumerated()), id: \.element.id) { index, subtask in
                        HStack(spacing: 12) {
                            Button { toggleCompletion(subtask) } label: {
                                Image(systemName: subtask.status == .done ? "checkmark.circle.fill" : "circle")
                                    .font(AppTypography.sectionTitle)
                                    .foregroundStyle(subtask.status == .done ? Color.accentColor : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(subtask.status == .done ? "Mark \(subtask.title) incomplete" : "Mark \(subtask.title) complete")

                            Button { selectedSubtask = subtask } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(subtask.title)
                                            .font(AppTypography.itemTitle)
                                            .foregroundStyle(.primary)
                                            .strikethrough(subtask.status == .done)
                                        if !subtask.details.isEmpty {
                                            Text(subtask.details)
                                                .font(AppTypography.supporting)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                        Text("\(appearance.title(for: subtask.status)) · \(subtask.priority.title)")
                                            .font(AppTypography.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(AppTypography.smallIcon)
                                        .foregroundStyle(.tertiary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open subtask \(subtask.title)")
                        }
                        .padding(.vertical, 12)

                        if index < subtasks.count - 1 { Divider() }
                    }
                }
            }
        }
    }

    private var prioritySymbol: String {
        switch task.priority {
        case .low: "arrow.down"
        case .normal: "minus"
        case .high: "arrow.up"
        case .urgent: "exclamationmark"
        }
    }

    private func finishEditing() {
        if taskWasDeleted { close() }
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    private func toggleCompletion(_ subtask: BoardTask) {
        let previousStatus = subtask.status
        let previousUpdatedAt = subtask.updatedAt
        subtask.status = previousStatus == .done ? .backlog : .done
        subtask.updatedAt = Date()
        do {
            try StoreWriter.save(context)
        } catch {
            subtask.status = previousStatus
            subtask.updatedAt = previousUpdatedAt
            self.error = error.localizedDescription
        }
    }
}

private struct TaskMetadataCard: View {
    let label: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(.white)
                .textCase(.uppercase)
            Label(value, systemImage: symbol)
                .font(AppTypography.itemTitle)
                .lineLimit(2)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .taskDetailCardSurface()
    }
}

private struct TaskDetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AppTypography.sectionTitle)
                .foregroundStyle(.white)

            content()
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .taskDetailCardSurface()
        }
    }
}

private extension View {
    func taskDetailCardSurface() -> some View {
        appCardSurface()
    }
}
