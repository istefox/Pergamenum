import Foundation

// ADR-0085 §D7, plan docs/plans/pg-387-n4-birth-of-note.md - R-12, and the topic parse of
// R-05 / R-15.

/// The one pure door from typed text to a tag.
///
/// The composer's tag field, «Classifica…» and both connectors read typed text through here, so
/// a value refused in one is refused in all of them.
enum TagEntry {
    enum Refusal: Error, Equatable, Sendable {
        case malformed(String)
        case notInVocabulary(Tag)
        case vocabularyUnavailable(TagNamespace)
        case dateTag(Tag)
        case notAllowedHere(Tag)

        /// The sentence a person reads for the refusal.
        var sentence: String {
            switch self {
            case .malformed(let text): "«\(text)» non è un tag valido."
            case .notInVocabulary(let tag): "\(tag) non è nel vocabolario."
            case .vocabularyUnavailable(let namespace):
                "Il vocabolario di \(namespace)-* non è disponibile: il valore non si può verificare."
            case .dateTag(let tag): "\(tag) è una data, e un tag non codifica date."
            case .notAllowedHere(let tag): "\(tag) non si sceglie qui: \(tag.namespace)-* lo assegna la nota."
            }
        }
    }

    /// Typed text as a tag: bare text reads as a topic, a closed-family value outside the
    /// vocabulary is refused, `type-*` and `status-*` are refused unless `namespaces` allows them.
    ///
    /// Checked in this order: the shape, the family, a date-shaped value, the vocabulary.
    static func check(
        _ typed: String,
        allowing namespaces: Set<TagNamespace>,
        vocabulary: Vocabulary
    ) -> Result<Tag, TagEntry.Refusal> {
        let text = bare(typed)
        guard let tag = Tag(text) ?? (Tag.isWellFormedValue(text) ? Tag(namespace: .topic, value: text) : nil)
        else { return .failure(.malformed(typed.trimmingCharacters(in: .whitespaces))) }
        guard namespaces.contains(tag.namespace) else { return .failure(.notAllowedHere(tag)) }
        if TagRules.isDateLike(tag.value) { return .failure(.dateTag(tag)) }
        if let allowed = vocabulary.values(for: tag.namespace) {
            if allowed.isEmpty { return .failure(.vocabularyUnavailable(tag.namespace)) }
            if !allowed.contains(tag.value) { return .failure(.notInVocabulary(tag)) }
        }
        return .success(tag)
    }

    /// What the field offers while `typed` is being written: vocabulary values for the closed
    /// families, used values (most used first) for the open ones, never a chosen tag.
    ///
    /// `typed` with a family prefix (`client-a`) matches whole tags; bare text matches values in
    /// any allowed family.
    static func completions(
        for typed: String,
        allowing namespaces: Set<TagNamespace>,
        usage: [(tag: Tag, count: Int)],
        vocabulary: Vocabulary,
        excluding chosen: [Tag],
        limit: Int
    ) -> [Tag] {
        let text = bare(typed)
        let hasFamily = TagNamespace.allCases.contains { text.hasPrefix($0.rawValue + "-") }
        func matches(_ tag: Tag) -> Bool {
            hasFamily ? tag.description.hasPrefix(text) : tag.value.hasPrefix(text)
        }

        let used = usage
            .filter { !$0.tag.namespace.isClosed }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.tag < $1.tag }
            .map(\.tag)
        let closed = TagNamespace.allCases.filter(\.isClosed).flatMap { namespace in
            (vocabulary.values(for: namespace) ?? []).sorted().map { Tag(namespace: namespace, value: $0) }
        }

        var offered: [Tag] = []
        for tag in used + closed
        where offered.count < limit && namespaces.contains(tag.namespace) && !chosen.contains(tag)
            && !offered.contains(tag) && matches(tag) {
            offered.append(tag)
        }
        return offered
    }

    /// The connectors' comma-separated topic string as tags: empty items ignored, the first
    /// refused item is the refusal.
    static func topics(fromList list: String, vocabulary: Vocabulary) -> Result<[Tag], TagEntry.Refusal> {
        var topics: [Tag] = []
        for item in list.split(separator: ",") {
            let trimmed = item.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            switch check(trimmed, allowing: [.topic], vocabulary: vocabulary) {
            case .success(let tag): if !topics.contains(tag) { topics.append(tag) }
            case .failure(let refusal): return .failure(refusal)
            }
        }
        return .success(topics)
    }

    /// `typed` without surrounding spaces and a leading `#`.
    private static func bare(_ typed: String) -> String {
        var text = typed.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        return text
    }
}
