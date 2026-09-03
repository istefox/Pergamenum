# Plan — One editor, always editable, and a table is a grid (PG-018)

- **ADR:** `docs/architecture/ADR-0029-editor-wysiwyg-unification.md`
  (the orchestrator relocates it to `docs/adr/0029-editor-wysiwyg-unification.md`)
- **SPEC:** `/Users/stefer/Developer/Pergamenum/SPEC.md` (R-01 … R-15)
- **BRAINSTORM:** `/Users/stefer/Developer/Pergamenum/BRAINSTORM.md` (2026-09-02) — Alternative A
  chosen by the user at every dialogue step; do not re-open B or C.
- **Branch base:** `main` at `bbe09a9`. ADR-0028 is merged, so `EditorDecorationDelegate+ListRendering`,
  `+CheckboxRendering`, `ListMarkerRendering` and `CardTextView`'s own span switch all exist.
- **Style:** TDD. Red precondition first on every task, per this repo's last six chains.

---

## Before anything: what the SPEC says that the source does not

Verified against the working tree at `bbe09a9`. Do not design or code against the left column.

| # | SPEC says | Source says | Where |
|---|---|---|---|
| C1 | The toggle lives in two places: `NoteTabBar.swift:70`, `VaultBrowser.swift:132` | **Six**, plus a keyboard shortcut and a per-tab stored property. The Vista menu (`MenuCommands.swift:44-46`), `CommandActions.swift:229-230`, `CommandActions+CanRun.swift:40` and `:96`, `EditorColumnView.swift:66-70`, `VaultController+Tabs.swift:25-27`, `NoteTab.swift:19`, and `ShortcutCommand.readingMode` with a `Cmd+Shift+M` default (`ShortcutCommand.swift:70`, `:135`, `:185`, `:275`) | grep `isReadingMode`, grep `readingMode` |
| C2 | R-12: keep `MarkdownReadingView` **and** `MarkdownBlocksView`, both "unreferenced by any toggle" | `MarkdownBlocksView` is **live and load-bearing** — `TranscludedNoteView.swift:104` draws every `![[nota]]` rendition with it, `:192` uses its `noteURL(_:)`. Only `MarkdownReadingView` loses both call sites. R-12's comment belongs on the wrapper alone (ADR §D14) | `TranscludedNoteView.swift:104`, `:192` |
| C3 | R-12: the retained renderer is reserved "for a future export/print feature" | Export **already exists** and does not use it: `NoteExporter` writes HTML and PDF through `NoteExport.html(from:title:)` | `NoteExporter.swift:43-47` |
| C4 | R-06: a new table is created "only via a slash-menu/Inserisci command, inserting an empty N×M grid" | The command **already ships**: `EditorCommand.table` (`:78-81`) writes the skeleton at `:182-187`, and the Inserisci menu writes the same constant. Nothing new is needed for R-06 but the grid rendering it (ADR §D11) | `EditorCommand.swift:78-81`, `:182-187` |
| C5 | R-07: pasting a table "matching the existing paste-URL→link pattern" | Needs **no paste-path change at all**. `paste(_:)` already falls through to `super` for text that is neither URL nor image; the pipes land as characters and the next styling pass draws the grid. `CompletingTextView+Pasteboard.swift` is a **protected interface** and stays untouched (ADR §D12) | `CompletingTextView+Pasteboard.swift:74-84`; `.claude/protected-interfaces` line 3 |
| C6 | Blockquote nesting "unbounded" | `MarkdownStyler` has **no blockquote span of any kind**, and `MarkdownBlockParser`'s quote accumulator strips exactly one `>` — so the retained renderer will draw one bar where the editor draws three. Named as debt in the ADR's Consequences; **not fixed here** | `MarkdownBlocks.swift:239` |
| C7 | Out of scope: "Workspace `.text` cards — nothing to unify there" | The card **shares `EditorDecorationDelegate` outright** (ADR-0028 §D1). What keeps it out of scope is its own span switch, which must be left alone (ADR §D17) | `CardTextView.swift:168`, `:285-312` |
| — | §8: a fence's pipes are never a table | Free: `MarkdownStyler.spans(in:)` computes `fences` first and the table pass takes them the way `wikilinkSpans(in:from:outside:)` already does | `MarkdownStyler.swift:92`, `:106` |
| — | §8: a malformed table stays plain text | Free: `alignments(in:)` returns nil, and `table(header:consuming:)` "consumes nothing unless it returns a table" | `MarkdownBlocks.swift:126-137` |

