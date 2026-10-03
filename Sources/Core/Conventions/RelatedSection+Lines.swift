import Foundation

/// The lines of `## Note correlate` and what each one is (PG-378). One walk, read by the linter
/// and search (`RelatedSection.parse`) and by «Collega»/«Scollega» (`RelatedLink`): with two
/// copies the linter counted a fenced `- [[B]]` as a link «Collega» could not see, so «Collega»
/// towards B wrote nothing at all.
extension RelatedSection {
    /// One line of the section: where it starts, its text up to the `\n` (a CRLF line keeps its
    /// `\r`), and whether a `\n` ends it. `trimmed` is computed once here, since `roles` and the
    /// writers read it several times per line.
    struct Line {
        let start: String.Index
        let text: String
        let isTerminated: Bool
        let trimmed: String

        init(start: String.Index, text: String, isTerminated: Bool) {
            self.start = start
            self.text = text
            self.isTerminated = isTerminated
            trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var isBlank: Bool { trimmed.isEmpty }
    }

    /// What a line of the section is, for reading, placing and removing a bullet.
    enum LineRole: Equatable {
        case blank, bullet, continuation, other
    }

    /// The lines of `range`, walked on unicode scalars as `sectionRange` does, since a CRLF pair
    /// is one `Character`.
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

    /// The role of each line. A bullet is a `-` indented by at most three columns (CommonMark)
    /// outside a fence (`WikilinkParser.codeRanges`, the rule `sectionRange` already applies).
    /// A continuation is a non-blank line right under a bullet (no blank line between) that is
    /// indented more than the bullet itself - a wrapped reason, or text under it - and a `-`
    /// line only if it is indented at least two columns more (a sub-item); one column more is a
    /// sibling bullet. A tab advances to the next multiple of four columns. A blank line ends the
    /// bullet, so the later paragraph of a loose item is not part of it and stays in the section
    /// as prose when the bullet is removed.
    static func roles(of lines: [Line], code: [Range<String.Index>]) -> [LineRole] {
        var roles: [LineRole] = []
        var bulletIndent: Int?
        for line in lines {
            guard !line.isBlank else {
                roles.append(.blank)
                bulletIndent = nil
                continue
            }
            let width = indentWidth(of: line.text)
            let isDash = line.trimmed.hasPrefix("-")
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
