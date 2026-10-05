**Requirement set:** `SPEC.md`

# Plan — N1 mockup PR: paragraph spacing and the H5/H6 distinction, against what shipped

`SPEC.md` here is the note-workflow SPEC (N1 to N5, Approved 2026-10-04) in this chain's working
tree. Its decisions say mockups ship first, as their own PR, and that N1's mockup covers only
paragraph spacing and the H5/H6 distinction.

N1's implementation is PR #897's chain (`docs/plans/pg-384-n1-seams.md`). Its SPEC rejected a
mockup: 8 pt, checked by eye. Its plan has no mockup task, so this one is kept, but it can no
longer come first. The session-2 tasks of that plan (Tasks 4 and 5) ship:

- `spacing.paragraph` at 8 pt in both themes;
- `ProseParagraphSpacing.paragraphRanges(in:spans:)`, which puts the spacing after every prose
  and heading source line, in the note editor only;
- H6 drawn regular in `textSecondary` (`ProseTypography.heading(level:)`,
  `ProseTypography.headingColor(level:)`).

**This PR is cut from `main` after that session 2 lands.** It puts what shipped beside the
alternatives our SPEC left open, so Stefano confirms or changes them at gate G1. The N1 delta's
Tasks 3 and 4 (`docs/plans/note-workflow-n1.md`) apply any change. With G1 confirming everything,
they apply nothing.

**ADR outcome: no ADR.** A gallery page decides nothing. A value G1 changes is a token value,
already governed by the tokens-only rule (CLAUDE.md design system, ADR-0030 for the prose faces).

## Settled inputs (registered, not reopened)

- **The mockup's scope.** Paragraph spacing and H5/H6 only (SPEC, Decisions, «Mockups ship
  first»).
- **R-08.** A `spacing.paragraph` token in both themes, on prose paragraphs only (lists, quotes,
  code and tables excluded). H6 regular weight in the secondary text colour.
- **Tokens only.** Every colour and face comes through `Theme` and `ProseTypography`.
- **No production view, theme file, token or rule changes in this PR.** The page reads the shipped
  rule and token. It never redeclares them.

## What reading `origin/main` @ `5056c61f` and #897's plan established

- **Spacing tokens are points.** Every `spacing.*` token is a DTCG `dimension` read as points;
  `DesignTokenDocument` ignores the unit. At Avenir Next 16 (`font.prose`), 0.5em is 8 pt and
  0.75em is 12 pt, so the candidates are drawn in points.
- **The shipped rule.** It includes heading lines, which our R-08 neither includes nor excludes.
  That is the one open reading, and this page shows it both ways.
- **Before session 2**, H5 and H6 were the same 17 pt bold face from `font.proseTitle`
  (`max(prose + 1, title - (level - 1) * 2)`). "Before" is therefore H5's face at H6's size, in
  `.textPrimary`.
- **The gallery.**
  - Each page is one `MockupGalleryView.Screen` case mapped to a `Page` in one `switch`, built
    from `MockupPage` and `MockupScene`.
  - `contentWidth` is 720 and `rowWidth` is 672.
  - `Tests/MockupGalleryLayoutTests.swift` checks width arithmetic only.
- **N2 territory.** N2 edits `EditorMockup.swift`, so this PR does not touch it.

## Tasks

### Task 1 — Coder: the comparison page (R-08)
Owner: coder
Files: Sources/Features/DesignGallery/PageTypographyMockup.swift, Sources/Features/DesignGallery/MockupGalleryView.swift
Tests: PageTypographyMockupTests.swift, MockupGalleryLayoutTests.swift
Signatures:
- PageTypographyMockup — `struct PageTypographyMockup: View`
- PageTypographyMockup.SixthHeading — `enum SixthHeading: Equatable { case before, shipped }`
- PageTypographyMockup.spacingCandidates — `static let spacingCandidates: [CGFloat] = [8, 12]`
- PageTypographyMockup.attributedSample — `static func attributedSample(spacing: CGFloat, spacesHeadings: Bool, spacesBlankLines: Bool, sixthHeading: SixthHeading, theme: Theme) -> NSAttributedString`
- MockupGalleryView.Screen.pageTypography — `case pageTypography` mapped to `Page("Pagina: paragrafi e titoli", "N1, da confermare", PageTypographyMockup())`
- ProseParagraphSpacing.paragraphRanges — `static func paragraphRanges(in text: String, spans: [MarkdownStyler.StyledRange]) -> [NSRange]` (session 2, relied on)
- ProseTypography.paragraphSpacing — `static func paragraphSpacing(_ theme: Theme) -> CGFloat` (session 2, relied on)
Red: no

**The sample.** One realistic note:

- a title (`#`);
- two prose paragraphs separated by a blank line;
- two consecutive lines with no blank line between them;
- a bullet list, a task line, a blockquote and a fenced code block;
- H4, H5 and H6 in sequence, each followed by one line of prose.

**How it is styled.**

- `MarkdownAttributedText.attributed(_:theme:)` styles the text, which after session 2 already
  draws the shipped H6.
- `attributedSample` sets `paragraphSpacing` on `ProseParagraphSpacing.paragraphRanges`, the
  shipped rule, composed through `ProseTypography.paragraphStyle(_:font:basedOn:)`, so the line
  height survives.
