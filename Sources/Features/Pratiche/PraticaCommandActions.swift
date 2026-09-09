import AppKit
import SwiftUI

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 7 -
// R-30, R-31, R-34; ADR-0023 §D1.
//
// What each `PraticaCommand` and each `MessageCommand` actually does, in one place.
// The catalogues name a command once; this is the other half of the same rule, the
// shape `BoardCardActions`/`BoardCardMenuItems` already use for the canvas card: the
// row's context menu and the toolbar/footer call the *same* body rather than two
// bodies that happen to agree today.
//
// Every vault write here goes through `VaultSession.write` (ADR §D5) and every
// deletion through `FileManager.trashItem` (R-34, ADR-0022 §D7). «Escludi» and
// «Sposta in…» register one block each on the **window's** `UndoManager`, handed in
// from the view's `@Environment(\.undoManager)` (ADR-0026 §D5) - this type never
// reaches for `NSApp.keyWindow?.undoManager`.

/// «Rigenera…» waiting for its confirmation (UX-BLUEPRINT: a sheet, not an alert -
/// R-34's «Elimina pratica» is the only alert in the feature).
struct PraticaRegenerationRequest: Equatable, Identifiable, Sendable {
    var praticaPath: String
    var notePath: String
    var messageID: String
    var subject: String

    var id: String { notePath }
}

@MainActor
struct PraticaCommandActions {
    let pratiche: PraticheController
    let vault: VaultController
    let navigation: Navigation
    /// The window's own, from `@Environment(\.undoManager)`. `nil` in a preview and in
    /// a window that has none, which is reported rather than degraded silently
    /// (`VaultController.moveItems`'s own rule).
    var undoManager: UndoManager?
    /// The timeline's single Quick Look host (`PraticaTimelineView`), so «Anteprima
    /// allegato» opens the same panel a chip click does rather than a second one.
    var onQuickLook: ((URL) -> Void)?

    // MARK: - Applicability

    /// The commands a pratica row offers. Both surfaces ask this rather than deriving
    /// their own list, which is the whole of ADR-0023 §D8.
    func commands(for pratica: PraticaListItem) -> [PraticaCommand] {
        PraticaCommand.available(isActive: !PraticheSidebarGrouping.isClosed(status: pratica.status))
    }

    /// The commands a message row offers - `.previewAttachment` only when there is one
    /// to preview, a copied file or an over-threshold store reference alike.
    func commands(for detail: PraticaRowDetail?) -> [MessageCommand] {
        let hasAttachments = !(detail?.attachments.isEmpty ?? true)
            || !(detail?.storeReferences.isEmpty ?? true)
        return MessageCommand.available(hasAttachments: hasAttachments)
    }

    /// Where «Sposta in…» and «Aggiungi anche a…» may send a message: every other
    /// pratica, most recent first, the same order the add-from-Mail sheet uses.
    func destinations(besides praticaPath: String) -> [PraticaListItem] {
        AddToPraticaOrdering.recentFirst(pratiche.pratiche.filter { $0.id != praticaPath })
    }

    // MARK: - The pratica cluster (R-34)

    func run(_ command: PraticaCommand, on pratica: PraticaListItem) {
        switch command {
        case .open:
            navigation.pane = .pratiche
            pratiche.select(pratica.id, in: vault)
        case .rename:
            pratiche.renameRequest = pratica
        case .close:
            setStatus("archived", on: pratica)
        case .reopen:
            setStatus("active", on: pratica)
        case .refresh:
            Task { await pratiche.refreshNow(pratica.id, in: vault) }
        case .revealInFinder:
            guard let root = vault.root else { return }
            NSWorkspace.shared.activateFileViewerSelecting([
                root.appending(path: pratica.id, directoryHint: .isDirectory),
            ])
        case .delete:
            pratiche.deletionRequest = pratica
        }
    }

