import Foundation
import Testing
@testable import Pergamenum

// ADR-0091 §D1 and §D3, plan docs/plans/per-paragraph-restyle.md, Task 1 (R-03, R-04).
//
// `ListNesting.role(of:)` and `folding(_:_:)` are the body of the forward loop `levels(in:)` already
// runs, as values; `levels(in:seed:)` and `level(in:lineStart:indent:seed:)` start that fold, or end
// the backward read, at a given stack. The oracle for the seeded reads is the unseeded ones over the
// whole note, with a seed folded here by a reference written from ADR-0091 C3 item 5 and nothing else.
// Red until Task 2 gives the placeholders their bodies.

// MARK: - A reference fold, written from the ADR and not from the code

private struct ReferenceFold {
    /// The width of a list marker and its one space, or nil: `- `, `* `, `+ `, `12. `, `12) `.
    static func markerWidth(_ content: Substring) -> Int? {
        guard let first = content.first else { return nil }
        if first == "-" || first == "*" || first == "+" {
            return content.dropFirst().first == " " ? 2 : nil
        }
        let digits = content.prefix(while: { $0.isASCII && $0.isNumber }).count
        guard digits > 0 else { return nil }
        let rest = content.dropFirst(digits)
        guard let delimiter = rest.first, delimiter == "." || delimiter == ")" else { return nil }
        return rest.dropFirst().first == " " ? digits + 2 : nil
    }

    /// One line folded into the stack, and the level it reads if it is a list line.
    static func fold(_ stack: [Int], line: Substring) -> (stack: [Int], level: Int?) {
        guard !line.isEmpty else { return (stack, nil) }
        let indentPrefix = line.prefix(while: { $0 == " " || $0 == "\t" })
        let indent = indentPrefix.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        if let width = markerWidth(line.dropFirst(indentPrefix.count)) {
            var next = stack
            while let top = next.last, top > indent { next.removeLast() }
            let level = min(1 + next.count, 6)
            next.append(indent + width)
            return (next, level)
        }
        return (indent == 0 ? [] : stack, nil)
    }

    /// The stack in force just before line `index`, for `lines` split on "\n".
    static func seed(before index: Int, in lines: [Substring]) -> [Int] {
        var stack: [Int] = []
        for line in lines[..<index] { stack = fold(stack, line: line).stack }
        return stack
    }
}

private func lines(of text: String) -> [Substring] {
    text.split(separator: "\n", omittingEmptySubsequences: false)
}

/// The start index of each "\n"-split line of `text`.
private func lineStarts(of text: String) -> [String.Index] {
    var starts = [text.startIndex]
    var index = text.startIndex
    while let newline = text[index...].firstIndex(of: "\n") {
        index = text.index(after: newline)
        starts.append(index)
    }
    return starts
}

private let nestedTexts: [String] = [
    "- a\n  - b\n    - c\n  - d\n- e",
    "- a\n  - b\n\n    - c\n      continuation\n  - d",
    "1. one\n2. two\n   - nested\n   - again\n3. three",
    "- a\n  - b\ntext\n  - c\n- d",
    "\t- a\n\t\t- b\n  - c",
    "- [ ] task\n  - child\n  - [x] done\n    - deep",
    "- a\n  - b\n    - c\n      - d\n        - e\n          - f\n            - g\n            - h",
    "plain\n  - indented list\n    - deeper\n- top",
]

// MARK: - role(of:) and folding(_:_:)

// (R-04) The four roles of a line, by the forward walk's own arithmetic.
@Test func aLineHasOneOfFourRoles() {
    #expect(ListNesting.role(of: "") == .blank)
    #expect(ListNesting.role(of: "- a") == .item(indent: 0, contentColumn: 2))
    #expect(ListNesting.role(of: "   - a") == .item(indent: 3, contentColumn: 5))
    #expect(ListNesting.role(of: "\t- a") == .item(indent: 4, contentColumn: 6))
    #expect(ListNesting.role(of: "10. a") == .item(indent: 0, contentColumn: 4))
    #expect(ListNesting.role(of: "   continued") == .continuation)
    #expect(ListNesting.role(of: "text") == .reset)
    #expect(ListNesting.role(of: "-text") == .reset)
}

// (R-04) A list line pops the entries deeper than its indent and pushes its content column.
@Test func foldingAListLinePopsThenPushes() {
    #expect(ListNesting.folding([], .item(indent: 0, contentColumn: 2)) == [2])
    #expect(ListNesting.folding([2], .item(indent: 2, contentColumn: 4)) == [2, 4])
    #expect(ListNesting.folding([2, 4], .item(indent: 2, contentColumn: 4)) == [2, 4])
    #expect(ListNesting.folding([2, 4], .item(indent: 0, contentColumn: 2)) == [2])
    #expect(ListNesting.folding([2, 4, 6], .item(indent: 3, contentColumn: 5)) == [2, 5])
}

// (R-04) A blank line and an indented non-list line change nothing; a line at column 0 clears it.
@Test func foldingABlankAContinuationAndAReset() {
    #expect(ListNesting.folding([2, 4], .blank) == [2, 4])
    #expect(ListNesting.folding([2, 4], .continuation) == [2, 4])
    #expect(ListNesting.folding([2, 4], .reset).isEmpty)
    #expect(ListNesting.folding([], .reset).isEmpty)
}

