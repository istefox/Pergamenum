import SwiftUI

// The Workspace tree's row, split out of `WorkspaceBrowser.swift` when ADR-0026's drag
// source, drop target and «Sposta in» menu took that file past the 1000 lines SwiftLint
// errors at - `NoteRowMenu.swift`'s own split from `NoteListPane`, for the same reason and
// at the same seam: a row is a record in and an action out, which is the half that moves
// cleanly. Nothing about the row changed in the move; what is new here is the move gesture.

/// Everything a Workspace row's drag, its drop and its «Sposta in» menu need, in one value
/// (ADR-0026 §D4, §D5, §D9).
///
/// A value rather than six more parameters, because the row passes every parameter it has
/// down its own recursion; and one value rather than a closure per surface, because the
/// drag and the menu are two renderings of one command (ADR-0023 §D1) and must ask the
/// same questions of the same state.
struct WorkspaceMoveContext {
    /// Every folder of the vault, for «Sposta in». `CanvasStore.allFolders()`, which is
    /// what the browser holds, and **never** `VaultController.folders` (ADR-0026 §D9,
    /// ADR-0022 §D11): the latter derives folders from note paths and therefore omits a
    /// folder holding only boards, which is precisely the folder a Workspace user makes.
    let folders: [String]
    /// Every lit row's id (ADR-0026 §D4). Read for one thing only: whether the row a drag
    /// or a menu started from is part of the set, and therefore whether the move carries
    /// the set or that row alone (R-11).
    let multiSelection: Set<String>
    /// What the drag in flight carries, remembered by the source row at drag start.
    /// A folder row's drop affordance is asked of this and of nothing else, because
    /// `.dropDestination`'s `isTargeted` closure never sees the payload (§D5).
    let dragging: [VaultItemRef]
    /// Turns ids into refs against the browser's own tree - a board by its `.canvas`
    /// path, a folder by its folder path (ADR-0025 §D3).
    let resolve: (Set<String>) -> [VaultItemRef]
    /// Remembers what this drag carries, for every folder row's `canDrop` (§D5).
    let onDragStart: ([VaultItemRef]) -> Void
    /// The move itself, performed by the browser and answered `false` when refused -
    /// which is what a `.dropDestination`'s `action` owes the drag.
    let perform: ([VaultItemRef], String) -> Bool
}

/// One row of the Workspace tree, and its subtree.
///
/// Flat and recursive, `NoteTreeRow`'s shape (`NoteListPane.swift:290-322`): the row, and
/// then - as a **sibling**, never as its content - the expanded children (ADR-0024 §D1).
/// The chevron is drawn by hand and the depth is paid for in padding, so every row of the
/// tree is a row of the one enclosing `List` and can carry a `.tag` the selection binding
/// is able to satisfy. A `DisclosureGroup`'s label is not such a row, which is why there
/// is none left in this pane.
///
/// `expanded` is the browser's shared set rather than state of this row's own: "Espandi
/// tutto" and a board revealed from outside both have to be able to open a folder this row
/// did not open itself.
struct WorkspaceRow: View {
    @Environment(\.theme) private var theme

    let node: WorkspaceTree.Node
    let depth: Int
    @Binding var expanded: Set<String>
    /// The lit row, read one way only (ADR-0024 §D9). Nothing drawn here is conditioned
    /// on it - the system draws the selected row's fill - except what VoiceOver is told.
    let selection: WorkspaceSelection?
    let onSelect: (WorkspaceSelection?) -> Void
    /// The two folder verbs, by folder path. The row does not perform them: it hands the
    /// path to the same closures the toolbar's buttons call, so the context menu is a
    /// second entry point rather than a second code path (ADR-0023 §D4).
    let onRename: (String) -> Void
    let onDelete: (String) -> Void
    /// The same two verbs for a board, by the `.canvas` file's own path (ADR-0025 §D6).
    /// Separate closures rather than one that branches, because the two file operations
    /// are different ones - a board rename repoints nodes and rewrites markers, a folder
    /// rename does neither - and this row already knows which kind it is.
    let onRenameBoard: (String) -> Void
    let onDeleteBoard: (String) -> Void
    /// The move verb's half of the row, in one value (ADR-0026 §D9).
    let move: WorkspaceMoveContext

    /// Whether something acceptable is hovering over this row right now - a folder row's
    /// accent stroke, and nothing else in this view is conditioned on it. False on a board
    /// row always: only a folder takes a drop (§D11).
    @State private var isDropTarget = false