    /// R-34: the status tag swaps in `pratica.md` and **no file moves** - a closed
    /// pratica is where it always was, it is only told apart by its tag.
    private func setStatus(_ value: String, on pratica: PraticaListItem) {
        let path = Self.praticaNotePath(of: pratica.id)
        updateNote(at: path) { document in
            var tags = document.frontmatter.tags.filter { $0.namespace != .status }
            if let tag = Tag("status-\(value)") { tags.append(tag) }
            document.frontmatter.tags = TagRules.ordered(tags)
        }
        pratiche.load(from: vault)
    }

    /// R-34's «Elimina pratica», once the alert has been answered: the whole folder to
    /// the Trash, through the facade that already trashes a folder with `trashItem`
    /// and follows every note it held out of the open tabs.
    func confirmDeletion(of pratica: PraticaListItem) {
        pratiche.deletionRequest = nil
        guard vault.trashFolder(at: pratica.id) else { return }
        if pratiche.selection == pratica.id { pratiche.select(nil, in: vault) }
        pratiche.load(from: vault)
    }

    /// «Rinomina…», once a name has been typed. The folder rename repoints every
    /// canvas path that pointed inside it; the ledger follows the folder, since it is
    /// keyed by that path and a rename would otherwise lose the pratica's whole
    /// import history.
    func confirmRename(of pratica: PraticaListItem, to newName: String) {
        pratiche.renameRequest = nil
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != pratica.title else { return }
        guard let newPath = vault.renameFolder(at: pratica.id, to: trimmed) else { return }
        pratiche.moveLedgerState(from: pratica.id, to: newPath, in: vault)
        if pratiche.selection == pratica.id {
            pratiche.select(newPath, in: vault)
        } else {
            pratiche.load(from: vault)
        }
    }

    // MARK: - The message cluster (R-31)

    func run(_ command: MessageCommand, on entry: PraticaTimelineEntry, detail: PraticaRowDetail?) {
        guard !command.carriesArgument else {
            // Both surfaces draw an argument-carrying command as a submenu built from
            // the destinations, so reaching here means one rendered it as something it
            // is not (`BoardCardActions.run(_:on:)`'s own guard).
            assertionFailure("\(command) carries an argument and is invoked through its submenu")
            return
        }
        switch command {
        case .openInMail:
            guard let url = PraticaTimelineModel.subjectLink(
                messageID: entry.messageID, isInMail: entry.isInMail
            ).url else { return }
            NSWorkspace.shared.open(url)
        case .previewAttachment:
            guard let url = detail?.attachments.first?.url else { return }
            onQuickLook?(url)
        case .exclude:
            exclude(entry, detail: detail)
        case .regenerate:
            requestRegeneration(of: entry, detail: detail)
        case .moveTo, .alsoAddTo:
            break
        }
    }

    /// R-31: the files go to the Trash and the `Message-ID` joins
    /// `pergamenum-dossier-excluded`, which is what keeps the next sync from bringing
    /// it back (`MembershipRule.candidates` subtracts that key before anything else).
    ///
    /// The message's own `.md` and its `.eml` sidecar, and **not** its attachments: the
    /// sync stores one copy of an attachment per digest (`attachmentNameByDigest`), so
    /// a file in `allegati/` is very often somebody else's attachment too, and trashing
    /// it would break a message nobody asked to touch.
    func exclude(_ entry: PraticaTimelineEntry, detail: PraticaRowDetail?) {
        guard let praticaPath = praticaPath(of: entry, detail: detail),
              let messageID = entry.messageID,
              let detail
        else { return }

        let trashed = trash(filesOf: detail.notePath)
        guard !trashed.isEmpty else { return }
        updateDossier(at: praticaPath) { dossier in
            if !dossier.excluded.contains(messageID) { dossier.excluded.append(messageID) }
        }
        reload()

        register(undoName: "Escludi") { actions in
            actions.restore(trashed)
            actions.updateDossier(at: praticaPath) { dossier in
                dossier.excluded.removeAll { $0 == messageID }
            }
            actions.reload()
            actions.register(undoName: "Escludi") { redo in
                redo.exclude(entry, detail: detail)
            }
        }
    }

