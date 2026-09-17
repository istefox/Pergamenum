# ADR-0018: The editor hides the syntax it can draw

- Status: accepted
- Date: 2026-08-22. Written from a defect Stefano hit by hand - an embedded picture takes
  twenty-seven presses of Backspace to remove, because in the editor it is nothing but text -
  and from two pieces of evidence that predate it: the TextKit 2 measurements of 2026-08-17,
  taken in this project, and a source reading of five open-source editors done for this
  decision. Four points are left for acceptance rather than assumed, and are named at the end
  of D7 and in the Consequences.
- Supersedes: nothing. **Amends SPEC §14** (*«Live preview completa | Esclusa v1 | Voce di
  costo massima; source mode con stile è sufficiente»*) and **SPEC §5** (*«sorgente visibile
  con stile applicato … NON live preview completa che nasconde la sintassi (fuori scope
  v1)»*), narrowly and in the shape ADR-0013 amended §7.3: three named constructs, not the
  rule. **Amends ADR-0005 §D2**, whose case for the Diario pane's two panes is that "the
  source keeps every character of its syntax and its styling, exactly as the Note pane's
  editor does".
- Depends on: `docs/20260817_TextKit2_live_editing.md` for every measurement quoted below, and
  **ADR-0010 §D2** for the rule that decides whether a `![[…]]` names a file or a note - this
  ADR takes the file branch and leaves the note branch exactly where ADR-0010 put it.

**Scope note (2026-09-17, ADR-0047 §D12 re-audit):** the Obsidian round-trip is no longer a
binding constraint. The decision below stands as taken and the format it chose is unchanged;
what no longer applies is the obligation that a future change keep Obsidian able to read the
result. Body untouched.

## Context

The editor is a TextKit 2 `NSTextView` that styles the markdown source in place and hides
nothing. `MarkdownStyler` says so in its own header - *"this never removes or replaces
characters - it only says what each range is"* - and it is right to: the buffer is the file.
`textDidChange` assigns `parent.text = textView.string`, that string reaches
`VaultController.updateOpenNoteText`, and `VaultSession.write` puts it on disk with
`NoteHistory` and, for a connector, `WriteJournal` recording the same bytes. There is no
serialisation step between the text view and the file, and principle 1 is that absence.

Two decisions put it there. SPEC §14 rules out live preview as the highest-cost item in the
project. ADR-0005 §D2 then built the Diario pane on the ruling: the rendering sits *beside* an
unchanged source editor, and *"this is not the live preview §14 rules out"* is the sentence
that makes the pane legal.

**What reopened it is not a wish, it is a gesture that does not exist.** A note holding
`![[foto-1-chi-siamo-2.jpg]]` gives no way to remove that picture other than twenty-seven
presses of Backspace, because the editor has no idea the twenty-seven characters are one
thing. Everything else about an embed already works - the Inserisci menu writes it, a drop
writes it, a click opens Quick Look (`EditorColumn+Text.swift:26`), reading mode draws the
picture (`EmbeddedFileView`) - and the one operation missing is the one a person performs on
a picture they no longer want.

**What was measured here, in this project, on 2026-08-17.** The SDK on disk still says what
the study quoted; `NSTextContentManager.h:120`, verbatim:

> Returns a custom NSTextParagraph for range in NSTextContentStorage.attributedString. When
> non-nil, textContentStorage uses the text paragraph instead of creating the standard
> NSTextParagraph with the attributed substring in range. **The attributed string for a custom
> text paragraph must have range.length.**

That constraint is the guarantee this project needs rather than an obstacle: the display may
differ from the storage in attributes and never in length, so no mechanism built on it can
change a single character of the file. Measured through it, with a 0.01pt font on the two `**`
runs of `**grassetto** e testo`:

| | x of the text after `**grassetto**` | line height |
|---|---|---|
| baseline | 117.51 | 16.00 |
| delegate substitution, font 0.01 | **85.39** | **16.00** |

