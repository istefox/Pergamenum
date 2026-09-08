# Plan — A visual query builder for `pergamenum-view` fences

- **ADR:** `docs/architecture/ADR-0034-pergamenum-view-query-builder.md`
  (the orchestrator relocates it to `docs/adr/0034-pergamenum-view-query-builder.md`, the ADR-0029
  and ADR-0033 precedent — the architect's write scope is `docs/architecture/`, this repo's ADRs
  live in `docs/adr/`)
- **SPEC:** `SPEC.md` (R-01 … R-17)
- **BRAINSTORM / UX blueprint / Claude Design:** none. All three optional gates were skipped —
  the SPEC settled the design questions in the interview. **Do not go looking for them.**
- **Branch base:** `feat/pergamenum-view-query-builder` at `0bec334`. ADR-0033 is merged (PR #178),
  so `ViewBlockAttachment`, `ViewBlockHostStore`, `NoteTextView+ViewBlocks`,
  `EditorDecorationDelegate+ViewBlockRendering` and `RenderedViewBlock`'s `failed(_:)` error card
  all exist and are the shape every task below builds on.
- **Style:** TDD. Red precondition first on every task, per this repo's last eight chains.
- **Nothing in the query layer is built.** `ViewBlock`, `ViewFilter`, `ViewField`, `ViewDateBound`,
  `ViewEvaluator`, `ViewQuerySource` are used exactly as merged. If a task looks like it needs to
  edit one of them, **stop and report** — that is R-17 failing, not a detail.

---

## Before anything: what the SPEC says that the source does not

Verified against the working tree at `0bec334`, by grep, at the line. **Do not design or code
against the left column.** The first five would each ship a builder that writes fences the app
rejects.

| # | SPEC says | Source says | Where |
|---|---|---|---|
| C1 | the date bound supports `oggi`, `oggi-N`, `inizio-settimana` | **`ViewDateBound.parse` accepts `today`, `today-N`, `week-start` and an ISO day, and nothing else.** The Italian words parse as nothing and the block fails on that line. Labels stay Italian; the **written text** is `ViewDateBound.todayKeyword` / `weekStartKeyword` (ADR §D12) | `Sources/Core/Query/ViewDateBound.swift:29-54`, `:80-87` |
| C2 | Ambito uses "the vault's existing folder-tree component (the same tree the Note/Workspace sidebars already draw)" | **No such component exists.** `NoteListPane`/`NoteTreeRow` and `WorkspaceBrowser+Tree`/`+Rows` are panes bound to `VaultController` selection, drag payloads and context menus. The app's actual folder **picker** is a flat `Menu` over `vault.folders`, at two sites. A new `FolderPickerMenu` is written; **no third tree** (ADR §D11, A9) | `NewNoteComposer.swift:110-123`; `NoteRowMenu.swift:34-48`; `VaultSession+Files.swift:92-105` |
| C3 | the `tag` term uses "the existing tag browser/picker" | `TagBrowserView` is a full pane: `HSplitView`, toolbar, rename sheet, rename-undo banner, pinned tags. **Not a picker.** Reusable part is the data — `IndexSnapshot.tagUsage()` and `TagNamespace.allCases` | `TagBrowserView.swift:15-66`; `IndexSnapshot+Search.swift:10-17`; `Vocabulary.swift:56-64` |
| C4 | `linksTo`/`linkedFrom` use "a searchable picker over vault note titles" | **No such picker exists.** `CompletingTextView`'s wikilink completion is an `NSPanel` driven from `rangeForUserCompletion` inside an `NSTextView` — structurally unusable in a SwiftUI sheet row. `RelatedLinkSheet` is the shape to copy: `TextField` + `List` over `vault.index.search(query, limit: 20)`. **`RelatedLinkSheet.swift` is not edited** (ADR §D11) | `CompletingTextView.swift:266-296`; `RelatedLinkSheet.swift:27-40`, `:73-76` |
| C5 | Ambito rows "each becoming a `path()` term; rows combine with `or`" | True **and enforced**: `ViewBlock.parse` runs `from`'s value through `ViewFilter.parse` then `collectPaths`, which throws for anything that is not `path()` or `or`. The writer may emit nothing else in `from`, ever | `ViewBlock.swift:175-193` |
| C6 | (unstated) the writer may emit any key | `ViewBlock.parse` throws on a **duplicate key** (`«where» è già alla riga N`) and on an **empty value** (`«sort» non ha valore`). A section with nothing in it must be **omitted**, never emitted bare | `ViewBlock.swift:129-136` |
| C7 | the comparison is "restricted to those two" fields; `has` picks from the 18 | Enforced in the parser, not by convention: `comparison` throws unless the field is `.date`/`.modified`; `has()` resolves through `ViewField(rawValue:)`. Pickers **restrict**, never validate afterwards | `ViewFilter.swift:179-204` |
| C8 | the affordance is needed "on both states of the fence's rendered chrome" | `RenderedViewBlock.body` calls `header(renderer:count:)` from **both** the `.failure` and `.success` branches, and `onEditSource`'s button already lives inside it. R-01 is **one `Button` in one place** and cannot diverge (ADR §D1) | `RenderedViewBlock.swift:51-61`, `:98-125` |
| C9 | (unstated) the insert command is the app's first | `EditorCommand.viewEntries` already puts **five** `Vista …` slash entries in the catalogue, each writing a raw skeleton with a caret placement. They stay. The new command is a sixth **surface**, in the Inserisci menu, not a replacement (ADR §D4) | `EditorCommand.swift:96-114`, `:155-168` |
| C10 | (unstated) opening the builder after an insert is free | The caret-insert channel is a **tuple in three declarations** — `Navigation.pendingInsertion`/`pendingCursorOffset` → `consumeInsertion()` → `EditorColumnView.pendingInsertion` → `NoteTextView.insertion`. Carrying "and open the builder" means changing that type (ADR §D4, contract table below) | `Navigation.swift:141-165`; `EditorColumnView.swift:30`, `:83-86`; `NoteTextView.swift:79`, `:332-338` |
| — | Out of scope: `MarkdownBlocksView`, `TranscludedNoteView`, `NoteExporter`, `ViewsPane`, `CardTextView` | Free and greppable: the new `RenderedViewBlock` input is optional with a `nil` default, and `nil` is today's behaviour. **None of those five files appears in this chain's diff.** Task 10 asserts it | ADR §D1, §D14 |

**Three constraints the SPEC could not know** (ADR §Context):

1. **`replaceAtomically(_:with:in:)` is the only mechanism a write to the note's characters may
   use** (`NoteTextView+EmbedCaret.swift:101-113`). No `insertText`, no undo group opened by hand,
   never a write through `parent.text`. R-13's single `Cmd+Z` is a property of there being one
   write, not a rule anyone keeps.
2. **A commit must re-read the fence from the live characters**, never trust the shape the sheet
   was opened on: `commitTable`'s reload guard (`NoteTextView+Tables.swift:169-192`) exists because
   the buffer can be replaced wholesale between two passes — an FSEvents reload, «Ricarica da
   disco», `updateNSView`'s own `textView.string = text`. ADR §D3 copies it.
3. **`EditorDecorationDelegate.viewBlockRun(in:atParagraphStart:)` was written for exactly this
   second caller** — its own header says so (`+ViewBlockRendering.swift:9-11`, `:86-90`): `static`,
   `NSString`, UTF-16, touching no delegate state, so a `@MainActor` commit path may call it.
   **Do not write a second fence-locating function.**

---

## Contract changes and their already-grepped call sites

Every row is a stale-assertion site found by grep **before** this plan was written. The coder does
not go looking for these; they are listed, and they are updated in the same task that changes the
contract. **Run the full unit suite after each task, not just the touched file's tests** — a
contract change breaks tests in files that never mention it.

| Contract | Change | Call sites that break |
|---|---|---|
| `RenderedViewBlock` | add `onEditQuery: (() -> Void)? = nil` (a **third** optional input, ADR-0033 §D9's rule) | **Additive with a default, so nothing breaks.** Two construction sites: `MarkdownBlocksView.swift:70` (**not edited** — passes nothing, keeps R-16/out-of-scope true by construction) and `ViewBlockHostStore.swift:107`. `Tests/ViewRenderingTests.swift` and `Tests/ViewBlockOutOfScopeTests.swift` name the type — defaults keep both green **unmodified**. |
| `ViewBlockHostStore.rootView(...)` | add `onEditQuery: (() -> Void)? = nil` | One production caller: `NoteTextView+ViewBlocks.swift:181`. **Test callers that must stay green unmodified:** `Tests/ViewBlockQuerySourceTests.swift:161` and `:171` call it with `(source:queries:theme:)` — a defaulted parameter keeps both compiling. |
| `NoteTextView` | add `onEditQuery: ((ViewQueryEditRequest) -> Void)? = nil` | **Additive with a default.** Three production sites: `EditorColumn+Text.swift:47` (**passes it**), `DiaryView.swift:88` and `TodayView.swift:192` (**pass nothing, keep today's behaviour** — the same deliberate nil ADR-0033 gave `queries`). Eight test construction sites (`Tests/EmbedResolutionTests.swift:56`, `FoldBadgeClickTests.swift:22`, `NoteFindTests.swift:271`, `EmbedDrawingTests.swift:178`, `ViewBlockCaretTests.swift:52`, `NoteListEditingTests.swift:54`, `TranscludedLineTests.swift:36`, and `Tests/EmbedEditorTestSupport.swift`) stay **unmodified**. |
| `Navigation.consumeInsertion()` | returns `Navigation.Insertion?` (struct: `text`, `cursorBack`, `opensQueryBuilder`) instead of `(text:cursorBack:)?` | **Compile errors, all five listed:** `Navigation.swift:141-165` (the two stored halves and the bundling), `EditorColumnView.swift:30` (`@State var pendingInsertion`), `EditorColumnView.swift:85` (the assignment), `NoteTextView.swift:79` (`var insertion`), `NoteTextView.swift:332-338` (`insertion.text`/`.cursorBack` reads), `EditorColumn+Text.swift:73-74` (`insertion:`/`onInsertionApplied:`). Nothing in `Tests/` or `UITests/` names `consumeInsertion` or constructs an `insertion:` — grepped, zero hits. |
| `Navigation.insert(_:cursorBack:)` | gains `opensQueryBuilder: Bool = false` | **No call site breaks** — the parameter is defaulted. Ten `navigation.insert(` sites exist (`MenuCommands.swift` ×7, `CommandActions.swift:228`, and two more); **none is edited**. The new Inserisci entry is an eleventh. |
| `ViewQueryEditRequest` | new type, `Sources/Features/Editor/` | New. No existing caller. |
| Six new files under `Sources/Features/Views/` | new | New. `tuist generate --no-open` after each task that adds one. |

**Protected interfaces — none touched, checked one by one:** `IndexCache.schemaVersion` (no index
field, no schema question anywhere in this chain), `VaultAPI.LintFinding` (no connector change of
any kind), `CompletingTextView+Pasteboard.swift` (the builder is a SwiftUI sheet — no paste path, no
drop path, no `Transferable`), `ImportNaming.recordingNoteTitle` (unrelated).
**`interface-check.sh` must stay silent for the whole chain.**

---

## Conventions binding on every task

- **The tester owns the interface, the coder owns the body.** Swift is compiled: a batch that leaves
  the target unable to build produces no red tests at all, only a build error. Every new type's
  *declaration* (stored properties, method signatures returning a stub, enum cases) is written in
  the **tester's** task together with the tests that call them. The coder fills in bodies.
- **`tuist generate --no-open` after every task that adds a file under `Sources/` or `Tests/`.** Also
  after any `git stash`/`git checkout` that adds or removes a file — the generated project still
  lists what is no longer there and the build fails naming the compiler rather than the cause.
- **Swift Testing (`@Test`/`#expect`) for all new tests.** Never XCTest, except inside `UITests/`,
  which is an XCTest bundle and stays one.
- **Every new test file's header comment cites both `ADR-0034` and this plan's basename**
  (`2026-09-07-pergamenum-view-query-builder`). That citation is this chain's coverage anchor —
  there is no separate harness script (below), so the test files are what names the plan.
- **Nothing new under `Sources/Core/**`, `Sources/Connector/**`, `Sources/CLI/**`,
  `Sources/MCPServer/**`, and no edit to any file in them.** Those are `sharedSources` globs
  (`Project.swift:72-97`) and R-17 draws the line at the directory. Every file this chain adds is
  under `Sources/Features/`; the only files edited outside it are `Sources/App/Navigation.swift` and
  `Sources/App/MenuCommands.swift`, neither of which is shared. **If a task looks like it needs to
  touch `Sources/Core/Query/`, stop and report.**
- **One principal type per file, and no view type over 150 lines** (`~/.claude/rules/swift.md`).
  Sections are `private struct`s in their own file, not computed properties on the sheet.
- **`@Observable`, never `ObservableObject`**, for the draft model. No force-unwrap, no `try!`.
- **No hardcoded colour, font, spacing or corner radius in any view.** Every value goes through
  `theme.color(_:)` / `themedText(_:color:)` / `theme.spacing(_:)` / `theme.radius(_:)`. A view that
  uses a colour without a token does not pass review (CLAUDE.md).
- **UI language is Italian; code, comments and commits are English.** The builder's labels are the
  SPEC's own words — Ambito, Filtro, Ordina, Raggruppa, Rendering, Colonne, Limite, Fatto, Annulla.
- **Accessibility identifiers on every control a UI test could ever want**, never the words on it
  (CLAUDE.md: prose grows, identifiers are the contract). At minimum:
  `rendered-view-edit-query`, `view-query-builder`, `view-query-done`, `view-query-cancel`,
  `view-query-reason`, `view-query-match-count`, `view-query-render`, `view-query-add-filter`.
- **`CardTextView.swift`, `MarkdownBlocksView.swift`, `TranscludedNoteView.swift`,
  `NoteExporter.swift`, `ViewsPane.swift` and `RelatedLinkSheet.swift` are not edited.** If a task
  looks like it needs one, **stop and report** — that is the design leaking.
- **The unit test command is `.claude/test-cmd` exactly as it stands** — `-only-testing:PergamenumTests`.
  **Do not widen it**: the UI suite in there terminates the app the person at the keyboard is using
  and leaves an instance holding the global hot key exclusively (CLAUDE.md, two hours lost once).
- **`scripts/uitests.sh` runs once, in Task 10, before merge** — never per task. An argument
  *replaces* the selection rather than adding to it. Any new UI-test file passes
  `-disableCalendar YES` and `-disableUpdater YES`.
- **No new harness script.** This repo has none of that kind; `scripts/` holds
  release / uitests / mcp-smoke / install-cli / appcast / fetch-sparkle-tools and stays as it is.
  Coverage for this chain is `.claude/test-cmd` plus `scripts/uitests.sh` plus the per-task test
  files named below, each citing this plan's basename in its header. Any throwaway helper written
  for a hand-check must be **Bash 3.2-clean**: no `mapfile`, no associative arrays, no
  `${x^^}`/`${x,,}`; collect array output with
  `arr=(); while IFS= read -r x; do arr+=("$x"); done < <(cmd)`.
- **`weakening-scan.sh` reports every Swift Testing test as `zero-assertion-test`** because its body
  scanner treats `#expect` as a comment. Expected, systematically wrong for this stack, advisory
  (CLAUDE.md). A genuinely assertion-free test still has to be caught by reading the diff.
- **The secret scanner's `assigned-secret` heuristic fires on design-token lines.** Expected false
  positives; read each hit before dismissing it.
- **Never disable or delete a test to make the suite pass.** If one must change, say why in chat
  first.

---

## Phase 1 — the pure half (no view, no AppKit, no vault)

### Task 1 — `ViewQueryFlattening`: is this `where` a flat AND of terms? (R-06, R-07)

- **Tester** writes `Tests/ViewQueryFlatteningTests.swift` and declares
  `enum ViewQueryFlattening { static func terms(of: ViewFilter) -> [ViewFilter]? }` in
  `Sources/Features/Views/ViewQueryFlattening.swift`, stubbed to return `nil`, so the target builds.
  Assertions, all against filters produced by the **real** `ViewFilter.parse` rather than
  hand-built, so the test cannot drift from the grammar:
  - `.all` → `[]` (a fence with no `where` shows zero rows, not a fallback) (R-07);
  - each of the **eight** leaf kinds alone → a one-element array holding that exact term —
    `path`, `tag`, `linksTo`, `linkedFrom`, `task(open)`, `has(tasks.open)`, `text`, and a
    `date >= 2026-08-01` comparison (R-06, one assertion per kind);
  - `a and b and c` → three terms **in source order** — the parser associates `and` to the left
    (`ViewFilter.swift:100-107`), so this is the assertion that pins the traversal;
  - `(a and b) and c` → three terms: parentheses need no case, the parser consumes them (ADR §D5);
  - `a or b` → `nil`; `not a` → `nil`; `a and not b` → `nil`; `a and (b or c)` → `nil` — the four
    shapes that send Filtro to the raw-text fallback (R-07);
  - a filter mixing a comparison with terms, `date >= today and tag("x")` → two terms, so the
    fallback is not triggered by the one term kind that is not a call.
- **Coder** implements the recursion. Five cases and no `default`, so a term added to `ViewFilter`
  later is a compile error here rather than a silently unflattenable filter.
- Budget: `Sources/Features/Views/ViewQueryFlattening.swift`, `Tests/ViewQueryFlatteningTests.swift` (~140 lines)

### Task 2 — `ViewQueryText`: the draft becomes a fence body, and the stub (R-04, R-05, R-08, R-09, R-10, R-15)

- **Tester** writes `Tests/ViewQueryTextTests.swift` and declares, in
  `Sources/Features/Views/ViewQueryText.swift`, the writer's whole surface stubbed:
  `body(of:) -> String`, `text(of term: ViewFilter) -> String`,
  `columnsToWrite(_ selection: [ViewField], render:) -> [ViewField]?`,
  `stub(atLineStart: Bool) -> (text: String, cursorBack: Int, openingOffset: Int)`.
  The `ViewQueryDraft` declaration it needs is Task 3's; this task's tests build it through a
  memberwise initialiser the tester declares here and Task 3 fills out.
  **The dominant assertion shape is a round trip**: write a draft, `ViewBlock.parse` the result,
  compare the parsed block to what was intended. A writer whose output the real parser rejects is
  the failure this whole chain exists to prevent.
  - **round trip, all seven keys** — the block ADR-0009 prints (`Tests/ViewQueryTests.swift:7-24`
    has it) is seeded into a draft, written, re-parsed, and equals the original (R-05, R-08, R-09,
    R-10);
  - **key order** is `ViewBlock`'s declaration order, asserted on the string;
  - **`from` is written `path("a") or path("b")` and nothing else** (C5, R-05); zero rows → the key
    is **absent** from the output (SPEC edge case);
  - **an empty section is omitted, never emitted bare** (C6): zero sort rows, no group outside a
    board, a blank limit — each asserted absent, and the result asserted to parse;
  - **`columnsToWrite` returns `nil` for every renderer's own `effectiveColumns`** — five
    assertions, one per `ViewBlock.Renderer` case, and the corresponding `body(of:)` output
    asserted to carry **no `columns:` line** (R-15);
  - `columnsToWrite` returns the selection when it differs by one element, and **when it differs
    only in order** — `[.tags, .title]` against a board's `[.title, .tags]` is written, not
    discarded (ADR §D9, A5; R-09);
  - **term rendering, one assertion per kind**, each re-parsed through `ViewFilter.parse` and
    compared to the term it came from — including a `tag("status-*")` glob, a `text()` argument
    containing a space (the quoting is what makes it lex), `task(open)`/`task(done)`, and
    `has(tasks.open)` (R-06 is Task 6's, the *rendering* of the eight kinds is here);
  - **date bounds write the parser's spellings** (C1): `.day`, `.today`, `.daysBeforeToday(7)`,
    `.weekStart` each written and re-parsed through `ViewDateBound.parse`, asserted equal —
    `oggi`/`inizio-settimana` must appear **nowhere** in the produced text;
  - **an incomplete term row contributes no term** (ADR §D7): a `tag` row with an empty argument
    produces no `tag("")` anywhere in the output;
  - **the stub** (R-04): `stub(atLineStart: true)` starts with the backticks and
    `openingOffset == 0`; `stub(atLineStart: false)` starts with `\n` and `openingOffset == 1`; both
    bodies parse (`render: table`), and both are closed fences — so
    `EditorDecorationDelegate.viewBlockRun` finds them.
- **Coder** implements the writer. Pure `String` in, `String` out; no `Theme`, no `VaultController`,
  no AppKit.
- **Contract-staleness:** `Tests/ViewQueryTests.swift` is the parser's own suite and must stay green
  **unmodified** — a red there means this task changed the grammar rather than writing to it.
- Budget: `Sources/Features/Views/ViewQueryText.swift`, `Tests/ViewQueryTextTests.swift` (~320 lines)

### Task 3 — `ViewQueryDraft` and the field-by-field seed (R-02, R-03)

- **Tester** writes `Tests/ViewQuerySeedTests.swift` and declares, in
  `Sources/Features/Views/ViewQuerySeed.swift`: the `@Observable final class ViewQueryDraft` (its
  stored sections — scope rows, filter rows or a raw `where` string, sort rows, group, render,
  ordered columns, limit) and `static func seed(from body: String) -> ViewQueryDraft`, stubbed.
  Assertions:
  - **a fence that parses seeds every one of the seven keys** (R-02), asserted by writing the seeded
    draft back out through Task 2's writer and comparing to the original body — round trip again,
    so seed and writer are tested against each other rather than each against a fixture;
  - **a fence whose `where` is flat seeds filter rows**; one whose `where` uses `or` seeds the
    **raw-text** field with the original `where` value verbatim **and still seeds the other six
    keys** (R-07 is Task 5's UI half; this is its data half) (R-02);
  - **R-03, one assertion per key**: a body where exactly one line is broken —
    `render: tabella` (not a renderer), `sort: creato desc` (an absent field, and the one
    `ViewField.absentFieldReason` has a sentence for), `limit: zero`, `from: type-note` (not a
    `path()`), `where: type-note` (a bareword), `group: tag("a") and tag("b")`,
    `columns: [titolo]` — each seeds **every other key correctly** and leaves the broken one at its
    default;
  - **a body that is not `key: value` at all** (prose, an empty fence) seeds an all-defaults draft
    with `render == .table` and nothing else (R-03);
  - **a `render: board` fence seeds `render` and `group` together** — the synthetic-block trick must
    not trip the board-needs-group rule (ADR §D6);
  - **a duplicate key seeds the first occurrence and does not throw** — the seeder is per key, so
    `ViewBlock.parse`'s own duplicate refusal (C6) never fires on it.
- **Coder** implements the seeder as ADR §D6 specifies: split on the first `:` per non-empty line,
  then per key parse `"render: table\n<key>: <value>"` (or `"render: <value>"` for `render` itself)
  through the **public** `ViewBlock.parse` and read the field off the result. **No new grammar, and
  no visibility change in `Sources/Core`** (A2, A6). Also implements `ViewQueryDraft`'s memberwise
  initialiser Task 2 declared.
- Budget: `Sources/Features/Views/ViewQuerySeed.swift`, `Tests/ViewQuerySeedTests.swift` (~300 lines)

---

## Phase 2 — the anchor and the one write

### Task 4 — `ViewQueryEditRequest` and `commitViewBlock`, with `commitTable`'s reload guard (R-13)

- **Tester** writes `Tests/ViewQueryCommitTests.swift`, modelled on the existing editor tests that
  drive a real `NSTextView` (`Tests/ViewBlockCaretTests.swift:52`'s `NoteTextView` construction and
  `Tests/TableRenderingTests.swift`'s storage helpers are the shapes to copy, not to import).
  Declares `ViewQueryEditRequest` (`id`, `source`, `commit`) in
  `Sources/Features/Editor/ViewQueryEditRequest.swift` and
  `Coordinator.commitViewBlock(_:at:in:) -> Bool` in
  `Sources/Features/Editor/NoteTextView+ViewBlockEditing.swift`, stubbed to `false`. Assertions:
  - **the happy path**: a note with one closed fence, commit a new body at the fence's opening
    offset → returns `true`, and the note's text is the same note with **only** the fence's range
    replaced — the text before and after the fence byte-identical (R-13);
  - **exactly one undo step** (R-13): after the commit, one `undoManager.undo()` restores the note
    to its previous text exactly, and a second undo does **not** peel off a second layer of this
    same commit;
  - **the fence moved out from under the sheet** — the buffer is edited (a line inserted above the
    fence) after the request was built and before `commit` runs → returns `false` and the buffer is
    **unchanged** (the SPEC's edge case, ADR §D3);
  - **the fence was deleted** → `viewBlockRun` at the offset answers nil → `false`, buffer
    unchanged;
  - **the fence's own text changed** at the same offset (someone typed inside it) → the recorded
    source no longer matches → `false`, buffer unchanged;
  - **model/buffer divergence** — `parent.text` and `textView.string` disagree at the offset, the
    state `commitTable`'s guard exists for → `false`;
  - **the replacement's shape**: the written text is `"```pergamenum-view\n<body>\n```"` with **no
    trailing newline**, because `viewBlockRun`'s range excludes the closing line's newline
    (ADR §D3) — asserted by comparing the whole note text, which catches a swallowed or doubled
    blank line;
  - **the opening line is normalised**: a fence opened `  ```pergamenum-view   ` commits to the
    canonical spelling and the note still parses.
- **Coder** implements `commitViewBlock` — the three-way guard, then
  `replaceAtomically(live.range, with:, in:)` and nothing else — and `ViewQueryEditRequest`.
  **`replaceAtomically` is the only write mechanism** (ADR-0019 §D7); no `insertText`, no undo group
  opened by hand, never a write through `parent.text`.
- **Contract-staleness:** run `Tests/ViewBlockRenderingTests.swift` and `Tests/TableRenderingTests.swift`
  in full — `viewBlockRun` gains a second caller in this task and must stay behaviourally identical.
- Budget: `Sources/Features/Editor/ViewQueryEditRequest.swift`, `Sources/Features/Editor/NoteTextView+ViewBlockEditing.swift`, `Tests/ViewQueryCommitTests.swift` (~280 lines)

---

## Phase 3 — the sheet

### Task 5 — the sheet shell: sections, validation, Fatto/Annulla (R-02, R-07, R-08, R-12, R-14)

- **Tester** extends `Tests/ViewQuerySeedTests.swift` with a `ViewQueryValidation` group and
  declares, in `Sources/Features/Views/ViewQueryBuilderSheet.swift`, the sheet
  (`source`, `queries`, `onCommit`, `onCancel`) plus the **pure** validation entry point the tests
  actually assert on — `static func validation(of draft: ViewQueryDraft) -> Result<ViewBlock, ViewBlockError>`
  — stubbed. Assertions on the pure function, never on a rendered view:
  - a complete draft → `.success`, and the block equals what Task 2's writer round-trips (R-02);
  - **a board with no group → `.failure`, carrying `assemble`'s own sentence** — asserted against
    the substring «aggiungi «group»», not a sentence retyped in the test (R-12, SPEC edge case);
  - a raw-text `where` that does not parse → `.failure` carrying `ViewFilter.parse`'s own line and
    reason (R-07, R-12, SPEC edge case);
  - an incomplete term row → `.failure` with its own reason, and Task 2 already asserted the row
    contributes no term to the body (ADR §D7);
  - **`validation` is `ViewBlock.parse` and not a second checker**: a draft that validates
    `.success` produces a body that `ViewBlock.parse` accepts, and vice versa — asserted over a
    table of drafts, which is R-12's real content.
- **Coder** writes the sheet shell and `Sources/Features/Views/ViewQuerySections.swift`: the seven
  sections in `ViewBlock`'s key order, each a `private struct` under 150 lines; the footer with
  «Annulla» (`.keyboardShortcut(.cancelAction)`, closes immediately, **no confirmation and no
  write** — R-14) and «Fatto» (`.keyboardShortcut(.defaultAction)`, `.disabled(!isValid)`) with the
  inline reason beside it. **Raggruppa is present only when `render == .board`** (R-08). Filtro
  renders the raw-text field when the seed carried one (R-07). Every value through a token; every
  control identified.
- **Watch for:** `Fatto` reporting a **refused** commit (Task 4 returning `false`) — the sheet stays
  open and shows the reason rather than closing on a write that did not happen.
- Budget: `Sources/Features/Views/ViewQueryBuilderSheet.swift`, `Sources/Features/Views/ViewQuerySections.swift`, `Tests/ViewQuerySeedTests.swift` (~380 lines)

### Task 6 — the eight term rows and the five pickers (R-05, R-06)

- **Tester** extends `Tests/ViewQueryTextTests.swift` with the row model's own assertions and
  declares `ViewQueryTermRow`'s row value (kind + argument) in
  `Sources/Features/Views/ViewQueryTermRow.swift`. The assertions are on the **row → term**
  conversion, which is pure, not on the controls:
  - each of the eight kinds converts to the `ViewFilter` case it names, with the argument the row
    holds (R-06, eight assertions);
  - the comparison row offers **only** `.date` and `.modified` and its conversion refuses anything
    else (C7) — a restriction, not a validation;
  - the `has` row offers all 18 `ViewField` cases and no more (R-06);
  - an Ambito row converts to a `path` glob and the section joins rows with `or` (R-05);
  - a row whose argument is empty converts to **nothing** (ADR §D7, and Task 2's counterpart
    assertion on the writer).
- **Coder** writes the rows and the pickers per ADR §D11, with **C2/C3/C4 as the binding facts**:
  - `FolderPickerMenu` — a `Menu` over `vault.folders` plus a free-text glob field, used by Ambito
    **and** the `path` row, declared once;
  - a tag picker grouped by `TagNamespace.allCases` over `vault.index.tagUsage()`, plus a glob
    field;
  - a note-title picker: `TextField` + `List` over `vault.index.search(query, limit: 20)`, the
    `RelatedLinkSheet` shape **copied, not extracted** — `RelatedLinkSheet.swift` is not edited;
  - a field picker over `ViewField.allCases` showing `ViewField.label`;
  - the date-bound control's three forms, writing `today`/`today-N`/`week-start` (C1).
- **Every read goes through an existing `VaultController` accessor** — `folders`, `index.search`,
  `index.tagUsage()`. No new index question, no protected file touched. If a picker looks like it
  needs a new accessor, **stop and report**.
- Budget: `Sources/Features/Views/ViewQueryTermRow.swift`, `Sources/Features/Views/ViewQuerySections.swift`, `Tests/ViewQueryTextTests.swift` (~360 lines)

### Task 7 — the live, debounced match count (R-11)

- **Tester** extends `Tests/ViewQueryTextTests.swift`:
  - **the debounce key is the assembled body**, asserted as a pure fact: two drafts that differ in a
    way the body does not record (re-picking the folder already picked, a column toggled off and
    back on) produce the **identical** string, so `.task(id:)` does not restart (R-11, and
    ADR-0009 §D7's "never per keystroke" — the same property `RenderedViewBlock.taskID` is tested
    for at `RenderedViewBlock.swift:92`);
  - a draft change that *does* change the body changes the key;
  - the count itself is `ViewEvaluator.evaluate(block, over: corpus).total` — asserted against a
    ten-note in-memory `ViewCorpus`, the shape `Tests/ViewEvaluatorTests.swift` already builds, so
    a filter matching zero notes yields `0` and **not** an error (SPEC edge case);
  - with `queries == nil` (no vault behind the sheet) the count is absent, not zero — the
    distinction `RenderedViewBlock` already draws between "no vault" and "no matches".
- **Coder** adds the `.task(id: body)` + `try? await Task.sleep(for: .milliseconds(250))` +
  `guard !Task.isCancelled` block to the sheet, writing «N note corrispondono» through
  `themedText(.caption, color: .textTertiary)` with identifier `view-query-match-count`.
  **No `Timer`, no Combine, no `DispatchQueue.asyncAfter`** — `.task(id:)`'s own cancellation is the
  debounce (ADR §D8).
- Budget: `Sources/Features/Views/ViewQueryBuilderSheet.swift`, `Tests/ViewQueryTextTests.swift` (~160 lines)

---

## Phase 4 — the two doors

### Task 8 — «Modifica query» on both fence states, threaded to the sheet (R-01, R-02, R-03)

- **Tester** writes `Tests/ViewQueryEntryPointTests.swift` and declares
  `RenderedViewBlock.onEditQuery`, `ViewBlockHostStore.rootView(onEditQuery:)` and
  `NoteTextView.onEditQuery`, all defaulted `nil`. Assertions:
  - **the affordance is present on a parseable fence and on one that fails `ViewBlock.parse`**
    (R-01) — asserted through the header being shared by both branches (C8) and, where a live
    render is needed, through the identifier `rendered-view-edit-query`;
  - **with `onEditQuery` nil, no control is drawn** — which is today's rendering, and what keeps
    `MarkdownBlocksView`/transclusion/export out of this feature (R-01's boundary);
  - **the request carries the fence's current body** (R-02): after a styling pass over a note whose
    fence body is X, the request built for that fence has `source == X`; after the body is edited
    and a new pass runs, a newly built request carries the **new** body — the staleness property
    the per-pass rebuild exists for (ADR §D2);
  - **an unparseable fence still produces a request with its raw body** (R-03) — this is the
    fix-it flow's entire precondition;
  - **two fences in one note produce two requests with different sources**, and the ordinal keying
    (ADR-0033 §D3) is untouched — asserted by `Tests/ViewBlockHostStoreTests.swift` staying green
    unmodified.
- **Coder** adds `onEditQuery` to `RenderedViewBlock` (one `Button` in `header(renderer:count:)`,
  beside `onEditSource` — **never two**, C8), threads it through `ViewBlockHostStore.rootView`
  and `refreshViewBlockHosts` (building the request in the same loop that already rebuilds the root
  view, capturing `opening` and `[weak textView]`, ADR §D2), adds `onEditQuery` to `NoteTextView`,
  passes it from `EditorColumn+Text.swift`'s `editing(_:)`, and presents the sheet from
  `EditorColumnView` with `.sheet(item:)` — handing it `viewQuerySource`, **the same source the
  drawn fence renders through** (ADR §D2).
- **`DiaryView.swift` and `TodayView.swift` are not edited.** They keep the `nil` default
  deliberately, exactly as they do for `queries`. If a task looks like it needs to edit them, stop
  and report.
- Budget: `Sources/Features/Views/RenderedViewBlock.swift`, `Sources/Features/Editor/ViewBlockHostStore.swift`, `Sources/Features/Editor/NoteTextView+ViewBlocks.swift`, `Sources/Features/Editor/NoteTextView.swift`, `Sources/Features/Editor/EditorColumn+Text.swift`, `Sources/Features/Editor/EditorColumnView.swift`, `Tests/ViewQueryEntryPointTests.swift` (~320 lines)

### Task 9 — the insert-view command: stub at the caret, builder in the same gesture (R-04)

- **Tester** extends `Tests/ViewQueryEntryPointTests.swift` and declares
  `Navigation.Insertion` (`text`, `cursorBack`, `opensQueryBuilder`), the new defaulted parameter on
  `Navigation.insert`, and `consumeInsertion()`'s new return type — **plus the five compile-forced
  edits listed in the contract table**, so the target builds. Assertions:
  - `insert(_:cursorBack:)` without the new argument leaves `opensQueryBuilder` false — the ten
    existing call sites keep their meaning (R-04's boundary);
  - **the stub lands at the caret and is a closed, parseable fence**: after the insertion is
    applied to a real `NSTextView`, `EditorDecorationDelegate.viewBlockRun` at the computed opening
    offset answers non-nil with a non-nil `block` whose `render == .table` (R-04);
  - **the opening offset is arithmetic, both ways** (ADR §D4): caret at a paragraph start → the stub
    has no leading newline and `openingOffset == insertionStart`; caret mid-line → leading newline
    and `openingOffset == insertionStart + 1`. Both asserted against `viewBlockRun` finding the
    fence, not against the number alone;
  - **the caret inside another construct** (the SPEC's edge case): with the caret mid-list-item and
    mid-table-row, the stub still lands as a recognisable fence — the newline is the same one
    `EditorCommand.separator` already writes, and no new placement rule exists to test;
  - **the request is raised exactly once** per insertion, and not again on the next view update —
    the same one-shot discipline `onInsertionApplied` already enforces.
- **Coder** changes `Navigation` (the struct, the defaulted parameter, `consumeInsertion`), updates
  the five compile-forced sites, adds the step to `NoteTextView.updateNSView`'s existing insertion
  branch (`:332-338`), and adds **one** entry to the Inserisci menu in `MenuCommands.swift`, beside
  «Tabella»: `Button("Vista…") { navigation.insert(stub.text, cursorBack: stub.cursorBack, opensQueryBuilder: true) }`.
- **No new `ShortcutCommand` case** (`Sources/Core`, R-17) and **no sixth slash-menu entry**
  (`EditorCommand.Action` has two kinds by declaration) — ADR §D4/A7. The five existing `Vista …`
  slash entries are **not** edited. If a task looks like it needs either, stop and report.
- **Contract-staleness:** run `Tests/EditorCommandTests.swift` in full — it reads
  `EditorCommand.Action` through its own `insertion(of:)` helper at `:176` and must stay green
  **unmodified**; a red there means this task edited the slash catalogue.
- Budget: `Sources/App/Navigation.swift`, `Sources/App/MenuCommands.swift`, `Sources/Features/Editor/NoteTextView.swift`, `Sources/Features/Editor/EditorColumnView.swift`, `Sources/Features/Editor/EditorColumn+Text.swift`, `Tests/ViewQueryEntryPointTests.swift` (~260 lines)

---

## Phase 5 — the fence around what must not move

### Task 10 — regression fence, full suite, UI suite, hand-check, docs (R-13, R-14, R-15, R-16, R-17)

- **Tester** writes `Tests/ViewQueryOutOfScopeTests.swift`:
  - **R-16** — a Workspace `.text` card never produces a `.viewBlock` kind, so no card reaches a
    host and no card draws the affordance (ADR-0033 §D13 / ADR-0029 §D17's seam). Asserted through
    `CardTextView`'s own kind switch answering nil for the span, the same way
    `Tests/CardConcealmentTests.swift` already asserts about other kinds — **`CardTextView.swift` is
    not edited**;
  - **R-16, second half** — `MarkdownBlocksView` still routes a `code(language: ViewBlock.language, …)`
    block to `RenderedViewBlock` passing **no** `onEditQuery`, so the transclusion, export and
    Viste-pane surfaces gain no builder;
  - **R-15** — the columns-omit rule asserted end to end: a fence written by the builder that never
    left its renderer's defaults carries no `columns:` line and is byte-identical to the minimal
    hand-written form; `from` and `limit` likewise absent when empty;
  - **R-13** — the three named coverage cases exist and are green by name: one atomic rewrite
    (Task 4), one undo step (Task 4), a refused commit leaving the buffer untouched (Task 4).
- **Coder**: nothing to implement if the design held. The task's real deliverable is the **grep
  evidence** in its report:
  - **R-17** — `git diff --stat` for the whole chain names **zero** files under `Sources/Core/`,
    `Sources/Connector/`, `Sources/CLI/`, `Sources/MCPServer/`. Confirm by building both connectors:
    `xcodebuild -workspace Pergamenum.xcworkspace -scheme perg -destination 'platform=macOS' build`
    and the same for `pergamenum-mcp`;
  - `MarkdownBlocksView.swift`, `TranscludedNoteView.swift`, `NoteExporter.swift`, `ViewsPane.swift`,
    `CardTextView.swift`, `RelatedLinkSheet.swift` appear in the chain's diff **zero times**;
  - `interface-check.sh` silent — no protected interface touched.
  If any of those is false, **stop and report** — the design leaked.
- **`.claude/test-cmd` exactly as it stands, whole `PergamenumTests` bundle, green.** Not the
  touched files' tests: a contract change breaks tests in files that never mention it.
- **`scripts/uitests.sh`** with no arguments, once, before merge. Kill every stale instance first
  and read the per-test seconds it prints: **60.2 s names the launch timeout, not a defect**
  (CLAUDE.md). Any new UI-test file passes `-disableCalendar YES` and `-disableUpdater YES` and
  finds controls by `accessibilityIdentifier`, never by the words on them.
- **R-14 — Stefano's hand-check, and it is the acceptance gate for this chain.** In a real vault:
  «Modifica query» on a live board and on an error card (R-01); the sheet fully seeded from a
  seven-key fence (R-02); a broken fence opened, fixed through the controls and committed (R-03);
  «Inserisci ▸ Vista…» from an empty line and from mid-paragraph (R-04); the match count updating
  as the draft settles, not per keystroke (R-11); «Fatto» disabled with its reason on a board with
  no group (R-12); **one `Cmd+Z` undoing the whole commit** (R-13); «Annulla» leaving the note
  untouched (R-14); a fence whose `where` uses `or` loading raw-in-Filtro and structured everywhere
  else (R-07).
- Update `PROJECT_BRIEF.md`: the Status section.
- **Update `CLAUDE.md`**, which every prior chain in this repo does and which is how the next
  session learns this decision exists: one line in the **Chain decision index** (`ADR-0034 — …`) and
  one **"Decisions from the …" section** carrying the decisions a reader must not re-litigate — the
  shared header affordance (§D1), the commit closure and its reload guard (§D2/§D3), the
  stub-first single write path (§D4), the round-trip-through-the-real-parser validation (§D6/§D7),
  the ordered columns rule (§D9), and the three "there is no such component" findings (C2/C3/C4).
- **HITL gate before commit.** Branch `feat/pergamenum-view-query-builder` (already checked out),
  Conventional Commits, never a direct commit to `main`, never a force-push.
- Budget: `Tests/ViewQueryOutOfScopeTests.swift`, `PROJECT_BRIEF.md`, `CLAUDE.md` (~220 lines) plus
  test-run reports; no source change expected.

---

## Requirement coverage

| Id | Tasks |
|---|---|
| R-01 | 8 |
| R-02 | 3, 5, 8 |
| R-03 | 3, 8 |
| R-04 | 2, 9 |
| R-05 | 2, 6 |
| R-06 | 1, 2, 6 |
| R-07 | 1, 5 |
| R-08 | 2, 5 |
| R-09 | 2, 5 |
| R-10 | 2, 5 |
| R-11 | 7 |
| R-12 | 5 |
| R-13 | 4, 10 |
| R-14 | 5, 10 |
| R-15 | 2, 10 |
| R-16 | 10 |
| R-17 | 10 |

Every id the SPEC declares is cited by at least one task; no id is cited that the SPEC does not
declare. R-16 and R-17 both carry `(no-test: …)` in the SPEC — the marker exempts them from a
dedicated behavioural assertion, never from a citing task, so Task 10 owns both and discharges them
by structural assertion plus grep evidence.

---

## Risks and HITL gates

- **The sheet is the largest SwiftUI surface in this feature area.** Eight sections, eight term
  kinds, five pickers, all under the 150-line-per-view rule. `ViewQueryTermRow` (Task 6) is the file
  most likely to need a second split during implementation; splitting it is expected, not a
  deviation.
- **Three "the SPEC names a component that does not exist" findings** (C2, C3, C4). Each costs a
  small new control rather than a reuse. If any of them turns out to be reusable after all, that is
  a better answer than this plan's — **report it, do not silently build the new one anyway**.
- **`Navigation.Insertion` is a contract change in a file every menu entry touches** (Task 9). Five
  compile-forced sites, all listed and all in the same task. The full suite runs after it.
- **A refused commit will read as the button not working** (ADR §D3, Consequences). The sheet must
  stay open and say why; a silent close on a write that did not happen is the failure mode this
  guard exists to prevent, and it is Task 5's «Fatto» branch that decides it.
- **Query cost on a real vault.** The count evaluates on the main actor and a `text()` term reads
  every candidate file — ADR-0009 §D7's numbers were measured on a two-note vault. Unmeasured,
  named in ADR-0034's Consequences, worth watching during the R-14 hand-check.
- **Two builders on one note in a split editor** resolve by refusal, not by merge. Correct, rare,
  and named.
- **HITL gates:** commit, push, merge to `main`, and the R-14 hand-check itself. No schema change,
  no migration, no deletion, no destructive command anywhere in this chain.
- **No new dependency.** `Tuist/Package.swift` is not touched; nothing goes through the Xcode UI.

---

EXTERNAL DEPENDENCY: tuist | binary | provisioned: true
EXTERNAL DEPENDENCY: xcodebuild | binary | provisioned: true

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -derivedDataPath "/Users/stefer/Developer/Pergamenum/.build/DerivedData" -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield

CODER-MODEL CANDIDATE: opus
