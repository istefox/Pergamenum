import Foundation

// ADR-0076 §D7 (PG-338), plan docs/plans/pratiche-message-anchored-entries.md, Task 6 -
// R-11, R-12; ADR-0023 §D1.
//
// One command a manual-entry row offers, named once so the row's context menu and its
// accessibility actions read the same catalogue - `MessageCommand`'s shape for the other
// kind of row. `import Foundation` only, for `MessageCommand`'s own reason.
enum PraticaEntryCommand: String, CaseIterable, Sendable {
    /// R-11: opens the message picker, and writes or replaces the entry's anchor line - on any
    /// manual entry, free, anchored or orphaned.
    case linkMessage
    /// R-12: removes the anchor line, and nothing else of the entry - only when there is one.
    case unlinkMessage

    var title: String {
        switch self {
        case .linkMessage: "Collega a un messaggio…"
        case .unlinkMessage: "Scollega dal messaggio"
        }
    }

    /// The SF Symbol both surfaces may draw (gate G1, decided by the implementation): a link
    /// being made and one being taken away.
    var symbol: String {
        switch self {
        case .linkMessage: "link.badge.plus"
        case .unlinkMessage: "minus.circle"
        }
    }

    /// The one stable AX identifier for this command's control.
    var identifier: String {
        "pratiche-entry-command-\(rawValue)"
    }

    /// The commands a manual-entry row offers (R-12): «Scollega dal messaggio» only when the
    /// entry carries an anchor line. Declaration order is the order the surfaces draw.
    static func available(hasAnchor: Bool) -> [PraticaEntryCommand] {
        allCases.filter { command in
            switch command {
            case .linkMessage: true
            case .unlinkMessage: hasAnchor
            }
        }
    }
}
