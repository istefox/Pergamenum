# Fix: tapping a `@remind` notification opens the note it came from (PG-243)

No `SPEC.md` governs this task. The repo-root `SPEC.md` belongs to #511, which has already
shipped, and is not this chain's input. The approved brief is the specification, and it
declares four requirement ids:

- **R-01** Tapping a delivered `@remind` notification (default action) passes its
  `userInfo["route"]` to `VaultController.handle(_:)`, so the note opens through the id
  route, with the path route as the fallback.
- **R-02** A tap from a cold launch works. If the vault is not open yet, the route waits in
  `routeState.pending` and is replayed.
- **R-03** A notification with no route (the «Invia una notifica di prova» test notification,
  identifier prefix `pergamenum.test.`) or with an unparsable route opens nothing, does not
  crash, and leaves only a log line.
- **R-04** Extracting the route from `userInfo` is a pure function, unit-tested without
  `UNUserNotificationCenter`.

SPEC §7.1 and §13 (M6) require local notifications for `@remind` and say nothing about the
tap. The intent is recorded only in code, at `ReminderScheduler.swift:180-181` ("so tapping
the notification opens the note it came from"). There is no SPEC conflict.

The plan was read at `da086cd` (`main`, clean tree). Every line number below was checked
against that tree.

## ADR outcome: no ADR

**Reason:** the tap reuses the app's one route door, `VaultController.handle(_:)`, whose id
route ADR-0059 §D7 governs and this chain leaves unchanged. It also reuses the
closure-wiring pattern `PergamenumApp.init` already uses for `vault.didChangeExternally`,
`didRelocateFolders` and `MenuBarItem`. Each decision below can be reversed in a few lines,
so the "hard to reverse" gate fails.

The overrides were checked and none applies:

- There is no security or compliance boundary, and no on-disk format change.
- The one non-obvious constraint, that the notification delegate must exist before launch
  finishes, is written as a comment at the construction site (Task 4). A launch log line
  (Task 4) makes it observable, so it does not stay invisible in the code.
- The one "don't" a reader might undo, routing the tap through `AppDelegate.vault`, is
  explained in that same comment.

## What the code says (facts, with sources)

| # | Finding | Source |
|---|---|---|
| F1 | `ReminderScheduler` is the notification delegate but implements only `willPresent`. Nothing in `Sources/` reads `userInfo["route"]`. | `Sources/Calendar/ReminderScheduler.swift:19-35`; `rg userInfo Sources` |
| F2 | The delegate is assigned in `ReminderScheduler.init`, and the scheduler is built as an inline `@State` default, which runs during `PergamenumApp.init`. | `ReminderScheduler.swift:21`, `PergamenumApp.swift:85` |
| F3 | Apple's rule for delegate timing. The macOS 27 SDK header says: *"The delegate must be set before the application returns from application:didFinishLaunchingWithOptions:."* Apple's protocol page says: *"before your app finishes launching … Assigning a delegate after the system calls these methods might cause you to miss incoming notifications."* | `MacOSX27.0.sdk/.../UNUserNotificationCenter.h:99`; developer.apple.com, `UNUserNotificationCenterDelegate` (read 2026-09-25) |
| F4 | Apple does **not** document whether `App.init` runs before AppKit's launch callbacks. The page for `App.main()` says only "Initializes and runs the app". What the code structure shows instead: `AppDelegate` comes from `@NSApplicationDelegateAdaptor`, a stored property of `PergamenumApp`. SwiftUI can forward `applicationWillFinishLaunching` and `applicationDidFinishLaunching` to it only after `PergamenumApp.init` has returned, and that init initialises every stored property, `reminders` included. **This is an inference, not a documented guarantee.** Task 4 logs it on every launch and M2 checks it. | `PergamenumApp.swift:67`; developer.apple.com, `App/main()` |
| F5 | Isolation facts. The SDK header has no isolation macro on the protocol, and `UserNotifications.apinotes` adds none. The target is `SWIFT_VERSION 6.0`, with no default actor isolation and no `NonisolatedNonsendingByDefault`. So a `nonisolated async` witness runs on the generic executor, not the main actor. `UNNotificationResponse` carries no Sendable annotation. | SDK headers; `Project.swift:20` |
| F6 | `appDelegate.vault` is assigned only in the window's `.onAppear`. A cold-launch tap routed through `AppDelegate` can arrive while it is still `nil`, and the route is lost. | `PergamenumApp.swift:253-256` |
| F7 | There is a window during vault opening where a route does not wait. `store` becomes non-nil at `session = newSession`. Then come `await rescan()`, then `restoreTabs()` (which is guarded on `tabs.isEmpty`), then the pending replay. A route that lands during the rescan opens its note through `show()`, and `show()` calls `rememberTabs()`, which overwrites the saved tab session. `restoreTabs()` then bails out. This already happens today for every route. A cold-launch tap is the likeliest trigger. | `VaultController.swift:209, 223, 225, 228-231`; `VaultController+Session.swift:35`; `VaultController+Tabs.swift:135` |
| F8 | Tasks from boards are scheduled too. `mintNoteID` refuses any path that is not `.md`, so such a task gets `note?file=<board>.canvas`. `NoteStore.read` has no extension check, so a tap would open the board's JSON as a note tab. A `.canvas` route already exists and works end to end: it switches the pane and opens the board. | `IndexSnapshot.swift:168-178`; `VaultSession+NoteIDs.swift:56`; `ReminderScheduler.swift:184-185`; `NoteStore.swift:96-110`; `VaultController+Routes.swift:52-54`; `RootView.swift:125-129`; `WorkspaceView.swift:107-108` |
| F9 | No route brings a closed window back. `rg "activate\(\|orderFront\|openWindow" Sources/App` finds nothing. `MenuBarItem`'s comment claims that routes "know how to" raise the window, and no code does it. This predates this chain. | `PergamenumApp.swift:188-190` |

## Design (one approach, with reasons)

**Where the tap is wired: a sink closure on `ReminderScheduler`, set in `PergamenumApp.init`.**

- The init sets `reminders.openRoute = { route in await vault.handle(route) }`, where
  `vault` is the local that init stores in `_vault`. This is the same object `menuBarItem`'s
  closures capture.
- The capture is strong, and there is no retain cycle, because `VaultController` holds no
  reference to the scheduler.

Three alternatives were rejected:

- *Through `AppDelegate.vault`* (the `application(_:open:)` path): F6 rules it out. On cold
  launch the property is still `nil` when the tap arrives.
- *Move the delegate into `AppDelegate.applicationWillFinishLaunching`*: this is Apple's
  textbook location, but it has the same `nil`-vault problem. It would also split
  `willPresent` and `didReceive` across two objects, and it would need a second pending
  buffer that duplicates `routeState.pending`.
- *`ReminderScheduler` holds a `VaultController`*: this ties the calendar layer to the
  app-layer controller. It also breaks the "plain values in, testable statics" shape that
  `requests(for:after:noteIDs:)` already follows (`ReminderScheduler.swift:158-163`).

**Delegate placement: the delegate object is unchanged; only where it is built moves.**

- `reminders` stops being an inline `@State` default. It is built as a local in
  `init()`, like `navigation` and `diary`, so the sink is set in the same synchronous init,
  before anything can call it.
- Keeping the inline default as well would build a throwaway scheduler first. That throwaway
  would briefly hold the (weak) delegate slot.
- The comment at that spot records that this construction must stay in `init`, which is the
  opposite of `armCapture()`/`updater.start()` (ADR-0031 §D3).

**Isolation.** `didReceive` has the same shape as the existing `willPresent`:

```swift
nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
) async
```

- On the nonisolated side it reads the non-Sendable `response` and classifies it through
  the pure static function (Task 1).
- It then awaits a main-actor method, passing only the `Sendable` `ReminderTap` value.
- It awaits the sink rather than spawning a `Task`, so the system's completion fires after
  the route is handled. `handle(_:)` does no heavy work for `.note`, `.noteID` or `.canvas`.
- It does not implement the completion-handler variant as well.

**R-02** then follows from the existing door: `handle(_:)` stores the route in
`routeState.pending` while `store == nil`. Task 5 closes the F7 window, so "not open yet"
also covers "still opening".

## Tasks

The rule for every task, since this is a type-checked target: **the tester owns the
declarations the tests reference, and the coder owns the bodies.**

- A tester commit adds the declarations with honest stub bodies, so the target builds and
  the new tests go red on assertions rather than on compile errors.
- Adding the two new test files requires `tuist generate --no-open` before building, because
  `Tests/**` is a Tuist glob (`Project.swift:260`).

Order is 1 → 7. Task 5 does not depend on Tasks 1–4. It is placed after them so that a cut
at plan approval removes a tail, not a middle.

### Task 1 — The tap classifier: a pure function, unit-tested (R-01, R-03, R-04)

**Files:** `Sources/Calendar/ReminderScheduler.swift`, `Tests/ReminderTapTests.swift` (new).

**Tester declares** these in `ReminderScheduler.swift`. The enum is top-level, not nested,
so its isolation is not in question:

```swift
/// What a tap on a delivered notification asks the app to do.
enum ReminderTap: Equatable, Sendable {
    case open(PergamenumRoute)
    case notDefaultAction   // dismissed, or a custom action: not a request to open anything
    case noRoute            // no route key, or an empty one - the test notification's shape
    case unreadableRoute    // not a String, not a URL, or not a route this app answers
}

// on ReminderScheduler
nonisolated static let routeKey = "route"
nonisolated static func tap(actionIdentifier: String, userInfo: [AnyHashable: Any]) -> ReminderTap {
    .noRoute   // stub; the coder replaces it
}
```

**Tester scenarios** (names are indicative):

- **T1.1** `UNNotificationDefaultActionIdentifier` with `[routeKey: "pergamenum://note?id=<uuid>"]`
  gives `.open(.noteID(uuid))`.
- **T1.2** The default action with a `note?file=` route gives `.open(.note(path:))`.
- **T1.3** Round trip. Classify the `content.userInfo` of the requests built by
  `ReminderScheduler.requests(for:after:noteIDs:)`:
  - with an id minted, the result is `.open(.noteID(...))`;
  - without one, the result is `.open(.note(path:))`.

  This pins that the writer and the reader agree on the key and the format.
- **T1.4** `[:]`, the shape of `sendTestNotification`, which sets no `userInfo`
  (`ReminderScheduler.swift:139-142`), gives `.noRoute`.
- **T1.5** `[routeKey: ""]` gives `.noRoute`. This is what `requests` writes when no URL can
  be built (`ReminderScheduler.swift:186`).
- **T1.6** These inputs give `.unreadableRoute`, as a parameterised test:
  `"pergamenum://sconosciuto"`, `"non è un url"`, `"https://example.test"`, and a
  non-String value (`42`).
- **T1.7** `UNNotificationDismissActionIdentifier`, and a custom identifier such as
  `"posticipa"`, carrying a valid route, give `.notDefaultAction`.
- **T1.8** A backstop for notifications delivered before Task 2 ships.
  `"pergamenum://note?file=Area/Board.canvas"` gives
  `.open(.canvas(path: "Area/Board.canvas", nodeID: nil))`, and so does `.CANVAS`
  (the extension check ignores case).

All scenarios are red against the stub, except T1.4 and T1.5. Those pass by construction:
they guard against over-firing.

**Coder** writes `tap` in this order:

1. If the action identifier is not `UNNotificationDefaultActionIdentifier`, return
   `.notDefaultAction`.
2. If `userInfo[routeKey]` is absent or `""`, return `.noRoute`.
3. If the value is not a `String`, or `URL(string:)` fails, or `PergamenumRoute(_:)` fails,
   return `.unreadableRoute`.
4. If the route is `.note(path)` and the path's extension, lowercased, is `canvas`, return
   `.open(.canvas(path:nodeID: nil))`.
5. Otherwise return `.open(route)`.

The coder also changes `requests` to write `Self.routeKey` instead of the literal `"route"`.
The existing `CalendarTests` keep reading the literal `"route"` on purpose: they pin the key
written into notifications already scheduled on disk.

### Task 2 — A board-sourced reminder carries the board route (R-01)

**Files:** `Sources/Calendar/ReminderScheduler.swift` (`requests`), `Tests/ReminderTapTests.swift`.

**Why this is in scope.** Without it, wiring the tap makes F8 live: a board task's reminder
would open the `.canvas` JSON in a note tab, and the editor's autosave could write text back
into the board file. Before this chain those taps did nothing.

**Tester.**

- **T2.1** Take a task parsed with `sourcePath: "Area/Board.canvas"` and set its
  `nodeID = "7a1f"`. Its request's route parses to
  `.canvas(path: "Area/Board.canvas", nodeID: "7a1f")`.
- This must hold even when `noteIDs` has an entry for that path: an id never wins for a
  board.
- T2.1 is red against the current `requests`.

**Coder.** In `requests`, when the lowercased `sourcePath` extension is `canvas`, use
`PergamenumLink.canvas(path:nodeID:)`. Otherwise keep the existing id-then-path expression.

**Contract change:** the notification payload for tasks sourced from boards.

Grep `ReminderScheduler.requests` finds:

- `ReminderScheduler.swift:106` (`reschedule`): no change needed.
- `Tests/CalendarTests.swift:229, 239, 248, 262, 274-275`: every one uses a `.md` source, so
  none asserts the old board shape. The comment at `CalendarTests.swift:246-247` becomes
  false; see Task 6.

### Task 3 — The delegate answers the tap (R-01, R-03)

**File:** `Sources/Calendar/ReminderScheduler.swift` only.

Add these:

- `@ObservationIgnored var openRoute: (@MainActor (PergamenumRoute) async -> Void)?`.
  - Its doc comment says it is wired once by `PergamenumApp.init` and is `nil` in tests.
  - It follows the shape of `VaultController.didRelocateFolders` (`VaultController.swift:122-129`).
- `import OSLog` and
  `private static let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "reminders")`.
- `nonisolated func userNotificationCenter(_:didReceive:) async`, which works in two steps:
  1. `let tap = Self.tap(actionIdentifier: response.actionIdentifier, userInfo: response.notification.request.content.userInfo)`;
  2. `await deliver(tap)`.
- `private func deliver(_ tap: ReminderTap) async`, on the main actor because the class is
  `@MainActor`. Its cases:
  - For `.open(route)`: log one notice with `route.kind` at `privacy: .public`. Then
    `guard let openRoute` (on `nil`, log "nessun destinatario" and return), and then
    `await openRoute(route)`.
  - For every other case: log one notice naming the case (public).
  - It never logs the raw route string, because a route carries note paths (PG-125).

Must not:

- call `NSApp.activate`. The system brings the app forward for a default-action tap, and the
  note at `PergamenumApp.swift:56-58` applies here too.
- call `recordProblem` for `.noRoute` or `.unreadableRoute`. R-03 asks for a log line only.

**No unit test for these lines, on purpose.** Building a `ReminderScheduler` inside the
hosted unit suite would point the host process's notification delegate at a throwaway
object. The decision itself lives in Task 1's pure function. The remaining glue, about five
lines, is covered by M1–M3.

### Task 4 — Wire the tap at launch, and make the delegate placement visible (R-01, R-02)

**File:** `Sources/App/PergamenumApp.swift`.

- Change `@State private var reminders = ReminderScheduler()` to
  `@State private var reminders: ReminderScheduler`, with no default.
- In `init()`, next to `vault.didChangeExternally`:

  ```swift
  let reminders = ReminderScheduler()
  reminders.openRoute = { route in await vault.handle(route) }
  _reminders = State(initialValue: reminders)
  ```

- Add a comment at that spot that says:
  - Apple's rule (F3), and that a cold-launch tap depends on it;
  - why construction stays in `init`, as opposed to `armCapture()`;
  - why the tap does not go through `appDelegate.vault` (F6).
- Update the property's doc comment (`PergamenumApp.swift:82-84`) to say where the scheduler
  is built.
- Add `applicationDidFinishLaunching(_:)` to `AppDelegate`. It logs one notice in category
  `reminders`: the type name of `UNUserNotificationCenter.current().delegate`, or «nessuno».
  This turns F4's inference into a fact on every launch, and M2 reads it. It needs
  `import UserNotifications` and `import OSLog`.
- The file is already at 402 lines, past SwiftLint's 400 `file_length` warning (the error is
  at 1000). Keep the additions to exactly the items above and do not refactor.

