import Foundation

/// What the Note pane's top bar says about the focused note's save state (ADR-0073 §D10).
///
/// A note is saved explicitly (ADR-0012 §D3), so a dirty note is **not saved**, not
/// "saving": the bar used to borrow the board's «Salvataggio…», which is true of a board's
/// ~1 s autosave and was read as an autosave in progress on a note nothing was saving
/// (PG-326). The board's own indicator in `BoardChrome` is untouched. `ConflictBannerCopy`'s
/// shape (ADR-0053): the view renders these and decides nothing.
struct NoteSaveIndicator: Equatable {
    let label: String
    let symbol: String

    init(hasUnsavedChanges: Bool) {
        if hasUnsavedChanges {
            label = "Non salvato"
            symbol = "arrow.triangle.2.circlepath"
        } else {
            label = "Salvato"
            symbol = "checkmark.circle"
        }
    }
}
