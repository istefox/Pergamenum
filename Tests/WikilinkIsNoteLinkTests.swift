import Foundation
import Testing
@testable import Pergamenum

// ADR-0084 §D1, SPEC R-24 (coverage): `Wikilink.isNoteLink` is the one predicate the index
// (`NoteStore.linkTargets`) and a backlink row count by. `BacklinkContextTests` ties the two over a
// corpus; this pins the predicate's own four shapes, so a drift in it fails here by name.

private func targets(_ text: String, keeping predicate: (Wikilink) -> Bool) -> [String] {
    WikilinkParser.links(in: text).filter(predicate).map(\.target)
}

@Test func aPlainLinkAnAliasedOneAndASectionOneAreNoteLinks() {
    let text = "[[Nota]] e [[Altra|testo]] e [[Terza#Sezione]]\n"

    #expect(targets(text, keeping: \.isNoteLink) == ["Nota", "Altra", "Terza"])
}

@Test func anEmbedOfANoteIsANoteLinkButAnEmbedOfAFileIsNot() {
    let text = "![[Nota]] e ![[Foto.png]] e ![[Scheda.pdf]]\n"

    #expect(targets(text, keeping: \.isNoteLink) == ["Nota"])
}

@Test func aCanvasTargetIsNeverANoteLinkWhateverTheCase() {
    let text = "[[Q4.canvas]] e [[Q3.CANVAS]] e ![[Q2.canvas]] e [[Q1]]\n"

    #expect(targets(text, keeping: \.isNoteLink) == ["Q1"])
}
