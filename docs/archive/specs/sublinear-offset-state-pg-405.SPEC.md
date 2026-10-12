Status: Approved (2026-10-12)

# SPEC — Sub-linear shift and splice of offset-keyed editor state (PG-405)

## Destination

A SPEC approved for `/workplan`. Reaching the end of the work it describes means a keystroke in a 1 MB
note no longer pays a cost proportional to the number of lines for moving, rebuilding or scanning the
editor's offset-keyed state, with the app-owned linear terms of ADR-0091 §D6 and ADR-0093 "What stays"
gone and a new ADR recording how.

## Objectives

PG-401 made a keystroke restyle the edited paragraph and lay out what it changed. What the app still owns
that grows with the note is the bookkeeping of positions: ADR-0093's profile attributes about 19% to 22%
of a 1 MB key to moving the offset-keyed state after each edit (the spell checker's unspellable ranges,
the embed runs, the decoration delegate's hidden markers) and a further share to the structure map's own
shift. The same stores are also rebuilt by the splice that follows the restyle, so shifting alone would
only move the cost.

This work makes those terms independent of the note's size. It does not by itself promise the 20 ms per
key target of PG-401: ADR-0093 measured about two thirds of a 1 MB key inside TextKit, which this work
does not touch. What it delivers is the removal of the largest term the app owns, measured, so the
person can set the ceilings from numbers.

## Scope and non-goals

In:
- The shift and the ranged splice of the three stores that grow with the number of lines: hidden markers,
  unspellable ranges, embed runs.
- The structure map's own linear terms on the keystroke path: the shift of the lines and runs below an
  edit, the fence parity read by the list-renumber window, and the linear scans in its splice.
- One shared pure type for the stores above, tests, a bench row, an ADR.

Out (detail below): the holders that grow with rare constructs, fold and reveal state, TextKit's own
bookkeeping, the full-restyle path.

## Decisions

- **Perimeter is every linear term, the structure map included** — the user chose it over "shift and
  splice of the three stores" and over "the two shifts named in the ledger". Rejected: only the two
  shifts of ADR-0093 — the splices of the same stores and the structure map are linear in the same way,
  so the measured gain would be partial and the cost would move rather than go.
- **Mechanism: sorted storage with a pending delta (a step), one shared type** — an edit moves a delta
  boundary instead of rewriting every entry, so keystrokes at the same place cost O(1) in entries
  touched, and a read is a binary search on the current absolute offset. Prior art in the same shape:
  Scintilla's line partitioning. Rejected: a tree with relative offsets — O(log n) even after a caret
  jump, but more code and harder to keep identical to the one shift rule in `StorageEdit`. Rejected:
  keeping the dictionaries and iterating only the tail — still O(n) on average, it halves the problem.
- **The shift rule stays `StorageEdit`'s** — the new type reproduces `shifted`, `shiftedKeys` and
  `clipped` exactly (ADR-0091 §D2, §D6); no second rule is written. Rejected: a rule of its own inside
  the new type — two rules would drift.
- **A far caret jump is paid once, and measured** — the first edit after a jump moves the delta boundary
  across the entries in between. It is accepted as a bounded one-off (an integer move, not a rebuild of
  dictionaries) and gets its own bench row. Rejected: a structure that is O(log n) in every case — see
  the tree above.
- **Rare-construct holders stay dictionaries with a declared bound** — tables, view blocks, embeds,
  renditions and the hosts of drawn views cost O(k) where k is the number of such constructs (zero to
  about 600 in the bench), not O(lines). Rejected: converting them — it puts the identity of the
  table grids and view hosts, which the R-05 twin asserts, at risk for no measurable gain.
- **Fold and reveal state stay out** — the fold stores grow with the folded section and are PG-402's;
  the reveal sets are large only for an enormous selection. Rejected: pulling PG-402 in — two ADRs
  would overlap.
- **Acceptance is a touched-entries counter plus the bench, ceilings fixed by the person** — the counter
  is deterministic, so it cannot flake under load; the bench measures what the person feels. Rejected:
  bench alone — noisy under load, and a term that regrows would hide inside it.

## Constraints

- **The result of an edit is byte for byte what the current implementation produces** — origin: user
  mandate (PG-401: typing, caret, undo, IME, list renumbering and reveal behave exactly as today) and
  ADR-0091 §D6.
- **Foundation only for the pure types** — origin: ADR-0091 §D1.
- **No new third-party dependency** — origin: ADR-0007 §D2 (the only one is the MCP SDK); a package that
  the dependency graph already resolves but no source imports is still a new dependency.
- **The golden corpus stays byte identical** — origin: ADR-0082 and PG-401 (119 cases).
- **The 1 MB hand check runs on a Release build, by the person** — origin: ADR-0082 §D7 and ADR-0093
  gates; Debug is too slow at 1 MB.
- **Surface parity** — origin: ADR-0082 and ADR-0091: note, Oggi, Diario and cards share the styler and
  stay consistent.
- **A displayed paragraph keeps the stored paragraph's length** — origin: platform (TextKit 2 content
  manager contract), unchanged by this work.
