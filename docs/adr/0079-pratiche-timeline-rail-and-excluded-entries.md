# ADR-0079: An excluded message takes its anchored entries out of the app's timeline, and an anchored entry hangs off its message by a rail

- Status: **accepted**. Merged to `main` via PR #864 (`575b7c56`, 2026-10-03), for `PG-369`/#824.
  Written before the implementation; the R-14 hand check (light and dark, 428 pt and a wide
  window, Escludi then Cmd+Z, an entry on another day, the rail token values) was not run at the
  flip, so the landing is recorded, not that check.
- Date: 2026-10-03. Written against `125582d3` (branch `docs/spec-pg-369`). `origin/main` is at
  `719050fb`, whose diff against `125582d3` touches `TODO.md` only. Every line number below was
  read at `125582d3`.
- Number: `0079` was checked free on every ref on 2026-10-03 (`git log --all -- 'docs/adr/0079*'`
  printed nothing; no ref's tree holds a `docs/adr/0079*`). Check again immediately before the
  merge (`docs/adr/README.md` rule 1).
- Source: `docs/specs/pratiche-timeline-rail-and-excluded.spec.md` (Approved 2026-10-03,
  `PG-369`, issue #824), which declares R-01 to R-15. Plan:
  `docs/plans/pg-369-pratiche-timeline-rail-and-excluded.md`.
- **Amends ADR-0076** §D2 (the placement rule gains a case), §D3 (the app's model hides that case),
  §D6's Outcomes and Escludi bullets (entries Escludi or a refused carry leaves in the source no
  longer read as orphaned), §D10 (`anchorState` gains a value), and, for the excluded case, the
  PG-338 SPEC's R-05, R-13, R-15 and R-22, its Escludi and carry («Carrying is append-then-remove»)
  decision bullets, its «Anchor naming a message that is not here» and «Hand-edited anchor line»
  edge cases, its UI flow 4, its «Placement states of an entry» table and its API / interfaces
  bullet on the shared timeline entry's anchor.
  **Extends** ADR-0049 §D8 (one row arithmetic places the rail too), ADR-0036 §D13 (the timeline
  stays read-only) and the PG-364 to PG-367 follow-up recorded in ADR-0076's implementation notes
  (two more tokens on the same inheritance path as `surface.entryNote`/`entryCall`).
- No on-disk format, no frontmatter key, no `Dossier`/`Dossier.render` change, no
  `IndexCache.schemaVersion` bump, no protected-interface change. `PraticaEntryAnchor.line(for:)`
  is untouched.

## Context

### What the SPEC already settled (registered here, not reopened)

One SPEC and one PR for both halves. The link is a vertical rail in the anchored indent, from the
message card's bottom edge to the last anchored entry, with a hook into each entry; every entry
stays its own `List` row. The rail takes its message's lane colour through one new token per
lane. The `↪` glyph leaves the heading; VoiceOver keeps «collegata al messaggio». An anchored
entry whose heading day differs from its message's shows day and time («3 ott 20:22»). An entry
anchored to an excluded message is hidden in the app: not drawn, not counted, not reachable from
the keyboard, still in `pratica.md` and the inspector, nothing written. The connectors list it as
`anchorState: "excluded"`. Each row stays independent: no group selection, no folding. No mockup
beyond the approved ASCII sketch; Stefano's hand check on the Debug build gates the merge. The
SPEC's rejected alternatives (one joined card, entries in the side margin, a coloured bar on the
entry, a neutral or accent rail, keeping the glyph, always day and time, a summary row for hidden
entries, the orphaned status quo, connectors that hide or stay unchanged, group folding) are its
own and are not re-argued here. Its Constraints (placement recomputed on every read, one
Foundation-only rule, read-only rows, every row a `List(selection:)` row, tokens in both themes,
one row arithmetic, 428 to 720 pt, no GUI test, no format change) are inputs to every decision
below.

### Evidence (facts, read at `125582d3`)

- **F1. The rule has four placements and one input.** `PraticaTimelineOrder.Placement`
  (`Sources/Core/Pratiche/PraticaTimelineOrder.swift:15-21`) is `message`, `free`,
  `anchored(messageID:)`, `orphaned(messageID:)`. `arrange(_:)` (`:56-104`) takes only the rows; an
  anchor no message owns becomes `.orphaned` on the spine at its heading date (`:79-82`).
- **F2. The exclusion list already exists and is already maintained.** `Dossier.excluded`
  (`Sources/Core/Pratiche/Dossier.swift:21-23`, key `pergamenum-dossier-excluded`) is written by
  Escludi (`PraticaCommandActions.exclude`, `PraticaCommandActions.swift:212-254`: the id is
  recorded first, the files trashed second, the undo restores the files and then removes the id)
  and by «Sposta in…» on the source pratica. `Dossier.parse(praticaFileAt:)` warns that the index
  cannot answer it (the cache keeps no `pergamenum-*` key, `:61-76`).
- **F3. Both readers already hold the bytes the list lives in.** The app's
  `readManualEntries` (`PraticheController+TimelineRead.swift:197-235`) decodes `pratica.md` once
  and hashes the same `Data` (`:202`). The connector's `entryRows(in:formatter:)`
  (`Sources/Connector/VaultPratiche.swift:305-327`) decodes it once too.
- **F4. Every consumer reads `timeline` or `filteredTimeline`.** `reloadTimeline(from:)`
  (`PraticheController+Ledger.swift:225-251`) assigns `timeline = PraticaTimelineModel.ordered(read.entries)`
  (`:241`). `filteredTimeline` (`PraticheController.swift:369-371`) filters it. The day sections and
  «Inserisci qui» neighbours (`PraticaTimelineView.swift:66-68`), Backspace
  (`PraticheController+DeleteKey.swift`, over `filteredTimeline`), the counts bar
  (`PraticaTimelineView.swift:295-308`, over `timeline`) and the sender menu
  (`PraticheController.swift`, over `timeline`) all start from one of the two.
- **F5. Three exhaustive switches over `Placement`.** `PraticaTimelineModel.ordered`
  (`PraticaTimelineModel.swift:132-143`), `VaultAPI.timeline(ofPraticaFolder:session:)`
  (`VaultPratiche.swift:239-248`) and the parity test (`Tests/PraticheConnectorAnchorTests.swift:237-241`).
  `PraticaMessagePicker.currentAnchor` (`PraticaMessagePicker.swift:21-26`) has a `default`.
- **F6. Two existing tests pin today's Escludi/move behaviour.**
  `PraticaEntryCarryPinnedTests.excludeLeavesTheEntriesByteIdenticalAndOrphanedAndUndoAnchorsThemAgain`
  (`Tests/PraticaEntryCarryPinnedTests.swift:17-41`) expects two `.orphaned` rows in `timeline`
  after Escludi (`:28-30`). `PraticaEntryCarryTests.aRefusedDestinationWriteMovesTheMessageAndLeavesTheEntriesOrphanedInTheSource`
  (`Tests/PraticaEntryCarryTests.swift:194-215`) expects two `.orphaned` rows in the source after a
  refused carry (`:213`), where the source now excludes the moved id.
- **F7. The row arithmetic and the indent.** `PraticaTimelineModel.rowColumns` and
  `anchoredIndent` (`PraticaTimelineModel+Layout.swift`) place the card and the note column; an
  anchored entry's row and its message's row reserve the same slot on the same side, so both rows
  get the same `PraticaRowColumns`. The indent is `theme.spacing(.l)`, 24 pt, on the lane's own
  edge. `LaneRowArrangement` (`PraticaLaneRowLayout.swift`) is the one `Layout` that places them,
  and its `sizeThatFits` is the taller of card and slot.
- **F8. The row background is opaque and spans the row view.** Measured in PG-364's hand check and
  pinned by `PraticaTimelineLaneHostedTests.theRowBackgroundSitsAboveTheSelectedRowsOwnHighlight`:
  `.listRowBackground(backgroundPrimary)` is a full-row hosting view under the cell. A row's height
  is its card's (`PraticaTimelineEntryGapHostedTests`), so the space between two cards of one day
  is the `List`'s own, not the row content's. Nothing measures yet whether a cell can draw into
  that space, or whether row views abut.
- **F9. The heading.** `PraticaEntryRow.header` draws `arrow.turn.down.right` for an anchored
  entry (`PraticaEntryRow.swift:92-96`) and the time alone (`:99`, `PraticaRowFormat.time`); its
  accessibility text appends «collegata al messaggio» (`:132-142`).
- **F10. The connector payload is not protected.** `VaultAPI.PraticaTimelinePayload.Entry`
  (`VaultPratiche.swift:198-209`) is absent from `.claude/protected-interfaces`; `anchorState` is a
  `String?`. `perg`'s `anchorLine(of:)` (`Sources/CLI/Commands/PraticheCommands.swift:122-129`)
  answers `nil` for an unknown state, and the MCP `pratica` tool description
  (`Sources/MCPServer/ToolCatalogue.swift:214-218`) names two states.

## Decisions

### §D1 — The shared rule gains `excluded`, below a present message and above `orphaned`

- `PraticaTimelineOrder.Placement` gains `case excluded(messageID: String)`.
- `arrange(_ items: [Item], excluded: Set<String> = []) -> [Placed]`. An entry whose anchor a
  message owns is `.anchored`, whatever the set holds (R-02). An entry whose anchor no message
  owns is `.excluded` when the set holds it (R-01), `.orphaned` otherwise (R-03). An excluded
  entry sits on the spine by its own heading date, exactly where an orphaned one would, so the
  connectors' order does not depend on the set.
- An empty set is today's rule, row for row (R-04). The default keeps every existing call, test
  included, compiling and meaning what it meant.
- Ids compare as ADR-0076 §D2 compares anchors: Swift string equality, the Message-ID with its
  angle brackets. A hand-typed list entry spelled differently matches nothing and leaves the entry
  `.orphaned`.
- **One reader of the input**, beside the rule:
  `PraticaTimelineOrder.excludedMessageIDs(inPraticaNote text: String) -> Set<String>`, through
  `Dossier.parse(NoteDocument.parse(text).frontmatter.foreignKeys)?.excluded`. Foundation-only;
  it compiles into `perg` and `pergamenum-mcp` through the `Sources/Core/**` glob. Not a second
  YAML reading: `Dossier.parse` stays the only parser of the key, and `Dossier.swift` is not edited.

### §D2 — The set is read from the bytes the entries are parsed from

The app's `TimelineRead` gains `excluded: Set<String>`, filled in `readManualEntries` from the same
decoded text it parses and hashes (F3). The connector's `entryRows` returns the set beside its rows
from its own single decode. Never from the index (F2), never cached, never a second read of
`pratica.md` that could disagree with the first. Placement is recomputed on every read, as
ADR-0076 §D2 requires.

### §D3 — The app drops `excluded` once, where the timeline is stored

`reloadTimeline(from:)` stores
`timeline = PraticaTimelineModel.hidingExcluded(PraticaTimelineModel.ordered(read.entries, excluded: read.excluded))`.
`hidingExcluded(_:)` is a pure function in `PraticaTimelineModel+Placement.swift` that removes every
row whose placement is `.excluded`.

Because every consumer starts from `timeline` (F4), the R-05 properties hold by construction and
no consumer changes: no row, no day section built from it alone, never an «Inserisci qui»
neighbour, never matched by the text filter, never a Backspace target or a keyboard stop, never in
the counts bar's «voci». The inspector reads `pratica.md` itself and keeps showing and editing the
text. Nothing is written.

Escludi then Cmd+Z needs no new code (R-06): Escludi records the id, the message file leaves, the
reload hides the entries; the undo restores the file, removes the id and reloads, and the entries
read as `.anchored` again. The body of `pratica.md` is byte-identical throughout. «Sposta in…» is
unchanged too: any entry left in the source (a refused or partial carry, ADR-0076 §D6) is anchored
to an id the source now excludes, so the same rule hides it there.

This amends ADR-0076 §D3 (the model now has a hidden case) and the Escludi sentence of §D6 ("they
read as orphaned, then anchored again" becomes "they are hidden, then anchored again").

### §D4 — The connectors list `excluded`, through the same rule

`VaultAPI.timeline(ofPraticaFolder:session:)` passes the set from §D2 to `arrange` and maps
`.excluded(messageID)` to `anchorMessageID = messageID`, `anchorState = "excluded"` (R-07). A
message and a free entry still carry neither key; the payload gains no field (F10). `perg pratica`
prints «il suo messaggio è stato escluso da questa pratica (`<id>`)» under such an entry, beside
today's «il suo messaggio non è più in questa pratica (`<id>`)». The MCP `pratica` tool description
names the third state and says the app does not show such an entry while its text stays in
`pratica.md`. `scripts/mcp-smoke.py`'s anchored stage gains one excluded entry, so the value is seen
crossing a real server. The connectors gain no write. This amends ADR-0076 §D10 and the PG-338
SPEC's R-22.

### §D5 — The rail is one pure piece per drawn row, placed by the row's own arithmetic

- **Which piece.** A new `PraticaTimelineModel+Rail.swift` holds
  `enum PraticaRailPiece { none, start, through, last }` and
  `railPieces(in rows: [PraticaTimelineEntry]) -> [PraticaTimelineEntry.ID: PraticaRailPiece]`,
  computed in one pass over the rows the view draws (`filteredTimeline`). A message whose next row
  is `.anchored` to its own Message-ID is `start`; an anchored entry whose next row is anchored to
  the same id is `through` (a full-height line plus a hook); the last of the group is `last` (a line
  down to the hook, then the corner). Everything else is `none`, and the view reads an absent id as
  `none` explicitly. A message whose entries are all filtered out has no anchored neighbour and
  draws nothing (SPEC edge cases). Day sections never split a group, since they key on `placedAt`
  (ADR-0076 §D3).
- **Where.** `railGeometry(columns:lane:step:)` derives, from the row's `PraticaRowColumns` and the
  indent step, the line's x (the middle of the indent: `cardX + step/2` on a leading lane,
  `cardX + cardWidth - step/2` on a trailing one) and the hook's end (the anchored card's near edge,
  `cardX + step` or `cardX + cardWidth - step`). A message row and its anchored rows share their
  columns (F7), so the line has one x down the group. The rail lies inside the indent and takes no
  width from the card or the note column (R-09); `rowColumns`, `anchoredIndent`, `laneWidth` and
  `PraticaRowColumns` are unchanged.
