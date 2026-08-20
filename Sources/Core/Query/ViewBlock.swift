import Foundation

/// What a `pergamenum-view` fence says (ADR-0009 §D1).
///
/// A view is a fenced block in an ordinary note, so it lives in the vault, is versioned
/// with everything else, and Obsidian renders it as an inert code block - the correct
/// behaviour for a reader that does not know how to run it.
///
/// The body is YAML-shaped rather than YAML: seven keys, one per line, all optional but
/// `render`, parsed by hand. A block that does not parse is an **error naming the line**
/// and never an empty result: an empty list is indistinguishable from a vault that lost
/// its notes, and that confusion has already cost this project an afternoon once.
struct ViewBlock: Equatable, Sendable {
    /// `from: path("Clienti")`, the scope. Empty means the whole vault.
    ///
    /// Only `path()` terms, combined with `or`. It is a scope rather than a second
    /// filter: §D7 has the watcher re-run a view when a change touches its `from`, and a
    /// scope that could say `text("x")` would make that test as expensive as the view.
    var scope: [String] = []
    /// `where:`, the filter. `.all` when the key is absent.
    var filter: ViewFilter = .all
    /// `sort: modified desc, title` - one or more fields, each optionally reversed.
    var sort: [SortKey] = []
    /// `group: tag("status-*")`. Required by `render: board`, optional for the rest.
    var group: Grouping?
    /// `render:`, the only key with no default.
    var render: Renderer
    /// `columns: [title, tags, modified]`. Empty leaves the choice to the renderer.
    var columns: [ViewField] = []
    /// `limit: 20`, applied after sorting and before grouping, so a limited board shows
    /// the same notes a limited table would.
    var limit: Int?

    struct SortKey: Equatable, Sendable {
        var field: ViewField
        var descending = false
    }

    enum Grouping: Equatable, Sendable {
        /// `group: tag("status-*")`: one column per tag matching the glob.
        case tag(String)
        /// `group: folder`: one column per distinct value of a field.
        case field(ViewField)

        /// Whether a board grouped this way may be dragged (§D5).
        ///
        /// Only a tag namespace. Dragging a card into a different `modified` value is
        /// meaningless, and a renderer that silently did nothing on drop would be worse
        /// than one that does not offer the gesture.
        var isWritable: Bool {
            if case .tag = self { return true }
            return false
        }
    }

    enum Renderer: String, Equatable, Sendable, CaseIterable {
        case table
        case board
        case gallery
        case calendar
        case list
    }

    /// The fence's info string. `MarkdownBlockParser` already hands reading mode a
    /// `.code(language:lines:)`, so this is the whole of what makes a code block a view.
    static let language = "pergamenum-view"
}

/// What a block that does not parse says, with the line it says it about.
///
/// Lines are 1-based within the fence body: the first line after the opening ``` is 1,
/// which is the line a person counts when they look at the block they wrote.
struct ViewBlockError: Error, CustomStringConvertible, Equatable {
    let line: Int
    let reason: String

    var description: String { "riga \(line): \(reason)" }
}

// MARK: - Parsing

extension ViewBlock {
    private static let keys = ["from", "where", "sort", "group", "render", "columns", "limit"]

