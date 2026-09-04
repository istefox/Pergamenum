# SPEC — Editor page typography: closing the distance to NotePlan (Phase A)

**Topic slug:** editor-page-typography-noteplan

**Date:** 2026-09-04
**Chain:** concept-to-code, standard path. Target ADR: 0030 (supersedes nothing; amends SPEC
§5 and §14 of `docs/20260811_Pergamenum_SpecApp.md`).
**Source roadmap:** `docs/20260904_Editor_Page_Roadmap.md` — this SPEC is its Phase A only.
Phases B (inline code, fenced code and frontmatter concealment) and C (click-reveal, mouse
selection, TextKit 2 viewport measurements) are out of scope and documented there for later chains.

## 1. Objective

Make the note editor read as a page rather than a code buffer, without touching the concealment
mechanism ADR-0018/0028/0029 built. The roadmap established, with sources, that NotePlan's editor
is the same hybrid model Pergamenum already ships (markers hidden, revealed at the caret,
paragraph-local refresh); what still separates the two is typography and page geometry. Phase A
closes exactly that: the prose face, the heading scale, the line height, and a readable-width
column, all expressed as design tokens, plus the user's ability to pick a prose font and size
from Impostazioni the way NotePlan's Preferences allow.

A second, equally binding goal: the editor currently violates CLAUDE.md's rule that a view using a
font without going through a token does not pass review. Nine `NSFont.` sites across five editor
files bypass `Theme.nsFont(_:)`. Phase A removes all of them.

## 2. Decisions already taken (interview of 2026-09-04)

| Question | Decision |
|---|---|
| Editor model | Hybrid NotePlan-style concealment, unchanged. No marker-free WYSIWYG. |
| Prose face | **Avenir Next**, 16pt, bold and italic from the same family; fallback to the system face when the family is not installed. NotePlan's own default theme values (verified on a public copy of its built-in "Toothpaste" theme: `AvenirNext-Regular` 16, `AvenirNext-Bold` 24 for H1). |
| Tokens | Two **new** tokens, `font.prose` and `font.proseTitle`. `font.body` / `font.title` stay SF 13 / 22 for the interface (11 UI call sites depend on them). `font.mono` stays for code, fences and frontmatter. |
| Heading scale | Interpolation between `font.proseTitle` and `font.prose`, the rule `CardTextAttributes.headingSize` already implements: `size = max(prose + 1, proseTitle − (level − 1) × 2)`. No per-level tokens, no ratio scale. |
| Shared rules | Extract the three typographic rules (body face, heading face per level, italic with fallback) into one pure helper used by both `MarkdownAttributedText` and `CardTextAttributes`. The two tables stay separate for what genuinely differs (clickable links, colours, embeds). |
| Line height | `lineHeight` multiple from the `font.prose` token (1.4), applied through `NSParagraphStyle`. **No** `paragraphSpacing`: in markdown the blank line is the paragraph separator and extra spacing would double it. |
| Readable width | Spacing token `spacing.readable` = 720pt, text column centred when the view is wider, full width below. A `VaultSettings` toggle, on by default, turns the cap off. Applies wherever `NoteTextView` is drawn (Editor, Diario, Oggi). |
| Workspace cards | `.text` cards move to the prose tokens too, consistent with ADR-0028's "same rendering on both surfaces". Card size scaling is unchanged. |
| Font picker | Impostazioni → Editor gains a prose font family and size picker, persisted through the existing `ThemeCustomization` mechanism (a DTCG file in `.pergamenum/themes/`), extended from colours-only to colours plus the two prose typography tokens. |

## 3. Scope

**In scope**

1. `EditorTypography` (name indicative; the ADR decides): a pure, Foundation/AppKit-only helper
   exposing `proseFont(theme)`, `proseBoldFont(theme)`, `proseItalicAttributes(theme)`,
   `headingFont(level, theme)`, `monoFont(theme)`, `paragraphStyle(theme)` (line-height only).
   Lives where `CardTextAttributes` and `MarkdownAttributedText` can both reach it; it is the
   **only** file under `Sources/Features/Editor` and `Sources/Features/Workspace` allowed to
   name `NSFont.`.
