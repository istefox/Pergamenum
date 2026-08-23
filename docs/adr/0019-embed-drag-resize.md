# ADR-0019: A drawn embed is resized by dragging it, and the size is written into the note

> **File placement note (for the operator, delete on move).** This project's convention puts
> every ADR under `docs/adr/`, numbered `0019-embed-drag-resize.md` beside its eighteen
> siblings. The agent that wrote this file is denied writes outside `docs/architecture/**` and
> `docs/superpowers/plans/**` by `agent-write-scope.sh`, so it landed here instead. Move it:
> `git mv docs/architecture/ADR-0019-embed-drag-resize.md docs/adr/0019-embed-drag-resize.md`
> and remove `docs/architecture/` if it is otherwise empty. The plan at
> `docs/superpowers/plans/2026-08-23-ridimensionamento-maniglie-embed-editor.md` names both
> paths.

- Status: accepted
- Date: 2026-08-23. Written directly after ADR-0018 slice 3 shipped a drawn picture in the
  editor at one fixed size, and from a reading of the code that draws it rather than from a
  plan for it: every mechanism named below already exists in this repository and was read at
  the line, and the two claims that could not be read out of the code are named as probes at
  the end of D8.
- Supersedes: nothing. **Extends ADR-0018 §D3**, whose *"the width is negotiated, not
  assumed"* is the sentence this ADR cashes in: D3 negotiated the width against the container
  and stopped there, so every embed in every note draws at whatever one constant said. It
  does not amend D3 - it uses the hook D3 named and never called.
- Depends on: **ADR-0018 §D3** (the attachment lives only in the substituted paragraph and is
  rebuilt from the text on every pass), **§D5** (a click on a drawn embed selects its run;
  the caret never enters it), **§D7** (`hidesMarkup`, the one setting that governs whether
  any of this exists), and `Tests/EmbedAttachmentProbeTests.swift` for the two measurements
  quoted in the Context.

## Context

ADR-0018 slice 3 draws a picture where `![[foto.png]]` is written. It draws every picture at
the same size, and the size is a constant in two places: `EmbedTable.renderWidth = 720`
(`NoteTextView+Embeds.swift:86`) and `EmbeddedFileView.renderWidth = 720`, kept equal on
purpose so that one render serves the editor and reading mode alike. Nothing else about the
picture's size is decided anywhere - the attachment is handed an `NSImage` and no bounds
(`EditorDecorationDelegate.swift:252-256`), so TextKit derives the layout bounds from
`image.size`, which is whatever `ThumbnailStore` happened to return.

That is fine for one picture and wrong for a note. A screenshot of a whole window and a small
diagram both arrive at the same width; a note that puts four pictures in a row has no way to
make three of them small and one large; and there is no gesture for size at all, in an editor
whose whole slice-3 argument was that *a picture on screen needs the operations a person
performs on a picture*. The one already delivered is deletion. This is the second.

**The syntax is not ours to invent, and it already parses.** Obsidian sizes an embed with
`![[foto.png|300]]` and `![[foto.png|300x200]]`, verified for the SPEC against two sources
rather than recalled. What matters here is what the codebase already does with it:
`Attachment.embed(inLine:)` (`Sources/Core/Conventions/Attachment.swift:29-37`) splits the
wikilink's inner text on `|` and keeps the part before it, with a comment that has been sitting
there since M1 - *"`![[foto.png|300]]` sizes the embed in Obsidian; the name is the part before
the pipe, and the size is not ours to interpret yet"*. So `Transclusion.target(ofLine:)` already
answers `.file`, `embedRun(inLine:)` already returns the whole run, `MarkdownStyler` already
emits `.embedRun`, and a note written in Obsidian with `![[foto.png|300]]` **already draws
today** - at 720, ignoring what it says. Every layer of the recogniser is in place and only the
last inch is missing: reading the number. That is the strongest single fact shaping this ADR, and
it is why nothing below touches `Attachment`.

**What the editor can and cannot do to itself.** Three constraints, all load-bearing:

- `EditorDecorationDelegate` is not `@MainActor` - Swift 6 refuses the conformance - and holds
  no `NSTextView`. Its own header says so, and PR #96 exists because an accessibility element
  was built there and had no view to parent itself to. Nothing interactive can live on it.
