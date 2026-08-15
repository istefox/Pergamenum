import Foundation

/// Creating a note, bringing a file into the vault, and linking two notes to each
/// other, as the app asks for them.
///
/// The work is on `VaultSession` (ADR-0007 §D3). What is left here is the part that
/// only makes sense with an editor on screen: a note the user just made is a note the
/// user wants to be looking at.
extension VaultController {
    /// Names the error type where it always was, so a view that catches it and the
    /// tests that expect it did not have to move with the code.
    typealias CreationError = VaultSession.CreationError

    /// Creates a note and opens it.
    @discardableResult
    func createNote(
        title: String,
        in folder: String = "",
        date: CalendarDate,
        category: NoteCategory = .note,
        topics: [Tag] = []
    ) throws -> String {
        guard let session else { throw CreationError.alreadyExists("nessuna cartella note aperta") }
        let relativePath = try session.createNote(
            title: title, in: folder, date: date, category: category, topics: topics
        )
        openNote(at: relativePath)
        return relativePath
    }

    /// Copies a dropped file into the folder of the note being edited and returns its
    /// name for the embed (SPEC §5).
    func importFileIntoVault(_ source: URL, near notePath: String) -> String? {
        session?.importFile(source, near: notePath)
    }

    /// Writes an image from the clipboard into the vault beside a note and returns its
    /// file name for the embed.
    func importPastedImage(_ data: Data, near notePath: String) -> String? {
        session?.importPastedImage(data, near: notePath)
    }

    /// The tags the editor offers after a `#`, most useful first.
    var tagSuggestions: [String] { session?.tagSuggestions ?? [] }

    /// Creates a structural link in both directions (wikilink.md W-05), and puts the
    /// editor back in step when it is showing the note that gained one.
    @discardableResult
    func addStructuralLink(
        from sourcePath: String,
        to targetTitle: String,
        reason: String,
        reverseReason: String
    ) -> Bool {
        guard let session else { return false }
        let created = session.addStructuralLink(
            from: sourcePath, to: targetTitle, reason: reason, reverseReason: reverseReason
        )
        if created, openNote?.relativePath == sourcePath { openNote(at: sourcePath) }
        return created
    }
}
