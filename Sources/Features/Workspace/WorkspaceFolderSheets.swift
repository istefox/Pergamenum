import Foundation

/// The create/rename sheets' decision logic, kept out of the view bodies so it is
/// testable without a view (ADR-0022 §D11).
///
/// RED placeholder (Task 6, ADR-0022, plan
/// `2026-08-25-workspace-ui-creazione-board-toolbar-e-r`): only the two pure
/// functions below exist, pinned by `Tests/WorkspaceBrowserToolbarTests.swift`.
/// `NewWorkspaceSheet` and `RenameWorkspaceSheet` - the actual SwiftUI views, their
/// `Picker`, their violation rendering through `ConformanceText.lines` and their
/// `accessibilityIdentifier`s (`workspace-new-sheet`, `workspace-new-name`,
/// `workspace-new-parent`, `workspace-rename-sheet`, `workspace-rename-name`) - are
/// Task 6 GREEN work for the coder.
enum WorkspaceNameField {
    /// What the sheet's "Crea"/"Rinomina" button reads to decide whether it is
    /// enabled, and what the inline violation text renders.
    enum State: Equatable {
        case invalid([NoteName.Violation])
        case taken
        case ok
    }

    /// `name` validated against `NoteName.validate`, then checked against the
    /// collision predicate `available` - `FolderFileOperations.nameIsAvailable`
    /// reached through `vault`, in the GREEN implementation (ADR-0022 §D11).
    ///
    /// Placeholder: deliberately wrong (always `.ok`), so the `.invalid` and
    /// `.taken` cases fail on their assertions rather than on a build error.
    static func state(name: String, parent: String, available: (String, String) -> Bool) -> State {
        .ok
    }
}

/// The create sheet's parent-folder picker options, and (Task 6 GREEN) the two
/// sheets themselves.
enum WorkspaceFolderSheets {
    /// The parent-folder picker's options, derived from the browser's own board list
    /// (`CanvasStore.allBoards()`) rather than from `vault.folders` - which is
    /// note-derived and would omit a folder holding only boards (ADR-0022 §D11).
    /// Root first (`""`), deduplicated, every ancestor folder included.
    ///
    /// Placeholder: deliberately wrong (always empty), so
    /// `parentOptionsMapsBoardsToRootFirstDeduplicatedAncestorsIncluded` fails on its
    /// assertion rather than on a build error.
    static func parentOptions(from boards: [String]) -> [String] {
        []
    }
}
