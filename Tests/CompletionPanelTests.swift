import AppKit
import SwiftUI
import Testing
@testable import Pergamenum

/// The one panel every completion is drawn in (PG-023).
///
/// `EditorCompletionTests` covers the rule - which trigger a piece of text is - and this
/// covers what the panel is then filled with, which key acts on it, and what reaches the
/// note. Driven on a real `CompletingTextView`, as `TranscludedLineTests` and
/// `FoldBadgeClickTests` are, because three defects shipped in one day were green in the
/// unit suite and only visible on screen: anything that can be exercised against real
/// AppKit here is one fewer thing resting on a hand check.

@MainActor
private func panelled(
    _ text: String,
    cursor: Int,
    titles: [String] = [],
    tags: [String] = [],
    commands: [EditorCommand] = []
) -> CompletingTextView {
    let view = CompletingTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    view.string = text
    view.setSelectedRange(NSRange(location: cursor, length: 0))
    view.noteTitles = titles
    view.tagSuggestions = tags
    view.editorCommands = commands
    view.refreshCompletion(theme: .emergency)
    return view
}

// MARK: - What each trigger fills the panel with

@MainActor
@Test func aWikilinkOffersNoteTitlesAsCandidates() {
    let view = panelled("Vedi [[Cur", cursor: 10, titles: ["Curva di trasmissibilità", "Altro"])
    #expect(view.completionPanel.isVisible)
    #expect(view.completionPanel.items == [.text("Curva di trasmissibilità", symbol: "doc.text")])
}

@MainActor
@Test func aTagOffersTagsAndSaysSoWithItsOwnIcon() {
    // The suggestions carry their own `#`, as `VaultSession.tagSuggestions` builds them,
    // and the replaced range carries it too - so the candidate is written over the `#cli`
    // whole rather than beside it.
    let view = panelled("Nota su #cli", cursor: 12, tags: ["#client-vibrofer", "#topic-gomma"])
    #expect(view.completionPanel.items == [.text("#client-vibrofer", symbol: "tag")])

    view.doCommand(by: #selector(NSTextView.insertNewline(_:)))
    #expect(view.string == "Nota su #client-vibrofer")
}

@MainActor
@Test func aSectionOffersTheHeadingsOfTheNoteNamedBeforeTheHash() {
    let view = CompletingTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    view.string = "[[Prove#"
    view.setSelectedRange(NSRange(location: 8, length: 0))
    view.noteSections = { _ in ["Campioni", "Strumenti"] }
    view.refreshCompletion(theme: .emergency)

    #expect(view.completionPanel.items == [
        .text("Campioni", symbol: "number"),
        .text("Strumenti", symbol: "number"),
    ])
}

@MainActor
@Test func aSlashOffersCommandsRatherThanStrings() {
    let view = panelled("/tit", cursor: 4, commands: EditorCommand.editorEntries)
    #expect(view.completionPanel.isVisible)
    #expect(!view.completionPanel.items.isEmpty)
    // Outside the macro: `allSatisfy` rethrows, and `#expect` will not swallow that.
    let everyRowIsACommand = view.completionPanel.items.allSatisfy(\.isCommand)
    #expect(everyRowIsACommand)
}

// MARK: - When there is nothing to show

@MainActor
@Test func nothingMatchedMeansNoPanelForACandidateList() {
    // What AppKit's list did, and the right answer here: the candidates are the vault's
    // own notes, so typing the name of one that does not exist yet is the ordinary case
    // and not a dead end worth a box. A command list says so instead, because there the
    // catalogue is closed and an empty result means the query was wrong.
    let view = panelled("Vedi [[zzz", cursor: 10, titles: ["Curva di trasmissibilità"])
    #expect(!view.completionPanel.isVisible)
}

@MainActor
@Test func aClosedCatalogueSaysNothingMatchedRatherThanGoing() {
    // The `:` list used to vanish mid-word while the `/` list stayed and explained itself -
    // one panel answering the same question two ways. Both catalogues are closed, so an
    // empty result means the query was wrong and is worth saying.
    let emoji = panelled("Nota :zqx", cursor: 9)
    #expect(emoji.completionPanel.isVisible)
    #expect(emoji.completionPanel.items.isEmpty)
    #expect(emoji.completionPanel.noMatch == "Nessuna emoji")

    let command = panelled("/zzz", cursor: 4, commands: EditorCommand.editorEntries)
    #expect(command.completionPanel.isVisible)
    #expect(command.completionPanel.items.isEmpty)
    #expect(command.completionPanel.noMatch == "Nessun comando")
}

