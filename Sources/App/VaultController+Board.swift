import Foundation

/// The vault controller's half of the Workspace board it owns (ADR-0091 §D1).
extension VaultController {
    /// The open board's vault-relative path, nil with none open (ADR-0091 §D4). Derived from
    /// `openBoard`, never mirrored: a stored copy pushed up by the view went stale once the pane
    /// left. The window history reads it through `WindowPlace.destination`.
    var openBoardPath: String? { openBoard.board.isEmpty ? nil : openBoard.board }

    /// Points the owned board at the vault at `url`, letting go of the previous one's
    /// (ADR-0091 §D2). `detach()` runs first, while the store still names the vault being left,
    /// so a pending edit is flushed there and never into the next one (ADR-0052).
    func rebindBoard(to url: URL) {
        openBoard.detach()
        openBoard.attach(to: CanvasStore(root: url), thumbnails: thumbnails, vault: self)
    }
}
