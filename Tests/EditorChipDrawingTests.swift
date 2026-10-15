import AppKit
import Testing
@testable import Pergamenum

// ADR-0087 §D5, plan docs/plans/note-workflow-n5.md, Task 3 (R-36, R-42).
//
// Inline code, a highlight, a tag and a date drawn as pills, through the in-process editor
// (`N5Editor`): the note is styled by the real coordinator, the caret placed, and the paragraph read
// back as the layout would receive it.
//
// Every note here starts with a plain `intro` paragraph so the caret can sit away from the chip
// (caret at 0), and the chip's own paragraph starts at 7.

@MainActor
@Suite struct EditorChipDrawing {
    private static let paragraph = 7

    private static func note(_ line: String) -> String { "intro\n\n\(line)\n" }

    private static func chip(_ built: N5Editor.Built, at offset: Int) -> InlineChip.Style? {
        built.textView.textStorage?.attribute(.pergamenumChip, at: offset, effectiveRange: nil) as? InlineChip.Style
    }

    private static func color(_ token: ColorToken, _ built: N5Editor.Built) -> NSColor {
        NSColor(built.theme.color(token))
    }

    private static func foreground(_ built: N5Editor.Built, at offset: Int) -> NSColor? {
        built.textView.textStorage?.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? NSColor
    }

    private static func kern(_ built: N5Editor.Built, at offset: Int) -> CGFloat? {
        let shown = N5Editor.displayed(built, at: paragraph)
        return shown?.attribute(.kern, at: offset - paragraph, effectiveRange: nil) as? CGFloat
    }

    // MARK: - Inline code

    @Test func inlineCodeCarriesTheChipOverItsContentAndConcealsItsBackticksOffTheCaret() { // R-36
        let note = Self.note("testo `codice` fine")
        let built = N5Editor.build(note, caret: 0)
        let style = Self.chip(built, at: 14)
        #expect(style != nil, "nessun .pergamenumChip sul contenuto del codice")
        #expect(style?.background == Self.color(.codeInlineBackground, built))
        for tick in [13, 20] {
            #expect(N5Editor.isConcealed(built, paragraph: Self.paragraph, at: tick), "backtick \(tick) non collassato")
            #expect((Self.kern(built, at: tick) ?? 0) > 0, "backtick \(tick) senza .kern")
        }
        #expect(!N5Editor.isConcealed(built, paragraph: Self.paragraph, at: 15))
    }

