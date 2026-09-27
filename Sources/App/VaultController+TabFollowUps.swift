import Foundation

/// What the tabs do after the session landed a change to their note: a write, a move or a
/// trash (ADR-0067).
///
/// Moved out of `VaultController+Tabs.swift` when ADR-0064 §D4's door took that file past
/// SwiftLint's 400 lines (ADR-0045's shape: a pure move into an extension of the same type).
extension VaultController {
    /// ADR-0067 §D3: the one handler the session's `landedChangeSubscriber` calls for every
    /// change it lands, installed by `open(_:)` and cleared by `close()` (§D4). No writer calls
    /// a catch-up step of its own any more (§D5): a step a caller can forget is the failure
    /// `CLAUDE.md`'s working agreement names, and a writer that remembered it would now deliver
    /// the same change twice.
    ///
    /// `internal`, not `private`: a test calls it directly with a hand-built change - with no
    /// timer and no gate, since `VaultDisk` has no seam that could suspend a write halfway
    /// (ADR-0046 §D11's reason).
    ///
    /// Every branch reaches every tab showing the path, in every column (ADR-0058 §D2): a write
    /// this app made is self-hashed, so the watcher never reports it, and this call is a tab's
    /// only chance to hear of it. Each tab decides dirty or clean for itself.
    func landed(_ change: VaultSession.LandedChange) {
        switch change {
        case .written(let result, let origin):
            caughtUp(with: result, savedBy: origin)
        case .moved(let from, let to):
            followed(from: from, to: to)
        case .trashed(let path):
            vanished(path)
        }
    }

    /// `.written`: ADR-0058 §D1 for every copy of the path, §D3 for the writer.
    ///
    /// **A buffer with unsaved changes raises the conflict prompt (ADR-0043 §D7).** The dirty
    /// buffer is the person's work, and ADR-0001 §D3.4 says never to merge and never to discard
    /// it - ask.
    ///
    /// **The writer is found by id, not by focus (§D2).** `saveOpenNote()` names its tab
    /// through `origin`, read before the `await`; the focus when the write resumes may be some
    /// other tab. A writer tab that closed or started showing another note meanwhile is
    /// skipped, because the path is part of the filter. The writer takes `savedText` only and
    /// **keeps its `text`**: anything typed during the suspension is newer than the write and
    /// stays unsaved. It is the one tab exempt from `catchUp(to:)` - its `savedText` is still
    /// the old text when this runs, so the rule would read its own save as a conflict.
    private func caughtUp(with result: VaultSession.WriteResult, savedBy origin: UUID?) {
        updateTabs(showing: result.path) { tab in
            if let origin, tab.id == origin {
                tab.note.savedText = result.text
                tab.note.externalChangePending = nil
            } else {
                tab.note.catchUp(to: .text(result.text))
            }
        }
    }

    /// `.moved`: follows a renamed or moved note in every tab that was showing it (§D3).
    ///
    /// A clean tab takes a fresh read of the new path. A dirty tab keeps its `text`, its
    /// `savedText` and any pending prompt, and only its path and title follow: the bytes did
    /// not change with the move, and discarding a dirty buffer is what ADR-0001 §D3.4 forbids.
    /// The app's own move verbs refuse a dirty note first (`canOperate(on:)`), so for them this
    /// widening is unobservable; a move made from Pratiche has no such refusal.
    private func followed(from oldPath: String, to newPath: String) {
        // The recent list is paths, so a rename has to be followed here too - the same
        // follow-up `VaultSession.moveStar` performs for the star.
        if let index = recentNotePaths.firstIndex(of: oldPath) { recentNotePaths[index] = newPath }
        // Asked first so a move of a note no tab shows never reads it, nor records a problem.
        guard columns.contains(where: { $0.tabs.contains { $0.note.relativePath == oldPath } }) else { return }
        let fresh = readForEditing(newPath)
        let title = fresh?.title
            ?? NoteName.title(fromFileName: (newPath as NSString).lastPathComponent)
        updateTabs(showing: oldPath) { tab in
            if let fresh, !tab.note.hasUnsavedChanges {
                tab = tab.showing(fresh)
            } else {
                tab.note.relativePath = newPath
                tab.note.title = title
            }
        }
    }

    /// `.trashed`: ADR-0064's rule, the one `reconcile(_:)` applies to a `.deleted` external
    /// change (§D3). A clean tab answers `.vanished` and closes; a dirty one is asked «Scarta ed
    /// elimina» / «Tieni la mia versione». Ids first, then close: closing shifts the indices
    /// `updateTabs` walks. `closeTabs` runs even with no clean tab, so the closed and recent
    /// lists never keep a row that opens nothing. The watcher's own `.deleted` for the same
    /// path arrives afterwards and finds either no tab or one already asking the same question.
    private func vanished(_ relativePath: String) {
        var clean: [NoteTab.ID] = []
        updateTabs(showing: relativePath) { tab in
            if tab.note.catchUp(to: .deleted) == .vanished {
                clean.append(tab.id)
            }
        }
        closeTabs(clean, ofVanishedNote: relativePath)
    }

    /// Closes the given tabs because their note's file is gone: the one place a tab closes for
    /// that reason (ADR-0064 §D4).
    ///
    /// An in-app trash (`landed(.trashed(_:))`), an external deletion of a clean tab's file
    /// (`reconcile(_:)`) and «Scarta ed elimina» all come here, so the three cannot drift.
    /// The path leaves `closedTabPaths` and `recentNotePaths` even when `ids` is empty: a note
    /// that is gone is not one to offer back with Cmd+Shift+T, nor one to list among the recent
    /// ones - both would be a row that opens nothing.
    func closeTabs(_ ids: [NoteTab.ID], ofVanishedNote relativePath: String) {
        for id in ids {
            closeTab(id)
        }
        closedTabPaths.removeAll { $0 == relativePath }
        recentNotePaths.removeAll { $0 == relativePath }
    }
}
