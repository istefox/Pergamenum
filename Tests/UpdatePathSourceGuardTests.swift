import Foundation
import Testing
@testable import Pergamenum

// ADR-0095 §D5 to §D10, plan docs/plans/no-whole-note-term-on-the-update-path-pg-406.md, Task 4 (PG-406,
// R-02, R-04, R-05, R-07, R-10).
//
// Some of what makes a keystroke cheap is an absence that no counter can see: a view that names the
// parse, or stores the whole note, is invalidated by every key whether or not the run-time path measures
// it today. These read the sources, comments excluded, the way `UnsavedMarkSourceGuardTests` does. The
// files are the ones plan Task 4 names, checked against the tree at `32cd8ed2`. Red until Task 5 except
// `TodayView`, whose binding already goes through `updateOpenNoteText`.

private func sourceLines(_ relativePath: String) throws -> [String] {
    let root = try resolvedRepoRoot()
    let source = try String(contentsOf: root.appending(path: relativePath), encoding: .utf8)
    return source.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
}

/// The lines of the declaration whose signature line contains `needle`, up to the closing brace at the
/// signature's own indentation; nil when no line has it.
private func body(of needle: String, in lines: [String]) -> String? {
    guard let start = lines.firstIndex(where: { $0.contains(needle) }) else { return nil }
    let indent = String(lines[start].prefix { $0 == " " })
    var collected: [String] = []
    for line in lines[(start + 1)...] {
        if line == indent + "}" { break }
        collected.append(line)
    }
    return collected.joined(separator: "\n")
}

private func containsWord(_ word: String, in text: String) -> Bool {
    text.range(of: "\\b\(word)\\b", options: .regularExpression) != nil
}

/// The three calls that read the whole note, as patterns. `foldedOrdinals(` is the free function only: the
/// store's `foldedOrdinals(ofOffsets:describing:text:)` is a method, which the footer calls on purpose
/// (plan Task 5, item 7), and `OutlinePaneInputs.foldedOrdinals` is a property.
private let parseTerms: [(name: String, pattern: String)] = [
    ("NoteOutline.entries(in:", "NoteOutline\\.entries\\(in:"),
    ("foldedOrdinals(", "(?<![.\\w])foldedOrdinals\\("),
    ("NoteFolding.foldableEntries(", "NoteFolding\\.foldableEntries\\("),
]

private let keystrokePathFiles = [
    "Sources/Features/Editor/EditorColumn+Text.swift",
    "Sources/Features/Editor/NoteListPane+Footer.swift",
    "Sources/Features/Editor/OutlinePane.swift",
]

@Suite struct UpdatePathSourceGuards {
    // (R-02, R-07) The column, the footer and the pane read the outline from the store; none of them
    // parses the note, translates the folds or walks it for foldable sections.
    @Test(arguments: keystrokePathFiles)
    func theViewsNameNoParseOfTheNote(_ path: String) throws {
        let lines = try sourceLines(path)
        for term in parseTerms {
            let found = lines.filter { $0.range(of: term.pattern, options: .regularExpression) != nil }
            #expect(found.isEmpty, "\(path) names \(term.name): \(found)")
        }
    }

    // (R-07) The pane is drawn from `OutlinePaneInputs`: it holds no text, reads no observed property of
    // the vault in its own body, and is placed with `.equatable()` so a keystroke that moved no row skips it.
    @Test func theOutlinePaneHoldsNoTextAndReadsNoObservedVaultState() throws {
        let lines = try sourceLines("Sources/Features/Editor/OutlinePane.swift")
        #expect(!lines.contains { $0.contains("vault.currentOutlineEntry") }, "the pane reads the current entry itself")
        #expect(!lines.contains { $0.contains("vault.foldedEntries") }, "the pane reads the folds itself")
        #expect(!lines.contains { $0.contains("let text: String") }, "the pane still holds the note's text")
    }

