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

    init(name: String, notes: String = "") {
        id = UUID()
        self.name = name
        self.notes = notes
        createdAt = Date()
    }
    var progress: Double { BoardRules.progress(statuses: taskList.map(\.status)) }
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
    var checklist: [ChecklistItem] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var project: Project?

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
