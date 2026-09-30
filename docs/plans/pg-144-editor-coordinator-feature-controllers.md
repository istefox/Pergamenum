# PG-144 — Editor structure: remove the duplicates, group the inputs, give each feature's state one owner

- Issue: `TODO.md` `PG-144` (P2, chain "editor"), GitHub #244. The ledger entry and its ten audit
  findings of 2026-09-12 are the whole brief. The repo-root `SPEC.md` belongs to another chain and
  is not this chain's input. The acceptance criteria are declared below as R-01 to R-10.
- ADR: **`docs/adr/0074-editor-coordinator-feature-controllers.md`** (new, proposed). Read §D2,
  §D3 and §D5 before Task 6. §D3's rule, "a value is read when it is read today", is the one a
  move can break without any test noticing.
- Governing prior ADRs, registered and not reopened: ADR-0018 §D2/§D5, ADR-0019 §D6/§D7, ADR-0023,
  ADR-0028 A9, ADR-0029 §D5/§D6, ADR-0033 §D2/§D3/§D4/§D5/§D15, ADR-0035 §D5, ADR-0037 §D6/§D7,
  ADR-0053 §D2 seam #4, and ADR-0001 §D1 with ADR-0007 (`Sources/Core` is Foundation-only and
  compiles into `perg` and `pergamenum-mcp`).
- Read at `3cdc97fb` (`kepler/fix-fable-chain-debt`, clean). `origin/main` is `06812344`. Between
  the two, the files this plan cites differ only in `Tests/MarkdownStylerTests.swift` (695 → 741
  lines, 77 → 81 `@Test`), `Sources/Features/Editor/MarkdownStyler.swift` and
  `Sources/Core/Editor/ListNesting.swift`, none of which a task moves code out of. Line numbers
  below are from `3cdc97fb`. After the precondition merge they may drift, and the coder re-reads
  them rather than trusting this file.
- Branch: the worktree's `kepler/fix-fable-chain-debt`. If the PR is opened from a fresh branch,
  CLAUDE.md's convention gives `refactor/pg-144-editor-structure`.

## Acceptance criteria

- **R-01** Nothing a person can see or do in the editor changes: vault notes, Diario, Oggi and
  the Workspace text card. The card shares `EditorDecorationDelegate`, `MarkupReveal` and the
  Coordinator's static span helpers. The evidence is the unit suite plus the hand-check pass H1 to
  H18 at gate G2.
- **R-02** Every PG-144 finding that still holds is closed, or deferred with a written reason. A
  finding whose shape has changed is named as such. The disposition table below is the record,
  and Task 8 writes the outcome into `TODO.md`.
- **R-03** No new SwiftLint `file_length` or `type_body_length` violation on any file created or
  touched. The error-level `file_length` on `Tests/MarkupHidingTests.swift` (1426 lines, limit
  1000) is gone. No `swiftlint:disable` is added and no threshold in `.swiftlint.yml` changes.
- **R-04** `Sources/Core` stays Foundation-only. `perg` and `pergamenum-mcp` build after every
  task that touches `Sources/Core` or `Project.swift`, and at the end.
- **R-05** `.claude/protected-interfaces` is untouched. `CompletingTextView+Pasteboard.swift` is
  byte-identical (`shasum` `6a6648fa242b1ba9b870bf01934379449c94c03f`), and every name it cites
  still exists where it cites it: `NoteTextView+EmbedCaret.swift`'s `PendingEmbedDeletion`,
  `selectEmbed(at:in:)`, `NoteTextView+Reveal`, `applyReveal`, `NoteTextView+Coordinator.swift`.
  `IndexCache.schemaVersion` stays 5.
- **R-06** Tests are moved, split or re-pointed, never weakened or deleted:
  - the `@Test` count and the count of `#expect(`/`#require(` never drop below the baseline;
  - no suite type name and no test function name changes;
  - a re-point changes a receiver or a label, never what is asserted.
- **R-07** After every task, `PergamenumTests` is green, including the in-process hosted-view
  tests (`HostedViewPrototypeTests`, `TableGridHostedAttachmentTests`,
  `WorkspaceFitOnOpenHostedTests`), and the `Pergamenum` scheme builds.
- **R-08** ADR-0074 is recorded, and each of ADR-0019, ADR-0029 and ADR-0033 gets a dated
  amendment note at its head. CLAUDE.md's chain index gains the ADR-0074 line. The status flips to
  accepted, with PR, merge hash and date, as the first docs change after the merge. (no-test:
  documentation obligation)
- **R-09** No stale reference is left. Every doc comment in `Sources/` and `Tests/` that names a
  moved member, field, type or test file names its new home. The protected file is exempt because
  R-05 keeps its citations true. (no-test: checked by the grep list in Task 8)
- **R-10** Before any code moves, each behaviour the move puts at risk and nothing pins today is
  pinned by a test:
  - the PG-093 replacement replay guard and its record-before-validate order;
  - the focus, scroll and match-jump one-shots;
  - the caret reset on a note switch;
  - the "read at the moment of use" sites of ADR-0074 §D3;
  - the never-key panel's contract;
  - the shared line-scan primitives.

## ADR outcome: new ADR

**`docs/adr/0074-editor-coordinator-feature-controllers.md`** (status: proposed).

The sub-controller design passes all three parts of the test:

- **Hard to reverse.** Around twenty files move, and 54 test reads are re-pointed.
- **Surprising without context.** Why is feature state in small classes the Coordinator forwards
  to, and why do those classes read their inputs through a closure?
- **A real trade-off.** Six alternatives exist, each rejected for a measured reason.

It also amends an ownership clause in three accepted ADRs, and the ledger entry asks for "the
sub-controller design as its own ADR".

The rest of the chain needs no ADR of its own:

- **The test splits (Task 1)** follow ADR-0045's precedent for files over the limit.
- **The panel and line-scan removals (Task 2)**, **the substitution preamble (Task 3)** and **the
  input grouping (Task 5)** each remove a duplicate or group fields, with no new boundary and no
  trade-off.
- **Two parts get recorded anyway, inside ADR-0074.** The shared block walk (§D8) shapes the
  controllers. Closing the line-scan duplicate takes early an extraction ADR-0028 A9 deferred
  (§D9), and that is a deviation from a recorded decision.

## Findings disposition