    /// R-31: the files move, and both dossiers are told - the source excludes the id
    /// (so its own sync never writes it back) and the destination includes it (so its
    /// own sync knows the message belongs there even outside a followed conversation).
    func move(_ entry: PraticaTimelineEntry, detail: PraticaRowDetail?, to destination: PraticaListItem) {
        guard let praticaPath = praticaPath(of: entry, detail: detail),
              let messageID = entry.messageID,
              let detail
        else { return }

        let moved = moveFiles(of: detail, from: praticaPath, to: destination.id)
        guard !moved.isEmpty else { return }
        updateDossier(at: praticaPath) { dossier in
            if !dossier.excluded.contains(messageID) { dossier.excluded.append(messageID) }
        }
        updateDossier(at: destination.id) { dossier in
            if !dossier.included.contains(messageID) { dossier.included.append(messageID) }
        }
        reload()

        register(undoName: "Sposta") { actions in
            actions.moveBack(moved)
            actions.updateDossier(at: praticaPath) { $0.excluded.removeAll { $0 == messageID } }
            actions.updateDossier(at: destination.id) { $0.included.removeAll { $0 == messageID } }
            actions.reload()
            actions.register(undoName: "Sposta") { redo in
                redo.move(entry, detail: detail, to: destination)
            }
        }
    }

    /// R-31: the files are copied, and **both** dossiers include the id - the message
    /// stays where it is and is now part of the other pratica as well.
    ///
    /// No undo block: this adds a file and changes nothing that was there, and
    /// «Escludi» on the copy is the way back. `UndoManager` would otherwise be carrying
    /// a step whose inverse is a deletion nobody asked for.
    func alsoAdd(_ entry: PraticaTimelineEntry, detail: PraticaRowDetail?, to destination: PraticaListItem) {
        guard let messageID = entry.messageID, let detail else { return }
        guard !copyFiles(of: detail, to: destination.id).isEmpty else { return }
        updateDossier(at: destination.id) { dossier in
            if !dossier.included.contains(messageID) { dossier.included.append(messageID) }
        }
        reload()
    }

    /// «Rigenera…» (§D6's second exception): asks first, because the message file may
    /// hold edits made by hand and rewriting it is exactly what §D6 otherwise forbids.
    private func requestRegeneration(of entry: PraticaTimelineEntry, detail: PraticaRowDetail?) {
        guard let praticaPath = praticaPath(of: entry, detail: detail),
              let messageID = entry.messageID, let detail
        else { return }
        guard entry.isInMail else {
            pratiche.report("«\(entry.subject)» non è più in Mail: non c'è nulla da cui rigenerarlo.")
            return
        }
        pratiche.regenerationRequest = PraticaRegenerationRequest(
            praticaPath: praticaPath, notePath: detail.notePath,
            messageID: messageID, subject: entry.subject
        )
    }

    /// The regeneration itself, once agreed to: the current files go to the Trash
    /// (recoverable, the only deletion convention this repo has), the id leaves the
    /// ledger so the message stops counting as already imported, and the pratica syncs
    /// - which writes the message again from Mail's own bytes.
    func confirmRegeneration(_ request: PraticaRegenerationRequest) {
        pratiche.regenerationRequest = nil
        guard !trash(filesOf: request.notePath).isEmpty else { return }
        pratiche.forgetImportedMessage(request.messageID, of: request.praticaPath, in: vault)
        Task { await pratiche.refreshNow(request.praticaPath, in: vault) }
    }

    // MARK: - The tray (R-30)

    /// «Aggiungi»: the conversation is followed from now on, and the sync that runs
    /// straight after imports it - "follows and imports", in that order, because the
    /// import reads the dossier from disk.
    func follow(_ proposal: PraticaTrayModel.PraticaTrayProposal) {
        guard let praticaPath = pratiche.selection else { return }
        updateDossier(at: praticaPath) { dossier in
            dossier = PraticaTrayModel.following(conversationID: proposal.conversationID, in: dossier)
        }
        pratiche.dismissTrayProposal(proposal.conversationID, for: praticaPath, in: vault)
        Task { await pratiche.refreshNow(praticaPath, in: vault) }
    }

