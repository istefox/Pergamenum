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

@Suite struct TopiclessNoteRuleTests {
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

    // PG-390
    @Test func aNoteGivenAnotherStatusAsATopicCarriesOneStatus() {
        // `perg note create --topic status-active`: a topicless `.note` is a capture, but a
        // `status-*` already in `topics` is its status, and `status-inbox` beside it would be
        // `multipleStatus` (T-05).
        let tags = TagRules.initialTags(for: .note, topics: [Tag("status-active")!])

        #expect(names(tags) == ["type-note", "status-active"])
        #expect(tags.filter { $0.namespace == .status }.count == 1)
    }

    // PG-390
    @Test func aCaptureGivenAnotherStatusAsATopicCarriesOneStatus() {
        let tags = TagRules.initialTags(for: .capture, topics: [Tag("status-waiting")!])

        #expect(names(tags) == ["type-note", "status-waiting"])
        #expect(tags.filter { $0.namespace == .status }.count == 1)
    }

    // (coverage) PG-390: the observable symptom named in the plan entry, through the linter's own
    // T-05 check rather than a count of tags.
    @Test func aStatusGivenAsATopicIsNotFlaggedAsMultipleStatus() {
        for category in [NoteCategory.note, .capture] {
            let tags = TagRules.initialTags(for: category, topics: [Tag("status-active")!])
            let violations = TagRules.validate(tags, category: category, vocabulary: .empty)

            #expect(!violations.contains { if case .multipleStatus = $0 { true } else { false } })
        }
    }

    // (coverage) PG-390: the status test is on the namespace over the whole list, so it holds
    // when the status sits among other tags, and the output stays in F-04 order.
    @Test func aStatusAmongOtherTopicsStillSuppressesStatusInbox() {
        let clientOnly = TagRules.initialTags(
            for: .note, topics: [Tag("status-archived")!, Tag("client-acme")!]
        )
        #expect(names(clientOnly) == names(TagRules.ordered(clientOnly)))
        #expect(!names(clientOnly).contains("status-inbox"))
        #expect(names(clientOnly).contains("status-archived"))
        #expect(names(clientOnly).contains("client-acme"))
        #expect(names(clientOnly).contains("type-note"))

        let withTopic = TagRules.initialTags(
            for: .note, topics: [Tag("topic-acustica")!, Tag("status-waiting")!]
        )
        #expect(names(withTopic).sorted() == ["status-waiting", "topic-acustica", "type-note"])
    }

    // (n1-seams R-01)
    @Test func aNoteGivenTypeNoteAsATopicCarriesItExactlyOnce() {
        let tags = TagRules.initialTags(for: .note, topics: [Tag("type-note")!, Tag("topic-acustica")!])

        #expect(names(tags) == ["type-note", "topic-acustica"])
    }
}
