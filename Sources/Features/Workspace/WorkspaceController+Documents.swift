import CoreGraphics
import Foundation

/// The Workspace «Documento» sheet's creation: the note and its card, and no tab (n1-seams
/// R-10, R-18).
extension WorkspaceController {
    /// What «Crea» in the «Documento» sheet came to: the note's path, or the sentence the
    /// sheet shows in place, so the person can change the title and try again.
    enum DocumentCreation: Equatable {
        case created(path: String)
        case failed(String)
    }

    /// Creates a note in the open board's folder and places its card at `point`, opening no tab:
    /// the person stays on the board (n1-seams R-10). The note goes through
    /// `VaultController.createNote`, so it is born like every other topic-less note (a capture,
    /// ADR-0080) and the sidebar rescans.
    ///
    /// The board and its folder are read before the write and checked again after it by
    /// `placeCreatedNote` (ADR-0043 §D7): a board opened meanwhile gets no card for a note made
    /// in the first one's folder. The note is still made, so the answer is still `.created`.
    func createDocument(
        titled title: String, at point: CGPoint, through vault: VaultController
    ) async -> DocumentCreation {
        let targetBoard = board
        let targetFolder = folder
        do {
            let path = try await vault.createNote(
                title: title, in: targetFolder, date: .today, opening: false
            )
            _ = placeCreatedNote(path, title: title, at: point, openedOn: targetBoard)
            return .created(path: path)
        } catch {
            return .failed(ConformanceText.creationFailure(error))
        }
    }
}
