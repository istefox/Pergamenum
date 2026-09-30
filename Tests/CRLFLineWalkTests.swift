import Foundation
import Testing
@testable import Pergamenum

/// PG-274 and PG-316: "\r\n" is one Swift Character, so a line walk that searches for "\n" never
/// finds a CRLF line's end. These pin every line walk that learned CRLF - note jumps, code fences,
/// folding, transclusion, section moves, tables, tasks, code spans and the card toggle - on both
/// endings, and the writes on a note that mixes the two.

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

// MARK: - Tables, tasks, code spans and the card toggle (PG-316)
//
// PG-274's residual walks. Each test writes the note in LF, derives the CRLF twin, and expects
// the same reading - and, for a write, the LF result with its ending turned into CRLF.

@Test func aCRLFTableIsFoundRowByRow() throws {
    let lf = "prima\n| a | b |\n|---|:-:|\n| 1 | 2 |\n\ndopo\n"
    let twin = crlf(lf)
    let lfTables = GFMTable.runs(in: lf, from: lf.startIndex, outside: [])
    let tables = GFMTable.runs(in: twin, from: twin.startIndex, outside: [])
    #expect(lfTables.count == 1)
    #expect(tables.count == 1)
    let table = try #require(tables.first)
    #expect(table.header == ["a", "b"])
    #expect(table.alignments == [.leading, .center])
    #expect(table.rows == [["1", "2"]])
    #expect(table.lineRanges.map { String(twin[$0]) } == ["| a | b |", "|---|:-:|", "| 1 | 2 |"])
    #expect(String(twin[table.range]) == crlf(String(lf[lfTables[0].range])))
}

@Test func aTableSerialisesWithTheLineBreakItIsGiven() throws {
    let table = try #require(GFMTable.parse(["| a | b |", "|---|---|", "| 1 | 2 |"][...]))
    #expect(table.serialised() == "| a | b |\n|---|---|\n| 1 | 2 |")
    #expect(table.serialised(lineBreak: .crlf) == crlf(table.serialised()))
}

private let taskNote = "# Lista\n- [ ] uno\n\n- [x] due @done(2026-01-01)\n```\n- [ ] codice\n```\n- [ ] tre"

@Test func tasksOfACRLFNoteMatchTheirLFTwin() {
    let lf = TaskParser.tasks(in: taskNote, sourcePath: "N.md")
    let cr = TaskParser.tasks(in: crlf(taskNote), sourcePath: "N.md")
    #expect(lf.map(\.lineIndex) == [1, 3, 7])
    #expect(cr.map(\.lineIndex) == lf.map(\.lineIndex))
    #expect(cr.map(\.rawLine) == lf.map(\.rawLine))
    #expect(cr.map(\.text) == lf.map(\.text))
    #expect(cr.map(\.state) == lf.map(\.state))
}

@Test func rewritingATaskLineKeepsTheCRLFEnding() throws {
    let twin = crlf(taskNote)
    for task in TaskParser.tasks(in: taskNote, sourcePath: "N.md") {
        let newLine = task.rawLine + " ^id(9)"
        let lf = try #require(
            TaskParser.rewrite(taskNote, at: task.lineIndex, expecting: task.rawLine, with: newLine)
        )
        let crTask = try #require(
            TaskParser.tasks(in: twin, sourcePath: "N.md").first { $0.lineIndex == task.lineIndex }
        )
        let cr = TaskParser.rewrite(twin, at: crTask.lineIndex, expecting: crTask.rawLine, with: newLine)
        #expect(cr == crlf(lf), "riga \(task.lineIndex)")
    }
    // A stale expectation is still refused.
    #expect(TaskParser.rewrite(twin, at: 1, expecting: "- [ ] altro", with: "x") == nil)
}

@Test func insertingASubtaskKeepsTheCRLFEnding() throws {
    // A parent in the middle of the note, and one on the last line with no terminator of its own.
    for note in ["- [ ] padre\n- [ ] altro\n", "prima\n- [ ] padre"] {
        let twin = crlf(note)
        let draft = TaskParser.SubtaskDraft(text: "figlio")
        let lfParent = try #require(TaskParser.tasks(in: note, sourcePath: "N.md").first { $0.text == "padre" })
        let crParent = try #require(TaskParser.tasks(in: twin, sourcePath: "N.md").first { $0.text == "padre" })
        let lf = try #require(TaskParser.insertingSubtask(in: note, below: lfParent, draft: draft))
        let cr = TaskParser.insertingSubtask(in: twin, below: crParent, draft: draft)
        #expect(cr == crlf(lf), "nota \(note.debugDescription)")
    }
}