- **Drawn by the arrangement.** `PraticaLaneRowLayout` gains `rail: PraticaRailPiece = .none` and
  the indent step, and `LaneRowArrangement` places a rail view as its first subview, beneath the
  card, from `railGeometry`. The rail is excluded from `sizeThatFits`, so no row changes height.
  It does not hit-test and is hidden from accessibility, so selection, menus, Backspace and the
  double-click/Return toggle reach the row exactly as before (R-13). The hook stops at the card's
  outer edge, so the 2 pt selection outline, drawn inside the card, is never covered.
- **Hook height.** The hook meets the entry at its heading: preferably through a custom vertical
  alignment guide set on `PraticaEntryRow.header` and read by the arrangement from the card
  subview's dimensions; failing that, a constant derived from the card's top padding and the
  heading line. The hosted test checks the hook's y lies within the heading's frame either way.
- **Across rows.** Each piece covers its own row's whole vertical extent, the `List`'s space above
  and below its card included (`start` from the card's bottom edge down, `through` top to bottom,
  `last` top to the hook), and never draws into another row's area. Whether a cell may draw into
  that space, and whether two row views abut, is measured first (gate M1 in the plan), in a hosted
  `List` with the production row chrome, and the measurement is recorded in this record's
  implementation notes. Ordered fallbacks: (1) each piece extends past its card by the measured
  amount; (2) the row's vertical `List` insets go to zero and the same space returns as padding
  inside the row, outside `PraticaLaneRowLayout`, so a piece spanning its cell spans its row view;
  (3) if neither yields an unbroken line, the work stops and the question goes back to Stefano,
  since the SPEC's rejected joined card would then need reopening. The hosted test checks
  continuity by geometry and by pixels sampled in every gap of the group, at 428, 800 and 1600 pt,
  with and without a scroller, received and sent (R-08).
