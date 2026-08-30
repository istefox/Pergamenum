import AppKit
import Foundation
import Testing
@testable import Pergamenum

// ADR-0028, plan `2026-08-29-wysiwyg-markdown-in-workspace`, Task 7 (R-09, R-11, R-12).
//
// Scope of this file: fold on a Workspace `.text` card - the pure rule that says which lines a
// fold takes away, and the transient table on `WorkspaceController` that says which headings of
// which card are folded right now. What a folded heading *looks like* (the badge, its count, the
// click that opens it) is `FoldedHeadingFragment`'s and is asserted in
// `Tests/FoldBadgeClickTests.swift`; what a fold *hides* is `NoteFolding`'s own subject and is
// asserted in `Tests/NoteFoldingTests.swift` against a note. Neither is re-derived here.
//
// The claim this file exists to check is narrower and is the one ADR-0028 §D8 rests on: **the
// note's pure fold types answer for a card with no adaptation at all**. `NoteFolding` and
// `FoldedHeadingFragment` are used unchanged by this task - if either had needed an edit, that
// would have been a design finding rather than a coding one (plan Task 7). It did not: the
// assertions below call `NoteFolding.layout(in:foldedEntries:)` directly on a card's own markdown
// and read the offsets a card's text view will hand `EditorDecorationDelegate`.
//
// RED on arrival: `CardTextView.Coordinator.releaseDecorations()` empties the marker and reveal
// tables but says nothing about the fold table, so
// `aFoldedCardsTableDoesNotSurviveItsTeardown` fails on its post-dismantle assertion. The card's
// own rendering wiring (the `foldedEntries` the view passes down, the `BoardCardMenu` submenu
// built from `NoteOutline.entries(in:)`, and the badge click in `FormattingTextView.mouseDown`)
// is this task's coder's work and is not asserted here - it is hand-checked in Task 8, the way
// this repo checks every other in-text AppKit gesture.
//
// Green on arrival, and deliberately so: the catalogue entry (`CardCommand.foldHeadings`) and the
// controller's own table are the *interface* half of the task, written with the tests that call
// them under this repo's compiled-language convention (plan, "Conventions binding on every
// task"). They are assertions about a contract, not about a body still to be filled in.

// MARK: - Fixtures

/// A card's own markdown: no frontmatter, because a `.canvas` text node never has one. That is
/// the one structural difference from a note, and `NoteOutline.bodyStart(of:)` handles it by
/// returning `startIndex` - which is exactly why nothing here needs adapting.
///
/// Two headings at different levels, a bullet list under the first and a blank line before the
/// second, so the fixture exercises the rule that actually matters (a section ends at the next
/// heading of the same or a higher level) and the one that catches an off-by-one (a blank line
/// is a line like any other and is hidden with the rest).
private let card = "# Titolo\n- primo\n- secondo\n\n## Sotto\ncorpo"

/// The UTF-16 offset each line of `card` begins at - the key space `NoteFolding.Layout` speaks
/// and `EditorDecorationDelegate` reads. Written out rather than computed, so a test that goes
/// red says which line moved.
private enum Line {
    static let titolo = 0
    static let primo = 9
    static let secondo = 17
    static let blank = 27
    static let sotto = 28
    static let corpo = 37
}

private func makeTempRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "pergamenum-card-fold-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

/// A card wired the way `CardTextView.makeNSView` wires it, minus the `Context` no test can
/// build - the same compromise `Tests/CardConcealmentTests.swift` makes, and for the same reason.
/// `allowsUndo` is set here because `makeNSView` sets it and the undo assertions below are about
/// what a real card's stack does.
@MainActor
private struct FoldCard {
    let scrollView: NSScrollView
    let textView: FormattingTextView
    let coordinator: CardTextView.Coordinator
}