2. `MarkdownAttributedText.attributes(for:theme:links:)` reads body, bold, italic, heading and
   code faces from the helper. `.bold` becomes the prose family's bold face, never
   `monospacedSystemFont`. `.italic` uses the real italic face where the family has one, the
   existing `.obliqueness: 0.2` otherwise. `.code`, `.codeBlock`, `.codeToken`, `.frontmatter`
   keep `font.mono`.
3. The remaining eight hardcoded `NSFont.` sites (`TableGridView+Rendering` ×3,
   `TableGridView+CellCommit` ×1, `EditorDecorationDelegate` ×1,
   `EditorDecorationDelegate+ListRendering` ×1, `MarkdownAttributedText` ×3 counted above)
   route through the helper. A table cell reads in the same face and size as the paragraph
   above it.
4. `CardTextAttributes` switches `bodyFont`/`headingSize`/`italicAttributes` to the helper and
   from `.body`/`.title` to `.prose`/`.proseTitle`. `Tests/CardTextViewTests.swift` is updated,
   not weakened: the assertions "bold is not monospaced" and "italic is oblique or italic" stay.
5. Token file changes in **both** `Resources/Themes/pergamenum-light.json` and
   `pergamenum-dark.json`: `font.prose` (`fontFamily: "Avenir Next"`, 16, 400, lineHeight 1.4),
   `font.proseTitle` (`fontFamily: "Avenir Next"`, 24, 700, lineHeight 1.2),
   `spacing.readable` (720). `TokenKeys.swift` gains `FontToken.prose`, `.proseTitle` and the
   spacing key; `Theme.emergency` gains matching fallbacks so a theme file missing them still
   loads.
6. `TypographyValue.Family` gains a **named family** case (e.g. `.named(String)`), parsed from any
   `fontFamily` string that is not `system`/`monospace`/`serif`. `Theme.nsFont(_:)` resolves it
   with `NSFont(name:size:)` on the family name (AppKit accepts a family name there, verified)
   and derives bold/italic through `withSymbolicTraits`, never through a weight trait, which
   silently returns the regular face on a named family (ADR-0030 §D3); falls back to
   `NSFont.systemFont` when the face is absent. `Theme.font(_:)` (SwiftUI) gets the same
   resolution through `Font.custom(_:size:)` with the same fallback.
7. Readable width in `NoteTextView`: the text container's width is capped at
   `spacing.readable` and centred inside the scroll view when the view is wider; below the cap
   the text tracks the view width exactly as today. The mechanism is the horizontal
   `textContainerInset`, `max(24, (viewWidth − 720) / 2)`, so 24 stays the floor and no frame is
   ever set (ADR-0030 §D6); the vertical inset 20 is unchanged. Governed by
   a new `VaultSettings.readableWidth: Bool` (default `true`), decoded with a fallback like
   `hidesMarkup`, and applied live when the setting changes.
8. Impostazioni → Editor: a "Larghezza di lettura" toggle beside the existing "Nascondi la
   sintassi" switch, and a "Carattere della nota" group with a font-family picker (system font
   list via `NSFontManager.availableFontFamilies`, plus "Sistema") and a size stepper/picker
   (12…24). Choosing writes `font.prose` and `font.proseTitle` overrides into the
   `personalizzato.json` theme through `ThemeCustomization`, whose `Draft` gains a
   `fonts: [FontToken: TypographyValue]` map beside `colors`. Title size follows body size by
   the fixed ratio 24/16 unless the theme file says otherwise. "Ripristina" removes the override
   like a colour reset does.
9. ADR-0030 and the SPEC amendments to `docs/20260811_Pergamenum_SpecApp.md` §5 (editor
   typography, readable width, font picker), §14 (the *Temi* row: user-customisable tokens now
   include prose typography, not colours only) and §11.3 (the token-examples list). The
   «Live preview completa» row of §14 is **not** touched: ADR-0029 already retired it, and the
   earlier premise that this chain amends it was wrong (ADR-0030 §D14). `PROJECT_BRIEF.md`
   status line if the brief tracks editor milestones.

