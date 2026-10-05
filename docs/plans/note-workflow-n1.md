**Requirement set:** `SPEC.md`

# Plan — N1 delta: what the note-workflow SPEC asks beyond PR #897's chain

`SPEC.md` here is the note-workflow SPEC (N1 to N5, Approved 2026-10-04) in this chain's working
tree. It is not the N1-only SPEC that PR #897 left at the repository root on `main`; that one is
archived as `docs/specs/note-workflow-n1-seams.spec.md`.

On 2026-10-05, Stefano kept PR #897 as the N1 implementation. That is `kepler/task-00994c70`
@ `593eaff3`, merged as `5056c61f`, and built from `docs/plans/pg-384-n1-seams.md`. That plan has
eight tasks:

- **Tasks 1 to 3** shipped in #897: the topic-less rule, the derived capture title, the inbox
  folder setting, ADR-0080 and the app SPEC amendments.
- **Tasks 4 to 8** are its session 2, still to build: completion, clickable tags and dates,
  `spacing.paragraph` and H6, the pane switches, Cmd+N, the inline creation errors, and the hand
  check.

**This plan is built only after #897 and that session 2 are both on `main`.** It holds only what
the note-workflow SPEC's N1 criteria ask and that chain does not deliver, or delivers differently.
Session 2's symbols are cited by the names its plan declares (`CommandActions.openEventNote`,
`CommandActions+Open.swift`, `WorkspaceController.createDocument`/`DocumentCreation`,
`VaultController.createNoteFromQuickOpen`/`quickSwitcherProblem`,
`ProseParagraphSpacing.paragraphRanges`, `ProseTypography.paragraphSpacing`/`headingColor`). If
the merged code names them differently, adopt the merged names. A missing capability is reported,
never re-implemented here.

**ADR outcome: one new ADR, `docs/adr/0088-one-truncator-and-a-capture-title-always-shown.md`
(proposed), amending ADR-0080 §D3 and §D4.** It records Tasks 1 and 2. The capture title is cut by
the one word-boundary truncator, which reverses ADR-0080 §D4's recorded rejection. The panel
always shows the title, and refuses a taken one with the composer's sentence, which amends §D3's
caption clause. Without that record, ADR-0080 would describe code that no longer exists.

Every other item here carries no ADR. Each follows a pattern the code already has and is cheap to
reverse:

- **The event-note focus** is a one-shot request in `closeRequest`'s shape.
- **«Documento»'s confirmation** is in-sheet state.
- **The folder's inline error** follows the note kind's route.
- **The G1 values** go through tokens.

R-09 too has no ADR, as long as Task 4's probe confirms the `.pointerStyle` route; if it fails, it
stops at gate G3 for one.

This file replaces the full N1 plan written on 2026-10-04. Its ADR draft,
`docs/adr/0080-a-note-born-without-a-topic-is-a-capture.md`, is superseded by #897's ADR-0080 and
is to be discarded (a human deletion).

## Covered by PR #897's chain (not cited by any task below)

- **R-01**, the topic-less rule on every creation path and the MCP dry-run diff. Done by their
  R-01/R-02, Tasks 1 and 2, shipped in #897.
- **R-03**, `[[` closing `]]` without doubling it, and alias rows that insert the title. Covered
  by their R-07/R-08, Tasks 4 and 5, pending. Their approved reading offers aliases in the note
  editor only, while the card closes `]]` but lists no aliases. Our R-03 does not tie its alias
  clause to a surface, so this is reported as a reading to confirm (gate G4), not planned.
- **R-06**, Cmd+N in the sidebar's folder with the parked draft winning and «Nuova nota qui»
  unchanged. Covered by their R-11, Tasks 6 and 7, pending.
- **R-07**, Cmd+click on `#client-acme` opening Tags, and on `>2026-10-14` opening Oggi. Covered
  by their R-12/R-13, Tasks 4 to 7, pending.
  - The styler's `.scheduled` span is `>` plus ten characters (`MarkdownStyler.swift:449-456`),
    so `>2026-10-14 10:00` is clickable on its date, as our Decisions ask.
  - Their chain also makes `!2026-10-14` clickable, which our Decision («the `>YYYY-MM-DD`
    scheduling tokens») does not name. That is reported at gate G4, not planned.
- **R-10**, the inbox folder setting, its default, its absent key and its field, used by note and
  task capture. Done by their R-16/R-17, Tasks 1 and 2, shipped in #897.

## What reading `origin/main` @ `5056c61f` established

