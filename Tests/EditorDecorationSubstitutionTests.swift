import AppKit
import Testing
@testable import Pergamenum

/// PG-144 Task 3 (ADR-0074 §D8, last paragraph): direct tests of the delegate's two shared
/// substitution helpers, `marker(of:at:)` and `substituteAttachment(_:over:in:)`.
@MainActor
@Suite struct EditorDecorationSubstitution {
    private static func delegate(_ markers: [HiddenMarker], at location: Int = 0) -> EditorDecorationDelegate {
        let delegate = EditorDecorationDelegate()
        delegate.apply(hiddenMarkers: [location: markers], hidingMarkup: true)
        return delegate
    }

    private static func fonts(of copy: NSAttributedString) -> [NSFont?] {
        (0 ..< copy.length).map { copy.attribute(.font, at: $0, effectiveRange: nil) as? NSFont }
    }

    // MARK: marker(of:at:)

    @Test func aMarkerThatFitsTheParagraphIsReturned() {
        let marker = HiddenMarker(range: NSRange(location: 2, length: 3), kind: .table)
        let delegate = Self.delegate([marker], at: 10)

        #expect(delegate.marker(of: .table, at: NSRange(location: 10, length: 5)) == marker)
    }

    @Test func aMarkerPastTheParagraphEndIsRefused() {
        let marker = HiddenMarker(range: NSRange(location: 2, length: 4), kind: .table)
        let delegate = Self.delegate([marker])

        #expect(delegate.marker(of: .table, at: NSRange(location: 0, length: 5)) == nil)
    }

    @Test func aMarkerEndingExactlyAtTheParagraphEndIsReturned() {
        let marker = HiddenMarker(range: NSRange(location: 2, length: 3), kind: .viewBlock)
        let delegate = Self.delegate([marker])

        #expect(delegate.marker(of: .viewBlock, at: NSRange(location: 0, length: 5)) == marker)
    }

    @Test func aZeroLengthMarkerIsReturnedAndTheCallersGuardDecides() {
        let marker = HiddenMarker(range: NSRange(location: 0, length: 0), kind: .table)
        let delegate = Self.delegate([marker])

        #expect(delegate.marker(of: .table, at: NSRange(location: 0, length: 4)) == marker)
    }

    @Test func onlyTheAskedKindIsReturned() {
        let quote = HiddenMarker(range: NSRange(location: 0, length: 2), kind: .blockquote)
        let bold = HiddenMarker(range: NSRange(location: 3, length: 2), kind: .emphasis)
        let delegate = Self.delegate([bold, quote])

        #expect(delegate.marker(of: .blockquote, at: NSRange(location: 0, length: 10)) == quote)
        #expect(delegate.marker(of: .list, at: NSRange(location: 0, length: 10)) == nil)
    }

    @Test func aParagraphWithNoRecordedMarkersAnswersNil() {
        let delegate = Self.delegate([HiddenMarker(range: NSRange(location: 0, length: 2), kind: .table)])

        #expect(delegate.marker(of: .table, at: NSRange(location: 7, length: 10)) == nil)
    }

    /// No fallthrough: the first marker of the kind decides. When it runs past the paragraph
    /// the lookup refuses, even though a later marker of the same kind would have fit - the
    /// pre-helper branches read `first(where:)` and then checked the fit, and so does this.
    @Test func aFirstMarkerPastTheParagraphEndRefusesEvenWhenALaterOneFits() {
        let first = HiddenMarker(range: NSRange(location: 2, length: 4), kind: .table)
        let second = HiddenMarker(range: NSRange(location: 0, length: 2), kind: .table)
        let delegate = Self.delegate([first, second])

        #expect(delegate.marker(of: .table, at: NSRange(location: 0, length: 5)) == nil)
    }

    @Test func whenTwoMarkersOfTheKindBothFitTheFirstIsReturned() {
        let first = HiddenMarker(range: NSRange(location: 2, length: 2), kind: .table)
        let second = HiddenMarker(range: NSRange(location: 0, length: 2), kind: .table)
        let delegate = Self.delegate([first, second])

        #expect(delegate.marker(of: .table, at: NSRange(location: 0, length: 5)) == first)
    }

    // MARK: substituteAttachment(_:over:in:)

    @Test func theSubstitutionKeepsTheParagraphLength() {
        let copy = NSMutableAttributedString(string: "| a | b |\n")
        let before = copy.length
        let marker = HiddenMarker(range: NSRange(location: 0, length: 9), kind: .table)

        EditorDecorationDelegate.substituteAttachment(NSTextAttachment(), over: marker, in: copy)

        #expect(copy.length == before)
    }

    @Test func theFirstCharacterBecomesTheAttachmentCharacterCarryingTheAttachment() {
        let copy = NSMutableAttributedString(string: "xx| a |\n")
        let attachment = NSTextAttachment()
        let marker = HiddenMarker(range: NSRange(location: 2, length: 5), kind: .table)

        EditorDecorationDelegate.substituteAttachment(attachment, over: marker, in: copy)

        #expect((copy.string as NSString).substring(with: NSRange(location: 2, length: 1)) == "\u{FFFC}")
        #expect(copy.attribute(.attachment, at: 2, effectiveRange: nil) as? NSTextAttachment === attachment)
        #expect(copy.attribute(.attachment, at: 1, effectiveRange: nil) == nil)
        #expect(copy.attribute(.attachment, at: 3, effectiveRange: nil) == nil)
    }

