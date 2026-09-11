import Foundation

/// The linter of SPEC §4.7, as `perg lint` and the MCP `lint` tool ask it from the app side.
///
/// The rules are on `VaultSession` (ADR-0007 §D3), so every caller judges a note by the same
/// code.
extension VaultController {
    /// Validates any note in the vault by path.
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
