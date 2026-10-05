**Requirement set:** `SPEC.md`

# N5 mockup PR: the page, part two (tokens and DesignGallery)

- SPEC: root `SPEC.md`, Approved 2026-10-04, milestone N5 (issue #890). This PR covers R-35 and
  the mockup half of R-44; R-36 to R-43 are built by `docs/plans/note-workflow-n5.md` after this
  PR's mockups are approved on the Debug build (SPEC §11.1, the SPEC's "Mockups ship first"
  decision).
- ADR: `docs/adr/0087-the-editor-draws-the-remaining-constructs.md` (new, Proposed). This PR
  realises its §D4 (the eight token keys, their thresholds, the derived callout card) and draws
  §D5 to §D11 as pictures. The ADR outcome for this plan is that ADR, shared with the code PR, not a
  second one.
- Base: `48a2d912` (`origin/main`). N5 is built last. **Dependencies, stated per the dispatch:**
  N2's styler rewrite (ADR-0082, plan `docs/plans/note-workflow-n2.md`) and N1's clickable tag and
  date (R-07, ADR-0080) must be on `main` before the **code** PR. This mockup PR depends on neither:
  it touches no editor code. It does touch the same theme files and `TokenKeys.swift` as N1's
  `spacing.paragraph` (R-08), so it is cut from `main` after N1 merges.
- Decisions registered from the SPEC, not reopened: callouts write `note`/`tip`/`important`/
  `warning`/`caution`, read `nota`/`suggerimento`/`importante`/`avviso`/`attenzione` as aliases,
  are labelled in Italian, and any other type draws neutral; clickable dates are `>YYYY-MM-DD`
  tokens only; no GUI tests in N5. The roadmap's Italian token names
  (`color.callout.{nota,…}`) are overruled by the first of these: the keys follow the keywords the
  file holds.