- The paragraph the delegate substitutes must keep its length
  (`NSTextContentManager.h:120`), so the size can never be encoded as extra characters in the
  displayed copy. It has to be an attribute of the attachment.
- `CompletingTextView` already owns exactly one custom mouse entry point,
  `mouseDown(with:)` in `CompletingTextView+Pasteboard.swift:15-19`, which offers the click to
  `onClickInMargin` and falls through to `super`. Three decorations are chained behind that
  one closure in `NoteTextView.wire(_:to:)`. There is no `mouseDragged` or `mouseUp` override
  anywhere in this codebase, and no drag of any kind on a decoration.

**What was already measured here, and what it removes from this decision.**
`Tests/EmbedAttachmentProbeTests.swift` was written for ADR-0018 §D6 probe 6 and answered two
sub-questions this ADR needs, in this project, on this SDK:

> Sub-question 2: attachmentBoundsForAttributes:... does fire for an attachment that lives
> only in the substituted paragraph, never in the real backing store.

with `#expect(attachment.boundsQueries > 0)` against a `LoggingAttachment: NSTextAttachment`
subclass overriding `attachmentBounds(for:location:textContainer:proposedLineFragment:position:)`
- and, in the same test, `#expect(attachment.imageQueries == 1)`: one draw pass asks the
attachment for its image exactly once, and no placeholder glyph paints underneath it. So a
subclass of `NSTextAttachment` is consulted for both its bounds and its image, for an attachment
that exists only in a substituted paragraph. That is the mechanism this whole ADR hangs on and
it is not a hope.

The SDK on disk agrees about what those two hooks mean. `NSTextAttachment.h` in
`MacOSX26.5.sdk`, verbatim:

> `:40` Returns the layout bounds. […] The NSTextAttachment implementation returns -bounds if
> not CGRectZero; otherwise, it derives the bounds value from image.size. Conforming objects
> can implement more sophisticated logic for negotiating the frame size based on the available
> container space and proposed line fragment rect.

> `:37` Returns the image object rendered at bounds inside textContainer. It should return an
> image appropriate for the target rendering context derived by arguments to this method.

Both hooks receive the `textContainer`. That is where the editor's column width comes from, at
layout time, on every pass - which is the fact that decides D2 and D3 below.

## Decision

**D1. The size is read out of the note's own text and nothing else stores it.**

`![[foto.png|300]]` draws 300 points wide; `![[foto.png|300x200]]` draws 300 by 200;
`![[foto.png]]` draws exactly as it does today. There is no per-embed record anywhere - not in
the index, not in `.pergamenum/`, not in frontmatter, not in a table on the Coordinator. This is
ADR-0018 §D3's own argument one level down, and it is repeated here because it is repeatable:
*"it is rebuilt from the text on every layout pass […] it cannot survive the thing it describes,
because it does not outlive the pass that made it."* A size held anywhere but in the characters
is a size that undo, redo, an FSEvents reload and the conflict banner's "Ricarica da disco" can
all put out of step with the note - and there is nothing downstream that would notice.

`Attachment.embed(inLine:)` is **not touched**. It already discards the suffix and gives the
right target for a sized embed, and it is a `Sources/Core` file compiled into `perg` and
`pergamenum-mcp`; the size is a fact about how the editor draws, and neither connector draws.
The reader is a new pure function in the editor layer, `EmbedResize.written(inRun:)`, returning
`.width(W)` or `.both(W, H)` or nil, beside `embedRun(inLine:)` where the rest of the editor's
own embed recognition already lives.

Rejected: **a `size` property on `Attachment.Embed`.** It puts an editor concern into a Core
type that two command-line tools compile, it changes the synthesised `Equatable` for every
existing comparison of an `Embed`, and reading mode - which SPEC keeps at 720 - would then be
carrying a field it must ignore. The cost is real and the benefit is a shorter call site.

Rejected: **any syntax of our own** - a custom attribute, a frontmatter map, an HTML `<img
width>`. SPEC's scope section rules it out in one line, and principle 4 is why: a vault that
opens in Obsidian without conversion cannot carry sizing this app alone can read.

**D2. The size is applied by an `NSTextAttachment` subclass, in the two hooks the SDK already
calls, and by nothing else.**

