import Foundation

/// The linter of SPEC §4.7, as the conformance view asks it.
///
/// The rules are on `VaultSession` (ADR-0007 §D3), so `perg lint` and this pane judge
/// a note by the same code. What is here is the one call that has no meaning outside
/// the app: the note being edited, which may not be what is on disk.
extension VaultController {
    /// Validates any note in the vault by path, for the vault-wide conformance view.
    func violations(forRecordAt relativePath: String) -> NoteViolations? {
        session?.violations(forRecordAt: relativePath)
    }

    /// Validates the open note as the editor has it, unsaved changes included.
    func violations(for note: OpenNote) -> NoteViolations {
        session?.violations(path: note.relativePath, title: note.title, text: note.text)
            ?? NoteViolations(
                name: [], frontmatter: [], tags: [],
                relatedMissingInSection: [], relatedMissingInFrontmatter: []
            )
    }
}
