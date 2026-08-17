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

// MARK: - The slash menu's trigger (M8)

@MainActor
@Test func theSlashMenuOpensWhereAPersonWouldNotBeTypingASlash() {
    // At the start of a line, and after a space. Those two places are the whole rule.
    #expect(textView("/", cursor: 1).shouldOfferCompletion())
    #expect(textView("/tab", cursor: 4).shouldOfferCompletion())
    #expect(textView("Testo /co", cursor: 9).shouldOfferCompletion())
    #expect(textView("Riga sopra\n/ti", cursor: 14).shouldOfferCompletion())
}

@MainActor
@Test func theSlashMenuStaysOutOfDatesUrlsAndOrdinaryProse() {
    // The three shapes a slash actually has in a note. None of them is a menu, and a
    // menu opening in any of them would make the editor feel possessed.
    #expect(!textView("24/08/2026", cursor: 10).shouldOfferCompletion())
    #expect(!textView("http://esempio", cursor: 14).shouldOfferCompletion())
    #expect(!textView("e/o", cursor: 3).shouldOfferCompletion())
    // A path typed by hand is the same case as a URL: something precedes the slash.
    #expect(!textView("Sources/App", cursor: 11).shouldOfferCompletion())
}

@MainActor
@Test func aSpaceEndsTheSlashMenuAndASecondSlashNeverStartsIt() {
    // `/ ` is someone writing a fraction or changing their mind; `//` is a comment or
    // half a URL. Neither is a command.
    #expect(!textView("/ ", cursor: 2).shouldOfferCompletion())
    #expect(!textView("/tab qui", cursor: 8).shouldOfferCompletion())
    #expect(!textView("//", cursor: 2).shouldOfferCompletion())
}

@MainActor
@Test func theSlashTriggerSurvivesTheStringsThatBrokeTheOtherTwo() {
    // The hostile-input half, which is why this file exists: `completionContext()` runs
    // on every keystroke, so it meets every half-typed and half-deleted line.
    #expect(!textView("", cursor: 0).shouldOfferCompletion())
    #expect(!textView("/tab", cursor: 0).shouldOfferCompletion())
    // A line of nothing but spaces, then a slash: still a legal place for the menu.
    #expect(textView("   /", cursor: 4).shouldOfferCompletion())
    // The slash as the last character of the file, on its own line.
    #expect(textView("Corpo\n\n/", cursor: 8).shouldOfferCompletion())
}

@MainActor
@Test func theSlashAndWhatFollowsAreReplacedTogether() {
    // The range includes the `/` itself, so choosing a command leaves no orphan slash -
    // and because it is one edit, undo takes the whole thing back at once.
    let view = textView("Testo /co", cursor: 9)
    #expect(view.rangeForUserCompletion == NSRange(location: 6, length: 3))
}

@MainActor
@Test func anOpenWikilinkStillWinsOverASlashInsideIt() {
    // Order matters and is deliberate: the two older triggers were there first and keep
    // behaving exactly as they did. Typing a slash inside an unclosed `[[` is far more
    // likely a title with a slash in it than a command.
    let view = textView("Vedi [[Nota /co", cursor: 15)
    #expect(view.shouldOfferCompletion())
    // The range is the wikilink's, not the slash's: from just after `[[`.
    #expect(view.rangeForUserCompletion == NSRange(location: 7, length: 8))
}
