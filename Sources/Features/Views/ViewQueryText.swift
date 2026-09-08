import Foundation

/// What the query builder edits: the fields of a `pergamenum-view` fence, one row model
/// per key, before they become text (ADR-0034 §D2).
///
/// A plain struct with the seven keys' worth of state and nothing else — Task 3 fills in
/// how a draft is built from a parsed `ViewBlock` and what makes one valid to commit;
/// this shard only needs the shape the writer below reads from.
struct ViewQueryDraft {
    var scope: [String] = []
    var terms: [ViewFilter] = []
    var sort: [ViewBlock.SortKey] = []
    var group: ViewBlock.Grouping?
    var render: ViewBlock.Renderer = .table
    var columns: [ViewField] = []
    var limit: String = ""
}

/// The query builder's writer: a `ViewQueryDraft` becomes the body of a `pergamenum-view`
/// fence (ADR-0034 §D3), and a fresh stub for the insert-view command (R-04).
///
/// Pure `String` in, `String` out. Nothing here reads a theme, a controller or the vault —
/// the one thing this type is trusted to get right is that its own output round-trips
/// through `ViewBlock.parse`, which every test in `ViewQueryTextTests.swift` checks by
/// doing exactly that rather than by comparing strings to strings.
enum ViewQueryText {
    /// The fence body for a draft, in `ViewBlock`'s own declaration order.
    ///
    /// Each key is either written whole or left out entirely (C6) — never an empty
    /// `sort:`, `group:` or `limit:` line the parser would have to special-case, and
    /// never a `where:` built from rows that carry no argument yet.
    static func body(of draft: ViewQueryDraft) -> String {
        var lines: [String] = []

        if !draft.scope.isEmpty {
            let joined = draft.scope.map { "path(\"\($0)\")" }.joined(separator: " or ")
            lines.append("from: \(joined)")
        }

        let terms = draft.terms.filter(isComplete)
        if !terms.isEmpty {
            lines.append("where: \(terms.map(text(of:)).joined(separator: " and "))")
        }

        if !draft.sort.isEmpty {
            lines.append("sort: \(draft.sort.map(text(of:)).joined(separator: ", "))")
        }

        // A `group` only means something for `render: board` (ADR-0009 §D1): the other
        // four renderers never draw grouped, so a group carried over from a board draft
        // stays unwritten rather than emitting a key nothing reads.
        if draft.render == .board, let group = draft.group {
            lines.append("group: \(text(of: group))")
        }

        // The one key with no default: always present, whatever it is.
        lines.append("render: \(draft.render.rawValue)")

        if let selection = columnsToWrite(draft.columns, render: draft.render) {
            lines.append("columns: [\(selection.map(\.rawValue).joined(separator: ", "))]")
        }

        let limit = draft.limit.trimmingCharacters(in: .whitespaces)
        if !limit.isEmpty {
            lines.append("limit: \(limit)")
        }

        return lines.joined(separator: "\n")
    }

    /// Whether `selection` is worth writing as `columns:`, or whether it is exactly what
    /// `render` already draws with no `columns:` key at all (R-15).
    ///
    /// `nil` for an empty selection too — an untouched draft carries no customisation to
    /// write, and `columns: []` would parse to the same `effectiveColumns` as no key at
    /// all (`ViewBlock.effectiveColumns` falls back to the renderer's default whenever
    /// `columns.isEmpty`), so writing it bare would cost a line for nothing.
    static func columnsToWrite(_ selection: [ViewField], render: ViewBlock.Renderer) -> [ViewField]? {
        guard !selection.isEmpty else { return nil }
        let defaults = ViewBlock(render: render).effectiveColumns
        return selection == defaults ? nil : selection
    }