@MainActor
private func makeFoldCard(_ text: String, editable: Bool = true) throws -> FoldCard {
    let view = CardTextView(
        text: .constant(text),
        theme: .emergency,
        style: CardTextStyle(color: nil, alignment: nil),
        isEditable: editable,
        hidesMarkup: true
    )
    let coordinator = view.makeCoordinator()
    let scrollView = FormattingTextView.scrollableTextView()
    let textView = try #require(
        scrollView.documentView as? FormattingTextView,
        "scrollableTextView() must hand back an instance of the receiving class"
    )

    textView.delegate = coordinator
    textView.allowsUndo = true
    textView.textContentStorage?.delegate = coordinator.decorations
    textView.textLayoutManager?.delegate = coordinator.decorations
    textView.string = text
    coordinator.configure(textView, editable: editable)
    coordinator.applyStyling(to: textView)
    textView.setSelectedRange(NSRange(location: 0, length: 0))
    return FoldCard(scrollView: scrollView, textView: textView, coordinator: coordinator)
}

/// The fold as the card's rendering pass will perform it: the pure layout, handed to the shared
/// delegate. Written out at each call site's level rather than hidden in a helper that could be
/// mistaken for production code - what is being asserted is that these two lines are the whole of
/// it, and that neither of them touches a character.
@MainActor
private func applyFold(_ entries: Set<Int>, to fold: FoldCard) -> NoteFolding.Layout {
    let layout = NoteFolding.layout(in: fold.textView.string, foldedEntries: entries)
    fold.coordinator.decorations.apply(
        hiddenLines: layout.hiddenLineOffsets, foldedHeadings: layout.foldedHeadings
    )
    return layout
}

// MARK: - R-09: the note's pure fold answers for a card, unadapted

/// `NoteOutline` numbers a card's headings the way it numbers a note's, and those ordinals are
/// what the fold submenu will offer and what the table below holds. Asserted first because every
/// other number in this file is an index into this list.
@Test func aCardsOwnMarkdownIsOutlinedByTheNotesOwnParser() {
    let entries = NoteOutline.entries(in: card)

    #expect(entries.count == 2)
    #expect(entries[0].kind == .heading(level: 1))
    #expect(entries[0].title == "Titolo")
    #expect(entries[1].kind == .heading(level: 2))
    #expect(entries[1].title == "Sotto")
}

/// The whole of ADR-0028 §D8's premise, in one call: the note editor's `NoteFolding` is handed a
/// card's text and answers with the offsets a card's text view needs - no card-shaped overload,
/// no adaptation, not a line of it edited by this task.
///
/// Folding entry 0 (`# Titolo`, level 1) takes everything after it, because no heading of the
/// same or a higher level follows: the two list items, the blank line, the `## Sotto` inside it
/// and its body. Five lines, which is also what the badge says.
@Test func foldingACardsFirstHeadingHidesEveryLineUnderItAndCountsThem() {
    let layout = NoteFolding.layout(in: card, foldedEntries: [0])

    #expect(layout.hiddenLineOffsets == [Line.primo, Line.secondo, Line.blank, Line.sotto, Line.corpo])
    // The heading's own line is never hidden - a folded section that took its title with it
    // would leave nothing to unfold.
    #expect(!layout.hiddenLineOffsets.contains(Line.titolo))
    #expect(layout.foldedHeadings == [Line.titolo: 5])
}

/// The nested heading folds on its own, hiding only its own body: the level rule holds on a card
/// exactly as it does in a note, which it must, because it is the same function.
@Test func foldingACardsNestedHeadingHidesOnlyItsOwnSection() {
    let layout = NoteFolding.layout(in: card, foldedEntries: [1])

    #expect(layout.hiddenLineOffsets == [Line.corpo])
    #expect(layout.foldedHeadings == [Line.sotto: 1])
}

/// Nothing folded is nothing hidden and no badge drawn - the state every card starts in and
/// returns to, and the one the delegate has to be handed for a card to look untouched.
@Test func aCardWithNothingFoldedHidesNothingAndDrawsNoBadge() {
    let layout = NoteFolding.layout(in: card, foldedEntries: [])

    #expect(layout.hiddenLineOffsets.isEmpty)
    #expect(layout.foldedHeadings.isEmpty)
}

/// A card with no heading in it - which is most cards - answers empty rather than guessing, so an
/// entry ordinal that names nothing can never hide a line.
@Test func foldingAnEntryThatDoesNotExistOnACardHidesNothing() {
    let layout = NoteFolding.layout(in: "solo testo\ne una seconda riga", foldedEntries: [0])

    #expect(layout.hiddenLineOffsets.isEmpty)
    #expect(layout.foldedHeadings.isEmpty)
}

// MARK: - R-09: the transient table, keyed by node id

