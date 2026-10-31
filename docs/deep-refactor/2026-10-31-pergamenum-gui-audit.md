# Pergamenum — GUI and colour audit (step 3 of 4)

Method: design review only (detector not applicable, native platform). Impeccable `critique`,
Operate mode, run on the source and the theme tokens; the app was **not rendered** for this pass,
so every visual judgement below is read from tokens and view code, and the proposal carries a
hand-check list (§7). Date 2026-10-31, tree `023c8d87`. Input: the step-1 surface inventory and
contrast tables, `Resources/Themes/pergamenum-{light,dark}.json`, `DESIGN.md`, web research on
armocromia (sources in §8).

## 0. Summary

The design system is in better shape than most: one token file per theme, warm neutrals, a
single restrained accent, two themes treated as first class, no hardcoded colour in a view (the
step-1 audit found one `NSColor.secondaryLabelColor`, PG-262). The visual identity is already an
**autumn** palette in armocromia terms: warm undertone, medium value, soft intensity. What
breaks it is the semantic layer: categories, the calendar reds and the blue family are bright,
cool and saturated (OKLCH chroma 0.15–0.21 against an accent of 0.11), so they read as stickers
on parchment. And 22 light / 12 dark text pairs fail WCAG AA, mostly the tertiary grey.

The proposal keeps every neutral and the accent where they are, and moves the semantic colours
into the same season: rust, brick, ochre, olive, sage, petrol, plum. Result, measured on 104
foreground/background pairs per theme:

| | Light now | Light proposed | Dark now | Dark proposed |
|---|---|---|---|---|
| Pairs under WCAG threshold | 22 | **0** | 12 | **0** |
| Max semantic chroma (OKLCH) | 0.208 | 0.150 | 0.181 | 0.125 |
| Category separation, min ΔE OKLab | 0.168 | 0.104 | 0.148 | 0.103 |
| Same, simulated deuteranopia | 0.030 | 0.045 | 0.029 | 0.047 |

The one cost is visible in the table: softer categories are closer to each other for normal
vision (still well above the ~0.02 just-noticeable difference), in exchange for better
separation for colour-blind users and a coherent palette. Categories always carry their name, so
colour stays a redundant cue.

## 1. Armocromia, translated to an interface

Armocromia (seasonal colour analysis, popularised in Italy by Rossella Migliaccio) classifies a
palette on four axes: **sottotono** (warm, cool, neutral), **valore** (light to dark),
**intensità** (bright/clear to soft/muted) and **contrasto** (difference in value between the
elements). The four seasons are the combinations: Primavera warm-light-bright, Estate
cool-light-soft, Autunno warm-deep-soft, Inverno cool-deep-bright; twelve sub-seasons refine
them. The underlying three dimensions are hue, value and chroma, the same three a perceptual
colour space measures. The theory is about people's colouring and its scientific validation is
weak; what transfers to an interface is its one useful rule: **every colour in a palette shares
the undertone and the intensity band, and varies in value and hue within them**.

Mapped to OKLCH (perceptually uniform: equal L steps look equal):

| Armocromia axis | OKLCH measure | Pergamenum light (autunno morbido) | Pergamenum dark (autunno profondo) |
|---|---|---|---|
| Sottotono | hue of the neutrals, and hue range of the accents | neutrals H 70–88 (warm); accents H 30–90 plus olive, petrol, plum muted toward warm | same hues |
| Valore | L | paper L 0.94–0.99, ink L 0.22, semantic text L 0.48–0.53 | ground L 0.19–0.29, ink L 0.95, semantic text L 0.74–0.78 |
| Intensità | C | ceiling C 0.15, most semantics 0.07–0.12, accent 0.11 | ceiling C 0.125 |
| Contrasto | WCAG ratio between layers | text ≥ 4.5:1 on every background, ≥ 7:1 for primary text on tinted surfaces | same |

