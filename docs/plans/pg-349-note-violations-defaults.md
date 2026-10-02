# PG-349 — `NoteViolations` defaults its five remaining fields, and the comments PG-146 left stale

**Requirement set:** none, ledger entry PG-349 is the brief

- Issue: `TODO.md` `PG-349` (P3, refactor), GitHub #773. The brief is the ledger entry. It comes from
  `docs/plans/pg-146-workspace-structure.md`: the verdict on `structure-ViewBoardRenderer.swift-c3e`
  and "Open for Stefano". There is no SPEC. The repo-root `SPEC.md`, `BRAINSTORM.md` and
  `UX-BLUEPRINT.md` belong to the PG-259 calendar chain and are not this chain's input. The acceptance
  items A-01 to A-14 are this plan's own, listed at the end. There are no R-ids.
- ADR: **none new**. See "ADR outcome".
- Governing prior ADRs, registered and not reopened:
  - ADR-0007 §D2: `NoteViolations` lives in `Sources/Core/Conventions`. `sharedSources` compiles it
    into `perg` and `pergamenum-mcp` (`Project.swift:88`). It stays Foundation-only;
  - ADR-0021 §D11 and ADR-0047 §D10 defaulted `taskMarkers` and `categories` to `[]` on this same type.
    This chain gives the five original fields the same default;
  - ADR-0053 and `.claude/protected-interfaces`: `VaultAPI.LintFinding`
    (`Sources/Connector/VaultPayloads.swift`) is protected. Its `init(path:_:)` reads a
    `NoteViolations` and is not touched. `CompletingTextView+Pasteboard.swift` is protected and is not
    touched either, although one comment below cites it;
  - ADR-0074 §D4/§D7: the editor coordinator's statics keep their names and their files. Moving a doc
    comment inside `NoteTextView+Coordinator.swift` stays within that;
  - ADR-0029 §D17 and ADR-0037's §D8 amendment (2026-09-09) supply the facts two of the comment fixes
    state.
- Read at `4b93331d`, this branch's HEAD and `origin/main` (clean tree, 2026-10-02). None of the 81
  `origin/*` refs, as of the last fetch, holds an unmerged change to any file below
  (`git diff --name-only origin/main...<branch>`). Refetch before the baseline.
- Branch: `refactor/pg-349-note-violations-defaults` (already cut).

## Inventory: every construction, measured

`rg -n "NoteViolations\(" Sources Tests UITests` on `4b93331d` finds eleven constructions, eight in
`Sources` and three in `Tests`. There are no others: no `.init(` spelling, no `extension NoteViolations`
and no explicit initialiser, so the synthesised memberwise initialiser is the only door.

| Site | Arguments today | After Task 2 |
| --- | --- | --- |
| `Sources/Features/Views/ViewBoardRenderer.swift:141` (board drop refusal) | `tags: outcome.introduced`, four `[]` | `NoteViolations(tags: outcome.introduced)` |
| `Sources/Features/Today/DayController+TaskDrop.swift:34` (Today drop refusal) | `tags: outcome.introduced`, four `[]` | `NoteViolations(tags: outcome.introduced)` |
| `Sources/Features/Contenitore/ContenitoreCommand.swift:189` (`refusal(forContainerName:)`) | `name: violations`, four `[]` | `NoteViolations(name: violations)` |
| `Sources/Features/Editor/NoteRowMenu.swift:109` (`RenameNoteSheet`) | `name: violations`, four `[]` | `NoteViolations(name: violations)` |
| `Sources/Features/Workspace/WorkspaceFolderSheets.swift:318` (`WorkspaceNameProblems`) | `name: violations`, four `[]` | `NoteViolations(name: violations)` |
| `Sources/Core/Conventions/ConformanceText.swift:132` (`creationFailure`) | `name: violations`, four `[]` | `NoteViolations(name: violations)` |
| `Sources/App/VaultController+Conformance.swift:16` (no-session fallback) | five `[]` | `NoteViolations()` |
| `Sources/Vault/VaultSession+Search.swift:190` (the linter) | all seven, computed | **unchanged** |
| `Tests/ConformanceTextTests.swift:16` (private helper) | all seven, explicit | unchanged |
| `Tests/ConformanceTextTests.swift:55` (`namesBothRelatedDirections`) | five, explicit | unchanged |
| `Tests/LintFindingStringsTests.swift:47` | all seven, explicit | unchanged |

What the measurement says:

- **All seven ledger sites are where the ledger puts them.** None has gone, none was already fixed, and
  there is no eighth. Six are single-axis. The seventh, `VaultController+Conformance.swift:16`, sets no
  axis at all.