    /// «Ignora»: one key of this pratica's own dossier, and nothing else - another
    /// pratica following the same counterpart still gets to propose it.
    func ignore(_ proposal: PraticaTrayModel.PraticaTrayProposal) {
        guard let praticaPath = pratiche.selection else { return }
        updateDossier(at: praticaPath) { dossier in
            dossier = PraticaTrayModel.ignoring(conversationID: proposal.conversationID, in: dossier)
        }
        pratiche.dismissTrayProposal(proposal.conversationID, for: praticaPath, in: vault)
    }

    // MARK: - Writing

    /// `pratica.md`'s dossier keys, read from the file and written back through
    /// `VaultSession.write`. Byte-preserving on every key it does not own
    /// (`Dossier.merging`, §D12).
    func updateDossier(at praticaPath: String, _ change: (inout Dossier) -> Void) {
        updateNote(at: Self.praticaNotePath(of: praticaPath)) { document in
            guard var dossier = Dossier.parse(document.frontmatter.foreignKeys) else { return }
            change(&dossier)
            document.frontmatter.foreignKeys = Dossier.merging(dossier, into: document.frontmatter.foreignKeys)
        }
    }

    /// One read-modify-write of a note, through the session so the index and the
    /// watcher stay in step - never `String.write(to:)`, which would leave the app
    /// looking at its own file as an external change.
    private func updateNote(at relativePath: String, _ change: (inout NoteDocument) -> Void) {
        guard let session = vault.session else { return }
        do {
            var document = NoteDocument.parse(try session.read(relativePath).text)
            let before = document
            change(&document)
            guard document != before else { return }
            try session.write(document.serialized(), to: relativePath)
        } catch {
            pratiche.report("«\(relativePath)» non è stato aggiornato: \(error.localizedDescription)")
        }
    }

    // MARK: - Files

    /// One file the Trash is holding, and where it came from - what makes «Escludi»
    /// undoable rather than confirmed (UX-BLUEPRINT).
    struct TrashedFile: Equatable, Sendable {
        var original: URL
        var inTrash: URL
        var relativePath: String
    }

    /// One file this batch moved, both ends, for the inverse.
    struct MovedFile: Equatable, Sendable {
        var from: URL
        var to: URL
    }

