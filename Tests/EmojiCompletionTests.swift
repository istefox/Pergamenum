import AppKit
import Testing
@testable import Pergamenum

// The fourth thing `CompletionPanel` can offer: an emoji, reached by typing `:` and a name.
//
// Split from `CompletionPanelTests` when that file passed the length the linter allows, and
// the seam is a real one - these are about a catalogue and a trigger, those are about the
// panel itself.

// MARK: - Emoji on `:`

@MainActor
private func emojiPanel(_ text: String, cursor: Int) -> CompletingTextView {
    let view = CompletingTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    view.string = text
    view.setSelectedRange(NSRange(location: cursor, length: 0))
    view.refreshCompletion(theme: .emergency)
    return view
}

@MainActor
@Test func aColonOffersEmojiAndDrawsTheirGlyphs() {
    let view = emojiPanel("Nota :bers", cursor: 10)
    #expect(view.completionPanel.isVisible)
    #expect(view.completionPanel.items == [.emoji(glyph: "🎯", name: "bersaglio")])
}

@MainActor
@Test func choosingAnEmojiWritesTheGlyphAndNothingElse() {
    // Not `:bersaglio:` and not the name: a shortcode left in the file is a syntax this app
    // does not otherwise have, and Obsidian would read it as plain text.
    let view = emojiPanel("Nota :bers", cursor: 10)
    view.doCommand(by: #selector(NSTextView.insertNewline(_:)))
    #expect(view.string == "Nota 🎯")
}

@MainActor
@Test func aColonInATimeOrAUrlOrFrontmatterOpensNothing() {
    // The three places a `:` is ordinary. None of them is at the start of a line or after a
    // space, which is the whole rule - the same one the slash menu uses.
    // Asserted on the rule, not on the panel: a closed panel proves nothing here, because a
    // query like `30` matches no emoji whether the rule ran or not. Written the other way
    // first, and the negative control caught it - it stayed green with the rule deleted.
    for (text, cursor) in [("Alle 14:30", 10), ("http://esempio", 14), ("date: 2026-08-18", 16)] {
        let view = emojiPanel(text, cursor: cursor)
        #expect(!view.shouldOfferEmoji(), "«\(text)» è stato letto come trigger emoji")
        #expect(!view.completionPanel.isVisible, "«\(text)» ha aperto il pannello")
    }
}

@MainActor
@Test func aColonMatchingNothingSaysSoRatherThanGoing() {
    // Was `aColonMatchingNothingOpensNothing`, and asserted the opposite. The emoji slice
    // hid the panel here reasoning about a `:` in prose - a case `punctuationTrigger`
    // already rules out, since it fires only at a line start or after a space. What was
    // actually happening: `:` alone opens all ninety-six rows, so the panel was already up
    // and vanished mid-word, while the command list in the same panel stayed and explained
    // itself. Both catalogues are closed; both now say so.
    let view = emojiPanel("Nota :zqx", cursor: 9)
    #expect(view.completionPanel.isVisible)
    #expect(view.completionPanel.items.isEmpty)
    #expect(view.completionPanel.noMatch == "Nessuna emoji")
}

@MainActor
@Test func escapeOnTheEmojiPanelLeavesTheColonAlone() {
    // ADR-0008 §D3 again: a person writing «ecco : due punti» keeps what they typed.
    let view = emojiPanel("Nota :", cursor: 6)
    #expect(view.completionPanel.isVisible)
    view.dismissCompletion()
    #expect(!view.completionPanel.isVisible)
    #expect(view.string == "Nota :")
}

@MainActor
@Test func theEmojiTriggerIsNeitherOfTheOtherTwoKinds() {
    // The third shape the panel can take, and it must not collide with either of the first
    // two: one panel, one shape at a time.
    let view = emojiPanel("Nota :bers", cursor: 10)
    #expect(view.shouldOfferEmoji())
    #expect(!view.shouldOpenSlashMenu())
    #expect(!view.shouldOfferCompletion())
}