| Finding | Audit, 2026-09-12 | Measured at `3cdc97fb` | Disposition | Task |
|---|---|---|---|---|
| `structure-NoteTextView+Coordinator.swift-d95` | 31 state fields, ~2,270 extension lines | 33 stored fields (26 internal, 5 `private`, 2 `private(set)`); 12 extension files, 2,284 lines; class body 294 (warning) | Holds, and has grown. Closed by ADR-0074: 23 fields move to 7 owners, 33 → 17 | 6, 7 |
| `structure-NoteTextView.swift-e7a` | 37 stored inputs; `FindInputs`/`OutlineInputs`/`EmbedInputs` | 38 inputs | Holds, reshaped: the third group is `VaultInputs` (below) | 5 |
| `structure-NoteTextView.swift-c97` | `updateNSView` 123 lines | 123 lines (`:321-443`), lint body 71, complexity 12 | Holds | 5 |
| `structure-NoteTextView+ViewBlocks.swift-00b` | `applyViewBlocks`/`applyTables` same 60-line skeleton | `applyViewBlocks` `:54-142` (lint 60), `applyTables` `+Tables:41-106` (lint 52) | Holds | 4 |
| `structure-NoteTextView+Tables.swift-a5b` | three caret-rescue copies | `rescueCaret` `+Coordinator:353`, `tableCaretRescue` `+Tables:129`, `viewBlockCaretRescue` `+ViewBlocks:264` | Holds | 4 |
| `structure-EditorDecorationDelegate+CheckboxRendering.swift-552`, `+TableRendering.swift-a75` | substitution preambles duplicated | The marker-lookup preamble is in **six** branches: list `+ListRendering:25`, quote `+QuoteRendering:20`, checkbox `+CheckboxRendering:28`, table `+TableRendering:30`, view block `+ViewBlockRendering:38`, embed `EditorDecorationDelegate.swift:644`. The attachment tail is in three: table, view block, embed | Holds and is wider than the audit named. Reshaped to all six | 3 |
| `structure-CompletionPanel.swift-602` | `NeverKeyPanel` + `makePanel` duplicated with `FormatBarPanel` | `CompletionPanel.swift:191-218`, `FormatBarPanel.swift:115-146`; they differ only in `contentRect` and `hasShadow` | Holds | 2 |
| `structure-ListContinuation.swift-f19` | five primitives verbatim from `LineFormat` | `Line`, `lines(in:)` (byte-identical without comments), `indentLength`, `isChecklistMarker`, `matches`, `isDigit`: `ListContinuation.swift:228/238/289/370/377/385` and `LineFormat.swift:110/126/253/232/263/271`. ADR-0028 A9 accepted the duplication "if a third caller ever appears"; none has | Holds. Closed under ADR-0074 §D9 unless Stefano vetoes at G0, in which case it is deferred with A9 as the reason | 2 |
| `structure-MarkupHidingTests.swift-7e8` | 1386 lines | 1426 lines, 71 `@Test`, now **error**-level | Holds, and is worse | 1 |
| `structure-MarkdownStylerTests.swift-ee1` | size | 695 lines on `3cdc97fb`, 741 and 81 `@Test` on `origin/main`, warning | Holds | 1 |
| Found while measuring | not in the ledger | `panel?.parent?.removeChildWindow(panel!)` at `CompletionPanel.swift:141` and `FormatBarPanel.swift:79`. It cannot crash today, because optional chaining short-circuits before `panel!` is evaluated, but it reads as a crash site | Fixed now (P4 rule), identical behaviour | 2 |
| Found while measuring | not in the ledger | `NoteTextView.swift:397-402` copies the private `viewBlockBody(in:range:)` of `+ViewBlockEditing.swift:64` inline | Closed | 5 |
| Found while measuring | not in the ledger | `+CheckboxClick.swift:26-27` copies `inContainer(_:of:)` inline | Closed | 6 |

**Why `VaultInputs` and not `EmbedInputs`.** The nine inputs are `vaultRoot`, `notePath`,
`thumbnails`, `transclusions`, `queries`, `onEditQuery`, `onOpenEmbed`, `onDropFile` and
`onPasteImage`. They feed embeds, view blocks, transclusions and note-switch detection, not embeds
alone, and they share one default: nil or no-op when no vault is open. A struct named after one
consumer would be wrong for the other three.

## Standing rules for every task

1. **Refactor only.** Nothing changes in behaviour or in what is drawn. If a move seems to need a
   behaviour change, stop and report it. Do not absorb it.
2. **The tester owns the signature and the coder owns the body** (a compiled, type-checked
   target). Within one task:
   - The tester writes the R-10 pins first. They are characterization tests, green against the
     code as it is.
   - The tester declares every new type, method and property that a new test calls, with a stub
     body. The target must build at hand-off, and the new tests are red.
   - The coder moves or writes the bodies, and makes the re-points a moved declaration forces
     (receiver or label only).
   - The tester reviews that re-point diff before the commit gate.
3. **`tuist generate --no-open` after any file is added or removed**, before building.
   `Project.swift` is not edited: the app target globs `Sources/**` (`Project.swift:244`), the
   tests glob `Tests/**` (`:262`), and `sharedSources` globs `Sources/Core/**` (`:88`).
4. **Lint before and after.** Run `swiftlint lint --quiet <touched files>` and record the before
   and after table in the commit body. A task is done when its named findings no longer appear and
   no new `file_length` or `type_body_length` line does.
5. **Counts before and after.** Run `rg -c '@Test' Tests | awk -F: '{s+=$2} END {print s}'` and the
   same count for `#expect\(|#require\(`. Neither may drop (R-06).
6. **Run `shasum Sources/Features/Editor/CompletingTextView+Pasteboard.swift` after every task**
   (R-05).
7. **Tests to run:**
   - full `PergamenumTests` after every task (TEST-CMD below);
   - `perg` and `pergamenum-mcp` builds after Task 2 and Task 8;
   - `scripts/uitests.sh` is not run per task.
8. **The doc comment travels with its member.** A comment elsewhere that names the member by its
   old place is fixed in the same task when its file is already touched. Otherwise it goes on Task
   8's list. The five "Not private because the pass lives in …" comments on the Coordinator are
   deleted in the task that makes their field `private`.
9. **One commit per task**, Conventional Commits:
   - `test(editor): …` for Task 1;
   - `refactor(editor): …` for Tasks 2 to 7;
   - `docs: …` for Task 8.

   Each commit is a HITL gate (CLAUDE.md). The diff of every deleted duplicate is shown at that
   gate.

## Before Task 1 — the baseline (orchestrator; HITL for the merge commit)

1. Run `git fetch origin`, then merge `origin/main` into the branch. Never rebase, never force.
   The pre-push merge-integrity hook (ADR-0061/0062) checks the merge.
2. Run `tuist install` once for the worktree, then `tuist generate --no-open`.
3. Record the baseline:
   - TEST-CMD green;
   - the `@Test` and assertion counts (on `3cdc97fb` they are 4058 and 10275 grep occurrences;
     re-measure after the merge);
   - the lint table for every file this plan names;
   - the Pasteboard `shasum`.
