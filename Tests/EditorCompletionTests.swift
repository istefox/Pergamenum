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
    #expect(textView("/", cursor: 1).shouldOpenSlashMenu())
    #expect(textView("/tab", cursor: 4).shouldOpenSlashMenu())
    #expect(textView("Testo /co", cursor: 9).shouldOpenSlashMenu())
    #expect(textView("Riga sopra\n/ti", cursor: 14).shouldOpenSlashMenu())
}

@MainActor
@Test func theSlashMenuStaysOutOfDatesUrlsAndOrdinaryProse() {
    // The three shapes a slash actually has in a note. None of them is a menu, and a
    // menu opening in any of them would make the editor feel possessed.
    #expect(!textView("24/08/2026", cursor: 10).shouldOpenSlashMenu())
    #expect(!textView("http://esempio", cursor: 14).shouldOpenSlashMenu())
    #expect(!textView("e/o", cursor: 3).shouldOpenSlashMenu())
    // A path typed by hand is the same case as a URL: something precedes the slash.
    #expect(!textView("Sources/App", cursor: 11).shouldOpenSlashMenu())
}

@MainActor
@Test func aSpaceEndsTheSlashMenuAndASecondSlashNeverStartsIt() {
    // `/ ` is someone writing a fraction or changing their mind; `//` is a comment or
    // half a URL. Neither is a command.
    #expect(!textView("/ ", cursor: 2).shouldOpenSlashMenu())
    #expect(!textView("/tab qui", cursor: 8).shouldOpenSlashMenu())
    #expect(!textView("//", cursor: 2).shouldOpenSlashMenu())
}

@MainActor
@Test func theSlashTriggerSurvivesTheStringsThatBrokeTheOtherTwo() {
    // The hostile-input half, which is why this file exists: `completionContext()` runs
    // on every keystroke, so it meets every half-typed and half-deleted line.
    #expect(!textView("", cursor: 0).shouldOpenSlashMenu())
    #expect(!textView("/tab", cursor: 0).shouldOpenSlashMenu())
    // A line of nothing but spaces, then a slash: still a legal place for the menu.
    #expect(textView("   /", cursor: 4).shouldOpenSlashMenu())
    // The slash as the last character of the file, on its own line.
    #expect(textView("Corpo\n\n/", cursor: 8).shouldOpenSlashMenu())
}

@MainActor
@Test func theSlashAndWhatFollowsAreReplacedTogether() {
    // The range includes the `/` itself, so choosing a command leaves no orphan slash -
    // and because it is one edit, undo takes the whole thing back at once.
    let view = textView("Testo /co", cursor: 9)
    #expect(view.rangeForUserCompletion == NSRange(location: 6, length: 3))
}

@MainActor
@Test func escapeClosesTheMenuForTheWholeWordAndNotUntilTheNextKeystroke() {
    // Found by asking what Escape should do with the slash. Without remembering the
    // dismissal the menu reopened on the very next character, because the context was
    // still a slash context - so `/usr/local` was unwritable in practice.
    let view = textView("/us", cursor: 3)
    #expect(view.shouldOpenSlashMenu())

    view.dismissSlashMenu()
    #expect(!view.shouldOpenSlashMenu())

    // Typing on: still the same slash, still dismissed.
    view.string = "/usr"
    view.setSelectedRange(NSRange(location: 4, length: 0))
    #expect(!view.shouldOpenSlashMenu())

    // A different slash, further along the line, is a new question and gets a menu.
    view.string = "/usr /l"
    view.setSelectedRange(NSRange(location: 7, length: 0))
    #expect(view.shouldOpenSlashMenu())
}

@MainActor
@Test func escapeLeavesTheTypedTextExactlyAsItWas() {
    // The other half of the same decision: dismissing must not delete. A capture
    // dismissed by accident keeps what was typed (ADR-0008 §D3) and so does this.
    let view = textView("Percorso /usr", cursor: 13)
    view.dismissSlashMenu()
    #expect(view.string == "Percorso /usr")
}

