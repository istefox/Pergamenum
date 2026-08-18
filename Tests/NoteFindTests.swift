import AppKit
import Foundation
import Testing
@testable import Pergamenum

private let note = """
La trasmissibilità sotto radice di due.
Curva di Trasmissibilità a 4 Hz, misure del 2026-08-04.
La trasmissibilità cresce con lo smorzamento. Confronto col 2025-11-12.
Dati di targa del ventilatore.
"""

private func found(_ text: String, _ query: NoteFind.Query, within scope: NSRange? = nil) -> [String] {
    let haystack = text as NSString
    return NoteFind.run(query, in: text, within: scope).ranges.map { haystack.substring(with: $0) }
}

// MARK: Literal

@Test func anEmptyFieldIsNotASearchThatFoundNothing() {
    // The distinction the bar draws on: `.idle` shows no count at all, `.matches([])` says
    // «nessuna corrispondenza».
    #expect(NoteFind.run(NoteFind.Query(text: ""), in: note) == .idle)
    #expect(NoteFind.run(NoteFind.Query(text: "flangia"), in: note) == .matches([]))
}

@Test func aLiteralFindIsCaseInsensitiveUntilItIsAskedNotToBe() {
    let insensitive = found(note, NoteFind.Query(text: "trasmissibilità"))
    #expect(insensitive == ["trasmissibilità", "Trasmissibilità", "trasmissibilità"])

    let sensitive = found(note, NoteFind.Query(text: "trasmissibilità", isCaseSensitive: true))
    #expect(sensitive == ["trasmissibilità", "trasmissibilità"])
}

@Test func matchesComeBackInDocumentOrder() {
    let ranges = NoteFind.run(NoteFind.Query(text: "trasmissibilità"), in: note).ranges
    #expect(ranges == ranges.sorted { $0.location < $1.location })
}

@Test func overlappingLiteralMatchesAreNotCountedTwice() {
    // `aa` in `aaaa` is two matches, not three: an overlapping third could not be replaced
    // without eating one of the others.
    #expect(found("aaaa", NoteFind.Query(text: "aa")).count == 2)
}

@Test func aLiteralSearchDoesNotReadItsQueryAsAPattern() {
    // The point of the option being off: `(` is a character, not the start of a group, and
    // a pattern that would not compile is simply text that is not there.
    #expect(found("costo (IVA esclusa)", NoteFind.Query(text: "(IVA")) == ["(IVA"])
    #expect(NoteFind.run(NoteFind.Query(text: "\\d+"), in: note) == .matches([]))
}

// MARK: Regex

