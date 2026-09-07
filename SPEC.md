# SPEC — PG-099: Views/board renderer orphaned by ADR-0029 editor unification

**Topic slug:** pg-099-views-board-renderer-orphaned-by

## Objectives

Restore a live, interactive surface for `pergamenum-view` fenced blocks (ADR-0009: table,
gallery, calendar, board renderers over `RenderedViewBlock.swift`) inside the note editor.

ADR-0029 (2026-09-02/03) removed the Modifica/Lettura toggle and unified editing into one
always-editable `NoteTextView`. `RenderedViewBlock`'s only remaining call site in the whole repo
is inside `MarkdownBlocksView.swift`, itself explicitly retained as dead code for the main editor
(ADR-0029 §D14). Its only live callers today are `TranscludedNoteView` (read-only `![[nota]]`
preview) and `NoteExporter` (HTML export) — neither is the main editor. Net effect: today a
`pergamenum-view` fence renders as raw fenced text in the live app; there is no way to see or drag
a kanban card, or see a rendered table/gallery/calendar view, anywhere reachable from the main
editor.

This is a regression, not a never-built feature: PG-012 (closed 2026-08-20) shipped all four
renderers inside the old Lettura mode; ADR-0029 removed Lettura two weeks later without re-wiring
`RenderedViewBlock` into the new unified editor.

Comparison against NotePlan (researched, ADR-0009's own reference point): NotePlan's own
kanban/board view (Folder Cards) is *also* a separate, non-inline surface, not drawn inside a
note's text flow. This SPEC does not treat "render inline" as required by that comparison — it is
a design choice on its own merits, decided below.

## Scope

**In scope:** all four renderers — table, gallery, calendar, board — restored to a live surface
inside the main note editor, in one pass. Board's drag-to-write mechanism (ADR-0009 §D5: dragging
a card rewrites the note's `status-*` tag via `VaultSession.write`, journalled/undoable/vocabulary-
checked, with existing rules for "no status" and "multiple statuses" cards) is carried forward
unchanged — this SPEC does not reopen ADR-0009's write semantics, only where/how the result is
displayed and interacted with.

**Out of scope:**
- Any change to `ViewsPane.swift`'s existing cataloguing behavior (name, renderer type, filter,
  match count, "open note at block location"). It keeps working exactly as today.
- Any change to `NoteExporter`'s HTML export rendering of a view block — already works via
  `MarkdownBlocksView`, untouched by this SPEC.
- Any change to `TranscludedNoteView`'s (`![[nota]]`) read-only rendering of a view block —
  already works via `MarkdownBlocksView` today and is confirmed to keep working unchanged (see
  Edge cases). This SPEC only restores the *main editor's* live surface.
- Any change to ADR-0009's query grammar (`from`/`where`/`sort`/`render`/`columns`/`limit`) or to
  which `StoredRecord`/`IndexSnapshot` fields a view can reference.
- A dedicated visual "query editor" UI (dropdowns, form fields) for authoring/editing a view's
  query. Editing stays text-based (see Architecture, caret behavior).

## Stack

No new dependency. Swift 6, SwiftUI on macOS 26 SDK, TextKit 2 via `NSTextView`/
`NSTextAttachmentViewProvider` — same stack ADR-0029's GFM table attachment already uses. No
schema change, no index bump (`IndexCache.schemaVersion` stays 3), no new protected interface.

## Architecture

**Rendering site — inline attachment, not a separate panel.** A `pergamenum-view` fence becomes
one `NSTextAttachment` anchored to its opening-fence paragraph, hosted via
`NSTextAttachmentViewProvider` — the same mechanism ADR-0029 §D2 introduced for the GFM table
grid (`YES` by default on `NSTextAttachment`, the "subclasses create their custom view hierarchy"
hook). The delegate's enumeration hook refuses to lay out the fenced body lines underneath it,
exactly as the table attachment already does for its body rows. This reuses an established,
already-shipped pattern rather than introducing a second one (panel-based) alongside it.

