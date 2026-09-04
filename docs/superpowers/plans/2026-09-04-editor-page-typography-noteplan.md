# Plan — The note is a page: editor typography, readable width, prose font picker (Phase A)

- **ADR:** `docs/adr/0030-editor-page-typography-noteplan.md` (relocated by the orchestrator
  on 2026-09-04 from the architect's `docs/architecture/` write scope; filing note removed)
- **SPEC:** `/Users/stefer/Developer/Pergamenum/SPEC.md` (R-01 … R-16)
- **Roadmap:** `docs/20260904_Editor_Page_Roadmap.md` — **Phase A only.** Phases B (inline
  code, fence and frontmatter concealment) and C (click-reveal, mouse selection, viewport
  measurement) are out of scope and must not be started here.
- **BRAINSTORM / UX blueprint:** none exist for this chain. The four decisions of 2026-09-04
  are in the roadmap's own table and in SPEC §2.
- **Branch base:** `main`. ADR-0029 is merged, so `TableGridView`, `TableGridStore`,
  `EditorDecorationDelegate+TableRendering`, `FoldedHeadingFragment` and `HorizontalRuleFragment`
  all exist.
- **Style:** TDD. Red precondition first on every task, per this repo's last seven chains.

---

## Before anything: what the SPEC says that the source does not

Verified against the working tree on 2026-09-04, by grep, at the line. Do not design or code
against the left column.

| # | SPEC says | Source says | Where |
|---|---|---|---|
| C1 | «Nine `NSFont.` sites across five editor files» | **Nine font-constructing sites across six files.** `grep -rn "NSFont\." Sources/Features/Editor Sources/Features/Workspace` returns **16 lines**: 9 editor constructions, 4 card constructions, 1 type name (`NSFont.Weight`), 1 constant (`NSFont.systemFontSize`), 2 doc comments. `TableGridView+Rendering` has **2** font sites, not 3 — `:179` is a `NSFont.Weight` parameter type | ADR §Context table |
| C2 | R-01: the grep «returns hits only in the shared typography helper file» | **Not satisfiable, and one part of it must not be.** `EditorDecorationDelegate.collapsedFont` is the 0.01pt concealment font — ADR-0018's mechanism, deliberately theme-independent. R-01 is read through **ADR §D8's allow-list** (collapse font, `NSFont.Weight`, `NSFont.systemFontSize`, default property values). The helper lives in `Sources/DesignSystem`, outside the grep's two directories entirely | `EditorDecorationDelegate.swift:153`; roadmap's own wording: *"zero hits outside a deliberately named allow-list"* |
| C3 | R-01/§3.3: the missing site list | **`FoldedHeadingFragment.swift:31` (`NSFont.systemFont(ofSize: 10, weight: .regular)`) is a tenth site neither the SPEC nor the roadmap names.** It is in scope: SPEC §8 says the fold badge "takes the prose or heading face from the helper, not a literal" | `FoldedHeadingFragment.swift:31` |
| C4 | §3.7: «Insets (`24 × 20`) are unchanged» | **The horizontal inset *is* the readable-width mechanism** (ADR §D6): `inset.width = max(24, (viewWidth − spacing.readable) / 2)`. 24 becomes its floor. Capping `textContainer.size` instead would need `widthTracksTextView = false` and then a frame to centre — the `setFrameSize` path `growToFitTheText`'s header spends nine lines warning about | `NoteTextView.swift:125`; `NoteTextView+Coordinator.swift:473-478` |
| C5 | §6: «`TypographyValue.Family` gains a named family case» | `Family` is a **`String`-raw-value enum**. Swift forbids a raw value alongside an associated-value case, so it needs a **hand-written `RawRepresentable`** with a non-failable `init(rawValue:)`. That also removes `DesignTokenDocument.swift:162`'s `?? .system`, which silently discards every unrecognised `fontFamily` today | `TokenValue.swift:16-21`, `DesignTokenDocument.swift:162` |
| C6 | §6/§8: `Theme.nsFont` resolves a named family «on the family's PostScript names» | **Not needed, measured.** `NSFont(name: "Avenir Next", size: 16)` → `AvenirNext-Regular`: the constructor takes a family name. **And the weight trait silently fails**: `descriptor.addingAttributes([.traits: [.weight: .bold]])` → `AvenirNext-Regular`. Bold must come from `withSymbolicTraits(.bold)` (→ `AvenirNext-Bold`, verified) | ADR §Context probe; ADR §D3 |
| C7 | §8: «`Theme.font(_:)` for SwiftUI … `Font.custom`» | Correct, and it needs the **resolved PostScript name** (`resolved.fontName`), not the family name, after an `NSFont` probe — or SwiftUI substitutes silently and the two frameworks draw different faces from one token | ADR §D3 |
| C8 | §8: «`ListMarkerRendering.paragraphStyle(level:font:)` … the line-height multiple must be carried into it» | Confirmed, and it is one of **three** sites that overwrite `.paragraphStyle` wholesale. The other two are `NoteTextView+Transclusion.swift:57-64` (`paragraphSpacing = reservedHeight`) and `CardTextView.swift:384-388` (card alignment). Grepped: there are no others | ADR §D5 |
| C9 | §2/§3.9: this chain amends SPEC §14's *«source mode con stile è sufficiente»* rationale | **That row was already retired by ADR-0029 on 2026-09-02** and its cell says so. The §14 row ADR-0030 actually amends is ***Temi***. Literal replacement text in ADR §D14 | `docs/20260811_Pergamenum_SpecApp.md:476-493` |
| C10 | §3.8: a toggle «beside the existing "Nascondi la sintassi" switch» | The switch is labelled **«Nascondi i marcatori mentre scrivi»** and carries `accessibilityIdentifier("settings-hides-markup")`. Copy the shape, not the SPEC's label | `EditorSettings.swift:19-24` |
| — | §5: `spacing.readable` is a spacing token | Free to add, with one consequence: `DesignGalleryView.swift:153` draws a `Rectangle` of `theme.spacing(token)` **squared** for every `SpacingToken.allCases` — a 720×720 swatch in an `HStack`. The ramp iterates an explicit five-token list instead (ADR §D7) | `DesignGalleryView.swift:150-160` |
| — | §5: `Theme.emergency` gains matching fallbacks | Free, and **enforced already**: `Tests/DesignSystemTests.swift:95` asserts `theme.inheritedTokens.isEmpty` for both bundled themes, so a `TokenKeys` case added without both JSON files goes red on its own | `DesignSystemTests.swift:95` |

**Four constraints the SPEC could not know** (ADR §Context):

1. **`EditorDecorationDelegate` cannot be `@MainActor`** (Swift 6 refuses both conformances,
   `:25-26`) and cannot read a `Theme`. Fonts arrive as pushed values, the way
   `badgeColor`/`badgeBackground`/`handleColor`/`ruleColor` already do inside
   `applyStyling`/`applyFolding`.
2. **`Sources/DesignSystem/**` is *not* in `sharedSources`** (`Project.swift:72-97`), so AppKit
   there is safe. `Sources/Core/**` **is**, and an `import AppKit` there breaks both connector
   builds.
3. **`setFrameSize` on the editor's text view re-enters SwiftUI's update pass** and once cost
   the Diario everything typed into it (`NoteTextView+Coordinator.swift:473-478`). Readable
   width touches no frame.
4. **`updateNSView` does not run on a window resize**, so the readable-width recompute needs an
   `NSViewFrameDidChange` observation on the scroll view's content view.

---

## Contract changes and their already-grepped call sites

Every row was grepped **before** this plan was written. The coder does not go looking for
these; they are listed, and they are updated in the same task that changes the contract.
**Run the full unit suite after each task, not just the touched file's tests** — a contract
change breaks tests in files that never mention it.

| Contract | Change | Call sites that break or go stale |
|---|---|---|
| `TypographyValue.Family` | `String` enum → hand-written `RawRepresentable` with `case named(String)` | **Compile errors (exhaustive switches, no `default`):** `Theme.swift:54` (`nsFont`), `Theme.swift:287-293` (`asDesign`, used by `font(_:)` at `:43`). **Behaviour change, no compile error:** `DesignTokenDocument.swift:162` loses its `?? .system`. **Tests:** grep returns **no** test constructing a `TypographyValue` or a `Family` — the round-trip coverage is new in Task 1. |
| `FontToken` | `+ prose`, `+ proseTitle` | **No compile error** (nothing switches exhaustively on it). **Goes red on its own:** `Tests/DesignSystemTests.swift:95` (`inheritedTokens.isEmpty`) until both bundled JSONs and `Theme.emergency` declare them. **Cosmetic:** `DesignGalleryView.swift:15` prints `FontToken.allCases.count`. |
| `SpacingToken` | `+ readable` | Same `DesignSystemTests:95` guard. **Layout break:** `DesignGalleryView.swift:153` iterates `allCases` and would draw a 720×720 swatch — switch to an explicit five-token list (ADR §D7). `:16` prints the count. |
| `Theme.nsFont(_:)` / `Theme.font(_:)` | a `.named` arm each | 4 `nsFont(.body)` + 2 `nsFont(.title)` + 7 `font(.body)` call sites, all **unaffected** (they resolve `system`/`monospace` families as before). Listed so nobody "fixes" them: `CapturePanelView:123`, `TaskComposer:41`, `DiaryEntrySheet:81`/`:165`, `NewNoteComposer:87`, `TaskDatePanels:58`/`:235`, `GoToDateSheet:31`, `MarkdownBlocksView:183`/`:229`, `MarkdownBlocksView+Table:17`, `CardTextAttributes:149`/`:154`. **Only the last two move** (Task 5). |
| `MarkdownAttributedText.base(theme:)` | `.font` becomes prose; gains `.paragraphStyle` | **Callers:** `MarkdownAttributedText.attributed(_:theme:links:)` (`:29`) and `NoteTextView+Coordinator.applyStyling`. **Tests that build fixture storage with an explicit monospaced 13 and therefore keep passing while no longer exercising the shipped face** — leave them alone, do not "modernise": `MarkupHidingTests:43`, `:788`, `TableRenderingTests:50`, `TransclusionLayoutTests:78`, `EmbedAttachmentProbeTests:202`. |
| `ListMarkerRendering.paragraphStyle(level:font:)` | `+ basedOn: NSParagraphStyle? = nil` | **Only caller:** `EditorDecorationDelegate+ListRendering.swift:64-69`. Defaulted, so nothing else breaks. **Tests:** grep `ListMarkerRendering` in `Tests/` before editing; assertions on `firstLineHeadIndent`/`headIndent` stay valid because the indent arithmetic is untouched — but their **expected values change** if the fixture font changes, so keep the fixtures' fonts as they are and add a new case for the composition. |
| `EditorDecorationDelegate` | `+ proseFont`, `+ badgeFont` (`nonisolated(unsafe) var`, system-face defaults) | No existing caller breaks — defaults cover every test that builds the delegate directly (`MarkupHidingTests`, `EmbedDrawingTests`, `TableRenderingTests`, `CardConcealmentTests`). The Coordinator assigns them in `applyStyling` beside `handleColor` (`:330`) and `ruleColor` (`:334`). |
| `CardTextAttributes` | `bodyFont` → `.prose`; `headingSize`/`italicAttributes` → helper | **Comments go stale and are rewritten in the same task:** `CardTextAttributes.swift:9`, `:17` (they quote the note editor's monospaced bold, which stops existing). **Test comment goes stale, assertion stays valid:** `Tests/CardTextViewTests.swift:26` and `:40-42` compare against `NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)` — after this change the note editor's bold is not monospaced either, so the *comparison target* is no longer "the note editor's bold". **Do not weaken:** "bold is not monospaced" and "italic is oblique or italic" both stay. |
| `VaultSettings` | `+ readableWidth: Bool = true` | **One construction site in the whole repo:** `VaultSettings.swift:127` (`static let default`). The memberwise `init` at `:208-236` gains a defaulted parameter, so no other call site exists to break. `decodeIfPresent` fallback at `:186`'s shape. **Settings JSON round-trip tests:** grep `VaultSettings` in `Tests/` and add the absent-key case there rather than in a new file. |
| `NoteTextView` | `+ var readableWidth = false` | **Three construction sites, each gains one argument:** `EditorColumn+Text.swift:47`, `DiaryView.swift:87`, `TodayView.swift:191` — the same three that already pass `hidesMarkup:`. |
| `ThemeCustomization.Draft` | `+ fonts: [FontToken: TypographyValue]`; `isEmpty` becomes `colors.isEmpty && fonts.isEmpty` | **Compile errors (memberwise init):** `ThemeEngine.swift:136` and `:154` construct `Draft(appearance:colors:)`. **Reader/writer:** `ThemeCustomization.load` (`:38-54`), `object(from:)` (`:86-108`). **Tests:** grep returns **no** test touching `ThemeCustomization` — the round-trip coverage is new in Task 7. |
| `DesignSystemSettings` footer | *«Tipografia, spaziature, raggi e ombre restano definiti dal file del tema»* | Half untrue once the picker ships. Rewritten in Task 7, not Task 8 — Impostazioni must not contradict itself between two tabs in the same commit. |

**Protected interfaces — none touched, checked one by one** (`.claude/protected-interfaces`):
`IndexCache.schemaVersion` (no index field, no migration — this is a rendering-layer feature),
`VaultAPI.LintFinding` (no connector change of any kind),
`CompletingTextView+Pasteboard.swift` (readable width is an inset on the text view, not a paste
path; no `CompletingTextView` file is edited by this chain). `interface-check.sh` must stay
silent for the whole chain. **If a task looks like it needs to edit a `CompletingTextView+*.swift`
file, stop and report.**

---

## Conventions binding on every task

- **The tester owns the interface, the coder owns the body.** Swift is compiled: a batch that
  leaves the target unable to build produces no red tests at all, only a build error. Every new
  type's *declaration* (enum cases, stored properties, function signatures returning a stub) is
  written in the **tester's** task together with the tests that call them. The coder fills in
  bodies.
- **`tuist generate --no-open` after every task that adds a file under `Sources/`.**
- **Swift Testing (`@Test`/`#expect`) for all new tests.** Never XCTest, except inside
  `UITests/`, which is an XCTest bundle and stays one.
- **Every new test file's header comment cites both `ADR-0030` and this plan's basename**
  (`2026-09-04-editor-page-typography-noteplan`).
- **One principal type per file** (`~/.claude/rules/swift.md`).
- **`Sources/Core/**` is a `sharedSources` glob (`Project.swift:73`)**: nothing in this chain
  goes there. `ProseTypography.swift` lives in `Sources/DesignSystem/`, which is **not** a
  shared glob, so its `import AppKit` is safe (ADR §D1).
- **No mechanism from ADR-0018 / ADR-0028 / ADR-0029 is reopened.** No new `HiddenMarker.Kind`,
  no new `MarkdownStyler.Span`, no change to `textContentStorage(_:textParagraphWith:)`'s
  substitution, to `textContentManager(_:shouldEnumerate:options:)`, to `MarkupReveal`, to
  `TableAttachment`/`TableGridStore`'s identity rule, or to `collapsedFont`. If a task looks
  like it needs one, **stop and report**.
- **`CardTextView.swift` is not edited** (ADR-0029 §D17, ADR-0030 §D10). The card takes the
  prose faces through `CardTextAttributes`; the line height deliberately stops at the editor.
- **The unit test command is `.claude/test-cmd` exactly as it stands** —
  `-only-testing:PergamenumTests`. Do not widen it: the UI tests in there terminate the app the
  person at the keyboard is using, and it runs at the end of every turn through the `Stop` hook
  (CLAUDE.md).
- **`scripts/uitests.sh` runs once, in Task 9, before merge** — never per task, and with **no
  argument** (an argument *replaces* the selection rather than adding to it).
- **No new harness script.** This repo has none of that kind; `scripts/` holds
  release / uitests / mcp-smoke / install-cli and stays as it is. Coverage for this chain is
  `.claude/test-cmd` plus `scripts/uitests.sh` plus the per-task test files below. Any throwaway
  helper for a hand check must be **Bash 3.2-clean** — no `mapfile`, no associative arrays, no
  `${x^^}` (macOS ships bash 3.2).
- **`weakening-scan.sh` reports every Swift Testing test as `zero-assertion-test`** because it
  treats `#expect` as a comment. Expected, systematically wrong for this stack, advisory
  (CLAUDE.md).
- **The secret scanner's `assigned-secret` heuristic fires on design-token lines** (`token` +
  `:`/`=` + 16 identifier chars). Expected on this chain more than most. Read each hit before
  dismissing it.
- **No hardcoded colour and — after this chain — no hardcoded font in any view.**

---

## Phase 1 — the token layer (no editor file is touched yet)

### Task 1 — a named font family is a token value, and three new tokens exist (R-04, R-05)

- Budget: `Sources/DesignSystem/TokenValue.swift`, `Sources/DesignSystem/TokenKeys.swift`,
  `Sources/DesignSystem/Theme.swift`, `Sources/DesignSystem/DesignTokenDocument.swift`,
  `Sources/Features/DesignGallery/DesignGalleryView.swift`,
  `Resources/Themes/pergamenum-light.json`, `Resources/Themes/pergamenum-dark.json`,
  `Tests/TypographyResolutionTests.swift` (new), `Tests/DesignSystemTests.swift` (~280 lines)

**Tester writes the declarations and the tests together.** In `TokenValue.swift`:
`Family` loses its `String` raw type and gains `case named(String)` plus a hand-written
`var rawValue: String` and a **non-failable** `init(rawValue: String)`. In `TokenKeys.swift`:
`FontToken.prose = "font.prose"`, `.proseTitle = "font.proseTitle"`,
`SpacingToken.readable = "spacing.readable"`.

**Red first**, in `Tests/TypographyResolutionTests.swift`:

- `Family(rawValue: "system"/"monospace"/"serif")` gives the three known cases; anything else
  gives `.named(thatString)`; `rawValue` round-trips every case verbatim, `.named` included
  (this is the assertion that protects the hand-written conformance);
- a DTCG document declaring `{"fontFamily": "Avenir Next", "fontSize": 16, "fontWeight": 400,
  "lineHeight": 1.4}` parses to `.named("Avenir Next")` — **today it parses to `.system`**, and
  that is the behaviour this test changes;
- `theme.nsFont(.prose)` on a theme naming an installed family returns a font whose
  `familyName` is that family (use **`Avenir Next`**: verified present in
  `/System/Library/Fonts/Avenir Next.ttc`, a system-protected face, not an optional download);
- a token with `fontWeight: 700` on a named family returns the family's **bold** face
  (`AvenirNext-Bold`), and the test asserts `symbolicTraits.contains(.bold)` **and**
  `fontName != regular.fontName` — the weight-trait route returns the regular face silently
  (ADR §Context probe) and only this second assertion catches it;
- a token naming a family that is **not installed** ("Totally Not A Font") returns
  `NSFont.systemFont(ofSize:weight:)` at the token's own size and weight — not nil, not a crash,
  nothing logged as an error (SPEC §7.4);
- `theme.font(.prose)` (SwiftUI) is built from the **same resolved face**: assert the helper
  that computes the name returns `resolved.fontName`, not the family string. If `Font` cannot be
  inspected, assert the internal resolver rather than the `Font` value — **do not** assert
  nothing.

In `Tests/DesignSystemTests.swift`, extend the existing bundled-theme test (`:95`):
both bundled themes resolve `font.prose`, `font.proseTitle` and `spacing.readable` without
falling back — `inheritedTokens.isEmpty` already asserts this, so the new work is adding the
three keys to both JSON files and to `Theme.emergency` and watching that test go from red to
green. Add one explicit assertion that `theme.spacing(.readable) == 720` in both.

**Coder** fills `Family`'s conformance, the `.named` arm of `Theme.nsFont(_:)` (family-name
constructor, `>= 600` → `withSymbolicTraits(.bold)`, `nil` → system face at the token's weight),
the `.named` arm of `Theme.font(_:)`/`asDesign`, removes `DesignTokenDocument.swift:162`'s
`?? .system`, adds the three tokens to both theme files and to `Theme.emergency`, and switches
`DesignGalleryView.swift:153`'s ramp from `SpacingToken.allCases` to the explicit five-step list
(ADR §D7) — **a 720×720 swatch in an `HStack` is what happens otherwise**.

### Task 2 — `ProseTypography`, the one place allowed to name a face (R-03, R-06, R-07)

- Budget: `Sources/DesignSystem/ProseTypography.swift` (new),
  `Tests/ProseTypographyTests.swift` (new) (~260 lines)

**Tester** declares the enum and its six signatures (ADR §D1) with stub bodies, and writes the
red tests:

- `prose(theme)` is `theme.nsFont(.prose)`; `proseBold(theme)` is the same family's bold face
  and is **never monospaced** — assert `!symbolicTraits.contains(.monoSpace)` and
  `familyName == prose(theme).familyName` (R-06's "falls back to the regular face rather than to
  a monospaced one");
- on a family with **no bold face**, `proseBold` returns the regular face, never nil, never a
  system substitute of a different family. Build the theme for this from a document naming a
  single-weight family installed on the machine, or — if none can be relied on — assert the
  documented fallback path directly and say so in the test's comment;
- `proseItalicAttributes(theme)` carries `.font` with `.italic` in its symbolic traits where the
  family has an italic face, and `[.obliqueness: 0.2]` where it does not. This is
  `CardTextAttributes.italicAttributes`'s existing rule moved, so its behaviour must not change
  — `Tests/CardTextViewTests.swift`'s italic assertion is the regression guard (R-06);
- `heading(level:theme:)` for levels 1…6 with prose 16 / proseTitle 24 gives
  **24, 22, 20, 18, 17, 17**; with `font.proseTitle` raised to 30 the six levels change with no
  code change (R-03) — build a second `Theme` from a document with a different `proseTitle` and
  assert the whole array, which is the assertion that makes R-03 real;
- `heading` never drops below `prose + 1` (the floor), and level 0 or 99 is clamped rather than
  crashing;
- `paragraphStyle(theme)` has `lineHeightMultiple == 1.4` (the `font.prose` token's
  `lineHeight`) and **`paragraphSpacing == 0`** (R-07: no spacing on plain paragraphs);
- `paragraphStyle(theme, basedOn: aStyleWithParagraphSpacing44AndFirstLineHeadIndent24)` keeps
  **both** of those and adds the multiple — this is the composition assertion that Tasks 3 and 4
  depend on, and it is the one that would silently regress the transclusion and list paths;
- `mono(theme)` is `theme.nsFont(.mono)`, and `mono(theme, size: 10)` is the same family at 10.

**Coder** fills the six bodies. No file outside `Sources/DesignSystem/` is touched in this task.

---

## Phase 2 — the editor reads the tokens

### Task 3 — `MarkdownAttributedText` styles from the tokens, not from literals (R-01, R-02, R-07)

- Budget: `Sources/Features/Editor/MarkdownAttributedText.swift`,
  `Sources/Features/Editor/NoteTextView+Transclusion.swift`,
  `Tests/MarkdownAttributedTextTests.swift` (new or existing — grep first),
  `Tests/TransclusionLayoutTests.swift` (~240 lines)

**Tester** writes red tests against `MarkdownAttributedText.base(theme:)` and
`attributes(for:theme:links:)`:

- `base(theme:)`'s `.font` is `ProseTypography.prose(theme)` — asserted by `familyName` and
  `pointSize`, and asserted **not** to be monospaced (R-02's `.bold` clause has a body twin:
  today `:18` is `monospacedSystemFont`);
- `base(theme:)` carries a `.paragraphStyle` whose `lineHeightMultiple` is the `font.prose`
  token's `lineHeight` and whose `paragraphSpacing` is 0 (R-07);
- `.heading(level:)` for 1…6 returns `ProseTypography.heading(level:theme:)` — same six numbers
  as Task 2, asserted here through the public entry point so the two cannot drift;
- `.bold` returns the prose family's bold face and **is never monospaced** (R-02, the explicit
  clause);
- `.italic` returns a real italic face for Avenir Next and `.obliqueness` for a family without
  one (R-06);
- `.code`, `.codeBlock`, `.codeToken` and `.frontmatter` still resolve to `theme.nsFont(.mono)`
  — assert `symbolicTraits.contains(.monoSpace)` for each, because this is the clause most
  likely to be broken by a careless global replace (R-02);
- a `.code` span **inside a heading** keeps the mono face at the heading's size (SPEC §8);
- `attributed(_:theme:)` over a note with a heading, bold, italic, a fence and a link produces
  attributes consistent with the four assertions above, with no `NSFont` in the result whose
  family is neither the prose family nor the mono family.

In `Tests/TransclusionLayoutTests.swift`, add the composition regression: the source line of a
transclusion carries **both** `paragraphSpacing == rendition.reservedHeight` **and** the prose
`lineHeightMultiple`. **Leave the existing fixture's font alone** (`:78` builds storage with an
explicit monospaced 13) — the new case builds its own storage through
`MarkdownAttributedText.base(theme:)`.

