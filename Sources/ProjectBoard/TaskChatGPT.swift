import SwiftUI
import SwiftData
import Observation

struct TaskChatGPTView: View {
    let runID: UUID
    var focusedItemID: UUID? = nil
    let onAccept: (UUID) throws -> Void
    let onClose: () -> Void
    @State private var acceptanceError: String?
    @State private var tracker = TaskGPTRuns.shared


    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onClose) { Image(systemName: "chevron.left") }
                    .appGlassButton(size: .medium, shape: .circle)
                    .accessibilityLabel("Back to task")
                Text("ChatGPT").font(AppTypography.pageTitle).frame(maxWidth: .infinity)
                Color.clear.frame(width: AppGlassButtonSize.medium.dimension, height: 1)
            }.padding(20)
            Divider()
            ScrollViewReader { proxy in
            ScrollView {
                if let run = tracker.runs[runID] {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(run.title).font(AppTypography.itemTitle)
                        if let error = tracker.persistenceError {
                            Text(error).font(AppTypography.supporting).foregroundStyle(.red)
                        }
                        TaskGPTRunProgress(run: run)
                        Text("Review each response, then choose Accept & Complete to mark that task done. Runs continue while Tierin is open; on iPhone, leaving the app may interrupt a request. Responses are saved on this device and remain available after restarting Tierin.")
                            .font(AppTypography.caption).foregroundStyle(.secondary)
                        HStack {
                            if run.isRunning {
                                Button("Stop") { tracker.stop(runID) }.appGlassButton()
                            } else if run.hasFailure {
                                Button("Retry unfinished") { tracker.resume(runID) }.appGlassButton()
                            }
                            if !run.isRunning {
                                Button("Clear run") { tracker.restart(runID); onClose() }.appGlassButton()
                            }
                        }
                        ForEach(run.items) { item in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(item.title).font(AppTypography.itemTitle)
                                GPTWorkStatus(state: item.state, accepted: item.accepted)
                                if let error = item.error {
                                    Text(error).font(AppTypography.supporting).foregroundStyle(.red)
                                }
                                if !item.output.isEmpty {
                                    Text(item.output).font(AppTypography.body).textSelection(.enabled)
                                }
                                if item.state == .completed {
                                    if item.accepted {
                                        Label("Accepted · Task completed", systemImage: "checkmark.circle.fill")
                                            .font(AppTypography.supporting).foregroundStyle(.green)
                                    } else {
                                        Button {
                                            do {
                                                try tracker.accept(runID: runID, itemID: item.id) {
                                                    try onAccept(item.id)
                                                }
                                            } catch { acceptanceError = error.localizedDescription }
                                        } label: {
                                            Label("Accept & Complete", systemImage: "checkmark")
                                        }
                                        .appGlassButton()
                                        .accessibilityLabel("Accept response and complete \(item.title)")
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16).appCardSurface()
                            .id(item.id)
                        }
                    }.padding(24)
                }
            }
            .onAppear {
                if let focusedItemID { proxy.scrollTo(focusedItemID, anchor: .top) }
            }
            }
        }
        .modifier(EditorSizing(width: 620, height: 700))
        .alert("Couldn’t accept response", isPresented: Binding(get: { acceptanceError != nil }, set: { if !$0 { acceptanceError = nil } })) {
            Button("OK") { acceptanceError = nil }
        } message: { Text(acceptanceError ?? "") }

    }
}

struct GPTWorkStatus: View {
    let state: TaskGPTWorkState
    var accepted = false
    private var title: String {
        accepted ? "Accepted" : state == .completed ? "Success · Ready for review" : state.rawValue
    }
    private var color: Color {
        switch state {
        case .completed: .green
        case .failed: .red
        case .running: .accentColor
        case .stopped: .orange
        case .queued: .secondary
        }
    }
    var body: some View {
        TagChip(name: title, color: color, compact: true)
            .accessibilityLabel("GPT: \(title)")
    }
}

struct TaskGPTRunProgress: View {
    let run: TaskGPTRunState
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if run.isRunning { ProgressView().controlSize(.small).accessibilityHidden(true) }
                Text(run.status).font(AppTypography.caption).foregroundStyle(.secondary)
            }
            if run.items.count > 1 || !run.isRunning {
                ProgressView(value: run.progress).progressViewStyle(.linear)
                    .accessibilityHidden(true)
            }
        }
    }
}

struct TaskGPTResponseLinks: View {
    let task: BoardTask
    let onOpen: (UUID, UUID?) -> Void
    @State private var tracker = TaskGPTRuns.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(relatedRuns) { run in
                Button {
                    onOpen(run.id, run.items.contains { $0.id == task.id } ? task.id : nil)
                } label: {
                    Label(relatedRuns.count == 1 ? "View GPT response" : "GPT: \(run.title)", systemImage: "arrow.up.right")
                        .font(AppTypography.caption)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
            }
        }
    }
    private var relatedRuns: [TaskGPTRunState] {
        var ids: Set<UUID> = []
        func collect(_ node: BoardTask) {
            guard ids.insert(node.id).inserted else { return }
            node.orderedSubtasks.forEach(collect)
        }
        collect(task)
        return tracker.runs.values.filter { run in
            ids.contains(run.id) || run.items.contains { ids.contains($0.id) }
        }.sorted { $0.id.uuidString < $1.id.uuidString }
    }

}

/// A shared workspace banner, outside task sheets and in-window modals.
struct TaskGPTBanner: View {
    @State private var tracker = TaskGPTRuns.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            if let notice = tracker.notice {
                HStack(spacing: 8) {
                    if notice.phase == .connecting {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: notice.phase == .sent ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundStyle(notice.phase == .sent ? Color.green : Color.orange)
                    }
                    Text(notice.message).font(AppTypography.supporting)
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                .padding(.horizontal, 16).padding(.top, 12)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .combine)
            }
        }
        .allowsHitTesting(false)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: tracker.notice?.id)
        .task(id: tracker.notice?.id) {
            guard let notice = tracker.notice, notice.phase != .connecting else { return }
            do { try await Task.sleep(for: .seconds(notice.phase == .sent ? 2 : 5)) } catch { return }
            tracker.dismissNotice(notice.id)
        }
    }
}

struct TaskGPTReviewRequest: Identifiable {
    let id: UUID
    let itemID: UUID?
}

@MainActor enum TaskGPTAcceptance {
    static func complete(_ taskID: UUID, in context: ModelContext) throws {
        let descriptor = FetchDescriptor<BoardTask>(predicate: #Predicate { $0.id == taskID })
        guard let target = try context.fetch(descriptor).first else {
            throw ChatGPTConnectionError.message("This task was deleted. Its response cannot be accepted.")
        }
        let previousStatus = target.status
        let previousUpdatedAt = target.updatedAt
        target.status = .done
        target.updatedAt = Date()
        do { try StoreWriter.save(context) }
        catch {
            target.status = previousStatus
            target.updatedAt = previousUpdatedAt
            throw error
        }
    }
}
