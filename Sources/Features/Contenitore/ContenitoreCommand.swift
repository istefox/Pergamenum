import Foundation

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D11 and §D12, plan
// docs/plans/contenitore.md, Task 7 - R-18, R-19, R-22, R-23, R-27.

/// One action on a Contenitore document, named once so the inspector, the row's context menu and
/// the menu bar read the same catalogue (ADR-0023 §D1, R-27).
///
/// Declaration order is the row menu's order, the mockup's (screen 1e).
enum ContenitoreCommand: String, CaseIterable, Sendable {
    case classify
    case open
    case openScheda
    case revealInFinder
    case copyLink
    case rename
    case moveTo
    case trash

    /// Where the menu bar carries a command (ADR-0071 §D11, gate G2): the «Documento» menu
    /// holds what the app did not already have; «Copia link Pergamenum» and «Mostra nel Finder»
    /// are File's existing entries and «Sposta nel Cestino» is Modifica's, each dispatching to
    /// the selected document while the pane is on screen (§D12).
    enum MenuBarMenu: Sendable {
        case documento
        case file
        case modifica
    }

    var title: String {
        switch self {
        case .classify: "Classifica…"
        case .open: "Apri"
        case .openScheda: "Apri scheda"
        case .revealInFinder: "Mostra nel Finder"
        case .copyLink: "Copia link Pergamenum"
        case .rename: "Rinomina…"
        case .moveTo: "Sposta in…"
        case .trash: "Sposta nel Cestino"
        }
    }

    var symbol: String {
        switch self {
        case .classify: "tag"
        case .open: "arrow.up.forward.square"
        case .openScheda: "doc.text"
        case .revealInFinder: "folder"
        case .copyLink: "link"
        case .rename: "pencil"
        case .moveTo: "arrow.right.square"
        case .trash: "trash"
        }
    }

    var menuBarMenu: MenuBarMenu {
        switch self {
        case .classify, .open, .openScheda, .rename, .moveTo: .documento
        case .copyLink, .revealInFinder: .file
        case .trash: .modifica
        }
    }

    /// The one AX identifier for this command's control, on every surface.
    var identifier: String { "contenitore-command-\(rawValue)" }

    // MARK: - The three surfaces (R-27)

    /// The inspector's buttons. «Classifica…» leads for a document still in the inbox (mockup
    /// 1d) and follows the others once it is classified, where it reopens the sheet.
    static func inspectorActions(isInbox: Bool) -> [ContenitoreCommand] {
        let rest = allCases.filter { $0 != .classify }
        return isInbox ? [.classify] + rest : rest + [.classify]
    }

    /// The row's context menu: every command, in declaration order.
    static var rowMenu: [ContenitoreCommand] { allCases }

    /// The commands the menu bar draws in `menu`, in declaration order.
    static func menuBar(_ menu: MenuBarMenu) -> [ContenitoreCommand] {
        allCases.filter { $0.menuBarMenu == menu }
    }
}

/// Performs `ContenitoreCommand`s and the container verbs, for every surface (ADR-0023 §D1).
///
/// The side effects that leave the app (open a file, reveal it) go through the controller's
/// `openFile` and `revealFiles`, so a test can run every command without launching a viewer or
/// the Finder.
@MainActor
struct ContenitoreCommandActions {
    let vault: VaultController
    let navigation: Navigation
    let contenitore: ContenitoreController

    /// Whether `command` can act on the scheda at `schedaPath` now.
    func canRun(_ command: ContenitoreCommand, on schedaPath: String) -> Bool {
        guard let session = vault.session, session.exists(schedaPath) else { return false }
        switch command {
        case .open: return session.companion(ofScheda: schedaPath) != nil
        case .classify, .openScheda, .revealInFinder, .copyLink, .rename, .moveTo, .trash: return true
        }
    }

    /// Runs `command` on the scheda at `schedaPath`. The commands that need an answer first
    /// («Classifica…», «Rinomina…», «Sposta in…», «Sposta nel Cestino») present their sheet or
    /// dialog; `rename(_:to:)`, `move(_:toContainer:)` and `trash(_:)` perform them.
    func run(_ command: ContenitoreCommand, on schedaPath: String) {
        guard canRun(command, on: schedaPath) else { return }
        contenitore.selection = schedaPath
        switch command {
        case .classify: contenitore.classifying = schedaPath
        case .open: open(schedaPath)
        case .openScheda: openScheda(schedaPath)
        case .revealInFinder: reveal(schedaPath)
        case .copyLink: contenitore.copyLink(for: schedaPath)
        case .rename: contenitore.renaming = schedaPath
        case .moveTo: contenitore.moving = schedaPath
        case .trash: contenitore.trashing = schedaPath
        }
    }