**Coder** rewrites the three `NSFont.` sites in `MarkdownAttributedText` through
`ProseTypography`, adds `.paragraphStyle` to `base(theme:)`, and changes
`NoteTextView+Transclusion.reserveSpace` (`:57-64`) to build its style as a **mutable copy of
the style already on the line** rather than a fresh one (ADR §D5). Nothing else in that file
changes; `reservedHeight`'s own computation is untouched and grows with the larger face by
itself.

### Task 4 — the remaining editor faces, the fold badge and the list line height (R-01, R-07, R-13)

- Budget: `Sources/Features/Editor/EditorDecorationDelegate.swift`,
  `Sources/Features/Editor/EditorDecorationDelegate+ListRendering.swift`,
  `Sources/Features/Editor/ListMarkerRendering.swift`,
  `Sources/Features/Editor/FoldedHeadingFragment.swift`,
  `Sources/Features/Editor/TableGridView.swift`,
  `Sources/Features/Editor/TableGridView+Rendering.swift`,
  `Sources/Features/Editor/TableGridView+CellCommit.swift`,
  `Sources/Features/Editor/NoteTextView+Coordinator.swift`,
  `Tests/TableRenderingTests.swift`, `Tests/MarkupHidingTests.swift` (~300 lines)

**Tester** declares `EditorDecorationDelegate.proseFont` / `.badgeFont`
(`nonisolated(unsafe) var`, system-face defaults), `FoldedHeadingFragment.badgeFont`, and
`ListMarkerRendering.paragraphStyle(level:font:basedOn:)`, then writes the red tests:

