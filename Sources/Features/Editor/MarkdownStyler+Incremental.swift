import Foundation

/// The fragment entry of the styler (ADR-0091 §D4).
///
/// Foundation only (ADR-0091 §D1): `MarkdownStyler` is not a shared source, so neither is this file.
extension MarkdownStyler {
    /// The only two things a fragment cannot see for itself.
    struct FragmentContext: Equatable, Sendable {
        /// The list stack in force at the fragment's first line.
        var listSeed: [Int]
        /// Whether a leading `---` is frontmatter: only when the fragment starts the note.
        var readsFrontmatter: Bool
    }

    /// `spans(in:)` over a fragment: the same steps in the same order, indices the fragment's own.
    /// The widening guarantees that no fence, table run, view block or wikilink crosses the
    /// fragment's edges, so these are the whole note's spans inside it.
    static func spans(inFragment fragment: String, context: FragmentContext) -> [StyledRange] {
        spans(in: fragment, readsFrontmatter: context.readsFrontmatter, listSeed: context.listSeed)
    }

    /// `current` with `dirty` cut out and `fragment` (already in the note's coordinates) put in,
    /// re-merged at the two seams only (ADR-0091 §D5). `current` is sorted and merged, as
    /// `merged(_:)` leaves it.
    static func spliced(_ current: [NSRange], replacing dirty: NSRange, with fragment: [NSRange]) -> [NSRange] {
        let dirtyEnd = NSMaxRange(dirty)
        var head: [NSRange] = []
        var tail: [NSRange] = []
        for range in current {
            if NSMaxRange(range) <= dirty.location {
                head.append(range)
            } else if range.location >= dirtyEnd {
                tail.append(range)
            } else {
                if range.location < dirty.location {
                    head.append(NSRange(location: range.location, length: dirty.location - range.location))
                }
                if NSMaxRange(range) > dirtyEnd {
                    tail.append(NSRange(location: dirtyEnd, length: NSMaxRange(range) - dirtyEnd))
                }
            }
        }

        var result = head
        for range in merged(fragment) + tail {
            if let last = result.last, range.location <= NSMaxRange(last) {
                let end = max(NSMaxRange(last), NSMaxRange(range))
                result[result.count - 1] = NSRange(location: last.location, length: end - last.location)
            } else {
                result.append(range)
            }
        }
        return result
    }
}
