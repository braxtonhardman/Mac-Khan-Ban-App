import Foundation

@main struct TaskGPTTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { fatalError(message) }
    }
    static func rejects(_ message: String, _ action: () throws -> Void) {
        do { try action(); fatalError(message) } catch { }
    }
    @MainActor static func main() async throws {
        let request = try TaskGPTClient.request(description: "Line one\nA \"quoted\" task 🐳", model: "test-model", token: "fixture-token")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        expect(request.url?.absoluteString == "https://api.openai.com/v1/responses", "Uses the supported public endpoint")
        expect(body["store"] as? Bool == false && body["stream"] as? Bool == true, "Uses stateless streaming")
        let input = body["input"] as! [[String: String]]
        expect(input == [["role": "user", "content": "Line one\nA \"quoted\" task 🐳"]], "Sends only the exact selected description")
        expect(body.count == 4, "No unrelated task or profile data in request")
        let content = TaskGPTContent(title: "Parent", description: "Build a flow", status: "Planned", subtasks: [
            TaskGPTContent(title: "First", description: "Line A\nLine B", status: "Done", subtasks: [
                TaskGPTContent(title: "Nested", description: "Detail", status: "Planned")
            ]),
            TaskGPTContent(title: "Second", description: "", status: "Backlog")
        ])
        let prompt = content.prompt
        expect(prompt.contains("1. First\n   Status: Done\n   Description:\n   Line A\n   Line B"), "Preserves descriptions and completed subtasks")
        expect(prompt.contains("    1.1. Nested"), "Numbers nested subtasks hierarchically")
        expect(prompt.range(of: "1. First")!.lowerBound < prompt.range(of: "2. Second")!.lowerBound, "Preserves supplied top-to-bottom order")
        expect(TaskGPTContent(title: "Leaf", description: "Exact description", status: "Done").prompt == "Exact description", "No subtasks preserves the original prompt")
        expect(TaskGPTContent(title: "Parent", description: "", status: "Planned", subtasks: content.subtasks).prompt.contains("2. Second"), "Subtasks can be sent without a parent description")
        expect(TaskGPTContent(title: "Add Markdown support", description: "", status: "Backlog").prompt == "Task: Add Markdown support\nStatus: Backlog", "Title-only tasks provide meaningful context")
        expect(TaskGPTContent(title: "Add Markdown support", description: " \n ", status: "Backlog").prompt.contains("Add Markdown support"), "Whitespace-only descriptions fall back to the task title")
        let hierarchyRequest = try TaskGPTClient.request(description: prompt, model: "test-model", token: "fixture")
        let hierarchyBody = try JSONSerialization.jsonObject(with: hierarchyRequest.httpBody!) as! [String: Any]
        expect((hierarchyBody["input"] as! [[String: String]])[0]["content"] == prompt, "The full hierarchy reaches the request unchanged")
        var run = TaskGPTRunState(id: UUID(), title: "Test", model: "fixture", items: [
            TaskGPTWorkItem(id: UUID(), title: "First", prompt: "First", state: .completed, output: "Keep this response"),
            TaskGPTWorkItem(id: UUID(), title: "Second", prompt: "Second", state: .failed, output: "Partial", error: "Failed"),
            TaskGPTWorkItem(id: UUID(), title: "Third", prompt: "Third")
        ])
        expect(run.completedCount == 1 && run.progress == 1.0 / 3.0, "Only finished responses contribute to GPT progress")
        expect(run.hasFailure && run.status.contains("paused"), "Failures remain visible")
        run.prepareRetry()
        expect(run.items[0].output == "Keep this response" && run.items[0].state == .completed, "Retry retains successful responses")
        expect(run.items[1].state == .queued && run.items[1].output.isEmpty && run.items[1].error == nil, "Retry clears failed partial response")
        expect(run.items[2].state == .queued, "Unstarted subtasks stay queued")
        run.items[1].state = .running
        expect(run.status == "GPT: subtask 2 of 3", "Running status follows displayed order")
        expect(run.completedCount == 1, "Running work never counts as completed")
        var calls: [String] = []
        var failSecond = true
        let tracker = TaskGPTRuns(validateModel: { _ in }, send: { prompt, _, output in
            calls.append(prompt)
            if prompt == "Second" && failSecond {
                throw ChatGPTConnectionError.message("Fixture failure")
            }
            output("Response: " + prompt)
        })
        let runID = UUID()
        let workItems = ["First", "Second", "Third"].map { TaskGPTWorkItem(id: UUID(), title: $0, prompt: $0) }
        tracker.start(taskID: runID, title: "Parent", model: "fixture", items: workItems)
        expect(tracker.notice?.phase == .connecting, "Starting immediately shows Connecting")
        let duplicate = tracker.start(taskID: runID, title: "Parent", model: "fixture", items: workItems)
        expect(duplicate == runID, "Repeated clicks open the existing run")
        while tracker.runs[runID]?.isRunning == true { await Task.yield() }
        expect(tracker.notice?.phase == .failed, "Failed requests show an error banner")
        expect(calls == ["First", "Second"], "Sequential execution stops at first failure")
        expect(tracker.runs[runID]?.items[2].state == .queued, "Failure leaves later work queued")
        failSecond = false
        tracker.resume(runID)
        while tracker.runs[runID]?.isRunning == true { await Task.yield() }
        expect(calls == ["First", "Second", "Second", "Third"], "Retry never resends successful work")
        expect(tracker.notice?.phase == .sent, "Actual response text changes the banner to Sent")
        let oldNotice = tracker.notice!.id
        tracker.announce(runID)
        tracker.dismissNotice(oldNotice)
        expect(tracker.notice != nil, "An old timeout cannot dismiss a newer banner")
        tracker.dismissNotice(tracker.notice!.id)
        expect(tracker.notice == nil, "Current banner dismisses after its timeout")
        expect(tracker.runs[runID]?.completedCount == 3, "All responses finish after retry")
        expect(tracker.run(containing: workItems[0].id)?.id == runID, "Subtask opens its parent run")
        var saves = 0
        try tracker.accept(runID: runID, itemID: workItems[0].id) { saves += 1 }
        try tracker.accept(runID: runID, itemID: workItems[0].id) { saves += 1 }
        expect(saves == 1 && tracker.runs[runID]?.items[0].accepted == true, "Accept saves once and records review")
        do {
            try tracker.accept(runID: runID, itemID: workItems[1].id) { throw ChatGPTConnectionError.message("Save failed") }
            fatalError("Failed save must throw")
        } catch { }
        expect(tracker.runs[runID]?.items[1].accepted == false, "Failed save never marks a response accepted")
        let cancellable = TaskGPTRuns(validateModel: { _ in }, send: { _, _, _ in
            try await Task.sleep(for: .seconds(10))
        })
        cancellable.start(taskID: runID, title: "Cancel", model: "fixture", items: workItems)
        cancellable.stop(runID)
        while cancellable.runs[runID]?.isRunning == true { await Task.yield() }
        expect(cancellable.runs[runID]?.items[0].state == .stopped, "Explicit stop is visible and never completes work")
        let historyFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: historyFolder) }
        let historyURL = historyFolder.appendingPathComponent("history.json")
        let durable = TaskGPTRuns(historyURL: historyURL, validateModel: { _ in }, send: { prompt, _, output in
            output("Saved: " + prompt)
        })
        durable.start(taskID: runID, title: "Persistent parent", model: "fixture", items: workItems)
        while durable.runs[runID]?.isRunning == true { await Task.yield() }
        try durable.accept(runID: runID, itemID: workItems[0].id) { }
        expect(durable.historySizeBytes > 0, "Saved history reports its on-disk size")
        let attributes = try FileManager.default.attributesOfItem(atPath: historyURL.path)
        expect(durable.historySizeBytes == (attributes[.size] as! NSNumber).int64Value, "Storage count matches actual file bytes")
        let reopened = TaskGPTRuns(historyURL: historyURL, validateModel: { _ in fatalError("Must not automatically reconnect") }, send: { _, _, _ in fatalError("Must not automatically resend") })
        expect(reopened.run(containing: workItems[1].id)?.id == runID, "Subtask response links survive reopening")
        expect(reopened.runs[runID]?.items[0].accepted == true, "Acceptance survives reopening")
        expect(reopened.runs[runID]?.items[1].output == "Saved: Second", "Response text survives reopening")
        expect(reopened.runs[runID]?.items.map(\.prompt) == workItems.map(\.prompt), "Prompts and item order survive reopening")
        var interrupted = reopened.runs[runID]!
        interrupted.isRunning = true
        interrupted.items[1].state = .running
        interrupted.items[1].output = "Partial response"
        interrupted.items[2].state = .queued
        try TaskGPTHistory.save([runID: interrupted], to: historyURL)
        let recovered = TaskGPTRuns(historyURL: historyURL)
        expect(recovered.runs[runID]?.isRunning == false, "Interrupted runs never resume automatically")
        expect(recovered.runs[runID]?.items[0].state == .completed, "Recovery preserves successful output")
        expect(recovered.runs[runID]?.items[1].state == .stopped && recovered.runs[runID]?.items[2].state == .stopped, "Recovery marks unfinished work stopped")
        expect(recovered.runs[runID]?.items[1].output == "Partial response", "Recovery preserves partial output for review")
        recovered.restart(runID)
        expect(try TaskGPTHistory.load(from: historyURL).isEmpty, "Explicit clear persists")
        let corrupt = Data("invalid archive".utf8)
        try corrupt.write(to: historyURL)
        let unreadable = TaskGPTRuns(historyURL: historyURL)
        unreadable.flushHistory()
        expect(unreadable.persistenceError != nil, "Unreadable history is reported")
        expect(try Data(contentsOf: historyURL) == corrupt, "Unreadable history is never overwritten")
        try unreadable.clearHistory()
        expect(unreadable.historySizeBytes == 0 && unreadable.persistenceError == nil, "Clear recovers unreadable history and resets size")
        expect(!FileManager.default.fileExists(atPath: historyURL.path), "Clear deletes the archive")
        let clearing = TaskGPTRuns(historyURL: historyURL, validateModel: { _ in }, send: { _, _, output in output("Saved") })
        clearing.start(taskID: runID, title: "Clear test", model: "fixture", items: workItems)
        rejects("Active runs cannot be cleared") { try clearing.clearHistory() }
        while clearing.runs[runID]?.isRunning == true { await Task.yield() }
        try clearing.clearHistory()
        expect(clearing.runs.isEmpty && clearing.historySizeBytes == 0, "Clear removes response links and storage")
        expect(TaskGPTRuns(historyURL: historyURL).runs.isEmpty, "Cleared history stays empty after restart")
        var stream = TaskGPTStream()
        try stream.consume(#"{"type":"response.created"}"#)
        try stream.consume(#"{"type":"response.output_text.delta","delta":"Hello "}"#)
        try stream.consume(#"{"type":"response.output_text.delta","delta":"world"}"#)
        expect(stream.text == "Hello world", "Accumulates deltas")
        rejects("Partial text must not count as completion") { try stream.finish() }
        try stream.consume(#"{"type":"response.completed"}"#)
        try stream.finish()
        var limited = TaskGPTStream()
        try limited.consume(#"{"type":"response.output_text.delta","delta":"Partial"}"#)
        rejects("Late usage errors must be surfaced") {
            try limited.consume(#"{"type":"response.failed","response":{"error":{"code":"subscription_sharing_usage_limit_exceeded"}}}"#)
        }
        expect(!limited.completed, "Failed output stays incomplete")
        for event in [#"{"type":"response.incomplete"}"#, #"{"type":"error","code":"unknown"}"#, "not json"] {
            rejects("Failure event must throw") { var stream = TaskGPTStream(); try stream.consume(event) }
        }
        var empty = TaskGPTStream()
        try empty.consume(#"{"type":"response.completed"}"#)
        rejects("Empty completions must be surfaced") { try empty.finish() }
        let url = URL(string: "https://api.openai.com/v1/responses")!
        for status in [401, 403, 429, 500] {
            rejects("HTTP failure must throw") { try TaskGPTClient.validate(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!) }
        }
        print("Task GPT tests passed")
    }
}
