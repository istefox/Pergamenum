# ADR-0083: Links answer to the pointer and the keyboard

- Status: planned. Milestone N3 of the note-workflow chain (`PG-386`, #888), SPEC R-20..R-23.
  The implementation is not on `main`; the flip to `accepted` names the merge commit of the N3
  code PR.
- Date: 2026-10-04. Written against `48a2d912` (`origin/main` at the time). Every line number
  below was read there. N3 is built after N1 (ADR-0080, PG-219's pointer) and N2 (ADR-0081, ADR-0082) merge,
  so the line numbers will have moved by then; the symbols named are the contract, not the lines.
- Number: `0083` reserved for this record by the chain's dispatch on 2026-10-04 and checked free
  on every ref (`git log --all -- 'docs/adr/0083*'` printed nothing). Check again immediately
  before the merge (`docs/adr/README.md` rule 1).
- Extends: ADR-0012 §D4 (a link can now land in the other column), ADR-0015 §D1/§D2 (a keyboard
  follow is a step, recorded by the derived destination, never by the call site), ADR-0023 §D1
  (one catalogue on two surfaces, for the disambiguation choice), ADR-0074 §D2/§D3 (the preview's
  state lives in one controller), ADR-0039 (a window-level sheet hosted at `RootView`).
- Amends: nothing.
- Companion: ADR-0084 (the inspector half of N3).

## Context

A wikilink in Pergamenum does one thing: Cmd+click on it opens the first note whose title matches,
in the focused column, and that is all. Measured on `48a2d912`:

- **No preview.** The only hover affordance is a `.toolTip`; nothing shows what a link points at
  without leaving the note.
- **One way to open.** `NoteTextView+Coordinator.textView(_:clickedOnLink:at:)` (line ~240)
  checks `.command` and calls `performLinkNavigation(_:)`, which calls `parent.onFollowLink(title)`.
  There is no new-tab or other-column variant, although the editor has both a tab strip and a
  split view (ADR-0012 §D2/§D4).
- **No keyboard.** No command follows the link under the caret. A person typing has to reach for
  the mouse to go where the text already says.
- **The first match, silently.** `vault.index.resolve(title:).first` decides which note a title
  means at five sites: `CommandActions+LinkNavigation.swift:24` (the editor and the Workspace
  card), `TodayView.swift:225` (Oggi), `DiaryView.swift:130` (Diario), `BoardTray.swift:196`
  (a board's note row) and `VaultSession+Notes.swift:232` (`addStructuralLink`'s target). Two notes
  called «Riunione» in two folders are a normal vault; which one opens depends on a sort.
- **A dangling link is a dead end.** Cmd+click on `[[X]]` with no note «X» records
  «nota non trovata: X» (PG-356) and offers nothing, and the `[[` completion popup shows nothing
  when nothing matches.

SPEC (root, Approved 2026-10-04) settled the gestures before this record, and they are registered
here, not reopened: the preview fires on Cmd + hover only (plain hover after a delay was
rejected); Cmd+click follows, Cmd+Shift+click opens in a new tab, Cmd+Opt+click opens in the
other column; Cmd+Opt+Return follows the link at the caret; «apri in una nuova tab» and «apri
nell'altra colonna» sit in Vista with no default key; a title resolving to several notes never
opens the first one silently, from any surface; at most three GUI tests in N3.

Two constraints bind the shape:

- `Sources/Features/Editor/CompletingTextView+Pasteboard.swift` is a protected interface, the
  whole file (`.claude/protected-interfaces`). Its `mouseDown` decides that a Cmd-click is a link
  click and hands it to the delegate; nothing in N3 may edit it.
- `CompletingTextView+CursorRects.swift` (per-link tracking areas, the pointing hand) is N1's
  territory (PG-219, SPEC R-09). N3 must not depend on its details or edit it.

## Decision

**D1. One open-link door, with a "how".**

```swift
enum LinkOpening: Equatable, Sendable { case replace, newTab, otherColumn }
```

`LinkOpening` lives in `Sources/Core/Links/` (Foundation only). Every surface that follows a link
goes through `CommandActions.open(link:how:)` (a title or a `.canvas` name) or, once a path is
known, `CommandActions.open(notePath:how:)`: the editor's click, the follow command (D3), the
disambiguation choice (D5), the backlink row menu (ADR-0084 §D1), Oggi, Diario, the Workspace card
and the task chip. The existing `open(link:)` becomes `open(link:how: .replace)`'s spelling and
stays as a one-line forward, so the Workspace card (`StickyTextCard`) and the task chip keep their
call.

The how reaches the controller as `VaultController.openNote(at:how:)`:

- `.replace` is today's `openNote(at:)` (dedupe in the focused column, the preview tab replaced).
- `.newTab` is today's `openNoteInNewTab(at:)`.
- `.otherColumn` is new, `openNoteInOtherColumn(at:)`: with one column it adds the second
  (`addColumn()`, the session-restore door, not `splitEditor()`, which would copy the source note
  into the new column) and focuses it; with two it focuses the other; then it opens the note there
  with `openNote(at:)`'s own dedupe. Two columns is still the ceiling (ADR-0012 §D4), so this
  extends §D4 by one gesture and changes nothing about what a column is.

The variants apply to note targets only. A `.canvas` board opens in the Workspace whatever the how,
because the Workspace is not a column (ADR-0012 §D4: "only notes"). An external URL opens in the
browser. A file embed keeps its Quick Look preview.

**D2. The click variants are read in the Coordinator, never in the protected file.**

`textView(_:clickedOnLink:at:)` already reads the live flags through the `modifierFlags` seam the
existing tests set. It maps them through one pure function, `LinkOpening.forClick(shift:option:)`:
Option present → `.otherColumn`; else Shift present → `.newTab`; else `.replace`. Option wins over
Shift because "the other column" is the stronger move and a person holding both meant more, not
less. `CompletingTextView+Pasteboard.swift` is not touched: its Cmd test still decides that the
click is a link click, and everything after the delegate call is the Coordinator's.

`NoteTextView` keeps `onFollowLink: (String) -> Void` unchanged (twenty-five test call sites and
the view-block `onOpenNote` hand-off depend on it). The new behaviour arrives as one grouped input,
`links: LinkInputs` in `NoteTextView+Inputs.swift`, empty by default, like `vault` and `outline`:
`follow` (target, how, anchor → an outcome, D5), `preview` (D7), `onCaretLinkChanged` (D3) and
`offerCreation` (D6). With `links.follow` nil the Coordinator falls back to `onFollowLink(title)`
for `.replace` and ignores the variants, so a text view with no vault behind it behaves as before.

**D3. The keyboard follows the link at the caret.**

Three commands are appended to `ShortcutCommand` (raw values are persisted keys, so appended, never
inserted), section `.view`, in the Vista menu:

| Command | Title | Default |
|---|---|---|
| `followLink` | Segui il link | Cmd+Opt+Return |
| `followLinkInNewTab` | Apri il link in una nuova tab | none |
| `followLinkInOtherColumn` | Apri il link nell'altra colonna | none |

"None" is `KeyBinding("")`, the value `ShortcutStore` already uses for a cleared override, so the
person can bind either variant in Impostazioni ▸ Scorciatoie. Cmd+Opt+Return is free in the
catalogue (`taskToggle` is Cmd+Return, `taskAddSubtask` Cmd+Shift+Return); it is measured against
`com.apple.symbolichotkeys` before it ships, the way every default since ADR-0021 was.

The editor reports the followable link at the caret on every selection change, the shape
`onOutlineEntryChanged` → `VaultController.recordOutlineEntry(_:inColumn:)` already has:
`links.onCaretLinkChanged` → `VaultController.recordLinkAtCaret(_:inColumn:)` writes
`NoteTab.linkAtCaret: URL?`, transient, never persisted. A report rather than a request into the
editor, because the Vista item must know whether it can run before the key is pressed
(`canRun(.followLink)` is "the Note pane is in front and the focused tab has a link at the caret").

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

`LinkDestination.resolve(_:notePaths:boards:)` takes the index's answer and the board list as
inputs. `LinkChoice.entries(for:)` turns an `.ambiguous` into one row per path, labelled by its
folder through `LinkChoice.folderLabel(of:)` (the vault-relative folder, «radice del vault» for a
note at the root), and a creatable `.missing` into one «Crea «X»» row. The catalogue is rendered on
two surfaces and on two only:

- **At a click**, an `NSMenu` at the click point, built by the Coordinator from the entries and
  shown through a presenter seam (`LinkChoiceMenuPresenting`; production calls
  `NSMenu.popUp(positioning:at:in:)`, which is modal tracking and therefore never runs in a test).
  The editor (`EditorColumnView`), Oggi and Diario host `NoteTextView` and all get it.
- **Otherwise**, a sheet: `LinkChoiceSheet`, hosted at `RootView` through
  `Navigation.linkChoice: LinkChoiceRequest?` (ADR-0039's precedent for a sheet every surface can
  reach). The keyboard follow, the Workspace card, the task chip and the board tray's title
  fallback get it, since none of them has a point to anchor a menu to.

The silent `.first` goes from every follow site the grep found: `CommandActions+LinkNavigation`,
`TodayView` (which also stops opening a note behind the Oggi pane: following now switches to the
Note pane, as the editor's follow always did), `DiaryView` (its `controller.flush()` stays first),
`BoardTray.resolvedPath(for:)`'s title fallback, and `addStructuralLink` (ADR-0084 §D4 moves it to
a path). Two more surfaces in the SPEC's list:

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
pane (`CommandActions` switches the pane from Oggi or Diario). The composer is the one "name a note"
surface (SPEC UI flows); N4 extends it and the offer follows whatever it becomes. The offer never
creates a file by itself.

**The `[[` popup gets the same row.** When the wikilink completion finds nothing and the typed
text is creatable, the popup shows one row, `CompletionItem.createNote(title:)`, «Crea «X»».
Choosing it completes the link through the insertion rule SPEC R-03 (N1) sets for a candidate, then
calls `links.offerCreation(title)`. A host with no `offerCreation` (a Workspace card) shows no row.

A draft already parked in the composer with a title is not overwritten by an offer: the offer opens
the composer on the parked draft and records «Una nota è già in preparazione: completala o annullala,
poi riprova». This is the recommended default; whether an offer should replace a parked draft is
the person's call and is raised at the plan gate.

**D7. The preview is a never-key panel, opened by Cmd and the pointer, owned by one controller.**

*What it shows* (`LinkPreviewContent.make(...)`, pure):

- a note target: its title and the first twelve lines of its body, or of the heading section when
  the link names one (`[[Nota#Sezione]]`), through `Transclusion.excerpt(of:section:)`, the
  function that already decides what a transclusion shows; a section no heading answers to says so;
- a board target: the board's name;
- several matches: «N note si chiamano «X»» and their folder labels;
- no match: «Nessuna nota si chiama «X»», plus «Cmd+clic per crearla» when creatable;
- an external URL or a file embed: nothing, no panel (SPEC edge case).

The section is not in the link's URL (`MarkdownAttributedText.noteURL(for:)` carries the title
only), so the controller reads it off `WikilinkParser` at the hovered index, the parse `LinkAtCaret`
already uses.

*When it shows* (`LinkPreviewTrigger`, a pure state machine in `Sources/Core/Links/`, time passed
in): Command is held, no non-modifier key has been pressed since, the pointer rests on one
`.editorLink` run, and 250 ms have passed since the last of those became true. Shift and Option do
not matter, so the panel stays while the person reaches for a click variant. The dwell keeps a
Cmd+S or Cmd+F chord typed with the pointer over a link from flashing a panel. It closes on Command
released, the pointer leaving the run, Escape (consumed only while the panel is up), any key, a
scroll, the window resigning key, the text changing, and the note changing.

*Where it lives* (ADR-0074 §D2/§D3): `LinkPreviewController`, a `@MainActor final class` in
`NoteTextView+LinkPreview.swift`, reading the parent's inputs through a provider at use time. It
owns a small tracker `NSResponder` that is the owner of one tracking area over the text view's
visible rect (`.mouseMoved`, `.mouseEnteredAndExited`, `.activeInKeyWindow`, `.inVisibleRect`), so
`CompletingTextView`'s own `mouseEntered`/`mouseExited` overrides (N1's file) are never involved.
While the pointer is inside, and only then, it holds exactly one local event monitor for
`.flagsChanged`, `.keyDown` and `.scrollWheel`; leaving the view, hiding, and the Coordinator's
teardown remove it, and the removal is asserted (PG-258: an orphan panel and a monitor that outlived
its view were that ticket). The point-to-link resolution is `CompletingTextView.linkCharacterIndex
(at:)`, called, not copied: the protected file stays the one place a point becomes a link. A
`mouseMoved` with Command already down starts the dwell too, so the panel does not depend on a
`flagsChanged` arriving after the pointer.

