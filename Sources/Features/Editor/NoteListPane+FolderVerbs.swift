import SwiftUI

// The folder half of the Note sidebar's commands: the toolbar row, what a single lit row
// means for it, and the three sheets its verbs open.
//
// In a file of its own for the reason `NoteListPane+Footer.swift` exists and for the reason
// `WorkspaceRow.swift` was split out of `WorkspaceBrowser.swift`: the toolbar-parity chain
// (2026-08-28) took `NoteListPane`'s own body past the 350 lines SwiftLint *errors* at, and
// these verbs are the self-contained half - a selection in, a write out - rather than the
// half that draws the tree.
extension NoteListPane {
    // MARK: Toolbar (2026-08-28, parity with `WorkspaceBrowserToolbar`)

    var toolbar: some View {
        NoteListToolbar(
            selection: currentSelection,
            onNew: { vault.beginNewNote(in: targetFolder) },
            onNewFolder: { creatingFolder = true },
            onRename: { renameSelection() },
            onDelete: { deleteSelection() },
            onExpandAll: { expanded = Self.allFolders(in: tree) },
            onCollapseAll: { expanded = [] }
        )
    }

    /// What a single lit row is, folder or note - `nil` for zero or two-or-more, the same
    /// gate `WorkspaceBrowserToolbar.canMutate(_:)` reads (ADR-0025 §D8: nothing to aim
    /// Rinomina/Elimina at, or a multi-select that answers "what does a drag carry" and
    /// nothing else, R-11).
    private var currentSelection: NoteListToolbar.Selection? {
        guard selectedRows.count == 1, let id = selectedRows.first,
              let node = NoteTree.node(withID: id, in: tree)
        else { return nil }
        return node.kind == .folder ? .folder(id) : .note(id)
    }

    /// Where "Nuova nota"/"Nuova cartella" land - `WorkspaceBrowser.target(for:)`'s own
    /// rule (`WorkspaceBrowser.swift:276-278`): a folder selected is made *beside* what a
    /// note selected sits inside, never inside either one. `""` (the vault root) with
    /// nothing selected.
    private var targetFolder: String {
        switch currentSelection {
        case .folder(let path): path
        case .note(let path): (path as NSString).deletingLastPathComponent
        case nil: ""
        }
    }

    /// The toolbar's "Rinomina", dispatched on the selection's kind - a note reuses the
    /// sheet the row's own context menu already opens (`NoteRowMenu.swift`), a folder
    /// opens the sheet added in this chain.
    private func renameSelection() {
        switch currentSelection {
        case .note(let path):
            renaming = vault.index.allNotes.first { $0.relativePath == path }
        case .folder(let path):
            renamingFolder = path
        case nil:
            break
        }
    }

    /// The toolbar's "Elimina", the same dispatch as `renameSelection()` above.
    private func deleteSelection() {
        switch currentSelection {
        case .note(let path):
            deleting = vault.index.allNotes.first { $0.relativePath == path }
        case .folder(let path):
            deletingFolder = path
        case nil:
            break
        }
    }

    /// The folder-delete dialog's message - `WorkspaceBrowser`'s own wording for its
    /// `.folder` `pendingDelete` case, over the same `FolderFileOperations.contentCounts`.
    private var deletingFolderCounts: String {
        guard let path = deletingFolder else { return "" }
        // `nil` when the folder could not be read (PG-048) - never defaulted to zero,
        // which is the answer for a folder that is genuinely empty.
        guard let counts = folderOperations?.contentCounts(at: path) else {
            return "Non è stato possibile leggere il contenuto della cartella. "
                + "Non è una cancellazione definitiva."
        }
        return "Va nel Cestino del Finder: \(counts.notes) nota/e, "
            + "\(counts.subfolders) sottocartella/e. Non è una cancellazione definitiva."
    }

    /// The toolbar's "Nuova cartella" - `CanvasStore.createFolder` writes no note inside
    /// it (R-01), the same rule `WorkspaceView+FolderVerbs.createFolder` follows for a
    /// board folder.
    private func createFolder(named name: String, in parent: String) {
        guard let root = vault.root else { return }
        do {
            _ = try CanvasStore(root: root).createFolder(named: name, in: parent)
            Task { await vault.rescan() }
        } catch {
            vault.recordProblem("nuova cartella: \(error)")
        }
    }

