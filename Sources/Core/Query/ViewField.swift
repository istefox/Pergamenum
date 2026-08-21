import Foundation

/// Everything a view can name (ADR-0009 §D2), and nothing else.
///
/// The list is closed on purpose: no user-defined fields, no computed columns, no
/// formulas. Every case here is already in `NoteRecord` or is derived from the whole
/// index, so a view stays answerable from a vault scan alone and principle 3 keeps
/// holding after this feature exists.
///
/// One name a reasonable person will try is deliberately absent, and
/// `ViewField.absentFieldReason` is why it gets a sentence instead of "campo
/// sconosciuto": `created`, because the index stores `modifiedAt` and only that. The
/// other one, `embedTargets`, was absent until M11 spent its single permitted schema
/// bump on it.
enum ViewField: String, CaseIterable, Sendable, Comparable {
    case title
    case path
    case folder
    case tags
    case date
    case aliases
    case related
    case modified
    case size
    case links
    case linkedFrom
    case embedTargets
    case tasksOpen = "tasks.open"
    case tasksDone = "tasks.done"
    case tasksTotal = "tasks.total"
    case deadlineNext = "deadline.next"
    case scheduledNext = "scheduled.next"
    case unresolved

    /// The names a person may write, in the order the ADR's table lists them - which is
    /// also the order an error message reads them back.
    static var names: [String] { allCases.map(\.rawValue) }

    /// Whether this field's value is a day, which is what a calendar can place a row on.
    var isDated: Bool { [.date, .modified, .deadlineNext, .scheduledNext].contains(self) }

    /// What a column header calls this field, in the interface's language.
    ///
    /// In `Core` beside the field itself rather than in the renderer: `perg view run`
    /// prints a header too, and two spellings of the same column is the pair that drifts.
    /// A table rather than a switch, for the reason `derivations` gives.
    var label: String { Self.labels[self] ?? rawValue }

    private static let labels: [ViewField: String] = [
        .title: "titolo", .path: "percorso", .folder: "cartella", .tags: "tag",
        .date: "data", .aliases: "alias", .related: "correlate", .modified: "modificata",
        .size: "dimensione", .links: "link", .linkedFrom: "linkata da",
        .embedTargets: "allegati", .tasksOpen: "task aperti", .tasksDone: "task fatti",
        .tasksTotal: "task", .deadlineNext: "scadenza", .scheduledNext: "pianificata",
        .unresolved: "link non risolti",
    ]

    static func < (lhs: ViewField, rhs: ViewField) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The sentence for a field that does not exist. Named here rather than at the
    /// parser's call site because the reason belongs to the field, and because a
    /// deliberate absence deserves better than the generic answer.
    static func absentFieldReason(_ name: String) -> String {
        switch name {
        case "created":
            "«created» non esiste: l'indice conserva solo la data di modifica, e aggiungerne una "
                + "di creazione è una decisione di schema (ADR-0009 §D2)"
        default:
            "campo sconosciuto «\(name)». Disponibili: \(names.joined(separator: ", "))"
        }
    }
}

/// The value of one field for one note.
///
/// Five shapes rather than a string, because sorting a deadline and sorting a title are
/// not the same operation and a view that sorted `2026-9-1` before `2026-10-1` would be
/// wrong in the one place a person checks.
enum ViewValue: Equatable, Sendable, Comparable {
    /// The field has no value here: an absent frontmatter key, a note with no deadline.
    case absent
    case text(String)
    case list([String])
    case number(Int)
    case day(CalendarDate)

    /// What `has()` reads. An absent key, an empty list and a note with no open task all
    /// read as false, which is §D3's own sentence.
    var isEmpty: Bool {
        switch self {
        case .absent: true
        case .text(let text): text.isEmpty
        case .list(let items): items.isEmpty
        case .number(let count): count == 0
        case .day: false
        }
    }