Nothing outside the app changes. Every existing use of `reminders` stays as it is:
`.environment(reminders)` ×2 and `.task(id: vault.taskGeneration)`.

### Task 5 — A route that arrives while the vault is opening waits for it (R-02)

**This goes beyond the brief's literal text; see Risks.** It is recommended because a
cold-launch tap is exactly the route most likely to land in F7's window. Stefano may cut it
at plan approval, in which case T5.1 is dropped and F7 is filed as its own issue.

**Files:**

- `Sources/App/VaultController+Routes.swift`: the `RouteState` flag, the `perform` guard and
  its comment.
- `Sources/App/VaultController.swift`: `open(_:)`.
- `Tests/PendingRouteTests.swift` (new).

**Tester declares** `var isOpeningVault = false` in `RouteState`, with a doc comment: "true
while `open(_:)` is between installing the session and restoring the tabs".

**Tester scenarios.** These are also R-02's first unit coverage: the pending replay has no
test today (`rg pending Tests/URLSchemeTests.swift` finds only the canvas route).

- **T5.1 (red)** Open a temporary vault with `.volatile()` stores, then set
  `controller.routeState.isOpeningVault = true`. Check each of these:
  - `await controller.handle(.note(path: "b.md"))` returns `false`;
  - `routeState.pending == .note(path: "b.md")`;
  - no tab was opened;
  - `openTabs.session(for:)` is unchanged.
