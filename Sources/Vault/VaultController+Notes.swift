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
        topics: [Tag] = [],
        body: String = ""
    ) throws -> String {
        guard let session else { throw CreationError.alreadyExists("nessuna cartella note aperta") }
        let relativePath = try session.createNote(
            title: title, in: folder, date: date, category: category, topics: topics, body: body
        ).path
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

    // MARK: The new-note draft

    /// Starts a new note in a folder, nil meaning "wherever the last one was going".
    ///
    /// The naming used to happen in a sheet floating over the window; it now happens in
    /// the editor pane itself, so a new note is composed where it will be edited.
    ///
    /// A parked draft is picked up rather than replaced (PG-028): stepping out to read a
    /// template and coming back with Cmd+N finds the title, the folder and the template
    /// still there. `folder` is nil from Cmd+N and the toolbar, and set only by "Nuova
    /// nota qui", which is the one caller that means a particular folder - a default of
    /// `""` could not tell the two apart and would send every restored draft back to the
    /// vault root.
    ///
    /// Only a draft with a title is picked up, which is the same threshold `parkNewNote`
    /// uses: a folder chosen and then walked away from is not a note somebody started
    /// writing, and Cmd+N still means the vault root.
    func beginNewNote(in folder: String? = nil) {
        var draft = parkedDraft ?? NoteDraft()
        if let folder { draft.folder = folder }
        noteDraft = draft
        isComposingNote = true
    }

    /// The draft worth coming back to, nil when there is none.
    private var parkedDraft: NoteDraft? {
        guard let noteDraft, !noteDraft.title.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }
        return noteDraft
    }

    /// Keeps what was typed when the composer is stepped out of rather than dismissed.
    ///
    /// The guard is the whole mechanism: `endNewNote()` clears the draft, so cancelling
    /// or creating leaves nothing to park and a parking call arriving afterwards - the
    /// composer's `onDisappear`, whose order against the button's action is SwiftUI's to
    /// decide - resurrects nothing. A draft with no title is not worth keeping.
    func parkNewNote(_ draft: NoteDraft) {
        guard noteDraft != nil else { return }
        noteDraft = draft.title.trimmingCharacters(in: .whitespaces).isEmpty ? nil : draft
    }

    /// Closes the composer and throws the draft away: «Annulla», Escape, the ×, and the
    /// note having been created. One method because it is one behaviour - a second name
    /// for it would suggest the two differ.
    func endNewNote() {
        noteDraft = nil
        isComposingNote = false
    }

    /// Whether the open note is the thing on screen, and so whether the panes around the
    /// editor are describing something the reader can see.
    ///
    /// False while the composer covers the editor column: the index, and the inspector's
    /// backlinks, conformance and history, then belong to a note nobody is looking at
    /// (PG-027).
    var isOpenNoteVisible: Bool { openNote != nil && !isComposingNote }
}
