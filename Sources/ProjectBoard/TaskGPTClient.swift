import Foundation
import Observation

struct TaskGPTModel: Decodable, Identifiable {
    let slug: String
    let display_name: String
    let visibility: String?
    var id: String { slug }
}

/// A snapshot of the selected task's hierarchy, ordered exactly like its detail view.
struct TaskGPTContent {
    let title: String
    let description: String
    let status: String
    var subtasks: [TaskGPTContent] = []

    var prompt: String {
        guard !subtasks.isEmpty else {
            return description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Task: \(title)\nStatus: \(status)" : description
        }
        var lines = ["Task: \(title)", "", "Description:", description.isEmpty ? "(No description)" : description,
                     "", "Subtasks (top-to-bottom display order; preserve this order when addressing them):"]
        for (index, child) in subtasks.enumerated() {
            lines += child.numberedLines(number: "\(index + 1)", depth: 0)
        }
        return lines.joined(separator: "\n")
    }

    private func numberedLines(number: String, depth: Int) -> [String] {
        let indent = String(repeating: "    ", count: depth)
        var lines = ["\(indent)\(number). \(title.replacingOccurrences(of: "\n", with: " "))", "\(indent)   Status: \(status)"]
        if !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("\(indent)   Description:")
            lines += description.components(separatedBy: "\n").map { "\(indent)   \($0)" }
        }
        for (index, child) in subtasks.enumerated() {
            lines += child.numberedLines(number: "\(number).\(index + 1)", depth: depth + 1)
        }
        lines.append("")
        return lines
    }
}

/// Descriptions leave the device only after the user taps the task GPT button.
enum TaskGPTClient {
    static func account() throws -> ChatGPTAccount {
        guard let data = try ChatGPTKeychain.read("connections"),
              let account = try JSONDecoder().decode(ChatGPTSavedConnections.self, from: data).account else {
            throw ChatGPTConnectionError.message("Connect ChatGPT in Settings → Accounts first.")
        }
        guard account.allowsPlanUsage else {
            throw ChatGPTConnectionError.message("Enable ChatGPT plan usage and reconnect in Settings → Accounts.")
        }
        guard account.expiresAt.timeIntervalSinceNow > 30 else {
            throw ChatGPTConnectionError.message("Your ChatGPT session has expired. Reconnect in Settings → Accounts, then try again.")
        }
        return account
    }

    static func models() async throws -> [TaskGPTModel] {
        let account = try account()
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(account.accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        struct Catalog: Decodable { let models: [TaskGPTModel] }
        let models = try JSONDecoder().decode(Catalog.self, from: data).models.filter { $0.visibility == "list" }
        guard !models.isEmpty else { throw ChatGPTConnectionError.message("No models are available for this ChatGPT account.") }
        return models
    }

    static func request(description: String, model: String, token: String) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "input": [["role": "user", "content": description]],
            "store": false,
            "stream": true
        ])
        return request
    }

    static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw ChatGPTConnectionError.message("ChatGPT returned an invalid response.") }
        switch http.statusCode {
        case 200..<300: return
        case 401: throw ChatGPTConnectionError.message("Reconnect ChatGPT in Settings → Accounts, then try again.")
        case 403: throw ChatGPTConnectionError.message("This ChatGPT account cannot use the selected model. Check plan usage in Settings or choose another model.")
        case 429: throw ChatGPTConnectionError.message("Your ChatGPT usage limit was reached. Please try again later.")
        default: throw ChatGPTConnectionError.message("ChatGPT couldn’t complete the request (\(http.statusCode)). Please try again.")
        }
    }

    @MainActor static func send(description: String, model: String, onText: (String) -> Void) async throws {
        let account = try account()
        let request = try request(description: description, model: model, token: account.accessToken)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        try validate(response)
        var stream = TaskGPTStream()
        var dataLines: [String] = []
        for try await line in bytes.lines {
            try Task.checkCancellation()
            if line.isEmpty {
                if !dataLines.isEmpty {
                    try stream.consume(dataLines.joined(separator: "\n"))
                    onText(stream.text)
                    dataLines.removeAll(keepingCapacity: true)
                    if stream.completed { break }
                }
            } else if line.hasPrefix("data:") {
                dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
                // AsyncBytes.lines may omit empty lines. OpenAI emits a complete JSON
                // object per data line; also allow objects split across data lines.
                let payload = dataLines.joined(separator: "\n")
                if payload == "[DONE]" || (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) != nil {
                    try stream.consume(payload)
                    onText(stream.text)
                    dataLines.removeAll(keepingCapacity: true)
                    if stream.completed { break }
                }
            }
        }
        if !dataLines.isEmpty { try stream.consume(dataLines.joined(separator: "\n")); onText(stream.text) }
        try stream.finish()
    }
}