- **T5.2 (green pin)** Seed a volatile `OpenTabsStore` through `remember(_:for:)` with one
  column holding `a.md`. Key it by the same URL later passed to `open`.
  1. On a controller that has not opened yet, `handle(.note(path: "b.md"))` returns `false`,
     and the route is pending.
  2. After `await open(root)`, the focused column holds `a.md` and `b.md`, `b.md` is active,
     `pending == nil`, and `isOpeningVault == false`.

  This pin turns red if the flag is cleared *after* the replay.
- **T5.3 (green pin)** Controller A opens the vault, mints an id for `b.md`, and closes.
  1. Controller B, before opening, gets `handle(.noteID(id))`, which returns `false` and
     leaves the route pending.
  2. After `open`, `openNote?.relativePath == "b.md"`.

**Coder.**

- In `open(_:)`, set `routeState.isOpeningVault = true` right after the `stateBase` guard.
  The function's one early return then needs no reset.
- Clear it right before the replay block, after `pinnedTags = …`. Never clear it after the
  replay: the replay goes back through `perform` and would hold its own route again.
- No new early return may sit between the set and the clear.
- In `perform`, make the guard
  `guard let store, !routeState.isOpeningVault else { routeState.pending = route; return false }`.
- Keep the single pending slot: the last route wins, as today.
- Update the comment above the guard.