    @Test func theFooterPlacesThePaneEquatable() throws {
        let lines = try sourceLines("Sources/Features/Editor/NoteListPane+Footer.swift")
        #expect(lines.contains { $0.contains(".equatable()") }, "the footer does not place the pane with .equatable()")
    }

    // (R-05) The find keeper hears the revision and reads the text when it needs it, not on every change.
    @Test func theFindKeeperHoldsNoTextAndWatchesNoText() throws {
        let lines = try sourceLines("Sources/Features/Editor/EditorColumn+Text.swift")
        let keeper = try #require(body(of: "private struct FindKeeping", in: lines), "FindKeeping is not declared")
        #expect(!keeper.contains("let text: String"), "FindKeeping still stores the whole note")
        #expect(!keeper.contains(".onChange(of: text)"), "FindKeeping still watches the whole note")
        #expect(keeper.contains(".onChange(of: revision)"), "FindKeeping does not watch the revision")
    }

    // (R-04) The tab chip draws a `ChipFace`; the two inspector sections take a title and a path. None of
    // them stores the buffer or the tab, so typing invalidates none of them.
    @Test(arguments: [
        "Sources/Features/Editor/BacklinksSection.swift", "Sources/Features/Editor/UnresolvedLinksSection.swift",
    ])
    func anInspectorSectionStoresNeitherTheBufferNorTheTab(_ path: String) throws {
        let code = try sourceLines(path).joined(separator: "\n")
        #expect(!code.contains("VaultController.OpenNote"), "\(path) stores the open note")
        #expect(!containsWord("NoteTab", in: code), "\(path) stores a tab")
    }

    @Test func theTabChipStoresAFaceAndNotTheTab() throws {
        let lines = try sourceLines("Sources/Features/Editor/NoteTabBar.swift")
        let chip = try #require(body(of: "private struct NoteTabChip", in: lines), "NoteTabChip is not declared")
        #expect(!chip.contains("VaultController.OpenNote"), "the chip stores the open note")
        #expect(!containsWord("NoteTab", in: chip), "the chip stores the tab")
        #expect(chip.contains("ChipFace"), "the chip does not take a ChipFace")
    }

    // (R-04) The inspector's category row reads the bounded frontmatter, not a parse of the whole note.
    @Test func theCategoryRowDoesNotParseTheNote() throws {
        let lines = try sourceLines("Sources/Features/Editor/VaultBrowser.swift")
        let found = lines.filter { $0.contains("NoteDocument.parse(") }
        #expect(found.isEmpty, "the inspector parses the whole note: \(found)")
        #expect(lines.contains { $0.contains("NoteDocument.frontmatter(in:") }, "the category row does not read the bounded frontmatter")
    }

    // (R-10) Diario's editor binding goes through `editorWrote`; Oggi's through `updateOpenNoteText`.
    @Test func diariosEditorBindingCallsEditorWrote() throws {
        let code = try sourceLines("Sources/Features/Diary/DiaryView.swift").joined(separator: "\n")
        #expect(code.contains("editorWrote("), "DiaryView's editor binding does not call editorWrote")
    }

    @Test func oggisEditorBindingGoesThroughUpdateOpenNoteText() throws {
        let code = try sourceLines("Sources/Features/Today/TodayView.swift").joined(separator: "\n")
        #expect(code.contains("updateOpenNoteText("), "TodayView does not bind through updateOpenNoteText")
    }

    // (R-02, R-07) The editor no longer takes the outline as ranges and ordinals, so nothing is parsed per
    // body to feed it. Doc comments are not counted.
    @Test(arguments: [
        "Sources/Features/Editor/NoteTextView+Coordinator.swift", "Sources/Features/Editor/NoteTextView+Inputs.swift",
    ])
    func theEditorNoLongerNamesTheOutlineRanges(_ path: String) throws {
        let found = try sourceLines(path).filter { $0.contains("outlineRanges") }
        #expect(found.isEmpty, "\(path) still names outlineRanges: \(found)")
    }
}
