import Foundation

// ADR-0084 §D1 (PG-386, N3 session C).

/// The catalogue of a backlink row's menu, rendered once as the `.contextMenu` and once as the
/// `.accessibilityActions` (ADR-0023 §D1).
enum BacklinkCommand: CaseIterable, Identifiable, Sendable {
    case open, openInOtherColumn, makeStructural, unlink

    var id: Self { self }

    var title: String {
        switch self {
        case .open: "Apri"
        case .openInOtherColumn: "Apri nell'altra colonna"
        case .makeStructural: "Rendi strutturale"
        case .unlink: "Scollega"
        }
    }

    /// «Rendi strutturale» on a row that is not structural, «Scollega» only on one that is: a row
    /// never offers both, because a link is either one or the other.
    static func available(for row: BacklinkRow) -> [BacklinkCommand] {
        [.open, .openInOtherColumn, row.isStructural ? .unlink : .makeStructural]
    }
}