**Contract change:** while a vault is opening, `handle(_:)` now returns `false` and holds the
route. Grep `\.handle\(` finds these call sites:

- Live callers: `PergamenumApp.swift:60, 193, 196, 291`, and the replay at
  `VaultController.swift:230`. All of them benefit.
- Tests: `Tests/URLSchemeTests.swift` (10 sites), `Tests/NoteIDRouteTests.swift` (8) and
  `Tests/RowCommandTests.swift:118`. Every one awaits `open(_:)` to completion first, so none
  reaches the new branch.

### Task 6 — Fix the comments and records the change makes false (R-01)

- `Sources/Core/URLScheme/PergamenumURL.swift:112-115`: the `PergamenumLink` doc still lists
  "reminder notifications" among users of the path form. That was stale after #539, and now
  reminders use id, then path, and the board route for board tasks.
- `Sources/Calendar/ReminderScheduler.swift:87-92` and `:180-183`: "or a `.canvas`-sourced
  task … falls back to the path route" becomes "a board task gets the board route".
- `Tests/CalendarTests.swift:246-247`: the same sentence in a test comment. Change the comment
  only; the assertions stay as they are.
- `Sources/App/PergamenumApp.swift:188-190` (F9): **no edit unless M6 measures it.** If M6
  shows the window does not come back, correct that comment and file the follow-up.