    /// One indent step. The rows are drawn flat inside a `List`, so the depth has to be
    /// paid for in padding rather than by nesting the views - `NoteTreeRow`'s constant,
    /// because the two sidebars indent by the same amount or they read as two designs.
    private static let indent: CGFloat = 14

    private var isExpanded: Bool { expanded.contains(node.id) }
    private var isSelected: Bool { selection?.path == node.id }
    private var hasChildren: Bool { !node.children.isEmpty }

    /// What selecting this row means, asked of the one function the `List`'s binding also
    /// asks, so a click and a right-click cannot disagree (ADR-0023 §D4).
    private var picked: WorkspaceSelection { WorkspaceBrowser.selection(for: node) }

    /// This row's own reference: a board by its `.canvas` path, a folder by its folder
    /// path (ADR-0025 §D3).
    private var reference: VaultItemRef {
        switch node.kind {
        case .folder: VaultItemRef(path: node.id, kind: .folder)
        case .board(let path): VaultItemRef(path: path, kind: .board)
        }
    }

    /// What a move started on this row carries (ADR-0026 §D4, R-11): the whole lit set
    /// when this row is part of it, this row alone when it is not - the SPEC's own rule,
    /// and AppKit's.
    ///
    /// Read by both surfaces, which is what makes «Sposta in» with two rows selected move
    /// both of them exactly as a drag of either one would (§D9).
    private var effectiveItems: [VaultItemRef] {
        move.resolve(move.multiSelection.contains(node.id) ? move.multiSelection : [node.id])
    }

    @ViewBuilder
    var body: some View {
        taggedRow
        if isExpanded {
            ForEach(node.children, id: \.id) { child in
                WorkspaceRow(
                    node: child,
                    depth: depth + 1,
                    expanded: $expanded,
                    selection: selection,
                    onSelect: onSelect,
                    onRename: onRename,
                    onDelete: onDelete,
                    onRenameBoard: onRenameBoard,
                    onDeleteBoard: onDeleteBoard,
                    move: move
                )
            }
        }
    }

    /// `.tag` **last in the chain**, on every row without exception.
    ///
    /// Last, because a modifier applied after it drops it and the failure is silent - the
    /// list lights nothing and swallows every click (`RootView.swift:205-208`). On every
    /// row, because ADR-0024 §D3's «foreign» board - the one kind that carried no tag and
    /// was therefore structurally unselectable - is gone with the concept: a `.canvas` is
    /// an ordinary, openable row wherever it lives and whatever it is called
    /// (ADR-0025 §D2), so the switch that used to decide this has nothing left to decide.
    ///
    /// `.draggable` and `.dropDestination` are applied inside `content`, ahead of this
    /// (ADR-0026 §D11) and for the same reason every other modifier is.
    ///
    /// No gesture recognizer sits between `content` and this `.tag` any more. ADR-0025
    /// §D9 originally hung the folder row's double-click-to-toggle here, wrapping the
    /// whole of `content` in `.simultaneousGesture(TapGesture(count: 2))` ahead of the
    /// `.tag` - and the exact risk that section's own text named before merge is the one
    /// that reached `WorkspaceOpenStateUITests
    /// .testClickingABoardLessFolderRowClosesTheOpenBoardAndSelectsOnlyItsRow_R04`:
    /// clicking a board-less folder row straight after a *different* row was selected
    /// intermittently failed to register the click as a selection change at all, because
    /// the double-tap recognizer spanning the entire row contested `List(selection:)`'s
    /// own tap recognizer over the same area. `chevron` is where the gesture lives now -
    /// see the comment there. `.draggable` is not that kind of recognizer: the Note
    /// sidebar's rows have carried one beside their `.tag` since ADR-0012 and select
    /// normally.
    private var taggedRow: some View {
        content.tag(node.id)
    }

    /// The row, then what it can do: a drag source always, a drop target only where a drop
    /// means something (§D11), and the `.tag` after both.
    ///
    /// `draggable(beginDrag())` rather than `draggable { beginDrag() }`: the parameter is
    /// an `@autoclosure @escaping () -> T`, so the call written this way *is* the deferred
    /// closure the drag start evaluates - and a trailing closure would instead make `T`
    /// itself `() -> VaultItemDrag`, which fails to compile against `T: Transferable` with
    /// a diagnostic that names neither the modifier nor this line.
    private var content: some View {
        accepting(label.draggable(beginDrag()))
    }

