import CoreGraphics
import Foundation

/// A `.canvas` file in JSON Canvas 1.0 format (jsoncanvas.org/spec/1.0).
///
/// The acceptance criterion for M2 is that a canvas written here opens in Obsidian
/// and the reverse, so this codec is deliberately conservative: it understands the
/// spec's own properties and carries everything else through untouched. An app that
/// silently dropped another tool's extra keys would satisfy the format and still
/// break the promise of interoperability (SPEC §3, principle 4).
struct CanvasDocument: Equatable, Sendable {
    var nodes: [CanvasNode]
    var edges: [CanvasEdge]
    /// Top-level keys outside `nodes` and `edges`, preserved verbatim.
    var unknown: [String: JSONValue]
    /// Elements of `nodes`/`edges` the codec cannot read - an object without `id` or `type`
    /// (nodes), without `id`, `fromNode` or `toNode` (edges), a node with a required key present
    /// with a wrong JSON type (`"x": "12"`, `"text": 42`, closing §D13.4), or anything that is not
    /// an object - kept with their original index and their readable neighbours, and written back
    /// beside them (ADR-0065 §D5.4, R-08, PG-281).
    var opaqueNodes: [CanvasOpaqueElement]
    var opaqueEdges: [CanvasOpaqueElement]

    static let empty = CanvasDocument(nodes: [], edges: [], unknown: [:])

    enum DecodingError: Error, CustomStringConvertible {
        case notAnObject
        case unreadable(String)
        /// `nodes` or `edges` is present and is not an array (ADR-0065 §D5.5): such a file cannot
        /// be written back consistently, because `encoded()` always writes an array.
        case notAList(String)

        var description: String {
            switch self {
            case .notAnObject: "the canvas file's root is not a JSON object"
            case .unreadable(let reason): "the canvas file could not be read: \(reason)"
            case .notAList(let key): "the canvas file's \(key) is not a list"
            }
        }
    }

    init(
        nodes: [CanvasNode] = [],
        edges: [CanvasEdge] = [],
        unknown: [String: JSONValue] = [:],
        opaqueNodes: [CanvasOpaqueElement] = [],
        opaqueEdges: [CanvasOpaqueElement] = []
    ) {
        self.nodes = nodes
        self.edges = edges
        self.unknown = unknown
        self.opaqueNodes = opaqueNodes
        self.opaqueEdges = opaqueEdges
    }

    init(data: Data) throws {
        // An empty file is a valid empty canvas: Obsidian creates one that way, and
        // failing to open it would strand the board.
        guard !data.isEmpty else {
            self = .empty
            return
        }
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw DecodingError.unreadable(error.localizedDescription)
        }
        guard let object = root as? [String: Any] else { throw DecodingError.notAnObject }

        (nodes, opaqueNodes) = try Self.elements(of: "nodes", in: object, read: CanvasNode.init, id: \.id)
        (edges, opaqueEdges) = try Self.elements(of: "edges", in: object, read: CanvasEdge.init, id: \.id)
        unknown = object
            .filter { $0.key != "nodes" && $0.key != "edges" }
            .compactMapValues(JSONValue.init)
    }

    /// Reads one array element by element, so one element the codec cannot read is kept as an
    /// opaque value instead of emptying the whole board (ADR-0065 §D5.4). An absent key reads as
    /// empty - JSON Canvas makes both optional - and a present non-array refuses the open (§D5.5).
    /// `id` names a readable element, so each opaque one can be anchored to its neighbours.
    private static func elements<Element>(
        of key: String,
        in object: [String: Any],
        read: ([String: Any]) -> Element?,
        id: (Element) -> String
    ) throws -> ([Element], [CanvasOpaqueElement]) {
        guard let raw = object[key] else { return ([], []) }
        guard let list = raw as? [Any] else { throw DecodingError.notAList(key) }
        var readable: [Element] = []
        var opaque: [CanvasOpaqueElement] = []
        for (index, element) in list.enumerated() {
            if let fields = element as? [String: Any], let value = read(fields) {
                readable.append(value)
            } else if let value = JSONValue(element) {
                opaque.append(CanvasOpaqueElement(index: index, value: value))
            }
        }
        return (readable, CanvasOpaqueElement.anchoring(opaque, amid: readable.map(id)))
    }

    func encoded() throws -> Data {
        var object: [String: Any] = unknown.mapValues(\.rawValue)
        object["nodes"] = CanvasOpaqueElement.interleaving(
            opaqueNodes, into: nodes.map(\.rawValue), ids: nodes.map(\.id)
        )
        object["edges"] = CanvasOpaqueElement.interleaving(
            opaqueEdges, into: edges.map(\.rawValue), ids: edges.map(\.id)
        )
        // Sorted keys so a file that did not change in content does not change on
        // disk either, which keeps the vault quiet under version control and under
        // iCloud sync. Slashes stay unescaped: `\/` is legal JSON and every parser
        // reads it back as `/`, but Obsidian does not write it that way, and a vault
        // where every path in every canvas is escaped differently depending on which
        // app touched it last produces a diff on every save.
        return try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    func node(id: String) -> CanvasNode? { nodes.first { $0.id == id } }
}

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

