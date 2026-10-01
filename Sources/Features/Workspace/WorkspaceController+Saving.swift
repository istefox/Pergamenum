import Foundation

/// How a board reaches disk: the autosave debounce, the flush every leave path calls, and the
/// guarded write with its reconciliation and its one door into `.conflicted` - ADR-0054 §D4/§D5
/// is what this code implements.
///
/// A file of its own under ADR-0045 (§D2: an extension of the same type; §D3: `private` widens
/// only where the split requires it). `save()`, `attemptSave`, `reconcileAfterRefusal` and
/// `enterConflicted` stay `private`, because every caller they have moved here with them.
extension WorkspaceController {
    // MARK: Saving

    /// Autosave delay of SPEC §6.1.
    private static let autosaveDelay = Duration.seconds(1)

    /// Not `private`: `mutate` and `apply(_:)` in `WorkspaceController.swift`
    /// (`// MARK: Editing`) schedule through it.
    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [autosaveDelay = Self.autosaveDelay] in
            try? await Task.sleep(for: autosaveDelay)
            guard !Task.isCancelled else { return }
            save()
        }
    }

    /// Writes now, cancelling any pending debounce. Called when leaving a board or
    /// closing the vault, where waiting out the delay would lose the edit.
    func flushPendingSave() {
        saveTask?.cancel()
        saveTask = nil
        if hasUnsavedChanges { save() }
    }

    /// `.canvas` paths never reach `VaultWatcher` (ADR-0054 §D7), so nothing tells this
    /// board when another writer has touched the file underneath it. `expecting:` is the
    /// substitute: the write proves against `origin`'s hash instead, and a mismatch is
    /// reconciled here rather than silently overwritten or silently discarded.
    private func save() {
        guard let store, hasUnsavedChanges else { return }
        // A conflicted board neither writes nor retries until the person chooses
        // `keepLocalBoard()` or `reloadBoardFromDisk()` (ADR-0054 §D5) - a retry per edit
        // would refuse once a second and fill the problem list.
        if case .conflicted = saveState { return }
        attemptSave(store: store, allowingRetry: true)
    }

    /// An origin of `.none`, or one naming a different board than `board`, writes with
    /// `expecting: nil` - there is nothing to prove and forcing a refusal would make the
    /// board unsavable.
    private func attemptSave(store: CanvasStore, allowingRetry: Bool) {
        let expecting: String? = {
            guard case .loaded(let originBoard, let hash, _) = origin, originBoard == board else { return nil }
            return hash
        }()

        do {
            let writtenHash = try store.save(document, board: board, expecting: expecting)
            replaceDocument(document, origin: .loaded(board: board, hash: writtenHash, document: document))
            saveState = .saved
        } catch is VaultWriteRefusal {
            guard allowingRetry else {
                // A second writer landed inside the retry window; treated as diverged
                // rather than reconciled and looped again (ADR-0054 §D4).
                enterConflicted(reason: VaultWriteRefusal.movedOn(board).description)
                return
            }
            reconcileAfterRefusal(store: store)
        } catch {
            // Left dirty on purpose: an indicator still showing unsaved changes is
            // the truth, and the next edit will retry.
            recordProblem("salvataggio di \(board): \(error)")
        }
    }

    /// ADR-0054 §D4: re-reads the board and asks the pure three-way rule what the
    /// external writer did, using the base `origin` kept from the read this board's
    /// unsaved edit started from.
    private func reconcileAfterRefusal(store: CanvasStore) {
        guard case .loaded(_, _, let base) = origin else {
            // `expecting` is only ever non-nil when `origin` matches this board, so a
            // refusal with nothing to reconcile against should not happen; nothing safe
            // to do but report it.
            enterConflicted(reason: VaultWriteRefusal.movedOn(board).description)
            return
        }

        let theirs: (document: CanvasDocument, hash: String)
        do {
            theirs = try store.read(board: board)
        } catch {
            recordProblem("salvataggio di \(board): \(error)")
            return
        }

        switch CanvasDocument.reconcile(mine: document, base: base, theirs: theirs.document) {
        case .adopted(let merged):
            replaceDocument(
                merged, origin: .loaded(board: board, hash: theirs.hash, document: theirs.document)
            )
            attemptSave(store: store, allowingRetry: false)
        case .diverged(let reasons):
            enterConflicted(
                reason: "\(VaultWriteRefusal.movedOn(board).description) (\(reasons.joined(separator: ", ")))"
            )
        }
    }

    /// The one door into `.conflicted` (ADR-0054 §D5): `recordProblem` fires here and only
    /// here, so re-entering `save()` while already conflicted - which `markPendingUnlessConflicted()`
    /// makes impossible until an explicit resolution - can never repeat it.
    private func enterConflicted(reason: String) {
        saveState = .conflicted(reason: reason)
        recordProblem(reason)
    }
}