- **Deviation to confirm at the gate:** the dispatch says "DesignGallery only". This PR also adds
  the eight colour tokens (two theme JSONs, `TokenKeys.swift`, `Theme.emergency`) and their test,
  because the gallery draws only through tokens (CLAUDE.md's design-system rule), so a mockup
  without them could not show the colours being approved. No view outside `DesignGallery` changes.

### Task 1 — The eight colour tokens in both themes and the emergency palette (R-35)
Owner: coder
Files:
- Resources/Themes/pergamenum-light.json
- Resources/Themes/pergamenum-dark.json
- Sources/DesignSystem/TokenKeys.swift
- Sources/DesignSystem/Theme.swift
Tests: DesignSystemTests.swift
Signatures:
- ColorToken.codeInlineBackground — case codeInlineBackground = "color.code.inlineBackground"
- ColorToken.highlight — case highlight = "color.highlight"
- ColorToken.quoteBar — case quoteBar = "color.quote.bar"
- ColorToken.calloutNote — case calloutNote = "color.callout.note"
- ColorToken.calloutTip — case calloutTip = "color.callout.tip"
- ColorToken.calloutImportant — case calloutImportant = "color.callout.important"
- ColorToken.calloutWarning — case calloutWarning = "color.callout.warning"
- ColorToken.calloutCaution — case calloutCaution = "color.callout.caution"
Red: no

Add the eight `ColorToken` cases with a comment naming ADR-0087 §D4. The code-inline key goes
beside the five `color.code.*` roles, but outside their "five and not more" comment, because it is
a surface, not a syntax role. Add each key to both bundled theme files under its DTCG group:
`color.code.inlineBackground`, a top-level `color.highlight`, a new `color.quote` group and a new
`color.callout` group. Add each to `Theme.emergency` with the light value. The PG-225 contract is
that `rawColor` force-unwraps the emergency entry, so a key missing there crashes the xctest
process rather than failing a test. `Theme.swift` is already at 415 lines, past the 400 warning
and far from the 1000 error; eight dictionary lines do not justify a split.

Starting values, computed against `color.background.primary` (`#FFFFFF` light, `#1A1917` dark).
They are tuned at the mockup gate, and the thresholds in Task 2 are what binds.

| Key | Light | Dark |
|---|---|---|
| `color.code.inlineBackground` | `#EEE9E1` | `#2B2925` |
| `color.highlight` | `#F9E7A1` | `#5C4B1A` |
| `color.quote.bar` | `#958D80` | `#6A655C` |
| `color.callout.note` | `#3B6EA5` | `#8AB4E8` |
| `color.callout.tip` | `#3F7A45` | `#9CC49B` |
| `color.callout.important` | `#7E4B7A` | `#C79BC4` |
| `color.callout.warning` | `#94600F` | `#E0B060` |
| `color.callout.caution` | `#B3261E` | `#F2867E` |

Measured with WCAG 2 luminance on 2026-10-04:

- light: callout colours 5.15 to 6.62 against white and at least 4.63 against their own card at
  opacity 0.08; quote bar 3.28; secondary text on the inline background 4.72; primary text on the
  highlight 13.92.
- dark: quote bar 3.04; every other pair 5.78 or more.

### Task 2 — Token test: keys, both themes, emergency values, contrast thresholds (R-35)
Owner: tester
Files:
- Tests/NoteConstructTokenTests.swift
- Tests/DesignSystemTests.swift
Tests: NoteConstructTokenTests.swift, DesignSystemTests.swift
Signatures:
- ColorToken.codeInlineBackground — case codeInlineBackground = "color.code.inlineBackground"
- ColorToken.highlight — case highlight = "color.highlight"
- ColorToken.quoteBar — case quoteBar = "color.quote.bar"
- ColorToken.calloutNote — case calloutNote = "color.callout.note"
- ColorToken.calloutTip — case calloutTip = "color.callout.tip"
- ColorToken.calloutImportant — case calloutImportant = "color.callout.important"
- ColorToken.calloutWarning — case calloutWarning = "color.callout.warning"
- ColorToken.calloutCaution — case calloutCaution = "color.callout.caution"
- Theme.rawColor(_:) — func rawColor(_ token: ColorToken) -> RGBA
- Theme.inheritedTokens — let inheritedTokens: [String]
- ThemeEngine.init(defaults:) — init(defaults: UserDefaults)
Red: no

Write a new suite in `PraticaRailTokenTests.swift`'s shape, beside `DesignSystemTests`, which is
past comfortable length. It asserts:

- the eight paths;
- both bundled themes define all eight (none in `inheritedTokens`), opaque, and load with no
  problems;
- `Theme.emergency` resolves each to Task 1's light value;
- ADR-0087 §D4's thresholds in both themes:
  - each callout colour at least 4.5:1 against `color.background.primary` and against itself
    composited at opacity 0.08 over it;
  - `color.quote.bar` at least 3:1 against `color.background.primary`;
  - `color.text.secondary` on `color.code.inlineBackground` at least 4.5:1;
  - `color.text.primary` on `color.highlight` at least 4.5:1;
- the five callout colours are pairwise distinct in each theme.

The 0.08 opacity is the literal ADR-0087 §D4 names. The code PR introduces
`CalloutStyle.backgroundOpacity` and its test pins that constant to the same value. Add the eight
paths to `bundledThemesDefineEveryToken`'s named list, one comment naming ADR-0087.

Not tester-first, on purpose. Declaring the cases before the coder fills `Theme.emergency` would
make the emergency assertions crash the xctest process (PG-225), not fail, and would hide every
other result of the run.

### Task 3 — DesignGallery: three N5 screens for the human gate (R-35, R-44)
Owner: coder
Files:
- Sources/Features/DesignGallery/MockupGalleryView.swift
- Sources/Features/DesignGallery/CalloutMockup.swift
- Sources/Features/DesignGallery/PageConstructsMockup.swift
- Sources/Features/DesignGallery/PageEmbedsMockup.swift
Tests: MockupGalleryLayoutTests.swift
Signatures:
- MockupGalleryView.Screen.callouts — case callouts, Page("Callout", "N5, da approvare", CalloutMockup())
- MockupGalleryView.Screen.constructs — case constructs, Page("Codice, citazioni e chip", "N5, da approvare", PageConstructsMockup())
- MockupGalleryView.Screen.embedsAndTables — case embedsAndTables, Page("Embed, transclusioni e tabelle", "N5, da approvare", PageEmbedsMockup())
- MockupPage — struct MockupPage<Content: View>: View
- MockupScene — struct MockupScene<Content: View>: View
Red: no

Three screens, each a `MockupPage` of `MockupScene`s within `contentWidth` (720) and the row
widths `MockupGalleryView` defines. Every colour, font, spacing and radius comes from a token.
The callout card's tint is the type token at opacity 0.08, the one derived colour ADR-0087 §D4
allows. Each file stays under 250 lines; `CodeBlockMockup.swift` is already 244 and is not
extended. Each screen shows, in light and dark through the gallery's own theme switch:

- **Callout** (`CalloutMockup.swift`):
  - the five types open, each with an icon, the Italian label as title and two body lines;
  - `> [!avviso]-` folded, title row with its chevron only, and the same callout open;
  - a callout whose line names its own title;
  - an unknown type (`> [!faq]`) neutral;
  - a nested quote inside a callout body;
  - the same `[!warning]` title line as a Workspace card shows it, title coloured only (R-38);
  - the slash-menu row «Callout».
- **Codice, citazioni e chip** (`PageConstructsMockup.swift`):
  - a sentence with an inline-code pill, off the caret and with the caret in it (backticks
    showing);
  - `==testo==` highlighted, and `` `a==b==` `` as code;
  - a `swift` fence with its header badge («swift», «12 righe»), a body line, the quiet closing
    line, and the header revealed with the caret on it;
  - the context-menu row «Copia il blocco»;
  - a three-level quote with full-height bars, one paragraph wrapping across two lines;
  - `#client-acme` as a chip (namespace secondary, value accent) and `>2026-10-14 10:30` as a date
    chip.
- **Embed, transclusioni e tabelle** (`PageEmbedsMockup.swift`):
  - an embed placeholder at a written `|480` before its picture;
  - an inline `![[scheda.pdf]]` chip in a sentence;
  - a whole-line `![[contratto.docx]]` chip;
  - a transclusion with its caption «da «Riunione 3 ottobre» › Decisioni» in the source row and the
    body under it, and the same line revealed;
  - a table column's menu open (Allinea a sinistra / al centro / a destra with the current one
    ticked, Ordina A→Z / Z→A), with a right-aligned column.

