import AppKit
import Testing
@testable import Pergamenum

// ADR-0093 §D7, composition step and the completion panel.
//
// A composition step replays the edit path without opening the completion panel (the marked text is
// not a word the person has written), but a panel that is already open is still refreshed: that
// refresh is the only path that closes it when the marked text ends its context. The commit is an
// ordinary `insertText`, reaches `textDidChange`, and opens the panel as any keystroke does.

@MainActor
@Suite(.serialized) struct CompositionCompletionPanel {
    private func editor(_ text: String, caret: Int) -> ScrolledEditorFixture {
        let fixture = ScrolledEditorFixture(text: text, bound: BoundText(text))
        fixture.textView.noteTitles = ["Prove"]
        fixture.textView.setSelectedRange(NSRange(location: caret, length: 0))
        return fixture
    }

    // An open panel whose context the marked text ends is closed by the composition step.
    @Test func aCompositionStepThatEndsTheContextClosesAnOpenPanel() {
        let fixture = editor("[[Pro", caret: 5)
        defer { fixture.textView.completionPanel.hide() }
        fixture.textView.refreshCompletion(theme: .emergency)
        #expect(fixture.textView.completionPanel.isVisible, "the panel did not open for [[Pro")

        fixture.textView.setMarkedText(
            "]]", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: 5, length: 0)
        )
        #expect(fixture.textView.hasMarkedText())
        #expect(!fixture.textView.completionPanel.isVisible, "the panel stayed open over text that is no longer a context")
    }

    // A composition step does not open a panel, and the committing insertText does.
    @Test func aCompositionStepOpensNoPanelAndTheCommitDoes() {
        let fixture = editor("ab", caret: 2)
        defer { fixture.textView.completionPanel.hide() }
        #expect(!fixture.textView.completionPanel.isVisible)

        fixture.textView.setMarkedText(
            "[[Pro", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: 2, length: 0)
        )
        #expect(fixture.textView.hasMarkedText())
        #expect(fixture.textView.string == "ab[[Pro")
        #expect(!fixture.textView.completionPanel.isVisible, "a composition step opened the panel")

        fixture.textView.insertText("[[Pro", replacementRange: fixture.textView.markedRange())
        #expect(!fixture.textView.hasMarkedText())
        #expect(fixture.textView.completionPanel.isVisible, "the committing insertText did not refresh the panel")
    }
}
