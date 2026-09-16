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
    /// The two advisory task-marker rules of ADR-0021 §D11 (R-11, R-12). Defaulted so
    /// the six existing construction sites, all passing the same five labelled
    /// arguments above, keep compiling untouched.
    var taskMarkers: [TaskMarkerViolation] = []
    /// The two advisory `pergamenum-category` rules of ADR-0047 (R-10). Defaulted so
    /// the seven existing construction sites keep compiling untouched.
    var categories: [CategoryViolation] = []

    var isEmpty: Bool {
        name.isEmpty && frontmatter.isEmpty && tags.isEmpty
            && relatedMissingInSection.isEmpty && relatedMissingInFrontmatter.isEmpty
            && taskMarkers.isEmpty && categories.isEmpty
    }

    var count: Int {
        name.count + frontmatter.count + tags.count
            + relatedMissingInSection.count + relatedMissingInFrontmatter.count
            + taskMarkers.count + categories.count
    }
}

/// The two advisory findings ADR-0021 §D11 adds to the linter of SPEC §4.7. Both are
/// produced by `VaultSession.violations(path:title:text:)` from the note's own text,
/// no index, no vault - and neither blocks a write (SPEC §4.7: "the linter reports and
/// does not correct").
enum TaskMarkerViolation: Equatable, Sendable {
    /// A task line carrying a second `^[[...]].canvas` marker (R-11). `kept` is the
    /// target used at read/index time - the first occurrence - and `ignored` is the
    /// second one, which `TaskParser` already discards silently; this is what makes
    /// that silence visible in the Conformità list.
    case duplicateWorkspace(line: Int, kept: String, ignored: String)
    /// A `^parent(N)` whose `^id(N)` does not exist in the same note (R-12). Ids are
    /// note-local (ADR-0021 §D2), so a matching id in a *different* note does not
    /// clear this finding.
    case orphanedParent(line: Int, parent: Int)
}

/// The two advisory `pergamenum-category` rules of ADR-0047 §D10 (R-10). Both need the
/// registry and the index - neither is a fact about the note's own text alone - which is
/// why they are produced by `VaultSession.violations(path:title:text:)` itself rather
/// than by a pure function like `taskMarkerViolations` above.
enum CategoryViolation: Equatable, Sendable {
    /// `pergamenum-category` names a slug the registry does not have. Fires even when
    /// the slug is already an *implicit* category from some task's own `#project-*` tag
    /// (SPEC edge case): inheritance still works, but a note-level link naming an
    /// unregistered slug is still a note-level finding, not a task-level one.
    case unknownSlug(String)
    /// A second note claims a slug an earlier one already claims. `home` is that
    /// earlier note's own path - the first in vault order, deterministically (SPEC
    /// "Nota collegata") - never this note's own path.
    case duplicateHome(String, home: String)
}
