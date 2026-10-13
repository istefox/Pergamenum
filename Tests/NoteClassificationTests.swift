import Foundation
import Testing
@testable import Pergamenum

// PG-387 (N4), ADR-0085 §D3, plan docs/plans/pg-387-n4-birth-of-note.md, Task 2 - R-02:
// the one rule that classifies any note, and the scheda rule as its special case.

private let vocabulary = Vocabulary(
    type: ["note", "invoice", "contract"],
    status: ["inbox", "active", "done"],
    area: ["sales"],
    source: ["email"],
    deliverableKind: []
)

private func tag(_ raw: String) -> Pergamenum.Tag { Pergamenum.Tag(raw)! }

private let capture = [tag("type-note"), tag("status-inbox")]

// MARK: - What the rule does

@Test func classifyingRemovesInboxKeepsTypeNoteAddsTopicsAndOrdersTheResult() throws {
    let result = NoteClassification.classify(
        tags: [tag("status-inbox"), tag("type-note"), tag("client-acme")],
        topics: [tag("topic-b"), tag("topic-a")],
        vocabulary: vocabulary
    )

    #expect(try result.get().map(\.description)
        == ["client-acme", "type-note", "topic-a", "topic-b"])
}

@Test func classifyingAddsTypeNoteWhenTheNoteHadNone() throws {
    let result = NoteClassification.classify(
        tags: [tag("status-inbox")], topics: [tag("topic-a")], vocabulary: vocabulary
    )

    #expect(try result.get().map(\.description) == ["type-note", "topic-a"])
}

@Test func aTopicTheNoteAlreadyCarriesIsNotDuplicatedAndAnotherStatusIsKept() throws {
    let result = NoteClassification.classify(
        tags: [tag("type-note"), tag("topic-a"), tag("status-active")],
        topics: [tag("topic-a")],
        vocabulary: vocabulary
    )

    #expect(try result.get().map(\.description) == ["type-note", "topic-a", "status-active"])
}

// MARK: - What it refuses

@Test func noTopicIsRefused() {
    #expect(NoteClassification.classify(tags: capture, topics: [], vocabulary: vocabulary)
        == .failure(.noTopic))
}

@Test func aTagThatIsNotATopicIsRefusedNamingIt() {
    #expect(NoteClassification.classify(tags: capture, topics: [tag("area-sales")], vocabulary: vocabulary)
        == .failure(.notATopic(tag("area-sales"))))
}

@Test func aDateShapedTopicIsRefusedNamingIt() {
    for raw in ["topic-2026", "topic-20261011"] {
        #expect(NoteClassification.classify(tags: capture, topics: [tag(raw)], vocabulary: vocabulary)
            == .failure(.dateTopic(tag(raw))), "«\(raw)»")
    }
}

@Test func anOrdinaryNumberThatIsNotAYearIsNotADate() throws {
    // The negative control: `isDateLike` restricts its digit heuristic to plausible years.
    let result = NoteClassification.classify(tags: capture, topics: [tag("topic-4140")], vocabulary: vocabulary)

    #expect(try result.get().contains(tag("topic-4140")))
}

@Test func moreThanSevenTagsIsRefusedWithTheCount() {
    let many = (1...7).map { tag("topic-t\($0)") }

    #expect(NoteClassification.classify(tags: capture, topics: many, vocabulary: vocabulary)
        == .failure(.tooManyTags(count: 8)))
}

@Test func exactlySevenTagsIsAccepted() throws {
    let six = (1...6).map { tag("topic-t\($0)") }

    #expect(try NoteClassification.classify(tags: capture, topics: six, vocabulary: vocabulary).get().count == 7)
}

// MARK: - One rule, two doors (the Contenitore's classification is the note's plus a type)

@Test func theSchedaRuleWithNoTypeEqualsTheNoteRule() {
    let topics = [tag("topic-guarnizioni")]

    #expect(ContenitoreClassification.classify(tags: capture, topics: topics, type: nil, vocabulary: vocabulary)
        == NoteClassification.classify(tags: capture, topics: topics, vocabulary: vocabulary))
}

@Test func theSchedaRuleWithATypeIsTheNoteResultPlusThatType() throws {
    let topics = [tag("topic-guarnizioni")]
    let noteResult = try NoteClassification.classify(tags: capture, topics: topics, vocabulary: vocabulary).get()
    let withType = try ContenitoreClassification.classify(
        tags: capture, topics: topics, type: tag("type-invoice"), vocabulary: vocabulary
    ).get()

    #expect(withType == TagRules.ordered(noteResult + [tag("type-invoice")]))
}

@Test func aDateShapedTopicIsNowRefusedOnASchedaToo() {
    // R-02's "one rule": the scheda rule used to accept `topic-2026`.
    #expect(ContenitoreClassification.classify(
        tags: capture, topics: [tag("topic-2026")], type: nil, vocabulary: vocabulary
    ) == .failure(.dateTopic(tag("topic-2026"))))
}

@Test func aSecondContentTypeIsStillReportedBeforeTheCount() {
    // A case that violates both: two content types, and eight tags once they are in.
    let many = (1...5).map { tag("topic-t\($0)") }
    let result = ContenitoreClassification.classify(
        tags: capture + [tag("type-invoice")], topics: many, type: tag("type-contract"), vocabulary: vocabulary
    )

    #expect(result == .failure(.secondType([tag("type-contract"), tag("type-invoice")])))
}

// MARK: - The sentences (moved to Core, wording byte-identical)

@Test func theFiveExistingSentencesKeepTheirWords() {
    #expect(ClassificationRefusal.noTopic.sentence == "Scegli almeno un argomento.")
    #expect(ClassificationRefusal.notATopic(tag("area-sales")).sentence == "area-sales non è un argomento.")
    #expect(ClassificationRefusal.unknownType(tag("type-fattura")).sentence
        == "type-fattura non è un tipo del vocabolario.")
    #expect(ClassificationRefusal.secondType([tag("type-contract"), tag("type-invoice")]).sentence
        == "Un solo tipo per documento: type-contract, type-invoice.")
    #expect(ClassificationRefusal.tooManyTags(count: 8).sentence == "8 tag, massimo 7.")
}

@Test func theDateTopicSentenceNamesTheTagItRefused() {
    let sentence = ClassificationRefusal.dateTopic(tag("topic-2026")).sentence

    #expect(sentence.contains("topic-2026"))
}

@Test func isDateLikeIsReachableAsTheSharedPredicate() {
    #expect(TagRules.isDateLike("2026"))
    #expect(TagRules.isDateLike("2026-08-11"))
    #expect(TagRules.isDateLike("20260811"))
    #expect(!TagRules.isDateLike("4140"))
    #expect(!TagRules.isDateLike("guarnizioni"))
}