**Out of scope**

- Concealing fence backticks, inline-code backticks or the frontmatter block (Phase B).
- Click-reveal caret re-mapping, mouse-selection probes, TextKit 2 viewport measurements
  (Phase C).
- Any change to `EditorDecorationDelegate`'s substitution or enumeration hooks, to
  `HiddenMarker`, `MarkupReveal`, `VaultSettings.hidesMarkup`.
- Per-level heading tokens, a modular ratio scale, `paragraphSpacing`.
- Changing `font.body`, `font.title`, `font.heading`, `font.caption` values or any UI text.
- A per-theme font choice UI beyond the single prose override (no per-token font editing).
- Print/export surfaces (`MarkdownBlocksView`, `NoteExporter`): they keep their own fonts.
- Obsidian file compatibility: nothing here writes to a note.

## 4. Stack and constraints

- Swift 6 strict concurrency, SwiftUI + AppKit (`NSViewRepresentable`), macOS 26 SDK, Tuist 4,
  Swift Testing. No new dependency.
- `EditorDecorationDelegate` is not `@MainActor` and cannot read `Theme`; any font it needs
  continues to be handed in as a value from the view (existing pattern). The helper must
  therefore be usable both from the main actor (views) and as pre-resolved `NSFont` values.
- `perg`/`pergamenum-mcp` compile `Sources/Core/**` and `Sources/Connector/**`; nothing in this
  feature may put AppKit into `Sources/Core`. `EditorTypography` lives under `Sources/Features`
  or `Sources/DesignSystem`, never `Sources/Core`.
- Binding design rule: no hardcoded colour or font in a view. This feature is its enforcement in
  the editor.
- `.claude/protected-interfaces` is not touched: `IndexCache.schemaVersion` and
  `VaultAPI.LintFinding` are unrelated.
- The unit suite runs through `.claude/test-cmd` (`-only-testing:PergamenumTests`), the UI suite
  by hand through `scripts/uitests.sh` before merge (CLAUDE.md).

## 5. Architecture

```
Resources/Themes/*.json  ──DTCG──▶ DesignTokenDocument ──▶ Theme(fonts: [FontToken: TypographyValue])
                                                             │  nsFont(.prose) / nsFont(.proseTitle) / nsFont(.mono)
                                                             ▼
                                   EditorTypography (pure rules: body, bold, italic, heading(level), paragraphStyle)
                                     │                                   │
                                     ▼                                   ▼
                     MarkdownAttributedText (note editor)      CardTextAttributes (Workspace .text card)
                     TableGridView (+Rendering, +CellCommit)   
                     EditorDecorationDelegate (+ListRendering) ← fonts handed in as values
                                     │
                                     ▼
                     NoteTextView: textContainer width = min(viewWidth, spacing.readable) if settings.readableWidth
```

`ThemeCustomization.Draft { appearance, colors, fonts }` → `personalizzato.json` (only overridden
tokens written) → `ThemeEngine` merges over the bundled theme exactly as colours are merged today.

## 6. Data model

- `FontToken`: `+ prose = "font.prose"`, `+ proseTitle = "font.proseTitle"`.
- `SpacingToken` (or the existing spacing enum): `+ readable = "spacing.readable"`.
- `TypographyValue.Family`: `system | monospace | serif | named(String)`; `rawValue` round-trips
  the family name so `ThemeCustomization` can write it back verbatim.
- `VaultSettings`: `+ readableWidth: Bool = true`, Codable with `decodeIfPresent` fallback.
- `ThemeCustomization.Draft`: `+ fonts: [FontToken: TypographyValue]`; `isEmpty` is
  `colors.isEmpty && fonts.isEmpty`.
- No index field, no frontmatter key, no `.canvas` property, no migration.

## 7. UI flows

