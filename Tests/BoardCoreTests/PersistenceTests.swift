import XCTest
import SwiftData
@testable import BoardCore

final class PersistenceTests: XCTestCase {
    @MainActor func testUpgradeAndAreaLifecyclePreserveProjectsAndTasks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("upgrade.store")
        let projectID: UUID
        do {
            let schema = Schema([LegacyModels.Project.self, LegacyModels.BoardTask.self])
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            let context = ModelContext(container)
            let project = LegacyModels.Project(name: "Existing project")
            projectID = project.id
            context.insert(project)
            let task = LegacyModels.BoardTask(title: "Existing task", status: .done, project: project)
            task.checklist = [ChecklistItem(title: "Keep me", isComplete: true)]
            context.insert(task)
            try context.save()
        }
        func openStore() throws -> ModelContainer {
            let schema = Schema([Project.self, BoardTask.self, ProjectArea.self])
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        }
        do {
            let container = try openStore()
            let context = ModelContext(container)
            let project = try XCTUnwrap(context.fetch(FetchDescriptor<Project>()).first)
            XCTAssertEqual(project.id, projectID)
            XCTAssertNil(project.area)
            XCTAssertEqual(project.tasks.first?.title, "Existing task")
            XCTAssertEqual(project.tasks.first?.checklist.first?.title, "Keep me")
            let area = ProjectArea(name: "Work")
            context.insert(area)
            project.area = area
            try StoreWriter.save(context)
        }
        do {
            let container = try openStore()
            let context = ModelContext(container)
            let project = try XCTUnwrap(context.fetch(FetchDescriptor<Project>()).first)
            let area = try XCTUnwrap(project.area)
            XCTAssertEqual(area.name, "Work")
            XCTAssertEqual(area.projects.map(\.id), [projectID])
            area.name = "Personal"
            try StoreWriter.save(context)
        }
        do {
            let container = try openStore()
            let context = ModelContext(container)
            let area = try XCTUnwrap(context.fetch(FetchDescriptor<ProjectArea>()).first)
            XCTAssertEqual(area.name, "Personal")
            context.delete(area)
            try StoreWriter.save(context)
        }
        let container = try openStore()
        let context = ModelContext(container)
        let project = try XCTUnwrap(context.fetch(FetchDescriptor<Project>()).first)
        XCTAssertEqual(project.id, projectID)
        XCTAssertNil(project.area)
        XCTAssertEqual(project.progress, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BoardTask>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProjectArea>()), 0)
    }

    @MainActor func testDiskRoundTripAndCascadeDelete() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.store")
        func openStore() throws -> ModelContainer {
            let schema = Schema([Project.self, BoardTask.self, ProjectArea.self])
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
