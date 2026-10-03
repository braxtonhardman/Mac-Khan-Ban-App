import XCTest
import SwiftData
@testable import BoardCore

final class PersistenceTests: XCTestCase {
    @MainActor func testSharedWorkspaceSaveCreatesAndEditsWithoutReplacingRelationships() throws {
        let schema = Schema([Project.self, BoardTask.self, ProjectArea.self, AppProfile.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        ])
        let context = ModelContext(container)
        let area = try StoreWriter.saveItem(nil, name: " Work ", in: context,
                                            create: { ProjectArea(name: "") })
        let project = try StoreWriter.saveItem(nil, name: " App ", in: context,
                                               create: { Project(name: "") }) {
            $0.area = area
            $0.notes = "Keep these notes"
        }
        let task = BoardTask(title: "Keep this task", project: project)
        context.insert(task)
        try StoreWriter.save(context)
        let projectID = project.id
        let areaID = area.id
        XCTAssertEqual(area.name, "Work")
        XCTAssertEqual(project.name, "App")
        _ = try StoreWriter.saveItem(area, name: " Personal ", in: context,
                                    create: { XCTFail("Editing must reuse the Area"); return ProjectArea(name: "") })
        _ = try StoreWriter.saveItem(project, name: " Tracker ", in: context,
                                    create: { XCTFail("Editing must reuse the Project"); return Project(name: "") })
        XCTAssertEqual(project.id, projectID)
        XCTAssertEqual(project.area?.id, areaID)
        XCTAssertEqual(project.area?.name, "Personal")
        XCTAssertEqual(project.name, "Tracker")
        XCTAssertEqual(project.notes, "Keep these notes")
        XCTAssertEqual(project.taskList.map(\.id), [task.id])
        XCTAssertThrowsError(try StoreWriter.saveItem(project, name: " ", in: context,
                                                     create: { Project(name: "") }))
        XCTAssertEqual(project.name, "Tracker")
        XCTAssertThrowsError(try StoreWriter.saveItem(nil, name: " ", in: context,
                                                     create: { ProjectArea(name: "") }))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProjectArea>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Project>()), 1)
    }

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
            try LegacyChecklistMigrator.run(in: context)
            let project = try XCTUnwrap(context.fetch(FetchDescriptor<Project>()).first)
            XCTAssertEqual(project.id, projectID)
            XCTAssertNil(project.area)
            let parent = try XCTUnwrap(project.topLevelTasks.first)
            XCTAssertEqual(parent.title, "Existing task")
            XCTAssertTrue(parent.checklist.isEmpty)
            XCTAssertEqual(parent.subtaskList.first?.title, "Keep me")
            XCTAssertEqual(parent.subtaskList.first?.status, .done)
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
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BoardTask>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProjectArea>()), 0)
    }

    @MainActor func testSubtasksPersistAsChildTasksWithoutJoiningBoardProgress() throws {
        let schema = Schema([Project.self, BoardTask.self, ProjectArea.self, AppProfile.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        ])
        let context = ModelContext(container)
        let project = Project(name: "Hierarchy")
        let parent = BoardTask(title: "Parent", status: .backlog, project: project)
        let child = BoardTask(title: "Child", status: .done, project: project)
        child.parentTask = parent
        context.insert(project)
        context.insert(parent)
        context.insert(child)
        try StoreWriter.save(context)

        XCTAssertEqual(project.topLevelTasks.map(\.id), [parent.id])
        XCTAssertEqual(parent.subtaskList.map(\.id), [child.id])
        XCTAssertEqual(child.parentTask?.id, parent.id)
        XCTAssertEqual(project.progress, 0, "Completed subtasks should not silently complete their parent task.")

        context.delete(parent)
        try StoreWriter.save(context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<BoardTask>()).isEmpty)
    }

    @MainActor func testSubtaskListCollapsesOfflineMigrationDuplicates() throws {
        let schema = Schema([Project.self, BoardTask.self, ProjectArea.self, AppProfile.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        ])
        let context = ModelContext(container)
        let project = Project(name: "Synced")
        let parent = BoardTask(title: "Parent", project: project)
        let sharedID = UUID()
        let older = BoardTask(title: "Older", project: project)
        older.id = sharedID
        older.updatedAt = Date(timeIntervalSince1970: 100)
        older.parentTask = parent
        let newer = BoardTask(title: "Newer", project: project)
        newer.id = sharedID
        newer.updatedAt = Date(timeIntervalSince1970: 200)
        newer.parentTask = parent
        context.insert(project)
        context.insert(parent)
        context.insert(older)
        context.insert(newer)
        try StoreWriter.save(context)

        XCTAssertEqual(parent.subtaskList.count, 1)
        XCTAssertEqual(parent.subtaskList.first?.title, "Newer")
    }

    @MainActor func testSavingDraftParentPersistsItsDraftSubtaskGraph() throws {
        let schema = Schema([Project.self, BoardTask.self, ProjectArea.self, AppProfile.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        ])
        let context = ModelContext(container)
        let project = Project(name: "Drafts")
        context.insert(project)
        try StoreWriter.save(context)

        let parent = BoardTask(title: "Unsaved parent")
        let child = BoardTask(title: "Unsaved child")
        child.parentTask = parent
        parent.subtasks = [child]
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BoardTask>()), 0)

        parent.project = project
        child.project = project
        if parent.modelContext == nil { context.insert(parent) }
        try StoreWriter.save(context)

        let tasks = try context.fetch(FetchDescriptor<BoardTask>())
        XCTAssertEqual(tasks.count, 2)
        XCTAssertEqual(tasks.first(where: { $0.parentTask == nil })?.subtaskList.first?.title, "Unsaved child")
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
