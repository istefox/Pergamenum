import AppKit
import Foundation
import Testing
@testable import Pergamenum

private func range(of word: String, in text: String) -> NSRange {
    (text as NSString).range(of: word)
}

private func toggling(
    _ format: InlineFormat, _ word: String, in text: String
) -> (text: String, selection: NSRange) {
    InlineFormat.toggled(format, in: text, over: range(of: word, in: text))
}

// MARK: Wrapping

@Test(arguments: InlineFormat.allCases)
func wrappingASelectionPutsTheMarkersAroundIt(_ format: InlineFormat) {
    let result = toggling(format, "amplifica", in: "l'isolatore amplifica invece")
    let marker = format.marker
    #expect(result.text == "l'isolatore \(marker)amplifica\(marker) invece")
    // The selection follows the words, not the characters: it must still cover «amplifica»
    // and not the markers, or pressing the same button again would act on something else.
    #expect((result.text as NSString).substring(with: result.selection) == "amplifica")
}

@Test func aSelectionAcrossALineBreakStillWraps() {
    // The range is derived and not counted by hand: the first version of this test said
    // length 11 where the words are 12 long, and failed on its own arithmetic.
    let note = "prima riga\nseconda riga"
    let result = InlineFormat.toggled(.bold, in: note, over: range(of: "riga\nseconda", in: note))
    #expect(result.text == "prima **riga\nseconda** riga")
}

@Test func anEmptySelectionIsANoOp() {
    // Otherwise pressing bold with nothing selected leaves `****` in the note and the caret
    // inside it, which then has to be deleted by hand.
    let note = "niente di selezionato"
    let result = InlineFormat.toggled(.bold, in: note, over: NSRange(location: 7, length: 0))
    #expect(result.text == note)
}

// MARK: Unwrapping, in both shapes

@Test func unwrappingWorksWithTheMarkersOutsideTheSelection() {
    // Double-clicking the word inside `**parola**` selects the word alone.
    let note = "l'isolatore **amplifica** invece"
    let result = toggling(.bold, "amplifica", in: note)
    #expect(result.text == "l'isolatore amplifica invece")
    #expect((result.text as NSString).substring(with: result.selection) == "amplifica")
}

@Test func unwrappingWorksWithTheMarkersInsideTheSelection() {
    // Dragging across the whole thing puts them inside. The same button, the same result,
    // and the same selection afterwards - or the second press acts on something different
    // from the first.
    let note = "l'isolatore **amplifica** invece"
    let result = toggling(.bold, "**amplifica**", in: note)
    #expect(result.text == "l'isolatore amplifica invece")
    #expect((result.text as NSString).substring(with: result.selection) == "amplifica")
}

@Test(arguments: InlineFormat.allCases)
func togglingTwiceGivesBackExactlyTheOriginal(_ format: InlineFormat) {
    let note = "l'isolatore amplifica invece"
    let once = toggling(format, "amplifica", in: note)
    let twice = InlineFormat.toggled(format, in: once.text, over: once.selection)
    #expect(twice.text == note)
}

// MARK: The trap

@Test func boldTextDoesNotReportItselfItalic() {
    // `**parola**` has a `*` on each side of `*parola*`, so a naive check says italic. It
    // would light the wrong button and, worse, un-wrap by removing one asterisk of two and
    // leaving `*amplifica*` behind.
    let note = "l'isolatore **amplifica** invece"
    let word = range(of: "amplifica", in: note)
    #expect(InlineFormat.isApplied(.bold, in: note, over: word))
    #expect(!InlineFormat.isApplied(.italic, in: note, over: word))
}

@Test func italicTextIsStillRecognisedAsItalic() {
    // The negative control for the one above: without it, an `isApplied(.italic)` that always
    // said false would pass.
    let note = "l'isolatore *amplifica* invece"
    #expect(InlineFormat.isApplied(.italic, in: note, over: range(of: "amplifica", in: note)))
}

@Test func unwrappingBoldLeavesNoStrayAsterisk() {
    let note = "l'isolatore **amplifica** invece"
    #expect(toggling(.bold, "amplifica", in: note).text == "l'isolatore amplifica invece")
}

