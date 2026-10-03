import Foundation
import SwiftData
#if SWIFT_PACKAGE
import BoardCore
#endif

@Model
final class ProjectArea {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    @Relationship(deleteRule: .nullify, inverse: \Project.area)
    var projects: [Project]? = []
    var projectList: [Project] { projects ?? [] }

    init(name: String) {
        id = UUID()
        self.name = name
        createdAt = Date()
    }
}

@Model
final class Project {
    var id: UUID = UUID()
    var name: String = ""
    var notes: String = ""
    var area: ProjectArea?
    var createdAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \BoardTask.project)
    var tasks: [BoardTask]? = []
    var taskList: [BoardTask] { tasks ?? [] }
    var topLevelTasks: [BoardTask] { taskList.filter { $0.parentTask == nil } }

    init(name: String, notes: String = "") {
        id = UUID()
        self.name = name
        self.notes = notes
        createdAt = Date()
    }
    var progress: Double { BoardRules.progress(statuses: topLevelTasks.map(\.status)) }
}

@Model
final class BoardTask {
    var id: UUID = UUID()
    var title: String = ""
    var details: String = ""
    var statusValue: String = "backlog"
    var priorityValue: Int = 1
    var dueDate: Date?
    var tags: [String] = []
    /// Retained temporarily so existing stores can convert V1 checklist rows into child tasks.
    var checklist: [ChecklistItem] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var project: Project?
    var parentTask: BoardTask?
    @Relationship(deleteRule: .cascade, inverse: \BoardTask.parentTask)
    var subtasks: [BoardTask]? = []
    /// Two offline devices can briefly produce the same deterministic migration record.
    /// Treat matching UUIDs as one logical child and prefer the most recently edited copy.
    var subtaskList: [BoardTask] {
        var newestByID: [UUID: BoardTask] = [:]
        for child in subtasks ?? [] {
            if let current = newestByID[child.id], current.updatedAt >= child.updatedAt { continue }
            newestByID[child.id] = child
        }
        return Array(newestByID.values)
    }

    init(title: String, status: TaskStatus = .backlog, project: Project? = nil) {
        id = UUID()
        self.title = title
        details = ""
        statusValue = status.rawValue
        priorityValue = TaskPriority.normal.rawValue
        tags = []
        checklist = []
        createdAt = Date()
        updatedAt = Date()
        self.project = project
        parentTask = nil
        subtasks = []
    }
    var status: TaskStatus {
        get { TaskStatus(rawValue: statusValue) ?? .backlog }
        set { statusValue = newValue.rawValue }
    }
    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityValue) ?? .normal }
        set { priorityValue = newValue.rawValue }
    }
}

/// Converts the original lightweight checklist values into full child tasks.
/// Keeping the old field during this release lets existing local and CloudKit stores upgrade safely.
@MainActor
enum LegacyChecklistMigrator {
    static func run(in context: ModelContext) throws {
        let tasks = try context.fetch(FetchDescriptor<BoardTask>())
        var changed = false

        for parent in tasks where !parent.checklist.isEmpty {
            let existingIDs = Set(parent.subtaskList.map(\.id))
            for legacy in parent.checklist where !existingIDs.contains(legacy.id) {
                let child = BoardTask(
                    title: legacy.title,
                    status: legacy.isComplete ? .done : .backlog,
                    project: parent.project
                )
                child.id = legacy.id
                child.parentTask = parent
                context.insert(child)
            }
            parent.checklist = []
            parent.updatedAt = Date()
            changed = true
        }

        if changed { try StoreWriter.save(context) }
    }
}

/// A profile is saved only after an explicit settings edit, avoiding startup-created duplicates.
/// If offline devices independently create profiles, the newest saved profile wins deterministically.
@Model
final class AppProfile {
    var id: UUID = UUID()
    var updatedAt: Date = Date()
    var stageNames: [String] = ["Backlog", "Planned", "In Progress", "Blocked", "Done"]
    var accentName: String = "blue"
    var appearanceMode: String = "system"
    var tagNames: [String] = []

    init(stageNames: [String], accent: AccentChoice) {
        self.stageNames = stageNames
        accentName = accent.rawValue
    }
    var appearance: BoardAppearance {
        BoardAppearance(stageNames: stageNames, accent: AccentChoice(rawValue: accentName) ?? .blue, mode: AppearanceMode(rawValue: appearanceMode) ?? .system)
    }
    static func current(in profiles: [AppProfile]) -> AppProfile? {
        profiles.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }.first
    }
}

/// All changes use explicit saves so storage failures can be reported and rolled back.
@MainActor
enum StoreWriter {
    static func save(_ context: ModelContext) throws {
        do { try context.save() }
        catch { context.rollback(); throw error }
    }
}

/// Common editable identity without changing either SwiftData model's stored schema.
protocol WorkspaceItem: PersistentModel {
    var name: String { get set }
}

extension Project: WorkspaceItem {}
extension ProjectArea: WorkspaceItem {}

extension StoreWriter {
    /// Mutate only on explicit Save; retain the shared rollback behavior on failure.
    static func saveItem<Item: WorkspaceItem>(
        _ existing: Item?, name: String, in context: ModelContext,
        create: () -> Item, configure: (Item) -> Void = { _ in }
    ) throws -> Item {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw WorkspaceItemError.emptyName }
        let item = existing ?? create()
        if existing == nil { context.insert(item) }
        item.name = cleanName
        configure(item)
        try save(context)
        return item
    }
}

private enum WorkspaceItemError: LocalizedError {
    case emptyName
    var errorDescription: String? { "Enter a name before saving." }
}
