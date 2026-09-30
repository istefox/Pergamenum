import Foundation

/// What «Salva tutto» did at quit, by tab id (ADR-0073 §D5).
struct QuitSaveReport: Equatable, Sendable {
    var saved: [NoteTab.ID] = []
    var failed: [NoteTab.ID] = []
    /// Left unwritten because the conflict banner was waiting, from the start or because an
    /// earlier save in the same batch landed on its path (F5).
    var conflicted: [NoteTab.ID] = []
    /// Left unwritten because the tab was opened from a vault other than the open one: its
    /// path would name a different file here (ADR-0073 §D5, departure 13).
    var foreign: [NoteTab.ID] = []
}

/// The quit's bulk save (ADR-0073 §D5). The question and the reply are `QuitCoordinator`'s;
/// this is only the writing, through the same door Cmd+S uses.
extension VaultController {
    /// Saves, in the review's order, each entry that is **still** dirty and **not**
    /// conflicted, and reports what it did.
    ///
    /// `columns` is re-read before every write (ADR-0043 §D7: a set read before an `await` is
    /// a filter, not a guard). A conflicted tab is never written by the bulk answer - the
    /// other writer's bytes are the person's to decide on - and neither is a tab of a previous
    /// vault, whose path names a different file in this one (`saveTab` refuses it, for every
    /// caller). Conflicted includes a tab whose conflict was raised by an earlier save of this
    /// same loop: the same note dirty in both columns with different text. A failure is
    /// reported and the loop goes on, so every tab that can be saved is.
    func saveForQuit(_ review: QuitReview) async -> QuitSaveReport {
        var report = QuitSaveReport()
        for entry in review.entries {
            guard let tab = tab(withID: entry.tabID), tab.note.hasUnsavedChanges else { continue }
            // `saveTab` refuses a previous vault's tab and records the problem itself; the flag
            // only decides which list the refusal goes on.
            let foreign = tab.isFromPreviousVault
            if !foreign, tab.note.externalChangePending != nil {
                report.conflicted.append(entry.tabID)
                continue
            }
            switch await saveTab(entry.tabID) {
            case .saved: report.saved.append(entry.tabID)
            case .failed:
                if foreign { report.foreign.append(entry.tabID) } else { report.failed.append(entry.tabID) }
            case .clean: break
            }
        }
        return report
    }
}
