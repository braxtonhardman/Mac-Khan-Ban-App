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
    func testInvalidNamesAndFallbacks() {
        XCTAssertNotNil(BoardAppearance(stageNames: [" ", "Next", "Active", "Waiting", "Done"]).validationError)
        XCTAssertNotNil(BoardAppearance(stageNames: ["Next", "next", "Active", "Waiting", "Done"]).validationError)
        XCTAssertEqual(BoardAppearance(stageNames: []).title(for: .done), "Done")
        XCTAssertEqual(AccentChoice.allCases.count, 8)
    }
}
