# Mac-Khan-Ban-App

ProjectBoard is a lightweight native macOS Kanban app for personal projects. Free to run locally, with no accounts, backend, subscriptions, or collaboration services. SwiftData stores your projects on your Mac. No Docker or SQL server is needed.

## Run

Requires macOS 14 or newer and Xcode 15 or newer. Development validation uses Xcode 27.

1. Open `ProjectBoard.xcodeproj` in Xcode.
2. Select the **ProjectBoard** scheme and **My Mac** destination.
3. Press **Command-R**. If Xcode requests signing, select your personal development team in Signing & Capabilities. No paid service is required for local development.

You can also build without a signing team:

```sh
xcodebuild -project ProjectBoard.xcodeproj -scheme ProjectBoard -configuration Debug -derivedDataPath DerivedData CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build
open DerivedData/Build/Products/Debug/ProjectBoard.app
```

## Use

- Create a project from the sidebar toolbar (**Shift-Command-N**).
- Select a project and add tasks with **Command-N**, or use a column's plus button.
- Click a card to edit its title, description, status, priority, due date, comma-separated tags, and checklist.
- Drag cards between Backlog, Planned, In Progress, Blocked, and Done. The card context menu also provides **Move To**.
- Right-click a task to delete it. Edit or delete a project with its toolbar menu or sidebar context menu. Deletions require confirmation; deleting a project also deletes its tasks.
- Project progress is completed tasks divided by all tasks. Empty projects show 0%. Checklists do not independently affect project progress.
- Edits are drafts until Save; Cancel discards them. The board scrolls horizontally in smaller windows.

## Data

The app uses the default local SwiftData store within its macOS app sandbox (`com.braxtonhardman.ProjectBoard`). It never connects to GitHub or any network service. Relaunching preserves saved changes. Save errors are shown and failed changes are rolled back; the app never silently resets an unreadable database.

Use the Xcode-built app consistently: the optional Swift package executable can use a different storage location because it is not bundled in the same sandbox. Back up the app container with your normal Mac backups. V1 has no export, sync, undo, or manual card ordering.

## Structure and tests

- `Sources/BoardCore`: portable status, priority, checklist, progress, and tag rules.
- `Sources/ProjectBoard/Models.swift`: SwiftData models and explicit save handling. Stable UUIDs identify projects and tasks.
- `Sources/ProjectBoard`: native NavigationSplitView, board, cards, and draft editors.
- `Tests/BoardCoreTests`: rule tests plus a temporary on-disk SwiftData round trip, field persistence, status change, and cascade deletion test. The model source is symlinked into this test target so tests exercise the production schema.

```sh
swift test
```

The Xcode app compiles the shared core directly; Swift Package Manager builds it as a separate module. There are no external dependencies.

## V2 roadmap: optional GitHub integration

1. Add a separate integration layer with a `GitHubClient` protocol and mock implementation, keeping HTTP and authentication out of views and SwiftData models.
2. Add explicit repository/issue/PR link records associated with stable local task UUIDs; introduce a versioned SwiftData schema and migration before changing persisted models.
3. Store opt-in credentials in macOS Keychain. Start with read-only issue/PR import and status refresh; preserve offline use.
4. Add explicit push actions, conflict review, rate-limit handling, retry tracking, and tests using API fixtures before any two-way sync.
5. Add JSON export/import and UI automation coverage.

## V1 validation

Validated on Apple Silicon with Xcode 27:

- Native Xcode Debug app build succeeded with local signing.
- All four automated tests passed, including on-disk persistence and cascade deletion.
- Interactive smoke check passed: app launch, project creation, task creation with description/tags/checklist, and dragging a card from Backlog to Planned.
- Full UI automation and distribution/notarization are not included in V1.
