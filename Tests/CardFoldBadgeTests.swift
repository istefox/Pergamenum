import AppKit
import Foundation
import Testing
@testable import Pergamenum

// PG-357, PG-358, PG-359: three defects found by hand on a Workspace text card.
//
// PG-357: the fold badge did nothing on a card at rest, because `claimsFoldBadge(at:)` was gated
// on `isEditable`. PG-358: the badge sat on the heading's baseline instead of beside its glyphs,
// because it measured the font at the line's first character, which with markup concealed is the
// hidden `# ` marker's near-zero face. PG-359: the tray's «Note referenziate» listed a note twice
// when a `.file` card and a `[[wikilink]]` named it.
//
// Driven through a real `FormattingTextView` offscreen, wired as `Tests/CardFoldTests.swift`
// wires one, because both badge defects live in TextKit 2 geometry and nowhere else.

@MainActor
@Suite struct CardFoldBadge {
    private static let text = "# Uno\ncorpo uno\ncorpo due\n## Sotto\nx"

    private static func card(editable: Bool, onToggleFold: @escaping (Int) -> Void) throws
        -> (FormattingTextView, CardTextView.Coordinator) {
        let view = CardTextView(
            text: .constant(text),
            theme: .emergency,
            style: CardTextStyle(color: nil, alignment: nil),
            isEditable: editable,
            hidesMarkup: true
        )
        let coordinator = view.makeCoordinator()
        let scrollView = FormattingTextView.scrollableTextView()
        let textView = try #require(scrollView.documentView as? FormattingTextView)
        textView.delegate = coordinator
        textView.textContentStorage?.delegate = coordinator.decorations
        textView.textLayoutManager?.delegate = coordinator.decorations
        textView.string = text
        coordinator.configure(textView, editable: editable)
        coordinator.applyStyling(to: textView)
        textView.onToggleFold = onToggleFold
        let layout = NoteFolding.layout(in: text, foldedEntries: [0])
        coordinator.decorations.apply(
            hiddenLines: layout.hiddenLineOffsets, foldedHeadings: layout.foldedHeadings
        )
        textView.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        textView.textContainer?.size = CGSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        let manager = try #require(textView.textLayoutManager)
        manager.invalidateLayout(for: manager.documentRange)
        manager.ensureLayout(for: manager.documentRange)
        return (textView, coordinator)
    }

    private static func folded(in textView: NSTextView) -> FoldedHeadingFragment? {
        guard let manager = textView.textLayoutManager else { return nil }
        var found: FoldedHeadingFragment?
        manager.enumerateTextLayoutFragments(
            from: manager.documentRange.location, options: [.ensuresLayout]
        ) {
            found = $0 as? FoldedHeadingFragment
            return found == nil
        }
        return found
    }

    /// The badge in the view's coordinates, which is what a click carries.
    private static func badge(in textView: NSTextView) throws -> CGRect {
        let frame = try #require(folded(in: textView)).badgeFrameInContainer
        let origin = textView.textContainerOrigin
        return frame.offsetBy(dx: origin.x, dy: origin.y)
    }

    // MARK: - PG-357

    @Test func aClickOnTheBadgeOfACardAtRestOpensItsSection() throws {
        var toggled: Int?
        let (textView, _) = try Self.card(editable: false) { toggled = $0 }
        #expect(!textView.isEditable)

        let box = try Self.badge(in: textView)
        #expect(textView.claimsFoldBadge(at: CGPoint(x: box.midX, y: box.midY)))
        #expect(toggled == 0)
    }

    @Test func aClickBesideTheBadgeOfACardAtRestStaysWithTheBoard() throws {
        // The trade-off PG-074 took for the checkbox: only the drawn badge is claimed, every
        // other point of a resting card goes on to the board's own gestures.
        var toggled: Int?
        let (textView, _) = try Self.card(editable: false) { toggled = $0 }

        let box = try Self.badge(in: textView)
        #expect(!textView.claimsFoldBadge(at: CGPoint(x: box.maxX + 40, y: box.midY)))
        #expect(!textView.claimsFoldBadge(at: CGPoint(x: box.midX, y: box.maxY + 40)))
        #expect(toggled == nil)
    }

    // MARK: - PG-358

    @Test func theBadgeIsCentredOnTheHeadingGlyphsNotOnItsBaseline() throws {
        let (textView, _) = try Self.card(editable: false) { _ in }
        let fragment = try #require(Self.folded(in: textView))
        let line = try #require(fragment.textLineFragments.first)

        // The heading's face read off its last character, never off the concealed marker.
        let string = line.attributedString
        let lastIndex = line.characterRange.upperBound - 1
        let heading = try #require(string.attribute(.font, at: lastIndex, effectiveRange: nil) as? NSFont)
        #expect(heading.pointSize > 1)

        let baseline = fragment.layoutFragmentFrame.minY + line.typographicBounds.minY + line.glyphOrigin.y
        let capMiddle = baseline - heading.capHeight / 2
        let badge = fragment.badgeFrameInContainer
        // Before PG-358 the badge's middle sat on the baseline, half a cap height too low.
        #expect(abs(badge.midY - capMiddle) < heading.capHeight / 4)
        #expect(badge.midY < baseline - heading.capHeight / 4)
    }
}

// MARK: - PG-359

@Test func aNoteNamedByACardAndByAWikilinkIsListedOnce() {
    let document = CanvasDocument(nodes: [
        CanvasNode(id: "a", kind: .file(path: "Prova/Brief.md", subpath: nil), x: 0, y: 0, width: 100, height: 100),
        CanvasNode(
            id: "b", kind: .text("Vedi [[Brief]] e [[Altro]] e [[Mancante]]"),
            x: 0, y: 0, width: 100, height: 100
        ),
    ])
    let paths = ["Prova/Brief.md": "Prova/Brief.md", "Brief": "Prova/Brief.md", "Altro": "Altro.md"]

    let notes = WorkspaceReferences.collapsing(WorkspaceReferences.notes(in: document)) { paths[$0] }

    // The card's own spelling wins, being first in the board's order; an unresolved link stays.
    #expect(notes == ["Prova/Brief.md", "Altro", "Mancante"])
}

@Test func twoUnresolvedLinksAreNeverCollapsedIntoEachOther() {
    let notes = WorkspaceReferences.collapsing(["Uno", "Due", "Uno"]) { _ in nil }

    #expect(notes == ["Uno", "Due"])
}