- **Two page-local adjustments**, both written as variants of the shipped output, never as a
  second rule:
  - with `spacesHeadings: false`, it drops the ranges that intersect a `.heading` span;
  - with `spacesBlankLines: true`, it adds the empty paragraphs lying between two spaced ones.
- With `.before`, the H6 run gets `ProseTypography.heading(level: 5, theme)`'s face at H6's size,
  in `theme.color(.textPrimary)`.
- No colour or face bypasses `Theme`.

The page hosts each scene in a read-only `NSTextView` through a small `NSViewRepresentable`
inside the file, in the shape of `TransclusionMockup`.

**Scenes**, Italian captions, in this order:

1. «Prima: nessuno spazio tra i paragrafi, H6 come H5» (0 pt, `.before`).
2. «Come spedito: 8 pt dopo prosa e titoli» (8, headings spaced, `.shipped`).
3. «8 pt, titoli senza spazio aggiunto» (8, headings not spaced).
4. «12 pt (0,75 em), dopo prosa e titoli» (12, headings spaced).
5. «8 pt, anche le righe vuote ricevono lo spazio», the compounding case: the gap becomes one line
   plus twice the spacing.
6. «H5 e H6: prima» beside «H5 e H6: come spedito», with H4 above each for scale.

The page shows the scenes in both themes, through the gallery's own toggle.

**The gallery entry.** One `Screen` case, `.pageTypography`, appended at the end of the enum, and
its `Page` in the existing `switch`. Nothing else in `MockupGalleryView.swift` moves. Run
`tuist generate --no-open` after adding the file.

### Task 2 — Tester: the page's wiring against the shipped rule (R-08)
Owner: tester
Files: Tests/PageTypographyMockupTests.swift
Tests: PageTypographyMockupTests.swift, MockupGalleryLayoutTests.swift, ProseParagraphSpacingTests.swift
Signatures:
- PageTypographyMockup.attributedSample — `static func attributedSample(spacing: CGFloat, spacesHeadings: Bool, spacesBlankLines: Bool, sixthHeading: SixthHeading, theme: Theme) -> NSAttributedString`
- MockupGalleryView.Screen.pageTypography — `case pageTypography`
Red: no

Pure tests against `Theme.emergency` plus one bundled theme loaded through `ThemeEngine`, in the
`PraticaRailTokenTests` shape.

- **The shipped scene.** `attributedSample(spacing: 8, spacesHeadings: true, spacesBlankLines:
  false, sixthHeading: .shipped, …)` carries `paragraphSpacing == 8` on exactly the paragraphs
  `ProseParagraphSpacing.paragraphRanges` returns.
  - It carries 0 on the list item, the task line, the quote, the code block and every blank line.
  - The line-height multiple equals `ProseTypography.paragraphStyle(theme)`'s.
- **`spacesHeadings: false`.** The H4, H5 and H6 lines carry 0, and every prose line is unchanged.
- **`spacesBlankLines: true`.** The blank line between two prose paragraphs carries the spacing.
- **`.before`.**
  - The H6 run's font has the bold trait and H5's face at H6's size.
  - Its colour is `theme.color(.textPrimary)`.
- **`.shipped`.** H6 has no bold trait and is in `.textSecondary`.
- **The gallery entry.** `MockupGalleryView.Screen.allCases` contains `.pageTypography`, titled
  «Pagina: paragrafi e titoli».

`MockupGalleryLayoutTests` and session 2's `ProseParagraphSpacingTests` run unchanged and stay
green.

This task is `Red: no`. It runs after Task 1, which already wrote the bodies: a mockup has no
behaviour to drive red first.

## Risks and HITL gates

- **G1, the comparison (HITL).** Stefano opens the DesignGallery on this checkout's Debug build,
  found by `WorkspacePath` as CLAUDE.md shows, never the newest DerivedData folder. He answers four
  questions:
  1. 8 or 12 pt;
  2. whether heading lines are spaced;
  3. whether blank lines are spaced;
  4. whether the shipped H6 stays.

  Recommended: keep what shipped, with blank lines not spaced. The answers feed
  `docs/plans/note-workflow-n1.md` Tasks 3 and 4, which are empty when everything is confirmed.
- **The mockup no longer comes first.** Our Decision («mockups ship first») cannot hold for N1:
  #897's chain builds the token without one. This page is a review of shipped values.
  - Its only possible code consequence is a token value or a rule clause.
  - If Stefano finds R-22's hand check of 8 pt and H6 (#897's Task 8) enough, this PR can be
    dropped. R-08's mockup obligation is then waived by his decision, not by this plan.
- **Points, not em.** The token is stored in points, so it does not follow a prose size changed in
  Personalizzato. Making it relative needs `DesignTokenDocument` to read units, which no SPEC item
  asks for.
- **Merge friction.**
  - Every milestone's mockup PR appends a `Screen` case to the same enum and `switch`. Append at
    the end; a conflict is resolved by keeping both cases.
  - N2's restyle may move `ProseParagraphSpacing`'s call site. This page calls the rule, not the
    call site.
- **HITL.** Commit, push, the PR and the merge are human gates. This PR changes no test outside
  its new file.

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield

CHECK-CMD CANDIDATE: ! swiftlint lint --quiet 2>&1 | grep -E "/Sources/.+: error: "
