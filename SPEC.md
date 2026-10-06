Status: Approved (2026-10-06)

# SPEC — The pointer reaches the screen (PG-219, #445)

## Destination

Hovering a clickable span in any editable text of the app shows the pointing hand, hovering any other
editable text shows the I-beam, and both are seen on screen by Stefano on a Debug build. The chain ends
with an ADR that records the route taken and what was measured, PG-219 closed, and N3's hover preview
(PG-386, task 2) unblocked. If no route shows the cursor, the chain ends earlier, at a stop gate with a
report (R-10).

## Objectives

An `NSCursor` set from AppKit code inside this app's SwiftUI view tree never reaches the screen: the pointing
hand over a link is absent, and the I-beam over editable text apparently always has been. The ledger entry
measured that `NSCursor.current` reads the pushed cursor for every tick of a real hover while the screen draws
the arrow, so the AppKit-side mechanisms (cursor rects, `push`/`pop`, `cursorUpdate` with `set`) are
exhausted. Every custom cursor that does work in the app goes through SwiftUI. This SPEC gets the pointer
onto the screen by the cheapest route that a measurement shows to work, and only escalates to a larger
restructure if that measurement fails. It also removes the dead cursor code, or its false claims, so the
codebase stops asserting a behaviour it does not have.

## Scope and non-goals

In:
- The pointing hand over every span the editor already treats as a click target, and the I-beam over the
  rest of the editable text.
- Every host of the two text-view classes: the Note editor, the Oggi pane's daily note, the Diario, and the
  Workspace card text while it is being edited.
- A probe that decides the route before any structural code is written.
- The ADR, the ledger and the documentation that this changes.

Out (one line each, detail below): a hand that depends on Cmd; the hover preview; the cursors that already
work; the cause of the AppKit/Window Server divergence as a goal of its own; read-only text outside the two
classes.

## Decisions

- **Probe first, restructure only on failure.** The first build task wraps the Note editor's text view in an
  unconditional `.pointerStyle(.link)` on a Debug build, then (if that shows nothing) puts the same modifier
  on a non-hit-testing clear overlay. If the hand shows, the fix is the cheap route: AppKit reports which
  pointer applies at the point (a single new callback input per host), SwiftUI draws it with `.pointerStyle`.
  Only if both probes fail does the `.onContinuousHover` restructure the ledger describes come into play,
  and then through gate G3 of this chain, not by improvisation. Rejected: committing to the `.onContinuousHover`
  restructure now (about forty forwarded properties and five call sites, paid before the cheap route is known
  to fail); and a root-cause hunt in AppKit's window-level cursor ownership (no precedent in the codebase,
  open-ended, nothing to bound it).
- **Every surface that hosts the two classes.** Note editor, Oggi, Diario, Workspace card in edit. The two
  classes are touched whichever route wins, and the ledger says the symptom is app-wide. Rejected: Note
  editor only, which would leave three surfaces with the wrong cursor and a new ticket for them.
- **The hand shows over a click target whether or not Cmd is held.** It matches the already-approved wording
  of the roadmap's R-09 («pointing hand over a link») and needs no modifier tracking. The one signal for
  "this span is clickable" is the editor's own link attribute, which wikilinks, CommonMark labels, tags and
  dates already carry; hover and click keep agreeing on what is a target. Rejected: hand only while Cmd is
  held (it promises exactly what Cmd+click does, but needs a refresh on a bare modifier change with the mouse
  still, and reopens an approved criterion).
- **Failure stops the chain at a human gate.** If neither probe shows the cursor, the build stops, writes up
  what was measured and where, PG-219 stays open and N3's hover preview stays blocked; Stefano decides whether
  a deeper diagnosis gets its own ADR. Rejected: continuing into an open-ended AppKit diagnosis for a time cap
  inside the same chain.
- **The screen is checked by hand.** A cursor on screen cannot be asserted by a test (UI tests cannot read it,
  and Accessibility is not granted on the dev machine), so the on-screen criteria are hand checks, recorded in
  the PR body, while the decision and the wiring are tested in process. Rejected: a GUI test whose assertion
  would not be about the cursor.

