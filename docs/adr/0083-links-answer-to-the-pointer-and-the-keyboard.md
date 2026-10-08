# ADR-0083: Links answer to the pointer and the keyboard

- Status: planned. Milestone N3 of the note-workflow chain (`PG-386`, #888), SPEC R-20..R-23.
  The implementation is not on `main`. It lands in N3's session B PR (the editor) and session C PR
  (the GUI tests of §D8); the flip to `accepted` comes in the first docs change after the session C
  PR merges and names both merge commits (SPEC R-31, `docs/adr/README.md` rule 2).
- Date: 2026-10-04, written against `48a2d912`. **Amended 2026-10-07** in place, before any code
  landed: §D7 is rewritten for an `NSPopover` (SPEC Decision "The preview is an `NSPopover`, not a
  `NeverKeyPanel`"), with its first Alternatives paragraph, and every line number below was read
  again on `origin/main` at `a2ada538`. Re-checked facts on that tree: N1 is on `main` (PG-384, PR
  #924, ADR-0080 accepted), PG-219's pointer is on `main` as ADR-0090 (PR #920), ADR-0082's styler
  code is on `main` (PR #921) although its record still reads `planned`, and ADR-0081 is not on
  `main`. This record depends on none of those beyond the `.editorLink` attribute the styler
  writes, which is present. The symbols named are the contract; the lines are where they were on
  `a2ada538`.
- Number: `0083` reserved for this record by the chain's dispatch on 2026-10-04 and checked free
  on every ref (`git log --all -- 'docs/adr/0083*'` printed nothing). Check again immediately
  before the merge (`docs/adr/README.md` rule 1).
- Extends: ADR-0012 §D4 (a link can now land in the other column), ADR-0015 §D1/§D2 (a keyboard
  follow is a step, recorded by the derived destination, never by the call site), ADR-0023 §D1
  (one catalogue on two surfaces, for the disambiguation choice), ADR-0074 §D2/§D3 (the preview's
  state lives in one controller), ADR-0039 (a window-level sheet hosted at `RootView`).
- Coexists with: ADR-0090 (the editor's pointer, drawn from `cursorUpdate`/`mouseMoved` overrides on
  `CompletingTextView`). This record neither edits nor reads those overrides (§D7).
- Amends: nothing.
- Companion: ADR-0084 (the inspector half of N3).

## Context

A wikilink in Pergamenum does one thing: Cmd+click on it opens the first note whose title matches,
in the focused column, and that is all. Measured on `a2ada538`:

- **No preview.** The only hover affordance is a `.toolTip`; nothing shows what a link points at
  without leaving the note.
- **One way to open.** `NoteTextView+Coordinator.textView(_:clickedOnLink:at:)` (line 244)
  checks `.command` through the `modifierFlags` seam and calls `performLinkNavigation(_:)`, which
  now lives in `NoteTextView+LinkNavigation.swift` (split out of the Coordinator because its body
  is at the length the linter allows) and calls `parent.onFollowLink(title)` for a note target.
  There is no new-tab or other-column variant, although the editor has both a tab strip and a
  split view (ADR-0012 §D2/§D4). A second path reaches the same method: «Apri collegamento» in the
  text view's context menu (`CompletingTextView+Pasteboard.swift`, `openLinkFromMenu`, line 283)
  calls `performLinkNavigation(_:)` directly, with no Command held.
- **No keyboard.** No command follows the link under the caret. A person typing has to reach for
  the mouse to go where the text already says.
- **The first match, silently.** `vault.index.resolve(title:).first` decides which note a title
  means at five sites: `CommandActions+LinkNavigation.swift:24` (the editor and the Workspace
  card), `TodayView.swift:231` (Oggi), `DiaryView.swift:141` (Diario), `BoardTray.swift:196`
  (a board's note row) and `VaultSession+Notes.swift:241` (`addStructuralLink`'s target). Two notes
  called «Riunione» in two folders are a normal vault; which one opens depends on a sort.
- **A dangling link is a dead end.** Cmd+click on `[[X]]` with no note «X» records
  «nota non trovata: X» (PG-356) and offers nothing, and the `[[` completion popup shows nothing
  when nothing matches.

SPEC (root, Approved 2026-10-07, which re-confirms the decisions of the chain SPEC approved
2026-10-04) settled the gestures before this record, and they are registered here, not reopened:
the preview fires on Cmd + hover after a 250 ms dwell, never on plain hover; it is an `NSPopover`,
never a `NeverKeyPanel`; Cmd+click follows, Cmd+Shift+click opens in a new tab, Cmd+Opt+click
opens in the other column; Cmd+Opt+Return follows the link at the caret and is remappable;
«apri in una nuova tab» and «apri nell'altra colonna» sit in Vista with no default key; a title
resolving to several notes never opens the first one silently, from any surface; a dangling link
offers «Crea «X»» through the composer, and a draft already parked there is kept; at most three GUI
tests in N3.

Two constraints bind the shape:

- `Sources/Features/Editor/CompletingTextView+Pasteboard.swift` is a protected interface, the
  whole file (`.claude/protected-interfaces`). Its `mouseDown` decides that a Cmd-click is a link
  click and hands it to the delegate, its `linkCharacterIndex(at:)` (line 80) turns a point into a
  link's character index, and its menu item calls `performLinkNavigation(_:)`. Nothing in N3 may
  edit it; N3 calls `linkCharacterIndex(at:)` and keeps the protocol method's signature.
- `CompletingTextView+CursorRects.swift` is ADR-0090's: the pointing hand over a link is decided by
  `cursorUpdate`/`mouseMoved` overrides on the text view, and the per-link tracking areas it once
  held are gone. N3 must not depend on those overrides or edit the file.

## Decision

**D1. One open-link door, with a "how".**

```swift
enum LinkOpening: Equatable, Sendable { case replace, newTab, otherColumn }
```

`LinkOpening` lives in `Sources/Core/Links/` (Foundation only). Every surface that follows a link
goes through `CommandActions.open(link:how:)` (a title or a `.canvas` name) or, once a path is
known, `CommandActions.open(notePath:how:)`: the editor's click, the context menu's «Apri
collegamento», the follow command (D3), the disambiguation choice (D5), the backlink row menu
(ADR-0084 §D1), Oggi, Diario, the Workspace card and the task chip. The existing `open(link:)`
keeps its spelling through a default argument (`how: .replace`), so the Workspace card
(`StickyTextCard`) and the task chip keep their call.

The how reaches the controller as `VaultController.openNote(at:how:)`:

- `.replace` is today's `openNote(at:)` (dedupe in the focused column, the preview tab replaced).
- `.newTab` is today's `openNoteInNewTab(at:)`.
- `.otherColumn` is new, `openNoteInOtherColumn(at:)`: with one column it adds the second
  (`addColumn()`, the session-restore door, not `splitEditor()`, which would copy the source note
  into the new column) and focuses it; with two it focuses the other; then it opens the note there
  with `openNote(at:)`'s own dedupe. Two columns is still the ceiling (ADR-0012 §D4), so this
  extends §D4 by one gesture and changes nothing about what a column is.

The three live in a new file, `VaultController+LinkOpening.swift`: `VaultController+Tabs.swift`,
where `openNote(at:)` and `addColumn()` are, is at 412 lines, past the file-length warning.

The variants apply to note targets only. A `.canvas` board opens in the Workspace whatever the how,
because the Workspace is not a column (ADR-0012 §D4: "only notes"). An external URL opens in the
browser. A file embed keeps its Quick Look preview. A tag or a day target keeps N1's routing
(`onOpenTag`, `onOpenDay`) whatever modifiers are held.

**D2. The click variants are read in the Coordinator, never in the protected file.**

`textView(_:clickedOnLink:at:)` already reads the live flags through the `modifierFlags` seam the
existing tests set. It maps them through one pure function, `LinkOpening.forClick(shift:option:)`:
Option present → `.otherColumn`; else Shift present → `.newTab`; else `.replace`. Option wins over
Shift because "the other column" is the stronger move and a person holding both meant more, not
less. It then calls `performLinkNavigation(_:how:fromClick:)`, the routing body in
`NoteTextView+LinkNavigation.swift`, which grows the how. The protocol method
`performLinkNavigation(_:)` keeps its signature, because the protected file calls it for «Apri
collegamento»; it forwards with `.replace` and `fromClick: false`, so an ambiguous title chosen from
that menu gets the sheet (D5), not a second menu at a point the first one has just left.
`CompletingTextView+Pasteboard.swift` is not touched: its Cmd test still decides that the click is a
link click, and everything after the delegate call is the Coordinator's.

`NoteTextView` keeps `onFollowLink: (String) -> Void` unchanged (54 occurrences under `Tests/` on
`a2ada538`, and the view-block `onOpenNote` hand-off depend on it). The new behaviour arrives as one
grouped input, `links: LinkInputs` in `NoteTextView+Inputs.swift`, empty by default, like `vault`,
`find` and `outline`: `follow` (a request → an outcome, D5), `choose` (a picked row), `preview`
(D7), `onCaretLinkChanged` (D3) and `offerCreation` (D6). With `links.follow` nil the Coordinator
falls back to `onFollowLink(title)` for `.replace` and ignores the variants, so a text view with no
vault behind it behaves as before.

**D3. The keyboard follows the link at the caret.**

Three commands are appended to `ShortcutCommand` (raw values are persisted keys, so appended, never
inserted), section `.view`, in the Vista menu after Indietro and Avanti:

| Command | Title | Default |
|---|---|---|
| `followLink` | Segui il link | Cmd+Opt+Return |
| `followLinkInNewTab` | Apri il link in una nuova tab | none |
| `followLinkInOtherColumn` | Apri il link nell'altra colonna | none |

"None" is `KeyBinding("")`, the value `ShortcutStore` already uses for a cleared override, so the
person can bind either variant in Impostazioni ▸ Scorciatoie. Cmd+Opt+Return is free in the
catalogue (`taskToggle` is `KeyBinding("return", .command)`, `taskAddSubtask`
`KeyBinding("return", [.command, .shift])`); it is measured against `com.apple.symbolichotkeys`
before it ships, the way every default since ADR-0021 was, and the build stops if it is taken
(SPEC edge case).

The editor reports the followable link at the caret on every selection change, the shape
`onOutlineEntryChanged` → `VaultController.recordOutlineEntry(_:inColumn:)` already has:
`links.onCaretLinkChanged` → `VaultController.recordLinkAtCaret(_:inColumn:)` writes
`NoteTab.linkAtCaret: URL?`, transient, never persisted by `OpenTabsStore`, and reset by
`NoteTab.showing(_:)` with the rest of the per-note state. A report rather than a request into the
editor, because the Vista item must know whether it can run before the key is pressed
(`canRun(.followLink)` is "the Note pane is in front and the focused tab has a link at the caret";
SPEC edge case: disabled, not a no-op). The report's body lives in `NoteTextView+LinkAtCaret.swift`
and `textViewDidChangeSelection` calls it in one line, since the Coordinator's body has no room.

Which link: one pure rule, `LinkAtCaret.pick(caret:runs:wikilinks:)` in `Sources/Core/Links/`.
`runs` are the `.editorLink` runs of the caret's paragraph (the URL the styler wrote, the same one
a click follows); `wikilinks` are the source ranges `WikilinkParser.links(in:)` finds in that
paragraph. A run containing the caret, or touching it at either edge, wins; otherwise a wikilink
whose source range contains the caret (inside `[[`, in the alias, on `]]`) maps to the run inside
it; among several candidates the shortest source range wins, which is what "innermost" means. A
file embed at the caret is not followable from the keyboard (its preview is a click on a drawn
picture) and reports nil. The URL is turned into a destination by the same
`MarkdownAttributedText.clickTarget(for:)` the click uses, so the keyboard and the pointer cannot
disagree about what a link points at.

**D4. Cmd+[ returns through ADR-0015, unchanged.**

A follow moves the focused note, so the destination `RootView` derives changes and the history
pushes (ADR-0015 §D2). No follow site calls the history. The other-column variant moves the focus
to the other column, which is also a destination change and also a step. Going back applies
`.note(sourcePath)` the way ADR-0015 already does, in the column that now has the focus; after an
other-column follow that is the second column, so the source shows in both. Recorded as a known
limit, not fixed here: refocusing the column whose front tab already shows the path is a small
amendment to ADR-0015's `apply`, worth its own ticket.

**D5. Several matches are a choice, never a guess.**

One resolution and one catalogue, both pure, in `Sources/Core/Links/`:

```swift
enum LinkDestination: Equatable, Sendable {
    case note(path: String)
    case board(path: String)
    case ambiguous(title: String, paths: [String])
    case missing(title: String, creatable: Bool)
    case missingBoard(name: String)
}
struct LinkChoice: Equatable, Sendable, Identifiable { ... }  // one row: open a path, or create
```

`LinkDestination.resolve(_:notePaths:board:)` takes the index's answer for a title and the board
answer for a `.canvas` name as inputs; the app passes `WorkspaceBoardResolver.resolve(_:in:)`'s
`unique` path (an `ambiguous` or `notFound` board is `missingBoard`, as today), so there is one
board resolver, not two. `LinkChoice.entries(for:)` turns an `.ambiguous` into one row per path,
labelled by its folder through `LinkChoice.folderLabel(of:)` (the vault-relative folder, «radice del
vault» for a note at the root), and a creatable `.missing` into one «Crea «X»» row. The catalogue is
rendered on two surfaces and on two only:

- **At a click**, an `NSMenu` at the click point, built by the Coordinator from the entries and
  shown through a presenter seam (`LinkChoiceMenuPresenting`; production calls
  `NSMenu.popUp(positioning:at:in:)`, which is modal tracking and therefore never runs in a test).
  The editor (`EditorColumnView`), Oggi and Diario host `NoteTextView` and all get it.
- **Otherwise**, a sheet: `LinkChoiceSheet`, hosted at `RootView` through
  `Navigation.linkChoice: LinkChoiceRequest?` (ADR-0039's precedent for a sheet every surface can
  reach, beside `taskPickingBoard`). The keyboard follow, «Apri collegamento», the Workspace card,
  the task chip and the board tray's title fallback get it, since none of them has a live point to
  anchor a menu to.

The silent `.first` goes from every follow site the grep found: `CommandActions+LinkNavigation`,
`TodayView` (which also stops opening a note behind the Oggi pane: following now switches to the
Note pane, as the editor's follow always did), `DiaryView` (its `controller.flush()` stays first),
`BoardTray.resolvedPath(for:)`'s title fallback, and `addStructuralLink` (ADR-0084 §D4 moves it to
a path). `TodayView` and `DiaryView` already read `CommandActions` from the environment. Two more
surfaces in the SPEC's list:

- **The structural-link sheet** selects by path, not by title, and labels a row with its folder
  when its title is shared (ADR-0084 §D4).
- **Quick Open's heading query** (`QuickSwitcher.headingQuery`, which takes
  `vault.index.search(notePart, limit: 1).first`) shows one heading group per note when the note
  part matches several notes' titles exactly, each group headed by its folder label.

The transclusion lookup (`EditorColumn+Text.transclusionSource`) and `QuickSwitcher.creationRow`'s
exact-match check are not follow sites and keep their reads. A board name matching two `.canvas`
files still records «board non trovata» as today: SPEC R-22 is about notes, and the board resolver
has its own `ambiguous` answer for a later change.

**D6. A dangling link offers to create its note, through the composer.**

`missing(title:creatable:)` is creatable when `NoteName.validate(title)` reports nothing and the
title does not end in `.md` or `.canvas`. The suffix rule keeps PG-356's test
(`OpenLinkUnresolvedTests`: `[[TRUST.md]]` names a path, not a title) green and keeps the
«nota non trovata» sentence for it. A creatable target:

- from a click, a one-row menu «Crea «X»» at the click;
- from the keyboard or a sheet surface, the same row in `LinkChoiceSheet`.

Choosing it calls one door, `VaultController.offerNoteCreation(title:besideNoteAt:)`, which fills
the composer's draft with the title and the source note's folder and shows the composer in the Note
pane (`CommandActions` switches the pane from Oggi or Diario). The door lives in
`VaultController+Notes.swift`, beside `beginNewNote(in:seed:)`, because the parked draft it must
read is private to that file. The composer is the one "name a note" surface (SPEC UI flows); N4
extends it and the offer follows whatever it becomes. The offer never creates a file by itself.

**The `[[` popup gets the same row.** When the wikilink completion finds nothing and the typed
text is creatable, the popup shows one row, `CompletionItem.createNote(title:)`, «Crea «X»».
Choosing it completes the link through the insertion N1 shipped for a candidate
(`CompletingTextView.insertWikilink(_:replacing:)`, n1-seams R-07: never `]]]]`), then calls
`links.offerCreation(title)`. A host with no `offerCreation` (a Workspace card, which has its own
`CardWikilinkCompletion`) shows no row. The row's handling lives in a new
`CompletingTextView+CreateNote.swift`, since `CompletingTextView.swift` is at 387 lines.

A draft already parked in the composer with a title is not overwritten by an offer: the offer opens
the composer on the parked draft and records «Una nota è già in preparazione: completala o annullala,
poi riprova» (SPEC edge case: "A draft parked in the composer is kept and the offer says so").

**D7. The preview is an `NSPopover` anchored beside the link, opened by Cmd and the pointer, its
lifecycle owned by one controller.** *Amended 2026-10-07: the record's first §D7 drew it in a
`NeverKeyPanel`; the SPEC reversed that (Alternatives).*

*What it shows* (`LinkPreviewContent.make(...)`, pure):

- a note target: its title and the first twelve lines of its body, or of the heading section when
  the link names one (`[[Nota#Sezione]]`), through `Transclusion.excerpt(of:section:)`, the
  function that already decides what a transclusion shows; a section no heading answers to says so;
- a board target: the board's name;
- several matches: «N note si chiamano «X»» and their folder labels;
- no match: «Nessuna nota si chiama «X»», plus «Cmd+clic per crearla» when creatable;
- an external URL or a file embed: nothing, no popover (SPEC edge case).

The section is not in the link's URL (`MarkdownAttributedText.noteURL(for:)` carries the title
only), so the controller reads it off `WikilinkParser` at the hovered index, the parse `LinkAtCaret`
already uses.

*When it shows* (`LinkPreviewTrigger`, a pure state machine in `Sources/Core/Links/`, time passed
in): Command is held, no non-modifier key has been pressed since, the pointer rests on one
`.editorLink` run, and 250 ms have passed since the last of those became true. Shift and Option do
not matter, so the popover stays while the person reaches for a click variant. The dwell keeps a
Cmd+S or Cmd+F chord typed with the pointer over a link from flashing a popover. It closes on
Command released, the pointer leaving the run, Escape (consumed only while the popover is up), any
key, a scroll, the window resigning key, the text changing, and the note changing.

*Where it lives* (ADR-0074 §D2/§D3): `LinkPreviewController`, a `@MainActor final class` in
`NoteTextView+LinkPreview.swift`, held by the Coordinator as one `lazy` property beside `tables`
and `reveal` and reading the parent's inputs through the same provider at use time. The controller
is the only owner of the lifecycle; nothing else shows or closes the popover. It owns:

- a small tracker `NSResponder` that is the owner of one tracking area over the text view's
  visible rect (`.mouseMoved`, `.mouseEnteredAndExited`, `.activeInKeyWindow`, `.inVisibleRect`;
  with `.inVisibleRect` AppKit tracks the visible rect itself, so no `updateTrackingAreas` re-add
  is needed). The tracker is a separate owner, so `CompletingTextView`'s own `cursorUpdate` and
  `mouseMoved` overrides (ADR-0090) neither see its events nor are needed by it;
- exactly one local event monitor for `.flagsChanged`, `.keyDown` and `.scrollWheel`, installed on
  entry and removed on exit, so it exists only while the pointer is inside the text view (PG-258:
  a monitor that outlived its view was that ticket);
- one observation of the text view's window resigning key, registered while the popover is up and
  removed when it goes;
- the presenter (below), the clock and the scheduler for the dwell, both injected.

The point-to-link resolution is `CompletingTextView.linkCharacterIndex(at:)`, called, not copied:
the protected file stays the one place a point becomes a link. A `mouseMoved` with Command already
down starts the dwell too, so the popover does not depend on a `flagsChanged` arriving after the
pointer. `tearDown()` hides the popover and removes the monitor, the tracking area and the window
observation, whether or not the text view still has a window: it is called from
`NoteTextView.dismantleNSView`, which runs after SwiftUI has detached the text view (its own comment
says so), and a pane switch is a rebuild, not a hide, so a popover left up there would be exactly
PG-258's orphan. Each removal is asserted in-process.

*What it is drawn in*: `LinkPreviewPopover`, the production `LinkPreviewPresenting`, holding one
`NSPopover` created once per controller and reused:

- `behavior = .applicationDefined`. The popover's header (`NSPopover.h`, macOS 27 SDK) gives that
  behaviour to the application, with AppKit closing it only in limited cases such as the
  positioning view's window closing; `.transient` and `.semitransient` close on AppKit's terms, and
  a second owner of the close would fight the trigger's list.
- `animates = false`: the popover follows a held key, and it goes the instant the key is released.
- Never detachable: no delegate implementing `popoverShouldDetach(_:)`.
- `contentViewController` is an `NSHostingController` of `LinkPreviewView`: tokens only, light and
  dark (`appearance` follows the text view's `effectiveAppearance`), identifier `link-preview`, and
  no focusable control in it, no text field, no button, nothing that accepts first responder.
- Anchored with `show(relativeTo:of:preferredEdge:)` to the link run's own rect in the text view,
  preferring the edge below the line; AppKit moves it to the opposite edge when there is no room.
  Anchored to the rect's edge, it is drawn beside the link and never over it, so a Cmd+click aimed
  at the link reaches the link (SPEC Decision). The preferred edge is given in the text view's
  coordinates, which are flipped; the coder confirms "below" on the Debug build rather than
  trusting the constant's name.
- Guarded before every show: no show when the text view has no window, the window is not visible,
  or the run's rect is empty. `NSPopover.h` documents an `NSInvalidArgumentException` for a
  positioning view not in a window and a no-op for one that is not visible, and
  `firstRect(forCharacterRange:)`-style queries answer zero for a range not laid out
  (`.claude/rules/swiftui-views.md`), so the layout is confirmed before the rect is read.

*Never first responder, checked rather than assumed.* `NSPopover.h` declares no property that keeps
the popover's window from becoming key, and whether a shown popover with this content takes key
status is not documented (insufficient data on 2026-10-07). So the presenter samples, immediately
before and after `show`, whether the editor's window is key and whether the text view is its first
responder (`LinkPreviewFocus`). If either went from true to false, it closes the popover at once,
gives first responder back to the text view, and reports the failure, and the trigger stays hidden
until a fresh dwell. The comparison is a pure function, `LinkPreviewFocus.lostKeyboard(before:after:)`,
tested in-process; the GUI test (D8) proves the real popover leaves the keyboard with the editor.
This is the cost the SPEC names: the guarantee rests on a test and a fail-closed check, not on a
type.

Showing and hiding go through the presenter seam, `LinkPreviewPresenting`: a hosted test never
orders a window front (the harness refuses it), so a spy stands in, and the real popover is proved
by one GUI test (D8). `NeverKeyPanel` and `PanelPlacement` are not used by the preview; they stay
what ADR-0074 §D9 made them for the completion popup and the format bar.

**D8. Two of N3's three GUI tests are this record's, and each is the only way to prove its claim.**

Both live in `UITests/WikilinkNavigationUITests.swift`, which already subclasses
`PergamenumUITestCase` and holds `testCommandClickOnAWikilinkNavigatesToTheLinkedNote` (CLAUDE.md:
no file builds its own `XCUIApplication`).

1. **Follow from the keyboard, then return.** Caret moved into `[[Destinazione]]` with arrow keys,
   Cmd+Opt+Return, the destination's editor in front, Cmd+[, the source back. In-process cannot
   prove it: the key equivalent reaches a menu item only through the real menu bar, the history is
   derived by an observer that lives in `RootView`'s body (ADR-0015 §D2), and a hosted view has no
   menu bar and no `RootView`. The pure rule, the caret report, `canRun` and `open(link:how:)` are
   all covered in-process; what this test adds is the chain end to end.
2. **The preview appears and goes.** The pointer over a link inside
   `XCUIElement.perform(withKeyModifiers: .command)`: the popover's `link-preview` element exists;
   after the block (Command released) it does not, and a character typed next lands in the note,
   so the editor kept the keyboard. In-process cannot prove it: the harness refuses `sendEvent` and
   `orderFront`, so neither a modifier-plus-pointer event nor a real popover exists there, and
   `NSPopover.show` is a no-op for a view that is not visible. The trigger, the content, the
   controller's monitor and tracking-area lifecycle, the guards and the focus comparison are
   covered in-process with the presenter spy.

The third GUI test, «Collega» a mention, is ADR-0084 §D7's.

## Alternatives considered

**A `NeverKeyPanel` placed by `PanelPlacement`** (this record's §D7 as written on 2026-10-04).
Rejected on 2026-10-07 by the person's constraint, recorded in the SPEC ("No `NeverKeyPanel` for
the preview", origin PG-258) and matching the roadmap's word: a hand-placed child panel that a
monitor shows and hides is the orphan-window shape PG-258 was about. What it gave is named so that
nobody mistakes the change for a free one: "never key" was a property of the type (`canBecomeKey`
false, ADR-0074 §D9's "enforced rather than assumed"), and `ignoresMouseEvents` let it overlap the
link harmlessly. The popover pays for the first with configuration, a fail-closed check and tests
(D7), and for the second by being anchored beside the link rather than over it; it removes one
positioning path, since AppKit's anchoring replaces `PanelPlacement` for this surface.

**An `NSPopover` with `.transient` or `.semitransient` behaviour.** Rejected: both close on
AppKit's terms (`.transient` on an interaction outside the popover, `.semitransient` on one in the
parent window), which would make two owners of one lifecycle, and the SPEC's close rules (Command
released, pointer leaving, any key, scroll, resign key, text or note change) are the trigger's.
`.applicationDefined` leaves the controller the only one.

**SwiftUI's `.popover` modifier**, used eight times elsewhere in the app. Rejected: it anchors to a
SwiftUI view's frame, and a link is a character range inside an AppKit `NSTextView` inside an
`NSViewRepresentable`; there is no SwiftUI view per link to attach it to, and its presentation is
driven by a binding, not by the controller that owns the trigger.

**Map the click variants in `CompletingTextView.mouseDown`.** Rejected: the file is protected as a
whole, and the delegate method the Coordinator already owns receives every link click with the
flags still readable.

**Change `onFollowLink` to `(String, LinkOpening) -> Void`.** Rejected: it is constructed at
dozens of test sites and handed to view blocks as `onOpenNote`; a grouped `links` input, empty by
default, adds the behaviour without touching a call that does not need it (`vault` and `outline` are
the precedent).

**Resolve ambiguity by a heuristic** (same folder as the source first, most recently opened first).
Rejected: the SPEC's rule is that nothing opens the first match silently, and a heuristic is a
silent first match with better odds. It also makes the same link open different notes from
different places, which is worse than asking.

**Keyboard follow as a request counter into the editor** (the `focusRequest` shape: the command
bumps a value, the editor follows). Rejected as the primary mechanism: the Vista item could not know
whether it can run, so it would be enabled over plain prose and do nothing. The report gives
`canRun` its answer.

**Create the note silently on Cmd+click of a dangling link.** Rejected: a typo becomes a file, and
the note skips the composer, which is where the folder, the template and the topic are chosen (and
where N4 puts `status-inbox` logic and the template choice). An offer costs one click.

**Plain hover after a delay** (the roadmap's 400 ms). Settled by the SPEC (rejected there: popovers
while reading), registered here only so the next reader does not mistake its absence for an
oversight.

## Consequences

Positive:

- A link can be read without leaving the note, opened three ways, and followed from the keyboard.
- No follow site guesses: ambiguity is a visible choice on every surface the grep found.
- A dangling link and an empty `[[` popup become the start of a note instead of a dead end.
- The pointer and the keyboard read one URL, written by the styler, through one `clickTarget`.

Negative:

- "Never first responder" is no longer a property of a type. It rests on the popover's
  configuration, a content view with nothing focusable, the fail-closed focus check and two tests
  (one in-process, one GUI). If a future macOS lets a popover of this kind take key status, the
  check closes it every time and the preview never stays visible: GUI test 2 turns red rather than
  the editor losing the caret.
- `ShortcutTests.noTwoCommandsShipOnTheSameKeys` and `everyShippedDefaultIsUsable` assumed every
  command ships bound. Both are amended, not disabled: an empty default is "ships unbound", excluded
  from the collision walk and from the usability check, and an explicit allow-list
  (`ShortcutCommand.shipsUnbound`, exactly the two variants) is pinned so a third unbound command is
  a red test, not a quiet gap.
- Oggi's follow now switches to the Note pane. Before, it opened a tab behind the Oggi pane where
  nothing was visible; the change is deliberate.
- After an other-column follow, Cmd+[ shows the source in the second column too (D4).
- The preview adds one controller, one tracking area, one popover and, while the pointer is inside,
  one monitor per editor; the lifecycle is the risk PG-258 names, and it is pinned in-process.
- Two GUI tests join the bounded suite; each is justified in D8.

Neutral:

- No on-disk format, frontmatter key, index field or `IndexCache.schemaVersion` changes. No
  protected interface is touched. `NeverKeyPanel`, `PanelPlacement` and ADR-0074 §D9 are unchanged.
- ADR-0090's pointer overrides are untouched and not relied on.
- The connectors are untouched by this record (navigation is the app's).
- `[[Nota#Sezione]]` still opens the note at its top on a click: following a section is not in the
  SPEC and is named here as a gap, not fixed.

## References

- SPEC (root, Approved 2026-10-07): R-20..R-23, R-30, R-31; Decisions "The preview is an
  `NSPopover`, not a `NeverKeyPanel`", "The preview appears on Cmd + hover", "One open-link door
  with a how", "A shared title is a choice", "A dangling link offers «Crea «X»»"; Constraint "No
  `NeverKeyPanel` for the preview"; Edge cases on the preview, Cmd+Opt+Return, the disabled follow
  and the parked draft; Test seams 1, 3, 4.
- `docs/20261003_Pergamenum_NoteWorkflowRoadmap.md` §2 N3; `docs/20261002_Pergamenum_NoteWorkflowReport.md`
  L-1..L-4, I-7.
- `NSPopover.h` and `NSTrackingArea.h` in the macOS 27 SDK (read 2026-10-07): `behavior`,
  `show(relativeTo:of:preferredEdge:)`'s exception and no-op, `animates`, detaching through the
  delegate only; `.inVisibleRect`.
- ADR-0012 §D2/§D4, ADR-0015 §D1/§D2, ADR-0023 §D1, ADR-0039, ADR-0074 §D2/§D3/§D9, ADR-0090,
  PG-219, PG-258, PG-356.
- Plans: `docs/plans/note-workflow-n3-mockup.md`, `docs/plans/note-workflow-n3.md`.
