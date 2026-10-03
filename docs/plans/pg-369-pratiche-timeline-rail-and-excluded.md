# Plan: Pratiche timeline, a rail for anchored entries and the "excluded" placement (PG-369)

**Requirement set:** SPEC.md

- **SPEC:** repo-root `SPEC.md` (Approved 2026-10-03, `PG-369`, issue #824). It is the authority for
  scope, decisions and R-01..R-15. Task 1 archives it as
  `docs/specs/pratiche-timeline-rail-and-excluded.spec.md`.
  - `UX-BLUEPRINT.md` was read as background on the pane's layout only; it adds no requirement.
    `BRAINSTORM.md` belongs to PG-018 and is not an input.
- **ADR:** `docs/adr/0079-pratiche-timeline-rail-and-excluded-entries.md` (new, `proposed`). It
  amends ADR-0076 §D2/§D3/§D6/§D10 for the excluded case (SPEC R-15 left the choice between a new
  record and an amendment; a new record was chosen because the SPEC brings its own decision set,
  a connector contract change and rejected alternatives, and ADR-0076 already carries two rounds
  of follow-up notes). Recheck the number against every ref right before the merge
  (`docs/adr/README.md` rule 1).
- **Base:** `125582d3`. Every line number below was read there. `origin/main` is at `719050fb`,
  whose diff against the base touches `TODO.md` only. Merge `origin/main` before Task 2, then
  `tuist install` and `tuist generate --no-open`.
- **Delivery: one PR** (SPEC Destination).

## SPEC decisions registered, not reopened

- One SPEC, one PR, both halves.
- The link is a connecting rail in the anchored indent, from the message card's bottom edge to
  the last anchored entry, with a hook into each entry. Every entry stays its own `List` row.
- The rail takes its message lane's colour, through one new token per lane.
- The `↪` glyph leaves the heading; VoiceOver keeps «collegata al messaggio».
- Day and time («3 ott 20:22») only when an anchored entry's day differs from its message's.
- An entry anchored to an excluded message is hidden in the app (not drawn, not counted, not
  reachable), stays in `pratica.md` and the inspector, nothing is written; a present message wins
  over the list; an unlisted dangling anchor stays orphaned with today's caption.
- The connectors list it as `anchorState: "excluded"` with its `anchorMessageID`, on the spine by
  heading date, through the one shared rule.
- Rows stay independent: no group selection, no folding, no summary row.
- No mockup beyond the approved ASCII sketch; Stefano's hand check gates the merge. Zero GUI tests.

## Interpretations resolved here (confirm at G0)

Each is a reading of the SPEC this plan builds on. A different answer re-plans the named task.

1. **R-06's "no write beyond the dossier change"** means `pratica.md`'s body is byte-identical and
   no frontmatter line other than `pergamenum-dossier-excluded` changes, as ADR-0076's plan read
   the PG-338 SPEC's criterion 13. **Recommended.** Task 4.
2. **"Not counted"** includes the counts bar's «N voci» (`PraticaTimelineView.countsText`), which
   today counts every manual entry of the unfiltered timeline. The bar then says what the timeline
   holds, not what `pratica.md` holds. **Recommended**, it is the SPEC's own word. Task 4.
3. **Hiding happens once, where `timeline` is stored** (ADR-0079 §D3), not in `filtered` or the
   view. Every consumer then inherits it. **Recommended.** Task 4.
4. **«Sposta in…» with a refused or partial carry** leaves entries in the source that the source
   now excludes, so they are hidden there, as the SPEC's UI flow says. The two carry sentences
   («… sono rimaste in «…»», «… sono ora sia in «…» sia in «…»») still name the right file and are
   not reworded (SPEC Out of scope: the verbs' behaviour is not changed). Two existing tests change
   their expectation accordingly (Task 4). **Recommended.**
5. **The year is not shown** in «3 ott 20:22» when the two days fall in different years; the day
   header above names the message's year. The SPEC's example has no year. **Recommended.** Task 7.
6. **The connector wording** (proposed, Stefano may reword at G0): `perg` prints «il suo messaggio
   è stato escluso da questa pratica (`<id>`)»; the MCP `pratica` description reads «anchorState
   (anchored; orphaned se il messaggio non c'è più; excluded se il messaggio è stato escluso dalla
   pratica: l'app non mostra la voce, il testo resta in pratica.md)». Task 3.

## What reading the code added (the coder must know these)

- **Three exhaustive switches over `PraticaTimelineOrder.Placement`** stop compiling when the case
  is added: `PraticaTimelineModel.swift:132-143`, `Sources/Connector/VaultPratiche.swift:239-248`,
  `Tests/PraticheConnectorAnchorTests.swift:237-241`. `PraticaMessagePicker.swift:21-26` has a
  `default` and compiles regardless.
- **`PraticaTimelineModel.swift` is exactly 400 lines**, SwiftLint's `file_length` warning
  threshold. Adding the `excluded:` parameter there tips it over: `ordered(_:)` moves to
  `PraticaTimelineModel+Placement.swift` (64 lines) as a pure move (ADR-0045's `Type+Aspect`
  convention).
- **`Tests/PraticaEntryCarryTests.swift` is exactly 400 lines.** Its one changed assertion (`:213`)
  must be net zero lines.
- **`Tests/PraticaTimelineLaneHostedTests.swift` is 380 lines** and `Tests/DesignSystemTests.swift`
  347: the new hosted rail tests and the token tests go in new files.
- **`Sources/DesignSystem/Theme.swift` is already 408 lines** (an existing warning). The two
  emergency entries add to it; no new violation kind.
- **The CLI and the MCP server cannot be unit-tested** (`Sources/CLI/**` and `Sources/MCPServer/**`
  are excluded from the app target). `perg`'s line and the tool description are verified by
  `scripts/mcp-smoke.py` and a hand run of `perg pratica`.
- **`TimelineRead(entries: [], details: [:])`** (`PraticheController+TimelineRead.swift:113`) is the
  one memberwise call: a defaulted `excluded` keeps it compiling.
- **The row background is opaque and full-row** (`PraticaTimelineView.swift:80`, pinned by
  `theRowBackgroundSitsAboveTheSelectedRowsOwnHighlight`), and a row is exactly its card's height
  (`PraticaTimelineEntryGapHostedTests`). How a cell can draw into the space between two cards is
  unmeasured: that is gate M1 in Task 6.

## Standing rules for every task

- **Tooling.** `tuist install` once per fresh worktree; `tuist generate --no-open` after adding any
  file. Every new file falls under an existing glob (`Sources/Core/**` reaches `perg` and
  `pergamenum-mcp` with no `sharedSources` edit). Never edit `.xcodeproj` or `.xcworkspace`.
- **Tester owns the signatures, coder owns the bodies.** Each "Declarations" list belongs to the
  tester half. Each declaration gets a body that keeps today's behaviour, so all three targets build
  and the new tests fail on their assertions, never on compilation.
- **Keep the build green.** Every task ends with the app, `perg` and `pergamenum-mcp` building. Run
  the **full** `PergamenumTests` after every coder half: the placement enum, the timeline model and
  `PraticaLaneRowLayout` are shared contracts.
- **Tests.** Swift Testing only, on `TemporaryVault` with a temporary state base, fixtures in the
  `CarryHarness` / `PraticaReadTimelineAnchorTests` shape. Never disable or delete a test. An
  assertion that must change is explained in chat before it is edited; the known ones are listed in
  Task 4. Zero GUI tests.
- **UI.** Italian strings, colours through tokens only, no new SwiftLint violation in a touched file.
- **Protected interfaces.** `.claude/protected-interfaces` untouched, `Dossier.render` and
  `PraticaEntryAnchor.line(for:)` included. `IndexCache.schemaVersion` unchanged. `Dossier.swift` and
  `PraticaManualEntries.swift` are not edited at all.

---

### Task 1 — Record and G0 (R-15)

Owners: the parent session and Stefano. No production code.

- **G0.** Stefano approves this plan, ADR-0079 (`proposed`) and the six interpretations.
- **Archive the SPEC.** Copy `SPEC.md` to `docs/specs/pratiche-timeline-rail-and-excluded.spec.md`
  (the PG-338 precedent), so ADR-0079 cites a path the next chain's `SPEC.md` does not overwrite.
- **ADR-0076, dated notes, body otherwise untouched** (an accepted ADR: Stefano's gate).
  - Head, after the status bullets: «**Amended 2026-10-03 by ADR-0079 (PG-369).** An entry whose
    anchor no message of the pratica carries, and which the pratica's `pergamenum-dossier-excluded`
    lists, is placed `excluded`: hidden in the app's timeline, listed by the connectors with
    `anchorState: "excluded"`. §D2, §D3, §D6's Escludi bullet and §D10 read with that case; the
    `↪` glyph of §D3 gives way to a rail (ADR-0079 §D5, §D7).»
  - Under §D2: «*Amended 2026-10-03 (ADR-0079 §D1): `arrange(_:excluded:)` places an anchor no
    message owns as `.excluded` when the pratica excludes it, `.orphaned` otherwise; an empty set is
    this rule.*»
  - Under §D3: «*Amended 2026-10-03 (ADR-0079 §D3): `reloadTimeline` drops `.excluded` rows before
    storing `timeline`.*»
  - Under §D6's Escludi bullet: «*Amended 2026-10-03 (ADR-0079 §D3): while the message is excluded
    its entries are hidden, not orphaned, and the undo anchors them again, still with no body
    write.*»
  - Under §D10: «*Amended 2026-10-03 (ADR-0079 §D4): `anchorState` may also be `"excluded"`.*»
- **The PG-338 SPEC** (`docs/specs/pratiche-message-anchored-entries.spec.md`), dated italic notes
  in the shape of its criterion 9's amendment, under three of its criteria (numbered as in that
  file, not as in this SPEC):
  - Criterion 5: «*Amended 2026-10-03 (ADR-0079): unless the pratica excludes that Message-ID; then the
    entry is hidden in the app and reported `excluded` by the connectors.*»
  - Criterion 13: «*Amended 2026-10-03 (ADR-0079): they are hidden, not shown as orphaned; undoing Escludi
    shows them anchored again.*»
  - Criterion 22: «*Amended 2026-10-03 (ADR-0079): and tells `excluded` apart too.*»

### Task 2 — The shared rule gains `excluded` (R-01, R-02, R-03, R-04)

**Declarations (tester):**

- `PraticaTimelineOrder.Placement.excluded(messageID: String)` in
  `Sources/Core/Pratiche/PraticaTimelineOrder.swift`.
- `PraticaTimelineOrder.arrange(_ items: [Item], excluded: Set<String> = []) -> [Placed]`, body
  ignoring the set (today's rule).
- `PraticaTimelineOrder.excludedMessageIDs(inPraticaNote text: String) -> Set<String>`, stub `[]`.
- `PraticaTimelineModel.ordered(_ entries: [PraticaTimelineEntry], excluded: Set<String> = [])`,
  moved from `PraticaTimelineModel.swift` to `PraticaTimelineModel+Placement.swift` (pure move plus
  the parameter, passed nowhere yet).
- Compile-only arms (F5 of ADR-0079): `.excluded` joins `.free, .orphaned: break` in `ordered`; a
  bare `.excluded` arm that sets nothing in `VaultPratiche.swift:239-248` (Task 3 fills it); in the
  parity test's switch, `case let .excluded(messageID): "excluded \(messageID)"`. Add `.excluded`
  beside `.orphaned` in `PraticaMessagePicker.currentAnchor` for consistency.

**Tests (tester), `Tests/PraticaTimelineOrderTests.swift`:**

- An anchor no message owns and the set holds is `.excluded(messageID:)`, its `placementDate` its
  own date, on the spine where an orphan would sit (R-01).
- A present message wins: the same id in the set, message present, gives `.anchored` (R-02),
  including when two messages carry the id (the first owns it).
- An anchor neither owned nor in the set stays `.orphaned` (R-03).
- An empty set reproduces today's output on a mixed fixture (messages, free, anchored, orphaned,
  ten same-minute entries) row for row, and every existing case in the file stays as it is (R-04).
- An excluded and an orphaned entry at one instant sort by ordinal, like two spine entries.
- `excludedMessageIDs(inPraticaNote:)`: reads `pergamenum-dossier-excluded` with quoted ids
  (`Dossier.render`'s spelling), with CRLF line breaks, with a hand-written unquoted list; no
  dossier or no key gives `[]`.

**Coder:** the two bodies. `excludedMessageIDs` goes through
`Dossier.parse(NoteDocument.parse(text).frontmatter.foreignKeys)?.excluded`, never a second YAML
reading. The entry branch of `arrange` checks the owner first, then the set, then falls to
`.orphaned`.

**Files:** `Sources/Core/Pratiche/PraticaTimelineOrder.swift`,
`Sources/Features/Pratiche/PraticaTimelineModel.swift`, `PraticaTimelineModel+Placement.swift`,
`PraticaMessagePicker.swift`, `Sources/Connector/VaultPratiche.swift` (arm only),
`Tests/PraticaTimelineOrderTests.swift`, `Tests/PraticheConnectorAnchorTests.swift` (arm only).

**Contract change:** a new enum case and two defaulted parameters. Call sites, from
`rg -n "arrange\(|PraticaTimelineModel.ordered\(" Sources Tests` at the base:
`VaultPratiche.swift:235`, `PraticaTimelineModel.swift:128`, `PraticheController+Ledger.swift:241`,
`Tests/PraticaTimelineOrderTests.swift:27,31`, `Tests/PraticaAnchorGapTests.swift:19`, and eleven
`ordered(` calls in `Tests/PraticaTimelineTests.swift`, `PraticaAnchoredTimelineTests.swift`,
`PraticaEntryCarryPinnedTests.swift` and `PraticheConnectorAnchorTests.swift`. The defaults keep all
of them compiling and meaning what they meant.

### Task 3 — The connectors report `excluded` (R-07, R-01, R-02, R-03)

**Tests (tester), `Tests/PraticheConnectorAnchorTests.swift`:**

- A fixture pratica whose dossier lists `<escluso@…>`, with one entry anchored to it and no message
  carrying it: the payload entry has `anchorState == "excluded"`, `anchorMessageID == "<escluso@…>"`,
  its `date` is its heading time, and it sits on the spine by that date (R-07).
- The same id listed but its message present: `"anchored"` (R-02). A dangling id not listed:
  `"orphaned"` (R-03).
- The encoded JSON holds `"anchorState":"excluded"`; a message and a free entry still carry
  neither key.

**Coder:**

- `entryRows(in:formatter:)` returns its rows and `PraticaTimelineOrder.excludedMessageIDs` of the
  same decoded text; `timeline(ofPraticaFolder:session:)` passes the set to `arrange` and maps
  `.excluded(messageID)` to `anchorMessageID`/`anchorState = "excluded"`. Update the `Entry` doc
  comment (`VaultPratiche.swift:192-197`).
- `Sources/CLI/Commands/PraticheCommands.swift:122-129`: `case "excluded"` with interpretation 6's
  sentence.
- `Sources/MCPServer/ToolCatalogue.swift:214-218`: the description names the third state.
- `scripts/mcp-smoke.py` `pratiche_anchors` (`:434-474`): the fixture's frontmatter gains
  `pergamenum-dossier-excluded` with one id, the body one entry anchored to it; check that entry's
  `anchorState == "excluded"` and that the `pratica` tool's description in `tools/list` contains
  `excluded`. Update the expected kinds list and indices.

**Verification:** build `perg` and `pergamenum-mcp`; run `scripts/mcp-smoke.py`; run `perg pratica`
on the smoke fixture or a throwaway vault and read the new line.

**Files:** `Sources/Connector/VaultPratiche.swift`, `Sources/CLI/Commands/PraticheCommands.swift`,
`Sources/MCPServer/ToolCatalogue.swift`, `scripts/mcp-smoke.py`,
`Tests/PraticheConnectorAnchorTests.swift`.

**Contract change:** `anchorState` gains a value. Consumers, from
`rg -n "anchorState|orphaned" Sources/CLI Sources/MCPServer Sources/Connector scripts/mcp-smoke.py Tests`:
`PraticheCommands.swift:125-128` (answers `nil` for an unknown value today, so an excluded entry
would print nothing), `ToolCatalogue.swift:217`, `scripts/mcp-smoke.py:436-472`,
`Tests/PraticheConnectorAnchorTests.swift:154,180,237-241`. All four are updated here or in Task 2.
`VaultAPI.PraticaTimelinePayload.Entry` is not a protected interface.

### Task 4 — The app reads the exclusion and hides the case once (R-05, R-06, R-03, R-13)

**Declarations (tester):**

- `PraticheController.TimelineRead.excluded: Set<String> = []`.
- `PraticaTimelineModel.hidingExcluded(_ entries: [PraticaTimelineEntry]) -> [PraticaTimelineEntry]`
  in `PraticaTimelineModel+Placement.swift`, stub returning its input.

**Tests (tester):**

- New `Tests/PraticaExcludedEntriesTests.swift`, pure: `hidingExcluded` removes `.excluded` rows
  only; on its output, `daySections` makes no section of a day that held only hidden rows,
  `nextRows` never names a hidden row, `filtered` with text matching a hidden entry's body or
  subject does not bring it back, `deleteKeyTarget` never answers it (R-05).
- Same file, over a `TemporaryVault` (`PraticaReadTimelineAnchorTests`' shape): `readTimeline`
  fills `excluded` from the dossier; after `reloadTimeline`, `timeline` and `filteredTimeline` (with
  a text filter matching it) hold no row of the excluded anchor (R-05); a listed id whose message
  file is present is `.anchored` and visible (R-02); a dangling unlisted anchor is `.orphaned` with
  `orphanCaption` (R-03); the id removed from the list by hand while the message stays absent turns
  the entry `.orphaned` and visible.
- `Tests/PraticheConnectorAnchorTests.swift`, the parity test (`:212-247`): its fixture gains an
  excluded entry and the app side calls `ordered(read.entries, excluded: read.excluded)`; order and
  placement still agree row for row, now including `"excluded"` (the counts in the test move by one,
  stated in chat first).

**Existing tests that assert the old behaviour, updated (explain in chat before editing):**

- `PraticaEntryCarryPinnedTests.excludeLeavesTheEntriesByteIdenticalAndOrphanedAndUndoAnchorsThemAgain`
  (`Tests/PraticaEntryCarryPinnedTests.swift:17-41`). After Escludi it expects two `.orphaned`
  rows in `timeline` (`:28-30`); the SPEC now hides them. New expectation: no row of
  `Rig.messageID` in `timeline`; `ordered(readTimeline(…).entries, excluded:)` places both
  `.excluded`; the body byte-identical; and, strengthening R-06, no frontmatter line other than the
  dossier keys changed (`CarryHarness.untouchedFrontmatter`). The undo half (two `.anchored`, body
  identical) stays. Rename to `excludeHidesTheEntriesLeavesThemByteIdenticalAndUndoAnchorsThemAgain`.
- `PraticaEntryCarryTests.aRefusedDestinationWriteMovesTheMessageAndLeavesTheEntriesOrphanedInTheSource`
  (`Tests/PraticaEntryCarryTests.swift:194-215`). `:213` expects two `.orphaned` rows in the
  source; the source now excludes the moved id, so both are hidden there. New expectation in one
  line: no entry of `Rig.messageID` in the source's `timeline`, the file still holding both blocks
  (`carriedBlocks().count == 2` at `:212` is unchanged). Net zero lines, the file is at 400. The
  test name keeps "InTheSource"; replace "Orphaned" by "Hidden".

**Coder:** `readManualEntries` (`PraticheController+TimelineRead.swift:197-235`) sets
`read.excluded = PraticaTimelineOrder.excludedMessageIDs(inPraticaNote: text)` from the text it
already decoded and hashed; `reloadTimeline` (`PraticheController+Ledger.swift:241`) stores
`hidingExcluded(ordered(read.entries, excluded: read.excluded))`; the `hidingExcluded` body.
Nothing else: Escludi, «Sposta in…», the carry and the inspector gain no code (R-06).

**Files:** `Sources/Features/Pratiche/PraticheController+TimelineRead.swift`,
`PraticheController+Ledger.swift`, `PraticaTimelineModel+Placement.swift`,
`Tests/PraticaExcludedEntriesTests.swift` (new), `Tests/PraticaEntryCarryPinnedTests.swift`,
`Tests/PraticaEntryCarryTests.swift`, `Tests/PraticheConnectorAnchorTests.swift`.

**Contract change:** `pratiche.timeline` no longer holds every parsed entry. Readers, from
`rg -n "\.timeline\b|filteredTimeline" Sources/Features/Pratiche`: `PraticaTimelineView.swift:43,296`
(rows and counts), `PraticheController.swift:369-371` (`filteredTimeline`) and its `senderAddresses`,
`PraticheController+DeleteKey.swift:19`, `PratichePane.swift:125` (the message picker, messages
only). All of them are meant to lose the rows; none needs an edit. Test readers: the two above, plus
`CarryHarness.entryPlacements` (`Tests/PraticaEntryCarryTests.swift:122-125`), whose other callers
(`:170`, `:185-188`, `Tests/PraticaAnchorGapTests.swift:72`, `PraticaEntryCarryPinnedTests.swift:39,56`)
assert placements that no exclusion touches and stay as they are.

### Task 5 — Two rail tokens (R-10)

**Declarations (tester):** `ColorToken.railReceived = "color.rail.received"` and
`.railSent = "color.rail.sent"` (`Sources/DesignSystem/TokenKeys.swift`); both in `Theme.emergency`
with placeholder values (PG-225: a token absent there crashes the test process); a new
`Sources/Features/Pratiche/PraticaTimelineModel+Rail.swift` with
`railToken(for: PraticaLane) -> ColorToken?`, stub `nil`.

Expected collateral reds until the coder half: the bundled themes report the two tokens as
missing (`ThemeEngine.swift:333`), so tests that expect `engine.problems.isEmpty` go red too. Run
the coder half straight after.

**Tests (tester), new `Tests/PraticaRailTokenTests.swift`:**

- Both bundled themes define both tokens (not in `inheritedTokens`).
- `Theme.emergency` resolves both (the `emergencyThemeDefinesTheEntryKindSurfaces` shape).
- A vault theme of each appearance without the keys inherits the bundled theme's value: opaque,
  not the emergency's (the `aVaultThemeWithoutTheEntryKindSurfacesInheritsThemFromTheBundledTheme`
  shape).
- WCAG 2 contrast of each token against `color.background.primary` is at least 3:1 in both bundled
  themes, through a relative-luminance helper in the test file.
- `railToken(for:)`: `.received` → `.railReceived`, `.sent` → `.railSent`, `.entry` → `nil`.

**Coder:** a `"rail": { "received", "sent" }` group in `Resources/Themes/pergamenum-light.json` and
`pergamenum-dark.json`, each a stronger tone of its lane's surface (`surface.received`,
`surface.sent`) meeting 3:1; emergency values mirroring the light theme; the `railToken` body.

**Files:** `Sources/DesignSystem/TokenKeys.swift`, `Sources/DesignSystem/Theme.swift`,
`Resources/Themes/pergamenum-light.json`, `Resources/Themes/pergamenum-dark.json`,
`Sources/Features/Pratiche/PraticaTimelineModel+Rail.swift` (new),
`Tests/PraticaRailTokenTests.swift` (new).

### Task 6 — The rail (R-08, R-09, R-10, R-13)

**Gate M1, first (tester and coder together, recorded in ADR-0079's implementation notes):** a
hosted probe in `Tests/PraticaTimelineRailHostedTests.swift`, a message row and two anchored rows in
a `List(selection:)` with the production row chrome, at 428 and 1600 pt, with and without filler
rows for a scroller. Measure: each cell's content frame against its `NSTableRowView` frame (found
through the view tree as `theRowBackgroundSitsAboveTheSelectedRowsOwnHighlight` does), so the space
above and below each card and any gap between row views; and whether a 2 pt bar a cell draws past
its card shows in the sampled pixels of that space. The outcome picks ADR-0079 §D5's path:
(1) each piece extends past its card by the measured amount; (2) zero vertical row insets, with the
same space returned as padding inside the row and outside `PraticaLaneRowLayout`; (3) neither gives
an unbroken line: stop and ask Stefano. The probe stays as the pinned witness.

To keep the test and production on one shape, the row chrome `PraticaTimelineView.list` applies
(`.listRowSeparator(.hidden)`, `.listRowBackground(backgroundPrimary)`, and path (2)'s insets if
taken) becomes one modifier, `View.praticaTimelineRowChrome()` in `PraticaLaneRowLayout.swift`,
applied by the view and by the hosted test.

**Declarations (tester), in `PraticaTimelineModel+Rail.swift` and `PraticaLaneRowLayout.swift`:**

- `enum PraticaRailPiece: Equatable, Sendable { case none, start, through, last }`.
- `struct PraticaRailGeometry: Equatable, Sendable { var x: CGFloat; var hookEnd: CGFloat }`.
- `PraticaTimelineModel.railPieces(in: [PraticaTimelineEntry]) -> [PraticaTimelineEntry.ID: PraticaRailPiece]`,
  stub `[:]`.
- `PraticaTimelineModel.railGeometry(columns: PraticaRowColumns, lane: PraticaLane, step: CGFloat) -> PraticaRailGeometry`,
  stub `x: 0, hookEnd: 0`.
- `PraticaLaneRowLayout` gains `rail: PraticaRailPiece = .none` and `railStep: CGFloat = 0`, so its
  four existing call sites (`PraticaTimelineView.swift:148`, `PraticaTimelineLaneHostedTests.swift:84,234`,
  `PraticaTimelineEntryGapHostedTests.swift:46`) compile unchanged.
- A custom `VerticalAlignment`, `.praticaEntryHeading`, for the hook height (ADR-0079 §D5).

**Tests (tester):**

- New `Tests/PraticaTimelineRailTests.swift`, pure:
  - A message with two anchored entries gives `start`, `through`, `last`; with one, `start`, `last`;
    a message with none, a free and an orphaned entry give `none`.
  - A message hidden by the sender filter, passed through `filtered` first, gives no piece to
    anything (SPEC edge cases); a group is never split by `daySections`.
  - A second message carrying an owned id gets `none`.
  - `railGeometry` on the columns of a 379, 396 and 720 pt column (428 pt with and without a
    scroller, and every width from 800 pt up), received and sent: `x` inside the indent
    (`[cardX, cardX + step]` leading, `[cardX + cardWidth - step, cardX + cardWidth]` trailing),
    identical for a message row and its anchored rows, and `hookEnd` at the anchored card's near
    edge.
- `Tests/PraticaTimelineRailHostedTests.swift`, hosted, at 428, 800 and 1600 pt × 0 and 60 filler
  rows, received and sent, with the real `PraticaEntryRow` and the production chrome:
  - Every rail segment shares one x within 0.5 pt, and each segment starts where the previous ends
    (R-08); pixels sampled at the rail's x in every gap of the group match the rail token.
  - The rail lies inside the indent and overlaps neither a card nor the note column, apart from the
    hook ending on the entry card's edge (R-09); the hook's y lies within the reported heading frame.
  - A selected entry's outline pixel at the card's edge is still the accent with the hook present.
  - The same continuity with the message and an entry expanded.
  - Every row is still exactly its card's height (R-09).
- `PraticaTimelineLayoutTests`, `PraticaTimelineLaneHostedTests` and
  `PraticaTimelineEntryGapHostedTests` are not edited and stay green (R-09).

**Coder:**

- The `railPieces` and `railGeometry` bodies.
- `LaneRowArrangement` places a rail view as its first subview, beneath the card, from
  `railGeometry` on the same `columns(rowWidth:)` it already computes; excluded from
  `sizeThatFits`; `.allowsHitTesting(false)` and `.accessibilityHidden(true)`. `start` runs from the
  card's bottom edge down, `through` over the whole row, `last` from the top to the hook then a
  corner into the card; extents per M1's path.
- The rail view draws a 2 pt line, the selection outline's width, in `railToken(for: lane)` through
  `@Environment(\.theme)`.
- `PraticaEntryRow.header` sets `.alignmentGuide(.praticaEntryHeading)`; the arrangement reads it
  from the card subview's dimensions, or falls back to a token-derived constant if the guide does
  not propagate (record which in the implementation notes).
- `PraticaTimelineView.list` computes `railPieces(in: entries)` once per body beside `nextRows`, and
  `row` passes `rail: pieces[entry.id] ?? .none` and `railStep: theme.spacing(.l)`.

**Files:** `Sources/Features/Pratiche/PraticaTimelineModel+Rail.swift`, `PraticaLaneRowLayout.swift`,
`PraticaTimelineView.swift`, `PraticaEntryRow.swift`, `Tests/PraticaTimelineRailTests.swift` (new),
`Tests/PraticaTimelineRailHostedTests.swift` (new).

### Task 7 — The heading: no `↪`, the day when it differs (R-11, R-12)

**Declarations (tester):**

- `PraticaTimelineModel.entryHeadingSymbols(for:) -> [String]`, stub returning today's list:
  `["arrow.turn.down.right", symbol]` for an anchored entry, `[symbol]` otherwise.
- `PraticaTimelineModel.headingShowsDay(_:calendar:) -> Bool`, stub `false`.
- `PraticaRowFormat.dayAndTime(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String`
  (`PraticaMessageRow.swift:332`), stub returning `time(date)`.
- `PraticaEntryRow.accessibilityText` becomes `static func accessibilityText(for:isExpanded:)`, a
  pure move of the private property (`PraticaEntryRow.swift:132-142`).

**Tests (tester), new `Tests/PraticaEntryHeadingTests.swift`:**

- No entry's symbols, anchored, free or orphaned, note or call, include `arrow.turn.down.right`
  (R-11); a call shows `phone`, a note `square.and.pencil`.
- An anchored entry's accessibility text contains «collegata al messaggio»; an orphaned one its
  caption; a free one neither (R-11).
- `headingShowsDay`: anchored on the message's day, false; on another day, true; free and orphaned,
  false (R-12). Midnight: 00:00 the next day against a message at 23:59, true. Zone: a calendar in
  `Europe/Rome` against one in UTC, with an entry at 22:30Z and its message at 21:00Z the same UTC
  day, true in Rome, false in UTC (the reader's calendar decides).
- `dayAndTime` under `it_IT` and a fixed zone gives «3 ott 20:22».

**Coder:** the bodies; `PraticaEntryRow.header` iterates `entryHeadingSymbols`, and shows
`dayAndTime(entry.date)` when `headingShowsDay(entry, calendar: .current)`, else `time(entry.date)`.
Compose the day and the time explicitly (the short day, a space, the time) rather than trusting a
localized template to omit a comma.

**Files:** `Sources/Features/Pratiche/PraticaTimelineModel+Placement.swift` (or `+Rail.swift`),
`PraticaMessageRow.swift` (`PraticaRowFormat`), `PraticaEntryRow.swift`,
`Tests/PraticaEntryHeadingTests.swift` (new).

### Task 8 — Verification, hand check, closing the record (R-13, R-14, R-15)

**Before the merge:**

- **Full suite**, `PergamenumTests`, with the pinned test command. R-13 rests on these staying
  green unedited: `PraticaDeleteKeyTests`, `PraticaTimelineNextRowsTests`, `PraticaEntryCommandTests`,
  `PraticaCommandTests`, `PraticaMessageRowFooterTests`, `PraticaTimelineLaneHostedTests`,
  `PraticaTimelineEntryGapHostedTests`, `PraticaTimelineLayoutTests`, `DesignSystemTests`.
- **Connectors.** Build `perg` and `pergamenum-mcp`; `scripts/mcp-smoke.py` passes, the excluded
  check included; `perg pratica` prints the new line (R-07).
- **Nothing protected moved.** `git diff origin/main -- .claude/protected-interfaces
  Sources/Core/Pratiche/Dossier.swift Sources/Core/Pratiche/PraticaManualEntries.swift
  Sources/Index/IndexCache.swift` is empty; `SharedSourcesPurityTests` green.
- **Lint and GUI.** No new SwiftLint violation in a touched file. `scripts/uitests.sh --status`,
  then `--affected` (advisory at merge, CLAUDE.md).
- **ADR checks.** `git fetch origin`; `scripts/check-adr-references.py`; `0079` still free on every
  ref (`git log --all -- 'docs/adr/0079*'`).
- **Hand check (R-14), Stefano, on this checkout's Debug build** (picked by `WorkspacePath`, CLAUDE.md),
  over a throwaway vault: light and dark; a 428 pt timeline and a wide window; a received and a sent
  message, each with two anchored entries, one written on another day; Escludi, then Cmd+Z; a
  selected anchored entry; the token values. The outcome, M1's numbers and path, and the
  hook-height mechanism go into ADR-0079's implementation notes.
- **Docs in the same PR (R-15).**
  - `DESIGN.md` "Binding decisions" (`:26-27`): a dated amendment naming the rail, the two
    `color.rail.*` tokens and the glyph's removal.
  - `CLAUDE.md` chain decision index: a new bullet after ADR-0078 and a suffix on ADR-0076's
    bullet, drafted below.

**After the merge (a docs change):** flip ADR-0079 to `accepted` with the PR, the merge's short hash
from `git log --first-parent main`, and the date; close `PG-369` in `TODO.md` through the project's
usual sync PR.

**Drafted CLAUDE.md chain index text.**

New bullet, after ADR-0078's:

> - **ADR-0079** — Closes `PG-369`/#824 and amends ADR-0076 for the excluded case. The shared
>   `PraticaTimelineOrder.arrange(_:excluded:)` gains `.excluded(messageID:)`: no message carries
>   the anchor and the pratica's own `pergamenum-dossier-excluded` lists it. A present message still
>   wins, an unlisted anchor stays `.orphaned`, and an empty set is today's output. The set is read
>   from the same `pratica.md` bytes as the entries (`PraticaTimelineOrder.excludedMessageIDs(inPraticaNote:)`).
>   The app drops `.excluded` rows once, where `reloadTimeline` stores `timeline`
>   (`PraticaTimelineModel.hidingExcluded`), so filters, day sections, «Inserisci qui», the counts
>   and Backspace never see them; the text stays in `pratica.md` and the inspector, nothing is
>   written, and undoing Escludi re-anchors by reading. `perg` and `pergamenum-mcp` list them with
>   `anchorState: "excluded"`. An anchored entry hangs off its message by a rail: one pure piece per
>   drawn row (`none`/`start`/`through`/`last`), placed by `LaneRowArrangement` from the row
>   arithmetic inside the 24 pt indent, outside the row's measured height, beneath the card, in
>   `color.rail.received`/`color.rail.sent` (at least 3:1 on `background.primary`). The `↪` glyph is
>   gone, and a heading on another day than its message reads «3 ott 20:22». Zero GUI tests. No
>   on-disk format, schema or protected interface touched. Amends ADR-0076 §D2/§D3/§D6/§D10 →
>   `docs/adr/0079-pratiche-timeline-rail-and-excluded-entries.md`

Suffix on ADR-0076's bullet, before its `→` path:

> *Amended by ADR-0079 (PG-369): an entry anchored to an excluded message is `excluded`, hidden in
> the app and listed by the connectors; the `↪` glyph gives way to a rail.*

If M1 yields a reusable fact about drawing across `List` rows, propose a working agreement for
CLAUDE.md in the same change, for Stefano to accept or drop.

## Requirement coverage

| R | Tasks | R | Tasks | R | Tasks |
| --- | --- | --- | --- | --- | --- |
| R-01 | 2, 3 | R-06 | 4 | R-11 | 7 |
| R-02 | 2, 3, 4 | R-07 | 3 | R-12 | 7 |
| R-03 | 2, 3, 4 | R-08 | 6 | R-13 | 4, 6, 8 |
| R-04 | 2 | R-09 | 6 | R-14 | 8 |
| R-05 | 4 | R-10 | 5, 6 | R-15 | 1, 8 |

R-14 and R-15 are `(no-test:)` criteria. Task 8 meets R-14 through Stefano's hand check, recorded
in ADR-0079's implementation notes. Tasks 1 and 8 meet R-15 through ADR-0079, the dated notes in
ADR-0076 and the PG-338 SPEC, and the CLAUDE.md lines.

## Order and dependencies

**Order:** Task 1 (G0) → 2 → 3 → 4 → 5 → 6 → 7 → 8.

- Task 3 needs Task 2's case and `excludedMessageIDs`.
- Task 4 needs Task 2; its parity-test update needs Task 3's connector change.
- Task 6 needs Task 5's token and `PraticaTimelineModel+Rail.swift`; it does not need Task 4, but
  hidden rows must already be gone from `filteredTimeline` for the pieces to be right, so it follows.
- Task 7 is independent of Tasks 5-6 and may run before them; it is placed last so the hand check
  sees the heading and the rail together.

## Risks, dependencies and HITL gates

- **G0: this plan, ADR-0079 and the six interpretations.** Blocks Task 2.
- **M1: rail continuity across `List` rows** is the one real technical risk (SPEC Test seams). The
  space between two cards belongs to the `List`, not to the row content, and is unmeasured; the row
  background is opaque and full-row. Path (1) or (2) is expected to hold; path (3) stops the work
  and is Stefano's decision, since it would reopen the SPEC's rejected joined card.
- **The pixel check may not see a `List` in a never-shown window.** If `HostedView.snapshot()`
  renders no table content, the hosted test keeps the geometry checks and the pixel half moves to
  the hand check, recorded in the implementation notes. Not a reason to add a GUI test.
- **The hook height** depends on a custom alignment guide propagating out of `PraticaEntryRow`;
  the fallback is a token-derived constant, checked against the heading's frame.
- **Two existing tests change their expectation** from orphaned to hidden (Task 4). This is the
  SPEC's decision, not a weakening; each change is explained in chat before the edit.
- **Readers built before this change** (`perg`/`pergamenum-mcp` on the `PATH`, the app on a second
  Mac through iCloud) keep reporting an excluded entry as orphaned. Rerun `scripts/install-cli.sh`
  and update every Mac after the update; nothing on disk differs.
- **Hidden text.** An excluded message's entries are reachable only through the inspector, and the
  carry's two sentences name a file whose source copy is not drawn in that timeline (interpretation
  4).
- **Stefano's gates.** The dated notes in the accepted ADR-0076 (Task 1); the hand check before the
  merge (R-14); commit, push and merge. No schema change, no deletion, no protected interface.
- **Nothing to provision.** No API, account, port or environment variable.

## TEST-CMD

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield

It is the existing `.claude/test-cmd`, kept restricted to `PergamenumTests` for the reason CLAUDE.md
gives: the `Stop` hook runs it every turn, and the UI suite would take over the person's screen and
global hot key.

## CHECK-CMD

CHECK-CMD CANDIDATE: swiftlint lint --quiet Sources/Core/Pratiche Sources/Features/Pratiche Sources/Connector Sources/DesignSystem Sources/CLI Sources/MCPServer

Read-only, scoped to the directories this plan touches. The project declares `.swiftlint.yml` but
no lint command, and `ci.yml` records that a whole-tree run fails by design on seven types, so an
unscoped run would fail every turn. Not run while planning: run it once on the base before adopting
it, and fall back to `NONE` if it already exits non-zero there.

**Outcome at the plan gate (2026-10-03):** run on the base, the scoped command exits 2 with 78
errors (`large_tuple` 24, `line_length` 42, `type_body_length` 12), so the fallback applies and the
pinned check command is `NONE`.

## Build result (2026-10-03)

BUILD · DONE WITH WARNINGS
Files: 37 (25 modified, 12 new; Sources 17, Tests 9, Resources 2, docs/scripts 9)
Tests: 5148 passed, 0 failed (PergamenumTests), 79 new incl. 6 (coverage)
Review: sonnet, safe; opus, safe
Coverage: R-01..R-13 covered by tests; R-14, R-15 no-test (STALE-WAIVER)
Deferred: 1 (out-of-diff 1)
Dropped: 2 (post-sweep 1, nit 1)
Dispatch: Round 1: coder — PG-338 SPEC/ADR-0076 carry wording
Dispatch: Round 2: coder — PG-338 edge case/UI flow 4, coder — ADR-0079 Amends/References
Dispatch: Round 3 (sweep): coder — spec table, ADR-0079 source path, 5 NITs, smoke re-run
Dispatch: Round 4 (sweep): coder — 2 NITs, debugger — dayAndTime default-branch test
INFO: review escalated, Size: 37 changed files, threshold 20
WARN: precondition: docs/adr/0079-pratiche-timeline-rail-and-excluded-entries.md uncommitted outside the skill's artifact list (repo ADRs live in docs/adr/); treated as a workflow artifact
WARN: STALE-WAIVER R-14
WARN: STALE-WAIVER R-15
WARN: FINDINGS SWEEP answered Ledger all without asking, under the task's standing instruction

```text
DEFER	out-of-diff	**MINOR** [other] Sources/Features/Pratiche/PraticaCommandActions.swift:314 — the Sposta undo lifts the source's exclusion even when moveBack did not restore the note; entries left in the source by .notCarried/.appendedOnly turn from hidden to orphaned and the source's sync may pick the message up again (pre-dates PG-369, medium confidence, read not run). (follow-up: coder)
DROP	post-sweep	**NIT** Sources/Features/Pratiche/PraticaTimelineModel+Placement.swift:3 — Header comment reflowed badly (sentence breaks mid-clause at "A sibling of"). Fix: rewrap the paragraph. (reviewer: sonnet)
FIX	swept	**MINOR** [other] docs/specs/pratiche-message-anchored-entries.spec.md:150-162 — PG-338 placement-state table, API bullet and :217 edge case lacked the excluded state; dated ADR-0079 notes added and named in ADR-0079's Amends/References. (reviewer: sonnet, opus)
FIX	swept	**MINOR** [plan-deviation] docs/adr/0079-pratiche-timeline-rail-and-excluded-entries.md:11 — ADR-0079 cited repo-root SPEC.md; now cites docs/specs/pratiche-timeline-rail-and-excluded.spec.md. (reviewer: opus)
FIX	swept	**MINOR** [failing-test] Tests/PraticaEntryHeadingTests.swift:168 — cached default branch of PraticaRowFormat.dayAndTime was untested; test added. (reviewer: sonnet)
FIX	swept	**MINOR** [other] docs/specs/pratiche-message-anchored-entries.spec.md:156 — placement-state table had no excluded state. (follow-up: coder)
FIX	swept	**MINOR** [other] docs/specs/pratiche-message-anchored-entries.spec.md:197 — edge case listed excluded and refused-carry anchors as orphaned. (follow-up: coder)
FIX	swept	**MINOR** [other] docs/adr/0076-pratiche-message-anchored-entries.md:352 — verified: the undo lifts the exclusion, so the sentence stays true; no change. (follow-up: coder)
FIX	swept	**MINOR** [other] Sources/CLI/Commands/PraticheCommands.swift:127 — not unit-testable; verified by scripts/mcp-smoke.py and a hand run of perg pratica. (follow-up: tester)
FIX	swept	**NIT** Sources/Features/Pratiche/PraticaTimelineView.swift:292 — countsText comment reworded. (reviewer: sonnet)
FIX	swept	**NIT** Sources/Features/Pratiche/PraticaMessageRow.swift:342 — dayAndTime default formatters cached. (reviewer: sonnet, opus)
FIX	swept	**NIT** Sources/Features/Pratiche/PraticaLaneRowLayout.swift:155 — card.dimensions(in:) computed only when a rail is drawn. (reviewer: sonnet)
FIX	swept	**NIT** docs/adr/0076-pratiche-message-anchored-entries.md:49 — pointer to ADR-0079 added. (reviewer: sonnet)
FIX	swept	**NIT** Tests/PraticheConnectorAnchorTests.swift:258-262 — fixture comment corrected. (reviewer: opus)
FIX	swept	**NIT** Sources/Connector/VaultPratiche.swift:221 — doc comments name ordered(_:excluded:). (reviewer: opus)
FIX	swept	**NIT** Tests/PraticaTimelineRailHostedTests.swift:74 — stand-in message card uses its lane's surface. (reviewer: opus)
```
