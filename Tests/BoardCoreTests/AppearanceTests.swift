import XCTest
@testable import BoardCore

final class AppearanceTests: XCTestCase {
    func testRenamingDoneDoesNotChangeCompletionSemantics() {
        let appearance = BoardAppearance(stageNames: ["Ideas", "Next", "Active", "Waiting", "Shipped"], accent: .purple)
        XCTAssertNil(appearance.validationError)
        XCTAssertEqual(appearance.title(for: .done), "Shipped")
        XCTAssertEqual(BoardRules.progress(statuses: [.done, .inProgress]), 0.5)
        XCTAssertEqual(TaskStatus.done.rawValue, "done")
    }
    func testFourStagesKeepLegacyCustomDoneName() {
        XCTAssertEqual(TaskStatus.allCases, [.backlog, .planned, .inProgress, .done])
        let upgraded = BoardAppearance(stageNames: ["Ideas", "Next", "Active", "Waiting", "Shipped"])
        XCTAssertEqual(upgraded.stageNames, ["Ideas", "Next", "Active", "Shipped"])
        XCTAssertEqual(upgraded.title(for: .done), "Shipped")
        XCTAssertNil(upgraded.validationError)
        XCTAssertEqual(TaskStatus(storedValue: "blocked"), .inProgress)
        let current = BoardAppearance(stageNames: ["Ideas", "Next", "Active", "Shipped"])
        XCTAssertEqual(current, upgraded)
    }
    func testTagLibraryNormalizationAndSearch() {
        XCTAssertEqual(TagRules.normalized([" Work ", "work", "", "Personal", "WORK"]), ["Personal", "Work"])
        XCTAssertEqual(TagRules.matches(["Firmware", "Hardware", "Design"], query: " WARE "), ["Firmware", "Hardware"])
        XCTAssertEqual(TagRules.existing(" work ", in: ["Work"]), "Work")
        XCTAssertNil(TagRules.existing("New", in: ["Work"]))
    }
    func testTagNameLimitPreservesExistingTags() {
        XCTAssertTrue(TagRules.isValidNewName(String(repeating: "a", count: 24)))
        XCTAssertFalse(TagRules.isValidNewName(String(repeating: "a", count: 25)))
        XCTAssertTrue(TagRules.isValidNewName("  Work  "))
        XCTAssertFalse(TagRules.isValidNewName("   "))
        XCTAssertFalse(TagRules.isValidNewName("Work\nPersonal"))
        XCTAssertTrue(TagRules.isValidNewName(String(repeating: "👩🏽‍💻", count: 24)))
        let legacy = String(repeating: "a", count: 40)
        XCTAssertEqual(TagRules.normalized([legacy]), [legacy])
    }
    func testInvalidNamesAndFallbacks() {
        XCTAssertNotNil(BoardAppearance(stageNames: [" ", "Next", "Active", "Waiting", "Done"]).validationError)
        XCTAssertNotNil(BoardAppearance(stageNames: ["Next", "next", "Active", "Waiting", "Done"]).validationError)
        XCTAssertEqual(BoardAppearance(stageNames: []).title(for: .done), "Done")
        XCTAssertEqual(AccentChoice.allCases.count, 8)
    }
}
