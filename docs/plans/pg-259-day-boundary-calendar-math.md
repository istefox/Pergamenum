# Plan: day-boundary and calendar math (`PG-259`, #573, Audit Fable chain 6)

- SPEC: `SPEC.md` (Approved 2026-09-28). It is the authority for scope, decisions and R-01..R-17.
- ADR: `docs/adr/0075-day-boundary-and-calendar-math.md` (`accepted`). Landed via PR #722
  (`5343eb58`, 2026-09-30); renumbered from 0071 before its first commit.
- Base: `2d1adb40` (`origin/main`). Every line number below was read from that tree on 2026-09-28.
- One PR, on branch `fix/pg-259-day-boundary-calendar-math`.
- **Three gates must be answered before `/build` starts.** G3 changes what T1's tests assert. G2
  changes T1's and T3's connector scope. G1 fixes a colour T4 asserts. See «Risks, dependencies
  and HITL gates».

**Gate answers (Stefano, 2026-09-28), binding for `/build`:** G3 = the 480-minute cap (a wrapped
line is recovered only when the recovered block lasts at most 480 minutes, otherwise skipped;
`ignoresMalformedTimelineLines` stays unchanged; SPEC R-03 amended). G2 = approved (non-numeric
`minutes` is refused with the same sentence; SPEC R-08 amended). G1 = `.textSecondary` (SPEC R-13
amended). Every «only if G2 is approved» step below applies; every «G3's literal reading /
alternative» branch below does not; «G1's token» means `.textSecondary`.

## SPEC decisions registered, not reopened

These are settled in SPEC §Decisions and carried into ADR-0075 §D0 as they stand:

- time blocks follow the diary's 24:00 rule, and the 23:59 cap is rejected;
- creation shortens rather than overlapping, refusing outright or moving earlier, with a minimum of
  `min(15, requested)`;
- `00:00` and wrapped ends already on disk are recovered, and the next rewrite stores the corrected
  form;
- an event is drawn per day as the part that day covers, and a fully covered day goes in the
  all-day row, through one shared helper for the Day and Week views;
- the connectors refuse a duration outside 5…480 with one sentence, and never clamp;
- a deadline is overdue only when it has passed, by the task rows' rule;
- the Today pane matches the daily note by its exact path;
- the diary's now-line timer runs only on today;
- unit tests on pure seams, zero GUI tests, and R-12 and R-16 are checked by hand;
- no on-disk format, schema or protected-interface change;
- the parser test that rejected `24:00` flips its expectation, and is never deleted.

## What reading the code added (the coder must know these)

1. **A second existing test conflicts with the recovery rule (gate G3).**
   `CalendarTests.ignoresMalformedTimelineLines` (`Tests/CalendarTests.swift:79-90`) asserts that
   `- 11:00-10:00 fine prima dell'inizio` is skipped. «An end earlier than the start reads as
   24:00», read literally, recovers it, and then R-17 cannot hold.
   - The recommendation (ADR-0075 §D1 rule 3) recovers a wrapped end only when the implied length
     is at most 480 minutes. That is every line the app could have written.
   - The alternative is the literal reading, which amends R-17 and changes that test's expectation.
     The test is never deleted.
2. **`vault.problems` is drawn only in Settings** (`SettingsView.swift:297-299`). `DayController.report`'s
   doc comment (`DayController.swift:297-298`) calls it «the banner the user actually reads», which
   is false. The day view's only sentence surface is `lastDrop`'s banner (`TodayView.swift:39`,
   `:87-111`). ADR-0075 §D3 routes the creation refusal there, and T2 corrects the comment.
3. **A move gets stricter.** `TimeBlock.moved` places through the new search with `minimum` = its
   own length. A move that used to land overlapping the next block now slides past it, or is
   refused. The seven existing gesture tests hold; the reasoning is in ADR-0075 §D2.
