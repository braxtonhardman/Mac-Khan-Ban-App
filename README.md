# Tierin

Tierin is a native SwiftUI personal project tracker for Mac and iPhone. SwiftData saves your work locally. Optional iCloud builds sync projects, areas, tasks, and profile settings through your private CloudKit database. There is no custom backend, Docker service, or third-party dependency. The free plan allows 3 projects and 1 area; an optional monthly Tierin Unlimited subscription removes those limits. Tasks and subtasks are unlimited on both plans.

## Run

Requires macOS 14+ or iOS 17+, and Xcode 27+ to build the native Icon Composer assets.

Open `ProjectBoard.xcodeproj` and choose a scheme. All schemes produce **Tierin.app**; the existing project and scheme names are retained for development:

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
open DerivedData/Build/Products/Debug/Tierin.app
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
- Click/tap a card to edit title, description, status, priority, due date, tags, and subtasks.
- Subtasks are full child tasks with their own status, priority, description, due date, and tags. Open a parent task and choose **Add Subtask** to reuse the task editor. Select a subtask row to edit it, or use its circular completion control for a quick status change.
- Drag cards between Backlog, Planned, In Progress, and Done. The card context menu also provides **Move To**.
- On iPhone, a column picker shows one column at a time; use the task editor or long-press **Move To** to change status.
- Right-click/long-press a task to delete it. Project deletion also deletes its tasks; both require confirmation.
- Project progress is completed top-level tasks divided by all top-level tasks. Subtask progress appears on the parent card and inside its editor; completing a child does not automatically complete its parent.
- Edits remain drafts until Save; Cancel discards them.

## Profile & Settings

The top-right profile button opens shared board preferences:

- The settings landing page groups profile and storage status, future account integrations, and general preferences. GitHub and OpenAI/ChatGPT appear as clearly marked, inactive connection placeholders until authentication is implemented.
- Rename all four stages. Names apply across projects and task status menus; the fourth stage still counts as completed work. Existing Blocked tasks appear in In Progress, and custom names for the remaining stages are preserved.
- Choose red, orange, yellow, green, teal, blue, purple, or pink as the app accent.
- Choose System, Light, or Dark appearance. Light and Dark override the device setting; System follows each device. The choice syncs with your profile.
- Create reusable tags in Profile → Tags. Task editors use searchable chips: type to find an existing tag or choose Create to add one. Tags already used on tasks appear automatically; capitalization and surrounding spaces do not create duplicates. Remove a chip to unassign it from that task.
- Save to apply changes, including newly created tags. Cancel discards draft changes. These preferences and the tag library persist in SwiftData and sync in iCloud builds.
- If two devices independently create a profile while offline, the newest saved profile is selected after sync; there is no database uniqueness constraint. Simultaneous edits remain subject to CloudKit merge behavior.
- Area collapse remains a local display preference.

## Apple Calendar deadlines

1. Open **Profile → Apple Calendar** on Mac or iPhone.
2. Choose **Connect Apple Calendar** and grant full Calendar access.
3. Select the Calendar account (choose iCloud for cross-device sharing), then choose **Create Tierin Calendar**. Tierin creates its own named calendar, or reuses an existing Tierin calendar in that account, and enables sync.
4. Save a due date on a task or subtask. Tierin creates an all-day event and updates its title, description, project name, and date when those change.

Sync runs while Tierin is open and resumes when it returns to the foreground. Removing a due date or deleting a linked task removes its event. Moving a task or subtask to Done removes its deadline event; reopening it with a due date restores the event. Connecting the dedicated Tierin calendar moves previously linked events into that destination. Unrelated events stay in their original calendars. **Sync Now** retries immediately; permission and calendar errors appear in the same settings page.

This is one-way sync from Tierin to Apple Calendar. Editing events in Calendar does not update tasks. Calendar access and the destination choice are local to each device; choose the same iCloud calendar on Mac and iPhone for a shared destination. Task links include a shared event identifier and task URL so another device can reuse an existing event. Concurrent offline creation can temporarily produce duplicates, which Tierin reconciles when both copies become visible.

Disconnect pauses sync on this device and leaves existing events in Calendar. Calendar settings take effect immediately. Only events linked to Tierin tasks are managed; unrelated and recurring events are left alone.

