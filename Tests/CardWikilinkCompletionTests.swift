import Foundation
import Testing
@testable import Pergamenum

// Point 1 of the workspace wikilink regression chain: `[[` autocomplete on Workspace `.text`
// cards. Scope of this file is the pure logic only - `WikilinkTrigger.context(in:caret:)` and
// `CardWikilinkCompletion.candidates(matching:notes:boards:)` - no AppKit, matching this repo's
// convention for `Tests/LineFormatTests.swift`/`Tests/CardFormattingTests.swift`. The popup's
// on-screen placement (`BoardWikilinkCompletionGeometry`) and `FormattingTextView`'s keyboard
// handling are exercised by hand, the same boundary `Tests/BoardFormatBarTests.swift`'s own
// header draws for its sibling feature.

// MARK: - `WikilinkTrigger.context(in:caret:)`

@Test func unclosedWikilinkIsATrigger() {
    let text = "Guarda [[prova"
    let context = WikilinkTrigger.context(in: text, caret: (text as NSString).length)
    #expect(context?.prefix == "prova")
}

@Test func aClosedWikilinkIsNotATrigger() {
    // The caret sits past the closing `]]`, with the whole link already behind it - the
    // rule only ever looks backward from the caret, exactly as
    // `CompletingTextView.completionContext()`'s own `.wikilink` case does.
    let text = "Guarda [[prova]] qui"
    let context = WikilinkTrigger.context(in: text, caret: (text as NSString).length)
    #expect(context == nil)
}

@Test func noOpenBracketsIsNotATrigger() {
    let text = "Nessun link qui"
    #expect(WikilinkTrigger.context(in: text, caret: (text as NSString).length) == nil)
}

@Test func theTriggerRangeCoversOnlyThePrefixAfterTheBrackets() {
    let text = "[[Des"
    let context = WikilinkTrigger.context(in: text, caret: (text as NSString).length)
    #expect(context?.range == NSRange(location: 2, length: 3))
}

@Test func theTriggerLooksOnlyAtTheCaretsOwnLine() {
    // An unclosed `[[` on a previous line must not leak a trigger onto a later, unrelated line.
    let text = "[[Aperto\nSeconda riga"
    let caret = (text as NSString).length
    #expect(WikilinkTrigger.context(in: text, caret: caret) == nil)
}

@Test func anEmptyPrefixRightAfterTheBracketsIsStillATrigger() {
    let text = "[["
    let context = WikilinkTrigger.context(in: text, caret: (text as NSString).length)
    #expect(context?.prefix == "")
    #expect(context?.range == NSRange(location: 2, length: 0))
}

// MARK: - `CardWikilinkCompletion.candidates(matching:notes:boards:)`

@Test func candidatesFuzzyRankNotesAndBoardsTogether() {
    let results = CardWikilinkCompletion.candidates(
        matching: "prv",
        notes: ["Prova", "Qualcos'altro"],
        boards: ["Calendar/testo.canvas"]
    )
    #expect(results.map(\.displayTitle) == ["Prova"])
}

@Test func aBoardCandidateInsertsItsBareFilenameNeverItsFullPath() {
    let results = CardWikilinkCompletion.candidates(
        matching: "testo",
        notes: [],
        boards: ["Calendar/testo.canvas"]
    )
    #expect(results.first?.insertText == "testo.canvas")
    #expect(results.first?.displayTitle == "Calendar/testo.canvas")
    #expect(results.first?.kind == .board)
}

@Test func aNoteCandidateInsertsItsPlainTitle() {
    let results = CardWikilinkCompletion.candidates(matching: "pro", notes: ["Prova"], boards: [])
    #expect(results.first?.insertText == "Prova")
    #expect(results.first?.kind == .note)
}

@Test func candidatesAreCappedAtTheLimit() {
    let notes = (0..<20).map { "Nota \($0)" }
    let results = CardWikilinkCompletion.candidates(matching: "Nota", notes: notes, boards: [], limit: 3)
    #expect(results.count == 3)
}

@Test func noMatchYieldsNoCandidates() {
    let results = CardWikilinkCompletion.candidates(matching: "zzz", notes: ["Prova"], boards: ["Calendar/testo.canvas"])
    #expect(results.isEmpty)
}
