Status: Approved (2026-10-04)

# SPEC — Note workflow N5, the page part two (PG-388, #890)

Restored from the chain SPEC `SPEC.md` at commit `f697b363` (the last commit holding the
N1..N5 text; root `SPEC.md` on `main` now belongs to another task). Only the parts N5 reads are
kept, verbatim: the decisions, constraints, edge cases and test seams that bind it, then
R-35..R-45. Facts in this file were true on `origin/main` @ `63831c64` on 2026-10-04; the plan
`docs/plans/note-workflow-n5.md` re-checks them on current `main`.

## Decisions
- **One PR per milestone, in order N1, N2, N3, N4, N5** — a regression in N2's styler cannot
  hold N1 hostage, and each PR closes one issue. Rejected: one PR for everything (weeks of
  drift, an unreviewable diff); one PR per ADR (splits N2, N3 and N4 into coupled halves).
- **Mockups ship first, as their own PR per milestone** — SPEC §11.1; the person approves the
  DesignGallery mockup on the Debug build, then the milestone's code is built. N1's mockup
  covers only paragraph spacing and the H5/H6 distinction. Rejected: HTML mockups drawn during
  this interview (not the real tokens and fonts); mockups for N4/N5 only (N2's gutter and N3's
  popover are visible changes too).
- **Callouts write the English type keywords** `note`, `tip`, `important`, `warning`, `caution`
  (the set GitHub and Obsidian style); the Italian names `nota`, `suggerimento`, `importante`,
  `avviso`, `attenzione` are read as aliases; the interface labels them in Italian; any other
  type is read as a callout and drawn neutral. Rejected: Italian keywords in the file (the
  roadmap's wording, which contradicts its own "Obsidian reads the file unchanged").
- **Clickable dates are the `>YYYY-MM-DD` scheduling tokens** (with or without an hour); a bare
  ISO date in prose is not a link. Rejected: every ISO date (false positives in prose).

## Constraints

- **The file never changes shape**: markdown, the closed four-key frontmatter (SPEC §4.3), flat
  namespaced tags (SPEC §4.4), JSON Canvas 1.0; every rendering change is display-only —
  origin: CLAUDE.md principles 1 and 4, SPEC §4.
- **Concealment keeps the character count**; a line that must look different is drawn by a
  layout fragment, its characters stay — origin: ADR-0028, the TextKit 2 design note.
- **One grammar**: after N2 every new construct enters the shared markdown parsers first and is
  drawn by every surface from the same span — origin: ADR-0077 §D1, roadmap §0.
- **Tokens only**: a new colour or spacing is a key in both theme files — origin: CLAUDE.md
  design system rule.
- **One write door, guarded**: every write through the session with `expecting:` or
  `expectingAbsent:`; state read before an `await` is re-read after it — origin: ADR-0043
  §D7/§D8, ADR-0057 §D3.
- **List rows**: flat rows in `List(selection:)`, no nested `.contextMenu`, keyboard focus per
  ADR-0070 — origin: ADR-0024, ADR-0069, ADR-0070.
- **Fully offline**; no index schema change; protected interfaces untouched (the word-boundary
  truncator behind `ImportNaming.recordingNoteTitle` is reused, never forked) — origin:
  CLAUDE.md principles 2 and 3, `.claude/protected-interfaces`.
- **GUI tests bounded**: at most three in N3 and two in N4, none elsewhere, each justified in
  its ADR, every file on `PergamenumUITestCase` — origin: CLAUDE.md merge-gate rule, user
  mandate in this interview.
- **PG-233's prompt stays** — origin: user decision 2026-10-03.

## Edge cases

- `==` inside a code span is not a highlight; a fence body stays editable when its header is
  drawn.
- An unknown callout type renders neutral; a folded callout's body hides through the shared
  hidden-line set (ADR-0078).

## Test seams

Chosen in the interview (2026-10-04), existing seams first, highest level possible:
1. Pure unit tests in `PergamenumTests` for everything in Core and the connector layer: the
   initial-tags rule, the capture title proposal, parser spans, callouts, highlights, table
   rewrites, templates, the backlink line finder, per-note unresolved targets, the mention
   rewrite, extract's two writes, classify's frontmatter rewrite.
2. The styler golden corpus, captured before N2's rewrite (the export corpus's shape), each
   difference classed A (fix) / B (deliberate) / C (regression); reused for N5's constructs and
   the export.
3. A restyle budget test with a fixed ceiling, in the suite the Stop hook runs.
4. Hosted-view tests (the in-process family) for the gutter reveal, the popover, the link
   commands, the inspector sections, the «Da classificare» pane, the composer sheet and the
   undo toast.
5. Connectors: `perg` tests, and `scripts/mcp-smoke.py` after each MCP change.
6. GUI tests only in N3 (at most three: follow from the keyboard, the preview appears, «Collega»
   a mention) and N4 (at most two: filing a capture, the daily template).

## Success criteria

### N5 — The page, part two (issue #890, ADR-0087)

- [ ] R-35 — Both themes define tokens for inline code background, highlight, the five callout
  types and the quote bar.
- [ ] R-36 — Inline code reads as a pill and `==testo==` as highlighted text with their
  delimiters concealed off-caret and revealed on it; `==` inside code is not a highlight.
- [ ] R-37 — A fence's opening line reads as a header with a language badge and a line count, its
  closing line drawn quietly, both revealed on caret; the body stays editable; «Copia il blocco»
  copies the body.
- [ ] R-38 — `> [!type] Titolo` and the foldable `-`/`+` forms render as callout cards in the
  type's colour; the app writes the English keywords, reads the Italian aliases, labels them in
  Italian, draws an unknown type neutral, folds the body through the shared hidden-line set, and
  inserts one from the slash menu; Workspace cards colour the title only.
- [ ] R-39 — Quoted paragraphs indent per nesting level in the secondary text colour beside a
  full-height bar in the quote-bar colour, in the editor and in the reading view.
- [ ] R-40 — An embed reserves its written or default size before its thumbnail loads; an inline
  or non-renderable embed reads as a chip (icon, name, Quick Look on click); a transclusion's
  source line reads as the caption «da «Nota» › Sezione», revealed on caret; the resize handle
  and `|W` writing are unchanged.
- [ ] R-41 — A table column's menu changes its alignment by rewriting the delimiter row and sorts
  the rows by that column, each as one undo step.
- [ ] R-42 — `#tag` reads as a chip (namespace in the secondary colour, value in the accent) and a
  `>date` as a date chip.
- [ ] R-43 — The HTML export agrees with the editor on every construct of R-36..R-42 (highlight as
  `<mark>`, callout as an aside), pinned by golden corpus cases.

### Across the chain

- [ ] R-44 — Each milestone ships as its own PR after its mockup PR, closes its issue (#886..#890)
  and its ledger entry, and records its ADRs (0080..0087, numbers taken at merge) (no-test:
  release process, checked at each /ship gate).
- [ ] R-45 — `perg`, `pergamenum-mcp` and the app build after every milestone, and
  `scripts/mcp-smoke.py` passes after each MCP change (no-test: build and smoke script, not a
  unit test).

## Not yet specified

_none_

## Out of scope

- **On-disk format, frontmatter schema, index schema** — unchanged by every milestone.
