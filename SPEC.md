# SPEC — PG-019: drag-to-reorder a section in the Outline pane

## Objectives

Let the user reorder a note's sections by dragging a heading row in `OutlinePane` to a new
position, moving the heading and its entire body (nested subsections, paragraphs, embeds
included) as one unit. The move is a real, journalled text rewrite through
`VaultSession.write` — not a UI-only reordering of the outline's own display — and is a single
undoable step in the editor.

## Scope

In scope:
- Computing a section's full extent (heading line + everything down to the next heading of
  equal-or-higher level), a concept `NoteOutline` does not currently have.
- Drag-and-drop in `OutlinePane` (`Sources/Features/Editor/OutlinePane.swift`) using
  `.draggable`/`.dropDestination`, with an insertion-line indicator during hover.
- Automatic heading-level adjustment of the moved section (and, preserving relative depth, its
  nested subsections) to fit the drop's new visual nesting.
- Rewriting the buffer through the same NSTextView mechanism `EmbedAttachment`'s drag-resize
  uses (ADR-0019: `shouldChangeText`/`beginEditing`/`replaceCharacters`/`endEditing`), so the
  move is one `NSUndoManager` step, followed by an explicit `saveOpenNote()` call so the result
  is written to disk immediately through `VaultSession.write` (journalled).
- Manual verification of the drag gesture in the running app before closing the ticket.

Out of scope:
- Any change to `NoteOutline.Entry`'s public shape beyond adding section-extent computation —
  `kind`/`title`/`range`/`level` are unchanged; a `sectionRange(for:in:)`-style helper is added
  alongside, not a replacement.
- Cross-note moves (dragging a section from one note into another).
- Any change to `NoteOutline.entries(in:)`'s existing behavior (frontmatter/fenced-code-block
  skipping stays exactly as-is; a `#`-looking line inside a fenced code block was never a
  heading and remains not one).
- Reordering entries that are not headings (the `.embed` case is never a drag source on its
  own — it moves only as part of the section it is nested under).
- A history/undo mechanism beyond the editor's own `NSUndoManager` — no interaction with
  `WriteJournal`'s separate connector-facing `undo` command is added or changed.

## Stack

No new dependency. Swift 6, SwiftUI (`.draggable`/`.dropDestination`, `Transferable`), the
existing `Sources/Core/Markdown/NoteOutline.swift` pure model, `VaultSession.write`, and the
editor's existing `NSTextView`-backed text storage (same layer ADR-0019's embed resize and
ADR-0026's drag-and-drop already use).

## Architecture

- **`NoteOutline`** (`Sources/Core/Markdown/NoteOutline.swift`) gains a pure function computing
  a section's extent: given the note's text and an entry's index in `entries(in:)`'s result,
  return the `Range<String.Index>` spanning from the heading line's start to the start of the
  next entry whose `level <= self.level` (or the end of the text if none). No change to
  `Entry` itself.
- **A new pure function** computes the rewritten text for a move: given the full note text, the
  source section's extent + level, the destination insertion point (expressed as "after entry
  at index N" / "at the top", consistent with what the drop target can express) and the target
  level (parent's level + 1, per the interview decision), it:
  1. Extracts the source section's text.
  2. Rewrites the heading-line `#` counts of the extracted text so the top heading becomes the
     target level, shifting every nested heading inside it by the same delta (preserving
     relative depth).
  3. Removes the extracted range from the original text and re-inserts the rewritten text at
     the destination.
  Lives beside `NoteOutline` (e.g. `NoteOutline+Move.swift`), Foundation-only, no SwiftUI —
  matching the existing split between pure logic and AppKit/SwiftUI call sites (ADR-0027 §D1's
  "share pure logic, never AppKit classes" precedent).
- **`OutlinePane`** gains: a `Transferable` payload identifying the dragged entry (its index),
  `.draggable` on each row, `.dropDestination` between rows computing the insertion point from
  hover position, and an insertion-line indicator view. On a valid drop it calls back into the
  editor (through a new closure parameter, mirroring `onSelect`'s existing shape) with the
  computed move.
- **The editor** (wherever `CompletingTextView`/its coordinator already performs the
  `shouldChangeText`/`beginEditing`/`replaceCharacters`/`endEditing` sequence for embed resize)
  gets a new entry point that runs that same sequence with the rewritten full text from the
  move function, then calls `vault.saveOpenNote()`.

## Data model

No new persisted storage. No schema change, no index bump — the move is expressed entirely as
plain markdown text, same principle as every other structural rewrite in this app (folder
rename, board repoint).

## API

No connector-facing (`VaultAPI`/CLI/MCP) surface is added. This is purely an in-app editor
interaction.

## UI flows

1. User opens a note with headings; `OutlinePane` renders its outline as today (indented rows
   by level, fold/unfold chevrons).
2. User presses and drags a heading row.
3. While dragging over other rows, an insertion line is drawn between rows at the hover
   position, indicating: (a) the sibling position where the section will land, and (b) via the
   line's indentation, the level it will land at (parent's level + 1).
4. Dropping on the section's own current position, on a position inside its own extent
   (including a nested subsection of itself), or with no insertion line shown, does nothing.
5. On a valid drop: the buffer is rewritten via the NSTextView sequence (one undo step), then
   `saveOpenNote()` writes to disk with the journal.
6. `OutlinePane`'s displayed entries update to reflect the new text (recomputed from
   `NoteOutline.entries(in:)` on the new `note.text`, same as any other edit).