    /// A folder row's drop target, and a board row left exactly as it was.
    ///
    /// The stroke is `TaskDropTarget`'s own shape and the same accent token
    /// (`TaskDrag.swift:69-72`) - a second drop affordance in this app looks like the
    /// first, and no colour is written here that is not a token (`CLAUDE.md`'s binding
    /// design-system rule).
    ///
    /// `isTargeted` lights the row only when the drag could actually land: a folder
    /// dragged onto itself or into its own descendant gives no affordance at all (§D5,
    /// R-06), which is pure string arithmetic against what the source stored and costs
    /// nothing per hover.
    @ViewBuilder
    private func accepting(_ row: some View) -> some View {
        switch node.kind {
        case .folder:
            row
                .overlay(
                    RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
                        .stroke(isDropTarget ? theme.color(.accentPrimary) : .clear, lineWidth: 1)
                )
                .dropDestination(for: VaultItemDrag.self) { drops, _ in
                    guard let items = drops.first?.items else { return false }
                    return move.perform(items, node.id)
                } isTargeted: { targeted in
                    isDropTarget = targeted && WorkspaceBrowser.canDrop(move.dragging, onFolder: node.id)
                }
        case .board:
            row
        }
    }

    /// What this drag carries, and the record of it the folder rows read while it is in
    /// flight (ADR-0026 §D5): the payload is on the pasteboard, but `isTargeted` never
    /// sees it, so the source side is the only place that can know.
    ///
    /// `dragName` is the row's own name, which is what `ProxyRepresentation(exporting:
    /// \.dragName)` puts on the pasteboard as a plain `String` (§D3) - the representation
    /// that keeps the editor's note-title drop working without touching the file that
    /// implements it.
    private func beginDrag() -> VaultItemDrag {
        let items = effectiveItems
        move.onDragStart(items)
        return VaultItemDrag(items: items, dragName: node.name)
    }

    private var label: some View {
        HStack(spacing: theme.spacing(.xs)) {
            chevron
            // One weight for every row: the dimmed pair ADR-0024 §D3 drew a «foreign»
            // board in is gone with the concept it stood for (ADR-0025 §D2). A board is
            // openable wherever it lives, so nothing here is drawn as if it were not.
            Image(systemName: icon)
                .foregroundStyle(theme.color(.textSecondary))
            Text(node.name)
                .themedText(.body, color: .textPrimary)
                .lineLimit(1)
            Spacer(minLength: theme.spacing(.xs))
            // Only where one was shown before the fold: the rows that have something
            // under them (ADR-0024 §D2).
            if hasChildren {
                Text("\(node.boardCount)").themedText(.caption, color: .textTertiary)
            }
        }
        .padding(.leading, CGFloat(depth) * Self.indent)
        .contentShape(Rectangle())
        // `.contain`, never `.combine`, and the difference is the whole of R-02/R-03.
        // `.combine` folds the row's texts into a single element whose macOS role is
        // `StaticText`, and a `StaticText` carries its words in `AXValue`: the label
        // below arrived in XCUITest's `value` while its `label` stayed empty, so no
        // assertion on the ", aperta"/", selezionata" suffix could ever match. Read out
        // of a failing run's exported UI hierarchy rather than guessed - `StaticText,
        // identifier: 'workspace-board-…', value: Workspace Dettagli…, Selected` - and
        // it is the same trap `UITests/WorkspaceIntegrationUITests.swift:176-181` already
        // wrote down for a plain `Text`. `.contain` makes the row a `Group`, which is the
        // shape that puts the words in `label`: `TaskPanelRow` (`LinkedTasksPanel.swift`)
        // and this pane's own `workspace-browser-header` are both already that.
        //
        // The second half costs more than the label and is the reason this is not a
        // cosmetic choice: `.combine` swallowed the chevron's own `.onTapGesture` into
        // the one merged element, and the merged element's activation point became the
        // triangle's - so a click on a row *with children* landed on the triangle and
        // expanded the folder instead of selecting it, while a childless row selected
        // normally. Measured, not inferred: the failing run's synthesized event drove the
        // pointer to x=218 (the triangle) on `Progetti`, against x=319 (the row's centre)
        // on the root board's row one click earlier. Under `.contain` the triangle is an
        // element of its own again and the row's hit point is the row's - which is
        // «the triangle expands, the row selects» (ADR-0024 §D5) holding for the
        // accessibility tree, not only for a mouse aimed by a person.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        // Belt and braces beside the label: whether this trait reaches XCUITest's
        // `isSelected` for custom `List` row content on macOS is unverified here, so the
        // label above carries the state in words and is what a test may depend on
        // (ADR-0024 §D9, R-13).
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier(WorkspaceBrowser.identifier(for: node))
        // Outside the combined accessibility element, the order the row carried before
        // this rewrite - and still ahead of the `.tag` that `taggedRow` applies last of
        // all, which is the one modifier nothing may follow.
        .contextMenu { menu }
    }

