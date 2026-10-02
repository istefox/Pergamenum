import CoreGraphics
import Foundation

/// Leaving a board (ADR-0066): every per-board transient state has one reset door, and every
/// leave path settles then flushes.
///
/// Before this, `attach`/`detach`/`load(board:)`/`select(_:)` each reset the part of the
/// board's transient state their author had in mind, and nothing else (PG-255, #569 points
/// 1–3, 7): the editing ids, the in-progress ink and the deferred refit outlived the board
/// they belonged to. A drawing started on board A was written into board B's folder; a live
/// `editingTextNodeID` kept every single-letter tool key suspended with no card in edit.
/// The rule `foldedHeadings` already stated - "a table keyed by node id would otherwise
/// outlive the board" - now has one door that applies it to all of them.
///
/// A split out of `WorkspaceController.swift` for its `type_body_length`, the ADR-0045
/// convention: the doors live here, the calls to them stay in the four navigation doors.
extension WorkspaceController {
    /// True while a card's own text field has focus: a `.text` card's body or a `.link`
    /// card's title (PG-073). What `BoardChrome` suspends the bare-key tool shortcuts on
    /// (#569 point 4) - a bare key with no modifier reaches `performKeyEquivalent:` ahead of
    /// the first responder, so renaming a link card to "video" switched tools on its `v`.
    ///
    /// Named for what it guards, not "anything is being edited": crop and drawing modes have
    /// no text field, and their tool shortcuts keep working.
    var isEditingText: Bool {
        editingTextNodeID != nil || editingTitleNodeID != nil
    }

    /// Clears every per-board transient state without writing anything (ADR-0066).
    ///
    /// Called on its own only where there is nothing left to write to - `attach`, whose
    /// previous store is already gone. Every other door reaches it through
    /// `settleBoardEditing()`, which commits first.
    func resetTransientEditing() {
        editingTextNodeID = nil
        editingTextDraft = ""
        editingTitleNodeID = nil
        editingTitleDraft = ""
        editingDrawingNodeID = nil
        activeDrawing = .empty
        // `cropOriginal`/`cropHandle` and `resizeOriginalFrame`/`resizeHandle` are left alone
        // on purpose: each `begin…` overwrites them before use, and the ids below gate them.
        croppingNodeID = nil
        cropDraft = nil
        cropDrawnSize = .zero
        // Gesture transients, which name node ids of the board being left the same way.
        draggingIDs = []
        dragTranslation = .zero
        dragSnap = nil
        activeGuides = []
        resizingNodeID = nil
        resizedFrame = nil
        arrowSourceID = nil
        arrowTranslation = .zero
        marqueeStart = nil
        marqueeRect = nil
        panOrigin = nil
        // A fold is transient and keyed by node id (ADR-0028 §D8): a table carried into
        // another board or vault would name ids that mean nothing there, or - worse - ids
        // that mean something else, since a canvas id is unique within its file and not
        // across a vault. This line is what makes "a fold resets when the board is
        // reopened" true.
        foldedHeadings = [:]
    }

    /// The obligation of leaving a board (ADR-0066): every open session is committed to the
    /// board still in `board`, then everything transient is reset.
    ///
    /// Must run while `current`, `store` and `board` still name the board being left -
    /// `mutate` guards on `current?.hasBoard`, and `commitDrawing` spells its path from
    /// `folder` - which is why every caller puts it before the line that moves them.
    ///
    /// Navigating away confirms, the way a click outside the card would (ADR-0020 D5), and
    /// that rule now covers ink too: strokes nobody pressed «Fatto» on are written into the
    /// board they were drawn on rather than carried to the next one (#569 point 2). A board
    /// not on screen has no ink to commit - `commitDrawing` writes the SVG before its
    /// `mutate` would refuse, so it is not asked. `resetTransientEditing()` runs last, so
    /// anything a guard above skipped still clears.
    func settleBoardEditing() {
        endCrop(confirm: true)
        endTextEdit(commit: true)
        endTitleEdit(commit: true)
        if isShowingBoard, !activeDrawing.strokes.isEmpty {
            commitDrawing()
        }
        resetTransientEditing()
    }