*What it is drawn in*: a `NeverKeyPanel` (ADR-0074 §D9's type, already behind the completion popup
and the format bar), placed by `PanelPlacement` below the link's line or above it when there is no
room, with `ignoresMouseEvents = true`, so a Cmd+click that lands where the panel overlaps still
reaches the link. Showing and hiding go through a presenter seam, `LinkPreviewPresenting`: a hosted
test never orders a window front (the harness refuses it), so a spy stands in, and the real panel is
proved by one GUI test (D8). The SPEC's Stack line names `NSPopover`; this is a deliberate deviation,
argued under Alternatives.

**D8. Two of N3's three GUI tests are this record's, and each is the only way to prove its claim.**

Both live in `UITests/WikilinkNavigationUITests.swift`, which already subclasses
`PergamenumUITestCase` (CLAUDE.md: no file builds its own `XCUIApplication`).

1. **Follow from the keyboard, then return.** Caret moved into `[[Destinazione]]` with arrow keys,
   Cmd+Opt+Return, the destination's editor in front, Cmd+[, the source back. In-process cannot
   prove it: the key equivalent reaches a menu item only through the real menu bar, the history is
   derived by an observer that lives in `RootView`'s body (ADR-0015 §D2), and a hosted view has no
   menu bar and no `RootView`. The pure rule, the caret report, `canRun` and `open(link:how:)` are
   all covered in-process; what this test adds is the chain end to end.
