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

    /// TODO(ADR-0025 Task 3/5): ADR-0024's `.board(folder:)` **constructor**, kept as a
    /// bridge over the real `.board(path:)` case above so the call sites Tasks 3 and 5
    /// own keep compiling and keep passing while this task re-cases the type. Swift
    /// resolves `WorkspaceSelection.board(…)` by argument label like an overloaded
    /// function, so `.board(folder:)` call sites need no edit; a *pattern* match on
    /// `.board` binds the path, which is why `WorkspaceController.select(_:)` reads
    /// `hasBoard`/`folder` rather than destructuring the case.
    ///
    /// It restates ADR-0024's folder→board rule (the `.canvas` inside a folder named
    /// after it) rather than inventing one, so every reader of `folder` below - the
    /// breadcrumb (`WorkspaceController.swift:226`), the tree's tag
    /// (`WorkspaceView.swift:126`), the toolbar's target (`WorkspaceBrowser.target(for:)`)
    /// - reads exactly the folder ADR-0024 stored. The vault root's board was named after
    /// the *vault* and this type cannot know that name, so the root's stand-in is a
    /// sentinel file name whose containing folder is `""`, which is the only property of
    /// it anything reads. Deleted with the last `.board(folder:)` call site in Task 5.
    static func board(folder: String) -> WorkspaceSelection {
        let trimmed = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return .board(path: Self.bridgeRootBoardName) }
        let name = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
        return .board(path: "\(trimmed)/\(name).\(CanvasStore.fileExtension)")
    }

    /// The stand-in file name for the vault root's board under the bridge above. Angle
    /// brackets so it cannot collide with a real board a person could create.
    private static let bridgeRootBoardName = "<root>.\(CanvasStore.fileExtension)"

    /// The id this selection names: the board's own path, or the folder's (ADR-0025 §D3).
    /// The `List`'s tag under Task 5, and an unwrap rather than a decision here.
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
