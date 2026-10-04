import XCTest
@testable import BoardCore

final class DeadlineEventTests: XCTestCase {
    func testNewAndLegacyLinksIdentifyTheSameTask() {
        let id = UUID()
        XCTAssertEqual(TaskLink.url(for: id).absoluteString, "tierin://task/\(id.uuidString)")
        XCTAssertEqual(TaskLink.taskID(from: TaskLink.url(for: id)), id)
        XCTAssertEqual(TaskLink.taskID(from: URL(string: "projectboard://task/\(id.uuidString)")), id)
        XCTAssertNotEqual(TaskLink.taskID(from: TaskLink.url(for: UUID())), id)
    }

    func testUnrelatedAndMalformedLinksAreRejected() {
        let id = UUID().uuidString
        for link in ["https://task/\(id)", "tierin://project/\(id)",
                     "tierin://task/extra/\(id)", "tierin://task/not-a-uuid",
                     "tierin://task/\(id)?other=true", "tierin://task/\(id)#other",
                     "tierin://user@task/\(id)"] {
            XCTAssertNil(TaskLink.taskID(from: URL(string: link)), link)
        }
        XCTAssertNil(TaskLink.taskID(from: nil))
    }

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
        XCTAssertEqual(payload.url.scheme, "tierin")
        XCTAssertEqual(payload.url.lastPathComponent, id.uuidString)
    }
}
