import XCTest
import SwiftData
@testable import BoardCore

final class WorkspaceLimitTests: XCTestCase {
    @MainActor private func makeContext() throws -> ModelContext {
        let schema = Schema([Project.self, BoardTask.self, ProjectArea.self, AppProfile.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        ])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    @MainActor func testFourthProjectAndSecondAreaAreBlockedWithoutInserting() throws {
        let context = try makeContext()
        for index in 1...3 {
            _ = try StoreWriter.saveItem(nil, name: "Project \(index)", in: context, create: { Project(name: "") })
        }
        XCTAssertThrowsError(try StoreWriter.saveItem(nil, name: "Fourth", in: context, create: { Project(name: "") })) {
            XCTAssertEqual(($0 as? WorkspaceLimitError)?.resource, .project)
        }
        _ = try StoreWriter.saveItem(nil, name: "Work", in: context, create: { ProjectArea(name: "") })
        XCTAssertThrowsError(try StoreWriter.saveItem(nil, name: "Personal", in: context, create: { ProjectArea(name: "") })) {
            XCTAssertEqual(($0 as? WorkspaceLimitError)?.resource, .area)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Project>()), 3)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProjectArea>()), 1)
        XCTAssertFalse(context.hasChanges)
    }

    @MainActor func testSubscribedUsersCanCreateBeyondBothLimitsAndStillEditAfterExpiry() throws {
        let context = try makeContext()
        for index in 1...5 {
            _ = try StoreWriter.saveItem(nil, name: "Project \(index)", in: context, hasUnlimitedAccess: true, create: { Project(name: "") })
            _ = try StoreWriter.saveItem(nil, name: "Area \(index)", in: context, hasUnlimitedAccess: true, create: { ProjectArea(name: "") })
        }
        let project = try XCTUnwrap(context.fetch(FetchDescriptor<Project>()).first)
        let area = try XCTUnwrap(context.fetch(FetchDescriptor<ProjectArea>()).first)
        _ = try StoreWriter.saveItem(project, name: "Still editable", in: context, create: { Project(name: "") })
        _ = try StoreWriter.saveItem(area, name: "Still accessible", in: context, create: { ProjectArea(name: "") })
        XCTAssertEqual(project.name, "Still editable")
        XCTAssertEqual(area.name, "Still accessible")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Project>()), 5)
        XCTAssertThrowsError(try StoreWriter.requireCreationAccess(.project, in: context, hasUnlimited: false))
    }

    @MainActor func testSaveRechecksQuotaAfterAnotherContextAddsAProjectAndDeletionFreesSpace() throws {
        let context = try makeContext()
        for index in 1...2 { context.insert(Project(name: "Existing \(index)")) }
        try context.save()
        try StoreWriter.requireCreationAccess(.project, in: context, hasUnlimited: false)
        let other = ModelContext(context.container)
        other.insert(Project(name: "Arrived while editing"))
        try other.save()
        XCTAssertThrowsError(try StoreWriter.saveItem(nil, name: "Draft", in: context, create: { Project(name: "") }))
        let project = try XCTUnwrap(context.fetch(FetchDescriptor<Project>()).first)
        context.delete(project)
        try context.save()
        _ = try StoreWriter.saveItem(nil, name: "Draft", in: context, create: { Project(name: "") })
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Project>()), 3)
    }
}
