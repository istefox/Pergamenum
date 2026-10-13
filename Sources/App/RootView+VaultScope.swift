import SwiftUI

// PG-409: the window state on `Navigation` that names a path of the open notes folder, cleared when
// another folder replaces it or it closes. Beside `RootView.swift` and `Navigation.swift` rather
// than in them, for the reason `RootView+Contenitore.swift` gives: both sit at the edge of
// `file_length`.

extension Navigation {
    /// Forgets what names a path of the notes folder being left (`vaultScopedNavigation()`):
    /// the tree's lit rows (n1-seams R-11), the «Da classificare» selection, and every request a
    /// sheet holds. Each of those is built from the folder left and answered against the next
    /// session, where its confirm would act on the same relative path (PG-409):
    /// - `classifying`, `praticaLinkRequest` (`.pratica(path:)`, `.message(notePath:)`) and
    ///   `taskPickingBoard` / `taskPickingCategory` (`TaskItem.sourcePath` and line) name files;
    /// - `linkChoice` opens `.open(path:)` and anchors a creation beside `sourcePath`;
    /// - `categoryEditorTarget` carries the whole `Category`, saved by slug over whatever the next
    ///   registry holds under it.
    ///
    /// `categoryLinkingNote` carries a slug and a name only and its note is chosen from the new
    /// vault's live list, so no path of the folder left is written through it; it is cleared too,
    /// because the sheet's title would name a category the new registry may not hold.
    ///
    /// Nothing disables «Apri cartella note…» or «Cartelle recenti» while a sheet is up, and a
    /// sheet is modal to its window only, so either can switch folders under it.
    func forgetVaultPaths() {
        noteTreeSelection = []
        unfiledSelection = nil
        classifying = nil
        praticaLinkRequest = nil
        taskPickingBoard = nil
        taskPickingCategory = nil
        linkChoice = nil
        categoryEditorTarget = nil
        categoryLinkingNote = nil
    }
}

extension View {
    /// Clears `Navigation`'s paths of the folder being left whenever the open folder changes
    /// (`Navigation.forgetVaultPaths()`).
    ///
    /// Here and not in `VaultController.switchVault(to:ask:)`, where `creationUndo` and
    /// `extraction` are reset: the controller holds no `Navigation`. It watches `root?.vaultKey`,
    /// the spelling `switchVault` itself compares by, and not `root`: a session keeps the URL it
    /// was opened with, so reopening the same folder through a link or a trailing slash moves
    /// `root` and not the folder. A switch to a different folder and `close()` move the key.
    func vaultScopedNavigation() -> some View {
        modifier(VaultScopedNavigation())
    }
}

private struct VaultScopedNavigation: ViewModifier {
    @Environment(VaultController.self) private var vault
    @Environment(Navigation.self) private var navigation

    func body(content: Content) -> some View {
        content.onChange(of: vault.root?.vaultKey) { _, _ in navigation.forgetVaultPaths() }
    }
}
