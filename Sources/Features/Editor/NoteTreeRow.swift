import AppKit
import SwiftUI

// The Note tree's row, its drag payload and its «Sposta in» menu, split out of
// `NoteListPane.swift` when ADR-0026's drag source, drop target and move menu took that
// file past the size SwiftLint errors at - `WorkspaceRow.swift`'s own split from
// `WorkspaceBrowser.swift`, for the same reason and at the same seam: a row is a record in
// and an action out, which is the half that moves cleanly. Nothing about the row changed in
// the move.

/// Everything a Note-sidebar row's drag, its drop and its «Sposta in» menu need, in one
/// value (ADR-0026 §D4, §D5, §D9) - `WorkspaceMoveContext`'s counterpart for this pane.
///
/// A value rather than three more parameters, because the row passes every parameter it
/// has down its own recursion; and one value rather than a closure per surface, because
/// the drag and the menu are two renderings of one command (ADR-0023 §D1) and must ask the
/// same questions of the same state.
///
/// Smaller than `WorkspaceMoveContext` by two fields, and each absence is a fact about
/// this pane rather than an economy. There is no `folders`: the Note tree is built from
/// note paths, so `vault.folders` - which is derived from those same paths - omits no
/// folder this tree draws (ADR-0026 §D9), and the row reads it from the environment it
/// already holds. There is no `multiSelection`/`resolve` pair either: the lit set only
/// ever holds note paths, so `beginDrag` answers "does this row carry the set or itself"
/// in the one place that holds the set, and the row asks nothing about it.
struct NoteMoveContext {
    /// What the drag in flight carries, remembered by the pane at drag start. A folder
    /// row's drop affordance is asked of this and of nothing else, because
    /// `.dropDestination`'s `isTargeted` closure never sees the payload (§D5).
    let dragging: [VaultItemRef]
    /// The payload a drag from this row puts on the pasteboard, and the record of it the
    /// folder rows read while it is in flight: the row's path, its kind, and its display
    /// name - a note's **title**, which is the §7.2 payload (§D3).
    let beginDrag: (String, VaultItemKind, String) -> VaultItemDrag
    /// The move itself, performed by the pane and answered `false` when refused - which is
    /// what a `.dropDestination`'s `action` owes the drag.
    let perform: ([VaultItemRef], String) -> Bool
}

/// One row of the folder tree, and its subtree.
///
/// Recursive rather than an `OutlineGroup`: the group owns its expansion state
/// privately, and this tree has to be opened from outside - by "Espandi tutto", and by
/// a note being opened from somewhere that is not the sidebar.
struct NoteTreeRow: View {
    @Environment(\.theme) var theme
    @Environment(VaultController.self) var vault

    let node: NoteTree.Node
    let depth: Int
    @Binding var expanded: Set<String>
    @Binding var renaming: NoteRecord?
    @Binding var deleting: NoteRecord?
    /// The move verb's half of the row, in one value (ADR-0026 §D9).
    let move: NoteMoveContext

    /// Whether something acceptable is hovering over this row right now - a folder row's
    /// accent stroke, and nothing else in this view is conditioned on it. False on a note
    /// row always: only a folder takes a drop (§D11).
    @State private var isDropTarget = false

    /// One indent step. The rows are drawn flat inside a `List`, so the depth has to
    /// be paid for in padding rather than by nesting the views.
    private static let indent: CGFloat = 14

    var body: some View {
        switch node.kind {
        case .folder: folderRow
        case .note: noteRow
        }
    }

    private var isOpen: Bool { expanded.contains(node.id) }

