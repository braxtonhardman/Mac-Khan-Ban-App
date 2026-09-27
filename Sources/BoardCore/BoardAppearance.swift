import Foundation

public enum AccentChoice: String, CaseIterable, Identifiable, Codable {
    case red, orange, yellow, green, teal, blue, purple, pink
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public struct BoardAppearance: Equatable {
    public var stageNames: [String]
    public var accent: AccentChoice
    public init(stageNames: [String] = TaskStatus.allCases.map(\.title), accent: AccentChoice = .blue) {
        self.stageNames = stageNames
        self.accent = accent
    }
    public func title(for status: TaskStatus) -> String {
        let index = TaskStatus.allCases.firstIndex(of: status)!
        guard stageNames.indices.contains(index) else { return status.title }
        let name = stageNames[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? status.title : name
    }
    public var validationError: String? {
        guard stageNames.count == TaskStatus.allCases.count else { return "Name all five stages." }
        let names = stageNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard names.allSatisfy({ !$0.isEmpty }) else { return "Stage names cannot be blank." }
        guard Set(names.map { $0.lowercased() }).count == names.count else { return "Give each stage a different name." }
        return nil
    }
}