4. Confirm that `docs/adr/0074*` is still free on `origin/main`.

---

### Task 1 — Split the two oversized test files (tester) (R-02, R-03, R-06, R-07)

A pure move. It is first because it clears the only error-level lint finding, and because Tasks 5
and 7 re-point reads inside these files. Pointing them at a file that is about to be split would
make the work twice.

**`Tests/MarkupHidingTests.swift`** (1426 lines, 71 `@Test`) becomes the files below. The line
ranges are from `3cdc97fb` and include each section's `// MARK` header:

| New file | Suites | ≈ lines |
|---|---|---|
| `Tests/MarkupHidingTests.swift` (kept) | `MarkupHiding` 100-158, `MarkupHidingEmphasis` 159-236, `MarkupHidingStrikethrough` 746-801, `MarkupHidingLink` 802-889, `MarkupHidingRule` and its `fragments` helper 890-963 | 370 |
| `Tests/MarkupHidingListTests.swift` | `MarkupHidingLists` 237-487, `ListMarkerRenderingComposition` 488-542 | 320 |
| `Tests/MarkupHidingCheckboxTests.swift` | `MarkupHidingCheckboxes` 588-745, `EditorDecorationDelegateProseFaces` 543-569, `FoldedHeadingFragmentBadgeFont` 570-587 | 215 |
| `Tests/MarkupHidingInlineSpanTests.swift` | `MarkupHidingInlineSpans` 1050-1333 | 300 |
| `Tests/MarkupCoordinatorTests.swift` | `MarkupCoordinator` and `NotificationCounter` 964-1049, `MarkupCoordinatorInlineSpans` 1334-1426 | 190 |
| `Tests/MarkupHidingFixture.swift` | `Frame`, `frames`, `substitutedParagraph`, `displayedParagraph`, `firstParagraphLength` (1-99), as static members of `enum MarkupHidingFixture` | 100 |

**`Tests/MarkdownStylerTests.swift`** (741 lines and 81 `@Test` after the merge; free `@Test`
functions under `// MARK` sections) becomes:

- `Tests/MarkdownStylerTests.swift`: heading, emphasis, PG-084, fences (≈ 360);
- `Tests/MarkdownStylerBlockTests.swift`: embed, lists, ADR-0029, CRLF (≈ 380);
- `Tests/MarkdownStylerFixture.swift`: `spans` and `styled` as statics of `enum
  MarkdownStylerFixture`.

A helper used by one section only moves with that section and stays `private`:
`emphasisMarkers`, `shellNote`, `italics`, `hasAnyListMarker`, `hasAnyBlockquoteMarker` and
`strikethroughMarkers`. The tester confirms each by grep.

**Rules:**

- A file-scope `private` helper used from two new files becomes a static of the fixture enum.
  That avoids an ambiguity with a same-named `private` helper in another test file. The only change
  allowed in a test body is the helper's qualified name.
- Every suite type name and every test function name stays as it is.
- Each new file is at most 400 lines. The table above is a proposal; `wc -l` decides.
- Update the comments in `Tests/` that name a moved suite by its old file:
  - `CardRoundTripTests.swift:93`;
  - `CardConcealmentTests.swift:79`, `:293`;
  - `EmbedDrawingTests.swift:8`, `:130`;
  - `ListIndentFontInvariantTests.swift:44`, `:92`;
  - `TableRenderingTests.swift:36`;
  - `ListNestingForwardPassTests.swift:91`, `:106`.

  `EditorDecorationDelegate.swift:596` is a source comment and goes to Task 8.

**Green:**

- full `PergamenumTests`;
- the `@Test` count for these suites is identical: 71 + 81;
- the assertion count is identical;
- the lint error on `MarkupHidingTests.swift` is gone.

---

### Task 2 — Leaf duplicates: the line-scan primitives and the never-key panel (tester, then coder) (R-01, R-02, R-03, R-04, R-06, R-07, R-10)

These are the two duplicates outside the Coordinator. They touch nothing in TextKit dispatch.

**Tester**

- Declare `enum LineScan` in `Sources/Core/Editor/LineScan.swift`, Foundation-only, with stub
  bodies:
  - `struct Line { start, contentEnd, end }`;
  - `static func lines(in: NSString) -> [Line]`;
  - `indentLength(on:in:)`;
  - `isChecklistMarker(in:at:limit:)`;
  - `matches(_:in:at:limit:)`;
  - `isDigit(_:)`.

  Access is `internal`: `sharedSources` compiles it into both tools, where nothing is `public`.
- Write `Tests/LineScanTests.swift`, red against the stubs:
  - `\r\n` is one terminator;
  - text ending in a terminator yields a trailing empty line;
  - empty text yields one line;
  - indent counts both spaces and tabs;
  - the checklist states are ` `, `x`, `X`, `>` and `-`, and anything else is refused;
  - `matches` refuses past `limit`;
  - `isDigit` is true for `0` to `9` only.
- Declare the shared panel in `Sources/Features/Editor/NeverKeyPanel.swift` as `final class
  NeverKeyPanel: NSPanel` (`canBecomeKey` and `canBecomeMain` false). Add a factory `static func
  make(contentRect: NSRect, hasShadow: Bool) -> NSPanel` with a stub body returning a plain
  `NSPanel`.
- Write `Tests/NeverKeyPanelTests.swift`, red against the stub. No test pins the contract today:
  - the panel is a `NeverKeyPanel`, with `canBecomeKey` and `canBecomeMain` false;
  - the style mask is `[.borderless, .nonactivatingPanel]`;
  - `isFloatingPanel` is true and the level is `.popUpMenu`;
  - `hasShadow` is as passed; the background is clear and the panel is not opaque;
  - it hides on deactivate, the animation behaviour is `.utilityWindow`, and it is not released
    when closed;
  - it does not ignore mouse events.

  It builds the panel only and never orders it front. `HostedViewSupport.swift`'s rule: no test
  takes the screen.

**Coder**

- Fill `LineScan`'s bodies by moving `ListContinuation`'s copies verbatim, with their comments.
  Delete the private copies in `ListContinuation.swift` and `LineFormat.swift`, and call `LineScan`
  from both. Each enum's other private helpers stay: `Edit`, `codeFenceFlags`,
  `isFenceDelimiter`, `marker`, `numberedMarkerLength` and the rest.
- Fill `make(contentRect:hasShadow:)` from the two `makePanel()` bodies. `CompletionPanel` calls
  it with 340×200 and a shadow; `FormatBarPanel` calls it with 240×32 and without one. Keep
  `FormatBarPanel`'s comment on why its shadow is off at the call site. Delete both private
  `NeverKeyPanel` classes and both `makePanel()`.
