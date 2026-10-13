import SwiftUI
import SwiftData
import EventKit
#if SWIFT_PACKAGE
import BoardCore
#endif

/// EventKit access and identifiers are local to each device. Apple syncs iCloud calendar events.
@MainActor
final class CalendarIntegration: ObservableObject {
    static let shared = CalendarIntegration()
    private let store = EKEventStore()
    private let defaults = UserDefaults.standard
    private var context: ModelContext?
    private var accountID = ""
    private var active = false
    private var pending: Task<Void, Never>?
    @Published private(set) var calendars: [EKCalendar] = []
    @Published private(set) var sources: [EKSource] = []
    @Published private(set) var selectedCalendarID = ""
    @Published private(set) var enabled = false
    @Published private(set) var busy = false
    @Published private(set) var authorized = false
    @Published private(set) var lastSync: Date?
    @Published private(set) var error: String?
    private var links: [UUID: DeadlineCalendarLink] = [:]
    private var prefix: String { "calendar-sync.\(accountID)." }
    var selectedCalendarName: String {
        calendars.first { $0.calendarIdentifier == selectedCalendarID }?.title ?? "Choose a calendar"
    }

    var suggestedSourceID: String {
        calendars.first { $0.calendarIdentifier == selectedCalendarID }?.source.sourceIdentifier
            ?? sources.first { $0.title.localizedCaseInsensitiveCompare("iCloud") == .orderedSame }?.sourceIdentifier
            ?? store.defaultCalendarForNewEvents?.source.sourceIdentifier
            ?? sources.first?.sourceIdentifier ?? ""
    }

    func tierinCalendar(in sourceID: String) -> EKCalendar? {
        let candidates = calendars.filter { $0.source.sourceIdentifier == sourceID }
        if let savedID = defaults.string(forKey: prefix + "dedicated-calendar." + sourceID),
           let saved = candidates.first(where: { $0.calendarIdentifier == savedID }) { return saved }
        return candidates.filter { $0.title.localizedCaseInsensitiveCompare("Tierin") == .orderedSame }
            .sorted { $0.calendarIdentifier < $1.calendarIdentifier }.first
    }

    func connectTierinCalendar(sourceID: String) {
        guard !busy else { return }
        refreshCalendars()
        guard authorized, let source = sources.first(where: { $0.sourceIdentifier == sourceID }) else {
            error = "Choose an available Calendar account first."
            return
        }
        error = nil
        do {
            let calendar: EKCalendar
            if let existing = tierinCalendar(in: sourceID) {
                calendar = existing
            } else {
                calendar = EKCalendar(for: .event, eventStore: store)
                calendar.title = "Tierin"
                calendar.source = source
                try store.saveCalendar(calendar, commit: true)
            }
            defaults.set(calendar.calendarIdentifier, forKey: prefix + "dedicated-calendar." + sourceID)
            refreshCalendars()
            connect(calendarID: calendar.calendarIdentifier)
        } catch {
            self.error = "Couldn’t create the Tierin calendar: \(error.localizedDescription) Choose another account or enable iCloud Calendars in Settings."
        }
    }

    private init() {}

    func configure(context: ModelContext, accountID: String, active: Bool) {
        self.context = context
        self.active = active
        if self.accountID != accountID {
            pending?.cancel()
            self.accountID = accountID
            selectedCalendarID = defaults.string(forKey: prefix + "calendar") ?? ""
            enabled = defaults.bool(forKey: prefix + "enabled")
            links = defaults.data(forKey: prefix + "links")
                .flatMap { try? JSONDecoder().decode([UUID: DeadlineCalendarLink].self, from: $0) } ?? [:]
            lastSync = defaults.object(forKey: prefix + "lastSync") as? Date
            error = nil
        }
        refreshCalendars()
        if active { schedule() } else { pending?.cancel() }
    }

    func refreshCalendars() {
        authorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        calendars = authorized ? store.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .sorted { ($0.source.title, $0.title) < ($1.source.title, $1.title) } : []
        sources = authorized ? store.sources.filter {
            $0.sourceType == .calDAV || $0.sourceType == .local || $0.sourceType == .exchange
        }.sorted { $0.title < $1.title } : []
    }

    func requestAccess() async {
        busy = true
        defer { busy = false }
        error = nil
        do {
            guard try await store.requestFullAccessToEvents() else {
                error = "Allow full Calendar access for Tierin in Settings → Privacy & Security → Calendars."
                refreshCalendars()
                return
            }
            store.reset()
            refreshCalendars()
            if sources.isEmpty { error = "Enable an account in Apple Calendar, then return here." }
        } catch { self.error = error.localizedDescription }
    }

    func connect(calendarID: String) {
        guard calendars.contains(where: { $0.calendarIdentifier == calendarID }) else { return }
        selectedCalendarID = calendarID
        enabled = true
        defaults.set(calendarID, forKey: prefix + "calendar")
        defaults.set(true, forKey: prefix + "enabled")
        syncNow()
    }

    func disconnect() {
        pending?.cancel()
        enabled = false
        defaults.set(false, forKey: prefix + "enabled")
        error = nil
    }

