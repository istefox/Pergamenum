# ADR-0030: The note is a page, and its faces come from the token file

- Status: proposed
- Date: 2026-09-04. Written after reading every file it names, at the line, on the working
  tree at `main`. The font facts in D3 were **measured on this machine** with a compiled
  AppKit probe (`NSFontManager`/`NSFontDescriptor`, macOS 26 / Darwin 25.6) rather than
  recalled; the probe's output is quoted where it contradicts the obvious design.
- **Supersedes nothing.** ADR-0018 §D1/§D2/§D3/§D5/§D7 (substitution at identical length,
  reveal on the caret's paragraph, display-only, the caret rules, the one setting),
  ADR-0028 §D2/§D4 (character-for-character substitution, the ordered list's own digits) and
  ADR-0029 §D4/§D5/§D6/§D7 (the table attachment, the enumeration refusal, the view provider,
  the commit path) are **not reopened**. This ADR changes attribute *values* and one text
  container's width. No delegate hook, no substitution, no enumeration rule, no attachment
  and no commit path is touched.
- **Amends SPEC §5** (adds the typography, readable-width and font-picker bullets),
  **SPEC §14** (the *Temi* row) and, smaller, **SPEC §11.3** (the token list). The literal
  text of all three amendments is in D14. Neither file is edited by this ADR — the plan's
  Task 8 applies it.
- **Amends ADR-0027 §D1** on one point only: `CardTextAttributes.bodyFont` moves from
  `font.body` to `font.prose` and its `.bold` arm stops naming `NSFont.systemFont` directly.
  §D1's actual prize — a card's bold is a real bold and never the note editor's monospaced
  bold — is kept and strengthened, because after this ADR the note editor has no monospaced
  bold either.
- **Amends ADR-0028 §D3** — `ListMarkerRendering.paragraphStyle(level:font:)` gains a base
  style to compose onto, so a list paragraph keeps the prose line height (D5).
- Depends on: **ADR-0001 §D1/§D4** (no AppKit in `Sources/Core`; a resolved theme is total and
  no view names a literal), **ADR-0028 §D1** (one delegate, two surfaces), **ADR-0029 §D17**
  (the card's own span switch is the seam), `docs/20260904_Editor_Page_Roadmap.md` Phase A.

## Context

**The editor breaks the one design rule this repo calls binding.** CLAUDE.md and SPEC §11.3
both say: *«una vista che usa un colore o un font non passando dai token non supera la
review»*. Colours obey it. Fonts do not. `MarkdownAttributedText.base(theme:)` opens with
`NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)` (`:18`), its heading arm computes
`NSFont.systemFont(ofSize: max(15, 24 - level * 2), weight: .semibold)` (`:52`), and its bold
arm returns the monospaced face in `.bold` (`:56`). The theme file, meanwhile, already
declares `font.body` as `system` 13 — so the "source mode" look on screen is the editor
overriding its own theme, not a theme anybody chose.

**What the greps actually return**, run for this ADR rather than taken from the SPEC:

```
$ grep -rn "NSFont\." Sources/Features/Editor Sources/Features/Workspace | wc -l
16
$ grep -rn "font(\.body)" Sources | wc -l      # 7
$ grep -rn "nsFont(\.body)" Sources | wc -l    # 4
$ grep -rn "nsFont(\.title)" Sources | wc -l   # 2
```

The sixteen decompose as:

| Site | What it is |
|---|---|
| `MarkdownAttributedText.swift:18`, `:52`, `:56` | body, heading, bold — the three the roadmap named |
| `TableGridView+Rendering.swift:76`, `:182` | a cell's face, and the face column widths are measured with |
| `TableGridView+Rendering.swift:179` | `NSFont.Weight` — a **type name** in a signature, not a font |
| `TableGridView+CellCommit.swift:180` | the 9pt «Riga»/«Colonna» control label |
| `EditorDecorationDelegate.swift:153` | `collapsedFont` = `monospacedSystemFont(ofSize: 0.01)` — **the concealment mechanism**, not typography |
| `EditorDecorationDelegate+ListRendering.swift:84` | `NSFont.systemFontSize` — a **constant**, inside a `.systemFont(ofSize:)` fallback for a paragraph carrying no font at all |
| `FoldedHeadingFragment.swift:31` | the 10pt fold badge — **a site the roadmap and the SPEC both missed** |
| `CardTextAttributes.swift:99`, `:107`, `:114`, `:121` | the card's heading, bold, code and code-block faces |
| `CardTextAttributes.swift:9`, `:17` | two **doc comments** quoting the note editor's monospaced bold |

So the editor holds nine font-constructing sites across **six** files, not five: the SPEC's
count is right by accident and its file list is wrong, because it counted a type name as a
font (`TableGridView+Rendering` has two font sites, not three) and never saw the fold badge.
R-01's literal wording — *"returns hits only in the shared typography helper file"* — is
therefore **not satisfiable**: a type name, a size constant, the 0.01pt collapse font and two
doc comments would all have to be rewritten to reach zero, and rewriting the collapse font
would reopen ADR-0018's mechanism. The roadmap's own wording is the correct one — *"zero hits
outside a deliberately named allow-list"* — and D8 names the list.

The eleven `.body`/`.title` call sites the SPEC cites are also confirmed, and they are the
app's chrome: `CapturePanelView:123`, `TaskDatePanels:58`/`:235`, `TaskComposer:41`,
`GoToDateSheet:31`, `DiaryEntrySheet:81`/`:165`, `MarkdownBlocksView:183`/`:229`,
`MarkdownBlocksView+Table:17`, `NewNoteComposer:87`, plus `CardTextAttributes:149`/`:154`,
which is the only pair this ADR moves.

**The delegate cannot read a theme.** `EditorDecorationDelegate` is not `@MainActor` (Swift 6
refuses both conformances, `:25-26`) and holds plain values pushed in from the Coordinator:
`decorations.badgeColor`, `decorations.badgeBackground`, `decorations.handleColor`,
`decorations.ruleColor`, all assigned inside `applyStyling`/`applyFolding` from
`NSColor(theme.color(…))`. Fonts must arrive the same way or not at all. That is not a new
crossing to invent; it is the fourth instance of one that already works.

**Three places overwrite `.paragraphStyle` wholesale**, and each would silently drop a line
height applied underneath it:

- `NoteTextView+Transclusion.swift:57-64` builds a fresh `NSMutableParagraphStyle`, sets
  `paragraphSpacing = rendition.reservedHeight`, and writes it over the source line;
- `EditorDecorationDelegate+ListRendering.swift:64-69` writes
  `ListMarkerRendering.paragraphStyle(level:font:)` over the whole displayed paragraph;
- `CardTextView.swift:384-388` builds a fresh style for a card's `pergamenum-textAlign`.

Grepped: those are the only three in `Sources/Features/Editor` and
`Sources/Features/Workspace`. Each is answered by name in D5.

**What was measured for this ADR, on this machine.** Avenir Next ships in
`/System/Library/Fonts/Avenir Next.ttc` — not in `Supplemental/`, so it is a
system-protected font present on every macOS 26 install rather than an optional download. A
compiled AppKit probe reported:

```
families: ["Avenir", "Avenir Next", "Avenir Next Condensed"]      (187 families installed)
AvenirNext-Regular | Regular | weight 5      AvenirNext-Bold     | Bold     | weight 9
AvenirNext-Italic  | Italic  | weight 5      AvenirNext-DemiBold | DemiBold | weight 8
NSFont(name: "Avenir Next", size: 16)                                 -> AvenirNext-Regular
NSFontDescriptor(.family: "Avenir Next").withSymbolicTraits(.bold)    -> AvenirNext-Bold
NSFontDescriptor(.family: "Avenir Next").withSymbolicTraits(.italic)  -> AvenirNext-Italic
NSFontManager.convert(_, toHaveTrait: .boldFontMask)                  -> AvenirNext-Bold
descriptor.addingAttributes([.traits: [.weight: NSFont.Weight.bold]]) -> AvenirNext-Regular   ← silent miss
NSFont(name: "Totally Not A Font", size: 16)                          -> nil
NSFont(descriptor: .family("Totally Not A Font"), size: 16)           -> nil
```

Four of those lines shape the decision and one of them would otherwise have been a defect:

1. **`NSFont(name:size:)` accepts a *family* name**, not only a PostScript name. No face names
   need hardcoding anywhere — which removes the SPEC's whole "verify the PostScript faces"
   concern, and means a picker can pass `NSFontManager.availableFontFamilies` entries straight
   through.
2. **The weight trait does not work on a named family.** Asking a descriptor for
   `NSFont.Weight.bold` returned `AvenirNext-Regular`, silently. A `font.proseTitle` token
   declaring `fontWeight: 700` resolved that way would have produced headings in the regular
   face with no error anywhere. The **symbolic** trait works, and so does
   `NSFontManager.convert(_:toHaveTrait:)`.
3. **A missing family returns `nil`** from both constructors — a clean, testable fallback
   signal, and the whole of the SPEC §8 edge case "theme names a missing family".
4. There are 187 families to put in a picker, which is a `Picker` inside a scroll view and not
   a design problem.

## Decision

**D1. The shared helper is `ProseTypography`, and it lives in `Sources/DesignSystem/`.**

A new file `Sources/DesignSystem/ProseTypography.swift`, `import AppKit`, one `enum` of static
functions:

```
prose(_ theme: Theme) -> NSFont
proseBold(_ theme: Theme) -> NSFont
proseItalicAttributes(_ theme: Theme) -> [NSAttributedString.Key: Any]
heading(level: Int, _ theme: Theme) -> NSFont
mono(_ theme: Theme, size: CGFloat? = nil) -> NSFont
paragraphStyle(_ theme: Theme, basedOn: NSParagraphStyle? = nil) -> NSParagraphStyle
```

`Sources/DesignSystem/` and not `Sources/Features/Editor/`, for three reasons of which the
third is binding:

- it is read by two feature modules — `Sources/Features/Editor` and
  `Sources/Features/Workspace` — and a rule shared by two peers belongs inside neither;
- turning a token into a face is `Theme.nsFont(_:)`'s own layer, and `Theme.swift` already
  imports AppKit in this directory. The helper is the second half of a job that starts there;
- **`Sources/DesignSystem/**` is not in `sharedSources`.** `Project.swift:72-97` lists
  `Sources/Core/**`, `Sources/Connector/**` and nineteen named files; DesignSystem is not among
  them, so `import AppKit` here cannot break the `perg` and `pergamenum-mcp` builds.
  `Sources/Core` is forbidden for exactly that reason and is not a candidate (A3).

`ListMarkerRendering` staying under `Sources/Features/Editor` is not a counter-precedent: it
encodes *how a bullet is drawn*, a rendering rule of one family of surfaces. This one encodes
*which face a token means*, which is the design system's job.

Rejected: **an extension on `Theme`** (`theme.proseFont`, `theme.headingFont(level:)`).
Shorter, but it puts the editor's heading scale on the type every view in the app holds, and
the next surface wanting a different scale must either share this one or shadow it. A named
enum is a thing to read; an extension is a thing to trip over.

Rejected: **`Sources/Features/Editor/EditorTypography.swift`** (the SPEC's indicative name and
location). It would make `Sources/Features/Workspace/CardTextAttributes.swift` import a rule
out of the Editor feature — the dependency direction ADR-0028 §D1 was careful *not* to create:
the card reuses a delegate that is already shared machinery, not the editor's own vocabulary.

**D2. `EditorDecorationDelegate`, `FoldedHeadingFragment` and `TableGridView` receive fonts as
values, pushed from the Coordinator, exactly as they already receive colours.**

Two new `nonisolated(unsafe) var`s on the delegate — `proseFont: NSFont` and
`badgeFont: NSFont`, both defaulting to a system face so a delegate built by an offscreen test
harness still draws — assigned in `applyStyling` beside `decorations.handleColor` and
`decorations.ruleColor` (`NoteTextView+Coordinator.swift:330`, `:334`):

```
decorations.proseFont = ProseTypography.prose(theme)
decorations.badgeFont = ProseTypography.mono(theme, size: <caption size>)
```

`FoldedHeadingFragment.badgeFont` follows `badgeColor`/`badgeBackground`, which the Coordinator
already sets through the delegate in `applyFolding` (`:183-184`). `TableGridView` needs no new
channel at all: `update(with:theme:)` (`TableGridView+Rendering.swift:21`) already takes the
`Theme` and assigns six colours from it, so the cell face is a seventh assignment in a method
that already exists.

No new hook, no new protocol, no `@MainActor` change anywhere. This is the crossing
`renditions`, `embedRenditions`, `tableViews` and four colours already make, for a fifth kind
of value.

Rejected: **giving the delegate a `Theme`.** It cannot hold one without either the `@MainActor`
conformance Swift 6 refuses or a captured reference that goes stale between passes — which is
the argument `apply(embeds:)`'s own header already makes for finished values.

**D3. A named font family is a fourth `TypographyValue.Family` case; it resolves through
`NSFont(name:size:)` on the *family* name, and its bold comes from the *symbolic* trait, never
from the weight trait.**

`TypographyValue.Family` stops being a compiler-synthesised `String` enum and becomes a
hand-written `RawRepresentable`:

```
enum Family: Equatable, Sendable, RawRepresentable {
    case system, monospace, serif, named(String)
    var rawValue: String        // "system" | "monospace" | "serif" | the family name
    init(rawValue: String)      // non-failable: anything else is .named(rawValue)
}
```

Non-failable on purpose, and that is what makes `DesignTokenDocument.typography(_:)`'s
existing line

```
let family = TypographyValue.Family(rawValue: object["fontFamily"] as? String ?? "system") ?? .system
```

lose its `?? .system` — today an unrecognised `fontFamily` string is silently discarded, which
is precisely why nobody could put a font name in a theme file before.

`Theme.nsFont(_:)` gains one arm:

```
case .named(let family):
    guard let base = NSFont(name: family, size: value.size) else {
        return NSFont.systemFont(ofSize: value.size, weight: weight)   // the token's own weight
    }
    guard value.weight >= 600 else { return base }
    let bold = base.fontDescriptor.withSymbolicTraits(.bold)
    return NSFont(descriptor: bold, size: value.size) ?? base
```

The `>= 600` step, rather than a nine-stop weight map, is forced by the measurement above:
`descriptor.addingAttributes([.traits: [.weight: …]])` returned the **regular** face for Avenir
Next and reported nothing. A family exposes whatever weights it ships, and the only weight axis
AppKit reaches reliably on an arbitrary family is the bold symbolic trait. A token declaring
700 gets the family's bold face; one declaring 400 gets its regular face; one declaring 500
gets regular — stated here rather than pretended otherwise.

Italic follows `CardTextAttributes.italicAttributes`'s existing shape, unchanged in substance:
`withSymbolicTraits(.italic)`, verified to contain `.italic` afterwards, else
`[.obliqueness: 0.2]`. That code already works and is already tested; it moves into the helper
and is called by both surfaces.

`Theme.font(_:)` (SwiftUI) resolves the **same** `NSFont` first and then names it:

```
case .named:
    guard let resolved = <the NSFont above> else { return Font.system(…) }
    return Font.custom(resolved.fontName, size: value.size)
```

Probing with `NSFont` and handing SwiftUI the resolved **PostScript** name (`AvenirNext-Bold`,
not `Avenir Next`) is what makes SPEC §8's *"the fallback must be explicit"* true:
`Font.custom` on an absent name substitutes silently, and AppKit and SwiftUI would draw two
different faces from one token with nothing reporting it.

Rejected: **hardcoding `AvenirNext-Regular`/`-Bold`/`-Italic` in the theme JSON**, as the
SPEC's §2 table implies by quoting NotePlan's theme. Measured unnecessary, and it would make
every user-picked family a three-key edit instead of one.

Rejected: **keeping `Family` a plain `String` enum and adding the family name as a separate
optional field on `TypographyValue`.** Two fields that can disagree
(`family: .system, name: "Avenir Next"`) where one value does the job.

**D4. The heading scale is `CardTextAttributes.headingSize`'s rule, moved into the helper and
read by both surfaces. No per-level tokens.**

`heading(level:_:)` returns the prose family at
`max(prose + 1, proseTitle − (level − 1) × 2)`, in the family's bold face by the same `>= 600`
rule as D3 (the `font.proseTitle` token declares 700). With the bundled values (prose 16,
proseTitle 24) the six levels are **24, 22, 20, 18, 17, 17** — H5 and H6 collide at the floor,
deliberately: a sixth level one point above the body is a distinction nobody sees, and the
alternative is five more keys in two theme files, which is what drift looks like.

Changing `font.proseTitle` in a theme file changes all six levels with no code change. That is
R-03, and it is a property of the arithmetic rather than a test anybody has to remember.

Rejected: **a modular ratio scale (1.25 / 1.333 per level).** Non-integral point sizes that
AppKit rounds inconsistently between the editor and a card at a scaled zoom, in exchange for a
typographic pedigree nobody asked for.

**D5. Line height is one `lineHeightMultiple` from the `font.prose` token, applied on the
editor's base attributes and *composed* — never overwritten — at the sites that build their own
paragraph style.**

`ProseTypography.paragraphStyle(_:basedOn:)` returns a mutable copy of `basedOn` (or a fresh
style) with `lineHeightMultiple` set from the `font.prose` token's `lineHeight` and **nothing
else set**. No `paragraphSpacing`: in markdown a blank line already separates paragraphs, and
spacing on top of it would double every gap.

The three overwrite sites, each answered by name:

- **`NoteTextView+Transclusion.reserveSpace`** reads the style already on the source line and
  mutates a copy, so `paragraphSpacing = reservedHeight` and the prose line height coexist.
  `reservedHeight` is computed from `TranscludedRendition.height(of:width:)` against the body
  face and grows with it — nothing to change there, which is exactly why
  `TransclusionLayoutTests` is the regression guard for this decision.
- **`ListMarkerRendering.paragraphStyle(level:font:)`** gains a third parameter,
  `basedOn: NSParagraphStyle?`, and `EditorDecorationDelegate+ListRendering` passes the style
  already carried by the displayed paragraph. The indent arithmetic (`stepInEms`,
  `glyphInEms`) is untouched and steps in proportion to the font it is handed — now 16pt prose
  instead of 13pt mono, so a nested item steps 24pt instead of 19.5pt. That amends ADR-0028
  §D3's signature and nothing else about it.
- **`CardTextView.baseAttributes`** is *not* touched, because D10 keeps the line height out of
  cards.

Rejected: **`minimumLineHeight`/`maximumLineHeight` in points.** They do not follow the user's
size choice, and the token is already expressed as a multiple.

**D6. Readable width is a horizontal `textContainerInset` computed by the Coordinator from the
scroll view's frame. Nothing sets a frame, and `CompletingTextView` gains no override.**

With `widthTracksTextView` left at its default `true` — which is what makes the editor track a
pane resize today — the container's width is the view's width minus twice the inset. So

```
inset.width = max(24, (viewWidth - theme.spacing(.readable)) / 2)
```

is the cap **and** the centring in one number, with today's 24pt inset as its floor. Below the
cap the expression yields 24 and the text behaves exactly as it does now. The vertical inset
(20) is untouched.

Two things follow, and both are why this shape was chosen over the obvious one:

- **Nothing sets a frame.** `growToFitTheText`'s header spends nine lines recording that
  `setFrameSize` re-enters SwiftUI's update pass, that `updateNSView` then writes back a value
  one keystroke old, and that it once cost the Diario everything typed into it — caught by
  `DiaryUITests` while the unit suite stayed green (`NoteTextView+Coordinator.swift:473-478`).
  Setting `textContainer.size` with `widthTracksTextView = false` puts the frame width back
  under manual control and walks into that path. An inset does not.
- **The recompute is driven by a frame-change observation on the scroll view's content view**
  (`contentView.postsFrameChangedNotifications = true`, observed by the Coordinator), because
  `updateNSView` does not run on a window resize. The observation is set up in `makeNSView` and
  torn down with the Coordinator.

**The SPEC's §3.7 sentence *"Insets (24 × 20) are unchanged"* is corrected here rather than
obeyed**: the horizontal inset *is* the mechanism and 24 is its minimum. Nothing else about the
insets changes.

`VaultSettings.readableWidth: Bool` gates it — default `true`, `decodeIfPresent` fallback,
exactly `hidesMarkup`'s shape (`VaultSettings.swift:186`) — reaches `NoteTextView` as a
property defaulting to **`false`** (the same permissive default `hidesMarkup` and `spellCheck`
take, so a text view built with no vault behind it behaves as before), and is passed by the
three surfaces that construct one: `EditorColumn+Text.swift:47`, `DiaryView.swift:87`,
`TodayView.swift:191`.

Rejected: **capping `textContainer.size.width` with `widthTracksTextView = false`.** It caps
but does not centre, so centring needs the frame after all.

Rejected: **wrapping `NoteTextView` in a SwiftUI `.frame(maxWidth:)`.** It narrows the scroll
view, so the scroller moves into the middle of the window and the editor's background stops at
the column's edge.

**D7. `spacing.readable` is a `SpacingToken`, and `DesignGalleryView` stops iterating
`SpacingToken.allCases` for its swatch ramp.**

`SpacingToken.readable = "spacing.readable"`, 720 in both bundled files. This is a scale of
five step values (4/8/16/24/40) gaining a sixth member that is not a step, and the place that
notices is `DesignGalleryView.swift:153`, which draws
`Rectangle().frame(width: theme.spacing(token), height: theme.spacing(token))` for every case —
a 720×720 swatch inside an `HStack`. The ramp iterates an explicit list of the five step
tokens; `spacing.readable` appears in the "all tokens" sheet as a measurement, not as a square.

Rejected: **a new `MeasureToken` enum for one value.** A whole `TokenKey` conformance, a sixth
dictionary on `Theme`, a sixth arm in `Theme.resolve` and a sixth entry in `Theme.emergency`,
so a gallery can iterate one list without a filter.

**D8. R-01's allow-list, named here so the acceptance check is decidable.**

After this change `grep -rn "NSFont\." Sources/Features/Editor Sources/Features/Workspace` must
return **only**:

| Allowed | Why |
|---|---|
| `EditorDecorationDelegate.swift` `collapsedFont` (`monospacedSystemFont(ofSize: 0.01)`) | ADR-0018's concealment mechanism, deliberately size- and theme-independent. It is a *non*-font; routing it through a token would let a theme break concealment |
| `TableGridView+Rendering.swift:179` `NSFont.Weight` in a signature | a type name |
| `EditorDecorationDelegate+ListRendering.swift:84` `NSFont.systemFontSize` | the last-resort constant for a paragraph carrying no font at all — an offscreen harness, never the app |
| `NSFont` type annotations and default property values on the delegate / `FoldedHeadingFragment` / `TableGridView` | so an object built without a theme still draws; the app overwrites them on every pass |

Everything else — the nine construction sites in the Context table, the two doc comments in
`CardTextAttributes.swift:9`/`:17` included — goes. The comments are rewritten because their
claim ("the note editor's monospaced bold") stops being true, not because a grep asks.
`ProseTypography.swift` lives under `Sources/DesignSystem`, so it is outside the grep's two
directories entirely and needs no exemption.

**D9. The user's font choice is a `fonts` map on `ThemeCustomization.Draft`, written into the
same `personalizzato.json` the colours already live in.**

`Draft` becomes `{ appearance, colors, fonts: [FontToken: TypographyValue] }`, with
`isEmpty == colors.isEmpty && fonts.isEmpty`. `object(from:)` writes each entry as a DTCG
typography token — `{"$type": "typography", "$value": {"fontFamily": …, "fontSize": …,
"fontWeight": …, "lineHeight": …}}` — through the same `insert(_:at:into:)` path in the same
sorted order, so the file stays byte-stable across two identical choices. `load(from:)` reads
`$value` as a dictionary: its existing `value(at:in:)` already returns whatever `$value` holds,
so it needs a type branch, not a new walker. A file written by an older build has no `font.*`
node and yields `fonts: [:]`.

`ThemeEngine` gains `setCustomFont(_:to:)` and `clearCustomFonts()` mirroring
`setCustomColor(_:to:)` / `clearCustomColor(_:)` line for line — the "no vault open, nowhere to
save" guard, the write-then-select ordering its header explains, and the fall through to
`resetCustomization()` when the draft goes empty. Deleting the file is already "back to the
base theme" and needs nothing new.

**Only `font.prose` and `font.proseTitle` are writable.** `font.body`, `.title`, `.heading`,
`.caption` and `.mono` are not offered: they are the interface's faces, eleven call sites
depend on them, and a person who shrinks the app's chrome by accident has no words for what
they did. Title size follows body size at the fixed 24/16 ratio unless the theme file already
declares otherwise.

**D10. Workspace `.text` cards take the prose family and the heading scale, and deliberately
**not** the line height.**

`CardTextAttributes.bodyFont` reads `.prose`, `headingSize` becomes
`ProseTypography.heading(level:_:)`, `.bold` and `.italic` come from the helper, `.code` and
`.codeBlock` stay on `font.mono` at the prose size. That is R-08 in full, and card size
scaling is unchanged: it multiplies the resolved point size exactly as it multiplies `.body`'s
today.

The line height stops at the editor, for a structural reason rather than a tidy one:
`CardTextView.baseAttributes` (`:384-388`) builds a fresh `NSMutableParagraphStyle` for a
card's `pergamenum-textAlign` (ADR-0027 §D4) and would have to learn to compose — a change to
a file ADR-0029 §D17 asks be left alone, inside a view that is deallocated on every
culling-rect crossing (ADR-0028 R-11, the `a853e8e` crash class). No requirement asks for it:
R-07 names prose and list paragraphs, R-08 names faces. Filed as debt in Consequences rather
than smuggled in.

ADR-0029 §D17's seam is untouched: nothing here adds a `HiddenMarker.Kind` or a
`MarkdownStyler.Span`, and `CardTextView.swift`'s own span switch is not edited.

**D11. `TableGridView`'s cells read the prose face at the prose size; its control labels take a
size derived from a token, not a literal.**

`makeCell(isHeader:)` sets `ProseTypography.prose(theme)` or `proseBold(theme)`, and
`width(of:weight:)` measures with the same face it draws with — the two must not disagree, or
every column is sized for a face nobody sees. `makeGroupLabel`'s 9pt «Riga»/«Colonna» label
derives its size from `font.caption` rather than naming 9.

The line-fragment consequence is real and is a hand check, not a claim: a 16pt cell is taller
than a 13pt one, and `tracksTextAttachmentViewBounds` (ADR-0029 §D6) means the header line's
fragment height follows the grid's own frame. The mechanism is unchanged; the number it
produces is not.

**D12. Typography is not behind `hidesMarkup`, and no switch is added except the
readable-width toggle.**

A proportional body is the editor's look, not a markup decision — the roadmap's own ruling.
With `hidesMarkup` off the markers are drawn, in the prose face, and everything else is exactly
as today. `readableWidth` earns a second setting only because it is a *geometry* preference
with a real reason to be turned off (a wide window used as two columns), which is the test
ADR-0018 §D7 set for adding a toggle at all.

**D13. No index field, no frontmatter key, no `.canvas` property, no migration, and no
protected interface touched.**

`IndexCache.schemaVersion` stays 3 — nothing here is indexed. `VaultAPI.LintFinding` and both
connectors are untouched: `perg` and `pergamenum-mcp` read and write markdown and have no
concept of a face. `CompletingTextView+Pasteboard.swift` is not edited. The only files whose
shape on disk changes are `.pergamenum/settings.json` (one new boolean, absent-tolerant) and
`.pergamenum/themes/personalizzato.json` (a new optional section). `interface-check.sh` must
stay silent for the whole chain.

**D14. The SPEC amendments, in literal text, so the plan's Task 8 applies rather than composes
them.**

**§5 — insert three bullets after the «Una tabella GFM è una griglia vera…» bullet, before
«Requisiti minimi»:**

> - **La tipografia dell'editor è una pagina, non un buffer di codice** (ADR-0030,
>   2026-09-04): il corpo della nota è reso con il token `font.prose` (Avenir Next 16,
>   interlinea 1.4) e i titoli con la scala interpolata fra `font.proseTitle` e `font.prose` —
>   `max(prose + 1, proseTitle − (livello − 1) × 2)`, sei livelli, nessun token per livello. Il
>   monospazio resta solo per il codice, i fence e il frontmatter (`font.mono`). Nessuna vista
>   dell'editor nomina più un carattere: le facce arrivano dai token come i colori, e la regola
>   vincolante di §11.3 vale ora anche per i font.
> - **Larghezza di lettura**: la colonna di testo è limitata a `spacing.readable` (720pt) e
>   centrata quando la vista è più larga; sotto quella soglia il testo segue la larghezza della
>   vista esattamente come prima. È un'impostazione della cartella note
>   (`VaultSettings.readableWidth`, attiva di default) e vale su tutte e tre le superfici che
>   disegnano l'editor: Nota, Diario e Oggi.
> - **Il carattere della nota si sceglie in Impostazioni → Editor**: famiglia fra quelle
>   installate più «Sistema», corpo da 12 a 24. La scelta è scritta come override dei token
>   `font.prose` e `font.proseTitle` in `.pergamenum/themes/personalizzato.json`, attraverso lo
>   stesso meccanismo dei colori (§11.3): resta un file DTCG nel vault, mai uno stato dell'app.
>   Una famiglia dichiarata da un tema e non installata degrada al carattere di sistema, senza
>   errore e senza crash.

**§14 — replace the *Temi* row.** Current text:

> | Temi | Design token JSON (DTCG), no CSS/WKWebView | Il CSS richiederebbe webview; i token danno lo stesso risultato in nativo e restano interoperabili con gli strumenti web di design |

becomes:

> | Temi | Design token JSON (DTCG), no CSS/WKWebView; dal 2026-09-04 i token personalizzabili dall'utente comprendono anche la tipografia del corpo nota, non più i soli colori (ADR-0030) | Il CSS richiederebbe webview; i token danno lo stesso risultato in nativo e restano interoperabili con gli strumenti web di design. La scelta del carattere resta un file di tema nel vault, mai una preferenza dell'app: stesso meccanismo, una classe di token in più |

**§14 — the row the roadmap expected to amend is already gone.** *«Live preview completa»* was
retired on 2026-09-02 by ADR-0029 and its cell already says so. ADR-0030 does **not** touch it,
and the SPEC's §2/§3.9 claim that this chain amends the *«source mode con stile è sufficiente»*
rationale is a stale premise, corrected here.

**§11.3 — extend the token-examples bullet.** In the sentence beginning *«Token semantici, mai
riferimenti diretti a colori nelle viste»*, the list `font.body`, `font.title`,
`spacing.s/m/l` becomes `font.body`, `font.title`, `font.prose`, `font.proseTitle`,
`spacing.s/m/l`, `spacing.readable`. Nothing else in §11.3 changes: its closing binding rule is
what this ADR enforces, not what it edits.

## Alternatives considered

**A1. Change `font.body` to Avenir Next 16 and use it for both the interface and the note,
adding no token at all.** The smallest possible diff: two theme files, no new key, no new enum
case, no `Theme.emergency` entry, and `CardTextAttributes` barely changes. **Rejected:**
`font.body` has eleven call sites outside the editor — `CapturePanelView:123`,
`TaskDatePanels:58`/`:235`, `TaskComposer:41`, `GoToDateSheet:31`, `DiaryEntrySheet:81`/`:165`,
`MarkdownBlocksView:183`/`:229`, `MarkdownBlocksView+Table:17`, `NewNoteComposer:87` — and they
are the app's chrome: sheets, composers, pickers, the transclusion renderer. A 16pt
proportional body in a settings row is a different app, and the person who wanted a nicer note
would have got a bigger Impostazioni instead. Two tokens is the cheapest way to say that "the
page" and "the interface" are different things.

**A2. Six per-level heading tokens (`font.h1` … `font.h6`).** Fully declarative: a theme author
sets every level, no arithmetic anywhere, and R-03's "changing the theme changes the levels" is
trivially true. **Rejected:** five more keys in two bundled files, five more `Theme.emergency`
entries, five more `FontToken` cases, five more chances for the two theme files to disagree —
and `CardTextAttributes.headingSize` already ships the interpolation rule, tested, in
production, for cards. The roadmap named this trade explicitly and chose the rule; nothing read
in the code argues the other way.

**A3. Put the helper in `Sources/Core/Typography.swift` so the connectors could reuse it.** It
would put one typographic rule in the directory this repo treats as the single source of shared
truth. **Rejected outright, and named here only because it is the mistake a reader might make:**
`Sources/Core/**` is a `sharedSources` glob (`Project.swift:73`) compiled into `perg` and
`pergamenum-mcp`, and `NSFont`/`NSParagraphStyle` are AppKit. The file would break both tool
builds on the first compile — ADR-0001 §D1 enforcing itself, which CLAUDE.md records happening
three times already. The connectors also have nothing to draw.

**A4. Implement the readable-width cap by setting the text container's size directly, with
`widthTracksTextView = false`.** The textbook approach: one line, no notification observer, and
it is what every macOS tutorial shows. **Rejected:** it hands the text view's frame width back
to manual control, and the frame is the thing this repo has a written scar about —
`growToFitTheText`'s header spends nine lines on why `setFrameSize` re-enters SwiftUI's update
pass and once cost the Diario everything typed into it, with `DiaryUITests` catching what the
unit suite missed. The inset route caps and centres in one number and touches no frame, at the
cost of one `NSViewFrameDidChange` observation.

**A5. A single `font.prose` token with the heading scale hardcoded in the helper.** One token
instead of two, and the scale becomes a constant nobody edits by mistake. **Rejected:** R-03
asks for a theme-driven scale, and a scale anchored to a value the theme cannot set is a scale
the theme cannot change. Two tokens is also what makes the user's size choice propagate to
headings by the fixed 24/16 ratio (D9) without a second control in Impostazioni.

**A6. Ship the typography and defer the font picker to a later phase.** Phase A would then be a
pure conformance fix — nine sites, two tokens, one width — with no `ThemeCustomization` change,
no settings UI and no `TypographyValue.Family` rework: roughly half the work and most of the
remaining risk. **Rejected, but it is the honest fallback if the chain runs long:** the picker
is what makes the token reachable by the person who has to live with the choice; without it,
"pick a prose font" means hand-editing JSON in the vault. Task 7 is separable from Tasks 1–6 by
construction, so this remains available at Gate 3 without a redesign.

**A7. Reuse `MarkdownAttributedText` for the card and delete `CardTextAttributes`.** With the
note editor's bold no longer monospaced, the reason ADR-0027 §D1 gave for two tables — *"that
table's `.bold` arm returns the monospaced face, wrong on a canvas card"* — expires with this
ADR. **Rejected:** the other reasons do not expire. The card's `.linkTarget` must never carry
`.link`, because a card has no note to route a click to; its `.embedRun` draws no preview; its
base attributes are overwritten by the card's own colour and alignment. One table serving both
needs three `if isCard` branches, which is two tables wearing a disguise. What is genuinely
shared is the *typography*, and that is exactly what D1 extracts.

**A8. Apply the line-height multiple to Workspace cards too, composing it into
`CardTextView.baseAttributes`.** Consistent with ADR-0028's "same rendering on both surfaces"
and three lines of code. **Rejected for this chain:** it edits a file two ADRs ask be left
alone, inside a view with a known deallocation hazard, and it changes the rendered height of
every text card on every existing board with no requirement asking for it. Kept as named debt
(Consequences) so the next card chain can take it deliberately.

## Consequences

**Positive**

- **The binding design rule becomes true rather than aspirational.** After this, a font in the
  editor comes from a token or it does not pass review, and the allow-list (D8) is four named
  exceptions with a written reason each instead of "nine sites we know about".
- **Changing a theme file changes the editor.** `font.prose`, `font.proseTitle` and
  `spacing.readable` are the whole surface: six heading levels, body, bold, italic, table
  cells, list indentation step and column widths all move when the token moves, with no code
  change. R-03 and most of R-04 are arithmetic, not promises.
- **No mechanism is touched.** No delegate hook, no substitution, no enumeration refusal, no
  attachment, no commit path, no `HiddenMarker.Kind`, no `MarkdownStyler.Span` case. The
  riskiest machinery in the repo is read-only for this chain — which is why the roadmap called
  Phase A low risk, and why that judgement survived reading the code.
- **Oggi and Diario get the whole feature for free**, as they did for ADR-0029: the three
  `NoteTextView(` call sites each gain one argument.
- **List indentation improves without being touched.** `ListMarkerRendering` steps in ems, so a
  16pt prose face steps 24pt per level where 13pt mono stepped 19.5pt. ADR-0028 §D3's
  proportionality argument pays out for the first time.
- **A named family in a theme file becomes possible at all.** Today `DesignTokenDocument`
  silently discards any `fontFamily` it does not recognise; after D3 a hand-written theme can
  name a face, which is what "readable by web tools and by Claude" (§11.3) was supposed to
  mean.

**Negative**

- **Every line-fragment height in the editor changes**, because the body face changes. Embed
  bounds, table grids, transclusion reserved height, the folded-heading badge and the
  horizontal rule all compute against the paragraph's font. All are correct by construction and
  none is verified by a test that can see a window. That is R-14, and it is the largest single
  risk here — inherited from ADR-0029 §D16's probe class rather than invented.
- **The height-measuring tests keep passing while measuring a face the app no longer ships.**
  `MarkupHidingTests:43`/`:788`, `TableRenderingTests:50`, `TransclusionLayoutTests:78` and
  `EmbedAttachmentProbeTests:202` all build their fixture storage with an explicit
  `NSFont.monospacedSystemFont(ofSize: 13)`. Left alone deliberately — re-pointing them would
  churn measurements and gain no assertion — and named here so nobody mistakes their green for
  coverage of the prose face.
- **A card's line height diverges from the editor's** (D10, A8). Visible only side by side, and
  filed as debt with its reason.
- **H5 and H6 render at the same size** with the bundled tokens (D4's floor). A theme raising
  `font.proseTitle` separates them.
- **`TypographyValue.Family` stops being a synthesised enum**, so it needs a hand-written
  `RawRepresentable` conformance a future case could get wrong. Mitigated by a round-trip test,
  not by discipline.
- **The user can pick a font that makes the app hard to read** — a single-weight display face,
  or 24pt everywhere. Bold degrades to the regular face instead of crashing (D3) and
  "Ripristina" removes the override, but there is no preview and no validation. Accepted for a
  personal app; a preview is a UI nobody asked for.
- **`DesignGalleryView`'s spacing ramp stops iterating `allCases`** (D7), so a future
  `SpacingToken` will not appear there automatically. A one-line list to maintain, chosen over
  a whole token family for one measurement.
- **`DesignSystemSettings`' footer becomes half untrue** — *«Tipografia, spaziature, raggi e
  ombre restano definiti dal file del tema»* — and must be rewritten in the same task that adds
  the picker, or Impostazioni contradicts itself two tabs apart.

**Neutral**

- **Obsidian compatibility is unchanged** (principle 4): nothing here writes to a note, a
  `.canvas` or a frontmatter key. The files that change are the two bundled themes, the vault's
  optional `personalizzato.json` and `settings.json`.
- **Both connectors are untouched** (D13), and `Sources/Core` gains nothing.
- **`hidesMarkup` off is unaffected**: markers are drawn, in the prose face, and the editor
  still reverts completely with one switch that already exists.
- **`DesignAndReadingUITests` and `NoteImageUITests` assert by `accessibilityIdentifier`, not
  by font or by prose** (CLAUDE.md's own working agreement), so they should survive untouched.
  "Should" is the honest word: the suite runs by hand before the merge (R-16), and that is
  where it is confirmed.
- **The unit suite can cover token resolution, family parsing, the heading arithmetic, the
  paragraph-style composition, the inset arithmetic and the customisation round trip, and
  nothing else.** Everything about how a page *looks* is on screen, which is what
  `scripts/uitests.sh` and R-14's hand check exist for.
- **This is Phase A only.** Phases B and C stay in `docs/20260904_Editor_Page_Roadmap.md` and
  get their own ADRs.

## Non-goals

- **Phases B and C of the roadmap.** No new `HiddenMarker.Kind`, no inline-code or fence
  concealment, no fence badge, no frontmatter fold, no click-reveal caret re-mapping, no
  mouse-selection probe, no TextKit 2 viewport measurement. Explicitly out of scope for this
  chain and documented there for later ones.
- **Reopening ADR-0018 / ADR-0028 / ADR-0029's mechanisms.** The substitution, the reveal
  triggers, the enumeration refusal, the table attachment and its view provider, the cell
  commit path and `collapsedFont` are read-only here.
- **Changing `font.body`, `font.title`, `font.heading`, `font.caption`, or any interface
  text's face.** Eleven call sites depend on them and none of them is a note.
- **Per-level heading tokens, a modular ratio scale, `paragraphSpacing` on plain paragraphs.**
- **A per-token font editor in Impostazioni.** Two tokens are writable; the rest are a theme
  file's business.
- **Print and export surfaces.** `MarkdownBlocksView` and `NoteExporter` keep their own fonts.
- **Tags as pills, callouts, footnotes, math, Mermaid.** ADR-0029's non-goals hold unchanged.

## References

- `docs/20260904_Editor_Page_Roadmap.md` — Phase A; the four decisions of 2026-09-04
- `docs/adr/0001-initial-architecture.md` §D1, §D4
- `docs/adr/0018-the-editor-hides-the-syntax-it-can-draw.md` §D1, §D2, §D3, §D5, §D7
- `docs/adr/0027-unificare-nota-e-testo-in-un-solo-strume.md` §D1 (amended), §D4
- `docs/adr/0028-wysiwyg-markdown-in-workspace.md` §D1, §D2, §D3 (amended), §D4
- `docs/adr/0029-editor-wysiwyg-unification.md` §D4, §D5, §D6, §D16, §D17
- `docs/20260811_Pergamenum_SpecApp.md` §5, §11.3, §14 (amended by D14; not edited by this ADR)
- `SPEC.md` (2026-09-04) R-01 … R-16
- Measured for this ADR on macOS 26 / Darwin 25.6:
  `NSFontManager.availableMembers(ofFontFamily:)`, `NSFont(name:size:)`,
  `NSFontDescriptor.withSymbolicTraits(_:)`,
  `NSFontDescriptor.addingAttributes([.traits: [.weight: …]])`,
  `NSFontManager.convert(_:toHaveTrait:)`, `/System/Library/Fonts/Avenir Next.ttc`
- Source read for this ADR: `MarkdownAttributedText.swift`, `CardTextAttributes.swift`,
  `CardTextView.swift`, `NoteTextView.swift`, `NoteTextView+Coordinator.swift`,
  `NoteTextView+Transclusion.swift`, `NoteTextView+Tables.swift`,
  `EditorDecorationDelegate.swift`, `+ListRendering`, `+TableRendering`,
  `ListMarkerRendering.swift`, `FoldedHeadingFragment.swift`, `TableGridView.swift`,
  `+Rendering`, `+CellCommit`, `Theme.swift`, `TokenValue.swift`, `TokenKeys.swift`,
  `DesignTokenDocument.swift`, `ThemeCustomization.swift`, `ThemeEngine.swift`,
  `DesignGalleryView.swift`, `EditorSettings.swift`, `DesignSystemSettings.swift`,
  `VaultSettings.swift`, `Resources/Themes/pergamenum-light.json`, `pergamenum-dark.json`,
  `Project.swift`, `.claude/protected-interfaces`, `.claude/test-cmd`,
  `Tests/DesignSystemTests.swift`, `CardTextViewTests.swift`, `MarkupHidingTests.swift`,
  `TableRenderingTests.swift`, `TransclusionLayoutTests.swift`