    /// The state said in words, because the colour that used to say it is gone (R-02) and
    /// was never something a screen reader could read anyway (ADR-0024 §D9).
    private var accessibilityLabel: String {
        switch node.kind {
        case .board:
            return isSelected ? "Workspace \(node.name), aperta" : "Workspace \(node.name)"
        case .folder:
            let base = "Cartella \(node.name), \(node.boardCount) Workspace"
            return isSelected ? "\(base), selezionata" : base
        }
    }

    /// The board symbol on a board row, the folder pair on a folder row - a direct read of
    /// the kind, since a row is one thing or the other and no longer both at once
    /// (ADR-0025 §D2). Nothing here is conditioned on the selection (R-02).
    private var icon: String {
        switch node.kind {
        case .board: return "rectangle.3.group"
        case .folder: return isExpanded ? "folder" : "folder.fill"
        }
    }

    /// Its own hit target, which is what keeps «the triangle expands, the row selects»
    /// implementable at all (ADR-0024 §D5). A row with nothing under it keeps the space
    /// so the names line up.
    ///
    /// Also where R-05 / ADR-0025 §D9's double click lives - moved here from the whole row
    /// (`taggedRow`'s comment has the failure and the fix). The chevron carries no `.tag`
    /// of its own, so `List(selection:)` has nothing here to starve - unlike the row body,
    /// where `.onTapGesture(count: 2)` would consume the click before the List ever saw
    /// it.
    ///
    /// The two recognizers below - plain `.onTapGesture` (default count 1) plus a
    /// `.simultaneousGesture(TapGesture(count: 2))` - are not the "documented" fix for
    /// disambiguating tap counts on one control: the seemingly more idiomatic pairing of
    /// two chained `.onTapGesture(count:)` modifiers (highest count first, per Apple's own
    /// guidance for that API) was tried on this chevron and confirmed broken by hand on
    /// macOS 26 inside this `List`: a single click stopped toggling and fell through to
    /// `List(selection:)`'s own row selection instead, and a double click did nothing at
    /// all. `.onTapGesture(count:)` always consumes the click it recognizes; two of them
    /// stacked with no combinator apparently left the click contested between the two
    /// recognizers and the enclosing `List`, rather than resolved by either.
    /// `.simultaneousGesture` never consumes, so the double-tap recognizer only ever adds a
    /// second, non-exclusive observer beside the plain single-tap one - which is what
    /// `ADR-0025 §D9` specified for the row-wide version this was moved from, and turns out
    /// to hold just as well confined to the chevron's own hit target.
    ///
    /// Verified empirically, not from memory of SwiftUI/AppKit gesture precedence (both
    /// warned against by this repo's own prior investigations): a throwaway XCUITest drove
    /// `.click()` and `.doubleClick()` against a temporary `accessibilityIdentifier` on
    /// this chevron and asserted on a nested row's existence as the `isExpanded` signal.
    /// Single click toggled without ever selecting the row (`selectedRowsInTree.count ==
    /// 0` held throughout); double click toggled reliably, and exactly once - the state
    /// after differed from the state before, never landing back where it started. That
    /// probe test and its debug identifier are gone from this repository; the finding is
    /// this comment. Still a manual-verification item before merge (R-05's own gate): the
    /// probe reads accessibility state, not what a person's actual double click feels like.
    @ViewBuilder
    private var chevron: some View {
        if hasChildren {
            triangle
                .contentShape(Rectangle())
                .onTapGesture { toggle() }
                .simultaneousGesture(TapGesture(count: 2).onEnded { toggle() })
        } else {
            triangle.hidden()
        }
    }

