import AppKit
import Testing
@testable import Pergamenum

// ADR-0087 §D3 and §D8, plan docs/plans/note-workflow-n5.md, Task 3 (R-38).
//
// A callout is a card: its title line is drawn by a `CalloutTitleFragment`, its body lines by
// `QuoteBarFragment`s carrying the card's piece, a folded one leaves the layout through the hidden-line
// set folded headings use, and a Workspace card colours the title and conceals nothing on it.
//
// Layout of the folded note below, in UTF-16 offsets: `intro` at 0, the title line at 7, body lines at
// 27 and 33, `fine` at 40.

@Suite struct CalloutKindStyle {
    @Test func theFiveKindsMapToTheirOwnColourToken() { // R-35, R-38
        #expect(CalloutKind.note.colorToken == .calloutNote)
        #expect(CalloutKind.tip.colorToken == .calloutTip)
        #expect(CalloutKind.important.colorToken == .calloutImportant)
        #expect(CalloutKind.warning.colorToken == .calloutWarning)
        #expect(CalloutKind.caution.colorToken == .calloutCaution)
    }

    @Test func anUnknownTypeHasNoTokenSoItDrawsNeutral() { // R-38
        #expect(CalloutKind.other("faq").colorToken == nil)
        #expect(CalloutKind(keyword: "faq").colorToken == nil)
    }

    @Test func eachOfTheFiveKindsHasItsOwnSymbol() { // R-38
        let kinds: [CalloutKind] = [.note, .tip, .important, .warning, .caution]
        let symbols = kinds.map(\.symbolName)
        #expect(symbols.allSatisfy { !$0.isEmpty })
        #expect(Set(symbols).count == 5, "\(symbols)")
    }

    @Test func theCardIsTheTypeColourAtOneFixedOpacity() { // R-35
        #expect(CalloutStyle.backgroundOpacity == 0.08)
    }
}

@MainActor
@Suite struct CalloutDrawing {
    private static let folded = "intro\n\n> [!avviso]- Titolo\n> uno\n> due\n\nfine\n"
    private static let title = 7
    private static let firstBody = 27
    private static let secondBody = 33

    private static func titleFragment(_ built: N5Editor.Built, at offset: Int = title) -> CalloutTitleFragment? {
        N5Editor.fragments(built)[offset] as? CalloutTitleFragment
    }

    /// An editor with the callout toggle wired, as the note editor's column wires it, and the fold pass
    /// run: the chevron and the fold are decided there (a callout folds only where it can be opened).
    private static func wired(_ text: String, caret: Int) -> N5Editor.Built {
        let built = N5Editor.build(text, caret: caret, outline: .init(onToggleCallout: { _ in }))
        built.coordinator.applyFolding(to: built.textView, folded: [], theme: built.theme)
        return built
    }

    // MARK: The title line

    @Test func aFoldedCalloutsTitleIsACalloutTitleFragmentOfItsKindAndFoldState() throws { // R-38
        let built = Self.wired(Self.folded, caret: 0)
        let fragment = try #require(Self.titleFragment(built))
        #expect(fragment.kind == .warning)
        #expect(fragment.isFolded == true)
        #expect(fragment.calloutOffset == Self.title)
    }

    @Test func aPlusCalloutStartsOpenAndAFixedOneIsNotFoldable() throws { // R-38
        let open = Self.wired("intro\n\n> [!tip]+ T\n> a\n", caret: 0)
        #expect(try #require(Self.titleFragment(open)).isFolded == false)
        let fixed = Self.wired("intro\n\n> [!tip] T\n> a\n", caret: 0)
        #expect(try #require(Self.titleFragment(fixed)).isFolded == nil)
    }

    @Test func theTitleLineKeepsItsStoredLengthOnceDisplayed() { // R-38
        for caret in [0, 12] {
            let built = N5Editor.build(Self.folded, caret: caret)
            let lengths = N5Editor.lengths(built, at: Self.title)
            #expect(lengths.displayed == lengths.stored, "caret \(caret): \(lengths)")
        }
    }

    // MARK: Folding

    @Test func aFoldedCalloutsBodyLeavesTheLayoutThroughTheHiddenLineSet() {
        // R-38
        let built = Self.wired(Self.folded, caret: 0)

        #expect(built.coordinator.folding.lastFoldLayout.hiddenLineOffsets == [Self.firstBody, Self.secondBody])
        let fragments = N5Editor.fragments(built)
        #expect(fragments[Self.firstBody] == nil, "il corpo è ancora nel layout")
        #expect(fragments[Self.secondBody] == nil, "il corpo è ancora nel layout")
        #expect(fragments[Self.title] != nil)
        #expect(fragments[40] != nil, "il testo dopo il callout deve restare")
    }

    @Test func aCaretInAHiddenBodyLineIsRescuedToTheTitleLine() {
        // R-38
        let built = Self.wired(Self.folded, caret: Self.firstBody + 3)

        let caret = built.textView.selectedRange().location
        #expect(caret >= Self.title && caret < Self.firstBody, "caret a \(caret)")
    }

