import Foundation

public struct DeadlineEvent {
    public let title: String
    public let notes: String
    public let url: URL
    public let start: Date
    public let end: Date

    public init(taskID: UUID, title: String, project: String, details: String, dueDate: Date, calendar: Calendar = .current) {
        self.title = "\(title) — \(project)"
        notes = details
        url = URL(string: "projectboard://task/\(taskID.uuidString)")!
        start = calendar.startOfDay(for: dueDate)
        end = calendar.date(byAdding: .day, value: 1, to: start)!
    }
}