@Test func aPlainSelectionIsAppliedToNothing() {
    let note = "l'isolatore amplifica invece"
    let word = range(of: "amplifica", in: note)
    for format in InlineFormat.allCases {
        #expect(!InlineFormat.isApplied(format, in: note, over: word))
    }
}

@Test func markersAreOrderedLongestFirst() {
    // The order of the cases is what makes the scan meet `**` before `*`, so it is asserted
    // rather than left to whoever next adds a case.
    let lengths = InlineFormat.allCases.map(\.marker.count)
    #expect(lengths == lengths.sorted(by: >))
}

// MARK: The two links

@Test func aWikilinkWrapsTheSelectionAndKeepsItSelected() {
    let note = "vedi la curva di trasmissibilità per i dati"
    let result = InlineFormat.wrapped(note, over: range(of: "curva di trasmissibilità", in: note), in: "[[", "]]")
    #expect(result.text == "vedi la [[curva di trasmissibilità]] per i dati")
    #expect((result.text as NSString).substring(with: result.selection) == "curva di trasmissibilità")
}

@Test func wrappingAnEmptySelectionIsANoOp() {
    let note = "niente di selezionato"
    #expect(InlineFormat.wrapped(note, over: NSRange(location: 3, length: 0), in: "[[", "]]").text == note)
}

// MARK: Where the bar is allowed

@MainActor
private func barIsVisible(selecting word: String, in note: String) -> Bool {
    let view = CompletingTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
    view.string = note
    let window = NSWindow(
        contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false
    )
    window.contentView = view
    view.setSelectedRange(range(of: word, in: note))
    view.refreshFormatBar(theme: .emergency)
    let visible = view.formatBar.isVisible
    view.formatBar.hide()
    window.orderOut(nil)
    return visible
}

private let fencedNote = """
Una riga di prosa da formattare.

```sh
grep --recursive trasmissibilità .
```
"""

@MainActor
@Test func noBarOverASelectionInsideACodeFence() {
    // There `**` is two asterisks in a program, not emphasis. `CodeFence.regions` is the same
    // call that keeps `#` from being a tag in there.
    #expect(!barIsVisible(selecting: "trasmissibilità", in: fencedNote))
}

@MainActor
@Test func theBarStillAppearsOverOrdinaryProse() {
    // The negative control, and it is the one that matters: a `refreshFormatBar` that never
    // showed the bar at all would pass the test above.
    #expect(barIsVisible(selecting: "prosa", in: fencedNote))
}

@MainActor
@Test func noBarWithoutASelection() {
    let view = CompletingTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
    view.string = fencedNote
    view.setSelectedRange(NSRange(location: 4, length: 0))
    view.refreshFormatBar(theme: .emergency)
    #expect(!view.formatBar.isVisible)
}

// MARK: Which side the bar takes

@MainActor
private func anchorSide(selecting text: String, in note: String) -> PanelPlacement.Side {
    let view = CompletingTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 300))
    view.string = note
    let window = NSWindow(
        contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false
    )
    window.contentView = view
    window.layoutIfNeeded()
    let side = view.formatBarAnchor(range(of: text, in: note)).side
    window.orderOut(nil)
    return side
}

private let twoParagraphs = """
Prima riga di prosa da formattare.
Seconda riga, che continua il discorso.
Terza riga, per avere spazio sotto.
"""

@MainActor
@Test func aOneLineSelectionKeepsTheBarAboveIt() {
    #expect(anchorSide(selecting: "prosa", in: twoParagraphs) == .above)
}

@MainActor
@Test func aSelectionSpanningLinesPutsTheBarBelowItsLastLine() {
    // The correction made on screen on 2026-08-18. Above the last line of a long selection is
    // the middle of what is selected, and anchoring to the *first* line - which is what the
    // plan said - put the bar at the top of the note, far from where the mouse had stopped.
    #expect(anchorSide(selecting: "prosa da formattare.\nSeconda riga", in: twoParagraphs) == .below)
}
