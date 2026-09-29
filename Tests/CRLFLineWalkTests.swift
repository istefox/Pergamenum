import Foundation
import Testing
@testable import Pergamenum

/// PG-274: "\r\n" is one Swift Character, so a line walk that searches for "\n" never finds
/// a CRLF line's end. These pin `NoteJump.lineRange` and `CodeFence.regions` on both endings.

private func slices(_ text: String) -> [String] {
    var result: [String] = []
    var index = 0
    while let range = NoteJump.lineRange(index, in: text) {
        result.append(String(text[range]))
        index += 1
    }
    return result
}

@Test func noteJumpFindsEachLineOfACRLFNote() {
    let lf = "uno\ndue\n\ntre"
    let crlf = lf.replacingOccurrences(of: "\n", with: "\r\n")
    #expect(slices(lf) == ["uno", "due", "", "tre"])
    #expect(slices(crlf) == slices(lf))
    #expect(NoteJump.lineRange(4, in: crlf) == nil)
}

@Test func codeFenceFindsTheRegionOfACRLFNote() {
    let lf = "prima\n```swift\nlet a = 1\n```\ndopo\n"
    let crlf = lf.replacingOccurrences(of: "\n", with: "\r\n")
    let regions = CodeFence.regions(in: crlf)
    #expect(regions.count == 1)
    #expect(regions.first?.language == "swift")
    // The body runs up to the closing fence, so it carries the last line's break: "\n" for LF,
    // "\r\n" for CRLF - the same shape, one ending each.
    #expect(regions.first.map { String(crlf[$0.body]) } == "let a = 1\r\n")
    #expect(CodeFence.regions(in: lf).first.map { String(lf[$0.body]) } == "let a = 1\n")
    #expect(regions.first.map { String(crlf[$0.range]) } == "```swift\r\nlet a = 1\r\n```")
    #expect(CodeFence.regions(in: lf).count == 1)
}

// MARK: - Folding, transclusion and section moves (PG-274 review)
//
// NoteOutline reports per-line CRLF headings, so every consumer that turns a heading into a
// line span has to count CRLF lines the way it counts LF ones. Each test writes the note once
// in LF and derives the CRLF twin, so the two can only differ by their ending.

private func crlf(_ lf: String) -> String { lf.replacingOccurrences(of: "\n", with: "\r\n") }

private let sectionNote = "## Uno\ncorpo uno\n### Due\ncorpo due\n## Tre\ncorpo tre\n"

private func sections(_ text: String) -> [String?] {
    NoteOutline.entries(in: text).indices.map { entry in
        NoteFolding.sectionRange(in: text, headingAt: entry).map { String(text[$0]) }
    }
}

private func applied(_ replacements: [(range: NSRange, text: String)]?, to text: String) -> String? {
    guard let replacements else { return nil }
    let mutable = NSMutableString(string: text)
    for (range, replacement) in replacements { mutable.replaceCharacters(in: range, with: replacement) }
    return mutable as String
}

@Test func sectionRangeStopsAtTheNextHeadingInACRLFNote() {
    let lf = sections(sectionNote)
    #expect(lf == ["## Uno\ncorpo uno\n### Due\ncorpo due", "### Due\ncorpo due", "## Tre\ncorpo tre\n"])
    #expect(sections(crlf(sectionNote)) == lf.map { $0.map(crlf) })
}

@Test func hiddenLinesOfAFoldMatchBetweenLFAndCRLF() {
    let lf = NoteFolding.hiddenParagraphs(in: sectionNote, foldedEntries: [0])
    #expect(lf == [1, 2, 3])
    #expect(NoteFolding.hiddenParagraphs(in: crlf(sectionNote), foldedEntries: [0]) == lf)
    #expect(NoteFolding.layout(in: crlf(sectionNote), foldedEntries: [0])
        == NoteFolding.layout(in: sectionNote, foldedEntries: [0]).mapOffsets(for: sectionNote, crlf: crlf(sectionNote)))
}