- **No site changes meaning.** At every one of the seven, each argument other than the one axis is a
  literal `[]`. By Swift's default-argument rule, each rewritten call builds a value equal to today's.
  No site passes a non-empty value for a field the rewrite would drop.
- **No test is affected.** The three test constructions pass their arguments explicitly, so they keep
  compiling and keep meaning what they mean. `ConformanceTextTests`' private `violations(...)` helper
  duplicates the new defaults and becomes redundant. It is left alone (rule 6).
- **What the defaults cost.** Today, the linter's construction cannot compile without the five original
  axes. After Task 2 it can: an axis dropped from that call compiles and silently reports nothing. It
  already had no such guarantee for `taskMarkers` and `categories`. For six of the seven axes, an
  end-to-end linter test would go red:
  - `name`, `frontmatter` and `tags`: `Tests/VaultTests.swift:401-403`;
  - `relatedMissingInSection`: `Tests/RelatedSectionTests.swift:54`;
  - `taskMarkers`: `Tests/TaskMarkerLintTests.swift`;
  - `categories`: `Tests/CategoryLintTests.swift`.

  `relatedMissingInFrontmatter` has no such test. Its only positive test is on the pure
  `RelatedSection.discrepancies` (`Tests/ConventionsTests.swift:285`), and
  `RelatedSectionTests.swift:55` asserts it empty. Task 1 closes that gap before Task 2 opens it.

## Inventory: every stale comment, re-located

The ledger's seven, found again by content on `4b93331d`:

| Ledger cite | Now | What is stale | Task |
| --- | --- | --- | --- |
| `CompletingTextView.swift:112` | `:111-113` (the path is on `:112`) | Cites `claimsFoldBadge`/`claimsCheckbox` in `Sources/Features/Workspace/FormattingTextView.swift`. PG-146 Task 3 moved both to `FormattingTextView+Clicks.swift` (`:134`, `:184`). | 3 |
| `MarkdownAttributedText.swift:25` | `:25` | "its `FormattingTextView.swift` twin" of `followLinkIfPresent(at:)`. The twin is at `FormattingTextView+Clicks.swift:77`. | 3 |
| `VaultController+Notes.swift:189` | `:189` | Cites `WorkspaceController.breadcrumb` as `WorkspaceController.swift:225-237`. It is in `WorkspaceController+Navigation.swift` (`:48`). | 3 |
| `NoteTextView+Coordinator.swift:396-406` | `:405-415` | The first eleven lines of the doc block above `hiddenKind(for:)` (`:424`), from "One span's hidden marker" to "trailing space.", describe `hiddenMarker(_:at:paragraphStart:)` (`:484`), which has no doc of its own. | 3 |
| `PratichePane+Links.swift:7` | `:7-9` | "`BoardTray.traySection`'s shape … that helper is `private` to a different `View` type". PG-146 Task 6 made it `private struct TraySection` at file scope (`BoardTray.swift:255`). | 3 |
| `EmbedAttachment.swift:139` | `:139` | "The corner radius `ResizeHandleView` already gives the Workspace's own grips". PG-146 Task 5 moved that drawing (`cornerRadius: visualSize / 4`) into `BoardGripView` (`BoardHandles.swift:64`, `:80`). The quarter-of-a-side fact is still right. | 3 |
| `CardTextView.swift:44-46` | `:40-46` | "A card's `hiddenKind` switch has no `.strikethrough`/`.link` case … so this setting only ever narrows the card's bold/italic reveal", and line 40's "for this card's bold/italic runs". This has been false since ADR-0037's §D8 amendment: `Coordinator.hiddenKind(for:)` (`:359-376`) maps both. It predates PG-146: `78cef096` wrote it on 2026-09-09, and the amendment came the same day. | 3 |

Found while re-locating the seven. None is in the ledger, and each is verified stale on `4b93331d`. Task
4 handles them, gated at G0:

| Id | Where | What is stale |
| --- | --- | --- |
| E1 | `NoteTextView+Coordinator.swift:419-423`, the second paragraph of `hiddenKind(for:)`'s own doc | "that `default` is the seam ADR-0029 §D17 relies on to keep this chain's four constructs - a live `NSView` grid above all - out of a card". Since ADR-0037's §D8 amendment the card maps `.strikethrough` and `.link`. What it still keeps out is blockquote, rule, message anchor and table. This is the block Task 3 is already editing. |
| E2 | `Tests/NoteEditorTeardownTests.swift:22` | `(CardTextView.swift:199)` for the card coordinator's own `UndoManager()`. Line `:199` is now a doc line, and `let undoManager = UndoManager()` is at `:204`. PG-146 Task 7 named this line ("rewrite it if not") and it drifted anyway. A comment-only test edit. |
| E3 | `Sources/Features/Workspace/CardTextView+Reveal.swift:22` | "the same restraint `NoteTextView+Reveal.swift:66-88` keeps". ADR-0074 moved that pass into `RevealController.apply(to:)` (same file, `:189-228`). Lines `:66-88` are now `MarkupReveal.inlineSpans`. |
| E4 | `Sources/Features/Workspace/CardTextAttributes.swift:33` | "this file's own `FormattingTextView.swift` twin resolves by hand". The hand resolution, `followLinkIfPresent(at:)`, has been in `FormattingTextView+Clicks.swift` since PG-146 Task 3. |

Checked and left alone:

- `Tests/WorkspaceEnterFolderTests.swift:262`: a historical "moved verbatim" note that PG-146 kept on
  purpose;
- `CompletingTextView+CursorRects.swift:71`: `frame(for:type:)` is still in
  `FormattingTextView.swift:84`;
- `MarkdownAttributedText.swift:19`: `textView(_:clickedOnLink:at:)` is still in
  `NoteTextView+Coordinator.swift:240`;
- `CardTextView.swift:28` and `:42`: `WorkspaceView.applyBoardSettings()` names a member, not a file,
  and is still right;
- `VaultSession+TaskDrop.swift:14-15` lists four of `NoteViolations`' six families. It does not mislead,
  because the guard it describes compares `tags` alone (`:68`).

The repository holds 186 `file.swift:NNN` citations. Only those naming a file that PG-146 split or that
ADR-0074 restructured were audited.

## ADR outcome: no new ADR

**No ADR.** Giving the five remaining fields a default extends the precedent ADR-0021 §D11 and ADR-0047
already set on the same type. It is reversible in one commit, and it moves no boundary, contract,
format or schema. The comment fixes are corrections, not decisions. The change fails all three
significance tests:

- it is easy to reverse;
- it is not surprising: the type already defaults two fields the same way;
- the one real alternative (below) is a style choice, not a trade-off with lasting cost.

None of the override cases applies either. No security or compliance boundary moves. No constraint is
invisible in the code, since the loss of compile-time completeness is stated on the type itself (Task 2)
and pinned by a test (Task 1). Nothing deviates from the obvious path, no explicit "no" is recorded, and
neither CLAUDE.md nor an ADR asks for a record on this topic.

**Considered and rejected, recorded here and not in an ADR.** The alternative was convenience
initialisers in an extension (`init()`, `init(name:)`, `init(tags:)`), with the five fields left
undefaulted. It would keep the linter's five original axes compiler-checked. It was rejected for three
reasons:

- it gives one type two conventions: two fields defaulted, five reached through initialisers shaped for
  particular call sites;
- each new single-axis shape would need a new initialiser;
- the one gap the compiler covered alone is closed by Task 1's test.

The ledger names the defaults, and this plan follows the ledger.

## Standing rules for every task

1. **Behaviour does not change, and there is no red phase.** Task 1's test is a guard: it is green on
   its first run and stays green. No test calls the new defaulted shape. The interface change (the
   defaults) therefore stays with the coder in Task 2, beside its seven callers, and the target builds
   at every commit.
2. **The only non-comment edits are the ones Task 2 lists.** Review each task with
   `git diff --word-diff`, and Task 3's move with
   `git diff --color-moved=dimmed-zebra --color-moved-ws=allow-indentation-change`.
3. **Comment edits match their surroundings:**
   - the same `///` or `//` form;
   - the same wrap width as the block they sit in;
   - a cited member names its file, never a line number.

   No comment edit may lengthen a file that already carries a `file_length` warning:
   - `CardTextView.swift` is at 403 lines (`file_length` warning, pre-existing): its rewrite adds no line;
   - `NoteTextView+Coordinator.swift` is at 634 lines (same): Task 3 is net zero, Task 4's E1 is net zero
     or shorter.
4. **Untouched:**
   - `.claude/protected-interfaces`;
   - `Sources/Connector/VaultPayloads.swift`;
   - `Sources/Features/Editor/CompletingTextView+Pasteboard.swift` (protected; the
     `MarkdownAttributedText.swift` comment cites it correctly and stays);
   - the linter's construction in `Sources/Vault/VaultSession+Search.swift`, except the transient
     mutation check in Task 2, which is never committed.
