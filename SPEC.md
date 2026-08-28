# SPEC — Unificare Nota e Testo in un solo strumento del Workspace con formattazione ricca del testo

**Topic slug:** unificare-nota-e-testo-in-un-solo-strume

## Objective

Replace the Workspace's two overlapping toolbar tools, **Nota** and **Testo** — both of which
create a `CanvasNode.Kind.text` card and differ only in whether `node.color` is pre-set, a
distinction already redundant with the existing "Colore" command available on every text card —
with a single **Testo** tool. In the same feature, give `.text` canvas cards real rich-text
formatting applied to a selection inside the card: bold, italic, strikethrough, text color,
alignment (left/center/right/justify), bullet/numbered lists and headings.

Both card types just became editable (commit `8c6405c`, `fix/workspace-editable-note-text-cards`)
via a plain `TextEditor` bound to a `String` draft. That binding has no notion of a text
selection, which is why the interview settled the interaction model before anything else:
selection-based formatting requires replacing that `TextEditor` with an `NSTextView`-backed
editor, reusing the app's existing TextKit 2 note-editor infrastructure (`CompletingTextView` and
its `NoteTextView+*` extensions under `Sources/Features/Editor/`) rather than building a second,
divergent rich-text engine.

## Scope

In scope:
- Removing the `.note` case from `WorkspaceController.Tool`; `.text` (title "Testo", shortcut
  `t`) becomes the sole card-creating tool for this family. The `n` shortcut is freed and
  assigned to nothing in this feature.
- The unified tool always creates a plain (uncolored) card, exactly today's `.text`/Testo
  behavior. A colored "sticky" look is still reachable afterward via the existing "Colore"
  command — no new color picker at creation time.
- Selection-based rich text formatting inside a `.text` card's editor: bold, italic,
  strikethrough, bullet lists, numbered lists, headings (`#`/`##`/`###`) — all stored as plain
  CommonMark markdown text in the node, since JSON Canvas already stores `.text` content as
  markdown and Obsidian reads CommonMark natively. No new persisted schema needed for these.
- Whole-card (not per-selection) text color and text alignment, applied to the entire card's
  text, persisted as new `pergamenum-textColor` / `pergamenum-textAlign` scalar properties on the
  `.canvas` node — the same prefixed-custom-property pattern ADR-0020 established for
  `pergamenum-crop`. Non-standard properties are preserved but not interpreted by Obsidian
  (CLAUDE.md principle 4).
- A floating formatting mini-toolbar that appears above an active text selection inside a card
  (Notion/Pages-style), offering bold/italic/strikethrough/color/alignment, plus matching
  keyboard shortcuts (Cmd+B, Cmd+I — both currently unbound; confirmed no collision with
  `ShortcutCommand`'s `newBoard` at Cmd+Shift+B or `toggleInspector` at Cmd+Opt+I).
- Replacing `StickyTextCard`'s `TextEditor`/static-`Text` pair with one NSTextView-backed
  component used for both editing and read-only display, so rendering never diverges between the
  two states. This card-scoped component is architecturally derived from
  `CompletingTextView`/TextKit 2 — the ADR (Step 2) decides exactly how much is shared vs.
  card-specific (no outline, no embeds, no wikilink completion, no transclusion — none of that
  applies to a canvas card).
- The **To Do** tool's cards (still a `.text` node with a literal `"- [ ] "` prefix, PG-074
  unchanged) go through the same `StickyTextCard`/editor component and therefore gain the same
  rich formatting with no special-casing.
- Existing `.canvas` files are read and written exactly as before: no migration, no rewrite of
  already-created nodes. A pre-existing colored card keeps `node.color`; a pre-existing plain
  card stays plain. The unification changes only what the toolbar creates from this point on.

Out of scope (tracked separately, not reopened here):
- `PG-074` — giving To Do a real interactive/indexed checklist `CanvasNode.Kind`.
- `PG-073` — the Link card's editable title.
- Any change to `.canvas` files created before this feature ships.
- A second, non-selection-based color/alignment mode (rejected during interview in favor of
  whole-card).

## Stack

No new external dependency. Swift 6, SwiftUI + AppKit via `NSViewRepresentable` (existing
pattern, CLAUDE.md), TextKit 2 (already used by `CompletingTextView`), JSON Canvas 1.0 file
format (existing `CanvasNode`/`JSONCanvas.swift`).