private extension NoteFolding.Layout {
    /// The same layout re-expressed in the CRLF twin's UTF-16 offsets: every LF before an
    /// offset became two code units.
    func mapOffsets(for lf: String, crlf: String) -> NoteFolding.Layout {
        func shift(_ offset: Int) -> Int {
            let prefix = String(lf.utf16.prefix(offset)) ?? ""
            return offset + prefix.filter { $0 == "\n" }.count
        }
        return NoteFolding.Layout(
            hiddenLineOffsets: Set(hiddenLineOffsets.map(shift)),
            foldedHeadings: Dictionary(uniqueKeysWithValues: foldedHeadings.map { (shift($0.key), $0.value) })
        )
    }
}

@Test func excerptOfALastSectionIsThatSectionInACRLFNote() {
    // Before the fix a CRLF note answered the whole note for "Tre" - the section's own comment
    // forbids quietly showing the note when the section is not the answer.
    #expect(Transclusion.excerpt(of: sectionNote, section: "Tre") == "## Tre\ncorpo tre\n")
    #expect(Transclusion.excerpt(of: crlf(sectionNote), section: "Tre") == crlf("## Tre\ncorpo tre\n"))
    #expect(Transclusion.excerpt(of: crlf(sectionNote), section: "Uno") == crlf("## Uno\ncorpo uno\n### Due\ncorpo due"))
    #expect(Transclusion.excerpt(of: crlf(sectionNote), section: "Assente") == nil)
}

@Test func aTranscludedNoteLineIsFoundInACRLFNote() {
    let lf = "intro\n![[Altra]]\n![foto](foto.png)\nfine\n"
    #expect(Transclusion.occurrences(in: lf).map(\.reference) == ["Altra"])
    #expect(Transclusion.occurrences(in: crlf(lf)).map(\.reference) == ["Altra"])
    #expect(Transclusion.embeddedFiles(in: lf) == ["foto.png"])
    #expect(Transclusion.embeddedFiles(in: crlf(lf)) == ["foto.png"])
}

@Test func draggingASubsectionToTheEndMatchesBetweenLFAndCRLF() throws {
    let note = "## Uno\n### Due\n## Tre"
    let lfResult = try #require(applied(OutlineMove.replacements(in: note, moving: 1, toPrecede: nil), to: note))
    #expect(lfResult == "## Uno\n## Tre\n## Due")
    let twin = crlf(note)
    let crlfResult = try #require(applied(OutlineMove.replacements(in: twin, moving: 1, toPrecede: nil), to: twin))
    #expect(crlfResult == crlf(lfResult))
}

@Test func sectionMovesMatchBetweenLFAndCRLF() throws {
    let note = "# A\ncorpo a\n## A1\ncorpo a1\n# B\ncorpo b\n# C\ncorpo c\n"
    let twin = crlf(note)
    for entry in 0..<5 {
        for destination in [nil, 0, 1, 2, 3, 4] as [Int?] {
            let lf = applied(OutlineMove.replacements(in: note, moving: entry, toPrecede: destination), to: note)
            let cr = applied(OutlineMove.replacements(in: twin, moving: entry, toPrecede: destination), to: twin)
            #expect(cr == lf.map(crlf), "move \(entry) before \(String(describing: destination))")
        }
        for target in 0..<5 {
            let lf = applied(OutlineMove.replacements(in: note, moving: entry, nestingUnder: target), to: note)
            let cr = applied(OutlineMove.replacements(in: twin, moving: entry, nestingUnder: target), to: twin)
            #expect(cr == lf.map(crlf), "nest \(entry) under \(target)")
        }
    }
    // A note with no trailing terminator: the moved section needs a leading one, in the note's own ending.
    let bare = "# A\n## A1\n# B"
    let lfBare = try #require(applied(OutlineMove.replacements(in: bare, moving: 0, toPrecede: nil), to: bare))
    let crBare = try #require(applied(OutlineMove.replacements(in: crlf(bare), moving: 0, toPrecede: nil), to: crlf(bare)))
    #expect(crBare == crlf(lfBare))
}
