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
    @State private var showingChatGPT = false
    @State private var chatGPTRunID = UUID()
    @State private var focusedGPTItemID: UUID?
    @State private var gptRuns = TaskGPTRuns.shared
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
        .sheet(isPresented: $showingChatGPT) {
            TaskChatGPTView(runID: chatGPTRunID, focusedItemID: focusedGPTItemID, onAccept: acceptGPTResponse, onClose: { showingChatGPT = false })
        }
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
            if showingChatGPT {
                MacInWindowModal(onDismiss: { showingChatGPT = false }) {
                    TaskChatGPTView(runID: chatGPTRunID, focusedItemID: focusedGPTItemID, onAccept: acceptGPTResponse, onClose: { showingChatGPT = false })
                }
            } else if showingEditor {
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
            HStack(spacing: 12) {
                if task.parentTask == nil {
                    AppGlassActionButton(symbol: .cancel, accessibilityLabel: "Close", action: close)
                        .keyboardShortcut(.cancelAction)
                } else {
                    Button(action: close) { Image(systemName: "chevron.left") }
                        .appGlassButton(size: .medium, shape: .circle)
                        .keyboardShortcut(.cancelAction)
                        .accessibilityLabel("Back to parent task")
                }
                Text(task.parentTask == nil ? "Task Details" : "Subtask Details")
                    .font(AppTypography.pageTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                HStack(spacing: 10) {
                    chatGPTButton
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
                if task.parentTask == nil {
                    metadataGrid
                }
                descriptionSection
                if let run = gptRuns.run(containing: task.id) {
                    TaskDetailSection(title: "GPT activity") {
                        VStack(alignment: .leading, spacing: 12) {
                            Button("View GPT response ↗") {
                                focusedGPTItemID = run.items.contains { $0.id == task.id } ? task.id : nil
                                chatGPTRunID = run.id
                                showingChatGPT = true
                            }.appGlassButton()
                        }
                    }
                }
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

    private var chatGPTButton: some View {
        Button {
            chatGPTRunID = gptRuns.start(taskID: task.id, title: task.title,
                model: AppProfile.current(in: profiles)?.chatGPTModel ?? "", items: gptWorkItems())
            gptRuns.announce(chatGPTRunID)
            NotificationCenter.default.post(name: .tierinGPTDidStart, object: nil)
            close()
        } label: {
            Image("ChatGPTLogo")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: AppGlassButtonSize.medium.iconDimension,
                       height: AppGlassButtonSize.medium.iconDimension)
        }
        .appGlassButton(size: .medium, shape: .circle)
        .accessibilityLabel("Send task to ChatGPT")
        .help("Send task to ChatGPT")
    }

    private func gptWorkItems() -> [TaskGPTWorkItem] {
        let context = gptContent(for: task).prompt
        var descendants: [BoardTask] = []
        var visited: Set<UUID> = [task.id]
        func collect(_ parent: BoardTask) {
            for child in parent.orderedSubtasks where visited.insert(child.id).inserted {
                descendants.append(child)
                collect(child)
            }
        }
        collect(task)
        guard !descendants.isEmpty else {
            return [TaskGPTWorkItem(id: task.id, title: task.title, prompt: context)]
        }
        return descendants.enumerated().map { index, child in
            TaskGPTWorkItem(id: child.id, title: child.title,
                prompt: context + "\n\nAddress only subtask \(index + 1) in depth-first display order: \(child.title). Provide a response for this subtask; do not claim to have completed actions in Tierin.")
        }
    }

    private func gptContent(for task: BoardTask, ancestors: Set<UUID> = []) -> TaskGPTContent {
        let visited = ancestors.union([task.id])
        return TaskGPTContent(
            title: task.title,
            description: task.details,
            status: appearance.title(for: task.status),
            subtasks: task.orderedSubtasks.filter { !visited.contains($0.id) }.map {
                gptContent(for: $0, ancestors: visited)
            }
        )
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
        let subtasks = task.orderedSubtasks
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

                            VStack(alignment: .leading, spacing: 8) {
                            Button { selectedSubtask = subtask } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        subtaskTitle(subtask)
                                        if !subtask.details.isEmpty {
                                            Text(subtask.details)
                                                .font(AppTypography.supporting)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
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
                                HStack(spacing: 10) {
                                    subtaskGPTStatus(subtask)
                                    if let run = gptRuns.run(containing: subtask.id) {
                                        Button {
                                            chatGPTRunID = run.id
                                            focusedGPTItemID = subtask.id
                                            showingChatGPT = true
                                        } label: {
                                            Label("View GPT response", systemImage: "arrow.up.right")
                                                .font(AppTypography.caption).foregroundStyle(.tint)
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 12)

                        if index < subtasks.count - 1 { Divider() }
                    }
                }
            }
        }
    }

    private func subtaskTitle(_ subtask: BoardTask) -> some View {
        Text(subtask.title)
            .font(AppTypography.itemTitle)
            .foregroundStyle(.primary)
            .strikethrough(subtask.status == .done)
    }

    @ViewBuilder private func subtaskGPTStatus(_ subtask: BoardTask) -> some View {
        if subtask.status == .done {
            TagChip(name: "Finished", color: .green, compact: true)
                .accessibilityLabel("Subtask finished")
        } else if let run = gptRuns.run(containing: subtask.id),
           let item = run.items.first(where: { $0.id == subtask.id }) {
            GPTWorkStatus(state: item.state, accepted: item.accepted)
        } else {
            TagChip(name: "Not started", color: .secondary, compact: true)
                .accessibilityLabel("GPT: Not started")
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

    private func acceptGPTResponse(_ taskID: UUID) throws {
        try TaskGPTAcceptance.complete(taskID, in: context)
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
