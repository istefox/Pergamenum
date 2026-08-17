# ADR-0010: Transclusion is a live view of another note, drawn by both surfaces

- Status: proposed
- Date: 2026-08-17
- Supersedes: nothing. Amends ADR-0009 §D2's schema numbering (see Consequences).
- Depends on: `docs/20260817_TextKit2_live_editing.md` for what the editor can and cannot
  do without touching the file.

## Context

The roadmap (`docs/20260816_Pergamenum_Roadmap.md`, M8) asks for `![[note]]` and
`![[note#heading]]` rendered inline in the reading view and "navigable in the editor",
and calls it the analogue of Craft's subpage — a page inside a page, done in a way
Obsidian reads. SPEC §5 mentions only the media form `![[nome-file.est]]`, so the
transcluded *note* is new and this is where it gets decided.

**Today the app treats every `![[…]]` as a file.** `Attachment.embed(inLine:)` accepts
any target on a line of its own; `EmbeddedFileView` asks `Attachment.resolve` for it and,
when the target is a note rather than a picture, draws *"file non trovato nel vault"*.
Clicking the same link in the editor reaches `VaultBrowser.preview(embed:)`, which
records the same problem. The message is not merely unhelpful, it is wrong: the file the
user named exists, it is just a note. That defect is PG-020 and it is a symptom of the
missing decision, not a bug to patch on its own.

Two other places already have an opinion about embeds. `NoteStore.linkTargets` filters
them out (`where !link.isEmbed`), so an embedded note produces no link, no backlink and
no unresolved-link report. `NoteOutline` lists an embed as an index entry, one indent
step under the heading above it, which is right and stays.

**The reason this needs an ADR rather than a slice.** Rendering a note inside the reading
view and nothing in the editor widens the distance between the two surfaces. Every such
addition converts the open question of PG-018 — whether to add NotePlan-style direct
editing later — from "add a display transform to the editor" into "choose which of two
editors the user gets". The editor is the surface where the note is written; if it is
also the surface that shows less, the reading view slowly becomes the real app.

**What was measured before deciding.** The morning study established that a substituted
paragraph may change attributes but never length, and that this constraint is the file
guarantee rather than an obstacle. What was unknown is whether attributes can buy
*vertical space*, because a preview needs somewhere to be. Probed offscreen on
2026-08-17, five paragraphs, `paragraphSpacing` 200 applied through
`NSTextContentStorageDelegate` to the `![[Altra nota]]` line alone:

| | baseline | substituted |
|---|---|---|
| text length | 59 | **59** |
| the embed line's own fragment height | 16.0 | **216.0** |
| y of the following line | 48.0 | 248.0 |
| y of the lines above | 0 / 16 / 32 | unchanged |

The space belongs to the embed line's **own layout fragment**, so a custom
`NSTextLayoutFragment` — the machinery the fold badge already uses — draws into its own
frame rather than overflowing into a neighbour's, and not one character enters the file.
That is what makes the decision below affordable rather than aspirational.

## Decision

**D1. A transclusion is a view of another note. Nothing is ever copied.**

The line on disk stays `![[nota]]`, byte for byte, in both surfaces and after every
render. No expansion is written into the host note, not on save, not on export, not on
close. The target is read fresh from the vault; the index holds structure, not content,
so it cannot be the source (ADR-0009 §D6 for the same reason on views).

This is principle 1 and principle 4 in one line: Obsidian opens the host note and
transcludes the same target from the same text.

**D2. `![[…]]` resolves to a note or to a file, and the extension decides.**

- a target ending in `.md` → a note, by path;
- a target with any other extension → a file, exactly as today;
- a target with no extension → a note, resolved by title through the index
  (`IndexSnapshot.resolve(title:)`), the same lookup `[[wikilink]]` uses.

Note resolution is attempted first for an extensionless target and never for one that
carries a foreign extension, so `![[foto.png]]` can never become a note lookup. When
nothing resolves, the message says which of the two was looked for — *"nota non trovata:
Altra nota"* or *"file non trovato nel vault: foto.png"*. That closes PG-020 as a
consequence of the rule rather than as a separate patch.

The classification is pure and lives in `Core/Markdown/Transclusion.swift`, so `perg` and
`pergamenum-mcp` compile it (ADR-0007). Deciding what a link points at is a vault
convention; drawing it is not.

**D3. Both surfaces draw it. Same content, two renditions.**

*Reading view*: the target's blocks rendered inline, set apart by a left rule and the
target's title as a small clickable header. Provenance has to be visible — text that
looks like the host note's own but is not is the one failure mode that makes a reader
edit the wrong file.

*Editor*: the source line `![[nota]]` **stays visible, selectable and editable**, and the
rendition is drawn underneath it in space reserved by the paragraph style, by a custom
`NSTextLayoutFragment`. The measurement above is the whole argument that this is possible
at all.

