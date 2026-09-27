import SwiftUI
import EventKit
#if SWIFT_PACKAGE
import BoardCore
#endif

/// EventKit identifiers are device-local and deliberately kept out of the synced model.
@MainActor
final class CalendarIntegration: ObservableObject {
    private let store = EKEventStore()
    @Published var calendars: [EKCalendar] = []
    @Published var selectedCalendarID = ""
    @Published var error: String?
    @Published var ready = false
    @Published var busy = false
    @Published var hasExistingEvent = false
    private var existingEvent: EKEvent?

    func prepare(taskID: UUID) async {
        busy = true
        defer { busy = false }
        do {
            guard try await store.requestFullAccessToEvents() else {
                error = "Calendar access is off. Enable ProjectBoard in System Settings → Privacy & Security → Calendars, then try again."
                return
            }
            calendars = store.calendars(for: .event).filter(\.allowsContentModifications)
            guard !calendars.isEmpty else {
                error = "No writable calendar is available. Create a calendar in Apple Calendar, then try again."
                return
            }
            if let id = UserDefaults.standard.string(forKey: key(taskID)) {
                existingEvent = store.event(withIdentifier: id)
            }
            hasExistingEvent = existingEvent != nil
            selectedCalendarID = existingEvent?.calendar.calendarIdentifier
                ?? store.defaultCalendarForNewEvents?.calendarIdentifier ?? calendars[0].calendarIdentifier
            if !calendars.contains(where: { $0.calendarIdentifier == selectedCalendarID }) {
                selectedCalendarID = calendars[0].calendarIdentifier
            }
            ready = true
        } catch { self.error = error.localizedDescription }
    }

    func save(task: BoardTask) -> Bool {
        guard let due = task.dueDate,
              let calendar = calendars.first(where: { $0.calendarIdentifier == selectedCalendarID }) else { return false }
        do {
            let payload = DeadlineEvent(taskID: task.id, title: task.title, project: task.project?.name ?? "ProjectBoard", details: task.details, dueDate: due)
            let event = existingEvent ?? EKEvent(eventStore: store)
            event.title = payload.title
            event.notes = payload.notes
            event.url = payload.url
            event.isAllDay = true
            event.startDate = payload.start
            event.endDate = payload.end
            event.calendar = calendar
            try store.save(event, span: .thisEvent, commit: true)
            UserDefaults.standard.set(event.eventIdentifier, forKey: key(task.id))
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    private func key(_ id: UUID) -> String { "calendar-event.\(id.uuidString)" }
}

struct CalendarDeadlineSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var integration = CalendarIntegration()
    let task: BoardTask

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Deadline in Calendar").font(.title2.bold())
            Text(task.title).font(.headline)
            if let due = task.dueDate {
                Text(due, format: .dateTime.weekday().month().day().year())
            }
            Text("Save an all-day event to a calendar you choose. Use this action again to update the event after changing the task. Changes in Calendar do not edit this task.")
                .font(.callout).foregroundStyle(.secondary)
            if integration.ready {
                Picker("Calendar", selection: $integration.selectedCalendarID) {
                    ForEach(integration.calendars, id: \.calendarIdentifier) { Text($0.title).tag($0.calendarIdentifier) }
                }
                Text(integration.hasExistingEvent ? "Updates the event previously added from this device." : "Creates a new event. Events added from another device are not linked here.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Choose Calendar…") { Task { await integration.prepare(taskID: task.id) } }
                    .disabled(integration.busy)
                Text("Calendar access is requested only when you choose a calendar.").font(.caption).foregroundStyle(.secondary)
            }
            if integration.busy { ProgressView() }
            if let error = integration.error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(integration.hasExistingEvent ? "Update Event" : "Add Event") {
                    if integration.save(task: task) { dismiss() }
                }.buttonStyle(.borderedProminent)
                    .disabled(!integration.ready || task.dueDate == nil)
            }
        }.padding(24).frame(idealWidth: 460)
    }
}
