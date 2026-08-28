# ADR-0027 — Unificare Nota e Testo in un solo strumento del Workspace, con formattazione ricca del testo

- **Date:** 2026-08-28
- **Chain:** `unificare-nota-e-testo-in-un-solo-strume` (concept-to-code, standard path)
- **SPEC:** `/Users/stefer/Developer/Pergamenum/SPEC.md`
- **Plan:** `docs/superpowers/plans/2026-08-28-unificare-nota-e-testo-in-un-solo-strume.md`
- **Supersedes:** nothing. **Builds on:** ADR-0018 (source-mode styling), ADR-0020 (prefixed
  scalar custom properties on a canvas node), ADR-0023 (one command catalogue, two surfaces),
  ADR-0026 §D8 (the window's undo stack).

## Status

Proposed — awaiting Gate 2.

## Context

The Workspace toolbar carries eleven tools (SPEC §6.4). Two of them, **Nota** (`n`) and
**Testo** (`t`), both create a `CanvasNode.Kind.text` node. The chain's premise is that they
are redundant and should collapse into one, and that `.text` cards should in exchange gain
real formatting: bold, italic, strikethrough, lists, headings, plus whole-card text colour
and alignment.

Both card kinds became editable four commits ago (`8c6405c`, branch
`fix/workspace-editable-note-text-cards`, not yet on `main`): `StickyTextCard` swaps a static
`Text` for a SwiftUI `TextEditor` bound to `WorkspaceController.editingTextDraft`, committing
once at `endTextEdit(commit:)` — the transient-draft discipline ADR-0020 §D5 established for
the crop editor.

### What the source actually says, against what the SPEC assumed

Ten claims were checked against the tree at `a6648d1` + the working branch. Six needed
correcting, and three of those change the design.

**C1. "Nota and Testo differ only in whether `node.color` is pre-set." False.** They differ in
three ways. Default size: `addStickyNote` makes a 220×120 card, `addFreeText` a 220×60 one
(`WorkspaceController.swift:588`, `:598`). Rendering: `StickyTextCard` keys its placeholder
string (`:23`), its font token (`.heading` vs `.body`, `:51`, `:65`) and its whole
padding/background/shadow branch (`:26-38`) off `node.color != nil`. So "apply Colore
afterwards" is not equivalent to "create a Nota" today — it also changes the card's typography.
This is a pre-existing coupling, not something this feature introduces, and §D8 below decides
what to do about it.

**C2. "`let tool: Tool = .note` call sites (`addStickyNote`, `WorkspaceView+Creation.swift`)
collapse into the existing `.text`/`addFreeText` path." False, twice over.** There is no such
call site: `grep -rn "Tool\.note|= \.note"` across `Sources/`, `Tests/` and `UITests/` finds
nothing. The only reference to the case outside its own declaration is
`WorkspaceController+Tools.swift:32`. And `addStickyNote` **must survive**, because
`Tool.todo` is the other caller (`+Tools.swift:33`, `.createSticky("- [ ] ")`) — deleting it
would take the To Do tool with it. The `.note` in `WorkspaceView+Creation.swift:72` is
`NewCanvasItemSheet.Kind.note`, an unrelated enum reached from `Tool.document`, which creates
a real `.md` file.

**C3. "That binding has no notion of a text selection, which is why selection-based formatting
requires replacing that `TextEditor` with an `NSTextView`." False as stated.** The MacOSX26.5
SDK ships `TextEditor(text: Binding<String>, selection: Binding<TextSelection?>)`, and
`TextSelection.Indices` exposes `case selection(Range<String.Index>)` with a matching
`init(range:)` — readable *and* restorable
(`…/MacOSX26.5.sdk/…/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface`). A plain
`TextEditor` on this deployment target can do selection-based markdown mutation today. The
conclusion (an `NSTextView`) is still right, but for two reasons the SPEC never gave —
per-range *styling* and a *selection rectangle* — and getting the reason right is what decides
how much gets built (§D1, alternative A1).

**C4. "A floating formatting mini-toolbar … (Notion/Pages-style)", presented as new.
Incomplete.** The app already has one, shipped at M8 for the note editor: `FormatBar.swift`
(the pill), `FormatBarPanel.swift` (the never-key child window that places it),
`CompletingTextView+FormatBar.swift` (when it appears, what each button does) and
`Sources/Core/Editor/InlineFormat.swift` (the pure wrap/unwrap arithmetic, including the
`isLongerMarker` guard for exactly the `****text**` nesting the SPEC's edge-case list worries
about). Bold, italic, strikethrough and code are already implemented, already tested, and
already correct.

**C5. Architecture §3, "where they are read/written in `CanvasNode`/`JSONCanvas.swift`".
False against the precedent it cites.** ADR-0020 §D2 deliberately keeps `pergamenum-crop`
*out* of `JSONCanvas.swift`. The key lives on `CanvasNode.unknown`, which `CanvasNode.init?`
already populates with every unrecognised key (`JSONCanvas.swift:187-189`) and `rawValue`
already re-emits (`:193`); the accessor is `CanvasCrop.read(from:)` in
`Sources/Features/Workspace/CanvasCrop.swift`. The codec is not touched, and must not be.

**C6. "No new persisted schema needed for these." True for persistence, incomplete for
rendering.** `MarkdownStyler` has no list span at all — the word "list" appears once in that
file, in a comment (`MarkdownStyler.swift:381`). A `- ` or `1. ` prefix will be written to the
node and will not be styled by anything. §D6 decides the scope boundary.

Four claims checked out and are relied on below: Cmd+B and Cmd+I are genuinely unbound
(`ShortcutCommand.swift:215` is `newBoard` at Cmd+Shift+B, `:276` is `toggleInspector` at
Cmd+Opt+I, and no other `b`/`i` binding exists); `.text`'s title/symbol/shortcut are as
described (`WorkspaceController.swift:29`, `:45`, `:59`); `editingTextNodeID`/
`editingTextDraft` are the transient mechanism (`:482-486`); and JSON Canvas 1.0 does permit
application-specific keys on a node and does define `text` as markdown (obsidianmd/jsoncanvas,
`_autodocs/parsing-and-serialization.md`, `_autodocs/nodes.md`).

### Two constraints the SPEC could not know

**The note editor is fenced.** `.claude/protected-interfaces` line 3 covers
`Sources/Features/Editor/CompletingTextView+Pasteboard.swift` — the note-title drop contract
ADR-0026 depends on. Any refactor that extracts a shared base out of `CompletingTextView` has
a live chance of touching it, and `interface-check.sh` BLOCKS on that.

**A dangling undo target crashes the app.** Commit `a853e8e`, landed today, added
`NoteTextView.dismantleNSView` to purge undo actions still targeting a deallocated text view
or its storage: leaving them produced `EXC_BAD_ACCESS` in `-[_NSUndoStack popAndInvoke]`,
reproduced by typing in a note, moving a board in the sidebar, and pressing Cmd+Z twice. A
canvas card's text view is created and destroyed far more often than the note editor's — once
per card, and again every time a card crosses the culling rect
(`BoardContentLayer.visibleNodes`). This feature walks straight into that trap unless it is
designed out.

## Decision

Build a **small, card-scoped `NSTextView`** that shares the note editor's *pure* logic and
none of its *view* classes. Reuse is drawn at the Foundation-only line, which is the line the
repo already draws: `Sources/Core/Editor/InlineFormat.swift`'s own header says it is under
`Sources/Core`, which both connectors compile, so it may import Foundation and nothing else.
Everything the card needs that is genuinely shareable is already on that side of the line, or
can be put there.

### D1 — The card gets its own `NSTextView`, and shares no AppKit class with the note editor

Two new files under `Sources/Features/Workspace/`:

- `FormattingTextView.swift` — `final class FormattingTextView: NSTextView`, built with
  `usingTextLayoutManager: true`. Its whole job is: style the source, report its selection
  rectangle in view coordinates, claim Cmd+B/Cmd+I, and apply a format as one undoable edit.
- `CardTextView.swift` — `struct CardTextView: NSViewRepresentable`, the bridge, with a
  `Coordinator` for `NSTextViewDelegate`.

The naming mirrors the pair that already exists — `NoteTextView` (bridge) plus
`CompletingTextView` (view) — so the second pair reads as a sibling rather than a fork.

**What is reused, verbatim, with no edit to the file it lives in:**

- `InlineFormat.toggled(_:in:over:)` for bold/italic/strikethrough. Foundation-only, already
  tested, and its `isLongerMarker` guard already answers the SPEC's `****text**` edge case.
- `MarkdownStyler.spans(in:)` as the *classifier*. It says what each range is; it never
  removes or replaces a character, which is precisely what a source-mode card wants.

**What is deliberately not reused:**

- `MarkdownAttributedText.attributes(for:theme:)`, the note editor's *look*. Its `.bold` arm
  returns `NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)`
  (`MarkdownAttributedText.swift:56`), a source-mode choice that is right in a note and wrong
  on a canvas card, where bold must simply be bold. The card gets its own attribute table,
  `CardTextAttributes`, in its own file. This also means the note editor's styling is not
  touched at all, which keeps the two surfaces free to look different on purpose.
- `CompletingTextView` and every `NoteTextView+*` extension. `NoteTextView` carries about forty
  inputs — note titles, tags, slash commands, emoji, embeds, transclusions, folding, find
  matches, outline ranges — none of which a canvas card has. Nothing is extracted from it, so
  the protected `CompletingTextView+Pasteboard.swift` is never in the blast radius.
- `FormatBarPanel`. See §D5.

**What is newly written to the shared side:** `Sources/Core/Editor/LineFormat.swift`,
Foundation-only, the line-prefix arithmetic `InlineFormat` has no equivalent of (§D6). Note
that `Sources/Core/**` is a glob in `Project.swift`'s `sharedSources` (`:73`), so this file is
compiled into `perg` and `pergamenum-mcp` automatically — and an `import AppKit` in it breaks
both connector builds rather than breaking itself, exactly as `InlineFormat.swift`'s own
header warns.

### D2 — The card's text view owns its undo manager, and purges it on dismantle

The `Coordinator` holds a private `UndoManager` and returns it from
`NSTextViewDelegate.undoManager(for:)`. The card's typing undo therefore never reaches the
window's stack.

This does not reverse ADR-0026 §D8. That decision said there are not two undo *domains* in
this app to keep apart — the sidebar's move-undo and the note editor's typing-undo are both
window-level operations on the vault, so they share the window's manager. A canvas card is
already outside that argument: the board's own Annulla is `BoardHistory` via
`workspace.undo()` (`WorkspaceController.swift:370`), a third stack that has never been the
window's. Pushing "restore the letter I typed into a card" onto the window's manager would put
a step the user cannot see between them and the board undo they meant.

`CardTextView.dismantleNSView` still purges actions targeting the view and its text storage,
mirroring `NoteTextView.dismantleNSView` (`NoteTextView.swift:331-337`). Belt and braces: the
private manager should make it unreachable, and the cost of being wrong about that is the
`a853e8e` crash on a view that is deallocated every time a card scrolls out of the culling
rect.

### D3 — One component, two states, and `isEditable` is the only difference

`CardTextView` is used for both display and editing, per the interview's decision. At rest:
`isEditable = false`, `isSelectable = false`, so the card's own tap/drag/double-click gestures
keep the pointer — which is the same condition `BoardContentLayer.selectionGestures(enabled:)`
already switches on (`:60`, `:226-245`). While editing: both true.

It is always inside an `NSScrollView` with `drawsBackground = false` and scrollers hidden.
Whether the view can be scrolled changes; what is drawn does not, which is what R-08 asks for.
Dropping the scroll view entirely would have been simpler but would regress today's
`TextEditor`, which scrolls when a card's text overflows its frame.

### D4 — `pergamenum-textColor` and `pergamenum-textAlign` follow the `CanvasCrop` shape exactly

A new value type `CardTextStyle` in `Sources/Features/Workspace/CardTextStyle.swift`, beside
`CanvasCrop.swift` and built the same way: `static let colorKey` / `static let alignKey`,
`read(from node: CanvasNode)`, a `formatted` string per key, and **no edit to
`Sources/Core/Canvas/JSONCanvas.swift`** — correcting C5. Nothing that reads out of `unknown`
ever mutates it, ADR-0020 §D2's own rule.

Encoding:

- `pergamenum-textAlign`: the string `"left"`, `"center"`, `"right"` or `"justify"`. Absent
  means natural. A malformed or unrecognised value is read as absent and is never corrected or
  removed, the same non-mutating rule `CanvasCrop.read` documents.
- `pergamenum-textColor`: a **`CanvasColor` raw value** — `"1"`…`"6"` for the JSON Canvas
  presets, or `"#RRGGBB"`. This is the third option, neither of the two the SPEC offered, and
  it is better than both: the type already exists in `JSONCanvas.swift:79-100`, already
  parses, already validates the 1…6 range, already round-trips, and it means a card's *text*
  colour and a card's *background* colour speak one vocabulary instead of two. Absent means
  `theme.color(.textPrimary)`, i.e. exactly today.

Presets are drawn from a fixed six-entry sRGB table on `CardTextStyle`, not from theme tokens.
This is the same carve-out `StickyTextCard.stickyColor` already takes for `CanvasColor.hex`
(`StickyTextCard.swift:76-79`, which calls `RGBA(hex:)` on a value read from the file): the
design system's "no hardcoded colour in a view" rule governs a view *choosing* a colour, and
this is a file-format value being *decoded*. The rule's purpose — that the app's own palette
stays themeable — is untouched, and the alternative would make a canvas authored in Obsidian
render its colour coding differently here, which CLAUDE.md principle 4 forbids.

### D5 — The floating bar is a board overlay in board space, never an `NSPanel` in screen space

`FormatBarPanel` positions itself from **screen coordinates**, taken from
`firstRect(forCharacterRange:actualRange:)` (`CompletingTextView+FormatBar.swift:67`). The
board wraps its whole content layer in `.scaleEffect(workspace.zoom, anchor: .topLeading)`
(`WorkspaceView.swift:354`) and then offsets by `pan`. An `NSView` hosted inside that is drawn
through a layer transform SwiftUI owns and AppKit's own geometry conversion does not
necessarily walk — so a panel placed from `firstRect` is placed from a rectangle that may know
nothing about the zoom or the pan.

Rather than measure whether that particular conversion happens to work, take the design that
is correct by construction and is already this file's own precedent. `BoardMarquee` and
`BoardGuides` (`BoardOverlays.swift:16-19`, `:44`) draw over the board as SwiftUI siblings
**outside** the `scaleEffect`, converting a board point `p` with the documented transform
`p * zoom + pan`. The new `BoardFormatBar` does the same:

1. `FormattingTextView` reports its selection rectangle in **its own view coordinates**,
   computed with TextKit 2's `textLayoutManager.enumerateTextSegments(in:type:.selection)`
   plus `textContainerOrigin` — a purely local measurement, unaffected by any ancestor
   transform, and never a screen coordinate.
2. The card adds its own board origin (`node.x`, `node.y`) to get a board point.
3. `BoardFormatBar` draws at `p * zoom + pan`, outside the `scaleEffect`, so the pill stays a
   constant size on screen at every zoom instead of shrinking to nothing at 25%.

The arithmetic in step 2 and 3 is a static function and is unit-testable without a window,
which is the point of putting it there.

### D6 — Lists and headings are line operations, and the card says so; the note editor's bar is not touched

`FormatBar.swift:9-11` records a decision with a reason: **no headings and no lists**, because
"a bar that appears over a selection and then acts on the whole line would be doing something
other than what is selected". R-05 requires both on a card. That is not a contradiction to
resolve by overruling the note editor — it is two surfaces where the same rule has different
force. In a note, a selection is a phrase inside a long document and the enclosing line is
invisible context. On a card of three or four lines, a selection is almost always whole lines
already.

So: the card gets its **own** bar, `CardFormatBar`, with its own catalogue.
`FormatBar.swift`, `FormatBarPanel.swift` and `CompletingTextView+FormatBar.swift` are not
edited by this chain at all. The cost is two pill views that could drift apart visually; that
is accepted, because the alternative is editing the note editor's shipped, reasoned design to
serve a canvas card.

`LineFormat` (`Sources/Core/Editor/`) is the new pure type. It operates on the full lines the
selection touches and toggles: applying a prefix already present removes it, applying a
heading level over a different level replaces it rather than stacking `#`, and a numbered list
renumbers from 1 across the affected run.

**Scope boundary, stated rather than discovered.** `MarkdownStyler` has no list span (C6), so
a list prefix written by `LineFormat` is *stored correctly and rendered as plain text*. Adding
a `.listMarker` span would change the note editor's appearance too, which is outside this
feature. R-05 asks that the prefix be inserted correctly, and that is what is delivered.
Headings do render, because `.heading` and `.headingMarker` spans already exist.

### D7 — Whole-card colour and alignment live on the command catalogue, never on the selection bar

The SPEC left this open ("in the same mini-toolbar (or the card's existing context menu /
`BoardCardControls`, per the ADR's UI-surface decision)") and then asked for "a visual
separator between the 'this selection' and 'this card' groups" to explain the difference. The
separator is decoration over an incoherence: the selection bar exists only while there is a
selection (an explicit SPEC edge case), and only while the card is being edited, so putting a
card-wide property there makes it unreachable at rest and makes the user select text to set
something that has nothing to do with the selection.

Two new `CardCommand` cases instead — `.textColor` and `.textAlign` — each with a submenu, the
shape `.color` and `.resize` already use (`BoardCardMenu.swift:191-194`). This is ADR-0023
§D1's own model: one catalogue, rendered by both the context menu and `BoardCardControls`, so
the two surfaces cannot offer different commands. It puts "text colour" exactly where
"Colore" already is.

**A consequence worth naming:** this answers the SPEC's open question about
`editingTextDraft`'s type with *no change at all*. Colour and alignment are written straight
to the document through `mutate`, as `setColor(_:forNodeIDs:)` already does
(`WorkspaceController.swift:529`). They never enter the draft, `endTextEdit(commit:)` and
`setText` are untouched, and the edge case "deleting all text leaves the properties in place"
holds by construction, because they were never attached to the text.

### D8 — `.note` is removed and nothing else about the two card shapes changes

`case note` goes from `Tool` and from its three exhaustive arms (`shortcut`, `title`,
`symbol`) plus `tapBehaviour`. `addStickyNote` **stays**, because `.todo` needs it (C2).
The `n` key is freed and assigned to nothing, as R-01 requires.

`addFreeText`'s 220×60 default is kept unchanged, per R-02's "exactly today's `.text`/Testo
behavior" — even though a 60-point-tall card is cramped for a rich-text surface, and even
though C1 means a card that later gets "Colore" applied also changes typography. Both are
pre-existing and both are visible; changing either here would be an unrequested change riding
along inside a unification. They are recorded in Consequences as follow-ups, not fixed.

### D9 — Protected interfaces: nothing is touched, and one entry is proposed

Checked, one by one:

- `Sources/Index/IndexCache.swift:schemaVersion` — **untouched.** `.canvas` files are not in
  the index at all (`VaultScanner.scan()` keeps only `.md`), so no node property can reach it.
- `Sources/Connector/VaultPayloads.swift:VaultAPI.LintFinding` — **untouched.** No connector
  change of any kind; a `.text` node carrying markdown and two extra prefixed keys is still a
  `.text` node to `VaultAPI`, and the SPEC's "No connector-facing API change" holds.
- `Sources/Features/Editor/CompletingTextView+Pasteboard.swift` — **untouched, and §D1 is
  written to keep it that way.** This is the constraint that rules out extracting a shared
  base class from the note editor, which would otherwise have been the obvious move.

Adding `CardCommand` cases touches no protected entry — `CardCommand` is not in the file.

**Proposed, not written** (see the report's `PROPOSED PROTECTED INTERFACES:` block): a single
entry covering `Sources/Features/Workspace/CardTextStyle.swift`'s two key constants. The
argument for it is that these strings are written into user files in an interoperable format,
and renaming one silently orphans every card a user has styled — the same class of harm as a
`schemaVersion` bump. The argument against is that `CanvasCrop.key` was never given an entry
for the identical class of value, so adding one only here is an inconsistency, and this check
BLOCKS once declared (ADR-0053 §D2). The consistent version covers both files. The operator
decides at Gate 2; nothing here creates or edits the file.

## Alternatives considered

**A1 — Keep SwiftUI's `TextEditor` and add the new `selection:` binding.** Genuinely available
on this deployment target and verified in the installed SDK (C3): `TextEditor(text:
Binding<String>, selection: Binding<TextSelection?>)` gives a `Range<String.Index>` that can be
read and restored, so R-03, R-04 and R-05 are all reachable with a fraction of the code and no
AppKit at all. **Rejected because it cannot satisfy R-08 or UI flow 2.** A `String`-bound
`TextEditor` cannot style a range, so bold would be stored and never drawn — the card would
show `**parola**` forever, which is the feature not existing. And it exposes no geometry for a
selection, so the floating bar has nothing to hang off. This was the closest call in the ADR
and it is worth recording that the SPEC's own stated reason for rejecting it was wrong while
its conclusion was right.

**A2 — `TextEditor(text: Binding<AttributedString>, selection:)`, the macOS 26 rich-text
editor.** Also real and also in the SDK (`swiftinterface:3064`). It would give bold, italic,
alignment and colour natively, with no `NSTextView`, no styler and no markdown arithmetic.
**Rejected on the file format.** JSON Canvas stores a text node's content as markdown
(confirmed against obsidianmd/jsoncanvas `_autodocs/nodes.md`), so every keystroke would need
an `AttributedString` ↔ CommonMark conversion in both directions, and the app owns no such
converter — `MarkdownStyler` classifies source, it does not parse to a document model.
Rounding a user's text through a lossy conversion on every edit is how a vault loses content.
It is also a WYSIWYG model, which contradicts ADR-0018's whole premise that this app edits
markdown *source* with the syntax visible and styled. A card that hides its markers while the
note editor shows them is two apps in one window.

**A3 — Extract a shared TextKit 2 base class out of `CompletingTextView` for both surfaces.**
The SPEC's Architecture §1 names this as the interview's direction ("reuse/adapt, not duplicate
wholesale"). **Rejected on blast radius and on a protected interface.** `CompletingTextView` is
358 lines of note-specific behaviour with eight extension files and about forty inputs on its
bridge; one of those files, `+Pasteboard.swift`, is a declared protected interface that
`interface-check.sh` blocks on. Extracting a base would mean editing the note editor — the
app's single most load-bearing view, with ADR-0018, ADR-0019 and ADR-0023 decisions embedded in
it — for the benefit of a canvas card that needs no completion, no embeds, no transclusion, no
folding and no find bar. §D1's line, sharing the Foundation-only logic and none of the AppKit
classes, gets the interview's intent with none of the cost.

**A4 — Reuse `FormatBarPanel` for the card's floating bar.** It exists, it works, it is
already a never-key panel that lets the text view keep first responder, and it would be about
twenty lines of wiring. **Rejected on the board's zoom transform.** It places itself from
screen coordinates derived from `firstRect(forCharacterRange:)`, and the board's content lives
inside `.scaleEffect(zoom, anchor: .topLeading)` plus a `pan` offset (`WorkspaceView.swift:354`).
Whether AppKit's conversion walks SwiftUI's layer transform is not something to find out by
shipping; §D5's board-space overlay is correct at every zoom by construction and reuses the
transform this exact file already documents twice.

**A5 — Add lists and headings to the existing `FormatBar` and use one bar for both surfaces.**
One pill view, no divergence risk, one catalogue. **Rejected because it overrules a recorded
decision to serve a different surface.** `FormatBar.swift:9-11` states, with its reason, that
line operations do not belong on a selection bar; those belong on `/`, "which writes at the
caret and is honest about it". Changing the note editor's bar so a canvas card can have
bullets is a change to a shipped, reasoned design made for a reason that does not apply to it.
§D6 keeps them separate and records the divergence instead of hiding it.

**A6 — Store colour and alignment as a `ColorToken` raw value and an integer alignment.** The
two options the SPEC offered. **Rejected on both halves.** A `ColorToken` raw value
(`"color.text.primary"`) is meaningless to any other reader of the file and couples a
portable vault file to this app's token catalogue, which is a thing that changes. An integer
alignment would be `NSTextAlignment.rawValue`, an AppKit implementation detail leaking into an
interoperable format, where `.natural` and `.left` differ by platform. §D4's `CanvasColor` raw
value plus a spelled-out alignment string is readable by a human opening the `.canvas`, needs
no new parser, and reuses a type the format already defines.

**A7 — Put text colour and alignment on the floating bar with a separator, as the SPEC
sketched.** One surface for everything a user might want to do to a card's text. **Rejected
because the bar is the wrong lifetime.** It appears only while editing *and* only while a
selection is non-empty (both SPEC constraints), so a card-wide property placed there is
unreachable at rest and demands an irrelevant text selection to set. §D7 puts it beside
"Colore", where the card's other card-wide property already is.

**A8 — Keep both tools and only add formatting.** The smallest possible change: R-03 through
R-12 without R-01 or R-02. **Rejected because it makes the redundancy worse, not better.** Once
a `.text` card has real formatting, "Nota" and "Testo" differ only in a background colour and a
default height while both offering the identical rich editor — two toolbar slots for one thing,
now with more surface area behind each. The unification is cheaper before the feature lands
than after.

## Consequences

### Positive

- The note editor is not modified. Not one file under `Sources/Features/Editor/` is edited by
  this chain, which keeps ADR-0018's reveal rules, ADR-0019's resize gesture, ADR-0023's embed
  menu and the protected `+Pasteboard.swift` drop contract entirely out of the blast radius.
- `InlineFormat` is reused verbatim, so R-03's correctness — including the `****text**` nesting
  edge case and the two selection shapes a double-click versus a drag produce — arrives already
  tested rather than reimplemented.
- The codec is untouched. `JSONCanvas.swift` gains nothing, so R-07 and R-10 hold by
  construction: a node with neither key decodes and re-encodes exactly as it does today,
  through the same `unknown` passthrough that has carried `pergamenum-crop` since ADR-0020.
- `endTextEdit(commit:)`, `setText` and `editingTextDraft`'s `String` type are all unchanged
  (§D7), so the ADR-0020 §D5 commit discipline is preserved without a single edit to it.
- Card-wide colour and alignment land on the existing command catalogue, so they get
  `BoardCardControls`, the context menu, accessibility identifiers and `CardCommandTests`'
  existing exhaustive coverage for free.
- The board-space overlay (§D5) is correct at every zoom and keeps the pill a constant on-screen
  size, which the screen-coordinate panel would not have done even if its conversion had worked.
- `LineFormat` on the `Sources/Core` side is testable with no window, no theme and no AppKit,
  and is reachable from a connector later if a `perg` command ever wants it.

### Negative

- **Two format-bar views now exist** (`FormatBar` for notes, `CardFormatBar` for cards) and can
  drift apart visually. Accepted deliberately in §D6; the alternative was editing the note
  editor's recorded design.
- **A list prefix is written but not styled** (§D6). A user who applies a bullet list sees the
  `- ` characters, not a bullet. This is honest source mode and consistent with the rest of the
  app, but it will read as half-finished next to bold, which does render.
- **Bold in a card and bold in a note will look different**, because the card gets its own
  attribute table rather than the note's monospaced source-mode `.bold` (§D1). Intended, and a
  second place where "the same markdown" has two appearances.
- **One `NSTextView` per visible `.text` card.** Today's cards at rest are a static `Text`,
  which is far cheaper. A board with many text cards now builds a real text view for each one
  inside the culling rect. `BoardGeometry.drawsPlaceholder(at:)` already replaces card content
  below a quarter zoom, which caps the worst case, but this is a real cost that did not exist.
- **A card's text now goes through the full note styler**, so a `#tag`, a `[[Nota]]` and the
  `- [ ] ` of a To Do card get styled where nothing styled them before. Visible change to
  existing boards on first open. Links are styled but deliberately not made clickable — a
  navigation surface nobody asked for.
- **Two more `CardCommand` cases** means four existing exhaustive test fixtures need updating
  in the same commit (see the plan's contract table), and the catalogue grows from ten to
  twelve, which is more menu.

### Neutral

- `addStickyNote` survives with one caller instead of two (`Tool.todo`). Its `color:` parameter
  keeps its `.preset(3)` default even though nothing now passes a different value.
- The `n` shortcut is freed and left unassigned, exactly as R-01 asks. Nothing claims it.
- `addFreeText`'s 220×60 default and the `node.color != nil` typography coupling (C1) are both
  left exactly as they are (§D8). Either could reasonably be revisited; neither is this
  feature's business, and both are now written down rather than folklore.
- The `.text` node's markdown content is unchanged in shape, so a card round-trips through
  Obsidian as it always has; the two new keys are additive and Obsidian preserves unrecognised
  node keys by the same rule this app does.
- `Tool` is transient state (`var tool: Tool = .select`) and is never persisted, so removing a
  case needs no migration and can break nothing on disk.

## References

- SPEC: `/Users/stefer/Developer/Pergamenum/SPEC.md`
- ADR-0018 `docs/adr/0018-the-editor-hides-the-syntax-it-can-draw.md` — source-mode styling,
  `MarkdownStyler`'s "says what a range is, never replaces it" contract.
- ADR-0020 `docs/adr/0020-image-card-crop.md` — §D2 the prefixed scalar custom property on
  `CanvasNode.unknown` with the codec untouched; §D5 the transient-draft, commit-once discipline.
- ADR-0023 `docs/adr/0023-universal-command-surface-parity.md` — §D1 one command catalogue read
  by both the context menu and the control bar.
- ADR-0026 `docs/adr/0026-drag-and-drop-board-files-into-workspace.md` — §D8 the window's undo
  stack, and why a canvas card is outside that argument (§D2 above).
- `.claude/protected-interfaces` — the three declared entries, all checked in §D9.
- Commit `a853e8e` — `NoteTextView.dismantleNSView`, the dangling-undo-target crash.
- Commit `8c6405c` (branch `fix/workspace-editable-note-text-cards`) — the `TextEditor` this
  feature replaces.
- MacOSX26.5 SDK, `SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface` — `TextEditor`'s three
  initialisers, `TextSelection.Indices`, `AttributedTextSelection` (A1, A2).
- JSON Canvas 1.0, obsidianmd/jsoncanvas `_autodocs/nodes.md` and
  `_autodocs/parsing-and-serialization.md` — text nodes are markdown; custom fields are allowed
  and must be preserved across a load/modify/save cycle.