Why autumn: the parchment ground, the cinnamon accent `#9A5B1F` and the honey dark accent
`#E0A96D` already sit there (H 58–68, C ≈ 0.10). The proposal does not change season, it makes
the whole palette belong to the one the app already chose. Autumn's own "cool" colours (petrol,
plum, olive) give enough hue range for categories and code without leaving the season.

## 2. Diagnosis of the current palette

- **[fact]** Neutrals and accent are coherent: hue 60–92, chroma ≤ 0.11 in both themes.
- **[fact]** Off-season, light: `category.blue` `#1F6FEB` C 0.202 H 260, `category.pink`
  `#DB3F6F` C 0.194, `calendar.holiday` `#D62828` C 0.208, `task.overdue` `#B3261E` C 0.178;
  the "blue family" (`task.scheduled`, `code.type`, `callout.note`, `rail.sent`,
  `surface.sent`, `sticky.blue`) at H 243–260 is the only cool cluster. `category.grey`
  `#6E7378` is the one cool grey among warm ones (H 248).
- **[fact]** Pure white `#FFFFFF` for `background.primary`, `surface.card`, `surface.raised`:
  the Winter white. Autumn's paper is ivory; the change is L −0.01, felt more than seen.
- **[fact]** Contrast: `text.tertiary` = `task.done` = `code.comment` `#9C968B` is 2.43–2.94:1 in
  light and 3.00–3.68:1 in dark, under AA everywhere it is drawn as text; `category.yellow` is
  2.45:1 on white; four semantic colours miss 4.5:1 on `background.tertiary` by a hair.
- **[fact]** Typography: system UI font for chrome, Avenir Next for the note (prose 16, title
  24). One family per role, sound. `font.control.label` is 9 pt semibold and draws text (table
  grid «Riga», «Colonna», `TableGridView+Rendering.swift:28`): below the 10 pt floor the macOS
  HIG uses for the smallest legible text. `font.icon.badge` 7 pt draws only glyphs, acceptable.

## 3. Proposed tokens

Every value was computed from an OKLCH target and checked (script and output in §7). Bold marks a
change. Unchanged on purpose: `text.primary`/`secondary` hue family, both accents (kept exactly),
spacing, radius, shadow and font tokens except `font.control.label` (9 → 10).

