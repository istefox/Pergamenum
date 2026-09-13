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

    /// The commands a plain button invokes - everything `CardCommand.carriesArgument` says
    /// is not built from a submenu's own values.
    func run(_ command: CardCommand, on node: CanvasNode) {
        guard !command.carriesArgument else {
            // Every argument-carrying command draws as a `Menu` on both surfaces, so
            // reaching here means one rendered it as something it is not.
            assertionFailure("\(command) carries an argument and is invoked through its submenu")
            return
        }
        switch command {
        case .open:
            open(node)
        case .editText:
            workspace.beginTextEdit(nodeID: node.id)
        case .renameLink:
            workspace.beginTitleEdit(nodeID: node.id)
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
        case .color, .textColor, .textAlign, .foldHeadings, .resize:
            // Unreachable: `carriesArgument` is true for every case listed here, and the
            // guard above already returned. Listed rather than `default` so a new
            // argument-carrying case must be routed here deliberately.
            break
        }
    }

    func setColor(preset: Int?, on node: CanvasNode) {
        workspace.setColor(preset.map { .preset($0) }, forNodeIDs: targets(node))
    }

    /// «Colore testo» (ADR-0027 §D4): the same preset-or-nil vocabulary `setColor(preset:on:)`
    /// already speaks, written to `CardTextStyle.colorKey` instead of the node's own `color`.
    func setTextColor(preset: Int?, on node: CanvasNode) {
        workspace.setTextColor(preset.map { .preset($0) }, forNodeIDs: targets(node))
    }

    /// «Allineamento» (ADR-0027 §D4): `nil` clears back to natural alignment.
    func setTextAlignment(_ alignment: CardTextStyle.Alignment?, on node: CanvasNode) {
        workspace.setTextAlignment(alignment, forNodeIDs: targets(node))
    }

    /// The markdown this card is *showing*: the live draft while it is being written into, its
    /// stored text otherwise, and nothing at all for a card kind that has none.
    ///
    /// The draft rather than the node matters here and nowhere else in this type: a fold names a
    /// heading by its ordinal in `NoteOutline.entries(in:)`, and while somebody is typing the
    /// node's stored text is the one they started from - a submenu built off it would offer
    /// ordinals that mean different headings than the ones the card's own text view is rendering.
    func cardText(of node: CanvasNode) -> String {
        if workspace.editingTextNodeID == node.id { return workspace.editingTextDraft }
        if case .text(let text) = node.kind { return text }
        return ""
    }

    /// Which of this card's headings are folded right now (ADR-0028 §D8).
    func foldedEntries(of node: CanvasNode) -> Set<Int> {
        workspace.foldedHeadings[node.id] ?? []
    }

    /// «Ripiega titoli», on one heading of one card.
    ///
    /// This card alone, never `targets(node)` the way «Colore» and «Elimina» act on the whole
    /// selection: an entry ordinal is an index into *this* card's own outline, so the same number
    /// names a different heading on every other card it reached - or no heading at all.
    func toggleFold(_ entry: Int, on node: CanvasNode) {
        workspace.toggleFold(entry, forNodeID: node.id)
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
        guard let url = PergamenumLink.canvas(path: workspace.board, nodeID: node.id) else {
            workspace.recordProblem("copia link: impossibile generare l'URL per \(workspace.board)")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    /// The URL `open(_:)` would hand to `NSWorkspace`, or `nil` when nothing should be
    /// opened - split out of `open(_:)` (ADR-0041 §D2, Task 2) so a `.canvas` node's `file`
    /// path can be exercised without driving `NSWorkspace` for real.
    ///
    /// It refuses silently rather than throwing because its one caller is a double click:
    /// a gesture has nobody to report to, and handing `NSWorkspace` a path outside the
    /// vault is the one outcome that must not happen.
    nonisolated static func resolvedOpenURL(for path: String, root: URL) -> URL? {
        try? VaultBoundary(root: root).url(for: path)
    }

    /// Double click, and «Apri»: enter a folder's board, or open the file the card points
    /// at.
    func open(_ node: CanvasNode) {
        if let subfolder = workspace.subfolder(for: node) {
            enter(subfolder)
            return
        }
        switch node.kind {
        case .file(let path, _):
            if path.lowercased().hasSuffix(".svg"), workspace.editDrawing(nodeID: node.id) {
                // One of our own drawings: reopen the ink rather than the image.
                workspace.tool = .drawing
            } else if path.hasSuffix(".md") {
                vault.openNote(at: path)
            } else if let root = vault.root, let url = Self.resolvedOpenURL(for: path, root: root) {
                NSWorkspace.shared.open(url)
            }
        case .link(let url):
            if let target = URL(string: url) { NSWorkspace.shared.open(target) }
        case .text:
            workspace.beginTextEdit(nodeID: node.id)
        case .group, .unknown:
            break
        }
    }

    /// A folder card, under the one rule §D5 gives every folder→board navigation: the
    /// resolver decides which board the folder means, `.unique` opens it, and
    /// `.ambiguous`/`.notFound` selects the folder rather than guessing at a board named
    /// after it (§D1). The board list is read in the gesture, never in a `body`, because
    /// `allBoards()` walks the whole vault uncached.
    private func enter(_ folder: String) {
        switch WorkspaceBoardResolver.board(
            inFolder: folder, among: workspace.store?.allBoards() ?? []
        ) {
        case .unique(let path): workspace.select(.board(path: path.value))
        case .ambiguous, .notFound: workspace.select(.folder(folder))
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
        if command.carriesArgument {
            Menu(command.title) { argumentItems(for: command, node: node, actions: actions) }
        } else if command == .fitToCrop {
            // Drawn inside «Ridimensiona» by `sizeItems`, which is where the card menu has
            // always drawn it: nothing of its own at the top level.
            EmptyView()
        } else {
            Button(command.title) { actions.run(command, on: node) }
        }
    }

    /// The submenu an argument-carrying command draws, one mapping shared by the context
    /// menu (`item` above) and the command bar (`BoardCardControls.control`), so the two
    /// cannot build a different submenu for the same command.
    @ViewBuilder
    static func argumentItems(
        for command: CardCommand, node: CanvasNode, actions: BoardCardActions
    ) -> some View {
        switch command {
        case .color: colorItems(node: node, actions: actions)
        case .textColor: textColorItems(node: node, actions: actions)
        case .textAlign: textAlignItems(node: node, actions: actions)
        case .foldHeadings: foldItems(node: node, actions: actions)
        case .resize: sizeItems(node: node, actions: actions)
        case .open, .editText, .renameLink, .copyLink, .crop, .fitToCrop, .removeCrop, .duplicate, .delete:
            // Unreachable: `carriesArgument` is false for every case listed here.
            EmptyView()
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

    /// «Colore testo» (ADR-0027 §D4): "Nessuno" (back to `theme.color(.textPrimary)`), then
    /// the same six JSON Canvas presets `colorItems` draws for the card's own background -
    /// one vocabulary for both, per `CardTextStyle`'s own doc comment.
    @ViewBuilder
    static func textColorItems(node: CanvasNode, actions: BoardCardActions) -> some View {
        Button("Nessuno") { actions.setTextColor(preset: nil, on: node) }
        ForEach(1...6, id: \.self) { preset in
            Button(BoardContentLayer.colorNames[preset - 1]) {
                actions.setTextColor(preset: preset, on: node)
            }
        }
    }

    /// «Allineamento» (ADR-0027 §D4): "Naturale" clears `CardTextStyle.alignKey`, then the
    /// four alignment values in reading order.
    @ViewBuilder
    static func textAlignItems(node: CanvasNode, actions: BoardCardActions) -> some View {
        Button("Naturale") { actions.setTextAlignment(nil, on: node) }
        Button("Sinistra") { actions.setTextAlignment(.left, on: node) }
        Button("Centro") { actions.setTextAlignment(.center, on: node) }
        Button("Destra") { actions.setTextAlignment(.right, on: node) }
        Button("Giustificato") { actions.setTextAlignment(.justify, on: node) }
    }

    /// «Ripiega titoli» (ADR-0028 §D8): one row per heading of this card's own markdown, checked
    /// while its section is folded.
    ///
    /// Built from `NoteOutline.entries(in:)` - the note's own parser, over a card's text, which
    /// `Tests/CardFoldTests.swift` asserts answers unadapted - and the ordinal each row carries is
    /// the entry's place in the **whole** outline, embeds included, because that is the number
    /// `NoteFolding` and `WorkspaceController.foldedHeadings` both speak. Filtering the list
    /// without keeping the ordinals would fold a different section than the one clicked, which is
    /// `QuickSwitcher.headingGroups`' own reason for enumerating before it filters.
    ///
    /// Only the headings with at least one line under them, the rule `OutlinePane.foldable` already
    /// applies to the note's own chevrons: an embed opens no section, and a heading with nothing
    /// beneath it would fold to nothing - a row that ticks and hides not one line.
    ///
    /// A `Toggle` rather than a `Button`, because macOS draws one in a menu as a checked row, which
    /// is what "a check per folded entry" is. Its getter reads the controller rather than a
    /// captured snapshot, so the check follows a fold made from anywhere else - the badge, the
    /// other surface - without this menu being rebuilt.
    @ViewBuilder
    static func foldItems(node: CanvasNode, actions: BoardCardActions) -> some View {
        let rows = foldRows(in: actions.cardText(of: node))
        if rows.isEmpty {
            // A card with no heading in it is most cards. Saying so is better than an empty
            // submenu, which reads as a command that is broken rather than one with nothing to
            // offer.
            Text("Nessun titolo da ripiegare")
        } else {
            ForEach(rows) { row in
                Toggle(isOn: Binding(
                    get: { actions.foldedEntries(of: node).contains(row.id) },
                    set: { _ in actions.toggleFold(row.id, on: node) }
                )) {
                    Text(row.title)
                }
            }
        }
    }

    /// One row per foldable heading, carrying the ordinal the fold is held by.
    ///
    /// A named type rather than the `(ordinal, entry)` pairs `enumerated()` hands back: Swift has
    /// no key path to a tuple's element, so a `ForEach` over those pairs has no `id` to be given.
    /// `QuickSwitcher.headingGroups` builds its own `Row` from the same enumeration for the same
    /// reason.
    private static func foldRows(in text: String) -> [FoldRow] {
        NoteOutline.entries(in: text).enumerated().compactMap { ordinal, entry -> FoldRow? in
            guard case .heading = entry.kind,
                  !NoteFolding.hiddenParagraphs(in: text, foldedEntries: [ordinal]).isEmpty
            else { return nil }
            return FoldRow(id: ordinal, title: entry.title.isEmpty ? "Senza titolo" : entry.title)
        }
    }

    /// A heading the fold submenu offers. `id` is its ordinal in the **whole** outline, embeds
    /// included - the number `NoteFolding` and `WorkspaceController.foldedHeadings` speak - and not
    /// its place among the rows, which would name a different section on any card holding an
    /// embed.
    private struct FoldRow: Identifiable {
        let id: Int
        let title: String
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
