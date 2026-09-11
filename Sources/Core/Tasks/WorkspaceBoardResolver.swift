import Foundation

/// Resolves a task's stored `workspacePath` (ADR-0021 D1/D5: a bare board **file name**, written
/// by the `^[[<board>.canvas]]` marker, never a vault-relative path) against the boards actually on
/// disk. Pure and no SwiftUI import, so it stays reachable from `perg`/`pergamenum-mcp` under
/// `Sources/Core/**`.
///
/// Callers supply the board list rather than a vault root: `CanvasStore.allBoards()` is an
/// uncached, full recursive filesystem walk (`WorkspacePicker` already fetches it once into
/// `@State` for this reason), and this resolver must not repeat that walk per call.
/// A vault-relative path known to name a board file, distinct from a bare folder path (PG-065).
/// Wraps only the payload `WorkspaceBoardResolution.unique` carries - it does not replace every
/// `String` path in the Workspace layer, which stays out of scope for this narrow introduction.
struct BoardPath: Hashable, Sendable, CustomStringConvertible {
    let value: String
    var description: String { value }
}

enum WorkspaceBoardResolution: Equatable, Sendable {
    /// Exactly one board on disk has this file name — the payload is its full vault-relative path.
    case unique(BoardPath)
    /// Two or more boards share this file name; which one was meant cannot be inferred.
    case ambiguous
    /// No board on disk has this file name — an orphaned marker.
    case notFound
}

enum WorkspaceBoardResolver {
    /// What the row is written by: the file name, extension included.
    static func fileName(of path: String) -> String {
        (path as NSString).lastPathComponent
    }

    /// The comparison `IndexSnapshot.tasks(assignedToWorkspace:)` and `WorkspacePicker.row`
    /// each implemented independently (PG-038): file name only, case-insensitive.
    static func matches(_ path: String, workspacePath: String?) -> Bool {
        guard let workspacePath else { return false }
        return fileName(of: path).lowercased() == workspacePath.lowercased()
    }

    static func resolve(_ workspacePath: String?, in boards: [String]) -> WorkspaceBoardResolution {
        guard let workspacePath else { return .notFound }
        // `matches(_:workspacePath:)`'s rule, with the needle lowercased once instead of
        // once per board, and stopping at the second hit: the payload is still the first
        // match in iteration order.
        let needle = workspacePath.lowercased()
        var hit: String?
        for board in boards where fileName(of: board).lowercased() == needle {
            guard hit == nil else { return .ambiguous }
            hit = board
        }
        guard let hit else { return .notFound }
        return .unique(BoardPath(value: hit))
    }

    /// «Which board does this folder mean» (ADR-0025 §D5) — the tree/breadcrumb/hand-off
    /// counterpart to `resolve(_:in:)`'s «which board does this marker name», sharing the same
    /// `WorkspaceBoardResolution` (one enum, two questions).
    ///
    /// The match is on the board's **containing folder**, never on `hasPrefix`: `A/b/x.canvas`
    /// is `A/b`'s board and not `A`'s, and a prefix test would hand a folder every board
    /// nested anywhere beneath it. The vault root is an ordinary folder here (`""`), with no
    /// case of its own - `deletingLastPathComponent` answers `""` for a bare file name.
    static func board(inFolder folder: String, among boards: [String]) -> WorkspaceBoardResolution {
        let target = normalized(folder)
        let hits = boards.filter { normalized(($0 as NSString).deletingLastPathComponent) == target }
        switch hits.count {
        case 0: return .notFound
        case 1: return .unique(BoardPath(value: hits[0]))
        default: return .ambiguous
        }
    }

    /// One spelling of "the vault root", `""`. Callers write it `""`, `"/"` (the spelling
    /// `WorkspaceBrowserToolbar.canMutate` exempts) or `"."`, and folding them here is what
    /// keeps a root-level board from being invisible to whichever one asked.
    private static func normalized(_ folder: String) -> String {
        let trimmed = folder.hasSuffix("/") ? String(folder.dropLast()) : folder
        return trimmed == "." ? "" : trimmed
    }
}
