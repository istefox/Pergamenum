import SwiftUI

/// The sidebar toolbar row: "+ Nuova workspace", "Rinomina", "Elimina", "Espandi
/// tutto", "Comprimi tutto" (ADR-0022 §D8, §D9).
///
/// RED placeholder (Task 5, ADR-0022, plan
/// `2026-08-25-workspace-ui-creazione-board-toolbar-e-r`): only `canMutate(folder:)`
/// is real logic here, pinned by `Tests/WorkspaceBrowserToolbarTests.swift`. The five
/// buttons, their identifiers and `WorkspaceBrowser`'s new toolbar row/selection state
/// are Task 5 GREEN work for the coder - this file exists only so the target builds
/// while that test is red.
struct WorkspaceBrowserToolbar: View {
    var body: some View {
        // Placeholder: the five buttons and their `accessibilityIdentifier`s
        // (`workspace-new`, `workspace-rename`, `workspace-delete`,
        // `workspace-expand-all`, `workspace-collapse-all`) are Task 5 GREEN.
        EmptyView()
    }

    /// Whether "Rinomina"/"Elimina" may act on `folder` - false for the vault root
    /// (whose board is named after the vault itself, ADR-0022 §D9, R-09).
    ///
    /// Placeholder: deliberately wrong (always `false`), so
    /// `canMutateIsFalseForTheVaultRootAndTrueForAnOrdinaryFolder` fails on its
    /// assertion for `"01 Progetti"` rather than on a build error.
    static func canMutate(folder: String) -> Bool {
        false
    }
}
