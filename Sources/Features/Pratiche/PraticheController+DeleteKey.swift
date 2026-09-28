import Foundation

// PG-298, ADR-0070 §D2 (`docs/plans/pg-298-timeline-backspace-exclude.md`, Task 2) - R-01,
// R-04, R-06: the one door Backspace goes through, in a file of its own rather than in
// `PraticheController.swift`, which already sits against SwiftLint's 400-line `file_length`
// warning at 641 lines (`selectedEntryID` stays a plain `var` there for this reason).

extension PraticheController {
    /// Backspace's own door (ADR-0070 §D2): applies `PraticaTimelineModel.deleteKeyTarget`
    /// to `filteredTimeline`, then clears `selectedEntryID` only when a target was found -
    /// leaving it untouched on a refusal, so a stray Backspace over a manual entry or a
    /// hidden row does not silently drop the selection (R-04).
    ///
    /// Clearing on a hit, rather than moving the selection to a neighbour, is what makes one
    /// press exclude at most one message (R-06): a key repeat or a second press before the
    /// timeline reloads finds `selectedEntryID` already `nil` and answers `nil` again.
    func takeDeleteKeyTarget() -> PraticaTimelineEntry? {
        guard let target = PraticaTimelineModel.deleteKeyTarget(
            selectedID: selectedEntryID, in: filteredTimeline
        ) else { return nil }
        selectedEntryID = nil
        return target
    }
}