`EmbedAttachment: NSTextAttachment` carries the written size (or nil) and the natural size, and
overrides both members of `NSTextAttachmentLayout`:

- `attachmentBounds(for:location:textContainer:proposedLineFragment:position:)` returns the
  resolved size. It has the `textContainer`, so the column is available *at layout time*, on
  every pass, without anyone pushing a number in.
- `image(for:attributes:location:textContainer:)` returns the picture drawn at exactly that
  bounds size, with the handle composited into it (D5).

`EditorDecorationDelegate.embedParagraph(at:storage:)` changes by three lines: it constructs an
`EmbedAttachment` instead of an `NSTextAttachment`, and hands it the size it parses from the
marker text it already re-reads through `stillSpellsAnEmbed`. It gains no new input, no new
stored property, and no knowledge of the container - which is exactly what it must not gain,
being neither `@MainActor` nor in possession of a view.

Rejected: **setting `attachment.bounds` from the delegate.** The header says a non-zero `bounds`
wins, so it would work - and the delegate has no container, so the column width would have to be
pushed in from the Coordinator on every styling pass and would be stale for exactly as long as a
window resize takes to reach the next pass. A note saved `|900` on a wide window, reopened
narrow, would draw past its own column until something else invalidated it. The negotiation hook
is correct by construction where the pushed value is correct by timing.

Rejected: **a custom `NSTextLayoutFragment`**, ADR-0018 §D3's stated fallback and the shape
`TranscludedLineFragment` and `FoldedHeadingFragment` already have. It is the right fallback and
the wrong default: the attachment route is already proven for this content (probe 6), it keeps
the picture inside TextKit's own attachment machinery - which is what
`frameForTextAttachment(at:)` reads, and therefore what the click, the caret and the
accessibility element all depend on - and a custom fragment would put the picture's geometry in
a second place. It stays available if D8's probe 1 fails.

**D3. One pure function resolves the drawn size, and everything that needs a size calls it.**

`EmbedResize.resolved(written:natural:column:) -> CGSize`:

- no written size: the natural size, width-clamped to the column, height scaled proportionally.
  This is R-06's *"dimensione di partenza naturale/thumbnail"* and it is today's behaviour plus
  a clamp;
- `.width(W)`: `W` clamped to `[80, column]`, height proportional to the natural aspect ratio;
- `.both(W, H)`: `W` clamped to `[80, column]`, `H` clamped to `[80, ∞)`. Free aspect ratio, per
  SPEC's scope - width and height move independently and the original ratio is not preserved.

**The column is `textContainer.size.width` minus twice its `lineFragmentPadding`, read from the
live container, and never a constant.** That is the same source `applyTransclusions` already
reads (`NoteTextView+Transclusion.swift:22-24`), and the padding term is the difference between
the column and what a line can actually occupy in it. `80` is a constant, on
`EmbedResize.minimumSide`, in the company of `TranscludedRendition.padding` and
`maximumBodyHeight` - a geometric floor is not a colour and does not want a design token.

Three callers, one rule: `EmbedAttachment.attachmentBounds` (what is drawn), the drag's own
per-frame clamp (what the overlay shows, R-05 - clamped *during* the drag, not only at commit,
because a rectangle that follows the pointer past the margin and then snaps back at release is a
different gesture from one that stops at the margin), and the commit that formats the suffix
(what is written). Three call sites of one function is the whole of why R-05 cannot disagree with
itself.

**D4. The render is asked for at the size it will be drawn at, and the cache key changes with
it. Reading mode is not touched.**

`EmbedTable.rendition(forSyntax:notePath:root:thumbnails:offset:)` already receives the run's own
text, so it parses the written size with the same `EmbedResize.written(inRun:)` and asks
`ThumbnailStore.thumbnail(for:width:)` for that width instead of the constant. **The signature
does not change** - the width is derived from an argument it already has, which also keeps it
under the parameter count SwiftLint caps this file at (`apply(runs:…)`'s own comment records
that the limit is already reached next door).

`renderWidth = 720` **stays**, demoted from "the width every embed renders at" to "the width an
embed with no written size renders at". So an unsized embed asks for exactly what it asks for
today, shares its render with `EmbeddedFileView` exactly as today, and nothing about reading mode
moves - `EmbeddedFileView.renderWidth` is not read, not changed, and not mentioned again.

