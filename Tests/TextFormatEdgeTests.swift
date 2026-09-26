import Foundation
import Testing
@testable import Pergamenum

// ADR-0064 §D9/§D10, plan docs/plans/format-edge-hardening.md, Task 6 - R-16, R-17, R-20, R-21.
//
// The text-level formats a note carries inside its body: a task line's tags, an inline embed,
// a link target, and the Unicode normalisation of a title.

// MARK: - R-16: a tag leaves by its own range

@Test func aPrefixTagLeavesNoResidue() {
    let text = TaskParser.displayText(from: "Rivedere offerta #topic-forni e #topic-forni-tunnel")
    #expect(!text.contains("-tunnel"))
    #expect(text == "Rivedere offerta e")
}

@Test func aLongerTagFirstLeavesNoResidue() {
    let text = TaskParser.displayText(from: "Rivedere offerta #topic-forni-tunnel e #topic-forni")
    #expect(!text.contains("-tunnel"))
    #expect(text == "Rivedere offerta e")
}

// MARK: - R-17: an inline embed is one span, with no orphan `!`

@Test func anInlineEmbedHasNoOrphanBang() {
    let spans = MarkdownInlineParser.spans(in: "Vedi ![[foto.png]] qui")
    #expect(!spans.contains { $0.text.contains("!") })
    #expect(spans.contains { $0.link == .embed(target: "foto.png") })
}

@Test func aSizedEmbedShowsItsReference() {
    let spans = MarkdownInlineParser.spans(in: "![[foto.png|300]]")
    #expect(spans.map(\.text) == ["foto.png"])
    #expect(spans.first?.link == .embed(target: "foto.png"))
}

@Test func anEmbedInAHeadingOutlinesAsItsReference() {
    let headings = NoteOutline.entries(in: "## ![[schema.png]]\n\nTesto.\n").filter {
        if case .heading = $0.kind { true } else { false }
    }
    #expect(headings.map(\.title) == ["schema.png"])
}

@Test func aMarkdownImageIsStillALink() {
    #expect(MarkdownInlineParser.spans(in: "![alt](x.png)").first?.link == .url("x.png"))
}

@Test func aWikilinkIsStillANoteLink() {
    #expect(MarkdownInlineParser.spans(in: "[[Nota]]").first?.link == .note(title: "Nota"))
}

// MARK: - R-20: a board is not a note

@Test func aBoardMarkerIsNotALinkTarget() {
    #expect(!NoteStore.linkTargets(in: "- [ ] x ^[[Q4.canvas]]\n").contains("Q4.canvas"))
    #expect(!NoteStore.linkTargets(in: "Vedi [[Q4.canvas]].\n").contains("Q4.canvas"))
}

@Test func aTranscludedNoteIsStillALinkTarget() {
    let targets = NoteStore.linkTargets(in: "![[Nota]]\n\n![[Nota.md]]\n")
    #expect(targets.contains("Nota"))
    #expect(targets.contains("Nota.md"))
}

@Test func aCanvasIsNotANoteReference() {
    #expect(!Transclusion.isNoteReference("Q4.canvas"))
}

@Test func everyListedExtensionDecides() {
    for ext in Transclusion.fileExtensions {
        #expect(!Transclusion.isNoteReference("x.\(ext)"), "x.\(ext) read as a note")
    }
    for ext in Transclusion.noteExtensions {
        #expect(Transclusion.isNoteReference("x.\(ext)"), "x.\(ext) read as a file")
    }
}

// MARK: - R-21: NFD and NFC are the same title (pinned, ADR-0064 §D10)

private let nfcCitta = "Citt\u{00E0}"
private let nfdCitta = "Citta\u{0300}"

@Test func nfdAndNfcNamesResolveToTheSameBoard() {
    let board = "Progetti/\(nfdCitta).canvas"
    guard case .unique(let path) = WorkspaceBoardResolver.resolve("\(nfcCitta).canvas", in: [board]) else {
        Issue.record("an NFC marker did not resolve the NFD board")
        return
    }
    #expect(path.value == board)
}

@Test func nfdAndNfcTitlesMatchInRename() {
    #expect(NoteRename.rewritingLinks(in: "Vedi [[\(nfdCitta)]].", from: nfcCitta, to: "Nuova")
        == "Vedi [[Nuova]].")
}

@Test func nfdAndNfcMatchInTransclusion() {
    let excerpt = Transclusion.excerpt(of: "## \(nfcCitta)\n\nTesto della sezione.\n", section: nfdCitta)
    #expect(excerpt?.contains("Testo della sezione.") == true)
    #expect(Transclusion.target(ofLine: "![[\(nfdCitta)]]") == .note(reference: nfcCitta, section: nil))
}
