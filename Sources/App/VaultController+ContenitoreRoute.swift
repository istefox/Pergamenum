import Foundation

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D10, plan
// docs/plans/contenitore.md, Task 6 - R-23, R-24.

/// What a `pergamenum://contenitore?id=` link asks the Contenitore pane to show.
enum ContenitoreRouteTarget: Equatable, Sendable {
    /// Select the document whose scheda is at this vault-relative path.
    case select(String)
    /// Open the pane with nothing selected: the id named no document (R-24).
    case none
}

/// The `.contenitore` route (ADR-0071 §D10), beside `VaultController+Routes.swift` so that
/// file keeps to the routes every pane shares.
extension VaultController {
    /// Resolves `id` through the note-id registry (ADR-0059), exactly as `note?id=` does, and
    /// sets `routeState.pendingContenitore`: `.select(path)` when the id names a scheda under
    /// the Contenitore root whose file is on disk, `.none` with one recorded problem otherwise.
    /// Either way the pane opens (`RootView` watches the value), so a link that misses still
    /// lands somewhere that says why.
    func selectContenitoreDocument(id: String) -> Bool {
        guard let session else {
            routeState.pendingContenitore = ContenitoreRouteTarget.none
            return false
        }
        let problem: String
        switch session.lookUpNote(id: id) {
        case .unknown:
            problem = "nessun documento del Contenitore con id \(id)"
        case .unreadable:
            problem = "il registro degli id delle note (\(VaultLayout.noteIDsFile)) non è leggibile: "
                + "impossibile aprire il documento con id \(id)"
        case .found(let path):
            let root = session.settings.contenitore.root
            let isScheda = session.index.schede(underRoot: root).contains { $0.relativePath == path }
            guard isScheda, session.exists(path) else {
                problem = isScheda
                    ? "il documento con id \(id) era in \(path), che non esiste più"
                    : "l'id \(id) indica \(path), che non è un documento del Contenitore"
                break
            }
            routeState.pendingContenitore = .select(path)
            return true
        }
        recordProblem(problem)
        routeState.pendingContenitore = ContenitoreRouteTarget.none
        return false
    }

    /// The pending target, cleared as it is read: the pane acts on a link once.
    func consumePendingContenitoreRoute() -> ContenitoreRouteTarget? {
        defer { routeState.pendingContenitore = nil }
        return routeState.pendingContenitore
    }
}