/// A node's colour: one of the six presets, a hex value, or a string this app does not read.
enum CanvasColor: Equatable, Sendable {
    case preset(Int)
    case hex(String)
    /// A colour string that is neither a preset nor a valid hex (`"7"`, `"#GGG"`, `"red"`), kept
    /// verbatim so it round-trips (ADR-0065 §D5.2, R-07). `init?` never produces it: a caller that
    /// wants to keep an unreadable value writes `CanvasColor(raw) ?? .unrecognised(raw)`.
    case unrecognised(String)

    init?(_ raw: String) {
        if raw.hasPrefix("#") {
            guard RGBA(hex: raw) != nil else { return nil }
            self = .hex(raw)
        } else if let preset = Int(raw), (1...6).contains(preset) {
            self = .preset(preset)
        } else {
            return nil
        }
    }

    var rawValue: String {
        switch self {
        case .preset(let value): String(value)
        case .hex(let value): value
        case .unrecognised(let value): value
        }
    }

    /// A node's or an edge's `color` value as the codec keeps it: a string always becomes a
    /// colour, understood or not; any other JSON type is not consumed (ADR-0065 §D5.3).
    static func kept(_ value: Any?) -> CanvasColor? {
        guard let raw = value as? String else { return nil }
        return CanvasColor(raw) ?? .unrecognised(raw)
    }
}

struct CanvasNode: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case text(String)
        /// A file in the vault, with an optional `#heading` or `#^block` subpath.
        case file(path: String, subpath: String?)
        case link(url: String)
        case group(label: String?)
        /// A type this app does not know. Kept so a canvas from a newer tool still
        /// round-trips instead of losing nodes.
        case unknown(type: String)
    }

    var id: String
    var kind: Kind
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    var color: CanvasColor?
    /// Every other property on this node, preserved.
    var unknown: [String: JSONValue]

    var frame: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    /// A container rather than a card. Asked often enough by the board, which treats
    /// the two differently at every step: a group is hollow to the pointer, it is not
    /// a preferred arrow target, and moving it moves what it holds.
    var isGroup: Bool {
        if case .group = kind { return true }
        return false
    }

    /// A coloured "Nota" rather than a plain "Testo" (ADR-0027 §D1) - re-implemented as
    /// `color != nil` in three call sites before PG-078 gave it one name, which already
    /// caused the Task 6 pill-alignment bug once (`BoardFormatBar.swift`'s own comment).
    var isNote: Bool { color != nil }

    var typeName: String {
        switch kind {
        case .text: "text"
        case .file: "file"
        case .link: "link"
        case .group: "group"
        case .unknown(let type): type
        }
    }

    init(
        id: String,
        kind: Kind,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        color: CanvasColor? = nil,
        unknown: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.color = color
        self.unknown = unknown
    }

    init?(_ object: [String: Any]) {
        guard let id = object["id"] as? String, let type = object["type"] as? String,
              let x = CanvasRequiredKey.number("x", in: object, absent: 0),
              let y = CanvasRequiredKey.number("y", in: object, absent: 0),
              let width = CanvasRequiredKey.number("width", in: object, absent: 260),
              let height = CanvasRequiredKey.number("height", in: object, absent: 120),
              let payload = CanvasRequiredKey.payload(ofType: type, in: object)
        else { return nil }

        self.id = id
        self.x = CGFloat(x)
        self.y = CGFloat(y)
        self.width = CGFloat(width)
        self.height = CGFloat(height)
        color = CanvasColor.kept(object["color"])

        // ADR-0065 §D5.1/§D5.3: each kind consumes only its own payload, an unknown kind none, and
        // an optional key only when it is understood. Everything else stays in `unknown`. A
        // required key present with a wrong JSON type answers nil instead, so the node is kept
        // opaque (§D5.4, closing §D13.4): see `CanvasRequiredKey`.
        var consumed: Set<String> = ["id", "type", "x", "y", "width", "height"]
        if color != nil { consumed.insert("color") }
        switch type {
        case "text":
            kind = .text(payload)
            consumed.insert("text")
        case "file":
            let subpath = object["subpath"] as? String
            kind = .file(path: payload, subpath: subpath)
            consumed.insert("file")
            if subpath != nil { consumed.insert("subpath") }
        case "link":
            kind = .link(url: payload)
            consumed.insert("url")
        case "group":
            let label = object["label"] as? String
            kind = .group(label: label)
            if label != nil { consumed.insert("label") }
        default:
            kind = .unknown(type: type)
        }
        unknown = object.filter { !consumed.contains($0.key) }.compactMapValues(JSONValue.init)
    }

    var rawValue: [String: Any] {
        var object: [String: Any] = unknown.mapValues(\.rawValue)
        object["id"] = id
        object["type"] = typeName
        object["x"] = Double(x)
        object["y"] = Double(y)
        object["width"] = Double(width)
        object["height"] = Double(height)
        if let color { object["color"] = color.rawValue }

        switch kind {
        case .text(let text): object["text"] = text
        case .file(let path, let subpath):
            object["file"] = path
            if let subpath { object["subpath"] = subpath }
        case .link(let url): object["url"] = url
        case .group(let label):
            if let label { object["label"] = label }
        case .unknown:
            break
        }
        return object
    }
}

