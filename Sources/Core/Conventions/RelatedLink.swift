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

    /// The note's own line break (ADR-0065 §D3, R-01): «Collega» on a CRLF note writes CRLF.
    private static func lineBreak(of document: NoteDocument) -> LineBreak {
        document.source?.lineBreak ?? .lf
    }

    /// Adds the bullet under `## Note correlate`, creating the section when absent and
    /// keeping the bullets in the same alphabetical order as `related` (W-06).
    ///
    /// Only the new bullet's line is written (PG-372): every other line of the section - prose,
    /// a fence and its own `-` lines, an indented sub-item, the blank lines, the bullets already
    /// there - stays as written and where it was. Rewriting the section from its bullets alone
    /// dropped all of it.
    private static func addBullet(target: String, reason: String, to body: String, lineBreak: LineBreak) -> String {
        let bullet = "- [[\(target)]] — \(reason)"
        let newline = lineBreak.characters

        guard let section = RelatedSection.sectionRange(in: body) else {
            // Scalar-level: a CRLF body ends in one `\r\n` Character, which is not `"\n"`.
            let separator = body.unicodeScalars.last == "\n" ? newline : newline + newline
            return body + separator + RelatedSection.heading + newline + newline + bullet + newline
        }
        guard let start = RelatedSection.bulletsStart(in: body, section: section) else {
            // The heading is the body's last line and has no line break of its own.
            return body + newline + newline + bullet + newline
        }
        let (index, text) = bulletInsertion(
            of: bullet, in: body, lines: RelatedSection.lines(of: body, in: start..<section.upperBound),
            sectionEnd: section.upperBound, newline: newline
        )
        var scalars = body.unicodeScalars
        scalars.insert(contentsOf: text.unicodeScalars, at: index)
        return String(scalars)
    }

    /// Where the new bullet goes, and the text inserted there: before the first link bullet
    /// that sorts after it; else after the last link bullet and its continuation lines; else,
    /// in a section with no link bullet, under the heading's blank line, set off from what
    /// follows by a blank line of its own. Only a bullet that links to a note is a sort anchor
    /// (`linkTarget(of:)`, the test `RelatedSection.parse` applies): a prose bullet such as
    /// `- vedi la cartella` is kept where it is and never pulls a new link above it. What a
    /// bullet is, and what belongs to it, is `roles(of:code:)`.
    private static func bulletInsertion(
        of bullet: String, in body: String, lines: [RelatedSection.Line], sectionEnd: String.Index, newline: String
    ) -> (String.Index, String) {
        let roles = RelatedSection.roles(of: lines, code: WikilinkParser.codeRanges(in: body))
        let anchors = lines.indices.filter { roles[$0] == .bullet && linkTarget(of: lines[$0].text) != nil }
        var position: Int
        var text = bullet + newline
        if let next = anchors.first(where: { RelatedSection.trimmed(lines[$0].text) > bullet }) {
            position = next
        } else if let last = anchors.last {
            position = last + 1
            while position < lines.count, roles[position] == .continuation { position += 1 }
        } else {
            position = lines.first.map { RelatedSection.isBlank($0.text) } == true ? 1 : 0
            if position == 0 { text = newline + text }
            let followed = position < lines.count
                ? !RelatedSection.isBlank(lines[position].text)
                : sectionEnd < body.endIndex
            if followed { text += newline }
        }
        guard position < lines.count else {
            // The body's last line may have no line break of its own: the new line needs one first.
            if lines.last?.isTerminated == false { text = newline + text }
            return (sectionEnd, text)
        }
        return (lines[position].start, text)
    }

    /// The title a bullet links to, read as `RelatedSection.parse` reads it: the first wikilink
    /// after the `-`, unless it is an embed.
    private static func linkTarget(of line: String) -> String? {
        let content = String(RelatedSection.trimmed(line).dropFirst()).trimmingCharacters(in: .whitespaces)
        guard let link = WikilinkParser.links(in: content).first, !link.isEmbed else { return nil }
        return link.target
    }

    /// Removes the target's bullet from `## Note correlate`, the inverse of `addBullet` (PG-372):
    /// only its lines go, every other line of the section stays as written, in its own line break.
    /// When nothing but blank lines is left under the heading they collapse as they always have:
    /// none, or one before a heading that follows.
    private static func removeBullet(target: String, from body: String, lineBreak: LineBreak) -> String {
        guard let section = RelatedSection.sectionRange(in: body),
              let start = RelatedSection.bulletsStart(in: body, section: section)
        else { return body }
        let lines = RelatedSection.lines(of: body, in: start..<section.upperBound)
        let removed = removedLines(
            for: target, in: lines, roles: RelatedSection.roles(of: lines, code: WikilinkParser.codeRanges(in: body)),
            reachesBodyEnd: section.upperBound == body.endIndex
        )
        guard !removed.isEmpty else { return body }

        let scalars = body.unicodeScalars
        let survivors = lines.indices.filter { !removed.contains($0) }
        var result = String(scalars[..<start])
        if survivors.allSatisfy({ RelatedSection.isBlank(lines[$0].text) }) {
            if section.upperBound < body.endIndex { result += lineBreak.characters }
        } else {
            for index in survivors {
                let end = index + 1 < lines.count ? lines[index + 1].start : section.upperBound
                result += String(scalars[lines[index].start..<end])
            }
        }
        return result + String(scalars[section.upperBound...])
    }

    /// The lines `removeBullet` takes out: each bullet linking to `target` with its continuation
    /// lines, which belong to it. A bullet set off by a blank line on each side also takes one of
    /// the two, and one ending the note takes the blank line before it. That is the shape
    /// `addBullet` writes under a heading followed by a blank line, so a link added there and
    /// then removed leaves the section as it was; under a heading with no blank line after it,
    /// or beside prose, the blank line `addBullet` added is not given back.
    private static func removedLines(
        for target: String, in lines: [RelatedSection.Line], roles: [RelatedSection.Role], reachesBodyEnd: Bool
    ) -> Set<Int> {
        var removed = Set<Int>()
        var index = 0
        while index < lines.count {
            guard roles[index] == .bullet, linkTarget(of: lines[index].text) == target else {
                index += 1
                continue
            }
            var end = index + 1
            while end < lines.count, roles[end] == .continuation { end += 1 }
            removed.formUnion(index..<end)
            let before = index - 1
            if before >= 0, !removed.contains(before), RelatedSection.isBlank(lines[before].text) {
                if end < lines.count, RelatedSection.isBlank(lines[end].text) {
                    removed.insert(end)
                    end += 1
                } else if end == lines.count, reachesBodyEnd {
                    removed.insert(before)
                }
            }
            index = end
        }
        return removed
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

/// The lines of `## Note correlate` and their roles: one reading shared by `RelatedSection.parse`
/// (the linter, «Collega»'s own count) and `RelatedLink` (where a bullet goes and what leaves
/// with it), so the two cannot disagree on what a link bullet is (PG-378).
extension RelatedSection {
    /// One line of the section: where it starts, its text up to the `\n` (a CRLF line keeps its
    /// `\r`), and whether a `\n` ends it.
    struct Line {
        let start: String.Index
        let text: String
        let isTerminated: Bool
    }

    /// The lines of `range`, walked on unicode scalars as `RelatedSection.sectionRange` does,
    /// since a CRLF pair is one `Character`.
    static func lines(of body: String, in range: Range<String.Index>) -> [Line] {
        let scalars = body.unicodeScalars
        var lines: [Line] = []
        var lineStart = range.lowerBound
        while lineStart < range.upperBound {
            let lineEnd = scalars[lineStart..<range.upperBound].firstIndex(of: "\n")
            let text = String(scalars[lineStart..<(lineEnd ?? range.upperBound)])
            lines.append(Line(start: lineStart, text: text, isTerminated: lineEnd != nil))
            guard let lineEnd else { break }
            lineStart = scalars.index(after: lineEnd)
        }
        return lines
    }

    static func trimmed(_ line: String) -> String {
        line.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isBlank(_ line: String) -> Bool {
        trimmed(line).isEmpty
    }

    /// What a line of the section is, for placing and removing a bullet.
    enum Role: Equatable {
        case blank, bullet, continuation, other
    }

    /// The role of each line. A bullet is a `-` indented by at most three spaces (CommonMark,
    /// and `RelatedSection.parse`, which trims every line, reads ` - [[B]]` as a link too)
    /// outside a fence (`WikilinkParser.codeRanges`, the rule `sectionRange` already applies).
    /// A continuation is a non-blank line right under a bullet (no blank line between) that is
    /// indented more than the bullet itself - a wrapped reason, or text under it - and a `-`
    /// line only if it is indented at least two columns more (a sub-item); one column more is a
    /// sibling bullet. A tab counts as four columns. A blank line ends the bullet, so the later
    /// paragraph of a loose item is not part of it and stays in the section as prose when the
    /// bullet is removed.
    static func roles(of lines: [Line], code: [Range<String.Index>]) -> [Role] {
        var roles: [Role] = []
        var bulletIndent: Int?
        for line in lines {
            guard !isBlank(line.text) else {
                roles.append(.blank)
                bulletIndent = nil
                continue
            }
            let width = indentWidth(of: line.text)
            let isDash = trimmed(line.text).hasPrefix("-")
            let isFenced = code.contains { $0.contains(line.start) }
            if isDash, !isFenced, width <= 3, bulletIndent.map({ width < $0 + 2 }) ?? true {
                roles.append(.bullet)
                bulletIndent = width
            } else if let indent = bulletIndent, width > indent {
                roles.append(.continuation)
            } else {
                roles.append(.other)
                bulletIndent = nil
            }
        }
        return roles
    }

    /// The columns of leading whitespace; a tab advances to the next multiple of four.
    private static func indentWidth(of line: String) -> Int {
        var width = 0
        for scalar in line.unicodeScalars {
            if scalar == " " {
                width += 1
            } else if scalar == "\t" {
                width = (width / 4 + 1) * 4
            } else {
                break
            }
        }
        return width
    }
}
