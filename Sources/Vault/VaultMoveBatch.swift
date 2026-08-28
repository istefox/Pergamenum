import Foundation

/// What a dragged row is: which kind of vault entry `VaultItemRef.path` names
/// (ADR-0026 §D6). Distinguishes a folder from a file mainly so `VaultMoveBatch.plan`
/// can tell whether "into a descendant of itself" applies at all.
enum VaultItemKind: Equatable, Sendable {
    case note
    case board
    case folder
}

/// A reference to one row a drag could have started from: its vault-relative path
/// before the move, and its kind. `Hashable` so a multi-selection set (the additive
/// `Set` selection model, ADR-0026 §D9) can hold it directly.
struct VaultItemRef: Equatable, Sendable, Hashable {
    let path: String
    let kind: VaultItemKind
}

/// One item's move, decided before anything touches disk: `item` unchanged (its `path`
/// stays the pre-move path), `from` its containing folder at the time of the drop, `to`
/// the destination folder the batch is landing in.
struct VaultMove: Equatable, Sendable {
    let item: VaultItemRef
    let from: String
    let to: String
}

/// The pure decision a drop makes, computed before `VaultSession+Move` (Task 3) performs
/// it (ADR-0026 §D1, §D6). `exists` is injected rather than read straight off
/// `FileManager`: it is the one impure input this type has, and injecting it is what
/// lets every rule below run against plain values, no temp directory required.
enum VaultMoveBatch {
    /// A plan either commits as a list of moves, or refuses the whole batch and names
    /// why - collision and cycle are both all-or-nothing (ADR-0026 §D6), never a partial
    /// commit.
    enum Result: Equatable {
        case moves([VaultMove])
        case refused([String])
    }

    /// Decides what dropping `items` into `destination` would do, without writing
    /// anything. `destination` is a vault-relative folder path, the vault root spelled
    /// `""` (R-05); `exists` answers whether a given vault-relative path is already taken
    /// on disk.
    ///
    /// The five ADR-0026 §D6 rules run in the order the ADR lists them - the batch is
    /// **pruned before it is validated**, so a redundant or already-satisfied item is
    /// never the thing that refuses the batch:
    ///
    /// 1. prune redundancies: an item whose ancestor folder is in the same batch moves
    ///    with that ancestor, so planning it separately would be a contradiction rather
    ///    than a second move - it is dropped silently, not reported;
    /// 2. drop no-ops: an item already directly inside `destination` leaves the batch and
    ///    is not an error, and therefore never reaches `inverse(of:)` to be "restored";
    /// 3. refuse cycles (§D5): a folder into itself or into one of its own descendants;
    /// 4. refuse collisions: a name the destination already holds, and two items in this
    ///    same batch that would land on one name;
    /// 5. answer once - `.moves` or `.refused`, never a partial commit, because a partial
    ///    commit has a partial inverse.
    static func plan(
        _ items: [VaultItemRef], into destination: String, exists: (String) -> Bool
    ) -> Result {
        // 1. Prune redundancies. The prefix is `"\(path)/"` and never the bare path, the
        // rule `FolderFileOperations.repointing` already follows: `a-altro` is a sibling
        // of `a`, not a descendant of it.
        let ancestors = items.filter { $0.kind == .folder }.map(\.path)
        let withoutRedundancies = items.filter { item in
            !ancestors.contains { item.path != $0 && item.path.hasPrefix("\($0)/") }
        }

        // 2. Drop no-ops: already directly inside the destination, nothing to move.
        let candidates = withoutRedundancies.filter { containingFolder(of: $0.path) != destination }

        // 3. Refuse cycles. Only a folder can contain the destination; a file never can.
        var reasons: [String] = []
        for item in candidates where item.kind == .folder {
            if destination == item.path || destination.hasPrefix("\(item.path)/") {
                reasons.append("«\(item.path)» non può essere spostata dentro sé stessa")
            }
        }

        // 4. Refuse collisions, on disk and within the batch itself. The conflicting name
        // goes in the reason string: R-07 requires it to be shown, and this is where the
        // dialog reads it from.
        var claimed: Set<String> = []
        for item in candidates {
            let landing = landingPath(of: item.path, in: destination)
            if exists(landing) {
                reasons.append("esiste già: \(landing)")
            }
            if !claimed.insert(landing).inserted {
                reasons.append("due elementi finirebbero entrambi in: \(landing)")
            }
        }

        // 5. Answer once. Nothing moves unless every item passed.
        guard reasons.isEmpty else { return .refused(reasons) }
        return .moves(
            candidates.map {
                VaultMove(item: $0, from: containingFolder(of: $0.path), to: destination)
            }
        )
    }

    /// The undo half of a completed move (R-11/R-12): `from`/`to` swapped per move,
    /// order preserved, so applying `inverse(of:)` to a plan's own output restores the
    /// state the plan started from.
    ///
    /// `item` is carried over untouched: it names the row as it was before the move, and
    /// the caller re-derives the current path from `to` when it performs the inverse.
    static func inverse(of moves: [VaultMove]) -> [VaultMove] {
        moves.map { VaultMove(item: $0.item, from: $0.to, to: $0.from) }
    }

    /// The folder holding `path`, `""` for an entry sitting at the vault root - the same
    /// `deletingLastPathComponent` spelling the file operations use.
    private static func containingFolder(of path: String) -> String {
        (path as NSString).deletingLastPathComponent
    }

    /// Where `path` would land inside `destination`, keeping its own last component: a
    /// move never renames (§D5, "reject means reject").
    private static func landingPath(of path: String, in destination: String) -> String {
        let name = (path as NSString).lastPathComponent
        return destination.isEmpty ? name : "\(destination)/\(name)"
    }
}