    /// The Diario and Oggi editors wire no toggle: a folded body would be hidden with no chevron to open it.
    @Test func aCalloutWithNoToggleWiredStaysOpenAndDrawsNoChevron() throws { // R-38
        let built = N5Editor.build(Self.folded, caret: 0)
        built.coordinator.applyFolding(to: built.textView, folded: [], theme: built.theme)

        #expect(built.coordinator.folding.lastFoldLayout.hiddenLineOffsets.isEmpty)
        #expect(try #require(Self.titleFragment(built)).isFolded == nil)
        let fragments = N5Editor.fragments(built)
        #expect(fragments[Self.firstBody] != nil, "il corpo deve restare visibile")
        #expect(fragments[Self.secondBody] != nil, "il corpo deve restare visibile")
    }

    /// The chevron is a fragment of the hidden-markup path, so with `hidesMarkup` off nothing could open a fold.
    @Test func aCalloutWithMarkupShownStaysOpenEvenWithAToggleWired() {  // R-38
        let built = N5Editor.build(Self.folded, hidesMarkup: false, caret: 0, outline: .init(onToggleCallout: { _ in }))
        built.coordinator.applyFolding(to: built.textView, folded: [], theme: built.theme)
        #expect(built.coordinator.folding.lastFoldLayout.hiddenLineOffsets.isEmpty)
    }

    @Test func anOpenCalloutHidesNothing() { // R-38
        let built = N5Editor.build("intro\n\n> [!note] T\n> a\n> b\n", caret: 0)
        built.coordinator.applyFolding(to: built.textView, folded: [], theme: built.theme)
        #expect(built.coordinator.folding.lastFoldLayout.hiddenLineOffsets.isEmpty)
    }

    // MARK: Body lines

    @Test func theBodyLinesOfAnOpenCalloutAreQuoteBarsWithFirstMiddleAndLast() throws { // R-38
        let built = N5Editor.build("intro\n\n> [!note] T\n> a\n> b\n> c\n", caret: 0)
        let fragments = N5Editor.fragments(built)
        let pieces = try [19, 23, 27].map { offset -> CalloutPiece? in
            let bar = try #require(fragments[offset] as? QuoteBarFragment, "nessuna QuoteBarFragment a \(offset)")
            #expect(bar.callout?.kind == .note)
            return bar.callout?.piece
        }
        #expect(pieces == [.first, .middle, .last])
    }

    @Test func aOneLineBodyIsTheOnlyPiece() throws { // R-38
        let built = N5Editor.build("intro\n\n> [!note] T\n> a\n\nfine\n", caret: 0)
        let bar = try #require(N5Editor.fragments(built)[19] as? QuoteBarFragment)
        #expect(bar.callout?.piece == CalloutPiece.only)
    }

    @Test func anOrdinaryQuoteCarriesNoCalloutPiece() throws { // R-39
        let built = N5Editor.build("intro\n\n> uno\n> due\n", caret: 0)
        let bar = try #require(N5Editor.fragments(built)[7] as? QuoteBarFragment)
        #expect(bar.callout == nil)
    }

    // MARK: A Workspace card

    @Test func aCardColoursACalloutsTitleInItsTypeColourAndConcealsNothingOnIt() throws { // R-38
        let note = "> [!warning] Titolo\n> corpo\n"
        let theme = Theme.emergency
        let view = CardTextView(
            text: .constant(note), theme: theme, style: CardTextStyle(color: nil, alignment: nil),
            isEditable: false, hidesMarkup: true, revealsInlineSpans: false
        )
        let coordinator = view.makeCoordinator()
        let scrollView = FormattingTextView.scrollableTextView()
        let textView = try #require(scrollView.documentView as? FormattingTextView)
        textView.delegate = coordinator
        textView.textContentStorage?.delegate = coordinator.decorations
        textView.textLayoutManager?.delegate = coordinator.decorations
        textView.string = note
        coordinator.configure(textView, editable: false)
        coordinator.applyStyling(to: textView)

        let storage = try #require(textView.textStorage)
        let titleOffset = (note as NSString).range(of: "Titolo").location
        let bodyOffset = (note as NSString).range(of: "corpo").location
        let kindColor = NSColor(theme.color(.calloutWarning))
        #expect(storage.attribute(.foregroundColor, at: titleOffset, effectiveRange: nil) as? NSColor == kindColor)
        #expect(storage.attribute(.foregroundColor, at: bodyOffset, effectiveRange: nil) as? NSColor != kindColor)

        // Nothing is concealed on the title line: no marker is recorded for its paragraph.
        #expect((coordinator.decorations.hiddenMarkers[0] ?? []).isEmpty)
        #expect((coordinator.hiddenMarkers[0] ?? []).isEmpty)
    }
}