The cache key becomes `"\(relativePath)@\(ThumbnailStore.bucket(for: width))"` rather than
`"\(relativePath)@\(Int(renderWidth))"`. Keying by the bucket rather than the request is what
makes two embeds at 300 and 310 share one render instead of holding two entries for one file that
`ThumbnailStore` would answer identically - the store quantises internally
(`ThumbnailStore.swift:119-122`, seven steps) and this key is what stops the table above it from
being finer-grained than the store below it.

**`ThumbnailStore`'s own header already anticipated this feature**, for the Workspace: *"Sizes
are quantised so that dragging a resize handle does not spawn a render per frame: SPEC §6.5 asks
for a regenerated thumbnail at the end of a resize, not during it."* This ADR's drag writes at
`mouseUp` and only then, so the re-render happens once per gesture, in the shape that comment
already describes. Nothing in the drag path touches `ThumbnailStore` at all.

**D5. The handle is drawn inside the picture, by the attachment, and is not a view.**

A 14-point square, inset 3 points from the picture's bottom-right corner, composited into the
image `EmbedAttachment.image(for:…)` returns, in a colour pushed in from the theme exactly as
`decorations.badgeColor` already is (`NoteTextView+Coordinator.swift:142`) - one line beside it,
no signature change anywhere.

**Inside the bounds, never outside**, and that is the load-bearing word. The attachment's bounds
are what `frameForTextAttachment(at:)` reports, which is what `selectEmbed(at:in:)` hit-tests
against and what `CompletingTextView+Accessibility` (PR #96) sets as the embed element's
accessibility frame. A handle drawn outside the bounds would have to grow them, and every one of
those would silently move. Drawn inside, the geometry of this ADR is byte-identical to the
geometry without it.

Rejected: **an `NSView` subview per drawn embed, or one overlay view listing them all.** Both
need the embed frames recomputed and the subview frames rewritten on every layout pass, every
scroll and every window resize - a second copy of geometry TextKit already owns, kept in step by
hand. The compositing route has no state to keep in step: the handle is at the picture's corner
because it is painted at the picture's corner.

Rejected: **a handle that appears on hover.** SPEC R-01 says it appears on every drawn embed;
hover state on a text attachment means tracking areas that move with the layout, which is the
subview problem again wearing a hat.

**D6. The drag is three overrides on `CompletingTextView` forwarding to one closure, and the
state lives on the Coordinator.**

`CompletingTextView` gains `var onEmbedResize: ((EmbedResize.Phase) -> Bool)?` - the same shape
as `onClickInMargin` and `claimsCommand`, and for the reason `claimsCommand`'s own comment gives:
*"this view has exactly one owner, and a closure makes that owner's identity a non-issue."*
`mouseDown` offers `.began` **before** `onClickInMargin`; `mouseDragged` and `mouseUp` offer
`.moved` and `.ended` and fall through to `super` when unclaimed. `.moved` and `.ended` answer
false whenever no drag is in progress, so an ordinary selection drag is untouched.

**How it coexists with click-to-select.** `.began` is claimed only when the point falls inside
the handle's hit rect - a 22-point square around the 14-point handle, so the target is bigger
than the paint, which is the ordinary allowance for a small control. Every other point on the
picture is not claimed, `onClickInMargin` runs next, and `selectEmbed(at:in:)` answers exactly as
it does today. The two cannot both claim a point, because one tests a corner square and the other
tests the frame only after the first declined. And a press inside the handle that moves nothing
before release rewrites nothing (the resolved size is unchanged) and selects the run instead, so
a click on the handle behaves like a click on the picture rather than like a dead zone.

The hit rect is computed from `selectEmbed`'s own arithmetic, read rather than rewritten:
`NSTextLayoutFragment.frameForTextAttachment(at:)` for the fragment-local rect,
`+ layoutFragmentFrame` to reach the container, `Coordinator.inContainer(_:of:)` to bring the
click into the same space (`NoteTextView+Transclusion.swift:204`), all inside the shared
`decoration(at:in:claimedBy:)` walk. `NoteTextView+EmbedResize.swift` is a Coordinator extension
beside `NoteTextView+EmbedCaret.swift` and does the same thing to the same numbers.

Rejected: **an event-tracking loop** (`NSWindow.trackEvents` inside `mouseDown`), the classic
AppKit resize-handle idiom, which would hold the whole gesture in one function with no stored
state. It cannot be driven by a test: the loop blocks on real events, and this project's unit
suite is the only place R-02, R-04 and R-05 can be asserted at all. Three overrides forwarding to
one method mean a test calls `resizeEmbed(.began(p), in: view)`, `.moved`, `.ended` directly - the
exact shape `EmbedCaretTests` already drives `selectEmbed(at:in:)` in. Testability decides this,
and the price is named: AppKit's own delivery of `mouseDragged` to the view that took the
`mouseDown` is then not covered by any test, and belongs to the on-screen check (probe 2).

**D7. Nothing is written until `mouseUp`, and then exactly one edit is made.**

During the drag: an `EmbedResizeOverlay: NSView`, added as a subview of the text view at
`.began`, its frame rewritten at each `.moved`, removed at `.ended`. It draws the pending
rectangle's border and the size as `W × H`, in colours and a font pushed in from the theme at
creation - the same way `TranscludedRendition` receives `ruleColor` and `captionColor`
(`NoteTextView+Transclusion.swift:98-99`) - because a view that takes a colour without a token
does not pass review. It returns nil from `hitTest(_:)`, so it is paint and never a responder.
Being a subview of the text view rather than of the scroll view, it scrolls with the text for
free. `NSTextStorage` is not touched, the layout is not invalidated, and `ThumbnailStore` is not
called: the overlay draws the already-rendered `NSImage` scaled, which is why a drag costs
nothing per frame and why R-02's "no source-text change during the drag" is a property of the
design rather than a rule someone has to keep.

At `.ended`, one replacement over the whole run - the range
`drawnEmbedRange(atParagraphStart:in:)` already returns - with the run rewritten to carry the
suffix. **Through the mechanism that already produces exactly one undo step in this feature**:
`NoteTextView+EmbedCaret.swift:92-102`'s `deleteAtomically`, generalised to
`replaceAtomically(_:with:in:)` and called by the existing deletion with `""`. Its own comment
states the discipline and the precedent it took it from - *"One undoable step, on the exact model
of `NoteTextView+Matches.swift`'s own `apply(_:to:)`: `shouldChangeText` first,
`beginEditing`/`replaceCharacters`/`endEditing`/`didChangeText()` after, and a stale range […]
skipped rather than trusted."* R-04 is that call and nothing else; a drag of one pixel and a drag
of four hundred produce the same single edit because there is only ever one.

`didChangeText()` then runs the chain that already exists: `Coordinator.textDidChange` sets
`parent.text`, calls `applyStyling`, `applyEmbeds`, `applyTransclusions`, `applyReveal`
(`NoteTextView+Coordinator.swift:174-190`) - so the new size is parsed, the render is requested at
the new width, and the picture redraws, on the same runloop pass as the release. Persistence is
`VaultSession.write` on the far end of `parent.text`, untouched, which is also the whole of R-08:
reopening reads the suffix through the same path a fresh open always did. The selection is left
on the rewritten run, which is where `selectEmbed` leaves it and which keeps ADR-0018 §D5's rule
that the caret never enters a drawn embed.

**The suffix.** `|W` when the resolved height is the proportional height for `W` within a point
after rounding, `|WxH` otherwise, integers, lowercase `x` - the two forms SPEC verified and no
third. The whole run is rewritten from its parsed target, so an embed that already carries a
suffix has it replaced rather than appended, and an embed with none gains one.

**A CommonMark embed gets no handle, and this is the one place SPEC and this ADR need a word.**
R-01 says every drawn image or PDF embed. ADR-0018 §D3 draws two spellings, and Obsidian's
verified sizing syntax exists only for the wikilink one: `![alt](foto.png|300)` was not verified
and SPEC's scope forbids writing any syntax that was not. So `![alt](foto.png)` keeps drawing
exactly as it does today and shows no handle - there is nowhere to put the answer. The
alternative, rewriting the author's `![alt](…)` into `![[…|300]]`, changes a spelling ADR-0018
§D3 went out of its way to preserve for vaults written elsewhere, on a gesture the person asked
nothing of the kind for. This app's own writers - `EditorEdits.embed(forFileNamed:)`,
`Wikilink.swift:269`, the drop path and the paste path - emit only the wikilink form, so no note
this app created is affected.

**D8. `hidesMarkup` off means no handle, through the same guard and not a second one. And this
ADR does not touch `CompletingTextView+Accessibility.swift`.**

`drawnEmbedRange(atParagraphStart:in:)` is the single answer to *is a picture actually on screen
at this offset right now* - it checks `hidesMarkup`, that a rendition exists, that an embed
marker is registered there, and that the characters still spell an embed
(`EditorDecorationDelegate.swift:298-306`). The handle's hit test calls that same function, exactly
as `selectEmbed` and `claimsEmbedCommand` do, rather than carrying an equivalent check of its own,
and gets R-07 free along with the two edge cases SPEC names for nothing: a render still in flight
has no entry, so no handle, and a `.missing` embed is not `.drawn`, so no handle either - the
`guard case .drawn` is one line on top of the range lookup. `claimsEmbedCommand`'s own R4 comment
says why the check is repeated at the caller rather than delegated, and the same reasoning stands
here.

**`CompletingTextView+Accessibility.swift` is not modified by this ADR, and cannot be affected by
it by accident.** R-10 puts keyboard and VoiceOver resizing out of scope: the handle gets no
`NSAccessibilityElement`, no role, no action, and appears nowhere in `accessibilityChildren()`.
That file builds one image element per drawn embed from `drawnEmbedRange` and sets its frame from
`frameForTextAttachment(at:)` - so the *only* two ways this ADR could disturb it are by changing
which offsets draw an embed (it does not: D1 changes no recogniser, and D8 reuses the same
`drawnEmbedRange`) or by changing the attachment's bounds relative to the picture (it does not:
D5 keeps the handle strictly inside the bounds). What that file does inherit, for free and
correctly, is the new size: a resized embed's accessibility frame follows its picture because it
is read from the picture. That is the whole of the interaction and it is in the right direction.

