import Foundation

// ADR-0036 (Pratiche), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 7 -
// R-31; UX-BLUEPRINT.md's menu bar map, "Messaggio" row.
//
// One command a message row offers, named once so the row footer and its context menu
// (ADR-0023 §D1) read the same catalogue. `import Foundation` only, matching
// `PraticaCommand`'s own header, for the same reason - not in `sharedSources`.
//
// Every declaration below is a tester-declared boundary (ADR-0155 §D1): `available` is
// stubbed to `[]`, never `fatalError`.
enum MessageCommand: String, CaseIterable, Sendable {
    case openInMail
    case previewAttachment
    /// R-31: files to Trash, id recorded on the dossier's `excluded` key - never
    /// re-imported.
    case exclude
    /// R-31: files moved, ids updated on both dossiers (source loses, destination
    /// gains).
    case moveTo
    /// R-31: files copied, both dossiers gain the id.
    case alsoAddTo
    case regenerate

    /// The Italian label both surfaces draw, pinned to UX-BLUEPRINT.md's menu bar map
    /// ("Messaggio" row).
    var title: String {
        switch self {
        case .openInMail: "Apri in Mail"
        case .previewAttachment: "Anteprima allegato"
        case .exclude: "Escludi dalla pratica"
        case .moveTo: "Sposta in…"
        case .alsoAddTo: "Aggiungi anche a…"
        case .regenerate: "Rigenera…"
        }
    }

    /// The SF Symbol both surfaces draw - one table, the same reasoning as
    /// `PraticaCommand.symbol`.
    var symbol: String {
        switch self {
        case .openInMail: "envelope"
        case .previewAttachment: "eye"
        case .exclude: "xmark.circle"
        case .moveTo: "folder"
        case .alsoAddTo: "plus.circle"
        case .regenerate: "arrow.triangle.2.circlepath"
        }
    }

    /// Whether performing this command needs an argument the command alone does not
    /// name - which pratica (`CardCommand.carriesArgument`'s own shape). Both surfaces
    /// draw such a command as a submenu built from that argument's own values.
    var carriesArgument: Bool {
        switch self {
        case .moveTo, .alsoAddTo: true
        case .openInMail, .previewAttachment, .exclude, .regenerate: false
        }
    }

    /// The commands a message row offers - `.previewAttachment` only when the message
    /// actually carries one.
    ///
    /// Declaration order is the order both surfaces draw, the same rule
    /// `PraticaCommand.available(isActive:)` follows.
    static func available(hasAttachments: Bool) -> [MessageCommand] {
        allCases.filter { command in
            switch command {
            case .previewAttachment: hasAttachments
            case .openInMail, .exclude, .moveTo, .alsoAddTo, .regenerate: true
            }
        }
    }

    /// The one stable AX identifier for this command's control, shared by the row
    /// footer and the context menu.
    var identifier: String {
        "pratiche-message-command-\(rawValue)"
    }
}
