Status: Approved (2026-10-10)

# SPEC — Per-keystroke restyle cost proportional to the edited paragraph (follow-up of PG-385 N2)

## Destination

A keystroke in a note costs time proportional to the edited paragraph plus what the edit can
structurally affect, not to the note: under a ceiling of about 20 ms CPU in the 50 KB, 200 KB and
1 MB synthetic notes (final ceilings fixed by the person at a gate), with typing, caret, undo, IME,
list renumbering and reveal behaving exactly as today. The result is a SPEC for `/workplan`, which
writes the ADR (extends ADR-0082 §D9 and the §D6/§D7 follow-ups, touches ADR-0077 §D1) and the plan.

## Objectives

Typing in a 50 KB note is unusable in a Release build and a 200 KB or 1 MB note cannot be used at
all (measured 2026-10-10: every keystroke restyles the whole note; Debug bench, CPU ms per key, 50 KB
205, 200 KB 826, 1 MB 6965 after the `wikilinkSpans` fix of PR #956). A person types faster than five
keys a second, so the cost per key must not grow with the note. Optimising the parsers cannot reach
that; the work has to stop being proportional to the note.

Secondary: remove the second styling pass the SwiftUI update runs after the binding write, and the
whole-text transclusion rescan on every key, where the design allows.

## Scope and non-goals

In: the note editor's keystroke path (`textDidChange` and the update that follows the binding write),
the styler's incremental entry point, the offset-keyed state the passes hold, the bench and tests.
Surfaces that embed the note editor (Oggi, Diario) inherit it. Out: the card editor, a scoped
`growToFitTheText`, moving styling off the main thread, any change to what a span means.

## Decisions

- **Dirty-range restyle** — attributes are rewritten only in the dirty range (the edited paragraph(s),
  widened by the invalidation rule); outside it the storage keeps its attributes, which `NSTextStorage`
  shifts itself. Offset-keyed state (hidden markers keyed by paragraph start, hidden-line sets, table
  and view-block offsets, unspellable ranges) is shifted by the edit's length delta in a linear pass
  over the dictionaries, with no parsing. Rejected: per-line span cache in line-relative coordinates —
  a new structure to keep coherent with undo, IME, rename and external change, and the same linear
  shift cost anyway.
- **Invalidation by structural signature, otherwise full restyle** — the edited lines are classified
  before and after the edit (line kind, fence-parity contribution, presence of `|`, `[[`, `]]`, `---`,
  list indent, view-block fence). Same signature: restyle the paragraph only. Different signature or any
  doubt: full restyle, exactly as today. Local blocks (a table run, a list run) widen to that block
  only. Rejected: always widening to the nearest block and never falling back — a fence opened or
  closed can change half the note, the rule set grows large, and divergence from the full result
  becomes likely.
- **The edited range comes from the text storage, not from `shouldChangeTextInRanges`** — so that undo,
  redo and programmatic replaces are covered by the same path; a wholesale string replace (note switch,
  external change) is a full restyle. (Assumption, see below.)
- **Layout stays whole-document in `growToFitTheText`** — not rewriting attributes outside the dirty
  range makes `ensureLayout(documentRange)` nearly free, because nothing is invalidated; the bench
  decides whether scoping it again is needed, and that would be a new decision with its own G-grow.
  Rejected: re-scoping now — brings back the failure that withdrew ADR-0082 §D7 (wrong scroll, whole
  note selected) and doubles the hand check.
- **The card stays on the whole-text path** — a card holds a few lines; same asymmetry as ADR-0082
  §D6's renumber. Parity is by construction: the incremental result must equal the full restyle of the
  same styler, which the property test proves. Rejected: sharing the incremental path — 15 card tests
  call `applyStyling` directly and the card has no edit-range hook, for a gain nobody measures.
- **A hidden kill switch** — a `UserDefaults` key not exposed in Impostazioni, plus a launch argument
  for tests, forces the full restyle always. Rejected: nothing beyond the tests (a residual divergence
  would need a release), and an idle full-restyle reconciliation (seconds on the main thread at 1 MB).
- **Bench contract** — the six existing rows are asserted at the ceiling fixed at the gate (proposal
  20 ms CPU); rows for the fallback paths (keystroke opening a fence, in a table, Enter in a list) are
  printed and never asserted, since they cost what a full restyle costs by construction.

## Constraints

- **Result equals the full restyle** — after any sequence of edits the attributes and the derived state
  equal a full restyle of the same text. Origin: user mandate (property test) and ADR-0082 §D2/§D8.
- **Golden corpus byte-identical** — the 119 cases of the styler corpus do not change. Origin: user
  mandate, ADR-0077 §D7.
- **A displayed paragraph keeps the stored paragraph's length** — attribute and style changes only.
  Origin: platform (`NSTextContentManager.h:120`).
- **Typing, caret, undo, IME/marked text, list renumbering and reveal behave as today**, including one
  undo step per keystroke with a renumber. Origin: user mandate, ADR-0082 §D6.
- **No colour or font outside the tokens.** Origin: CLAUDE.md.
- **The shared sources stay free of SwiftUI** so `perg` and `pergamenum-mcp` build. Origin: ADR-0001 §D1.
- **A test is restated only with the reason said first**, never weakened silently. Origin: CLAUDE.md.
- **The G-grow hand check (1 MB, Release)** is part of acceptance and is done by the person: type at
  the end and in the middle, Cmd+Down, scroll to the end, click low in the pane. Origin: ADR-0082 §D7.
- **Merge coordination with PG-219** (branch `docs/spec-pg-219-cursor-feedback`) through
  `sync_operation`: `textDidChange` and `growToFitTheText` live in the file it restructures.

## Stack

Swift 6 strict concurrency, SwiftUI plus `NSTextView` (TextKit 2), Swift Testing. No new dependency.

## Data model

The dirty range: a range in post-edit coordinates plus the length delta, accumulated from the text
storage's edit notifications between two restyles. The structural signature of a line, compared before
and after. The shift of every offset-keyed table by the delta for offsets at or after the edit.

## API / interfaces

An incremental entry point on the styler returning the spans of a range given the context the range
needs (fence state at its start, list level, frontmatter bounds), kept in the shared sources. A way for
each offset-keyed controller to shift its state. A launch-argument and defaults key for the kill switch.
No change to a span's meaning or to the connectors.

## Edge cases

- Opening or closing a code fence or a `pergamenum-view` fence; frontmatter at the top; a table header
  whose delimiter row is edited; setext-like and list continuation; nested list levels; blockquotes;
  `[[` and `]]` pairing across lines; multi-line inline constructs: all go through the signature, and
  the property test generates them.
- Edit spanning several paragraphs (paste, cut, replace); undo and redo; IME marked text in progress
  (restyle must not disturb the marked range); find highlights and folding active during typing.
- Edit at offset 0 or at the end; empty note; CRLF lines; U+2028 and lone `\r` inside a line.
- Reveal under the caret and the pending selection after a renumber.
- The second pass after the binding write finds nothing changed and does nothing.

## Test seams

1. A pure property test on the styler: random edit sequences from a structural alphabet (backtick, `|`,
   `-`, `#`, `[`, `]`, `>`, digits, spaces, newline, letters), fixed seeds, incremental result equals
   full restyle. The highest and cheapest seam.
2. The golden corpus as oracle, unchanged.
3. The hosted `NoteTextView` through the existing scrolled-editor fixture: caret, undo, marked text,
   renumber, reveal, the absent second pass, shifted offset-keyed state.
4. The existing restyle-budget bench, extended with printed fallback rows.

No new GUI test. Tests that assert synchronous whole-note styling after a keystroke are restated with
the reason said first.

## Success criteria

- [ ] R-01 — A keystroke in the middle of a paragraph costs at most the ceiling fixed at the gate
  (proposal 20 ms CPU) in all six bench rows (50 KB, 200 KB, 1 MB, prose and fences), measured as today.
- [ ] R-02 — Property test: after random edit sequences the attributes of the storage and the
  offset-keyed derived state equal a full restyle of the same text.
- [ ] R-03 — The 119 golden cases are byte-identical.
- [ ] R-04 — An edit that changes a line's structural signature falls back to the full restyle (or
  widens to the block), proven for fence open/close, view-block fence, frontmatter, table header and
  delimiter row, list indent change, blockquote, `[[`/`]]`.