*(As of this writing PR #96 is **open**, not merged - `main` has no
`CompletingTextView+Accessibility.swift`. Nothing in this ADR depends on it landing; both
branches touch `CompletingTextView`'s stored properties and `embedParagraph(at:storage:)`, which
is a textual conflict and not a design one. See the Consequences.)*

**Two probes, with a pass criterion each, before anything is built on them.**

1. **A non-default `attachmentBounds` return actually sizes the line.** Probe 6 measured that the
   override *fires*; it never measured that a returned rect different from `image.size` is
   honoured. Return 200 × 150 for an image whose natural size is 64 × 48, in a substituted
   paragraph, image and PDF first page alike (R-09). **Passes** when the layout fragment's height
   follows the returned bounds and `image(for:)` is handed the same rect. Failing, D2's rejected
   `attachment.bounds` route is tried next with the column pushed in from the Coordinator, and
   only if that also fails does ADR-0018 §D3's custom-fragment fallback come out.
2. **`mouseDragged` reaches a view whose `mouseDown` did not call `super`.** Not answerable
   offscreen - it is AppKit's own event dispatch, and calling the override directly from a test
   proves our logic and not the delivery. It is the assumption D6 rests on. It belongs to the
   on-screen check, with a written result, held to the standard ADR-0010's Consequences set:
   *"not a reason to decide differently; a reason not to claim the feature works until someone
   has clicked there."*