    @ViewBuilder
    private var folderRow: some View {
        HStack(spacing: theme.spacing(.xs)) {
            // Its own hit target for the toggle, moved off the row body (2026-08-28, toolbar
            // parity chain): `WorkspaceRow.chevron`'s exact pattern - a plain `.onTapGesture`
            // (single click) plus a non-consuming `.simultaneousGesture(TapGesture(count: 2))`
            // (double click), both confined to the chevron alone. A row-wide gesture here
            // would starve `List(selection:)`'s own tap once this row carries a `.tag`
            // (ADR-0025 §D9's exact failure mode) - which it now does, since a folder row
            // became selectable for Rinomina/Elimina to have something to aim at.
            Image(systemName: "chevron.right")
                .rotationEffect(.degrees(isOpen ? 90 : 0))
                .font(.caption2)
                .foregroundStyle(theme.color(.textTertiary))
                .contentShape(Rectangle())
                .onTapGesture { toggle() }
                .simultaneousGesture(TapGesture(count: 2).onEnded { toggle() })
            Image(systemName: isOpen ? "folder" : "folder.fill")
                .foregroundStyle(theme.color(.accentPrimary))
            Text(node.name).themedText(.body).lineLimit(1)
            Spacer(minLength: theme.spacing(.xs))
            Text("\(node.noteCount)").themedText(.caption, color: .textTertiary)
        }
        .padding(.leading, CGFloat(depth) * Self.indent)
        .contentShape(Rectangle())
        // `draggable(move.beginDrag(...))` rather than `draggable { ... }`: the parameter is
        // an `@autoclosure @escaping () -> T`, so the call written this way *is* the
        // deferred closure the drag start evaluates - a trailing closure would instead make
        // `T` itself `() -> VaultItemDrag`, which fails to compile against `T: Transferable`
        // with a diagnostic that names neither the modifier nor this line (R-04).
        .draggable(move.beginDrag(node.id, .folder, node.name))
        // `TaskDropTarget`'s own shape and the same accent token (`TaskDrag.swift:66-71`) -
        // a second drop affordance in this app looks like the first, and no colour is
        // written here that is not a token (CLAUDE.md's binding design-system rule).
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
                .stroke(isDropTarget ? theme.color(.accentPrimary) : .clear, lineWidth: 1)
        )
        // Lit only when the drag could actually land: a folder dragged onto itself or into
        // its own descendant gives no affordance at all (§D5, R-06), which is pure string
        // arithmetic against what the source stored and costs nothing per hover. The rule
        // is `WorkspaceBrowser.canDrop` itself and not a second spelling of it - one cycle
        // rule for both trees, or the two sidebars refuse different things.
        .dropDestination(for: VaultItemDrag.self) { drops, _ in
            guard let items = drops.first?.items else { return false }
            return move.perform(items, node.id)
        } isTargeted: { targeted in
            isDropTarget = targeted && WorkspaceBrowser.canDrop(move.dragging, onFolder: node.id)
        }
        .accessibilityIdentifier("folder-\(node.id)")
        .contextMenu { folderMenu }
        // `.tag` last in the chain, matching `noteRow`'s own rule (ADR-0026 §D11): a
        // modifier applied after it drops it, and the failure is silent.
        .tag(node.id)

