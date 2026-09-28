import XCTest
import SwiftData
@testable import BoardCore

final class PersistenceTests: XCTestCase {
    @MainActor func testProfilePersistsAndResolvesOfflineDuplicates() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("profile.store")
        func openStore() throws -> ModelContainer {
            let schema = Schema([Project.self, BoardTask.self, ProjectArea.self, AppProfile.self])
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        }
        do {
            let container = try openStore()
            let context = ModelContext(container)
            let older = AppProfile(stageNames: TaskStatus.allCases.map(\.title), accent: .blue)
            older.updatedAt = Date(timeIntervalSince1970: 100)
            let newer = AppProfile(stageNames: ["Ideas", "Next", "Active", "Waiting", "Shipped"], accent: .purple)
            newer.updatedAt = Date(timeIntervalSince1970: 200)
            newer.appearanceMode = AppearanceMode.dark.rawValue
            newer.tagNames = ["Work", "Personal"]
            context.insert(older)
            context.insert(newer)
            try StoreWriter.save(context)
        }
        let container = try openStore()
        let context = ModelContext(container)
        let profiles = try context.fetch(FetchDescriptor<AppProfile>())
        let current = try XCTUnwrap(AppProfile.current(in: profiles))
        XCTAssertEqual(current.appearance.title(for: .done), "Shipped")
        XCTAssertEqual(current.appearance.accent, .purple)
        XCTAssertEqual(current.appearance.mode, .dark)
        XCTAssertEqual(current.tagNames, ["Work", "Personal"])
        XCTAssertEqual(AppProfile.current(in: profiles.reversed())?.id, current.id)
    }

    @MainActor func testUpgradeFromAreasSchemaToCloudSchema() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("areas.store")
        do {
            let schema = Schema([LegacyAreaModels.Project.self, LegacyAreaModels.BoardTask.self, LegacyAreaModels.ProjectArea.self])
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            let area = LegacyAreaModels.ProjectArea(name: "Personal")
            let project = LegacyAreaModels.Project(name: "Preserve me")
            context.insert(area)
            context.insert(project)
            project.area = area
            let task = LegacyAreaModels.BoardTask(title: "Deadline", project: project)
            task.dueDate = Date(timeIntervalSince1970: 1800000000)
            context.insert(task)
            try context.save()
        }
        let schema = Schema([Project.self, BoardTask.self, ProjectArea.self, AppProfile.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        let context = ModelContext(container)
        let project = try XCTUnwrap(context.fetch(FetchDescriptor<Project>()).first)
        XCTAssertEqual(project.name, "Preserve me")
        XCTAssertEqual(project.area?.name, "Personal")
        XCTAssertEqual(project.taskList.first?.dueDate, Date(timeIntervalSince1970: 1800000000))
    }

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
            let schema = Schema([Project.self, BoardTask.self, ProjectArea.self, AppProfile.self])
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        }
        do {
            let container = try openStore()
            let context = ModelContext(container)
            let project = try XCTUnwrap(context.fetch(FetchDescriptor<Project>()).first)
            XCTAssertEqual(project.id, projectID)
            XCTAssertNil(project.area)
            XCTAssertEqual(project.taskList.first?.title, "Existing task")
            XCTAssertEqual(project.taskList.first?.checklist.first?.title, "Keep me")
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
            XCTAssertEqual(area.projectList.map(\.id), [projectID])
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
            let schema = Schema([Project.self, BoardTask.self, ProjectArea.self, AppProfile.self])
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
        let task = try XCTUnwrap(project.taskList.first)
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
