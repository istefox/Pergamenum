import Foundation

/// The three-way comparison a refused board autosave asks (ADR-0054 §D4): what did the
/// external writer change between the bytes the board loaded and the bytes now on disk,
/// and can the board's own unsaved edit absorb that change without losing either side.
///
/// Pure and in `Core`, like `WorkspaceReferences`: it is exercised against three
/// `CanvasDocument` values built in memory, with no window, no vault, no disk.
extension CanvasDocument {
    /// What reconciling `mine` against `theirs`, using `base` as the common ancestor,
    /// produced.
    enum Reconciliation: Equatable {
        /// Every difference between `base` and `theirs` was a `.file` node's path or
        /// subpath, and is folded into `mine`'s own copy of that node (or, for a node
        /// `mine` has since deleted, simply not resurrected). The associated document
        /// carries both the caller's unsaved edit and the external repoint.
        case adopted(CanvasDocument)
        /// At least one difference was not a `.file` repoint - a node added, removed or
        /// changed in some other way, an edge changed, or a top-level `unknown` key
        /// changed - and nothing was decided automatically. The associated array names
        /// every node id, edge id and key that could not be spoken for.
        case diverged([String])
    }

    /// The rule, stated in one sentence (ADR-0054 §D4): a `.file` node's path is a fact
    /// about the filesystem, not a property of the board, so where disk and memory
    /// disagree about one, disk wins - and where they disagree about anything else,
    /// nothing is decided automatically.
    ///
    /// `base == theirs` answers `.adopted(mine)` without comparing anything else: the
    /// refusal that triggered this call came from bytes that re-encode differently, not
    /// from a content change (ADR-0054's own risk note on `encoded()`'s determinism).
    static func reconcile(mine: Self, base: Self, theirs: Self) -> Reconciliation {
        guard base != theirs else { return .adopted(mine) }

        var merged = mine
        var reasons: [String] = []

        let baseNodes = Dictionary(uniqueKeysWithValues: base.nodes.map { ($0.id, $0) })
        let theirsNodes = Dictionary(uniqueKeysWithValues: theirs.nodes.map { ($0.id, $0) })
        for id in Set(baseNodes.keys).union(theirsNodes.keys).sorted() {
            switch (baseNodes[id], theirsNodes[id]) {
            case (let before?, let after?):
                guard before != after else { continue }
                guard let repoint = Self.filePathRepoint(from: before, to: after) else {
                    reasons.append(id)
                    continue
                }
                // `mine` may have deleted this node itself: the repoint then has nothing
                // left to apply, and that is not a conflict - the deletion is kept and
                // the vanished id is not resurrected (ADR-0054 §D4).
                if let index = merged.nodes.firstIndex(where: { $0.id == id }) {
                    merged.nodes[index].kind = .file(path: repoint.path, subpath: repoint.subpath)
                }
            case (nil, _?), (_?, nil):
                // Added or removed by `theirs` - never a repoint, so never spoken for.
                reasons.append(id)
            case (nil, nil):
                continue
            }
        }

        let baseEdges = Dictionary(uniqueKeysWithValues: base.edges.map { ($0.id, $0) })
        let theirsEdges = Dictionary(uniqueKeysWithValues: theirs.edges.map { ($0.id, $0) })
        for id in Set(baseEdges.keys).union(theirsEdges.keys).sorted()
        where baseEdges[id] != theirsEdges[id] {
            reasons.append(id)
        }

        for key in Set(base.unknown.keys).union(theirs.unknown.keys).sorted()
        where base.unknown[key] != theirs.unknown[key] {
            reasons.append(key)
        }

        return reasons.isEmpty ? .adopted(merged) : .diverged(reasons)
    }

    /// Whether `before` and `after` - the same node id in `base` and in `theirs` - differ
    /// in nothing but a `.file` node's `path`/`subpath`. `nil` for any other difference:
    /// a kind change, a geometry change, a colour change or an `unknown` change all fall
    /// through to the caller's `.diverged` branch.
    private static func filePathRepoint(
        from before: CanvasNode, to after: CanvasNode
    ) -> (path: String, subpath: String?)? {
        guard case .file(let path, let subpath) = after.kind, case .file = before.kind else { return nil }
        guard before.x == after.x, before.y == after.y,
              before.width == after.width, before.height == after.height,
              before.color == after.color, before.unknown == after.unknown
        else { return nil }
        return (path, subpath)
    }
}
