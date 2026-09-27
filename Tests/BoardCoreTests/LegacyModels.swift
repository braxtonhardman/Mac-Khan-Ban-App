import Foundation
import SwiftData
import BoardCore

// Frozen V1 schema used to verify upgrades preserve existing stores.
enum LegacyModels {
@Model
final class Project {
    @Attribute(.unique) var id: UUID
    var name: String
    var notes: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \BoardTask.project)
    var tasks: [BoardTask] = []

    init(name: String, notes: String = "") {
        id = UUID()
        self.name = name
        self.notes = notes
        createdAt = Date()
    }
    var progress: Double { BoardRules.progress(statuses: tasks.map(\.status)) }
}

@Model
final class BoardTask {
    @Attribute(.unique) var id: UUID
    var title: String
    var details: String
    var statusValue: String
    var priorityValue: Int
    var dueDate: Date?
    var tags: [String]
    var checklist: [ChecklistItem]
    var createdAt: Date
    var updatedAt: Date
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

}
