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
/// that lives here - `canMutate(_:)` - is a pure function precisely so it can be
/// tested without a view.
struct WorkspaceBrowserToolbar: View {
    @Environment(\.theme) private var theme

    /// The row «Rinomina» and «Elimina» act on, whichever kind it is: a board file or a
    /// folder, with no fallback when nothing is selected (ADR-0025 §D8, ADR-0024 §D7).
    /// The two verbs dispatch on its case, and so does the wording below.
    let selection: WorkspaceSelection?
    let onNew: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    let onExpandAll: () -> Void
    let onCollapseAll: () -> Void

    var body: some View {
        HStack(spacing: theme.spacing(.xs)) {
            button("Nuova workspace", symbol: "plus", identifier: "workspace-new", action: onNew)
            button(
                "Rinomina \(targetNoun)", symbol: "pencil", identifier: "workspace-rename",
                enabled: Self.canMutate(selection), action: onRename
            )
            button(
                "Elimina \(targetNoun)", symbol: "trash", identifier: "workspace-delete",
                enabled: Self.canMutate(selection), action: onDelete
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

    /// The noun the two verbs are said with: a board row and a folder row are renamed and
    /// deleted by the same two buttons, under the same two identifiers, and only the
    /// wording tells them apart (ADR-0025 §D8) - 200 points of pane will not hold four
    /// buttons where two will do, and a UI test reads the identifier and never the words
    /// (CLAUDE.md).
    ///
    /// «cartella» with nothing selected, where both buttons are disabled anyway: a
    /// tooltip on a dead button names the kind of thing a click would have to pick first.
    private var targetNoun: String {
        selection?.hasBoard == true ? "board" : "cartella"
    }

    /// Whether «Rinomina»/«Elimina» may act on `selection` (ADR-0025 §D8, R-08):
    ///
    /// - `nil` → `false`, nothing selected and nothing to aim at (ADR-0024 §D7);
    /// - `.board` → `true`, a `.canvas` file is never the vault root;
    /// - `.folder(f)` → false for the vault root, whose rename would be a rename of the
    ///   vault (ADR-0022 §D9, R-09).
    ///
    /// That last branch is ADR-0022 §D9's root exemption, kept even though ADR-0025 §D2
    /// makes the root unselectable by construction - a guard whose precondition is «this
    /// state is unreachable» is a guard that stops being true the first time somebody
    /// makes it reachable, and this pane has had three chains in a row add rows to it.
    /// The slashes are trimmed first, the same normalisation `FolderFileOperations` makes
    /// on everything it is handed, so `"/"` names the root here too rather than passing
    /// for a folder called nothing.
    ///
    /// One rule, read by both surfaces (ADR-0023 §D1): this view's `.disabled`, and the
    /// tree row's context menu.
    static func canMutate(_ selection: WorkspaceSelection?) -> Bool {
        switch selection {
        case .none: return false
        case .board: return true
        case .folder(let folder):
            return !folder.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty
        }
    }
}
