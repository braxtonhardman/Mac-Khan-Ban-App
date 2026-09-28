# Mac-Khan-Ban-App

ProjectBoard is a native SwiftUI personal project tracker for Mac and iPhone. SwiftData saves your work locally. Optional iCloud builds sync projects, areas, tasks, and profile settings through your private CloudKit database. There is no custom backend, app account, subscription, Docker service, or third-party dependency.

## Run

Requires macOS 14+ or iOS 17+, and Xcode 15+. Development validation uses Xcode 27.

Open `ProjectBoard.xcodeproj` and choose a scheme:

| Scheme | Destination | Storage |
| --- | --- | --- |
| ProjectBoard | My Mac | Local SwiftData |
| ProjectBoard iPhone | iPhone or iOS Simulator | Local SwiftData |
| ProjectBoard iCloud | My Mac | Local SwiftData + private iCloud sync |
| ProjectBoard iPhone iCloud | iPhone or iOS Simulator | Local SwiftData + private iCloud sync |

Press **Command-R**. Signing is configured for the repository owner's development team, `92F54J4WUJ`. Other developers should select their own team and provision their own identifiers.

Local Mac build without a developer account:

```sh
xcodebuild -project ProjectBoard.xcodeproj -scheme ProjectBoard -configuration Debug -derivedDataPath DerivedData CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build
open DerivedData/Build/Products/Debug/ProjectBoard.app
```

Local iPhone simulator build:

```sh
xcodebuild -project ProjectBoard.xcodeproj -scheme 'ProjectBoard iPhone' -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

## Projects and Areas

- Use **Create → New Project** at the top left (Shift-Command-N on Mac).
- Right-click an empty part of the sidebar and choose **New Area…**, or use **Create → New Area**. Areas group related projects, such as Work, Personal, or Learning.
- Right-click or long-press a project for **Move to Area**, or select its area in the project editor.
- Right-click or long-press an area heading to rename it, create a project there, or remove it. Removing an area keeps its projects and tasks in **Unassigned**.
- Click an area heading's chevron to collapse/expand it. Project rows show names only; project progress appears above the selected board.
- Area expansion preferences persist independently on each device.

## Tasks

- Select a project, then use **… → New Task** (Command-N on Mac) or a column's plus button.
- Click/tap a card to edit title, description, status, priority, due date, comma-separated tags, and checklist.
- Drag cards between Backlog, Planned, In Progress, Blocked, and Done. The card context menu also provides **Move To**.
- On iPhone, a column picker shows one column at a time; use the task editor or long-press **Move To** to change status.
- Right-click/long-press a task to delete it. Project deletion also deletes its tasks; both require confirmation.
- Progress is completed tasks divided by all tasks. Empty projects show 0%. Checklists do not independently affect progress.
- Edits remain drafts until Save; Cancel discards them.

## Profile & Settings

The top-right profile button opens shared board preferences:

- Rename all five stages. Names apply across projects and task status menus; the fifth stage still counts as completed work.
- Choose red, orange, yellow, green, teal, blue, purple, or pink as the app accent.
- Choose System, Light, or Dark appearance. Light and Dark override the device setting; System follows each device. The choice syncs with your profile.
- Create reusable tags in Profile → Tags. Task editors use searchable chips: type to find an existing tag or choose Create to add one. Tags already used on tasks appear automatically; capitalization and surrounding spaces do not create duplicates. Remove a chip to unassign it from that task.
- Save to apply changes, including newly created tags. Cancel discards draft changes. These preferences and the tag library persist in SwiftData and sync in iCloud builds.
- If two devices independently create a profile while offline, the newest saved profile is selected after sync; there is no database uniqueness constraint. Simultaneous edits remain subject to CloudKit merge behavior.
- Area collapse remains a local display preference.

## Apple Calendar deadlines

1. Set a task's due date and save it.
2. Right-click/long-press its card and choose **Add or Update Deadline in Calendar…**.
3. Choose Calendar, grant Calendar access if requested, select a writable calendar, and click **Add Event**.

This creates an all-day deadline event. Use the same action on the same device to update it after editing a task. Full Calendar access is required to choose a calendar and update an existing event; access is requested only by this explicit action.

Calendar integration is an explicit export/update, not automatic two-way sync. Deleting/completing a task or clearing its due date does not remove its Calendar event. Calendar edits do not change tasks. EventKit identifiers are stored locally per device; adding the same deadline from another device can create another event. Choose one device for managing each task's Calendar link. The selected calendar may itself sync through your Apple account.

## iCloud setup and behavior

CloudKit requires an active Apple Developer Program membership. Both targets use bundle identifier `com.braxtonhardman.ProjectBoard` and container `iCloud.com.braxtonhardman.ProjectBoard`.

1. In Xcode, choose your existing team under Signing & Capabilities. Enable automatic signing and allow Xcode to register your development devices when needed.
2. Verify that the same CloudKit container is available for both app targets. Cloud configurations include iCloud and push entitlements; iPhone also needs Remote notifications background mode.
3. Run the **iCloud** scheme on Mac and iPhone. Use the same iCloud account and the same CloudKit environment on both. Normal Debug schemes deliberately keep data local.
4. Open **Profile & Settings → Storage & Sync** inside the top-right profile button to check account status, recent CloudKit activity, and reported errors.
5. Create a project on one device, wait for sync, and verify it on the other. Edit a task and its status on the second device, then verify the change on the first. Repeat with an Area and a checklist.

CloudKit sync is asynchronous and may be delayed by connectivity, system scheduling, or account conditions. Local edits remain stored while offline. The app does not claim that all devices are up to date merely because a local save succeeded. Simultaneous edits to the same field follow the underlying SwiftData/CloudKit merge behavior; a checklist is a single persisted value rather than independently merged items.

Before distribution, deploy the development schema to Production in Apple's CloudKit Console and verify both devices against that environment. Development and Production databases are separate. Do not use this repository's default development signing as App Store distribution configuration.

Apple references: [SwiftData sync](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices), [CloudKit setup](https://developer.apple.com/documentation/cloudkit/enabling-cloudkit-in-your-app), [Calendar access](https://developer.apple.com/documentation/eventkit/accessing-the-event-store).

## Persistence and architecture

The app retains its original bundle identifier and default local SwiftData store. Upgrades preserve existing V1 projects; projects without an area appear under Unassigned. Tests create stores with frozen earlier model definitions and reopen them using the current schema to verify migration.

CloudKit-compatible models use default scalar values, optional relationships with inverses, and application-generated UUIDs without database uniqueness constraints. The default store is reused when switching to an iCloud build; existing local records become eligible for upload. Back up the app container before testing distribution builds or experimenting with iCloud accounts.

- `Sources/BoardCore`: status, priority, checklist, progress/tag rules, and deadline event mapping.
- `Sources/ProjectBoard/Models.swift`: SwiftData models, the `WorkspaceItem` name contract, and shared create/update saves with rollback.
- `WorkspaceItemEditor`: shared Project/Area name fields, validation display, Cancel/Save actions, and Mac/iPhone form layouts. Project-specific fields and Area name uniqueness stay in their own editors.
- Areas and Projects retain separate stored models and deletion rules: removing an Area preserves projects; removing a Project cascades to its tasks. This abstraction does not change the SwiftData or CloudKit schema.
- `Sources/ProjectBoard/CalendarIntegration.swift`: isolated EventKit integration.
- `Sources/ProjectBoard/SyncStatus.swift`: private CloudKit configuration and observable sync status.
- `Sources/ProjectBoard`: shared native UI with Mac/iPhone adaptations.
- `Tests/BoardCoreTests`: rules, DST-safe deadline mapping, persistence, area lifecycle, and migration tests. The production model file is symlinked into the test target.

```sh
swift test
```

Xcode compiles the core directly into both apps; Swift Package Manager builds it as a separate module. The optional package executable can use a different store because it is not bundled in the same sandbox. Use the Xcode app consistently for your real data.

## Next: GitHub integration

1. Add a `GitHubClient` protocol with a mock implementation; keep HTTP and authentication out of views and models.
2. Associate repository/issue/PR link records with stable local task UUIDs, with a tested schema upgrade.
3. Store opt-in credentials in Keychain. Start with read-only imports and status refresh while preserving offline use.
4. Add explicit push actions, conflict review, retries, and rate-limit tests before two-way GitHub sync.
5. Add JSON export/import, undo, manual card ordering, and broader UI automation.

## Validation notes

- Ten automated tests cover progress, tags, checklist encoding, DST-safe calendar dates, persistence, area lifecycle, upgrades from V1 and Areas schemas, profile validation, and profile persistence/offline duplicate selection.
- Mac UI smoke checks cover existing data after upgrade, Area creation/moving/collapse, and the simplified project-name sidebar.
- iCloud needs signed builds and an available Apple account. A successful build and account check do not establish that data has reached a second device.
- Real-device sync, Calendar event creation after permission, and distribution remain separate manual checks. Use your own Mac/iPhone with the same Apple account to complete the sync checklist above.
- Signed Mac and iPhone simulator builds pass. The Mac profile/settings and simplified sidebar were checked in the running app. The Mac reports an available iCloud account and starts CloudKit activity. Simulator installation stalled during runtime validation, so no iPhone runtime or two-device sync pass is claimed.

## Typography

`AppTypography.swift` defines the shared typography scale. Use roles consistently instead of assigning sizes per view. Native navigation bars, menus, alerts, and date pickers retain platform typography. All app text uses the system font and iPhone text scales with Dynamic Type.

| Role | Used for | Default Mac size |
| --- | --- | --- |
| Board title | Active project name | 22 pt bold |
| Page title | Workspace, sheet titles | 17 pt bold |
| Section heading | Areas, board stages, form sections | 15 pt semibold |
| Context title | Project name alongside a sheet title | 15 pt regular |
| Item title | Task names, emphasized values | 13 pt semibold |
| Body | Project rows, fields, actions | 13 pt regular |
| Supporting | Descriptions, tag chips | 12 pt regular |
| Caption | Dates, tags on cards, checklists, help text | 11 pt regular |

`AppSection` applies the section heading style to grouped forms. Icon-only controls have separate symbol sizes.