- In both `hide()` methods, replace `panel?.parent?.removeChildWindow(panel!)` with an `if let
  panel` form. Behaviour is identical.
- Fix the comment at `FormatBarPanel.swift:112`, which cites `CompletionPanel.NeverKeyPanel`.

**Call sites:** `LineScan` has none outside the two enums. The panel has
`CompletionPanel.swift:197` and `FormatBarPanel.swift:121`.

**Green:**

- full `PergamenumTests`, especially `ListContinuationTests`, `LineFormatTests`,
  `CompletionPanelTests`, `CompletionPanelPlacementTests`, `BoardFormatBarTests` and
  `InlineFormatTests`;
- the `perg` and `pergamenum-mcp` builds (R-04).

On a G0 veto of ADR-0074 §D9, the `LineScan` half of this task is dropped, f19 is recorded as
deferred citing ADR-0028 A9, and the panel half stands alone.

---

### Task 3 — One marker lookup and one attachment substitution for the decoration delegate (tester, then coder) (R-01, R-02, R-03, R-06, R-07)

Closes 552 and a75 in their wider shape (ADR-0074 §D8, last paragraph). The Workspace card uses
this delegate too.

**Tester.** Declare in a new `Sources/Features/Editor/EditorDecorationDelegate+Substitution.swift`,
with stub bodies:

- `func marker(of kind: HiddenMarker.Kind, at range: NSRange) -> HiddenMarker?`. It returns the
  paragraph's marker of that kind whose `NSMaxRange` fits inside `range.length`, read from
  `hiddenMarkers[range.location]` exactly as the six branches read it.
- `static func substituteAttachment(_ attachment: NSTextAttachment, over marker: HiddenMarker, in
  copy: NSMutableAttributedString)`. It replaces the marker's first character with `"\u{FFFC}"`,
  sets `.attachment` on it, and gives the rest of the marker `collapsedFont` when it has a rest.

Both stay non-isolated. The delegate is not `@MainActor`, and these run on the layout path.

Coverage check before the move. Every branch is already driven:

- list, checkbox, link and rule by the split `MarkupHiding*Tests`;
- quote by `QuoteRenderingTests`;
- table by `TableRenderingTests` and `TableGridHostedAttachmentTests`;
- view block by `ViewBlockRenderingTests`;
- embed by `EmbedDrawingTests`;
- the card by `CardConcealmentTests` and `CardRoundTripTests`.

Add direct tests of the two helpers, red against the stubs:

- a marker past the paragraph's end is refused;
- a zero-length marker is returned, since the caller's guard decides;
- the substitution keeps the paragraph's length;
- the rest collapses only when the marker is longer than 1.

**Coder.** Adopt both helpers in the six branches. Each branch keeps its own guards and its own
tail:

- the `marker.range.length > 0` guard of table and view block;
- `tableRun` and `viewBlockRun`, re-read against the live characters;
- the checkbox's "collapse the other markers only when not revealed";
- the unconditional collapse in list and quote, and quote's tooltips;
- the embed branch's own guard order at `EditorDecorationDelegate.swift:644-707`.

Collapsing the surviving markers is shared only if its three copies are byte-identical once the
reveal condition is lifted to the caller. Otherwise it stays per branch, and the reason goes in
the commit body.

**Watch for:**

- `EditorDecorationDelegate.swift` has a `file_length` warning (863) and a `type_body_length`
  warning (302). Neither may grow. The helpers live in the new extension file, which counts toward
  neither.
- The paragraph length must never change. That is `NSTextContentManager.h:120`'s constraint, the
  one every branch comment cites.

**Green:**

- full `PergamenumTests`, especially the suites listed above and
  `ListIndentFontInvariantTests`;
- hosted `TableGridHostedAttachmentTests`.

---

### Task 4 — One hidden-block line walk and one caret-rescue rule (tester, then coder) (R-01, R-02, R-03, R-06, R-07)

Closes 00b and a5b (ADR-0074 §D8). The passes are still Coordinator extensions here. Task 6 moves
them, already smaller.

**Tester.** Declare in a new `Sources/Features/Editor/HiddenBlockLines.swift`, with stub bodies:

- `struct HiddenBlockLines`, built from the text, an anchor offset and the recognised range. It
  answers:
  - the anchor paragraph's `HiddenMarker` over `0 ..< contentsEnd - start`, or nil when
    `contentsEnd <= start`;
  - the hidden line starts from `end` to `NSMaxRange(range)`.
- `enum CaretRescue`:
  - `static func target(for selection: NSRange, hidden: Set<Int>, in text: NSString, owner:
    (Int) -> Int?) -> Int?`, answering where the caret goes, or nil when it stays;
  - `@MainActor static func place(_ offset: Int?, in textView: NSTextView)`, which is
    `setSelectedRange` then `scrollRangeToVisible` and does nothing for nil.

Add direct tests, red against the stubs:

- a two-line table, a table at the end of text without a trailing newline, and a CRLF table give
  the right hidden starts;
- a caret on a hidden line goes to its owner's target;
- a caret on a visible line stays;
- a selection spanning a hidden line is treated as today's three copies treat it. Read them first:
  `+Tables:129`, `+ViewBlocks:264`, `+Coordinator:353`.

`TableCaretTests`, `ViewBlockCaretTests` and `NoteFoldingTests`/`FoldBadgeClickTests` already
pin the three callers.

**Coder**

- `applyTables` and `applyViewBlocks` build their hidden sets and owner maps through
  `HiddenBlockLines`.
- `tableCaretRescue`, `viewBlockCaretRescue` and folding's `rescueCaret` call `CaretRescue.target`
  with their own owner closure: the table header, the opening fence, the fold's heading.
- The two pending-caret placements after `endEditing` call `CaretRescue.place`.
- Everything that differs stays with its construct: the grid store keyed by offset, the host store
  keyed by ordinal (ADR-0033 §D3), each change check, each refresh.
- `rescueCaret` keeps its call position in `applyFolding` (`+Coordinator:328-352`).

**Done when:**

- the `function_body_length` warnings at `+Tables:41` (52) and `+ViewBlocks:54` (60) are gone;
- `+ViewBlocks:65`'s `large_tuple` warning is gone or unchanged, never new;
- full `PergamenumTests` is green, especially `TableCaretTests`, `TableEditTests`,
  `ViewBlockCaretTests`, `ViewBlockRenderingTests`, `ViewBlockQuerySourceTests`,
  `NoteFoldingTests` and `FoldBadgeClickTests`, plus hosted `TableGridHostedAttachmentTests`.

---

### Task 5 — Group the inputs and take `updateNSView` apart (tester, then coder) (R-01, R-02, R-03, R-06, R-07, R-10)

