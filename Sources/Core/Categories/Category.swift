import Foundation

/// One entry in the category registry (SPEC "Data model — Category"): the entity
/// behind a task's `#project-<slug>` tag, existing independently of any note.
///
/// `Codable` and `Sendable`, no SwiftUI import: this type is compiled into both
/// connectors (ADR-0047 §D4/`Stack`), and a SwiftUI import here would break `perg` and
/// `pergamenum-mcp` by design (ADR-0001 §D1).
struct Category: Codable, Equatable, Sendable, Identifiable {
    /// Immutable once created (SPEC "Decisions": "renaming changes only the display
    /// name"), matching the tag value grammar `Tag.isWellFormedValue` and unique
    /// across both levels of the registry.
    let slug: String
    var name: String
    /// A palette name, never a hex value - resolved to a design token at render time
    /// (CLAUDE.md design-system rule, SPEC "Constraints": "a view uses colour only
    /// through a token").
    var color: String
    /// An SF Symbol name from the restricted picker (SPEC "Not yet specified"), optional.
    var symbol: String?
    var description: String?
    var deadline: CalendarDate?
    /// The parent's slug, when this is a sub-category. Must name a top-level category:
    /// depth is at most two (SPEC "Data model").
    var parent: String?
    /// Position among siblings.
    var order: Int
    var archived: Bool

    var id: String { slug }

    init(
        slug: String,
        name: String,
        color: String,
        symbol: String? = nil,
        description: String? = nil,
        deadline: CalendarDate? = nil,
        parent: String? = nil,
        order: Int = 0,
        archived: Bool = false
    ) {
        self.slug = slug
        self.name = name
        self.color = color
        self.symbol = symbol
        self.description = description
        self.deadline = deadline
        self.parent = parent
        self.order = order
        self.archived = archived
    }
}

/// `CalendarDate` carries no `Codable` conformance of its own - nothing before this
/// chain stored one directly in a `Codable` type (`IndexCache`'s `StoredFrontmatter`
/// keeps it as a plain ISO string and converts by hand). `Category.deadline` is the
/// first field that wants the synthesized `Codable` to just work, so the conformance
/// is added here, through the same ISO 8601 form `CalendarDate.description`/`init(iso:)`
/// already use for every other on-disk representation.
extension CalendarDate: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let date = CalendarDate(iso: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "not an ISO 8601 calendar date: \(raw)"
            )
        }
        self = date
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
