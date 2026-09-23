import Foundation

/// Renaming, moving and deleting a note from the sidebar (SPEC §10, context menus).
///
/// The file work is on `VaultSession` (ADR-0007 §D3). Three things stay here, and all
/// three are about the editor: refusing while a buffer has unsaved edits, following
/// the note to its new path if it was open, and rescanning afterwards.
extension VaultController {
    /// Refuses while the note has unsaved edits.
    ///
    /// Moving a file out from under the editor would either lose the buffer or raise
    /// the external-change prompt for a change the app itself made. Asking the user to
    /// save first is the honest version of both.
    ///
    /// Not `private`, since ADR-0026 §D10: `VaultController+Move`'s batch move asks the
    /// same question of every note it is about to carry, and a second copy of the guard
    /// is a second place for it to stop matching the editor's actual state.
    func canOperate(on relativePath: String) -> Bool {
        // The question is whether *any* tab is dirty, so it stops at the first one rather
        // than flattening every column's tabs into an array to ask for its emptiness.
        let hasDirtyTab = columns.contains { column in
            column.tabs.contains { $0.note.relativePath == relativePath && $0.note.hasUnsavedChanges }
        }
        guard !hasDirtyTab else {
            recordProblem(Self.unsavedNoteRefusal)
            return false
        }
        return true
    }

    /// The exact sentence `canOperate(on:)` records, kept as one value so
    /// `VaultController+Move.swift`'s batch-level guard can hand back the same string
    /// through `MoveBatchOutcome.refusals` instead of a second wording of it.
    static let unsavedNoteRefusal = "salva la nota prima di rinominarla, spostarla o eliminarla"

    /// Renames a note and every link that pointed at it (wikilink.md W-08).
    @discardableResult
    func renameNote(at relativePath: String, to newTitle: String) async -> Bool {
        guard let session, canOperate(on: relativePath) else { return false }
        do {
            let outcome = try await session.renameNote(at: relativePath, to: newTitle)
            for failure in outcome.failures {
                recordProblem("link non aggiornato in \(failure)")
            }
            // A refusal (ADR-0046 §D1/§D6) is not recoverable by trying again: once the
            // file has moved, `renameNote`'s own `oldTitle` is derived from its *new* name,
            // so a second call would rewrite nothing here either. Reused verbatim rather
            // than a second sentence for the same condition (`VaultWriteRefusal.description`).
            for refusal in outcome.refusals {
                recordProblem(VaultWriteRefusal.movedOn(refusal).description)
            }
            Task {
                await rescan()
                movedNote(from: relativePath, to: outcome.newPath)
            }
            return true
        } catch {
            recordProblem("rinomina: \(error)")
            return false
        }
    }

    @discardableResult
    func moveNote(at relativePath: String, toFolder folder: String) async -> Bool {
        guard let session, canOperate(on: relativePath) else { return false }
        do {
            let outcome = try await session.moveNote(at: relativePath, toFolder: folder)
            // Board-repoint failures and refusals were dropped on the floor here before
            // ADR-0046 (§D7): a move touches no note text, only `.canvas` cards, so both
            // channels are this pair of loops rather than `renameNote`'s "link" wording.
            for failure in outcome.failures {
                recordProblem("riferimento non aggiornato: \(failure)")
            }
            for refusal in outcome.refusals {
                recordProblem(VaultWriteRefusal.movedOn(refusal).description)
            }
            Task {
                await rescan()
                movedNote(from: relativePath, to: outcome.newPath)
            }
            return true
        } catch {
            recordProblem("spostamento: \(error)")
            return false
        }
    }

    /// Moves a note to the Finder's trash and says what now links to nothing.
    ///
    /// The caller confirms first: this method does the deleting, it does not ask.
    @discardableResult
    func trashNote(at relativePath: String) async -> Bool {
        guard let session, canOperate(on: relativePath) else { return false }

        do {
            let dangling = try await session.trashNote(at: relativePath)
            if !dangling.isEmpty {
                // Not rewritten: the links are now broken, and silently deleting them
                // from other people's notes would destroy the only record that
                // something used to be there.
                let title = NoteName.title(
                    fromFileName: (relativePath as NSString).lastPathComponent
                )
                recordProblem("\(dangling.count) note linkavano «\(title)»: ora il link non risolve")
            }
            trashedNote(at: relativePath)
            await rescan()
            return true
        } catch {
            recordProblem("eliminazione: \(error)")
            return false
        }
    }

    /// Every folder in the vault, for the "Sposta in…" menu.
    var folders: [String] { session?.folders ?? [] }

    /// The notes under `Templates/`, for the composer's template menu.
    var templates: [NoteRecord] { session?.templates ?? [] }

    // MARK: Preferite (ADR-0012 D6)
    //
    // Three lines onto `VaultSession+Starred`, where the set and the file live. The rename and
    // the move above already carry the star with the note, because they go through the session
    // too - a facade that owned the set would have to remember to, and would eventually not.

    /// The starred notes, title-sorted, for the section at the top of the sidebar.
    var starredNotes: [NoteRecord] { session?.starredNotes ?? [] }

    func isStarred(_ relativePath: String) -> Bool { session?.isStarred(relativePath) ?? false }

    func toggleStar(_ relativePath: String) { session?.toggleStar(relativePath) }

    // MARK: I tag appuntati
    //
    // Not on `VaultSession`, unlike the stars: a pin is this machine's shortcut into its own
    // browser, so it lives in `UserDefaults` keyed by the vault's path, where the open tabs
    // live (ADR-0012 D10). A connector has no browser and would have nothing to do with it.

    func isPinned(_ tag: Tag) -> Bool { pinnedTags.contains(tag) }

    /// Pins a tag at the end of the list, or unpins it. Order is the order they were pinned:
    /// alphabetical would move a row under the pointer the moment a new pin arrives.
    func togglePin(_ tag: Tag) {
        guard let root else { return }
        if let index = pinnedTags.firstIndex(of: tag) {
            pinnedTags.remove(at: index)
        } else {
            pinnedTags.append(tag)
        }
        pinnedTagsStore.remember(pinnedTags, for: root)
    }

    // MARK: La rinomina di un tag (ADR-0012 D7)
    //
    // Three lines onto `VaultSession+TagRename`, where the writes and the journal are. The
    // sheet asks for the preview, then for the rename, and keeps the ids so it can offer to put
    // it back - which is the whole of the undo, since the session refuses any note that moved on.

    func tagRenamePreview(_ old: Tag, to new: Tag) -> [VaultSession.TagRenameChange] {
        session?.tagRenamePreview(old, to: new) ?? []
    }

    @discardableResult
    func renameTag(_ old: Tag, to new: Tag) async -> VaultSession.TagRenameOutcome {
        guard let session else { return .init() }
        return await session.renameTag(old, to: new)
    }

    @discardableResult
    func undoJournalledWrites(_ ids: [String]) async -> VaultSession.TagRenameOutcome {
        guard let session else { return .init() }
        return await session.undoJournalledWrites(ids)
    }

    /// Writes the shipped views into `Templates/`, skipping any that are already there.
    @discardableResult
    func installSampleViews() async -> VaultSession.SampleViewsOutcome {
        guard let session else { return .init() }
        return await session.installSampleViews()
    }

    /// A card dropped between two columns of a board (ADR-0009 §D5). The rescan the write
    /// triggers is the watcher's, as for every other write the app makes.
    @discardableResult
    func moveOnBoard(_ path: String, from old: Tag?, to new: Tag?) async -> VaultSession.BoardDropOutcome {
        guard let session else { return .init(path: path) }
        return await session.moveOnBoard(path, from: old, to: new)
    }
}
