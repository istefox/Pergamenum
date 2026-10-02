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
    /// ADR-0076 §D7 (PG-338), R-02, R-03: a «Nota» anchored to this message, written now under
    /// the message's own counterpart - on every row, the last one included. Placed just before
    /// ADR-0049's «Collega una nota…», the other verb about a note and this message, so the three
    /// near labels read as one group (gate G1, decided by the implementation).
    case addNote
    /// R-02, R-03: the same, as a «Telefonata».
    case addCall
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
        case .moveTo: "Sposta in"
        case .alsoAddTo: "Aggiungi anche a"
        case .regenerate: "Rigenera…"
        case .addNote: "Aggiungi nota"
        case .addCall: "Aggiungi telefonata"
        case .linkNote: "Collega una nota…"
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
        // The counts bar's own two glyphs for the same two kinds (`PraticaTimelineView`), so a
        // verb reads the same wherever it is drawn.
        case .addNote: "square.and.pencil"
        case .addCall: "phone"
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
        case .openInMail, .previewAttachment, .exclude, .regenerate, .addNote, .addCall, .linkNote, .unlinkNote:
            false
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
            // ADR-0076 §D7: always, and never by position - the last row gets them too (R-02).
            case .openInMail, .exclude, .moveTo, .alsoAddTo, .regenerate, .addNote, .addCall, .linkNote: true
            }
        }
    }

    /// The commands a message row draws as `.accessibilityActions` (ADR-0076 §D7, R-02): every
    /// available one that carries no argument. An argument-carrying command is a submenu of
    /// destinations on both visible surfaces, which an accessibility action has no way to be.
    static func accessibilityCommands(hasAttachments: Bool, hasLinkedNote: Bool) -> [MessageCommand] {
        available(hasAttachments: hasAttachments, hasLinkedNote: hasLinkedNote).filter { !$0.carriesArgument }
    }

    /// How the row's footer draws `commands` (ADR-0076 §D7, PG-338): a few verbs as text buttons,
    /// every other one inside «Altro», each group in the order `commands` arrives in, so no
    /// command is listed twice.
    ///
    /// Primary: «Apri in Mail» and «Aggiungi nota», nothing else - «Apri in Mail · Aggiungi nota ·
    /// Altro ▸». The hand check measured a footer of four verbs plus «Altro» wider than a message
    /// lane in an 800 pt timeline, so it stacked into a column and every card filled its lane;
    /// with two it stays one line down to narrow timelines, and only there does the row's
    /// `ViewThatFits` stack it. «Aggiungi telefonata», «Collega una nota…» and «Scollega nota» live in
    /// «Altro» with the rest, and the context menu and the accessibility actions still list every
    /// command. An argument-carrying command is never primary: it is a submenu of destinations,
    /// which «Altro» can nest. The switch is exhaustive on purpose, so a new command has to be
    /// placed here before it builds.
    static func footerSplit(_ commands: [MessageCommand]) -> (primary: [MessageCommand], overflow: [MessageCommand]) {
        let isPrimary: (MessageCommand) -> Bool = { command in
            switch command {
            case .openInMail, .addNote: true
            case .addCall, .linkNote, .unlinkNote, .previewAttachment, .exclude, .moveTo, .alsoAddTo, .regenerate:
                false
            }
        }
        return (commands.filter(isPrimary), commands.filter { !isPrimary($0) })
    }

    /// The one stable AX identifier for this command's control, shared by the row
    /// footer and the context menu.
    var identifier: String {
        "pratiche-message-command-\(rawValue)"
    }
}