| token | light now | light proposed | dark now | dark proposed |
|---|---|---|---|---|
| `background.primary` | `#FFFFFF` | **`#FDFBF7`** | `#1A1917` | **`#1A1815`** |
| `background.secondary` | `#F7F5F1` | **`#F7F3EC`** | `#222120` | **`#22201D`** |
| `background.tertiary` | `#EFEBE4` | **`#F0EBE2`** | `#2C2A27` | **`#2D2A26`** |
| `surface.card` | `#FFFFFF` | **`#FEFDFA`** | `#242320` | **`#25221F`** |
| `surface.raised` | `#FFFFFF` | **`#FFFEFC`** | `#2C2A27` | **`#2E2B27`** |
| `surface.sunken` | `#F2EFE9` | **`#F2EEE6`** | `#141311` | **`#141210`** |
| `surface.received` | `#F1EFEA` | **`#F2EFE8`** | `#2B2A27` | **`#2B2825`** |
| `surface.sent` | `#E7EEF6` | **`#E3F2F2`** | `#22303C` | **`#1A3031`** |
| `surface.entry` | `#FBF2D9` | **`#FBF1D9`** | `#3D3524` | **`#3D3424`** |
| `surface.entryNote` | `#FFF1BF` | **`#FEF1C8`** | `#453911` | **`#463915`** |
| `surface.entryCall` | `#DFF2E3` | **`#E4F2DE`** | `#1D3B2C` | **`#283825`** |
| `rail.received` | `#8F897C` | **`#8D8579`** | `#857F73` | **`#867F74`** |
| `rail.sent` | `#6189B4` | **`#4C8588`** | `#5F8DB8` | **`#589194`** |
| `border.subtle` | `#E5E0D8` | **`#E4DFD6`** | `#34322E` | **`#36322E`** |
| `border.strong` | `#CFC8BC` | **`#CFC8BB`** | `#4A473F` | **`#4C473F`** |
| `text.primary` | `#1C1B18` | **`#1F1B17`** | `#F2EFE9` | **`#F0ECE5`** |
| `text.secondary` | `#6B665D` | **`#696259`** | `#A8A398` | **`#ADA79C`** |
| `text.tertiary` | `#9C968B` | **`#6D675D`** | `#77726A` | **`#9B948B`** |
| `text.inverted` | `#FFFFFF` | **`#FEFDFA`** | `#1A1917` | **`#1A1815`** |
| `accent.primary` | `#9A5B1F` | `#9A5B1F` | `#E0A96D` | `#E0A96D` |
| `accent.muted` | `#F3E7DA` | **`#F3E5D7`** | `#3A2E22` | **`#3A2E21`** |
| `accent.onAccent` | `#FFFFFF` | **`#FEFDFA`** | `#1A1917` | **`#1A1815`** |
| `canvas.background` | `#F2EFE9` | **`#F2EEE6`** | `#141311` | **`#141210`** |
| `canvas.grid` | `#E3DED4` | **`#E3DDD2`** | `#26241F` | **`#25221D`** |
| `canvas.selection` | `#9A5B1F` | `#9A5B1F` | `#E0A96D` | `#E0A96D` |
| `task.open` | `#1C1B18` | **`#1F1B17`** | `#F2EFE9` | **`#F0ECE5`** |
| `task.done` | `#9C968B` | **`#6D675D`** | `#77726A` | **`#9B948B`** |
| `task.scheduled` | `#3B6EA5` | **`#206F78`** | `#8AB4E8` | **`#7ABEC6`** |
| `task.overdue` | `#B3261E` | **`#A23F2C`** | `#F2B8B5` | **`#EA9A7E`** |
| `task.cancelled` | `#9C968B` | **`#6D675D`** | `#77726A` | **`#9B948B`** |
| `calendar.prefestive` | `#C98B84` | **`#AD7F74`** | `#A8837D` | **`#AB897E`** |
| `calendar.festive` | `#B3261E` | **`#A23F2C`** | `#EE9A94` | **`#E99F88`** |
| `calendar.holiday` | `#D62828` | **`#B14328`** | `#FF8A80` | **`#EE8D70`** |
| `code.keyword` | `#7E4B7A` | **`#7D4A6D`** | `#C79BC4` | **`#CF9CBD`** |
| `code.string` | `#4B7A4F` | **`#546C3A`** | `#9CC49B` | **`#A9C18D`** |
| `code.comment` | `#9C968B` | **`#6D675D`** | `#77726A` | **`#9B948B`** |
| `code.number` | `#2F6E6B` | **`#2B7068`** | `#79BDB8` | **`#86C2B6`** |
| `code.type` | `#3B6EA5` | **`#32647F`** | `#8AB4E8` | **`#86B9D3`** |
| `code.inlineBackground` | `#EEE9E1` | **`#F0EAE2`** | `#2B2925` | **`#2B2825`** |
| `highlight` | `#F9E7A1` | **`#FAE6A5`** | `#5C4B1A` | **`#4A3B13`** |
| `quote.bar` | `#958D80` | **`#948B7E`** | `#6A655C` | **`#6E685F`** |
| `callout.note` | `#3B6EA5` | **`#206F78`** | `#8AB4E8` | **`#7ABEC6`** |
| `callout.tip` | `#3F7A45` | **`#4E6E3B`** | `#9CC49B` | **`#A7C28C`** |
| `callout.important` | `#7E4B7A` | **`#7D4A6D`** | `#C79BC4` | **`#CF9CBD`** |
| `callout.warning` | `#94600F` | **`#8E5D11`** | `#E0B060` | **`#DCAF67`** |
| `callout.caution` | `#B3261E` | **`#A23F2C`** | `#F2867E` | **`#E99075`** |
| `sticky.yellow` | `#FBF0C4` | **`#F8EDC4`** | `#4A3F1E` | **`#44391B`** |
| `sticky.green` | `#DFEBD4` | **`#E1EBD2`** | `#2E3D2A` | **`#323C27`** |
| `sticky.blue` | `#D8E5F0` | **`#D6EBEC`** | `#26374A` | **`#213A3D`** |
| `sticky.pink` | `#F6DEE0` | **`#F7DEDA`** | `#4A2E32` | **`#49312E`** |
| `sticky.grey` | `#E8E5DF` | **`#E6E2DC`** | `#33312D` | **`#33302C`** |
| `sticky.orange` | `#F9E3CC` | **`#FAE1CB`** | `#4A3626` | **`#4A3625`** |
| `sticky.purple` | `#E6DDF0` | **`#ECDBEA`** | `#3A2E4A` | **`#412E3F`** |
| `category.yellow` | `#D99A00` | **`#B88722`** | `#F5C542` | **`#F0BF61`** |
| `category.green` | `#2E9E4F` | **`#508B52`** | `#4CC26A` | **`#80BD81`** |
| `category.blue` | `#1F6FEB` | **`#1B6F80`** | `#5A9EFF` | **`#4F9CAE`** |
| `category.pink` | `#DB3F6F` | **`#964267`** | `#FF6B8A` | **`#C46B90`** |
| `category.grey` | `#6E7378` | **`#7F7973`** | `#9AA0A6` | **`#A9A49C`** |

