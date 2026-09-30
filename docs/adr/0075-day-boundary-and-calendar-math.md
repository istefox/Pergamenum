# ADR-0075: Day-boundary and calendar math — a time block ends at 24:00 and is placed in free time, an event is drawn on each day as the part of it that day covers

- Status: **accepted**. Merged to `main` via PR #722 (`5343eb58`, 2026-09-30), for `PG-259`/#573.
- Date: 2026-09-28. Written before the implementation, against `2d1adb40` (`origin/main`), tree clean
  apart from `SPEC.md` (`shasum` `f7c1f58`). Every file:line below was read from that tree today.
- **Numbering note.** `0069` is the highest ADR under `docs/adr/` on `origin/main`. `0070` is taken
  by the `PG-298` chain (`fix/pg-298-timeline-backspace-exclude`, commit `c7121c0d`), so this ADR is
  `0071`; `git log --all --oneline -- 'docs/adr/0071*'` was empty on every ref on 2026-09-28. The
  number is rechecked immediately before the merge; if another chain lands 0071 first, this file
  moves with `git mv` and the register in `docs/adr/README.md` gets the entry (rule 1).
  **Renumbered 2026-09-30, before its first commit:** `0071` (`contenitore-managed-document-archive`)
  through `0074` landed on `origin/main` while this chain was in flight, so this ADR is `0075`. Every
  reference in the chain's own files moved with it; `0071` never named this decision on any ref.
- **Plan gates answered 2026-09-28 (Stefano):** G3 = 480-minute cap on recovering a wrapped end; G2 =
  a non-numeric connector duration is refused; G1 = `.textSecondary` for a deadline not yet passed.
  The sections below record these answers as decided (§D1, §D4, §D6).
- Source: `SPEC.md` (Approved 2026-09-28), issue **#573** (`PG-259`, Audit Fable chain 6), ROADMAP
  §Chain 6 items 1–8. Item 4's second half (diary resize clamping) was refuted in the SPEC and is not
  touched.
- **What this extends.** ADR-0004 §D7 (a block's length is a setting: near midnight or the next
  block it may now be shorter), the diary's 24:00 rule (reused, not changed), ADR-0006 (the Oggi
  window's widening is fed by projected ranges), ADR-0013 §D4 (four week kinds, kept) and §D5 (the
  hour drop, which can now report a refused block), ADR-0053 §D2 seam #10 (wrapped, not replaced),
  ADR-0063 §D1 (a connector refuses a malformed number with one sentence in the shared layer).
- **What this amends.** Nothing. ADR-0004 §D5's «the colour deadlines are drawn in everywhere else»
  stops being literally true for the category view and the week plan (§D6); the mini calendar's
  deadline dot it governs is untouched, and §D9 names the gap.
- **Reopens nothing else.** Principles 1 and 3 hold. No on-disk format change: `24:00` is already a
  value the diary writes into the same daily notes (SPEC Constraints). No frontmatter key, no
  `IndexCache.schemaVersion` change, no protected interface touched. `perg` and `pergamenum-mcp`
  output shapes are unchanged.
- **One conflict, settled by gate G3 of the plan.** The SPEC's recovery rule, read literally, and
  R-17 could not both hold: `CalendarTests.ignoresMalformedTimelineLines` asserts that `11:00-10:00`
  is skipped. G3 took the 480-minute cap, so that test stands unchanged and SPEC R-03 was amended;
  §D1 records the decision and the declined alternative.

## Context

The day is treated as unbounded in two places, and the diary already solved the same case.

**Time blocks.** `TimeBlock.timeText` (`Sources/Calendar/TimeBlock.swift:27-29`) writes minute 1440 as
`00:00` through `(minutes / 60) % 24`. `TimeBlockSection.minutes(from:)` (`:186-192`) refuses hour 24,
and `parse` (`:119-124`) keeps a line only when `end > start`. `DayController.write`
(`Sources/Features/Today/DayController.swift:284-295`) rewrites the whole section from the parsed
blocks, so an unparsed line is deleted by the next write of that day. `TimeBlock.resized` and
`TimeBlock.moved` already produce an end of exactly 1440 (`Tests/TimeBlockGestureTests.swift:44-51`,
`:69-73`). `TimeBlock.freeStart` (`:45-52`) tests only whether the start point sits inside a block,
steps by `max(15, duration)`, and its `< 24 * 60` guard ignores the duration: a 60-minute drop at
09:45 above a 10:00 block lands at 09:45–10:45, and a 60-minute drop at 23:30 ends at 1470, written
`00:30`, then dropped. Its three callers are `DayController.addBlock` (`DayController.swift:182`,
reached from «Inserisci Blocco Tempo», `DayReferences.swift:144`, and the hour drop,
`DayController+TaskDrop.swift:49`), `VaultSession.addTimeBlock` (`VaultSession+TimeBlocks.swift:74`,
reached from capture and from `VaultAPI.addTimeBlock`, `Sources/Connector/VaultWrites.swift:240`) and
`TimeBlock.moved` (`:70`). `DayController.addBlock` returns nil in silence; the hour drop then
overwrites `lastDrop` with a success line.

