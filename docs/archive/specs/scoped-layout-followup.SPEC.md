Status: Approved (2026-10-11)

# SPEC — What is left of the per-keystroke cost after the per-paragraph restyle

## Destination

An approved SPEC for `/workplan` covering four pieces of PG-401 (#967) that follow PR #971 (ADR-0091):
the layout of a keystroke proportional to what the keystroke changed, the list renumbering
proportional to the runs it touches, the structural edits measured, and the delegate, undo, redo
and IME paths verified on the path the app really takes. Reaching the end of the work means the
50 KB and 200 KB bench rows are under 20 ms CPU per key, the 1 MB rows are measured with the part
that stays at TextKit's floor named, and the person has run the Release hand checks.

## Objectives

After #971 a keystroke no longer restyles the note, but four rows of the six Debug bench rows are
still over 20 ms (200 KB: 23 and 38 ms; 1 MB: 122 and 523 ms). The profile of the 1 MB fences row
puts the largest app-owned cost in laying out the whole note after each key, followed by the
whole-text list renumbering. A parallel line of work, not shipped by the person's decision, measured
what removing both buys (200 KB: 12 and 14 ms; 1 MB: about 60 ms) and found three things #971 does
not yet cover: the delegate that hears the storage is sometimes not the coordinator, undo, redo and
composed text may not reach the restyle on the real path, and the structural edits that fall back to
a wide restyle are not measured.

The aim is to take those pieces onto #971 without taking the parallel design, and to say plainly
what stays at TextKit's floor.

## Scope and non-goals

In scope:
- (a) Laying out only what TextKit lost since the last call, instead of the whole note, in the
  editor surfaces that share the note coordinator (note, Oggi, Diario).
- (b) Renumbering ordered lists from a window around the edit instead of from the top of the note,
  in the same surfaces.
- (c) Bench rows for the structural edits that fall back to a wide restyle, printed and not asserted.
- (d) Verifying first, on the path the running app takes, the delegate that hears the storage and the
  undo, redo and composed-text paths; fixing what the verification shows.

Not in scope, one line each (reasons below): the text card, a ranged fold layout, the embed and
view-block update pass, the cost TextKit itself pays inside an insertion.

## Decisions

- **The layout debt is its own record, fed by the storage's processed edits.** It holds either
  "everything is owed" or a set of owed ranges in the current text. A fragment loses its layout in
  three ways: a processed storage edit (characters or attributes), an explicit whole-document
  invalidation, a new container width. Each reaches the record; a fourth way must go through it.
  Rejected: laying out only the caret's fragment and the viewport (ADR-0082 §D7) — it failed the
  G-grow hand check because every pass invalidated the whole note and heights above the viewport
  became estimates; that cause is what #971 removed, the invariant stays the same (no estimate in the
  note after a keystroke).
- **The record hears edits in the same storage delegate #971 already installs, in its second
  callback.** The restyle record keeps reading the pre-fixing range; the layout record reads the
  post-fixing range, because attribute fixing widens the range to the paragraph and that widened range
  is what TextKit re-creates. Rejected: a second delegate object replacing the coordinator as the
  storage's delegate — two owners of one slot is how the flake below can arise.
- **Every whole-document invalidation of a note editor goes through one door of the record.** That
  covers folding, transclusion and a view block's measured height. Rejected: leaving the calls where
  they are and teaching the record by comment — the next one added would silently leave estimates.
- **The text card is untouched.** It has its own coordinator, no grow-to-fit and no layout call; its
  fold invalidation is not on this path. ADR-0091 §D9 already keeps the card on its whole-text path.
  Rejected: converting the card's door too — nothing consumes the record there.
- **The record vouches for nothing while the storage's delegate is not the coordinator.** In that
  case the layout is the whole note, the answer before this work. The coordinator also clears the
  delegate when its view is dismantled. Rejected: waiting for a root cause before guarding — the flake
  (3 runs in 10 of the full suite, not reproducible once observed) is unexplained, and the guard costs
  nothing when the delegate is right.
- **A launch argument restores the whole-note layout.** Same shape as the restyle kill switch of
  ADR-0091 §D8, so a bad hand check can be isolated between #971 and this work without a rebuild.
- **The windowed renumbering starts at a line the structure map vouches for.** The start is the last
  boundary at or before the line before the edit whose previous line ends every ordered run (a blank
  line, a column-0 line that is not a list item, or the start of the note), taken with its fence
  parity from the map #971 already keeps; it reads forward until the runs that touch the edit, widened
  by a line each side, have ended. It must equal the whole-text result. Rejected: a fixed number of
  lines above and below — a run can be arbitrarily long and the answer would differ from the
  whole-text one.
- **Undo, redo and composed text are verified through the real operation, then fixed if the result
  differs.** The existing hosted twin calls the update pass by hand after an undo, which hides a missing
  notification. If the real path does not restyle, the fix observes the undo manager's change
  notifications and an override of the composed-text entry point, replaying the same edit path;
  otherwise no code changes. Rejected: reporting only — a restyle that is stale after undo is a defect
  the person would meet in the first minute of use.
