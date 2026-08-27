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
    /// anything. `exists` answers whether a given vault-relative path is already taken
    /// on disk.
    ///
    /// Placeholder body only - the five ADR-0026 §D6 rules (cycle refusal, descendant
    /// drop, already-there drop, collision refusal, name-clash-within-batch refusal) are
    /// implemented in the code step of Task 1.
    static func plan(
        _ items: [VaultItemRef], into destination: String, exists: (String) -> Bool
    ) -> Result {
        .refused([])
    }

    /// The undo half of a completed move (R-11/R-12): `from`/`to` swapped per move,
    /// order preserved, so applying `inverse(of:)` to a plan's own output restores the
    /// state the plan started from.
    ///
    /// Placeholder body only - returns the input unchanged.
    static func inverse(of moves: [VaultMove]) -> [VaultMove] {
        moves
    }
}