- [ ] R-05 — Offset-keyed state below the edit is shifted, not rebuilt: hidden markers, hidden lines,
  tables, view blocks, unspellable ranges and folding agree with a full restyle after an edit above them.
- [ ] R-06 — Undo, redo and a pasted multi-paragraph replace restyle correctly; one undo step per
  keystroke including a renumber; caret and reveal under the caret as today.
- [ ] R-07 — IME marked text is not disturbed by the restyle.
- [ ] R-08 — The second styling pass after the binding write is a no-op when text, theme and settings
  are unchanged since the last pass; asserted by a test.
- [ ] R-09 — Transclusions are not rescanned across the whole text on a keystroke that does not touch
  a transclusion line or change the fence structure; the rendition table still equals a full scan.
- [ ] R-10 — A launch argument forces the full restyle and the kill switch key does the same; with it
  on, behaviour equals today's.
- [ ] R-11 — The card editor is unchanged and its tests stay green; Oggi and Diario draw the same spans
  as the note editor.
- [ ] R-12 — Fallback-path bench rows (fence opened, table, Enter in a list) are printed. (no-test: the
  rows are reported, never asserted, by decision)
- [ ] R-13 — Every test restated has its reason recorded in the ADR first.  (no-test: process
  obligation, checked by reading the ADR)
- [ ] R-14 — G-grow hand check passes on a Release build with a 1 MB note. (no-test: hand check done by the person on a Release build)
- [ ] R-15 — Release build, 50 KB note: a sentence types without perceptible lag. (no-test: hand check done by the person on a Release build)
- [ ] R-16 — A new ledger entry (roadmap) exists for this task and links PG-385 (#887) and PR #956.
  (no-test: ledger obligation, verified by reading TODO.md)

## Not yet specified

- The exact members of the structural signature and the widening rule per block type: the plan fixes
  them from the grammar, the property test finds the misses.
- Whether the unspellable ranges and the paragraph-spacing pass can be shifted or must be recomputed
  over the dirty range plus neighbours.

## Out of scope

- Re-scoping the layout in `growToFitTheText`: the safe whole-document behaviour is kept; revisit only
  if the bench shows it dominates, as a new decision.
- Moving styling to a background thread or deferring it: it stays synchronous to keep typing exact.
- The card editor's incremental path: no measured gain (see Decisions).
- Parser micro-optimisations: already reached the limit of what proportional-to-note work can give.

## Domain terms

- **Dirty range**: the paragraph(s) an edit touched plus what the invalidation rule adds.
- **Structural signature**: the compact summary of a line's block-level role compared before and after
  an edit to decide between paragraph-only and full restyle.