@MainActor
@Test(arguments: [
    ("Vedi [[zzz", 10),
    ("Vedi [[Prove#zzz", 16),
    ("Nota su #zzz", 12)
])
func anOpenEndedListStillGoesWhenNothingMatches(_ text: String, _ cursor: Int) {
    // The other half of the rule, and the half that must not move: these three offer the
    // vault's own notes, sections and tags, so typing a name that does not exist yet is how
    // one gets named. All three shared a guard that this change deleted; two had no test.
    let view = CompletingTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    view.string = text
    view.setSelectedRange(NSRange(location: cursor, length: 0))
    view.noteTitles = ["Curva di trasmissibilità"]
    view.tagSuggestions = ["#client-vibrofer"]
    view.noteSections = { _ in ["Campioni", "Strumenti"] }
    view.refreshCompletion(theme: .emergency)

    #expect(!view.completionPanel.isVisible)
}

@MainActor
@Test func everyTriggerHasDecidedWhatAnEmptyResultMeans() {
    // The table itself, so a sixth trigger added without deciding fails here rather than on
    // screen. Closed catalogues carry a phrase that already agrees with its own noun;
    // open-ended ones carry nil.
    #expect(CompletingTextView.Context.slash(prefix: "/").noMatch == "Nessun comando")
    #expect(CompletingTextView.Context.emoji(prefix: ":").noMatch == "Nessuna emoji")
    #expect(CompletingTextView.Context.wikilink(prefix: "").noMatch == nil)
    #expect(CompletingTextView.Context.section(note: "Prove", prefix: "").noMatch == nil)
    #expect(CompletingTextView.Context.tag(prefix: "#").noMatch == nil)
}

@MainActor
@Test func leavingTheContextClosesThePanel() {
    let view = panelled("Vedi [[Cur", cursor: 10, titles: ["Curva di trasmissibilità"])
    #expect(view.completionPanel.isVisible)

    view.string = "Vedi [[Curva]] e poi altro"
    view.setSelectedRange(NSRange(location: 26, length: 0))
    view.refreshCompletion(theme: .emergency)
    #expect(!view.completionPanel.isVisible)
}

// MARK: - Escape

@MainActor
@Test func escapeKeepsThePanelShutForTheSameWord() {
    // AppKit remembered this for the three completions it served. Nothing else will now,
    // so it is carried here: without it the panel reopened on the very next keystroke,
    // because the context was still the same context.
    let view = panelled("Vedi [[Cur", cursor: 10, titles: ["Curva di trasmissibilità"])
    view.dismissCompletion()
    #expect(!view.completionPanel.isVisible)

    view.string = "Vedi [[Curv"
    view.setSelectedRange(NSRange(location: 11, length: 0))
    view.refreshCompletion(theme: .emergency)
    #expect(!view.completionPanel.isVisible)
    // And the text is untouched, which is the other half of ADR-0008 §D3.
    #expect(view.string == "Vedi [[Curv")
}

@MainActor
@Test func aFreshTriggerOpensThePanelAgainAfterAnEscape() {
    let view = panelled("Vedi [[Cur", cursor: 10, titles: ["Curva di trasmissibilità"])
    view.dismissCompletion()

    view.string = "Vedi [[Curva]] e [[Cur"
    view.setSelectedRange(NSRange(location: 22, length: 0))
    view.refreshCompletion(theme: .emergency)
    #expect(view.completionPanel.isVisible)
}

// MARK: - Choosing