@Test func codeRangesOfACRLFNoteMatchTheirLFTwin() {
    let lf = "[[Fuori]]\n```\n[[Dentro]]\n```\nuna `[[Span]]` e [[Dopo]]\n`aperto\nchiuso` [[Ultimo]]\n"
    let twin = crlf(lf)
    #expect(WikilinkParser.links(in: lf).map(\.target) == ["Fuori", "Dopo", "Ultimo"])
    #expect(WikilinkParser.links(in: twin).map(\.target) == ["Fuori", "Dopo", "Ultimo"])
    #expect(WikilinkParser.codeRanges(in: twin).map { String(twin[$0]) }
        == WikilinkParser.codeRanges(in: lf).map { crlf(String(lf[$0])) })
}

@MainActor
@Test func aCardParagraphOffsetCountsCRLFLines() {
    let lf = "- [ ] uno\n\n- [ ] due\n- [ ] tre"
    let twin = crlf(lf)
    // Paragraph starts in UTF-16: every CRLF line break is one code unit longer than its LF twin.
    #expect(FormattingTextView.lineIndex(atParagraphOffset: 0, in: twin) == 0)
    #expect(FormattingTextView.lineIndex(atParagraphOffset: 11, in: lf) == 2)
    #expect(FormattingTextView.lineIndex(atParagraphOffset: 13, in: twin) == 2)
    #expect(FormattingTextView.lineIndex(atParagraphOffset: 21, in: lf) == 3)
    #expect(FormattingTextView.lineIndex(atParagraphOffset: 24, in: twin) == 3)
}

@MainActor
@Test func togglingACardTaskKeepsTheCRLFEnding() throws {
    let root = try CanvasTemporaryRoot()
    try root.makeDirectory("A")
    let store = CanvasStore(root: root.url)
    let board = try store.createBoard(named: "A", in: "A")
    let controller = WorkspaceController()
    controller.attach(to: store)
    defer { controller.detach() }
    controller.open(board: board)

    let lf = "- [ ] uno\n- [x] due @done(2026-01-01)\n- [ ] tre"
    let lfNode = controller.addStickyNote(lf, at: .zero)
    let crNode = controller.addStickyNote(crlf(lf), at: CGPoint(x: 300, y: 0))
    func text(_ id: String) -> String? {
        if case .text(let stored) = controller.document.node(id: id)?.kind { return stored }
        return nil
    }
    for line in 0..<3 {
        controller.toggleTask(atLineIndex: line, forNodeID: lfNode)
        controller.toggleTask(atLineIndex: line, forNodeID: crNode)
        #expect(text(crNode) == text(lfNode).map(crlf), "riga \(line)")
    }
    #expect(text(lfNode)?.hasPrefix("- [x] uno @done(") == true)
    #expect(text(lfNode)?.contains("\n- [ ] due\n") == true)
}

@MainActor
@Test func committingACellOfACRLFTableKeepsItsRowsCRLF() {
    let lf = "prima\n| a | b |\n|---|---|\n| 1 | 2 |\ndopo\n"
    let twin = crlf(lf)
    let fixture = EmbedEditorFixtures.editor(text: twin, hidesMarkup: true, root: nil, thumbnails: nil)
    // "prima\r\n" is seven UTF-16 units; the header paragraph starts right after it.
    let committed = fixture.coordinator.commitTable(
        .cell(row: 0, column: 0, text: "9"), at: 7, in: fixture.textView
    )
    #expect(committed)
    #expect(fixture.textView.string == crlf("prima\n| a | b |\n|---|---|\n| 9 | 2 |\ndopo\n"))
}

// MARK: - Each code-range walk on its own (PG-316 review)
//
// `codeRanges` has two walks: the fence pass and the backtick-span pass. The combined test above
// would stay green if one of them still read a CRLF note as one line and the other hid it, so
// each is pinned by a note only it can get wrong.

@Test func aCRLFFenceHidesItsLinksWithoutAnyBacktickSpan() {
    let lf = "[[Fuori]]\n```\n[[Dentro]]\n```\n[[Dopo]]\n"
    let twin = crlf(lf)
    #expect(WikilinkParser.links(in: lf).map(\.target) == ["Fuori", "Dopo"])
    #expect(WikilinkParser.links(in: twin).map(\.target) == ["Fuori", "Dopo"])
    #expect(WikilinkParser.codeRanges(in: twin).count == 1)
}

@Test func aCRLFBacktickSpanStopsAtItsLineEndWithoutAnyFence() {
    // The lone backtick on line 2 must not pair with the one on line 4: a span never crosses a line.
    let lf = "[[Uno]] `aperto\n[[Due]]\n[[Tre]] `altro\n[[Quattro]]\n"
    let twin = crlf(lf)
    let expected = WikilinkParser.links(in: lf).map(\.target)
    #expect(expected == ["Uno", "Due", "Tre", "Quattro"])
    #expect(WikilinkParser.links(in: twin).map(\.target) == expected)
    #expect(WikilinkParser.codeRanges(in: twin).isEmpty)
}

