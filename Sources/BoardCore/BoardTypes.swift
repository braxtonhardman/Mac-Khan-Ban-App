import Foundation

public enum TaskStatus: String, CaseIterable, Codable, Identifiable {
    case backlog, planned, inProgress, blocked, done
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .backlog: return "Backlog"
        case .planned: return "Planned"
        case .inProgress: return "In Progress"
        case .blocked: return "Blocked"
        case .done: return "Done"
        }
    }
    public var symbol: String {
        switch self {
        case .backlog: return "tray"
        case .planned: return "calendar"
        case .inProgress: return "circle.lefthalf.filled"
        case .blocked: return "exclamationmark.circle"
        case .done: return "checkmark.circle.fill"
        }
    }
}

public enum TaskPriority: Int, CaseIterable, Codable, Identifiable {
    case low, normal, high, urgent
    public var id: Int { rawValue }
    public var title: String { ["Low", "Normal", "High", "Urgent"][rawValue] }
}

public struct ChecklistItem: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var isComplete: Bool
    public init(id: UUID = UUID(), title: String, isComplete: Bool = false) {
        self.id = id
        self.title = title
        self.isComplete = isComplete
    }
}

public enum BoardRules {
    public static func progress(statuses: [TaskStatus]) -> Double {
        guard !statuses.isEmpty else { return 0 }
        return Double(statuses.filter { $0 == .done }.count) / Double(statuses.count)
    }
    public static func tags(from text: String) -> [String] {
        var seen = Set<String>()
        return text.split(separator: ",").compactMap {
            let tag = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return !tag.isEmpty && seen.insert(tag.lowercased()).inserted ? tag : nil
        }
    }
}