    @Test func theRestOfALongerMarkerCollapsesAndNothingElseDoes() {
        let copy = NSMutableAttributedString(string: "xx| a |yy\n")
        let marker = HiddenMarker(range: NSRange(location: 2, length: 5), kind: .table)

        EditorDecorationDelegate.substituteAttachment(NSTextAttachment(), over: marker, in: copy)

        let fonts = Self.fonts(of: copy)
        for index in 3 ..< 7 { #expect(fonts[index] === EditorDecorationDelegate.collapsedFont) }
        for index in [0, 1, 2, 7, 8, 9] { #expect(fonts[index] !== EditorDecorationDelegate.collapsedFont) }
    }

    @Test func aOneCharacterMarkerCollapsesNothing() {
        let copy = NSMutableAttributedString(string: "x|y\n")
        let marker = HiddenMarker(range: NSRange(location: 1, length: 1), kind: .embed)

        EditorDecorationDelegate.substituteAttachment(NSTextAttachment(), over: marker, in: copy)

        #expect(copy.length == 4)
        #expect((copy.string as NSString).substring(with: NSRange(location: 1, length: 1)) == "\u{FFFC}")
        #expect(Self.fonts(of: copy).allSatisfy { $0 !== EditorDecorationDelegate.collapsedFont })
    }
}

// MARK: - N5 Task 3 (ADR-0087, plan `note-workflow-n5.md`): every new branch keeps the paragraph length

/// Each of ADR-0087's new substitutions collapses characters and replaces none, because the displayed
/// paragraph must be as long as the stored one (`NSTextContentManager.h:120`). Driven with hand-built
/// markers, the way `MarkupHidingRule` drives the rule: the delegate must serve the marker (a non-nil
/// paragraph), keep its length, and give the paragraph back untouched when the caret reveals it. Red
/// until Tasks 4 to 7 give each kind a re-validation and a branch (today `stillSpells` refuses all six).
@MainActor
@Suite struct EditorDecorationNewSubstitutions {
    struct Case: CustomStringConvertible, Sendable {
        let name: String
        let note: String
        let at: Int
        let markers: [HiddenMarker]
        let collapsed: [Int]
        var description: String { name }
    }

    nonisolated static let cases: [Case] = [
        Case(
            name: "inline code", note: "testo `codice` fine\n", at: 0,
            markers: [
                HiddenMarker(range: NSRange(location: 6, length: 1), kind: .inlineCode),
                HiddenMarker(range: NSRange(location: 13, length: 1), kind: .inlineCode),
            ],
            collapsed: [6, 13]
        ),
        Case(
            name: "highlight", note: "testo ==x== fine\n", at: 0,
            markers: [
                HiddenMarker(range: NSRange(location: 6, length: 2), kind: .highlight),
                HiddenMarker(range: NSRange(location: 9, length: 2), kind: .highlight),
            ],
            collapsed: [6, 7, 9, 10]
        ),
        Case(
            name: "fence opening", note: "```swift\nlet a = 1\n```\n", at: 0,
            markers: [HiddenMarker(range: NSRange(location: 0, length: 8), kind: .fenceOpening)],
            collapsed: [0, 7]
        ),
        Case(
            name: "fence closing", note: "```swift\nlet a = 1\n```\n", at: 19,
            markers: [HiddenMarker(range: NSRange(location: 0, length: 3), kind: .fenceClosing)],
            collapsed: [0, 2]
        ),
        Case(
            name: "callout marker", note: "> [!note] Titolo\n> corpo\n", at: 0,
            markers: [HiddenMarker(range: NSRange(location: 0, length: 10), kind: .calloutMarker)],
            collapsed: [0, 9]
        ),
        Case(
            name: "embed chip", note: "vedi ![[scheda.pdf]] fine\n", at: 0,
            markers: [
                HiddenMarker(range: NSRange(location: 5, length: 3), kind: .embedChip),
                HiddenMarker(range: NSRange(location: 18, length: 2), kind: .embedChip),
            ],
            collapsed: [5, 6, 7, 18, 19]
        ),
    ]

    @Test(arguments: cases)
    func theSubstitutionServesTheMarkerAndKeepsTheParagraphLength(_ item: Case) {
        let displayed = MarkupHidingFixture.displayedParagraph(item.note, markers: item.markers, at: item.at)
        #expect(displayed != nil, "\(item.name): nessuna sostituzione")
        #expect(displayed?.attributedString.length == MarkupHidingFixture.firstParagraphLength(of: item.note, at: item.at))
        for offset in item.collapsed {
            #expect(
                (displayed?.attributedString.attribute(.font, at: offset, effectiveRange: nil) as? NSFont)
                    == EditorDecorationDelegate.collapsedFont,
                "\(item.name): offset \(offset) non è nel font collassato"
            )
        }
    }

    @Test(arguments: cases)
    func aRevealedParagraphIsLeftAlone(_ item: Case) {
        // Block kinds reveal by paragraph, the inline ones by paragraph unless ADR-0037's span-grained
        // setting is on, which these cases leave off: either way the caret in the paragraph shows raw.
        #expect(
            MarkupHidingFixture.displayedParagraph(item.note, markers: item.markers, at: item.at, revealed: [item.at])
                == nil
        )
    }

    @Test(arguments: cases)
    func theSettingOffServesNothing(_ item: Case) {
        #expect(MarkupHidingFixture.displayedParagraph(item.note, markers: item.markers, at: item.at, hidesMarkup: false) == nil)
    }

    @Test(arguments: cases)
    func aStaleMarkerAgainstProseDoesNotCollapseIt(_ item: Case) {
        let prose = String(repeating: "x", count: item.note.count - 1) + "\n"
        #expect(MarkupHidingFixture.displayedParagraph(prose, markers: item.markers, at: 0) == nil)
    }
}