struct CanvasEdge: Identifiable, Equatable, Sendable {
    enum Side: String, Equatable, Sendable {
        case top, right, bottom, left
    }

    enum End: String, Equatable, Sendable {
        case none, arrow
    }

    var id: String
    var fromNode: String
    var fromSide: Side?
    /// Defaults to `none` per the spec.
    var fromEnd: End?
    var toNode: String
    var toSide: Side?
    /// Defaults to `arrow` per the spec.
    var toEnd: End?
    var color: CanvasColor?
    var label: String?
    var unknown: [String: JSONValue]

    init(
        id: String,
        fromNode: String,
        fromSide: Side? = nil,
        fromEnd: End? = nil,
        toNode: String,
        toSide: Side? = nil,
        toEnd: End? = nil,
        color: CanvasColor? = nil,
        label: String? = nil,
        unknown: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.fromNode = fromNode
        self.fromSide = fromSide
        self.fromEnd = fromEnd
        self.toNode = toNode
        self.toSide = toSide
        self.toEnd = toEnd
        self.color = color
        self.label = label
        self.unknown = unknown
    }

    init?(_ object: [String: Any]) {
        guard let id = object["id"] as? String,
              let fromNode = object["fromNode"] as? String,
              let toNode = object["toNode"] as? String
        else { return nil }

        self.id = id
        self.fromNode = fromNode
        self.toNode = toNode
        fromSide = (object["fromSide"] as? String).flatMap(Side.init)
        toSide = (object["toSide"] as? String).flatMap(Side.init)
        fromEnd = (object["fromEnd"] as? String).flatMap(End.init)
        toEnd = (object["toEnd"] as? String).flatMap(End.init)
        color = CanvasColor.kept(object["color"])
        label = object["label"] as? String

        // ADR-0065 §D5.3 (G1.7): an optional key is consumed only when it was understood; a side
        // or an end this app does not know, and a non-string colour or label, stay in `unknown`.
        var consumed: Set<String> = ["id", "fromNode", "toNode"]
        let understood: [(String, Bool)] = [
            ("fromSide", fromSide != nil), ("toSide", toSide != nil),
            ("fromEnd", fromEnd != nil), ("toEnd", toEnd != nil),
            ("color", color != nil), ("label", label != nil),
        ]
        for (key, isUnderstood) in understood where isUnderstood { consumed.insert(key) }
        unknown = object.filter { !consumed.contains($0.key) }.compactMapValues(JSONValue.init)
    }

    var rawValue: [String: Any] {
        var object: [String: Any] = unknown.mapValues(\.rawValue)
        object["id"] = id
        object["fromNode"] = fromNode
        object["toNode"] = toNode
        if let fromSide { object["fromSide"] = fromSide.rawValue }
        if let toSide { object["toSide"] = toSide.rawValue }
        if let fromEnd { object["fromEnd"] = fromEnd.rawValue }
        if let toEnd { object["toEnd"] = toEnd.rawValue }
        if let color { object["color"] = color.rawValue }
        if let label { object["label"] = label }
        return object
    }
}
