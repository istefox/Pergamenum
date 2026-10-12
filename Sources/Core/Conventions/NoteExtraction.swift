import Foundation

// ADR-0085 §D8, plan docs/plans/pg-387-n4-birth-of-note.md - R-13, R-15.

/// The pure planning of «Estrai in una nota»: a line range to an `NSRange`, the frontmatter check,
/// the extracted text and the source with `[[Titolo]]` in its place. Shared with the connectors.
///
/// Every offset is in UTF-16 units, the unit an `NSTextView` selection and `NSString` count in.
enum NoteExtraction {
    enum Refusal: Error, Equatable, Sendable {
        case empty
        case outOfBounds
        case textChanged
        case touchesFrontmatter

        /// The sentence a person reads for the refusal.
        var sentence: String {
            switch self {
            case .empty: "Non c'è testo da estrarre."
            case .outOfBounds: "L'intervallo indicato non è nella nota."
            case .textChanged: "Il testo selezionato è cambiato nel frattempo: selezionalo di nuovo."
            case .touchesFrontmatter: "La selezione tocca il frontmatter, che resta nella nota."
            }
        }
    }

    struct Plan: Equatable, Sendable {
        let extracted: String
        let replacedSource: String
        let link: String
    }

    /// Lines `lines` (1-based, inclusive, counted over the whole file) as a range of `text`,
    /// the last line's terminator included.
    static func range(ofLines lines: ClosedRange<Int>, in text: String) -> Result<NSRange, NoteExtraction.Refusal> {
        let string = text as NSString
        var lineRanges: [NSRange] = []
        var location = 0
        while location < string.length {
            let line = string.lineRange(for: NSRange(location: location, length: 0))
            lineRanges.append(line)
            location = NSMaxRange(line)
        }
        guard lines.lowerBound >= 1, lines.upperBound <= lineRanges.count else { return .failure(.outOfBounds) }
        let start = lineRanges[lines.lowerBound - 1].location
        return .success(NSRange(location: start, length: NSMaxRange(lineRanges[lines.upperBound - 1]) - start))
    }

    /// The extracted text and the replaced source for `range` of `source`, or why it is refused.
    ///
    /// A final line break in the range stays in the source and is not extracted, so a line range
    /// leaves `[[Titolo]]` on a line of its own. `expectedText`, when given, must be the text at
    /// `range` exactly. A range touching the frontmatter block is refused, so the block is
    /// byte-identical by construction.
    static func plan(
        source: String,
        range: NSRange,
        expectedText: String?,
        title: String
    ) -> Result<NoteExtraction.Plan, NoteExtraction.Refusal> {
        let string = source as NSString
        guard range.location >= 0, range.length >= 0, NSMaxRange(range) <= string.length else {
            return .failure(.outOfBounds)
        }
        let selected = string.substring(with: range)
        if let expectedText, expectedText != selected { return .failure(.textChanged) }
        guard range.location >= frontmatterLength(of: source) else { return .failure(.touchesFrontmatter) }

        var replaced = range
        for terminator in ["\r\n", "\n", "\r"] where selected.hasSuffix(terminator) {
            replaced.length -= (terminator as NSString).length
            break
        }
        guard replaced.length > 0 else { return .failure(.empty) }

        let link = "[[\(title)]]"
        return .success(Plan(
            extracted: string.substring(with: replaced),
            replacedSource: string.replacingCharacters(in: replaced, with: link),
            link: link
        ))
    }

    /// The UTF-16 length of the frontmatter block at the head of `source`, 0 without one.
    private static func frontmatterLength(of source: String) -> Int {
        let document = NoteDocument.parse(source)
        guard document.hasFrontmatterBlock else { return 0 }
        // The body is the verbatim tail after the block; anything else is not a split this can
        // trust, and the whole text counts as the block rather than risk writing into it.
        guard source.hasSuffix(document.body) else { return (source as NSString).length }
        return (source as NSString).length - (document.body as NSString).length
    }
}
