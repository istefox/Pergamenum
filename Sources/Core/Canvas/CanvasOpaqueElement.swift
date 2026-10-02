import Foundation

/// An element of `nodes` or `edges` the codec cannot read, with the index it had in the file and
/// the readable elements on either side of it there (ADR-0065 §D5.4, PG-281).
struct CanvasOpaqueElement: Equatable, Sendable {
    var index: Int
    var value: JSONValue
    /// The readable element right before it in the file; nil when none was.
    var after: Anchor?
    /// The readable element right after it in the file; nil when none was.
    var before: Anchor?

    /// A readable element, named by its id and by which occurrence of that id it is, so that a
    /// duplicated id (ADR-0065 §D6.1) still names exactly one element.
    struct Anchor: Hashable, Sendable {
        var id: String
        var occurrence: Int
    }

    /// `opaque` with each element's neighbours filled in from `ids`, the readable elements' ids in
    /// file order. Called once, when the file is read.
    static func anchoring(_ opaque: [Self], amid ids: [String]) -> [Self] {
        let anchors = Self.anchors(of: ids)
        return opaque.sorted { $0.index < $1.index }.enumerated().map { rank, element in
            let gap = Self.gap(of: element, rank: rank, count: anchors.count)
            var anchored = element
            anchored.after = gap > 0 ? anchors[gap - 1] : nil
            anchored.before = gap < anchors.count ? anchors[gap] : nil
            return anchored
        }
    }

    /// Writes each opaque element back beside the readable neighbour it had: right after the
    /// element it followed while that one is still there, else right before the one it preceded,
    /// else at its file index clamped to the array's end. An unedited document encodes its array
    /// exactly as it read it, and an edited one keeps each opaque element next to whichever
    /// neighbour survived: `[A, opaque, B]` with `A` deleted writes `[opaque, B]`, not
    /// `[B, opaque]` (PG-281). Opaque elements that land in one place keep their file order.
    /// `ids` are `readable`'s ids, in the same order.
    static func interleaving(_ opaque: [Self], into readable: [Any], ids: [String]) -> [Any] {
        let position = Dictionary(uniqueKeysWithValues: Self.anchors(of: ids).enumerated().map { ($1, $0) })
        var placed: [Int: [Self]] = [:]
        for (rank, element) in opaque.sorted(by: { $0.index < $1.index }).enumerated() {
            let gap = element.after.flatMap { position[$0] }.map { $0 + 1 }
                ?? element.before.flatMap { position[$0] }
                ?? Self.gap(of: element, rank: rank, count: readable.count)
            placed[min(gap, readable.count), default: []].append(element)
        }
        var result: [Any] = []
        for gap in 0...readable.count {
            result += (placed[gap] ?? []).map(\.value.rawValue)
            if gap < readable.count { result.append(readable[gap]) }
        }
        return result
    }

    /// How many readable elements came before `element` in the file: its index less the opaque
    /// elements ahead of it (`rank`), clamped to the `count` there are.
    private static func gap(of element: Self, rank: Int, count: Int) -> Int {
        min(max(element.index - rank, 0), count)
    }

    private static func anchors(of ids: [String]) -> [Anchor] {
        var seen: [String: Int] = [:]
        return ids.map { id in
            defer { seen[id, default: 0] += 1 }
            return Anchor(id: id, occurrence: seen[id, default: 0])
        }
    }
}