    /// Parses the body of a fence, without the fence lines themselves.
    static func parse(_ source: String) throws -> ViewBlock {
        var keys: [String: (line: Int, value: String)] = [:]

        for (offset, raw) in source.components(separatedBy: .newlines).enumerated() {
            let line = offset + 1
            let text = raw.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            guard let separator = text.firstIndex(of: ":") else {
                throw ViewBlockError(line: line, reason: "riga senza «chiave: valore»")
            }
            let key = String(text[text.startIndex..<separator]).trimmingCharacters(in: .whitespaces)
            guard Self.keys.contains(key) else {
                throw ViewBlockError(
                    line: line,
                    reason: "chiave sconosciuta «\(key)». Le sette sono: \(Self.keys.joined(separator: ", "))"
                )
            }
            // A second `where` quietly winning over the first is exactly the kind of
            // thing a person spends an evening on.
            if let first = keys[key] {
                throw ViewBlockError(line: line, reason: "«\(key)» è già alla riga \(first.line)")
            }
            let value = String(text[text.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { throw ViewBlockError(line: line, reason: "«\(key)» non ha valore") }
            keys[key] = (line, value)
        }

        return try assemble(keys)
    }

    private static func assemble(_ keys: [String: (line: Int, value: String)]) throws -> ViewBlock {
        guard let rendering = keys["render"] else {
            throw ViewBlockError(line: 1, reason: "manca «render»: una vista deve dire come si disegna")
        }
        guard let renderer = Renderer(rawValue: rendering.value.lowercased()) else {
            throw ViewBlockError(
                line: rendering.line,
                reason: "«\(rendering.value)» non è un renderer. Disponibili: "
                    + Renderer.allCases.map(\.rawValue).joined(separator: ", ")
            )
        }

        var block = ViewBlock(render: renderer)
        if let entry = keys["from"] { block.scope = try scope(entry.value, line: entry.line) }
        if let entry = keys["where"] { block.filter = try ViewFilter.parse(entry.value, line: entry.line) }
        if let entry = keys["sort"] { block.sort = try sortKeys(entry.value, line: entry.line) }
        if let entry = keys["group"] { block.group = try grouping(entry.value, line: entry.line) }
        if let entry = keys["columns"] { block.columns = try columns(entry.value, line: entry.line) }
        if let entry = keys["limit"] { block.limit = try limit(entry.value, line: entry.line) }

        // §D1: a board without `group` is a parse error, not a board with one column and
        // not a read-only one. A silent single column looks like a filter that matched
        // nothing, and a read-only board looks like a bug in the dragging.
        if renderer == .board, block.group == nil {
            throw ViewBlockError(
                line: rendering.line,
                reason: "una board è fatta di colonne: aggiungi «group», per esempio group: tag(\"status-*\")"
            )
        }
        return block
    }

    /// `from: path("Clienti") or path("Archivio/Clienti")`.
    private static func scope(_ value: String, line: Int) throws -> [String] {
        var globs: [String] = []
        try collectPaths(in: try ViewFilter.parse(value, line: line), line: line, into: &globs)
        return globs
    }

    private static func collectPaths(in filter: ViewFilter, line: Int, into globs: inout [String]) throws {
        switch filter {
        case .path(let glob): globs.append(glob)
        case .or(let lhs, let rhs):
            try collectPaths(in: lhs, line: line, into: &globs)
            try collectPaths(in: rhs, line: line, into: &globs)
        default:
            throw ViewBlockError(
                line: line,
                reason: "«from» accetta solo path(), eventualmente più d'uno unito da «or». Il resto va in «where»"
            )
        }
    }

    private static func sortKeys(_ value: String, line: Int) throws -> [SortKey] {
        try value.components(separatedBy: ",").compactMap { component in
            let parts = component.split(separator: " ").map(String.init)
            guard let name = parts.first else { return nil }
            guard let field = ViewField(rawValue: name) else {
                throw ViewBlockError(line: line, reason: ViewField.absentFieldReason(name))
            }
            switch parts.count {
            case 1: return SortKey(field: field)
            case 2 where parts[1].lowercased() == "desc": return SortKey(field: field, descending: true)
            case 2 where parts[1].lowercased() == "asc": return SortKey(field: field)
            default:
                let rest = parts.dropFirst().joined(separator: " ")
                throw ViewBlockError(line: line, reason: "dopo «\(name)» va asc o desc, non «\(rest)»")
            }
        }
    }

    private static func grouping(_ value: String, line: Int) throws -> Grouping {
        if value.hasPrefix("tag(") {
            guard case .tag(let glob) = try ViewFilter.parse(value, line: line) else {
                throw ViewBlockError(line: line, reason: "«group» vuole un solo tag(), non un'espressione")
            }
            return .tag(glob)
        }
        guard let field = ViewField(rawValue: value) else {
            throw ViewBlockError(line: line, reason: ViewField.absentFieldReason(value))
        }
        return .field(field)
    }

    /// `columns: [title, tags]`, brackets optional.
    private static func columns(_ value: String, line: Int) throws -> [ViewField] {
        let inner = value.hasPrefix("[") && value.hasSuffix("]") ? String(value.dropFirst().dropLast()) : value
        return try inner.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { name in
                guard let field = ViewField(rawValue: name) else {
                    throw ViewBlockError(line: line, reason: ViewField.absentFieldReason(name))
                }
                return field
            }
    }

    private static func limit(_ value: String, line: Int) throws -> Int {
        guard let limit = Int(value), limit > 0 else {
            throw ViewBlockError(line: line, reason: "«limit» vuole un intero positivo, non «\(value)»")
        }
        return limit
    }
}

// MARK: - Finding them in a note

extension ViewBlock {
    /// Every view fence in a note body, in source order, each parsed or with the error to
    /// draw where it would have gone.
    ///
    /// Built on `MarkdownBlockParser`, which already knows where a fence starts and ends
    /// and hands back its language: a second scanner for the same thing would be a second
    /// answer to "is this line inside a code block".
    static func blocks(in body: String) -> [Result<ViewBlock, ViewBlockError>] {
        MarkdownBlockParser.blocks(in: body).compactMap { block in
            guard case .code(let language, let lines) = block, language == Self.language else { return nil }
            return Result { try parse(lines.joined(separator: "\n")) }
                .mapError { $0 as? ViewBlockError ?? ViewBlockError(line: 1, reason: "\($0)") }
        }
    }
}