- **The ledger entry stays `PG-405`; the PR body says "refs", never "close"** — origin: project memory.

## Stack

Swift 6, AppKit text view on TextKit 2, Swift Testing. No new target and no new package.

## Data model

Two shapes of the shared type, one pure value type each, both ordered by current absolute offset:

- an ordered list of disjoint ranges (unspellable ranges, embed runs, the structure map's run lists);
- an ordered table keyed by offset whose values ride along unchanged (hidden markers by paragraph
  start; the structure map's per-line records).

Stored positions are relative to a pending delta; the current absolute position is derived on read. Every
operation answers in the text's current coordinates: shift by an edit, replace the entries inside a dirty
range, look up an exact key, find the entry containing or preceding an offset, enumerate a range.

## API / interfaces

- The apply-an-edit and replace-inside-a-dirty-range operations take the existing `StorageEdit` and the
  existing dirty range; their results equal the current dictionary and array code.
- The decoration delegate keeps its whole-dictionary entry (the full path) and its ranged splice entry
  (the incremental path); only what they hold changes.
- The test snapshots (`DerivedStateSnapshot`, `DecorationSnapshot`) keep their value types; they are
  produced from the new storage.
- A debug-only touched-entries counter on the shared type, read by tests.

## Edge cases

- An edit that rewrites several entries: those wholly inside the replaced range are dropped, one that
  straddles an end is clipped (unspellable ranges become up to two parts), one that contains the edit
  stretches; a moved key that lands on a stayed key wins (the rule in `StorageEdit`).
- The merge invariant of the unspellable list (sorted, disjoint, adjacent ranges merged) holds across a
  splice boundary exactly as a full recomputation would leave it.
- Empty stores, an edit at offset 0, an edit at the end, a deletion of the whole note, a split of one line
  into two and a join of two into one.
- The first edit after a caret jump (delta boundary moved across many entries), and an alternation of two
  far edit positions.
- Undo, redo and IME composition replay produce ordinary edits and flow through the same path.
- The full-restyle path (kill switch on, or a structural fallback) replaces the whole store in one build.
- A fence opened or closed above a long stretch of text flips the parity of every line below: the
  structure map answers parity from the fence list, not by walking the lines.

## Test seams

Four levels, one of them new:
1. **New, pure:** model-based tests of the shared type against a naive array or dictionary implementing
   the `StorageEdit` rule, over random edit sequences, for the shift, the ranged splice and the lookups.
   The only new seam; it exists because the type is new.
2. **Existing twins stay unchanged and green:** the R-05 shift twin, the hosted random-edit twin
   (incremental equals full restyle), the structure map and renumber-window property tests, the golden
   corpus.
3. **Counter:** entries touched by a shift and by a splice at 50 KB, 200 KB and 1 MB, bounded by a
   constant independent of n; read in the pure seam and on the real editor stores.
4. **Bench:** the existing restyle-budget bench at 1 MB prose and fences, plus a row for the first edit
   after a caret jump. Ceilings are written by the person at a gate.

## Success criteria

- [ ] R-01 — For random sequences of edits, the shared type's contents equal a naive implementation of the
  `StorageEdit` rule after every edit, for the keyed-table shape and for the range-list shape.
- [ ] R-02 — Replacing the entries inside a dirty range leaves the store equal to filtering the old
  entries outside the range and merging the new ones in, including the merged-adjacent-ranges invariant
  at the boundaries.
- [ ] R-03 — The golden corpus, the shift twin, the hosted incremental-equals-full twin and the
  structure map and renumber-window property tests pass unchanged; none is weakened or restated.
- [ ] R-04 — Reads on the hot path (hidden markers, reveal and fold lookups by paragraph start) are exact
  lookups costing O(log n) at most; none of them iterates the store.
- [ ] R-05 — For an edit at the same position as the previous one, the entries touched by the shift and by
  the splice of hidden markers, unspellable ranges and embed runs are bounded by a constant independent
  of the note's size, asserted at 50 KB, 200 KB and 1 MB.
- [ ] R-06 — The first edit after a caret jump touches no more than the entries between the two positions
  plus that constant; the bench has a row for it.
- [ ] R-07 — In the structure map, the shift of the lines and runs below an edit, the fence parity and
  the scans of the splice cost O(log n) plus the entries touched, and the map still equals one built
  from the text after random edits.
- [ ] R-08 — The values the stores carry keep their identity across a shift (marker arrays, and the
  views and hosts of the rare-construct holders); the identity assertions of the existing twin pass.
- [ ] R-09 — With the full-restyle kill switch on, nothing shifts and the full path runs as before.
- [ ] R-10 — Note, Oggi, Diario and card editors behave identically to a full restyle after random edits
  (the surfaces' existing hosted tests pass).
- [ ] R-11 — Bench rows at 1 MB (prose and fences) and the after-jump row are recorded before and after;
  the person writes the ceilings at a gate. (no-test: ceilings are a human decision, ADR-0082 §D9)
- [ ] R-12 — A profile of a 1 MB keystroke on a Release build no longer lists the shift or the splice of
  these stores among the top app-owned terms; the remaining terms are named with their shares.
  (no-test: a sampled profile read by hand)
- [ ] R-13 — Hand check on a Release build with a 1 MB note, done by the person: type at the end and in
  the middle, Enter, a wrapping sentence, Cmd+Down, scroll to the end, click low in the pane; undo and
  redo; an IME composition. (no-test: ADR-0082 §D7)
- [ ] R-14 — A new ADR extends ADR-0091 §D6 and ADR-0093 "What stays", records the rejected alternatives
  above and the bounds of the holders left as they are; the ledger gets entries for whatever linear term
  remains. (no-test: documentation obligation)
- [ ] R-15 — The shared type and its tests import Foundation only and add no dependency.

## Not yet specified

- The list-seed back-walk (renumbering walks back to the nearest reset) is bounded by the length of a
  list, not of the note. Whether a 1 MB note that is one list makes it a term worth fixing is for the
  profile of R-12 to say.
- The constant that bounds R-05 and R-06, and the exact public shape of the shared type, are for the
  plan and the ADR.

## Out of scope

- Rare-construct holders (tables, view blocks, embeds, transclusions, hosts): cost O(constructs),
  converting them risks the identity the R-05 twin asserts for no bench gain.
- Fold state (PG-402) and reveal sets: fold grows with the folded section and has its own entry; reveal
  is large only for an enormous selection.
- TextKit's own bookkeeping, the layout managers' synchronisation and the scroll size estimate (PG-404):
  about two thirds of a 1 MB key, not app-owned.
- The bench row that carries embeds and view blocks (PG-403).
- The full-restyle path and its fallback rules: unchanged.