@Test func aPatternFindsWhatALiteralCannot() {
    let dates = found(note, NoteFind.Query(text: #"\b\d{4}-\d{2}-\d{2}\b"#, isRegex: true))
    #expect(dates == ["2026-08-04", "2025-11-12"])
}

@Test func aPatternStillBeingTypedIsNotAnError() {
    // `\b(\d{4` is on the way to `\b(\d{4})`, and a find that threw or went red on every
    // keystroke would be unusable. Both of these are states a person types through.
    #expect(NoteFind.run(NoteFind.Query(text: #"\b(\d{4"#, isRegex: true), in: note) == .invalidPattern)
    #expect(NoteFind.run(NoteFind.Query(text: "[", isRegex: true), in: note) == .invalidPattern)
}

@Test func aValidPatternThatFindsNothingIsNotAnInvalidOne() {
    // The pair the mockup puts in the same corner of the same line. A test that let these
    // two be equal would let the bar say the wrong one.
    let result = NoteFind.run(NoteFind.Query(text: #"\bflangia\b"#, isRegex: true), in: note)
    #expect(result == .matches([]))
    #expect(result != .invalidPattern)
}

@Test func zeroLengthMatchesAreDropped() {
    // `a*` matches the empty string at every position and `\b` at every word edge. Kept,
    // the count means nothing, the stepper cannot step, and replace-all never terminates.
    #expect(found("banana", NoteFind.Query(text: "a*", isRegex: true)) == ["a", "a", "a"])
    #expect(NoteFind.run(NoteFind.Query(text: #"\b"#, isRegex: true), in: "una parola") == .matches([]))
}

@Test func aPatternHonoursTheCaseOption() {
    #expect(found(note, NoteFind.Query(text: "^la", isRegex: true, isCaseSensitive: true)).isEmpty)
    #expect(found("La riga", NoteFind.Query(text: "^La", isRegex: true, isCaseSensitive: true)) == ["La"])
}

// MARK: Scope

@Test func aScopedSearchIgnoresWhatIsOutsideItAndStillAnswersInAbsoluteRanges() {
    let haystack = note as NSString
    let secondLine = haystack.range(of: "Curva di Trasmissibilità a 4 Hz, misure del 2026-08-04.")
    let ranges = NoteFind.run(NoteFind.Query(text: "trasmissibilità"), in: note, within: secondLine).ranges

    #expect(ranges.count == 1)
    // Absolute and not scope-relative: the text view is handed these to highlight, and a
    // range measured from the start of the selection would paint the wrong words.
    #expect(ranges.first.map { NSLocationInRange($0.location, secondLine) } == true)
    #expect(haystack.substring(with: ranges[0]) == "Trasmissibilità")
}

@Test func aScopeStaleAfterAnEditIsClampedRatherThanTrusted() {
    // The scope is the selection captured when the bar opened, and the note can be edited
    // with the bar open. A range past the end must not crash the search.
    let result = NoteFind.run(
        NoteFind.Query(text: "targa"), in: note, within: NSRange(location: 10, length: 100_000)
    )
    #expect(result.ranges.count == 1)
    #expect(NoteFind.run(
        NoteFind.Query(text: "targa"), in: note, within: NSRange(location: 0, length: 0)
    ) == .matches([]))
}

// MARK: Replacement

@Test func captureGroupsExpandInTheReplacement() {
    let query = NoteFind.Query(text: #"\b(\d{4})-(\d{2})-(\d{2})\b"#, isRegex: true)
    let match = (note as NSString).range(of: "2026-08-04")
    let replaced = NoteFind.replacement(for: query, matching: match, in: note, template: "$3/$2/$1")
    #expect(replaced == "04/08/2026")
}

@Test func aLiteralReplacementLeavesDollarSignsAlone() {
    // Somebody replacing with `$1` under a literal search means those two characters, and
    // `NSRegularExpression`'s template syntax would eat them.
    let query = NoteFind.Query(text: "prezzo")
    let match = (note as NSString).range(of: "targa")
    #expect(NoteFind.replacement(for: query, matching: match, in: note, template: "$1 netto") == "$1 netto")
}

@Test func aReplacementResolvesItsGroupsAgainstItsOwnMatch() {
    // Not against the document: the second date must give its own numbers, not the first's.
    let query = NoteFind.Query(text: #"(\d{4})-(\d{2})-(\d{2})"#, isRegex: true)
    let second = (note as NSString).range(of: "2025-11-12")
    #expect(NoteFind.replacement(for: query, matching: second, in: note, template: "$1") == "2025")
}

// MARK: The session

@MainActor
private func session(_ query: String, over text: String, scope: NSRange? = nil) -> FindSession {
    let session = FindSession()
    session.open(replacing: false, over: scope, in: text)
    session.query = query
    session.update(in: text)
    return session
}

@MainActor
@Test func theStepperWrapsAtBothEnds() {
    // Wrapping is what makes the count honest: «3 di 3» followed by «1 di 3» says the search
    // went round, which is the question a person asks by pressing the key again.
    let find = session("trasmissibilità", over: note)
    #expect(find.matches.count == 3)
    #expect(find.tally == "1 di 3")

    find.step(by: 1)
    find.step(by: 1)
    #expect(find.tally == "3 di 3")
    find.step(by: 1)
    #expect(find.tally == "1 di 3")
    find.step(by: -1)
    #expect(find.tally == "3 di 3")
}

@MainActor
@Test func steppingWithNothingFoundDoesNothingRatherThanCrashing() {
    let find = session("flangia", over: note)
    find.step(by: 1)
    #expect(find.currentMatch == nil)
    #expect(find.tally == "nessuna corrispondenza")
}

@MainActor
@Test func theIndexClampsWhenAnEditRemovesTheLastMatch() {
    // Not reset: an edit that removes the match being looked at should leave the stepper on
    // the new last one, not send it back to the top of the note.
    let find = session("trasmissibilità", over: note)
    find.step(by: 2)
    #expect(find.tally == "3 di 3")

    find.update(in: "La trasmissibilità e basta.")
    #expect(find.tally == "1 di 1")
    #expect(find.currentMatch != nil)
}

@MainActor
@Test func theThreeStatesOfTheCountAreDistinguishable() {
    // They share one line in the bar and mean different things: nothing asked, an answer of
    // none, and a pattern still being written.
    let idle = session("", over: note)
    #expect(idle.tally == nil)

    let none = session("flangia", over: note)
    #expect(none.tally == "nessuna corrispondenza")
    #expect(!none.tallyIsPlain)

    let broken = session(#"\b(\d{4"#, over: note)
    broken.isRegex = true
    broken.update(in: note)
    #expect(broken.tally == "pattern incompleto")
    #expect(!broken.tallyIsPlain)

    let found = session("trasmissibilità", over: note)
    #expect(found.tally == "1 di 3")
    #expect(found.tallyIsPlain)
}

@MainActor
@Test func aCaretIsNotAScope() {
    // Cmd+F with nothing selected means the whole note. Taking the caret as a scope would
    // give a search of zero characters, which finds nothing and looks broken.
    let find = FindSession()
    find.open(replacing: false, over: NSRange(location: 5, length: 0), in: note)
    find.query = "trasmissibilità"
    find.update(in: note)

    #expect(find.scope == nil)
    #expect(find.matches.count == 3)
}

@MainActor
@Test func aSelectionIsTheScopeAndTheCountSaysSo() {
    let line = (note as NSString).range(of: "Curva di Trasmissibilità a 4 Hz, misure del 2026-08-04.")
    let find = session("trasmissibilità", over: note, scope: line)
    #expect(find.scope != nil)
    #expect(find.tally == "1 di 1")
}

@MainActor
@Test func closingForgetsTheSearchButReopeningKeepsTheQuery() {
    // Cmd+F with a search already run is how a person comes back to it, so the query
    // survives; the results do not, because the note may be a different note by then.
    let find = session("trasmissibilità", over: note)
    find.close()
    #expect(!find.isOpen)
    #expect(find.matches.isEmpty)
    #expect(find.query == "trasmissibilità")

    find.open(replacing: false, over: nil, in: note)
    #expect(find.tally == "1 di 3")
}

@MainActor
@Test func replaceAllIsOrderedLastMatchFirst() {
    // The order is load-bearing: applied from the top, the first replacement moves every
    // range after it and the second lands in the wrong place.
    let find = session("trasmissibilità", over: note)
    find.replacement = "trasmissione"
    let planned = find.replacements(in: note)

    #expect(planned.count == 3)
    let locations = planned.map(\.range.location)
    #expect(locations == locations.sorted(by: >))
}

// MARK: Focus

/// Scrolling to a match must not take the keyboard.
///
/// The defect this holds shut, found on screen one keystroke into the first use of the bar:
/// the first letter typed into the find field changed the query, the query found a match, the
/// match scrolled, `scroll` ended with `makeFirstResponder(textView)` - which is right for the
/// index, where arriving at a section and typing should write there - and the second letter
/// went into the note.
///
/// Driven on a real window with a real `NSTextView`, because first responder is not a value
/// this code owns: AppKit decides it, and a hand-built stand-in would agree with whatever was
/// written rather than with what happens.
@MainActor
private func firstResponderAfterScroll(takingFocus: Bool) -> NSResponder? {
    let view = NoteTextView(
        text: .constant(note), theme: .emergency, noteTitles: [], tagSuggestions: [],
        onFollowLink: { _ in }
    )
    let coordinator = view.makeCoordinator()
    let textView = CompletingTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    textView.string = note

    // Something else holding the keyboard, standing in for the find field.
    let elsewhere = NSTextField(frame: NSRect(x: 0, y: 300, width: 400, height: 24))
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 330))
    container.addSubview(textView)
    container.addSubview(elsewhere)

    let window = NSWindow(
        contentRect: container.frame, styleMask: [.titled], backing: .buffered, defer: false
    )
    window.contentView = container
    window.makeFirstResponder(elsewhere)

    coordinator.scroll(textView, to: (note as NSString).range(of: "targa"), takingFocus: takingFocus)
    let responder = window.firstResponder
    window.orderOut(nil)
    // A field editor is the window's, not the field's: compare by who it is editing.
    return (responder as? NSTextView)?.delegate as? NSResponder ?? responder
}

@MainActor
@Test func steppingToAMatchLeavesTheKeyboardWhereItWas() {
    let responder = firstResponderAfterScroll(takingFocus: false)
    #expect(responder is NSTextField)
}

@MainActor
@Test func theIndexsJumpStillTakesTheKeyboard() {
    // The negative control, and the reason `takingFocus` is a parameter rather than a
    // deletion: the index needs exactly what the find bar must not have.
    let responder = firstResponderAfterScroll(takingFocus: true)
    #expect(responder is CompletingTextView)
}
