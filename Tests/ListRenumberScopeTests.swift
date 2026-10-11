import Foundation
import Testing
@testable import Pergamenum

// ADR-0082 §D6, plan docs/plans/pg-385-n2-page.md, Task 2 (PG-385, R-16).
//
// `ListContinuation.renumbered(_:touching:)`: the ordered runs that contain the edited lines (the
// edited range widened by one line on each side) are renumbered, and nothing else is. Red against
// the stub, which answers `nil`; every test unwraps with `try #require` so a stub fails on an
// assertion rather than a trap. `edited` is a range of the text as it is after the edit.

private func range(of needle: String, in text: String) -> NSRange {
    (text as NSString).range(of: needle)
}

/// The text with the renumbering applied: what the editor's atomic replace produces.
private func applied(_ renumbering: ListContinuation.Renumbering, to text: String) -> String {
    let rewritten = NSMutableString(string: text)
    rewritten.replaceCharacters(in: renumbering.range, with: renumbering.replacement)
    return rewritten as String
}

@Suite struct ListRenumberScope {
    // MARK: Only the touched run

    // (n2-page R-16) A misnumbered run elsewhere is left alone (G0 item 7).
    @Test func onlyTheRunTouchingTheEditIsRewritten() throws {
        let text = "1. a\n3. b\n4. c\n\nprosa\n\n5. x\n7. y"
        let edited = range(of: "b", in: text)

        let renumbering = try #require(ListContinuation.renumbered(text, touching: edited))

        #expect(applied(renumbering, to: text) == "1. a\n2. b\n3. c\n\nprosa\n\n5. x\n7. y")
        #expect(
            NSMaxRange(renumbering.range) <= range(of: "\n\nprosa", in: text).location,
            "the rewritten range stays inside the edited run"
        )
    }

    // (n2-page R-16) The same text edited in the other run rewrites that one only.
    @Test func theOtherRunIsRewrittenWhenTheEditIsThere() throws {
        let text = "1. a\n3. b\n4. c\n\nprosa\n\n5. x\n7. y"
        let edited = range(of: "y", in: text)

        let renumbering = try #require(ListContinuation.renumbered(text, touching: edited))

        #expect(applied(renumbering, to: text) == "1. a\n3. b\n4. c\n\nprosa\n\n5. x\n6. y")
    }

    // (n2-page R-16) When the edited run is the only misnumbered one, the scoped answer equals the
    // whole-text one.
    @Test func appliedItEqualsTheWholeTextAnswerWhenTheEditedRunIsTheOnlyMisnumberedOne() throws {
        let text = "1. a\n3. b\n4. c\n\nprosa\n\n1. x\n2. y"
        let edited = range(of: "3. b", in: text)

        let renumbering = try #require(ListContinuation.renumbered(text, touching: edited))
        let whole = try #require(ListContinuation.renumbered(text))

        #expect(applied(renumbering, to: text) == whole)
    }

    // (n2-page R-16) A run that starts at 3 is renumbered from 3, never from 1 (ADR-0028 §A6).
    @Test func aRunKeepsItsOwnFirstOrdinal() throws {
        let text = "3. a\n5. b\n6. c"
        let renumbering = try #require(ListContinuation.renumbered(text, touching: range(of: "5. b", in: text)))
        #expect(applied(renumbering, to: text) == "3. a\n4. b\n5. c")
    }

    // MARK: The one-line widening

    // (n2-page R-16) A deleted separator that merges two runs is seen: the edit sits at the join.
    @Test func aDeletedSeparatorThatMergesTwoRunsIsSeen() throws {
        let text = "1. a\n2. b\n1. c\n2. d"
        let join = NSRange(location: range(of: "1. c", in: text).location, length: 0)

        let renumbering = try #require(ListContinuation.renumbered(text, touching: join))

        #expect(applied(renumbering, to: text) == "1. a\n2. b\n3. c\n4. d")
    }

    // (n2-page R-16) An edit on the line between two runs sees the line above and the line below.
    @Test func anEditOnTheSeparatorLineSeesTheRunOnEachSide() throws {
        let text = "1. a\n3. b\n\n1. c\n3. d"
        let separator = NSRange(location: range(of: "\n\n", in: text).location + 1, length: 0)

        let renumbering = try #require(ListContinuation.renumbered(text, touching: separator))

        #expect(applied(renumbering, to: text) == "1. a\n2. b\n\n1. c\n2. d")
    }

    // (n2-page R-16) At the very end of the text, where an edit often lands.
    @Test func anEditAtTheEndOfTheTextSeesTheLastRun() throws {
        let text = "1. a\n3. b"
        let end = NSRange(location: (text as NSString).length, length: 0)

        let renumbering = try #require(ListContinuation.renumbered(text, touching: end))

        #expect(applied(renumbering, to: text) == "1. a\n2. b")
    }

    // MARK: Nothing to do

    // (n2-page R-16) A fenced "list" is not a list, wherever the edit is.
    @Test func aFencedListIsIgnored() {
        let text = "```\n1. a\n3. b\n```\n\nprosa"
        #expect(ListContinuation.renumbered(text, touching: range(of: "3. b", in: text)) == nil)
    }

    // (n2-page R-16) An edit inside a fence does not reach the real run two lines further down.
    @Test func anEditInsideAFenceDoesNotRewriteARunBeyondTheWidening() {
        let text = "```\nx\n```\n\nprosa\n\n1. a\n3. b"
        #expect(ListContinuation.renumbered(text, touching: range(of: "x", in: text)) == nil)
    }

    // (n2-page R-16) `nil` when nothing changes: no undo step for a keystroke that changed no number.
    @Test func answersNilWhenTheTouchedRunIsAlreadyContiguous() {
        let text = "1. a\n2. b\n3. c\n\nprosa"
        #expect(ListContinuation.renumbered(text, touching: range(of: "2. b", in: text)) == nil)
    }

    // (n2-page R-16)
    @Test func answersNilForATextWithNoOrderedList() {
        let text = "- a\n- b\n\nprosa"
        #expect(ListContinuation.renumbered(text, touching: range(of: "prosa", in: text)) == nil)
    }

    // (n2-page R-16) A misnumbered run is not reached by an edit far from it.
    @Test func answersNilWhenOnlyADistantRunIsMisnumbered() {
        let text = "prosa\n\nancora prosa\n\nsenza liste\n\n1. a\n3. b"
        #expect(ListContinuation.renumbered(text, touching: range(of: "prosa", in: text)) == nil)
    }

    // MARK: mapping

    // (n2-page R-16) The case the editor pins: a run's tenth item, `10.`, becomes `9.` and a
    // location after it moves back one.
    @Test func aLocationAfterAShrunkTenMovesBackOne() throws {
        let text = "1. a\n2. b\n3. c\n4. d\n5. e\n6. f\n7. g\n8. h\n10. j\nprosa"
        let edited = NSRange(location: range(of: "10. j", in: text).location, length: 0)
        let renumbering = try #require(ListContinuation.renumbered(text, touching: edited))
        #expect(applied(renumbering, to: text) == "1. a\n2. b\n3. c\n4. d\n5. e\n6. f\n7. g\n8. h\n9. j\nprosa")

        let start = range(of: "10. j", in: text).location
        #expect(renumbering.mapping(0) == 0, "before the rewritten range")
        #expect(renumbering.mapping(start) == start, "at the start of the rewritten marker")
        #expect(renumbering.mapping(start + 2) == start + 1, "right after the shrunk `10`")
        #expect(renumbering.mapping(49) == 48, "the caret of NoteListEditingTests' 49 to 48 case")
        #expect(renumbering.mapping((text as NSString).length) == (text as NSString).length - 1)
    }

    // (n2-page R-16) A location inside a rewritten run stays inside it.
    @Test func aLocationInsideARewrittenMarkerStaysInsideIt() throws {
        let text = "1. a\n2. b\n3. c\n4. d\n5. e\n6. f\n7. g\n8. h\n10. j\nprosa"
        let edited = NSRange(location: range(of: "10. j", in: text).location, length: 0)
        let renumbering = try #require(ListContinuation.renumbered(text, touching: edited))
        let start = range(of: "10. j", in: text).location

        // The old marker is `10` at [start, start + 2); the new one is `9` at [start, start + 1).
        let inside = renumbering.mapping(start + 1)
        #expect((start...(start + 1)).contains(inside), "mapped to \(inside)")
    }

    // (n2-page R-16) Two rewritten markers in one rewritten range: a location between them moves
    // by the first one's delta only, and a location after both by the two. Two runs, each with a
    // tenth item that becomes a ninth, joined by an edit on the line between them.
    @Test func aLocationBetweenTwoRewrittenRunsMovesByTheFirstDeltaOnly() throws {
        let text = "8. a\n10. b\n\n8. c\n10. d\nprosa"
        let nsText = text as NSString
        let separator = NSRange(location: range(of: "\n\n", in: text).location + 1, length: 0)

        let renumbering = try #require(ListContinuation.renumbered(text, touching: separator))
        #expect(applied(renumbering, to: text) == "8. a\n9. b\n\n8. c\n9. d\nprosa")

        let a = range(of: "a", in: text).location
        let b = range(of: "b", in: text).location
        let c = range(of: "c", in: text).location
        let d = range(of: "d", in: text).location
        #expect(renumbering.mapping(a) == a, "before both")
        #expect(renumbering.mapping(b) == b - 1, "after the first shrink")
        #expect(renumbering.mapping(c) == c - 1, "between the two: the first delta only")
        #expect(renumbering.mapping(d) == d - 2, "after both")
        #expect(renumbering.mapping(nsText.length) == nsText.length - 2)
    }

    // (n2-page R-16) The strongest statement of `mapping`: every character that is not a digit of a
    // rewritten marker is found at the mapped location of the rewritten text.
    @Test func everyNonDigitCharacterLandsOnItselfInTheRewrittenText() throws {
        let text = "1. a\n3. c\n4. d\n5. e\n6. f\n7. g\n8. h\n9. i\n10. j\n11. k\nprosa"
        let edited = NSRange(location: range(of: "3. c", in: text).location, length: 0)
        let renumbering = try #require(ListContinuation.renumbered(text, touching: edited))
        let old = text as NSString
        let new = applied(renumbering, to: text) as NSString
        let digits = CharacterSet.decimalDigits

        for index in 0..<old.length {
            let character = old.substring(with: NSRange(location: index, length: 1))
            if character.unicodeScalars.allSatisfy({ digits.contains($0) }) { continue }
            let mapped = renumbering.mapping(index)
            #expect(mapped >= 0 && mapped < new.length, "\(index) mapped out of range to \(mapped)")
            guard mapped >= 0, mapped < new.length else { continue }
            #expect(
                new.substring(with: NSRange(location: mapped, length: 1)) == character,
                "old \(index) \(String(reflecting: character)) landed on \(mapped)"
            )
        }
    }
}
