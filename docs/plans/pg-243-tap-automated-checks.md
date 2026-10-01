# Automated coverage for PG-243's hand checks (M1–M5)

PG-243 shipped in PR #554 (`e5edd45`, in release 1.9.2 build 1480). Its plan,
`docs/plans/pg-243-reminder-notification-tap.md`, left seven hand checks (M1–M7). M1 passed by
hand on 2026-09-25. M2 could not be measured on a Debug build, because LaunchServices
cold-launched another worktree's build sharing `it.stefer.pergamenum.debug`.

This plan moves into the unit suite everything those checks verify below the banner. The
banner click itself belongs to Notification Center's process, so no test in this repo can
perform it.

No SPEC governs this task: the repo-root `SPEC.md` belongs to another chain. The requirement
ids below are this plan's own.

- **R-01** Delivering a classified tap reaches the route sink exactly once for `.open`, and
  never for `.noRoute`, `.unreadableRoute` or `.notDefaultAction`. A `nil` sink is a no-op.
  This covers M1 and M3, the glue PG-243 left untested on purpose.
- **R-02** The running app's notification delegate is a `ReminderScheduler`. M2 checks the
  wiring, though not the timing.
- **R-03** End to end through the payload the scheduler itself writes:
  - a tap that arrives before the vault opens is replayed, and the note opens (M2);
  - a tap after an in-app rename opens the renamed note (M4);
  - a board task's tap reaches the Workspace and opens no note tab (M5).

Read at `e8653dd` (`origin/main`). `Sources/Calendar/ReminderScheduler.swift` is unchanged
since `e5edd45`.

## ADR outcome: no ADR

**Reason:** this is test coverage plus one test seam on an existing type. No decision is
added or reversed. The seam is a default-valued init parameter, removable in one line.

## Tasks

### Task 1: the test seam on `ReminderScheduler` (R-01)

**File:** `Sources/Calendar/ReminderScheduler.swift`.

- `override init()` becomes `init(becomesDelegate: Bool = true)`:
  - it calls `super.init()`;
  - it sets `center.delegate = self` only when the flag is `true`.

  Its doc comment says the `false` form exists for the unit suite only. The reason: a
  scheduler built in a test must not take the host process's real delegate slot. The
  existing comment in `Tests/ReminderTapTests.swift:7-10` records that hazard.
- `private func deliver(_:)` becomes `func deliver(_:)` (internal). Add one comment naming
  `Tests/ReminderDeliveryTests.swift` as its reader, following ADR-0045's widening convention.
- `PergamenumApp.swift` keeps calling `ReminderScheduler()` and is not edited.

### Task 2: delivery tests (R-01)

**File:** `Tests/ReminderDeliveryTests.swift` (new). The type is `@MainActor`, and every scheduler
is built with `becomesDelegate: false`.

- **D1** `.open(.noteID(x))` calls `openRoute` once, with `.noteID(x)`. Record the calls in
  a local array captured by the closure.
- **D2** `.open(.canvas(path:nodeID:))` is passed through unchanged.
- **D3** `.noRoute`, `.unreadableRoute` and `.notDefaultAction` produce zero calls. Write this as a
  parameterised test.
- **D4** `.open` with `openRoute == nil` returns and does not trap.
- **D5** The seam's own guard: building `ReminderScheduler(becomesDelegate: false)` leaves
  `UNUserNotificationCenter.current().delegate` identical (`===`) to what it was before.

### Task 3: the host's delegate is the scheduler (R-02)

**File:** `Tests/ReminderDeliveryTests.swift`.

- **H1** `UNUserNotificationCenter.current().delegate is ReminderScheduler` inside the
  unit-test host.
- **Check first, then decide.** The unit target depends on the app target (`Project.swift`,
  `PergamenumTests`), so the host is expected to run `PergamenumApp.init`. Run H1 once,
  alone. If the host never runs it (the delegate is `nil`), **drop H1**, write in the report why
  it was dropped, and leave R-02 to the release hand check. A test that only passes when run
  alongside others is not acceptable.

### Task 4: payload-to-route chains (R-03)

**File:** `Tests/ReminderTapChainTests.swift` (new). Use the `TemporaryVault`,
`VaultController(recents: .volatile(), openTabs: .volatile())` and `.volatile()` stores, as in
`Tests/PendingRouteTests.swift` and `Tests/NoteIDRouteTests.swift`. Classify through
`ReminderScheduler.tap(actionIdentifier: UNNotificationDefaultActionIdentifier, userInfo:)` and
hand the route to `controller.handle(_:)`. The scheduler's own `deliver`/sink are what Task 2
covers; here the sink is the controller directly.

- **C1 (M2)** Controller A opens a vault with a `@remind` task in `b.md`, mints the id, builds
  the request with `ReminderScheduler.requests(for:after:noteIDs:)`, and closes. Controller B
  has not opened yet. Classify the request's `content.userInfo`:
  1. `handle` returns `false`, and the route is pending;
  2. after `await open(root)`, `openNote?.relativePath == "b.md"`.
- **C2 (M4)** Build the request with the minted id. Then `renameNote(at: "b.md", to: "B
  rinominata")` and `rescan()`. Classifying and handling the request opens
  `B rinominata.md`. Scheduling before the rename is the point of the test: the payload was
  written while the old name was current.
- **C3 (M5)** Add a task whose `sourcePath` is `Area/Area.canvas`, with a `nodeID`. Its
  request, classified and handled, does three things:
  - `handle` returns `true`;
  - `consumePendingCanvasRoute()` gives that path and that node id;
  - `openNote` stays `nil`, and no tab shows the `.canvas` file.

  The board fixture is the one `Tests/URLSchemeTests.swift:theCanvasRouteIsHandedToTheWorkspace`
  uses.

### Task 5: verify

1. `tuist generate --no-open`, because two new test files match the `Tests/**` glob.
2. Run the full `PergamenumTests` suite with the TEST-CMD below.
3. Run SwiftLint on the touched files.

## What stays manual, and why

Record these on PG-243 when the work ships:

- **The banner click with the app closed.** This includes F4: is the delegate set before
  launch finishes? Only a real launch from Notification Center exercises it.
- **M6, window closed.** AppKit window state. F9 is a known gap that predates this work.
- **M7, another app in front.** System activation behaviour.

PG-270 is out of scope. A test written for it would be red until the gap is fixed, so it
belongs with that fix.

## Risks

- **H1 depends on how the test host launches.** Task 3's "check first" rule covers this.
- **Isolation of the sink closure.** `openRoute` is `@MainActor ... async`. The recording
  array in D1–D4 is mutated inside it, so the test type must be `@MainActor` too.

## TEST-CMD

`TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test`
`TEST-CMD MODE: brownfield`