- **R-02.**
  - `ImportNaming.truncatedAtSpace(_:toFit:)` (`ImportNaming.swift:190`) is a second
    word-boundary loop beside `truncatedAtWordBoundary(_:toFit:)` (`:170`). Its one caller is
    `CaptureTitle.swift:70`, and four tests in `CaptureTitleTests.swift:194-219` pin it.
  - The two functions differ when the first word exceeds the budget: `""` against a hard cut.
    They also differ on runs of spaces, which `CaptureTitle` has already collapsed.
  - `CaptureController.titleCaption` (`:97`) returns `nil` unless the title differs, and
    `CapturePanelTests.swift:305` and `:390-391` pin that.
  - A taken title reaches the panel as `ConnectorError`'s «esiste già: …» (`VaultWrites.swift:85`,
    caught at `CaptureController.swift:164`). The composer says «Esiste già una nota in …»
    (`ConformanceText.creationFailure`).
- **R-04.** The editor takes the keyboard only when `focusedColumnIndex` changes or the composer
  ends (`EditorColumnView.swift:152-162`), never when the Note pane appears. Their session 2
  switches the pane for the event note and makes it the active tab, but moves no keyboard focus
  into it.
- **R-05.**
  - Their SPEC rejected «a confirmation with «Apri»», reasoning that the sheet closes before the
    write ends. Their Task 7 keeps the sheet open until the write ends, then closes it.
  - `docs/plans/note-workflow-n4.md` keeps «Apri in the confirmation» when its composer replaces
    the sheet's note kind.
- **R-08.**
  - Their SPEC rejected the mockup. Session 2 ships `spacing.paragraph` at 8 pt in both themes,
    applied after every prose **and heading** source line, in the note editor only (their
    interpretation 6).
  - H6 is regular weight in `textSecondary`, in the editor and the cards.
  - Our Decisions require the N1 mockup on paragraph spacing and H5/H6. The mockup
    (`docs/plans/note-workflow-n1-mockup.md`) is kept and now reviews the shipped values (gate G1).
- **R-09.**
  - `PG-219` is out of their scope. `NSCursor.pointingHand` is still set in
    `CompletingTextView+CursorRects.swift:62` and `FormattingTextView+CursorRects.swift:43`.
  - The `.cursor` attribute is set in `MarkdownAttributedText.swift:220` and
    `CardTextAttributes.swift:165,176`.
  - None of these reaches the screen (the ledger entry). The one working custom pointer is
    SwiftUI's: `TimelineBlockBox.swift:105` uses `.pointerStyle`, available from macOS 15 with
    `.link` and `.horizontalText` (developer.apple.com, checked 2026-10-04).
- **R-11.**
  - Their R-18 shows a failure inline for Quick Open and «Documento» only.
  - The sheet's folder kind still goes to the problem list alone (`WorkspaceView+Creation.swift:62-69`,
    out of their scope).
  - Their stubs record nothing and their tests do not assert the problem list, which our R-11
    asks for as well. `WorkspaceController.recordProblem` reports to `VaultController.problems`
    (`WorkspaceController.swift:343`). Adding a link card cannot fail (`addLink(_:at:) -> String`).
- **R-12.**
  - #897 amended §4.1, §4.3, §8.1, §12 and §16. Our R-12 names §4.2 for the capture title rule,
    which landed in §16; ADR-0080 corrects the premise that §4.2 holds capture wording.
  - §10 already states Cmd+Shift+B, Cmd+Shift+D and Ctrl+Cmd+3.
  - The four "from the template" comments are corrected.

## Tasks

Two tester tasks declare symbols with neutral bodies: `nil`, `false`, `.text`, and today's
behaviour otherwise. Never a `fatalError`, which would crash the test host instead of turning it
red. Run `tuist generate --no-open` after adding a file. A pinned test that changes is changed
only after saying why in chat (global rule); each one is named below with its reason.

### Task 1 — Tester: one truncator, a caption that always shows, the composer's sentence (R-02)
Owner: tester
Files: Sources/Core/Conventions/ImportNaming.swift, Tests/CaptureTitleTests.swift, Tests/CapturePanelTests.swift
Tests: CaptureTitleTests.swift, CapturePanelTests.swift, CaptureTests.swift, ConventionsNamingTests.swift, PraticaNamingTests.swift, InboxFolderReachTests.swift
Signatures:
- ImportNaming.truncatedAtWordBoundary — `static func truncatedAtWordBoundary(_ slug: String, toFit budget: Int, separator: Character = "-") -> String`
- ImportNaming.truncatedAtSpace — `static func truncatedAtSpace(_ text: String, toFit limit: Int) -> String` (relied on, contract unchanged)
- CaptureController.titleCaption — `func titleCaption(now: Date = Date(), calendar: Calendar = .current) -> String?` (relied on, behaviour changes)
- CaptureController.capture — `func capture(into session: VaultSession?) async -> Bool` (relied on)
- ConformanceText.creationFailure — `static func creationFailure(_ error: Error) -> String` (relied on)
Red: yes

**Declaration.** `truncatedAtWordBoundary` gains `separator: Character = "-"`. Its neutral body
ignores it and keeps splitting on `-`. Every existing caller compiles unchanged.