4. **`DayController` is at SwiftLint's `type_body_length` limit.** `DayController+TaskDrop.swift:5-7`
   says so. If T2's additions cross the limit, move `addBlock` into a new
   `Sources/Features/Today/DayController+Blocks.swift`. Widen `report` from `private` to `internal`
   with one comment naming the file that reads it (ADR-0045's convention), then run
   `tuist generate --no-open`.
5. **`CalendarEvent` imports EventKit, so the projection is app-only.** A new file under
   `Sources/Calendar/` other than `TimeBlock.swift` is in the app target and not in
   `sharedSources` (`Project.swift:103` names `TimeBlock.swift` alone). No `Project.swift` edit is
   needed, but a `tuist generate --no-open` is.
6. **EventKit's end convention for an all-day event was not verified.** ADR-0075 §D5 makes
   `isAllDay` win over the minute rule on every day `bucketed` put the event on, so the projection
   never depends on it.
7. **Publishing a block that ends at 24:00** calls `EventKitStore.date(day, hour: 24, minute: 0)`
   (`DayController.swift:237-243`). Whether `Calendar` normalises that to the next midnight was not
   verified. The case already existed through resize and is named in ADR-0075 §D9. T7 includes an
   optional hand observation.
8. **`TimelineBlockBox.swift:37`** formats the dragged end with `TimeBlock.timeText`, so a drag to
   midnight will read `24:00` there too. That is intended.

## Standing rules for every task

- **Tooling.** `tuist install` once per fresh worktree. `tuist generate --no-open` after any file is
  added. Never edit `.xcodeproj`/`.xcworkspace`.
- **Tester owns the signatures, coder owns the bodies.**
  - A tester task adds every declaration with a stub body that preserves today's behaviour. The
    target then builds, and the new tests fail for the intended reason. The stub for each
    declaration is given below.
  - The tester also makes the mechanical edits a signature change forces at existing call sites.
  - The coder task that follows replaces the bodies, and only then do the reds go green.
- **Keep the build green.** Every task ends with the app, `perg` and `pergamenum-mcp` building and
  `PergamenumTests` green, apart from the reds the preceding tester task declared.
- **Tests.** Never disable or delete a test. An assertion that must change is explained in chat
  first. The known ones are named in each task. The `rejectsInvalidTimes` flip is mandated by the
  SPEC; `ignoresMalformedTimelineLines` changes only if G3 takes the literal reading.
- **UI.** Strings are Italian. Colours and fonts go through tokens (`CLAUDE.md` binding rule). No
  GUI test is added (SPEC).
- **Protected interfaces stay untouched.** None of `.claude/protected-interfaces` is on this chain's
  path. A diff touching one is a defect.

---

## Task 1 — (tester) Declare the time-block seams and write their red suites (R-01, R-02, R-03, R-04, R-05, R-06, R-07, R-08, R-17)

**Declarations** (ADR-0075 §D2, §D4):

- `Sources/Calendar/TimeBlock.swift`:
  - `static let durationRange: ClosedRange<Int> = 5...480`. The value is final. Reading it from
    `VaultSettings` is T3's job.
  - `struct Slot: Equatable, Sendable { let start: Int; let duration: Int }`, nested in `TimeBlock`.
  - `static func freeSlot(from preferred: Int, in blocks: [TimeBlock], duration: Int, minimum: Int)
    -> Slot?`. The stub body is today's behaviour:
    `freeStart(from: preferred, in: blocks, duration: duration).map { Slot(start: $0, duration: duration) }`.
- **Only if G2 is approved:** `Sources/Connector/VaultWrites.swift` (or `VaultReads.swift`, beside
  `limit(parsing:named:)`) declares `static func blockMinutes(parsing raw: String?) throws -> Int?`.
  The stub is `raw.flatMap(Int.init)`, today's `perg` behaviour.

**Red tests.** Every fixture day note is written through `TemporaryVault`, never through the
parser under test.

- `Tests/CalendarTests.swift`, formatting and parsing (R-01, R-03, R-17):
  - **R-17 flip, explained in chat before the edit.** `rejectsInvalidTimes` (`:179-182`) loses
    `"24:00"` and gains `"24:01"` and `"25:00"`. `parsesValidTimes` (`:174-177`) gains
    `("24:00", 1440)`. No other case changes.
  - `timeText(1440) == "24:00"`, and `timeText(0) == "00:00"` still holds.
  - Round trip: a section with `- 23:00-24:00 Chiusura` parses to an end of 1440. It writes back
    containing `23:00-24:00`, and parses again to an equal block (R-01).
  - `- 23:00-00:00 A` and `- 09:00-00:00 Lungo` read with end 1440. After `write`, the section
    holds `23:00-24:00` and `09:00-24:00` (R-03).
  - `- 23:30-00:30 Tardi` reads as 23:30–24:00 and rewrites as `23:30-24:00` (R-03, the wrapped line).
  - `- 24:00-24:00 X` and `- 00:00-00:00 Y` are skipped.
  - `ignoresMalformedTimelineLines` stays exactly as it is, under G3's recommendation. Under the
    literal reading, its expectation changes to include the `11:00-10:00` line, with the chat
    explanation first.
- `Tests/CalendarTests.swift`, the search (R-04, R-05, R-06). One `@Test` per case, and none with a
  gap-free assertion only:
  - empty day, from 09:00 with 30/15, gives `Slot(540, 30)`;
  - a start inside a hand-written `09:00-09:10` moves to exactly 09:10, giving `Slot(550, 30)`;
  - shortened before the next block: `[10:00-11:00]`, from 09:45 with 60/15, gives `Slot(585, 15)`;
  - shortened at midnight: from 23:45 with 60/15, gives `Slot(1425, 15)` (SPEC edge case);
  - a start that snaps to 24:00 (from 23:53) gives nil (SPEC edge case);
  - 10 minutes in a 12-minute gap: `[09:00-09:18, 09:30-10:00]`, from 09:00 with 10/10, gives
    `Slot(558, 10)` (SPEC edge case);
  - a short run is passed over, not refused: `[09:00-09:50, 10:00-11:00]`, from 09:00 with 60/15,
    gives `Slot(660, 60)`;
  - no run of at least the minimum left: `[23:00-23:50]`, from 23:00 with 60/15, gives nil;
  - a block of zero length in the list does not stall the search;
  - invariant (R-04, R-05): over a fixed table of layouts and starts, every returned slot overlaps no
    block and ends at or before 1440. The table is deterministic, with no randomness.
- `Tests/TimeBlockGestureTests.swift` (R-02, R-04):
  - `resized(block(23:00, 30), toDuration: 180)` written into `## Timeline` and parsed back equals
    the block, with end 1440;
  - `moved(block(23:00, 60), toStart: 23:45)` written and parsed back equals the moved block;
  - `moved(block(09:00, 60), toStart: 09:30, among: [10:00-11:00])` starts at 11:00, not 09:30.
- `Tests/DayControllerTests.swift` (R-06, R-07), through `makeController`:
  - `addBlock(from:preferredStart: 23*60+45)` with the default 30 gives a block of 15 minutes, and
    the file holds `- 23:45-24:00 …`;
  - with `- 10:00-11:00 Riunione` in the note, `addBlock(preferredStart: 9*60+45)` gives 09:45–10:00;
  - with `- 23:00-24:00 Pieno` in the note, `addBlock(preferredStart: 23*60+30)` returns nil. Then:
    - `lastDrop?.isRefusal == true`;
    - `lastDrop?.summary` contains «nessuno spazio libero»;
    - `lastDrop?.journalID == nil`;
    - `problems` holds the same sentence;
    - the file is byte-identical.
  - The hour drop: a task `- [ ] Chiamare >2026-08-10` in a note, with the same full last hour on the
    day note, dropped with `drop(_:on: day, at: TaskTime(hour: 23, minute: 30))`. Then:
    - it returns true, because the move landed;
    - `lastDrop?.isRefusal == true`;
    - the summary contains both «Spostato al» and «nessuno spazio libero»;
    - `lastDrop?.journalID != nil`.
- `Tests/VaultSessionTests.swift` (R-05, R-06, R-07, session half):
  - `addTimeBlock(… startMinutes: 23*60+45)` gives a block of 15 minutes, and `timeBlocks(on:)`
    reads its end as 1440;
  - with the last hour full, it returns nil and `problems.last` contains «nessuno spazio libero».
- `Tests/ConnectorTests.swift` (R-06, R-08):
  - `minutes` 0, 4, 481 and -5 each throw a `ConnectorError` with `isUsage == true`, whose
    description names «minutes» and the value;
  - nothing is written on a refusal: the daily note does not exist afterwards, and the
    `dryRun: true` arm refuses too;
  - 5 and 480 are accepted;
  - shortening says so: after a block at 10:00, `at: "09:45", minutes: 60` returns a `note`
    containing «accorciato a 15 minuti», and `VaultAPI.day` shows `09:45`–`10:00`;
  - `aBlockOnAnOccupiedHourMovesAndSaysSo` (`:440-459`) stays unchanged;
  - **only if G2 is approved:** `blockMinutes(parsing: "abc")` and `("")` throw the same sentence
    shape, `(nil)` gives nil, and `("45")` gives 45.
- `scripts/mcp-smoke.py`, in the `hardening()` stage (`:479`), for R-08:
  - `add_time_block` with `minutes` 481 and then 0 is refused (`isError`, text naming «minutes»),
    and the server lives;
  - **only if G2 is approved,** `"minutes": "abc"` is refused the same way.

  The `writing()` stage's calls (`:231-238`) stay unchanged. This file is run in T7, not by the
  unit suite.

**Expected reds:** every new test above, plus the flipped `rejectsInvalidTimes`/`parsesValidTimes`
cases. Everything else stays green.

## Task 2 — (coder) The time-block model, the two app creation paths and the refusal banner (R-01, R-02, R-03, R-04, R-05, R-06, R-07)

- `Sources/Calendar/TimeBlock.swift` (ADR-0075 §D1, §D2):
  - `timeText` returns `DiaryGrid.timeText(minutes)`.
  - `TimeBlockSection.minutes(from:)` returns `DiarySection.minutes(from: text)`.
  - `parse` applies §D1 rules 1–4, with rule 3 as G3 decided. Nothing else in `parse` changes.
  - `freeSlot` gets its body per §D2. A block with `durationMinutes <= 0` is ignored. A run closed
    by midnight that is shorter than `minimum` returns nil.
  - `moved` keeps its `wanted` clamp and calls `freeSlot(from: wanted, in: others, duration: d,
    minimum: d)`. It returns nil on nil. The redundant `free + duration <= 1440` check goes, because
    the slot guarantees it.
  - `freeStart` is deleted. Its callers are `:70`, `DayController.swift:182` and
    `VaultSession+TimeBlocks.swift:74`, and no test calls it. The doc comments at `:40-44` and
    `:59-66` are rewritten to describe `freeSlot`.
- `Sources/Features/Today/DayController.swift` (§D3):
  - `addBlock` calls `freeSlot(…, minimum: min(15, duration))` and builds the block with
    `slot.duration`.
  - On nil it calls `report(sentence)` with today's «blocco tempo: nessuno spazio libero il …», sets
    `lastDrop = Drop(summary: sentence, journalID: nil, isRefusal: true)`, and returns nil.
  - `Drop`'s and `lastDrop`'s doc comments widen to «the last drop or block insertion».
    `report`'s comment stops calling `vault.problems` the banner the user reads.
  - Apply note 4 if SwiftLint complains.
- `Sources/Features/Today/DayController+TaskDrop.swift` (§D3):
  - `drop` keeps `addBlock`'s result.
  - When an hour was asked and `addBlock` returned nil, the final `lastDrop` is built as follows:
    - `summary`: the existing `"Spostato al \(target.italianForm), \(time.text)"`, followed by
      `". Blocco non creato: nessuno spazio libero il \(day.compactForm)"`;
    - `journalID`: `outcome.journalID`;
    - `isRefusal`: true.
  - `addBlock` has already set its own `lastDrop`; the drop overwrites it with the combined one.
- `Sources/Vault/VaultSession+TimeBlocks.swift`: `addTimeBlock` calls
  `freeSlot(…, minimum: min(15, duration))` and builds the block with `slot.duration`. The refusal
  path (`recordProblem`) is unchanged. The doc comment at `:61-64` says the block may be shorter.

### Update tests and call-sites asserting the old behaviour (Task 2)

Grep-confirmed at `2d1adb40`:

- **`freeStart`**: 3 call sites (listed above), 0 tests. All are replaced and the function is
  deleted.
- **`timeText(1440)` becomes `"24:00"`**:
  - `endText` consumers: `VaultPayloads.swift:112` (the connector `day` payload `end`),
    `DayReferences.swift:204`, and `TimeBlockSection.render` (`TimeBlock.swift:180`);
  - `TimeBlock.timeText` in `TimelineBlockBox.swift:37`.

  No test asserts `"00:00"` for an end.
- **`minutes(from: "24:00")`**: `CalendarTests.swift:179`, flipped in T1.
- **Placement tests that must stay green unchanged**:
  - `VaultSessionTests.swift:245-260`;
  - `TaskComposerTests.swift:317-332`;
  - `ConnectorTests.swift:440-459`;
  - `DayControllerTests.swift:38-80`;
  - all of `TimeBlockGestureTests.swift:17-73`.

  Each was checked by hand against §D2's rule.
- **Capture** (`VaultController+Tasks.swift:71`) reaches `VaultSession.addTimeBlock` through
  `VaultController+TimeBlocks.swift:46-62` and needs no edit. A shortened block is simply shorter.

## Task 3 — (coder) The connectors check the duration, say when a block was shortened, and share the range with the settings (R-06, R-08)

- `Sources/Connector/VaultWrites.swift`, in `addTimeBlock` (`:232-256`), per ADR-0075 §D4:
  - After the title check, and before `day(rawDay)` and any session call, the method refuses a
    non-nil `minutes` outside `TimeBlock.durationRange`. It throws
    `ConnectorError("«minutes» vuole una durata da 5 a 480 minuti: «\(minutes)» non lo è", usage: true)`,
    with the bounds read from the range, not typed.
  - The success `note` joins the existing «spostato alle…» sentence with «accorciato a N minuti»
    when `placed.block.durationMinutes` is below the requested or default duration. Both go into one
    `String?`, and the shape is unchanged.
- `Sources/Vault/VaultSettings.swift:202`: the clamp reads
  `min(max(minutes, TimeBlock.durationRange.lowerBound), TimeBlock.durationRange.upperBound)`.
  `VaultTests.swift:611-617` stays green unchanged.
- `Sources/MCPServer/ToolCatalogue+Writing.swift:179`: the `minutes` description, today «durata;
  quella di default del vault se omessa», gains the range («da 5 a 480 minuti»). This is a
  description string, not a schema shape change.
- **Only if G2 is approved:**
  - `blockMinutes(parsing:)` gets its body: nil for nil, the `Int` for a readable value, and
    otherwise the same sentence as a usage error.
  - `Sources/CLI/Commands/WriteCommands.swift:137` calls it instead of `flatMap(Int.init)`.
  - `Sources/MCPServer/VaultHost.swift:255` reads `minutes` through a checked reader in
    `ToolArguments.swift` that keeps absent (nil) apart from unreadable (refused with the same
    sentence), ADR-0063 §D1.4's shape. A new reader is needed because `checkedInt` (`:54-70`) speaks
    the `limit` sentence.
  - ADR-0063 §D9's `--minutes abc` bullet is then closed. Say so in the PR, and drop the matching
    §D9 bullet from ADR-0075.

### Update tests and call-sites asserting the old behaviour (Task 3)

- **`VaultAPI.addTimeBlock`**, grep-confirmed:
  - callers: `WriteCommands.swift:133` and `VaultHost.swift:251`;
  - tests: `ConnectorTests.swift:446-449`;
  - smoke: `mcp-smoke.py:231-238`.

  None passes an out-of-range value, so all stay unchanged.
- **`VaultSettings`' clamp** is exercised by `VaultTests.swift:611-617`, `RolloverTests.swift:118-122`
  and `SpellCheckTests.swift:35-40`. All stay unchanged, because the bounds are the same numbers.

## Task 4 — (tester) Declare the projection, the overdue rule, the grid identities and the daily-note predicate, and write their red suites (R-09, R-10, R-11, R-13, R-14, R-15)

**Declarations**, each with the stub named:

- `Sources/Calendar/DayProjection.swift` (new, Foundation only, app target, then
  `tuist generate --no-open`), per ADR-0075 §D5:
  - `enum DayProjection: Equatable, Sendable { case none, allDay, timed(startMinute: Int, endMinute: Int) }`;
  - `static func of(start: Date, end: Date, on day: CalendarDate, calendar: Calendar = .current)
    -> DayProjection`. Stub: `.none`.
  - `static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int`. Stub: the body of
    today's private `DayTimeline.minutes(from:)`, which is today's behaviour, moved.
  - `struct ProjectedEvent: Identifiable { let event: CalendarEvent; let startMinute: Int; let endMinute: Int; var id: String { event.id } }`;
  - `extension CalendarEvent { func projection(on day: CalendarDate, calendar: Calendar = .current) -> DayProjection }`.
    Stub: `.none`.
  - `extension Array where Element == CalendarEvent { func projected(on day: CalendarDate, calendar: Calendar = .current) -> (allDay: [CalendarEvent], timed: [ProjectedEvent]) }`.
    The stub is today's split, unclipped: the flagged events go in `allDay`. Each timed event gets
    `startMinute = minuteOfDay(start)` and `endMinute = startMinute + max(15, minutes(end - start))`.
- `Sources/Features/Today/DayTimeline.swift`: `static func hours(for window: HourWindow, blocks:
  [TimeBlock], timed: [ProjectedEvent]) -> HourWindow`. Stub: the existing seam over block ranges and
  the given event ranges. The existing `hours(for:startMinutes:endMinutes:)` stays.
- `Sources/Features/Today/WeekPlan.swift`:
  - `WeekEntry` gains `var isOverdue: Bool = false`. It is declared after `lineIndex`, so the
    memberwise calls at `WeekPlanTests.swift:146,156` and `TaskDropTests.swift:33` compile unchanged.
  - `WeekEntry` gains `var token: ColorToken`. Stub: `kind.token`.
  - `entries(on:events:blocks:tasks:today: CalendarDate = .today)`. The stub ignores `today`.
- `Sources/Core/Tasks/TaskItem.swift`: `static func isPastDue(_ due: CalendarDate, on day:
  CalendarDate) -> Bool`, with body `due < day`. That is today's comparison, named. `isOverdue(on:)`
  is not rewired here.
- `Sources/Core/Categories/Category.swift`: `func isDeadlineOverdue(on day: CalendarDate) -> Bool`.
  Stub: `deadline != nil`, today's always-red behaviour.
- `Sources/Features/Today/MiniCalendar.swift`, in `enum MonthGrid`:
  - `struct Cell: Identifiable, Equatable { let id: Int; let date: CalendarDate? }` and
    `static func cells(of month: CalendarDate) -> [[Cell]]`. The stub uses today's identity, where a
    blank cell collides: `id` is the date's hash for a date and 0 for nil, so blanks share an id;
  - `struct WeekdayHeader: Identifiable { let id: Int; let initial: String }` and
    `static let weekdayHeaders: [WeekdayHeader]`. The stub uses today's identity, so the two «M»
    headers collide: `id` is the initial's hash.
- `Sources/App/VaultController+TimeBlocks.swift`: `func isDailyNote(_ relativePath: String, for day:
  CalendarDate) -> Bool`. Stub: `relativePath.contains(day.compactForm)`, today's `TodayView` rule.

**Red tests:**

- `Tests/WeekPlanTests.swift` (R-09, R-10), beside the bucketing tests at `:167-226`. The
  projection tests use a fixed `Calendar` with `Europe/Rome` and an explicit day. The
  `CalendarEvent` is built the way the file's `event(_:hour:allDay:)` helper (`:52`) builds one:
  - Monday 09:00 to Wednesday 11:00 projects as follows:
    - Monday is `.timed(540, 1440)`;
    - Tuesday is `.allDay`;
    - Wednesday is `.timed(0, 660)`;
    - Thursday is `.none`.
  - 22:00 to 01:00 is `.timed(1320, 1440)` on the first day and `.timed(0, 60)` on the next.
  - An event ending exactly at 00:00 is `.none` on the next day (SPEC edge case).
  - 00:00 to the next 00:00 of one day is `.allDay` (SPEC edge case).
  - A flagged `isAllDay` event is `.allDay` on every day it touches.
  - A zero-length event at 10:00 is `.timed(600, 600)`.
  - A DST day (`2026-03-29` or `2026-10-25` in Rome): an event 00:00 to 12:00 projects `.timed(0,
    720)`, in clock minutes.
  - `projected(on:)` puts the Tuesday part of the multi-day event in `allDay`, not in `timed`.
  - `WeekPlan.entries(on: tuesday, events: [multiDay], …)` gives the event `minutes == nil`, sorted
    first. On Wednesday it gives `minutes == 0` and `timeText == "00:00"`, not 09:00. This pins
    R-10 behaviourally, and T7's `rg` pins it structurally.
- `Tests/WeekPlanTests.swift` (R-13), for the deadline entries, with `today:` passed explicitly:
  - an open task due on a day before `today` has `isOverdue == true` and `token == .taskOverdue`;
  - one due on `today` or later has `isOverdue == false` and `token ==` G1's token;
  - a done task due before `today` has `isOverdue == false`;
  - the other three kinds keep `kind.token`.
- `Tests/CategoryRegistryTests.swift` (R-13): `isDeadlineOverdue(on:)` is true for a deadline the
  day before, and false for the same day, the day after, and no deadline.
- `Tests/HourWindowTests.swift` (R-11), beside `:58-72`:
  - with a window of 09–14 and the Tuesday part of a Monday-to-Wednesday event (`projected(on:
    tuesday).timed`, which is empty), the window is unchanged;
  - with a 22:00–01:00 event on its second day, the window widens to 0 and not to 22–24;
  - the two existing seam tests stay unchanged.
- `Tests/MonthGridTests.swift` (R-14):
  - for September 2026 (leading blanks) and a month with trailing blanks, every `Cell.id` across
    the grid is distinct;
  - the dates, read in order, equal `weeks(of:)`;
  - the seven `weekdayHeaders` ids are distinct and the initials read «L M M G V S D».

  The existing ten tests stay unchanged.
- `Tests/DayControllerTests.swift` (R-15), through `makeController`'s `VaultController`:
  - `isDailyNote("Calendar/20260925.md", for: 2026-09-25)` is true;
  - `isDailyNote("Calendar/20260925-riunione.md", …)` is false (SPEC edge case);
  - `isDailyNote("Altro/20260925.md", …)` is false.

**Expected reds:** the projection tests, the R-10 week-entry test, R-11, the overdue tests for a
not-yet-passed deadline and the category predicate, R-14, and R-15's negative cases.

## Task 5 — (coder) Events are drawn through the projection in the Day and Week views (R-09, R-10, R-11)

- `Sources/Calendar/DayProjection.swift`: the bodies per ADR-0075 §D5.
  - The day's bounds come from the same computation as `EventKitStore.dayRange`
    (`EventKitStore+Dates.swift:8-18`): `calendar.startOfDay` and `byAdding .day, value: 1`.
  - The end is 1440 when the clipped end equals the next midnight, and its clock minute otherwise.
  - An `isAllDay` event that touches the day is `.allDay`.
  - `projected(on:)` reuses `splitByAllDay` for the flag and appends every `.allDay` timed event to
    `allDay`.
- `Sources/Features/Today/DayTimeline.swift`:
  - `allDayEvents` and `timedEvents` come from `events.projected(on: controller.day)`.
  - The `ForEach` iterates `ProjectedEvent` and builds `TimelineEntry(start: p.startMinute,
    duration: max(15, p.endMinute - p.startMinute), …)`.
  - `eventNoteMark` and `eventNoteMenuItem` receive `p.event`.
  - `hours` calls `hours(for:blocks:timed:)`, which widens by `startMinute` and by
    `min(1440, max(endMinute, startMinute + 15))`, the drawn extent.
  - `openEventNote` (`:114-127`) stamps `DayProjection.minuteOfDay(event.start/end)`.
  - The private `minutes(from:)` (`:239-242`) and `duration(of:)` (`:244-246`) are deleted.
- `Sources/Features/Today/WeekPlan.swift`:
  - `eventEntries(_:on:)` switches on `event.projection(on: day)`:
    - `.allDay` gives `minutes: nil`;
    - `.timed(s, _)` gives `minutes: s` and `timeText: text(ofMinutes: s)`;
    - `.none` is dropped.
  - The sort is unchanged.
  - The private `minutes(from:)` (`:227-230`) is deleted.
- `Sources/Calendar/CalendarService.swift` is untouched.

### Update tests and call-sites asserting the old behaviour (Task 5)

- **`WeekPlan.entries`**: the production caller is `DayController.swift:144`, which passes
  `today: .today` explicitly. The five test calls at `WeekPlanTests.swift:65,88,100,114,128` compile
  through the default and stay unchanged. Their events are single-day, so the projection gives the
  same minutes.
- **`DayTimeline.hours(for:startMinutes:endMinutes:)`** stays, and so do its two tests
  (`HourWindowTests.swift:58-72`).
- **`splitByAllDay`**'s tests (`CalendarTests.swift:320-360`) stay unchanged.

## Task 6 — (coder) Deadline colour, mini-calendar identities, the Today daily note, the diary gestures and timer (R-12, R-13, R-14, R-15, R-16)

- **R-13** (ADR-0075 §D6):
  - `TaskItem.isOverdue(on:)` becomes `state.isOpen` plus `isPastDue`.
  - `Category.isDeadlineOverdue(on:)` returns `deadline.map { TaskItem.isPastDue($0, on: day) } ?? false`.
  - `WeekPlan.deadlineEntries` takes `today` and sets `isOverdue: task.isOverdue(on: today)`.
  - `WeekEntry.token` returns `.taskOverdue` when `kind == .deadline && isOverdue`, G1's token for
    any other deadline, and `kind.token` otherwise.
  - `WeekEntryRows.swift:34` and `:70` read `entry.token`.
  - `CategoryView.swift:114-117` picks `.taskOverdue` when `category.isDeadlineOverdue(on: .today)`
    and G1's token otherwise.
  - `WeekEntryKind` keeps four cases. `WeekMockupPieces.swift` is untouched.
- **R-14** (§D7):
  - The `MonthGrid.cells(of:)` and `weekdayHeaders` bodies use positional ids.
  - `MiniCalendar.weekdayRow` (`:66-74`) iterates `MonthGrid.weekdayHeaders`.
  - `grid` (`:76-86`) iterates `Array(MonthGrid.cells(of: month).enumerated())` by `\.offset` for the
    rows, and `Cell` for the cells.
  - The private `weekdayInitials` (`:176`) is deleted. `weeks` is deleted only if nothing else reads
    it.
- **R-15** (§D7): the body of `isDailyNote` is `relativePath == dailyNotePath(for: day)`.
  `TodayView.swift:206` calls `vault.isDailyNote(note.relativePath, for: day)`.
- **R-12** (§D7): both `DragGesture`s in `DiaryEntryCard.swift` (`:172`, `:183`) gain
  `coordinateSpace: .global`. Add one comment pointing at `TimelineBlockBox.swift:107-115` for the
  reason. No other change: the translation is a height delta in both spaces.
- **R-16** (§D7): `DiaryTimeline.swift:52-57` becomes `.task(id: controller.day)`.
  - It returns at once unless `controller.day == .today`.
  - Each loop sets `now = Date()`, breaks when `CalendarDate(now) != controller.day`, and sleeps
    30 s.
  - The now-line condition at `:169` is unchanged.
  - Keep the existing comment's point, one task and no Combine.

### Update tests and call-sites asserting the old behaviour (Task 6)

- **`isOverdue(on:)`**: `TaskTests.swift:123-128` stays unchanged, because the body is the same rule.
- **`kind.token` readers**: `WeekEntryRows.swift:34,70` are switched. `WeekView.swift:92,132` read
  the holiday `ItalianHolidays.DayKind.token`, not a week kind, and are not touched.
- **`MonthGrid.weeks(of:)`**: its tests stay unchanged.
- No test asserts the category deadline colour or the Today pane's substring rule.

## Task 7 — (orchestrator, then Stefano) Verification, hand checks and the gates (R-12, R-16, R-17)

- **Build and suite:**
  - build the app, then `perg` and `pergamenum-mcp` (their shared sources changed: `TimeBlock.swift`,
    `VaultWrites.swift`, `VaultSettings.swift`);
  - run the full `PergamenumTests`, not only the touched files. A contract changed (`timeText`,
    placement, the connector refusal), and a test in an unrelated file can share it.
  - **R-17:** the only existing test whose expectation changed is `rejectsInvalidTimes`, plus
    `ignoresMalformedTimelineLines` only under G3's literal reading. Confirm with
    `git diff 2d1adb40 -- Tests/` that no other existing assertion was edited.
- **Smoke and lint:**
  - build `pergamenum-mcp`, then run `scripts/mcp-smoke.py`. `hardening()` must pass the new
    `add_time_block` refusals;
  - SwiftLint over the touched files, with no new error-level `file_length`/`type_body_length`
    violation (note 4);
  - R-10, structurally: `rg -n 'dateComponents\(\[\.hour, \.minute\]'
    Sources/Features/Today/DayTimeline.swift Sources/Features/Today/WeekPlan.swift` returns nothing.
- **Hand checks (Stefano),** on the latest Debug build (`APP=$(ls -dt
  ~/Library/Developer/Xcode/DerivedData/Pergamenum-*/Build/Products/Debug/Pergamenum.app | head -1);
  open -n "$APP"`), with a throwaway vault via `-recentVaults '("/path")'`:
  - **R-12:** open the Diario, then drag a diary entry up and down, and resize its bottom edge. It
    follows the pointer without oscillating or overshooting.
  - **R-16:** open a past day in the Diario and confirm no now-line. Open today and confirm the line
    moves. Optionally, leave today open across a minute boundary.
  - Visual checks of R-07 and R-09:
    - drop a task on 23:30 over a full last hour, and the banner shows the refusal with «Annulla»;
    - a multi-day calendar event shows in the all-day row on its middle day, and at its real hours
      on the first and last.
  - Optional observation for ADR-0075 §D9: publish a block that ends at 24:00 and check the Apple
    Calendar event ends at midnight. The result goes into the ADR's implementation notes, whatever
    it is.
- **Gates:** see below. Nothing is committed or pushed without Stefano.

---

## Requirement coverage

| R-id | Tasks | Test home |
|------|-------|-----------|
| R-01 | T1, T2 | CalendarTests |
| R-02 | T1, T2 | TimeBlockGestureTests |
| R-03 | T1, T2 | CalendarTests |
| R-04 | T1, T2 | CalendarTests, TimeBlockGestureTests |
| R-05 | T1, T2 | CalendarTests, VaultSessionTests |
| R-06 | T1, T2, T3 | CalendarTests, DayControllerTests, VaultSessionTests, ConnectorTests |
| R-07 | T1, T2 | DayControllerTests, VaultSessionTests |
| R-08 | T1, T3 | ConnectorTests, `scripts/mcp-smoke.py` |
| R-09 | T4, T5 | WeekPlanTests |
| R-10 | T4, T5 | WeekPlanTests, plus T7's `rg` |
| R-11 | T4, T5 | HourWindowTests |
| R-12 | T6, T7 | none (`no-test`), hand check in T7 |
| R-13 | T4, T6 | WeekPlanTests, CategoryRegistryTests |
| R-14 | T4, T6 | MonthGridTests |
| R-15 | T4, T6 | DayControllerTests |
| R-16 | T6, T7 | none (`no-test`), hand check in T7 |
| R-17 | T1, T7 | CalendarTests; T7's diff check |

## Order and dependencies

- G1, G2 and G3 are answered first.
- T1 then T2 then T3 is the time-block half. T3 needs T2's `freeSlot` for the shortening note.
- T4 then T5 then T6 is the calendar half. T4 needs G1's token for its R-13 assertion.
- The halves share no file except `DayController.swift`: T2 edits `addBlock`, and T5 needs no edit
  there beyond T4's `today:` argument. Run them in the order written, one sequential coder.
- T7 closes.

## Risks, dependencies and HITL gates

- **The recovery reads typos as blocks.** A hand-typed `18:00-01:00` becomes 18:00–24:00 and is
  stored so on the next write. This is accepted in ADR-0075 Consequences. Under G3's literal
  reading, every end-before-start line does this, including `10:00-09:00`.
- **Moves get stricter** (note 3). A move that used to overlap now slides or is refused. A refused
  move is still invisible in the day view (ADR-0075 §D9), and a hand check may notice it.
- **Stale placement** (ADR-0075 §D9). Two quick creations before the first write lands can still
  overlap. The window is narrower than before, but it is not closed.
- **DST.** The projection is in clock minutes. The T4 DST test pins one case. A DST day still draws
  24 rows.
- **SwiftLint on `DayController`** (note 4) may force a file split and a `tuist generate`.
- **External resources:** none. No network, no OAuth, no new dependency. EventKit access is not
  needed by any unit test, because the projection takes plain dates.

**Gates:**

- **G3, before T1: the recovery rule against R-17.** Options:
  - (a) Recommended: recover a wrapped end only when the implied length is at most 480 minutes.
    `ignoresMalformedTimelineLines` stays unchanged, and R-17 holds as written.
  - (b) The literal SPEC reading. Every end earlier than the start reads as 24:00.
    `ignoresMalformedTimelineLines` changes its expectation for `11:00-10:00`, with the chat
    explanation first and never deleted. R-17 and SPEC Constraints are amended to name it.
- **G2, before T1: unreadable `minutes` text.** `perg --minutes abc` and MCP `"minutes": "abc"`.
  - Recommended: approve. It is the same sentence through a shared parser, and it closes ADR-0063
    §D9's bullet. It widens the SPEC's R-08 from «out of range» to «out of range or unreadable»,
    which is chain 3's own rule, cited by the SPEC.
  - Declining keeps it named in ADR-0075 §D9.
- **G1, before T4: the colour of a deadline not yet passed.**
  - `.textSecondary` is recommended. It matches «SCADENZE IN ARRIVO»'s date, and it stays distinct
    from the event, block and task colours in the month.
  - The alternatives are `.taskScheduled`, which reads as a block, and `.taskOpen`, which reads as a
    task.
- **G4, a test assertion that changes meaning.** It covers `rejectsInvalidTimes`, plus
  `ignoresMalformedTimelineLines` under G3(b). Each is explained in chat before the edit.
- **G5, commit and push.** Only on the feature branch, never on `main`, with Conventional Commits.
  - The pre-push merge-integrity and landing checks run (ADR-0061/0062).
  - The PR body says `Closes #573`.
  - `TODO.md`'s `PG-259` line closes through the usual sync PR.
- **G6, ADR renumbering** immediately before the merge (`docs/adr/README.md` rule 1). `PG-260` and
  `PG-298` are in flight.
- **G7, optional.** A chain-index entry for ADR-0075 in `CLAUDE.md`. A `CLAUDE.md` edit is
  Stefano's call.
- **UI suite:** not run for this chain beyond what `scripts/uitests.sh --affected` selects at merge
  (`CLAUDE.md` merge-gate rule). It is advisory and does not block.

## Open for Stefano

G1, G2 and G3 were answered on 2026-09-28; see «Gate answers» at the top. Nothing else is open.
