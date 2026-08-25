import SwiftUI

/// The selected card's commands, as a floating capsule over the board (ADR-0023 §D7).
///
/// Not a window-toolbar group: the Workspace already contributes four items up there, and
/// five more that appear and vanish on every click would re-lay-out Annulla, Ripeti and
/// Anteprima under the pointer. This is the same object as `BoardPenControls`, which comes
/// and goes with the Disegno tool in this exact slot - a contextual cluster that follows
/// what is selected rather than which tool is held.
///
/// Every control is drawn from `CardCommand.available(for:isCroppable:hasCrop:)` and
/// performed through `BoardCardActions`, so the bar and the card's own context menu offer
/// the same commands, under the same titles and icons, doing the same thing
/// (ADR-0023 §D1, §D8).
///
/// Plan `docs/superpowers/plans/2026-08-25-universal-command-surface-parity.md`, Task 3
/// (R-06, R-07, R-13).
struct BoardCardControls: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    let workspace: WorkspaceController

    /// Whether the bar is shown at all: exactly one selected card, and nothing otherwise
    /// (R-07).
    ///
    /// A pure function of the selection, which is what makes "hidden, not disabled"
    /// testable without a window - and there is no bar to disable, so the rule is not one
    /// anybody has to remember to apply. A multi-selection keeps the context menu, whose
    /// `targets(_:)` rule already decides correctly between "the whole selection" and
    /// "just this card"; a bar over two cards would have to reimplement that and could
    /// only get it wrong.
    static func isShown(selection: Set<String>) -> Bool {
        selection.count == 1
    }

    var body: some View {
        if let node = selectedNode {
            let actions = BoardCardActions(workspace: workspace, vault: vault)
            HStack(spacing: theme.spacing(.xs)) {
                ForEach(actions.commands(for: node), id: \.self) { command in
                    control(command, node: node, actions: actions)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.color(.textSecondary))
            .padding(.horizontal, theme.spacing(.s))
            .padding(.vertical, theme.spacing(.xs))
            .background(theme.color(.surfaceRaised))
            .clipShape(Capsule())
            .themedShadow(.card)
            .accessibilityIdentifier("board-card-bar")
        }
    }

    /// The one selected card, or nothing. Read through `isShown` rather than beside it, so
    /// the rule that decides whether the bar exists is the rule that decides what it acts
    /// on.
    private var selectedNode: CanvasNode? {
        guard Self.isShown(selection: workspace.selection),
              let id = workspace.selection.first
        else { return nil }
        return workspace.document.node(id: id)
    }

    /// One control per command, icon-only: the bar is a row over the board, and the title
    /// is on the tooltip. `Colore` and `Ridimensiona` carry an argument, so they are the
    /// same submenus the context menu builds; `Ritaglia` collapses its group into one
    /// control here, where a row of icons has no room for a button per crop state.
    @ViewBuilder
    private func control(
        _ command: CardCommand, node: CanvasNode, actions: BoardCardActions
    ) -> some View {
        switch command {
        case .color:
            submenu(command) { BoardCardMenuItems.colorItems(node: node, actions: actions) }
        case .resize:
            submenu(command) { BoardCardMenuItems.sizeItems(node: node, actions: actions) }
        case .crop:
            submenu(command) { BoardCardMenuItems.cropItems(node: node, actions: actions) }
        case .fitToCrop, .removeCrop:
            // Drawn inside «Ridimensiona» and «Ritaglia» respectively, exactly where the
            // context menu draws them: nothing of their own on the bar.
            EmptyView()
        case .open, .copyLink, .duplicate, .delete:
            Button {
                actions.run(command, on: node)
            } label: {
                Image(systemName: command.symbol)
            }
            .help(command.title)
            .accessibilityLabel(command.title)
            .accessibilityIdentifier(command.identifier)
        }
    }

    private func submenu(
        _ command: CardCommand, @ViewBuilder content: () -> some View
    ) -> some View {
        Menu {
            content()
        } label: {
            Image(systemName: command.symbol)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(command.title)
        .accessibilityLabel(command.title)
        .accessibilityIdentifier(command.identifier)
    }
}