Closes e7a and c97.

**Tester, pins first.** These are green against today's code. `NSViewRepresentable.Context` cannot
be built in a test (`CardConcealmentTests.swift:32`), so drive a real `updateNSView` by hosting a
`NoteTextView` through `HostedView` (`Tests/HostedViewSupport.swift`). Its window refuses focus
and the screen. Change the inputs between two updates.

- **PG-093.** The same `replacements` batch handed to two consecutive updates is applied once, and
  `onReplacementsApplied` is called once. A batch whose ranges are out of bounds is recorded
  before it is refused: a second update carrying it does not try again.
- **Focus.** An unchanged `focusRequest` takes focus once, and an incremented one takes it again.
  Assert the selection moves and `takeFocus` runs. In the hosted window "has focus" is observable
  only as far as `HostedView` allows, so assert on what it exposes. If that is nothing, assert on
  the coordinator's bookkeeping and say so in the test's comment.
- **Scroll and match jump.** A `scrollRequest` with the same `id` scrolls once and calls
  `onScrollApplied` once. A `matchJump` at the same location moves the caret once.
- **Note switch.** New text with a new `notePath` puts the caret at 0. New text with the same
  `notePath` keeps the caret, clamped.

Then declare, in a new `Sources/Features/Editor/NoteTextView+Inputs.swift`, the three structs,
fields only, defaults exactly as today's (unused until the coder adopts them):

- `NoteTextView.FindInputs`: `findRequest`, `onFindApplied`, `matches`, `currentMatch`,
  `replacements`, `onReplacementsApplied`, `matchJump`;
- `NoteTextView.OutlineInputs`: `outlineRanges`, `onOutlineEntryChanged`, `scrollRequest`,
  `onScrollApplied`, `foldedEntries`, `onToggleFold`;
- `NoteTextView.VaultInputs`: `vaultRoot`, `notePath`, `thumbnails`, `transclusions`, `queries`,
  `onEditQuery`, `onOpenEmbed`, `onDropFile`, `onPasteImage`.

**Coder**

- `NoteTextView` stores `find`, `outline` and `vault` instead of the 22 fields: 38 → 19 stored
  inputs. The memberwise init takes `find: FindInputs = .init()` and so on. Reads become
  `parent.find.matches`, `parent.vault.notePath` and so on, in `NoteTextView.swift`,
  `+Coordinator.swift:237`, `:240`, `:435`, `+Embeds.swift:285-287`, `+Reveal.swift:157-158`,
  `+Transclusion.swift:91`, `:178` and `+ViewBlocks.swift:191-200`.
- Split `updateNSView` into named steps and call them in today's order, unchanged:
  1. push the plain properties and sync the text, including the note-switch caret;
  2. run the passes: styling, embeds, transclusions, folding, matches, reveal, grow;
  3. consume the insertion and the query builder it may open;
  4. consume the one-shots: focus, find, replacements, match jump, scroll.

  The body ends at 50 lint lines or fewer and complexity 10 or less, which clears both warnings at
  `NoteTextView.swift:321`. The steps may live in `NoteTextView+Inputs.swift` or a new
  `NoteTextView+Update.swift`. `NoteTextView.swift`'s own `file_length` warning (466) must not
  grow, and it is expected to fall under 400.
- The insertion step computes the fence body through `viewBlockBody(in:range:)`, made `internal`
  in `+ViewBlockEditing.swift`, instead of the inline copy at `:397-402`.
- The one-shot bookkeeping (`lastFocusRequest`, `lastScrollRequest`, `lastMatchLocation`,
  `lastNotePath`) stays on the Coordinator in this task. Task 7 moves it.

**Call sites, from `rg -n "NoteTextView\(" Sources Tests`:**

- production: `EditorColumn+Text.swift:47` (21 grouped labels), `TodayView.swift:207`,
  `DiaryView.swift:105`;
- tests passing a grouped label: `EditorHeightTests`, `FoldBadgeClickTests`, `EmbedDrawingTests`,
  `EmbedResolutionTests`, `ViewQueryOutOfScopeTests`, `ViewBlockQuerySourceTests`,
  `TranscludedLineTests`, `ViewQueryEntryPointTests`, `EmbedEditorTestSupport` and the split
  `MarkupCoordinator*`/`MarkupHiding*` files. The coder re-greps, because the label grep is
  approximate;
- `NoteSectionsProviderTests.swift:11`'s comment names `coordinator.parent.transclusions`.

Label-only edits.

**Assumption to check at G2.** `NoteTextView` already carries non-optional closures at top level
(`onFollowLink`, `onInsertionApplied`), so SwiftUI cannot treat two successive values as equal
today, and grouping fields cannot make `updateNSView` run less often. This is read from the code,
not measured. Hand check H10 to H12 is where a difference would show.

**Green:**

- full `PergamenumTests` with the new pins;
- the `Pergamenum` build;
- `CardTextView` is untouched and builds.

---

### Task 6 — ADR-0074, first application: the write door, and the two block controllers (tester, then coder; gate G1 afterwards) (R-01, R-02, R-03, R-05, R-06, R-07, R-10)

**Tester**

- Pin ADR-0074 §D3's "read at the moment of use" for the two block constructs:
  - `commitTable` after `coordinator.parent` is replaced with `hidesMarkup: false` refuses. It
    reads the current parent, not one captured earlier.
  - A view-block host vended before a parent swap keeps the `onEditQuery` it was vended with.
    That is today's capture at vend time (`+ViewBlocks:191-200`). Pin whichever behaviour the code
    has. Do not assume it.
- Declare the shells in their files, with signatures only:
  - `@MainActor final class TableBlockController` in `NoteTextView+Tables.swift`, with
    `init(parent: @escaping () -> NoteTextView?, decorations: EditorDecorationDelegate)`, read
    accessors `grids`, `drawn` and `hiddenRows`, and stub `apply(to:in:)`, `refresh(in:)` and
    `clear(in:)`;
  - `@MainActor final class ViewBlockController` in `NoteTextView+ViewBlocks.swift`, with the same
    `init`, read accessors `hosts`, `drawn` and `hiddenLines`, and the statics moved in name only:
    `revealedViewBlock`, `viewBlockRanges`, `selectionReveals`.
  - The exact method names are the tester's to choose. The table in ADR-0074 §D2 fixes what each
    one owns.
- `ViewBlockCaretTests`' reads of `Coordinator.revealedViewBlock` (8) are re-pointed by the
  coder, because they follow the static when it moves.

**Coder**

