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
        dragAnchorID = nil
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

    /// Drops a reframing owed to the board being left (#569 point 7). A deferred refit that
    /// outlived its board ran after `detach()` emptied the document and framed the viewport
    /// on nothing.
    func cancelPendingRefit() {
        refitTask?.cancel()
        refitTask = nil
        pendingRefit = nil
    }
}
