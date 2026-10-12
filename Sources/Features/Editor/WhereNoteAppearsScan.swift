import Foundation
import Observation

// ADR-0084 §D6 (PG-386, N3 session C).

/// The model behind «Dove compare»: resting until asked, then the boards and the pratiche that
/// point at the note.
@MainActor
@Observable
final class WhereNoteAppearsScan {
    enum State: Equatable {
        case resting
        case scanning
        case found(NoteAppearances)
    }

    private(set) var state: State = .resting

    @ObservationIgnored private let vault: VaultController
    let notePath: String

    init(vault: VaultController, notePath: String) {
        self.vault = vault
        self.notePath = notePath
    }

    /// Reads the files, or answers from the memo when `again` is false and the index has not
    /// moved. The read runs on the main actor, as the session does, so the spinner gets one turn
    /// of the run loop to be drawn before it starts: the shape of the mention scan.
    func scan(again: Bool) async {
        guard state != .scanning else { return }
        state = .scanning
        await Task.yield()
        state = .found(vault.noteAppearances(ofNoteAt: notePath, rescan: again))
    }
}