    /// One `where` term, or one operand of `sort`/`group` reused for the `not` case —
    /// re-parsed by every call site in `ViewQueryTextTests.swift`, which is the actual
    /// contract: this only has to agree with `ViewFilter.parse`, never with a fixture.
    static func text(of term: ViewFilter) -> String {
        switch term {
        case .all:
            return ""
        case .and(let lhs, let rhs):
            return "\(text(of: lhs)) and \(text(of: rhs))"
        case .or(let lhs, let rhs):
            return "\(text(of: lhs)) or \(text(of: rhs))"
        case .not(let inner):
            return "not \(text(of: inner))"
        case .path(let value):
            return "path(\"\(value)\")"
        case .tag(let value):
            return "tag(\"\(value)\")"
        case .linksTo(let value):
            return "linksTo(\"\(value)\")"
        case .linkedFrom(let value):
            return "linkedFrom(\"\(value)\")"
        case .task(let state):
            return "task(\(taskStateWord(state)))"
        case .has(let field):
            return "has(\(field.rawValue))"
        case .text(let value):
            return "text(\"\(value)\")"
        case .comparison(let field, let symbol, let bound):
            // `bound.text` is the parser's own spelling (`ViewDateBound.text`), which is
            // why `today`/`today-7`/`week-start` are the only words that ever reach here.
            return "\(field.rawValue) \(symbol.rawValue) \(bound.text)"
        }
    }

    /// A closed, parseable `pergamenum-view` fence for the insert-view command (R-04):
    /// the stub the query builder always opens on, so "Fatto" edits an existing fence
    /// rather than sometimes writing one — a single implementation for the commit path
    /// (ADR-0034 §D10).
    ///
    /// `atLineStart` decides whether a leading `\n` is needed to give the fence its own
    /// line — the caret may be mid-line when the command runs. `openingOffset` is where
    /// the opening backticks land within `text`, which is what
    /// `EditorDecorationDelegate.viewBlockRun(in:atParagraphStart:)` needs to find them.
    /// `cursorBack`, `NoteTextView`'s own convention (`EditorCommand.swift`'s skeletons),
    /// is counted from the end of `text` rather than written as a literal, so editing the
    /// stub later never leaves it pointing at the wrong character.
    static func stub(atLineStart: Bool) -> (text: String, cursorBack: Int, openingOffset: Int) {
        let head = atLineStart ? "" : "\n"
        let closing = "\n```\n"
        let fence = "```\(ViewBlock.language)\nrender: \(ViewBlock.Renderer.table.rawValue)\(closing)"
        return (text: head + fence, cursorBack: closing.count, openingOffset: head.count)
    }

    /// Whether a term carries an argument yet — an empty-string row contributes nothing
    /// to `where` (ADR-0034 §D7) rather than writing `tag("")`, which would parse into a
    /// glob matching nothing and look like a deliberate filter.
    private static func isComplete(_ term: ViewFilter) -> Bool {
        switch term {
        case .path(let value), .tag(let value), .linksTo(let value), .linkedFrom(let value), .text(let value):
            !value.isEmpty
        case .not(let inner):
            isComplete(inner)
        case .all, .and, .or, .task, .has, .comparison:
            true
        }
    }

    private static func text(of key: ViewBlock.SortKey) -> String {
        key.descending ? "\(key.field.rawValue) desc" : key.field.rawValue
    }

    private static func text(of grouping: ViewBlock.Grouping) -> String {
        switch grouping {
        case .tag(let glob): "tag(\"\(glob)\")"
        case .field(let field): field.rawValue
        }
    }

    /// `task()`'s two spellings. `TaskItem.State` carries two more cases
    /// (`.rescheduled`, `.cancelled`) that `ViewFilter.task` never actually holds — the
    /// parser's own `state(_:)` only ever produces `.open`/`.done` — so they fall back to
    /// `open` defensively rather than needing a third word the grammar has no room for.
    private static func taskStateWord(_ state: TaskItem.State) -> String {
        switch state {
        case .done: "done"
        case .open, .rescheduled, .cancelled: "open"
        }
    }
}
