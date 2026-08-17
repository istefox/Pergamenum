# How far TextKit 2 goes towards NotePlan-style direct editing

**Date:** 2026-08-17
**Status:** study, decides nothing. SPEC §14 excludes full live preview from v1 ("voce di
costo massima"); reopening it needs an ADR, and this note is the evidence such an ADR would
be argued from.

## The question

Today the app has two surfaces: an editor that styles the markdown source in place (SPEC §5,
"Obsidian source mode improved") and a separate reading mode. NotePlan has one: you type on
the source and the syntax characters get out of the way. How much of that is reachable with
the frameworks already in this project, and what does it cost?

## Method

Two sources, and no third.

1. **The installed SDK**, `MacOSX.sdk` version 26.5, the headers this project actually
   compiles against. Every API claim below is quoted from a header on disk, not recalled.
2. **Six probes** built as throwaway tests inside `PergamenumTests`: an offscreen
   `NSTextContentStorage` + `NSTextLayoutManager` + `NSTextContainer`, measured with
   `enumerateTextSegments(in:type:options:)`. Every number below was produced on this
   machine on 2026-08-17. The decisive probe is reproduced at the end so it can be re-run.

Confirmed first, because everything depends on it: the editor is on **TextKit 2**. Nothing in
`NoteTextView` or `CompletingTextView` touches `layoutManager`, which is what silently drops an
`NSTextView` back to TextKit 1.

## What TextKit 2 offers, and which half of it works

There are exactly two documented channels for making the display differ from the storage, and
they are not equivalent.

### Rendering attributes — appearance only, measured

`NSTextLayoutManager.setRenderingAttributes(_:for:)` with the
`renderingAttributesValidator` callback. The header claims they participate in layout:

> Rendering attributes overrides the document text attributes stored in NSTextParagraphs
> supplied by NSTextContentManager. NSTextLayoutFragment associated with a text paragraph
> **applies the overriding attributes before executing layout**.

Measured, they did not. The validator **is** invoked (probe: 1 call, 1 range carrying
attributes), so the channel is live, but a `font` of 0.01 or a `kern` of -7.8 delivered
through it left the metrics untouched:

| what was applied to the two `**` runs | x of the text after them |
|---|---|
| nothing (baseline) | 117.51 |
| rendering attribute, font 0.01 | 117.51 |
| rendering attribute, kern -7.8 | 117.51 |
| rendering attribute, clear colour | 117.51 |

Confidence: medium. What is certain is that the naive use of the API does not collapse a run.
It is possible that a live `NSTextView` orders validation and layout differently from an
offscreen stack driven by `ensureLayout`. Anyone building this should re-measure inside a real
view before concluding the channel is useless — but it cannot be assumed to work.

This channel is still worth knowing about for a different reason: it colours **without touching
the text storage**, which is what `NoteTextView.applyStyling` does today by rewriting the whole
attribute run on every keystroke.

### The content storage delegate — this is the one that works

`NSTextContentStorageDelegate.textContentStorage(_:textParagraphWith:)` returns a substitute
`NSTextParagraph` for a paragraph of the backing store. The header states the constraint that
shapes the whole design:

> The attributed string for a custom text paragraph **must have range.length**.

So the displayed text may differ from the stored text in *attributes*, never in *length*. That
is not a limitation here, it is the guarantee this project needs: the editor's buffer is the
file's text, written to disk as it stands, and any mechanism that deleted or substituted
characters would break principle 1 (file over app) and the promise written at the top of
`MarkdownStyler` — it never removes or replaces characters.

Measured, with a 0.01pt font applied to the delimiters inside the substituted paragraph:

| | x of the text after `**grassetto**` |
|---|---|
| baseline | 117.51 |
| delegate substitution, font 0.01 | 85.39 |

32.12 points recovered over four hidden characters, 8.03 each, against a 13pt monospace
advance of 7.81. The run collapses to effectively nothing, and **line height is unchanged at
16.00** — the rest of the line still carries the real font, so the line does not shrink.

A negative `kern` also collapses (86.31) but leaves ~0.9pt of residue and would need tuning per
font and size. The tiny font is the better instrument.

## Reveal on caret, which is the whole interaction

The feel of NotePlan is not hiding, it is hiding *and coming back* when the caret enters the
line. That needs a paragraph to be re-mapped without the text changing. It works:

```
line hidden      w = 96.46
caret enters it  w = 128.58
```

Triggered by `storage.edited(.editedAttributes, range: paragraphRange, changeInLength: 0)`,
which re-invokes the delegate. Not one character of the note was touched.

Invalidation is **local**: after that call the delegate was asked for exactly two paragraphs,
the one edited and the one after it. It is not a whole-document re-map.

## Cost, measured

| operation | note | per operation |
|---|---|---|
| one keystroke, full re-layout | 33 KB, 400 paragraphs | **2.17 ms** |
| caret moving between lines (reveal + re-hide) | same note | **0.89 ms** |

For comparison, on the same machine `MarkdownStyler.spans` over a 17 KB note with a 400-line
code fence takes 5.83 ms, and that already runs on every keystroke today. The transform is not
the expensive part of this idea.

## What does not come for free

**The caret walks through hidden characters.** Measured: with `**` collapsed, moving backward
by character from offset 3 visits 2, 1, 0, 0. `NSTextSelectionNavigation` knows nothing about
the display transform, so the caret stops twice inside a run that occupies no space, and the
insertion point appears not to move. Skipping has to be implemented on top, in
`doCommand(by:)` and in whatever handles clicks — the same layer where the slash menu already
intercepts arrows. This is the single largest piece of work and the one that decides whether
it feels right.

**The delegate is not on the main actor.** Swift 6 refuses the conformance:

```
conformance of 'X' to protocol 'NSTextContentStorageDelegate'
crosses into main actor-isolated code and can cause data races
```

So the transform runs isolated from everything: it cannot read `VaultController`, the theme,
or the caret position directly. Whatever it needs — the current paragraph, the token colours —
has to be handed to it as `Sendable` values and updated from outside. That is a real
architectural constraint on the design, discovered by the compiler rather than by reading.

**Not probed, and each one can still sink it**: selecting with the mouse across a collapsed
run; `NSTextFinder` counting indices over hidden text; input methods and dead keys; VoiceOver;
undo coalescing when a reveal happens mid-typing; and what a collapsed run does to word-wrap
at the right margin.

## Addendum, same day: hiding whole lines is a different mechanism, and a better-behaved one

Folding a section came up straight after this study and turned out **not** to be the same
problem. A zero-width font collapses the glyphs of a line; it does nothing to the `\n`, so a
folded section would be a stack of empty rows.

The mechanism for whole lines is `NSTextContentManagerDelegate.shouldEnumerateTextElement`,
whose header says returning NO makes an element "skipped from the enumeration", and whose
companion `enumerateTextElementsFromLocation` says an implementation may "hide some elements
from the layout". Measured, hiding two paragraphs out of six:

| | before | after |
|---|---|---|
| laid-out fragments | 6 | 4 |
| height | 96.0 | 64.0 |

Then confirmed on screen in the real editor, which is the half the offscreen stack could not
answer for the earlier findings either.

**And the caret does not walk into them.** Arrow-down from the heading of a folded section
lands on the next *visible* line: measured, from offset 5 with lines 1-2 hidden, the caret
went to 33, inside the following heading. The elements are not in the layout, so
`NSTextSelectionNavigation` never sees them. That is the exact opposite of the zero-width
route, where the caret stops twice inside a run that occupies no space — and it means the
expensive part named above, writing the caret-skipping by hand, is **not** needed for
folding. It is still needed for hiding delimiters.

Two more things learned by doing it:

- A badge saying how much is hidden cannot be text — the note's characters are the file's
  characters. It exists as a custom `NSTextLayoutFragment` that draws past the end of the
  line, with `renderingSurfaceBounds` widened so the drawing is not clipped. This works, and
  it is the same door any inline decoration would go through.
- `NSTextContentStorage.delegate` is typed as `NSTextContentStorageDelegate`, so the
  element-hiding hook and the paragraph-substitution hook must live on the *same* object.

## How far it goes, feature by feature

| NotePlan behaviour | with what is here | evidence |
|---|---|---|
| headings styled in place, syntax visible | **already done** | shipped since M1 |
| bold/italic/code styled in place | **already done** | shipped since M1 |
| code fences coloured | **already done** | today, M8 |
| hide `**`, `#`, `[[ ]]` when the caret is elsewhere | **reachable** | measured above |
| show them again when the caret enters the line | **reachable** | measured above |
| caret behaving sensibly around hidden runs | **must be built** | measured: it does not |
| folding a whole section | **built, M8** | see the addendum above |
| clickable checkbox in the text | reachable, unprobed | `NSTextAttachmentViewProvider` exists in the SDK |
| image drawn inline instead of `![[foto.png]]` | reachable with a caveat | an attachment is one character; the wikilink is many, and length must be preserved, so the picture would have to be drawn by a custom `NSTextLayoutFragment` rather than substituted |
| tables rendered as grids while editing | **out of reach at sane cost** | the fragment would have to lay out a grid over a length-preserved run |

## What I would do, if it is ever decided

Not all of it. One slice: hide only the delimiters that never nest and never need a decision —
the `#` of a heading and the `*`/`_` of emphasis — with reveal on the caret's paragraph, and
leave everything else exactly as it is today. That is enough to know within a day whether the
reveal rule feels right, which is the only thing worth knowing early, and it does not touch
wikilinks, tasks, tags or fences.

The thing to settle **before** M8 continues, and the reason this study happened now: the
transclusion slice puts rendering into reading mode that the editor cannot do. Every such
addition widens the gap between the two surfaces and turns "add direct editing" into "choose
between two editors". If direct editing is wanted at all, transclusion should be designed as
something the editor can draw.

## Reproducing the decisive measurement

```swift
let storage = NSTextStorage(string: "**grassetto** e testo")
storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                     range: NSRange(location: 0, length: storage.length))

final class Hider: NSObject, NSTextContentStorageDelegate, @unchecked Sendable {
    func textContentStorage(_ s: NSTextContentStorage, textParagraphWith range: NSRange) -> NSTextParagraph? {
        guard let original = s.textStorage?.attributedSubstring(from: range) else { return nil }
        let copy = NSMutableAttributedString(attributedString: original)
        let tiny = NSFont.monospacedSystemFont(ofSize: 0.01, weight: .regular)
        for hidden in [NSRange(location: 0, length: 2), NSRange(location: 11, length: 2)] {
            copy.addAttribute(.font, value: tiny, range: hidden)
        }
        return NSTextParagraph(attributedString: copy)   // same length, different attributes
    }
}

let content = NSTextContentStorage()
let hider = Hider()
content.delegate = hider
content.textStorage = storage
let layout = NSTextLayoutManager()
content.addTextLayoutManager(layout)
layout.textContainer = NSTextContainer(size: CGSize(width: 600, height: 1_000_000))
layout.ensureLayout(for: layout.documentRange)

// Measure the frame of "e testo" with enumerateTextSegments: 85.39 with the delegate,
// 117.51 without it.
```
