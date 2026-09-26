import Foundation

// ADR-0036 (Pratiche), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 7 -
// R-31; UX-BLUEPRINT.md's menu bar map, "Messaggio" row.
//
// One command a message row offers, named once so the row footer and its context menu
// (ADR-0023 §D1) read the same catalogue. `import Foundation` only, matching
// `PraticaCommand`'s own header, for the same reason - not in `sharedSources`.
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
    /// R-02 (ADR-0049 §D10): opens `PraticaLinkPicker` for this message's
    /// `pergamenum-mail-note` key - offered regardless of an existing link, since
    /// picking a new target replaces rather than appends (the relation is 0/1).
    case linkNote
    /// R-02: clears `pergamenum-mail-note`, offered only when there is a link to
    /// remove (`available(hasAttachments:hasLinkedNote:)` below).
    case unlinkNote

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
        case .linkNote: "Collega nota…"
        case .unlinkNote: "Scollega nota"
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
        case .linkNote: "doc.badge.plus"
        case .unlinkNote: "doc.badge.minus"
        }
    }

    /// Whether performing this command needs an argument the command alone does not
    /// name - which pratica (`CardCommand.carriesArgument`'s own shape). Both surfaces
    /// draw such a command as a submenu built from that argument's own values.
    var carriesArgument: Bool {
        switch self {
        case .moveTo, .alsoAddTo: true
        case .openInMail, .previewAttachment, .exclude, .regenerate, .linkNote, .unlinkNote: false
        }
    }

    /// The commands a message row offers - `.previewAttachment` only when the message
    /// actually carries one, `.unlinkNote` only when `pergamenum-mail-note` is set
    /// (R-02, ADR-0049 §D10).
    ///
    /// Declaration order is the order both surfaces draw, the same rule
    /// `PraticaCommand.available(isActive:)` follows.
    static func available(hasAttachments: Bool, hasLinkedNote: Bool) -> [MessageCommand] {
        allCases.filter { command in
            switch command {
            case .previewAttachment: hasAttachments
            case .unlinkNote: hasLinkedNote
            case .openInMail, .exclude, .moveTo, .alsoAddTo, .regenerate, .linkNote: true
            }
        }
    }

    /// The one stable AX identifier for this command's control, shared by the row
    /// footer and the context menu.
    var identifier: String {
        "pratiche-message-command-\(rawValue)"
    }
}