## iCloud setup and behavior

CloudKit requires an active Apple Developer Program membership. Both targets use bundle identifier `com.braxtonhardman.Tierin` and container `iCloud.com.braxtonhardman.ProjectBoard`.

1. In Xcode, choose your existing team under Signing & Capabilities. Enable automatic signing and allow Xcode to register your development devices when needed.
2. Verify that the same CloudKit container is available for both app targets. Cloud configurations include iCloud and push entitlements; iPhone also needs Remote notifications background mode.
3. Run the **iCloud** scheme on Mac and iPhone. Use the same iCloud account and the same CloudKit environment on both. Normal Debug schemes deliberately keep data local.
4. Open **Profile & Settings → Storage & Sync** inside the top-right profile button to check account status, recent CloudKit activity, and reported errors.
5. Create a project on one device, wait for sync, and verify it on the other. Edit a task and its status on the second device, then verify the change on the first. Repeat with an Area and a subtask.

CloudKit sync is asynchronous and may be delayed by connectivity, system scheduling, or account conditions. Local edits remain stored while offline. The app does not claim that all devices are up to date merely because a local save succeeded. Simultaneous edits to the same field follow the underlying SwiftData/CloudKit merge behavior; a checklist is a single persisted value rather than independently merged items.

Before distribution, deploy the development schema to Production in Apple's CloudKit Console and verify both devices against that environment. Development and Production databases are separate. Do not use this repository's default development signing as App Store distribution configuration.

