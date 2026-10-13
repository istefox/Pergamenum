import Foundation

// ADR-0085 §D3, plan docs/plans/pg-387-n4-birth-of-note.md - R-02.

/// The one rule that classifies any note: `status-inbox` removed, `type-note` kept or added,
/// the topics added, at most seven tags. `ContenitoreClassification.classify` is this rule plus
/// the optional content type.
enum NoteClassification {
    /// The note's tags after «Classifica», in frontmatter order, or why it was refused.
    ///
    /// Refusal order: no topic, a tag that is not a topic, a date-shaped topic, then the count.
    ///
    /// `vocabulary` is not read, and nothing is validated against it: topics are an open family,
    /// whose shape `TagEntry` checks as they are typed (ADR-0085 §D3). It is kept for parity with
    /// `ContenitoreClassification.classify` and because the plan declares this signature.
    static func classify(
        tags: [Tag],
        topics: [Tag],
        vocabulary: Vocabulary
    ) -> Result<[Tag], ClassificationRefusal> {
        if let refusal = topicRefusal(topics) { return .failure(refusal) }
        let result = merge(tags: tags, adding: topics)
        if result.count > TagRules.maximumTagsPerNote { return .failure(.tooManyTags(count: result.count)) }
        return .success(TagRules.ordered(result))
    }

    /// The topic checks both rules run first, in this order.
    static func topicRefusal(_ topics: [Tag]) -> ClassificationRefusal? {
        guard !topics.isEmpty else { return .noTopic }
        if let stray = topics.first(where: { $0.namespace != .topic }) { return .notATopic(stray) }
        if let dated = topics.first(where: { TagRules.isDateLike($0.value) }) { return .dateTopic(dated) }
        return nil
    }

    /// The merge both rules share: `status-inbox` removed, `type-note` and `added` appended when
    /// missing. Unordered: each rule checks its own refusals on it before ordering.
    static func merge(tags: [Tag], adding added: [Tag]) -> [Tag] {
        let typeNote = Tag(namespace: .type, value: "note")
        let inbox = Tag(namespace: .status, value: "inbox")
        var result = tags.filter { $0 != inbox }
        for tag in [typeNote] + added where !result.contains(tag) {
            result.append(tag)
        }
        return result
    }
}

extension ClassificationRefusal {
    /// The sentence «Classifica» shows for the refusal. The five existing wordings moved here
    /// from `ContenitoreInspectorModel.swift` byte-identical, so the Contenitore keeps its words
    /// and the connectors can use them.
    var sentence: String {
        switch self {
        case .noTopic: "Scegli almeno un argomento."
        case .notATopic(let tag): "\(tag) non è un argomento."
        case .dateTopic(let tag): "\(tag) è una data, non un argomento."
        case .unknownType(let tag): "\(tag) non è un tipo del vocabolario."
        case .secondType(let tags): "Un solo tipo per documento: \(tags.map(\.description).joined(separator: ", "))."
        case .tooManyTags(let count): "\(count) tag, massimo \(TagRules.maximumTagsPerNote)."
        }
    }
}
