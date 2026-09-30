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
    /// in frontmatter order. Refused when there is no topic, a topic is not a `topic-*`, the
    /// type is not in the vocabulary, a second content type would result, or more than seven
    /// tags would.
    static func classify(
        tags: [Tag],
        topics: [Tag],
        type: Tag?,
        vocabulary: Vocabulary
    ) -> Result<[Tag], ClassificationRefusal> {
        guard !topics.isEmpty else { return .failure(.noTopic) }
        if let stray = topics.first(where: { $0.namespace != .topic }) {
            return .failure(.notATopic(stray))
        }
        if let type, type.namespace != .type || !vocabulary.type.contains(type.value) {
            return .failure(.unknownType(type))
        }

        let typeNote = Tag(namespace: .type, value: "note")
        let inbox = Tag(namespace: .status, value: "inbox")
        var result = tags.filter { $0 != inbox }
        for tag in [typeNote] + topics + [type].compactMap(\.self) where !result.contains(tag) {
            result.append(tag)
        }

        let contentTypes = result.filter { $0.namespace == .type && $0 != typeNote }
        if contentTypes.count > 1 { return .failure(.secondType(TagRules.ordered(contentTypes))) }
        if result.count > TagRules.maximumTagsPerNote { return .failure(.tooManyTags(count: result.count)) }
        return .success(TagRules.ordered(result))
    }
}
