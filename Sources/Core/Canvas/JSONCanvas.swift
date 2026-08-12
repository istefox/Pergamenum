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

    static let empty = CanvasDocument(nodes: [], edges: [], unknown: [:])

    enum DecodingError: Error, CustomStringConvertible {
        case notAnObject
        case unreadable(String)

        var description: String {
            switch self {
            case .notAnObject: "the canvas file's root is not a JSON object"
            case .unreadable(let reason): "the canvas file could not be read: \(reason)"
            }
        }
    }

    init(nodes: [CanvasNode] = [], edges: [CanvasEdge] = [], unknown: [String: JSONValue] = [:]) {
        self.nodes = nodes
        self.edges = edges
        self.unknown = unknown
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

        nodes = (object["nodes"] as? [[String: Any]] ?? []).compactMap(CanvasNode.init)
        edges = (object["edges"] as? [[String: Any]] ?? []).compactMap(CanvasEdge.init)
        unknown = object
            .filter { $0.key != "nodes" && $0.key != "edges" }
            .compactMapValues(JSONValue.init)
    }

    func encoded() throws -> Data {
        var object: [String: Any] = unknown.mapValues(\.rawValue)
        object["nodes"] = nodes.map(\.rawValue)
        object["edges"] = edges.map(\.rawValue)
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

/// A node's colour: one of the six presets, or a hex value.
enum CanvasColor: Equatable, Sendable {
    case preset(Int)
    case hex(String)

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
        }
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
        guard let id = object["id"] as? String, let type = object["type"] as? String else { return nil }

        self.id = id
        x = CGFloat((object["x"] as? NSNumber)?.doubleValue ?? 0)
        y = CGFloat((object["y"] as? NSNumber)?.doubleValue ?? 0)
        width = CGFloat((object["width"] as? NSNumber)?.doubleValue ?? 260)
        height = CGFloat((object["height"] as? NSNumber)?.doubleValue ?? 120)
        color = (object["color"] as? String).flatMap(CanvasColor.init)

        switch type {
        case "text":
            kind = .text(object["text"] as? String ?? "")
        case "file":
            kind = .file(path: object["file"] as? String ?? "", subpath: object["subpath"] as? String)
        case "link":
            kind = .link(url: object["url"] as? String ?? "")
        case "group":
            kind = .group(label: object["label"] as? String)
        default:
            kind = .unknown(type: type)
        }

        let consumed: Set<String> = ["id", "type", "x", "y", "width", "height", "color",
                                     "text", "file", "subpath", "url", "label"]
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
        color = (object["color"] as? String).flatMap(CanvasColor.init)
        label = object["label"] as? String

        let consumed: Set<String> = ["id", "fromNode", "fromSide", "fromEnd",
                                     "toNode", "toSide", "toEnd", "color", "label"]
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
