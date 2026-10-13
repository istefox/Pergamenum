import Foundation
import Testing
@testable import Pergamenum

// ADR-0096 §D3 (planned), plan docs/plans/no-whole-note-term-on-the-update-path-pg-406.md, Task 2 (PG-406).
// R-08: save, close and quit decide on the exact compare, never on the mark. The mark is cheap and may
// read dirty late; a decision that read it would keep a buffer undone back to its saved text in the quit
// question. Nothing at run time tells the two apart before the pause fires, so the call sites are read.
//
// The sites are plan item 8's decision list, checked against the tree at `32cd8ed2`. A display site
// (`NoteTabBar`, `VaultTopBar`, `CommandActions+CanRun`) reads `hasUnsavedChanges` on purpose and is
// not listed.

/// File, and how many lines of it decide on a buffer's dirtiness. Every one of those lines must name
/// `differsFromSaved` (at least that many do), and the file must name `hasUnsavedChanges` nowhere outside a comment.
private let decisionFiles: [(path: String, sites: Int)] = [
    ("Sources/App/CommandActions.swift", 1),
    ("Sources/App/VaultController+Tabs.swift", 1),
    ("Sources/App/QuitReview.swift", 1),
    ("Sources/App/VaultController+Quit.swift", 1),
    ("Sources/App/VaultController+Files.swift", 1),
    ("Sources/App/VaultController+Folders.swift", 1),
    ("Sources/App/VaultController+TabFollowUps.swift", 1),
    ("Sources/App/VaultController+Editing.swift", 2),
    ("Sources/App/VaultController+NoteBirth.swift", 2),
    ("Sources/Features/Editor/EditorColumn+Closing.swift", 1),
]

@Suite struct UnsavedMarkSourceGuardTests {
    private func code(_ relativePath: String) throws -> [String] {
        let root = try resolvedRepoRoot()
        let source = try String(contentsOf: root.appending(path: relativePath), encoding: .utf8)
        return source.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    @Test(arguments: decisionFiles.map(\.path))
    func aDecisionSiteReadsTheExactAnswer(_ path: String) throws {
        let lines = try code(path)
        let expected = try #require(decisionFiles.first { $0.path == path }).sites

        // `openBoard.hasUnsavedChanges` is the Workspace board's own mark (PG-392, ADR-0095), not a note
        // buffer's: `VaultController+Folders.swift` reads it beside the note check. The guard is about `OpenNote`.
        let marked = lines.filter { $0.contains("hasUnsavedChanges") && !$0.contains("openBoard.hasUnsavedChanges") }
        let exact = lines.filter { $0.contains("differsFromSaved") }
        #expect(marked.isEmpty, "\(path) decides on the mark: \(marked)")
        #expect(exact.count >= expected, "\(path) reads differsFromSaved on \(exact.count) lines, expected \(expected)")
    }

    /// The lines of the function whose signature contains `needle`, up to the closing brace at the
    /// signature's own indentation; nil when no line has it. A signature spread over several lines is
    /// read from the line carrying `needle`, which is all the bodies below need.
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

    // `catchUp` is the one decision inside the buffer itself: its departure 15 compare is the exact
    // answer, and the `.text` branch takes the incoming text through `adopt`, which links the revisions.
    @Test func catchUpDecidesOnTheExactAnswerAndAdopts() throws {
        let lines = try code("Sources/Vault/NoteTab.swift")
        let found = body(of: "mutating func catchUp(to", in: lines)
        let catchUp = try #require(found, "catchUp is gone from NoteTab.swift")

        #expect(!catchUp.contains("hasUnsavedChanges"), "catchUp reads the mark")
        #expect(catchUp.contains("differsFromSaved"), "catchUp does not read the exact answer")
        #expect(catchUp.contains("adopt("), "catchUp's .text branch does not adopt")
    }

    // `OpenNote.==` reads the revisions and the fields that are not the text. A body that named the
    // text would put the whole-note compare back under SwiftUI's diff.
    @Test func theBuffersEqualityNamesNeitherTextNorSavedText() throws {
        var found: String?
        for path in ["Sources/Vault/NoteTab.swift", "Sources/Vault/OpenNote+Revision.swift"] where found == nil {
            found = body(of: "static func ==", in: try code(path))
        }
        let equality = try #require(found, "OpenNote has no hand-written ==")

        #expect(equality.contains("revision"), "== does not read the revision")
        #expect(!equality.contains("savedText"), "== compares savedText")
        #expect(equality.range(of: #"\.text\b"#, options: .regularExpression) == nil, "== compares text")
    }
}
