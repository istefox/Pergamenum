import AppKit
import Testing
@testable import Pergamenum

/// Choosing a `[[` candidate closes the link (n1-seams R-07): the person typed `[[Tras`, picked a
/// note, and the line should read `[[Titolo]]` with the caret after it, not leave an open link for
/// them to close by hand. Two layers: the pure insertion rule, and the real views that apply it.

private let longTitle = "Trasmissibilità e rapporto di frequenza"

// MARK: - The pure rule

@Suite struct WikilinkClosingInsertion {
    @Test func nothingAheadWritesTheTitleAndTheClosingBrackets() { // (n1-seams R-07)
        let result = WikilinkTrigger.closingInsertion(of: "Titolo", ahead: "")
        #expect(result.text == "Titolo]]")
        #expect(result.caretOffset == "Titolo]]".count)
    }

    @Test func textAheadThatIsNotAClosingPairIsTreatedAsNothingAhead() { // (n1-seams R-07)
        let plain = WikilinkTrigger.closingInsertion(of: "Titolo", ahead: " e poi altro")
        #expect(plain.text == "Titolo]]")
        #expect(plain.caretOffset == "Titolo]]".count)
    }

    @Test func aClosingPairAheadIsReusedAndTheCaretMovesPastIt() { // (n1-seams R-07)
        let result = WikilinkTrigger.closingInsertion(of: "Titolo", ahead: "]] e poi")
        #expect(result.text == "Titolo")
        #expect(result.caretOffset == "Titolo]]".count)
    }

    @Test func aSingleBracketAheadIsTreatedAsNothingAhead() { // (n1-seams R-07)
        let result = WikilinkTrigger.closingInsertion(of: "Titolo", ahead: "] e")
        #expect(result.text == "Titolo]]")
        #expect(result.caretOffset == "Titolo]]".count)
    }

    @Test func aSpaceBeforeTheBracketsIsTreatedAsNothingAhead() { // (n1-seams R-07)
        let result = WikilinkTrigger.closingInsertion(of: "Titolo", ahead: " ]]")
        #expect(result.text == "Titolo]]")
        #expect(result.caretOffset == "Titolo]]".count)
    }
}

// MARK: - The note editor

@MainActor
private func wikilinkView(_ text: String, caret: Int) -> CompletingTextView {
    let view = CompletingTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    view.string = text
    view.setSelectedRange(NSRange(location: caret, length: 0))
    view.noteTitles = [longTitle, "Altro"]
    view.refreshCompletion(theme: .emergency)
    return view
}

@MainActor
@Suite struct WikilinkClosingInTheEditor {
    @Test func returnClosesTheLinkAndLeavesTheCaretAtTheEnd() { // (n1-seams R-07)
        let view = wikilinkView("Vedi [[Tras", caret: 11)
        #expect(view.completionPanel.isVisible)
        view.doCommand(by: #selector(NSTextView.insertNewline(_:)))

        #expect(view.string == "Vedi [[\(longTitle)]]")
        #expect(view.selectedRange() == NSRange(location: (view.string as NSString).length, length: 0))
    }

    @Test func aClosingPairAlreadyAheadOfTheCaretIsNotDoubled() { // (n1-seams R-07)
        let text = "Vedi [[Tras]] e"
        let view = wikilinkView(text, caret: 11)
        #expect(view.completionPanel.isVisible)
        view.doCommand(by: #selector(NSTextView.insertNewline(_:)))

        #expect(view.string == "Vedi [[\(longTitle)]] e")
        let after = ("Vedi [[\(longTitle)]]" as NSString).length
        #expect(view.selectedRange() == NSRange(location: after, length: 0))
    }

    @Test func clickingARowClosesTheLinkToo() { // (n1-seams R-07)
        let view = wikilinkView("Vedi [[Tras", caret: 11)
        let row = view.completionPanel.items.first
        #expect(row != nil)
        guard let row else { return }
        view.completionPanel.onChoose?(row)

        #expect(view.string == "Vedi [[\(longTitle)]]")
    }
}

// MARK: - The Workspace card

@MainActor
@Suite struct WikilinkClosingInACard {
    private static func card(_ text: String, caret: Int) -> FormattingTextView {
        let view = FormattingTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        view.string = text
        view.wikilinkNoteTitles = [longTitle]
        view.setSelectedRange(NSRange(location: caret, length: 0))
        view.refreshWikilinkCompletion()
        return view
    }

    @Test func aChosenCandidateIsWrittenWithItsClosingBrackets() { // (n1-seams R-07)
        let view = Self.card("Vedi [[Tras", caret: 11)
        #expect(view.wikilinkCompletion != nil)
        view.doCommand(by: #selector(NSTextView.insertNewline(_:)))

        #expect(view.string == "Vedi [[\(longTitle)]]")
        #expect(view.selectedRange().location == (view.string as NSString).length)
    }

    @Test func aClosingPairAlreadyAheadIsNotDoubled() { // (n1-seams R-07)
        let view = Self.card("Vedi [[Tras]] e", caret: 11)
        #expect(view.wikilinkCompletion != nil)
        view.doCommand(by: #selector(NSTextView.insertNewline(_:)))

        #expect(view.string == "Vedi [[\(longTitle)]] e")
        let after = ("Vedi [[\(longTitle)]]" as NSString).length
        #expect(view.selectedRange().location == after)
    }
}
