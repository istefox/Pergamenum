import Foundation
import Testing
@testable import Pergamenum

// PG-384 (N1 seams), ADR-0080 §D1: one rule decides `status-inbox`, in the one function
// that already decides a new note's tags. One test per row of the ADR's table.
//
// Pure: no vault, no session. `ConventionsImportTests` keeps the `.note` + topic row and
// the `.capture` / `.daily` rows it already pins; the rows here restate them so this file
// reads as the whole table.

private func names(_ tags: [Pergamenum.Tag]) -> [String] { tags.map(\.description) }

// (n1-seams R-01)
@Test func aDailyNoteIsBornWithTypeNoteAlone() {
    #expect(names(TagRules.initialTags(for: .daily)) == ["type-note"])
    #expect(!names(TagRules.initialTags(for: .daily)).contains("status-inbox"))
}

// (n1-seams R-01)
@Test func aCaptureIsBornWithTypeNoteAndStatusInbox() {
    #expect(names(TagRules.initialTags(for: .capture)) == ["type-note", "status-inbox"])
}

// (n1-seams R-01)
@Test func aNoteWithATopicIsNotACapture() {
    let tags = TagRules.initialTags(for: .note, topics: [Tag("topic-acustica")!])

    #expect(names(tags) == ["type-note", "topic-acustica"])
    #expect(!names(tags).contains("status-inbox"))
}

// (n1-seams R-01)
@Test func aNoteWithNoTagsIsACapture() {
    // The commonest case, and the defect: Cmd+N with the topic field left empty.
    #expect(names(TagRules.initialTags(for: .note)) == ["type-note", "status-inbox"])
    #expect(names(TagRules.initialTags(for: .note, topics: [])) == ["type-note", "status-inbox"])
}

// (n1-seams R-01)
@Test func aNoteWithOnlyAClientTagIsStillACapture() {
    // The test is on the namespace, not on whether the list is empty (ADR-0080 §D1):
    // a `client-acme` says whose note it is, not what it is about.
    let tags = TagRules.initialTags(for: .note, topics: [Tag("client-acme")!])

    #expect(names(tags).contains("status-inbox"))
    #expect(names(tags).contains("client-acme"))
    #expect(names(tags).contains("type-note"))
}

// (n1-seams R-01)
@Test func aNoteWithATopicAndAClientIsNotACapture() {
    // The Pratiche shape: `topic-pratica` plus a `client-*`.
    let tags = TagRules.initialTags(
        for: .note, topics: [Tag("topic-pratica")!, Tag("client-acme")!]
    )

    #expect(!names(tags).contains("status-inbox"))
    #expect(names(tags).contains("topic-pratica"))
    #expect(names(tags).contains("client-acme"))
}

// (n1-seams R-01)
@Test func aNoteGivenStatusInboxAsATopicCarriesItExactlyOnce() {
    // `perg note create --topic status-inbox`, MCP `create_note`, the Cmd+N topic field:
    // none checks the namespace, and a doubled `status-inbox` is `multipleStatus`.
    let tags = TagRules.initialTags(for: .note, topics: [Tag("status-inbox")!])

    #expect(names(tags) == ["type-note", "status-inbox"])
}

// (n1-seams R-01)
@Test func aCaptureGivenStatusInboxAsATopicCarriesItExactlyOnce() {
    let tags = TagRules.initialTags(for: .capture, topics: [Tag("status-inbox")!])

    #expect(names(tags) == ["type-note", "status-inbox"])
}

// (n1-seams R-01)
@Test func aNoteGivenTypeNoteAsATopicCarriesItExactlyOnce() {
    let tags = TagRules.initialTags(for: .note, topics: [Tag("type-note")!, Tag("topic-acustica")!])

    #expect(names(tags) == ["type-note", "topic-acustica"])
}
