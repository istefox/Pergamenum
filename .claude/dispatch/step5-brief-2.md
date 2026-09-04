<!-- step5-brief: plan=/Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md tasks=3,4,5 lines=172-256 -->
# Step 5 Batch Brief -- 2026-09-04-sparkle-auto-update-integration.md -- tasks 3-5

## Task text (verbatim, plan lines 172-256)

### Task 3 — the updater controller: allocated in `init`, started from the window, absent under `-disableUpdater` (R-02, R-03)

- Budget: `Sources/App/SparkleUpdateController.swift` (new),
  `Sources/App/PergamenumApp.swift`, `Tests/SparkleUpdateControllerTests.swift` (new)
  (~200 lines)
- **Tester first.** Declaration + tests. The class:
  `@MainActor @Observable final class SparkleUpdateController` holding an
  `SPUStandardUpdaterController` built with `startingUpdater: false, updaterDelegate: nil,
  userDriverDelegate: nil`, plus `private(set) var canCheckForUpdates = false`,
  `private let isIsolated = UserDefaults.standard.bool(forKey: "disableUpdater")`,
  `func start()`, `func checkForUpdates()`, and a stored `NSKeyValueObservation?`.
- **Do not instantiate `SPUStandardUpdaterController` in a unit test.** `startUpdater` can put a
  modal alert on screen; a modal alert in the unit suite is a hang, and the suite runs at the end
  of every turn. The tests assert only what can be asserted without it: that `isIsolated` reads
  the `disableUpdater` default (set it in a `UserDefaults` suite in the test and read it back
  through the same key), and that `start()` is a no-op when isolated. If a test cannot be written
  without constructing the Sparkle object, **do not write it** — R-02 and R-08's real coverage is
  Task 4's UI test and Task 10's hand check. Say so in the test file's header comment rather than
  leaving a gap nobody can see.
- **Coder** fills the bodies:
  - `start()` returns immediately when `isIsolated`; otherwise `controller.startUpdater()` and
    installs the KVO observation:
    `controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] u, _ in MainActor.assumeIsolated { self?.canCheckForUpdates = u.canCheckForUpdates } }`.
    **Store the returned token** — KVO stops the instant it is discarded, silently.
    `MainActor.assumeIsolated` and not a `Task { @MainActor in … }`: Sparkle posts this on the
    main thread and a hop would make the menu item lag its own state (ADR §D5).
  - `checkForUpdates()` → `controller.updater.checkForUpdates()`.
  - `PergamenumApp`: `@State private var updater = SparkleUpdateController()` (a plain inline
    default — nothing in `init` needs it, unlike `navigation`/`history`), and `updater.start()`
    added to `armCapture()` (`:125-130`), which is where the hot key is registered and where the
    file's own comment says NSApp-adjacent work belongs. **Not in `init()`** (ADR §D3).
- Green: `.claude/test-cmd`. Then launch a Debug build by hand once
  (`APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/Pergamenum-*/Build/Products/Debug/Pergamenum.app | head -1); open -n "$APP" --args -recentVaults '("/tmp/throwaway")'`)
  and confirm no alert appears at launch. Use `-t` on the `ls`, or you get a stale build.

### Task 4 — «Cerca Aggiornamenti…» in the Pergamenum menu, beside «Informazioni su Pergamenum» (R-02)

- Budget: `Sources/App/MenuCommands.swift`, `Sources/App/PergamenumApp.swift`,
  `UITests/UpdateMenuUITests.swift` (new) (~120 lines)
- **Tester first.** `UITests/UpdateMenuUITests.swift`, XCTest (the UI bundle stays XCTest), which
  launches with **both** `-disableCalendar YES` **and** `-disableUpdater YES`, opens the
  `Pergamenum` app menu and asserts a menu item titled «Cerca Aggiornamenti…» exists.
  **It never clicks it** — a click is a real network fetch and, under `-disableUpdater`, a
  no-op that proves nothing. R-02's "triggers Sparkle's standard update-check UI" half is
  verified by hand in Task 10; say so in the test's header.
- This is the one place in the repo where finding a control by its title is correct rather than
  forbidden: CLAUDE.md's rule is about *app-authored* controls, and a `CommandGroup` button has no
  `accessibilityIdentifier` surface. The title is the contract here.
- **Coder:** a new `struct UpdateCommands: Commands` in `Sources/App/MenuCommands.swift`
  (the file that already holds `ViewCommands`, `EditCommands`, `HelpCommands`):

  ```
  CommandGroup(after: .appInfo) {
      Button("Cerca Aggiornamenti…") { updater.checkForUpdates() }
          .disabled(!updater.canCheckForUpdates)
  }
  ```

  `after: .appInfo` is Sparkle's own documented placement and is the standard macOS location.
  **No `import Sparkle` in this file** — it speaks to `SparkleUpdateController` only (ADR §D2).
  **No `ShortcutCommand` case and no key binding**: ADR-0023 §D5's precedent — the catalogue is
  the set of rebindable shortcuts, not all commands, and this one never had a key.
- Register it in `PergamenumApp`'s `.commands` block (`:196-215`), after `HelpCommands`.
- Green: `.claude/test-cmd` (unaffected) plus this one UI test run in isolation:
  `scripts/uitests.sh PergamenumUITests/UpdateMenuUITests` — remember an argument **replaces**
  the selection.

### Task 5 — every UI-test file keeps the updater out of its launch (R-02, R-03)

- Budget: all 18 files under `UITests/` (~40 lines)
- Add `-disableUpdater YES` to every `XCUIApplication().launchArguments`, beside the
  `-disableCalendar YES` that is already in all eighteen. **All of them, not only the ones that
  would notice** — the same rule CLAUDE.md states for the calendar flag, bought the hard way.
- No new test. This is the prophylactic against the failure mode ADR §D4 describes: an updater
  that starts on every launch, before any appcast exists, putting an alert on screen and turning
  a whole run into 60.2 s launch timeouts that look like defects and are not.
- Green: `scripts/uitests.sh` with **no argument**, the full bundle, once. Read the per-test
  seconds it prints beside any failure before believing it, and kill stale instances first
  (`ps -Ao pid,command | grep Pergamenum.app/Contents/MacOS`) — the script does this itself, but
  a red run with stale instances alive is not evidence.

---

## Phase 2 — the release path (no app file is touched again)

## File map (from Budget: declarations, tasks 3-5)

- all 18 files under UITests/

No parseable Budget: for task(s): 3 4 (absent is not zero -- consult the task text above)

## Excluded tasks (not in this batch)

- Task 1 -- see /Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md
- Task 2 -- see /Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md
- Task 6 -- see /Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md
- Task 7 -- see /Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md
- Task 8 -- see /Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md
- Task 9 -- see /Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md
- Task 10 -- see /Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md

Full plan: /Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md

## Context documents (open only for the reason stated -- not read unconditionally)

- ADR: /Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/docs/adr/0031-sparkle-auto-update-integration.md -- D3 (startingUpdater false, started from armCapture), D4 (-disableUpdater launch argument, all 18 UI-test files), D5 (@Observable + one NSKeyValueObservation, no Combine), D7 (no timer, no automaticallyChecksForUpdates write)
- SPEC: /Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/SPEC.md -- requirement IDs R-02, R-03 for this batch's tests
- CLAUDE.md: /Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/CLAUDE.md -- working agreements on UI tests (-disableCalendar precedent, accessibilityIdentifier rule and its one exception here, uitests.sh argument semantics, stale instances)