// (R-04) Folding `role(of:)` line by line is the walk `levels(in:)` makes: the stack after every
// line equals the reference's, so `levels(in:)` can become the fold over the roles.
@Test(arguments: nestedTexts)
func foldingTheRolesIsTheWalkTheLevelsMake(_ text: String) {
    var stack: [Int] = []
    var reference: [Int] = []
    var sawAnOpenItem = false
    for line in lines(of: text) {
        stack = ListNesting.folding(stack, ListNesting.role(of: line))
        reference = ReferenceFold.fold(reference, line: line).stack
        #expect(stack == reference, "\(line.debugDescription)")
        if !reference.isEmpty { sawAnOpenItem = true }
    }
    // Non-vacuity: every text opens an item at some line, so a fold that stays empty cannot pass.
    #expect(sawAnOpenItem)
}

// MARK: - levels(in:seed:)

// (R-03) An empty seed is the unseeded walk.
@Test(arguments: nestedTexts)
func anEmptySeedIsTheUnseededWalk(_ text: String) {
    let unseeded = ListNesting.levels(in: text)
    #expect(!unseeded.isEmpty)
    #expect(ListNesting.levels(in: text, seed: []) == unseeded)
}

// (R-03) A seed of one open item of content column 2 puts a line indented 2 one level down.
@Test func aSeedDeepensTheForwardWalk() {
    let text = "  - child\n  - sibling"
    let starts = lineStarts(of: text)
    let seeded = ListNesting.levels(in: text, seed: [2])
    #expect(seeded[starts[0]] == 2)
    #expect(seeded[starts[1]] == 2)
    let alone = ListNesting.levels(in: text, seed: [])
    #expect(alone[starts[0]] == 1)
    #expect(alone[starts[1]] == 1)
}

// (R-03) A line at column 0 that is no list line clears the seed, as it clears any stack.
@Test func aResetLineInTheFragmentDropsTheSeed() {
    let text = "plain\n  - child"
    let starts = lineStarts(of: text)
    #expect(ListNesting.levels(in: text, seed: [2, 4])[starts[1]] == 1)
}

// (R-03) The oracle: the levels of a note's tail, seeded with the stack the head leaves, are the
// levels the whole note gives its tail lines. Every split point of every text.
@Test(arguments: nestedTexts)
func aSeededTailReadsTheLevelsOfTheWholeNote(_ text: String) {
    let all = lines(of: text)
    let wholeStarts = lineStarts(of: text)
    let whole = ListNesting.levels(in: text)
    #expect(!whole.isEmpty)
    for split in 0..<all.count {
        let tail = all[split...].joined(separator: "\n")
        let tailStarts = lineStarts(of: tail)
        let seeded = ListNesting.levels(in: tail, seed: ReferenceFold.seed(before: split, in: all))
        for offset in 0..<tailStarts.count {
            #expect(
                seeded[tailStarts[offset]] == whole[wholeStarts[split + offset]],
                "split \(split), line \(split + offset) of \(text.debugDescription)"
            )
        }
    }
}

// MARK: - level(in:lineStart:indent:seed:)

// (R-03) The backward read stops at the seed when it reaches the top of the fragment.
@Test func aSeedBottomsOutTheBackwardRead() {
    let text = "  - child"
    #expect(ListNesting.level(in: text, lineStart: text.startIndex, indent: 2, seed: [2]) == 2)
    #expect(ListNesting.level(in: text, lineStart: text.startIndex, indent: 2, seed: []) == 1)
    // And it is what the whole note says when the open item is the line above.
    let whole = "- a\n  - child"
    #expect(ListNesting.level(in: whole, lineStart: lineStarts(of: whole)[1], indent: 2) == 2)
}

// (R-03) A reset line inside the fragment closes every open list, so the seed above it counts for nothing.
@Test func aResetLineStopsTheBackwardReadBeforeTheSeed() {
    let text = "plain\n  - child"
    let start = lineStarts(of: text)[1]
    #expect(ListNesting.level(in: text, lineStart: start, indent: 2, seed: [2, 4]) == 1)
}

// (R-03) An empty seed is the unseeded backward read.
@Test(arguments: nestedTexts)
func anEmptySeedIsTheUnseededBackwardRead(_ text: String) {
    let starts = lineStarts(of: text)
    var compared = 0
    for (index, line) in lines(of: text).enumerated() {
        guard case .item(let indent, _) = ListNesting.role(of: line) else { continue }
        let plain = ListNesting.level(in: text, lineStart: starts[index], indent: indent)
        #expect(ListNesting.level(in: text, lineStart: starts[index], indent: indent, seed: []) == plain)
        compared += 1
    }
    #expect(compared > 0, "role(of:) found no list line in \(text.debugDescription)")
}

// (R-03) The oracle again, backward: every list line of a tail reads, with the head's stack as its
// seed, the level the whole note's backward read gives it.
@Test(arguments: nestedTexts)
func aSeededBackwardReadMatchesTheWholeNote(_ text: String) {
    let all = lines(of: text)
    let wholeStarts = lineStarts(of: text)
    var compared = 0
    for split in 0..<all.count {
        let tail = all[split...].joined(separator: "\n")
        let tailStarts = lineStarts(of: tail)
        let seed = ReferenceFold.seed(before: split, in: all)
        for offset in 0..<tailStarts.count {
            guard case .item(let indent, _) = ListNesting.role(of: all[split + offset]) else { continue }
            let expected = ListNesting.level(in: text, lineStart: wholeStarts[split + offset], indent: indent)
            let read = ListNesting.level(in: tail, lineStart: tailStarts[offset], indent: indent, seed: seed)
            #expect(read == expected, "split \(split), line \(split + offset) of \(text.debugDescription)")
            compared += 1
        }
    }
    #expect(compared > 0, "role(of:) found no list line in \(text.debugDescription)")
}