32.12 points recovered over four hidden characters against a 7.81pt advance: the run collapses
to nothing and the line does not shrink, because the rest of it still carries the real font.
Reveal - hiding and bringing back without touching the text - was measured too:
`storage.edited(.editedAttributes, range: paragraphRange, changeInLength: 0)` re-invokes the
delegate, invalidation is **local** (the delegate was asked for exactly two paragraphs, the one
edited and the one after), and the round trip costs **0.89 ms** against the 5.83 ms
`MarkdownStyler.spans` already spends on every keystroke of a 17 KB note. The transform is not
the expensive part of this idea.

Three things the same study found that shape everything below. **The caret walks through
hidden characters**: `NSTextSelectionNavigation` knows nothing of the display transform, and
moving backward by character from offset 3 over a collapsed `**` visited 2, 1, 0, 0. **The
delegate cannot be `@MainActor`** - Swift 6 refuses the conformance - so it holds plain values
handed to it from outside, which is exactly what `EditorDecorationDelegate` already does for
folding and transclusion. And **a picture is not a substitution**: an attachment is one
character (`NSTextAttachment.h:19`, `NSAttachmentCharacter = 0xFFFC`, and the convenience
initialisers at `:98-101` create *"an attributed string containing attachment using
NSAttachmentCharacter as the base character"*), while `![[foto.png]]` is thirteen and the
length may not change.

**What five other editors do, read in their source rather than in their marketing.** Typora and
NotePlan, the two products this is modelled on, publish nothing verifiable about their engines
and are cited here as behaviour, never as technique - there is no source to read. The five that
could be read:

- **muya** (Marktext's engine, Typora-inspired) is *hybrid*. Emphasis and links are text whose
  delimiters a CSS class collapses, chosen by comparing the token's range with the cursor
  (`inlineRenderer/renderer/index.ts:125-134`). Images are atomic DOM nodes with
  `contenteditable: 'false'` and `dataset.raw` holding the exact markdown
  (`renderer/image.ts:37-46`). One-key deletion is free by construction, and the bill arrives
  in serialisation: the source is not diffed, it is rebuilt from scratch after every edit by
  re-reading `data-raw` off whichever nodes are still in the DOM (`selection/dom.ts:51-73`).
- **Milkdown** (ProseMirror) is a document tree; the image node is `atom: true, inline: true,
  isolating: true` and needs no deletion handler at all. Its bill is a dedicated
  `inline-nodes-cursor-plugin.ts` intercepting `beforeinput`/`compositionstart` to work around
  a Chrome cursor bug between adjacent atoms, and a round trip that regenerates syntax from
  `src`/`alt`/`title` instead of preserving the author's bytes.
- **Vditor's Instant Rendering** is the closest concept - one pane, syntax hidden - and still
  text, with `vditor-ir__marker` collapsed by `width:0;overflow:hidden`, which is the same
  trick as a 0.01pt font. Deletion is *not* free: an ordinary Backspace touches one marker
  character and the whole block is then re-parsed by an external WASM engine and its HTML
  replaced.
- **Zettlr** (CodeMirror 6, the same engine as Obsidian's Live Preview, and open) is the most
  instructive. `Decoration.replace` with a `WidgetType`, and **no dedicated state whatsoever**:
  no `atomicRanges` anywhere in `markdown-editor/`, no deletion logic for widgets. The buffer is
  always only text; a Backspace touching a delimiter makes the Lezer tree stop matching, the
  decoration disappears, the raw markdown comes back. The "atomic" behaviour is emergent, not
  written. It also needs no IME handling at all, where Vditor and muya both carry composition
  flags.
- **Ghostwriter** (C++/Qt, `QPlainTextEdit` + `QSyntaxHighlighter`) is the nearest architectural
  relative of an `NSTextView` among the five - a real native text widget with no DOM under it -
  and the finding is negative and was confirmed by grep: **it does not hide markdown at all**.
  Colour on the markup, full colour on the text, images never drawn inline, preview in a
  separate HTML pane. The same two-channel architecture Pergamenum has today.

**The synthesis, which is what the decisions below rest on.** None of the five gets one-key
deletion for free without paying elsewhere: the cost lands either in keeping a mapping between
what is drawn and what will be written (muya, Vditor) or in cursor and IME defects at the edges
of adjacent atomic nodes (Milkdown). Zettlr shows that for *simple inline delimiters* the
cheapest correct design is not an explicit per-token reveal state machine but the ordinary
edit-and-reparse cycle - which in this codebase is `MarkdownStyler.spans`, already running on
every keystroke, and which the local study measured invalidating itself when the text changes.
And Ghostwriter shows there is no precedent to copy for the picture: nobody in this sample has
drawn an image inline in a native, non-browser text widget, which is why D6 gates that slice on
a probe rather than on a plan.

## Decision

**D1. Three delimiters are hidden - the `#` of a heading and the `*` or `_` of emphasis - by
substituting the paragraph, never by touching the text.**

`EditorDecorationDelegate` gains the second hook of the protocol it already conforms to.
`NSTextContentStorageDelegate` inherits from `NSTextContentManagerDelegate`
(`NSTextContentManager.h:118`), so the element-hiding hook folding uses and the
paragraph-substitution hook this needs are two methods on one object, which is what the SDK
requires: `NSTextContentStorage.delegate` is a single reference.

The substituted paragraph is the original attributed substring with a monospaced 0.01pt font
added over the delimiter ranges and nothing else changed. Identical length, so
`NSTextContentManager.h:120` is satisfied by construction rather than by care.

**The delimiter ranges come from `MarkdownStyler`, as two new `Span` cases, and not from a
second parser.** `.heading(level:)` today covers the whole line (`MarkdownStyler.swift:167`)
and `.bold`/`.italic` cover the whole run including their markers (`emphasis(_:at:)` returns
`cursor + 2 - index`), so nothing currently isolates the characters to hide. Two cases - a
heading marker and an emphasis marker - are added beside them, produced by the same walk
`applyStyling` already performs on every keystroke, so hiding costs one more append and no
second parse. It also makes disagreement impossible: the characters that are hidden and the
characters that are coloured come out of one pass over one string.

The compiler will ask about them in the two tables that have no `default` -
`MarkdownAttributedText.colorToken(for:)`, whose comment already calls it *"the one table that
must stay exhaustive"*, and `MarkdownStyler.suppressesSpellCheck(_:)`. It will **not** ask
about `MarkdownAttributedText.attributes(for:)`, which has a `default`, and that is the one
that needs a deliberate answer: a revealed delimiter should be dimmer than the prose it wraps,
and falling through to the default gives it the same colour as the text.

Rejected: **rendering attributes** (`NSTextLayoutManager.setRenderingAttributes`). The header
claims they are applied before layout; measured, they were not - a font of 0.01 and a kern of
-7.8 delivered through the validator both left the following text at exactly 117.51, unmoved.
The validator fires, so the channel is live; it colours without touching storage, which is why
`NoteTextView+Matches` uses it for the find bar. It does not collapse a run.

Rejected: **deleting the characters from the buffer and putting them back on save.** It is the
muya and Vditor design, it is where both of them pay, and here it would mean the editor's text
is no longer the file's text - which is the whole of principle 1 and the reason
`MarkdownStyler`'s header opens the way it does.

**D2. Reveal is a rule about a paragraph, and it has four triggers.**

Hiding without coming back is not what NotePlan feels like and is not editable. The delimiters
of a paragraph are drawn when any of these is true, and collapsed otherwise:

- **the caret is in that paragraph** - the ordinary case, and the only one a person will name;
- **there is marked text** (`hasMarkedText()`) - an input method composing inside a collapsed
  run is the first of the five unproven risks, and revealing for the duration of a composition
  removes the class rather than handling it. muya and Vditor both carry a composition flag for
  the same reason; Zettlr, on CodeMirror 6, needs none, which says the hazard is a property of
  the substrate and not of the idea;
- **the selection has a length and intersects the paragraph** - what is copied must be what is
  seen, and a selection dragged over collapsed markers otherwise puts characters on the
  pasteboard that were never on screen;
- **the find bar's current match intersects it.** `applyMatches` paints with a *rendering*
  attribute, which the measurement above says does not change metrics, so a hit inside a
  collapsed run would be a highlight 0.01 points wide. The stepper landing on a match must
  show it.

Triggered by `storage.edited(.editedAttributes, range:, changeInLength: 0)` **over the two
paragraphs involved - the one left and the one entered - and never over the document.**
`applyFolding` currently does the whole document (`NoteTextView+Coordinator.swift:126-128`),
which is correct for a fold and would be wrong here: this runs on every arrow key, and the
0.89 ms measured is the local figure. The guard is the shape `lastOutlineEntry` already has in
`textViewDidChangeSelection` - act when the paragraph *changes*, not on every keystroke.

Rejected: **reveal per token, by comparing the caret to each delimiter's range** - muya's
`checkConflicted()`. It is finer, it flickers less, and it is a second state machine that has
to be kept in step with the parse. The paragraph is the unit the SDK's own invalidation works
in, and matching the mechanism's granularity is what keeps the reveal from needing state at all.

**D3. An image or PDF embed is drawn as the picture or the first page, in place, and the
mapping problem is designed out rather than solved.**

Two spellings, both recognised, both alone on a line: `![[nome.est]]` (this app's own form,
resolving through `Attachment.resolve`) and CommonMark `![alt](nome.est)` (the form a vault
opened from Obsidian or written by hand may already contain, and that `Wikilink.swift` and
`MarkdownStyler` do not recognise today - a second recogniser is added beside the wikilink one,
resolving the path the same way any relative link does, `alt` carried through as the
attachment's accessibility label rather than drawn as text). Either spelling, resolving to a
file whose type conforms to `public.image` or to `com.adobe.pdf`, is drawn: the image itself,
or the PDF's first page through the same `PDFPage.thumbnail(of:for:)` call the Workspace card
already uses (SPEC §6.5) - a first page stands for a document in the Workspace already, so
drawing it inline is the existing rule applied to a second surface, not a new one. The
mechanism is an `NSTextAttachment` carried by the **substituted paragraph**, applied to one
character of the run, with the remaining characters collapsed by D1's instrument. Length
preserved: the run's character count in, the same count out, wikilink or CommonMark alike.

**Everything this ADR was asked to justify - where the mapping lives, how it survives
undo/redo, what happens when FSEvents delivers an external edit while an attachment is on
screen - is answered the same way: the question does not arise, and that is the reason for
this shape rather than the other one.** An attachment placed in the *backing store* would put
U+FFFC where `![[foto.png]]` is; `textView.string` would stop being the file; `textDidChange`
would hand that string to `VaultController.updateOpenNoteText` and `VaultSession.write` would
put an object replacement character on disk, into `NoteHistory` and into
`WriteJournal.textBefore`. Preventing that needs a durable attachment-to-source mapping, and
then: undo and redo move characters underneath the mapping, an FSEvents-driven reload replaces
the whole buffer under it, and the conflict banner's "Ricarica da disco" swaps the text while
the attachments stay. Every one of those is a place the mapping and the text can disagree, and
a disagreement means the file gets written wrong - silently, since nothing downstream inspects
what it is given. muya rebuilds its source from `data-raw` after **every** edit precisely
because this is not a problem you solve once.

The attachment in the substituted paragraph is a different object. It is rebuilt from the text
on every layout pass, exactly as `renditions` and `hiddenLineOffsets` already are; it is never
consulted when writing; it cannot survive the thing it describes, because it does not outlive
the pass that made it. There is nothing to keep in step. Undo and redo are ordinary text edits
and the drawing follows on the next pass. An external change reloads the buffer and the next
pass draws whatever the new text says. This is derivation in the sense principle 3 already uses
for the index, applied one level down.

**Where the picture comes from.** `ThumbnailStore` is an `actor` returning
`Task<NSImage?, Never>` and the delegate is synchronous and off the main actor, so the image or
the PDF's first page is rendered and handed over as a finished value keyed by line offset - the
shape `apply(renditions:)` already has, and the same store the Workspace card already calls, so
a thumbnail cached for one surface is not re-rendered for the other. The first pass over a line
has no image and leaves the raw text drawn; the render arrives and the second pass draws the
picture. That is `EmbeddedFileView.hasLooked` one surface over.

**The width is negotiated, not assumed.** `NSTextAttachmentLayout`'s
`attachmentBoundsForAttributes:location:textContainer:proposedLineFragment:position:` is handed
the proposed line fragment, and the header says conforming objects *"can implement more
sophisticated logic for negotiating the frame size based on the available container space"*. So
the line grows to the picture rather than the picture being clipped to the line, and unlike the
transclusion of ADR-0010 §D5 no `paragraphSpacing` has to be bought in advance.

**The fallback is already in this codebase.** If the probe of D6 finds that an attachment
attribute over a length-preserved multi-character run draws nothing, or draws once per
character, the picture is drawn by a custom `NSTextLayoutFragment` over the collapsed run
instead - which is what the study recommended, and which `FoldedHeadingFragment` and
`TranscludedLineFragment` are two working instances of. The decision is the *display-only*
principle; the instrument is the cheaper of two that both satisfy it.

**Both spellings, images and PDFs, and nothing else.** Widening past the wikilink form and
past images was a deliberate choice made against the draft of this ADR, not the cheaper
default: it costs a second recogniser (`Wikilink.swift:269` writes only the wikilink form,
`EditorEdits.embed(forFileNamed:)` too, so this app's own notes never need the CommonMark
branch - it exists for a vault that already holds notes written elsewhere) and it costs the
`.pdf` branch of D6's probe 6 in addition to the image one, since a rendered PDF page is a
second kind of attachment content to verify, not a free extension of the first. Both are
accepted here because the alternative - a vault opened from Obsidian showing some embeds as
pictures and some as raw brackets depending on which spelling a past editor used - is a worse
failure than the extra recogniser. A drawn PDF embed loses its previous click-to-Quick-Look
behaviour in favour of the click-selects-the-run rule of D5, consistently with a drawn image.

**D4. Everything else stays exactly as it is, and each exclusion has its own reason.**

- **`[[nota]]`** - the target is the readable part and hiding the brackets buys almost nothing;
  the completion after `[[` writes into that range, and a hidden delimiter under an open
  completion panel is the interaction with the most moving parts in the editor.
- **`![[nota]]`** - a transcluded note keeps ADR-0010 §D3 unchanged: the source line stays
  visible, the rendition is drawn underneath. A picture is the content; a transcluded note is a
  *reference* to content that lives in another file, and ADR-0010's own argument - *"provenance
  has to be visible - text that looks like the host note's own but is not is the one failure
  mode that makes a reader edit the wrong file"* - is the reason the two forms of `![[…]]` are
  treated differently here. One line can only be one of them: both `Attachment.embed(inLine:)`
  and `Transclusion.occurrences` require the embed to be the whole line, and ADR-0010 §D2's
  extension rule sorts them.
- **`#tag`** - a tag is a value a person reads and searches for, not punctuation around one.
- **Code fences** - inside a fence markdown is not markdown, which `MarkdownStyler.spans`
  already knows and spends its first pass establishing. Hiding anything there is hiding part of
  a program.
- **Tables drawn as a grid** - out of reach at sane cost, and the study says so: the fragment
  would have to lay out a grid over a length-preserved run.
- **`- [ ]` task markers** - a clickable checkbox in the text is reachable
  (`NSTextAttachmentViewProvider` exists) and is a separate decision with its own interaction,
  not a delimiter to collapse.

**D5. The caret is taught the run, and this is the largest piece of work in the ADR.**

Measured and not in doubt: the caret stops inside a collapsed run and the insertion point
appears not to move. It is handled in `doCommand(by:)` on `CompletingTextView` - the same layer
where the completion panel already claims arrows while it is open - and in the click handling
beside `onClickInMargin`.

- **Moving.** `moveLeft:`/`moveRight:` and their extending variants cross a collapsed run in
  one step, landing on its far edge. A revealed run - the caret is already in that paragraph,
  so by D2 it is drawn - behaves exactly as it does today, character by character. The skip
  applies only to what is collapsed, which is the rule that keeps it from feeling arbitrary.
- **Deleting a delimiter.** Ordinary. Backspace at the edge of a collapsed `**` deletes one
  character, the emphasis stops parsing, `MarkdownStyler` stops producing the marker spans and
  the raw text comes back on the same pass. This is Zettlr's emergent behaviour and it is
  correct here for the same reason: nothing has to be written for it.
- **Deleting a picture or a PDF page.** Not ordinary, and the reason this ADR exists.
  `deleteBackward:` with the caret at the right edge of a drawn embed run, and `deleteForward:`
  at its left edge, remove the **whole run** in one edit, through
  `shouldChangeText(inRanges:replacementStrings:)` so it is one undo step - the same discipline
  `apply(_:to:)` keeps for replace-all, and for the same stated reason: forty presses of Cmd+Z
  to get back is not an undo.
- **Clicking a drawn embed** selects the whole run.
  `NSTextLayoutFragment.frameForTextAttachmentAtLocation:` gives the rect (*"returns CGRectZero
  if location is not with any attachment"*), which is the same hit-test shape
  `openTransclusion(at:in:)` already uses against `renditionFrame`. With the run selected,
  Backspace and typing over it are the ordinary paths and need no case of their own.

**A drawn embed does not follow D2's reveal rule.** This is a deliberate exception and it is the
one place the two halves of the ADR pull apart. If a picture reverted to text whenever the caret
reached its line, then the caret would be inside text exactly when a person wants to delete a
picture, and Backspace would be back to removing one character of twenty-seven. So the picture
stays drawn, the caret steps over the run rather than into it, and the source is not editable in
place. The cost is stated in the Consequences and it is real: renaming the file in a drawn embed
becomes delete-and-retype rather than an edit.

**D6. Six probes, with a stated pass criterion each. Five gate slice 2 and one gates slice 3.**

The five the study named as unproven and able to sink this, each of which is about a collapsed
run in the middle of a line, which is why they belong to the slice that puts one there:

1. **Input methods.** Type an accented vowel through press-and-hold and through a dead key with
   the caret inside a paragraph that holds emphasis; type with a CJK input method if one can be
   installed. **Passes** when the composed character lands where it was typed and the
   marked-text underline is drawn at full size - which is what D2's `hasMarkedText()` trigger is
   for, and this probe is the check that the trigger fires early enough.
2. **VoiceOver.** Read a paragraph with collapsed markers and a drawn picture. **Passes** when
   the markers are announced as part of the line - the string *is* the accessibility value in a
   native text view, unlike a DOM - and the picture is announced as something rather than as
   silence. If it is silence, an accessibility description on the attachment is the fix and the
   probe says whether one is needed.
3. **Mouse selection across a collapsed run.** Drag from before an emphasis run to after it.
   **Passes** when the selection rectangle is continuous, the copied text is the full source
   including the markers, and the drag does not stall at the zero-width run.
4. **Undo coalescing.** Type a word, cross a paragraph boundary so a reveal fires, type another,
   then Cmd+Z. **Passes** when the undo steps are the typing and not the reveals -
   `.editedAttributes` with `changeInLength: 0` must not open an undo group. This is the one
   most likely to fail quietly and the one a user would report as "undo does nothing".
5. **Word wrap.** Put an emphasis run so its collapsed markers fall at the right margin, then
   widen and narrow the pane. **Passes** when the break lands where the visible text says it
   should and does not shift when the run is revealed - a reveal changing the wrap point makes
   the whole paragraph jump as the caret enters it.

And the sixth, which decides how slice 3 is built rather than whether it happens:

6. **An attachment on a length-preserved run, image and PDF page alike.** Apply `.attachment`
   to one character of a thirteen-character run in a substituted paragraph, with the other
   twelve at 0.01pt - once with an `NSImage`, once with a rendered PDF first page from
   `ThumbnailStore`. **Passes** when each is drawn exactly once and the line's height grows to
   it. Failing for either, slice 3 uses the custom `NSTextLayoutFragment` fallback of D3 for
   that content type and loses nothing but a day; the two are independent, so one can pass
   through the attachment route while the other falls back.

Three of these cannot be answered offscreen and two of them (1 and 2) cannot be answered by an
automated test at all - no UI test drives an input method or VoiceOver. They are hand checks
with a written result, held to the standard ADR-0010's Consequences already set: *"neither is a
reason to decide differently; both are reasons not to claim the feature works until someone has
clicked there."* The result of each goes into `PROJECT_BRIEF.md` beside the slice, not into a
commit message.

**D7. One setting governs the whole ADR, default on.**

`VaultSettings` gains one optional `Bool` in the Editor pane beside the spell checker. Off
restores today's editor exactly - every character visible, pictures as text, caret unmodified -
because both halves go through the same delegate and the same span list.

One switch rather than two, and rather than none. **Rather than none**, because this reopens a
decision SPEC §14 took on cost grounds and D5 removes an ability that exists today; a ruling
that has to be reverted in code if the reveal rule does not convince is a ruling nobody will
test honestly. **Rather than two**, because a person who wants pictures drawn but delimiters
visible is describing an implementation split, not a preference, and two toggles would need two
names nobody can write.

The setting is a vault setting and not a `UserDefaults` one, by ADR-0012 §D6's question: how
you want to read your own notes is a fact about the vault, not about this desk.

## Slices

Three, each usable on its own, each verified on screen before the next starts, and the setting
of D7 in from the first so that every one of them is revertible by a toggle.

1. **The instrument, on the `#` of a heading.** The delegate's paragraph-substitution hook,
   `MarkdownStyler`'s heading-marker span, D2's reveal rule with its four triggers, D5's
   crossing for one boundary, D7's setting. The heading marker is the cheapest possible case and
   deliberately first: it sits at the start of a line, so the caret can only arrive at it from
   the right or from above and the skip is one direction rather than two, and nothing can wrap
   inside it. This is the slice that answers the only question worth answering early - whether
   the reveal rule feels right - in the day the study said it should take.
2. **`*` and `_`, and the five probes.** Emphasis is the general case: two edges, in the middle
   of prose, able to fall across a wrap. Probes 1 to 5 of D6 belong here and gate acceptance,
   because every one of them is about exactly this shape. If two of them fail in a way that
   cannot be fixed cheaply, slice 1 still stands on its own and slice 3 is still reachable -
   which is why the delimiters and the picture are separate slices rather than one feature.
3. **The picture.** Starts with a mockup, per the design-system rule and per ADR-0010's own
   precedent: a picture drawn inline in the editor with no source line under it has no precedent
   in this app, and its width, its margins and what a selected embed looks like are appearance
   decisions. Then probe 6, then D3's drawing and D5's deletion and click **in one slice** -
   shipping a drawn picture without one-key deletion would be worse than today, since today at
   least the text is there to select.

Nothing follows slice 3. The exclusions in D4 are exclusions, not a backlog.

## Consequences

- **The file is untouched, and it is untouched by construction rather than by discipline.**
  Nothing in this ADR writes into `NSTextStorage`; every transform lives in a substituted
  paragraph the SDK requires to be the same length. So `textView.string` is still the note,
  `VaultSession.write` still receives markdown, `NoteHistory.record` still snapshots markdown
  and `WriteJournal.Entry.textBefore` still holds markdown - and `undo` in the connectors keeps
  comparing hashes of the same bytes it always did. That is the single most important
  consequence and it is why D3 refuses the persistent mapping.
- **`MarkdownStyler` grows two `Span` cases and the compiler names two of the three tables.**
  `colorToken(for:)` and `suppressesSpellCheck(_:)` have no `default` and will ask;
  `attributes(for:)` has one and will not, so the revealed delimiter's colour has to be added
  there on purpose. Grepped: the only other consumers of `Span` are the styler's own tests,
  which assert with `contains` and `filter` rather than on a whole set, so the additions do not
  break them - but the check is the **full unit suite**, not that grep, and it runs at the end
  of every turn anyway.
- **Six comments in the codebase state the old ruling as permanent and become wrong.**
  `EditorColumn+Text.swift:22-24` (*"The editor shows `![[foto.png]]` as text and always will"*),
  `NoteTextView.swift:26-28`, `MarkdownStyler.swift:5-8`, `MarkdownAttributedText.swift:60-61`,
  `MockupScreens.swift:64`, and the header of `UITests/NoteImageUITests.swift:7-8`. A comment
  that carries a decision an ADR has reopened is how the next reader gets the old rule from the
  code and never sees the new one.
- **The hiding reaches three surfaces, not one.** `NoteTextView` is built by
  `EditorColumn+Text.swift:43`, `DiaryView.swift:98` and `TodayView.swift:180`, so the Diario
  pane's source editor - the one sitting beside its own live rendering - hides syntax too. That
  is the concrete content of the ADR-0005 §D2 amendment: the pane's two halves are still a
  source and a rendering, and the source is no longer literal.
- **The two `![[…]]` forms now look different in the same editor**, and it will be noticed. A
  transcluded note keeps its source line with a card beneath it; a picture replaces its source.
  The rule that sorts them is ADR-0010 §D2's, unchanged and already implemented, and the reason
  is ADR-0010 §D3's own about provenance - but it is a difference a person has to be told once.
- **Renaming a file in a drawn embed stops being an in-place edit.** The caret cannot enter the
  run (D5), so it becomes select-and-retype, helped by the completion that already fires after
  `![[`. This is the price of the exception in D5 and the reason D7's setting covers the picture
  as well as the delimiters.
- **A find match inside a collapsed run is counted and not seen**, except the current one, which
  D2 reveals. The counter says "3 di 7" honestly and two of the seven are behind hidden markers
  until the stepper reaches them. Acceptable, and named rather than discovered.
- **`EditorDecorationDelegate` stops being about two features.** It carries folding and
  transclusion today in three `nonisolated(unsafe)` stores; this adds the hide list, the revealed
  paragraph and the attachment table. Its header calls it *"one object because a text view has
  one content-storage delegate and one layout-manager delegate; two features, kept as two
  separate inputs so neither can quietly depend on the other's state"* - the discipline stands
  and the sentence needs rewriting for four.
- **Folding and hiding are different hooks and cannot fight.** A folded line is not enumerated at
  all, so it is never handed to the substitution hook, and the study measured that the caret
  cannot enter it either. What does need care is the invalidation: `applyFolding` invalidates the
  whole document and D2's reveal must not, or a feature that runs on every arrow key inherits a
  cost measured for one that runs on a click.
- **There is no precedent for slice 3 in a native text widget.** Ghostwriter, the closest
  architectural relative among the five editors read, does not hide markdown at all and never
  draws a picture inline. Every editor that does is a browser with a DOM under it. That is not an
  argument against trying; it is the argument for probe 6 gating the slice and for a fallback
  that already works twice in this codebase.
- **None of this is unit-testable end to end, and `.claude/test-cmd` is where that bites.** The
  interaction is on screen: what the caret does, what a drag copies, what an input method
  composes. The unit suite can cover `MarkdownStyler`'s new spans and the pure range arithmetic
  of the crossing rule, and nothing else. The assertions live in the UI suite, and
  `scripts/uitests.sh` before every merge to `main` is the rule that already exists for exactly
  this - with `-disableCalendar YES` and `accessibilityIdentifier` rather than prose, per the
  working agreements.
- **The SPEC amendment is debt, filed the way ADR-0017 §D5 filed its own.** §14's row and §5's
  first bullet both stop being true when slice 1 ships. The amendment is written when the ADR is
  accepted, not when the code lands, because a spec that contradicts an accepted ADR is worse
  than one that lags an implementation.