## 4. Design review (Operate mode)

### Design health (Nielsen, 0–4)

| # | Heuristic | Score | Key issue |
|---|---|---|---|
| 1 | Visibility of system status | 3 | two save indicators on the Note pane, three save models (step 2 W-12) |
| 2 | Match with the real world | 4 | Italian domain language, «pratica», «Contenitore», «Diario» |
| 3 | User control and freedom | 3 | four different undo strips (W-13); category delete without confirmation (W-04) |
| 4 | Consistency and standards | 2 | conflict banners, delete verbs, create position, inspector (W-02 to W-06) |
| 5 | Error prevention | 3 | Cmd+Left/Cmd+E shadowing text keys (W-01, W-10) |
| 6 | Recognition rather than recall | 3 | pane shortcuts out of sidebar order (W-09) |
| 7 | Flexibility and efficiency | 4 | full keyboard coverage, rebindable shortcuts, CLI and MCP |
| 8 | Aesthetic and minimalist design | 3 | coherent neutrals; saturated semantic colours and the theme toggle on ten toolbars add noise |
| 9 | Error recovery | 3 | refusals are named and specific; conflict banner order differs by surface |
| 10 | Help and documentation | 3 | three help sheets; no shortcut cheat sheet |
| | **Total** | **31/40** | good, held back by cross-surface consistency |

### Design specificity

Authored, not generic: the parchment ground, the cinnamon accent, Avenir Next for prose and the
timeline lanes of Pratiche are specific to a personal knowledge tool for an Italian professional.
What reads as category default is the semantic layer (GitHub-blue categories, Material reds).

### What works

- **One accent, used for state.** `accent.primary` marks selection, the current item and primary
  actions only; the operate-mode rule is respected.
- **Two real themes.** Dark is not an inversion: surfaces, lanes and stickies are re-tinted.
- **Tokens are the only door.** The binding rule holds in the view code (step 1 found zero
  colour literals outside one fallback).

### Priority issues

- **[P1] Tertiary text below AA in both themes.** Captions, done tasks and code comments are the
  most frequent secondary reading in the app. Fix: §3 values (`#6D675D` light, `#9B948B` dark).
- **[P2] Off-season semantic colours.** They fight the parchment and pull the eye to metadata.
  Fix: §3, one intensity ceiling (C ≤ 0.15 light, ≤ 0.125 dark) written into the token file's
  `$description` so a new token respects it.
- **[P2] No component layer.** Sheet widths (twelve distinct values), paddings 1/2/3/6 and four
  toast/banner shapes are literals (PG-262). The palette lands better once banners, toasts and
  sheet frames are components.