**`CaptureTitleTests`, new cases** (ADR-0088 §D1):

- `truncatedAtWordBoundary("uno due tre", toFit: 7, separator: " ") == "uno due"`;
- `truncatedAtWordBoundary("abcdefghij klm", toFit: 4, separator: " ") == ""`;
- `truncatedAtWordBoundary("uno-due-tre", toFit: 7) == "uno-due"`, today's default.

The four `truncatedAtSpace` tests (`:194-219`) stay unmodified. They are the proof that the
wrapper keeps the contract. `ConventionsNamingTests` and `PraticaNamingTests` stay unmodified and
green: the two protected names keep their bytes.

**`CapturePanelTests`** (ADR-0088 §D2). Two pinned expectations change, and the reason goes in
their comments: the caption now shows whenever a «Nota nuova» has text, so the person sees which
line becomes the title.

- `theCaptionIsNilForALegalFirstLine` (`:305`) becomes `theCaptionNamesALegalFirstLineToo`:
  `"Titolo: Mescola per il distretto"`.
- The last assertion of `theCaptionStopsAtALoneCarriageReturnAndAtACRLF` (`:390-391`) expects
  `"Titolo: Mescola per il distretto"`.

The empty-text and other-destination tests stay `nil` and unmodified.

New tests, in a temporary vault through `capture(into:)`:

- **A taken legal title.** `00 Inbox/Mescola per il distretto.md` exists. Sending
  `"Mescola per il distretto\nAltro"` returns `false`, and `outcome` is
  `.refused("Esiste già una nota in 00 Inbox/Mescola per il distretto.md")`. The existing file is
  byte-identical, and no other file appears. The caption still reads
  «Titolo: Mescola per il distretto».
- **A taken derived title.** `Idea: usare i token anche per i font?` is sent while
  `00 Inbox/Idea usare i token anche per i font.md` exists. It is refused with the same sentence
  shape.
- **The inbox setting.** With `inboxFolder = "Triage"`, the refused path in the sentence is under
  `Triage/`.

**The connector stays as it is.** `CaptureTests.swift:172` keeps pinning «esiste già» from
`VaultAPI.capture`, unmodified.

### Task 2 — Coder: one truncator, the caption, the panel's refusal (R-02)
Owner: coder
Files: Sources/Core/Conventions/ImportNaming.swift, Sources/Features/Capture/CaptureController.swift
Tests: CaptureTitleTests.swift, CapturePanelTests.swift, CaptureTests.swift, ConventionsNamingTests.swift, PraticaNamingTests.swift
Signatures:
- ImportNaming.truncatedAtWordBoundary — `static func truncatedAtWordBoundary(_ slug: String, toFit budget: Int, separator: Character = "-") -> String`
- ImportNaming.truncatedAtSpace — `static func truncatedAtSpace(_ text: String, toFit limit: Int) -> String`
Red: no

**`truncatedAtWordBoundary`.**

- It splits and joins on `separator`; nothing else in its body changes.
- Its doc comment names the third caller: `truncatedAtSpace`, for `CaptureTitle` (ADR-0088 §D1).
  ADR-0045's sentence, that an edit here turns the protected names' tests red, stays.

**`truncatedAtSpace`.**

- Its body becomes one call: `truncatedAtWordBoundary(text, toFit: limit, separator: " ")`,
  returning `String(text.prefix(limit))` when that is `""` and `limit > 0`. Keep its `limit <= 0`
  guard.
- Its doc comment replaces «Beside `truncatedAtWordBoundary` rather than a generalisation of it»
  with the ADR-0088 §D1 reason.
- `CaptureTitle.swift` is not touched.

**`titleCaption`.** It drops the `differsFromTyped` condition and keeps the destination and
empty-text guards.

**`capture(into:)`.**

- For `.note`, before calling `VaultAPI.capture`, derive the title through the same
  `CaptureTitle.typedLine` and `derive` calls `titleCaption` makes. The path is
  `"\(folder ?? session.inboxFolder)/\(title).md"`.
- If `session.exists(path)`, set
  `outcome = .refused(ConformanceText.creationFailure(VaultSession.CreationError.alreadyExists(path)))`,
  log it as the existing refusals are, and return `false` without writing.
- This is a filter, not a guard (ADR-0043 §D7): `createNote`'s own check stays the guard, so a
  file appearing in between is still refused, in the connector's wording.
- `VaultAPI.capture` and `VaultWrites` are not touched.

**After the task.**

- Build `perg` and `pergamenum-mcp`: `ImportNaming.swift` is shared source.
- `rg -n 'lastIndex\(of: " "\)' Sources/Core/Conventions/ImportNaming.swift` must find nothing,
  which shows that one cutting loop is left.