    /// Every folder id in the tree - "Espandi tutto", from the toolbar above and from the
    /// tree's own context menu in `NoteListPane.folderTree`, which is why it is not
    /// `private` to this file.
    static func allFolders(in nodes: [NoteTree.Node]) -> Set<String> {
        var result: Set<String> = []
        for node in nodes where node.kind == .folder {
            result.insert(node.id)
            result.formUnion(allFolders(in: node.children ?? []))
        }
        return result
    }

    // MARK: The verbs' sheets

    /// The three presentations the folder verbs open, applied to the pane by `body`
    /// in the position the chain used to spell them out - after the note rename sheet
    /// and the note delete dialog, before the move-refused alert - so nothing about
    /// which modifier sits where changed with the move.
    func folderVerbSheets(_ content: some View) -> some View {
        content
            // The toolbar's "Nuova cartella" (2026-08-28): the same sheet type
            // `WorkspaceBrowser` uses, kept only to `.folder` - its `.board` arm is never
            // reached from here. `CanvasStore.createFolder` writes no note inside it (R-01's
            // own rule, unchanged by which pane asked).
            .sheet(isPresented: $creatingFolder) { newFolderSheet }
            // The toolbar's "Rinomina" on a folder row - `VaultController.renameFolder`
            // already exists and already repoints every card and board path under it
            // (ADR-0022 §D1); this is the first UI in this pane that reaches it.
            .sheet(isPresented: Binding(
                get: { renamingFolder != nil },
                set: { if !$0 { renamingFolder = nil } }
            )) { renameFolderSheet }
            // The toolbar's "Elimina" on a folder row - same wording and same counts
            // `WorkspaceBrowser`'s own folder-delete confirmation uses
            // (`FolderFileOperations.contentCounts`), `VaultController.trashFolder` doing the
            // actual move to the Finder's Trash (R-11's rule, unchanged by which pane asked).
            .confirmationDialog(
                "Eliminare «\(deletingFolder.map { ($0 as NSString).lastPathComponent } ?? "")» e il suo contenuto?",
                isPresented: Binding(
                    get: { deletingFolder != nil },
                    set: { if !$0 { deletingFolder = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Sposta nel Cestino", role: .destructive) {
                    if let path = deletingFolder { vault.trashFolder(at: path) }
                    deletingFolder = nil
                }
                Button("Annulla", role: .cancel) { deletingFolder = nil }
            } message: {
                Text(deletingFolderCounts)
            }
    }

    /// The "Nuova cartella" sheet's own body, named rather than written inline in the
    /// modifier above only so that chain stays inside SwiftLint's function-body length -
    /// the closure evaluates it at presentation time exactly as it evaluated the literal.
    private var newFolderSheet: some View {
        NewWorkspaceSheet(
            kind: .folder,
            parents: WorkspaceFolderSheets.parentOptions(from: diskFolders),
            initialParent: targetFolder,
            isNameAvailable: { name, parent in
                folderOperations?.nameIsAvailable(name, in: parent) ?? true
            },
            onConfirm: { name, parent in
                creatingFolder = false
                createFolder(named: name, in: parent)
            },
            onCancel: { creatingFolder = false }
        )
    }

    /// The folder-rename sheet's own body, named for the same reason as `newFolderSheet`.
    /// The `if let` is the one that was written inside the modifier's closure: a sheet
    /// presented while `renamingFolder` is nil draws nothing, as before.
    @ViewBuilder
    private var renameFolderSheet: some View {
        if let path = renamingFolder {
            RenameWorkspaceSheet(
                kind: .folder,
                path: path,
                isNameAvailable: { name, parent in
                    folderOperations?.nameIsAvailable(name, in: parent) ?? true
                },
                onConfirm: { newName in
                    renamingFolder = nil
                    vault.renameFolder(at: path, to: newName)
                },
                onCancel: { renamingFolder = nil }
            )
        }
    }
}