- `replaceAtomically(_:with:in:)` becomes `static` in `+EmbedCaret.swift`. `decoration(in:claimedBy:)`
  becomes `static` in `+Transclusion.swift` (ADR-0074 §D4). The 14 call sites in 8 files become
  `Self.…`: `+CheckboxClick:104`, `+EmbedCaret:63`, `:152`, `:217`, `+EmbedResize:60`, `:282`,
  `+ListEditing:42`, `:65`, `+TableCaret:71`, `:96`, `+Tables:189`, `+Transclusion:158`, `:179`,
  `+ViewBlockEditing:57`. No test calls either.
- `toggleCheckbox`'s inline container arithmetic (`+CheckboxClick:26-27`) calls
  `Self.inContainer(_:of:)`.
- Move into `TableBlockController`:
  - `tableGrids`, `lastTableRows`, `drawnTables`, `pendingTableCaret`;
  - `applyTables`'s body, `refreshTableGrids`, `tableCaretRescue`, `clearTables`.

  `applyTables` stays on the Coordinator as a one-line forward, since `applyStyling` calls it by
  name. `commitTable` stays a Coordinator extension, because it owns no state (§D5).
- Move into `ViewBlockController`:
  - `viewBlockHosts`, `lastViewBlockLines`, `drawnViewBlocks`, `pendingViewBlockCaret`,
    `pendingViewBlockRelayout`, `lastRevealedViewBlock`;
  - `applyViewBlocks`'s body, `refreshViewBlockHosts`, `viewBlockHeightChanged`,
    `scheduleViewBlockRelayout`, `viewBlockCaretRescue`, `clearViewBlocks`;
  - the three statics.

  In `scheduleViewBlockRelayout`, `Task { @MainActor [weak self, weak textView] }`
  (`+ViewBlocks:245`) now captures the controller. The per-turn coalescing is unchanged
  (ADR-0035 §D5). `commitViewBlock` stays in `+ViewBlockEditing.swift` and reads
  `viewBlocks.drawn[offset]?.source`.
- `applyStyling` calls `tables.refresh` and `viewBlocks.refresh` where it calls the two refreshes
  today, in the same order after `endEditing`. `textViewDidChangeSelection` asks `viewBlocks`
  whether the selection crossed a fence (ADR-0033 §D5), and calls `applyStyling` exactly when
  today's guard does.
- All moved state is `private` or `private(set)`, and the "Not private because…" comments for
  these fields are deleted.

**Re-points (receiver only):**

- `ViewBlockCaretTests`: `drawnViewBlocks` 6, `lastViewBlockLines` 4, `Coordinator.revealedViewBlock`
  8;
- `ViewBlockQuerySourceTests`: `drawnViewBlocks` 6, `viewBlockHosts` 4;
- `ViewQueryEntryPointTests`: `viewBlockHosts` 7.

`applyViewBlocks` keeps its name, so `ViewBlockRenderingTests:359`, `:395` and
`ViewBlockQuerySourceTests:373` are untouched.

**Green:**

- full `PergamenumTests`, especially every `Table*`, `ViewBlock*` and `ViewQuery*` suite and
  hosted `TableGridHostedAttachmentTests`;
- the Pasteboard `shasum` (R-05).

**G1 — Stefano reviews the first application before Task 7.** The review covers the diff, the lint
table, the Coordinator's field count (33 → 23 at this point), and whether reading the code got
easier or harder. **Go** runs Task 7. **No-go** stops the chain at Task 6 (ADR-0074 Alternative 4
becomes the outcome). The rest of d95 is recorded as deferred, with G1's reason, and ADR-0074 is
amended to cover only what landed.

---

### Task 7 — ADR-0074, the rest: folding, reveal, transclusion, embed resize, the request ledger (tester, then coder) (R-01, R-02, R-03, R-05, R-06, R-07, R-10)

Closes d95.

**Tester, pins first.** These are green today and cover §D3's remaining sites:

- `openTransclusion` after a parent swap calls the **new** `onFollowLink` (`+Transclusion:162`);
- `unfold` after a parent swap calls the new `onToggleFold` (`:178`);
- `applyReveal` after a parent swap reads the new `matches`, `currentMatch` and
  `revealsInlineSpans` (`+Reveal:157-168`);
- `resizeEmbed(.began)` after a parent swap draws its overlay with the new theme
  (`+EmbedResize:144`), if the overlay style is observable in-process. If it is not, say so and
  rely on H7.
- The outline-entry callback fires only when the entry changes (`+Coordinator:237-240`).

Then declare these shells, each in its file, with an `init` taking the provider and the
collaborators ADR-0074 §D3 names:

- `FoldController` in a new `NoteTextView+Folding.swift`;
- `RevealController` in `+Reveal.swift`;
- `TransclusionController` in `+Transclusion.swift`;
- `EmbedResizeController` in `+EmbedResize.swift`, taking `embeds` and `decorations`;
- `RequestLedger` in a new `NoteTextView+Requests.swift`, whose claim methods keep today's
  compare-then-record order and the replacement ledger's record-before-validate.

**Coder**

- Move the fields to their owners as ADR-0074 §D2's table assigns them:
  - `lastFoldLayout`, `applyFolding` and `rescueCaret` → `FoldController`;
  - `lastRevealed`, `lastRevealedSpans` and the reveal pass → `RevealController`. `MarkupReveal`
    stays in `+Reveal.swift`, untouched: `CardTextView+Reveal.swift` calls it.
  - `lastRenditions`, `renditionCache`, the transclusion pass and `openTransclusion`'s body →
    `TransclusionController`. `unfold` stays a Coordinator extension.
  - `embedDrag`, the three resize phases, `grabbedEmbed`, `commit`, `abandonResize`, `overlayStyle`
    and `handleRect(forEmbedAt:in:)` → `EmbedResizeController`. `EmbedDrag` and
    `PendingEmbedDeletion` keep their declarations and files.
  - `lastFocusRequest`, `lastScrollRequest`, `lastMatchLocation`, `lastAppliedReplacements`,
    `lastAppliedReplacementTexts`, `lastNotePath` and `lastOutlineEntry` → `RequestLedger`.
    Task 5's one-shot step and `+Matches.swift`'s `alreadyApplied`/`apply(_:to:)` consult it.
- The forwards that stay, by name: `applyFolding`, `applyReveal`, `applyTransclusions`,
  `openTransclusion`, `resizeEmbed`. Their names are cited by the protected file (`applyReveal`),
  by `CardTextView+Fold.swift:17` and by ADR-0019/ADR-0033. Everything else is called on the
  controller.
- Optional, only if the Coordinator's body is still over 250 lint lines: move the statics
  `hiddenKind`, `linkDelimiters` and `hiddenMarker` (`+Coordinator:592-665`) into a Coordinator
  extension in a new `NoteTextView+HiddenMarkers.swift`, with names unchanged. `CardTextView.swift:396`
  and `:405` call two of them through `NoteTextView.Coordinator.`, which still resolves.