### Task 3 — Tester: the pointer, and the G1 re-pins (R-08, R-09)
Owner: tester
Files: Sources/Features/Editor/EditorPointer.swift, Sources/Features/Editor/CompletingTextView.swift, Sources/Features/Editor/CompletingTextView+CursorRects.swift, Sources/Features/Workspace/FormattingTextView.swift, Sources/Features/Workspace/FormattingTextView+CursorRects.swift, Sources/Features/Editor/NoteTextView.swift, Sources/Features/Workspace/CardTextView.swift, Tests/EditorPointerTests.swift, Tests/DesignSystemTests.swift, Tests/ProseParagraphSpacingTests.swift, Tests/ProseTypographyTests.swift
Tests: EditorPointerTests.swift, DesignSystemTests.swift, ProseParagraphSpacingTests.swift, ProseTypographyTests.swift, ListIndentFontInvariantTests.swift, TransclusionLayoutTests.swift, WikilinkClickNavigationTests.swift, TagDateClickTargetTests.swift, CardTextViewTests.swift
Signatures:
- EditorPointer — `enum EditorPointer: Equatable, Sendable { case text, link }` with `var style: PointerStyle` (SwiftUI; app-only file)
- CompletingTextView.pointer — `func pointer(at point: NSPoint) -> EditorPointer`
- CompletingTextView.trackPointer — `func trackPointer(at point: NSPoint)`
- CompletingTextView.onPointerChange — `var onPointerChange: ((EditorPointer) -> Void)?` (stored, in `CompletingTextView.swift`)
- FormattingTextView.pointer — `func pointer(at point: NSPoint) -> EditorPointer`
- FormattingTextView.trackPointer — `func trackPointer(at point: NSPoint)`
- FormattingTextView.onPointerChange — `var onPointerChange: ((EditorPointer) -> Void)?` (stored, in `FormattingTextView.swift`)
- NoteTextView.onPointerChange — `var onPointerChange: (EditorPointer) -> Void = { _ in }`
- CardTextView.onPointerChange — `var onPointerChange: (EditorPointer) -> Void = { _ in }`
- SpacingToken.paragraph, ProseTypography.paragraphSpacing, ProseTypography.headingColor, ProseParagraphSpacing.paragraphRanges — as session 2 ships them (relied on)
Red: yes

**R-09.** Neutral bodies: `pointer(at:)` returns `.text`, and `trackPointer` does nothing.
Every new property is defaulted, because about twenty tests build `NoteTextView(`.

`EditorPointerTests.swift` (new, in-process: an offscreen window, a `CompletingTextView` and a
`FormattingTextView`, each holding one `.editorLink` run, laid out with `updateTrackingAreas()`
called):

- `pointer(at:)` is `.link` at the run's midpoint and `.text` over plain text.
- It is `.link` over a Cmd+clickable `#client-acme` and `>2026-10-14` too, which session 2 made
  `.editorLink` runs.
- `trackPointer` called over the link, then over text twice, calls back exactly `[.link, .text]`:
  once per change, never repeated.
- `EditorPointer.link.style == .link`, and `.text.style == .horizontalText`.

The cursor actually drawn on screen cannot be asserted in-process. It is checked by hand in
Task 8.

**R-08, only where G1's answers differ from what session 2 shipped.** Session 2 ships 8 pt,
spacing after heading lines, blank lines not spaced, and H6 regular in `textSecondary`.

- **The value.** If G1 picks 12 pt, the pins of `spacing.paragraph == 8` change to 12 in
  `DesignSystemTests` (both themes and `Theme.emergency`) and in `ProseParagraphSpacingTests`'
  hosted case.
- **Headings.** If G1 excludes them, `ProseParagraphSpacingTests` expects no range on a heading
  line.
- **Blank lines.** If G1 spaces them, a blank line between two prose lines is in the result.
- **H6.** If G1 rejects the H6 face, `ProseTypographyTests`' H6 pins return to the H5 face in
  `.textPrimary`.

Each changed pin names G1 in its comment. If G1 confirms everything, this half writes nothing.

### Task 4 — Coder: the pointer through SwiftUI, and the G1 values (R-08, R-09)
Owner: coder
Files: Sources/Features/Editor/EditorPointer.swift, Sources/Features/Editor/CompletingTextView.swift, Sources/Features/Editor/CompletingTextView+CursorRects.swift, Sources/Features/Workspace/FormattingTextView.swift, Sources/Features/Workspace/FormattingTextView+CursorRects.swift, Sources/Features/Editor/NoteTextView.swift, Sources/Features/Editor/NoteTextView+Update.swift, Sources/Features/Editor/EditorColumn+Text.swift, Sources/Features/Today/TodayView.swift, Sources/Features/Diary/DiaryView.swift, Sources/Features/Workspace/CardTextView.swift, Sources/Features/Workspace/StickyTextCard.swift, Sources/Features/Editor/MarkdownAttributedText.swift, Sources/Features/Workspace/CardTextAttributes.swift, Resources/Themes/pergamenum-light.json, Resources/Themes/pergamenum-dark.json, Sources/DesignSystem/Theme.swift, Sources/Features/Editor/ProseParagraphSpacing.swift, Sources/DesignSystem/ProseTypography.swift
Tests: EditorPointerTests.swift, DesignSystemTests.swift, ProseParagraphSpacingTests.swift, ProseTypographyTests.swift
Signatures:
- EditorPointer.style — `var style: PointerStyle`
Red: no

