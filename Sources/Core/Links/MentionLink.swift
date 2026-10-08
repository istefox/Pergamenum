import Foundation

// ADR-0084 §D3 (PG-386, N3 session A).

/// What «Collega» writes for a mention.
///
/// `[[Titolo]]` when the matched text is the title byte for byte, otherwise `[[Titolo|testo]]`,
/// so the prose reads exactly as it did - an alias, a case or an accent difference alike.
/// `[[alias]]` alone would dangle: `resolve(title:)` indexes titles, not aliases. Everything
/// outside the mention's range is left byte for byte.
enum MentionLink {
    static func rewrite(_ text: String, mention: UnlinkedMentions.Mention, title: String) -> String {
        let link = mention.matched == title ? "[[\(title)]]" : "[[\(title)|\(mention.matched)]]"
        return (text as NSString).replacingCharacters(in: mention.range, with: link)
    }
}
