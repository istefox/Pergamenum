import Foundation

/// The closed tag families, loaded rather than compiled in.
///
/// SPEC §4.6 is explicit that the `harness-system` repo is the source of truth and
/// that the app holds a declared replica in `.pergamenum/vocabolari.json`. Hard-coding
/// the tables here would make the app the second source of truth, which is the one
/// thing that section forbids, so the values arrive as data and the code only knows
/// the shape.
struct Vocabulary: Equatable, Sendable, Codable {
    /// `type-*`, `status-*`, `area-*`, `source-*`: a value outside the table is a
    /// blocking error at typing time (SPEC §4.4).
    var type: Set<String>
    var status: Set<String>
    var area: Set<String>
    var source: Set<String>
    /// Deliverable kinds from naming.md 6.1, used by the export file name builder.
    var deliverableKind: Set<String>

    /// An empty vocabulary. Every closed-family value is unknown until the real
    /// tables are imported, so the linter reports rather than silently accepting.
    /// Chosen over a guessed table on purpose: a wrong closed value would be written
    /// into real notes and then have to be found again.
    static let empty = Vocabulary(type: [], status: [], area: [], source: [], deliverableKind: [])

    var isEmpty: Bool {
        type.isEmpty && status.isEmpty && area.isEmpty && source.isEmpty && deliverableKind.isEmpty
    }

    func values(for namespace: TagNamespace) -> Set<String>? {
        switch namespace {
        case .type: type
        case .status: status
        case .area: area
        case .source: source
        case .client, .competitor, .project, .topic: nil
        }
    }
}

/// The eight namespaces of tag.md T-01, in the order the frontmatter must list them.
enum TagNamespace: String, CaseIterable, Sendable, Comparable {
    case client
    case competitor
    case project
    case type
    case topic
    case status
    case area
    case source

    /// Closed families take their values from the vocabulary; open families follow
    /// formation rules only.
    var isClosed: Bool {
        switch self {
        case .type, .status, .area, .source: true
        case .client, .competitor, .project, .topic: false
        }
    }

    private var order: Int {
        TagNamespace.allCases.firstIndex(of: self) ?? 0
    }

    static func < (lhs: TagNamespace, rhs: TagNamespace) -> Bool {
        lhs.order < rhs.order
    }
}