## Architecture

Decisions the ADR (Step 2) must make explicitly, building on what the interview already settled:

1. **Editor component boundary.** How much of `CompletingTextView`'s TextKit 2 setup (text
   storage, layout manager, syntax highlighting for `**bold**`/`*italic*`/`# heading`/list
   markers) is extracted into something both the main note editor and canvas cards can use,
   versus a new, smaller `NSTextView` subclass for cards that duplicates only what it needs. The
   interview's direction is "reuse/adapt", not "duplicate wholesale" — the ADR draws the actual
   line.
2. **Selection formatting → markdown mutation.** How a floating toolbar's "bold" action, given an
   `NSRange` selection, mutates the underlying markdown string (wrap/unwrap `**...**`, toggle
   list/heading prefixes per line) without corrupting existing markdown already in the card, and
   how the mini-toolbar's own visibility/position is driven from `NSTextView` selection-changed
   notifications inside an `NSViewRepresentable`.
3. **`pergamenum-textColor` / `pergamenum-textAlign` schema.** Exact value encoding (e.g. a
   `ColorToken` raw value vs. a hex string; `"left"|"center"|"right"|"justify"` vs. an integer),
   where they are read/written in `CanvasNode`/`JSONCanvas.swift`, and how `StickyTextCard`'s
   renderer applies them to the whole `NSTextView` (paragraph style for alignment, foreground
   color attribute for color) independent of the per-character bold/italic/strikethrough markdown
   styling.
4. **Read-only rendering path.** How the same component renders non-editable when the card is
   not being edited (`isEditable = false` on the same `NSTextView`, vs. a still-separate static
   path) so editing and display can never visually diverge, per the interview's decision.
5. **`WorkspaceController.Tool` migration.** Removing `.note` safely — every switch over `Tool`
   (`BoardChrome.swift`'s toolbar, any other exhaustive switch) needs updating in one pass; `let
   tool: Tool = .note` call sites (`addStickyNote`, `WorkspaceView+Creation.swift`) collapse into
   the existing `.text`/`addFreeText` path.
6. **Protected-interface check.** Whether `CardCommand`'s catalogue or `VaultPayloads`' JSON
   shapes (ADR-0021 §D-noted protected interfaces) are touched by adding formatting commands —
   if so, the deliberate-edit process for `.claude/protected-interfaces` applies.

## Data model

- `WorkspaceController.Tool`: `.note` case removed. `.text` keeps title "Testo", symbol
  `"textformat"`, shortcut `"t"`. `n` becomes an unassigned shortcut.
- `CanvasNode` (`Sources/Core/Canvas/JSONCanvas.swift`): `.text(String)` case unchanged in shape;
  the markdown `String` itself now may contain `**bold**`, `*italic*`, `~~strikethrough~~`,
  `- item` / `1. item`, `# heading` markup, all plain CommonMark, no schema change.
- `CanvasNode` custom properties: two new optional, prefixed, scalar keys —
  `pergamenum-textColor` and `pergamenum-textAlign` — following the `pergamenum-crop` precedent.
  Absent on any card that has never had these set (including every card that exists today).
  Encoding decided by the ADR (Architecture §3).
- `StickyTextCard.swift`: `TextEditor` + static `Text` pair replaced by one `NSViewRepresentable`
  wrapping the shared/derived NSTextView component, in both its editing and read-only modes.
- `WorkspaceController`: `editingTextNodeID`/`editingTextDraft` remain the transient-state
  mechanism (ADR-0020 §D5 pattern), but the draft type and the commit path
  (`endTextEdit(commit:)` → `setText`) may need to also carry/read the two new card-level
  properties — exact shape left to the ADR.

## API

No connector-facing API change: `Sources/Connector/VaultAPI` reads/writes `.canvas` files through
`CanvasNode`, and a `.text` node with markdown content plus two new optional prefixed properties
is still a `.text` node — no new payload shape, no new MCP/CLI surface.

## UI flows

1. **Create a text card.** Click "Testo" (or press `t`), click the board → a plain `.text` card
   is created and immediately enters editing (existing behavior, `WorkspaceView+Creation.swift`).
2. **Apply inline formatting.** While editing, select a run of text inside the card → a floating
   mini-toolbar appears above the selection with Bold / Italic / Strikethrough / Color /
   Alignment / List / Heading controls; clicking one mutates the markdown under the selection.
   Cmd+B and Cmd+I do the same for bold/italic without touching the toolbar.
3. **Set card-wide color/alignment.** Text color and alignment controls in the same mini-toolbar
   (or the card's existing context menu / `BoardCardControls`, per the ADR's UI-surface decision)
   apply to the whole card, not just the selection — visibly different behavior from
   bold/italic/etc., which the mini-toolbar's own layout should make clear (e.g. a visual
   separator between "this selection" and "this card" groups).