    // MARK: - Performers

    /// «Rinomina…»: the note door renames the pair (R-21).
    @discardableResult
    func rename(_ schedaPath: String, to newTitle: String) async -> Bool {
        await contenitore.settleEditing()
        guard !refusesForOwedEdit(at: schedaPath) else { return false }
        let renamed = await vault.renameNote(at: schedaPath, to: newTitle)
        if renamed, let session = vault.session {
            let folder = (schedaPath as NSString).deletingLastPathComponent
            let path = (folder.isEmpty ? "" : folder + "/") + NoteName.fileName(for: newTitle)
            if session.exists(path) { contenitore.selection = path }
        }
        return renamed
    }

    /// «Sposta in…»: into `<container>/<YYYY>` (R-20), with the selection following the pair.
    @discardableResult
    func move(_ schedaPath: String, toContainer container: String) async -> Bool {
        await contenitore.settleEditing()
        guard !refusesForOwedEdit(at: schedaPath) else { return false }
        guard let session = vault.session, vault.canOperate(on: schedaPath) else { return false }
        do {
            let outcome = try await session.moveDocument(at: schedaPath, toContainer: container)
            for failure in outcome.failures { vault.recordProblem("riferimento non aggiornato: \(failure)") }
            for refusal in outcome.refusals { vault.recordProblem(VaultWriteRefusal.movedOn(refusal).description) }
            if contenitore.selection == schedaPath { contenitore.selection = outcome.newPath }
            Task { await vault.rescan() }
            return true
        } catch {
            vault.recordProblem("spostamento: \(error)")
            return false
        }
    }

    /// «Sposta nel Cestino», once confirmed: file and scheda go to the Finder Trash together
    /// (R-22). What now links to nothing is reported, never rewritten. Returns where the files
    /// went in the Trash, nil when nothing was trashed.
    @discardableResult
    func trash(_ schedaPath: String) async -> [URL]? {
        await contenitore.settleEditing()
        guard !refusesForOwedEdit(at: schedaPath) else { return nil }
        guard let session = vault.session, vault.canOperate(on: schedaPath) else { return nil }
        do {
            let (orphaned, trashURLs) = try await session.trashDocument(at: schedaPath)
            if !orphaned.isEmpty {
                let title = NoteName.title(fromFileName: (schedaPath as NSString).lastPathComponent)
                vault.recordProblem("\(orphaned.count) note linkavano «\(title)»: ora il link non risolve")
            }
            if contenitore.selection == schedaPath { contenitore.selection = nil }
            await vault.rescan()
            return trashURLs
        } catch {
            vault.recordProblem("eliminazione: \(error)")
            return nil
        }
    }

    // MARK: - Container verbs (R-19)

    /// Why a container name was refused, or nil when it may be created or renamed to.
    static func refusal(forContainerName name: String) -> String? {
        switch ContenitoreNaming.validateContainerName(name) {
        case .valid: nil
        case .yearName: "Un nome di quattro cifre è riservato alle cartelle anno."
        case .invalid(let violations):
            ConformanceText.lines(NoteViolations(name: violations)).joined(separator: ". ")
        }
    }

    /// «Nuovo sottocontenitore…»: a folder named `name` in `parent` (the root for a top-level
    /// one), creating the root first when it does not exist yet. Returns the refusal or failure
    /// sentence, nil on success.
    func createContainer(named name: String, in parent: String) async -> String? {
        if let refusal = Self.refusal(forContainerName: name) { return refusal }
        guard let root = vault.root, let session = vault.session else { return "Nessun vault aperto." }
        do {
            let rootFolder = try session.store.url(for: parent)
            try FileManager.default.createDirectory(at: rootFolder, withIntermediateDirectories: true)
            _ = try CanvasStore(root: root).createFolder(named: name, in: parent)
            contenitore.containersChanged()
            await vault.rescan()
            return nil
        } catch {
            return "Sottocontenitore non creato: \(error)"
        }
    }

