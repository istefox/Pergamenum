<!-- step5-brief: plan=/Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-04-editor-page-typography-noteplan.md tasks=7 lines=386-436 -->
# Step 5 Batch Brief -- 2026-09-04-editor-page-typography-noteplan.md -- tasks 7-7

## Task text (verbatim, plan lines 386-436)

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

## File map (from Budget: declarations, tasks 7-7)

- (none declared -- no task in this range carries a parseable Budget:)

No parseable Budget: for task(s): 7 (absent is not zero -- consult the task text above)

## Excluded tasks (not in this batch)

- Task 1 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-04-editor-page-typography-noteplan.md
- Task 2 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-04-editor-page-typography-noteplan.md
- Task 3 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-04-editor-page-typography-noteplan.md
- Task 4 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-04-editor-page-typography-noteplan.md
- Task 5 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-04-editor-page-typography-noteplan.md
- Task 6 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-04-editor-page-typography-noteplan.md
- Task 8 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-04-editor-page-typography-noteplan.md
- Task 9 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-04-editor-page-typography-noteplan.md

Full plan: /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-04-editor-page-typography-noteplan.md

## Context documents (open only for the reason stated -- not read unconditionally)

- ADR: /Users/stefer/Developer/Pergamenum/docs/adr/0030-editor-page-typography-noteplan.md -- R-11/R-12 settings write path and file format decisions
- SPEC: /Users/stefer/Developer/Pergamenum/SPEC.md -- requirement IDs for this batch's tests
- CLAUDE.md: /Users/stefer/Developer/Pergamenum/CLAUDE.md -- personalizzato.json write conventions