    private var triangle: some View {
        Image(systemName: "chevron.right")
            .rotationEffect(.degrees(isExpanded && hasChildren ? 90 : 0))
            .themedText(.caption, color: .textTertiary)
    }

    /// On the row's own `HStack`, where ADR-0023 §D2 put it - and §D2's warning now has
    /// nothing left to warn about: there is no `DisclosureGroup` in this pane for a
    /// modifier to leak out of onto every disclosed descendant, so its conclusion holds by
    /// construction rather than by care (ADR-0024 §D1).
    ///
    /// Plain titles, no SF Symbols: the toolbar keeps its `pencil`/`trash` and this menu
    /// keeps the absence of one, which is what «the same symbol» means for a surface that
    /// draws none (ADR-0023 §D1).
    @ViewBuilder
    private var menu: some View {
        // One gate now, and not restated here: `canMutate(_:)` is the same rule the
        // toolbar's two buttons are enabled by, asked of the same value in the second
        // place it is rendered (ADR-0023 §D1, §D3, ADR-0025 §D8). ADR-0024's second gate -
        // `selection(for:) != nil`, which refused a «foreign» board - went with the
        // concept: both kinds of row are renamed and deleted here (R-08).
        if WorkspaceBrowserToolbar.canMutate(picked) {
            Button("Rinomina…") { requestRename() }
            Button("Elimina…", role: .destructive) { requestDelete() }
        }
        moveMenu
    }

    /// «Sposta in ▸», the second rendering of the drag (ADR-0026 §D9) - and the one that
    /// is keyboard-reachable, VoiceOver-reachable and deterministically testable, which is
    /// why it exists at all: no test in this repository has ever driven a `.draggable` →
    /// `.dropDestination` pasteboard drag.
    ///
    /// The destinations are the browser's own `folders`, which is `CanvasStore
    /// .allFolders()` and never `VaultController.folders` - the latter omits a folder
    /// holding only boards (ADR-0022 §D11), which is exactly the folder this pane makes.
    ///
    /// Two things are disabled rather than hidden, so the menu's shape does not change
    /// from row to row: the folder this row already sits in (a move that moves nothing)
    /// and any destination the cycle rule refuses - this row, if it is a folder, and
    /// everything under it (R-06).
    @ViewBuilder
    private var moveMenu: some View {
        Menu("Sposta in") {
            Button("(radice)") { requestMove(to: "") }
                .disabled(!canMove(to: ""))
            ForEach(move.folders, id: \.self) { folder in
                Button(folder) { requestMove(to: folder) }
                    .disabled(!canMove(to: folder))
            }
        }
        .accessibilityIdentifier("workspace-move-menu")
    }

    /// The folder this row sits in - `""` at the vault root, the same spelling every path
    /// rule in this feature uses.
    private var parentFolder: String {
        (reference.path as NSString).deletingLastPathComponent
    }

    private func canMove(to destination: String) -> Bool {
        destination != parentFolder && WorkspaceBrowser.canDrop(effectiveItems, onFolder: destination)
    }

    /// The menu's move, which is the drop's move: the same effective set, through the same
    /// closure, refused for the same reasons and reported in the same dialog.
    ///
    /// The selection is **not** set first, unlike `requestRename()`/`requestDelete()`
    /// below: selecting this row would collapse a multi-row set to one (R-11's whole
    /// point) and, for a board row, open it - a move is not a reason to change what is on
    /// screen.
    private func requestMove(to destination: String) {
        _ = move.perform(effectiveItems, destination)
    }

    /// The selection first, for what it shows rather than for what it seeds: both verbs
    /// are handed this row's own path and neither reads the selection back, but a
    /// secondary click selects nothing by itself, and a sheet or a dialog opened over a
    /// row the list has not lit reads as acting on another one (ADR-0023 §D4).
    private func requestRename() {
        onSelect(picked)
        switch node.kind {
        case .folder: onRename(node.id)
        case .board(let path): onRenameBoard(path)
        }
    }

    /// `requestRename()`'s shape for the destructive verb, and the same reason for setting
    /// the selection first.
    private func requestDelete() {
        onSelect(picked)
        switch node.kind {
        case .folder: onDelete(node.id)
        case .board(let path): onDeleteBoard(path)
        }
    }

    private func toggle() {
        if isExpanded {
            expanded.remove(node.id)
        } else {
            expanded.insert(node.id)
        }
    }
}
