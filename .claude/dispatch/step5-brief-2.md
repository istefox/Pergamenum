<!-- step5-brief: plan=/Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-02-editor-wysiwyg-unification.md tasks=4,5,6 lines=232-340 -->
# Step 5 Batch Brief -- 2026-09-02-editor-wysiwyg-unification.md -- tasks 4-6

## Task text (verbatim, plan lines 232-340)

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

## File map (from Budget: declarations, tasks 4-6)

- (none declared -- no task in this range carries a parseable Budget:)

No parseable Budget: for task(s): 4 5 6 (absent is not zero -- consult the task text above)

## Excluded tasks (not in this batch)

- Task 1 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-02-editor-wysiwyg-unification.md
- Task 2 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-02-editor-wysiwyg-unification.md
- Task 3 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-02-editor-wysiwyg-unification.md
- Task 7 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-02-editor-wysiwyg-unification.md
- Task 8 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-02-editor-wysiwyg-unification.md

Full plan: /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-02-editor-wysiwyg-unification.md

## Context documents (open only for the reason stated -- not read unconditionally)

- ADR: docs/adr/0029-editor-wysiwyg-unification.md -- table grid NSTextAttachmentViewProvider mechanism (D9-D13), pattern seed from Step 4.5 tracer bullet
- SPEC: SPEC.md -- requirement IDs for this batch's tests
- CLAUDE.md: CLAUDE.md -- editor WYSIWYG conventions and working agreements
