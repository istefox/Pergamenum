import SwiftUI

/// What each `CardCommand` actually does, in one place.
///
/// `CardCommand` names a command once (ADR-0023 §D1); this is the other half of the same
/// rule. The card's own context menu (`BoardCardMenuItems`) and the board's contextual
/// command bar (`BoardCardControls`) call the *same* body rather than two bodies that
/// happen to agree today - a menu entry and a toolbar button that delete different sets of
/// cards is exactly the drift this feature exists to close.
///
/// Every body below was moved out of `BoardContentLayer`, which drew the only surface
/// there was, and is otherwise unchanged - including which cards each one acts on.
///
/// Plan `docs/superpowers/plans/2026-08-25-universal-command-surface-parity.md`, Task 3
/// (R-06, R-13).
@MainActor
struct BoardCardActions {
    let workspace: WorkspaceController
    let vault: VaultController

    // MARK: Applicability

    /// The cards an action applies to: the whole selection when the card is part of it,
    /// otherwise just this one. Acting on the selection when the user right-clicked
    /// something outside it is how a context menu deletes the wrong thing.
    func targets(_ node: CanvasNode) -> Set<String> {
        workspace.selection.contains(node.id) ? workspace.selection : [node.id]
    }

    /// Whether "Ritaglia" belongs on this card at all (ADR-0020 D8): a raster image, at a
    /// zoom where there is something on screen to aim at.
    func isCroppable(_ node: CanvasNode) -> Bool {
        guard case .file(let path, _) = node.kind else { return false }
        return CanvasCrop.isCroppable(path: path) && !BoardGeometry.drawsPlaceholder(at: workspace.zoom)
    }

    func hasCrop(_ node: CanvasNode) -> Bool {
        CanvasCrop.read(from: node) != nil
    }

    /// The commands this card offers, in menu order. Both surfaces ask this rather than
    /// deriving their own list, which is the whole of ADR-0023 §D8.
    func commands(for node: CanvasNode) -> [CardCommand] {
        CardCommand.available(for: node, isCroppable: isCroppable(node), hasCrop: hasCrop(node))
    }

    // MARK: Performing

    /// The commands a plain button invokes - everything except the two the surfaces draw
    /// as submenus, which carry an argument (a colour, a size) the command alone does not.
    func run(_ command: CardCommand, on node: CanvasNode) {
        switch command {
        case .open:
            open(node)
        case .copyLink:
            copyLink(to: node)
        case .crop:
            workspace.beginCrop(nodeID: node.id, drawnSize: workspace.displayFrame(for: node).size)
        case .removeCrop:
            workspace.removeCrop(nodeIDs: targets(node))
        case .fitToCrop:
            Task { await fitToCrop(node) }
        case .duplicate:
            workspace.duplicate(nodeIDs: targets(node))
        case .delete:
            workspace.delete(nodeIDs: targets(node))
        case .color, .resize:
            // Both surfaces draw these two as a `Menu`, never as a button, so reaching
            // here means a surface rendered one as something it is not.
            assertionFailure("\(command) carries an argument and is invoked through its submenu")
        }
    }

    func setColor(preset: Int?, on node: CanvasNode) {
        workspace.setColor(preset.map { .preset($0) }, forNodeIDs: targets(node))
    }

    func resize(_ node: CanvasNode, to size: CGSize) {
        for id in targets(node) {
            workspace.resize(nodeID: id, to: size)
        }
    }

    /// "Adatta al ritaglio" (ADR-0020 D4): resizes each target that carries a crop to the
    /// height its own cropped region implies at its current width, so the card stops
    /// letterboxing without ever moving the crop itself. Needs the source image's own
    /// pixel size, which only `ThumbnailStore` knows - the one part of this action that
    /// cannot be synchronous.
    func fitToCrop(_ node: CanvasNode) async {
        guard let store = workspace.thumbnails else { return }
        for id in targets(node) {
            guard let target = workspace.document.node(id: id),
                  case .file(let path, _) = target.kind,
                  let crop = CanvasCrop.read(from: target)
            else { continue }
            let task = await store.thumbnail(for: path, width: target.width)
            guard let image = await task.value else { continue }
            let croppedAspect = (crop.width * image.size.width) / (crop.height * image.size.height)
            guard croppedAspect.isFinite, croppedAspect > 0 else { continue }
            workspace.resize(nodeID: id, to: CGSize(width: target.width, height: target.width / croppedAspect))
        }
    }