## Consequences

- **The note gains characters it did not have, and that is the feature.** Every other transform
  in ADR-0018 is display-only and this one writes. `|300` goes into the file, through
  `parent.text` → `VaultController.updateOpenNoteText` → `VaultSession.write`, with `NoteHistory`
  snapshotting it like any edit. It is the author's own note gaining Obsidian's own syntax, but
  it is a write, and the one-undo-step discipline of D7 is what makes it a normal one.
- **An embed sized in Obsidian is honoured the moment this ships, with no migration.** The
  recogniser chain has been discarding the suffix since M1 and drawing the picture at 720
  regardless. Notes already in the Labs vault written with `|300` will change size on first open
  after this lands. That is correct, it writes nothing, and it is worth expecting rather than
  being surprised by.
- **A resized embed stops sharing its render with reading mode.** Today the editor and
  `EmbeddedFileView` both ask 720, which buckets to 960, so one file is one render. An embed
  written `|300` asks 300, buckets to 320, and becomes a second cache entry and a second file
  under the thumbnail directory. That is the point rather than a cost - a picture drawn at 300
  points should not be a 1280-pixel render - and the ceiling is `ThumbnailStore`'s own seven
  buckets, so a file can cost at most seven renders over its whole life however often it is
  resized.
- **A picture drawn larger than the bucket it was rendered at is a picture drawn soft.** The
  bucket ladder rounds *up*, so this only happens transiently: between the release and the new
  render landing, the old image is scaled into the new bounds. One pass, then the right render
  arrives through `setRenditions` and redraws. Named because "the picture goes blurry for a
  moment when I let go" is a defect report somebody would otherwise open.
