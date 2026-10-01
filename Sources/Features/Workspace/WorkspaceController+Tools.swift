import Foundation

/// The board's tool catalogue and its tap classification: `Tool` itself, with its
/// `title`/`symbol`/`shortcut`, and what each tool does when the board is tapped - an
/// extension file of `WorkspaceController` (ADR-0045 §D2), holding no stored state.
///
/// `Tool` is declared inside `extension WorkspaceController`, so it is still spelled
/// `WorkspaceController.Tool` everywhere it is read.
extension WorkspaceController {
    /// The tools of SPEC §6.4, ten of the eleven it lists: ADR-0027 §D8 unified Nota
    /// into Testo, so `.text` is the only tool of that family and the `n` key is free.
    /// `forms` is excluded from v1 and kept only so the toolbar layout does not have to
    /// be redone in v2.
    enum Tool: String, CaseIterable, Identifiable, Sendable {
        case select, text, folder, image, document, link, todo, forms, drawing, arrow

        var id: String { rawValue }

        var isAvailable: Bool { self != .forms }

        /// Single-key shortcut. Tools without one are not reachable from the keyboard.
        var shortcut: String? {
            switch self {
            case .select: "v"
            case .text: "t"
            case .folder: "f"
            case .image: "i"
            case .document: "d"
            case .link: "l"
            case .todo: "k"
            case .drawing: "p"
            case .arrow: "a"
            case .forms: nil
            }
        }

        var title: String {
            switch self {
            case .select: "Seleziona"
            case .text: "Testo"
            case .folder: "Cartella"
            case .image: "Immagine"
            case .document: "Documento"
            case .link: "Link"
            case .todo: "To Do"
            case .forms: "Moduli (v2)"
            case .drawing: "Disegno"
            case .arrow: "Freccia"
            }
        }

        var symbol: String {
            switch self {
            case .select: "cursorarrow"
            case .text: "textformat"
            case .folder: "folder"
            case .image: "photo"
            case .document: "doc.text"
            case .link: "link"
            case .todo: "checklist"
            case .forms: "rectangle.on.rectangle.slash"
            case .drawing: "pencil.tip"
            case .arrow: "arrow.up.right"
            }
        }
    }
}

/// What each of the ten tools of SPEC §6.4 does when the board is tapped (eleven in the
/// SPEC; ADR-0027 §D8 unified Nota into Testo).
///
/// Declared here, beside `Tool`'s own `title`/`symbol`/`shortcut`, rather than in the
/// board view: the view used to hand-write one branch per tool and then restate, in a
/// trailing `if`, which tools are driven by dragging - two places that had to agree
/// about eleven cases. Here the classification is one value the view reads.
extension WorkspaceController.Tool {
    enum TapBehaviour {
        case selectNothing
        /// A sticky note seeded with this text.
        case createSticky(String)
        case createFreeText
        /// A naming sheet, which creates the item once confirmed.
        case sheet(NewCanvasItemSheet.Kind)
        case importPanel
        /// Drawn by dragging rather than by tapping: a tap does nothing *and* the tool
        /// is not reset afterwards, which would end the gesture in progress.
        case dragDriven
        /// Not in v1 (`forms`): a tap does nothing, but the tool still resets.
        case unavailable
    }

    var tapBehaviour: TapBehaviour {
        switch self {
        case .select: .selectNothing
        case .todo: .createSticky("- [ ] ")
        case .text: .createFreeText
        case .folder: .sheet(.folder)
        case .link: .sheet(.link)
        case .document: .sheet(.note)
        case .image: .importPanel
        // The drawing layer takes over the board while its tool is active; the arrow is
        // drawn by dragging between two cards.
        case .drawing, .arrow: .dragDriven
        case .forms: .unavailable
        }
    }

    /// Whether one use of this tool ends by dragging rather than by tapping, so
    /// `finishToolUse` must not reset it (SPEC §6.4).
    var isDragDriven: Bool {
        if case .dragDriven = tapBehaviour { return true }
        return false
    }
}