**Four constraints the SPEC could not know** (ADR §Context):

1. **A displayed paragraph may not change length** (`NSTextContentManager.h:120`). Every marker is
   *substituted*, never inserted or removed.
2. **A `\n` at 0.01pt still breaks the line**, measured in this project — which is why a table's body
   rows must be *un-enumerated*, not collapsed (`EditorDecorationDelegate.swift:17-18`, ADR §D4).
3. **`EditorDecorationDelegate` cannot be `@MainActor`** and owns no view. The grid is created and
   owned by the Coordinator and handed over as a finished value, the crossing `renditions` and
   `embedRenditions` already make (`EditorDecorationDelegate.swift:25-26`, `:76`, `:83`).
4. **`NSTextAttachmentViewProvider` is untried in this repo.** ADR §D16 probe 2 is a real gate on
   Tasks 4–5, not a formality.

---

## Contract changes and their already-grepped call sites

Every row is a stale-assertion site found by grep **before** this plan was written. The coder does
not go looking for these; they are listed, and they are updated in the same task that changes the
contract. **Run the full unit suite after each task, not just the touched file's tests** — a
contract change breaks tests in files that never mention it.

| Contract | Change | Call sites that break |
|---|---|---|
| `MarkdownStyler.Span` | add `.blockquoteMarker(level:)`, `.strikethroughMarker`, `.horizontalRule`, `.tableRun` | **Compile errors (no `default`):** `MarkdownStyler.suppressesSpellCheck(_:)` (`:120-132`), `MarkdownAttributedText.colorToken(for:)` (`:106`), `CardTextAttributes.colorToken(for:)` (`:181`). **Safe, have a `default`:** `MarkdownAttributedText.attributes(for:)` (`:44`, default at `:90`), `CardTextAttributes.attributes(for:)` (`:92`, default at `:138`). **Compiles but is wrong until updated:** `NoteTextView+Coordinator.swift:280-287`'s kind switch. **Left alone on purpose (ADR §D17):** `CardTextView.swift:289`'s kind switch. **Tests:** the only two full-array assertions are `Tests/MarkdownStylerTests.swift:54` (`# Titolo`) and `:100` (`*corsivo*`) — neither text contains a new construct, so both stay green; `:235`'s `emphasisMarkers("~~**testo**~~") == ["**","**"]` filters on `.emphasisMarker` and is unaffected by a new `.strikethroughMarker`. |
| `HiddenMarker.Kind` | add `.blockquote`, `.strikethrough`, `.link`, `.rule`, `.table` | **Compile error (no `default`):** `EditorDecorationDelegate.stillSpells(_:_:at:)` (`:407-429`). **Additive, no break:** `Tests/EmbedDrawingTests.swift:42`, `:309`; `Tests/MarkupHidingTests.swift:101`, `:162`; `Tests/CardConcealmentTests.swift:114`, `:118`, `:123-124`, `:143`, `:251` all name a kind explicitly when constructing a `HiddenMarker`. |
| `EditorDecorationDelegate` | add `apply(tableRows:)` (a **fifth** input, never merged into `apply(hiddenLines:foldedHeadings:)` — ADR §D5) | No existing caller breaks; `textContentManager(_:shouldEnumerate:options:)` (`:167-174`) changes to consult the union. `Tests/MarkupHidingTests.swift` and `Tests/EmbedDrawingTests.swift` build the delegate directly and pass no rows — the new set defaults empty. |
| `MarkdownBlockParser` | table grammar moves out to `GFMTable` (Core, Foundation only) and is called from here | **Sources:** `MarkdownBlocks.swift:128-205` (`table`, `alignments`, `cells`, `fit` — all `private`, so no external caller). **Tests:** grep `Tests/MarkdownBlockTests.swift` (or whatever asserts `.table(...)`) — the assertions are on `MarkdownBlock.Table` values, which **do not change shape**, so they must stay green *unmodified*. If one needs editing, the extraction changed behaviour and is wrong. |
| `ShortcutCommand` | **remove** `.readingMode` | **Compile errors:** `ShortcutCommand.swift:70`, `:135`, `:185`, `:275`; `CommandActions.swift:229-230`; `CommandActions+CanRun.swift:40`; `MenuCommands.swift:44-46`; `Tests/CommandActionTests.swift:48`. **Compiles and stays true:** `Tests/EditorCommandTests.swift:152` (`appCommands.count == allCases.count - 2` — still two filtered). **User data:** a rebound `Cmd+Shift+M` becomes an orphan key, already tolerated by `ShortcutStore.decode` (`:137`). |
| `NoteTab` / `VaultController` | **remove** `isReadingMode` | **Compile errors:** `NoteTab.swift:19`; `VaultController+Tabs.swift:25-27`; `NoteTabBar.swift:69-80`; `VaultBrowser.swift:132-137`; `EditorColumnView.swift:66-70`; `CommandActions+CanRun.swift:96`. **Tests that must be re-pointed, never deleted:** `Tests/EditorColumnTests.swift:125-140` and `Tests/NoteTabTests.swift:88-108`, `:112-128`, `:170-178` — their subject is **per-tab/per-column state isolation**, and `isReadingMode` is only the carrier. Re-point each assertion onto `currentOutlineEntry`/`foldedEntries`, which are already asserted beside it in the same tests. Deleting them would delete the isolation guarantee. |
| `EditorColumn+Text.swift` | **remove** `reading(_:)` (`:176-188`) | Its only caller is `EditorColumnView.swift:66-70`, removed in the same task. `MarkdownReadingView` itself stays (R-12). |
| `DiaryController` | **remove** `Layout` and `layout` | **Compile errors:** `DiaryController.swift:34`, `:61`; `DiaryToolbar.swift:47-55`; `DiaryView.swift:82-95`, `:116-127`. **UI tests:** grep `diary-layout` and `diary-preview` in `UITests/` before Task 7 — `DiaryView.swift:126` sets `diary-preview`, so any test using it must be re-pointed at `diary-editor`. |