- Every moved field is `private` or `private(set)`, and the remaining "Not private because…"
  comments are deleted. The Coordinator ends with 17 stored fields: `parent`, `textView`,
  `modifierFlags`, `undoManager`, `isStyling`, `decorations`, `unspellableRanges`, `embedRuns`,
  `frameObserver`, `embeds`, and `tables`, `viewBlocks`, `embedResize`, `transclusion`, `folding`,
  `reveal`, `requests`.

**Re-points (receiver only):**

- `EmbedResizeGestureTests`: `embedDrag` 8, `handleRect(forEmbedAt:in:)` 4;
- the split `MarkupCoordinatorTests`: `lastRevealedSpans` 7.

`CardConcealmentTests`' `lastRevealedSpans` belongs to the card's own Coordinator. It is **not**
re-pointed.

**Done when:**

- the Coordinator class body is under 250 lint lines (from 294);
- `+Coordinator.swift`'s `function_body_length` at `:446` and cyclomatic warning at `:592` are
  unchanged or gone, never new;
- `NoteTextView+Coordinator.swift`'s `file_length` warning (800) has shrunk. Whether it gets under
  400 is recorded, not required: it is an existing warning, and R-03 forbids only new ones;
- full `PergamenumTests`;
- the Pasteboard `shasum`.

---

### Task 8 — Close-out: stale references, records, final verification (coder for comments; orchestrator for records; Stefano for G2) (R-01, R-02, R-03, R-04, R-05, R-08, R-09)

- **Stale-reference sweep (R-09).** Run each grep below over `Sources Tests`, excluding
  `CompletingTextView+Pasteboard.swift`, and fix every hit that names an old place:
  - `rg -n "NoteTextView\+Coordinator\.(applyFolding|lastFoldLayout|lastRevealed|revealedViewBlock)"`;
  - `rg -n "NoteTextView\.Coordinator\.(lastRevealed|lastFoldLayout|embedDrag|drawn|viewBlockHosts|tableGrids)"`;
  - `rg -n "Coordinator\.embedDrag|pendingViewBlockRelayout|CompletionPanel\.NeverKeyPanel"`;
  - `rg -n "MarkupHidingTests\.swift"` and `rg -n "MarkdownStylerTests"`.

  Known hits on `3cdc97fb`:
  - `CardTextView.swift:208`, `:216`, `:226`, `:411`, `:423`, `:432`;
  - `CardTextView+Fold.swift:17`;
  - `FormattingTextView.swift`;
  - `EditorDecorationDelegate.swift:596`;
  - `TableGridStore.swift`;
  - `NoteTextView+Tables.swift:7`;
  - `+EmbedResize.swift:308`;
  - `+EmbedCaret.swift:232`.

  ADR bodies are historical and are not edited. Only the three amendment notes below are added.
- **Records (R-08), each one a HITL gate:**
  - flip nothing yet; ADR-0074 stays `proposed` until the merge;
  - add a dated head note to ADR-0019 (§D6), ADR-0029 (§D6) and ADR-0033 (§D2), in the form
    `**Amended 2026-MM-DD (ADR-0074):** the owner named here is now <controller>; nothing this
    section decides about behaviour changes`;
  - add the ADR-0074 line to CLAUDE.md's chain decision index;
  - record the outcome on the `PG-144` entry in `TODO.md`, including any finding deferred at G0 or
    G1.
- **Final verification:**
  - full `PergamenumTests`;
  - the `Pergamenum`, `perg` and `pergamenum-mcp` builds (R-04);
  - the lint table for every file created or touched, compared with the baseline (R-03);
  - the `@Test` and assertion counts compared with the baseline (R-06);
  - the Pasteboard `shasum` and `git diff origin/main -- .claude/protected-interfaces` empty
    (R-05);
  - `scripts/check-adr-references.py` clean after `git fetch`.
- **G2 — hand check by Stefano (R-01).** Use a Debug build: `APP=$(ls -dt
  ~/Library/Developer/Xcode/DerivedData/Pergamenum-*/Build/Products/Debug/Pergamenum.app | head -1)`,
  launched with `open -n "$APP" --args -recentVaults '("/path/to/a/throwaway/vault")'`. First check
  `ps` that no UI-test instance is alive (CLAUDE.md). The checks, H1 to H18:

  | Id | Area | What to verify |
  |---|---|---|
  | H1 | Concealment | Heading `#` and emphasis markers hide; the caret reveals the paragraph; with inline-span reveal on, only the span |
  | H2 | Lists | Glyphs draw. Return continues an item; Return on an empty item ends the list; Tab and Shift+Tab indent; an ordered list renumbers after a deletion |
  | H3 | Checkboxes | A click toggles `[ ]`/`[x]`; Cmd+Z undoes it in one step |
  | H4 | Quotes | Quote bars and tooltips |
  | H5 | Tables | The grid draws. A cell edit commits on Tab and Return; the caret lands right after a commit; add or remove a row; Cmd+Z undoes one step |
  | H6 | View fences | The fence renders; the caret inside reveals the source; leaving renders it again; Inserisci ▸ Vista opens the query builder; «Modifica query» commits |
  | H7 | Embeds | The picture draws. Dragging the resize handle writes `\|W` on release as one undo step; Backspace removes the whole embed; right-click shows the embed menu |
  | H8 | Transclusion | A `![[Nota#Sezione]]` line renders; a click opens the note |
  | H9 | Folding | Fold a heading; a click on the badge unfolds; a caret inside the folded body goes to the heading |
  | H10 | Find and replace | Typing in the find field never moves focus into the note (the 2026-08-18 defect); Return steps through the matches; replace-all is one undo step and is not replayed on the next update (PG-093) |
  | H11 | Outline | A click on an entry scrolls and moves the caret; the current entry follows the caret; moving an entry rewrites the note |
  | H12 | Note switch | Switching note puts the caret at 0; an external edit to the same note keeps it |
  | H13 | Completion panel | `[[` opens it; typing filters; the panel never takes the keyboard; Esc closes it |
  | H14 | Format bar | A selection shows the bar; bold toggles; the bar never takes the keyboard |
  | H15 | Readable width | Resizing the window keeps the column centred |
  | H16 | Diario and Oggi | H1, H2 and H10 in both panes |
  | H17 | Workspace text card | Concealment, reveal, lists, the format bar, folding in a card |
  | H18 | Spelling | Spell check does not underline markdown syntax |