- **Same look collapsed or expanded.** The pieces depend on the rows' order only, never on
  expansion or selection (the SPEC's "each row stays independent").

### §D6 — Two tokens, one per lane

`ColorToken.railReceived = "color.rail.received"` and `.railSent = "color.rail.sent"`, defined in
`pergamenum-light.json`, `pergamenum-dark.json` and `Theme.emergency` (PG-225's contract: a token
missing from the emergency theme crashes the test process). Each is a stronger tone of its lane's
surface (`surface.received`, `surface.sent`), at least 3:1 against `background.primary`, the
timeline's background, in both themes (WCAG 2 non-text contrast). A vault theme without the keys
inherits them from the bundled theme of its appearance, the path `surface.entryNote`/`entryCall`
already take. `PraticaTimelineModel.railToken(for: PraticaLane) -> ColorToken?` answers the host
lane's token, and `nil` for `.entry`. The exact values are the coder's, inside these bounds, and
Stefano approves them in the hand check (R-10, R-14).

### §D7 — The heading: no `↪`, and the day when it differs

- `PraticaTimelineModel.entryHeadingSymbols(for:) -> [String]` is the heading's symbol list:
  `["phone"]` for a call, `["square.and.pencil"]` otherwise, anchored or not. The row iterates it,
  so `arrow.turn.down.right` is gone (R-11). The accessibility text keeps «collegata al
  messaggio» for an anchored entry.
- `PraticaTimelineModel.headingShowsDay(_ entry:calendar:) -> Bool` is true exactly for an
  `.anchored` entry whose `date` and `placedAt` (its message's date) fall on different days of
  `calendar`. The view passes `.current`, the calendar that draws the day headers, which settles
  midnight and zone offsets as the SPEC's edge case asks (R-12). Free and orphaned entries answer
  false and keep the time alone.
- `PraticaRowFormat.dayAndTime(_:)` writes the short day and the time, «3 ott 20:22» in Italian, in
  the person's own locale and zone; a test pins the Italian spelling with an explicit locale and
  zone.

### §D8 — Named and not fixed

- **Other reading surfaces** (export, transclusion, hover preview) are untouched (SPEC, ADR-0076
  §D12).
- **The year is not shown** when an anchored entry's day differs from its message's in another
  year; the day header above names the message's year. The SPEC's example has no year.
- **Readers built before this change** (a `perg` or `pergamenum-mcp` already on the `PATH`, the app
  on a second Mac sharing the vault through iCloud) still place an excluded entry as `orphaned`.
  Nothing on disk differs, so updating them is enough; ADR-0076's PG-367 note gives the same advice.
- **The carry's sentences** («… sono rimaste in «…»», «… sono ora sia in «…» sia in «…»») still name
  the file that holds the entries; after this change the source copy is hidden in the source
  timeline, and the inspector of that `pratica.md` shows it. Their wording is not changed here.
- **A hand-typed exclusion id** not spelled like the message's Message-ID matches nothing (§D1).

## Alternatives considered

- **Hide in the view, or in `filtered`, instead of at the one assignment of `timeline`.** Rejected.
  Five consumers read `timeline` or `filteredTimeline` (F4), and each would have to remember to skip
  the case: the counts bar and the sender menu read `timeline`, which `filtered` never touches. A
  check every caller must remember is the shape CLAUDE.md's `VaultBoundary` agreement warns about.
  Dropping the rows where `timeline` is stored leaves nothing to forget.
- **Drop excluded rows inside `PraticaTimelineOrder.arrange`.** Rejected. The connectors must list
  them (the SPEC's decision), and the rule is shared on purpose (ADR-0076 §D2): a rule that drops
  rows would need a second, connector-only variant, which is the drift ADR-0076 F2 measured.
- **Read the exclusion list through `PraticheController.dossier(at:vaultRoot:)`.** Rejected. It is a
  second read of `pratica.md`; an edit landing between the two reads would place entries against a
  list from a different version of the file than the entries and `timelineOrigin` came from.
- **One rail drawn over the whole `List`**, from row frames gathered through anchor preferences.
  Rejected. A `List` realises only the rows near the viewport, so the rail would break at the edges
  of what is realised, and an overlay above the rows draws above the opaque cards and the selection
  outline, which it would then have to mask.
- **The rail drawn inside `.listRowBackground`.** Rejected. That view spans the full row, insets
  included (F8), so it would work in a different coordinate space from the card. It knows neither
  the card's bottom edge (where `start` begins) nor the heading (where `through` and `last` hook), so
  each piece would be split between two layers.
- **Extend `PraticaRowColumns` with a rail field.** Rejected. Its memberwise value is compared
  whole by the existing layout tests, and R-09 asks for them to stay green as they are. A derived
  `railGeometry` keeps the rail on the same arithmetic without touching the struct.

## Consequences

**Positive.** An anchored entry reads as its message's at a glance, on either side, with the time
and subject given back the glyph's room. Escludi takes the message and its notes away together and
Cmd+Z brings both back, with no write beyond the dossier key the verb already writes. The app and
the connectors agree on why an entry has no message, through one rule. Hiding happens in one
place, so no current or future consumer of the timeline can show an excluded entry by omission.

**Negative.** The app's timeline no longer shows every entry of `pratica.md`: hidden text is
reachable only through the inspector, and a carry's sentence names a file whose source copy is not
drawn there. `PraticaLaneRowLayout` grows a third subview drawn outside its measured height, which
depends on how a macOS `List` lays out row views; the hosted test is the witness if a future macOS
changes it. Two more tokens for every vault theme author to consider.

**Neutral.** No schema, frontmatter or message-file change and no migration. The connector JSON
gains one value of an existing key. Two existing tests change their expectation from `.orphaned`
to hidden, as the SPEC's decision requires (F6).

## Gates

- **G0: the plan and this record**, with the plan's interpretations.
- **M1: the rail continuity measurement**, inside the plan's rail task. It is a measurement, not a
  human gate, until fallback (3) of §D5 is reached; then it is Stefano's.
- **Hand check (R-14)** on the Debug build before the merge: light and dark, 428 pt and a wide
  window, a received and a sent message with two anchored entries (one on another day), Escludi
  then Cmd+Z. The rail token values are approved there.
- **Stefano's usual gates**: commit, push and merge, and the dated notes added to the accepted
  ADR-0076.

## Implementation notes

Written by the implementation on 2026-10-03, against `68ecfdf1` (`origin/main`, which already held
everything the plan asked to merge before Task 2).

- **Gate M1: path (1).** A scratch probe first, then the pinned witness
  `Tests/PraticaTimelineRailHostedTests.swift`, both in a hosted `List` with the production chrome
  (`View.praticaTimelineRowChrome()`, now the one modifier `PraticaTimelineView.list` applies too), at
  428, 800 and 1600 pt, with 0 and 60 filler rows, received and sent (24 cases, all green). Measured on
  macOS 27: the `NSTableView` has a vertical intercell spacing of 0, so consecutive `NSTableRowView`s
  abut (a 60 pt card gave a 68 pt row view at y 38-106, the next 40 pt card 106-154, the next
  154-202); every row view has `clipsToBounds == true`; the cell (`ListTableCellView`) spans the row
  view's full height, and the SwiftUI content sits exactly 4 pt in from the row view's top and bottom.
  So the 8 pt between two cards of one day is 4 pt of each row's own view, and a bar a cell draws past
  its card shows inside its own row and is clipped at the row's edge. Each piece therefore reaches
  `PraticaTimelineModel.railRowInset` (4 pt) past its row's measured bounds, and the pieces of two
  rows meet at the shared row edge. Path (2) was not needed, and nothing changes `listRowInsets`.
  The witness pins the geometry (row views abut and clip, content 4 pt in, every row exactly its
  card's height) and the pixels: every point at the rail's x, from under the message card to the last
  entry's hook, is the rail, and nothing is drawn below the corner.
- **The snapshot renders the table, and it is colour-managed.** `cacheDisplay` in a never-shown window
  draws the `List`'s rows, so the pixel half stayed in the hosted test (the plan's risk did not
  occur). The bitmap reads colours back transformed (the light theme's `#6189B4` came back near
  `#7C9ABD`, the amber card likewise), so a rail pixel is compared with a swatch of the same token
  drawn in a row of the same `List`, never with the token's own components.
- **Hook height: the custom alignment guide propagates.** `PraticaEntryRow.header` sets
  `.alignmentGuide(.praticaEntryHeading) { $0[VerticalAlignment.center] }`, and `LaneRowArrangement`
  reads `card.dimensions(in:)[.praticaEntryHeading]` through the padding, `.clipShape`, the selection
  overlay and the `VStack`. Measured: the hook lies 15 pt under the card's top (8 pt of
  `spacing.s` plus half the heading line); the witness checks it lies within the heading line. The
  token-derived constant fallback was not needed. The guide's default is the card's top, so a future
  break would put the hook on the card's top edge and fail the witness rather than pass silently.
- **How the rail is drawn.** Not one shape but up to two filled rectangles per row, a bar and a hook,
  told apart by a `LayoutValueKey`, declared first so they sit beneath the card and the slot, left out
  of `sizeThatFits`, never hit-tested, hidden from accessibility. `start` runs from the card's bottom
  edge (the card's own height, not the row's, so a taller note slot does not move it) to 4 pt below
  the row; `through` from 4 pt above to 4 pt below with a hook; `last` from 4 pt above down to the
  hook, which with the hook makes the corner. The hook ends on the entry card's near edge, so the
  2 pt selection outline drawn inside the card is never covered.
- **Token values** (Stefano approves them at the hand check, §D6): light `color.rail.received`
  `#8F897C` (3.48:1 on `#FFFFFF`), `color.rail.sent` `#6189B4` (3.65:1); dark `#857F73` (4.42:1 on
  `#1A1917`), `#5F8DB8` (5.01:1). `Theme.emergency` mirrors the light values.
- **Departures from the letter of the plan.** (1) `hidingExcluded` was written with its body in the
  same edit that moved `ordered(_:)` (Task 2), not as a Task 4 stub; nothing reads it before Task 4's
  `reloadTimeline`. (2) The MCP `pratica` description moved into
  `ToolCatalogue.praticaDescription`, in an extension at the foot of `ToolCatalogue.swift`: its two
  extra lines took the enum body to 252 lines, a new `type_body_length` warning, and the extension
  keeps it at its old size (`ToolCatalogue+Writing.swift`'s precedent). (3) The witness's message
  card is a plain block in the lane's colour, not a `PraticaMessageRow`; the entries are the real
  `PraticaEntryRow`. (4) `PraticaEntryRow`'s private `isAnchored` was deleted: with the glyph gone and
  `accessibilityText(for:isExpanded:)` static, nothing read it.
- **Proposed working agreement, for Stefano to accept or drop** (the plan's M1 clause): *A cell of a
  macOS `List` may draw outside its content, but only into its own row view.* Measured on macOS 27
  (ADR-0079 M1): row views abut, each clips to its bounds, and the content sits 4 pt in from the row
  view's top and bottom, so a decoration meant to cross rows is drawn one piece per row, reaching
  exactly that inset, never as one overlay spanning rows. `PraticaTimelineRailHostedTests` is the
  witness if a later macOS changes it.
- **R-14, the hand check: not done yet.** Stefano's, on this checkout's Debug build, before the merge.
- **The status flip to `accepted`: not done yet.** It happens in the first docs change after the merge.

## References

- `docs/specs/pratiche-timeline-rail-and-excluded.spec.md` (PG-369),
  `docs/plans/pg-369-pratiche-timeline-rail-and-excluded.md`
- ADR-0076 §D2, §D3, §D6, §D10, §D12 and its implementation notes (PG-364 to PG-367); ADR-0049
  §D8; ADR-0036 §D13; ADR-0024; ADR-0025 §D9; ADR-0070; ADR-0023 §D1
- `docs/specs/pratiche-message-anchored-entries.spec.md` R-05, R-13, R-15, R-22, the Escludi and
  «Carrying is append-then-remove» decision bullets, the «Anchor naming a message that is not here»
  and «Hand-edited anchor line» edge cases, UI flow 4, the «Placement states of an entry» table and
  the API / interfaces bullet on the timeline entry's anchor; ADR-0076 §D6's Outcomes and Escludi
  bullets
- Code, at `125582d3`: `Sources/Core/Pratiche/PraticaTimelineOrder.swift`,
  `Sources/Features/Pratiche/PraticaTimelineModel.swift`, `PraticaTimelineModel+Placement.swift`,
  `PraticaTimelineModel+Layout.swift`, `PraticaLaneRowLayout.swift`, `PraticaEntryRow.swift`,
  `PraticaTimelineView.swift`, `PraticheController+TimelineRead.swift`,
  `PraticheController+Ledger.swift`, `Sources/Connector/VaultPratiche.swift`,
  `Sources/CLI/Commands/PraticheCommands.swift`, `Sources/MCPServer/ToolCatalogue.swift`,
  `Sources/DesignSystem/TokenKeys.swift`, `Sources/DesignSystem/Theme.swift`,
  `Resources/Themes/pergamenum-light.json`, `Resources/Themes/pergamenum-dark.json`