    func schedule() {
        pending?.cancel()
        guard active && enabled else { return }
        pending = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
            self?.syncNow()
        }
    }

    func syncNow() {
        guard active, enabled, !busy, let context else { return }
        refreshCalendars()
        guard authorized else {
            error = "Calendar access is off. Allow full access to resume syncing."
            return
        }
        guard calendars.contains(where: { $0.calendarIdentifier == selectedCalendarID }) else {
            error = "The selected calendar is unavailable or read-only. Choose another calendar to resume syncing."
            return
        }
        // Never export unsaved editor changes or infer deletions from a failed fetch.
        guard !context.hasChanges else { return }
        busy = true
        defer { busy = false }
        do {
            let tasks = try context.fetch(FetchDescriptor<BoardTask>())
            var deadlines: [UUID: DeadlineEvent] = [:]
            var completedDeadlines: [UUID: Date] = [:]
            for task in tasks.sorted(by: { $0.updatedAt < $1.updatedAt }) {
                if links[task.id] == nil, let external = task.calendarExternalIdentifier,
                   let exportedDate = task.calendarLastExportedDate {
                    links[task.id] = DeadlineCalendarLink(eventID: "", externalID: external, date: exportedDate)
                }
                guard let due = task.dueDate else { continue }
                // Adopt events created by the previous manual-export feature.
                if links[task.id] == nil, let oldID = defaults.string(forKey: "calendar-event.\(task.id.uuidString)") {
                    links[task.id] = DeadlineCalendarLink(eventID: oldID, date: due)
                }
                if task.status == .done {
                    completedDeadlines[task.id] = due
                } else {
                    deadlines[task.id] = DeadlineEvent(taskID: task.id, title: task.title,
                        project: task.project?.name ?? "Tierin", details: task.details, dueDate: due)
                }
            }
            var updatedLinks = links
            try DeadlineCalendarSync.reconcile(deadlines: deadlines, completedDeadlines: completedDeadlines, calendarID: selectedCalendarID,
                links: &updatedLinks, store: EventKitDeadlineStore(store: store)) { saved in
                    self.links = saved
                    if let data = try? JSONEncoder().encode(saved) { self.defaults.set(data, forKey: self.prefix + "links") }
                }
            var metadataChanged = false
            for task in tasks {
                let synced = links[task.id]
                if task.calendarExternalIdentifier != synced?.externalID || task.calendarLastExportedDate != synced?.date {
                    task.calendarExternalIdentifier = synced?.externalID
                    task.calendarLastExportedDate = synced?.date
                    metadataChanged = true
                }
            }
            if metadataChanged { try StoreWriter.save(context) }
            lastSync = Date()
            defaults.set(lastSync, forKey: prefix + "lastSync")
            error = nil
        } catch { self.error = "Calendar sync paused: \(error.localizedDescription)" }
    }
}

@MainActor
private final class EventKitDeadlineStore: DeadlineCalendarStore {
    let store: EKEventStore
    init(store: EKEventStore) { self.store = store }
    private func owns(_ event: EKEvent, taskID: UUID) -> Bool {
        TaskLink.taskID(from: event.url) == taskID && !event.hasRecurrenceRules
    }
    private func link(_ event: EKEvent) -> DeadlineCalendarLink {
        DeadlineCalendarLink(eventID: event.eventIdentifier,
                             externalID: event.calendarItemExternalIdentifier, date: event.startDate)
    }
    func matchingEvents(taskID: UUID, link: DeadlineCalendarLink?, date: Date?) throws -> [DeadlineCalendarLink] {
        var found: [String: EKEvent] = [:]
        func add(_ event: EKEvent?) {
            guard let event, owns(event, taskID: taskID) else { return }
            found[event.eventIdentifier] = event
        }
        if let link {
            add(store.event(withIdentifier: link.eventID))
            if let external = link.externalID {
                for item in store.calendarItems(withExternalIdentifier: external) { add(item as? EKEvent) }
            }
        }
        // A task URL is shared across devices even though EventKit local identifiers are not.
        for day in Set([date, link?.date].compactMap { $0 }) {
            let start = day.addingTimeInterval(-172_800)
            let end = day.addingTimeInterval(172_800)
            for event in store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil)) { add(event) }
        }
        return found.values.sorted {
            let left = $0.calendarItemExternalIdentifier ?? $0.eventIdentifier ?? ""
            let right = $1.calendarItemExternalIdentifier ?? $1.eventIdentifier ?? ""
            return left == right ? $0.eventIdentifier < $1.eventIdentifier : left < right
        }.map(self.link)
    }
    func upsert(_ payload: DeadlineEvent, calendarID: String, existing: DeadlineCalendarLink?) throws -> DeadlineCalendarLink {
        guard let calendar = store.calendar(withIdentifier: calendarID), calendar.allowsContentModifications else {
            throw CalendarSyncError.unavailable
        }
        let prior = existing.flatMap { store.event(withIdentifier: $0.eventID) }
        if let prior {
            guard let taskID = TaskLink.taskID(from: payload.url), owns(prior, taskID: taskID) else {
                throw CalendarSyncError.changedEvent
            }
        }
        let event = prior ?? EKEvent(eventStore: store)
        let changed = event.title != payload.title || event.notes != payload.notes || event.url != payload.url
            || !event.isAllDay || event.startDate != payload.start || event.endDate != payload.end
            || event.calendar?.calendarIdentifier != calendarID
        if changed {
            event.title = payload.title; event.notes = payload.notes; event.url = payload.url
            event.isAllDay = true; event.startDate = payload.start; event.endDate = payload.end
            event.calendar = calendar
            try store.save(event, span: .thisEvent, commit: true)
        }
        return link(event)
    }
    func remove(_ link: DeadlineCalendarLink, taskID: UUID) throws {
        guard let event = store.event(withIdentifier: link.eventID), owns(event, taskID: taskID) else { return }
        try store.remove(event, span: .thisEvent, commit: true)
    }
}

