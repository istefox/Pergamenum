import Foundation
import Testing

// ADR-0093 §D3, plan docs/plans/scoped-layout-followup.md, Task 3 (R-08).
//
// A whole-document invalidation of a note editor goes through one door, `LayoutDebt.invalidateWholeDocument(of:)`
// in `NoteTextView+Layout.swift`, because a site that calls `invalidateLayout(` itself leaves the record
// believing the layout is current while TextKit's is not. The editor's surfaces are the three
// directories that build a `NoteTextView`. This reads the source, as `UITestLaunchHarnessGuardTests`
// does, since nothing at run time can see a call that was never routed.
//
// The Folding, Transclusion and ViewBlocks controllers call the door, and outside the door's own file
// nothing in these directories calls `invalidateLayout(`. (`Sources/Features/Workspace/CardTextView+Fold.swift` has a call of its own, outside these
// directories on purpose: a card has no record to keep.)

@Suite struct LayoutDoorGuard {
    private static let door = "NoteTextView+Layout.swift"
    private static let directories = ["Sources/Features/Editor", "Sources/Features/Today", "Sources/Features/Diary"]

    /// Every `.swift` file under the directories, recursively. A file that cannot be read is
    /// recorded, never skipped: a guard that read nothing would pass.
    private static func sources() throws -> [(path: String, contents: String)] {
        let root = try resolvedRepoRoot()
        var found: [(path: String, contents: String)] = []
        for directory in directories {
            let base = root.appendingPathComponent(directory)
            guard let walker = FileManager.default.enumerator(atPath: base.path) else {
                Issue.record("cannot list \(directory)")
                continue
            }
            for case let relative as String in walker where relative.hasSuffix(".swift") {
                let path = "\(directory)/\(relative)"
                guard let contents = try? String(
                    contentsOf: base.appendingPathComponent(relative), encoding: .utf8
                ) else {
                    Issue.record("unreadable source: \(path)")
                    continue
                }
                found.append((path, contents))
            }
        }
        return found.sorted { $0.path < $1.path }
    }

    /// The calls in `contents`: `(line, text)` of every line that is not a comment and has the call.
    static func calls(in contents: String) -> [(line: Int, text: String)] {
        var found: [(line: Int, text: String)] = []
        for (index, line) in contents.components(separatedBy: "\n").enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") { continue }
            if trimmed.contains("invalidateLayout(") { found.append((index + 1, trimmed)) }
        }
        return found
    }

    // (R-08) No file outside the door calls `invalidateLayout(`.
    @Test func noEditorSurfaceInvalidatesTheLayoutOutsideTheDoor() throws {
        let sources = try Self.sources()
        // 157 files at the time of writing: far fewer means the listing went wrong.
        #expect(sources.count >= 150, "only \(sources.count) files read under \(Self.directories)")
        #expect(sources.contains { $0.path.hasSuffix(Self.door) }, "the door file is missing")

        var offences: [String] = []
        for source in sources where !source.path.hasSuffix(Self.door) {
            for call in Self.calls(in: source.contents) {
                offences.append("\(source.path):\(call.line): \(call.text)")
            }
        }
        #expect(offences.isEmpty, "route these through LayoutDebt.invalidateWholeDocument(of:): \(offences)")
    }

    // (R-08) The scan itself: a call is found, a comment is not, a call in a comment after code still is.
    @Test func theScanFindsACallAndSkipsAComment() {
        let text = """
        func a() {
            // manager.invalidateLayout(for: range)
            /// invalidateLayout(for:) is the door
            manager.invalidateLayout(for: manager.documentRange)
        }
        """
        let found = Self.calls(in: text)
        #expect(found.count == 1)
        #expect(found.first?.line == 4)
    }
}
