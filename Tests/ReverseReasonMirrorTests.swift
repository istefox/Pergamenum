import Foundation
import Testing
@testable import Pergamenum

// ADR-0084 §D4 (the reverse reason is an editable mirror), SPEC R-27, plan
// docs/plans/note-workflow-n3.md Task 1.
//
// The rule is a value, so it is tested without the sheet: the reverse reason follows the forward
// one as it is typed until the person edits it, and is never overwritten after that.

@Test func aFreshMirrorIsEmptyAndNotEdited() {
    let mirror = ReverseReasonMirror()

    #expect(mirror.reverse == "")
    #expect(!mirror.isEdited)
}

@Test func theReverseReasonFollowsTheForwardOneAsItIsTyped() {
    var mirror = ReverseReasonMirror()

    mirror.forwardChanged(to: "u")
    #expect(mirror.reverse == "u")
    mirror.forwardChanged(to: "usa i dati")
    #expect(mirror.reverse == "usa i dati")
    mirror.forwardChanged(to: "usa i dati di taratura")
    #expect(mirror.reverse == "usa i dati di taratura")
    #expect(!mirror.isEdited, "seguire il motivo di andata non è una modifica della persona")
}

@Test func anEditedReverseReasonIsNeverOverwrittenByTheForwardOne() {
    var mirror = ReverseReasonMirror()
    mirror.forwardChanged(to: "usa i dati")

    mirror.reverseEdited(to: "fornisce i dati")
    mirror.forwardChanged(to: "usa i dati di taratura")
    mirror.forwardChanged(to: "")

    #expect(mirror.reverse == "fornisce i dati")
    #expect(mirror.isEdited)
}

@Test func anEditThatHappensToEqualTheForwardTextStillCountsAsAnEdit() {
    var mirror = ReverseReasonMirror()
    mirror.forwardChanged(to: "fornitura")

    mirror.reverseEdited(to: "fornitura")
    #expect(mirror.isEdited, "il testo coincide, ma la persona ha scelto: è una modifica")

    mirror.forwardChanged(to: "fornitura di taratura")
    #expect(mirror.reverse == "fornitura")
}

@Test func editingBeforeAnyForwardTextStopsTheMirrorFollowing() {
    var mirror = ReverseReasonMirror()

    mirror.reverseEdited(to: "scritto prima")
    mirror.forwardChanged(to: "arriva dopo")

    #expect(mirror.reverse == "scritto prima")
    #expect(mirror.isEdited)
}

@Test func theLastEditWins() {
    var mirror = ReverseReasonMirror()

    mirror.reverseEdited(to: "primo")
    mirror.reverseEdited(to: "secondo")

    #expect(mirror.reverse == "secondo")
}