    /// Renames a sub-container through the vault's folder door, refusing a year name first.
    ///
    /// The inspector's unsaved edit settles first: it may sit on a document inside the container,
    /// and a write started after the folder moved would go to the old path, be refused and be
    /// discarded. The selection and the scope follow the folder (a document or a container
    /// nested in it keeps its place under the new name).
    func renameContainer(_ path: String, to name: String) async -> String? {
        if let refusal = Self.refusal(forContainerName: name) { return refusal }
        await contenitore.settleEditing()
        guard !refusesForOwedEdit(inside: path) else {
            return "Sottocontenitore non rinominato: \(Self.owedEditSentence)."
        }
        guard let newPath = vault.renameFolder(at: path, to: name) else {
            return "Sottocontenitore non rinominato: vedi i problemi del vault."
        }
        contenitore.containersChanged()
        contenitore.followRelocatedContainers([MovedNote(old: path, new: newPath)])
        return nil
    }

    /// Moves a sub-container, with everything in it, under `parent` (R-19).
    func moveContainer(_ path: String, into parent: String, undo: UndoManager?) async {
        await contenitore.settleEditing()
        guard !refusesForOwedEdit(inside: path) else { return }
        let outcome = await vault.moveItems([VaultItemRef(path: path, kind: .folder)], into: parent, undo: undo)
        contenitore.containersChanged()
        if outcome.didMove {
            let newPath = parent + "/" + (path as NSString).lastPathComponent
            contenitore.followRelocatedContainers([MovedNote(old: path, new: newPath)])
        }
    }

    /// Trashes a sub-container, once confirmed. What pointed inside it falls back: the scope to
    /// «Tutti», the selection to nothing.
    func trashContainer(_ path: String) async {
        await contenitore.settleEditing()
        guard !refusesForOwedEdit(inside: path) else { return }
        guard vault.trashFolder(at: path) else { return }
        contenitore.containersChanged()
        if case .container(let scoped) = contenitore.scope, Self.isInside(scoped, container: path) {
            contenitore.scope = .all
        }
        if let selected = contenitore.selection, Self.isInside(selected, container: path) {
            contenitore.selection = nil
        }
    }

    /// True for `path` itself and for anything below it.
    private static func isInside(_ path: String, container: String) -> Bool {
        path == container || path.hasPrefix(container + "/")
    }

    /// `path` as it reads once `old` became `new`, nil when it was not inside `old`.
    static func remapped(_ path: String, from old: String, to new: String) -> String? {
        guard isInside(path, container: old) else { return nil }
        return new + path.dropFirst(old.count)
    }

    // MARK: - Pieces

    /// The sentence recorded when a verb is refused because a scheda's edit could not be written.
    static let owedEditSentence = "salva la modifica alla scheda prima di rinominare, spostare o eliminare il documento"

    /// After `settleEditing()`: true, with the refusal recorded, when the edit on `schedaPath` is
    /// still owed (its write failed). The pair must not move from under a draft nothing can write
    /// back to the old path.
    private func refusesForOwedEdit(at schedaPath: String) -> Bool {
        guard contenitore.unsettledScheda(at: schedaPath) != nil else { return false }
        vault.recordProblem(Self.owedEditSentence)
        return true
    }

    /// The container twin: any owed edit on a scheda inside `container`.
    private func refusesForOwedEdit(inside container: String) -> Bool {
        guard contenitore.unsettledScheda(inside: container) != nil else { return false }
        vault.recordProblem(Self.owedEditSentence)
        return true
    }

    private func open(_ schedaPath: String) {
        guard let session = vault.session,
              let companion = session.companion(ofScheda: schedaPath),
              let url = try? session.store.url(for: companion)
        else { return }
        contenitore.openFile(url)
    }

    private func openScheda(_ schedaPath: String) {
        navigation.pane = .notes
        vault.openNote(at: schedaPath)
    }

    /// The file when it is there, the scheda otherwise, so a «file mancante» document still
    /// reveals something.
    private func reveal(_ schedaPath: String) {
        guard let session = vault.session else { return }
        let path = session.companion(ofScheda: schedaPath) ?? schedaPath
        guard let url = try? session.store.url(for: path) else { return }
        contenitore.revealFiles([url])
    }
}
