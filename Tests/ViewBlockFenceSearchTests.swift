import AppKit
import Foundation
import Testing
@testable import Pergamenum

// ADR-0094 §D6, plan docs/plans/sublinear-offset-state-pg-405.md, Task 7 ((coverage), PG-405, R-07).
//
// `Coordinator.currentViewBlockFences(touching:)` hands `ViewBlockController.selectionCrossedFence` the
// closed view-block fences that touch the selection, found by search in the map, where it used to hand it
// every closed view-block fence of the note. The controller keeps the first one the selection reveals, so
// the two are the same answer. The oracle is the old shape: every closed view-block fence, filtered by
// `ViewBlockController.selectionReveals`.

private let note = """
prima
```swift
let a = 1
```
mezzo
```pergamenum-view
render: table
```
poi
```pergamenum-view
render: table
```
fine
```pergamenum-view
render: table
"""

/// The closed `pergamenum-view` fences of `text`, as `NSRange`s from the opening backticks through the
/// closing fence's last backtick: the last one in `note` never closes and is not among them.
private func closedViewBlockFences(in text: String) -> [NSRange] {
    let ns = text as NSString
    var found: [NSRange] = []
    var search = NSRange(location: 0, length: ns.length)
    while true {
        let open = ns.range(of: "```pergamenum-view\n", options: [], range: search)
        guard open.location != NSNotFound else { break }
        let rest = NSRange(location: NSMaxRange(open), length: ns.length - NSMaxRange(open))
        let close = ns.range(of: "\n```", options: [], range: rest)
        if close.location != NSNotFound {
            found.append(NSRange(location: open.location, length: NSMaxRange(close) - open.location))
        }
        search = NSRange(location: NSMaxRange(open), length: ns.length - NSMaxRange(open))
    }
    return found
}

@MainActor
@Suite struct ViewBlockFenceSearchTests {
    private func selections(in text: String) -> [NSRange] {
        let ns = text as NSString
        let length = ns.length
        var places = [0, length, length / 2]
        for needle in ["```swift", "mezzo", "poi", "fine", "```pergamenum-view"] {
            let at = ns.range(of: needle).location
            places += [at - 1, at, at + 3]
        }
        let carets = places.filter { $0 >= 0 && $0 <= length }.map { NSRange(location: $0, length: 0) }
        // Selections that start outside a fence and end inside it, and ones that cover several.
        return carets + [
            NSRange(location: 2, length: 40), NSRange(location: 0, length: length), NSRange(location: 20, length: 3),
            NSRange(location: ns.range(of: "poi").location, length: 4),
        ]
    }

    private func expected(_ selection: NSRange, in text: String) -> [NSRange] {
        closedViewBlockFences(in: text).filter { ViewBlockController.selectionReveals(selection, fence: $0) }
    }

    // (coverage) On a freshly styled note the search answers what filtering every closed fence answers, for
    // carets on, next to and between the fences and for selections reaching one or several of them.
    @Test func theSearchIsTheFilterOfEveryClosedViewBlockFence() throws {
        let fixture = ScrolledEditorFixture(text: note)
        defer { fixture.window.orderOut(nil) }
        fixture.openLikeTheApp()
        #expect(closedViewBlockFences(in: note).count == 2, "the fixture note holds two closed view blocks")

        var sawAnAnswerWithAFence = false
        for selection in selections(in: note) {
            let found = try #require(fixture.coordinator.currentViewBlockFences(touching: selection), "\(selection)")
            #expect(found == expected(selection, in: note), "\(selection)")
            sawAnAnswerWithAFence = sawAnAnswerWithAFence || !found.isEmpty
        }
        #expect(sawAnAnswerWithAFence, "no selection reached a fence, so nothing was compared")
    }

    // (coverage) A keystroke above the fences moves them, and the answer follows the text.
    @Test func theSearchFollowsTheFencesAfterAKeystrokeAboveThem() throws {
        let fixture = ScrolledEditorFixture(text: note)
        defer { fixture.window.orderOut(nil) }
        fixture.openLikeTheApp()

        fixture.type("xyz", at: 3)
        let text = fixture.textView.string
        #expect(text != note)

        for selection in selections(in: text) {
            let found = try #require(fixture.coordinator.currentViewBlockFences(touching: selection), "\(selection)")
            #expect(found == expected(selection, in: text), "\(selection)")
        }
    }

    // (coverage) No selection reveals nothing; an unclosed fence is never among the answers.
    @Test func aMissingSelectionAnswersNothingAndAnUnclosedFenceIsNeverAnswered() throws {
        let fixture = ScrolledEditorFixture(text: note)
        defer { fixture.window.orderOut(nil) }
        fixture.openLikeTheApp()

        let none = try #require(
            fixture.coordinator.currentViewBlockFences(touching: NSRange(location: NSNotFound, length: 0))
        )
        #expect(none.isEmpty)
        let ns = note as NSString
        let atTheUnclosedOne = NSRange(location: ns.length - 3, length: 0)
        let found = try #require(fixture.coordinator.currentViewBlockFences(touching: atTheUnclosedOne))
        #expect(found.isEmpty)
    }

    // (coverage) The kill switch keeps no scope, so the search has no map to answer from and says so: the
    // controller then parses the text, as it did before.
    @Test func withoutAScopeTheSearchAnswersNil() {
        let fixture = ScrolledEditorFixture(text: note, forcesFullRestyle: true)
        defer { fixture.window.orderOut(nil) }
        fixture.openLikeTheApp()

        #expect(fixture.coordinator.currentViewBlockFences(touching: NSRange(location: 0, length: 0)) == nil)
    }
}