- **Acceptance target: asserted up to 200 KB, measured at 1 MB.** The four rows up to 200 KB must be
  under 20 ms CPU per key in the Debug bench on the development Mac; the two 1 MB rows are measured,
  their ceilings are fixed by the person at a gate (the parallel line's ceilings are not inherited),
  and the share that stays inside TextKit's insertion is stated in the ADR. Rejected: all six under
  20 ms — about 80% of the 1 MB cost is TextKit's own bookkeeping of an insertion, before any app code
  runs; a criterion the app cannot meet would be waived at the gate, not met.
- **One build, one hand-check pass on Release.** The build starts now, without waiting for the hand
  checks of #971; the person's Release pass covers both and the launch arguments isolate the culprit if
  it fails. Rejected: waiting for #971's gates first — it doubles the person's Release sessions for a
  change that shares the same checks.
- **The structural bench rows are printed, not asserted.** Same rule as the three fallback rows of
  #971. Rejected: ceilings now — those edits restyle half the note by design and TextKit lays out that
  half; a ceiling would pin the machine, not the code.

## Constraints

- **The text storage keeps the stored paragraph's length (attribute and style changes only)** —
  origin: platform, TextKit's content manager contract, restated in ADR-0091.
- **Typing, caret, undo, composed text, list renumbering and the reveal of markup behave exactly as
  today** — origin: user mandate on PG-401, ADR-0091.
- **The golden corpus stays byte-identical and the incremental result equals a full restyle** —
  origin: ADR-0091 and ADR-0082.
- **After a keystroke no height in the note is an estimate** — origin: ADR-0082 §D7's withdrawal, the
  G-grow finding (Cmd+Down then a click selected the whole note).
- **The shared Core sources are Foundation only** — origin: ADR-0001 §D1; the windowed renumbering
  lives in Core and compiles into `perg` and `pergamenum-mcp`.
- **The card keeps the whole-text renumbering and restyle** — origin: ADR-0082 §D6, ADR-0091 §D9.
- **The G-grow hand check, the new ceilings and the two extra G-type checks are the person's, on a
  Release build** — origin: user mandate; Debug is far too slow at 1 MB.
- **A new ADR number is taken from origin/main at write time and re-checked before the merge** —
  origin: repository practice; 0092 is the first free number at the time of this SPEC and another line
  of work holds an unpublished file with that number.

## Stack

Swift 6, AppKit/TextKit 2 (`NSTextStorage` delegate, `NSTextLayoutManager`), Swift Testing, the
hosted-editor fixtures and the bench script already in the repository. No new dependency.

## Data model

One new record, owned by the note coordinator and not persisted:
- whether the whole document is owed;
- the owed UTF-16 ranges in the current text, moved with each edit and widened by one character on
  each side when laid out;
- the container width the layout was last made at.

The windowed renumbering gets a start line and a fence parity as inputs and returns what the
whole-text form returns, plus the range of lines it read so a test can assert that range does not
grow with the note.

## API / interfaces

- The grow-to-fit entry keeps its signature and its three steps; only the layout call changes from
  the document range to what the record owes.
- A single entry point on the record for "invalidate everything", replacing the direct calls in the
  fold, transclusion and view-block passes.
- A launch argument and a defaults key that restore the whole-note layout, named like the existing
  restyle switch.
- The windowed renumbering as a sibling of the scoped one, with the whole-text form unchanged.
- A bench flag that adds the structural rows to the printed table.

## UI flows

None added. The visible behaviour on a keystroke, after Cmd+Down, on a click low in the pane, on undo,
redo and composed text, and with a folded section is unchanged.

## Edge cases

- Whole-note layout is owed at: the first call of a coordinator, after any whole-text pass (note
  switch, external change, theme or setting change), after a fold, transclusion or view-block height
  change, and after a width change.
- An owed range after a deletion is never empty: it owes the paragraph the deletion joined.
- TextKit invalidates the paragraph after an attribute edit together with it: each owed range is laid
  out widened by one character on each side.
- A storage delegate that is not the coordinator: whole-note layout.
- Fences, tables, frontmatter and view-block fences change structure beyond their line: the restyle
  falls back as in ADR-0091; the layout then owes the restyled range, which is what the structural
  rows measure.
- Renumbering across a fence: the window's start carries the fence parity; a run that crosses the
  window's start is impossible by construction of the start line.
- Line separators the renumberer reads (lone CR, NEL, LINE SEPARATOR, PARAGRAPH SEPARATOR) split
  lines differently from the grammar; the fence parity of a grammar line counts them.
- Undo and redo of a keystroke that renumbered a list stays one undo step.
- Composed text: the marked range and the selection are unchanged by a restyle during composition.

## Test seams

Existing seams only, as agreed:
1. The hosted editor with the full twin, driven by the real operations (typing, replacing, undo
   manager, marked text) and without calling the update pass by hand: layout debt, delegate guard,
   dismantle, undo, redo, composed text, kill switch.
2. The pure Core tests of list continuation: windowed renumbering against the whole-text form, as a
   property over generated edits, plus a count of lines read that does not grow with the note.
3. The grow-to-fit scope tests, which already pin ADR-0082 §D7 in-process.
4. The restyle bench, for the asserted rows up to 200 KB and the printed structural rows.
A structural guard test over the editor sources pins the single invalidation door, as the UI harness
guard test does for its own rule.

## Success criteria

- [ ] R-01 — The coordinator clears the storage delegate when its view is dismantled, and a hosted
  test shows the storage has no delegate afterwards.
- [ ] R-02 — With the storage's delegate replaced by another object, the next grow-to-fit lays out the
  whole note and no height is an estimate; with the delegate correct it lays out only what is owed.
- [ ] R-03 — For each of undo, redo, and a composed-text sequence (set marked text, replace it, commit),
  driven through the real operation with no manual update pass, the text, the binding value, the
  attributes run by run and the derived state of the incremental editor equal those of a full-restyle
  twin. Written red first; if it is red, the fix of Decisions applies and it turns green.
- [ ] R-04 — The ADR records, for undo, redo and composed text, whether the real path posts the
  change notification and what the replay hooks are, with the method used to find out.
- [ ] R-05 — After a keystroke (a character, a new paragraph, an insertion that wraps the line) at the
  top and after a jump down the note, no layout fragment of the note has an estimated height, in the
  editor surfaces that share the note coordinator; the two ADR-0082 §D7 pinning tests stay green
  unchanged.
- [ ] R-06 — After a keystroke, Cmd+Down and a click, the top of the view stays on the same text and
  the click lands where it was aimed (in-process).
- [ ] R-07 — The layout record owes the whole note exactly at: first use, a whole-text pass, a fold
  change, a transclusion change, a view-block height change, a container width change; and only the
  edited ranges after a keystroke, a reveal, an embed and a view-block per-paragraph edit.
- [ ] R-08 — A guard test fails if any editor source for the note surfaces invalidates the layout of
  the whole document anywhere but the record's single entry point.
- [ ] R-09 — The launch argument restores the whole-note layout; with it on, R-05 and R-06 still hold.
- [ ] R-10 — The windowed renumbering equals the whole-text renumbering for generated notes and edits
  (ordered and unordered runs, nested levels, blank-line boundaries, code fences with both markers,
  gapped ordinals, the four extra line separators); the generator is non-vacuous.
- [ ] R-11 — The number of lines the windowed renumbering reads for the same edit is the same in a
  50 KB and in a 1 MB note.
- [ ] R-12 — The text card still renumbers with the whole-text form and its tests are unchanged.
- [ ] R-13 — The bench script has a flag that prints the structural rows (fence opened with no fence
  below, fence opened above later fences, `[[` typed with no `]]` below, `]]` written with the last
  `]]` far above), each with CPU ms and the dirty-range length; none is asserted.
- [ ] R-14 — The four bench rows up to 200 KB read under 20 ms CPU per key in Debug on the development
  Mac, and the asserted ceilings for the six rows are the person's, set at a gate.
- [ ] R-15 — The golden corpus is byte-identical, the property test of #971 (incremental equals full)
  is green, and the unit suite passes.
- [ ] R-16 — The new ADR extends ADR-0091, records the amendment to ADR-0082 §D7 (reopened and now
  scoped), the before and after numbers per row, the profile that names what stays at TextKit's floor,
  and the three ledger entries named in Out of scope. (no-test: documentation obligation)
- [ ] R-17 — The person runs the G-grow hand check on a Release build with a 1 MB note (type at the
  end and in the middle, Enter, a wrapping sentence, Cmd+Down, scroll to the end, click about 60 pt
  above the bottom edge then type, repeat after a keystroke at the top), sets the new ceilings, and adds
  to the G-type check undo and redo after typing in a 50 KB note, and an IME composition.
  (no-test: hand check by the person on Release)

## Not yet specified

_none_

## Out of scope

- **The text card's coordinator and its fold invalidation** — no grow-to-fit or layout call exists
  there, and it keeps the whole-text restyle by ADR-0091 §D9.
- **A ranged fold layout** — with a section folded the fold layout reads the whole note on every
  update (measured 414 ms at 1 MB by the parallel line); it needs a new declaration and an equivalence
  test first. Ledger entry.
- **The embed and view-block update pass** — O(embeds) and O(view blocks) per keystroke, unmeasured
  (the bench note has neither). Ledger entry: a bench row that carries them, then each made
  proportional or named with its number.
- **TextKit's own bookkeeping of an insertion** — about 80% of the remaining 1 MB cost is spent inside
  the content storage's element ranges and the layout manager's invalidation, before any app code
  runs, and is the same in Release. A note laid out lazily with a scroll anchor might keep fewer cached
  elements; unmeasured. Ledger entry.
- **The parallel line's design for the dirty range** (its own recorder, offset table, incremental
  styler) — the person decided not to ship it; only the pieces above are taken, as ideas and tests.

## Domain terms

- **Layout debt** — the part of TextKit's layout of the note that is no longer valid since the last
  grow-to-fit: nothing, some ranges, or everything.
- **Whole-text form / scoped form (renumbering)** — as in ADR-0082 §D6: the first scans every line,
  the second only the runs touching an edit.