    /// Ordering within a kind, and a fixed order between kinds so a sort never depends on
    /// which note happened to come first. `absent` sorts last ascending: a note with no
    /// deadline is not a note whose deadline is the beginning of time.
    static func < (lhs: ViewValue, rhs: ViewValue) -> Bool {
        switch (lhs, rhs) {
        case (.absent, .absent): false
        case (.absent, _): false
        case (_, .absent): true
        case (.text(let a), .text(let b)): a.localizedStandardCompare(b) == .orderedAscending
        case (.list(let a), .list(let b)): a.joined(separator: " ") < b.joined(separator: " ")
        case (.number(let a), .number(let b)): a < b
        case (.day(let a), .day(let b)): a < b
        default: lhs.sortRank < rhs.sortRank
        }
    }

    private var sortRank: Int {
        switch self {
        case .day: 0
        case .number: 1
        case .text: 2
        case .list: 3
        case .absent: 4
        }
    }
}

/// The two things about a note that only the whole vault can answer.
///
/// Precomputed once per evaluation rather than asked per note: both are a scan over
/// every record, and asking them inside the row loop is the quadratic version of the
/// same answer.
struct ViewGraph: Sendable {
    /// Titles of the notes linking to each note path, `linkedFrom`.
    var incoming: [String: [String]] = [:]
    /// The link targets of each note that no note in the vault answers to (W-07).
    var unresolved: [String: [String]] = [:]

    static let empty = ViewGraph()
}

extension ViewField {
    /// The value of this field for one note.
    ///
    /// Pure: everything comes from the record or from the graph handed in, and nothing
    /// here opens a file. `text()` is the one term that reads a note, and it is a filter
    /// rather than a field.
    func value(of record: NoteRecord, in graph: ViewGraph = .empty) -> ViewValue {
        guard let derivation = Self.derivations[self] else {
            assertionFailure("campo senza derivazione: \(rawValue)")
            return .absent
        }
        return derivation(record, graph)
    }

    /// The whole of §D2's table, written as a table.
    ///
    /// An eighteen-way `switch` scores 18 on SwiftLint's cyclomatic complexity, and
    /// `CommandActions.run` records why this codebase restructures rather than writes its
    /// first `swiftlint:disable`. The trade is the same one made there: a dictionary
    /// cannot be exhaustive at compile time, so `everyFieldHasADerivation` asks all of
    /// `allCases` for a value, and a field added without one is an `assertionFailure` on
    /// the first Debug run rather than a column that quietly says nothing.
    private static let derivations: [ViewField: @Sendable (NoteRecord, ViewGraph) -> ViewValue] = [
        .title: { record, _ in .text(record.title) },
        .path: { record, _ in .text(record.relativePath) },
        .folder: { record, _ in record.folder.isEmpty ? .absent : .text(record.folder) },
        .tags: { record, _ in .list(record.frontmatter.tags.sorted().map(\.description)) },
        .date: { record, _ in record.frontmatter.date.map(ViewValue.day) ?? .absent },
        .aliases: { record, _ in .list(record.frontmatter.aliases) },
        .related: { record, _ in .list(record.frontmatter.related) },
        .modified: { record, _ in .day(CalendarDate(record.modifiedAt)) },
        .size: { record, _ in .number(record.byteSize) },
        .links: { record, _ in .list(record.linkTargets) },
        .linkedFrom: { record, graph in .list(graph.incoming[record.relativePath] ?? []) },
        .embedTargets: { record, _ in .list(record.embedTargets) },
        .tasksOpen: { record, _ in .number(record.tasks.count { $0.state.isOpen }) },
        .tasksDone: { record, _ in .number(record.tasks.count { $0.state == .done }) },
        .tasksTotal: { record, _ in .number(record.tasks.count) },
        .deadlineNext: { record, _ in earliest(record.tasks.compactMap { $0.state.isOpen ? $0.due : nil }) },
        .scheduledNext: { record, _ in earliest(record.tasks.compactMap { $0.state.isOpen ? $0.scheduled : nil }) },
        .unresolved: { record, graph in .list(graph.unresolved[record.relativePath] ?? []) },
    ]

    /// The earliest of a set of days, with no clock involved.
    ///
    /// "Next" here means the first one still open, not the first one after today: a view
    /// that read the current date would give two different answers to the same question
    /// on two different days, and neither the tests nor `perg view run` could say which
    /// was right.
    private static func earliest(_ days: [CalendarDate]) -> ViewValue {
        days.min().map(ViewValue.day) ?? .absent
    }
}