    /// The message's own `.md` and its `.eml` sidecar - see `exclude(_:detail:)` for
    /// why the attachments stay where they are.
    private func trash(filesOf notePath: String) -> [TrashedFile] {
        guard let root = vault.root else { return [] }
        var trashed: [TrashedFile] = []
        for relativePath in Self.messageFilePaths(of: notePath) {
            let url = root.appending(path: relativePath, directoryHint: .notDirectory)
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { continue }
            var landed: NSURL?
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: &landed)
            } catch {
                pratiche.report("«\(relativePath)» non è stato eliminato: \(error.localizedDescription)")
                continue
            }
            guard let inTrash = landed as URL? else { continue }
            trashed.append(TrashedFile(original: url, inTrash: inTrash, relativePath: relativePath))
        }
        return trashed
    }

    /// The inverse of `trash(filesOf:)`: back out of the Trash, to exactly where each
    /// file was.
    private func restore(_ files: [TrashedFile]) {
        for file in files {
            do {
                try FileManager.default.moveItem(at: file.inTrash, to: file.original)
            } catch {
                pratiche.report("«\(file.relativePath)» non è tornato al suo posto: \(error.localizedDescription)")
            }
        }
    }

    private func moveFiles(of detail: PraticaRowDetail, from praticaPath: String, to destination: String) -> [MovedFile] {
        guard let root = vault.root else { return [] }
        let folder = root
            .appending(path: destination, directoryHint: .isDirectory)
            .appending(path: PraticheController.messagesDirectoryName, directoryHint: .isDirectory)
        var moved: [MovedFile] = []
        for relativePath in Self.messageFilePaths(of: detail.notePath) {
            let source = root.appending(path: relativePath, directoryHint: .notDirectory)
            guard FileManager.default.fileExists(atPath: source.path(percentEncoded: false)) else { continue }
            guard let target = prepared(folder, for: source) else { continue }
            do {
                try FileManager.default.moveItem(at: source, to: target)
                moved.append(MovedFile(from: source, to: target))
            } catch {
                pratiche.report("«\(relativePath)» non è stato spostato: \(error.localizedDescription)")
            }
        }
        // The attachments are copied rather than moved for the same reason «Escludi»
        // leaves them alone: one file in `allegati/` can be several messages'
        // attachment, and this one is only taking its own copy with it.
        copyAttachments(of: detail, to: destination)
        return moved
    }

    private func copyFiles(of detail: PraticaRowDetail, to destination: String) -> [URL] {
        guard let root = vault.root else { return [] }
        let folder = root
            .appending(path: destination, directoryHint: .isDirectory)
            .appending(path: PraticheController.messagesDirectoryName, directoryHint: .isDirectory)
        var copied: [URL] = []
        for relativePath in Self.messageFilePaths(of: detail.notePath) {
            let source = root.appending(path: relativePath, directoryHint: .notDirectory)
            guard FileManager.default.fileExists(atPath: source.path(percentEncoded: false)) else { continue }
            guard let target = prepared(folder, for: source) else { continue }
            do {
                try FileManager.default.copyItem(at: source, to: target)
                copied.append(target)
            } catch {
                pratiche.report("«\(relativePath)» non è stato copiato: \(error.localizedDescription)")
            }
        }
        copyAttachments(of: detail, to: destination)
        return copied
    }

    private func copyAttachments(of detail: PraticaRowDetail, to destination: String) {
        guard !detail.attachments.isEmpty, let root = vault.root else { return }
        let folder = root
            .appending(path: destination, directoryHint: .isDirectory)
            .appending(path: PraticheController.attachmentsDirectoryName, directoryHint: .isDirectory)
        for attachment in detail.attachments {
            guard FileManager.default.fileExists(atPath: attachment.url.path(percentEncoded: false))
            else { continue }
            let target = folder.appending(path: attachment.name, directoryHint: .notDirectory)
            // The same name is the same attachment: the sync names an attachment after
            // its date and its own file name, so overwriting would be writing the same
            // bytes twice.
            guard !FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) else { continue }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: attachment.url, to: target)
            } catch {
                pratiche.report("«\(attachment.name)» non è stato copiato: \(error.localizedDescription)")
            }
        }
    }

    private func moveBack(_ files: [MovedFile]) {
        for file in files {
            do {
                try FileManager.default.moveItem(at: file.to, to: file.from)
            } catch {
                pratiche.report(
                    "«\(file.to.lastPathComponent)» non è tornato al suo posto: \(error.localizedDescription)"
                )
            }
        }
    }

    /// The destination folder, created if it is not there, and a name inside it that
    /// is free - `ImportNaming.uniqueFileName`'s `-2` rather than an overwrite, which
    /// would destroy whatever was already called that.
    private func prepared(_ folder: URL, for source: URL) -> URL? {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            pratiche.report("«\(folder.lastPathComponent)» non è stata creata: \(error.localizedDescription)")
            return nil
        }
        let name = ImportNaming.uniqueFileName(source.lastPathComponent, in: folder)
        return folder.appending(path: name, directoryHint: .notDirectory)
    }

    // MARK: - Plumbing

    /// The message's `.md` and the `.eml` beside it (R-09's sidecar), vault-relative.
    private static func messageFilePaths(of notePath: String) -> [String] {
        [notePath, (notePath as NSString).deletingPathExtension + ".eml"]
    }

    static func praticaNotePath(of praticaPath: String) -> String {
        "\(praticaPath)/\(PraticheController.praticaFileName)"
    }

    /// Which pratica a row belongs to: the folder its file sits in, never the current
    /// selection alone - a command invoked from a row is about that row.
    private func praticaPath(of entry: PraticaTimelineEntry, detail: PraticaRowDetail?) -> String? {
        guard let notePath = detail?.notePath,
              let range = notePath.range(of: "/\(PraticheController.messagesDirectoryName)/")
        else { return pratiche.selection }
        return String(notePath[..<range.lowerBound])
    }

    /// Re-reads what the writes above changed. The index is asked to rescan too,
    /// because files came and went and the list column counts them.
    private func reload() {
        pratiche.reloadTimeline(from: vault)
        Task { await vault.rescan() }
    }

    /// One block on the window's undo stack, or a reported refusal - never a silent
    /// degradation (ADR-0026 §D8's own rule, applied here).
    private func register(undoName: String, _ body: @escaping @MainActor (PraticaCommandActions) -> Void) {
        guard let undoManager else {
            pratiche.report("operazione non annullabile: nessun gestore di undo disponibile")
            return
        }
        undoManager.setActionName(undoName)
        undoManager.registerUndo(withTarget: pratiche) { [vault, navigation, undoManager, onQuickLook] _ in
            MainActor.assumeIsolated {
                body(PraticaCommandActions(
                    pratiche: pratiche, vault: vault, navigation: navigation,
                    undoManager: undoManager, onQuickLook: onQuickLook
                ))
            }
        }
    }
}

