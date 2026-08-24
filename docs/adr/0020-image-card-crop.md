# ADR-0020: An image card is cropped by a rectangle written into the canvas, and the file on disk is never touched

- Status: accepted
- Date: 2026-08-23. Written from a reading of the Workspace code rather than from a plan for it:
  every mechanism named below already exists in this repository and was read at the line. The two
  claims that could not be read out of the code are named as probes at the end of the Decision,
  and one of them gates the first task of the plan.
- Supersedes: nothing. **Fills a hole in SPEC §6.5**, whose image card reads *"rendering diretto,
  resize proporzionale, crop non distruttivo opzionale"* and whose §6.4 tool 5 repeats it
  (*"card ridimensionabile con crop non distruttivo"*). The resize half has existed since M2; the
  crop half has never been implemented, and nothing in `Sources/Features/Workspace/` mentions a
  crop rectangle, a `CIImage` or a mask.
- Depends on: **SPEC §6.2** (extra Pergamenum properties use prefixed keys and must be ignored and
  preserved by other apps), **SPEC §6.3** (the eight resize grips and the Shift lock),
  **principle 1** (file over app) and **principle 4** (Obsidian compatibility) of `CLAUDE.md`,
  and the crop's whole storage argument rests on `CanvasNode.unknown`
  (`Sources/Core/Canvas/JSONCanvas.swift:122, 187-189, 193`), which is already tested in three
  directions by `Tests/CanvasTests.swift:48-83, 127-140`.

## Context

An image on a board today is a `file` node drawn by `NodeCard.previewCard`: a `ThumbnailImage`
asking `ThumbnailStore` for a render at `node.width`, `.aspectRatio(contentMode: .fit)` inside
`cardChrome`, with the file name and the extension underneath. It can be moved, it can be resized
from eight grips with Shift for proportion, it can be given one of the six JSON Canvas colours,
and it can be sent to Quick Look with the space bar. It cannot be re-framed. A screenshot of a
whole window and the one detail in it that matters are the same card, and the only way to show
the detail is to open an image editor, crop the file, and lose the rest of it.

**Two facts about the file format decide most of this ADR, and only one of them is in the spec.**

JSON Canvas 1.0 has no crop. A `file` node's properties are exactly `id`, `type`, `x`, `y`,
`width`, `height`, optional `color`, `file`, optional `subpath` - read from the spec page itself,
which says nothing at all about custom or unknown properties: it neither permits them nor forbids
them nor tells an implementation what to do with the ones it finds. SPEC §6.2 is where the rule
comes from for this app: *"Proprietà aggiuntive di Pergamenum usano chiavi prefissate e devono
essere ignorate/preservate da altre app."*

The second fact is not in any spec and is the one that chooses the encoding. Obsidian's forum
carries a bug report from July 2024 (v1.6.5) titled *"Canvas file corruption if file node has
custom property of type object or list"*: Obsidian's own serialiser emitted a trailing comma after
such a property and the canvas then failed to open. A team member answered *"Will be fixed in
Obsidian v1.7"*, and the thread sits in the Bug graveyard. Two things follow, and they point in
opposite directions:

- Obsidian **does** round-trip unknown keys on canvas nodes rather than dropping them. It could not
  have corrupted a file by re-serialising a property it had discarded. This is the strongest
  available evidence for the interop half of the feature, and it is evidence from a defect rather
  than from documentation, which is the only kind on offer.
- A **non-scalar** custom property on a **file node** is exactly the shape that broke. Fixed
  upstream or not, the vault is the user's own and the failure mode is "the board will not open".

This app's side of the round trip is already built and already tested. `CanvasDocument` keeps every
top-level key it does not understand, `CanvasNode` keeps every node property outside its `consumed`
set, `CanvasEdge` does the same, `JSONValue` distinguishes `true` from `1` on purpose
(`JSONValue.swift:21-27`), and the encoder writes sorted keys with unescaped slashes so a file that
did not change in content does not change on disk. `Tests/CanvasTests.swift` asserts all of it,
including a foreign `styleAttributes` object surviving a cycle. So the app can carry anything; the
question is only what is safe to hand to the other reader.

**What "non-destructive" has to mean here.** SPEC uses the adjective twice and it is not
decoration: the source image must stay byte-identical on disk, and removing the crop must return
the card to exactly what it drew before. That rules out the obvious implementation (re-encode the
pixels) and it also rules out the tempting one (write a cropped copy beside the original), because
undoing a crop would then have to delete a file, and permanent deletion is a gate a person has to
answer, not something a Cmd+Z performs.

