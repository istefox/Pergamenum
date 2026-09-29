import Foundation
import Testing
@testable import Pergamenum

// PG-085 (ADR-0028 §D-Negative): CommonMark's content-column list-nesting rule, extracted
// as a shared pure function called by both MarkdownStyler's styling pass and
// EditorDecorationDelegate's layout-time re-read. These tests exercise `ListNesting.level`
// directly, at a line's own start with its own indent-in-columns already computed - the
// same inputs both call sites pass.

// MARK: - Helpers

/// `text`'s `String.Index` right before the first line that starts with `marker`.
private func lineStart(of marker: String, in text: String) -> String.Index {
    guard let range = text.range(of: marker) else {
        fatalError("marker not found: \(marker)")
    }
    // range.lowerBound is already a line start for every marker used below (none appear
    // mid-line in these fixtures).
    return range.lowerBound
}

@Test func aLoneItemWithNoAncestorIsLevelOne() {
    let text = "- sotto"
    #expect(ListNesting.level(in: text, lineStart: text.startIndex, indent: 0) == 1)
}

@Test func threeSpaceChildNestsUnderATwoColumnParent() {
    // R-04: content column of "- " is 2; indent 3 >= 2, so it nests.
    let text = "- padre\n   - figlio"
    let target = lineStart(of: "- figlio", in: text)
    #expect(ListNesting.level(in: text, lineStart: target, indent: 3) == 2)
}

@Test func threeSpaceChildDoesNotNestUnderAFourColumnParent() {
    // R-05: content column of "12. " is 4; indent 3 < 4, so it stays a level-1 sibling.
    let text = "12. padre\n   - figlio"
    let target = lineStart(of: "- figlio", in: text)
    #expect(ListNesting.level(in: text, lineStart: target, indent: 3) == 1)
}

@Test func tieBreakAttachesToTheDeepestListThatStillFits() {
    // R-06: "- a" (content column 2) opens "- b" (indent 2, content column 4); a line
    // indented 3 reaches "- a"'s content column but not "- b"'s, so it lands at "- b"'s
    // own level, not one deeper.
    let text = "- a\n  - b\n   - c"
    let target = lineStart(of: "- c", in: text)
    #expect(ListNesting.level(in: text, lineStart: target, indent: 3) == 2)
}

@Test func levelCapsAtSix() {
    // R-07: seven genuinely nested levels would compute level 7 uncapped.
    let sevenDeep = (1...7)
        .map { String(repeating: "  ", count: $0 - 1) + "- n\($0)" }
        .joined(separator: "\n")
    let target = lineStart(of: "- n7", in: sevenDeep)
    #expect(ListNesting.level(in: sevenDeep, lineStart: target, indent: 12) == 6)
}

@Test func aSimpleTwoSpaceNestStillResolvesToLevelTwo() {
    // The common case every note and card in this vault already uses - Pergamenum's own
    // Enter-continuation always emits this exact shape.
    let text = "- a\n  - b"
    let target = lineStart(of: "- b", in: text)
    #expect(ListNesting.level(in: text, lineStart: target, indent: 2) == 2)
}

@Test func aTopLevelParagraphClosesEveryOpenList() {
    // A non-indented, non-list line between two list runs closes every ancestor - the
    // second run starts fresh at level 1 regardless of its own indentation.
    let text = "- a\n  - b\n\nparagrafo\n\n  - c"
    let target = lineStart(of: "- c", in: text)
    #expect(ListNesting.level(in: text, lineStart: target, indent: 2) == 1)
}

// MARK: - CRLF notes (PG-274)

/// "\r\n" is one Swift `Character`, so a walk searching for "\n" never found a CRLF line's end:
/// the forward pass read the whole note as one line and the backward walk copied the whole
/// prefix per list line. Both must give a CRLF note the levels its LF twin gets.
@Test func aCRLFListNestsLikeItsLFTwin() {
    let lf = "- a\n  - b\n    - c\n  - d\n- e"
    let crlf = lf.replacingOccurrences(of: "\n", with: "\r\n")

    func forwardLevels(_ text: String) -> [Int] {
        ListNesting.levels(in: text).sorted { $0.key < $1.key }.map(\.value)
    }
    #expect(forwardLevels(lf) == [1, 2, 3, 2, 1])
    #expect(forwardLevels(crlf) == forwardLevels(lf))
    #expect(ListNesting.levels(in: crlf).count == 5)
}

@Test func theBackwardWalkOfACRLFListMatchesItsLFTwin() {
    let lf = "- a\n  - b\n    - c\n\n  - d"
    let crlf = lf.replacingOccurrences(of: "\n", with: "\r\n")
    for (marker, indent) in [("- b", 2), ("- c", 4), ("- d", 2)] {
        // Each fixture line starts with its indentation, so walk from the marker back to the
        // line's own start rather than passing the marker's position.
        func start(_ text: String) -> String.Index {
            let found = text.range(of: marker)!.lowerBound
            var index = found
            while index > text.startIndex, text[text.index(before: index)] == " " { index = text.index(before: index) }
            return index
        }
        #expect(
            ListNesting.level(in: crlf, lineStart: start(crlf), indent: indent)
                == ListNesting.level(in: lf, lineStart: start(lf), indent: indent),
            "«\(marker)»"
        )
    }
    #expect(ListNesting.level(in: crlf, lineStart: crlf.range(of: "    - c")!.lowerBound, indent: 4) == 3)
}

@Test func theStylerGivesACRLFListTheLevelsOfItsLFTwin() {
    let lf = "- a\n  - b\n    - c\n"
    let crlf = lf.replacingOccurrences(of: "\n", with: "\r\n")
    let levels = { (text: String) -> [Int] in
        MarkdownStyler.spans(in: text).compactMap { match -> Int? in
            if case .listMarker(_, let level) = match.span { return level }
            return nil
        }
    }
    #expect(levels(lf) == [1, 2, 3])
    #expect(levels(crlf) == levels(lf))
}
