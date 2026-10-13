import Foundation
import Testing
@testable import Pergamenum

// (coverage) ADR-0096 §D5 and ADR-0065 §D1.2, plan docs/plans/no-whole-note-term-on-the-update-path-pg-406.md,
// Task 6 (PG-406).
//
// `FrontmatterSource.closingDelimiterIndex(inLines:)` is the one delimiter test the array form now calls, so
// the seven existing readers share it with the new bounded reader. Its doc comment states two things no test
// pins on its own: it answers what the array form always answered, and it reads no line past the closing
// delimiter (the point of the sequence form: the bounded reader must not split the body).

/// A line source that records how many lines were taken from it.
private final class Taken {
    var count = 0
}

private struct CountingLines: Sequence {
    let lines: [String]
    let taken: Taken

    struct Iterator: IteratorProtocol {
        var base: IndexingIterator<[String]>
        let taken: Taken

        mutating func next() -> String? {
            guard let line = base.next() else { return nil }
            taken.count += 1
            return line
        }
    }

    func makeIterator() -> Iterator { Iterator(base: lines.makeIterator(), taken: taken) }
}

private let delimiterCases: [[String]] = [
    [],
    [""],
    ["---"],
    ["---", "---"],
    ["---", "date: 2026-10-13", "---", "corpo", "---"],
    ["---\r", "date: 2026-10-13\r", "---\r", "corpo\r"],
    ["\u{FEFF}---", "tags: []", "---"],
    ["---  ", "a: b", "---   "],
    ["intro", "---", "a: b", "---"],
    ["---", "a: b", "corpo"],
]

@Suite struct FrontmatterDelimiterSequenceTests {
    @Test(arguments: delimiterCases)
    func theSequenceFormAnswersWhatTheArrayFormAnswers(lines: [String]) {
        #expect(
            FrontmatterSource.closingDelimiterIndex(inLines: lines) == FrontmatterSource.closingDelimiterIndex(in: lines)
        )
        let lazy = lines.lazy.map { $0 }
        #expect(
            FrontmatterSource.closingDelimiterIndex(inLines: lazy) == FrontmatterSource.closingDelimiterIndex(in: lines)
        )
    }

    @Test func theClosingDelimiterIsFoundAtItsIndex() {
        #expect(FrontmatterSource.closingDelimiterIndex(inLines: ["---", "a: b", "---", "corpo"]) == 2)
        #expect(FrontmatterSource.closingDelimiterIndex(inLines: ["---", "---"]) == 1)
        #expect(FrontmatterSource.closingDelimiterIndex(inLines: ["corpo", "---", "---"]) == nil)
        #expect(FrontmatterSource.closingDelimiterIndex(inLines: ["---", "a: b"]) == nil)
    }

    @Test func noLinePastTheClosingDelimiterIsTaken() {
        let taken = Taken()
        let body = Array(repeating: "una riga di corpo", count: 10_000)
        let lines = CountingLines(lines: ["---", "date: 2026-10-13", "---"] + body, taken: taken)

        #expect(FrontmatterSource.closingDelimiterIndex(inLines: lines) == 2)
        #expect(taken.count == 3, "the delimiter test read \(taken.count) lines for a block that closes on the third")
    }

    @Test func aNoteWithoutAnOpeningDelimiterTakesOneLine() {
        let taken = Taken()
        let lines = CountingLines(lines: ["corpo"] + Array(repeating: "---", count: 100), taken: taken)

        #expect(FrontmatterSource.closingDelimiterIndex(inLines: lines) == nil)
        #expect(taken.count == 1)
    }
}