- `docs/adr/0059-…md:355, 500-502` describe the reminder route as it was before #539. This is
  history, so the ADR body is not edited.
- `TODO.md:44` (PG-243) is closed at ship. At `TODO.md:510` (PG-237), "Hand check owed,
  blocked on PG-243" gets M4's result. The coder does not edit either line mid-chain.
- `CLAUDE.md`: no change, since there is no ADR and no new working agreement.

### Task 7 — Verify: the full unit suite, then the hand check (R-01, R-02, R-03)

**Automatic checks.**

1. Run `tuist generate --no-open`, for the two new test files.
2. Run the **full** `PergamenumTests` (the TEST-CMD below), not only the new files. Task 5
   changes `handle(_:)` for every route, and Task 2 changes the notification payload.
3. Run SwiftLint on the touched files.

**No GUI test.** A notification banner belongs to Notification Center's own process, not to
the app's accessibility tree, so the app's UI suite cannot click it. The suite's budget is
also deliberately small.

**Manual checks (Stefano).**

Setup:

- Use the latest Debug build:
  `open -n "$(ls -dt ~/Library/Developer/Xcode/DerivedData/Pergamenum-*/Build/Products/Debug/Pergamenum.app | head -1)"`.
- In a second terminal, run:
  `log stream --level info --predicate 'subsystem == "it.stefer.pergamenum" AND (category == "reminders" OR category == "url-scheme")'`.