5. **`sharedSources` and Tuist.** No file is added or removed, and no `import` changes under
   `Sources/Core`. So after the baseline, no `tuist generate` is needed and `Project.swift` is not edited.
6. **Test edits.** Task 1 adds one test, and Task 4's E2 changes a comment in a test file. No other test
   is edited, and no assertion changes. `ConformanceTextTests`' now-redundant helper stays as it is.
7. **Lint** before and after, on every touched file: `swiftlint lint --quiet <files>`. No new finding,
   no `swiftlint:disable`, no `.swiftlint.yml` change. The baseline findings in scope are all
   pre-existing:
   - `ConformanceText.swift`: complexity at `:36`, line length at `:72` and `:74`;
   - `CardTextView.swift`: `file_length` 403;
   - `NoteTextView+Coordinator.swift`: complexity at `:424`, function body at `:268`, `file_length` 634;
   - `MarkdownAttributedText.swift`: complexity at `:126` and `:227`;
   - `CardTextAttributes.swift`: complexity at `:110`;
   - `Tests/NoteEditorTeardownTests.swift`: line length at `:115`.
8. **Counts.** The baseline on `4b93331d` is 4978 `@Test` and 13625 `#expect(`/`#require(` grep
   occurrences:
   - `rg -c '@Test' Tests | awk -F: '{s+=$2} END {print s}'`;
   - the same for `'#expect\(|#require\('`.

   After Task 1, and from then on: 4979 and 13627.
9. **Tests to run:** the full `PergamenumTests` (TEST-CMD) after every task, not only the suites named.
   A signature that gains defaults can change overload resolution wherever `NoteViolations(` is
   written.
10. **One commit per task**, Conventional Commits. Each commit is a HITL gate, with the diff shown.

## Before Task 1: the baseline (orchestrator)

1. `git fetch origin`. If `origin/main` has moved past `4b93331d`, merge it in: never rebase, never
   force. Then re-run the overlap check from the header for the files below.
2. `tuist install` once for this worktree, then `tuist generate --no-open`.
3. Record:
   - TEST-CMD green;
   - `perg` and `pergamenum-mcp` built green (commands in Task 2);
   - the two counts;
   - the lint table from rule 7, re-run.
4. `scripts/uitests.sh --status`. Record the verdict it holds for `main`, and start no run.

---

### Task 1 — Pin the linter's one unpinned axis (tester) (A-05, A-11)

**File:** `Tests/RelatedSectionTests.swift` only.

- **One new test**, a `@MainActor` free `@Test` placed after `theLinterInventsNoDiscrepancyFromASubHeading`
  (`:43-56`). A suggested name: `theLinterReportsASectionLinkMissingFromRelated`.
- **Its shape** is that test's: a `TemporaryVault`, and a `VaultSession(root:stateBase:bundledVocabulary:)`
  built exactly as that test builds it. Its note comes from the file's own `note(related:_:)` helper.
- **The fixture:** `related: ["[[A]]"]`, with body
  `"## Note correlate\n\n- [[A]] — motivo\n- [[B]] — motivo\n"`.
- **Two assertions,** on `session.violations(path: "Nota.md", title: "Nota", text:)`:
  - `relatedMissingInFrontmatter == ["B"]`;
  - `relatedMissingInSection.isEmpty`.
- **A doc comment of two or three lines,** in the file's style. It says why the test exists: once every
  `NoteViolations` field has a default, the compiler no longer makes the linter fill this axis. The other
  six axes already have an end-to-end test; name the files from the inventory.
- **Green on its first run,** on the current tree.

**Done when:**

- the suite is green;
- the counts are 4979 and 13627.

**Commit:** `test(conventions): pin the linter's related-missing-in-frontmatter axis (PG-349)`.

### Task 2 — Default the five fields; the seven sites write only their axis (coder) (A-01, A-02, A-03, A-04, A-05, A-06, A-07, A-10, A-12)

**Files:**

- `Sources/Core/Conventions/NoteViolations.swift`;
- `Sources/Core/Conventions/ConformanceText.swift`;
- `Sources/App/VaultController+Conformance.swift`;
- `Sources/Features/Views/ViewBoardRenderer.swift`;
- `Sources/Features/Today/DayController+TaskDrop.swift`;
- `Sources/Features/Contenitore/ContenitoreCommand.swift`;
- `Sources/Features/Editor/NoteRowMenu.swift`;
- `Sources/Features/Workspace/WorkspaceFolderSheets.swift`.

**The type.**