- **`EmbedTable.renderWidth`'s own comment becomes wrong and has to be rewritten.** It currently
  reads *"The width every embed renders at, matching `EmbeddedFileView.renderWidth` bit for
  bit"*, and both halves stop being true: it is the width an *unsized* embed renders at, and the
  bit-for-bit match now only holds for that case. A comment carrying a rule the code no longer
  keeps is how the next reader gets the old rule and never sees the new one - the same finding
  ADR-0018's Consequences recorded about six comments, one of which was in this file's
  neighbourhood.
- **`deleteAtomically` is generalised and renamed.** One call site
  (`NoteTextView+EmbedCaret.swift:63`), file-private, no test names it - grepped. The check is
  the full unit suite, not that grep.
- **`applyEmbeds(to:)` keeps its signature and `applyStyling(to:theme:)` gains one line.** The
  handle's colour is set beside where `decorations.badgeColor` is already set from a theme token
  rather than threaded through `applyEmbeds`, which has no theme and would need one at three call
  sites (`NoteTextView.swift:152`, `NoteTextView.swift:243`,
  `NoteTextView+Coordinator.swift:178`).
- **`CompletingTextView` gains its first drag, and with it a class of defect this codebase has
  never had.** Every existing mouse interaction is a click that either claims the point or does
  not. A drag has a beginning, a middle and an end, and the end can be missed - the pointer
  leaves the window, the window loses key, the app is switched away mid-gesture. `.ended` is the
  only thing that removes the overlay and writes the text, so a missed `mouseUp` leaves a
  rectangle painted over the note and no write. Recovery on window-resigned-key is deliberately
  not designed in here; the on-screen check is where this is looked for, and if it bites the fix
  is a `cancelOperation` and a resigned-key hook, not a redesign.
- **The unit suite can carry more of this feature than it could carry of ADR-0018 slice 3, and
  still not all of it.** The size grammar, the clamp, the suffix formatting and the run rewrite
  are pure and go offscreen. The gesture goes through a real `CompletingTextView` in a real
  `NSWindow`, the fixture `EmbedCaretTests` already built. What stays out: whether AppKit
  delivers the drag at all (probe 2), whether the handle is visible enough to aim at, and whether
  the rectangle tracks the pointer without lag. Those are the on-screen check and
  `scripts/uitests.sh` before the merge, per the working agreements.
- **PR #96 is open and touches the same two files.** It adds a stored property to
  `CompletingTextView` and rewrites the `.accessibilityAttachment` lines of
  `embedParagraph(at:storage:)`; this work adds a stored closure to the first and constructs an
  `EmbedAttachment` in the second. Textual conflict, trivial to resolve, but it decides where
  this branch forks from - and if #96 lands first, the accessibility test it adds to
  `EmbedCaretTests` is one more thing the full suite has to keep green through D2's change of
  attachment class. Nothing here should be merged without deciding that order deliberately.
- **`![alt](foto.png)` becomes a second-class embed in a way a person can see.** It draws, it
  deletes, it selects, and it has no handle. The rule that sorts the two spellings is Obsidian's
  own syntax and not a judgement about the spellings, but it is a difference somebody has to be
  told once - the same shape as ADR-0018's own *"the two `![[…]]` forms now look different in the
  same editor"*.
- **The SPEC is not amended.** SPEC §5 and §14 were already amended by ADR-0018 for the whole of
  hidden syntax and drawn embeds; sizing an embed that is drawn is inside that amendment, not a
  new incursion into a ruling. R-01's wikilink-only reading is recorded in D7 rather than as a
  SPEC change, because it is a consequence of the verified syntax and not a change of intent.