@MainActor
@Test func theTwoKindsOfCompletionNeverBothOpen() {
    // The slash menu is a panel of ours and the other two are AppKit's list. A context
    // that answered yes to both would put two lists on screen at once, which is the
    // failure this pair of predicates exists to make impossible.
    for text in ["/", "/tab", "Testo /co"] {
        let view = textView(text, cursor: (text as NSString).length)
        #expect(view.shouldOpenSlashMenu())
        #expect(!view.shouldOfferCompletion())
    }
    for text in ["Vedi [[Curva", "Nota su #cli"] {
        let view = textView(text, cursor: (text as NSString).length)
        #expect(!view.shouldOpenSlashMenu())
        #expect(view.shouldOfferCompletion())
    }
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

// MARK: - Sections after `#` inside a wikilink (M8)

private let sectioned = """
# Prove in laboratorio

## Campioni

tre campioni

### Durezza

a freddo

## Strumenti

un fonometro
"""

@MainActor
private func completing(_ text: String, cursor: Int, sections: @escaping (String) -> [String]) -> CompletingTextView {
    let view = textView(text, cursor: cursor)
    view.noteSections = sections
    return view
}

@MainActor
private func headings(of note: String) -> [String] {
    NoteOutline.entries(in: note).compactMap { entry in
        guard case .heading = entry.kind else { return nil }
        return entry.title
    }
}

@MainActor
@Test func aHashInsideAnOpenWikilinkOffersThatNotesHeadings() {
    let view = completing("![[Prove#", cursor: 9) { _ in headings(of: sectioned) }
    let offered = view.completions(forPartialWordRange: view.rangeForUserCompletion, indexOfSelectedItem: nil)
    // Every heading, in the order the note has them - the order the index draws and the
    // one the person wrote. Sorting by length instead put a `###` from the bottom of the
    // note first, which is what the first version did and it read as arbitrary on sight.
    #expect(offered == ["Prove in laboratorio", "Campioni", "Durezza", "Strumenti"])
    // The embed form is the one that matters here, and it behaves like the plain one:
    // `![[Prove#…]]` is what a transclusion of a section is written as.
    #expect(view.shouldOfferCompletion())
}

@MainActor
@Test func typingFiltersTheHeadings() {
    let view = completing("[[Prove#Cam", cursor: 11) { _ in headings(of: sectioned) }
    let offered = view.completions(forPartialWordRange: view.rangeForUserCompletion, indexOfSelectedItem: nil)
    #expect(offered == ["Campioni"])
}

@MainActor
@Test func onlyWhatFollowsTheHashIsReplaced() {
    // The note's name is already right. Replacing it too would delete what the completion
    // is a completion of, and the user would watch `[[Prove` disappear as they chose.
    let view = completing("[[Prove#Cam", cursor: 11) { _ in headings(of: sectioned) }
    #expect(view.rangeForUserCompletion == NSRange(location: 8, length: 3))
}

@MainActor
@Test func aPipeMeansTheDisplayTextIsBeingTypedAndNotAHeading() {
    let view = completing("[[Prove|Cam", cursor: 11) { _ in headings(of: sectioned) }
    // Still a wikilink context, so the note titles answer - not the headings.
    #expect(view.completions(forPartialWordRange: view.rangeForUserCompletion, indexOfSelectedItem: nil) == nil)
}

@MainActor
@Test func aNoteNobodyCanResolveOffersNothingRatherThanFailing() {
    let view = completing("[[Fantasma#", cursor: 11) { _ in [] }
    #expect(view.completions(forPartialWordRange: view.rangeForUserCompletion, indexOfSelectedItem: nil) == nil)
}

@MainActor
@Test func everyHeadingOfferedIsOneThatTransclusionCanFind() {
    // The invariant that makes this feature worth having: the list offers the stripped form
    // `NoteOutline` produces, and `Transclusion.excerpt` matches against the same form. A
    // list offering `## **Campioni**` would be a list of sections that resolve to nothing.
    let view = completing("[[Prove#", cursor: 8) { _ in headings(of: sectioned) }
    let offered = view.completions(forPartialWordRange: view.rangeForUserCompletion, indexOfSelectedItem: nil)
    #expect(offered?.isEmpty == false)
    for heading in offered ?? [] {
        #expect(Transclusion.excerpt(of: sectioned, section: heading) != nil)
    }
}