- `name`, `frontmatter`, `tags`, `relatedMissingInSection` and `relatedMissingInFrontmatter` each gain
  `= []`.
- The declaration order does not change. It is the memberwise initialiser's parameter order, and the
  linter and two tests pass all seven arguments in that order.
- No explicit `init` and no `extension`. `Equatable`, `Sendable`, `isEmpty` and `count` are untouched.
  `import Foundation` stays the only import.
- **Its comments.** Two sentences go: "Defaulted so the six existing construction sites … keep compiling
  untouched" (`:15-17`) and "Defaulted so the seven existing construction sites keep compiling
  untouched" (`:19-20`). Both are false once every site omits what it does not set.
  - Each of the two fields keeps the sentence that says what it holds, with its ADR citation.
  - The type's doc gains one short paragraph with the rule. Every field defaults to empty, so a caller
    with findings on one axis writes only that axis (a refused drop's tags, a refused name). The linter,
    `VaultSession.violations(path:title:text:)`, is the one construction that fills every axis, and a
    field added later has to be added there by hand.

**The seven sites,** one call each, and nothing else on the line changes:

- `ViewBoardRenderer.swift:141` and `DayController+TaskDrop.swift:34`:
  `ConformanceText.lines(NoteViolations(tags: outcome.introduced))`;
- `ContenitoreCommand.swift:189`: `ConformanceText.lines(NoteViolations(name: violations)).joined(separator: ". ")`;
- `NoteRowMenu.swift:109`: `ForEach(ConformanceText.lines(NoteViolations(name: violations)), id: \.self) { line in`;
- `WorkspaceFolderSheets.swift:318`: `ConformanceText.lines(NoteViolations(name: violations))`;
- `ConformanceText.swift:132`: `let named = NoteViolations(name: violations)`;
- `VaultController+Conformance.swift:16`: `?? NoteViolations()`. It may join the line above it if that
  fits in 120 columns.

A call that now fits on one line within 120 columns (the `line_length` warning) collapses onto it. One
that does not keeps the wrap it has.

**Build both connectors:**

```bash
xcodebuild -workspace Pergamenum.xcworkspace -scheme perg -destination 'platform=macOS' build
xcodebuild -workspace Pergamenum.xcworkspace -scheme pergamenum-mcp -destination 'platform=macOS' build
```

**The mutation check (reviewer, never committed).** In a single turn, because the `Stop` hook runs
TEST-CMD at every turn end:

1. Delete the `relatedMissingInFrontmatter:` argument line from the linter's construction in
   `VaultSession+Search.swift`.
2. Build and run TEST-CMD. Exactly Task 1's test goes red.
3. Put the line back with an inverse edit (`git checkout --` is denied on this machine).
4. Confirm that `git diff --exit-code -- Sources/Vault/VaultSession+Search.swift` passes.

**Done when:**

- `rg -n "relatedMissingInSection: \[\]" Sources` and `rg -n "frontmatter: \[\], tags:" Sources` are
  both empty;
- `rg -n "NoteViolations\(" Sources` lists exactly eight lines: the linter in `VaultSession+Search.swift`
  (unchanged, seven labels), six one-label calls, and one `NoteViolations()`;
- `rg -n "keep compiling untouched" Sources/Core/Conventions/NoteViolations.swift` is empty;
- both connector builds are green, and the suite is green;
- the counts are unchanged since Task 1;
- the mutation check passed;
- no new lint finding in the eight files.

**Commit:** `refactor(conventions): default every NoteViolations field to empty (PG-349)`.

### Task 3 — The seven comments PG-146 left stale (coder) (A-08, A-10, A-13)

**Files:**

- `Sources/Features/Editor/CompletingTextView.swift`;
- `Sources/Features/Editor/MarkdownAttributedText.swift`;
- `Sources/App/VaultController+Notes.swift`;
- `Sources/Features/Editor/NoteTextView+Coordinator.swift`;
- `Sources/Features/Pratiche/PratichePane+Links.swift`;
- `Sources/Features/Editor/EmbedAttachment.swift`;
- `Sources/Features/Workspace/CardTextView.swift`.

Comments only. Each edit changes the stale part and nothing around it:

1. **`CompletingTextView.swift:112`**: `Sources/Features/Workspace/FormattingTextView.swift` becomes
   `Sources/Features/Workspace/FormattingTextView+Clicks.swift`. Rewrap `:111-113` only if a line passes
   the block's width.
2. **`MarkdownAttributedText.swift:25`**: "`FormattingTextView.swift` twin" becomes
   "`FormattingTextView+Clicks.swift` twin".
3. **`VaultController+Notes.swift:189`**: "(`WorkspaceController.swift:225-237`)" becomes
   "(`WorkspaceController+Navigation.swift`)".
4. **`NoteTextView+Coordinator.swift`**: move `:405-415` verbatim to directly above
   `static func hiddenMarker(` (`:484`). Those are the eleven `///` lines from "One span's hidden marker,
   its range relative" to "range still stops at the marker's trailing space.". After the move, the doc
   sits on the function it describes. `hiddenKind(for:)` keeps the rest of its block, which now begins
   "Which kind of hidden marker a span becomes". Net line count: zero.
5. **`PratichePane+Links.swift:7-9`**: what is reproduced is now `BoardTray.swift`'s `TraySection`, a view
   `private` to that file. A suggested replacement for the sentence: "`BoardTray.swift`'s `TraySection`
   has the same shape and is reproduced here as `linksSection` rather than shared: it is `private` to
   that file." It keeps the paragraph's three-line footprint. See "Open for Stefano" on sharing it.
6. **`EmbedAttachment.swift:139`**: `ResizeHandleView` becomes `BoardGripView`. The rest of the sentence
   stays.
7. **`CardTextView.swift:40-46`**. State what is true now:
   - the setting narrows the card's emphasis, strikethrough and link runs;
   - since ADR-0037's §D8 amendment, `Coordinator.hiddenKind(for:)` maps `.strikethrough` and `.link`
     the way the note editor's table does.

   Drop "(ADR-0029 §D17, not widened by this chain)" and "only ever narrows the card's bold/italic
   reveal". Line 40's "bold/italic runs" goes too. Keep the sentence on the route
   (`applyBoardSettings()` → `revealsInlineSpans` → `StickyTextCard`) and the "defaulted `var`" sentence.
   No more than the seven lines it replaces (rule 3).

**Done when:**

- these greps are empty:
  - `rg -n "Workspace/FormattingTextView\.swift" Sources/Features/Editor`;
  - `rg -n "WorkspaceController\.swift:[0-9]" Sources`;
  - `rg -n "traySection" Sources`;
  - `rg -n "ResizeHandleView" Sources/Features/Editor`;
  - `rg -n "bold/italic" Sources/Features/Workspace/CardTextView.swift`;
- in `NoteTextView+Coordinator.swift`, the line above `static func hiddenMarker(` is a `///` line, and
  `hiddenKind(for:)`'s block begins "Which kind of hidden marker";
- `CardTextView.swift` is at most 403 lines and `NoteTextView+Coordinator.swift` at most 634;
- there is no new lint finding, and the suite is green;
- `scripts/check-adr-references.py`, run after `git fetch`, is clean. The rewritten comments cite
  ADR-0037, and that ADR lives in this directory.

**Commit:** `docs: correct the comments PG-146 left stale outside its fence (PG-349)`.

### Task 4 — Four more stale comments found while planning (coder) (A-09, A-10) — gated at G0

**Files:**

- `Sources/Features/Editor/NoteTextView+Coordinator.swift`;
- `Tests/NoteEditorTeardownTests.swift`, comment only;
- `Sources/Features/Workspace/CardTextView+Reveal.swift`;
- `Sources/Features/Workspace/CardTextAttributes.swift`.

The edits:

- **E1.** In `hiddenKind(for:)`'s doc, the `default` no longer keeps "this chain's four constructs" out
  of a card. Say what it keeps out now: the live `NSView` grid above all, then blockquote, rule and
  message anchor. Add that ADR-0037's §D8 amendment gave the card strikethrough and links. Keep "The two
  are one call apart on purpose." Net zero lines or fewer.
- **E2.** "(`CardTextView.swift:199`)" becomes "(its `undoManager`, `CardTextView.swift`)". Nothing else
  in the test file changes.
- **E3.** "the same restraint `NoteTextView+Reveal.swift:66-88` keeps" becomes "the same restraint
  `RevealController.apply(to:)` keeps (`NoteTextView+Reveal.swift`)".
- **E4.** "this file's own `FormattingTextView.swift` twin resolves by hand" becomes "…
  `FormattingTextView+Clicks.swift`'s `followLinkIfPresent(at:)` resolves by hand", rewrapped within
  the block.

**Done when:**

- `rg -n "(CardTextView|NoteTextView\+Reveal)\.swift:[0-9]" Sources Tests` is empty;
- `rg -n "four constructs" Sources/Features/Editor/NoteTextView+Coordinator.swift` is empty;
- `rg -n "\`FormattingTextView\.swift\` twin" Sources` is empty;
- line counts follow rule 3; no new lint finding; the suite is green; the counts are unchanged.

**Commit:** `docs: correct four more stale comment citations (PG-349)`.

### Task 5 — Close-out (orchestrator) (A-04, A-06, A-11, A-12, A-13, A-14)

- **Final verification:**
  - TEST-CMD green;
  - the `perg` and `pergamenum-mcp` builds green;
  - counts at 4979 and 13627;
  - the lint table before and after, in the PR body;
  - `git diff --name-only origin/main...HEAD` lists none of `.claude/protected-interfaces`,
    `Sources/Connector/VaultPayloads.swift` or `Sources/Features/Editor/CompletingTextView+Pasteboard.swift`;
  - `scripts/check-adr-references.py` clean, after `git fetch`.
- **At merge:** `scripts/uitests.sh --status`, then `--affected`. In `classes_for_path`
  (`scripts/uitests.sh:163-183`), `Sources/Core/Conventions/*`, `Sources/Features/Editor/*`, `Sources/App/*`
  and `Sources/Vault/*` all map to `ALL`. So this is the full GUI suite, about 25 minutes. The result is
  advisory (CLAUDE.md merge gate). A `contaminated` verdict means rerun, not act.
- **`TODO.md`:** `PG-349` becomes `[x]` with the PR number. Record whether Task 4 landed or was dropped,
  and add the "Open for Stefano" follow-up if Stefano files it.
- **After merge:** close GitHub #773. There is no ADR status to flip.

## Observable-contract staleness

**The changed contract.** The synthesised memberwise initialiser
`NoteViolations.init(name:frontmatter:tags:relatedMissingInSection:relatedMissingInFrontmatter:taskMarkers:categories:)`
gains default values on its first five parameters, and the type gains the implicit `init()`. The change
is additive: every existing call still compiles and still builds the same value.

Nothing else changes:

- no HTTP status, output format, on-disk format or schema;
- no accessibility identifier;
- no JSON shape: `perg lint --json` and the MCP `lint` tool build `VaultAPI.LintFinding` from the
  linter's construction, which is unchanged.

**Call sites found by grep** (`rg -n "NoteViolations\(" Sources Tests UITests`):

| Kind | Sites | Action |
| --- | --- | --- |
| Production, single-axis or none | the seven in the inventory | rewritten in Task 2 |
| Production, full | `Sources/Vault/VaultSession+Search.swift:190` | unchanged; Task 1 pins its last unpinned axis |
| Tests | `Tests/ConformanceTextTests.swift:16`, `:55`; `Tests/LintFindingStringsTests.swift:47` | unchanged. They pass every argument explicitly, and none asserts the old, undefaulted shape. |
| UITests | none | — |

The task "update tests and call-sites asserting the old behaviour" is Task 2 for the seven call sites.
No test asserts the old behaviour, so no test is updated. **Run the full `PergamenumTests` after every
task** (rule 9), not only the suites named.

## Risks and HITL gates

### Risks

- **The linter loses compile-time completeness on five axes.** Mitigations: Task 1's guard, Task 2's
  mutation check, and the six existing per-axis tests named in the inventory.
- **A future eighth field** added with `= []` can be left out of the linter with no compiler error.
  This has been true since ADR-0021 and is unchanged here. Task 2's type doc names the linter as the one
  full construction, which is where a reader adding a field looks.
- **`NoteViolations()` resolution.** Once every stored property has a default, Swift synthesises both
  `init()` and the memberwise initialiser. `NoteViolations()` is the ordinary call for that case (SE-0242
  behaviour, stated from the language rules and not yet built on this Xcode 27 toolchain). Task 2's build
  is the check. If it fails, the fallback at `VaultController+Conformance.swift:16` is
  `NoteViolations(name: [])`.
- **The GUI suite at merge is the full suite**, about 25 minutes, because Core, Editor, App and Vault
  paths map to `ALL`. It is advisory.
- **File-length creep.** A comment rewrite that adds lines to `CardTextView.swift` (403) or
  `NoteTextView+Coordinator.swift` (634) worsens a pre-existing warning. Rule 3 forbids it.
- **Merge conflicts with parallel chains** are expected only in `TODO.md`. Merge `origin/main` in, and
  never force.

### Dependencies

Nothing external: no third-party API, consent flow, cloud console, environment variable or port. No SPM
dependency changes. No context7 lookup was made, because no library, SDK or service is involved, only
Swift's memberwise initialiser.

### HITL gates

None of them is the implementing agent's to pass:

- **G0: approve this plan.** That covers the no-ADR outcome, Task 1's added test, and Task 4. Drop any of
  E1 to E4 here, or Task 4 as a whole.
- **The baseline merge of `origin/main`,** if it has moved.
- **Each task's commit,** with its diff.
- **At merge:** `scripts/uitests.sh --status`, then `--affected`.
- **Push, the pull request, the merge to `main`,** and the closing of #773.
- **Nothing here authorises:**
  - editing an assertion;
  - a `swiftlint:disable` or a threshold change;
  - an edit to `.claude/protected-interfaces`, `VaultPayloads.swift` or
    `CompletingTextView+Pasteboard.swift`;
  - committing the mutation check;
  - changing `.claude/test-cmd`.

  If a task cannot meet its bar without one of these, stop and report.

## Open for Stefano

- **`TraySection` and `linksSection` are now one `private` apart.** Since PG-146 Task 6, `TraySection`
  (`BoardTray.swift:255`) is a standalone generic view. `PratichePane+Links.swift`'s `linksSection`
  (`:35-57`) is the same view down to the token: a caption header, an optional count, the `-header`
  identifier, then either the empty text or the rows. Sharing it would take three things:
  - widening `TraySection`;
  - moving it to a neutral home, such as `Sources/DesignSystem/` beside `BreadcrumbBar.swift`;
  - having `linksSection` call it with `badge: count > 0 ? "\(count)" : nil`,
    `accessibilityLabel: "\(title): \(count)"` and `isEmpty: count == 0`.

  The identifiers would stay byte-identical. `TraySection`'s own doc gives the argument for sharing: "a
  header that drifts from the one under it is the kind of difference nobody decided on".
  **Recommendation:** do it as its own small PR right after this one. It is not folded in here because it
  moves a view across two features, and this PR's brief is a default and some comments. Task 3 makes the
  comment true for today, and that PR would delete it.
- **`ConformanceTextTests`' private helper** duplicates the new defaults. Recommendation: leave it. It
  is harmless, and keeping the tests unedited is what lets them testify that the explicit form still
  means the same thing.

## Acceptance items

- **A-01** The five fields default to `[]`. Declaration order, `Equatable`/`Sendable`, `isEmpty` and
  `count` are unchanged. No `init` or `extension` is added, and the file stays Foundation-only.
- **A-02** The seven sites write only their axis: six one-label calls and one `NoteViolations()`.
- **A-03** The linter's construction in `VaultSession+Search.swift` is unchanged and still passes all
  seven labels.
- **A-04** No behaviour change: the full `PergamenumTests` is green after every task, and no assertion is
  edited.
- **A-05** The linter's `relatedMissingInFrontmatter` axis is pinned end to end, and the pin is shown to
  fail when that argument is removed.
- **A-06** The `perg` and `pergamenum-mcp` schemes build.
- **A-07** `NoteViolations`' comments state the defaulting rule, and the two "keep compiling untouched"
  sentences are gone.
- **A-08** The seven ledger comments are true.
- **A-09** E1 to E4 are true, for whichever of them G0 keeps.
- **A-10** There is no new SwiftLint finding. `CardTextView.swift` is at most 403 lines and
  `NoteTextView+Coordinator.swift` at most 634.
- **A-11** The counts go from 4978 `@Test` and 13625 `#expect(`/`#require(` to 4979 and 13627.
- **A-12** No protected interface is touched, and neither is `.claude/protected-interfaces`.
- **A-13** `scripts/check-adr-references.py` is clean.
- **A-14** Close-out: the GUI `--affected` run at merge (advisory), `PG-349` closed in `TODO.md` with
  the PR number, and #773 closed.

---

TEST-CMD CANDIDATE: `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test`

TEST-CMD MODE: brownfield

This is `.claude/test-cmd` verbatim, and it stays that way on purpose. The `Stop` hook runs it at the
end of every turn, and CLAUDE.md records why `-only-testing:PergamenumTests` is load-bearing. It covers
every suite this plan relies on. The rest runs at the gates above and is never wired into the hook:

```bash
xcodebuild -workspace Pergamenum.xcworkspace -scheme perg -destination 'platform=macOS' build             # Task 2, Task 5
xcodebuild -workspace Pergamenum.xcworkspace -scheme pergamenum-mcp -destination 'platform=macOS' build   # Task 2, Task 5
scripts/uitests.sh --status && scripts/uitests.sh --affected                                              # at merge, advisory, selects ALL
```
