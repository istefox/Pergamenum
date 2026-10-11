import AppKit
import Testing
@testable import Pergamenum

// ADR-0082 §D8, plan docs/plans/pg-385-n2-page.md, Task 2 (PG-385, R-19).
//
// Workspace cards conceal quote and rule markers; tables, view blocks and message anchors stay
// out of cards (ADR-0029 §D17's `default: nil`). The card fixture is `CardConcealmentTests`' own,
// copied rather than imported on this repo's per-file-fixture convention. The quote and rule tests
// are red until Task 4 maps `.blockquoteMarker` and `.horizontalRule` in `CardTextView.hiddenKind`;
// the three "stays out" tests are green guards that must stay green after it.

@MainActor
private struct Card {
    let scrollView: NSScrollView
    let textView: FormattingTextView
    let coordinator: CardTextView.Coordinator

    /// What the delegate hands back for the paragraph containing `offset`, asked as AppKit asks it
    /// during a layout pass: `nil` is "draw the stored paragraph as it is".
    func displayed(paragraphAt offset: Int) -> NSTextParagraph? {
        guard let storage = textView.textContentStorage else { return nil }
        let range = (textView.string as NSString).paragraphRange(for: NSRange(location: offset, length: 0))
        return coordinator.decorations.textContentStorage(storage, textParagraphWith: range)
    }

    /// Every paragraph's start offset in the text.
    var paragraphStarts: [Int] {
        let text = textView.string as NSString
        var starts: [Int] = []
        var index = 0
        while index < text.length {
            starts.append(index)
            index = NSMaxRange(text.paragraphRange(for: NSRange(location: index, length: 0)))
        }
        return starts
    }

    /// The layout fragments, keyed by their paragraph's offset, from the card's own layout manager.
    func fragments() -> [Int: NSTextLayoutFragment] {
        guard let layout = textView.textLayoutManager, let content = layout.textContentManager else { return [:] }
        layout.ensureLayout(for: layout.documentRange)
        var byOffset: [Int: NSTextLayoutFragment] = [:]
        layout.enumerateTextLayoutFragments(from: layout.documentRange.location, options: [.ensuresLayout]) { fragment in
            byOffset[content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)] = fragment
            return true
        }
        return byOffset
    }

    var allMarkers: [HiddenMarker] { coordinator.hiddenMarkers.values.flatMap { $0 } }
}

@MainActor
private func makeCard(_ text: String, alignment: CardTextStyle.Alignment? = nil, editable: Bool = false) throws -> Card {
    let view = CardTextView(
        text: .constant(text),
        theme: .emergency,
        style: CardTextStyle(color: nil, alignment: alignment),
        isEditable: editable,
        hidesMarkup: true,
        revealsInlineSpans: false
    )
    let coordinator = view.makeCoordinator()
    let scrollView = FormattingTextView.scrollableTextView()
    let textView = try #require(
        scrollView.documentView as? FormattingTextView,
        "scrollableTextView() must hand back an instance of the receiving class"
    )
    scrollView.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
    textView.frame = scrollView.frame
    textView.textContainer?.size = CGSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
    textView.delegate = coordinator
    textView.textContentStorage?.delegate = coordinator.decorations
    textView.textLayoutManager?.delegate = coordinator.decorations
    textView.string = text
    coordinator.configure(textView, editable: editable)
    coordinator.applyStyling(to: textView)
    textView.setSelectedRange(NSRange(location: 0, length: 0))
    return Card(scrollView: scrollView, textView: textView, coordinator: coordinator)
}

@MainActor
@Suite struct CardBlockMarkers {
    // MARK: Red until Task 4

    // (n2-page R-19) A quote at rest is drawn with bars where its `>` were, one bar per `>`.
    @Test func aQuoteAtRestIsSubstitutedWithBars() throws {
        let card = try makeCard("> citato\naltro")

        let displayed = try #require(card.displayed(paragraphAt: 0), "the quote paragraph is not substituted")
        #expect(displayed.attributedString.string.hasPrefix(String(EditorDecorationDelegate.quoteBar)))
        #expect(displayed.attributedString.length == ("> citato\n" as NSString).length, "the substitution keeps the length")
        #expect(card.allMarkers.contains { $0.kind == .blockquote })
    }

