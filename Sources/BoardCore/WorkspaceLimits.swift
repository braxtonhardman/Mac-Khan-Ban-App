import Foundation

public enum WorkspaceResource: String, Equatable, Sendable {
    case project, area

    public var freeLimit: Int { self == .project ? 5 : 2 }
    public var limitMessage: String {
        self == .project
            ? "Your free workspace includes 5 projects. Unlock Unlimited to add another."
            : "Your free workspace includes 2 areas. Unlock Unlimited to add another."
    }

    public func canCreate(existingCount: Int, hasUnlimited: Bool) -> Bool {
        hasUnlimited || existingCount < freeLimit
    }
}

public struct WorkspaceLimitError: LocalizedError {
    public let resource: WorkspaceResource
    public init(_ resource: WorkspaceResource) { self.resource = resource }
    public var errorDescription: String? { resource.limitMessage }
}