- **the list composition (R-07):** a list paragraph whose storage already carries a paragraph
  style with `lineHeightMultiple` 1.4 keeps that multiple *and* gains
  `firstLineHeadIndent`/`headIndent` from `ListMarkerRendering` — assert all three on one
  displayed paragraph. Without `basedOn:` the multiple is dropped, which is the defect this
  assertion exists for;
- the indent arithmetic is **unchanged**: `firstLineHeadIndent == font.pointSize * 1.5 * depth`
  and `headIndent == firstLineHeadIndent + pointSize * 0.75`, for the same font the existing
  tests use. If an existing `ListMarkerRendering` assertion needs its expected number changed,
  the composition changed the arithmetic and is wrong;
- **the displayed paragraph's length still equals the stored paragraph's** for a list line
  (ADR-0028 §D2's invariant — restated here because this task touches the list branch);
- **R-13:** a `TableGridView` built from a fixture table draws its cells in the prose family at
  the prose size, its header cells in the same family's bold, and measures its column widths
  with the **same** face it draws with. Assert on `NSTextField.font` of a header and a body cell
  after `update(with:theme:)`, by `familyName` and `pointSize`;
- the fold badge's font comes from `badgeFont` and not from a literal 10pt system face.

**Coder** routes every remaining site through `ProseTypography`:
`TableGridView+Rendering.makeCell` (`:76`) and `width(of:weight:)` (`:182`),
`TableGridView+CellCommit.makeGroupLabel` (`:180`, size from `font.caption`),
`FoldedHeadingFragment.badge` (`:31`), and adds
`decorations.proseFont` / `decorations.badgeFont` assignments to `applyStyling` beside
`handleColor` (`:330`) and `ruleColor` (`:334`).

**Then run the R-01 acceptance grep** and confirm the result is exactly ADR §D8's allow-list:

```sh
grep -rn "NSFont\." Sources/Features/Editor Sources/Features/Workspace
```

Expected survivors and nothing else: `EditorDecorationDelegate.swift`'s `collapsedFont`,
`TableGridView+Rendering.swift`'s `NSFont.Weight` parameter type,
`EditorDecorationDelegate+ListRendering.swift`'s `NSFont.systemFontSize` fallback, and the
`NSFont` type annotations / default property values on the delegate, the fragment and the grid.
**A hit anywhere else is a missed site — report it, do not widen the allow-list.**

### Task 5 — the Workspace card moves to the prose tokens (R-08)

- Budget: `Sources/Features/Workspace/CardTextAttributes.swift`,
  `Tests/CardTextViewTests.swift` (~140 lines)

**Tester** writes the red tests before the switch:

- `CardTextAttributes.base(theme:)`'s font is `ProseTypography.prose(theme)` — i.e. `.prose`,
  not `.body`;
- `.heading(level:)` sizes match `ProseTypography.heading(level:theme:)` exactly for 1…6 (the
  card and the editor must not compute two scales);
- `.bold` comes from the helper and is still **not monospaced** — `Tests/CardTextViewTests.swift`
  already asserts this at `:33` and `:41-42`; **the assertions stay, unweakened**, and only the
  comparison's stale comment is rewritten (after this chain the note editor's bold is not
  monospaced either, so `:26`'s framing is what changes, never the `#expect`);
- `.italic` is still oblique-or-italic (the existing assertion, kept verbatim);
- `.code` and `.codeBlock` still resolve to a monospaced face, at the **prose** size.

**Coder** switches `bodyFont` to `.prose`, replaces `headingSize` and `italicAttributes` with
helper calls, routes the four `NSFont.` sites (`:99`, `:107`, `:114`, `:121`) through
`ProseTypography`, and rewrites the two stale doc comments at `:9` and `:17`.
**`CardTextView.swift` is not edited** — the line height deliberately stops at the editor
(ADR §D10), and the card's own span switch is ADR-0029 §D17's seam.

---

## Phase 3 — the page geometry and the choice

### Task 6 — the text column has a readable width, and a setting turns it off (R-09, R-10)

- Budget: `Sources/Vault/VaultSettings.swift`, `Sources/Features/Editor/NoteTextView.swift`,
  `Sources/Features/Editor/NoteTextView+Coordinator.swift`,
  `Sources/Features/Editor/EditorColumn+Text.swift`,
  `Sources/Features/Diary/DiaryView.swift`, `Sources/Features/Today/TodayView.swift`,
  `Sources/Features/Settings/EditorSettings.swift`,
  `Tests/ReadableWidthTests.swift` (new), plus the existing `VaultSettings` decode test
  (grep for it) (~260 lines)

**Tester** declares `VaultSettings.readableWidth: Bool` (default `true`, `decodeIfPresent`
fallback in the same style as `hidesMarkup` at `:186`), `NoteTextView.readableWidth = false`,
and a **pure** function on the Coordinator —
`static func horizontalInset(viewWidth: CGFloat, cap: CGFloat, minimum: CGFloat, isOn: Bool) -> CGFloat`
— which is where all of R-09's coverage lives, because the geometry itself needs a window and
this arithmetic does not. Red tests:

- `isOn == true`, `viewWidth` 1200, cap 720, minimum 24 → **240** (so the container is exactly
  720 wide and centred);
- `isOn == true`, `viewWidth` 700 (narrower than the cap) → **24**, i.e. today's behaviour;
- `isOn == true`, `viewWidth` exactly `720 + 48` → **24** — the boundary, asserted explicitly
  because an off-by-one here is a jumping column;
- `isOn == false`, any width → **24**;
- a degenerate `viewWidth` of 0 or a negative → **24**, never a negative inset;
- `VaultSettings.default.readableWidth == true`; a `settings.json` **without** the key decodes
  to `true` (R-10's fallback), and one with `false` decodes to `false`.

**Coder** wires it: the Coordinator observes `NSView.frameDidChangeNotification` on the scroll
view's content view (`postsFrameChangedNotifications = true`, set in `makeNSView`, observation
torn down with the Coordinator) and assigns `textView.textContainerInset` from the pure function
above; `updateNSView` calls the same assignment so a settings change re-lays out an open note
without reopening it (R-10). **Nothing sets a frame** — see ADR §D6 and
`NoteTextView+Coordinator.swift:473-478`. The three surfaces each pass
`readableWidth: vault.settings.readableWidth` beside their existing `hidesMarkup:`
(`EditorColumn+Text.swift:47`, `DiaryView.swift:87`, `TodayView.swift:191`).

`EditorSettings` gains a **«Larghezza di lettura»** `Toggle` with
`accessibilityIdentifier("settings-readable-width")`, beside the existing
`settings-hides-markup` switch (which is labelled *«Nascondi i marcatori mentre scrivi»*, not
what the SPEC calls it — C10), plus one `.themedText(.caption, …)` line of explanation in the
same voice as the ones already there.

### Task 7 — Impostazioni chooses the note's face, and the choice is a file in the vault (R-11, R-12)

- Budget: `Sources/DesignSystem/ThemeCustomization.swift`, `Sources/DesignSystem/ThemeEngine.swift`,
  `Sources/Features/Settings/EditorSettings.swift`,
  `Sources/Features/Settings/DesignSystemSettings.swift`,
  `Tests/ThemeCustomizationTests.swift` (new) (~340 lines)

**Tester** declares `Draft.fonts: [FontToken: TypographyValue]` (and `isEmpty` as
`colors.isEmpty && fonts.isEmpty`), `ThemeEngine.setCustomFont(_:to:)` and
`clearCustomFonts()`, then writes the red tests against a temporary directory:

- `write` then `load` round-trips a `fonts` entry byte-for-byte: family, size, weight,
  lineHeight — including a **named** family with a space in it (`Avenir Next`), which is the
  case the `rawValue` round trip of Task 1 exists to protect;
- a file written with the same draft twice is **byte-identical** (the sorted-keys/pretty
  discipline `object(from:)`'s comment already states, extended to a second token type);
- `load` on a file with **no `font` section** returns `fonts: [:]` and the colours unchanged
  (R-12, "written by an older build");
- `load` on a file with a `font` section and **no colours** returns the fonts and
  `colors: [:]`;
- `isEmpty` is false with fonts only, false with colours only, true with neither;
- `clearCustomFonts()` on a draft with no colours left **removes the file**, matching what
  `clearCustomColor` already does through `resetCustomization()` (R-12);
- `setCustomFont` with **no vault open** sets `customizationProblem` and writes nothing — the
  same guard `setCustomColor` has;
- a written `font.prose` override actually reaches `ThemeEngine.current.nsFont(.prose)` after
  `loadUserThemes`, which is the assertion that proves the whole path rather than the file
  format.

**Coder** fills `object(from:)`'s typography branch, `load`'s dictionary branch, the two
`ThemeEngine` methods (mirroring `setCustomColor`/`clearCustomColor` including the
write-then-select ordering its header explains), and builds the UI in `EditorSettings`:

- a **«Carattere della nota»** group with a family `Picker` — `"Sistema"` plus
  `NSFontManager.shared.availableFontFamilies` (187 on this machine; read **once**, stored, the
  way `EditorSettings` already reads `NSSpellChecker.shared.availableLanguages`) — and a size
  control over 12…24;
- `accessibilityIdentifier`s (`settings-prose-font-family`, `settings-prose-font-size`,
  `settings-prose-font-reset`), never a lookup by label — prose grows (CLAUDE.md);
- choosing writes **both** `font.prose` and `font.proseTitle`, the title size following the body
  at the fixed 24/16 ratio (ADR §D9), and the open editor re-styles live because
  `ThemeEngine.current` changing is what `updateNSView` already watches;
- **«Ripristina carattere»** removes both overrides and, with no colour override left, removes
  the file;
- rewrite `DesignSystemSettings`' footer sentence *«Tipografia, spaziature, raggi e ombre
  restano definiti dal file del tema»*, which stops being true in this same commit.

---

## Phase 4 — the record and the suite

### Task 8 — the ADR is filed and the SPEC is amended (R-15)

- Budget: `docs/adr/0030-editor-page-typography-noteplan.md` (relocated),
  `docs/20260811_Pergamenum_SpecApp.md`, `CLAUDE.md`, `PROJECT_BRIEF.md` (~140 lines)

- ~~Relocate the ADR to `docs/adr/`~~ — already done by the orchestrator on 2026-09-04
  (`docs/adr/0030-editor-page-typography-noteplan.md`, filing note removed). Nothing to do here.
- **Apply the three SPEC amendments verbatim from ADR §D14**: §5 (three new bullets after the
  GFM-table bullet), §14 (the *Temi* row replaced), §11.3 (the token-examples list extended).
  *This is the only task that edits `docs/20260811_Pergamenum_SpecApp.md`; nothing earlier may.*
- **Do not touch §14's «Live preview completa» row** — ADR-0029 already retired it, and SPEC.md
  §2's claim that this chain amends it is a stale premise (C9).
- Add **ADR-0030** to `CLAUDE.md`'s **Chain decision index** and a *"Decisions from the editor
  page typography chain (ADR-0030)"* section, matching the eleven already there. It must name at
  minimum: the two new tokens and why `font.body` did not move; `ProseTypography` living in
  `Sources/DesignSystem` and why never in `Sources/Core`; the delegate receiving fonts as pushed
  values; the readable width being an **inset**, never a frame; and ADR §D8's allow-list, so the
  next reader does not "finish the job" by routing `collapsedFont` through a token.
- Update `PROJECT_BRIEF.md`'s Status with the phase and the R-14 probe results from Task 9.

### Task 9 — the hand check and the UI suite (R-14, R-16)

- Budget: `PROJECT_BRIEF.md`, manifest notes (no source change) (~60 lines)

**R-14 — hand check on a throwaway vault**, in light **and** dark, with the body at 16pt and
then with a theme file forced to name a missing family. Launch a Debug build with
`ls -dt .../Pergamenum-*/Build/Products/Debug/Pergamenum.app | head -1` (**`-t` matters**:
alphabetical order hands back a stale build) and `-recentVaults '("/path")'` (**the plist array
form**; a bare path leaves `stringArray(forKey:)` nil). Record each result in the manifest
notes:

1. an image/PDF **embed**'s line-fragment height and the text under it;
2. a **table grid**'s fragment height at 16pt cells and the paragraph after it (ADR-0029 §D16
   probe 3's twin, re-run because the number changed even though the mechanism did not);
3. **nested first responder** in a table cell: click, Tab, Shift-Tab, Escape (ADR-0029 §D16
   probe 2, re-run for the same reason);
4. a **list glyph**'s baseline against its own text at the new line height, at three nesting
   levels;
5. a **transclusion**'s reserved height with the larger body face;
6. the **heading fold badge** and a **horizontal rule**;
7. the **find bar**'s highlight rectangles (they come from layout, so they should follow with no
   code — confirm, do not assume);
8. the **readable width** at a window wider and narrower than 720 + 48, and the toggle flipped
   with a note open (no reopen);
9. the **font picker**: pick a family, pick 20pt, confirm the editor re-styles live and
   `.pergamenum/themes/personalizzato.json` holds both overrides; then "Ripristina".

**R-16 — run `scripts/uitests.sh` with no arguments** before the merge to `main`. An argument
*replaces* the selection rather than adding to it. Kill stale instances first — a run started
with one alive has produced 18 failures that were not defects — and read the per-test seconds
the script prints: **60.2 s names the launch timeout, not a broken feature**.
`DesignAndReadingUITests` and `NoteImageUITests` assert by `accessibilityIdentifier` and should
stay green; **no assertion may be relaxed to make them pass**. If one goes red, report it with
its timing rather than editing it.

---

## TEST-CMD CANDIDATE

```
TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -derivedDataPath "/Users/stefer/Developer/Pergamenum/.build/DerivedData" -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield
```

This is `.claude/test-cmd` unchanged — **no change is needed for this chain**. The UI suite is
deliberately not in it (CLAUDE.md: it runs at the end of every turn through the `Stop` hook, and
`XCUIApplication().launch()` terminates the app the person at the keyboard is using).
`scripts/uitests.sh` runs once, in Task 9.

No external dependency: this feature calls no third-party API, no cloud console, no consent flow
and no externally provisioned resource. Avenir Next is a system-protected font already present
at `/System/Library/Fonts/Avenir Next.ttc`, not a download — and a missing family degrades to
the system face by design (ADR §D3), so even that is not a dependency. Nothing to declare.