private enum CalendarSyncError: LocalizedError {
    case unavailable, changedEvent
    var errorDescription: String? {
        switch self {
        case .unavailable: "The selected calendar is no longer writable."
        case .changedEvent: "The linked event changed ownership. Reconnect your calendar to retry."
        }
    }
}

struct CalendarSettingsView: View {
    @ObservedObject private var integration = CalendarIntegration.shared
    @State private var sourceID = ""
    var body: some View {
        Form {
            AppSection("Provider") {
                Label("Apple Calendar", systemImage: "calendar").font(AppTypography.itemTitle)
                Text("Use a calendar available in the Apple Calendar app on this device.")
                    .font(AppTypography.supporting).foregroundStyle(.secondary)
            }
            AppSection("Destination calendar") {
                if integration.authorized {
                    Text("Tierin").font(AppTypography.itemTitle)
                    Picker("Account", selection: $sourceID) {
                        Text("Choose an account").tag("")
                        ForEach(integration.sources, id: \.sourceIdentifier) { source in
                            Text(source.title).tag(source.sourceIdentifier)
                        }
                    }
                    Button(integration.tierinCalendar(in: sourceID) == nil ? "Create Tierin Calendar" : "Use Tierin Calendar") {
                        integration.connectTierinCalendar(sourceID: sourceID)
                    }
                    .appGlassButton()
                    .disabled(sourceID.isEmpty || integration.busy)
                    Text("A dedicated Tierin calendar keeps your task deadlines together. An existing Tierin calendar in this account will be reused. Choose iCloud to share it across devices.")
                        .font(AppTypography.supporting).foregroundStyle(.secondary)
                    if integration.enabled {
                        Text("Currently syncing to \(integration.selectedCalendarName)")
                            .font(AppTypography.supporting).foregroundStyle(.secondary)
                    }
                } else {
                    Button("Connect Apple Calendar") { Task { await integration.requestAccess() } }
                        .appGlassButton().disabled(integration.busy)
                }
                Text("Dated tasks and subtasks become all-day events. Tierin updates their titles, descriptions, and dates, and removes linked events when you complete a task, remove its deadline, or delete it. Reopening a dated task restores its event. Calendar edits do not change your tasks.")
                    .font(AppTypography.supporting).foregroundStyle(.secondary)
            }
            AppSection("Sync status") {
                Text(integration.enabled ? "Sync enabled on this device" : "Not connected")
                    .font(AppTypography.itemTitle)
                if let date = integration.lastSync {
                    Text("Last synced \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(AppTypography.supporting).foregroundStyle(.secondary)
                }
                if let error = integration.error {
                    Text(error).font(AppTypography.supporting).foregroundStyle(.red)
                }
                if integration.busy { ProgressView() }
                if integration.enabled {
                    HStack {
                        Button("Sync Now", action: integration.syncNow).appGlassButton().disabled(integration.busy)
                        Button("Disconnect", action: integration.disconnect).appGlassButton()
                    }
                }
                Text("Sync runs while Tierin is open and when you return to it. Choose the same iCloud calendar on your Mac and iPhone to see events on both. Calendar permission and selection are saved separately on each device. Disconnecting leaves existing events in Calendar. Connection changes apply immediately.")
                    .font(AppTypography.supporting).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            integration.refreshCalendars()
            sourceID = integration.suggestedSourceID
        }
        .onChange(of: integration.authorized) { _, granted in
            if granted { sourceID = integration.suggestedSourceID }
        }
    }
}

/// The board shortcut opens the same configuration used in Profile.
struct CalendarDeadlineSheet: View {
    @Environment(\.dismiss) private var dismiss
    let task: BoardTask
    var onClose: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Apple Calendar").font(AppTypography.pageTitle)
                HStack {
                    AppGlassActionButton(symbol: .cancel, accessibilityLabel: "Close Calendar settings") {
                        if let onClose { onClose() } else { dismiss() }
                    }
                    Spacer()
                }
            }.padding(20)
            CalendarSettingsView()
        }.modifier(EditorSizing(width: 560, height: 640))
    }
}
