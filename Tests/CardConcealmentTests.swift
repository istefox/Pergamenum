import AppKit
import Testing
@testable import Pergamenum

// ADR-0028, plan `2026-08-29-wysiwyg-markdown-in-workspace`, Task 5 (R-02, R-03, R-04, R-11).
//
// Scope of this file: the Workspace card's own half of the rendering rule the two surfaces now
// share - the styling walk that fills the hidden-marker table, the reveal that lets the caret's
// paragraph show its raw source, the setting that governs both, and the teardown that has to
// leave nothing behind. The rule itself (what a collapsed marker measures, what a bullet
// replaces, what a stale entry does) is `Tests/MarkupHidingTests.swift`'s subject and is not
// re-asserted here: this file asks whether the *card* feeds that rule the same inputs the note
// editor feeds it.
//
// Built on the same two patterns those files established: `MarkupHidingTests`' windowless
// `NSTextContentStorage` harness - the delegate's substitution hook called by hand, the way
// AppKit calls it during a layout pass - and `CardFormattingTests`' bare offscreen
// `FormattingTextView`. No window is created and no layout is forced: every assertion below is
// about what the delegate is *told* and what it hands back, neither of which needs a screen.
//
// RED on arrival: `CardTextView.Coordinator.applyStyling(to:)` does not yet touch `decorations`
// at all, `applyReveal(to:)` is a stub returning the empty set without publishing anything, and
// `dismantleNSView` purges only the undo stack. Every `@Test` below fails on an assertion rather
// than crashing the run - deliberately, so the rest of the suite still reports.

/// The card, wired the way `CardTextView.makeNSView` wires it: a `FormattingTextView` inside the
/// scroll view Apple's own `scrollableTextView()` builds, the coordinator as its delegate, and -
/// the two lines this task is about - the coordinator's `EditorDecorationDelegate` as both the
/// content storage's and the layout manager's delegate (`NoteTextView.swift:148-149`'s pair).
///
/// The harness assigns those two itself rather than calling `makeNSView`, which needs an
/// `NSViewRepresentable.Context` no test can build - the same compromise `MarkupHidingTests`'
/// `MarkupCoordinator` suite makes for the note editor. What it must never do is *reimplement*
/// what it is checking: the styling walk and the reveal are called on the real coordinator.
@MainActor
private struct Card {
    let scrollView: NSScrollView
    let textView: FormattingTextView
    let coordinator: CardTextView.Coordinator

    /// What the delegate hands back for the paragraph containing `offset`, asked exactly as
    /// AppKit asks it during a layout pass. `nil` is "draw the stored paragraph as it is" - the
    /// setting off, the paragraph revealed under the caret, or nothing to conceal; anything else
    /// is a displayed paragraph with the markers collapsed into `collapsedFont`.
    func displayed(paragraphAt offset: Int) -> NSTextParagraph? {
        guard let storage = textView.textContentStorage else { return nil }
        let range = (textView.string as NSString).paragraphRange(for: NSRange(location: offset, length: 0))
        return coordinator.decorations.textContentStorage(storage, textParagraphWith: range)
    }
}

@MainActor
private func makeCard(
    _ text: String, hidesMarkup: Bool = true, editable: Bool = false
) throws -> Card {
    let view = CardTextView(
        text: .constant(text),
        theme: .emergency,
        style: CardTextStyle(color: nil, alignment: nil),
        isEditable: editable,
        hidesMarkup: hidesMarkup
    )
    let coordinator = view.makeCoordinator()
    let scrollView = FormattingTextView.scrollableTextView()
    let textView = try #require(
        scrollView.documentView as? FormattingTextView,
        "scrollableTextView() must hand back an instance of the receiving class"
    )

    textView.delegate = coordinator
    textView.textContentStorage?.delegate = coordinator.decorations
    textView.textLayoutManager?.delegate = coordinator.decorations
    textView.string = text
    coordinator.configure(textView, editable: editable)
    coordinator.applyStyling(to: textView)
    // `applyStyling` rewrites every attribute in the storage, and on a text view with no window
    // that leaves the selection at the end of the text rather than at the start - the harness
    // artifact `MarkupHidingTests.MarkupCoordinator.editor(hidesMarkup:)` records for the note
    // editor. Pinned here so each test below starts from a known caret and then moves it itself.
    textView.setSelectedRange(NSRange(location: 0, length: 0))
    return Card(scrollView: scrollView, textView: textView, coordinator: coordinator)
}

@MainActor
@Suite struct CardConcealment {
    /// One card carrying all three kinds of marker this chain touches, on three separate lines,
    /// so a single fixture answers "does the card's walk produce the note's table" for every one
    /// of them at once.
    private static let card = "# Titolo\n- primo\n**grassetto**"
    /// `"# Titolo\n"` is nine characters, `"- primo\n"` eight.
    private static let headingParagraph = 0
    private static let listParagraph = 9
    private static let emphasisParagraph = 17

    // MARK: - R-04's precondition: the card's table has the note's shape