/// Partial output is never treated as successful until the terminal event arrives.
struct TaskGPTStream {
    private(set) var text = ""
    private(set) var completed = false
    mutating func consume(_ data: String) throws {
        guard data != "[DONE]" else { return }
        guard let bytes = data.data(using: .utf8),
              let event = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let type = event["type"] as? String else {
            throw ChatGPTConnectionError.message("ChatGPT returned an unreadable response.")
        }
        switch type {
        case "response.output_text.delta", "response.refusal.delta":
            text += event["delta"] as? String ?? ""
        case "response.completed": completed = true
        case "response.failed", "response.incomplete", "error":
            let response = event["response"] as? [String: Any]
            let error = (response?["error"] as? [String: Any]) ?? (event["error"] as? [String: Any]) ?? event
            let code = error["code"] as? String ?? ""
            if code == "subscription_sharing_usage_limit_exceeded" || code == "subscription_sharing_usage_unavailable" {
                throw ChatGPTConnectionError.message("ChatGPT plan usage is currently unavailable or its limit was reached. Try again later.")
            }
            throw ChatGPTConnectionError.message("ChatGPT didn’t finish this response. Any text shown is incomplete. Please try again.")
        default: break
        }
    }
    func finish() throws {
        guard completed else { throw ChatGPTConnectionError.message("The connection ended before ChatGPT finished. Any text shown is incomplete.") }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChatGPTConnectionError.message("ChatGPT finished without a text response.")
        }
    }
}


/// Value snapshots: a running request never retains or mutates SwiftData tasks.
struct TaskGPTWorkItem: Identifiable, Codable {
    let id: UUID
    let title: String
    let prompt: String
    var state: TaskGPTWorkState = .queued
    var output = ""
    var error: String?
    var accepted = false
}

enum TaskGPTWorkState: String, Codable {
    case queued = "Queued"
    case running = "Running"
    case completed = "Response ready"
    case failed = "Failed"
    case stopped = "Stopped"
}

struct TaskGPTRunState: Identifiable, Codable {
    let id: UUID
    let title: String
    let model: String
    var items: [TaskGPTWorkItem]
    var isRunning = false
    var completedCount: Int { items.filter { $0.state == .completed }.count }
    var hasFailure: Bool { items.contains { $0.state == .failed || $0.state == .stopped } }
    var progress: Double { items.isEmpty ? 0 : Double(completedCount) / Double(items.count) }
    var status: String {
        if let index = items.firstIndex(where: { $0.state == .running }) {
            return items.count == 1 ? "GPT is responding…" : "GPT: subtask \(index + 1) of \(items.count)"
        }
        if isRunning { return "Connecting to GPT…" }
        if hasFailure { return "GPT paused · \(completedCount)/\(items.count) responses ready" }
        return "GPT responses ready · \(completedCount)/\(items.count)"
    }
    mutating func prepareRetry() {
        for index in items.indices where items[index].state != .completed {
            items[index].state = .queued
            items[index].error = nil
            items[index].output = ""
        }
    }
}

