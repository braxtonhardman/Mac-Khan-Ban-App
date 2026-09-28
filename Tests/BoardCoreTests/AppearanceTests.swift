import XCTest
@testable import BoardCore

final class AppearanceTests: XCTestCase {
    func testRenamingDoneDoesNotChangeCompletionSemantics() {
        let appearance = BoardAppearance(stageNames: ["Ideas", "Next", "Active", "Waiting", "Shipped"], accent: .purple)
        XCTAssertNil(appearance.validationError)
        XCTAssertEqual(appearance.title(for: .done), "Shipped")
        XCTAssertEqual(BoardRules.progress(statuses: [.done, .blocked]), 0.5)
        XCTAssertEqual(TaskStatus.done.rawValue, "done")
    }
    func testTagLibraryNormalizationAndSearch() {
        XCTAssertEqual(TagRules.normalized([" Work ", "work", "", "Personal", "WORK"]), ["Personal", "Work"])
        XCTAssertEqual(TagRules.matches(["Firmware", "Hardware", "Design"], query: " WARE "), ["Firmware", "Hardware"])
        XCTAssertEqual(TagRules.existing(" work ", in: ["Work"]), "Work")
        XCTAssertNil(TagRules.existing("New", in: ["Work"]))
    }
    func testInvalidNamesAndFallbacks() {
        XCTAssertNotNil(BoardAppearance(stageNames: [" ", "Next", "Active", "Waiting", "Done"]).validationError)
        XCTAssertNotNil(BoardAppearance(stageNames: ["Next", "next", "Active", "Waiting", "Done"]).validationError)
        XCTAssertEqual(BoardAppearance(stageNames: []).title(for: .done), "Done")
        XCTAssertEqual(AccentChoice.allCases.count, 8)
    }
}
