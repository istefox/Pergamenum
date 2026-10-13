import Foundation
import Testing
@testable import Pergamenum

// ADR-0095 §D6, plan docs/plans/no-whole-note-term-on-the-update-path-pg-406.md, Task 4 (PG-406, R-06, R-07).
//
// The outline map is a second reader of the rule `NoteOutline.entries(in:)` applies, so every assertion
// here compares it with that function (and with `foldedOrdinals(ofOffsets:in:)` and
// `NoteFolding.foldableEntries(in:)`), never with a hand-written answer. A corpus that holds each shape
// the rule has to get right, one text at a time. Red until Task 5: the red-phase map answers empty.

/// What the map is compared with: the parse, converted to the map's units.
enum OutlineOracle {
    static func items(_ text: String) -> [OutlineMap.Item] {
        NoteOutline.entries(in: text).map {
            OutlineMap.Item(range: NSRange($0.range, in: text), kind: $0.kind, title: $0.title, level: $0.level)
        }
    }

    /// The rows the sidebar draws: the parse and the foldable set of `NoteFolding`.
    static func rows(_ text: String) -> [OutlineRow] {
        let foldable = NoteFolding.foldableEntries(in: text)
        return NoteOutline.entries(in: text).enumerated().map { index, entry in
            OutlineRow(kind: entry.kind, title: entry.title, level: entry.level, isFoldable: foldable.contains(index))
        }
    }
}

struct OutlineCase: Sendable, CustomTestStringConvertible {
    var name: String
    var text: String
    /// Whether the parse finds at least one entry in `text`, so an empty map cannot pass for a right one.
    var hasEntries = true

    var testDescription: String { name }
}

let outlineCorpus: [OutlineCase] = [
    OutlineCase(name: "headings one to six", text: "# Uno\n## Due\n### Tre\n#### Quattro\n##### Cinque\n###### Sei\n####### sette\n"),
    OutlineCase(name: "a tag line is not a heading", text: "#tag-uno non titolo\n# Titolo\n#client-acme\n"),
    OutlineCase(name: "embeds on their own line", text: "# Uno\n![[foto.png]]\ntesto\n![[doc.pdf|300]]\n## Due\n![alt](immagine.png)\n"),
    OutlineCase(name: "remote and inline embeds", text: "# Uno\n![x](https://example.com/a.png)\nun ![[inline.png]] nel testo\n![[locale.png]]\n"),
    OutlineCase(name: "CRLF lines", text: "# Uno\r\ncorpo\r\n## Due\r\n![[foto.png]]\r\n# Tre\r\n"),
    OutlineCase(name: "a heading as the last line without a terminator", text: "testo\n# Ultimo"),
    OutlineCase(name: "a heading as the last line with a terminator", text: "testo\n# Ultimo\n"),
    OutlineCase(name: "headings inside a backtick fence", text: "# Fuori\n```\n# dentro\n![[x.png]]\n```\n## Dopo\n"),
    OutlineCase(name: "headings inside a tilde fence", text: "# Fuori\n~~~\n# dentro\n~~~\n## Dopo\n"),
    OutlineCase(name: "headings inside a pergamenum-view fence", text: "# Fuori\n```pergamenum-view\n# dentro\nfrom: tag\n```\n## Dopo\n"),
    OutlineCase(name: "an unclosed fence swallows the rest", text: "# Fuori\n```\n# dentro\n## anche questo\n"),
    OutlineCase(name: "a frontmatter block holding a hash", text: "---\ndate: 2026-10-13\n# x\ntags: []\n---\n# Titolo\ntesto\n"),
    OutlineCase(name: "a setext heading is not an entry", text: "Titolo\n======\n\nSottotitolo\n-----------\n# Vero\n"),
    OutlineCase(name: "markup in a title", text: "## Vedi [[Altra nota]] e **forte**\n# `codice` qui\n"),
    OutlineCase(name: "indented lines", text: "   # Indentato\n\t## Con tab\n    ### Quattro spazi\n"),
    OutlineCase(name: "no entries at all", text: "solo testo\nsu due righe\n", hasEntries: false),
    OutlineCase(name: "an empty note", text: "", hasEntries: false),
    OutlineCase(name: "accents and emoji before a heading", text: "è già così 🎉 ò\n# Titolo è\ncorpo\n## Due 🎉\nfine\n"),
]