- Notifications must be allowed for this build (in the app's Settings), with the alert style
  set to banner or alert.

| # | Setup | Expected |
|---|---|---|
| M1 warm | App running. A note containing `- [ ] Prova tap @remind(<today> <now+2 min>)`; you are looking at another note. Click the banner body. | The reminder's note opens in a tab. The log shows the tap line (`noteID`), then `route ricevuta: noteID`, then `route esito: true`. |
| M2 **cold launch** | Two other notes open in tabs. Schedule a reminder 3 minutes ahead, then quit with Cmd+Q. When the banner appears, click it. | The app launches and the window appears. **Both saved tabs are restored and** the reminder's note is open and focused. The log shows, in order: the `applicationDidFinishLaunching` line naming `ReminderScheduler`; the tap line; `route esito: false` (the route was held); then, after the vault opens, `route ricevuta` and `route esito: true`. Before trusting the result, run `ps -Ao pid,command \| grep Pergamenum.app/Contents/MacOS` to confirm **the Debug build** launched and not `/Applications/Pergamenum.app` (see Risks). |
| M3 no route | Settings › «Invia una notifica di prova». Click the notification. | Nothing opens and no problem banner appears. The log shows one line for `noRoute`. |
| M4 renamed (the hand check PG-237 left owed) | Schedule a reminder, rename its note in the app, wait for the banner, click it. | The renamed note opens. |
| M5 board task | A `@remind` on a board's To Do card. Click its banner. | The Workspace pane opens on that board. No tab shows JSON. |
| M6 window closed | App running, window closed with Cmd+W. Click a reminder banner. | **Record what happens.** This is not a gate. If the window does not come back, file a follow-up; the menu-bar «Oggi»/«Inbox» entries have the same gap (F9). |
| M7 other app in front | Another app is frontmost. Click a reminder banner. | Pergamenum comes forward with the note open. |

If M2's log shows «nessuno» as the delegate, or shows no tap line at all, F4's inference
failed. **Stop and report it, and do not patch blind.** Record M1–M7 in the PR description,
since there is no ADR to hold implementation notes.

## Risks and HITL gates

- **The delegate placement rests on an inference (F4), not on documentation.** It is covered
  by Task 4's launch log line and by M2. Confidence in the inference is high, because it
  follows from how `@NSApplicationDelegateAdaptor` has to be read. It is still not
  documented by Apple.
- **Cold launch may start the wrong copy.** On a cold launch, LaunchServices chooses which
  app with `it.stefer.pergamenum` to start, and it may pick `/Applications/Pergamenum.app`.
  M2 is then a result about the installed release, not about this build. Check with `ps`.
  If the wrong copy launched, ask Stefano. Moving the installed copy aside is his decision
  (CLAUDE.md, Versioning).
- **HITL: scope beyond the brief, which needs Stefano's yes or no when the plan is approved.**
  - **Task 5** (F7) changes how `handle(_:)` behaves during an open, for **every** route.
    Recommendation: keep it. The cold-launch tap is its most likely trigger, and what it
    prevents is a silent loss of the saved tab session. If it is cut, file F7 as its own
    issue; T5.2 and T5.3 stay, because they pin R-02's existing mechanism.
  - **Task 2** (F8) is needed rather than optional. Without it, the tap makes the
    "board JSON in the editor" path live.
- **Vault mismatch.** A reminder scheduled from vault A and tapped while vault B is open
  does not open silently wrong. The id route records «nessuna nota con id …» and the path
  route records «il link punta a una nota che non esiste». Accepted, because the failure is
  visible.
- **No recent vault at cold launch.** The route stays pending until a vault is opened, and
  is then replayed against that vault. There is also one pending slot: two taps before the
  vault opens means the last one wins, as today.
- **Window not reopened (F9, M6).** This predates the chain and is not fixed here. It is
  measured, and a follow-up is filed if M6 shows it.
- **Pre-existing, out of scope, noted only.**
  - `scheduledIDs` exists only in memory, so after a relaunch the notifications of deleted
    tasks linger until they fire.
  - The Settings caption «macOS non mostra una notifica mentre la sua app è in primo piano»
    (`SettingsView.swift:204`) contradicts `willPresent`'s `[.banner, .sound, .list]`.
- **HITL: commit, push, PR, merge.** These follow the usual gates. There is no schema change,
  no on-disk format change, no deletion, no new dependency and no network call.
- **External resources: none.** The one prerequisite is the notification permission for the
  Debug build. It is a TCC grant tied to the Apple Development signature, and Stefano gives
  it once, inside the app, before M1.

## TEST-CMD

`TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test`
`TEST-CMD MODE: brownfield`

This is the command already approved for this directory, identical to `.claude/test-cmd`.
The unit suite exists and runs now. Run `tuist generate --no-open` first, after the tester
adds `Tests/ReminderTapTests.swift` and `Tests/PendingRouteTests.swift`.
