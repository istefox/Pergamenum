import Foundation
import Testing
@testable import Pergamenum

// (coverage) PG-425: the two pure helpers behind the heading with no title. The hosted test
// `aHeadingWithNoTitleHangsItsRunWhenRevealed` (GutterRevealGeometryTests) pins the visible result;
// these pin the helpers' own contract as their doc comments state it: `titlelessHeadingRun` answers
// the `#` run and the one space after it, in the note's coordinates, for a heading with nothing but
// spaces after the run, and nil otherwise; `isTitlelessHeading` answers whether a heading marker has
// nothing after it in its paragraph but spaces and the line's end.

private func run(_ line: String, in note: String? = nil, at location: Int = 0) -> NSRange? {
    let text = (note ?? line) as NSString
    return EditorDecorationDelegate.titlelessHeadingRun(
        in: NSRange(location: location, length: (line as NSString).length), of: text
    )
}

@Test func aBareHeadingRunIsTheHashesAndTheOneSpace() {
    #expect(run("# ") == NSRange(location: 0, length: 2))
    #expect(run("## ") == NSRange(location: 0, length: 3))
    #expect(run("###### ") == NSRange(location: 0, length: 7))
}

@Test func extraSpacesAfterTheRunAreNotPartOfIt() {
    #expect(run("###   ") == NSRange(location: 0, length: 4))
}

@Test func theRunIsAnsweredInTheNotesCoordinates() {
    let note = "Intro\n\n## \nfine\n"
    #expect(run("## ", in: note, at: 7) == NSRange(location: 7, length: 3))
}

@Test func aHeadingWithATitleHasNoBareRun() {
    #expect(run("# Titolo") == nil)
    #expect(run("## a") == nil)
    #expect(run("###  Titolo") == nil)
}

@Test func aLineThatIsNotAHeadingHasNoBareRun() {
    #expect(run("#") == nil, "without the space it is prose")
    #expect(run("######") == nil)
    #expect(run("####### ") == nil, "seven hashes is not a heading")
    #expect(run("") == nil)
    #expect(run("   ") == nil)
    #expect(run("testo # ") == nil)
}

@Test func aSpanPastTheEndOfTheNoteHasNoBareRun() {
    let span = NSRange(location: 4, length: 3)
    #expect(EditorDecorationDelegate.titlelessHeadingRun(in: span, of: "# \n" as NSString) == nil)
}

// MARK: isTitlelessHeading

private func isBare(
    _ kind: HiddenMarker.Kind = .heading, marker: NSRange, paragraph: NSRange, in text: String
) -> Bool {
    EditorDecorationDelegate.isTitlelessHeading(
        HiddenMarker(range: marker, kind: kind), of: paragraph, in: text as NSString
    )
}

@Test func aHeadingMarkerWithNothingAfterItIsBare() {
    #expect(isBare(marker: NSRange(location: 0, length: 2), paragraph: NSRange(location: 0, length: 3), in: "# \n"))
    // The last paragraph, with no terminator at all.
    #expect(isBare(marker: NSRange(location: 0, length: 2), paragraph: NSRange(location: 0, length: 2), in: "# "))
    // Extra spaces after the run.
    #expect(isBare(marker: NSRange(location: 0, length: 4), paragraph: NSRange(location: 0, length: 7), in: "###   \n"))
}

@Test func theParagraphsOwnOffsetIsRespected() {
    let text = "Intro\n\n## \nfine\n"
    #expect(isBare(marker: NSRange(location: 0, length: 3), paragraph: NSRange(location: 7, length: 4), in: text))
}

@Test func aHeadingMarkerWithATitleAfterItIsNotBare() {
    #expect(!isBare(marker: NSRange(location: 0, length: 2), paragraph: NSRange(location: 0, length: 9), in: "# Titolo\n"))
    #expect(!isBare(marker: NSRange(location: 0, length: 2), paragraph: NSRange(location: 0, length: 4), in: "# a\n"))
}

@Test func onlyAHeadingMarkerCanBeBare() {
    let text = "# \n"
    for kind: HiddenMarker.Kind in [.emphasis, .list, .blockquote, .checkbox, .embed] {
        #expect(!isBare(kind, marker: NSRange(location: 0, length: 2), paragraph: NSRange(location: 0, length: 3), in: text))
    }
}

@Test func aMarkerPastTheParagraphIsNotBare() {
    #expect(!isBare(marker: NSRange(location: 0, length: 9), paragraph: NSRange(location: 0, length: 3), in: "# \n"))
}
