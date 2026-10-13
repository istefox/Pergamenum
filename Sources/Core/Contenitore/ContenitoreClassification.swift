import Foundation

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D12, plan
// docs/plans/contenitore.md, Task 2 - R-18.

/// Why «Classifica» refused a classification.
enum ClassificationRefusal: Error, Equatable, Sendable {
    /// No `topic-*` was chosen: a classified scheda must carry one, or it fails the linter's
    /// topic rule once `status-inbox` is gone.
    case noTopic
    /// A tag offered as a topic is not a `topic-*`.
    case notATopic(Tag)
    /// A tag offered as a topic encodes a date (T-07): `topic-2026`, `topic-20261011`.
    /// (PG-387, ADR-0085 §D3: the one rule refuses it for a note and a scheda alike.)
    case dateTopic(Tag)
    /// The content type is not a `type-*` of the closed vocabulary.
    case unknownType(Tag)
    /// The result would carry more than one content type besides `type-note`.
    case secondType([Tag])
    /// The result would carry more than `TagRules.maximumTagsPerNote` tags.
    case tooManyTags(count: Int)
}

/// «Classificato» is `status-inbox` removed and at least one `topic-*` present (SPEC
/// "Colour and classification", ADR-0071 §D12).
enum ContenitoreClassification {
    /// The scheda's tags after «Classifica»: `tags` with `status-inbox` removed, `type-note`
    /// kept (added if missing), the chosen `topics` and the optional content `type` added,
    /// in frontmatter order. Refused when there is no topic, a topic is not a `topic-*` or
    /// encodes a date, the type is not in the vocabulary, a second content type would result,
    /// or more than seven tags would. `NoteClassification.classify` with a type added.
    static func classify(
        tags: [Tag],
        topics: [Tag],
        type: Tag?,
        vocabulary: Vocabulary
    ) -> Result<[Tag], ClassificationRefusal> {
        // The note rule's topic checks first, in its order (PG-387, ADR-0085 §D3: one rule).
        if let refusal = NoteClassification.topicRefusal(topics) { return .failure(refusal) }
        if let type, type.namespace != .type || !vocabulary.type.contains(type.value) {
            return .failure(.unknownType(type))
        }

        let result = NoteClassification.merge(tags: tags, adding: topics + [type].compactMap(\.self))

        let typeNote = Tag(namespace: .type, value: "note")
        let contentTypes = result.filter { $0.namespace == .type && $0 != typeNote }
        if contentTypes.count > 1 { return .failure(.secondType(TagRules.ordered(contentTypes))) }
        if result.count > TagRules.maximumTagsPerNote { return .failure(.tooManyTags(count: result.count)) }
        return .success(TagRules.ordered(result))
    }
}
