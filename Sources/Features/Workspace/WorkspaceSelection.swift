import Foundation

/// The single value that says both which row of the Workspace tree is lit and whether a
/// board is drawn (ADR-0024 §D4), with the board named by its own file path (ADR-0025 §D3).
///
/// Before this type, those two facts were two variables (`WorkspaceBrowser.selectedFolder`
/// and `WorkspaceController.hasOpenBoard`/`folder`) that had to be kept in agreement by
/// hand and were not - a board's row and its parent folder's row could both read as
/// selected at once, for two different reasons (ADR-0024 F1). Anything that reads either
/// fact reads this one value instead.
///
/// ADR-0025 §D3: a board is addressed by its **own** file path, never derived from the
/// folder holding it, so a folder may hold any number of boards under any name and each
/// one is a selection of its own (R-03, R-04, R-06). `.folder("")` is representable and
/// never produced: there is no root row to click (§D2) and the breadcrumb's root segment
/// calls `select(nil)` instead (§D4).
enum WorkspaceSelection: Equatable, Sendable {
    /// The board on screen, by the `.canvas` file's own vault-relative path -
    /// `01 Progetti/qualsiasi-nome.canvas`. The containing folder is read off it
    /// (`folder` below), never the other way round (ADR-0025 §D3).
    case board(path: String)
    /// Selected for the toolbar's verbs; opens nothing (ADR-0024 §D5, R-05).
    case folder(String)

    /// The id this selection names: the board's own path, or the folder's (ADR-0025 §D3).
    /// The `List`'s tag, and an unwrap rather than a decision here.
    var path: String {
        switch self {
        case .board(let path): return path
        case .folder(let folder): return folder
        }
    }

    /// The folder this selection sits in: the board file's containing folder, or the
    /// folder itself. `""` for a board at the vault root, which is the same `""` the
    /// folder case spells the root with (ADR-0025 §D3).
    var folder: String {
        switch self {
        case .board(let path): return (path as NSString).deletingLastPathComponent
        case .folder(let folder): return folder
        }
    }

    /// True only for `.board` - whether a board is drawn, not merely whether a row is lit.
    var hasBoard: Bool {
        if case .board = self { true } else { false }
    }
}