**Caret behavior — reveal raw source on caret entry, reusing ADR-0018's existing mechanism.**
Unlike the GFM table (whose content *is* note prose, edited by typing into rendered cells), a
`pergamenum-view` fence's body is a short declarative query
(`from`/`where`/`sort`/`render`/`columns`/`limit`) over data that lives elsewhere in the vault —
config, not prose. When the caret enters the fence, the rendered attachment is replaced by the raw
fenced text for direct editing (same reveal-on-caret rule ADR-0018 already applies to headings,
emphasis, blockquotes, etc.); moving the caret back out re-renders the attachment from the (now
possibly changed) source. No new query-editing UI is introduced.

**Sizing — fixed height with internal scroll.** The attachment reserves a bounded height; its
board/gallery/calendar/table content scrolls internally within that height. The note's layout
below the block does not shift as the rendered content's row/card count changes. (Contrast with
ADR-0019's user-resizable image/PDF embed handle — deliberately not reused here: a view's height is
about how much of a query result to show at once, not about a fixed asset's aspect ratio, and a
persisted resize handle is unscoped for this pass.)

**Live refresh — subscribes to the existing index, matching PG-012's original behavior.** The
attachment observes `IndexSnapshot` updates the same way the old Lettura-mode renderer did. A
change elsewhere in the vault that affects the query's result set (e.g. another note's `status-*`
tag changing) is reflected in an already-open note's rendered view without requiring the note to
be reopened or refocused.

**Malformed query — fails closed to raw text.** If a fence's query cannot be parsed (bad key,
unparseable `where`-clause, etc.), no attachment is created for that block; it renders as plain
fenced text, identically to today's behavior for every fence this feature doesn't touch. No new
inline error/warning UI.

**Click/drag interaction — the attachment's rendered rows/cards claim their own clicks.** A plain
click on a table row, gallery item, or calendar entry navigates to/opens the linked note; a plain
drag on a board card performs ADR-0009's existing drag-to-write. No modifier key is required. This
matches the GFM table attachment's existing precedent: its own `NSView` claims clicks inside its
bounds, and clicking outside the attachment's rendered rows (e.g. between them, or elsewhere in the
note) behaves as ordinary text-editing caret placement.

**Transclusion and export are unaffected.** `TranscludedNoteView` and `NoteExporter` already
render a `pergamenum-view` fence correctly via `MarkdownBlocksView` today (they were never broken
by ADR-0029 — only the main editor was). This SPEC adds a second, independent live rendering path
for the main editor; it does not modify `MarkdownBlocksView`, `TranscludedNoteView`, or
`NoteExporter`.

## Data model

No change. `RenderedViewBlock` continues to read from `IndexSnapshot`/`StoredRecord` exactly as
today; the query grammar, the closed field list, and the board's write path (`status-*` tag via
`VaultSession.write`) are all unchanged from ADR-0009.

## API

No `Sources/Connector`/`Sources/Core` change. This is an `Sources/Features/Editor` +
`Sources/Features/Views` presentation-layer fix; `perg`/`pergamenum-mcp` are unaffected.

## UI flows

1. User types or already has a `pergamenum-view` fence in a note, cursor outside the fence →
   the fence renders as a live table/gallery/calendar/board attachment, fixed-height,
   internally scrollable, reflecting the current query result.
2. User clicks a row/card in the rendered attachment → the linked note opens (table/gallery/
   calendar), or (board) the drag interaction rewrites the dragged note's `status-*` tag per
   ADR-0009 §D5's existing rules.
3. User clicks into the fence's raw text (to edit `from`/`where`/`sort`/etc.) → the attachment is
   replaced by the raw fenced text; user edits normally; moving the caret out re-renders the
   attachment against the edited query.
4. Vault data changes elsewhere while the note is open → the open attachment's rendered content
   updates live, without requiring reopen/refocus.
5. A fence with an invalid/unparseable query → renders as plain fenced text, no attachment, no
   error UI.
6. `Viste` sidebar (`ViewsPane.swift`) — unchanged: lists every view in the vault and opens the
   note at that block's location, where the inline attachment above now renders live.

## Edge cases

- **Multiple `pergamenum-view` blocks in one note.** Each fence resolves to its own independent
  attachment; no shared state between them.
