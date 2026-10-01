import AppKit
import Testing
@testable import Pergamenum

// ADR-0076 §D9 (PG-338), plan docs/plans/pratiche-message-anchored-entries.md, Task 7 - R-20.
//
// The Pratiche anchor line in the editor: one `.messageAnchor` span over the whole line, and,
// with «Nascondi markup» on, the line collapsed on ADR-0029's whole-line path and drawn by a
// `MessageAnchorFragment` - the horizontal rule's shape (`MarkupHidingRule`), line for line.

@Suite struct MessageAnchorStyling {
    private static let anchor = "<!-- pergamenum-message: <a1@example.com> -->"

    @Test func anAnchorLineIsOneMessageAnchorSpanOverTheWholeLine() {
        let note = "## 2026-09-30 10:00 Nota · Mario\n\(Self.anchor)\ncorpo\n"
        #expect(MarkdownStylerFixture.styled(note, .messageAnchor) == Self.anchor)
        #expect(MarkdownStylerFixture.spans(note).filter { $0 == .messageAnchor }.count == 1)
    }

    @Test func surroundingWhitespaceStaysInsideTheSpan() {
        let line = "  \(Self.anchor)  "
        #expect(MarkdownStylerFixture.styled(line, .messageAnchor) == line)
    }

    @Test func theAnchorLineYieldsNoOtherSpan() {
        // The id's `<`, `@` and the comment's `-->` must not be read as any other construct.
        #expect(MarkdownStylerFixture.spans(Self.anchor) == [.messageAnchor])
    }

    @Test(arguments: [
        "<!-- pergamenum-message:  -->",
        "<!-- pergamenum-message: <a1@example.com>",
        "<!-- altro: <a1@example.com> -->",
        "testo <!-- pergamenum-message: <a1@example.com> -->",
    ])
    func aNearMissIsNoAnchor(line: String) {
        #expect(!MarkdownStylerFixture.spans(line).contains(.messageAnchor))
    }

    @Test func aMessageIDIsNotSpellChecked() {
        #expect(MarkdownStyler.suppressesSpellCheck(.messageAnchor))
    }
}

@MainActor
@Suite struct MessageAnchorHiding {
    private static let line = "<!-- pergamenum-message: <a1@example.com> -->"
    private static let note = "\(line)\ncorpo\n"
    private static let marker = HiddenMarker(
        range: NSRange(location: 0, length: (line as NSString).length), kind: .messageAnchor
    )

    @Test func anAnchorParagraphCollapsesEntirelyIntoTheCollapsedFontAndKeepsItsLength() {
        let displayed = MarkupHidingFixture.displayedParagraph(Self.note, markers: [Self.marker])
        #expect(displayed != nil, "nessuna sostituzione")
        #expect(displayed?.attributedString.length == MarkupHidingFixture.firstParagraphLength(of: Self.note))
        for offset in 0..<(Self.line as NSString).length {
            #expect(
                (displayed?.attributedString.attribute(.font, at: offset, effectiveRange: nil) as? NSFont)
                    == EditorDecorationDelegate.collapsedFont,
                "offset \(offset) non è nel font collassato"
            )
        }
    }

    @Test func anAnchorParagraphIsLaidOutAsAMessageAnchorFragment() {
        let laidOut = MarkupHidingFixture.fragments(text: Self.note, markers: [0: [Self.marker]], hidesMarkup: true)
        #expect(laidOut[0] is MessageAnchorFragment)
    }

    @Test func theHookReturnsNilForARevealedAnchorParagraph() {
        #expect(MarkupHidingFixture.displayedParagraph(Self.note, markers: [Self.marker], revealed: [0]) == nil)
    }

    @Test func theAnchorHookIsInertWhenTheSettingIsOff() {
        #expect(MarkupHidingFixture.displayedParagraph(Self.note, markers: [Self.marker], hidesMarkup: false) == nil)
        let laidOut = MarkupHidingFixture.fragments(text: Self.note, markers: [0: [Self.marker]], hidesMarkup: false)
        #expect(!(laidOut[0] is MessageAnchorFragment))
    }

    @Test func aStaleAnchorEntryDoesNotCollapseProse() {
        let prose = "corpo della voce che non è un'ancora\ndopo\n"
        #expect(MarkupHidingFixture.displayedParagraph(prose, markers: [Self.marker]) == nil)
        let laidOut = MarkupHidingFixture.fragments(text: prose, markers: [0: [Self.marker]], hidesMarkup: true)
        #expect(!(laidOut[0] is MessageAnchorFragment))
    }
}