**UI tests that click the toggle** (all four rewritten in Task 6, none deleted):
`UITests/DesignAndReadingUITests.swift:117` (renders + source), `:156` (a table rather than its
pipes — **this one becomes the editor's own table-grid test**), `:174` (keyboard scrolling in a view
that no longer exists on that path), and `UITests/NoteImageUITests.swift:55` (embed drawn in
Lettura). The shared helper `openNoteInReadingMode()` (`:221-227`) goes with them.

**Protected interfaces — none touched, checked one by one (ADR §D12):**
`IndexCache.schemaVersion` (rendering-layer feature, no index field), `VaultAPI.LintFinding` (no
connector change of any kind), `CompletingTextView+Pasteboard.swift` (R-07 needs no paste change;
the grid's mouse handling is inside the attachment's own view, not on the text view).
`interface-check.sh` must stay silent for the whole chain.

---

## Conventions binding on every task

- **The tester owns the interface, the coder owns the body.** Swift is compiled: a batch that leaves
  the target unable to build produces no red tests at all, only a build error. Every new type's
  *declaration* (enum cases, stored properties, method signatures returning a stub) is written in the
  **tester's** task together with the tests that call them. The coder fills in bodies.
- **`tuist generate --no-open` after every task that adds a file under `Sources/`.**
- **Swift Testing (`@Test`/`#expect`) for all new tests.** Never XCTest, except inside `UITests/`,
  which is an XCTest bundle and stays one.
- **Every new test file's header comment cites both** `ADR-0029` and this plan's basename
  (`2026-09-02-editor-wysiwyg-unification`).
- **One principal type per file** (`~/.claude/rules/swift.md`). `EditorDecorationDelegate` will cross
  `type_body_length` again: split into `EditorDecorationDelegate+TableRendering.swift` beside the
  existing `+ListRendering` / `+CheckboxRendering`.