**What the board already knows how to do, and what this feature should therefore not reinvent.**
Three mechanisms are in place and each does exactly what a crop needs:

- `BoardGeometry.resized(_:handle:by:lockAspect:)` (`BoardGeometry.swift:80-112`) is a pure
  function over a rectangle and one of eight grips. It moves the right edges, it moves the origin
  for the top and left grips, it enforces a minimum, and `lockAspect` keeps the incoming
  rectangle's ratio. Six tests cover it in `BoardInteractionTests.swift:13-58`.
- Transient gesture state on the controller, committed once on release. The resize does it
  (`resizingNodeID`, `resizedFrame`, `beginResize`/`updateResize`/`endResize`), the drag does it,
  the arrow does it, and `WorkspaceController.swift:279-296` states why in a comment written after
  the mistake: committing per frame writes the file dozens of times and fills the undo stack with a
  step per pixel.
- `mutate(creatingOnDisk:_:)` is the single door every board change goes through - it records
  history, marks the board dirty and schedules the one-second autosave - so a feature that goes
  through it gets undo, redo, the "Salvato" indicator and the watcher's own-write suppression
  (`lastWrittenHash`) with no new plumbing.

**One thing the code does not know and this ADR needs.** `ThumbnailStore.renderWithQuickLook`
asks `QLThumbnailGenerator` for `CGSize(width: width, height: width)` - a **square** - and builds
the `NSImage` from `representation.contentRect.size` (`ThumbnailStore.swift:95-104`). If that
returns a padded or letterboxed square for a wide photograph, then a rectangle expressed as a
fraction of the returned image is not a fraction of the file, and every crop is offset by the pad.
Nothing in this repository measures it. It is probe 1 and it gates task 1.

## Decision

**D1. The crop is a rectangle in the source image's own normalised coordinates, stored as one
prefixed, scalar key on the node: `"pergamenum-crop": "x y w h"`.**

Four decimals, space separated, each in `[0, 1]`, origin top-left, relative to the image as it is
rendered for display (which is to say after EXIF orientation, because that is the image the person
saw when they dragged the rectangle). `"pergamenum-crop": "0.1200 0.0800 0.5500 0.6000"` means
"show the region starting 12% across and 8% down, 55% wide and 60% tall".

Normalised and not pixels, because the card draws a `ThumbnailStore` render whose pixel size
depends on which of seven buckets the card's width fell into; a crop in pixels would mean a
different region at every bucket, and the bucket changes when the card is resized. Normalised
coordinates are the only expression that survives the render being regenerated at another size,
which it will be, routinely, by the feature that already exists.

A **string scalar** and not an object `{"x":…}` or an array `[…]`, for the Obsidian corruption class
named in the Context: a non-scalar custom property on a file node is the exact shape that produced
an unopenable canvas in v1.6.5. Fixed in v1.7 or not, a string costs nothing and removes the class.
The four decimals also keep the file quiet under iCloud and git, which the encoder's sorted-keys
comment already cares about.

One key and not four (`pergamenum-crop-x`, `-y`, `-w`, `-h`), because four keys can survive
partially. A reader that keeps three of them leaves a crop that is half a rectangle, and there is
no honest way to draw that. One key is present or absent.

The prefix is `pergamenum-`, kebab-case, matching every other namespaced string this app already
owns: `pergamenum-view` (the query fence, ADR-0009), `pergamenum-drawing` (the SVG metadata marker,
`DrawingSVG.swift:73`), `pergamenum-light` / `pergamenum-dark` (the bundled theme ids).

Rejected: **the dotted form `pergamenum.crop`**, which is what the third-party example in
`CanvasTests.swift:53` uses (`someOtherApp.flag`). It is a reasonable convention and it is not this
app's; consistency with four existing namespaced strings in this repository beats consistency with
one string in a test fixture that was written to imitate somebody else.

**D2. The crop is never consumed out of `unknown`, and `Sources/Core/Canvas/JSONCanvas.swift` is
not modified at all.**

`CanvasNode.init?(_:)`'s `consumed` set is untouched, `rawValue` is untouched, and no stored
property is added. The crop is read by a pure `CanvasCrop.read(from: CanvasNode) -> CanvasCrop?`
that looks in `node.unknown["pergamenum-crop"]`, and written by a helper that sets or removes that
one key inside an existing `mutate`. Four things follow, and each of them is a cost avoided rather
than a preference:

- **A malformed or foreign value round-trips untouched**, because nothing ever removes it. If a
  hand edit or another tool leaves `"pergamenum-crop": "banana"`, the card draws whole and the file
  keeps the string. A typed property would have to either drop it (data loss on a key we ourselves
  defined) or keep a shadow copy of it (two places holding one fact).
- **`CanvasNode`'s synthesised `Equatable` does not change**, so no existing comparison anywhere
  changes meaning. `BoardHistory` compares documents; `CanvasTests.roundTripsAnObsidianCanvas`
  compares documents.
- **The codec keeps its single job.** `JSONCanvas.swift` implements JSON Canvas 1.0 and carries
  everything else through; a `crop` field in it would be this app's extension living inside the
  file that exists to be neutral.
- **The connectors are not touched.** `Sources/Core/**` is compiled into `perg` and
  `pergamenum-mcp` through `sharedSources`; `Sources/Connector/` never mentions Canvas at all
  (grepped: zero matches), so neither binary has a canvas capability to teach.

Rejected: **`var crop: CanvasCrop?` as a first-class property on `CanvasNode`.** Type safety at the
call site, in exchange for all four costs above. This is ADR-0019 §D1's own argument at a different
layer, and it lands the same way.

`CanvasCrop` itself lives at `Sources/Features/Workspace/CanvasCrop.swift`, not in
`Sources/Core/Canvas/`. It is pure `CoreGraphics` and `Foundation` and would compile into both
connectors harmlessly, but nothing there draws and nothing there reads canvases; putting a format
detail into Core before a Core caller exists is a guess about a future binary. Moving a pure file
later is a rename.

**D3. Nothing on disk is ever rewritten. "Non-destructive" is a property of the design, not a
promise the code has to keep.**

There is no `CIImage`, no re-encode, no `CGImageDestination`, no cropped sidecar file. The whole
feature's only write is one string on one node inside the `.canvas` the board already saves every
second through `CanvasStore.save`. Removing the crop removes the key and the card draws exactly
what it drew before, through exactly the same code path. Quick Look (SPEC §6.6), double-click to
open, the same image embedded in a note, the same image on another board, and any other application
all see an untouched file, because none of them read the key.