4. **Leave editing.** Unchanged: Esc commits, outside click commits, focus loss commits — now
   also persisting `pergamenum-textColor`/`pergamenum-textAlign` if they were touched.
5. **View a card at rest.** The same rendering engine used while editing draws bold/italic/lists/
   headings/color/alignment, non-editable, so what you see while typing is exactly what you see
   after.
6. **To Do cards.** Same tool family, same editor, same formatting — the `"- [ ] "` line prefix
   is untouched, PG-074's future checklist model is not implemented here.

## Edge cases

- A card with no formatting applied (today's every card) renders and behaves identically to
  before — no visual regression on existing boards.
- Undo/redo of a formatting action follows the same single-commit-at-`endTextEdit` discipline as
  plain text edits (ADR-0020 §D5) — a bold toggle is not a per-keystroke document mutation.
- Deleting all text in a formatted card leaves the card's `pergamenum-textColor`/
  `pergamenum-textAlign` properties in place (they describe the card, not its content) until the
  card itself is deleted or its color/alignment is explicitly reset.
- A `.canvas` file edited by hand or by Obsidian that already carries an unrelated
  `pergamenum-*`-prefixed key must round-trip unchanged — this feature's two new keys are
  additive, never a rename or reinterpretation of an existing key.
- A markdown wrap operation (e.g. bold) on a selection that already contains partial markdown
  (an already-bold sub-range) must not produce corrupted nesting like `****text**`.
- The mini-toolbar must not appear/steal focus when a selection is empty (plain caret movement),
  matching the interview's "selection-based" framing.

## Success criteria

- [ ] R-01 — The Workspace toolbar has exactly one tool that creates a `.text` card ("Testo",
  shortcut `t`); `WorkspaceController.Tool` no longer has a `.note` case.
- [ ] R-02 — Creating a card with the unified tool always produces a plain (uncolored) card; the
  existing "Colore" command still changes its background afterward.
- [ ] R-03 — Selecting text inside an editing `.text` card and applying bold/italic/strikethrough
  wraps/unwraps the correct CommonMark markup around exactly that selection, leaving the rest of
  the card's text untouched.
- [ ] R-04 — Cmd+B and Cmd+I apply bold/italic to the current selection with no collision with
  any existing `ShortcutCommand` binding.
- [ ] R-05 — Applying a bullet list, a numbered list, or a heading level to one or more selected
  lines inserts the correct CommonMark line prefix(es).
- [ ] R-06 — Setting text color or alignment applies to the whole card's text, persisted as
  `pergamenum-textColor` / `pergamenum-textAlign` on the `.canvas` node, and survives a save/close/
  reopen of the board.
- [ ] R-07 — A `.canvas` file containing a card with no `pergamenum-textColor`/
  `pergamenum-textAlign` properties (every card that exists today) opens and renders exactly as
  before this feature.
- [ ] R-08 — The same rendering component draws a card identically whether it is currently being
  edited or shown at rest — no static/editing visual divergence.
- [ ] R-09 — A To Do card (`"- [ ] "` prefix) supports the same inline formatting as any other
  `.text` card, with no special-casing that excludes it.
- [ ] R-10 — Opening the "Labs" Obsidian vault's existing boards (or any pre-existing `.canvas`
  file) shows no corruption or unexpected `pergamenum-*` keys on cards this feature never touched.
- [ ] R-11 — `scripts/uitests.sh` passes before merge, covering at minimum: unified-tool card
  creation, one bold/italic round trip, one card-color/alignment round trip (no-test: this is a
  process gate run once at merge time, not a per-behavior assertion the suite itself states).
- [ ] R-12 — The full unit test suite (`-only-testing:PergamenumTests`) passes, including new
  tests for the `Tool` enum change, the markdown-mutation logic, and the new `CanvasNode`
  properties' encode/decode round-trip.