@Test func aFencedTaskInACRLFNoteIsNotATask() {
    let twin = crlf("- [ ] fuori\n```\n- [ ] dentro\n```\n- [ ] dopo\n")
    let tasks = TaskParser.tasks(in: twin, sourcePath: "N.md")
    #expect(tasks.map(\.text) == ["fuori", "dopo"])
    #expect(tasks.map(\.lineIndex) == [0, 4])
}

// MARK: - A note that mixes LF and CRLF (PG-316 review)
//
// A write keeps each existing line's own ending (ADR-0065 §D3), so a mixed note stays mixed: the
// CRLF twins above cannot tell a per-line rule from a per-note one. Each note here is spelled as
// (content, ending) pairs, so the expectation names every line's ending explicitly.

private func joined(_ lines: [(content: String, ending: String)]) -> String {
    lines.map { $0.content + $0.ending }.joined()
}

@Test func rewritingATaskLineKeepsThatLinesOwnEndingInAMixedNote() {
    let lines: [(content: String, ending: String)] = [
        ("- [ ] uno", "\r\n"), ("- [ ] due", "\n"), ("- [ ] tre", "\r\n"), ("- [ ] quattro", ""),
    ]
    let note = joined(lines)
    let tasks = TaskParser.tasks(in: note, sourcePath: "N.md")
    #expect(tasks.map(\.lineIndex) == [0, 1, 2, 3])
    #expect(tasks.map(\.rawLine) == lines.map(\.content))
    for task in tasks {
        let newLine = task.rawLine + " ^id(9)"
        var expected = lines
        expected[task.lineIndex].content = newLine
        let rewritten = TaskParser.rewrite(note, at: task.lineIndex, expecting: task.rawLine, with: newLine)
        #expect(rewritten == joined(expected), "riga \(task.lineIndex)")
    }
}

@Test func aSubtaskEndsAsItsParentDoesInAMixedNote() throws {
    // `separator` is what the parent line ends with after the insertion: its own ending when it
    // had one, the note's (read off its first line break) when it was the unterminated last line.
    // The child always ends as the parent did.
    let cases: [(lines: [(content: String, ending: String)], parent: Int, separator: String)] = [
        ([("prima", "\r\n"), ("- [ ] padre", "\n"), ("- [ ] altro", "\r\n")], 1, "\n"),
        ([("prima", "\n"), ("- [ ] padre", "\r\n"), ("- [ ] altro", "\n")], 1, "\r\n"),
        ([("prima", "\r\n"), ("altro", "\n"), ("- [ ] padre", "")], 2, "\r\n"),
    ]
    let draft = TaskParser.SubtaskDraft(text: "figlio")
    for (lines, parentIndex, separator) in cases {
        let note = joined(lines)
        // The LF spelling of the same note gives the parent and child lines the insertion writes.
        let lfNote = lines.map(\.content).joined(separator: "\n")
        let lfParent = try #require(TaskParser.tasks(in: lfNote, sourcePath: "N.md").first { $0.text == "padre" })
        let lfLines = try #require(TaskParser.insertingSubtask(in: lfNote, below: lfParent, draft: draft))
            .components(separatedBy: "\n")
        let parent = try #require(TaskParser.tasks(in: note, sourcePath: "N.md").first { $0.text == "padre" })
        #expect(parent.lineIndex == parentIndex)

        var expected = lines
        expected[parentIndex] = (lfLines[parentIndex], separator)
        expected.insert((lfLines[parentIndex + 1], lines[parentIndex].ending), at: parentIndex + 1)
        let inserted = TaskParser.insertingSubtask(in: note, below: parent, draft: draft)
        #expect(inserted == joined(expected), "nota \(note.debugDescription)")
    }
}

@MainActor
@Test func committingACellOfAMixedTableUsesTheTablesFirstLineBreak() {
    // The table is rewritten whole, so its rows take one ending, read off the table's own first
    // line break (not the note's); the lines around it keep theirs.
    let cases: [(note: String, expected: String)] = [
        ("prima\n| a | b |\r\n|---|---|\n| 1 | 2 |\ndopo\n",
         "prima\n| a | b |\r\n|---|---|\r\n| 9 | 2 |\ndopo\n"),
        ("prima\r\n| a | b |\n|---|---|\r\n| 1 | 2 |\r\ndopo\r\n",
         "prima\r\n| a | b |\n|---|---|\n| 9 | 2 |\r\ndopo\r\n"),
    ]
    for (note, expected) in cases {
        let fixture = EmbedEditorFixtures.editor(text: note, hidesMarkup: true, root: nil, thumbnails: nil)
        // The header paragraph starts right after "prima" and its line break.
        let header = ("prima" as NSString).length + (note.hasPrefix("prima\r\n") ? 2 : 1)
        let committed = fixture.coordinator.commitTable(
            .cell(row: 0, column: 0, text: "9"), at: header, in: fixture.textView
        )
        #expect(committed, "nota \(note.debugDescription)")
        #expect(fixture.textView.string == expected, "nota \(note.debugDescription)")
    }
}