Apple references: [SwiftData sync](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices), [CloudKit setup](https://developer.apple.com/documentation/cloudkit/enabling-cloudkit-in-your-app), [Calendar access](https://developer.apple.com/documentation/eventkit/accessing-the-event-store).

## Persistence and architecture

Tierin now uses bundle identifier `com.braxtonhardman.Tierin`. The original CloudKit container `iCloud.com.braxtonhardman.ProjectBoard` and model module names remain unchanged to preserve stored data. New calendar links use `tierin://task/<UUID>`. Earlier `projectboard://` links still open tasks, and automatic Calendar sync updates linked events to the Tierin scheme in place. The new bundle identifier creates a separate installation and sandbox: local-only data and sign-in preferences are not automatically transferred from the old app. Keep the old installation until its data has synced and you have verified the new installation. Sign in again with Apple and use the same iCloud account and CloudKit environment to retrieve cloud data. Upgrades preserve existing V1 projects; projects without an area appear under Unassigned. Original checklist rows are converted into full child tasks at startup. Tests create stores with frozen earlier model definitions and reopen them using the current schema to verify migration.

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

## Next: account integrations

1. Add a `GitHubClient` protocol with a mock implementation; keep HTTP and authentication out of views and models.
2. Associate repository/issue/PR link records with stable local task UUIDs, with a tested schema upgrade.
3. Store opt-in credentials in Keychain. Start with read-only imports and status refresh while preserving offline use.
4. Add explicit push actions, conflict review, retries, and rate-limit tests before two-way GitHub sync.
5. Define an `OpenAIClient` boundary and explicit user-controlled project context before enabling ChatGPT-assisted planning. Keep provider credentials in Keychain and out of SwiftData and CloudKit.
6. Add JSON export/import, undo, manual card ordering, and broader UI automation.

## Validation notes

- Fifteen automated tests cover progress, tags, legacy checklist migration and sync reconciliation, child-task drafts and persistence, DST-safe calendar dates, persistence, area lifecycle, upgrades from V1 and Areas schemas, profile validation, and profile persistence/offline duplicate selection.
- Mac UI smoke checks cover existing data after upgrade, Area creation/moving/collapse, and the simplified project-name sidebar.
- iCloud needs signed builds and an available Apple account. A successful build and account check do not establish that data has reached a second device.
- Real-device sync, Calendar event creation after permission, and distribution remain separate manual checks. Use your own Mac/iPhone with the same Apple account to complete the sync checklist above.
- Signed Mac and physical-iPhone builds pass. The redesigned profile/settings flow was checked in the running Mac app, and the current iPhone build was installed and launched on the connected device.

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

## App branding

The app uses the stacked project-board symbol in `Design/WorkspaceMark.svg`.
Light appearance is blue on white; dark appearance is white on blue. The shared
`WorkspaceMark` view follows the app's System/Light/Dark preference on welcome and
sign-in screens. Installed icons follow the device's icon appearance settings.

`WorkspaceIcon.icon` is the Icon Composer source included in both Xcode targets.
It contains explicit default and dark variants; Xcode also generates compatibility
icons for supported older systems. `Assets.xcassets/AppIcon.appiconset` contains
standalone raster exports for tooling that does not use Icon Composer.

After changing the source vector, regenerate its SwiftUI geometry, native icon
package, and PNG/SVG exports on a Mac with Xcode:

```sh
python3 Design/generate_brand_assets.py
```

The app's interactive accent color remains a separate profile preference.


## Tierin Unlimited monthly subscription

- Free: 3 projects and 1 named area across the whole workspace. Unassigned is a virtual group and does not count as an area.
- Unlimited: unlimited projects and areas for the duration of the monthly subscription. Tasks, subtasks, editing, viewing, deleting, calendar export, and iCloud sync are not paywalled.
- Creating a fourth project or second area opens the paywall. The shared persistence writer rechecks counts immediately before insertion, including records that arrived while an editor was open.
- Existing data over the limits remains accessible after an upgrade, expiry, refund, or restore failure. No projects or areas are deleted or hidden. Deleting items frees quota.
- Counts use the local SwiftData replica. Two offline devices may temporarily exceed the limits before iCloud merges their changes. The merged records remain accessible; further creation is blocked. A globally atomic quota would require a coordinating backend.
- Ownership uses verified StoreKit 2 entitlements, not an editable SwiftData profile flag. Current entitlements are checked on launch, foreground, transaction updates, and every minute while the root view is alive. StoreKit maintains its local transaction cache for offline access.
- Cancelling renewal keeps access until the paid period ends; expired/refunded access reverts to Free creation limits. Billing grace periods follow StoreKit current entitlements.
- **Profile → Plan** opens Upgrade, Restore Purchases, and Manage Subscription. The subscription belongs to the App Store account, which can differ from the account used for Sign in with Apple or iCloud.

### App Store Connect setup required before real purchases

1. Add Mac and iOS to the same app record/universal purchase using the existing bundle ID. Use one subscription group named **Tierin Unlimited**.
2. Add an **auto-renewable subscription** with product ID `com.braxtonhardman.Tierin.unlimited.monthly`, duration **1 month**, and display name **Tierin Unlimited Monthly**.
3. Choose the supported US storefront price closest to **US$2/month**. The local test configuration uses **$1.99/month** as a test price only; it does not configure App Store Connect. The live paywall always uses Apple's localized `Product.displayPrice`. Sales tax may be additional; the app does not promise $2 including tax.
4. Complete the paid-app agreement, banking/tax setup, product availability, localization, review screenshot, and review submission. Configure both platforms under the same subscription to restore on Mac and iPhone.
5. Publish a Privacy Policy URL and supply it in App Store Connect and the app before submission. The app currently contains a readable in-app privacy disclosure and links Apple's standard Terms of Use; a public privacy-policy URL is still required for distribution.
6. Test on sandbox accounts/TestFlight: new subscription, cancellation, renewal, expiration, billing retry/grace period, refund/revocation, reinstall/restore, and restoration on the other platform.

Real product setup and App Review approval are external to this repository. If Apple returns no matching monthly subscription, the paywall shows Purchase unavailable and offers retry/restore; no fake price or local flag grants access.

### Local testing

Run **Tierin StoreKit Mac** or **Tierin StoreKit iPhone** from Xcode to use `Tierin.storekit`. These are dedicated local-payment test schemes; the normal schemes keep StoreKit configuration off. Local StoreKit transactions are simulated and do not charge an account or transfer to another device. Use a disposable simulator/test workspace when testing limits.

Use Xcode's **Debug → StoreKit → Manage Transactions** to test subscription renewal, expiration, refund, and interrupted/pending purchases. Automated `swift test` coverage includes quota boundaries, stale editor counts, deletion freeing capacity, editing over-limit data, success, cancellation, pending approval, errors, missing products, restore, and entitlement updates. The state tests use an injected StoreKit boundary; they do not replace sandbox purchase validation.
