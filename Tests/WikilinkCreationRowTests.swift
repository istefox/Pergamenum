import AppKit
import Testing
@testable import Pergamenum

/// R-23 (ADR-0083 §D6): when the `[[` completion finds nothing and the typed text can be a note's
/// title, the popup shows one «Crea «X»» row. Choosing it closes the link through the rule N1
/// shipped for a candidate and calls `links.offerCreation` once. The row needs a host that can
/// act on it, so every test here wires the text view the way `makeNSView` does.
@MainActor
@Suite struct WikilinkCreationRow {
    private final class Offers {
        var titles: [String] = []
    }

    private static func view(
        _ text: String, caret: Int, titles: [String] = ["Altro"], offering offers: Offers? = nil
    ) -> CompletingTextView {
        var note = NoteTextView(
            text: .constant(text), theme: .emergency, noteTitles: titles, tagSuggestions: [],
            hidesMarkup: false, onFollowLink: { _ in },
            vault: .init(vaultRoot: nil, notePath: "Nota.md", thumbnails: nil)
        )
        if let offers { note.links.offerCreation = { offers.titles.append($0) } }
        let coordinator = note.makeCoordinator()
        let view = CompletingTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        note.wire(view, to: coordinator)
        note.pushInputs(to: view, coordinator: coordinator)
        view.string = text
        view.noteTitles = titles
        view.setSelectedRange(NSRange(location: caret, length: 0))
        view.refreshCompletion(theme: .emergency)
        return view
    }

    private static func rows(_ view: CompletingTextView) -> [CompletionItem] {
        view.completionPanel.items
    }

    @Test func anOpenLinkWithNoCandidateAndAHandlerOffersOnlyTheCreateRow() {
        let view = Self.view("Vedi [[Bozza", caret: 12, offering: Offers())

        #expect(Self.rows(view) == [.createNote(title: "Bozza")])
        view.completionPanel.hide()
    }

    @Test func noRowWhenACandidateMatches() {
        let view = Self.view("Vedi [[Bozza", caret: 12, titles: ["Bozza finale"], offering: Offers())

        let rows = Self.rows(view)
        #expect(!rows.isEmpty)
        #expect(!rows.contains { if case .createNote = $0 { true } else { false } })
        view.completionPanel.hide()
    }

    @Test(arguments: ["a:b", "Nota.md", "Board.canvas"])
    func noRowWhenTheTextCannotBeATitle(typed: String) {
        let text = "Vedi [[\(typed)"
        let view = Self.view(text, caret: (text as NSString).length, offering: Offers())

        #expect(!Self.rows(view).contains { if case .createNote = $0 { true } else { false } })
        view.completionPanel.hide()
    }

    @Test func noRowWithoutAHandler() {
        let view = Self.view("Vedi [[Bozza", caret: 12, offering: nil)

        #expect(!Self.rows(view).contains { if case .createNote = $0 { true } else { false } })
        view.completionPanel.hide()
    }

    @Test func choosingTheRowClosesTheLinkAndOffersTheTitleOnce() {
        let offers = Offers()
        let view = Self.view("Vedi [[Bozza", caret: 12, offering: offers)

        view.doCommand(by: #selector(NSTextView.insertNewline(_:)))

        #expect(view.string == "Vedi [[Bozza]]")
        #expect(view.selectedRange() == NSRange(location: 14, length: 0))
        #expect(offers.titles == ["Bozza"])
    }

    @Test func aClosingPairAlreadyAheadIsNeverDoubled() {
        let offers = Offers()
        let view = Self.view("Vedi [[Bozza]] e", caret: 12, offering: offers)

        view.doCommand(by: #selector(NSTextView.insertNewline(_:)))

        #expect(view.string == "Vedi [[Bozza]] e")
        #expect(!view.string.contains("]]]]"))
        #expect(view.selectedRange() == NSRange(location: 14, length: 0))
        #expect(offers.titles == ["Bozza"])
    }

    @Test func clickingTheRowDoesTheSame() throws {
        let offers = Offers()
        let view = Self.view("Vedi [[Bozza", caret: 12, offering: offers)
        let row = try #require(Self.rows(view).first)

        view.completionPanel.onChoose?(row)

        #expect(view.string == "Vedi [[Bozza]]")
        #expect(offers.titles == ["Bozza"])
    }
}
