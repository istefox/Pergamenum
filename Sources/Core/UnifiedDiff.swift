import Foundation

/// A unified diff between two versions of a text, for showing a write before it
/// happens.
///
/// Written here rather than shelled out to `diff(1)`: a guardrail that depends on an
/// external process is a guardrail that can be missing, and this has to work the same
/// whether it runs from a shell or from an MCP server answering a model (ADR-0007 §D6).
///
/// Line-based, which is what a markdown note wants: the unit a person reads a change in
/// is the line, and a character-level diff of a rewritten task line would show the
/// letters that moved rather than the fact that a date changed.
enum UnifiedDiff {
    /// Renders the change, or nil when there is none.
    ///
    /// Nil rather than an empty string, so a caller can tell "nothing would change"
    /// from "something changed and rendered to nothing" - the first is worth saying out
    /// loud before a write is skipped.
    /// `isNew` names the file that is not there yet as `/dev/null`, the way `diff -u`
    /// does. Calling it `a/<path>` would say a file exists that does not, and the
    /// commonest write a connector makes is creating a note.
    static func between(
        _ before: String, _ after: String, path: String, context: Int = 3, isNew: Bool = false
    ) -> String? {
        guard before != after else { return nil }

        let old = isNew ? [] : before.components(separatedBy: "\n")
        let new = after.components(separatedBy: "\n")
        let edits = diff(old, new)

        var lines = [isNew ? "--- /dev/null" : "--- a/\(path)", "+++ b/\(path)"]
        for hunk in hunks(from: edits, context: context) {
            lines.append(hunk.header)
            lines.append(contentsOf: hunk.lines)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: The edit script

    enum Edit: Equatable {
        case keep(String)
        case remove(String)
        case insert(String)
    }

    /// Longest common subsequence, walked back into an edit script.
    ///
    /// The table is O(n·m) in memory, which for a note is nothing and for a book would
    /// matter; notes are what this reads.
    static func diff(_ old: [String], _ new: [String]) -> [Edit] {
        var lengths = Array(
            repeating: Array(repeating: 0, count: new.count + 1), count: old.count + 1
        )
        for i in stride(from: old.count - 1, through: 0, by: -1) {
            for j in stride(from: new.count - 1, through: 0, by: -1) {
                lengths[i][j] = old[i] == new[j]
                    ? lengths[i + 1][j + 1] + 1
                    : max(lengths[i + 1][j], lengths[i][j + 1])
            }
        }

        var edits: [Edit] = []
        var i = 0
        var j = 0
        while i < old.count, j < new.count {
            if old[i] == new[j] {
                edits.append(.keep(old[i]))
                i += 1
                j += 1
            } else if lengths[i + 1][j] >= lengths[i][j + 1] {
                edits.append(.remove(old[i]))
                i += 1
            } else {
                edits.append(.insert(new[j]))
                j += 1
            }
        }
        edits.append(contentsOf: old[i...].map(Edit.remove))
        edits.append(contentsOf: new[j...].map(Edit.insert))
        return edits
    }

    // MARK: Hunks

    private struct Hunk {
        var header: String
        var lines: [String]
    }

    /// Groups the edit script into hunks with `context` unchanged lines around each
    /// change, so a one-line edit in a long note prints four lines and not the note.
    private static func hunks(from edits: [Edit], context: Int) -> [Hunk] {
        // Which edits are changes, and therefore what has to be inside a hunk.
        let changed = edits.indices.filter { if case .keep = edits[$0] { false } else { true } }
        guard !changed.isEmpty else { return [] }

        var ranges: [ClosedRange<Int>] = []
        for index in changed {
            let low = max(0, index - context)
            let high = min(edits.count - 1, index + context)
            if let last = ranges.last, low <= last.upperBound + 1 {
                ranges[ranges.count - 1] = last.lowerBound...max(last.upperBound, high)
            } else {
                ranges.append(low...high)
            }
        }

        let starts = lineNumbers(for: edits)
        return ranges.map { hunk(edits, range: $0, startingAt: starts[$0.lowerBound]) }
    }

    /// The 1-based line each edit sits on, in the old text and in the new.
    private static func lineNumbers(for edits: [Edit]) -> [(old: Int, new: Int)] {
        var oldLine = 1
        var newLine = 1
        var starts: [(old: Int, new: Int)] = []
        for edit in edits {
            starts.append((oldLine, newLine))
            switch edit {
            case .keep: oldLine += 1; newLine += 1
            case .remove: oldLine += 1
            case .insert: newLine += 1
            }
        }
        return starts
    }

    private static func hunk(
        _ edits: [Edit], range: ClosedRange<Int>, startingAt start: (old: Int, new: Int)
    ) -> Hunk {
        var lines: [String] = []
        var oldCount = 0
        var newCount = 0
        for index in range {
            switch edits[index] {
            case .keep(let text): lines.append(" \(text)"); oldCount += 1; newCount += 1
            case .remove(let text): lines.append("-\(text)"); oldCount += 1
            case .insert(let text): lines.append("+\(text)"); newCount += 1
            }
        }
        return Hunk(
            header: "@@ -\(start.old),\(oldCount) +\(start.new),\(newCount) @@",
            lines: lines
        )
    }
}
