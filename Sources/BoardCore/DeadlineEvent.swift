import Foundation

/// Generate Tierin links while recognizing links already saved by earlier releases.
public enum TaskLink {
    public static func url(for taskID: UUID) -> URL {
        URL(string: "tierin://task/\(taskID.uuidString)")!
    }

    public static func taskID(from url: URL?) -> UUID? {
        guard let url,
              ["tierin", "projectboard"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.lowercased() == "task",
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil,
              url.pathComponents.count == 2 else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }
}

public struct DeadlineEvent {
    public let title: String
    public let notes: String
    public let url: URL
    public let start: Date
    public let end: Date

    public init(taskID: UUID, title: String, project: String, details: String, dueDate: Date, calendar: Calendar = .current) {
        self.title = "\(title) — \(project)"
        notes = details
        url = TaskLink.url(for: taskID)
        start = calendar.startOfDay(for: dueDate)
        end = calendar.date(byAdding: .day, value: 1, to: start)!
    }
}

/// Device-local links can be recovered by the stable task URL when Calendar changes its IDs.
public struct DeadlineCalendarLink: Codable, Equatable {
    public var eventID: String
    public var externalID: String?
    public var date: Date
    public init(eventID: String, externalID: String? = nil, date: Date) {
        self.eventID = eventID; self.externalID = externalID; self.date = date
    }
}

@MainActor
public protocol DeadlineCalendarStore {
    func matchingEvents(taskID: UUID, link: DeadlineCalendarLink?, date: Date?) throws -> [DeadlineCalendarLink]
    func upsert(_ payload: DeadlineEvent, calendarID: String, existing: DeadlineCalendarLink?) throws -> DeadlineCalendarLink
    func remove(_ link: DeadlineCalendarLink, taskID: UUID) throws
}

@MainActor
public enum DeadlineCalendarSync {
    /// Persist after each successful operation so an interrupted batch can safely retry.
    public static func reconcile(
        deadlines: [UUID: DeadlineEvent], completedDeadlines: [UUID: Date] = [:], calendarID: String,
        links: inout [UUID: DeadlineCalendarLink], store: DeadlineCalendarStore,
        persist: ([UUID: DeadlineCalendarLink]) -> Void
    ) throws {
        for id in deadlines.keys.filter({ completedDeadlines[$0] == nil }).sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let payload = deadlines[id] else { continue }
            let matches = try store.matchingEvents(taskID: id, link: links[id], date: payload.start)
            let event = try store.upsert(payload, calendarID: calendarID, existing: matches.first)
            links[id] = event
            persist(links)
            // Only events carrying this task's exact ownership URL can be returned by the adapter.
            for duplicate in matches where duplicate.eventID != event.eventID {
                try store.remove(duplicate, taskID: id)
            }
        }
        // Search completed tasks by their ownership URL even if this device never exported them.
        for id in Set(links.keys).union(completedDeadlines.keys) where deadlines[id] == nil || completedDeadlines[id] != nil {
            let matches = try store.matchingEvents(taskID: id, link: links[id], date: completedDeadlines[id])
            for event in matches { try store.remove(event, taskID: id) }
            links.removeValue(forKey: id)
            persist(links)
        }
    }
}
