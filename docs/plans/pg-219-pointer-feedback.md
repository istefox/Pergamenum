**Requirement set:** `SPEC.md`

# Plan — PG-219: the pointer reaches the screen (#445)

`SPEC.md` is the PG-219 SPEC (Approved 2026-10-06) at this worktree's root. Everything below was
read on `main` at `9103768f` (PR #910) on 2026-10-06.

**ADR outcome: one new ADR, `docs/adr/0090-the-editor-pointer-is-drawn-by-appkit.md` (proposed),
written with this plan.** /build fills in three parts: its Probe result, the route in §D5 and its
Implementation notes (Tasks 1, 5 and 6).

It qualifies on all three counts:

- **Hard to reverse.** Two text-view classes and four hosts are wired to it.
- **Surprising without context.** A reader finds AppKit tracking areas and no `NSCursor`, and the
  obvious "fix" is to put the `set()` back.
- **A real trade-off.** The cheap route, the `.onContinuousHover` restructure and a root-cause hunt
  were all on the table.

The override applies too. The constraint that an AppKit cursor never reaches the screen in this
app is invisible in the code, and the route deliberately deviates from the obvious AppKit approach.
SPEC R-11 and the ledger entry ask for the record as well.

- **Number.** 0090 was checked free on every local and remote-tracking ref on 2026-10-06:
  `git log --all -- 'docs/adr/009*'` is empty and the highest on `main` is 0089. Check again
  immediately before the merge (`docs/adr/README.md` rule 1).
- **What it extends.**
  - ADR-0074 §D2/§D3: the pointer state is one `@MainActor final class`, and inputs are read through
    `coordinator.parent` at call time.
  - ADR-0027 §D1: the card still shares no AppKit class with the note editor. What they share is a
    value type and a tracker object.
- **What it changes.** It amends neither ADR. It changes the `.cursor` test pins from #188 (§D7,
  Task 2).

**Relation to `docs/plans/note-workflow-n1.md`.** This plan supersedes that plan's R-09 parts, and
Task 6 amends it. The superseded parts are:

- the pointer half of its Tasks 3 and 4;
- Task 7's "PG-219/#445 is closed by this PR";
- Task 8's pointer grep and pointer hand check;
- its gate G3.

Its G1 parts (`spacing.paragraph`, H6) and all its other tasks stay as they are.

Two of its pointer designs are deliberately not carried over:

- **`pointer(at:)` answered from the padded `linkTrackingAreas` rects.** This breaks the SPEC
  Constraint «the link-hover geometry is not a second source of truth». Those rects are padded by
  3 pt and 2 pt, so the hand would show where a click does nothing.
- **A test asserting `EditorPointer.link.style == .link`.** It does not compile: `PointerStyle`
  conforms only to `Sendable` and `SendableMetatype`, not `Equatable` (developer.apple.com JSON
  documentation, checked 2026-10-06).

## Registered from the SPEC, not reopened

- **Probe first.** Probe A puts `.pointerStyle(.link)` on the Note editor's text view. Probe B puts
  the same modifier on a clear overlay that does not take hits.
  - If either shows the hand, take the cheap route: AppKit says which pointer, SwiftUI draws it.
  - The `.onContinuousHover` restructure comes in only through gate G3.
- **Every host of the two classes:** Note editor, Oggi, Diario, Workspace card while edited.
- **The hand shows over a click target whether or not Cmd is held.** The `.editorLink` attribute is
  the one signal.
- **If both probes fail, the chain stops** at a human gate with a report (R-10).
- **The screen is checked by hand.** No GUI test.
- **Constraints:**
  - `CompletingTextView+Pasteboard.swift` stays byte-identical.
  - No availability fallback.
  - Tokens only, though no colour or font is introduced here.
  - `NoteTextView` gains at most one forwarded callback.
  - The tracking-area geometry is reused (PG-220), and the attribute is the signal.
  - N3 does not depend on this work's details (ADR-0083).

## What reading the code established

- **Every working custom cursor goes through SwiftUI.**
  - `TimelineBlockBox.swift:105` uses `.pointerStyle(.frameResize(position: .bottom))`.
  - `EditorColumns.swift:78`, `WorkspacePaneDivider.swift:50` and `BoardHandles.swift:94` push and
    pop an `NSCursor` from SwiftUI's own `.onHover`.
  - The two text views' AppKit overrides were measured never to reach the screen. Both
    `+CursorRects` headers and the ledger record this.
- **`NSTextView` installs its own whole-bounds tracking area** with `.cursorUpdate`, `.mouseMoved`
  and `.inVisibleRect`. `cursorUpdate(with:)` fires on every mouse-moved tick inside the view. This
  was measured during #191 and is recorded in both headers.
- **There is one point-to-link resolution per view (PG-220).**
  - The note editor's is `CompletingTextView.linkCharacterIndex(at:)`,
    `CompletingTextView+Pasteboard.swift:80`. It is internal, in the protected file, and is used
    here without editing it.
  - The card's twin is `private`, `FormattingTextView+Clicks.swift:45`.
- **Hosts.**
  - `NoteTextView(` is built in three places in `Sources`: `EditorColumn+Text.swift`,
    `TodayView.swift:216` and `DiaryView.swift:110`.
  - `CardTextView(` is built in one: `StickyTextCard.swift:57`.
  - 39 test files build one or the other. A defaulted parameter keeps them compiling.
- **A pointer value must not reach a host's `body`.** `NoteTextView.updateNSView` runs `runPasses`
  (`NoteTextView+Update.swift:54`), which restyles the whole note. If a pointer value re-ran a host's
  `body`, it would build a new `NoteTextView` value and pay that restyle on every link boundary the
  pointer crosses.
- **Hosted attachments.**
  - Table grids and view blocks are subviews held in `EditorDecorationDelegate.tableViews` (`:231`)
    and `.viewBlockHosts` (`:240`).
  - `superview != nil` means "on screen right now" (`CompletingTextView+Accessibility.swift:123`).
  - Drawn embeds are found by `drawnEmbedRange(atParagraphStart:in:)` (`:745`).
- **None of the touched source files is in `Project.swift`'s `sharedSources`.** They are app-only,
  so `import SwiftUI` is allowed and `perg`/`pergamenum-mcp` do not compile them.
- **Neither class overrides** `didChangeText`, `setSelectedRanges(_:affinity:stillSelecting:)` or
  `viewDidMoveToWindow`.

## The SPEC's two `Not yet specified` items, resolved

**1. The `.cursor` attribute is dead, and is removed.**

- **Where it is written:**
  - `MarkdownAttributedText.swift:234`, in `clickable(_:url:)`;
  - `MarkdownAttributedText+Clicks.swift:50`, in `clickAttributes(for:source:)` (tag and date runs);
  - `CardTextAttributes.swift:175` and `:186`.
- **Nothing in `Sources` reads it.**
- **Apple names no reader.** The documentation of `NSAttributedString.Key.cursor` says only «The
  value of this attribute is an NSCursor object. The default value is the cursor returned by the
  iBeam method» (checked 2026-10-06).
