import AppKit
import Testing
@testable import Pergamenum

/// R-22 (ADR-0083 §D3): the editor reports the followable link at the caret through
/// `links.onCaretLinkChanged` on selection changes, so «Segui il link» knows whether it can run
/// before the key is pressed. Driven against a real styled text view, no window shown.
@MainActor
@Suite struct LinkAtCaretReports {
    private static let text = "Vedi [[Destinazione]] qui e altro testo."

    private static func editor(text: String = text) -> (EmbedEditorFixtures.Fixture, LinkInputsSpy) {
        let fixture = EmbedEditorFixtures.editor(text: text, hidesMarkup: false, root: nil, thumbnails: nil)
        fixture.textView.delegate = fixture.coordinator
        let spy = LinkInputsSpy()
        spy.install(on: fixture.coordinator)
        fixture.coordinator.applyStyling(to: fixture.textView, theme: .emergency)
        fixture.textView.layoutSubtreeIfNeeded()
        return (fixture, spy)
    }

    private static func caret(_ location: Int, in fixture: EmbedEditorFixtures.Fixture) {
        fixture.textView.setSelectedRange(NSRange(location: location, length: 0))
    }

    @Test func movingIntoALinkReportsItsURLOnce() throws {
        let (fixture, spy) = Self.editor()
        let url = MarkdownAttributedText.noteURL(for: "Destinazione")

        Self.caret(2, in: fixture)
        Self.caret(10, in: fixture)
        Self.caret(12, in: fixture)
        Self.caret(14, in: fixture)

        // Along the link the report does not repeat: it is made when the answer changes.
        #expect(spy.caretReports.compactMap { $0 } == [url])
        #expect(spy.caretReports.last == .some(url))
    }

    @Test func movingOutOfALinkReportsNil() {
        let (fixture, spy) = Self.editor()
        let url = MarkdownAttributedText.noteURL(for: "Destinazione")

        Self.caret(10, in: fixture)
        Self.caret(2, in: fixture)

        #expect(spy.caretReports.compactMap { $0 } == [url])
        #expect(spy.caretReports.last == .some(nil))
    }

    @Test func theCaretJustInsideTheBracketsStillReportsTheLink() {
        let (fixture, spy) = Self.editor()

        Self.caret(6, in: fixture)

        #expect(spy.caretReports.last == .some(MarkdownAttributedText.noteURL(for: "Destinazione")))
    }

    @Test func aCaretInPlainTextReportsNoLink() {
        let (fixture, spy) = Self.editor()

        Self.caret(2, in: fixture)
        Self.caret(30, in: fixture)

        #expect(spy.caretReports.compactMap { $0 }.isEmpty)
    }

    @Test func aFileEmbedReportsNoLink() {
        let (fixture, spy) = Self.editor(text: "Vedi ![[immagine.png]] qui.")

        Self.caret(10, in: fixture)

        #expect(spy.caretReports.compactMap { $0 }.isEmpty)
    }

    @Test func withNoHandlerMovingTheCaretIsHarmless() {
        let fixture = EmbedEditorFixtures.editor(text: Self.text, hidesMarkup: false, root: nil, thumbnails: nil)
        fixture.textView.delegate = fixture.coordinator
        fixture.coordinator.applyStyling(to: fixture.textView, theme: .emergency)

        Self.caret(10, in: fixture)

        #expect(fixture.textView.selectedRange().location == 10)
    }

    // MARK: A text change, not only a caret move

    @Test func typingALinkReportsItWithoutTheCaretMovingAfterwards() {
        let (fixture, spy) = Self.editor(text: "Vedi ")
        Self.caret(5, in: fixture)

        fixture.textView.insertText("[[Nota]]", replacementRange: NSRange(location: 5, length: 0))

        #expect(spy.caretReports.last == .some(MarkdownAttributedText.noteURL(for: "Nota")))
    }

    @Test func deletingABracketOfTheLinkUnderTheCaretReportsNil() {
        let (fixture, spy) = Self.editor(text: "Vedi [[Nota]] x")
        Self.caret(12, in: fixture)
        #expect(spy.caretReports.last == .some(MarkdownAttributedText.noteURL(for: "Nota")))

        fixture.textView.deleteBackward(nil)

        #expect(fixture.textView.string == "Vedi [[Nota] x")
        #expect(spy.caretReports.last == .some(nil))
    }
}
