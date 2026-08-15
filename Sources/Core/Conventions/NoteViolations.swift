import Foundation

/// Everything the linter of SPEC §4.7 found wrong with one note.
///
/// In `Core/Conventions` with the rules that produce it, rather than at the bottom of
/// `VaultController.swift` where it began: the verdict on a note is not a fact about
/// the app's user interface, and `perg lint` has to name the same type the Conformità
/// pane does (ADR-0007 §D2).
struct NoteViolations: Equatable, Sendable {
    var name: [NoteName.Violation]
    var frontmatter: [FrontmatterViolation]
    var tags: [TagViolation]
    var relatedMissingInSection: [String]
    var relatedMissingInFrontmatter: [String]

    var isEmpty: Bool {
        name.isEmpty && frontmatter.isEmpty && tags.isEmpty
            && relatedMissingInSection.isEmpty && relatedMissingInFrontmatter.isEmpty
    }

    var count: Int {
        name.count + frontmatter.count + tags.count
            + relatedMissingInSection.count + relatedMissingInFrontmatter.count
    }
}