1. **Open a note.** Body in Avenir Next 16, headings 24/22/20/18/17/17 semibold from the same
   family, code spans and fences in `font.mono`, line height 1.4. On a window wider than 720 +
   insets the text column is centred at 720; narrower windows behave as today.
2. **Toggle "Larghezza di lettura" off.** The column returns to full width immediately, no
   reopen. Persisted in `.pergamenum/settings.json` like `hidesMarkup`.
3. **Pick a font in Impostazioni → Editor.** A `Picker` lists "Sistema" plus the installed
   families; a size control offers 12…24. On change the editor re-styles live; the choice is
   written to `.pergamenum/themes/personalizzato.json` as `font.prose` / `font.proseTitle`
   overrides. "Ripristina carattere" deletes the two overrides; if no colour override remains,
   the file is removed as it is today for colours.
4. **Theme names a missing family.** `Theme.nsFont(.prose)` returns the system face at the
   token's size and weight; nothing is logged as an error, nothing crashes; Impostazioni shows
   the family name the file declares.
5. **Workspace `.text` card.** Same family and heading scale as the editor; card-level size
   scaling multiplies the prose size as it multiplies `.body` today.
6. **`hidesMarkup` off.** Typography is unaffected: markers are drawn, in the prose face.

## 8. Edge cases

- **List glyph alignment.** `ListMarkerRendering.paragraphStyle(level:font:)` builds its own
  `NSParagraphStyle`; the line-height multiple must be carried into it (or composed onto it),
  otherwise list paragraphs would be tighter than prose paragraphs.
- **Transclusion `reservedHeight`.** `NoteTextView+Transclusion` sets `paragraphSpacing` on the
  source line's style to make room for the rendition. The prose paragraph style must not
  overwrite it; the reserved height is recomputed with the larger body face.
- **`EmbedAttachment` / `TableAttachment` line fragments.** Both compute against the paragraph's
  font. A 16pt body changes fragment heights; the D16 probes of ADR-0029 (table fragment
  height, nested first responder) are re-run by hand.
- **Heading fold badge and `HorizontalRuleFragment`.** Both draw with a font handed in; they take
  the prose or heading face from the helper, not a literal.
- **Avenir Next has no monospace.** Code stays `font.mono`; a `.code` span inside a heading keeps
  the mono face at the heading's size, as today.
- **Named family without a bold or italic face** (a user picks a single-weight font). Bold falls
  back to `NSFontManager.convert(_:toHaveTrait:)` result or the regular face; italic falls back
  to `.obliqueness`. Never a crash, never an empty attribute dictionary.
- **Two theme files disagree.** Light and dark must both declare the new tokens; a unit test
  loads both bundled themes and asserts the three keys resolve.
- **`personalizzato.json` written by an older build** (no `fonts`). `ThemeCustomization.load`
  returns `fonts: [:]`; nothing else changes.
- **Readable width with the Outline pane / Diario split.** The cap is on the text container, so a
  narrow editor column is unaffected; only a column wider than 720 + insets centres.
- **Find bar highlight rectangles** come from layout, so they follow the new metrics without
  code; noted for the hand-check.
- **`Theme.font(_:)` for SwiftUI** with a named family uses `Font.custom`; if the family is
  absent SwiftUI silently substitutes — the fallback must be explicit (`NSFont` probe first) so
  SwiftUI and AppKit agree on the face.

## 9. Acceptance and Definition of Done

Build green, SwiftLint 0 errors, unit suite green, `scripts/uitests.sh` green before merge, then
the criteria below.

## Success criteria