@MainActor @Observable
final class TaskGPTRuns {
    static let shared = TaskGPTRuns(historyURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Tierin/ChatGPT/history.json"))
    @ObservationIgnored private let historyURL: URL?
    @ObservationIgnored private var persistenceTask: Task<Void, Never>?
    @ObservationIgnored private var historyLoadFailed = false
    private(set) var persistenceError: String?
    private(set) var historySizeBytes: Int64 = 0
    var hasActiveRuns: Bool { runs.values.contains { $0.isRunning } }
    @ObservationIgnored private let validateModel: (String) async throws -> Void
    @ObservationIgnored private let send: (String, String, (String) -> Void) async throws -> Void

    init(
        historyURL: URL? = nil,
        validateModel: @escaping (String) async throws -> Void = { model in
            let models = try await TaskGPTClient.models()
            guard models.contains(where: { $0.slug == model }) else {
                throw ChatGPTConnectionError.message("The selected model is unavailable. Choose another in Settings → Accounts → ChatGPT, then clear this run and tap GPT again.")
            }
        },
        send: @escaping (String, String, (String) -> Void) async throws -> Void = { prompt, model, onText in
            try await TaskGPTClient.send(description: prompt, model: model, onText: onText)
        }
    ) {
        self.historyURL = historyURL
        self.validateModel = validateModel
        self.send = send
        refreshHistorySize()
        if let historyURL {
            do {
                runs = try TaskGPTHistory.load(from: historyURL)
                flushHistory()
            } catch {
                historyLoadFailed = true
                persistenceError = "Couldn’t read saved GPT history. The existing file has been preserved."
            }
        }
    }

    private(set) var runs: [UUID: TaskGPTRunState] = [:] {
        didSet { schedulePersistence() }
    }

    private func schedulePersistence() {
        guard historyURL != nil, !historyLoadFailed, persistenceTask == nil else { return }
        persistenceTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            self?.flushHistory()
        }
    }

    func flushHistory() {
        persistenceTask?.cancel()
        persistenceTask = nil
        guard let historyURL, !historyLoadFailed else { return }
        do {
            try TaskGPTHistory.save(runs, to: historyURL)
            refreshHistorySize()
            persistenceError = nil
        } catch {
            persistenceError = "GPT history couldn’t be saved on this device. Keep Tierin open and check available storage."
            notice = TaskGPTNotice(runID: UUID(), phase: .storageFailure)
        }
    }
    private func refreshHistorySize() {
        guard let historyURL else { return }
        historySizeBytes = ((try? FileManager.default.attributesOfItem(atPath: historyURL.path)[.size]) as? NSNumber)?.int64Value ?? 0
    }

    func clearHistory() throws {
        guard !hasActiveRuns else {
            throw ChatGPTConnectionError.message("Stop running GPT requests before clearing history.")
        }
        // Delete successfully before discarding the in-memory review state.
        if let historyURL, FileManager.default.fileExists(atPath: historyURL.path) {
            try FileManager.default.removeItem(at: historyURL)
        }
        persistenceTask?.cancel()
        persistenceTask = nil
        historyLoadFailed = false
        runs.removeAll()
        flushHistory()
        refreshHistorySize()
        persistenceError = nil
        notice = nil
    }

    private(set) var notice: TaskGPTNotice?

    func announce(_ id: UUID) {
        guard let run = runs[id] else { return }
        let phase: TaskGPTNotice.Phase = run.hasFailure ? .failed
            : run.items.contains(where: { !$0.output.isEmpty }) ? .sent : .connecting
        notice = TaskGPTNotice(runID: id, phase: phase)
    }

    func dismissNotice(_ id: UUID) {
        if notice?.id == id { notice = nil }
    }
    @ObservationIgnored private var workers: [UUID: Task<Void, Never>] = [:]

    func run(containing taskID: UUID) -> TaskGPTRunState? {
        if let direct = runs[taskID] { return direct }
        return runs.values.first { $0.items.contains { $0.id == taskID } }
    }

    @discardableResult
    func start(taskID: UUID, title: String, model: String, items: [TaskGPTWorkItem]) -> UUID {
        if let existing = run(containing: taskID) { return existing.id }
        let ids = Set(items.map(\.id)).union([taskID])
        if let existing = runs.values.first(where: { $0.isRunning && !ids.isDisjoint(with: Set($0.items.map(\.id)).union([$0.id])) }) {
            return existing.id
        }
        // A new parent run supersedes older, finished runs for its descendants.
        let superseded = runs.values.filter {
            !$0.isRunning && !ids.isDisjoint(with: Set($0.items.map(\.id)).union([$0.id]))
        }.map(\.id)
        for id in superseded { runs[id] = nil }
        runs[taskID] = TaskGPTRunState(id: taskID, title: title, model: model, items: items)
        resume(taskID)
        return taskID
    }