// The real line-to-concealment path, unlike `MessageAnchorHiding` above, which builds its
// `HiddenMarker` by hand: a note styled by the real `NoteTextView.Coordinator` must hand the
// delegate a `.messageAnchor` marker (`hiddenKind(for:)`'s arm), and a Workspace card styled by
// the real `CardTextView.Coordinator` must hand it none, since its own kind mapping ends in
// `default: nil` (ADR-0029 §D17).
@MainActor
@Suite struct MessageAnchorWiring {
    private static let line = "<!-- pergamenum-message: <a1@example.com> -->"
    private static let heading = "## 2026-09-30 10:00 Nota · Mario\n"
    private static let note = "\(heading)\(line)\ncorpo\n"
    private static let anchorParagraph = (heading as NSString).length

    @Test func theNoteEditorsStylingPassMarksTheAnchorLineAsAMessageAnchor() {
        let view = NoteTextView(
            text: .constant(Self.note), theme: .emergency, noteTitles: [], tagSuggestions: [],
            hidesMarkup: true, onFollowLink: { _ in }
        )
        let coordinator = view.makeCoordinator()
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.delegate = coordinator
        textView.textContentStorage?.delegate = coordinator.decorations
        textView.string = Self.note
        coordinator.applyStyling(to: textView, theme: .emergency)

        let markers = coordinator.decorations.hiddenMarkers
        #expect(
            markers[Self.anchorParagraph] == [
                HiddenMarker(range: NSRange(location: 0, length: (Self.line as NSString).length), kind: .messageAnchor)
            ]
        )
        #expect(markers.values.joined().filter { $0.kind == .messageAnchor }.count == 1)
    }

    @Test func aWorkspaceCardNeverProducesAMessageAnchorMarker() throws {
        let view = CardTextView(
            text: .constant(Self.note),
            theme: .emergency,
            style: CardTextStyle(color: nil, alignment: nil),
            isEditable: false,
            hidesMarkup: true,
            revealsInlineSpans: false
        )
        let coordinator = view.makeCoordinator()
        let scrollView = FormattingTextView.scrollableTextView()
        let textView = try #require(scrollView.documentView as? FormattingTextView)
        textView.delegate = coordinator
        textView.textContentStorage?.delegate = coordinator.decorations
        textView.textLayoutManager?.delegate = coordinator.decorations
        textView.string = Self.note
        coordinator.configure(textView, editable: false)
        coordinator.applyStyling(to: textView)

        #expect(!coordinator.hiddenMarkers.values.joined().contains { $0.kind == .messageAnchor })
        #expect(!coordinator.decorations.hiddenMarkers.values.joined().contains { $0.kind == .messageAnchor })
        #expect(coordinator.hiddenMarkers[Self.anchorParagraph] == nil)
    }
}

// The marker drawn whole: with «Nascondi markup» on, the anchor row is only a few points tall, and
// a rendering surface sized to the row clipped the envelope to a 2-3 px sliver (PG-338's visual
// check). The row here is collapsed newline included, the shape the editor actually lays out.
@MainActor
@Suite struct MessageAnchorMarkerBounds {
    private static let line = "<!-- pergamenum-message: <a1@example.com> -->"

    private static func collapsedAnchorFragment() throws -> MessageAnchorFragment {
        let content = NSTextContentStorage()
        let layout = NSTextLayoutManager()
        content.addTextLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.textContainer = container

        let marker = HiddenMarker(range: NSRange(location: 0, length: (line as NSString).length), kind: .messageAnchor)
        let delegate = EditorDecorationDelegate()
        delegate.apply(hiddenMarkers: [0: [marker]], hidingMarkup: true)
        content.delegate = delegate
        layout.delegate = delegate

        let text = NSMutableAttributedString(
            string: "\(line)\n", attributes: [.font: EditorDecorationDelegate.collapsedFont]
        )
        text.append(NSAttributedString(
            string: "corpo\n", attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)]
        ))
        content.textStorage?.setAttributedString(text)
        layout.ensureLayout(for: layout.documentRange)

        var first: NSTextLayoutFragment?
        layout.enumerateTextLayoutFragments(from: layout.documentRange.location, options: [.ensuresLayout]) {
            first = $0
            return false
        }
        return try #require(first as? MessageAnchorFragment)
    }

    @Test func theRenderingSurfaceHoldsTheWholeEnvelopeOverACollapsedRow() throws {
        let fragment = try Self.collapsedAnchorFragment()
        let marker = fragment.markerFrame
        try #require(!marker.isNull)
        // The precondition the defect needs: the envelope is taller than the row it sits on.
        #expect(fragment.layoutFragmentFrame.height < marker.height)
        #expect(fragment.renderingSurfaceBounds.contains(marker))
    }

    @Test func theEnvelopeIsCentredOnTheRowAndStartsAtItsLeadingEdge() throws {
        let fragment = try Self.collapsedAnchorFragment()
        let marker = fragment.markerFrame
        #expect(marker.minX == 0)
        #expect(abs(marker.midY - fragment.layoutFragmentFrame.height / 2) < 0.001)
    }
}
