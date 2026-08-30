import CoreGraphics
import Foundation

/// One command a canvas card offers, named once so the card's own context menu and the
/// board's contextual command bar (ADR-0023 §D1, §D7) read the same catalogue instead of
/// two hand-kept lists that can drift apart.
///
/// `import Foundation` and `import CoreGraphics` only, deliberately: this file stays a
/// pure catalogue a test can read without pulling in SwiftUI. Not in `sharedSources`
/// (ADR-0023 §A6 - the connectors have no board-editing surface).
///
/// Plan `docs/superpowers/plans/2026-08-25-universal-command-surface-parity.md`, Task 1
/// (R-06, R-13).
enum CardCommand: String, CaseIterable, Sendable {
    case open
    case editText
    case copyLink
    case color
    /// Whole-card text colour, offered only on a `.text` node (ADR-0027 §D4, §D7) - sits
    /// right next to `.color` in menu order, because §D7 puts "text colour" exactly where
    /// "Colore" already is, never on the selection-scoped format bar.
    case textColor
    /// Whole-card text alignment, offered only on a `.text` node (ADR-0027 §D4, §D7) - same
    /// reasoning and the same menu slot as `.textColor` above.
    case textAlign
    /// Fold a heading's section on a `.text` card (ADR-0028 §D8), offered only there for the
    /// same reason the two above are: a card with no markdown in it has no heading to fold.
    ///
    /// A submenu rather than a plain button, like `.color` and `.textAlign`: the command
    /// carries an argument - *which* heading - built from `NoteOutline.entries(in:)` over the
    /// node's own text. The Workspace has no in-text disclosure control to port, because the
    /// note editor has none either: fold there comes from `OutlinePane`'s chevron, outside the
    /// editor (ADR-0028 §D8).
    case foldHeadings
    case resize
    case fitToCrop
    case crop
    case removeCrop
    case duplicate
    case delete

    /// The Italian label both surfaces draw for this command (ADR-0023 §D1) - pinned to
    /// exactly what `BoardContentLayer`'s context menu draws today
    /// (`BoardContentLayer.swift:55-89`), plus `Duplica`, this feature's one net-new
    /// command (ADR-0023 §D11). A title is user-facing contract even where no test
    /// reaches it, so these are moved rather than retyped.
    var title: String {
        switch self {
        case .open: "Apri"
        case .editText: "Modifica testo"
        case .copyLink: "Copia link Pergamenum"
        case .color: "Colore"
        case .textColor: "Colore testo"
        case .textAlign: "Allineamento"
        case .foldHeadings: "Ripiega titoli"
        case .resize: "Ridimensiona"
        case .fitToCrop: "Adatta al ritaglio"
        case .crop: "Ritaglia"
        case .removeCrop: "Rimuovi ritaglio"
        case .duplicate: "Duplica"
        case .delete: "Elimina"
        }
    }

    /// The SF Symbol both surfaces draw for this command (R-13). One table, so the bar's
    /// icon and the menu's icon cannot disagree - which is what turns R-13 from a review
    /// item into a property of the code.
    ///
    /// Only `.delete` has a prior use to reuse: `trash`, from the Workspace browser's own
    /// toolbar (`WorkspaceBrowserToolbar.swift:35`). The card's context menu draws
    /// icon-less buttons today, and so do the menu bar and `NoteRowMenu`, so every other
    /// case below is a first choice recorded here rather than left to a review.
    /// `.duplicate` is a new command and picks `doc.on.doc`, the system's own duplicate
    /// glyph.
    ///
    /// `eye` is deliberately *not* `.open`'s symbol: it already means "Anteprima rapida"
    /// in this same board toolbar (`WorkspaceView.swift:261`), and reusing it would make
    /// the two commands indistinguishable.
    var symbol: String {
        switch self {
        case .open: "arrow.up.forward.square"
        case .editText: "text.cursor"
        case .copyLink: "link"
        case .color: "paintpalette"
        case .textColor: "paintbrush"
        case .textAlign: "text.aligncenter"
        case .foldHeadings: "chevron.up.chevron.down"
        case .resize: "arrow.up.left.and.arrow.down.right"
        case .fitToCrop: "aspectratio"
        case .crop: "crop"
        case .removeCrop: "xmark.rectangle"
        case .duplicate: "doc.on.doc"
        case .delete: "trash"
        }
    }

    /// The commands `node` offers, in menu order, given whether it can be cropped
    /// (`BoardContentLayer.isCroppable(node)`, unchanged - it needs the board's zoom, so
    /// only the caller can answer it) and whether it already carries a crop
    /// (`CanvasCrop.read(from:)`). ADR-0023 §D1, §D8.
    ///
    /// The order is the one the context menu already draws: "Adatta al ritaglio" sits
    /// inside the "Ridimensiona" group, right after it, and "Rimuovi ritaglio" right
    /// after "Ritaglia" (`BoardContentLayer.swift:66-87`).
    ///
    /// `isCroppable` alone decides whether any crop command appears; `hasCrop` only ever
    /// adds to what it allows. A node the board cannot crop must not offer crop commands
    /// because a leftover `pergamenum-crop` key survived on it.
    ///
    /// `node` is part of the signature because applicability is a property of the card:
    /// the two flags a caller passes are both derived from it, and a future rule that
    /// varies by `kind` lands here instead of at every call site.
    static func available(for node: CanvasNode, isCroppable: Bool, hasCrop: Bool) -> [CardCommand] {
        // A `.text` card has nothing for «Apri» to open (`BoardCardActions.open` no-ops on
        // it) - «Modifica testo» is the command that actually does something, in the same
        // menu slot.
        let opener: CardCommand = { if case .text = node.kind { .editText } else { .open } }()
        var commands: [CardCommand] = [opener, .copyLink, .color]
        // ADR-0027 §D7: whole-card text colour and alignment sit right after «Colore»,
        // only on a `.text` node - every other card kind has no text to colour or align.
        // ADR-0028 §D8 adds «Ripiega titoli» at the end of that same group, for the same
        // reason and on the same one card kind: only a `.text` node has markdown of its own
        // to fold, and its headings are what the submenu is built from.
        if case .text = node.kind {
            commands.append(contentsOf: [.textColor, .textAlign, .foldHeadings])
        }
        commands.append(.resize)
        if isCroppable {
            if hasCrop { commands.append(.fitToCrop) }
            commands.append(.crop)
            if hasCrop { commands.append(.removeCrop) }
        }
        commands.append(.duplicate)
        commands.append(.delete)
        return commands
    }

    /// The one stable AX identifier for this command's control, shared by
    /// `BoardCardControls` and the card's own context menu (R-06).
    ///
    /// Derived from `rawValue` rather than typed per case, so a command cannot ship
    /// without an identifier and two commands cannot collide on one: adding a case to the
    /// enum is the whole of adding its identifier.
    var identifier: String {
        "board-card-\(rawValue)"
    }
}
