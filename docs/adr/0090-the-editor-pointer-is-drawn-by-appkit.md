# ADR-0090: The editor's pointer is decided and drawn by AppKit, from two overrides

- Status: **proposed**. It lands with the PG-219 PR built from `docs/plans/pg-219-pointer-feedback.md`.
  Flip it to `accepted` as the first docs change after that PR merges, naming the PR, its merge
  hash as `git log --first-parent main` shows it, and the date (`docs/adr/README.md` rule 2).
- Date: 2026-10-06. Written against `main` at `9103768f` (PR #910). Amended the same day (route C,
  see `## Amendment`): the file name keeps its first title, because `CLAUDE.md` and the plan cite it.
- Number: `0090` was checked free on every local and remote-tracking ref on 2026-10-06. Check it
  again immediately before the merge (`docs/adr/README.md` rule 1).
- Source: the repo-root `SPEC.md` of PG-219 (#445), Approved 2026-10-06, R-01 to R-12.
- **Extends ADR-0074 §D2.** The decision lives in each text view's own file, the drawing in one
  shared value type, `EditorPointer`.
- **Extends ADR-0027 §D1.** The Workspace card still shares no AppKit class with the note editor.
  What the two text views share is a value type, which neither of them owns.
- **Amends neither.** It changes the #188 R-06 test pins on the `.cursor` attribute (§D7).
- **No other changes.** No on-disk format, schema, setting or protected interface changes, and
  `CompletingTextView+Pasteboard.swift` is byte-identical.
- `## Probe result`, `## Amendment` and `## Implementation notes` were filled by /build.

## Amendment: route C replaces route A (2026-10-06)

The ADR was first written for route A: AppKit decides, SwiftUI `.pointerStyle` draws. A real mouse
disproved it, and the decision below is route C: **AppKit decides and AppKit draws**, from
`cursorUpdate(with:)` and `mouseMoved(with:)`. What changed, and why:

- **Probe A was read too generously.** Its answer came from a drag-select and could not separate a
  link from plain text, so it never proved plain hover (see `## Probe result`).
- **Measured with a real mouse.** `.pointerStyle` over the `NSTextView` showed the hand for an
  instant at most, then the I-beam, although the modifier's state and `body` evaluated correctly.
- **The cause.** `NSTextView`'s own `mouseMoved(with:)` puts its I-beam back after anything set
  earlier. A cursor set only from `cursorUpdate(with:)` shows while the mouse is still (after a
  click) and is gone at the first move. Setting the cursor again after `super.mouseMoved(with:)`
  holds, with the mouse moving along the link. Confirmed by Stefano on 2026-10-06 («ora funziona»).
- **What was wrong in the premise.** «An `NSCursor` set from AppKit never reaches the screen»
  was too strong. The #191 mechanisms (`resetCursorRects`, enter/exit push and pop, `set()` in
  `cursorUpdate` alone) lost to `NSTextView`'s later I-beam, not to a Window Server divide.
