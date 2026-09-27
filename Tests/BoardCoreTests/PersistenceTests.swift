import XCTest
import SwiftData
@testable import BoardCore

final class PersistenceTests: XCTestCase {
    @MainActor func testDiskRoundTripAndCascadeDelete() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.store")
        func openStore() throws -> ModelContainer {
            let schema = Schema([Project.self, BoardTask.self])
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        }
        let projectID: UUID
        do {
            let container = try openStore()
            let context = ModelContext(container)
            let project = Project(name: "Test project", notes: "Notes")
            projectID = project.id
            context.insert(project)
            let task = BoardTask(title: "Ship", project: project)
            context.insert(task)
            task.status = .done
            task.priority = .urgent
            task.details = "Release notes"
            task.tags = ["v1"]
            task.dueDate = Date(timeIntervalSince1970: 1800000000)
            task.checklist = [ChecklistItem(title: "Build", isComplete: true)]
            try StoreWriter.save(context)
        }
        let container = try openStore()
        let context = ModelContext(container)
        let project = try XCTUnwrap(context.fetch(FetchDescriptor<Project>()).first)
        XCTAssertEqual(project.id, projectID)
        XCTAssertEqual(project.progress, 1)
        let task = try XCTUnwrap(project.tasks.first)
        XCTAssertEqual(task.status, .done)
        XCTAssertEqual(task.priority, .urgent)
        XCTAssertEqual(task.details, "Release notes")
        XCTAssertEqual(task.tags, ["v1"])
        XCTAssertEqual(task.dueDate, Date(timeIntervalSince1970: 1800000000))
        XCTAssertEqual(task.checklist.first?.isComplete, true)
        task.status = .blocked
        try StoreWriter.save(context)
        XCTAssertEqual(project.progress, 0)
        context.delete(project)
        try StoreWriter.save(context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<BoardTask>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Project>()).isEmpty)
    }
}