The alternative — reading view only — is refused for the reason in the Context: it makes
the editor the poorer surface and turns a later display transform into a choice between
two editors.

The other alternative — replacing the source line with the rendition, NotePlan style — is
refused because SPEC §14 excludes hiding syntax while typing in v1, and because it is a
different decision with its own cost (PG-018, the caret walking through hidden
characters). Keeping the source line visible is what makes this ADR compatible with
either outcome of that one: if direct editing is ever adopted, the transclusion line is
one more thing it hides, not a design to redo.

**D4. What the editor draws is a rendition, not a nested editor.**

The preview does not take the caret, does not accept typing, and has no selection of its
own. A click on it opens the target note; typing goes to the source line where the caret
already is. An editable nested editor is a second editor — with its own undo stack, its
own find, its own selection model — and there is no evidence in this project that it can
be made to feel right.

**D5. The rendition is bounded, and a section transclusion reuses the rule that exists.**

`![[nota#sezione]]` shows the section from its heading to the next heading of the **same
or a higher level** — `NoteFolding`'s rule, already implemented and tested against a
hostile note. It is not re-derived here; a second copy would drift.

The height must be known before the fragment draws, so the rendition is measured first
and the paragraph spacing set from it. It is **capped**: past the cap the preview ends
with the target's name and a "apri la nota" affordance. A note transcluding a
four-thousand-line note must not become unscrollable, and an unbounded preview would make
the host note's own length depend on someone else's editing.

**D6. Depth one. A transcluded note's own transclusions are not expanded.**

Inside a rendition, `![[…]]` renders as a labelled link, never as a second nesting. This
makes a cycle impossible by construction — a note transcluding itself shows one link, not
a stack overflow — with no visited set and no depth counter to get wrong. It also bounds
the cost of opening any note to reading the notes it names directly.

Full recursion with a cycle check was considered and refused: it buys a picture nobody
asked for and pays with unbounded reads on every open.

**D7. A transcluded note is a link. A file embed still is not.**

`NoteStore.linkTargets` starts counting `![[note]]` where the target resolves as a note
under D2, so a transclusion produces a backlink and appears among unresolved links when
the target does not exist. This is what a reader expects and what Obsidian does; a note
that half the vault transcludes with no backlinks to show for it would be a lie the panel
tells.

File embeds stay out, which keeps `embedTargets` exactly the separate field ADR-0009 §D2
reserved for M11's gallery.

The stored meaning of `linkTargets` changes, so cached rows written before this are
wrong in a way no field addition would repair. `IndexCache.schemaVersion` is therefore
bumped to **2** in M8, and M11's `embedTargets` bump becomes **3**. Named here rather
than discovered later, which is the discipline ADR-0009 asked for and is now spending.

**D8. A transclusion refreshes when its target changes, and never per keystroke.**

Resolved on open and on a watcher event touching a target of the note on screen,
debounced like every other watcher-driven refresh. Typing in the host note re-styles the
host note; it does not re-read anybody else's file.

## Consequences

- **The two surfaces converge instead of diverging**, which is the reason this ADR exists
  and the only consequence worth reading twice. After it, the editor shows everything the
  reading view shows except the prose rendering of markdown itself.
- **PG-020 closes as a by-product.** The wrong message was the missing rule showing
  through.
- **The custom layout fragment stops being a one-off.** The fold badge was the first, this
  is the second, and two users are what turn a trick into machinery worth having a name
  for.
- **One schema bump in M8, to 2**, discarding every cached row on first launch and paying
  one cold scan. ADR-0009 §D7 measured the ratio at roughly two to one on the current
  vault; the milliseconds there describe a two-note vault and are not a scale claim.
- **The measurement is offscreen.** `paragraphSpacing` reserving fragment height was
  proved in a bare TextKit 2 stack, not in a live `NSTextView` with a scroller, a ruler
  and an ongoing edit. It is confirmed on screen before the slice ships, exactly as the
  folding mechanism was — and if it does not hold there, the slice stops and says so
  rather than working around it.
- **Two behaviours are unprobed and are the first thing to try by hand**: where a click
  inside the reserved blank space puts the caret, and what selecting across a transcluded
  line copies to the pasteboard. Neither is a reason to decide differently; both are
  reasons not to claim the feature works until someone has clicked there.
- **The slice starts with a mockup**, per the design-system rule: the left rule, the
  target's title, the cap and its affordance, and the editor's card under a live source
  line are all appearance decisions, and the editor one has no precedent in the app.
- **Block references `![[nota#^id]]` are out of scope and named rather than forgotten.**
  Obsidian has them; the roadmap asks for headings only. Adding them later means one more
  case in D2's resolution and a block-id parser, not a change to anything decided here.
- **Depth one will be argued with.** The answer is the same as ADR-0009's on the query
  grammar: a second level needs a question it answers that a click does not, written
  down, not a general mechanism.