/// Fold, then unfold, and the card is back where it started. The plain half of the command, and
/// the one every other assertion here rests on.
@MainActor
@Test func togglingACardsFoldTwiceReturnsItToNothingFolded() {
    let workspace = WorkspaceController()

    workspace.toggleFold(0, forNodeID: "n")
    #expect(workspace.foldedHeadings["n"] == [0])

    workspace.toggleFold(0, forNodeID: "n")
    #expect((workspace.foldedHeadings["n"] ?? []).isEmpty)
}

/// Keyed by node id, which is what makes two cards on one board fold independently. A single set
/// on the controller would have folded every card the moment one of them was folded - and with
/// entry ordinals meaning different headings on each, it would have hidden arbitrary lines.
@MainActor
@Test func twoCardsFoldIndependentlyBecauseTheTableIsKeyedByNodeID() {
    let workspace = WorkspaceController()

    workspace.toggleFold(0, forNodeID: "a")
    workspace.toggleFold(1, forNodeID: "b")

    #expect(workspace.foldedHeadings["a"] == [0])
    #expect(workspace.foldedHeadings["b"] == [1])

    workspace.toggleFold(0, forNodeID: "a")

    #expect((workspace.foldedHeadings["a"] ?? []).isEmpty)
    #expect(workspace.foldedHeadings["b"] == [1], "piegare una card non tocca l'altra")
}

/// R-09's second half, literally: «lo stato di fold non è persistito nel file `.canvas`». A fold
/// is a way of looking at a card, so it may not reach the document, may not make the board dirty,
/// and may not become a step of the board's own Annulla (R-12) - three separate ways a view state
/// could leak into a file that principle 1 says is the only truth.
@MainActor
@Test func foldingACardWritesNothingToTheBoardAndLeavesItClean() throws {
    let root = try makeTempRoot()
    let store = CanvasStore(root: root)
    try FileManager.default.createDirectory(
        at: root.appending(path: "A", directoryHint: .isDirectory), withIntermediateDirectories: true
    )
    let path = try store.createBoard(named: "b", in: "A")
    try store.save(
        CanvasDocument(nodes: [
            CanvasNode(id: "n", kind: .text(card), x: 0, y: 0, width: 200, height: 200)
        ]),
        board: path
    )
    let workspace = WorkspaceController()
    workspace.attach(to: store)
    workspace.open(board: path)
    let before = workspace.document

    workspace.toggleFold(0, forNodeID: "n")

    #expect(workspace.document == before, "una piega non scrive nulla nel nodo")
    #expect(workspace.hasUnsavedChanges == false, "e non sporca la board")
    #expect(workspace.canUndo == false, "e non è un passo dell'Annulla della board")
    #expect(workspace.foldedHeadings["n"] == [0], "la piega esiste, ma solo qui")
}

/// R-09's third half, and the line that enforces it: «si azzera alla riapertura della board».
/// `attach` is where a vault is opened, and a table keyed by node id that survived it would name
/// ids belonging to another vault's files - a canvas id is unique inside its own file, not across
/// a vault, so a stale entry would not merely be useless, it could fold the wrong card.
@MainActor
@Test func attachingToAVaultClearsEveryFoldTheLastOneLeftBehind() throws {
    let root = try makeTempRoot()
    let workspace = WorkspaceController()
    workspace.toggleFold(0, forNodeID: "n")
    #expect(!workspace.foldedHeadings.isEmpty, "premessa: c'è una piega da azzerare")

    workspace.attach(to: CanvasStore(root: root))

    #expect(workspace.foldedHeadings.isEmpty)
}

/// The same reset from the other side of the crossing: closing a vault leaves no fold behind for
/// the next one to inherit.
@MainActor
@Test func detachingClearsEveryFold() throws {
    let root = try makeTempRoot()
    let workspace = WorkspaceController()
    workspace.attach(to: CanvasStore(root: root))
    workspace.toggleFold(0, forNodeID: "n")
    #expect(!workspace.foldedHeadings.isEmpty, "premessa: c'è una piega da azzerare")

    workspace.detach()

    #expect(workspace.foldedHeadings.isEmpty)
}

// MARK: - R-11: a fold does not survive the card that drew it

