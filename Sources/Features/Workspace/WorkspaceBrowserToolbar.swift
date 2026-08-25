import SwiftUI

/// The sidebar's second row: the three verbs of R-01 and the two tree commands
/// (ADR-0022 §D8, §D9).
///
/// A row of its own, below `WorkspaceBrowser`'s header rather than inside it. The header
/// carries `.accessibilityElement(children: .contain)` and its own identifier, and on
/// macOS an identifier on a container reaches its descendants: a button placed in there
/// risks answering to `workspace-browser-header` instead of to its own identifier, which
/// is the only handle a UI test is allowed to use (ADR-0022 §F9, CLAUDE.md).
///
/// It decides nothing. The verbs are closures the browser passes in, and the one rule
/// that lives here - `canMutate(folder:)` - is a pure function precisely so it can be
/// tested without a view.
struct WorkspaceBrowserToolbar: View {
    @Environment(\.theme) private var theme

    /// The folder «Rinomina» and «Elimina» act on: the selected row, or the open board's
    /// own folder when nothing has been clicked (ADR-0022 §D9).
    let target: String
    let onNew: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    let onExpandAll: () -> Void
    let onCollapseAll: () -> Void

    var body: some View {
        HStack(spacing: theme.spacing(.xs)) {
            button("Nuova workspace", symbol: "plus", identifier: "workspace-new", action: onNew)
            button(
                "Rinomina", symbol: "pencil", identifier: "workspace-rename",
                enabled: Self.canMutate(folder: target), action: onRename
            )
            button(
                "Elimina", symbol: "trash", identifier: "workspace-delete",
                enabled: Self.canMutate(folder: target), action: onDelete
            )
            Spacer()
            button(
                "Espandi tutto", symbol: "rectangle.expand.vertical",
                identifier: "workspace-expand-all", action: onExpandAll
            )
            button(
                "Comprimi tutto", symbol: "rectangle.compress.vertical",
                identifier: "workspace-collapse-all", action: onCollapseAll
            )
        }
        .padding(.horizontal, theme.spacing(.s))
        .padding(.bottom, theme.spacing(.xs))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Comandi del Workspace")
        .accessibilityIdentifier("workspace-browser-toolbar")
    }

    /// One toolbar button: an SF Symbol, its Italian name as both tooltip and
    /// accessibility label, and its identifier.
    ///
    /// Icon-only because the pane is 200 points wide and five labelled buttons do not fit
    /// across it. The words are still there - in the tooltip, which is where a person
    /// reads them, and in the accessibility label. A UI test reads the identifier and
    /// never the words (CLAUDE.md), which is what makes that split safe.
    private func button(
        _ title: String,
        symbol: String,
        identifier: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 22, height: 22)
                .foregroundStyle(theme.color(enabled ? .textSecondary : .textTertiary))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        // `.plain` draws a disabled button exactly like an enabled one, so the dimming
        // has to be asked for - the same pair `BoardToolbar` uses for a locked tool.
        .opacity(enabled ? 1 : 0.4)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }

    /// Whether «Rinomina»/«Elimina» may act on `folder` - false for the vault root, whose
    /// board is named after the vault itself and whose rename would be a rename of the
    /// vault (ADR-0022 §D9, R-09).
    ///
    /// The slashes are trimmed first, the same normalisation `FolderFileOperations` makes
    /// on everything it is handed, so `"/"` names the root here too rather than passing
    /// for a folder called nothing.
    static func canMutate(folder: String) -> Bool {
        !folder.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty
    }
}
