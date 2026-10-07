**Requirement set:** `SPEC.md`

# N2 mockup PR: block markers hanging in the gutter (DesignGallery only)

- SPEC: root `SPEC.md`, Approved 2026-10-04, milestone N2 (issue #887, ledger `PG-385`). This PR
  draws R-13 and R-14 as pictures; it satisfies neither on its own. The code that satisfies them,
  and R-15 to R-19, is `docs/plans/note-workflow-n2.md`, built only after the person approves this
  mockup on the Debug build (the SPEC's "Mockups ship first, as their own PR per milestone").
- **Assumes N1 merged first** (`docs/plans/note-workflow-n1.md`): N2 is built after N1, so this
  branch is cut from `main` after N1's merge. Nothing here depends on an N1 detail; the only shared
  file is `MockupGalleryView.swift`, whose `Screen` enum every milestone's mockup PR extends.
- ADR outcome: **`docs/adr/0081-block-markers-reveal-in-the-gutter.md`** (new, Proposed), shared
  with the code PR, not a second record. This PR is the picture its gates G1 and G2 are decided on:
  the gutter's value, the heading marker's face, the quote step, the narrow-width shift, and the
  optional permanent `H2` badge. The ADR file lands with the code PR, so `main` never carries a
  `proposed` record ahead of its implementation (`docs/adr/README.md`, rule 2's check).
- Registered from the SPEC, not reopened: mockups ship first as their own PR; tokens only; no GUI
  tests in N2; the file never changes shape.
- No new token in this PR. The gutter candidates are drawn as sums of existing spacing tokens
  (`spacing.xl` = 40, `spacing.xl` + `spacing.s` = 48, `spacing.xl` + `spacing.m` = 56), so the
  gallery keeps the design-system rule; the code PR adds `spacing.gutter` with the approved value.

## Tasks

### Task 1 — The gutter-reveal mockup page (R-13, R-14)
Owner: coder
Files: Sources/Features/DesignGallery/GutterRevealMockup.swift, Sources/Features/DesignGallery/MockupGalleryView.swift
Tests: MockupGalleryLayoutTests.swift
Signatures:
- GutterRevealMockup — struct GutterRevealMockup: View
- GutterRevealMockup.narrowWidth — static let narrowWidth: CGFloat
- GutterRevealMockup.readableWidth — static let readableWidth: CGFloat
- MockupGalleryView.Screen.gutter — case gutter
- MockupPage — struct MockupPage<Content: View>: View (relied on)
- MockupScene — struct MockupScene<Content: View>: View (relied on)
- ProseTypography.heading — static func heading(level: Int, _ theme: Theme) -> NSFont (relied on)
Red: no

A new page, `GutterRevealMockup`, registered as `case gutter` in `MockupGalleryView.Screen` with
`Page("Margine dei marcatori", "N2, da approvare", GutterRevealMockup())`. Captions in Italian, as
every other page. Draw with the real faces: `theme.font(.prose)` for body and list text, headings
through `Font(ProseTypography.heading(level:theme))`, markers in `color.textTertiary`, the
revealed heading run in `theme.font(.caption)`. Every colour and size through a token.

The one thing the picture has to prove is that the content does not move, so every scene draws a
thin vertical guide at the content column in `color.borderSubtle`, and draws each item twice, one
row concealed and one row revealed, directly under each other. A marker hangs by being laid out
right-aligned in a frame that ends at the column (`HStack(spacing: 0) { marker.frame(width:
column, alignment: .trailing); content }`): that places the content at exactly the column whatever
the marker's width, which is ADR-0081's target, without measuring anything in the mockup. The
column arithmetic is ADR-0081's, stated in a doc comment that cites §D2 to §D4, not reimplemented
as a reusable type: the code PR owns it.

Scenes, top to bottom:

1. «Elenco annidato»: three levels mixing bullets, ordered items (`1.`, `10.`) and one task line;
   concealed (`•`, digits, checkbox glyph) above revealed (`-`, digits, checkbox unchanged), the
   guide at `C(L) = G + 1.5 em × L + 0.75 em` for each level. One wrapped item shows the second
   line aligned under the first line's text.
2. «Titoli»: H1 to H6, concealed (title on the guide at G) and revealed (`#` run in the caption
   face hanging left of the guide). The revealed H6 shows `###### `, the widest run the gutter must
   hold.
3. «Citazioni»: one and two levels, bars `▏` concealed and `> >` revealed, both hanging to the quote
   column; drawn twice, with the quote step at 0.75 em and at 0 (G1 decides).
4. «Larghezza stretta e leggibile»: the same short note (a heading, a paragraph, a two-level list,
   a quote) at `narrowWidth` and at `readableWidth`, with a dashed ghost guide where the text starts
   today (29 pt from the edge at narrow width) so the 24 pt move at narrow width is visible, and
   the readable scene showing the column unmoved and the markers in what used to be margin.
5. «Variante: livello del titolo sempre visibile»: concealed H1 to H3 with a dim `H1`, `H2`, `H3`
   label in the gutter, caption face, `color.textTertiary` (gate G2).
6. «Valori del margine»: the revealed H6 and a revealed three-level quote at G = 40, 48 and 56,
   built from the spacing tokens named above, so the person sees which value holds `###### `.

`narrowWidth` and `readableWidth` are static so a test can check them: `readableWidth` must not
exceed `MockupGalleryView.rowWidth` (672), the overflow defect the gallery's own comment records
(a scene wider than the row is clipped at both edges). The readable scene therefore draws the
column at a reduced but proportional width and says so in its caption; the narrow scene uses about
the width of the Diario pane (a value read from the running app before drawing it, not guessed).

### Task 2 — Pin the new page's wiring and widths (R-13, R-14)
Owner: tester
Files: Tests/MockupGalleryLayoutTests.swift
Tests: MockupGalleryLayoutTests.swift
Signatures:
- MockupGalleryView.Screen.gutter — case gutter (relied on)
- GutterRevealMockup.narrowWidth — static let narrowWidth: CGFloat (relied on)
- GutterRevealMockup.readableWidth — static let readableWidth: CGFloat (relied on)
Red: no

Two tests beside the existing arithmetic ones: the gutter page is listed in `Screen.allCases` with
the milestone string `"N2, da approvare"`; both scene widths are positive and at most
`MockupGalleryView.rowWidth`. Arithmetic and wiring only, no view is built, the file's stated scope.
What the page looks like is checked by eye at the gate.

## Risks & HITL gates

- **Mockup approval (G1 and G2 of ADR-0081), human, on the Debug build, before any view code.**
  Decides: the gutter value (40, 48 or 56, or another sum of tokens), the heading marker face
  (caption or something else), the quote step (0.75 em or 0), whether the narrow-width shift is
  acceptable, and the permanent `H2` badge yes or no. The code plan's Task 5 reads these answers;
  without them it cannot start.
- The picture is not the implementation: the mockup places the content by a SwiftUI frame, the
  code PR by measured paragraph indents in TextKit. The code PR's hosted geometry tests are what
  prove R-13 and R-14; this PR proves only that the person wants the result.
- `MockupGalleryView.swift` is edited by every milestone's mockup PR (N1, N3, N4 and N5 add their
  own `Screen` case). The conflict is one `case` line and one `page` line each; resolve by keeping
  every case, in milestone order.
- Commit and push are the human's, at the `/ship` gate. Branch suggestion:
  `feature/n2-gutter-mockup`.

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield

CHECK-CMD CANDIDATE: NONE

## Build result (2026-10-07)

BUILD · DONE WITH WARNINGS
Files: 5 changed (GutterRevealMockup.swift, GutterRevealMockupPieces.swift, MockupGalleryView.swift, MockupGalleryLayoutTests.swift, this plan)
Tests: 5617 passed, 0 failed, 5 known issues already present, 0 (coverage)
Review: sonnet, safe to merge
Coverage: COVERED     R-13  plan,tests
Coverage: COVERED     R-14  plan,tests
Coverage: UNCOVERED   R-44  plan
Dispatch: Round 1: coder — Columns arithmetic (GutterRevealMockup.swift:160), coder — unlabelled pairs (GutterRevealMockup.swift:317)
Dispatch: Round 2 (sweep): coder — 3 NITs (Pieces:52, GutterRevealMockup:34, :54)
WARN: R-44 has no test; it is a process requirement (mockup PR approved on the Debug build, then the code PR)
WARN: SPEC read from docs/specs-pending/pg-385-n2-page.SPEC.md, not the root SPEC.md, which belongs to PG-219
WARN: page not seen on screen, G1 and G2 are decided by eye on the Debug build

```text
FIX	swept	**NIT** Sources/Features/DesignGallery/GutterRevealMockupPieces.swift:52 — Dash pattern [3, 3] and state label width 64 are bare literals where the plan says every size goes through a token.
FIX	swept	**NIT** Sources/Features/DesignGallery/GutterRevealMockup.swift:34 — 420 duplicates the minWidth literal of DiaryView and TodayView with no pin, so the mockup can go stale silently if that minimum changes.
FIX	swept	**NIT** Sources/Features/DesignGallery/GutterRevealMockup.swift:54 — Awkward Italian in the scene 1 caption: "non si spostava già"; suggest "non si sposta già oggi".
```