/// A card's text view is deallocated on every culling-rect crossing (ADR-0028 §Context, the
/// `a853e8e` crash class), so the fold table the shared delegate holds has the same lifetime as
/// the marker and reveal tables `Tests/CardConcealmentTests.swift` already asserts are dropped.
/// It is the third table and the same hazard: offsets measured against text that is gone, read on
/// the next layout pass of whatever storage still points at this delegate.
///
/// The rebuild is the second half of the claim: a coordinator restyled over different text must
/// not bring back a fold nobody asked for. An entry for a node that no longer exists is dropped,
/// never resurrected.
@MainActor
@Test func aFoldedCardsTableDoesNotSurviveItsTeardown() throws {
    let fold = try makeFoldCard(card)
    let layout = applyFold([0], to: fold)
    #expect(layout.foldedHeadings == [Line.titolo: 5], "premessa: la piega è davvero applicata")
    #expect(fold.coordinator.decorations.isFolding, "premessa: il delegate la sta disegnando")

    CardTextView.dismantleNSView(fold.scrollView, coordinator: fold.coordinator)

    #expect(!fold.coordinator.decorations.isFolding, "la tabella delle pieghe è svuotata")

    // Rebuilt: same coordinator, other text, no fold asked for.
    fold.textView.string = "un'altra card, senza titoli"
    fold.coordinator.applyStyling(to: fold.textView)

    #expect(!fold.coordinator.decorations.isFolding, "una piega non torna da sola")
}

// MARK: - R-12: folding is view state, and Cmd+Z never sees it

/// Folding registers no text edit at all, which is what keeps R-12 true for it: there is nothing
/// to take back, so the one undo the person presses reaches straight past the fold to the last
/// real change - it never spends a press putting a section back that they can reopen by clicking
/// the badge.
///
/// The text edit before the fold is the positive control: without it, "no action was registered"
/// would be a claim about an undo manager that might simply not be recording in this harness.
/// `groupsByEvent = false` plus explicit grouping is `CardConcealmentTests`' own idiom for making
/// `canUndo` deterministic where no run loop is turning.
@MainActor
@Test func oneUndoAfterAFoldTakesBackTheTextEditAndNotTheFold() throws {
    let fold = try makeFoldCard(card)
    let workspace = WorkspaceController()
    let undoManager = fold.coordinator.undoManager
    undoManager.groupsByEvent = false
    let before = fold.textView.string

    undoManager.beginUndoGrouping()
    fold.textView.replaceWholeText(
        with: before + "\nriga aggiunta", selecting: NSRange(location: 0, length: 0)
    )
    undoManager.endUndoGrouping()
    let edited = fold.textView.string
    #expect(edited != before, "premessa: la modifica è avvenuta")
    #expect(undoManager.canUndo, "premessa: una modifica del testo registra un'azione")

    workspace.toggleFold(0, forNodeID: "n")
    _ = applyFold(workspace.foldedHeadings["n"] ?? [], to: fold)

    // Not one character: a fold hides lines from the layout, it does not remove them from the
    // storage (principle 1 - the card's text is a node in a file on disk).
    #expect(fold.textView.string == edited, "ripiegare non tocca un carattere")

    undoManager.undo()

    #expect(fold.textView.string == before, "il solo annulla disponibile è quello della modifica")
    #expect(workspace.foldedHeadings["n"] == [0], "la piega non è stata annullata: non era una modifica")
}

/// The same claim without the surrounding edit, stated as the undo manager sees it: a fold on a
/// card nobody has typed into leaves the stack exactly as empty as it found it.
@MainActor
@Test func foldingRegistersNoUndoActionAtAll() throws {
    let fold = try makeFoldCard(card)
    let workspace = WorkspaceController()
    let undoManager = fold.coordinator.undoManager
    undoManager.groupsByEvent = false
    #expect(!undoManager.canUndo, "premessa: si parte da uno stack vuoto")

    workspace.toggleFold(0, forNodeID: "n")
    _ = applyFold(workspace.foldedHeadings["n"] ?? [], to: fold)
    workspace.toggleFold(0, forNodeID: "n")
    _ = applyFold(workspace.foldedHeadings["n"] ?? [], to: fold)

    #expect(!undoManager.canUndo, "né piegare né dispiegare registra un'azione")
    #expect(fold.textView.string == card, "e il sorgente della card è quello di partenza")
}