The diary's two functions already say what a time-block line should: `DiaryGrid.timeText`
(`Sources/Core/Diary/DiaryEntry.swift:86-89`) writes `24:00` for `dayMinutes`, and
`DiarySection.minutes(from:)` (`:295-303`) reads hour 24 minute 0 as 1440 and nothing else past 23.

**Events.** `CalendarService.bucketed` (`Sources/Calendar/CalendarService.swift:210-227`) puts an event
on every day it touches, with an exclusive end. The Day view (`DayTimeline.swift:239-246`) and the
week plan (`WeekPlan.swift:227-230`) each convert `event.start` to minutes privately and place every
copy at the start day's clock time with the full duration. A Monday 09:00 to Wednesday event is drawn
at 09:00 on Tuesday; a 22:00–01:00 dinner is drawn at 22:00 the next day. `DayTimeline.hours`
(`:20-28`) widens the hour window from the unclipped start and duration, so the Tuesday grid is
stretched to midnight.

**Five smaller defects** (ROADMAP §Chain 6 items 4–8): `DiaryEntryCard.swift:172,183` measure drags
in the `.local` space of the view they move, against the measured warning at
`TimelineBlockBox.swift:107-115`; `CategoryView.swift:114-117` and `WeekPlan.swift:29` paint every
deadline `.taskOverdue`; `MiniCalendar.swift:80` uses `id: \.self` over `[CalendarDate?]` padded with
nil, and `:68`/`:176` use `id: \.self` over `["L","M","M","G","V","S","D"]`; `TodayView.swift:206`
embeds any open note whose path contains the day's compact date; `DiaryTimeline.swift:52-57` assigns
`now` every 30 s whatever day is shown, though the line is drawn only for today (`:169`).

## Decision

### §D0 — The SPEC's decisions are registered, not reopened

These are settled in SPEC §Decisions, with their rejected alternatives, and this ADR carries them as
they stand: blocks follow the diary's midnight rule (not a 23:59 cap); creation shortens rather than
overlapping, refusing outright or moving earlier; lines already on disk are recovered, both the
`00:00` end and the wrapped end; an event is drawn per day as the part that day covers, with a
fully covered day in the all-day row, through one shared helper; connectors refuse an out-of-range
duration rather than clamping it; a deadline is overdue only when it has passed, by the task rows'
rule; the Today pane matches the daily note by exact path; the diary timer runs only on today; zero
GUI tests. What follows is how, and the choices the SPEC left open.

### §D1 — A time block ends at 24:00, through the diary's own two functions (R-01, R-02, R-03, R-17)

- `TimeBlock.timeText(_:)` returns `DiaryGrid.timeText(_:)`, and `TimeBlockSection.minutes(from:)`
  returns `DiarySection.minutes(from:)`. Neither diary function changes. For every value other than
  1440 and `"24:00"` both produce what the time-block copies produce today (checked against every
  case of `CalendarTests.parsesValidTimes`/`rejectsInvalidTimes`), so every existing formatting and
  parsing test other than the one R-17 flips holds as written.
- The rule is shared, not copied: two copies of one rule are how the two timelines diverged. Both
  files compile into all three targets (`TimeBlock.swift` is named in `sharedSources`,
  `Project.swift:103`; `DiaryEntry.swift` is under `Sources/Core/**`), so the connectors see the same
  rule.