@MainActor
@Suite struct OutlineMapCorpus {
    @Test(arguments: outlineCorpus)
    func theItemsEqualTheParse(_ c: OutlineCase) {
        let map = OutlineMap(text: c.text)
        let expected = OutlineOracle.items(c.text)
        if c.hasEntries { #expect(!expected.isEmpty, "the corpus case holds no entry: \(c.name)") }
        #expect(map.items == expected)
        #expect(map.entries.count == expected.count)
    }

    @Test(arguments: outlineCorpus)
    func rebuildReadsTheSameAsTheInit(_ c: OutlineCase) {
        var map = OutlineMap()
        #expect(map.items.isEmpty)
        map.rebuild(text: c.text)
        #expect(map.items == OutlineOracle.items(c.text))
        #expect(map == OutlineMap(text: c.text))
    }

    @Test(arguments: outlineCorpus)
    func theOrdinalsEqualTheFreshTranslation(_ c: OutlineCase) {
        let map = OutlineMap(text: c.text)
        let items = OutlineOracle.items(c.text)
        let length = (c.text as NSString).length
        // Every entry's offset, and two that name nothing: one inside an entry's line, one past the end.
        var offsets = Set(items.map(\.range.location))
        offsets.insert(length + 7)
        if let first = items.first { offsets.insert(first.range.location + 1) }
        #expect(map.ordinals(ofOffsets: offsets) == foldedOrdinals(ofOffsets: offsets, in: c.text))
        for offset in offsets {
            #expect(
                map.ordinals(ofOffsets: [offset]) == foldedOrdinals(ofOffsets: [offset], in: c.text),
                "offset \(offset)"
            )
        }
        #expect(map.ordinals(ofOffsets: []).isEmpty)
        if c.hasEntries { #expect(!map.ordinals(ofOffsets: Set(items.map(\.range.location))).isEmpty) }
    }

    @Test(arguments: outlineCorpus)
    func isFoldableEqualsTheFoldableEntries(_ c: OutlineCase) {
        let map = OutlineMap(text: c.text)
        let foldable = NoteFolding.foldableEntries(in: c.text)
        let count = NoteOutline.entries(in: c.text).count
        for ordinal in 0..<count {
            #expect(map.isFoldable(ordinal) == foldable.contains(ordinal), "entry \(ordinal)")
        }
    }

    @Test(arguments: outlineCorpus)
    func theLevelOfAnEntryIsTheParsesLevel(_ c: OutlineCase) {
        let map = OutlineMap(text: c.text)
        for (ordinal, entry) in NoteOutline.entries(in: c.text).enumerated() {
            #expect(map.level(ofEntry: ordinal) == entry.level, "entry \(ordinal)")
        }
    }

    @Test(arguments: outlineCorpus)
    func lastEntryAtOrBeforeIsTheLinearScan(_ c: OutlineCase) {
        let map = OutlineMap(text: c.text)
        let locations = OutlineOracle.items(c.text).map(\.range.location)
        let length = (c.text as NSString).length
        for caret in 0...length {
            #expect(
                map.lastEntry(atOrBefore: caret) == locations.lastIndex { $0 <= caret },
                "caret \(caret)"
            )
        }
    }
}

// MARK: - Edits driven by hand

@MainActor
@Suite struct OutlineMapEdits {
    @Test func anEditAboveMovesTheEntriesBelowAndKeepsTheOnesAbove() throws {
        let before = "# Uno\ncorpo\nintro\n## Due\nfine\n"
        var map = OutlineMap(text: before)
        let items = map.items
        // `#require`, not `#expect`: the lines below index `items`, and an empty map must fail the test
        // and not stop the run.
        try #require(items.count == 2)

        // Two characters typed in the line "intro": the second heading moves by two, the first does not.
        let typed = (before as NSString).replacingCharacters(in: NSRange(location: 12, length: 0), with: "xx")
        map.apply(StorageEdit(range: NSRange(location: 12, length: 2), delta: 2))
        #expect(map.items.map(\.title) == items.map(\.title))
        #expect(map.items.map(\.range.location) == [items[0].range.location, items[1].range.location + 2])
        #expect(map.items == OutlineOracle.items(typed))
    }