## Constraints

- **The pasteboard/mouse-down file of the note editor is a protected interface, whole file** — origin:
  `.claude/protected-interfaces`, restated by ADR-0083. Nothing in this chain edits it; it already exposes
  the point-to-link resolution the pointer reuses.
- **No compatibility fallback for older macOS** — origin: project stack (macOS 27). `.pointerStyle` is used
  directly, with no availability gate.
- **Every colour and font through a token** — origin: design system rule. This work introduces neither.
- **`NoteTextView`'s forwarded inputs do not grow beyond one new callback** on the cheap route — origin: ADR-0074
  §D2/§D3 (controllers, not new stored inputs) and the ledger's own cost estimate; the larger restructure is
  allowed only through gate G3.
- **The tracking-area geometry that hover and clicks share is reused, not duplicated** — origin: PG-220
  (one point-to-link resolution per view).
- **The link-hover geometry is not a second source of truth for "what is clickable"** — origin: the two
  classes' own comments; the attribute is the signal.
- **N3 must not depend on this work's details** — origin: ADR-0083 (the pointer is N1's territory, N3 only needs
  it to exist).

## Stack

Swift 6, SwiftUI `.pointerStyle` (macOS 15+, used directly on 27), AppKit `NSTextView` subclasses
(`CompletingTextView`, `FormattingTextView`) behind `NSViewRepresentable` hosts. Swift Testing for unit and
in-process tests. No new dependency.

## Data model

None on disk. In memory, one small value per host describing what the pointer is over:

```swift
enum EditorPointer: Equatable { case text, link }
```

`.text` maps to the horizontal-text pointer style, `.link` to the link style. A pointer outside the text view's
text (nothing under it) is not this type's business: the host applies no style and the system default stands.

## API / interfaces

- Each of the two text-view classes answers **what pointer applies at a point in its own coordinate space** (a
  pure answer from the text storage and layout) and **reports it only when it changes**, through one callback.
- Each host (Note editor, Oggi, Diario, Workspace card text) holds the last reported value and applies the
  matching `.pointerStyle` to its text view.
- No change to the vault, the index, the connectors or any on-disk format.

## UI flows

Hover over a link, tag or date: pointing hand. Move onto plain text: I-beam. Move out of the text view: system
default. No visual change otherwise, no settings, no menu entries.

## Edge cases

- **A link restyled or moved under a still pointer** (an edit above it, a reveal-on-caret, a reflow): the
  answer is recomputed when the geometry changes, not only on mouse movement, so a hand never stays over text
  that is no longer a link and an I-beam never stays over one that now is.
- **The pointer leaves the text view or the window, the view is removed, the card is culled or the pane is
  switched while a hand is up**: the reported value resets, nothing stays pushed.
- **A drag in progress** (text selection drag, dropping a note title or a file): the pointer logic does not fight
  the system's drag cursor.
- **Hosted attachments inside the text** (a table grid, a view block, an image or PDF embed): their own views own
  the pointer there; this work does not force the I-beam over them.
- **Board zoom and pan** (Workspace cards): the answer uses view-space geometry, so it holds at any zoom.
- **The window is not key**: no pointer change is reported, as today's tracking areas already behave.
- **A cursor already pushed by a divider's `onHover`**: those keep working and are not changed; the hand check
  covers them.

## Test seams

1. **Pure pointer decision**, at the unit level: the point-to-pointer answer over a text storage with link,
   tag, date and plain runs, including wrapped links, the boundary of a link and a point outside any text.
   Reuses the existing in-process text view construction the editor tests already use.
2. **Wiring**, in process: the callback fires on a change and not twice for the same answer, resets on
   leaving, and each host applies the style it was told. Reuses the hosted-view test shape already in the merge
   gate.
3. **Screen**, by hand, on a Debug build: the probe, the hand, the I-beam on each surface, and the unchanged
   dividers. Recorded in the PR body (route taken and macOS build). No GUI test.

## Success criteria