- `minutes(from:)` accepts `24:00` wherever it appears; position is `parse`'s business. With `s` the
  start and `e` the end as read:
  1. `s` must be below 1440, so a line starting `24:00` is skipped;
  2. `e == 0` with `s > 0` reads as 1440. This is the `00:00` end of a block that ran to midnight,
     unconditionally: `resized` can produce any start with an end of midnight, so no length bound is
     sound here;
  3. `0 < e < s` reads as 1440 when `e + 1440 - s ≤ TimeBlock.durationRange.upperBound` (480), and is
     skipped otherwise. **Decided at gate G3.** Such a line is one the old formatter could have written:
     creation only ever used a length from the settings range, so a wrapped line from the app
     implies at most 480 minutes (`23:30-00:30` implies 60 and reads as `23:30-24:00`). A line like
     `11:00-10:00` implies 1380 and is not a wrap; it stays malformed, which is what
     `CalendarTests.ignoresMalformedTimelineLines` (`Tests/CalendarTests.swift:79-90`) asserts;
  4. then `e > s`, as today, so `00:00-00:00` is still skipped (§D9).
- Nothing is rewritten on a read. The corrected form reaches the file on the next write of that
  day's section, which renders from the parsed blocks.
- The block model is `0 ≤ start < end ≤ 1440` (SPEC Data model).
- The connectors' `--at`/`at` parser (`VaultAPI.minutesFromMidnight`, `VaultLookup.swift:39-47`) is
  not this function and keeps refusing `24:00` as a start, pinned by `ConnectorTests.swift:63`.
  `TaskTime(text: "24:00")` keeps returning nil (`TaskTests.swift:290`).

**Gate G3, the conflict and its answer.** The SPEC's decision read «an end earlier than the start
(a line that wrapped past midnight) reads as `24:00`». Read as covering every such line, it recovered
`11:00-10:00` as `11:00-24:00`. `ignoresMalformedTimelineLines` would then have failed, so a second
existing test would have changed meaning, and R-17 («every other existing calendar, diary and week
test stays green unchanged») and SPEC Constraints (one test flips) would have stopped being true.
The SPEC did not name that test. The plan recommended rule 3 as written above, and Stefano took it
at G3 on 2026-09-28: it reads the SPEC's parenthesis as the definition of a wrap, keeps R-17 whole,
and still recovers every line the app wrote. SPEC R-03 was amended to state the cap. The literal
reading (rule 3 without the bound, `ignoresMalformedTimelineLines` changing its expectation for the
`11:00-10:00` line) was declined. Either way, the parser change stayed inside §D1.

### §D2 — One placement search, with a minimum each caller states (R-04, R-05, R-06)

`TimeBlock.freeSlot(from:in:duration:minimum:) -> TimeBlock.Slot?` replaces `freeStart`, and
`Slot` carries a start and a duration.

1. The start is `snap(preferred)`, the quarter-hour snap every block already gets.
2. While the start is before 1440:
   - if a block contains it (`start ≤ s < end`), the start moves to that block's end, exactly, not
     snapped. A hand-written `09:00-09:10` leaves 09:10 usable and no gap is invented;
   - otherwise the free run is `min(first block start after it, 1440) - start`. When the run is at
     least `minimum`, the search returns the start and `min(duration, run)`. When it is shorter, the
     start moves to the end of the block that closed the run, and the search goes on.
3. At 1440 there is no slot, and the search returns nil.

Every step moves the start strictly forward, because every block the parser or a creation path
produces has `end > start`. A block with no length is ignored by the search rather than trusted, so
a hand-built list cannot stall it.

The callers state the minimum:

- **Creation** passes `min(15, duration)` (SPEC). `DayController.addBlock` and
  `VaultSession.addTimeBlock` write the slot's duration, not the requested one.
- **A move** passes the block's own duration. A move keeps its length, which it always did. It also
  no longer lands on top of the next block, which the start-only test allowed: a 60-minute block
  moved to 09:30 above a 10:00–11:00 block now lands at 11:00 instead of 09:30–10:30.

A run shorter than the minimum is passed over, not refused. The SPEC's UI flow refuses only «when
no slot of at least 15 minutes remains», and the existing placement tests assume a taken hour
slides on (`VaultSessionTests.swift:245-260`, `TaskComposerTests.swift:317-332`,
`ConnectorTests.swift:440-459`, `DayControllerTests.swift:61-80`). All of them hold as written, as
do the four `moved` tests in `TimeBlockGestureTests.swift:17-51`.

### §D3 — A refused creation says so in the day view's one banner (R-07)

- The day view has one place that shows a sentence: `lastDrop`'s banner, drawn at the top of all
  three scales (`TodayView.swift:39`, `:87-111`). `DayController.report` reaches `problems` and
  `vault.problems`, and the latter is drawn only in Settings (`SettingsView.swift:297-299`), despite
  `report`'s doc comment calling it «the banner the user actually reads». That is why `move`'s
  refusal (`DayController.swift:209`) is invisible today.