**Probe first, before anything else is written** (`PG-219`):

1. On a Debug build, wrap the Note editor's `NoteTextView` in `EditorColumn+Text` in an
   unconditional `.pointerStyle(.link)`.
2. Hover the text.
3. If the pointing hand shows, remove the probe and go on.
4. If it does not, try the modifier on a `Color.clear` overlay with `allowsHitTesting(false)`.
5. If neither shows, stop. R-09 stays red and gate G3 is raised (an ADR for the
   `.onContinuousHover` restructure the ledger entry describes). Do not improvise it.

Record the route and the macOS build in the PR body.

**R-09.**

- **`pointer(at:)`** answers `.link` when a rect of the existing `linkTrackingAreas` contains the
  point. It reuses the geometry hover and clicks already share, with no second scan.
- **`trackPointer(at:)`** keeps the last answer and calls `onPointerChange` only on a change.
  `cursorUpdate(with:)`, `mouseEntered` and `mouseExited` call it with the event's location in
  view space.
- **Both `cursorUpdate` overrides** lose `NSCursor.pointingHand.set()` and keep `super`. Shorten
  the two files' header comments to what is now true, citing `PG-219` and this plan.
- **The hosts** each hold `@State var pointer: EditorPointer = .text`, pass
  `onPointerChange: { pointer = $0 }`, and apply `.pointerStyle(pointer.style)` to the text view.
  There are three:
  - the Note editor (`EditorColumn+Text`);
  - the Today pane's daily note (`TodayView`);
  - the Diario (`DiaryView`).
- **A Workspace card** does the same in `StickyTextCard`, while it is being edited only. A card
  that is not being edited is dragged, not typed into.
- **The `.cursor` attribute** goes from `MarkdownAttributedText.clickable` (`:220`) and
  `CardTextAttributes` (`:165`, `:176`): it never reached the screen.

**R-08.** Apply G1's answers, only where they differ from what session 2 shipped:

- **The value:** the `spacing.paragraph` value in both theme files and in `Theme.emergency`.
- **Headings:** the heading exclusion in `ProseParagraphSpacing.paragraphRanges`.
- **Blank lines:** their inclusion, in the same function.
- **H6:** the face and colour in `ProseTypography`.

With G1 confirming everything, this half is empty and the PR body says so.

