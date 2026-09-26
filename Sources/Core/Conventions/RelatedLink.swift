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
        document.body = addBullet(
            target: target, reason: trimmedReason, to: document.body, lineBreak: lineBreak(of: document)
        )
        return document.serialized()
    }

    /// Removes a structural link from both writings.
    static func remove(target: String, from text: String) -> String {
        var document = NoteDocument.parse(text)
        document.frontmatter.related.removeAll { normalised($0) == target }
        document.body = removeBullet(target: target, from: document.body, lineBreak: lineBreak(of: document))
        return document.serialized()
    }

    /// The note's own line break (ADR-0064 §D3, R-01): «Collega» on a CRLF note writes CRLF.
    private static func lineBreak(of document: NoteDocument) -> LineBreak {
        document.source?.lineBreak ?? .lf
    }

    /// Adds the bullet under `## Note correlate`, creating the section when absent and
    /// keeping the bullets in the same alphabetical order as `related` (W-06).
    private static func addBullet(target: String, reason: String, to body: String, lineBreak: LineBreak) -> String {
        let bullet = "- [[\(target)]] — \(reason)"
        let newline = lineBreak.characters

        guard let section = RelatedSection.sectionRange(in: body) else {
            // Scalar-level: a CRLF body ends in one `\r\n` Character, which is not `"\n"`.
            let separator = body.unicodeScalars.last == "\n" ? newline : newline + newline
            return body + separator + RelatedSection.heading + newline + newline + bullet + newline
        }
        var bullets = Self.bullets(in: body, section: section)
        bullets.append(bullet)
        bullets.sort()
        return rewritingBullets(of: body, section: section, as: bullets, lineBreak: lineBreak)
    }

    private static func removeBullet(target: String, from body: String, lineBreak: LineBreak) -> String {
        guard let section = RelatedSection.sectionRange(in: body) else { return body }
        let bullets = Self.bullets(in: body, section: section).filter { !$0.contains("[[\(target)]]") }
        return rewritingBullets(of: body, section: section, as: bullets, lineBreak: lineBreak)
    }

    /// The section's bullet lines, trimmed - a CRLF line's `\r` included.
    private static func bullets(in body: String, section: Range<String.Index>) -> [String] {
        guard let start = RelatedSection.bulletsStart(in: body, section: section) else { return [] }
        return body[start..<section.upperBound]
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("-") }
    }

    /// The heading line stays as written; below it, a blank line, the bullets, and a blank line
    /// before the next heading when one follows - every line ended in the note's own line break
    /// (ADR-0064 §D9.3, R-01).
    private static func rewritingBullets(
        of body: String, section: Range<String.Index>, as bullets: [String], lineBreak: LineBreak
    ) -> String {
        let newline = lineBreak.characters
        let start = RelatedSection.bulletsStart(in: body, section: section)
        var replacement = start == nil ? newline : ""
        if !bullets.isEmpty {
            replacement += newline + bullets.joined(separator: newline) + newline
        }
        if section.upperBound < body.endIndex { replacement += newline }

        var result = body
        result.replaceSubrange((start ?? section.upperBound)..<section.upperBound, with: replacement)
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
