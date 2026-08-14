import AppKit
import Testing
@testable import Pergamenum

/// The editor's completion trigger, exercised on the text view itself.
///
/// `completionContext()` runs on every keystroke through `textDidChange`, so anything
/// it does to a string a person can type has to hold for every string a person can
/// type - including the ones left half-deleted.

@MainActor
private func textView(_ text: String, cursor: Int) -> CompletingTextView {
    let view = CompletingTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    view.string = text
    view.setSelectedRange(NSRange(location: cursor, length: 0))
    return view
}

@MainActor
@Test func survivesAHashAtTheStartOfTheLine() {
    // Backspacing through `## Timeline` passes through a line that is a single `#`.
    // Looking at the character before it used to trap: there is no character before it.
    #expect(textView("#", cursor: 1).shouldOfferCompletion())
    #expect(textView("#tag", cursor: 4).shouldOfferCompletion())
    #expect(textView("Corpo\n#tag", cursor: 10).shouldOfferCompletion())
}

@MainActor
@Test func readsAHeadingAsAHeadingRatherThanATag() {
    // `# ` opens a heading, and the space ends any tag.
    #expect(!textView("# ", cursor: 2).shouldOfferCompletion())
    #expect(!textView("## Timeline", cursor: 11).shouldOfferCompletion())
    #expect(!textView("# Titolo", cursor: 8).shouldOfferCompletion())
}

@MainActor
@Test func completesATagOnlyAfterASpace() {
    #expect(textView("Nota su #cli", cursor: 12).shouldOfferCompletion())
    // Part of a word: `pippo#tag` is not a tag.
    #expect(!textView("pippo#tag", cursor: 9).shouldOfferCompletion())
}

@MainActor
@Test func completesAnOpenWikilink() {
    #expect(textView("Vedi [[Curva", cursor: 12).shouldOfferCompletion())
    // Closed: nothing left to complete.
    #expect(!textView("Vedi [[Curva]]", cursor: 14).shouldOfferCompletion())
}

@MainActor
@Test func replacesTheWholePartialTag() {
    let view = textView("Nota su #cli", cursor: 12)
    #expect(view.rangeForUserCompletion == NSRange(location: 8, length: 4))
}