Add the three `Screen` cases and their `page` lines. N1 to N4's mockup PRs add cases to the same
`case` line of `Screen`; whichever merges second rebases that one line.

**Human gate (HITL):** Stefano approves the three screens on the Debug build, in light and dark,
before `docs/plans/note-workflow-n5.md` starts. The approval fixes the token names and confirms or
retunes Task 1's values, which must still pass Task 2. If the gate changes a value, Task 1 and
Task 2 are amended in this PR, not in the code PR.

## Risks and HITL gates

- **Token names are frozen here.** A rename after the gate is a change to both themes, the
  emergency palette and every consumer the code PR adds. The code PR's plan relies on these eight
  names and on `CalloutStyle.backgroundOpacity` = 0.08.
- **A person's own theme** under `.pergamenum/themes/` inherits the eight new keys from its base
  (`Theme(document:inheriting:)` fills from `.emergency` or the bundled parent), so no vault theme
  breaks. Its `inheritedTokens` lists them until the person sets them, as for every token added
  since M0.
- **Contrast is asserted, not eyeballed**, but only for the pairs Task 2 names. The callout title
  on a Workspace card's sticky colour is not checked: cards colour the title only, and the sticky
  palette varies. Look at it at the gate.
- **Merge order with N1**: N1 adds `spacing.paragraph` to the same three files. Cut this branch
  after N1 merges, or expect a trivial conflict in `TokenKeys.swift` and the theme JSONs.
- HITL: the mockup approval above; commit and push of this branch; the merge. No schema change,
  deletion or deploy.

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield

CHECK-CMD CANDIDATE: NONE
