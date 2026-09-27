import XCTest
@testable import BoardCore

final class BoardRulesTests: XCTestCase {
    func testProgressOnlyCountsDone() {
        XCTAssertEqual(BoardRules.progress(statuses: []), 0)
        XCTAssertEqual(BoardRules.progress(statuses: [.backlog, .planned, .inProgress, .blocked, .done]), 0.2)
        XCTAssertEqual(BoardRules.progress(statuses: [.done, .done]), 1)
    }
    func testTagsTrimAndDeduplicateWhilePreservingOrder() {
        XCTAssertEqual(BoardRules.tags(from: " Swift, ,macOS, swift, MACOS, local "), ["Swift", "macOS", "local"])
    }
    func testChecklistRoundTripPreservesIdentityAndCompletion() throws {
        let items = [ChecklistItem(title: "Prototype", isComplete: true), ChecklistItem(title: "Ship")]
        XCTAssertEqual(try JSONDecoder().decode([ChecklistItem].self, from: JSONEncoder().encode(items)), items)
    }
}