    func resume(_ id: UUID) {
        guard var run = runs[id], !run.isRunning else { return }
        run.prepareRetry()
        run.isRunning = true
        runs[id] = run
        flushHistory()
        notice = TaskGPTNotice(runID: id, phase: .connecting)
        workers[id] = Task { await execute(id) }
    }

    func accept(runID: UUID, itemID: UUID, save: () throws -> Void) throws {
        guard let index = runs[runID]?.items.firstIndex(where: { $0.id == itemID }),
              let item = runs[runID]?.items[index], item.state == .completed, !item.accepted else { return }
        try save()
        runs[runID]?.items[index].accepted = true
        flushHistory()
    }

    func stop(_ id: UUID) { workers[id]?.cancel() }

    func restart(_ id: UUID) {
        guard runs[id]?.isRunning == false else { return }
        runs[id] = nil
        flushHistory()
    }

    private func execute(_ id: UUID) async {
        defer {
            runs[id]?.isRunning = false
            workers[id] = nil
            flushHistory()
        }
        guard let snapshot = runs[id] else { return }
        var activeIndex = snapshot.items.firstIndex { $0.state != .completed } ?? 0
        do {
            guard !snapshot.model.isEmpty else {
                throw ChatGPTConnectionError.message("Choose a model in Settings → Accounts → ChatGPT, then clear this run and tap GPT again.")
            }
            try await validateModel(snapshot.model)
            for index in snapshot.items.indices where snapshot.items[index].state != .completed {
                activeIndex = index
                try Task.checkCancellation()
                runs[id]?.items[index].state = .running
                try await send(snapshot.items[index].prompt, snapshot.model) { text in
                    self.runs[id]?.items[index].output = text
                    if !text.isEmpty, self.notice?.runID == id, self.notice?.phase == .connecting {
                        self.notice = TaskGPTNotice(runID: id, phase: .sent)
                    }
                }
                try Task.checkCancellation()
                runs[id]?.items[index].state = .completed
            }
        } catch {
            guard runs[id]?.items.indices.contains(activeIndex) == true else { return }
            notice = TaskGPTNotice(runID: id, phase: Task.isCancelled ? .stopped : .failed)
            runs[id]?.items[activeIndex].state = Task.isCancelled ? .stopped : .failed
            runs[id]?.items[activeIndex].error = Task.isCancelled
                ? "Stopped. Any partial response is incomplete."
                : (error as? ChatGPTConnectionError)?.localizedDescription ?? "Couldn’t reach ChatGPT. Try again."
        }
    }
}


struct TaskGPTNotice: Identifiable {
    enum Phase { case connecting, sent, failed, stopped, storageFailure }
    let id = UUID()
    let runID: UUID
    let phase: Phase
    var message: String {
        switch phase {
        case .connecting: "Connecting…"
        case .sent: "Sent to ChatGPT"
        case .failed: "GPT failed · Open task for details"
        case .stopped: "GPT stopped"
        case .storageFailure: "GPT history couldn’t be saved"
        }
    }
}

extension Notification.Name {
    static let tierinGPTDidStart = Notification.Name("TierinGPTDidStart")
}

/// Local history contains task snapshots and responses, never credentials.
enum TaskGPTHistory {
    private struct Archive: Codable {
        var version = 1
        let runs: [TaskGPTRunState]
    }
    static func save(_ runs: [UUID: TaskGPTRunState], to url: URL) throws {
        if runs.isEmpty {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            return
        }
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let archive = Archive(runs: runs.values.sorted { $0.id.uuidString < $1.id.uuidString })
        let data = try JSONEncoder().encode(archive)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func load(from url: URL) throws -> [UUID: TaskGPTRunState] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: url))
        guard archive.version == 1 else {
            throw ChatGPTConnectionError.message("Unsupported GPT history version")
        }
        var result: [UUID: TaskGPTRunState] = [:]
        for var run in archive.runs {
            if run.isRunning || run.items.contains(where: { $0.state == .running }) {
                run.isRunning = false
                for index in run.items.indices where run.items[index].state == .running || run.items[index].state == .queued {
                    run.items[index].state = .stopped
                    run.items[index].error = "Interrupted when Tierin closed. Review partial output or retry unfinished work."
                }
            }
            result[run.id] = run
        }
        return result
    }
}
