import SwiftUI

/// The Note sidebar's second row: the two creations and the two mutating verbs, mirroring
/// `WorkspaceBrowserToolbar` byte for byte in shape (2026-08-28, toolbar-parity chain).
///
/// A row of its own, below `NoteListPane`'s header rather than inside it, for the same
/// reason `WorkspaceBrowserToolbar` sits outside `WorkspaceBrowser`'s header: the header
/// carries `.accessibilityElement(children: .contain)` and its own identifier, which on
/// macOS reaches every descendant - a button inside it would answer to
/// `note-browser-header` instead of to its own identifier.
///
/// It decides nothing. The verbs are closures `NoteListPane` passes in, and `canMutate(_:)`
/// is a pure function precisely so it can be tested without a view.
struct NoteListToolbar: View {
    @Environment(\.theme) private var theme

    /// The row «Rinomina» and «Elimina» act on: a note or a folder, with no fallback when
    /// nothing is selected. Mirrors `WorkspaceSelection`'s two-case shape.
    enum Selection: Equatable {
        case note(String)
        case folder(String)
    }

    let selection: Selection?
    let onNew: () -> Void
    let onNewFolder: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    let onExpandAll: () -> Void
    let onCollapseAll: () -> Void

    var body: some View {
        HStack(spacing: theme.spacing(.xs)) {
            button("Nuova nota", symbol: "plus", identifier: "note-toolbar-new", action: onNew)
            button(
                "Nuova cartella", symbol: "folder.badge.plus",
                identifier: "note-toolbar-new-folder", action: onNewFolder
            )
            button(
                "Rinomina \(targetNoun)", symbol: "pencil", identifier: "note-toolbar-rename",
                enabled: Self.canMutate(selection), action: onRename
            )
            button(
                "Elimina \(targetNoun)", symbol: "trash", identifier: "note-toolbar-delete",
                enabled: Self.canMutate(selection), action: onDelete
            )
            Spacer()
            button(
                "Espandi tutto", symbol: "rectangle.expand.vertical",
                identifier: "note-toolbar-expand-all", action: onExpandAll
            )
            button(
                "Comprimi tutto", symbol: "rectangle.compress.vertical",
                identifier: "note-toolbar-collapse-all", action: onCollapseAll
            )
        }
        .padding(.horizontal, theme.spacing(.s))
        .padding(.bottom, theme.spacing(.xs))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Comandi delle Note")
        .accessibilityIdentifier("note-list-toolbar")
    }

    /// One toolbar button, icon-only for the same width reason `WorkspaceBrowserToolbar`
    /// gives - the words live in the tooltip and the accessibility label, never on screen;
    /// a UI test reads the identifier and never the words (CLAUDE.md).
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
        .opacity(enabled ? 1 : 0.4)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }

    /// The noun the two verbs are said with: a note row and a folder row are renamed and
    /// deleted by the same two buttons, and only the wording tells them apart.
    private var targetNoun: String {
        switch selection {
        case .folder: "cartella"
        default: "nota"
        }
    }

    /// Whether «Rinomina»/«Elimina» may act on `selection`:
    /// - `nil` → `false`, nothing selected;
    /// - `.note` → `true`;
    /// - `.folder(f)` → `true` unless `f` is the vault root, kept for shape parity with
    ///   `WorkspaceBrowserToolbar.canMutate` even though the Note tree draws no root row
    ///   to select in the first place.
    static func canMutate(_ selection: Selection?) -> Bool {
        switch selection {
        case .none: return false
        case .note: return true
        case .folder(let folder):
            return !folder.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty
        }
    }
}
