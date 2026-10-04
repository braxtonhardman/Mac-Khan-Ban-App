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
                MacInWindowModal {
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
                MacInWindowModal {
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
                Text("Task Details").font(AppTypography.pageTitle)
                HStack {
                    Button(action: close) { Image(systemName: "xmark") }
                        .appGlassButton(size: .large, shape: .circle)
                        .keyboardShortcut(.cancelAction)
                        .accessibilityLabel("Close")
                    Spacer()
                    Button { showingEditor = true } label: { Image(systemName: "pencil") }
                        .appGlassButton(size: .large, shape: .circle)
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
        Form {
            titleBlock
            Section { metadataGrid.padding(.vertical, 4) }
            descriptionSection
            if !task.tags.isEmpty { tagsSection }
            subtasksSection
        }
        .formStyle(.grouped)
    }

    private var titleBlock: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label(project.name, systemImage: "rectangle.3.group")
                    .font(AppTypography.contextTitle)
                    .foregroundStyle(.secondary)

                if let parent = task.parentTask {
                    Label("Subtask of \(parent.title)", systemImage: "arrow.turn.up.left")
                        .font(AppTypography.supporting)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        } header: {
            Text(task.title)
                .font(AppTypography.boardTitle)
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .textCase(nil)
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
            Text(task.details.isEmpty ? "No description" : task.details)
                .foregroundStyle(task.details.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var tagsSection: some View {
        TaskDetailSection(title: "Tags") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160), alignment: .leading)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(task.tags, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(AppTypography.supporting)
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.1), in: Capsule())
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
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .taskDetailCardSurface()
    }
}

private struct TaskDetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Section {
            content()
                .padding(.vertical, 6)
        } header: {
            Text(title)
                .font(AppTypography.sectionTitle)
                .foregroundStyle(.white)
                .textCase(nil)
        }
    }
}

private struct TaskDetailCardSurface: ViewModifier {
    private var background: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    private var surfaceTint: Color {
        #if os(iOS)
        Color.clear
        #else
        Color.primary.opacity(0.04)
        #endif
    }

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(background)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(surfaceTint)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            }
    }
}

private extension View {
    func taskDetailCardSurface() -> some View {
        modifier(TaskDetailCardSurface())
    }
}
