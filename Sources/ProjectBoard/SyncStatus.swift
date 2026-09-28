import SwiftUI
import CloudKit
import CoreData

@MainActor
final class SyncStatus: ObservableObject {
    static let shared = SyncStatus()
    static let containerIdentifier = "iCloud.com.braxtonhardman.ProjectBoard"
    static var isCloudBuild: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "ProjectBoardCloudEnabled") as? String) == "YES"
        || (Bundle.main.object(forInfoDictionaryKey: "ProjectBoardCloudEnabled") as? Bool) == true
    }
    @Published var account = "Checking iCloud…"
    @Published var activity = "Waiting for iCloud activity."
    @Published var lastTransfer: Date?
    private var observer: NSObjectProtocol?

    init() {
        guard Self.isCloudBuild else {
            account = "Local storage"
            activity = "This build saves on this device. Use an iCloud scheme in Xcode to enable sync."
            return
        }
        observer = NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else { return }
            Task { @MainActor in
                guard let self else { return }
                if let error = event.error {
                    self.activity = "iCloud reported: \(error.localizedDescription)"
                } else if event.endDate == nil {
                    self.activity = "Syncing with iCloud…"
                } else if event.succeeded {
                    self.activity = "Last iCloud operation completed. Updates may take a moment to appear on other devices."
                    if event.type == .import || event.type == .export { self.lastTransfer = event.endDate }
                }
            }
        }
        Task { await refreshAccount() }
    }
    func refreshAccount() async {
        guard Self.isCloudBuild else { return }
        do {
            switch try await CKContainer(identifier: Self.containerIdentifier).accountStatus() {
            case .available: account = "iCloud account available"
            case .noAccount: account = "Sign in to iCloud in Settings to sync."
            case .restricted: account = "iCloud is restricted on this device."
            case .temporarilyUnavailable: account = "iCloud is temporarily unavailable. Local edits remain saved."
            default: account = "iCloud account status is unavailable."
            }
        } catch { account = error.localizedDescription }
    }
}

struct SyncStatusView: View {
    @EnvironmentObject private var status: SyncStatus
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Storage & Sync", systemImage: "icloud").font(AppTypography.pageTitle)
            Text(status.account).font(AppTypography.itemTitle)
            Text(status.activity).foregroundStyle(.secondary)
            if let date = status.lastTransfer {
                Text("Last transfer: \(date.formatted())").font(AppTypography.caption)
            }
            Text("Use the same iCloud account and app environment on Mac and iPhone. Projects, areas, tasks, and profile settings sync automatically in iCloud builds. Layout preferences and Calendar event links stay on each device.")
                .font(AppTypography.supporting)
            HStack {
                if SyncStatus.isCloudBuild {
                    Button("Check Account") { Task { await status.refreshAccount() } }
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).modifier(EditorSizing(width: 470))
    }
}