- **Sections amended:** D1, D3, D4, D5, D8 and D9 are rewritten below; D2, D6 and D7 stand
  (D2's tracking-area paragraph is dropped). The tracker, the host state objects, the
  `onPointerChange:` input, the modifier and the per-link tracking areas of the first design are
  deleted, not kept.

## Context

**The defect.** In this app, an `NSCursor` set from AppKit code inside the SwiftUI view tree did not
reach the screen (read as «never» when this ADR was first written; `## Amendment` says what was
really happening). The pointing hand over a link has never shown, and the I-beam over editable text
apparently never has either.

**What was measured.** During the #191 chain, three mechanisms were implemented and logged
(read there as «never reaches the screen»; the measured cause is in `## Amendment`):

- `resetCursorRects()`/`addCursorRect`;
- `mouseEntered`/`mouseExited` with `push()`/`pop()`;
- `cursorUpdate(with:)` with `set()`.

Each one fired as designed, and none held on the screen. `NSCursor.current` read the set cursor on
every tick of a real hover while the screen drew the arrow or the I-beam. The first reading blamed a
divide between AppKit's bookkeeping and the Window Server; PG-219's real-mouse measurement found
the cause in `NSTextView`'s own `mouseMoved(with:)` instead (`## Amendment`).

**What worked elsewhere.** (Route A relied on the first of these; see `## Amendment`.)

- `TimelineBlockBox.swift:105` uses `.pointerStyle(.frameResize(position: .bottom))`.
- The editor columns' divider, the Workspace pane divider and the board handles push and pop an
  `NSCursor` from SwiftUI's own `.onHover`: `EditorColumns.swift:78`, `WorkspacePaneDivider.swift:50`
  and `BoardHandles.swift:94`.

**The SwiftUI API.** `pointerStyle(_ style: PointerStyle?) -> some View` is available from macOS 15,
and `PointerStyle` has `.link` and `.horizontalText`. `PointerStyle` conforms only to `Sendable` and
`SendableMetatype`, not to `Equatable`. This was checked in the developer.apple.com JSON
documentation on 2026-10-06.

**What is affected.** Two `NSTextView` subclasses and four hosts:

- `CompletingTextView`, behind `NoteTextView`, in the Note editor, Oggi and the Diario;
- `FormattingTextView`, behind `CardTextView`, in a Workspace text card.

The ledger estimates that restructuring `NoteTextView` around `.onContinuousHover` means threading
about forty forwarded properties through five call sites.

**What is clickable.** A span is clickable when it carries the `.editorLink` attribute. Each view reads
it through one point-to-link resolution, `linkCharacterIndex(at:)` (PG-220). The note editor's is in
the protected `CompletingTextView+Pasteboard.swift`.

**The cost of an update.** Every `NoteTextView.updateNSView` runs `runPasses`, which restyles the
whole note.

**The `.cursor` attribute.** `MarkdownAttributedText` sets it on link, tag and date runs, and
`CardTextAttributes` sets it on card link runs. Nothing in `Sources` reads it. Apple's documentation
names no reader: «The value of this attribute is an NSCursor object. The default value is the cursor
returned by the iBeam method» (checked 2026-10-06).


## Decision

**D1. AppKit decides which pointer applies and AppKit draws it, through one door.**

- `EditorPointer` (`enum EditorPointer: Equatable, Sendable { case text, link }`) is the one place a
  text view's cursor becomes an `NSCursor`: `cursor` maps `.text` to `.iBeam` and `.link` to
  `.pointingHand`, and `apply()` calls `set()`.
- `CompletingTextView` and `FormattingTextView` decide through `pointer(at:)` and call
  `applyPointer(at:)`. Neither names an `NSCursor` (`NoAppKitCursorInTheTextViews` pins it).
- `nil` means no pointer applies here: the view calls `super` and the system keeps its own.

**D2. The decision is the attribute, read through the one resolution clicks use.**

`CompletingTextView.pointer(at:)` answers, in this order:

1. `nil` outside its bounds;
2. `nil` over an on-screen hosted attachment, which is a table grid or a view block whose
   `superview != nil`;
3. `nil` over a paragraph that draws an embed (reachable only while markup is hidden — see
   implementation note 3);
4. `.link` where `linkCharacterIndex(at:)` finds an `.editorLink`;
5. `.text` everywhere else in the view, including empty space past a line's end.

`FormattingTextView.pointer(at:)` answers:

1. `nil` when the card is not editable, or outside its bounds;
2. `.link` through its own `linkCharacterIndex(at:)`, widened from `private`;
3. `.text` otherwise.


Hover and click agree at every point, because both read the same resolution, and the hand never
shows where a click does nothing.

**D3. Two overrides, one rule: set it after the system has.**

- `cursorUpdate(with:)` arrives on every mouse-moved tick through `NSTextView`'s own whole-bounds
  tracking area. Where a pointer applies it is the whole answer, and `super` is not called.
- `mouseMoved(with:)` calls `super` first, which puts `NSTextView`'s I-beam back, and then applies
  the pointer again. Without this second call the hand is gone at the first move (the measured
  defect).
- Both count only while the window is key (D4). No tracker, no stored point, no deferred hop.

**D4. A window that is not key applies nothing.** Both overrides fall through to `super`, so an
inactive window keeps the system's pointer.

**D5. Nothing in the hosts.** `NoteTextView` and `CardTextView` gain no input, and no host keeps
pointer state. The first design's `onPointerChange:`, `EditorPointerState` and
`.editorPointer(_:)` are deleted from the four hosts.

**D6. The hand does not depend on Cmd.** It shows over every `.editorLink` run, as the SPEC decided.
That needs no modifier tracking, and the attribute keeps meaning "this span is clickable".

**D7. The `.cursor` attribute is removed.**

- **Where:** `MarkdownAttributedText.clickable(_:url:)`, `MarkdownAttributedText.clickAttributes(for:source:)`
  and `CardTextAttributes`.
- **Why it is dead:**
  - Nothing in the app reads it.
  - Its only possible reader is AppKit's cursor pipeline inside `NSTextView`, which the two
    overrides now bypass by setting the cursor themselves; the attribute could only compete.
  - Kept, it would assert a behaviour the app does not have, which SPEC R-09 forbids.
- **The tests that change.** The #188 R-06 pins asserted the attribute on card link and embed runs
  and on a CommonMark label. They now assert its absence. Their `.editorLink` assertions are
  unchanged.

**D8. A text view's pointer is set after `NSTextView`'s own.** A future custom pointer over an
`NSTextView` subclass sets its cursor from `cursorUpdate(with:)` and again after
`super.mouseMoved(with:)`, through `EditorPointer.apply()`. Setting it from a SwiftUI `.pointerStyle`
over the view, or from `cursorUpdate` alone, was measured not to hold. `CLAUDE.md` carries this as
a working agreement.

**D9. What is tested where.**

- **Unit:** the decision (`pointer(at:)`), the mapping (`EditorPointer.cursor`) and that
  `applyPointer(at:)` leaves `NSCursor.current` reading the applied cursor.
- **By hand (R-02 to R-04, R-08):** the visible pointer over a moving real mouse, because a
  synthetic event does not reproduce `NSTextView`'s own reset between two ticks and a UI test
  cannot read the cursor; and the dividers. No GUI test is added.

This departs from the letter of SPEC R-06 («pinned by in-process tests»): the in-process pin stops at
`NSCursor.current` after a direct call, not at a real hover sequence.

**Departures from SPEC.md (R-11).** SPEC.md still describes route A and is not rewritten.
- R-06: no callback exists, so no change-only report. The unit pin stops at `NSCursor.current`
  after a direct call to `applyPointer(at:)` (D9).
- R-07: a link that moves under a still pointer is not re-asked until the next mouse move. Named
  under Negative consequences.
- R-09: the per-link tracking areas and their padding are deleted, not kept as re-ask triggers.
- Edge cases «reset on leaving the view or window» and «drag in progress»: nothing is stored, so
  nothing needs a reset; a window that is not key applies nothing (D4). Hover during a drag-select is
  checked by hand.

## Probe result

- **Date:** 2026-10-06.
- **macOS:** ProductVersion 27.0.1, BuildVersion 26A434. **Xcode:** 27.0 (27A266a).
- **Pasteboard baseline:** `shasum -a 256 Sources/Features/Editor/CompletingTextView+Pasteboard.swift` =
  `d2cabf0cbcfae3fcd1c9c4658b80e6506063f0bd5494b70a322e5703868203e1`.
- **Probe A** (`.pointerStyle(.link)` on the Note editor's `NoteTextView(...)` expression). Stefano's
  answer: «manina, stabile anche nell'evidenziare», read during a drag-select with the format bar
  up. **Limit, found later:** that reading did not separate the plain first line from the link row
  and did not test plain hover, so it did not prove route A. Superseded.
- **Route A, built:** with a real mouse the hand showed for an instant and reverted to the I-beam
  over the link, on the Note editor.
- **Experiments after the research** (Apple developer forums, SwiftUI cursor-reset reports):
  - X, `set()` in `cursorUpdate` alone, `super` not called: the hand shows with the mouse still
    after a click, and is gone at the first move.
  - Y, X plus `set()` again after `super.mouseMoved(with:)`: the hand stays on the link while the
    mouse moves. Stefano: «ora funziona».
- **Route: C.** The experiment code and its temporary logging were removed.

## Alternatives considered

- **Route A: `.pointerStyle` from a host-owned modifier, fed by a tracker.** Built first, then
  dropped: it never won against `NSTextView`'s I-beam on plain hover (`## Amendment`). It also
  carried a tracker, four host state objects and an input on each representable, all gone.
- **Restructure `NoteTextView` and `CardTextView` around `.onContinuousHover` now** (the ledger's
  route). Not needed: route C needs no forwarded properties.
- **Hunt the root cause in AppKit's window-level cursor ownership.** Not needed: the cause was
  measured, `NSTextView`'s own `mouseMoved`.
- **Show the hand only while Cmd is held.** Rejected by the SPEC. It needs a refresh on a bare
  modifier change with the mouse still, and it reopens an approved criterion.
- **Decide from the padded tracking-area rectangles.** Rejected, and no longer built. It makes
  the hover geometry a second source of truth for «what is clickable», and the rectangles are padded,
  so the hand would show where a click does nothing.
- **Push/pop from `mouseEntered`/`mouseExited`.** Tried in #191 and lost to `NSTextView`'s I-beam
  in the same way.
- **Keep the `.cursor` attribute as harmless.** Rejected (D7).
- **One shared helper class holding the overrides for both text views.** Rejected by ADR-0027 §D1.
  The two classes keep twin overrides. What they share is `EditorPointer`.

## Consequences

- **Positive.**
  - The hand and the I-beam show on the Note editor, Oggi, the Diario and an edited Workspace card.
  - Hover and click agree at every point, through one resolution per view.
  - Less machinery than the first design: no tracker, no host state, no forwarded callback.
  - The cursor files and the attributed-text tables stop claiming behaviour the app does not have.
  - N3's hover preview (PG-386, ADR-0083) is unblocked without depending on any of this.
- **Negative.**
  - The pointer updates at the next mouse move, not when text moves under a still mouse.
  - The ordering «set after `super.mouseMoved`» is a measurement of today's `NSTextView`, not
    documented API; a future macOS that changes where it resets the cursor changes the outcome.
  - No test pins the visible pointer, so a regression on screen is caught only by hand.
  - The note editor resolves the point twice off a link while markup is hidden (note 3).
- **Neutral.**
  - The two files keep their `+CursorRects` names: ADR-0083 cites them.
  - Hosted attachments keep whatever pointer their own views give.

## Implementation notes

Recorded by /build on 2026-10-06. The hand check of route C (Task 5, gate G5) is recorded in the
plan's `## Hand check`.

1. **Route C, in two overrides.** See `## Amendment`. `cursorUpdate(with:)` sets, and
   `mouseMoved(with:)` calls `super` then sets again.
2. **Gate G4's readings, as planned.** (a) Empty space inside the view is `.text`. (b) A table grid,
   a view block or a drawn embed gives `nil`, the system default. (c) Only `.editorLink` runs get the
   hand. (d) A card that is not editable gives `nil`. (e) `.cursor` is removed.
3. **Hosted attachments are found by their own frame, converted.** `pointer(at:)` tests
   `convert(view.bounds, from: view)` for every `tableViews` and `viewBlockHosts` value whose
   `superview != nil`. The embed check asks `drawnEmbedRange(atParagraphStart:in:)` for the paragraph
   holding the point's character index: the one `linkCharacterIndex(at:)` returned over a link,
   otherwise `characterIndexForInsertion(at:)` asked a second time, because `linkCharacterIndex(at:)`
   is the click path's resolution (PG-220) and is left byte-identical. The whole check runs only while
   `decorations.hidesMarkup` is true.
4. **The card's `linkCharacterIndex(at:)` is widened with ADR-0045's comment shape**
   («Internal, not private: … reads it»).
5. **The measuring harness.** `screencapture -C -R` captures cursors faithfully, but synthetic mouse
   moves reach the app only a handful of times, so only a real mouse is a valid test of hover
   behaviour. A synthetic probe misled the first readings.

## References

- `SPEC.md` of PG-219 (#445): Decisions, Constraints, Edge cases, Test seams, R-01 to R-12.
- `docs/plans/pg-219-pointer-feedback.md`: the implementation plan and its hand check.
- Related ADRs:
  - ADR-0074 §D2;
  - ADR-0027 §D1;
  - ADR-0045, the widening convention;
  - ADR-0083 (N3, the hover preview);
  - ADR-0088, its «Not decided here» bullet on the pointer.
- Ledger entries: PG-219, PG-220 (one point-to-link resolution), PG-384, PG-386 and PG-340.
- Source files:
  - `Sources/Features/Editor/EditorPointer.swift`;
  - `Sources/Features/Editor/CompletingTextView+CursorRects.swift`;
  - `Sources/Features/Workspace/FormattingTextView+CursorRects.swift`;
  - `Sources/Features/Editor/CompletingTextView+Pasteboard.swift` (`linkCharacterIndex(at:)`);
  - `Sources/Features/Workspace/FormattingTextView+Clicks.swift`.
- Apple Developer documentation and forums, read 2026-10-06: `NSCursor`, `NSResponder.cursorUpdate(with:)`,
  `View.pointerStyle(_:)`, `NSAttributedString.Key.cursor`.