- **`Sources/Core/**` is a `sharedSources` glob (`Project.swift:73`)**: a new file there compiles into
  `perg` and `pergamenum-mcp`. **Foundation only** — an `import AppKit`/`import SwiftUI` there breaks
  both connector builds (ADR-0001 §D1 enforcing itself).
- **`CardTextView.swift` is not edited** (ADR §D17). The one exception the compiler forces is
  `CardTextAttributes.colorToken(for:)` learning the new spans — a colour, never a kind mapping. If a
  task looks like it needs to map a kind there, **stop and report**.
- **`CompletingTextView.swift` and every `CompletingTextView+*.swift` stay untouched.** If a task
  looks like it needs one, stop and report.
- **The unit test command is `.claude/test-cmd` exactly as it stands** — `-only-testing:PergamenumTests`.
  Do not widen it; the UI suite in there terminates the app the person at the keyboard is using
  (CLAUDE.md).
- **`scripts/uitests.sh` runs once, in Task 8, before merge** — never per task.
- **No new harness script.** This repo has none of that kind; `scripts/` holds
  release / uitests / mcp-smoke / install-cli and stays as it is. Coverage for this chain is the
  existing `.claude/test-cmd` plus `scripts/uitests.sh`, and the per-task test files named below.
  Any throwaway helper for a hand-check must be Bash 3.2-clean (no `mapfile`, no associative arrays,
  no `${x^^}`).
- **`weakening-scan.sh` reports every Swift Testing test as `zero-assertion-test`** because it treats
  `#expect` as a comment. Expected, systematically wrong for this stack, advisory (CLAUDE.md).
- **The secret scanner's `assigned-secret` heuristic fires on design-token lines.** Expected; read
  each hit before dismissing it.
- **No hardcoded colour in any view.** The grid's borders, its header weight and the rule's line all
  come from theme tokens pushed in the way `decorations.badgeColor` and `decorations.handleColor`
  already are (`NoteTextView+Coordinator.swift:164-165`, `:307`).

---

## Phase 1 — the delimiters (lowest risk, no new mechanism)

### Task 1 — `MarkdownStyler` learns four constructs, and the exhaustive tables learn the spans (R-03)

- Budget: `Sources/Features/Editor/MarkdownStyler.swift`,
  `Sources/Features/Editor/MarkdownAttributedText.swift`,
  `Sources/Features/Workspace/CardTextAttributes.swift`, `Tests/MarkdownStylerTests.swift`
  (~220 lines)

**Tester writes the declarations and the tests together.** In `MarkdownStyler.Span`:
`case blockquoteMarker(level: Int)`, `case strikethroughMarker`, `case horizontalRule`,
`case tableRun` (the last is declared here and only *used* from Task 3 — declaring it now keeps the
exhaustive tables from being edited twice).

**Red first**, in `Tests/MarkdownStylerTests.swift`, using the file's existing `spans(_:)` and
`styled(_:_:)` helpers:

- `> citazione` yields one `.blockquoteMarker(level: 1)` whose styled text is `"> "`; `>> due` yields
  level 2 with `">> "`; `>>>> quattro` yields level 4 — **no cap** (R-03, unbounded);
- `>>>senza spazio` yields a marker too (GFM allows the space to be omitted), with the styled text
  being the `>`s alone;
- `---`, `- - -`, `***`, `___` each yield exactly one `.horizontalRule` covering the whole line;
  `--` yields none; a `---` **on the first line of a note with frontmatter** yields none, because
  `spans(in:)` starts at `bodyStart` (regression guard: the frontmatter delimiter must never become
  a rule);
