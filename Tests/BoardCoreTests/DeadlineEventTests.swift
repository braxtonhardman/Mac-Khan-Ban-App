import XCTest
@testable import BoardCore

final class DeadlineEventTests: XCTestCase {
    func testAllDayDeadlineUsesCalendarDayAcrossDST() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let due = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 15))!
        let id = UUID()
        let payload = DeadlineEvent(taskID: id, title: "Ship", project: "App", details: "Notes", dueDate: due, calendar: calendar)
        XCTAssertEqual(calendar.component(.hour, from: payload.start), 0)
        XCTAssertEqual(calendar.component(.day, from: payload.end), 9)
        XCTAssertEqual(payload.end.timeIntervalSince(payload.start), 23 * 3600)
        XCTAssertEqual(payload.title, "Ship — App")
        XCTAssertEqual(payload.notes, "Notes")
        XCTAssertEqual(payload.url.lastPathComponent, id.uuidString)
    }
}
