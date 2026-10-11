import CoreGraphics
import Foundation

/// The Workspace new-item sheet's two creation doors: the «Documento» kind, the note and its
/// card with no tab (n1-seams R-10, R-18), and the folder kind, the folder and its card with the
/// failure worded for the sheet (note-workflow R-11).
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
            // Shown in the sheet and kept in the problem list as well (note-workflow R-11).
            let sentence = ConformanceText.creationFailure(error)
            recordProblem(sentence)
            return .failed(sentence)
        }
    }

    /// The folder kind of the sheet: makes the folder and its card, and answers the sentence the
    /// sheet shows when it could not, nil when it was made (note-workflow R-11). The sentence is
    /// recorded in the problem list too, and the sheet stays open on it, the note kind's route.
    /// Every error keeps its own text: an invalid name (`FileOperationError.invalidTitle`)
    /// describes itself as the note kind words it (`ConformanceText`), and the others
    /// (`CanvasStore.StoreError`, `VaultBoundary.Violation`, a file-system failure) as they do.
    func createFolderFromSheet(named name: String, at point: CGPoint) -> String? {
        do {
            _ = try createFolder(named: name, at: point)
            return nil
        } catch {
            let sentence = "\(error)"
            recordProblem(sentence)
            return sentence
        }
    }
}