- [ ] R-01 — Before any structural change, the probe has been run on a Debug build, on the Note editor's text
  view: the unconditional `.pointerStyle(.link)` first, then the same on a non-hit-testing clear overlay if
  the first shows nothing. The result (which, if either, showed the hand, and the macOS build) is written in
  the PR body and in the ADR. (no-test: a cursor on screen cannot be asserted by a test; Stefano's hand check
  is the evidence)
- [ ] R-02 — On the Note editor, hovering a wikilink, a CommonMark label, a `#tag` or a `>date`/`!date` span
  shows the pointing hand on screen. (no-test: hand check, recorded in the PR body)
- [ ] R-03 — On the Note editor, hovering editable text that is not one of those spans shows the I-beam on
  screen. (no-test: hand check, recorded in the PR body)
- [ ] R-04 — R-02 and R-03 hold on the Oggi pane's daily note, the Diario and a Workspace card while it is
  being edited, at board zoom other than 100% for the card. (no-test: hand check, recorded in the PR body)
- [ ] R-05 — The pointer decision is pinned by unit tests: a point inside a link gives the link pointer, inside
  a tag and a date the same, inside plain text gives the text pointer, outside the text gives nothing, and a
  link wrapped over two lines answers on both lines.
- [ ] R-06 — The callback reports an answer only when it differs from the last one, and reports the reset when
  the pointer leaves the view; a host applies the pointer style matching what it was last told. Pinned by
  in-process tests.
- [ ] R-07 — A link whose position changes under a still pointer (an edit above it, a restyle) updates the
  reported pointer without a mouse movement. Pinned by an in-process test that changes the text and reads the
  answer at the same point.
- [ ] R-08 — The existing custom cursors (the editor columns' divider, the Workspace pane divider, the board
  handles and the crop editor) behave as before: resize cursor on hover, arrow after, no cursor left pushed.
  (no-test: hand check, recorded in the PR body)
- [ ] R-09 — Code and comments that claim a cursor behaviour the app does not have are gone or made true: the
  `cursorUpdate` overrides no longer call `NSCursor.pointingHand.set()` and the two cursor-rects files' headers
  describe what is now the case, citing PG-219 and the ADR. The tracking-area geometry stays as the shared
  link-hover geometry. The protected note-editor mouse file is byte-identical.
- [ ] R-10 — If both probes of R-01 fail, the chain stops at a human gate: no restructure is written, the
  measurements are recorded, PG-219 stays open, N3's hover preview stays blocked, and the report names what
  Stefano must decide next. (no-test: a process obligation)
- [ ] R-11 — An ADR records the route, the probe result and the departures from this SPEC, with the rejected
  alternatives above; the ledger closes PG-219 (#445) on the cheap route, and PG-384's phase and PG-386's
  prerequisite note are updated. (no-test: documentation obligation)
- [ ] R-12 — The unit suite and the in-process tests pass; no GUI test is added.

## Not yet specified

- **The fate of the `.cursor: pointingHand` attribute set on link runs** in the editor's and the cards'
  attributed text. Whether it is dead (nothing reads it once the pointer comes from SwiftUI) or still
  consulted by `NSTextView` is a fact the plan must read from the code before deciding to keep or remove it;
  R-09 only requires that it does not claim a behaviour the app does not have.
- **The exact shape of the single callback and where each host stores the value** are design details for
  `/workplan`, bounded by the Constraints above.

## Out of scope

- **A hand that depends on Cmd** — rejected by the interview (see Decisions); reopen only with a stated reason.
- **The N3 hover preview (PG-386)** — it is unblocked by this work, not part of it.
- **The divider, board handle and crop cursors** — they work and go through SwiftUI already; only R-08's
  regression check touches them.
- **The AppKit/Window Server divergence as a goal in itself** — this work routes around it; explaining it is
  allowed only if the probe makes it cheap, and a deeper diagnosis needs its own decision (R-10).
- **PG-089** — closed won't-fix, a different mechanism (the drag session's operation mask).
- **Read-only text outside the two text-view classes** — a surface that does not host `CompletingTextView` or
  `FormattingTextView` is not changed here; an audit of such surfaces is a separate ticket if wanted.
