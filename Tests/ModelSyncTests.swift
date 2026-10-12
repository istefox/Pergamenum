import AppKit
import Foundation
import Testing
@testable import Pergamenum

// PG-406 (ADR-0094 §D9): `updateNSView` no longer compares the whole note with the model after a
// keystroke when the view wrote that very text and nothing has edited it since. The record answers
// "the view holds the model" only when it is true; every other case falls through to the compare.

@Suite struct ModelSyncRecord {
    @Test func nothingWrittenYetHoldsNothing() {
        let sync = ModelSync()
        #expect(!sync.viewHolds(""))
        #expect(!sync.viewHolds("note"))
    }

    @Test func aWrittenTextIsHeldUntilAnEditArrives() {
        var sync = ModelSync()
        sync.wrote("note")
        #expect(sync.viewHolds("note"))
        sync.heardEdit()
        #expect(!sync.viewHolds("note"), "an edit since the write may have changed the view's text")
    }

    @Test func aModelThatMovedOnIsNotHeld() {
        var sync = ModelSync()
        sync.wrote("note")
        #expect(!sync.viewHolds("noted"), "the model was replaced from outside; only the full compare may decide")
        #expect(!sync.viewHolds("nota"))
        #expect(!sync.viewHolds(""))
    }

    @Test func aLaterWriteHoldsAgain() {
        var sync = ModelSync()
        sync.wrote("a")
        sync.heardEdit()
        sync.wrote("ab")
        #expect(sync.viewHolds("ab"))
        #expect(!sync.viewHolds("a"))
    }
}

@MainActor
@Suite(.serialized) struct ModelSyncHosted {
    // (PG-406) After a keystroke through the real edit path, the record holds the model's text, and an
    // edit that bypasses the binding (a reload assigning the string) lets go of it.
    @Test func aKeystrokeLeavesTheRecordHoldingTheModelAndAReloadReleasesIt() {
        let bound = BoundText("alpha\nbeta\n")
        let fixture = ScrolledEditorFixture(text: bound.value, bound: bound)
        defer { fixture.window.orderOut(nil) }
        fixture.openLikeTheApp()

        fixture.type("x", at: 5)

        #expect(bound.value == "alphax\nbeta\n")
        #expect(
            fixture.coordinator.modelSync.viewHolds(bound.value),
            "the keystroke wrote the binding and nothing edited the view after"
        )
        #expect(!fixture.coordinator.modelSync.viewHolds("alpha\nbeta\n"), "a model that differs must not be held")

        fixture.textView.string = "reloaded\n"

        #expect(!fixture.coordinator.modelSync.viewHolds(bound.value), "a reload edited the storage after the write")
    }

    // (PG-406) Undo is a storage edit that posts the change notification: it writes the binding again,
    // so the record follows the text the view now holds.
    @Test func theRecordFollowsEveryKeystroke() {
        let bound = BoundText("one\n")
        let fixture = ScrolledEditorFixture(text: bound.value, bound: bound)
        defer { fixture.window.orderOut(nil) }
        fixture.openLikeTheApp()

        for (index, character) in "abc".enumerated() {
            fixture.type(String(character), at: 3 + index)
            #expect(fixture.coordinator.modelSync.viewHolds(bound.value))
        }
        #expect(bound.value == "oneabc\n")
    }
}