- `DayController.addBlock`, on a nil slot, reports the sentence as today's `report` does and sets
  `lastDrop = Drop(summary: sentence, journalID: nil, isRefusal: true)`. «Inserisci Blocco Tempo»
  shows the refusal through that alone.
- The hour drop's `>` write has already landed and is journalled when `addBlock` runs. When
  `addBlock` returns nil, the drop sets one banner that says both things: where the task went, then
  the refusal. It keeps `journalID`, so «Annulla» still undoes the move, and it sets
  `isRefusal: true`, because the hour was the part of the gesture that asked for the block and the
  block was not made.
- `Drop` and `lastDrop` keep their names. The doc comments widen from «what a drag left behind» to
  the last drop or block insertion. No second banner is added.
- The session path is unchanged: `VaultSession.addTimeBlock` records its problem
  (`VaultSession+TimeBlocks.swift:76`), which is what capture and both connectors already read.
- A shortened block is not a refusal. In the app the block is on the timeline at its real length,
  and no banner is raised. The connectors say it in their `note` (§D4).
- **Implementation notes (2026-09-29, from the PG-259 hand check).**
  - A task dropped on a full last hour crashed the app. The composed two-sentence summary wrapped
    under the banner's old `.fixedSize(horizontal: false, vertical: true)`, so the banner above the
    Today view's `HSplitView` grew while `CoreDragCommitDropAnimationTransaction` was still
    committing, and AppKit threw from `-[NSWindow _postWindowNeedsUpdateConstraints]` through
    `SplitViewChildController.hostingView(_:didUpdateMinSize:maxSize:)`. Deferring the state write
    did not help (measured): the drag's nested run loop keeps draining the main queue.
  - The constraint that fixed it: **the banner never changes height after it appears.** The first
    fix, `.lineLimit(2, reservesSpace: true)`, stopped the crash in the hand check, but
    `TaskDropBannerTests` then measured it still growing: the reservation leaves out the line
    spacing `themedText` adds (`.caption`: two lines reserved 26pt, two real lines took 32pt), so a
    one-line banner replaced by a wrapped one grew by 6pt. The banner, extracted into
    `TaskDropBanner` (`Sources/Features/Today/TaskDropBanner.swift`), now sizes its text slot with a
    hidden two-line text in the same themed style and draws the summary over it with
    `.lineLimit(2)`; a longer summary is readable through `.help`. The test pins one fitting height
    at 640pt for a one-line summary, the composed refusal, the direct refusal and a summary longer
    than two lines, in a window never shown. Hand-checked in the GUI on 2026-09-29: no crash on
    the full-last-hour drop, the composed refusal and «Annulla» shown, the empty-hour drop unchanged.
  - `addBlock` gained `announcesRefusal: Bool = true`, and the hour drop passes `false`, so the drop
    is the one place that composes its banner. On its own it did not fix the crash, and it is not
    what the crash needed; it stays because one composer per banner is the clearer shape.
  - The banner speaks the interface's date: both refusal sentences end in `day.italianForm`
    (`11/08/2026`), and the direct path's reads «Blocco tempo non creato: nessuno spazio libero il
    …». `report`, and through it `problems`, `vault.problems`, the session and the connectors, keep
    their `compactForm` sentences unchanged.
  - **The «24:00» row.** A block ending at 24:00 widens the Day timeline to `last == 24`, and
    `DayTimeline.hourLines` then drew a «24:00» row whose drop handed `TaskTime(hour: 24, minute: 0)`
    to `drop`. Nothing reached the disk at 24:00, because `TaskTime.init(hour:minute:)` clamps the
    hour to 0…23 (`TaskItem.swift:127`, kept as is), but the row scheduled at 23:00 under a label
    promising midnight. Decided (Stefano, 2026-09-29): **the «24:00» row is not a drop target.**
    `DayTimeline.droppableHours(in:)` ends at 23; the row is still drawn, without `TaskDropTarget`
    or the `timeline-hour-24` identifier, so the grid's height, the bottom line and the window
    maths (R-11, `HourWindowTests`) are unchanged. `DayControllerTests.theMidnightRowIsNotADropTarget`
    pins the seam.

### §D4 — The connectors check the duration once, in the shared layer (R-08)