2. **The preview appears and goes.** The pointer over a link inside
   `XCUIElement.perform(withKeyModifiers: .command)`, the panel's `link-preview` identifier exists;
   after the block (Command released), it does not. In-process cannot prove it: the harness refuses
   `sendEvent` and `orderFront`, so neither a modifier-plus-pointer event nor a real panel exists
   there. The trigger, the content, the controller's monitor lifecycle and the first-responder
   invariant are covered in-process with the presenter spy.

The third GUI test, «Collega» a mention, is ADR-0084 §D7's.

## Alternatives considered

**`NSPopover` for the preview (the SPEC Stack line's word).** Rejected. An `NSPopover`'s window can
become key, and whether it does depends on its content and behaviour flags rather than on its type;
the SPEC's edge case is "never takes first responder", and a guarantee that rests on configuration
is the shape ADR-0074 §D9 replaced with `NeverKeyPanel` ("enforced rather than assumed"). A popover
also closes on its own terms under `.transient`/`.semitransient`, which fights a trigger whose close
rules are the SPEC's, and anchoring one to a character rect inside a TextKit 2 view inside a
SwiftUI host is a third positioning path beside `PanelPlacement`. What it would have given, the
arrow and the chrome, is drawn by the content view with tokens, and the mockup decides how it looks.

**Map the click variants in `CompletingTextView.mouseDown`.** Rejected: the file is protected as a
whole, and the delegate method the Coordinator already owns receives every link click with the
flags still readable.

**Change `onFollowLink` to `(String, LinkOpening) -> Void`.** Rejected: it is constructed at
twenty-five test sites and handed to view blocks as `onOpenNote`; a grouped `links` input, empty by
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

**Plain hover after a delay.** Settled by the SPEC (rejected there), registered here only so the
next reader does not mistake its absence for an oversight.

## Consequences

Positive:

- A link can be read without leaving the note, opened three ways, and followed from the keyboard.
- No follow site guesses: ambiguity is a visible choice on every surface the grep found.
- A dangling link and an empty `[[` popup become the start of a note instead of a dead end.
- The pointer and the keyboard read one URL, written by the styler, through one `clickTarget`.

Negative:

- `ShortcutTests.noTwoCommandsShipOnTheSameKeys` and `everyShippedDefaultIsUsable` assumed every
  command ships bound. Both are amended, not disabled: an empty default is "ships unbound", excluded
  from the collision walk and from the usability check, and an explicit allow-list
  (`ShortcutCommand.shipsUnbound`, exactly the two variants) is pinned so a third unbound command is
  a red test, not a quiet gap.
- Oggi's follow now switches to the Note pane. Before, it opened a tab behind the Oggi pane where
  nothing was visible; the change is deliberate.
- After an other-column follow, Cmd+[ shows the source in the second column too (D4).
- The preview adds one controller, one tracking area and one monitor per editor while the pointer
  is inside; the lifecycle is the risk PG-258 names, and it is pinned in-process.
- Two GUI tests join the bounded suite; each is justified in D8.

Neutral:

- No on-disk format, frontmatter key, index field or `IndexCache.schemaVersion` changes. No
  protected interface is touched.
- The connectors are untouched by this record (navigation is the app's).
- `[[Nota#Sezione]]` still opens the note at its top on a click: following a section is not in the
  SPEC and is named here as a gap, not fixed.

## References

- SPEC (root, Approved 2026-10-04): N3 R-20..R-23; Decisions "Hover preview fires on Cmd + hover
  only", "Link variants"; Edge cases on several matches and on the preview; Test seams 4 and 6.
- `docs/20261003_Pergamenum_NoteWorkflowRoadmap.md` §2 N3; `docs/20261002_Pergamenum_NoteWorkflowReport.md`
  L-1..L-4, I-7.
- ADR-0012 §D2/§D4, ADR-0015 §D1/§D2, ADR-0023 §D1, ADR-0039, ADR-0074 §D2/§D3/§D9, PG-219, PG-258,
  PG-356.
- Plans: `docs/plans/note-workflow-n3-mockup.md`, `docs/plans/note-workflow-n3.md`.