- **[P3] 9 pt control label.** Raise `font.control.label` to 10 pt.
- **[P3] Pure white ground.** Ivory `#FDFBF7` and its neighbours in §3; keep `#FFFFFF` only for
  `text.inverted`/`onAccent` if the hand check prefers it (they are now ivory too, ≥ 4.5:1).

### Minor observations

- `sticky.*` light values sit at L 0.91–0.95 with C ≤ 0.055: in the proposal they become
  butter, sage, mineral teal, clay blush, warm grey, apricot, heather.
- `border.strong` is 1.6–1.9:1 on the ground: fine for decorative hairlines, not enough where a
  border is the only sign of a control's edge (WCAG 1.4.11 asks 3:1). Use it only decoratively.
- The `Themes/` and `themes/` folders under `Resources` are the same folder on a
  case-insensitive volume, listed twice by `ls`; check `Project.swift` names one spelling.

## 5. Component and layout notes (for the roadmap)

From the step-1 non-token tables, grouped:

| Area | Now | Proposal |
|---|---|---|
| Sheet widths | 340, 360, 380, 420, 440, 460, 520, 560, 620, 720, 780, 820 | three tokens: `size.sheet.s` 420, `m` 560, `l` 720 (PG-262 already names "three sheet widths") |
| Micro spacing | literal 1, 2, 3, 6 | add `spacing.xxs` 2 and use `xs` 4 / `s` 8 elsewhere |
| Banners and toasts | conflict ×3, undo strips ×4 | `ConflictBanner` and `UndoToast` components (contract C-07, C-09 of step 2) |
| Toolbar | theme toggle on ten panes | removed (step 2 W-11) |
| Motion | `.easeOut(0.2)` literal (PG-264) | `motion.standard` 0.2 s token, 150–250 ms band |

## 6. Questions to consider

- Should `background.primary` move to ivory, or stay white for the editor only (Craft-like page
  on a warm desk)? The proposal moves it; the contrast holds either way.
- Should categories stay five fixed presets, or should the registry accept any colour and the
  app snap it to the nearest in-season preset?

Questions skipped: the decisions above are for step 4's roadmap, per the one-step-at-a-time rule.

## 7. Verification and hand checks

- Script: `scratchpad/gui/check.py` (OKLCH, WCAG 2.1 relative luminance, Machado 2009
  deuteranopia matrix); 104 pairs per theme: every text and semantic token on four backgrounds
  (4.5:1), code tokens on `code.inlineBackground` and the ground (4.5:1), rails, category dots,
  `calendar.prefestive`, `quote.bar` (3:1), primary text on every tinted surface (7:1),
  secondary text on them (4.5:1), `onAccent` on accent (4.5:1).
- Not verified: the rendered look. Hand check on a Debug build with the proposed JSON copied
  into `.pergamenum/themes/` as a user theme (no code change needed, `ThemeEngine` loads it):
  editor page in both themes, Oggi week with holidays, Pratiche lanes, a board with every sticky,
  the category sidebar.
- Accents are kept at their exact current values; the check above was rerun with them (light `accent.primary` on `background.tertiary` 4.55:1).

- A browser preview of both palettes, before and after, on a sample note, task line, code span,
  callouts, Pratiche lanes, categories and stickies: `2026-10-31-pergamenum-palette-preview.html`
  (an approximation in web fonts; the app check above still applies).

## 8. Sources

- [Rossella Migliaccio, Armocromia](https://rossellamigliaccio.com/en/pages/armocromia)
- [Eroica Fenice, Cos'è l'armocromia](https://www.eroicafenice.com/salotto-culturale/cose-l-armocromia/)
- [My Personal Trainer, Armocromia: test a casa](https://www.my-personaltrainer.it/bellezza/armocromia-test-a-casa-come-farlo-da-sole.html)
- [Sterling Style Academy, 12 seasonal color analysis](https://sterlingstyleacademy.com/feeds/blog/12-seasonal-color-analysis)
- [Curate Your Style, The 12 colour seasons](https://www.curateyourstyle.london/blogs/colour-seasons)
- [Frontend Checklist, OKLCH](https://frontendchecklist.io/rules/css/color-oklch)