@MainActor
@Test func returnWritesTheCandidateOverExactlyWhatWasTyped() {
    let view = panelled("Vedi [[Cur", cursor: 10, titles: ["Curva di trasmissibilità"])
    view.doCommand(by: #selector(NSTextView.insertNewline(_:)))

    // The bare title, as AppKit's list inserted it: the `]]` is left for the person to
    // close, so nothing about what reaches the file changes.
    #expect(view.string == "Vedi [[Curva di trasmissibilità")
    #expect(!view.completionPanel.isVisible)
}

@MainActor
@Test func aSectionReplacesOnlyWhatFollowsTheHash() {
    let view = CompletingTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    view.string = "[[Prove#Cam"
    view.setSelectedRange(NSRange(location: 11, length: 0))
    view.noteSections = { _ in ["Campioni", "Strumenti"] }
    view.refreshCompletion(theme: .emergency)
    view.doCommand(by: #selector(NSTextView.insertNewline(_:)))

    #expect(view.string == "[[Prove#Campioni")
}

@MainActor
@Test func theArrowKeysWalkTheListAndStopAtItsEnds() {
    let view = panelled(
        "Vedi [[C", cursor: 8,
        titles: ["Curva di trasmissibilità", "Campioni", "Cataloghi"]
    )
    #expect(view.completionPanel.selectedIndex == 0)

    view.doCommand(by: #selector(NSTextView.moveDown(_:)))
    #expect(view.completionPanel.selectedIndex == 1)
    // Up at the top stays at the top rather than wrapping to the bottom: in a long list
    // "I have gone too far" would otherwise become "where am I".
    view.doCommand(by: #selector(NSTextView.moveUp(_:)))
    view.doCommand(by: #selector(NSTextView.moveUp(_:)))
    #expect(view.completionPanel.selectedIndex == 0)
}

@MainActor
@Test func fifteenDownArrowsWalkPastTheFirstScreenfulAndStopAtTheListsEnd() {
    // The test above only covers a 3-item list's two ends (ui-suite-replacement plan §2
    // row 10: it did not hold as coverage for `CompletionPanelUITests:146`, which drove
    // fifteen real down arrows over a list long enough that the selection walks past
    // what fits on screen unscrolled - `CompletionPanelView`'s row list is capped at
    // 320pt and its floor is 120pt, well under twenty rows' worth). The retired GUI test
    // reached this with `:`, not `[[`: a wikilink's own candidates are ranked and capped
    // at 12 (`CompletingTextView.swift:356`), too short to press fifteen times into. The
    // emoji catalogue is the one open-ended, unbounded-by-a-limit list the panel offers
    // (`EmojiCatalogue.matching("")` returns the whole thing, catalogue order, no cap),
    // which is what the retired test actually walked.
    let view = panelled("Nota :", cursor: 6)
    let total = EmojiCatalogue.entries.count
    #expect(view.completionPanel.items.count == total)
    #expect(view.completionPanel.selectedIndex == 0)

    for _ in 0..<15 { view.doCommand(by: #selector(NSTextView.moveDown(_:))) }
    #expect(view.completionPanel.selectedIndex == 15)
    #expect(view.completionPanel.selected == .emoji(glyph: "🧪", name: "provetta"))

    // Far past the catalogue's own end (`total + 10` presses on top of the fifteen
    // already made): stops at the last row rather than reading past it.
    for _ in 0..<(total + 10) { view.doCommand(by: #selector(NSTextView.moveDown(_:))) }
    #expect(view.completionPanel.selectedIndex == total - 1)
    #expect(view.completionPanel.selected == .emoji(glyph: "✈️", name: "aereo"))

    // `CompletionPanelView`'s `ScrollViewReader.scrollTo(selectedIndex)` (`:79`, `:82`)
    // runs inside the `NSHostingView` `CompletionPanel.render(into:maxHeight:)` rebuilds
    // on every `moveSelection` - proven here by `selectedIndex` reaching the catalogue's
    // last row without the render pipeline crashing or losing track of the list; the
    // `ScrollView`'s own pixel offset is SwiftUI-internal and not something a unit test
    // reaches, the same boundary `docs/adr/0053-test-seams-for-the-in-process-merge-gate.md`'s
    // hosted-view prototype names for a SwiftUI gesture.
}

@MainActor
@Test func clickingARowLandsWhereReturnLands() {
    // The panel never acts on a choice itself; it hands it back. That is what makes a
    // click and a Return the same edit rather than two implementations of one.
    let view = panelled("Vedi [[Cur", cursor: 10, titles: ["Curva di trasmissibilità"])
    view.completionPanel.onChoose?(.text("Curva di trasmissibilità", symbol: "doc.text"))

    #expect(view.string == "Vedi [[Curva di trasmissibilità")
    #expect(!view.completionPanel.isVisible)
}

@MainActor
@Test func anEmptyPanelDoesNotTeachKeysThatDoNothing() {
    // «↑↓ scegli» and «↩ inserisci» name a row to move to and a row to insert, and over an
    // empty list there is no row.
    //
    // Asserted on the rule and NOT on the rendered strings. Walking the hosting view for its
    // text was written first and is the reason a suite run ended at 647 tests and the next one
    // hung: `value(forKey: "stringValue")` on an arbitrary NSView raises an Objective-C
    // exception Swift cannot catch. What the footer actually draws was confirmed on screen.
    let empty = CompletionPanelView(
        items: [], query: "zqx", noMatch: "Nessuna emoji",
        selectedIndex: 0, maxHeight: 400, onChoose: { _ in }
    )
    #expect(!empty.showsRowKeys)

    // The negative control: with rows the keys come back. Without it this passes on a footer
    // that never shows them at all.
    let filled = CompletionPanelView(
        items: EditorCommand.editorEntries.map(CompletionItem.command), query: "",
        noMatch: "Nessun comando", selectedIndex: 0, maxHeight: 400, onChoose: { _ in }
    )
    #expect(filled.showsRowKeys)
}
