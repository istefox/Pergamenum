import Foundation

/// Creates a structural link between two notes (SPEC §4.5, wikilink.md W-04/W-05).
///
/// A structural link is written twice in each note - once in `related`, once as a
/// bullet under `## Note correlate` - and both notes get it, each with its own reason.
/// The app keeps the two writings aligned so the linter never has to report a
/// discrepancy it caused itself.
enum RelatedLink {
    enum Error: Swift.Error, CustomStringConvertible {
        case reasonRequired
        case tooManyLinks(count: Int)
        case linkingToItself

        var description: String {
            switch self {
            case .reasonRequired:
                "un legame strutturale richiede un motivo (W-04)"
            case .tooManyLinks(let count):
                "\(count) legami strutturali, massimo \(RelatedSection.maximumLinks) (W-09)"
            case .linkingToItself:
                "una nota non si collega a se stessa"
            }
        }
    }

    /// Adds a structural link to one note's text.
    ///
    /// Both writings are updated together: `related` in the frontmatter and the bullet
    /// under the heading. Writing only one is what produces the W-06 discrepancy the
    /// conformance view reports.
    static func add(
        target: String,
        reason: String,
        to text: String,
        selfTitle: String
    ) throws -> String {
        let trimmedReason = reason.trimmingCharacters(in: .whitespaces)
        // W-04: without a reason it is a citation, not a structural link, and belongs
        // inline in the body rather than in `related`.
        guard !trimmedReason.isEmpty else { throw Error.reasonRequired }
        guard target != selfTitle else { throw Error.linkingToItself }

        var document = NoteDocument.parse(text)
        let existing = RelatedSection.parse(from: document.body)
        guard !existing.contains(where: { $0.target == target }) else { return text }
        guard existing.count < RelatedSection.maximumLinks else {
            throw Error.tooManyLinks(count: existing.count + 1)
        }

        let quoted = "[[\(target)]]"
        if !document.frontmatter.related.contains(where: { normalised($0) == target }) {
            document.frontmatter.related.append(quoted)
            document.frontmatter.related.sort()
        }
        document.body = addBullet(target: target, reason: trimmedReason, to: document.body)
        return document.serialized()
    }

    /// Removes a structural link from both writings.
    static func remove(target: String, from text: String) -> String {
        var document = NoteDocument.parse(text)
        document.frontmatter.related.removeAll { normalised($0) == target }
        document.body = removeBullet(target: target, from: document.body)
        return document.serialized()
    }

    /// Adds the bullet under `## Note correlate`, creating the section when absent and
    /// keeping the bullets in the same alphabetical order as `related` (W-06).
    private static func addBullet(target: String, reason: String, to body: String) -> String {
        let bullet = "- [[\(target)]] — \(reason)"

        guard let heading = body.range(of: RelatedSection.heading) else {
            let separator = body.hasSuffix("\n") ? "\n" : "\n\n"
            return body + separator + RelatedSection.heading + "\n\n" + bullet + "\n"
        }

        let afterHeading = body[heading.upperBound...]
        let sectionEnd = afterHeading.range(of: "\n#")?.lowerBound ?? body.endIndex

        var bullets = body[heading.upperBound..<sectionEnd]
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("-") }
        bullets.append(bullet)
        bullets.sort()

        var result = body
        result.replaceSubrange(
            heading.upperBound..<sectionEnd,
            with: "\n\n" + bullets.joined(separator: "\n") + "\n"
        )
        return result
    }

    private static func removeBullet(target: String, from body: String) -> String {
        guard let heading = body.range(of: RelatedSection.heading) else { return body }
        let afterHeading = body[heading.upperBound...]
        let sectionEnd = afterHeading.range(of: "\n#")?.lowerBound ?? body.endIndex

        let bullets = body[heading.upperBound..<sectionEnd]
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("-") }
            .filter { !$0.contains("[[\(target)]]") }

        var result = body
        result.replaceSubrange(
            heading.upperBound..<sectionEnd,
            with: bullets.isEmpty ? "\n" : "\n\n" + bullets.joined(separator: "\n") + "\n"
        )
        return result
    }

    /// `"[[Titolo]]"` and `[[Titolo]]` both reduce to the bare title.
    private static func normalised(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("\""), text.hasSuffix("\""), text.count >= 2 {
            text = String(text.dropFirst().dropLast())
        }
        return WikilinkParser.links(in: text).first?.target ?? text
    }
}
