/// The single value that says both which row of the Workspace tree is lit and whether a
/// board is drawn (ADR-0024 §D4).
///
/// Before this type, those two facts were two variables (`WorkspaceBrowser.selectedFolder`
/// and `WorkspaceController.hasOpenBoard`/`folder`) that had to be kept in agreement by
/// hand and were not - a board's row and its parent folder's row could both read as
/// selected at once, for two different reasons (ADR-0024 F1). Anything that reads either
/// fact reads this one value instead.
enum WorkspaceSelection: Equatable, Sendable {
    /// This folder's board is loaded and drawn on screen.
    case board(folder: String)
    /// Selected for the toolbar's verbs; opens nothing (ADR-0024 §D5, R-05).
    case folder(String)

    /// The folder path either case names.
    var folder: String {
        switch self {
        case .board(let folder): return folder
        case .folder(let folder): return folder
        }
    }

    /// True only for `.board` - whether a board is drawn, not merely whether a row is lit.
    var hasBoard: Bool {
        if case .board = self { true } else { false }
    }
}
