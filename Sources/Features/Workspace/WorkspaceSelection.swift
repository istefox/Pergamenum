/// The single value that says both which row of the Workspace tree is lit and whether a
/// board is drawn (ADR-0024 §D4).
///
/// Before this type, those two facts were two variables (`WorkspaceBrowser.selectedFolder`
/// and `WorkspaceController.hasOpenBoard`/`folder`) that had to be kept in agreement by
/// hand and were not - a board's row and its parent folder's row could both read as
/// selected at once, for two different reasons (ADR-0024 F1). Anything that reads either
/// fact reads this one value instead.
///
/// ADR-0025 §D3 (Task 2, RED): a board is addressed by its own file path, not by the
/// folder it used to be folded into, so `.board` is being re-cased from `folder: String`
/// to `path: String` - the `.folder("")` this doc comment will carry once that lands is
/// never produced, because there is no root row to click (§D2) and the breadcrumb's root
/// segment calls `select(nil)` instead (§D4).
///
/// `.board(path:)` below is a **placeholder bridge**, not the real case: two `case board`
/// declarations differing only in their argument label compile (Swift resolves the
/// constructor call by label, like an overloaded function), but every *pattern match*
/// against `.board` becomes ambiguous the moment a second one exists - confirmed with
/// `swiftc -typecheck` before writing this, because `WorkspaceController.swift:281,295`
/// and `Tests/WorkspaceOpenStateTests.swift`/`Tests/WorkspaceBrowserToolbarTests.swift`
/// still pattern-match and construct the **old** `.board(folder:)` case and are not this
/// task's to rewrite (Tasks 3 and 5 own them). The bridge reuses `.board(folder:)`'s
/// storage so those three files keep compiling and keep passing, unchanged, while this
/// file's own tests exercise the new call shape. The coder's GREEN phase replaces this
/// bridge with a real `case board(path: String)`, deleting `.board(folder:)` and fixing
/// the three call sites above in the same change - it cannot be done piecemeal because of
/// the ambiguity just described.
enum WorkspaceSelection: Equatable, Sendable {
    /// This folder's board is loaded and drawn on screen.
    case board(folder: String)
    /// Selected for the toolbar's verbs; opens nothing (ADR-0024 §D5, R-05).
    case folder(String)

    /// ADR-0025 §D3's real case, once GREEN lands. For now: a placeholder constructor
    /// (see the type's doc comment) that stores `path` in the existing `.board(folder:)`
    /// slot verbatim - `.folder`'s own real logic (`deletingLastPathComponent`) is not
    /// implemented here, so `folder` below reads the whole path back unchanged for a
    /// value built this way, which is deliberately wrong until the coder writes it.
    static func board(path: String) -> WorkspaceSelection {
        .board(folder: path)
    }

    /// The id either case names - ADR-0025 §D3's `path`. Trivial regardless of which
    /// case: an unwrap, not a decision, so it reads correctly today for both the legacy
    /// `.board(folder:)` value and one built through the placeholder constructor above.
    var path: String {
        switch self {
        case .board(let value): return value
        case .folder(let value): return value
        }
    }

    /// The folder path either case names. Under ADR-0025 this becomes "the containing
    /// folder" (`deletingLastPathComponent` for `.board`, `self` for `.folder`) - real
    /// logic left for the coder's GREEN phase, so a `.board` value built through the
    /// placeholder constructor above still reads its whole path back here rather than
    /// the folder that contains it.
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