    /// Puts a `pergamenum://canvas?file=…&node=…` link on the pasteboard, so a card can be
    /// linked to from Obsidian, DEVONthink or Mail (SPEC §9).
    func copyLink(to node: CanvasNode) {
        // The path of the board actually open, not one derived from its folder
        // (ADR-0025 §D1) - so the link reopens this `.canvas` whatever it is called.
        guard let url = PergamenumLink.canvas(path: workspace.board, nodeID: node.id) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    /// Double click, and «Apri»: enter a folder's board, or open the file the card points
    /// at.
    func open(_ node: CanvasNode) {
        if let subfolder = workspace.subfolder(for: node) {
            // TODO(ADR-0025 Task 4): the resolver decides which board this folder means -
            // `.unique` opens it, `.ambiguous` and `.notFound` stop here (§D5). Selecting
            // is that rule's safe half and all this task needs: a folder no longer
            // implies a board file, so opening one by name would open a board that may
            // not exist.
            workspace.select(.folder(subfolder))
            return
        }
        switch node.kind {
        case .file(let path, _):
            if path.lowercased().hasSuffix(".svg"), workspace.editDrawing(nodeID: node.id) {
                // One of our own drawings: reopen the ink rather than the image.
                workspace.tool = .drawing
            } else if path.hasSuffix(".md") {
                vault.openNote(at: path)
            } else if let root = vault.root {
                NSWorkspace.shared.open(root.appending(path: path))
            }
        case .link(let url):
            if let target = URL(string: url) { NSWorkspace.shared.open(target) }
        case .text, .group, .unknown:
            break
        }
    }
}

/// The card's context menu, and the two submenus the command bar shares with it.
///
/// Built by iterating `CardCommand.available(for:isCroppable:hasCrop:)` rather than by
/// listing entries: the titles, the icons and the applicability rules come from the
/// catalogue, so the menu and the bar cannot list a card's commands differently
/// (ADR-0023 §D8).
@MainActor
enum BoardCardMenuItems {
    /// Every entry the card offers, in the order `BoardContentLayer` drew them before this
    /// list came from the catalogue - «Adatta al ritaglio» inside «Ridimensiona», «Rimuovi
    /// ritaglio» right after «Ritaglia» - plus «Duplica», this feature's one net-new
    /// command (ADR-0023 §D11).
    @ViewBuilder
    static func menu(for node: CanvasNode, actions: BoardCardActions) -> some View {
        ForEach(actions.commands(for: node), id: \.self) { command in
            if separatorPrecedes(command) { Divider() }
            item(command, node: node, actions: actions)
        }
    }

    /// The three groups the menu has always had - what the card is, what it looks like,
    /// what happens to it - now expressed once instead of at three literal `Divider()`s.
    private static func separatorPrecedes(_ command: CardCommand) -> Bool {
        switch command {
        case .color, .crop, .duplicate: true
        default: false
        }
    }

    @ViewBuilder
    private static func item(
        _ command: CardCommand, node: CanvasNode, actions: BoardCardActions
    ) -> some View {
        switch command {
        case .color:
            Menu(command.title) { colorItems(node: node, actions: actions) }
        case .resize:
            Menu(command.title) { sizeItems(node: node, actions: actions) }
        case .fitToCrop:
            // Drawn inside «Ridimensiona» by `sizeItems`, which is where the card menu has
            // always drawn it: nothing of its own at the top level.
            EmptyView()
        case .open, .copyLink, .crop, .removeCrop, .duplicate, .delete:
            Button(command.title) { actions.run(command, on: node) }
        }
    }

    /// «Colore»: no colour, then the six JSON Canvas presets (SPEC §6.2).
    @ViewBuilder
    static func colorItems(node: CanvasNode, actions: BoardCardActions) -> some View {
        Button("Nessuno") { actions.setColor(preset: nil, on: node) }
        ForEach(1...6, id: \.self) { preset in
            Button(BoardContentLayer.colorNames[preset - 1]) {
                actions.setColor(preset: preset, on: node)
            }
        }
    }

    /// «Ridimensiona»: the presets of SPEC §10, and «Adatta al ritaglio» below them on a
    /// card that carries a crop.
    @ViewBuilder
    static func sizeItems(node: CanvasNode, actions: BoardCardActions) -> some View {
        ForEach(BoardContentLayer.sizePresets, id: \.name) { preset in
            Button(preset.name) { actions.resize(node, to: preset.size) }
        }
        if actions.hasCrop(node) {
            Divider()
            Button(CardCommand.fitToCrop.title) { actions.run(.fitToCrop, on: node) }
        }
    }

    /// «Ritaglia», as the command bar draws it: the crop group collapsed into one control,
    /// so the bar stays a row of icons rather than growing a button per crop state. The
    /// context menu keeps both entries at its own top level, where there is room for them.
    @ViewBuilder
    static func cropItems(node: CanvasNode, actions: BoardCardActions) -> some View {
        Button(CardCommand.crop.title) { actions.run(.crop, on: node) }
            .accessibilityIdentifier(CardCommand.crop.identifier)
        if actions.hasCrop(node) {
            Button(CardCommand.removeCrop.title) { actions.run(.removeCrop, on: node) }
                .accessibilityIdentifier(CardCommand.removeCrop.identifier)
        }
    }
}