    @Test func inlineCodeRevealsItsBackticksWithTheCaretInTheParagraph() { // R-36
        let note = Self.note("testo `codice` fine")
        let built = N5Editor.build(note, caret: 16)
        for tick in [13, 20] {
            #expect(
                !N5Editor.isConcealed(built, paragraph: Self.paragraph, at: tick), "backtick \(tick) ancora collassato"
            )
        }
    }

    // MARK: - Highlight

    @Test func aHighlightCarriesTheHighlightBackgroundAndConcealsItsDelimitersOffTheCaret() { // R-36
        let note = Self.note("testo ==x== fine")
        let built = N5Editor.build(note, caret: 0)
        let style = Self.chip(built, at: 15)
        #expect(style != nil, "nessun .pergamenumChip sul contenuto dell'evidenziato")
        #expect(style?.background == Self.color(.highlight, built))
        for delimiter in [13, 14, 16, 17] {
            #expect(N5Editor.isConcealed(built, paragraph: Self.paragraph, at: delimiter), "delimitatore \(delimiter)")
        }
        #expect(!N5Editor.isConcealed(built, paragraph: Self.paragraph, at: 15))
    }

    // With the markup shown nothing paints the pill, so the run is the card's plain background; hidden, the
    // pill is the paint and a background beside it would draw twice.
    @Test func aHighlightWithTheMarkupShownIsPaintedAsABackground() { // R-36
        let built = N5Editor.build(Self.note("testo ==x== fine"), hidesMarkup: false, caret: 0)
        for offset in 13...17 {
            let background = built.textView.textStorage?.attribute(.backgroundColor, at: offset, effectiveRange: nil)
            #expect(background as? NSColor == Self.color(.highlight, built), "carattere \(offset) senza sfondo")
        }
        let outside = built.textView.textStorage?.attribute(.backgroundColor, at: 12, effectiveRange: nil)
        #expect(outside == nil, "lo sfondo esce dall'evidenziato")
    }

    @Test func aHighlightWithTheMarkupHiddenHasNoBackgroundBesideItsPill() { // R-36
        let built = N5Editor.build(Self.note("testo ==x== fine"), caret: 0)
        #expect(built.textView.textStorage?.attribute(.backgroundColor, at: 15, effectiveRange: nil) == nil)
    }

    @Test func aHighlightRevealsItsDelimitersWithTheCaretInTheParagraph() { // R-36
        let built = N5Editor.build(Self.note("testo ==x== fine"), caret: 15)
        for delimiter in [13, 14, 16, 17] {
            #expect(!N5Editor.isConcealed(built, paragraph: Self.paragraph, at: delimiter), "delimitatore \(delimiter)")
        }
    }

    @Test func doubleEqualsInsideACodeSpanIsNoHighlight() { // R-36, the SPEC's edge case
        let note = Self.note("`a==b==` fine")
        #expect(!MarkdownStylerFixture.spans(note).contains(.highlight))
        let built = N5Editor.build(note, caret: 0)
        // Inside the code span the chip is the code's, and the `==` stay visible characters.
        #expect(Self.chip(built, at: 9)?.background == Self.color(.codeInlineBackground, built))
        #expect(Self.chip(built, at: 9)?.background != Self.color(.highlight, built))
        #expect(!N5Editor.isConcealed(built, paragraph: Self.paragraph, at: 9))
    }

    // MARK: - Tags and dates

    @Test func aTagChipDimsItsNamespaceAndAccentsItsValue() { // R-42
        let built = N5Editor.build(Self.note("vedi #client-acme qui"), caret: 0)
        #expect(Self.chip(built, at: 12) != nil, "nessun .pergamenumChip sul tag")
        // `#client-` is the namespace, `acme` the value.
        for offset in 12..<20 {
            #expect(Self.foreground(built, at: offset) == Self.color(.textSecondary, built), "namespace \(offset)")
        }
        for offset in 20..<24 {
            #expect(Self.foreground(built, at: offset) == Self.color(.accentPrimary, built), "valore \(offset)")
        }
    }

    @Test func aDateChipKeepsItsAngleBracketVisible() { // R-42
        let built = N5Editor.build(Self.note("con >2026-10-14 ok"), caret: 0)
        // "con " is four characters, so the `>` sits at 7 + 4.
        #expect(Self.chip(built, at: 11) != nil, "nessun .pergamenumChip sul >data")
        #expect(!N5Editor.isConcealed(built, paragraph: Self.paragraph, at: 11))
        #expect(!N5Editor.isConcealed(built, paragraph: Self.paragraph, at: 12))
    }

    @Test func theCmdClickLinkIsStillOnTheTagAndTheDateRanges() { // R-42, N1's attribute
        let tag = N5Editor.build(Self.note("vedi #client-acme qui"), caret: 0)
        #expect(tag.textView.textStorage?.attribute(.editorLink, at: 12, effectiveRange: nil) != nil)
        #expect(tag.textView.textStorage?.attribute(.editorLink, at: 22, effectiveRange: nil) != nil)
        let date = N5Editor.build(Self.note("con >2026-10-14 ok"), caret: 0)
        #expect(date.textView.textStorage?.attribute(.editorLink, at: 11, effectiveRange: nil) != nil)
        #expect(date.textView.textStorage?.attribute(.editorLink, at: 18, effectiveRange: nil) != nil)
    }

    // MARK: - Length and fragments

    @Test(arguments: [
        "testo `codice` fine", "testo ==x== fine", "`a==b==` fine", "vedi #client-acme qui", "con >2026-10-14 ok",
    ])
    func theDisplayedParagraphKeepsTheStoredLength(line: String) { // R-36, R-42
        for caret in [0, 9] {
            let built = N5Editor.build(Self.note(line), caret: caret)
            let lengths = N5Editor.lengths(built, at: Self.paragraph)
            #expect(lengths.displayed == lengths.stored, "\(line.debugDescription) caret \(caret): \(lengths)")
        }
    }

    @Test(arguments: [
        "testo `codice` fine", "testo ==x== fine", "vedi #client-acme qui", "con >2026-10-14 ok",
    ])
    func aParagraphWithChipsIsLaidOutAsAChipLineFragment(line: String) { // R-36, R-42
        let built = N5Editor.build(Self.note(line), caret: 0)
        #expect(N5Editor.fragments(built)[Self.paragraph] is ChipLineFragment)
    }

    @Test func aParagraphWithoutChipsKeepsTheStandardFragment() { // R-36
        let built = N5Editor.build(Self.note("solo testo senza segni"), caret: 0)
        #expect(!(N5Editor.fragments(built)[Self.paragraph] is ChipLineFragment))
    }

    // MARK: - The painter's rects

    @Test func aPillWrappingAcrossTwoLinesGivesTwoRects() throws { // R-36
        // The paragraph starts the note, so a range in the paragraph and one in the document agree.
        let code = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron"
        let note = "`\(code)` coda\n\nfine\n"
        let built = N5Editor.build(note, width: 200, caret: note.utf16.count - 2)
        let fragment = try #require(N5Editor.fragments(built)[0])
        let range = NSRange(location: 1, length: (code as NSString).length)
        let crossed = fragment.textLineFragments.filter { NSIntersectionRange($0.characterRange, range).length > 0 }
        try #require(crossed.count >= 2, "the fixture must wrap")

        let rects = InlineChipPainter.rects(for: range, in: fragment, padding: 2)
        #expect(rects.count == crossed.count)
        #expect(rects.allSatisfy { $0.width > 0 && $0.height > 0 })
    }

    @Test func aPillOnOneLineGivesOneRect() throws { // R-36
        let note = "`ab` coda\n\nfine\n"
        let built = N5Editor.build(note, caret: note.utf16.count - 2)
        let fragment = try #require(N5Editor.fragments(built)[0])
        #expect(InlineChipPainter.rects(for: NSRange(location: 1, length: 2), in: fragment, padding: 2).count == 1)
    }
}