- **At merge, advisory:** `scripts/uitests.sh --status`, then `--affected`. It selects every class
  for an editor change. That run does not block the merge (CLAUDE.md's merge-gate rule), and a
  `contaminated` verdict is rerun, not acted on.
- **After merge:** flip ADR-0074 to `accepted` with the PR, the merge hash from `git log
  --first-parent main` and the date. That is the first docs change after the merge.

## Observable-contract staleness

Every contract this chain changes, and the call sites grep found on `3cdc97fb`. Run the full
`PergamenumTests` after each change, not only the suites named: a moved contract can break an
unrelated suite that constructs the editor.

| Contract | Task | Call sites |
|---|---|---|
| `NoteTextView` memberwise-init labels: 22 fields → `find`, `outline`, `vault` | 5 | Production: `EditorColumn+Text.swift:47`, `TodayView.swift:207`, `DiaryView.swift:105`. Tests: 29 construction sites in 23 files (`rg -n "NoteTextView\(" Tests`). About ten pass a grouped label (listed in Task 5) |
| `parent.<grouped input>` reads | 5 | `NoteTextView.swift`, `+Coordinator.swift:237`, `:240`, `:435`, `+Embeds.swift:285-287`, `+Reveal.swift:157-158`, `+Transclusion.swift:91`, `:178`, `+ViewBlocks.swift:191-200` |
| Coordinator state moved to controllers | 6, 7 | 54 test reads in five files (ADR-0074 §D5 table). No test writes moved state |
| `replaceAtomically(_:with:in:)` and `decoration(in:claimedBy:)` become `static` | 6 | 14 call sites in 8 files (10 and 4; listed in Task 6), none in tests |
| `NeverKeyPanel` from two `private` nested classes to one shared type | 2 | `CompletionPanel.swift:197`, `FormatBarPanel.swift:121` |
| `ListContinuation`/`LineFormat` private primitives replaced by `LineScan` | 2 | Inside the two enums only |
| Delegate substitution preamble | 3 | The six branch functions only |
| Test-file locations of the split suites | 1 | The comment list in Task 1, plus `EditorDecorationDelegate.swift:596` in Task 8 |

## Risks and HITL gates

**Risks**

- **The order of the passes changes silently.** This is the one defect class the unit suite may
  not catch, because no single test runs the four sequences end to end. The mitigations:
  - ADR-0074 §D1 keeps every sequence written out at its call site;
  - the reviewer compares each sequence line by line against the Context list in ADR-0074;
  - H1 to H18.
- **A value read at a different moment** (ADR-0074 §D3), such as a closure captured at init
  instead of read at click time. It is invisible to a green suite unless it is pinned, which is why
  R-10 exists and Tasks 6 and 7 pin the sites before the moves.
- **The Workspace card regresses through a shared piece:** `EditorDecorationDelegate` (Task 3),
  the static span helpers (Task 7, optional move), `MarkupReveal`. The mitigations are
  `CardConcealmentTests`, `CardRoundTripTests`, `CardFoldTests`, `CardFormattingTests` and H17.
- **Concurrency.** The delegate helpers of Task 3 run off the main actor on the layout path. They
  must stay non-isolated, and they must read `hiddenMarkers` exactly as the branches do today. A
  `@MainActor` annotation added "for safety" would not compile cleanly or, worse, would hop.
- **`HostedView` may not expose focus** (Task 5's focus pin). If it does not, the pin asserts on the
  bookkeeping and says so, and H10 carries the rest.
- **Merge conflicts with parallel chains.**
  - The perf chain being specified in parallel (PG-138, PG-141, PG-142) touches
    `Sources/Features/Editor/VaultBrowser.swift` and `Sources/Features/Views/RenderedViewBlock.swift`,
    which this chain does not edit.
  - `ViewBlockController` hosts `RenderedViewBlock` without changing it.
  - Conflicts are expected only in `TODO.md` (resolve by merging `origin/main` into the branch,
    never by force) and in the ADR number.
- **The diff is wide.** About 30 test files change, all by receiver or label. A reviewer should
  read the test diff with `--word-diff` and reject any hunk that touches an assertion.
- **`git blame` stops at the move commits.** `git log -C --follow` recovers it. The PR body says
  so.

**Dependencies.** Nothing external: no third-party API, no consent flow, no cloud console, no new
environment variable or port. Tuist 4, the Xcode 27 toolchain and `swiftlint 0.65.1`
(`/opt/homebrew/bin/swiftlint`) are already required. `scripts/uitests.sh` needs no copy of the
app open out of `/Applications`.

**HITL gates, none of them the implementing agent's to pass:**

- **G0: approve this plan and ADR-0074**, including the separate yes or no on ADR-0074 §D9. The
  §D9 decision closes ADR-0028 A9's duplication early. **Passed 2026-09-29: plan and ADR-0074
  approved, §D9 yes (extract now).**
- **The precondition merge of `origin/main`.** It is a merge commit.
- **Each task's commit**, with the diff shown. That includes the deleted duplicate bodies in
  Tasks 2, 3 and 4: deletions of code whose behaviour survives in one shared place.
- **G1 after Task 6:** go or no-go for Task 7. **Passed 2026-09-29: go (Coordinator at 25
  stored fields, i.e. the plan's 23 plus the two controller references; receivers-only
  re-points).**
- **G2: the hand-check pass H1 to H18.**
- **The ADR number re-check against `origin/main`** immediately before the merge
  (`docs/adr/README.md` §1).
- **Push, pull request, merge to `main`**, then the ADR status flip.
- **Nothing here authorises** `swiftlint:disable`, a threshold change, an edit to
  `CompletingTextView+Pasteboard.swift` or `.claude/protected-interfaces`, or disabling a test. If a
  task cannot meet its bar without one, stop and report.

## Open for Stefano

- **ADR-0074 §D9.** Close ADR-0028 A9's accepted duplication now (the recommendation), or defer it
  until a third caller appears?
- **G1's bar.** The recommendation is to go on to Task 7 if the Coordinator is at 23 fields with no
  test assertion touched, and the two controllers read more easily than the extensions did.

---

TEST-CMD CANDIDATE: `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test`

TEST-CMD MODE: brownfield

This is `.claude/test-cmd` verbatim and it deliberately stays unchanged. It runs through the
`Stop` hook at the end of every turn, and CLAUDE.md records why `-only-testing:PergamenumTests` is
load-bearing. It includes the in-process hosted-view tests this chain's merge gate needs. The
verifications it does not cover run at the gates named above and are never wired into the hook:

```bash
xcodebuild -workspace Pergamenum.xcworkspace -scheme perg           -destination 'platform=macOS' build
xcodebuild -workspace Pergamenum.xcworkspace -scheme pergamenum-mcp -destination 'platform=macOS' build
scripts/uitests.sh --status && scripts/uitests.sh --affected   # at merge, advisory
```