// MARK: - The two surfaces

/// The pratica row's context menu and the same catalogue drawn as a toolbar row.
///
/// Built by iterating `PraticaCommandActions.commands(for:)` rather than by listing
/// entries: the titles, the symbols and the applicability rules come from the
/// catalogue, so a surface cannot list a pratica's commands differently (ADR-0023 §D8).
@MainActor
enum PraticaMenuItems {
    @ViewBuilder
    static func menu(for pratica: PraticaListItem, actions: PraticaCommandActions) -> some View {
        ForEach(actions.commands(for: pratica), id: \.self) { command in
            if command == .delete { Divider() }
            Button(command.title) { actions.run(command, on: pratica) }
                .accessibilityIdentifier(command.identifier)
        }
    }
}

/// The message row's footer and its context menu (ADR-0023 §D1) - one catalogue, two
/// renderings, the argument-carrying pair drawn as a submenu of destinations on both.
@MainActor
enum MessageMenuItems {
    @ViewBuilder
    static func menu(
        for entry: PraticaTimelineEntry, detail: PraticaRowDetail?, actions: PraticaCommandActions
    ) -> some View {
        ForEach(actions.commands(for: detail), id: \.self) { command in
            item(command, entry: entry, detail: detail, actions: actions)
        }
    }

    @ViewBuilder
    static func item(
        _ command: MessageCommand,
        entry: PraticaTimelineEntry,
        detail: PraticaRowDetail?,
        actions: PraticaCommandActions
    ) -> some View {
        if command.carriesArgument {
            Menu(command.title) {
                destinations(command, entry: entry, detail: detail, actions: actions)
            }
            .accessibilityIdentifier(command.identifier)
        } else {
            Button(command.title) { actions.run(command, on: entry, detail: detail) }
                .accessibilityIdentifier(command.identifier)
        }
    }

    /// The submenu both surfaces build from the same list, so «Sposta in ▸» and
    /// «Aggiungi anche a ▸» cannot offer different pratiche in the menu and in the
    /// footer.
    @ViewBuilder
    private static func destinations(
        _ command: MessageCommand,
        entry: PraticaTimelineEntry,
        detail: PraticaRowDetail?,
        actions: PraticaCommandActions
    ) -> some View {
        let others = actions.destinations(besides: actions.praticaPathForMenu(of: detail))
        if others.isEmpty {
            Text("Nessun'altra pratica")
        } else {
            ForEach(others) { destination in
                Button("\(destination.client) › \(destination.title)") {
                    switch command {
                    case .moveTo: actions.move(entry, detail: detail, to: destination)
                    case .alsoAddTo: actions.alsoAdd(entry, detail: detail, to: destination)
                    default: break
                    }
                }
            }
        }
    }
}

extension PraticaCommandActions {
    /// The folder a row's file sits in, for the destinations submenu - the same
    /// arithmetic `praticaPath(of:detail:)` does, reachable from the menu builder.
    func praticaPathForMenu(of detail: PraticaRowDetail?) -> String {
        guard let notePath = detail?.notePath,
              let range = notePath.range(of: "/\(PraticheController.messagesDirectoryName)/")
        else { return pratiche.selection ?? "" }
        return String(notePath[..<range.lowerBound])
    }
}