    // (n2-page R-19) Two levels, two bars. The two levels are spelled `>>`: the shared grammar,
    // and the old styler before it, count the `>` of one unbroken run, so `> > x` is a level-1 quote
    // whose text starts with `> ` (corpus S13 vs S14). The test first wrote `> > dentro`; that read
    // a nesting syntax neither SPEC R-19 nor the plan asked the grammar to learn.
    @Test func aNestedQuoteGetsOneBarPerLevel() throws {
        let card = try makeCard(">> dentro\naltro")

        let displayed = try #require(card.displayed(paragraphAt: 0))
        #expect(displayed.attributedString.string.hasPrefix(String(repeating: String(EditorDecorationDelegate.quoteBar), count: 2)))
        #expect(displayed.attributedString.length == (">> dentro\n" as NSString).length, "the substitution keeps the length")
    }

    // (n2-page R-19) `> > x` is one level: one bar, the second `>` stays text (corpus S13). Pins the
    // card to the grammar the Note pane uses.
    @Test func aSpacedPairOfQuoteMarksIsOneLevelInACardAsInTheNotePane() throws {
        let card = try makeCard("> > dentro\naltro")

        let displayed = try #require(card.displayed(paragraphAt: 0))
        let text = displayed.attributedString.string
        #expect(text.hasPrefix(String(EditorDecorationDelegate.quoteBar)))
        #expect(!text.hasPrefix(String(repeating: String(EditorDecorationDelegate.quoteBar), count: 2)))
    }

    // (n2-page R-19) A rule's layout fragment is a `HorizontalRuleFragment`.
    @Test func aRuleIsLaidOutAsAHorizontalRuleFragment() throws {
        let text = "sopra\n\n---\n\nsotto"
        let card = try makeCard(text)
        let offset = (text as NSString).range(of: "---").location

        #expect(card.allMarkers.contains { $0.kind == .rule })
        #expect(card.fragments()[offset] is HorizontalRuleFragment, "the rule at \(offset) is a plain fragment")
    }

    // (n2-page R-19, G0 item 4) A card keeps its own paragraph style: an aligned card's concealed
    // quote stays aligned and adds no page line height.
    @Test func anAlignedCardsConcealedQuoteKeepsItsAlignmentAndAddsNoLineHeight() throws {
        let card = try makeCard("> citato\naltro", alignment: .center)

        let displayed = try #require(card.displayed(paragraphAt: 0), "the quote paragraph is not substituted")
        let style = try #require(
            displayed.attributedString.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        )
        #expect(style.alignment == .center)
        #expect(style.lineHeightMultiple == 0, "the quote carries a line height multiple of \(style.lineHeightMultiple)")
    }

    // MARK: Green guards: what stays out of a card

    // (n2-page R-19) A table is not concealed in a card (`default: nil`).
    @Test func aTableIsStillNotConcealed() throws {
        let card = try makeCard("| a | b |\n|---|---|\n| 1 | 2 |\n")

        #expect(!card.allMarkers.contains { $0.kind == .table || $0.kind == .rule }, "\(card.allMarkers)")
        for start in card.paragraphStarts {
            #expect(card.displayed(paragraphAt: start) == nil, "paragraph at \(start) is substituted")
        }
    }

    // (n2-page R-19) A view block is not concealed in a card.
    @Test func aViewBlockIsStillNotConcealed() throws {
        let card = try makeCard("```pergamenum-view\nrender: list\n```\n")

        #expect(!card.allMarkers.contains { $0.kind == .viewBlock }, "\(card.allMarkers)")
        for start in card.paragraphStarts {
            #expect(card.displayed(paragraphAt: start) == nil, "paragraph at \(start) is substituted")
        }
    }

    // (n2-page R-19) A message anchor is not concealed in a card.
    @Test func aMessageAnchorIsStillNotConcealed() throws {
        let anchor = try #require(PraticaEntryAnchor.line(for: "abc@example.com"))
        let card = try makeCard("\(anchor)\ntesto\n")

        #expect(!card.allMarkers.contains { $0.kind == .messageAnchor }, "\(card.allMarkers)")
        #expect(card.displayed(paragraphAt: 0) == nil)
    }
}