7. A section that was folded before the drag stays folded after (fold state keys off title/
   position and is recomputed the same way it already is after any other edit).

## Edge cases

- Dragging a folded section moves its hidden content too (decided).
- Dropping past the end of the note (below the last row) inserts at the end, at root level (no
  parent) unless dropped visually nested under the last section.
- A section containing further nested subsections carries them all; their heading levels shift
  by the same delta as the top-level moved heading, preserving relative nesting.
- Dropping a section onto itself, or onto any position inside its own current extent (including
  a child subsection), shows no insertion-line affordance and the drop is a no-op — same
  asymmetric treatment ADR-0026 uses for a folder-into-itself cycle (no affordance on hover,
  rather than an affordance that then errors).
- Unsaved changes already in the buffer (`hasUnsavedChanges == true`) at drag time are not
  discarded: the move is computed against the current in-memory `note.text` (not a fresh read
  from disk), so the rewritten buffer already contains both the user's prior edits and the
  move, and the subsequent `saveOpenNote()` persists both together atomically.
- A `#`-prefixed line inside a fenced code block is not a heading and is never a drag source or
  a valid drop target — unchanged, since `NoteOutline.entries(in:)` already excludes fenced
  code blocks from heading detection.
- A note with zero headings shows `OutlinePane`'s existing empty state; no drag source exists.

## Success criteria

- [ ] R-01 — `NoteOutline` exposes a pure function returning a section's full text extent (heading line through the start of the next heading of level ≤ its own, or end of text), covered by Swift Testing cases for a top-level section, a nested section, and the last section in a note
- [ ] R-02 — A pure function rewrites a note's text moving one section's extent to a new position, shifting the moved section's own heading level and every nested heading inside it by the same delta so relative nesting is preserved, covered by Swift Testing cases for moving to a shallower level, a deeper level, and the same level
- [ ] R-03 — `OutlinePane` supports dragging a heading row via `.draggable`, and shows an insertion-line indicator at valid drop positions between rows during hover (no-test: SwiftUI drag-and-drop gesture rendering has no reliable automated coverage in this repo per ADR-0026's own precedent, verified by hand instead)
- [ ] R-04 — Dropping on the dragged section's own current position, or on any position inside its own extent (including a nested subsection of itself), shows no insertion-line affordance and performs no move
- [ ] R-05 — On a valid drop, the target heading level is computed as the visual parent row's level + 1 (root level when dropped with no visual parent), covered by a Swift Testing case per the move function from R-02
- [ ] R-06 — A folded section, when dragged, moves its full hidden extent along with the heading (no-test: depends on the same manual drag verification as R-03, since fold state and drag both live in the SwiftUI view layer)
- [ ] R-07 — The move rewrites the editor's buffer through the same `shouldChangeText`/`beginEditing`/`replaceCharacters`/`endEditing` sequence ADR-0019's embed resize uses, so the move is exactly one `Cmd+Z` step, verified by hand in the running app (no-test: NSUndoManager step-grouping across a real drag gesture is not exercisable from Swift Testing)
- [ ] R-08 — Immediately after the buffer rewrite, `saveOpenNote()` is called, persisting the move to disk through `VaultSession.write` with the journal, including any unsaved edits already present in the buffer before the drag
- [ ] R-09 — `xcodebuild ... -only-testing:PergamenumTests test` passes with the new tests from R-01/R-02/R-05 included and zero regressions
- [ ] R-10 — Stefano manually verifies the drag gesture end-to-end in the running app (drag a section to a new position, confirm the file on disk and the outline both reflect the move, confirm Cmd+Z undoes it) before the ticket is closed (no-test: this is a human hand-check of a live UI gesture, not a claim any automated suite can assert)