- **A fence inside a transcluded note (`![[nota]]`).** Keeps rendering read-only via
  `TranscludedNoteView`/`MarkdownBlocksView`, unchanged by this feature.
- **A fence inside an exported HTML note.** Keeps rendering via `NoteExporter`/
  `MarkdownBlocksView`, unchanged by this feature.
- **Board card with no status tag, or with multiple status tags.** Governed entirely by ADR-0009
  §D5's existing rules; not reopened here.
- **Empty query result (no matches).** `RenderedViewBlock`'s existing empty-state handling applies
  unchanged inside the attachment.
- **Caret briefly passing through the fence during selection/navigation (not a deliberate click
  into it).** Follows the same reveal-on-caret semantics ADR-0018 already defines for every other
  concealed construct — this feature introduces no new rule here, only a new construct governed by
  the existing one.

## Success criteria

- [ ] R-01 — A `pergamenum-view` fence with `render: table` renders as a live, interactive
  inline attachment in the main note editor (not raw fenced text), reflecting the current query
  result.
- [ ] R-02 — A `pergamenum-view` fence with `render: gallery` renders as a live, interactive
  inline attachment in the main note editor.
- [ ] R-03 — A `pergamenum-view` fence with `render: calendar` renders as a live, interactive
  inline attachment in the main note editor.
- [ ] R-04 — A `pergamenum-view` fence with `render: board` renders as a live, interactive inline
  attachment in the main note editor, and dragging a card between columns rewrites the dragged
  note's `status-*` tag per ADR-0009 §D5's existing rules (write is journalled and undoable).
- [ ] R-05 — Moving the caret into a rendered view's fence reveals its raw fenced source text for
  editing; moving the caret out re-renders the attachment against the (possibly edited) query.
- [ ] R-06 — The attachment reserves a fixed height and scrolls its rendered content internally;
  the note's layout below the block does not shift as the result set's size changes.
- [ ] R-07 — A change elsewhere in the vault that affects an open view's query result (e.g. a
  `status-*` tag edited in another note) is reflected in the still-open note's rendered attachment
  without requiring the note to be reopened or refocused.
- [ ] R-08 — A `pergamenum-view` fence that is closed but whose query does not parse renders the
  same error card `RenderedViewBlock` already shows on the transclusion, export and Viste-pane
  surfaces (the line, the reason, and the source as written), except while the caret sits inside
  the fence, where it stays plain editable text exactly as an unclosed fence does (ADR-0033 §D7
  follow-up, 2026-09-07 — reverses the original "no attachment, no error UI").
- [ ] R-09 — Clicking a row/card inside a rendered table, gallery, or calendar attachment
  navigates to/opens the linked note with a plain click (no modifier key required).
- [ ] R-10 — `TranscludedNoteView` (`![[nota]]` read-only preview) continues to render a
  `pergamenum-view` fence exactly as it does today, unmodified by this feature.
- [ ] R-11 — `NoteExporter`'s HTML export continues to render a `pergamenum-view` fence exactly
  as it does today, unmodified by this feature.
- [ ] R-12 — `ViewsPane.swift` ("Viste" sidebar: cataloguing, filter, match count, "open note at
  block location") is unmodified and continues to work exactly as today.
- [ ] R-13 — Unit test coverage exists for: attachment creation from a valid fence, fallback to
  raw text on an unparseable fence, and live refresh on an `IndexSnapshot` update. (no-test:
  n/a — this is itself the test-coverage requirement, not a documentation obligation)
- [ ] R-14 — Stefano manually hand-checks each of the four renderers (table, gallery, calendar,
  board) in a real vault, including the board's drag-to-write, before this feature is considered
  done. (no-test: TextKit2 attachment layout/interaction is this repo's documented blind spot for
  XCUITest — ADR-0019/0029 precedent and the working agreements' own firstRect-not-laid-out-yet
  trap require a manual hand-check for attachment-based editor features)
- [ ] R-15 — The full unit suite (`-only-testing:PergamenumTests`) passes green before this
  feature is committed.