    /// The board's half of «Esci» (#506): settles, then writes what the ~1 s autosave
    /// debounce still owes, before the app is allowed to terminate.
    ///
    /// Synchronous, unlike `DiaryController.settle()` (ADR-0057 §D8): `save()` is, so
    /// `AppDelegate.applicationShouldTerminate(_:)` calls this before it decides anything
    /// and needs no `.terminateLater` for it. A conflicted board is not flushed - the write
    /// was already refused and was reported when it entered `.conflicted` (ADR-0054 §D5);
    /// quitting does not overwrite the other writer's bytes.
    func settleForTermination() {
        settleBoardEditing()
        if case .conflicted = saveState { return }
        flushPendingSave()
    }

    /// The board's half of a sidebar rename/move/trash (`WorkspaceView+FolderVerbs.swift`):
    /// answers whether the verb may touch disk, and when it may, has already settled and
    /// flushed the open board. One door, so no verb can run the three steps out of order or
    /// skip one (PG-288).
    ///
    /// The order is the decision. The conflict guard first, so a refused verb settles
    /// nothing: a conflicted board's open sessions stay sessions rather than being merged
    /// into a document the verb is about to refuse to leave. Then settle and flush - the
    /// ~1 s autosave would otherwise land on the path the verb moves away from and recreate
    /// it (ADR-0022 §F10), and a draft committed after the move would be flushed there too
    /// (ADR-0066). Then the guard again, because that flush's own write can be refused and
    /// enter `.conflicted`, and the file must not move out from under a fresh conflict.
    func settleForVerb() -> Bool {
        guard canLeaveOpenBoardForVerb() else { return false }
        settleBoardEditing()
        flushPendingSave()
        return canLeaveOpenBoardForVerb()
    }

    /// Drops a reframing owed to the board being left (#569 point 7). A deferred refit that
    /// outlived its board ran after `detach()` emptied the document and framed the viewport
    /// on nothing.
    func cancelPendingRefit() {
        refitTask?.cancel()
        refitTask = nil
        pendingRefit = nil
    }

    /// Cancels the deferred refit but keeps what was asked for (PG-289): a concentrazione
    /// «dimensione reale» requested within the ~350 ms debounce before a board change was
    /// lost by `cancelPendingRefit()`, and the fit-on-open of the new board ran in its place.
    /// The request is about the viewport, not the board, so `load(board:)` keeps it and
    /// `applyPendingRefit(in:)` applies it to the board that is on screen once the layout
    /// settles.
    func deferPendingRefit() {
        refitTask?.cancel()
        refitTask = nil
    }

    // MARK: - After an `await` (#569 point 9)

    /// A board read before an `await`, asked again after it (ADR-0043 §D7): the person can
    /// open another board, or a folder, while the suspension runs.
    func isStillShowing(_ board: String) -> Bool {
        isShowingBoard && self.board == board
    }

    /// Places the card for a note created while `board` was open. When another board, or no
    /// board, is on screen now, nothing is placed: the note exists on disk, a card on the
    /// board that happens to be open would be the wrong one, so it is reported instead.
    /// Answers the new node's id, nil when nothing was placed.
    @discardableResult
    func placeCreatedNote(
        _ path: String, title: String, at point: CGPoint, openedOn board: String
    ) -> String? {
        guard isStillShowing(board) else {
            recordProblem("nota «\(title)» creata in \(path), ma la board è cambiata: non è stata aggiunta")
            return nil
        }
        return placeFile(path, at: point, creatingOnDisk: path)
    }

    /// Follows a move that ran while `openBefore` was open: reopens that board at the path
    /// it landed on. Nothing happens when the person opened something else meanwhile (they
    /// are left where they went) or when the move did not carry the open board. Reopened
    /// rather than left alone: the document on screen was read from a file that has moved,
    /// and `open(board:)` re-reads it, refreshes the folder and redraws the breadcrumb, so
    /// the board never flickers closed (R-13). Answers the path opened, nil otherwise.
    @discardableResult
    func followMove(from openBefore: String, moves: [VaultMove]) -> String? {
        guard isStillShowing(openBefore) else { return nil }
        let landed = WorkspaceFolderNavigation.boardAfterMove(open: openBefore, moves: moves)
        guard landed != openBefore else { return nil }
        open(board: landed)
        return landed
    }
}
