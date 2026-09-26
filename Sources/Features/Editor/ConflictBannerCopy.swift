import Foundation

/// What the conflict banner says, decided from the pending change it answers (ADR-0064 §D5).
///
/// Lifted out of the view's `body` so a unit test can read it (ADR-0053's seam shape): the
/// banner renders these three strings and decides nothing itself.
///
/// A deletion never offers «Ricarica da disco» (SPEC R-04): there is nothing on disk to
/// reload, so the first button says what `acceptExternalChange()` does for it - close the tab
/// and leave the file deleted.
struct ConflictBannerCopy: Equatable {
    let message: String
    let acceptLabel: String
    let keepLabel: String

    init(pending: VaultSession.ExternalChange.Content) {
        switch pending {
        case .text:
            message = "La nota è cambiata su disco mentre la stavi modificando."
            acceptLabel = "Ricarica da disco"
            keepLabel = "Tieni la mia versione"
        case .deleted:
            message = "La nota è stata eliminata dal disco mentre la stavi modificando."
            acceptLabel = "Scarta ed elimina"
            keepLabel = "Tieni la mia versione"
        }
    }
}
