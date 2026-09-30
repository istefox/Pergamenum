import SwiftUI

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D10 and §D11, plan
// docs/plans/contenitore.md, Task 6 - R-04, R-23, R-24, R-26.
//
// Beside `RootView.swift` rather than in it: that file sits at the edge of `file_length`.

extension RootView {
    @ViewBuilder
    var contenitorePane: some View {
        if vault.root == nil {
            needsVault("Il Contenitore archivia i documenti che metti nella cartella di raccolta: senza un vault non c'è dove tenerli.")
        } else {
            ContenitoreView()
        }
    }
}

extension View {
    /// Starts the Contenitore controller for each open vault and each change of Settings ›
    /// Contenitore, and brings the pane forward for a `pergamenum://contenitore` link.
    func contenitoreLifecycle() -> some View {
        modifier(ContenitoreLifecycle())
    }
}

/// What `.task(id:)` restarts the controller on: another vault, another session on the same
/// folder, or a changed drop folder or root.
private struct ContenitoreLifecycleKey: Equatable {
    let session: ObjectIdentifier?
    let settings: ContenitoreSettings
}

private struct ContenitoreLifecycle: ViewModifier {
    @Environment(VaultController.self) private var vault
    @Environment(Navigation.self) private var navigation
    @Environment(ContenitoreController.self) private var contenitore

    func body(content: Content) -> some View {
        content
            // The `pendingCanvas` shape (`RootView.body`): the link switches the pane here, where
            // Navigation lives. The controller is app-level, so it consumes the target at once
            // and the pane finds the selection already set when it appears.
            .onChange(of: vault.routeState.pendingContenitore) { _, pending in
                guard pending != nil else { return }
                navigation.pane = .contenitore
                contenitore.consumeRoute()
            }
            .task {
                guard vault.routeState.pendingContenitore != nil else { return }
                navigation.pane = .contenitore
                contenitore.consumeRoute()
            }
            .task(id: ContenitoreLifecycleKey(
                session: vault.session.map(ObjectIdentifier.init),
                settings: vault.settings.contenitore
            )) {
                await contenitore.start()
            }
    }
}
