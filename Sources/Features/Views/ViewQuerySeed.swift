import Foundation
import Observation

/// What the query builder edits: the fields of a `pergamenum-view` fence, one row model
/// per key, before they become text (ADR-0034 §D2).
///
/// `@Observable` because the sheet's controls (Task 5) bind directly to its properties —
/// a plain struct would need a wrapper `@State` the sheet reassigns wholesale on every
/// row edit, which is not how the rest of this app's forms work.
///
/// `rawWhere` is the raw-text fallback for a `where` the row model cannot express (`or`,
/// `not`, a nesting no flat conjunction can show, ADR-0034 §D5): `nil` means `terms` is
/// authoritative, a non-nil string means it is written back verbatim and `terms` is empty.
@Observable
final class ViewQueryDraft {
    var scope: [String]
    var terms: [ViewFilter]
    var rawWhere: String?
    var sort: [ViewBlock.SortKey]
    var group: ViewBlock.Grouping?
    var render: ViewBlock.Renderer
    var columns: [ViewField]
    var limit: String

    init(
        scope: [String] = [],
        terms: [ViewFilter] = [],
        rawWhere: String? = nil,
        sort: [ViewBlock.SortKey] = [],
        group: ViewBlock.Grouping? = nil,
        render: ViewBlock.Renderer = .table,
        columns: [ViewField] = [],
        limit: String = ""
    ) {
        self.scope = scope
        self.terms = terms
        self.rawWhere = rawWhere
        self.sort = sort
        self.group = group
        self.render = render
        self.columns = columns
        self.limit = limit
    }
}

/// R-02/R-03: a `ViewQueryDraft` seeded from an existing fence body, field by field.
///
/// The whole feature is a sheet that must never disagree with the note (ADR-0034 §D7), so
/// seeding never invents a second grammar over the same text (§D6). It reuses the one real
/// parser, `ViewBlock.parse`, isolated per key: a line that does not parse leaves its own
/// control at its default rather than failing the whole draft, and one broken key never
/// touches the other six.
extension ViewQueryDraft {
    /// The seven keys `ViewBlock.parse` knows, in the order the parser rejects a stray one.
    private static let keys = ["from", "where", "sort", "group", "render", "columns", "limit"]

    /// A syntactically valid `group` value used only to keep the `render`-key recovery
    /// below from tripping `ViewBlock.assemble`'s board-needs-group rule (ADR-0009 §D1):
    /// the parse that recovers `render` never reads `.group` off its result, so what this
    /// says does not matter, only that it parses.
    private static let placeholderGroup = "tag(\"__seed__\")"

    /// Builds a draft from a fence's body. Nonthrowing: a body that is not `key: value` at
    /// all, or where every key is broken, still returns a draft, holding the same defaults
    /// `ViewQueryDraft()` would (R-03).
    static func seed(from body: String) -> ViewQueryDraft {
        let draft = ViewQueryDraft()
        let raw = rawEntries(in: body)

        if let value = raw["from"], let parsed = recovered(key: "from", value: value) {
            draft.scope = parsed.scope
        }
        if let value = raw["where"], let parsed = recovered(key: "where", value: value) {
            if let terms = ViewQueryFlattening.terms(of: parsed.filter) {
                draft.terms = terms
                draft.rawWhere = nil
            } else {
                draft.terms = []
                draft.rawWhere = value
            }
        }
        if let value = raw["sort"], let parsed = recovered(key: "sort", value: value) {
            draft.sort = parsed.sort
        }
        if let value = raw["group"], let parsed = recovered(key: "group", value: value) {
            draft.group = parsed.group
        }
        if let value = raw["render"], let parsed = recovered(key: "render", value: value) {
            draft.render = parsed.render
        }
        if let value = raw["columns"], let parsed = recovered(key: "columns", value: value) {
            draft.columns = parsed.columns
        }
        if let value = raw["limit"], let parsed = recovered(key: "limit", value: value), let limit = parsed.limit {
            draft.limit = String(limit)
        }
        return draft
    }

    /// One key's raw value, isolated through the real parser (ADR-0034 §D6): `"render:
    /// table\n<key>: <value>"` for the six keys `render` does not gate, `"render:
    /// <value>\ngroup: …"` for `render` itself, so a `board` value recovers without the
    /// board-needs-group rule seeing a missing group that belongs to a different line.
    private static func recovered(key: String, value: String) -> ViewBlock? {
        let synthetic = key == "render"
            ? "render: \(value)\ngroup: \(placeholderGroup)"
            : "render: table\n\(key): \(value)"
        return try? ViewBlock.parse(synthetic)
    }

    /// The body's `key: value` pairs, first occurrence per key (C6's own duplicate rule,
    /// applied leniently instead of thrown) — the same per-line split `ViewBlock.parse`
    /// uses, so a colon inside a quoted argument never breaks the key/value boundary.
    private static func rawEntries(in body: String) -> [String: String] {
        var entries: [String: String] = [:]
        for raw in body.components(separatedBy: .newlines) {
            let text = raw.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            guard let separator = text.firstIndex(of: ":") else { continue }
            let key = String(text[text.startIndex..<separator]).trimmingCharacters(in: .whitespaces)
            guard keys.contains(key), entries[key] == nil else { continue }
            let value = String(text[text.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            entries[key] = value
        }
        return entries
    }
}
