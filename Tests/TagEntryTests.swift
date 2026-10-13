import Foundation
import Testing
@testable import Pergamenum

// PG-387 (N4), ADR-0085 §D7, plan docs/plans/pg-387-n4-birth-of-note.md, Task 2 - R-12, and the
// topic parse behind R-05 and R-15: `TagEntry`, the one door from typed text to a tag.

private let vocabulary = Vocabulary(
    type: ["note", "invoice"],
    status: ["inbox", "active", "done"],
    area: ["sales", "hr"],
    source: ["email"],
    deliverableKind: []
)

private func tag(_ raw: String) -> Pergamenum.Tag { Pergamenum.Tag(raw)! }

/// What the composer's tag field lets through: the open families and the closed ones it does not
/// own. `type-*` and `status-*` are the initial-tags rule's.
private let fieldNamespaces: Set<TagNamespace> = [.topic, .client, .project, .competitor, .area, .source]

// MARK: - check

@Test func bareTextReadsAsATopic() {
    #expect(TagEntry.check("materiali", allowing: fieldNamespaces, vocabulary: vocabulary)
        == .success(tag("topic-materiali")))
}

@Test func aHashAndAnExplicitNamespaceAreKept() {
    #expect(TagEntry.check("#client-acme", allowing: fieldNamespaces, vocabulary: vocabulary)
        == .success(tag("client-acme")))
    #expect(TagEntry.check("project-ponte", allowing: fieldNamespaces, vocabulary: vocabulary)
        == .success(tag("project-ponte")))
}

@Test func aClosedFamilyValueInTheVocabularyIsAccepted() {
    #expect(TagEntry.check("area-sales", allowing: fieldNamespaces, vocabulary: vocabulary)
        == .success(tag("area-sales")))
}

@Test func aClosedFamilyValueOutsideTheVocabularyIsRefused() {
    #expect(TagEntry.check("area-xyz", allowing: fieldNamespaces, vocabulary: vocabulary)
        == .failure(.notInVocabulary(tag("area-xyz"))))
}

@Test func aClosedFamilyAgainstAnEmptyVocabularyIsReportedAsUnavailableNotAsValid() {
    #expect(TagEntry.check("area-xyz", allowing: fieldNamespaces, vocabulary: .empty)
        == .failure(.vocabularyUnavailable(.area)))
}

@Test func aDateShapedValueIsRefused() {
    #expect(TagEntry.check("topic-2026", allowing: fieldNamespaces, vocabulary: vocabulary)
        == .failure(.dateTag(tag("topic-2026"))))
    #expect(TagEntry.check("20261011", allowing: fieldNamespaces, vocabulary: vocabulary)
        == .failure(.dateTag(tag("topic-20261011"))))
}

@Test func typeAndStatusAreRefusedWhereTheFieldDoesNotAllowThem() {
    #expect(TagEntry.check("type-note", allowing: fieldNamespaces, vocabulary: vocabulary)
        == .failure(.notAllowedHere(tag("type-note"))))
    #expect(TagEntry.check("status-done", allowing: fieldNamespaces, vocabulary: vocabulary)
        == .failure(.notAllowedHere(tag("status-done"))))
}

@Test func textThatIsNotATagAtAllIsMalformed() {
    guard case .failure(.malformed) = TagEntry.check("Topic Bad", allowing: fieldNamespaces, vocabulary: vocabulary) else {
        Issue.record("«Topic Bad» was not refused as malformed")
        return
    }
}

@Test func everyTagEntryRefusalHasADistinctNonEmptySentence() {
    let refusals: [TagEntry.Refusal] = [
        .malformed("Topic Bad"), .notInVocabulary(tag("area-xyz")), .vocabularyUnavailable(.area),
        .dateTag(tag("topic-2026")), .notAllowedHere(tag("type-note")),
    ]
    let sentences = refusals.map(\.sentence)

    #expect(sentences.allSatisfy { !$0.isEmpty })
    #expect(Set(sentences).count == sentences.count)
}

// MARK: - completions

private let usage: [(tag: Pergamenum.Tag, count: Int)] = [
    (tag("topic-altro"), 20), (tag("topic-macchine"), 9), (tag("topic-materiali"), 5),
    (tag("client-acme"), 4), (tag("client-beta"), 12), (tag("project-ponte"), 3),
]

@Test func anOpenFamilyOffersTheUsedValuesMostUsedFirst() {
    let offered = TagEntry.completions(
        for: "topic-m", allowing: fieldNamespaces, usage: usage, vocabulary: vocabulary,
        excluding: [], limit: 10
    )

    #expect(offered == [tag("topic-macchine"), tag("topic-materiali")])
}

@Test func theClientChipsComeFromTheMostUsedClients() {
    let offered = TagEntry.completions(
        for: "client-", allowing: fieldNamespaces, usage: usage, vocabulary: vocabulary,
        excluding: [], limit: 10
    )

    #expect(offered == [tag("client-beta"), tag("client-acme")])
}

@Test func aClosedFamilyOffersTheVocabularyValues() {
    let offered = TagEntry.completions(
        for: "area-", allowing: fieldNamespaces, usage: usage, vocabulary: vocabulary,
        excluding: [], limit: 10
    )

    #expect(Set(offered) == [tag("area-sales"), tag("area-hr")])
    #expect(offered.count == 2)
}

@Test func aChosenTagIsNeverOffered() {
    let offered = TagEntry.completions(
        for: "topic-m", allowing: fieldNamespaces, usage: usage, vocabulary: vocabulary,
        excluding: [tag("topic-macchine")], limit: 10
    )

    #expect(offered == [tag("topic-materiali")])
}

@Test func theLimitIsHonoured() {
    let offered = TagEntry.completions(
        for: "topic-", allowing: fieldNamespaces, usage: usage, vocabulary: vocabulary,
        excluding: [], limit: 2
    )

    #expect(offered == [tag("topic-altro"), tag("topic-macchine")])
}

@Test func aFamilyTheFieldDoesNotAllowIsNeverOffered() {
    let withTypes: [(tag: Pergamenum.Tag, count: Int)] = usage + [(tag("type-note"), 99)]
    let offered = TagEntry.completions(
        for: "type-", allowing: fieldNamespaces, usage: withTypes, vocabulary: vocabulary,
        excluding: [], limit: 10
    )

    #expect(offered.isEmpty)
}

// MARK: - topics(fromList:)

@Test func aCommaSeparatedStringIsTwoTopics() throws {
    #expect(try TagEntry.topics(fromList: "a, b", vocabulary: vocabulary).get()
        == [tag("topic-a"), tag("topic-b")])
    #expect(try TagEntry.topics(fromList: "a,b", vocabulary: vocabulary).get()
        == [tag("topic-a"), tag("topic-b")])
}

@Test func anEmptyItemIsIgnored() throws {
    #expect(try TagEntry.topics(fromList: "a,,b", vocabulary: vocabulary).get()
        == [tag("topic-a"), tag("topic-b")])
}

@Test func aMalformedItemIsTheRefusal() {
    guard case .failure(.malformed) = TagEntry.topics(fromList: "a, Topic Bad", vocabulary: vocabulary) else {
        Issue.record("a malformed item was accepted")
        return
    }
}
