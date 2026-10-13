import XCTest
@testable import BoardCore

@MainActor
final class CalendarSyncTests: XCTestCase {
    final class FakeStore: DeadlineCalendarStore {
        struct Record { var taskID: UUID; var payload: DeadlineEvent; var calendar: String }
        var records: [String: Record] = [:]
        var failingTask: UUID?
        var saves = 0
        func matchingEvents(taskID: UUID, link: DeadlineCalendarLink?, date: Date?) throws -> [DeadlineCalendarLink] {
            records.filter { $0.value.taskID == taskID }.sorted { $0.key < $1.key }.map {
                DeadlineCalendarLink(eventID: $0.key, externalID: $0.key, date: $0.value.payload.start)
            }
        }
        func upsert(_ payload: DeadlineEvent, calendarID: String, existing: DeadlineCalendarLink?) throws -> DeadlineCalendarLink {
            let taskID = UUID(uuidString: payload.url.lastPathComponent)!
            if taskID == failingTask { throw NSError(domain: "test", code: 1) }
            let id = existing?.eventID ?? UUID().uuidString
            records[id] = Record(taskID: taskID, payload: payload, calendar: calendarID)
            saves += 1
            return DeadlineCalendarLink(eventID: id, externalID: id, date: payload.start)
        }
        func remove(_ link: DeadlineCalendarLink, taskID: UUID) throws {
            guard records[link.eventID]?.taskID == taskID else { return }
            records.removeValue(forKey: link.eventID)
        }
    }
    func payload(_ id: UUID, day: TimeInterval = 1_800_000_000, title: String = "Task") -> DeadlineEvent {
        DeadlineEvent(taskID: id, title: title, project: "Project", details: "Notes", dueDate: Date(timeIntervalSince1970: day))
    }
    func testCreateUpdateAndMoveCalendarReuseOneEvent() throws {
        let id = UUID(), store = FakeStore()
        var links: [UUID: DeadlineCalendarLink] = [:]
        try DeadlineCalendarSync.reconcile(deadlines: [id: payload(id)], calendarID: "Work", links: &links, store: store, persist: { _ in })
        let firstID = links[id]?.eventID
        let edited = payload(id, day: 1_900_000_000, title: "Updated")
        try DeadlineCalendarSync.reconcile(deadlines: [id: edited], calendarID: "Personal", links: &links, store: store, persist: { _ in })
        XCTAssertEqual(links[id]?.eventID, firstID)
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.records[firstID!]?.calendar, "Personal")
        XCTAssertEqual(store.records[firstID!]?.payload.title, "Updated — Project")
        XCTAssertEqual(store.records[firstID!]?.payload.start, edited.start)
    }
    func testRemovingDeadlineOrTaskRemovesOnlyItsLinkedEvent() throws {
        let id = UUID(), unrelated = UUID(), store = FakeStore()
        var links: [UUID: DeadlineCalendarLink] = [:]
        try DeadlineCalendarSync.reconcile(deadlines: [id: payload(id)], calendarID: "Work", links: &links, store: store, persist: { _ in })
        store.records["personal"] = .init(taskID: unrelated, payload: payload(unrelated), calendar: "Work")
        try DeadlineCalendarSync.reconcile(deadlines: [:], calendarID: "Work", links: &links, store: store, persist: { _ in })
        XCTAssertTrue(links.isEmpty)
        XCTAssertEqual(Set(store.records.keys), ["personal"])
    }
    func testAnotherDeviceRecoversEventWithoutItsLocalLink() throws {
        let id = UUID(), store = FakeStore()
        store.records["shared"] = .init(taskID: id, payload: payload(id), calendar: "iCloud")
        var links: [UUID: DeadlineCalendarLink] = [:]
        try DeadlineCalendarSync.reconcile(deadlines: [id: payload(id)], calendarID: "iCloud", links: &links, store: store, persist: { _ in })
        XCTAssertEqual(links[id]?.eventID, "shared")
        XCTAssertEqual(store.records.count, 1)
    }
    func testConcurrentDuplicatesConvergeToOneEvent() throws {
        let id = UUID(), store = FakeStore()
        for key in ["a", "b"] { store.records[key] = .init(taskID: id, payload: payload(id), calendar: "iCloud") }
        var links: [UUID: DeadlineCalendarLink] = [:]
        try DeadlineCalendarSync.reconcile(deadlines: [id: payload(id)], calendarID: "iCloud", links: &links, store: store, persist: { _ in })
        XCTAssertEqual(Set(store.records.keys), ["a"])
    }
    func testCompletionRemovesEventAndReopeningRestoresIt() throws {
        let id = UUID(), unrelated = UUID(), store = FakeStore()
        var links: [UUID: DeadlineCalendarLink] = [:]
        let deadline = payload(id)
        try DeadlineCalendarSync.reconcile(deadlines: [id: deadline], calendarID: "Tierin", links: &links, store: store, persist: { _ in })
        store.records["personal"] = .init(taskID: unrelated, payload: payload(unrelated), calendar: "Tierin")
        try DeadlineCalendarSync.reconcile(deadlines: [:], completedDeadlines: [id: deadline.start], calendarID: "Tierin", links: &links, store: store, persist: { _ in })
        XCTAssertNil(links[id])
        XCTAssertEqual(Set(store.records.keys), ["personal"])
        try DeadlineCalendarSync.reconcile(deadlines: [id: deadline], calendarID: "Tierin", links: &links, store: store, persist: { _ in })
        XCTAssertNotNil(links[id])
        XCTAssertEqual(store.records.values.filter { $0.taskID == id }.count, 1)
    }
    func testCompletionRemovesEventsFromAnotherDeviceWithoutLocalLinks() throws {
        let id = UUID(), store = FakeStore(), deadline = payload(id)
        for key in ["a", "b"] { store.records[key] = .init(taskID: id, payload: deadline, calendar: "iCloud") }
        var links: [UUID: DeadlineCalendarLink] = [:]
        try DeadlineCalendarSync.reconcile(deadlines: [:], completedDeadlines: [id: deadline.start], calendarID: "iCloud", links: &links, store: store, persist: { _ in })
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertTrue(links.isEmpty)
        XCTAssertEqual(store.saves, 0)
    }
    func testPartialFailurePersistsSuccessfulLinksForRetry() throws {
        let ids = [UUID(), UUID()].sorted { $0.uuidString < $1.uuidString }
        let store = FakeStore()
        store.failingTask = ids[1]
        var links: [UUID: DeadlineCalendarLink] = [:], persisted: [UUID: DeadlineCalendarLink] = [:]
        let deadlines = Dictionary(uniqueKeysWithValues: ids.map { ($0, payload($0)) })
        XCTAssertThrowsError(try DeadlineCalendarSync.reconcile(deadlines: deadlines, calendarID: "Work", links: &links, store: store, persist: { persisted = $0 }))
        XCTAssertNotNil(persisted[ids[0]])
        XCTAssertNil(persisted[ids[1]])
        store.failingTask = nil
        try DeadlineCalendarSync.reconcile(deadlines: deadlines, calendarID: "Work", links: &links, store: store, persist: { persisted = $0 })
        XCTAssertEqual(store.records.count, 2)
        XCTAssertEqual(persisted.count, 2)
    }
}