Rejected: **writing a cropped copy beside the original.** It is destructive by SPEC's own word, it
doubles the vault for every crop, it makes "remove the crop" a file deletion, and it breaks the one
thing a board is for: the node points at the file the folder actually contains (SPEC §6.1, "la
board è una vista spaziale della cartella reale").

Rejected: **the crop as an index field.** Principle 3 of `CLAUDE.md` is explicit that the SQLite
cache regenerates entirely from a vault scan and is never the source of truth. A crop there would
evaporate on the next reindex, and nothing downstream would notice - the exact failure ADR-0019 §D1
rejected for the same reason at the note level.

**D4. The card's size and the crop are two independent facts, and neither one moves the other.**

The crop says *which part of the image is shown*. The card's frame says *how big the window is*.
The crop region is drawn into the card's existing image area under the same `fit` rule the whole
image uses today, so a crop is exactly what the person dragged, and the card does not jump when the
crop is confirmed.

The consequence is honest and worth stating rather than hiding: a crop whose aspect ratio differs
from the card's leaves letterboxing inside the card - which is the same letterboxing an ordinary
uncropped photograph already has in a card of a different shape today. The escape hatch is one new
item in the "Ridimensiona" submenu that already exists in the card's context menu
(`BoardContentLayer.swift:66-74`): **"Adatta al ritaglio"**, which calls the existing
`resize(nodeID:to:)` with the card's current width and the height the crop's aspect implies. One
menu item, one call, no new mechanism, and it is explicit - the board only reflows when asked.

Rejected: **resizing the card automatically when a crop is confirmed.** A board laid out as a grid
of equal cards is a thing people make, and a gesture inside one card that silently changes that
card's height breaks the grid without ever mentioning it.

Rejected: **aspect-fill and clip.** Then the visible region is the intersection of the crop and the
card's aspect, the rectangle drawn during the gesture is not what appears after it, and there is no
way to look at a card and know what its crop is.

Rejected, and this is the alternative that deserves the most careful answer: **making the card's own
frame be the crop window** - the eight existing grips crop an image card instead of resizing it,
Miro-style, with the image held at a fixed scale behind a movable window. It is a good model in an
app built around it. It is wrong here for two reasons that are both about the rest of the board.
SPEC §6.5 lists *"resize proporzionale, crop non distruttivo"* as two things, and §6.3's eight grips
are defined once for every card type; making them mean one thing on a `.png` and another on a
`.pdf` is how a board acquires gestures that need a legend. And it would make card size destructive
to framing: growing the card to fill a gap in the layout would reveal image the person had
deliberately cropped away.

**D5. The crop is edited in an explicit mode, on one card at a time, and the mode is transient
state on the controller.**

New stored properties on `WorkspaceController`, beside `resizingNodeID` and for the reason its
comment already gives: `croppingNodeID: String?`, `cropDraft: CGRect?` (normalised),
`cropHandle: BoardGeometry.Handle`, `cropOriginal: CGRect`. The behaviour lives in a new
`WorkspaceController+Crop.swift`, following `+Gestures`, `+Drawing`, `+Import` and `+Viewport`;
the state has to live on the class because an extension cannot hold it, which is what
`WorkspaceController.swift:99-104` already says about `activeDrawing`.

**Entering**: the card's context menu, "Ritaglia", enabled only for a croppable card (D8). SPEC §10
lists the canvas card menu as *"minimo richiesto"*, so adding to it is inside the spec rather than
against it. Double-click is not used: it opens the file (SPEC §6.5) and must keep doing so.
Entering crop mode on a second card confirms the first.

**Inside the mode**: the card draws the **whole** image, scrimmed outside the crop rectangle with
`theme.color(.canvasBackground).opacity(0.7)` - the part being cropped away visibly becomes board -
with the rectangle outlined in `theme.color(.canvasSelection)` and eight grips reusing
`ResizeHandleView`'s visual language. Dragging a grip runs `BoardGeometry.resized`; dragging inside
the rectangle moves it, clamped so it stays within the image; Shift locks the rectangle's current
proportions, because `lockAspect` already means exactly that. **The card's own resize grips are
hidden while it is being cropped**, so no point on screen belongs to two gestures - which is what
makes D4's independence true for the pointer and not only for the model.

**The gesture runs in the drawn image's own point space, not in normalised space**, and normalises
only at commit. This is not a detail: in normalised space a "locked aspect ratio" would mean a
ratio of fractions, so Shift on a 3000×1000 photograph would hold a shape that is not square on
screen and not square in the file either. Working in points, `BoardGeometry.resized` means on a
crop rectangle exactly what it means on a card, and the six tests that already cover it cover this
too.

`BoardGeometry.resized` gains one parameter, `minimum: CGSize = minimumSize`, because the crop's
floor is a fraction of the image (`CanvasCrop.minimumFraction = 0.02`, converted to points at the
drawn size) rather than the 40×30 board units that stop a card from swallowing its own grips. It is
a defaulted parameter, so the one production call site
(`WorkspaceController+Gestures.swift:131`) and the six test call sites
(`BoardInteractionTests.swift:14, 21, 29, 37, 44, 52`) are unaffected - all seven were grepped, not
assumed - but the signature is an observable contract and the full suite is the check, not the grep.

**Leaving**: Enter or a click outside the card confirms; Esc cancels. Cancel writes nothing at all -
not an empty `mutate`, nothing - so a cancelled crop leaves no undo step and no autosave.

Rejected: **cropping with a modifier held on the existing resize grips** (Option+drag to crop).
Invisible, undiscoverable, unmentionable in a menu, and it collides with Shift, which already means
proportional.

Rejected: **a modal sheet with a crop editor in it.** The board's own vocabulary is direct
manipulation on the card; a sheet would be the only place on this board where a spatial edit
happens somewhere other than in space. It would also make "Adatta al ritaglio" impossible to
preview against the neighbouring cards.

**D6. Confirming is one `mutate`, one undo step, and at most one key.**

`endCrop(confirm: true)` normalises the draft, clamps it into the unit square, and:

- if the result is the whole image within a rounding epsilon, it **removes** the key rather than
  writing `"0.0000 0.0000 1.0000 1.0000"`. So dragging a crop back out to full size returns the
  file to exactly the bytes it had before the crop existed, and a canvas never accumulates a no-op
  property that another reader has to carry;
- otherwise it sets the key.

`refreshContents()` is not called: no file appears or disappears, and the tray is about files.
Undo and redo come free through `BoardHistory`, which restores whole documents - so Cmd+Z removes a
crop and Cmd+Shift+Z puts it back with no new history plumbing, exactly as it already does for a
colour or a resize.

"Rimuovi ritaglio" in the context menu is the same removal without the mode, shown only when the
node carries the key.

**D7. The render is asked for at the resolution the visible region needs, and that is the only
performance-visible change.**

`ThumbnailImage` asks `ThumbnailStore.thumbnail(for:width:)` for `node.width` today. A crop of
fractional width `w` magnifies the visible region by `1/w`, so the request becomes
`node.width / w`, clamped to the store's top bucket. The `.task(id:)` key already quantises through
`ThumbnailStore.bucket(for:)` (`NodeCard.swift:246`), so nothing renders per frame - and the crop
gesture does not touch the model at all until confirm, so during a drag nothing renders at all.

Inside crop mode the card needs the **whole** image and asks for `node.width`, today's number. It
is a framing gesture, not a retouch, and a scrimmed preview at card resolution is what it needs.

The ceiling is real and is named rather than raised: `ThumbnailStore`'s ladder stops at 1280
(`ThumbnailStore.swift:120`), so a very tight crop on a small card draws soft. Raising it is a
change to that actor's own quantisation and to its cache footprint, and it belongs to whoever finds
the softness unacceptable in practice, with its own reasoning. This ADR does not touch
`ThumbnailStore`.

**D8. Which cards can be cropped, and the two-list problem this does not make worse.**

Croppable is decided in exactly one place, `CanvasCrop.isCroppable(path:)`, over raster image
extensions. The repository already holds two lists that disagree - `NodeCard.symbol(for:)` has
`png, jpg, jpeg, heic, gif, svg` (`NodeCard.swift:158`) and `ViewGridRenderers` has
`png, jpg, jpeg, heic, gif, webp, tiff` (`ViewGridRenderers.swift:111`). Unifying them is a
refactor with its own blast radius across two features and is not this ADR's business; adding a
third list silently would be. So `isCroppable` is the crop's single answer, and the divergence is
recorded here so the next person finds it deliberately rather than by being bitten.

`svg` is excluded: an SVG on a board is usually one of this app's own drawings, which double-click
reopens for ink editing (`BoardContentLayer.swift:238`), and a crop rectangle over an editable
drawing is two models of one object. PDFs are excluded: SPEC §6.5 gives the PDF card a page badge
and a page selector, and framing a document page is a different feature with a different name.

Below `BoardGeometry.placeholderZoom` (25%) a card is drawn as a plain rectangle, so crop mode
refuses to open there - there is nothing on screen to aim at. Same refusal when the thumbnail has
not arrived yet: you cannot re-frame what is not drawn.

**D9. The crop is a fact about this node on this board, and about nothing else.**

Two nodes pointing at the same file can carry different crops, which is the point: one board shows
the whole photograph and another shows the detail. The editor's embeds are unaffected - ADR-0019
sizes an embed with Obsidian's `|W` suffix in the note's own text and knows nothing about canvas
nodes, and this ADR writes nothing into any `.md`. The two features share a `ThumbnailStore` and
nothing else.

**Two probes, with a pass criterion each.**

1. **`QLThumbnailGenerator` preserves the source aspect ratio through
   `ThumbnailStore.renderWithQuickLook`.** The request is a square (`CGSize(width: width, height:
   width)`) and the returned image's size comes from `contentRect`. If a wide photograph comes back
   padded into a square, normalised coordinates over the returned image are not normalised
   coordinates over the file and every crop is offset by the pad. **Passes** when a 1200×400, a
   400×1200 and a 600×600 fixture each return an `NSImage` whose aspect ratio matches the source
   within 1%. **Failing**, the crop must be measured against `NSImage(contentsOf:)`'s own size for
   image cards - one extra read per card, cached - or the store's square request has to change,
   which is a change to a shared actor and needs its own decision. This gates task 1.
2. **Obsidian preserves `pergamenum-crop` across an edit of its own.** The Context's evidence is a
   corruption defect, which proves Obsidian re-serialises unknown node keys but was measured on a
   version that got it wrong. **Passes** when a board cropped here, opened in Obsidian, with the
   same card moved and saved there, comes back with the key intact and the same value, and the
   crop still draws. **Failing**, the fallback is a sidecar file beside the `.canvas`, which keeps
   "file over app" and loses the round-trip promise, and would need its own ADR. This is task 8 and
   it is a manual step, not a unit test.

## Consequences

- **The canvas gains a property no other application understands, and that is the deal SPEC §6.2
  already struck.** A board cropped here and opened in Obsidian shows the whole image - correctly,
  because Obsidian has no crop - and the key rides along untouched. Nothing is lost in either
  direction; the two applications simply disagree about how much of the picture to show.
- **A crop is invisible outside this app, including to this app's own connectors.** `perg` and
  `pergamenum-mcp` have no canvas capability at all today, so there is nothing to teach and nothing
  that will drift. If a canvas read is ever added there, `CanvasCrop` is a pure file that moves
  into `Sources/Core/Canvas/` with a rename.
- **Quick Look shows the uncropped file, and that is right.** The space bar opens the file the
  folder contains. Someone will read it as a bug once; it is the same answer as "the file on disk
  is untouched", which is the feature.
- **A tight crop draws soft until somebody raises the thumbnail ceiling.** `1/w` magnification
  against a 1280-pixel ladder means a crop below roughly 20% of the width on a 260-point card is
  asking for more pixels than the store will ever return. Named here so the first report of it is
  recognised rather than investigated.
- **`BoardGeometry.resized` gains a parameter and stops being a board-only function.** Seven call
  sites, all unaffected by the default (grepped: `WorkspaceController+Gestures.swift:131` and six
  in `BoardInteractionTests.swift`). Its doc comment says *"Applies a resize drag to a card"* and
  becomes wrong the moment a crop rectangle goes through it - a comment carrying a rule the code no
  longer keeps is how the next reader gets the old rule, so it is rewritten in the same task.
- **`ThumbnailImage` gains a parameter.** One call site (`NodeCard.swift:94`, grepped). An
  uncropped card must keep today's exact path - same requested width, same `fit`, same cache key -
  so that a feature about image cards cannot regress PDF, email or note cards, which use the same
  view.
- **The board gains its first modal state.** Every existing board interaction is either a tool
  selection or a gesture that ends when the mouse comes up. Crop mode persists across events and
  can therefore be left open: a mode entered and then forgotten while the user navigates to another
  board, closes the vault, or hits Cmd+Z. `open(folder:)`, `detach()` and `undo()` each need to end
  it, and that is three lines rather than a design, but it is three lines that will not be written
  unless they are listed. They are, in task 3.
- **The scrim reuses `color.canvas.background` instead of getting a token of its own.** A new
  `color.canvas.cropScrim` would be the token-purist answer and costs three files plus a red test:
  `TokenKeys.swift`, both bundled themes under `Resources/Themes/`, the emergency palette in
  `Theme.swift`, and `DesignSystemTests.bundledThemesDefineEveryToken` fails until all of them
  agree. Reusing the board's own background colour is semantically true - the cropped-away part
  becomes board - and is within the binding rule, since it goes through a token. If the on-screen
  check says the scrim is too weak in the light theme (`#F2EFE9` at 70% over a photograph), adding
  the token is a contained follow-up and this paragraph is its brief.
- **The image extension lists stay at two, and the third one has a name.** `isCroppable` is
  deliberately not a unification. Someone will eventually notice that a `.webp` gets a photo icon
  in one view, a document icon in another, and no crop in a third. That is a real inconsistency,
  it predates this ADR by two features, and it is recorded rather than absorbed.
- **The unit suite can carry nearly all of this.** The grammar, the clamping, the normalisation
  round trip, the no-op-removal rule and the grip arithmetic are pure. The controller transitions
  and the canvas round trip go through a real `WorkspaceController` over a `TemporaryRoot`, which
  `CanvasTests.swift:305-386` already does a dozen times. What stays out: whether the scrim reads,
  whether a grip can be hit at 60% zoom, and whether Obsidian keeps the key - the last of which is
  probe 2 and has a written pass criterion rather than a hope.
- **The SPEC is not amended.** §6.5 asked for this and §6.2 said where extra properties go; this
  ADR chooses the encoding and the gesture, which is what an ADR is for. §14 is untouched: no
  decision listed there is reopened.

## Implementation plan

Eight tasks, ordered by dependency. Every task names the SPEC sections it satisfies (this feature
has no R-numbered requirement document; the SPEC's own section numbers are the identifiers that
exist).

### Task 1 - Probe the thumbnail's aspect fidelity before anything is built on it (probe 1, SPEC §6.5)

New `Tests/CanvasCropProbeTests.swift`. Write three fixture PNGs (1200×400, 400×1200, 600×600) into
a `TemporaryRoot`, drive `ThumbnailStore` with a temporary cache directory, assert each returned
`NSImage`'s aspect ratio matches its source within 1%.

**This is a gate.** If it fails, stop and revise D1 and D7 before writing anything else: the crop
would have to be measured against the full-resolution image rather than the render.
Budget: `Tests/CanvasCropProbeTests.swift` (~70 lines).

### Task 2 - `CanvasCrop`: the value type, the grammar and the geometry (SPEC §6.2, §6.5)

New `Sources/Features/Workspace/CanvasCrop.swift`: the normalised rectangle, `read(from:)` over
`node.unknown["pergamenum-crop"]`, `formatted` (four decimals, space separated), `clamped` into the
unit square with `minimumFraction = 0.02`, `isWhole` (the epsilon rule of D6), `isCroppable(path:)`,
and the two conversions between normalised space and the drawn image's point space.

Modify `Sources/Features/Workspace/BoardGeometry.swift`: add `minimum: CGSize = minimumSize` to
`resized(...)` and rewrite its doc comment, which currently says "a card".

**Contract change, call-sites already enumerated** (grepped, not inferred): production
`WorkspaceController+Gestures.swift:131`; tests `BoardInteractionTests.swift:14, 21, 29, 37, 44, 52`.
All seven compile unchanged under a defaulted parameter - run the **full** suite anyway, not just
the new file: a defaulted parameter is exactly the kind of change that compiles everywhere and
means something new in one place.

Verify: new pure tests in `Tests/CanvasCropTests.swift` - a parse/format round trip, out-of-range
and malformed strings rejected without throwing, the 2% floor, `isWhole` true for `"0 0 1 1"` and
for a value one epsilon inside it, `isCroppable` true for png/jpg/jpeg/heic/gif and false for
svg/pdf/md/eml.
Budget: `CanvasCrop.swift`, `BoardGeometry.swift`, `Tests/CanvasCropTests.swift` (~260 lines).

### Task 3 - Controller state and transitions (SPEC §6.5, §6.3)

Modify `Sources/Features/Workspace/WorkspaceController.swift`: four stored properties (D5). New
`Sources/Features/Workspace/WorkspaceController+Crop.swift`: `beginCrop(nodeID:drawnSize:)`,
`updateCrop(handle:translation:lockAspect:)`, `moveCrop(by:)`, `endCrop(confirm:)`,
`removeCrop(nodeIDs:)`, `cropDisplayRect(for:)`.

**Include the three exits the Consequences name**: `open(folder:)`, `detach()` and a successful
`undo()`/`redo()` each end crop mode.

Verify, in `Tests/CanvasTests.swift`'s controller half over a `TemporaryRoot`: confirming writes
exactly one key and one history step; cancelling writes nothing and leaves `hasUnsavedChanges`
alone; cropping back to whole removes the key rather than writing `"0 0 1 1"`; Cmd+Z restores the
uncropped node; navigating away ends the mode.
Budget: `WorkspaceController.swift`, `WorkspaceController+Crop.swift`, `Tests/CanvasTests.swift`
(~280 lines).

### Task 4 - Draw the cropped region in the card (SPEC §6.5 "rendering diretto")

Modify `Sources/Features/Workspace/NodeCard.swift`: `ThumbnailImage` gains `crop: CanvasCrop?` and
requests `width / crop.width` when one is present; `previewCard` passes `CanvasCrop.read(from:
node)`. Cropped drawing is scale-and-offset-and-clip; **the uncropped path is untouched** - same
requested width, same `.aspectRatio(contentMode: .fit)`, same `.task(id:)` key.

**Contract change**: `ThumbnailImage`'s initialiser. One call site, `NodeCard.swift:94` (grepped).

Verify: on screen, since this is drawing. A card with a hand-written `pergamenum-crop` in its
`.canvas` draws the region named and nothing else; the same card with the key deleted draws exactly
as it does on `main`. Full suite green (PDF, email and note cards share this view).
Budget: `NodeCard.swift` (~90 lines).

### Task 5 - The crop editor overlay and the grips (SPEC §6.3, §11.3)

New `Sources/Features/Workspace/BoardCropEditor.swift` beside `BoardOverlays.swift`: the whole image,
the scrim outside the rectangle (`canvasBackground` at 0.7), the outline and eight grips
(`canvasSelection`), the inside-drag to move, Shift to lock. **No hardcoded colour anywhere** - the
binding rule of `CLAUDE.md` and SPEC §11.3.

Modify `Sources/Features/Workspace/BoardContentLayer.swift`: show the editor for
`workspace.croppingNodeID` and **suppress the card's own resize grips** for that node. Modify
`Sources/Features/Workspace/WorkspaceView.swift`: Esc cancels, Enter confirms, a click on the board
background confirms.

Verify: on screen at 100%, 60% and 30% zoom - grips hittable, scrim visible in both themes, Esc and
Enter both land. Refusal below 25% zoom and with no thumbnail yet.
Budget: `BoardCropEditor.swift`, `BoardContentLayer.swift`, `WorkspaceView.swift` (~300 lines).

### Task 6 - The context menu (SPEC §10, §6.5)

Modify `Sources/Features/Workspace/BoardContentLayer.swift`: "Ritaglia" (croppable cards only),
"Rimuovi ritaglio" (cards carrying the key only), and "Adatta al ritaglio" inside the existing
"Ridimensiona" submenu, calling `resize(nodeID:to:)` with the crop's aspect. Italian UI strings,
English code and comments.

Verify: the menu on a `.png`, on a `.pdf`, on a sticky note and on a group shows exactly the items
that apply; "Adatta al ritaglio" is one undo step.
Budget: `BoardContentLayer.swift` (~70 lines).

### Task 7 - The non-destructiveness and round-trip tests (principle 1, principle 4, SPEC §6.2)

Add to `Tests/CanvasCropTests.swift` and `Tests/CanvasTests.swift`:

- **the file is not touched**: SHA-256 the source image before a crop, after a crop, and after
  removing it; all three equal. This is the test that makes the word in the SPEC mean something.
- **the canvas round-trips**: crop, `CanvasStore.save`, `load`, the key is present with the same
  value and every other property of the node is unchanged.
- **a foreign key survives a crop**: a node carrying `someOtherApp.flag` keeps it through
  crop → remove-crop.
- **the value is a JSON string, not an object or a list**: assert the raw type after encoding. This
  is the Obsidian corruption class, asserted in the suite rather than remembered.

Budget: `Tests/CanvasCropTests.swift`, `Tests/CanvasTests.swift` (~140 lines).

### Task 8 - Interop probe, on-screen check, UI suite, and the decision index (probe 2, working agreements)

1. Probe 2: crop a board here, open it in `/Applications/Obsidian.app`, move the same card there,
   save, reopen here. Write the result down - key present, value unchanged, crop still drawn - in
   the ADR or the PR body. A pass criterion with no written answer is not a probe.
2. `scripts/uitests.sh` with no arguments, before the merge to `main`, per the working agreements.
3. Append one line to the "Chain decision index" in `CLAUDE.md`, matching the ADR-0019 entry's
   shape.

No budget: the outcome of a probe cannot be estimated in lines.

## References

- SPEC §6.2 (canvas format and prefixed properties), §6.3 (resize grips), §6.4 tool 5 (Immagine),
  §6.5 (card per tipo, "Card immagine"), §6.6 (Quick Look), §10 (context menus), §11.3 (design
  tokens), §14 (decisions not reopened) - `docs/20260811_Pergamenum_SpecApp.md`
- JSON Canvas 1.0, file node properties - https://jsoncanvas.org/spec/1.0/
- "Canvas file corruption if file node has custom property of type object or list", Obsidian forum,
  July 2024, fixed in v1.7 -
  https://forum.obsidian.md/t/canvas-file-corruption-if-file-node-has-custom-property-of-type-object-or-list/84698
- ADR-0019 (`docs/adr/0019-embed-drag-resize.md`) - the parallel decision one layer up: a size that
  lives only in the content, one undo step at release, transient gesture state.
- ADR-0017 (`docs/adr/0017-the-derived-stores-leave-the-vault.md`) - why the thumbnail cache is
  disposable, which is why a crop cannot live in it.
- `Sources/Core/Canvas/JSONCanvas.swift`, `Sources/Vault/CanvasStore.swift`,
  `Sources/Vault/ThumbnailStore.swift`, `Sources/Features/Workspace/*`, `Tests/CanvasTests.swift`,
  `Tests/BoardInteractionTests.swift`
