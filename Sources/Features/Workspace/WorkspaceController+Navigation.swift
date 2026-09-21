import Foundation

/// Entering a folder from anywhere that names one (ADR-0053 §D2 #1, ADR-0025 §D5).
///
/// Three call sites used to spell this out by hand - the breadcrumb's ancestor segment
/// (`BoardChrome`), a folder card's double click (`BoardCardMenu`) and the editor hand-off
/// (`WorkspaceView.placePendingNote`) - and now share it, so the rule and the tests that pin it
/// live in one place.
extension WorkspaceController {
    /// The one rule §D5 gives every folder-to-board navigation: the board that folder
    /// unambiguously means is opened, and `.ambiguous`/`.notFound` selects the folder instead -
    /// never a board derived from its name (§D1). An empty `folder` is the vault root and selects
    /// `nil` in that second case, since `.folder("")` is never produced (§D3).
    ///
    /// Returns what the resolver said, for the one caller that also has to report it. The board
    /// list is read here, in the gesture, and never in a `body`: `allBoards()` walks the whole
    /// vault uncached.
    ///
    /// The breadcrumb's root segment does not come through here: it means "nothing selected", and
    /// a root holding exactly one board would resolve `.unique` and open it. Its `folder.isEmpty`
    /// guard stays at its own call site.
    @discardableResult
    func enter(folder: String) -> WorkspaceBoardResolution {
        let resolution = WorkspaceBoardResolver.board(inFolder: folder, among: store?.allBoards() ?? [])
        switch resolution {
        case .unique(let path): select(.board(path: path.value))
        case .ambiguous, .notFound: select(folder.isEmpty ? nil : .folder(folder))
        }
        return resolution
    }
}

extension WorkspaceBoardResolver {
    /// What the editor hand-off records when the folder of the note it sends does not mean
    /// exactly one board (ADR-0025 §D5, §F8), or `nil` when it does and there is nothing to say.
    /// The vault root is named in words rather than by an empty path.
    static func placementProblem(
        for note: String, inFolder folder: String, resolution: WorkspaceBoardResolution
    ) -> String? {
        let container = folder.isEmpty ? "la radice del vault" : "«\(folder)»"
        switch resolution {
        case .unique:
            return nil
        case .ambiguous:
            return "\(note): \(container) contiene più di una board, aprine una e riprova"
        case .notFound:
            return "\(note): \(container) non contiene nessuna board, creane una e riprova"
        }
    }
}