- **Any reader would be in the measured-dead pipeline.** The only possible reader is AppKit's own
  cursor-rect or `cursorUpdate` pipeline inside `NSTextView`. That pipeline was measured never to
  reach the screen. Once SwiftUI owns the pointer, it could only compete with it.
- **Keeping it breaks R-09:** it claims a behaviour the app does not have.

**Tests that change** (Task 2):

- `CardTextViewTests.swift:196` and `:202`, and `MarkdownAttributedTextTests.swift:314`, flip to
  asserting the attribute is absent.
- The test names that say "AndCursor" are renamed.

Why they change: they pinned the attribute as the carrier of the pointing hand (#188's R-06), and
the hand never came from it. The global rule says a test that changes is explained in chat first, so
the build session states this before editing them.

**2. The callback shape, and where each host keeps the value.**

- **One input per host.** `NoteTextView` and `CardTextView` each gain
  `onPointerChange: (EditorPointer?) -> Void`, defaulted to `{ _ in }`.
  - It is wired in `wire(_:to:)` and in the card's closure block as
    `{ coordinator.parent.onPointerChange($0) }`. It reads `parent` at call time (ADR-0074 §D3).
  - `nil` means two things: no style applies here (the SPEC's "nothing under it"), or the pointer
    left (the reset).
- **Each host keeps the value in `@State var pointerState = EditorPointerState()`.** That is an
  `@MainActor @Observable final class` with one property, `pointer: EditorPointer?`.
  - The host passes `onPointerChange: { pointerState.pointer = $0 }` and applies
    `.editorPointer(pointerState)`.
  - The state is read only inside `EditorPointerModifier`'s `body`. Its `content` is SwiftUI's
    placeholder, so a pointer change re-evaluates the modifier alone. It never re-runs the host's
    `body`, `NoteTextView.updateNSView` or `runPasses`. A hosted body-count test pins this (Task 2).
- **Where each host declares it:**
  - **The Note editor** declares it in `EditorColumnView.swift`. It is internal, like that view's
    other `@State` properties, because `EditorColumn+Text.swift`, an extension in another file,
    applies it.
  - **`TodayView`, `DiaryView` and `StickyTextCard`** declare it `private`.

## Tasks

The order is binding.

- **Task 1 runs first and alone.**
- **Task 2 waits for Task 1's recorded answer.** Its declarations are structural code, so it does not
  start until the route is A, A′ or B (gates G1/G2).
- **If no probe passes,** gate G3 stops the chain and Tasks 2 to 6 do not run.

### Task 1 — Coder: the probe, before anything structural (R-01, R-10)
Owner: coder
Files: Sources/Features/Editor/EditorColumn+Text.swift, docs/plans/pg-219-pointer-feedback.md, docs/adr/0090-the-editor-pointer-is-drawn-by-appkit.md
Signatures:
- Probe A — `.pointerStyle(.link)` appended to the `NoteTextView(...)` expression in `EditorColumn+Text.editing(_:)`, before `.modifier(FindKeeping(...))`, temporary
- Probe B — `.overlay { Color.clear.contentShape(Rectangle()).pointerStyle(.link).allowsHitTesting(false) }` on the same expression, in place of probe A, temporary
- Probe A′ — probe A with both `cursorUpdate(with:)` overrides temporarily returning without calling `super` or `set()`, run only if gate G1 says so
Red: no

This task is a measurement with a human in the loop. The build session cannot see the cursor;
Stefano can. Nothing structural is written before his answer is recorded.

1. **Baseline.**
   - Record `shasum -a 256 Sources/Features/Editor/CompletingTextView+Pasteboard.swift` in
     `## Probe result` below.
   - Check that `git status --short` shows only `SPEC.md`, this plan and ADR-0090.
   - This is a fresh worktree: run `tuist install`, then `tuist generate --no-open`.
2. **Probe A.** Add the probe A line, then build Debug with `xcodebuild -workspace
   Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' build`.
3. **A throwaway vault** in the session scratchpad, never Stefano's own.
   - `Probe.md`, with frontmatter `date: 2026-10-06` and `tags: [topic-probe]`, and this body:

     ```
     Testo normale su cui tenere fermo il puntatore, abbastanza lungo da occupare una riga intera.

     [[Seconda nota]] · [etichetta](https://example.com) · #client-acme · >2026-10-14 · !2026-10-15
     ```

   - `Seconda nota.md`, with any body.
   - One empty directory for `-stateBase` and one for `-mailStoreRoot`.
4. **Launch.**
   - Find this checkout's Debug app with the `WorkspacePath` snippet in `CLAUDE.md`, never by the
     newest DerivedData folder.
   - Run `open -n "$APP" --args -recentVaults '("<vault>")' -stateBase <state> -disableCalendar YES
     -disableUpdater YES -disableContenitore YES -disablePlaud YES -mailStoreRoot <mail>`.
5. **The question, asked in chat, not through AskUserQuestion.** It is a measurement reported in
   Stefano's own words. A multiple-choice prompt would have to mark a recommended answer (global
   rule), and that would lead the witness.

   > «Probe A di PG-219. Nella finestra appena aperta apri «Probe» nel pannello Note e fai un clic
   > nel testo, così la finestra è attiva. Tieni il puntatore fermo circa 3 secondi sulla prima riga
   > (testo normale), poi su [[Seconda nota]], poi muovilo lentamente lungo la seconda riga.
   > Descrivi cosa vedi: la manina sempre e stabile, una manina che lampeggia o si alterna con
   > I-beam o freccia, oppure mai la manina?»

6. **Reading the answer (gate G1).**
   - **A steady hand over all of the text:** probe A passes, and the route is A.
   - **Never the hand:** run probe B.
   - **A flicker:** stop and ask Stefano which to run next.
     - A flicker shows that SwiftUI's pointer does reach the screen and that something re-asserts
       another cursor between ticks. The likely candidate is `super.cursorUpdate`'s own I-beam.
     - The choices are probe A′, which isolates that candidate (recommended), or probe B.
     - If A′ is steady, the route is A with `cursorUpdate` not calling `super`. That is a departure,
       recorded in ADR-0090.
7. **Probe B (gate G2).**
   - Quit the probe instance with Cmd+Q, because two instances contend for the global hot key.
   - Swap probe A for probe B, rebuild and relaunch.
   - Ask the same question, plus:

     > «Un clic singolo mette ancora il cursore di testo dove clicchi, e Cmd+clic su [[Seconda nota]]
     > la apre ancora?»

   - B passes only with a steady hand and both clicks unaffected.
8. **Remove the probe** with an inverse Edit (`git checkout --` is denied on this machine).
   - `git diff --exit-code -- Sources/Features/Editor/EditorColumn+Text.swift` must exit 0.
   - After A′, run the same check on both `+CursorRects` files.
   - Quit the probe instance. `ps -Ao pid,command | grep Pergamenum.app/Contents/MacOS` must show
     none left on the probe vault.
9. **Record the result** in `## Probe result` below and in ADR-0090's `## Probe result`. The PR body
   repeats it (Task 5). Record:
   - the date;
   - `sw_vers` ProductVersion and BuildVersion;
   - `xcodebuild -version`;
   - `git rev-parse --short HEAD`;
   - each answer verbatim, in quotes;
   - the route: A, A′, B or none.
10. **If no probe shows a steady hand, stop at gate G3 (R-10).** Write no restructure. PG-219 stays
    open and N3's hover preview (PG-386) stays blocked.

    Report to Stefano: what was measured, where it is recorded, and the measurement to append to
    PG-219's ledger entry through the usual `chore(tasks)` sync. Then name the decisions that are
    his:

    1. **A separate chain with its own ADR,** with two candidate routes:
       - the ledger's `.onContinuousHover` restructure;
       - a cheaper variant that this plan's design makes possible: keep the AppKit decision and
         the callback, and draw through `.onHover`/`.onContinuousHover` plus `NSCursor`
         push/pop in the host. That is the dividers' working shape, and it needs no forwarded
         properties.
    2. **Whether R-09's truth-in-comments part ships alone now.** That part is the headers made
       true, no `set()`, and `.cursor` removed. It does not depend on the route.
    3. **ADR-0090's draft:** keep it as the record of a negative probe, with status `rejected`, or
       discard it. Discarding is a deletion, so it is his call.

    Tasks 2 to 6 do not run.

### Task 2 — Tester: the decision, the tracker, the wiring, the dead attribute (R-05, R-06, R-07, R-09)
Owner: tester
Files: Sources/Features/Editor/EditorPointer.swift, Sources/Features/Editor/CompletingTextView.swift, Sources/Features/Editor/CompletingTextView+CursorRects.swift, Sources/Features/Workspace/FormattingTextView.swift, Sources/Features/Workspace/FormattingTextView+CursorRects.swift, Sources/Features/Editor/NoteTextView.swift, Sources/Features/Workspace/CardTextView.swift, Tests/EditorPointerTests.swift, Tests/EditorPointerHostTests.swift, Tests/CardTextViewTests.swift, Tests/MarkdownAttributedTextTests.swift
Tests: EditorPointerTests.swift, EditorPointerHostTests.swift, CardTextViewTests.swift, MarkdownAttributedTextTests.swift, TagDateClickTargetTests.swift, TableGridHostedAttachmentTests.swift, EmbedDrawingTests.swift, NoteTextViewUpdatePinsTests.swift
Signatures:
- EditorPointer — `enum EditorPointer: Equatable, Sendable { case text, link }` (new file `Sources/Features/Editor/EditorPointer.swift`, `import SwiftUI`, app-only)
- EditorPointer.style — `var style: PointerStyle` (`.text` → `.horizontalText`, `.link` → `.link`)
- EditorPointerTracker — `@MainActor final class EditorPointerTracker` (same file)
- EditorPointerTracker.onChange — `var onChange: ((EditorPointer?) -> Void)?`
- EditorPointerTracker.schedule — `var schedule: (@escaping @MainActor () -> Void) -> Void` (default: one `Task { @MainActor in work() }` hop)
- EditorPointerTracker.reported — `private(set) var reported: EditorPointer?`
- EditorPointerTracker.windowLocation — `private(set) var windowLocation: NSPoint?`
- EditorPointerTracker.viewArea — `var viewArea: NSTrackingArea?`
- EditorPointerTracker.track — `func track(_ pointer: EditorPointer?, atWindowLocation location: NSPoint)`
- EditorPointerTracker.refresh — `func refresh(_ answer: @escaping @MainActor (NSPoint) -> EditorPointer?)`
- EditorPointerTracker.reset — `func reset()`
- EditorPointerTracker.detach — `func detach()`
- EditorPointerState — `@MainActor @Observable final class EditorPointerState { var pointer: EditorPointer? }` (same file)
- EditorPointerModifier — `struct EditorPointerModifier: ViewModifier { let state: EditorPointerState }` (same file)
- View.editorPointer — `func editorPointer(_ state: EditorPointerState) -> some View` (same file)
- CompletingTextView.pointerTracker — `let pointerTracker = EditorPointerTracker()` (stored, `CompletingTextView.swift`)
- CompletingTextView.pointer — `func pointer(at point: NSPoint) -> EditorPointer?` (`CompletingTextView+CursorRects.swift`)
- CompletingTextView.trackPointer — `func trackPointer(at point: NSPoint?)`
- CompletingTextView.refreshPointer — `func refreshPointer()`
- CompletingTextView.onPointerChange — `var onPointerChange: ((EditorPointer?) -> Void)? { get set }` (computed, forwards to `pointerTracker.onChange`)
- FormattingTextView.pointerTracker — `let pointerTracker = EditorPointerTracker()` (stored, `FormattingTextView.swift`)
- FormattingTextView.pointer — `func pointer(at point: NSPoint) -> EditorPointer?` (`FormattingTextView+CursorRects.swift`)
- FormattingTextView.trackPointer — `func trackPointer(at point: NSPoint?)`
- FormattingTextView.refreshPointer — `func refreshPointer()`
- FormattingTextView.onPointerChange — `var onPointerChange: ((EditorPointer?) -> Void)? { get set }` (computed, forwards to `pointerTracker.onChange`)
- NoteTextView.onPointerChange — `var onPointerChange: (EditorPointer?) -> Void = { _ in }` (after `onTakeFocus`, the last stored input)
- CardTextView.onPointerChange — `var onPointerChange: (EditorPointer?) -> Void = { _ in }` (after `onOpenDay`)
- CompletingTextView.linkCharacterIndex — `func linkCharacterIndex(at point: CGPoint) -> Int?` (relied on; protected file, unchanged)
Red: yes

**This task starts only after Task 1 recorded route A, A′ or B.**

**Declarations get neutral bodies.** The target must build, and nothing uses `fatalError`.

- `EditorPointer.style` is the full two-case switch. It is part of the type's definition, and no
  test can compare a `PointerStyle`.
- `track`, `refresh`, `reset` and `detach` do nothing.
- `pointer(at:)` returns `nil` in both classes, and `trackPointer`/`refreshPointer` do nothing.
- `onPointerChange` on both text views forwards to `pointerTracker.onChange`.
- `EditorPointerModifier.body` returns `content` unchanged.
- The two `onPointerChange` host inputs are declared and not yet wired.
- `hoveredLinkCount` stays until Task 3.

**`Tests/EditorPointerTests.swift`** (new) builds real views in an offscreen window, styled through
the coordinator, as `TagDateClickTargetTests.fixture` and `EmbedEditorFixtures.editor` already do. A
test point is the midpoint of a character range's `enumerateTextSegments` segment, offset by
`textContainerOrigin`.

- **The decision on `CompletingTextView` (R-05).** The text holds a plain line, then
  `[[Seconda nota]]`, `[etichetta](https://example.com)`, `#client-acme`, `>2026-10-14` and
  `!2026-10-15`, then a wikilink long enough to wrap at the fixture's width.
  - `.link` at the midpoint of the wikilink, the CommonMark label, the tag, `>date` and `!date`.
  - `.text` over plain text.
  - `.text` in empty space inside the view below the last line (reading G4(a)).
  - `nil` outside the view's bounds.
  - `.link` on both segments of the wrapped link. `#require` exactly two segments, or the case is
    vacuous.
  - **The boundary.** Sweep the second line in 1 pt steps. At every point, `pointer(at:) == .link`
    exactly when `linkCharacterIndex(at:) != nil`, so hover and click agree everywhere (PG-220).
- **Hosted attachments.**
  - **A table grid.** Build it the way `TableGridHostedAttachmentTests` does: an `NSScrollView`,
    then `layoutIfNeeded`, `layoutSubtreeIfNeeded` and `layoutViewport`. `#require(grid.superview !=
    nil)`, then expect `nil` at the grid's centre converted to the text view.
  - **A drawn image embed.** `nil` at its picture centre, using `EmbedEditorFixtures`'
    `waitForRendition`/`pictureFrame`.
- **The decision on `FormattingTextView`.** Style a card through `CardTextAttributes`, as
  `CardTagAndDateClicks` builds it.
  - Editable: `.link` over a wikilink and a tag, `.text` over plain text, `nil` outside.
  - With `isEditable = false`: `nil` everywhere.
- **The tracker (R-06), no view.** Inject a recorder and `schedule = { $0() }` unless stated
  otherwise.
  - `track(.link)`, `track(.link)`, `track(.text)`, `track(.text)`, `reset()` records
    `[.link, .text, nil]`.
  - `reset()` with nothing reported records nothing.
  - **Detach waits for the queue.** With a manual queue as `schedule`: `detach()` after `.link`
    records nothing until the queue runs, then records `nil`.
  - **A late `nil` is dropped.** `detach()` then `track(.text)` before the queue runs records
    `[.link, .text]`.
  - **A released tracker still delivers.** Release the tracker after `detach()` and before the
    queue runs: `nil` is still delivered.
  - **Refresh coalesces.** Two `refresh` calls make one queued closure. When it runs, it calls
    `answer` once with `windowLocation`. With no location (never tracked, or after `reset`), `answer`
    is not called.
- **Per view (R-06).** A `CompletingTextView` with a recorder: `trackPointer(at:)` over the link, the
  link again, plain text, then `nil` records `[.link, .text, nil]`. The same on `FormattingTextView`.
- **A link moves under a still pointer (R-07).** Use `schedule = { $0() }` and the text
  `"riga semplice abbastanza lunga\n[[Seconda nota]]"`.
  - `trackPointer` over line 0 records `.text`.
  - Delete line 0 through `insertText("", replacementRange:)`. That goes through `didChangeText` and
    the coordinator's restyle. The record becomes `[.text, .link]` with no further call.
  - The mirror case: insert a plain line above a link that is under the pointer. It records
    `[.link, .text]`.
  - **A restyle.** With `hidesMarkup` on, put the caret into the link's paragraph
    (`setSelectedRange`). `#require` that the link's segment frame moved. The last record equals
    `pointer(at:)` at the stored point.
- **No AppKit cursor (R-09).** A source guard checks every
  `Sources/Features/Editor/CompletingTextView*.swift` and
  `Sources/Features/Workspace/FormattingTextView*.swift` file. No line outside a comment contains
  `NSCursor`. The files are read under `resolvedRepoRoot()`, following
  `UITestLaunchHarnessGuardTests`.

**`Tests/EditorPointerHostTests.swift`** (new, hosted with `HostedView` and `settle()`).

- **`NoteTextView` (R-06).**
  - Host it with `onPointerChange: { state.pointer = $0 }` and `.editorPointer(state)`.
  - Find its `CompletingTextView` as `NoteTextViewUpdatePinsTests` does.
  - `trackPointer(at:)` over the link, then `settle()`: `state.pointer == .link`.
  - Over plain text: `.text`. With `nil`: `nil`.
- **`CardTextView` (R-06).** The same while editable. Then the model sets `isEditable` to false.
  After `settle()`, `state.pointer == nil`, which is the refresh at the end of `updateNSView`.
- **A model change under a still pointer (R-07).**
  - The text comes from a model object through `Binding(get:set:)`.
  - Track over plain line 0, then replace the model text so the link moves under that point.
  - After `settle()`, `state.pointer == .link`.
  - This is the refresh at the end of `runPasses`. A programmatic change never reaches
    `didChangeText`.
- **The editor is not rebuilt by a pointer change.**
  - The test's host view builds `NoteTextView(...).editorPointer(state)` as the real hosts do, and
    counts its own `body` evaluations in a class box.
  - `state.pointer = .link` then `settle()` leaves the count unchanged.
  - The test is green on arrival. It guards Task 4.
- **Every host is wired (R-06).** A source guard checks every `Sources` file that builds
  `NoteTextView(` or `CardTextView(`:
  - it passes `onPointerChange:` at least as many times as it builds one;
  - it contains `.editorPointer(`.

  On the base these are four files: `EditorColumn+Text.swift`, `TodayView.swift`, `DiaryView.swift`
  and `StickyTextCard.swift`.

**The dead attribute (R-09).**

- `CardTextViewTests.swift:196` and `:202` become `#expect(attributes[.cursor] == nil, ...)`. The
  message cites ADR-0090 §D7.
- `MarkdownAttributedTextTests.swift:314` changes the same way.
- Four tests drop "AndCursor" from their names:
  - `linkTargetCarriesLinkAndCursorForAResolvableTarget`
  - `embedTargetCarriesLinkAndCursorForAFileReference`
  - `aCommonMarkLinkLabelCarriesLinkAndCursorForAnExternalURL`
  - `aCommonMarkLinkLabelCarriesLinkAndCursorForAVaultRelativeNote` (this one never asserted the
    cursor)
- Their `.editorLink` assertions stay exactly as they are.

**What cannot be pinned in-process is named, not faked.**

- `PointerStyle` is not `Equatable` and has no public reader, and a UI test cannot read the cursor.
- So R-06's "a host applies the matching style" is pinned only up to the value the modifier reads.
- The mapping and the screen are checked by hand in R-02/R-03's check. This is a departure,
  recorded in ADR-0090 §D9.

**Red before Task 3:**

- the decision cases;
- the tracker, per-view and R-07 cases;
- the `NSCursor` source guard, which `NSCursor.pointingHand.set()` still fails;
- the three flipped `.cursor` pins;
- the host source guard.

The body-count guard is green.

### Task 3 — Coder: the text views answer and report (R-05, R-06, R-07, R-09)
Owner: coder
Files: Sources/Features/Editor/EditorPointer.swift, Sources/Features/Editor/CompletingTextView.swift, Sources/Features/Editor/CompletingTextView+CursorRects.swift, Sources/Features/Workspace/FormattingTextView.swift, Sources/Features/Workspace/FormattingTextView+CursorRects.swift, Sources/Features/Workspace/FormattingTextView+Clicks.swift, Sources/Features/Editor/NoteTextView.swift, Sources/Features/Editor/NoteTextView+Update.swift, Sources/Features/Workspace/CardTextView.swift, Sources/Features/Editor/MarkdownAttributedText.swift, Sources/Features/Editor/MarkdownAttributedText+Clicks.swift, Sources/Features/Workspace/CardTextAttributes.swift
Tests: EditorPointerTests.swift, EditorPointerHostTests.swift, CardTextViewTests.swift, MarkdownAttributedTextTests.swift, TagDateClickTargetTests.swift, WikilinkClickNavigationTests.swift
Signatures:
- FormattingTextView.linkCharacterIndex — `func linkCharacterIndex(at point: CGPoint) -> Int?` (widened from `private` in `FormattingTextView+Clicks.swift`, with one comment naming `FormattingTextView+CursorRects.swift` as its reader, ADR-0045's convention)
- NoteTextView.runPasses — `func runPasses(on textView: CompletingTextView, coordinator: Coordinator)` (relied on; gains one last call)
Red: no

**The tracker, in `EditorPointer.swift`.**

- **`track`** stores `location`. When `pointer != reported`, it sets `reported` and calls `onChange`
  synchronously. It is called only from AppKit event handlers or from a deferred refresh, never
  inside a SwiftUI update.
- **`refresh`** is coalesced: one pending closure at a time, scheduled through `schedule` with
  `[weak self]`. When it runs with a `windowLocation`, it calls
  `track(answer(location), atWindowLocation: location)`.
- **`reset`** is synchronous, since it is called from `mouseExited`. It clears `windowLocation`. If
  `reported != nil`, it sets `reported = nil` and calls `onChange(nil)`.
- **`detach`** handles removal from the window, which can happen inside a SwiftUI update.
  - It clears `windowLocation`. If `reported != nil`, it sets `reported = nil`.
  - It then schedules the delivery, capturing `onChange` strongly and `self` weakly:
    `schedule { [weak self] in if self?.reported == nil { deliver?(nil) } }`.
  - A tracker released meanwhile still delivers. One that reported something newer meanwhile drops
    the stale `nil`.
- **`EditorPointerModifier.body`** stays a pass-through here. Task 4 gives it the route.

**Both text views mirror each other** in their `+CursorRects` files, as twins rather than a shared
helper (ADR-0027 §D1).

- **`pointer(at:)` in `CompletingTextView`:**
  - `nil` outside `bounds`.
  - `nil` inside the converted frame of any `tableViews` or `viewBlockHosts` value whose
    `superview != nil`. Reach them through `textContentStorage?.delegate as? EditorDecorationDelegate`,
    as `drawnTableGrids()` does.
  - `nil` when the paragraph holding `characterIndexForInsertion(at:)` draws an embed
    (`drawnEmbedRange(atParagraphStart:in:)`).
  - `.link` when `linkCharacterIndex(at:) != nil`.
  - Otherwise `.text`.
- **`pointer(at:)` in `FormattingTextView`:**
  - `nil` when `!isEditable`, or outside `bounds`.
  - `.link` when the widened `linkCharacterIndex(at:) != nil`.
  - Otherwise `.text`.
- **`trackPointer(at:)`.** With `nil`, it calls `pointerTracker.reset()`. Otherwise it calls
  `pointerTracker.track(pointer(at:), atWindowLocation: convert(point, to: nil))`.
- **`refreshPointer()`.** It calls `pointerTracker.refresh { [weak self] in ... }`, converting the
  window point back with `convert(_:from: nil)` and answering `pointer(at:)`. The point is kept in
  window coordinates so that a scroll or a reflow re-asks where the mouse really is.
- **`updateTrackingAreas()`.**
  - The link areas stay exactly as they are: same geometry, same padding (PG-220).
  - Add one view-wide area, `[.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]` with
    owner `self`. It is kept in `pointerTracker.viewArea` and replaced on each call.
  - End with `refreshPointer()`.
- **`mouseEntered`.** For the view area or a link area, call `trackPointer(at:)` at the event's
  location. Crossing a link area only triggers a re-ask; the attribute decides. Otherwise, `super`.
- **`mouseExited`.**
  - The view area: `trackPointer(at: nil)`.
  - A link area: re-ask at the event's location.
  - Otherwise, `super`.
- **`cursorUpdate(with:)`.** Call `super`, then `trackPointer(at:)` at the event's location, only
  when `window?.isKeyWindow == true`. Never `set()`.
  - On route A′, do not call `super`.
  - The per-tick delivery comes from #191's measurement. If the hand check shows the pointer
    lagging inside a run, add `mouseMoved(with:)` with the same body after `super`. That is a named
    contingency, not the default.
- **`didChangeText()`.** Call `super`, then `refreshPointer()`. `super` posts the notification the
  coordinator restyles on, so the refresh asks after the restyle.
- **`setSelectedRanges(_:affinity:stillSelecting:)`.** Call `super`, then `refreshPointer()` unless
  still selecting. A drag-select is left to the system.
- **`viewDidMoveToWindow()`.** Call `super`, then `pointerTracker.detach()` when `window == nil`.
  This covers a culled card, a pane switch and a closed tab.

**Stored state and comments.**

- `hoveredLinkCount` is deleted in both classes. `pointerTracker` takes its place, with a one-line
  comment.
- The comments on `linkTrackingAreas` (`CompletingTextView.swift:51-60`,
  `FormattingTextView.swift:23-28`) are corrected. The areas drive hover events for the pointer
  report, not a pointing-hand cursor.
- **The two file headers are rewritten** to say what is now the case, citing `PG-219` and ADR-0090.
  Each keeps one sentence of the measured history: AppKit cursors never reach the screen in this
  window, and `NSCursor.current` agreed while the arrow showed. Each says the file keeps its name
  because ADR-0083 cites it.
- `FormattingTextView+CursorRects.swift`'s `cursorUpdate` doc comment says that answering last is
  what makes the cursor stick. It is rewritten too.

**Wiring.**

- `NoteTextView.wire(_:to:)` gains `textView.onPointerChange = { coordinator.parent.onPointerChange($0) }`.
- `runPasses` ends with `textView.refreshPointer()`, after `growToFitTheText`.
- `CardTextView`'s closure block gains
  `textView.onPointerChange = { [weak coordinator] in coordinator?.parent.onPointerChange($0) }`, in
  the file's own style.
- `CardTextView.updateNSView` ends the `duringViewUpdate` block with `textView.refreshPointer()`.

**The dead attribute.**

- `.cursor` leaves three places:
  - `MarkdownAttributedText.clickable(_:url:)` (`:234`);
  - `MarkdownAttributedText.clickAttributes(for:source:)` (`:50`), together with its doc comment's
    «link and cursor»;
  - `CardTextAttributes` (`:175`, `:186`).
- Read every other `cursor` comment in those three files before keeping it. "Cursor" also means the
  caret in this codebase.

**Untouched:** `CompletingTextView+Pasteboard.swift`, not one byte.

**`CompletingTextView.swift` is at 397 lines,** against SwiftLint's 400-line warning. The swap of
stored state must not grow it, and the new code goes into the `+CursorRects` extension.

### Task 4 — Coder: the four hosts draw it (R-02, R-03, R-04, R-06)
Owner: coder
Files: Sources/Features/Editor/EditorPointer.swift, Sources/Features/Editor/EditorColumnView.swift, Sources/Features/Editor/EditorColumn+Text.swift, Sources/Features/Today/TodayView.swift, Sources/Features/Diary/DiaryView.swift, Sources/Features/Workspace/StickyTextCard.swift
Tests: EditorPointerHostTests.swift
Signatures:
- EditorPointerModifier.body — `func body(content: Content) -> some View` (the route Task 1 recorded)
- EditorColumnView.pointerState — `@State var pointerState = EditorPointerState()` (internal: `EditorColumn+Text.swift` reads it)
- TodayView.pointerState — `@State private var pointerState = EditorPointerState()`
- DiaryView.pointerState — `@State private var pointerState = EditorPointerState()`
- StickyTextCard.pointerState — `@State private var pointerState = EditorPointerState()`
Red: no

**`EditorPointerModifier.body`, per route:**

- **Route A or A′:** `content.pointerStyle(state.pointer?.style)`.
- **Route B:** `content.overlay { Color.clear.contentShape(Rectangle()).pointerStyle(state.pointer?.style).allowsHitTesting(false) }`.

Either way, `state.pointer` is read here and nowhere else. A `nil` style leaves the system default,
which is what the SPEC asks for over hosted attachments and outside the text.

**The four hosts.** Each declares its state, passes `onPointerChange: { pointerState.pointer = $0 }`
and applies `.editorPointer(pointerState)` directly on the text view's expression:

- **`EditorColumn+Text.editing(_:)`:** after `NoteTextView(...)`, before
  `.modifier(FindKeeping(...))`.
- **`TodayView.noteBody`:** after `NoteTextView(...)`, before `.frame(minHeight: 320)`.
- **`DiaryView.editor`:** after `NoteTextView(...)`, before its `.frame`.
- **`StickyTextCard.content`:** after `CardTextView(...)`. The card reports `nil` while it is not
  being edited, so it needs no condition here.

**Constraints:**

- No host `body` reads `pointerState.pointer`. Writing it from the closure is not a read.
- No host gains another stored input on the text view.
- No token, colour or font is introduced.
- `EditorColumnView`'s state is internal, like its other `@State` properties, because an extension
  in another file applies it. The other three hosts keep theirs `private`.

### Task 5 — Tester: staleness sweep, full verification, the hand check (R-02, R-03, R-04, R-08, R-09, R-12)
Owner: tester
Files: docs/plans/pg-219-pointer-feedback.md
Tests: EditorPointerTests.swift, EditorPointerHostTests.swift, CardTextViewTests.swift, MarkdownAttributedTextTests.swift, TagDateClickTargetTests.swift, WikilinkClickNavigationTests.swift, NoteTextViewUpdatePinsTests.swift, TableGridHostedAttachmentTests.swift
Signatures:
- (none: this task adds no symbol, it re-reads every contract Tasks 2 to 4 changed)
Red: no

**Update tests and call sites asserting the old behaviour.** These greps ran on `9103768f`. Run each
again on the branch and list anything new.

- **The `.cursor` attribute and the AppKit hand:** `grep -rnE
  'NSCursor\.pointingHand|\.cursor\]|\.cursor:|hoveredLinkCount' Sources Tests`.
  - On the base it finds:
    - `CompletingTextView+CursorRects.swift:16` (a header comment), `:49`, `:57`, `:61`, `:62`;
    - `FormattingTextView+CursorRects.swift:25`, `:33`, `:42`, `:43`;
    - `CompletingTextView.swift:60`;
    - `FormattingTextView.swift:27-28`;
    - `MarkdownAttributedText.swift:234`;
    - `MarkdownAttributedText+Clicks.swift:50`;
    - `CardTextAttributes.swift:175`, `:186`;
    - `CardTextViewTests.swift:196`, `:202`.
  - After Task 3, `Sources` may hold header-comment mentions only, and `Tests` only the flipped
    `== nil` pins.
  - `MarkdownAttributedTextTests.swift:314` uses `attribute(.cursor, ...)`, which this grep does not
    match. Task 2 flipped it; re-read it.
- **The new inputs.** `NoteTextView(` has three `Sources` sites and `CardTextView(` has one. 39 test
  files build one or the other with the default. The host source guard covers the `Sources` side.
- **`linkTrackingAreas` and `cursorUpdate`** appear only in the two classes and their `+CursorRects`
  files. N3's ADR-0083 cites `CompletingTextView+CursorRects.swift` by name, and the name is kept.
- **The protected file is untouched.**
  - `git diff --exit-code origin/main -- Sources/Features/Editor/CompletingTextView+Pasteboard.swift`
    exits 0.
  - Its `shasum -a 256` equals Task 1's baseline.

**Full verification, in this order.** Run the whole bundle, not just the new files: a contract change
can break tests in modules that share it.

1. TEST-CMD, the whole `PergamenumTests` bundle.
2. Build `perg` and `pergamenum-mcp`. No shared source changed, but this proves it.
3. `swiftlint lint --quiet` per touched Swift file, read for new findings only. The whole repo is red
   by design, which is why CHECK-CMD is `NONE`.
4. `git fetch origin`, then `scripts/check-adr-references.py`.
5. At merge, `scripts/uitests.sh --status`, then `--affected`. Both are advisory per `CLAUDE.md`, and
   no GUI test is added (R-12).

**The hand check (gate G5; R-02, R-03, R-04, R-08).** Use this checkout's Debug build, found by
`WorkspacePath`, on Task 1's throwaway vault, launched the same way. Add a `Probe.canvas` holding one
text card with a wikilink and a tag. Stefano reports in chat, and the build session records each
item.

1. **Note editor.**
   - The hand over the wikilink, the CommonMark label, `#client-acme`, `>2026-10-14` and
     `!2026-10-15`. It stays steady while the pointer is held still.
   - The I-beam over the plain line and in the empty space below the text.
   - The system arrow outside the editor.
2. **Oggi and Diario.** The daily note and the Diario behave as in item 1, over a link and over
   plain text.
3. **Workspace.** The card while its text is being edited shows the hand and the I-beam, at board
   zoom 100% and at another zoom. At rest, it shows no hand.
4. **The existing cursors (R-08).** The editor columns' divider, the Workspace pane divider, the
   board handles and the crop editor: resize cursor on hover, arrow after, nothing left pushed.
5. **Drags.** A drag-select across a link, and a note title dragged onto the editor. The system
   cursor wins, and nothing sticks afterwards.
6. **A second, non-key window** over a link: no change while it is not key.
7. **Scrolling, as an observation only:** with the pointer held still over a link and over text.

The answers go verbatim under `## Hand check` below and in the PR body's "Hand check" section, with
Task 1's probe result.

### Task 6 — Coder: the record, the agreements, the ledger (R-11)
Owner: coder
Files: docs/adr/0090-the-editor-pointer-is-drawn-by-appkit.md, docs/adr/0088-one-truncator-and-a-capture-title-always-shown.md, docs/plans/note-workflow-n1.md, CLAUDE.md
Signatures:
- ADR-0090 — `- Status: **proposed**` until the post-merge flip; §D5's route, `## Probe result` and `## Implementation notes` filled
- CLAUDE.md working agreement — the frozen text below
Red: no

(no-test: documentation, ADR and ledger text, checked by reading the diff.)

**ADR-0090.**

- Fill `## Probe result` from Task 1, and the route in §D5.
- Fill `## Implementation notes` with every departure. Candidates:
  - route A′'s `cursorUpdate` without `super`;
  - the `mouseMoved` contingency, if taken;
  - gate G4's readings, as answered;
  - the zoom finding, if any.
- Check the number again on every ref before the merge.

**ADR-0088.** Its «The pointer (`PG-219`, R-09)» bullet under «Not decided here» gains one
sentence: «Decided in ADR-0090: the route measured by its probe, built by
`docs/plans/pg-219-pointer-feedback.md`.» ADR-0088 is still `proposed`, so its body may change.

**`docs/plans/note-workflow-n1.md`.**

- **Remove:**
  - the pointer half of Task 3 and Task 4: files, signatures, the probe, the R-09 paragraphs, and the
    R-09 citations in both headings;
  - Task 7's «`PG-219`/#445 is closed by this PR»;
  - Task 8's pointer grep and pointer hand-check line;
  - gate G3.
- **Add:** its «Covered by» section gains R-09, delivered by this plan and ADR-0090.
- **Keep:** its G1 halves and every other task, untouched.
- **If the N1 delta's build has already started,** do not edit the file. Report the overlap to the
  orchestrator.

**`CLAUDE.md`.**

- The Chain decision index gains an ADR-0090 line after ADR-0089's, in the index's style.
- Working agreements gain this entry, proposed for Stefano's approval at G5:

  > - **An `NSCursor` set from AppKit code inside this app's SwiftUI tree never reaches the screen.**
  >   `set()` in `cursorUpdate(with:)`, `push()`/`pop()` from an `NSView` override and cursor rects
  >   all leave `NSCursor.current` reading the new cursor while the screen draws the arrow (PG-219).
  >   A view that needs a pointer decides which one in AppKit and lets SwiftUI draw it: `.pointerStyle`
  >   on the host, as `EditorPointerModifier` does (ADR-0090), or SwiftUI's own `.onHover`, as the
  >   dividers do. Never add a `cursorUpdate`/`resetCursorRects` override expecting it to show.

**After the merge (R-11).** These are human-approved follow-ups.

- **Flip ADR-0090 to `accepted`** as the first docs change after the merge. Name the PR, its merge
  hash from `git log --first-parent main`, and the date (README rule 2).
- **Update the ledger** through the usual `chore(tasks)` sync, never a hand edit inside the feature
  PR:
  - **`PG-219`/#445 is closed.** The PR body says `Closes #445`.
  - **`PG-384`'s phase.** «Task 8 (PG-219) remains» becomes «Task 8 (PG-219) closed by PR #N». The
    note-workflow N1 delta remains its own question (that plan's G6).
  - **`PG-386`'s prerequisite note** drops «PG-219» from «PG-378 and PG-219 first», naming the
    closing PR.

## Risks and HITL gates

- **G0, the base and the number (HITL).**
  - Branch from `main` at or after `9103768f`.
  - Run `tuist install` and `tuist generate --no-open` before the first build, and again after
    Task 2 adds its three files.
  - Check ADR number 0090 on every ref immediately before the merge. Parallel chains are in flight:
    the N1 delta and `docs/spec-pg-385-n2-page-markers`.
  - **Keep the plan and the ADR on the build branch.** Do not land them first in a docs-only PR, as
    #904 did with ADRs 0081 to 0088. That would put ADR-0090 on `main` as `proposed` without its
    implementation, and `check-adr-references.py` rule 2 would then report it on every open PR
    until the flip (PG-340).
- **G1, probe A's answer (HITL).** Stefano's own words decide. A flicker asks him to choose A′ or B.
- **G2, probe B's answer (HITL),** only if A fails.
- **G3, both probes fail (HITL, R-10).** Stop and report as in Task 1 step 10. Tasks 2 to 6 do not
  run.
- **G4, readings to confirm at plan approval.** Each is planned as stated unless Stefano says
  otherwise.
  - **(a) "Outside the text gives nothing" means outside the text view.** Empty space inside it,
    past a line's end or below the last line, gives the I-beam, as an AppKit text view does.
  - **(b) Over a table grid, a view block or a drawn embed, no style is applied.** The system default
    shows; the I-beam is never forced there. A grid cell's own pointer is unchanged and out of
    scope.
  - **(c) Only `.editorLink` runs get the hand.** A task checkbox, the fold chevron, the margin and a
    transclusion block keep the I-beam, even though they react to clicks. Extending the hand to them
    would be a follow-up ticket, if wanted.
  - **(d) A Workspace card at rest shows neither the hand nor the I-beam.** It is dragged, not typed
    into.
  - **(e) The `.cursor` attribute is removed,** and three test pins flip, as explained above.
  - **(f) R-06's "the host applies the matching style" is pinned in-process only up to the value
    the modifier reads.** The `PointerStyle` mapping is checked by hand (ADR-0090 §D9).
- **G5, the hand check (HITL),** and approval of the proposed `CLAUDE.md` working agreement.
- **Human gates and scope.**
  - Commit, push, the PR, the merge, the post-merge ADR flip and the ledger sync are all
    human-gated.
  - No schema, deploy, deletion or external resource is involved.
  - The probe vault lives in the session scratchpad.
- **Risks.**
  - **Board zoom.** The card's AppKit hit-testing maps the event point the same way clicks do. If
    the hand sits offset from the link at a zoom other than 100%, clicks share that conversion. That
    is a pre-existing defect: file it, do not fix it here.
  - **A non-key window could keep a stale hand** while its content changes. The contingency is a
    reset on `NSWindow.didResignKeyNotification`, added only if the hand check shows it.
  - **`cursorUpdate` per tick is a #191 measurement, not documented API.** The `mouseMoved`
    contingency is in Task 3.
  - **Observation must invalidate the modifier and not the host.** The body-count test pins this.
    If it fails, do not replace the modifier with a generic wrapper `View` that holds the editor
    value, because that re-diffs `NoteTextView` and restyles the note. Stop and report instead.
  - **Hosted tests flake under concurrent `xcodebuild` runs (PG-331).** Read a red's report from the
    xcresult before rerunning.
  - **Merge friction with the N1 delta.** It touches the same hosts and `NoteTextView.swift`, and its
    Tasks 3 and 4 name the same pointer files. Task 6 reconciles that plan; whichever lands second
    rebases onto the other.
  - **N3 is unaffected.** ADR-0083 owns its own tracker and tracking area and only calls
    `linkCharacterIndex(at:)`, and nothing here changes either.

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield

CHECK-CMD CANDIDATE: NONE

The repository declares no static check that is green on the tree. Whole-repo SwiftLint is red by
design and is not in `ci.yml`, as `docs/plans/pg-384-n1-seams.md` recorded. Task 5 lints the touched
files by hand.

## Probe result

- **Date:** 2026-10-06.
- **macOS:** ProductVersion 27.0.1, BuildVersion 26A434.
- **Xcode:** 27.0 (27A266a).
- **Commit:** `9103768f` (base, plus the temporary probe line, since removed).
- **Pasteboard baseline:** `shasum -a 256 Sources/Features/Editor/CompletingTextView+Pasteboard.swift` =
  `d2cabf0cbcfae3fcd1c9c4658b80e6506063f0bd5494b70a322e5703868203e1`.
- **Probe A** (`.pointerStyle(.link)` on the Note editor's `NoteTextView(...)` expression, Debug build,
  throwaway vault in the session scratchpad). Stefano's answer, verbatim: «manina, stabile anche
  nell'evidenziare». His screenshot shows the hand over the second line (the link row) during a
  drag-select, with the format bar up. Limit of the reading: the answer does not separate the plain
  first line from the link row. The probe asks only whether SwiftUI's pointer reaches the screen
  steadily against `NSTextView`'s own cursor handling, and it does.
- **Probes A′ and B:** not run, as A passed.
- **Route: A, later superseded by C (`## Route C amendment`).** The probe line was removed by an inverse Edit and
  `git diff --exit-code -- Sources/Features/Editor/EditorColumn+Text.swift` exits 0. No probe instance
  is left running.

## Hand check

*Filled by /build in Task 5.* Record Stefano's answers for items 1 to 7 verbatim, with the date and
the build.

Route A's check failed on 2026-10-06 (hand for an instant, then the I-beam). Route C (see
`## Route C amendment`) was confirmed on the Note editor by Stefano the same day, «ora funziona», on
an experiment build. The check of the final route C build, all items, is owed:

- 2026-10-06, route C build (Debug, dylib 18:44), real mouse, items 1 to 6 (Note editor, Oggi, Diario,
  Workspace card, dividers and handles, non-key window, scroll): Stefano, verbatim: «tutto ok».

## Build result (2026-10-06)

BUILD · DONE WITH WARNINGS
Files: 21 modified, 6 new (EditorPointer.swift, EditorPointerTests.swift, EditorPointerHostTests.swift, ADR-0090, this plan, SPEC.md); CompletingTextView+Pasteboard.swift untouched (shasum d2cabf0c…8203e1)
Tests: PergamenumTests green, 5482 tests in 323 suites, 5 known issues (not compared with main); hosted pointer tests included; screen draw is a hand check (gate G5), not pinned
Review: sonnet, safe; opus, safe (escalated, 4 rounds: initial, loop 2, sweep 1)
Coverage: SPEC.md R-01..R-12 covered; 5 stale (no-test:) waivers, see WARN
Open: none
Deferred: QuickLookFocusTests.swift:245 neverShown flake (PG-331 sighting, no honest fix); ADRs 0081-0088 still `proposed` (their implementation is not on main); CardTextView.swift 418 lines vs 412 on main (best reachable 415)
Dropped: EditorPointerTests.swift file_length (688 lines, 47 test files already over); EditorPointer.swift:59 doc-comment wording (NIT)
Dispatch: Round 0 (red): tester — Task 2
Dispatch: Round 1: coder — EditorPointer.swift:104 test gap, ADR-0090 note 8, CursorRects:24 double resolution
Dispatch: Round 2: coder — HostTests:217 restyle pin, CursorRects:38 hidesMarkup guard, HostTests:124 neverShown, EditorPointer.swift:108 evaluated note
Dispatch: Round 1 (sweep): coder — refresh guard, ADR-0090 header/§D2/§D3 citation, CardTextView comments, QuickLookFocusTests:245, ADRs 0081-0088
Dispatch: Round 2 (sweep): debugger — EditorPointerTests.swift:451 refresh guard pins (not re-reviewed, rounds exhausted)
WARN: STALE-WAIVER R-01, R-02, R-04, R-08, R-10: the SPEC's (no-test: …) clauses protect nothing now, delete them from SPEC.md
WARN: CardTextView.swift 418 lines, over SwiftLint file_length 400 (412 on main)
WARN: EditorPointer.swift:111 SwiftLint redundant_discardable_let, false positive inside a ViewBuilder
WARN: check-adr-references.py exits 1 on ADRs 0081-0088 (rule 2) and hashes ef8d28d/c2cf19b; merge origin/main (PR #908) before the PR
INFO: review escalated, size: 27 changed files, threshold 20
INFO: Task 1 done inline (probe A, route A), recorded in `## Probe result`
INFO: hand check (gate G5), Stefano's approval of the CLAUDE.md working agreement and ADR-0090 `accepted` are still owed

```text
DEFER	no-honest-fix	**MINOR** [other] Tests/QuickLookFocusTests.swift:245 — neverShown flake, PG-331 shape, add as a sighting to #704
DEFER	not-landed	**MINOR** [other] docs/adr/0081:3 — ADRs 0081-0088 stay proposed, implementation not on main
DEFER	not-reachable	**MINOR** [other] Sources/Features/Workspace/CardTextView.swift:418 — file_length over 400, 412 on main
DROP	nit	**NIT** Sources/Features/Editor/EditorPointer.swift:59 — doc comment wording
DROP	unlocated	**MINOR** [other] Tests/EditorPointerTests.swift — file_length 688
```

NEXT: /ship

## Route C amendment (2026-10-06)

Route A failed the real-mouse hand check, and after research and two experiments the build moved to
route C, chosen by Stefano: AppKit decides and AppKit draws.

- **Measured:** `set()` in `cursorUpdate(with:)` alone shows the hand while the mouse is still and
  loses it at the first move, because `NSTextView`'s `mouseMoved(with:)` puts its I-beam back. A
  second `set()` after `super.mouseMoved(with:)` holds (experiment Y, «ora funziona»).
- **Code:** `EditorPointer.apply()` is the one `NSCursor` call; both text views override
  `cursorUpdate(with:)` and `mouseMoved(with:)`, key window only. Deleted: `EditorPointerTracker`,
  `EditorPointerState`, `EditorPointerModifier`, `.editorPointer(_:)`, `onPointerChange:`, the
  per-link tracking areas and `refreshPointer()`.
- **Tests:** the suites of the deleted mechanism (`EditorPointerTrackerTests`, `TextViewPointerReports`,
  `PointerFollowsTheText`, `PointerWiringOfTheTextViews`, the host wiring and no-rebuild pins) are
  removed with it, not weakened: they asserted behaviour that no longer exists. Kept: the decision
  suites and `NoAppKitCursorInTheTextViews`. Added: `EditorPointerCursorMapping`,
  `NoteEditorAppliesThePointer`, `CardAppliesThePointer` (what reaches `NSCursor.current`).
- **Docs:** ADR-0090 amended in place (`## Amendment`), the `CLAUDE.md` working agreement and index
  entry rewritten.
- **Route C review (2026-10-06):** one reviewer (sonnet), verdict safe, no BLOCKER or MAJOR. Six MINOR
  and three NIT, all fixed: two dead `updateTrackingAreas()` calls and their comments, a stale
  accessibility doc reference, route A wording in three test messages, ADR-0090's Context and
  cross-reference, a `Departures from SPEC.md` list in the ADR, the ADR file renamed to
  `0090-the-editor-pointer-is-drawn-by-appkit.md` (CLAUDE.md and this plan updated), and two new tests
  pinning that both overrides leave a non-key window alone. Not re-reviewed after the fixes.
- **Hand check:** passed, see `## Hand check`.
- **Superseded in the Build result above:** the test count, the file list, the review verdicts and the
  `NEXT: /ship` line describe route A. The route C build has not been reviewed again.