    /// The card's styling pass must fill exactly the table `EditorDecorationDelegate` reads:
    /// keyed by paragraph-start offset, every range relative to its own paragraph, one entry per
    /// hidden marker and none for the spans that are only coloured.
    ///
    /// Written against the ranges `MarkdownStyler` actually produces rather than against a
    /// count alone: `.heading` and `.emphasis` ranges start at the marker character, while a
    /// `.list` range starts at the paragraph's own start so the indentation is inside it
    /// (ADR-0028 §D4, `NoteTextView+Coordinator.hiddenMarker(_:at:paragraphStart:)`). A card
    /// whose walk got that one asymmetry wrong would still report the right number of markers
    /// and would draw every nested item flush left.
    @Test func theStylingWalkFillsTheSameMarkerTableTheNoteEditorsDoes() throws {
        let card = try makeCard(Self.card)
        let markers = card.coordinator.hiddenMarkers

        #expect(Set(markers.keys) == [Self.headingParagraph, Self.listParagraph, Self.emphasisParagraph])
        // `"# "` - the hash and the single space after it.
        #expect(
            markers[Self.headingParagraph] == [HiddenMarker(range: NSRange(location: 0, length: 2), kind: .heading)]
        )
        // `"- "` from the paragraph's own start, indentation included (there is none here).
        #expect(
            markers[Self.listParagraph] == [HiddenMarker(range: NSRange(location: 0, length: 2), kind: .list)]
        )
        // Both `**` of `**grassetto**`: opening at 0, closing eleven characters later.
        #expect(
            markers[Self.emphasisParagraph] == [
                HiddenMarker(range: NSRange(location: 0, length: 2), kind: .emphasis),
                HiddenMarker(range: NSRange(location: 11, length: 2), kind: .emphasis)
            ]
        )
        // And the delegate was actually handed it, which is the half the table alone cannot say.
        #expect(card.coordinator.decorations.hiddenMarkerCount == 4)
        #expect(card.coordinator.decorations.hidesMarkup)
    }

    /// PG-086's own precondition, alongside the one above: a checkbox line's marker lands in the
    /// same table under a `.checkbox` kind, five characters wide (the whole `- [ ]`), not folded
    /// into `.list` - a checkbox is never a list marker (ADR-0028 §D11).
    @Test func theStylingWalkFillsAChekboxEntryForATaskLine() throws {
        let card = try makeCard("- [ ] fai\n**grassetto**")
        let markers = card.coordinator.hiddenMarkers
        let checkboxParagraph = 0

        #expect(Set(markers.keys) == [checkboxParagraph, checkboxParagraph + 10])
        #expect(
            markers[checkboxParagraph] == [
                HiddenMarker(range: NSRange(location: 0, length: 5), kind: .checkbox)
            ]
        )
    }

    /// Principle 1, at the card's own level: styling changes how the source is drawn and never
    /// what it says. The card's text is a node in a `.canvas` file on disk.
    @Test func theCardsStringIsByteIdenticalAfterStylingAndReveal() throws {
        let card = try makeCard(Self.card, editable: true)
        card.coordinator.applyReveal(to: card.textView)

        #expect(card.textView.string == Self.card)
    }

    // MARK: - R-04: a card at rest conceals everything

    /// A card nobody is writing into has no caret in it, so it reveals nothing - which is the
    /// whole of R-04: the board shows rendered markdown, not source with one line of syntax
    /// showing because a text view somewhere still remembers where its selection was.
    @Test func aCardAtRestRevealsNothingAndConcealsEveryParagraph() throws {
        let card = try makeCard(Self.card, editable: false)
        // Aimed at the list line on purpose. Whether AppKit honours a selection on a view it has
        // just been told is not selectable does not matter: the answer must be empty either way,
        // because it is `isEditable` that decides, not where a selection happens to sit.
        card.textView.setSelectedRange(NSRange(location: Self.listParagraph, length: 0))

        #expect(card.coordinator.applyReveal(to: card.textView).isEmpty)
        #expect(card.displayed(paragraphAt: Self.headingParagraph) != nil, "il titolo resta nascosto")
        #expect(card.displayed(paragraphAt: Self.listParagraph) != nil, "l'elenco resta nascosto")
        #expect(card.displayed(paragraphAt: Self.emphasisParagraph) != nil, "il grassetto resta nascosto")
    }

    // MARK: - R-03: the caret's paragraph, and only it, shows its source

    @Test func anEditableCardRevealsExactlyTheCaretsParagraph() throws {
        let card = try makeCard(Self.card, editable: true)
        // Inside `- primo`, not at its very start, so this asserts the paragraph the caret is in
        // and not an offset that happens to be a paragraph start already.
        card.textView.setSelectedRange(NSRange(location: Self.listParagraph + 3, length: 0))

        #expect(card.coordinator.applyReveal(to: card.textView) == [Self.listParagraph])
        // Nil is the raw source laid out: the `- ` is back under the caret, no bullet, nothing
        // shifting sideways as the caret arrives.
        #expect(card.displayed(paragraphAt: Self.listParagraph) == nil, "la riga col cursore mostra il sorgente")
        #expect(card.displayed(paragraphAt: Self.headingParagraph) != nil, "le altre righe restano nascoste")
        #expect(card.displayed(paragraphAt: Self.emphasisParagraph) != nil, "le altre righe restano nascoste")
    }

    /// A selection, not a caret: every paragraph it spans is drawn in full, the way
    /// `MarkupReveal.paragraphs` already answers for the note editor. Asserted here because the
    /// card's `applyReveal` is a second call site of that one pure function, and a card that
    /// passed only its caret would conceal markers inside the very text being selected.
    @Test func aSelectionSpanningTwoParagraphsRevealsBoth() throws {
        let card = try makeCard(Self.card, editable: true)
        let selection = NSRange(
            location: Self.headingParagraph + 2,
            length: Self.listParagraph + 4 - (Self.headingParagraph + 2)
        )
        card.textView.setSelectedRange(selection)

        #expect(
            card.coordinator.applyReveal(to: card.textView) == [Self.headingParagraph, Self.listParagraph]
        )
        #expect(card.displayed(paragraphAt: Self.emphasisParagraph) != nil, "la riga fuori selezione resta nascosta")
    }

    // MARK: - ADR-0028 §D10: one setting, and off means off

    /// Off, and nothing is concealed on the card either. The table is still filled - the walk
    /// runs whatever the setting says, exactly as `NoteTextView+Coordinator.applyStyling` fills
    /// it and then hands the setting over beside it - so what is being asserted is that the
    /// *switch* is what makes the mechanism inert, not an empty table that would leave the
    /// feature broken in a way turning the setting back on could not fix.
    @Test func nothingIsConcealedOnTheCardWhenTheSettingIsOff() throws {
        let card = try makeCard(Self.card, hidesMarkup: false, editable: true)

        #expect(card.coordinator.decorations.hiddenMarkerCount == 4)
        #expect(card.coordinator.decorations.hidesMarkup == false)
        for offset in [Self.headingParagraph, Self.listParagraph, Self.emphasisParagraph] {
            #expect(card.displayed(paragraphAt: offset) == nil, "nessuna sostituzione a \(offset)")
        }
    }

    /// The card must not invent a second switch: what it draws follows the vault's setting,
    /// which reaches it through the controller (`WorkspaceView.applyBoardSettings()`), and the
    /// controller's own starting value is the vault's default rather than a third opinion.
    @Test func theControllerCarriesTheVaultsSettingAndNotOneOfItsOwn() {
        #expect(WorkspaceController().hidesMarkup == VaultSettings.default.hidesMarkup)
    }

    // MARK: - R-11: teardown leaves nothing behind

    /// A card's text view is deallocated far more often than the editor's - once per card, and
    /// again every time a card crosses `BoardContentLayer.visibleNodes`' culling rect - so the
    /// two things it holds that outlive a view have to go: the undo actions targeting it
    /// (already the case, and re-asserted here so the addition below cannot quietly displace it)
    /// and the delegate's own tables, which are new with this task.
    @Test func dismantlingACardPurgesItsUndoActionsAndClearsTheDelegatesTables() throws {
        let card = try makeCard(Self.card, editable: true)
        let storage = try #require(card.textView.textStorage)
        let undoManager = card.coordinator.undoManager

        // The delegate's two tables are filled here by hand rather than by the styling walk, so
        // that this test answers for teardown alone and not for Task 5's other half: whatever
        // `applyStyling` and `applyReveal` end up handing the delegate, `dismantleNSView` has to
        // be able to let go of it.
        card.coordinator.decorations.apply(
            hiddenMarkers: [
                Self.headingParagraph: [HiddenMarker(range: NSRange(location: 0, length: 2), kind: .heading)]
            ],
            hidingMarkup: true
        )
        _ = card.coordinator.decorations.apply(revealedParagraphs: [Self.listParagraph])

        // Grouping by event closes a group at the end of a run loop iteration, and there is no
        // run loop turning here - so the group is opened and closed by hand and `canUndo` is a
        // deterministic answer rather than a race with the harness.
        undoManager.groupsByEvent = false
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: card.textView) { _ in }
        undoManager.registerUndo(withTarget: storage) { _ in }
        undoManager.endUndoGrouping()
        #expect(undoManager.canUndo, "premessa: il test deve partire da azioni davvero registrate")
        #expect(card.coordinator.decorations.hiddenMarkerCount == 1, "premessa: tabella piena")

        CardTextView.dismantleNSView(card.scrollView, coordinator: card.coordinator)

        #expect(!undoManager.canUndo, "nessuna azione può sopravvivere alla vista che ne è il target")
        #expect(card.coordinator.decorations.hiddenMarkerCount == 0, "la tabella dei marcatori è svuotata")
        // The reveal table has no count to read, so it is asked the one question it answers:
        // `apply(revealedParagraphs:)` returns what *changed*, so an empty answer to an empty set
        // means the set it replaced was already empty.
        #expect(
            card.coordinator.decorations.apply(revealedParagraphs: []).isEmpty,
            "la tabella dei paragrafi rivelati è svuotata"
        )
        #expect(card.displayed(paragraphAt: Self.headingParagraph) == nil, "niente da disegnare dopo lo smontaggio")
    }
}