- [ ] R-01 — `grep -rn "NSFont\." Sources/Features/Editor Sources/Features/Workspace` returns no font *construction* outside the allow-list of ADR-0030 §D8 (`EditorDecorationDelegate.collapsedFont`, ADR-0018's concealment non-font; the `NSFont.Weight` type name in `TableGridView+Rendering`; the `NSFont.systemFontSize` last-resort constant in `EditorDecorationDelegate+ListRendering`; `NSFont` type annotations and default property values); every former construction site, `FoldedHeadingFragment` included, reads through the shared typography helper under `Sources/DesignSystem`.
- [ ] R-02 — `MarkdownAttributedText` styles body, bold, italic and headings from `Theme.nsFont(.prose)` / `.proseTitle`; `.bold` is never `monospacedSystemFont`; `.code`, `.codeBlock`, `.codeToken` and `.frontmatter` use `Theme.nsFont(.mono)`.
- [ ] R-03 — Heading sizes follow `max(prose + 1, proseTitle − (level − 1) × 2)` for levels 1…6, computed from the tokens; changing `font.proseTitle` in the theme JSON changes every level with no code change.
- [ ] R-04 — Both bundled themes declare `font.prose` (Avenir Next, 16, 400, lineHeight 1.4), `font.proseTitle` (Avenir Next, 24, 700) and `spacing.readable` (720), and `Theme.emergency` resolves all three when a theme file omits them.
- [ ] R-05 — `TypographyValue.Family` parses an arbitrary `fontFamily` string as a named family; `Theme.nsFont(_:)` returns that family's regular face when installed and `NSFont.systemFont` at the same size and weight when it is not.
- [ ] R-06 — Italic uses the family's real italic face when one exists, `.obliqueness: 0.2` otherwise; bold uses the family's bold face, falling back to the regular face rather than to a monospaced one.
- [ ] R-07 — Prose paragraphs carry a paragraph style whose line-height multiple equals the `font.prose` token's `lineHeight`; no `paragraphSpacing` is added to plain paragraphs; list paragraphs keep their marker indentation and gain the same line height.
- [ ] R-08 — `CardTextAttributes` reads its body, heading and italic faces from the shared helper on the prose tokens; `CardTextViewTests` still asserts bold is non-monospaced and italic is oblique or italic.
- [ ] R-09 — With `VaultSettings.readableWidth == true` and a text view wider than `spacing.readable` plus insets, the text container width equals `spacing.readable` and the column is horizontally centred; with the setting off, or a narrower view, the container tracks the view width as before.
- [ ] R-10 — `VaultSettings.readableWidth` defaults to `true`, decodes with a fallback when absent from an older `settings.json`, and toggling it in Impostazioni → Editor re-lays out an open note without reopening it.
- [ ] R-11 — Impostazioni → Editor offers a prose font-family picker ("Sistema" plus installed families) and a size control in 12…24; a change writes `font.prose` and `font.proseTitle` overrides to `.pergamenum/themes/personalizzato.json` through `ThemeCustomization`, and the open editor re-styles live.
- [ ] R-12 — `ThemeCustomization.Draft` gains `fonts: [FontToken: TypographyValue]`; `load` reads a file without a `fonts` section as an empty map; "Ripristina" removes the two font overrides and removes the file when no override of any kind remains.
- [ ] R-13 — A table cell (`TableGridView`) renders in the prose face at the prose size, and `TableRenderingTests` covers it.
- [ ] R-14 — Hand-check on a throwaway vault, recorded in the manifest notes: embed and table line-fragment heights, list glyph baseline, transclusion reserved height, heading fold badge and horizontal rule, find-bar highlight, in light and dark, with the body at 16pt and with a missing family forced through the theme file. (no-test: visual layout probes that need a real window, same class as ADR-0029 §D16)
- [ ] R-15 — ADR-0030 written under `docs/adr/` with the decisions of §2, and SPEC §5, §14 (*Temi* row) and §11.3 of `docs/20260811_Pergamenum_SpecApp.md` amended in place with the literal text of ADR-0030 §D14. (no-test: documentation obligation, verified by reading the diff)
- [ ] R-16 — `scripts/uitests.sh` run before the merge to `main`; `DesignAndReadingUITests` and `NoteImageUITests` stay green without any assertion being relaxed. (no-test: the UI suite runs outside test-cmd by CLAUDE.md rule and is recorded in the manifest, not asserted by a unit test)
