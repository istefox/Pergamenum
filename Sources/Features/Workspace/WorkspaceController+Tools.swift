import Foundation

/// What each of the eleven tools of SPEC §6.4 does when the board is tapped.
///
/// Declared here, beside `Tool`'s own `title`/`symbol`/`shortcut`, rather than in the
/// board view: the view used to hand-write one branch per tool and then restate, in a
/// trailing `if`, which tools are driven by dragging - two places that had to agree
/// about eleven cases. Here the classification is one value the view reads.
///
/// In an extension file rather than in `WorkspaceController.swift` only because that
/// file's type body is already over the length SwiftLint errors on; nothing here needs
/// stored state.
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
        case .note: .createSticky("")
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