        if isOpen {
            ForEach(node.children ?? []) { child in
                NoteTreeRow(
                    node: child,
                    depth: depth + 1,
                    expanded: $expanded,
                    renaming: $renaming,
                    deleting: $deleting,
                    move: move
                )
            }
        }
    }

    @ViewBuilder
    private var folderMenu: some View {
        Button("Nuova nota qui") { vault.beginNewNote(in: node.id) }
        Button(isOpen ? "Comprimi" : "Espandi") { toggle() }
        moveMenu
        Divider()
        Button("Rivela nel Finder") {
            guard let root = vault.root else { return }
            NSWorkspace.shared.activateFileViewerSelecting([
                root.appending(path: node.id, directoryHint: .isDirectory),
            ])
        }
    }

    /// «Sposta in ▸», the second rendering of the drag (ADR-0026 §D9) - and the one that is
    /// keyboard-reachable, VoiceOver-reachable and deterministically testable, which is why
    /// it exists at all: no test in this repository has ever driven a `.draggable` →
    /// `.dropDestination` pasteboard drag.
    ///
    /// On the **folder** rows only. The note rows have had this menu since ADR-0016
    /// (`NoteRowMenu.swift:30-36`) and are left exactly as they are (§D9).
    ///
    /// The destinations are `vault.folders`, which is correct here and would not be in the
    /// Workspace pane: that list is derived from note paths, and so is this tree, so it
    /// omits no folder this pane draws (ADR-0022 §D11 read the other way round).
    ///
    /// Two things are disabled rather than hidden, so the menu's shape does not change from
    /// row to row: the folder this row already sits in (a move that moves nothing) and any
    /// destination the cycle rule refuses - this row and everything under it (R-06).
    @ViewBuilder
    private var moveMenu: some View {
        Menu("Sposta in") {
            Button("(radice)") { requestMove(to: "") }
                .disabled(!canMove(to: ""))
            ForEach(vault.folders, id: \.self) { folder in
                Button(folder) { requestMove(to: folder) }
                    .disabled(!canMove(to: folder))
            }
        }
        .accessibilityIdentifier("note-move-menu")
    }

    /// This row's own reference. A folder row is never part of the lit set - it carries no
    /// `.tag` - so a move started here carries this folder and nothing else, whatever else
    /// is selected.
    private var reference: VaultItemRef {
        VaultItemRef(path: node.id, kind: .folder)
    }

    /// The folder this row sits in - `""` at the vault root, the same spelling every path
    /// rule in this feature uses.
    private var parentFolder: String {
        (node.id as NSString).deletingLastPathComponent
    }

    private func canMove(to destination: String) -> Bool {
        destination != parentFolder && WorkspaceBrowser.canDrop([reference], onFolder: destination)
    }

    /// The menu's move, which is the drop's move: the same reference, through the same
    /// closure, refused for the same reasons and reported in the same place.
    private func requestMove(to destination: String) {
        _ = move.perform([reference], destination)
    }

    private var noteRow: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Image(systemName: "doc.text")
                .foregroundStyle(theme.color(.textTertiary))
            Text(node.name).themedText(.body).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, CGFloat(depth) * Self.indent)
        // Dragged onto a folder row this moves the file (R-03); dragged onto a task line in
        // the editor it still becomes a wikilink (SPEC §7.2), because `VaultItemDrag` puts
        // `node.name` - which `NoteTree.build(from:)` sets from `NoteRecord.title` - on the
        // pasteboard as a plain `String` beside the structured payload (ADR-0026 §D3,
        // R-09). Byte-identical to the `.draggable(node.name)` that used to be here.
        .draggable(move.beginDrag(node.id, .note, node.name))
        // The row's own identifier, and **no** `.accessibilityElement(children: .contain)`
        // beside it (ADR-0026 §D11): `NoteTreeAndShortcutsUITests:54-90` finds every folder
        // and note by the words on it, and regrouping the row's children would move those
        // words out of `staticTexts` and break eight assertions that have nothing to do
        // with this feature. The Workspace rows already carry `.contain` and are
        // unaffected; these rows have never paid for it and are not made to start here.
        .accessibilityIdentifier("note-row-\(node.id)")
        .contextMenu {
            if let record = vault.index.allNotes.first(where: { $0.relativePath == node.id }) {
                NoteRowMenu(note: record, renaming: $renaming, deleting: $deleting)
            }
        }
        // `.tag` **last in the chain**, normalised to the Workspace pane's order (ADR-0026
        // §D11) rather than left where it was: a modifier applied after it drops it, and
        // the failure is silent - the list lights nothing and swallows every click
        // (`RootView.swift:205-208`).
        .tag(node.id)
    }

    private func toggle() {
        if isOpen {
            expanded.remove(node.id)
        } else {
            expanded.insert(node.id)
        }
    }
}
