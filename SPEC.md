# SPEC — PG-074: interactive checkbox and task indexing for the Workspace To Do tool (+ PG-086)

**Topic slug:** pg-074-give-the-to-do-tool-an-interactiv

## Objectives

SPEC §6.4, tool 8 (To Do): "Crea una card lista task: checkbox interattive con la sintassi §7.1.
I task della card sono indicizzati come quelli delle note (appaiono in Attività, pianificabili,
collegabili); il file di origine è il `.canvas`." Today `WorkspaceController+Tools.swift:33`
(`case .todo: .createSticky("- [ ] ")`) creates an ordinary `.text` card containing the literal
string `"- [ ] "` — no checkbox glyph, no click-to-toggle, no task indexing. This chain closes
that gap in full, plus its sibling TODO.md finding PG-086 (no real checkbox glyph is drawn on a
task line anywhere in the app — only coloured characters via `.taskMarker(done:)`), included by
explicit choice because both surfaces (`MarkdownAttributedText.swift:126`,
`CardTextAttributes.swift:191`) share the same `MarkdownStyler` span and the same fix shape.

## Scope

In scope:
- A Workspace To Do card is a multi-line task **list** (SPEC's own wording: "card lista task"),
  using the full §7.1 syntax (`>data`, `!scadenza`, `@remind(...)`, `@repeat(n/N)`, `[[wikilink]]`,
  `#project-*`, state markers `[ ]`/`[x]`/`[>]`/`[-]`) — not a single-task sticky and not a reduced
  syntax subset.
- A real checkbox glyph replaces the coloured `[ ]`/`[x]` characters on a task line, in both the
  Workspace card surface and the note editor surface (PG-086).
- Click-to-toggle on the glyph flips `[ ]`↔`[x]`, appends/removes `@done(YYYY-MM-DD)` on completion,
  and writes the change back to the line's source file atomically.
- Task lines inside a Workspace To Do card's `.text` node are indexed into the same task machinery
  notes already use (`TaskItem`, `IndexCache`, the Attività views), with the card's `.canvas` file
  as `sourcePath` — satisfying "indicizzati come quelli delle note … il file di origine è il
  `.canvas`" literally.

Out of scope (unchanged, or a separate ticket):
- Any new `CanvasNode.Kind` — the To Do card stays a `.text` node (see Architecture).
- `PG-085` (list nesting depth) and `PG-084` (non-recursive inline-span parser) — unrelated
  `MarkdownStyler`/`EditorDecorationDelegate` defects, not touched by this chain.
- Rollover, reminders, project sub-tasks, wikilink-based task↔note/canvas linking (§7.2/§7.3) —
  already implemented (ADR-0021) and reused as-is, not redesigned.
- A Workspace To Do card is never itself the target of a `[[wikilink]]` task-link the way a note or
  a `.canvas` board can be (§7.1's `[[Progetto X.canvas]]` example links to a *board*, not to a
  task list embedded inside one) — no change to `WorkspaceBoardResolver` or §7.2's linking UI.

## Stack

No new dependency. Swift 6, SwiftUI, AppKit `NSTextView` (TextKit 2) — same stack ADR-0019/
ADR-0020/ADR-0026/ADR-0028 already used for card interactivity and WYSIWYG rendering.

## Architecture

### Rendering (reuses ADR-0028's mechanism, extends `EditorDecorationDelegate`)

The To Do card stays an ordinary `.text` `CanvasNode`, drawn by `StickyTextCard`'s `NSTextView` +
`EditorDecorationDelegate` (ADR-0028 §D1) — no new `CanvasNode.Kind`, preserving JSON Canvas 1.0 /
Obsidian round-trip (CLAUDE.md principle 4). A checkbox glyph is substituted character-for-character
for the `[ ]`/`[x]`/`[>]`/`[-]` state marker inside `MarkdownStyler`'s existing `.taskMarker(done:)`
span, the same way ADR-0028 substituted list bullets/ordinals: TextKit 2 forbids changing the
displayed paragraph's length in `textContentStorage(_:textParagraphWith:)`, so the substitution
must not insert or remove characters, only redraw the same span's glyph run. This one substitution
rule is shared verbatim by both surfaces this chain touches (Workspace card and note editor,
PG-086) since both already read `.taskMarker(done:)` off the same `MarkdownStyler` output — only
each surface's own attribute table (`CardTextAttributes` vs `MarkdownAttributedText`) decides how
to draw it, per ADR-0027 §D1's "share pure logic, never AppKit classes."

### Interaction (reuses ADR-0019/ADR-0020's atomic-write pattern)

A click lands on the drawn glyph's own hit-test rect (not the whole line — avoids toggling by
accident while editing surrounding text, same reasoning as the resize/crop handles). On a hit:
1. Compute the new line via `TaskParser.line(for:settingState:today:)` — already produces the
   correct marker swap **and** the `@done(YYYY-MM-DD)`/`@done` removal pair (SPEC §7.1: "Data
   completamento, apposta automaticamente"). No new line-rewriting logic; this function already
   exists and is already tested (`TaskParser+Writes.swift`).
2. Write it back through the same atomic `shouldChangeText`/`beginEditing`/`replaceCharacters`/
   `endEditing` sequence ADR-0019's embed resize and the Backspace-delete path already use — one
   undo step per toggle, regardless of the click's origin.

### Indexing (new: a board-scan source parallel to `NoteStore`, no schema bump)

Today `NoteStore.read(_:)` is the only place that calls `TaskParser.tasks(in:sourcePath:)`, over a
note's markdown text, feeding `IndexCache` (schemaVersion 3). A parallel scan is added for
Workspace boards: during the same vault rescan, every `.text` `CanvasNode` in every `.canvas` file
whose first line matches a task-list start (`^- \[.\] `, the same state-marker alphabet §7.1
defines) has its full text run through `TaskParser.tasks(in:sourcePath:)` with `sourcePath` set to
the board's own relative path (e.g. `"01 Progetti/Board.canvas"`) — literally the ".canvas" source
path SPEC §6.4 calls for. No card-level marker/flag is added to `CanvasNode` to distinguish a To Do
card from a freehand Nota/Testo card that happens to start with the same syntax: the content-based
heuristic is the entry criterion, and it is deliberately inclusive — a Nota card a user free-writes
starting with `"- [ ] "` is indexed exactly like a purpose-created To Do card, which is consistent
with §6.4's own framing of To Do as "just" a starting template over the shared `.text` mechanism,
not a distinct, gated data type.

`TaskItem.sourcePath` and `StoredTask` already store a bare `String` with no note-specific
assumption baked in (ADR-0021 §D "`StoredTask` re-parses `rawLine` through `TaskParser.parse`
rather than serializing fields, so a field TaskParser already recognizes is free in the cache with
no migration") — a `.canvas`-suffixed `sourcePath` is a new *value* in an existing column, not a
schema change. `IndexCache.schemaVersion` stays 3.

**Rewrite target resolution.** A task's `sourcePath` may now name either a note (`.md`) or a board
(`.canvas`). Every existing task-mutation call site that writes back to `sourcePath` (reschedule,
due-date, complete/reopen, from any Attività view) must resolve which store owns that path — the
`NoteStore` (existing) or `CanvasStore`'s board-node text (new) — and write through the matching
one. This is the one piece of existing task-completion machinery (§7.3: "Completare un task da
qualsiasi vista aggiorna il file markdown di origine") that must learn a second file kind; it was
written assuming every `sourcePath` was a note.

### PG-086 — real checkbox glyph (both surfaces)

Same substitution rule as above (character-for-character, no length change), applied independently
of whether a task is indexed: PG-086 is a pure rendering fix and fires on any `.taskMarker(done:)`
span in either editor, To Do card or plain note, whether or not that task line is presently
indexed. This keeps PG-086 correct even for a task line inside a Nota/Testo card that the heuristic
above does not treat as list-worthy for indexing (e.g. a single stray `- [ ]` line with no other
task-shaped content around it — still gets a real glyph, even if IndexCache does not surface it).

## Data model

No new persisted field, no schema bump. `TaskItem`/`StoredTask` (`Sources/Core/Tasks/`) are reused
unchanged; `sourcePath` now legitimately carries a `.canvas`-suffixed value alongside its existing
`.md`-suffixed ones. No new `CanvasNode` field (see Architecture — the heuristic is content-based,
not a stored marker).

## API

No new public API surface, no connector change. `perg`/`pergamenum-mcp` task-listing commands
already read through `IndexSnapshot`; a To Do card's tasks appear there automatically once the scan
source above is wired in, with no separate connector work.

## UI flows

1. **Create.** Toolbar "To Do" (SPEC §6.4 row 8, shortcut K) creates a `.text` card seeded with one
   `"- [ ] "` line, exactly as today — `WorkspaceController+Tools.swift:33` is unchanged. The user
   types further lines to build the list; each new `"- [ ] "`-prefixed line is a new task the same
   scan picks up on the next rescan.
2. **Render.** Every task line in the card shows a real checkbox glyph (open/done/rescheduled/
   cancelled per §7.1's four state markers) instead of coloured `[ ]`/`[x]` text.
3. **Toggle.** Clicking the glyph flips its state, stamps/clears `@done(...)`, one undo step.
4. **Appear in Attività.** After the next rescan, the task shows in the Oggi/Prossimi/etc. views
   exactly like a note-sourced task: schedulable (`>data`), can carry a due date (`!scadenza`), a
   reminder, wikilinks. Its origin badge/click-through opens the board (not a note editor).
5. **Complete from Attività.** Completing the task from any Attività view writes `@done(...)` back
   into the board's `.canvas` file (see Architecture's rewrite-target resolution), mirroring §7.3's
   "Completare un task da qualsiasi vista aggiorna il file markdown di origine" — here, the file of
   origin is a `.canvas`, not markdown, but the write-back principle is identical.

## Edge cases

- **Card holding a mix of task lines and free prose.** Only lines matching the state-marker syntax
  are treated as tasks; surrounding prose renders and edits normally, unaffected.
- **A Nota/Testo card that happens to start with `"- [ ] "`.** Indexed like a To Do card per the
  deliberately inclusive heuristic (Architecture) — not a bug, a chosen consequence, documented so
  a future report of "my note got indexed as a task" is triaged against this SPEC, not treated as a
  new defect.
- **Toggling a task whose board file changed on disk since the last read** (stale line index). The
  toggle write reuses `TaskParser.rewrite(_:at:expecting:with:)`, which already refuses (`nil`) when
  the line at that index no longer matches the expected original — the same staleness guard note
  tasks already rely on, applied unchanged to a board's text.
- **Deleting the card, or the line, out from under an open Attività view.** Handled by the existing
  rescan-and-refresh cycle IndexCache already uses for a deleted/edited note; no new invalidation
  path needed since the board scan participates in the same rescan.
- **A task line inside a To Do card that also carries a `[[wikilink]]`.** §7.2's existing
  task↔note/canvas linking panel and backlink indexing apply unchanged — the panel logic keys off
  `TaskItem`/wikilink text, not off `sourcePath`'s file extension.
- **Obsidian round-trip.** A `.canvas` file with a To Do card's text node opens unmodified in
  Obsidian — no new node type, no new property; Obsidian shows the raw `"- [ ] "` markdown text
  exactly as JSON Canvas 1.0 defines, since the checkbox glyph is a Pergamenum-only rendering layer
  over unmodified text (CLAUDE.md principle 1 and 4).

## Success criteria

- [ ] R-01 — A new Workspace To Do card seeds one `- [ ] ` line as today; typing further
      `- [ ] `-prefixed lines is supported with no card-size or line-count restriction beyond the
      existing text card limits.
- [ ] R-02 — Every task line (state markers `[ ]`, `[x]`, `[>]`, `[-]`) on a Workspace card renders
      a real checkbox glyph in place of the coloured bracket characters, verified by a unit test
      asserting the substitution is character-length-preserving (no paragraph-length change).
- [ ] R-03 — The same real checkbox glyph renders on task lines in the note editor (PG-086),
      sharing the substitution rule with R-02, verified by a unit test on `MarkdownAttributedText`.
- [ ] R-04 — Clicking a rendered checkbox glyph toggles `[ ] `↔`[x] `, appends `@done(YYYY-MM-DD)`
      on completion and removes it on reopen, via `TaskParser.line(for:settingState:today:)`,
      verified by unit tests over that function's existing coverage extended for the toggle case.
- [ ] R-05 — The click write-back uses one atomic undo step (`shouldChangeText`/`beginEditing`/
      `replaceCharacters`/`endEditing`), verified by manual hand-check (no XCUITest, per CLAUDE.md's
      established precedent for click/drag gesture interactions) (no-test: gesture/click hit-testing on a live NSTextView is verified by hand per this repo's established drag/resize/crop precedent, not by XCUITest).
- [ ] R-06 — A `.text` `CanvasNode` inside a `.canvas` board whose task lines match the §7.1 state-marker
      syntax is scanned during the existing vault rescan and produces `TaskItem`s with `sourcePath`
      equal to the board's relative path, verified by a unit test against a fixture board.
- [ ] R-07 — Tasks indexed from a To Do card appear in the Attività views (Oggi/Prossimi/etc.)
      alongside note-sourced tasks, verified by a unit test on `IndexSnapshot`'s aggregated task list
      including a board-sourced `TaskItem`.
- [ ] R-08 — Completing, rescheduling, or setting a due date on a board-sourced task from any
      Attività view writes the change back into the board's `.canvas` file (not a note), verified by
      a unit test that the correct store (`CanvasStore` vs `NoteStore`) is resolved and written.
- [ ] R-09 — A stale board-sourced task (its line index no longer matches the expected original
      text) refuses the write rather than corrupting an unrelated line, verified by a unit test
      reusing `TaskParser.rewrite`'s existing staleness guard.
- [ ] R-10 — A `.canvas` file containing a To Do card round-trips through Obsidian unmodified — no
      new JSON Canvas property, no new node type (no-test: verified by opening the fixture .canvas in Obsidian by hand, consistent with every prior ADR-0019/0020/0025/0026/0028 round-trip check in this repo's history).
- [ ] R-11 — `test-cmd` (`-only-testing:PergamenumTests`) builds clean and passes 100% after this
      chain's changes.
- [ ] R-12 — TODO.md's PG-074 and PG-086 entries are both closed with a note describing the actual
      implementation and cross-referencing each other (no-test: a documentation/bookkeeping obligation on TODO.md, not something a test asserts).