- `VaultAPI.addTimeBlock` refuses a `minutes` outside `TimeBlock.durationRange` (`5...480`) before any
  disk work and before the session is asked, as a usage error. It uses one sentence that names the
  argument and the value, in ADR-0063 §D1's shape: `«minutes» vuole una durata da 5 a 480 minuti:
  «481» non lo è`. `perg` and the MCP server both reach it, so neither front end changes for the
  range. `perg` has no harness, so its half is covered by the shared-layer test and by review, as in
  ADR-0063.
- `TimeBlock.durationRange` becomes the one statement of the range. `VaultSettings`' clamp
  (`VaultSettings.swift:202`, `min(max(minutes, 5), 480)`) reads it, so the settings file and the
  connectors cannot disagree about it later.
- A valid duration follows §D2. When the slot is shorter than asked, `WriteSummary.note` says so
  («accorciato a N minuti»), joined to the existing «spostato alle…» sentence when both apply. The
  shape (`path`, `applied`, `diff`, `note`) does not change. Without it, the connector would write
  something other than what was asked and say nothing, which is the reason the SPEC gives for
  refusing to clamp.
- **Unreadable text was gate G2 of the plan, approved.** Before this chain `perg --minutes abc`
  became nil through `flatMap(Int.init)` (`Sources/CLI/Commands/WriteCommands.swift:137`), and so did
  MCP's lenient `arguments.int("minutes")` (`ToolArguments.swift:41-49`, `VaultHost.swift:255`). Both
  then fell back to the vault default, the case ADR-0063 §D9 named and left open. The resolution
  reads the text through one shared parser, `VaultAPI.blockMinutes(parsing:)`
  (`Sources/Connector/VaultWrites.swift`), with the same sentence; `perg` calls it, and MCP reads its
  value through `ToolArguments.checkedInt(_:parsing:)`, which keeps absent apart from unreadable
  (ADR-0063 §D1.2/§D1.4). This closes the `--minutes abc` half of ADR-0063 §D9's bullet;
  `--ordinal abc` stays open there. No §D9 bullet is needed here.

### §D5 — An event is projected onto the day before it is drawn (R-09, R-10, R-11)

- A new file, `Sources/Calendar/DayProjection.swift`, is pure Foundation and compiled into the app
  only: neither connector knows EventKit (`CLAUDE.md`, «AI connector»). It holds:
  - `enum DayProjection { case none, allDay, timed(startMinute:endMinute:) }` (SPEC Data model);
  - `DayProjection.of(start:end:on:calendar:)`, with `calendar` defaulting to `.current`;
  - `DayProjection.minuteOfDay(_:calendar:)`, the one date-to-minute conversion;
  - `CalendarEvent.projection(on:)` and `[CalendarEvent].projected(on:)`. The latter returns the
    all-day events and the timed events with their clipped minutes.
- **The rule.**
  - The day runs from its local midnight to the next local midnight, the computation
    `EventKitStore.dayRange` already makes (`EventKitStore+Dates.swift:8-18`). A DST day is 23 or 25
    hours; the minutes are clock minutes.
  - An event that starts at or before the day's midnight and ends at or after the next is `allDay`.
  - An event whose clipped range is empty is `none`. That includes an end exactly at the day's
    start, so an event ending at midnight belongs to the day before only, as `bucketed` already
    asserts (`WeekPlanTests.swift:209-226`).
  - Anything else is `timed`, with the clipped start's clock minute, and 1440 when the clipped end
    is the next midnight.
  - A zero-length event inside the day is `timed(m, m)`. It is drawn at the view's existing
    15-minute floor, as today, and is not made invisible.
- **`isAllDay` wins.** An event EventKit flags all-day is `allDay` on every day it touches, whatever
  end it reports. The minute rule applies only to timed events. `splitByAllDay`
  (`CalendarEvent.swift:53-55`) stays and does the flag half.
- **Day view.** The all-day strip lists `projected(on: day).allDay`: the flagged events plus every
  timed event that covers the day. The grid places the timed ones at their clipped minutes, keeping
  its `max(15, …)` drawing floor. The hour window is widened from the clipped ranges through a new
  static seam, `DayTimeline.hours(for:blocks:timed:)`, which feeds the existing
  `hours(for:startMinutes:endMinutes:)` (ADR-0053 §D2 seam #10). `openEventNote` keeps stamping the
  event's own clock start and end (`DayTimeline.swift:114-127`), now through `minuteOfDay`. The
  view's private `minutes(from:)` and `duration(of:)` are deleted.
- **Week plan.** `eventEntries` takes the day. `allDay` gives `minutes: nil` and sorts first, as an
  all-day event does today. `timed` gives the clipped start and its `timeText`. `none` is dropped.
  The private `minutes(from:)` is deleted.
- `CalendarService.bucketed` is unchanged: it decides the days, and the projection decides the hours
  on each.

### §D6 — One overdue rule, four week kinds (R-13)

- The comparison inside `TaskItem.isOverdue(on:)` (`Sources/Core/Tasks/TaskItem.swift:86-89`)
  becomes a named static, `TaskItem.isPastDue(_:on:)` (`due < day`). `isOverdue(on:)` keeps its
  open-state guard on top. `Category.isDeadlineOverdue(on:)` (`Sources/Core/Categories/`) calls the
  same static. «By the same rule task rows use» is then true by construction, not by two `<` signs
  agreeing.
- **Week plan.** `WeekEntry` gains `isOverdue`, defaulted to false so the memberwise initialisers in
  `WeekPlanTests.swift:146,156` and `TaskDropTests.swift:33` compile unchanged. A deadline entry sets
  it from `task.isOverdue(on: today)`, so a done task's past deadline is not overdue, exactly as its
  row is not. `WeekPlan.entries` gains `today:`, defaulted to `.today` so the five existing calls
  compile. `DayController.span` passes it explicitly.
- A computed `WeekEntry.token` returns `.taskOverdue` for an overdue deadline, the ordinary deadline
  colour for one not past, and `kind.token` for every other kind. `WeekEntryRow` and
  `MonthEntryRow` (`WeekEntryRows.swift:34`, `:70`) read it.
- Overdue is a property of the entry, not a fifth `WeekEntryKind`: ADR-0013 §D4 fixes four kinds and
  no fifth, and the design gallery's mockups keep reading `kind.token`.
- **The ordinary deadline colour was gate G1 of the plan, answered `.textSecondary`.** The app has
  no deadline token that is not red. The one place that already paints a deadline not yet passed is
  «SCADENZE IN ARRIVO» (`DayReferences.swift:164-168`: flag `.taskScheduled`, date `.textSecondary`).
  The plan recommended `.textSecondary` and Stefano chose it (SPEC R-13 amended). In the month, where
  colour alone carries the kind, `.taskOpen` would read as a task and `.taskScheduled` as a block;
  `.textSecondary` stays distinct from all three. Every colour goes through a token.

### §D7 — The four smaller fixes (R-12, R-14, R-15, R-16)

- **Mini calendar (R-14).** `MonthGrid` gains a pure layout for the view:
  - `cells(of:)`, rows of an identifiable `Cell` whose id is its position in the grid, with the
    optional date;
  - `weekdayHeaders`, the seven initials, each identified by its position.

  `MiniCalendar` iterates those, rows included. `MonthGrid.weeks(of:)` is unchanged, because its
  tests read it. A position identity is enough for a grid whose cells never reorder.
- **Today pane (R-15).** `VaultController.isDailyNote(_:for:)` compares the path with
  `dailyNotePath(for:)` (`VaultController+TimeBlocks.swift:14-17`), the path every other daily-note
  lookup builds (`RootView.swift:55` already compares exactly). `TodayView.noteBody` calls it.
- **Diary gestures (R-12).** Both `DragGesture`s in `DiaryEntryCard` take
  `coordinateSpace: .global`, the `TimelineBlockBox` precedent. Apple's documentation (Context7
  `/websites/developer_apple_swiftui`, read 2026-09-28) gives
  `init(minimumDistance:coordinateSpace: some CoordinateSpaceProtocol = .local)`, with `.global` at
  the root of the view hierarchy.
- **Diary timer (R-16).** The `.task` becomes `.task(id: controller.day)`. It returns at once unless
  the shown day is today. On each tick it stops once the clock has left that day, after one last
  assignment, so the line disappears at midnight rather than freezing.

### §D8 — What is tested where

Zero GUI tests (SPEC). Every behaviour with a seam is a unit test in `PergamenumTests`, in the files
the SPEC's Test seams name:

- `CalendarTests`: formatting, parsing, recovery, round trip, the search, and R-17's flip.
  `rejectsInvalidTimes` loses `"24:00"` and gains `"24:01"` and `"25:00"`; `parsesValidTimes` gains
  `("24:00", 1440)`.
- `TimeBlockGestureTests`: moves and resizes ending at midnight surviving write and read, and a move
  that no longer overlaps.
- `DayControllerTests` and `VaultSessionTests`: shortening and refusal through the controller, the
  hour drop and the session. `DayControllerTests` also covers `isDailyNote`.
- `ConnectorTests` and `scripts/mcp-smoke.py`: the duration range, and the shortening `note`.
- `WeekPlanTests`: the projection and the week entries' placement and overdue flag.
- `HourWindowTests`: the window widened from projected ranges.
- `MonthGridTests`: cell and weekday identities.
- `CategoryRegistryTests`: the category deadline predicate.
- `TaskDropBannerTests` (added after the hand check): the drop banner's constant height, hosted in
  a window never shown (`HostedViewSupport.swift`), so still no GUI test.

R-12 and R-16 are verified by hand (SPEC `no-test`).

### §D9 — Named here and not fixed

- **`DayController.addBlock` places against `blocks` as they stand at the call**
  (`DayController.swift:176-195`), outside the write queue (`:284-295`). Two blocks created before
  the first write lands are placed against the same stale list and can still overlap. Fixing it
  moves placement inside the queue and changes `addBlock`'s synchronous return, so it is its own
  ticket.
- **A refused move is still silent in the day view.** `DayController.move` reports to the Settings
  list only (`:209`), and the dragged block snaps back. §D2 makes refusals more frequent, since a
  move can no longer overlap. The §D3 banner is the obvious surface; the SPEC scopes R-07 to
  creation.
- **Publishing a block that ends at 24:00: verified, closed.** Its end is built with
  `EventKitStore.date(day, hour: 24, minute: 0)` (`DayController.swift:237-243`), which calls
  `Calendar.current.date(from:)`. On macOS 27 in Europe/Rome, hour 24 of 2026-08-20 yields
  `2026-08-20 22:00:00 +0000`, the local midnight that starts the 21st, equal to
  `date(from:)` of 2026-08-21 with no hour (checked 2026-09-29). The published event therefore ends
  at the right instant. Kept here only as the record that it was checked.
- **`00:00-00:00`** is still skipped and deleted on the next write (§D1 rule 4). A block from
  midnight to midnight could only come from a resize over a 00–24 window.
- **A wrapped line implying more than 480 minutes** (G3's cap) is still skipped. Only
  a connector call with a `minutes` above the settings range, accepted before this chain, could have
  written one.
- **Deadlines are still red elsewhere.** The mini calendar's deadline dot (`MiniCalendar.swift:111`,
  ADR-0004 §D5) and the `!date` marker of task rows (`TasksView+Row.swift:52`,
  `LinkedTasksPanel.swift:91`) paint every deadline `.taskOverdue`. After §D6 the week and the
  category view are the only two surfaces that tell a future deadline from a past one.
- **`MiniCalendar.hasDailyNote`** (`:153-162`) builds the daily-note path by hand instead of calling
  `dailyNotePath(for:)`.
- **The connector's «spostato alle…» note** compares the placed start with the unsnapped request
  (`VaultWrites.swift:250-252`), so `--at 09:07` on a free morning says it moved to 09:00.
  Pre-existing and cosmetic.

## Alternatives considered

### §D1: where the 24:00 rule lives, and which lines it recovers

- **A second copy inside `TimeBlock`.** Three lines, no coupling. Rejected: two copies of one rule
  is exactly how the time-block formatter came to disagree with the diary's, and the ROADMAP's fix
  is to share it.
- **A neutral owner (`DayClock`) that both call.** The cleanest naming. Rejected for this chain: it
  edits the diary's file, which the SPEC puts out of scope as the correct reference, and it adds a
  type to hold two one-line functions. If a third timeline ever needs the rule, the move is
  mechanical.
- **Recover every end earlier than its start** (G3's alternative). It is the SPEC sentence read
  literally, with no bound to explain. Declined at G3 (2026-09-28): it would have turned a typo such
  as `10:00-09:00` into a 14-hour block the next write makes permanent, and it broke R-17 on a test
  the SPEC did not consider.

### §D2: how the search advances, and what a short run means

- **Step in quarter hours from the snapped start.** It keeps every start on the quarter. Rejected:
  after a hand-written block ending at 09:10 it lands on 09:15 and invents a five-minute gap. After a
  block ending at 09:20 it lands on 09:30, so a 10-minute request in a 12-minute gap, a SPEC edge
  case, fails. The old step, by `max(15, duration)`, is the defect itself.
- **Refuse at the first run shorter than the minimum.** It is simpler to state. Rejected: the SPEC's
  UI flow refuses only when no slot of at least 15 minutes remains. The existing «a taken hour
  slides on» tests would then depend on whether the next run happened to be short.
- **Let a move shorten too.** One minimum for everyone. Rejected: a move that changes a block's
  length is a resize nobody asked for, and `resized` already exists for that.

### §D3: where the refusal is shown

- **A new `blockRefusal` property with its own line on the timeline.** It is closer to the grid.
  Rejected: `TodayView` already argues that one banner, not three, answers a gesture made on any
  scale (`:87-91`), and a second banner is a second thing to dismiss.
- **The hour drop keeps `isRefusal: false`.** The move did succeed. Rejected: the user dropped on an
  hour to get a block. A green check over a block that was not made is the silence R-07 removes.

### §D5: where the projection lives

- **`Sources/Core`, shared with the connectors.** Rejected: neither connector reads EventKit, and
  `CalendarEvent` imports it. A shared file would carry a type nobody on that side can build.
- **Clipping inside each view.** Rejected by the SPEC: that is the duplication that let the two
  views drift.

### §D6: how overdue reaches the week

- **A fifth kind, `.overdueDeadline`.** Rejected: ADR-0013 §D4 fixes four kinds, and a kind that
  changes at midnight would make an entry's identity depend on the clock.
- **Decide overdue in the view from the column's day.** The view knows the day but not the task's
  state, so a done task's past deadline would turn red. Rejected: the rule includes the open-state
  guard, and only `WeekPlan` has the task.

## Consequences

### Positive

- No time-block line is lost to where it ends. Lines damaged by the old formatter are repaired on
  the next write of their day.
- No new block overlaps another or crosses midnight, from any of the three creation paths or from a
  move.
- A refused creation is visible where it was attempted.
- A multi-day event sits on each day at the hours it occupies, and a fully covered day shows it once
  in the all-day row instead of a stretched grid.
- One date-to-minute conversion for events, one overdue comparison, one duration range, and one
  24:00 rule.

### Negative

- A hand-typed line whose end is before its start and within 480 minutes of it (`18:00-01:00`) now
  reads as running to midnight, where before it was dropped on the next write. The parser cannot
  tell such a typo from a wrap. The result is visible and correctable, where the old one was silent
  loss. G3's declined alternative would have read every such line this way.
- A block created near midnight or next to another block can be shorter than the vault's setting.
  The app says nothing about it: the block is drawn at its real length.
- `TimeBlock.swift` now depends on two diary functions, which a reader of the time-block code has to
  follow into `DiaryEntry.swift`.
- Moves that used to land overlapping now slide further or are refused (§D9: refused silently).

### Neutral

- `24:00` appears in the connectors' `day` payload `end` field where `00:00` appeared before, for the
  blocks the old code could still read.
- The projection works on local clock minutes. On a DST day the grid keeps drawing 24 hourly rows,
  as it does today.

## Acceptance

- Every R-id of the SPEC is covered by a unit test named in §D8, except R-12 and R-16, which are
  verified by hand: a diary entry dragged and resized follows the pointer without oscillating, and a
  past day shows no now-line while today does.
- `PergamenumTests` is green in full. The only existing test whose expectations change is
  `CalendarTests.rejectsInvalidTimes` (R-17); `ignoresMalformedTimelineLines` stays unchanged, G3
  having taken the 480-minute cap.
- `perg` and `pergamenum-mcp` build. `scripts/mcp-smoke.py` passes with the new duration checks.
- `rg -n 'dateComponents\(\[\.hour, \.minute\]' Sources/Features/Today/DayTimeline.swift
  Sources/Features/Today/WeekPlan.swift` returns nothing (R-10).

## References

- `SPEC.md` (Approved 2026-09-28); issue #573 / `PG-259`; ROADMAP §Chain 6.
- ADR-0004 §D5/§D7; ADR-0006; ADR-0013 §D4/§D5; ADR-0043 (the write queue in
  `DayController.write`); ADR-0053 §D2 seam #10; ADR-0063 §D1/§D9.
- `docs/adr/README.md` rule 1 (numbering).
- Apple, SwiftUI `DragGesture.init(minimumDistance:coordinateSpace:)`, read through Context7 on
  2026-09-28.