### Task 5 — Tester: the event note's caret, «Documento»'s «Apri», every sheet failure in place and in the list (R-04, R-05, R-11)
Owner: tester
Files: Sources/App/VaultController.swift, Sources/App/VaultController+Tabs.swift, Sources/App/CommandActions+Reveal.swift, Sources/Features/Workspace/BoardSheets.swift, Sources/Features/Workspace/WorkspaceController+Documents.swift, Tests/NoteRevealTests.swift, Tests/WorkspaceDocumentCreationTests.swift, Tests/QuickOpenCreationTests.swift, Tests/VaultSwitchTests.swift
Tests: NoteRevealTests.swift, WorkspaceDocumentCreationTests.swift, QuickOpenCreationTests.swift, VaultSwitchTests.swift, CommandActionNavigationTests.swift, CommandActionTests.swift, WindowPlaceTests.swift
Signatures:
- VaultController.editorFocusRequest — `private(set) var editorFocusRequest = 0` (stored, in `VaultController.swift`)
- VaultController.requestEditorFocus — `func requestEditorFocus()`
- VaultController.takeEditorFocusRequest — `func takeEditorFocusRequest(forColumn column: Int) -> Bool`
- CommandActions.showInNotePane — `func showInNotePane(_ path: String)` (new file `CommandActions+Reveal.swift`, beside session 2's `CommandActions+Open.swift`)
- CommandActions.openEventNote — `@discardableResult func openEventNote(for eventTitle: String, on day: CalendarDate, start: TaskTime?, end: TaskTime?, attendees: [String]) async -> String?` (session 2, relied on)
- NewCanvasItemSheet.Confirmation — `enum Confirmation: Equatable { case editing; case working; case created(path: String, title: String); case failed(String) }`
- NewCanvasItemSheet.confirmation — `static func confirmation(after creation: WorkspaceController.DocumentCreation, title: String) -> Confirmation`
- WorkspaceController.createDocument — `func createDocument(titled title: String, at point: CGPoint, through vault: VaultController) async -> DocumentCreation` (session 2, relied on)
- WorkspaceController.createFolderFromSheet — `func createFolderFromSheet(named name: String, at point: CGPoint) -> String?` (the failure sentence, `nil` when created)
- VaultController.createNoteFromQuickOpen — `@discardableResult func createNoteFromQuickOpen(title: String) async -> Bool` (session 2, relied on)
Red: yes

**Neutral bodies.**

- `requestEditorFocus` does nothing, and `takeEditorFocusRequest` returns `false`.
- `showInNotePane` does nothing.
- `confirmation(after:title:)` maps `.created` to `.editing`, today's "close", and `.failed(s)` to
  `.failed(s)`.
- `createFolderFromSheet` calls today's `createFolder(named:at:)` and returns `nil` on success. On
  a throw it records the problem as today and returns `nil`.

If session 2 already gave the sheet a phase state, extend it with `.created(path:title:)` rather
than declaring a second one, and name the merged type in the signature instead.

**`NoteRevealTests.swift`** (new, built as `OpenLinkUnresolvedTests` builds `CommandActions`):

- **The event note (R-04).** After `commandActions.openEventNote(...)` from `.today`:
  - the pane is `.notes`, as session 2 delivers;
  - `takeEditorFocusRequest(forColumn: vault.focusedColumnIndex)` is `true` once, then `false`;
  - the other column's answer is `false`;
  - a failed open requests nothing.
- **«Apri» (R-05).** `showInNotePane(path)`:
  - sets `.notes`;
  - opens `path` in a new tab of the focused column, so it is that column's active tab;
  - leaves one focus request pending.
- **Cmd+Shift+D** requests no focus. R-04 asks for focus on the event note only (gate G5).

**`VaultSwitchTests`.** A vault switch clears a pending focus request.

**`WorkspaceDocumentCreationTests`** (session 2's, extended):

- **The confirmation (R-05).** `confirmation(after: .created(path: "00 Inbox/X.md"), title: "X")`
  is `.created(path: "00 Inbox/X.md", title: "X")`: the sheet stays open on its confirmation.
  `.failed(s)` gives `.failed(s)`.
- **The problem list (R-11).** A taken title through `createDocument` leaves its sentence in
  `vault.problems` as well as in `.failed`.
- **The folder (R-11).** `createFolderFromSheet` with a taken or invalid name returns the sentence
  and leaves it in `vault.problems`. A valid name returns `nil` and places one folder node.

**`QuickOpenCreationTests`** (session 2's, extended, R-11). A failed `createNoteFromQuickOpen`
leaves its sentence in `vault.problems` as well as in `quickSwitcherProblem`.

If session 2's code already records these, those assertions are green on arrival. They pin R-11's
second half, which its own tests do not.

### Task 6 — Coder: the caret, the confirmation, the folder error (R-04, R-05, R-11)
Owner: coder
Files: Sources/App/VaultController.swift, Sources/App/VaultController+Tabs.swift, Sources/App/VaultController+VaultSwitch.swift, Sources/App/CommandActions+Open.swift, Sources/App/CommandActions+Reveal.swift, Sources/Features/Editor/EditorColumnView.swift, Sources/Features/Workspace/BoardSheets.swift, Sources/Features/Workspace/WorkspaceView+Creation.swift, Sources/Features/Workspace/WorkspaceController+Documents.swift, Sources/App/VaultController+Notes.swift
Tests: NoteRevealTests.swift, WorkspaceDocumentCreationTests.swift, QuickOpenCreationTests.swift, VaultSwitchTests.swift
Signatures:
- WorkspaceController.placeCreatedNote — relied on, its real signature
- ConformanceText.creationFailure — `static func creationFailure(_ error: Error) -> String` (relied on)
Red: no

**R-04.**

- **The request.** `CommandActions.openEventNote` (session 2) calls `vault.requestEditorFocus()`
  after a successful open and the pane switch.
- **The answer.** `EditorColumnView` answers with `.onChange(of: vault.editorFocusRequest,
  initial: true)`: when `takeEditorFocusRequest(forColumn: columnIndex)` is true, it bumps
  `focusRequest`. `initial: true` is what reaches a column that appears after the pane switch (the
  `closeRequest` precedent, `:105`).
- **If the first responder does not land on the first update** after the pane mounts (checked by
  hand in Task 8), defer the bump one `Task { @MainActor }` hop.
- **Vault switch.** `VaultController+VaultSwitch` clears the request with the other vault-scoped
  state.

**R-05.**

- `showInNotePane` calls `vault.openNoteInNewTab(at:)`, sets `navigation.pane = .notes` and
  requests focus.
- `NewCanvasItemSheet` uses `confirmation(after:title:)`: on `.created` it does not close.
  Instead it shows «Documento «Titolo» creato e posizionato sulla board.» with «Apri» and «Fine».
  - «Fine» is the default action and also answers Esc.
  - «Apri» calls `onOpen(path)`, wired in `WorkspaceView+Creation` to `showInNotePane`, then
    closes.
  - Text through `.themedText`, tokens only.

**R-11.**

- **The folder kind.** `WorkspaceView+Creation`'s `.folder` branch calls `createFolderFromSheet`,
  and a sentence keeps the sheet open on `.failed`, the note kind's route.
  `createFolderFromSheet` records through `recordProblem` and returns
  `"\(error)"`, today's wording.
- **The problem list.** If session 2's `createDocument` or `createNoteFromQuickOpen` does not yet
  record its sentence, add the `recordProblem` call. Neither surface loses its inline sentence.

### Task 7 — Coder: the app SPEC's §4.2 pointer, the records, the ledger (R-12, R-44)
Owner: coder
Files: docs/20260811_Pergamenum_SpecApp.md, docs/adr/0080-a-topicless-note-is-a-capture.md, docs/adr/0088-one-truncator-and-a-capture-title-always-shown.md, CLAUDE.md
Signatures:
- SPEC (app) §4.2, §16 — Italian prose, tagged *Emendato AAAA-MM-GG (ADR-0088)*
Red: no

(no-test: documentation, ADR and ledger text, checked by reading the diff.)

**App SPEC §4.2.** One sentence after the «Note» bullet, so the section our R-12 names states the
rule without moving it:

> «Una nota creata dalla cattura «Nota nuova» con una prima riga che non è un nome valido riceve
> un titolo proposto: la regola è in §16.»

**App SPEC §16.** The sentence «Il pannello mostra «Titolo: …» prima dell'invio» becomes:

> «Il pannello mostra sempre «Titolo: …» prima dell'invio, anche quando coincide con la riga; un
> titolo già preso è rifiutato con la frase del compositore e non scrive nulla.»

Tag it *Emendato (ADR-0088)*. §4.3, §8.1 and §10 are already right (#897); change nothing there.

**ADR-0080.** One scope line at its head, after the status line, ADR-0047's way:

> «§D3's caption clause and the panel's refusal of a taken title, and §D4, amended by ADR-0088.»

Its body is untouched.

**`CLAUDE.md`.** The Chain decision index gains an ADR-0088 line after ADR-0080's, in the index's
style.

**After the merge** (R-44):

- **ADR-0088.** Flip it to `accepted`, naming the PR, its merge hash from
  `git log --first-parent main` and the date (`docs/adr/README.md` rule 2).
- **The ledger.**
  - `PG-219`/#445 is closed by this PR.
  - `PG-384`/#886 closes with it, if gate G6 keeps #886 open until the delta merges.
  - Use the usual `chore(tasks)` sync, not a hand edit inside the feature PR.

### Task 8 — Tester: staleness sweep and full verification (R-45)
Owner: tester
Files: Tests/CapturePanelTests.swift
Tests: CapturePanelTests.swift, CaptureTitleTests.swift, CaptureTests.swift, ConventionsNamingTests.swift, PraticaNamingTests.swift, EditorPointerTests.swift, NoteRevealTests.swift, WorkspaceDocumentCreationTests.swift, QuickOpenCreationTests.swift, CardTextViewTests.swift, MarkdownAttributedTextTests.swift
Signatures:
- (none: this task adds no symbol, it re-reads every observable contract Tasks 1 to 6 changed)
Red: no

**Update tests and call sites asserting the old behaviour.** The greps below ran on `5056c61f`.
Re-run each one after session 2 lands and on the branch, then list anything new.

- **`titleCaption` for a legal line.** Stale: `CapturePanelTests.swift:305` and `:390-391`,
  rewritten in Task 1. `rg -n 'titleCaption' Sources Tests` finds `CapturePanelView.swift` (shows
  it whenever non-nil, so unchanged) and the tests.
- **`truncatedAtWordBoundary` gains a parameter.**
  - Callers: `ImportNaming.swift:134` (`recordingNoteTitle`) and `PraticaNaming.swift:36`, both on
    the default.
  - Tests: `ConventionsNamingTests.swift:145-146` and `PraticaNamingTests.swift:68-69`, unmodified.
- **The capture panel refuses a taken title before writing.** `CaptureTests.swift:172` pins the
  connector's wording and stays unmodified. No other test sends a taken `.note` through
  `capture(into:)`.
- **The pointer.** `rg -n 'NSCursor.pointingHand|\.cursor\]|\.cursor:' Sources` must find nothing
  after Task 4. On the base it finds `CompletingTextView+CursorRects.swift:62`,
  `FormattingTextView+CursorRects.swift:43`, `MarkdownAttributedText.swift:220` and
  `CardTextAttributes.swift:165,176`.
- **`NewCanvasItemSheet` no longer closes on a created note.** `NewCanvasItemSheet(` has one call
  site (`WorkspaceView+Creation.swift:50`). N4 later replaces its note kind and keeps the
  confirmation.

**Full verification, in this order:**

1. The whole `PergamenumTests` bundle (TEST-CMD), not only the touched files.
2. Builds of `perg` and `pergamenum-mcp`.
3. `scripts/mcp-smoke.py`. No MCP source changes here, but `ImportNaming.swift` is shared.
4. CHECK-CMD.
5. `scripts/check-adr-references.py` after `git fetch`.
6. At merge, `scripts/uitests.sh --status`, then `--affected`, advisory per CLAUDE.md. N1 adds no
   GUI test.

**By hand, on this checkout's Debug build** (found by `WorkspacePath`, CLAUDE.md):

- the I-beam over editor and editing-card text;
- the pointing hand over a wikilink, a URL, a `#tag` and a `>date` (R-09);
- the caret in the editor after «Nota per questo evento» (R-04);
- «Documento» showing its confirmation, with «Apri» landing in the Note pane with the caret
  (R-05);
- a taken folder name reported in the sheet (R-11);
- the capture caption shown on a legal line, and a taken title refused with «Esiste già una nota
  in …» (R-02).

## Risks and HITL gates

- **G0, base and SPEC file (HITL).**
  - This plan starts only after session 2 of `docs/plans/pg-384-n1-seams.md` is on `main`.
  - The root `SPEC.md` on `main` is #897's N1-only SPEC. This chain's note-workflow `SPEC.md`
    replaces it when this chain commits, which is a conflict for the orchestrator. Their copy is
    already archived, so replacing the root file loses nothing.
  - The coverage tooling must read the note-workflow SPEC, or it will count #897's R-ids.
- **G1, the mockup answers (HITL, from `docs/plans/note-workflow-n1-mockup.md`).** Task 3's and
  Task 4's R-08 halves apply them, and are empty when G1 confirms what session 2 shipped.
- **G2, ADR-0088 against ADR-0080 (HITL).**
  - The truncator reversal and the always-on caption contradict decisions Stefano approved for
    #897.
  - Both SPECs are his; this plan implements the note-workflow SPEC's constraint and UI flow.
  - If he prefers ADR-0080's choices, Tasks 1 and 2 and ADR-0088 drop, and R-02 moves to the
    covered list.
  - Recommendation: keep ADR-0088. One cutting loop is ADR-0045 §D5's own rule, and the
    taken-title edge case cannot be met without the caption.
- **G3, the PG-219 probe fails (HITL).** R-09 stays red. The PR either ships without it (#445
  stays open) or waits for an ADR on the `.onContinuousHover` restructure. Nothing else here
  depends on R-09.
- **G4, readings of #897's chain to confirm.** Neither is planned unless Stefano asks:
  - aliases offered in the note editor only, not in Workspace cards (our R-03);
  - `!date` clickable as well as `>date` (beyond our R-07's Decision).
- **G5, focus scope.** R-04 asks for the caret on the event note only. Giving Cmd+Shift+D the same
  request is one line; not planned unless asked.
- **G6, issue #886.** Their session 2 records `PG-384` tasks 1 to 7 and 9 as done. Our R-44 wants
  N1's issue closed by N1's PR. Recommended: keep #886 open until this delta merges, or file a
  follow-up issue for it. The person decides.
- **N4 depends on this delta.**
  - `docs/plans/note-workflow-n4.md` keeps «Apri in the confirmation» when its composer replaces
    the sheet's note kind (R-05 here).
  - It cites the inbox setting as «ADR-0080 §D6». In #897's ADR-0080 that is §D5 (§D6 is where
    it is edited); N4's citation needs that correction.
  - N3 (`docs/plans/note-workflow-n3.md`) assumes PG-219's pointer from N1: R-09 here.
- **Merge friction.**
  - Session 2 edits most files Tasks 3 to 6 touch. The CursorRects files are this delta's alone.
  - `CommandActions+Reveal.swift` is new so as not to edit session 2's `CommandActions+Open.swift`
    beyond one call.
- **Protected surfaces.**
  - `truncatedAtWordBoundary`'s default path is pinned by the protected names' own tests,
    unmodified.
  - `CompletingTextView+Pasteboard.swift` is not edited.
- **HITL, always.** Commit, push, the PR and its merge are Stefano's. There is no schema change,
  no data deletion and no deploy. Deleting the superseded
  `docs/adr/0080-a-note-born-without-a-topic-is-a-capture.md` (untracked) is a human step.
- **No externally provisioned resource is needed.**

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield

CHECK-CMD CANDIDATE: ! swiftlint lint --quiet 2>&1 | grep -E "/Sources/.+: error: "