    @Test func aSpliceReadsTheLinesOfTheDirtyRange() {
        let before = "intro\ncorpo\nfine\n"
        var map = OutlineMap(text: before)
        #expect(map.items.isEmpty)

        // A heading line typed between the first two lines.
        let after = "intro\n# Nuovo\ncorpo\nfine\n"
        let dirty = NSRange(location: 6, length: 8)
        map.apply(StorageEdit(range: dirty, delta: 8))
        map.splice(after as NSString, in: dirty, fences: StructureMap(text: after).fences)
        #expect(map.items == OutlineOracle.items(after))
        #expect(map.items.map(\.title) == ["Nuovo"])
    }

    @Test func aSpliceSkipsTheLinesAFenceCovers() {
        let after = "# Uno\n```\n# dentro\n```\n## Due\n"
        var map = OutlineMap(text: "# Uno\n```\nx\n```\n## Due\n")
        let dirty = NSRange(location: 10, length: 9)
        // "x\n" became "# dentro\n" inside the closed fence: no entry appears.
        map.apply(StorageEdit(range: dirty, delta: 7))
        map.splice(after as NSString, in: dirty, fences: StructureMap(text: after).fences)
        #expect(map.items == OutlineOracle.items(after))
        #expect(map.items.map(\.title) == ["Uno", "Due"])
    }

    @Test func aSpliceDropsTheEntryOfALineThatStoppedBeingOne() {
        let before = "# Uno\ncorpo\n## Due\n"
        var map = OutlineMap(text: before)
        #expect(map.items.count == 2)
        // The second heading's "## " is deleted: the line becomes prose.
        let after = "# Uno\ncorpo\nDue\n"
        let dirty = NSRange(location: 12, length: 4)
        map.apply(StorageEdit(range: NSRange(location: 12, length: 0), delta: -3))
        map.splice(after as NSString, in: dirty, fences: StructureMap(text: after).fences)
        #expect(map.items == OutlineOracle.items(after))
        #expect(map.items.map(\.title) == ["Uno"])
    }
}

// MARK: - The per-line rule in Core

struct OutlineLineRuleTests {
    @Test func aHeadingIsItsLevelAndItsPlainTitle() {
        #expect(NoteOutline.entry(inLine: "# Uno") == NoteOutline.LineEntry(kind: .heading(level: 1), title: "Uno"))
        #expect(NoteOutline.entry(inLine: "### Tre") == NoteOutline.LineEntry(kind: .heading(level: 3), title: "Tre"))
        #expect(NoteOutline.entry(inLine: "## Vedi [[Altra nota]]") == NoteOutline.LineEntry(kind: .heading(level: 2), title: "Vedi Altra nota"))
    }

    @Test func aTagOrASeventhHashIsNoEntry() {
        #expect(NoteOutline.entry(inLine: "#tag-uno") == nil)
        #expect(NoteOutline.entry(inLine: "####### sette") == nil)
        #expect(NoteOutline.entry(inLine: "testo") == nil)
        #expect(NoteOutline.entry(inLine: "") == nil)
    }

    @Test func anEmbedOnItsOwnLineIsAnEntryAndARemoteOneIsNot() {
        #expect(NoteOutline.entry(inLine: "![[foto.png]]") == NoteOutline.LineEntry(kind: .embed, title: "foto.png"))
        #expect(NoteOutline.entry(inLine: "![alt](immagine.png)") == NoteOutline.LineEntry(kind: .embed, title: "alt"))
        #expect(NoteOutline.entry(inLine: "![x](https://example.com/a.png)") == nil)
    }

    @Test func theRuleGivesEntriesInTheSameKindsAndTitlesAsTheParse() {
        // The parse is the oracle: every line of a mixed text, trimmed as `entries(in:)` trims it.
        let text = "# Uno\n![[foto.png]]\ncorpo\n## Due **forte**\n#tag\n![x](https://e.com/a.png)\n"
        let fromRule = text.split(separator: "\n", omittingEmptySubsequences: false).compactMap {
            NoteOutline.entry(inLine: $0.trimmingCharacters(in: .whitespaces))
        }
        let fromParse = NoteOutline.entries(in: text).map { NoteOutline.LineEntry(kind: $0.kind, title: $0.title) }
        #expect(!fromParse.isEmpty)
        #expect(fromRule == fromParse)
    }
}