- `~~testo~~` yields two `.strikethroughMarker`s of `"~~"` each, and still yields `.strikethrough`;
  `~~~~` yields no markers (the `emphasisMarkers` guard's twin: hiding them would collapse the run);
- `[testo](https://x.it)` yields `.linkSyntax` over `[` and over `](https://x.it)`, leaving `testo`
  unspanned — **reusing the existing `.linkSyntax` case**, not a new one (ADR §D1);
- every one of the above written **inside a fence** yields none of these spans (R-09's sibling).

Then update the three exhaustive tables the compiler names: `suppressesSpellCheck` (all four are
syntax → `true`), `MarkdownAttributedText.colorToken(for:)` and `CardTextAttributes.colorToken(for:)`.
Assert in `Tests/MarkdownStylerTests.swift` that `suppressesSpellCheck` answers `true` for each new
case.

**Coder** fills the recognisers. The rule grammar is `MarkdownBlockParser.isRule`'s, reused — if it
has to be made non-private to reuse it, do that rather than restating it.

### Task 2 — the four constructs are concealed, and a concealed link says where it goes (R-03, R-04)

- Budget: `Sources/Features/Editor/EditorDecorationDelegate.swift`,
  `Sources/Features/Editor/EditorDecorationDelegate+QuoteRendering.swift` (new),
  `Sources/Features/Editor/HorizontalRuleFragment.swift` (new),
  `Sources/Features/Editor/NoteTextView+Coordinator.swift`, `Tests/MarkupHidingTests.swift`,
  `Tests/QuoteRenderingTests.swift` (new) (~340 lines)

**Tester** declares `HiddenMarker.Kind` cases `.blockquote`, `.strikethrough`, `.link`, `.rule`
(`.table` is Task 4's), the `quoteParagraph(at:storage:)` signature and `HorizontalRuleFragment`'s
stored properties, and writes the red tests against a delegate driven the way
`Tests/MarkupHidingTests.swift` already drives one:

- `>> due` displays `"▏▏ due"` — one bar per level, **character for character**, the paragraph's
  length unmoved (assert `displayed.length == stored.length`, the R-05-of-ADR-0028 shape);
- a blockquote paragraph containing `**grassetto**` renders both its bars **and** its collapsed `**`
  — the `survivors(among:of:in:)` reuse the list branch needed (`+ListRendering.swift:60`);
- the caret's own paragraph reveals every one of the four (ADR-0018 §D2), asserted through
  `apply(revealedParagraphs:)` exactly as the existing heading tests do;
- a `.rule` paragraph's characters are collapsed to `collapsedFont` and
  `textLayoutFragmentFor:in:` returns a `HorizontalRuleFragment` for it;
- a stale marker — the characters no longer spelling what the last styling pass recorded — collapses
  **nothing**, per marker, not per paragraph (`stillSpells` family, one new arm each);
- a concealed `[[Nota]]` carries `.toolTip` with the resolved title, and a `[testo](url)` carries the
  URL (R-04).

**Coder** fills `stillSpellsABlockquoteMarker`, `…AStrikethroughMarker`, `…ALinkDelimiter`,
`…ARule`, the quote branch, the fragment's `draw(at:in:)`, and the `.toolTip` attribute. In
`NoteTextView+Coordinator.applyStyling`, map the four new spans to their kinds at `:280-287`.

**Hand check before Task 3 (probe 1, ADR §D16):** open a note with all four constructs, hover a
concealed wikilink. If no tooltip appears under TextKit 2, **stop and report** — D3's fallback drops
R-04 rather than adding a tracking-area layer, and that is a decision for the user.

---

## Phase 2 — the table grid (the new mechanism)

> **Recommended gate before Task 4.** ADR §D16 probe 2 — Tab/Shift-Tab between two `NSTextField`s in
> an `NSTextAttachmentViewProvider` view inside a real `CompletingTextView` — is the brainstorm's
> named risk and is untried territory for this codebase. A narrow tracer-bullet probe scoped to
> exactly that question is worth a day here, because a negative result forces the ADR's rejected
> Alternative B or C and that is a different ADR, not a mid-implementation pivot. **Whether to spend
> the probe is the orchestrator's and the user's call at Step 4.5, not this plan's.** Task 3 is
> independent of the answer and can proceed either way.

### Task 3 — one GFM grammar, extracted, with ranges (R-05, R-09, R-10)

- Budget: `Sources/Core/Markdown/GFMTable.swift` (new), `Sources/Core/Markdown/MarkdownBlocks.swift`,
  `Sources/Features/Editor/MarkdownStyler.swift`, `Tests/GFMTableTests.swift` (new) (~300 lines)

**Tester** declares `GFMTable` — a `Sendable` value with `header: [String]`, `alignments`, `rows`,
the source `Range<String.Index>` of the whole table, the range of each **line**, and
`static func runs(in text: String, from: String.Index, outside: [CodeFence.Region]) -> [GFMTable]`
plus `static func parse(_ lines: ArraySlice<String>) -> GFMTable?` and
`func serialised() -> String` — and writes the red tests:

- a two-column table with a header, a delimiter row and two body rows parses, with the source range
  covering exactly those four lines and not the blank line after (R-05);
- the three delimiter forms give `.leading` / `.center` / `.trailing`, matching what
  `MarkdownBlockParser.alignments(in:)` already returns;
- a pipe-containing paragraph with **no** delimiter row parses as nothing (R-10);
- a delimiter row whose column count disagrees with the header parses as nothing (R-10);
- a short row is padded and a long row truncated, GFM's rule, unchanged from `fit(_:to:)`;
- `\|` inside a cell survives the round trip, and a Windows path keeps its backslashes
  (`cells(in:)`'s existing escape rule — assert it, it is easy to lose in an extraction);
- **every one of the above inside a fence yields nothing** (R-09);
- `serialised()` round-trips: `parse(serialised().lines) == self` for each fixture.

Then rewire `MarkdownBlockParser.table(header:consuming:)` to call `GFMTable`, and **do not touch
its tests** — `MarkdownBlock.Table`'s shape does not change, so the existing block-parser assertions
must stay green unmodified. If one needs editing, the extraction changed behaviour and is wrong.

Finally, emit `.tableRun` from `MarkdownStyler.spans(in:)` through a `tableSpans(in:from:outside:)`
pass placed beside `wikilinkSpans(in:from:outside:)` and taking the same `fences` argument.

### Task 4 — the grid is drawn, its rows leave the layout, and the caret cannot enter them (R-05)

- Budget: `Sources/Features/Editor/TableAttachment.swift` (new),
  `Sources/Features/Editor/TableGridView.swift` (new),
  `Sources/Features/Editor/TableGridStore.swift` (new),
  `Sources/Features/Editor/EditorDecorationDelegate+TableRendering.swift` (new),
  `Sources/Features/Editor/EditorDecorationDelegate.swift`,
  `Sources/Features/Editor/NoteTextView+Coordinator.swift`,
  `Tests/TableRenderingTests.swift` (new) (~450 lines)

**Tester** declares `TableAttachment: NSTextAttachment` (overriding
`viewProviderForParentView:location:textContainer:`), `TableGridView: NSView`, `TableGridStore`
(`@MainActor`, `view(for:in:) -> TableGridView` keyed by table identity),
`EditorDecorationDelegate.apply(tableRows:)` and `tableParagraph(at:storage:)`, then writes red
tests driving the delegate the way `Tests/EmbedDrawingTests.swift` already drives the embed branch:

- with a `.table` marker and a row set registered, the header paragraph's displayed copy has
  `\u{FFFC}` at the marker's first character, a `TableAttachment` on it, and the rest collapsed —
  **and its length equals the stored paragraph's**;
- `textContentManager(_:shouldEnumerate:)` answers `false` for every body-row offset and `true` for
  the header and for the line after the table;
- **the union rule (ADR §D5):** with a fold registered *and* a table registered, both sets are
  honoured; `apply(hiddenLines:foldedHeadings:)` with an empty set does **not** clear the table rows,
  and vice versa. This is the assertion that stops the fifth input being quietly merged into the
  second;
- with `hidesMarkup` false, nothing is hidden and no attachment is made — the pipes are text (§D9);
- a stale table — the characters no longer spelling one — draws nothing and hides nothing;
- `TableGridStore` returns **the same view instance** for two consecutive requests with the same
  table identity, and a different one after the identity changes. This is the assertion that keeps
  first responder alive across a styling pass (ADR §D6).

**Coder** fills the branches, wires `TableGridStore` onto the Coordinator beside `embeds`
(`NoteTextView+Coordinator.swift:77`), sets `tracksTextAttachmentViewBounds = true`, adds the table
pass to `applyStyling`/`updateNSView` with its **own** change guard (`applyFolding`'s early return
does not cover it), and adds `rescueCaret`'s table twin: a caret in a row that has just become
hidden goes to the table's header offset.

**Hand check before Task 5 (probe 3, ADR §D16):** a three-row table's line fragment is as tall as
the grid and the paragraph below it starts underneath.

### Task 5 — a cell commits once, structurally, in one undo step (R-05, R-06, R-07, R-08)

- Budget: `Sources/Features/Editor/TableGridView.swift`,
  `Sources/Features/Editor/TableEdit.swift` (new),
  `Sources/Features/Editor/NoteTextView+Tables.swift` (new),
  `Sources/Features/Editor/NoteTextView.swift` (one closure in `wire(_:to:)`),
  `Tests/TableEditTests.swift` (new) (~380 lines)

**Tester** declares `TableEdit` — a pure value describing one commit (`.cell(row:column:text:)`,
`.addRow(after:)`, `.removeRow(_:)`, `.addColumn(after:)`, `.removeColumn(_:)`) and
`func applied(to: GFMTable) -> GFMTable` — plus
`Coordinator.commitTable(_:at:in:) -> Bool`, and writes red tests:

- each of the five edits applied to a fixture yields the expected `GFMTable`, and `serialised()` of
  the result is the expected markdown — **pure, no text view needed**, which is where the bulk of
  the coverage lives;
- removing the last column, or the last body row, is refused rather than producing a table with no
  columns (a malformed table is what R-10 says must not exist);
- driven through a real `NSTextView` the way `Tests/EmbedCaretTests` drives `selectEmbed(at:in:)`:
  `commitTable` calls `replaceAtomically` exactly once, whatever the edit (R-08), and the whole
  table's source range is what it replaces;
- **the reload guard (ADR §D8):** a commit whose recorded range no longer spells the same-shaped
  table is **dropped**, the buffer unchanged and the function answering `false`. Assert it two ways —
  the text replaced wholesale under the grid, and the table moved by an edit above it;
- pasting `EditorCommand.table`'s own skeleton into a note produces a table the recogniser accepts
  (R-06 and R-07 in one assertion — the skeleton and a pasted table are the same input).

**Coder** fills the commit path, the grid's Tab/Shift-Tab/Enter/blur handling, its add/remove row and
column affordances (theme tokens only), and the one closure on `wire(_:to:)`.

**Hand check before Task 6 (probe 2 and probe 4, ADR §D16):** click into a cell, Tab through the
grid, Shift-Tab back, Escape out; then type in two cells and press Cmd+Z twice and confirm each
press reverses exactly one commit. Write the result into `PROJECT_BRIEF.md`.

---

## Phase 3 — the toggle, the Diario pane, the documents

### Task 6 — `isReadingMode` and everything that reaches it are removed (R-01, R-02, R-12)

- Budget: `Sources/Vault/NoteTab.swift`, `Sources/Vault/VaultController+Tabs.swift`,
  `Sources/Features/Editor/NoteTabBar.swift`, `Sources/Features/Editor/VaultBrowser.swift`,
  `Sources/Features/Editor/EditorColumnView.swift`, `Sources/Features/Editor/EditorColumn+Text.swift`,
  `Sources/App/MenuCommands.swift`, `Sources/App/CommandActions.swift`,
  `Sources/App/CommandActions+CanRun.swift`, `Sources/Core/Shortcuts/ShortcutCommand.swift`,
  `Tests/EditorColumnTests.swift`, `Tests/NoteTabTests.swift`, `Tests/CommandActionTests.swift`,
  `UITests/DesignAndReadingUITests.swift`, `UITests/NoteImageUITests.swift` (~320 lines)

Work the contract table above, top to bottom. Three things that are not deletions:

- **`Tests/EditorColumnTests.swift:125-140` and `Tests/NoteTabTests.swift:88-108`, `:112-128`,
  `:170-178` are re-pointed, never deleted.** Their subject is per-tab and per-column state
  isolation; `isReadingMode` was only the carrier. Move each assertion onto `currentOutlineEntry` or
  `foldedEntries`, both already asserted beside it in the same test bodies. Rename the tests that
  say "ReadingMode" in their name.
- **The four UI tests are rewritten, not deleted** (list above). `DesignAndReadingUITests:156`
  («reading mode renders a table rather than its pipes») becomes the editor's own table-grid test and
  is the most valuable one in this chain — re-point it at the editor and assert on the grid's
  `accessibilityIdentifier`, never on the words in a cell (working agreements: prose grows).
  `:174`'s keyboard-scrolling assertion has no surface left on that path; move it to the editor or
  delete it **with a written reason in the commit message**, never silently.
- **`MarkdownReadingView` stays** and gains R-12's comment: retained, unreferenced, reserved for a
  future print/preview surface, with the honest note that `NoteExporter` already exports through
  `NoteExport.html` and does not use it. **`MarkdownBlocksView` gets no such comment** — it is live
  (`TranscludedNoteView.swift:104`).

Also correct the stale comment at `NoteTabBar.swift:6-8` («What the header carried and a tab cannot -
the Modifica/Lettura choice and the save state»), which now describes a control that does not exist.

### Task 7 — the Diario pane hosts the same editor and nothing beside it (R-11)

- Budget: `Sources/Features/Diary/DiaryView.swift`, `Sources/Features/Diary/DiaryController.swift`,
  `Sources/Features/Diary/DiaryToolbar.swift`, `Tests/DiaryControllerTests.swift`,
  `UITests/DiaryUITests.swift` (~180 lines)

Remove `DiaryController.Layout` and `layout`, the toolbar picker (`:47-55`), `DiaryView.preview` and
the `body(for:)` switch; `writingColumn` becomes header, divider, editor. Grep `diary-layout` and
`diary-preview` in `UITests/` **first** and re-point every hit at `diary-editor`. Rewrite
`DiaryView.swift:7-13`, which states ADR-0005 §D2's superseded premise verbatim.

Two things stay exactly as they are: `DiaryTimeline` and everything in ADR-0005 §D3–§D8, and the
600 ms debounce plus the four flush triggers (§D7) — `growToFitTheText`'s own comment records that
the diary is where a re-entrant SwiftUI update once cost everything typed into it
(`NoteTextView+Coordinator.swift:370-376`). Do not touch that path while removing a sibling view.

### Task 8 — the documents, and the UI suite (R-12, R-13, R-14, R-15)

- Budget: `docs/20260811_Pergamenum_SpecApp.md`, `PROJECT_BRIEF.md`, `CLAUDE.md`,
  `docs/adr/0029-editor-wysiwyg-unification.md` (~120 lines)

- **`docs/20260811_Pergamenum_SpecApp.md` §14**: retire the *«Live preview completa | Esclusa v1 |
  Voce di costo massima; source mode con stile è sufficiente»* row, citing ADR-0029. **§5**: remove
  the two-mode description and its closing note flagging this chain as in progress (R-15). *This is
  the only task that edits that file; nothing earlier may.*
- Confirm the ADR states its supersessions explicitly (R-14) — it does, in its header; this task is
  the check, not a rewrite.
- Add ADR-0029 to `CLAUDE.md`'s **Chain decision index** and a "Decisions from the editor WYSIWYG
  unification chain" section, matching the eight already there.
- Update `PROJECT_BRIEF.md` with the four probe results from D16.
- **Run `scripts/uitests.sh` with no arguments** (R-13). An argument *replaces* the selection rather
  than adding to it. Kill stale instances first and read the per-test seconds before believing a red
  run — 60.2 s names the launch timeout, not a defect (CLAUDE.md).

---

## TEST-CMD CANDIDATE

```
TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -derivedDataPath "/Users/stefer/Developer/Pergamenum/.build/DerivedData" -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield
```

The UI suite is deliberately **not** in this command (CLAUDE.md: it runs at the end of every turn
through the `Stop` hook, and the UI tests terminate the app the person at the keyboard is using).
`scripts/uitests.sh` runs once, in Task 8.

No external dependency: this feature calls no third-party API, no cloud console and no consent flow.
Nothing to declare.
