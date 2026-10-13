import Foundation

// PG-387 (N4), ADR-0085 §D5, plan docs/plans/pg-387-n4-birth-of-note.md, Task 5 - R-04.

/// The frontmatter preview «Classifica…» draws: the tags before and after, with `status-inbox`
/// struck through and the tags the classification adds marked.
enum ClassificaPreview {
    struct Line: Equatable {
        let tag: Tag
        let struck: Bool
        let added: Bool
    }

    /// One line per tag of `current` (struck when `result` drops it) and per added tag of `result`.
    static func lines(current: [Tag], result: [Tag]) -> [Line] {
        let kept = current.map { Line(tag: $0, struck: !result.contains($0), added: false) }
        let added = result.filter { !current.contains($0) }.map { Line(tag: $0, struck: false, added: true) }
        return kept + added
    }

    /// «N di 7 tag».
    static func countLabel(_ count: Int) -> String {
        "\(count) di \(TagRules.maximumTagsPerNote) tag"
    }
}
