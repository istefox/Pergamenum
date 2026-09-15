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

    /// The filesystem half of this type, split out to its own file (ADR-0045 §D2,
    /// PG-143) - `exclude`, `move`, `alsoAdd` and `confirmRegeneration` below reach
    /// it rather than trashing/moving/copying files themselves.
    private var files: PraticaFileOperations {
        PraticaFileOperations(vault: vault, pratiche: pratiche)
    }

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
            Task { @MainActor in await setStatus("archived", on: pratica) }
        case .reopen:
            Task { @MainActor in await setStatus("active", on: pratica) }
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
    private func setStatus(_ value: String, on pratica: PraticaListItem) async {
        let path = PraticaNaming.praticaNotePath(of: pratica.id)
        await updateNote(at: path) { document in
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
            Task { @MainActor in await exclude(entry, detail: detail) }
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
    func exclude(_ entry: PraticaTimelineEntry, detail: PraticaRowDetail?) async {
        guard let praticaPath = praticaPath(detail: detail),
              let messageID = entry.messageID,
              let detail
        else { return }

        let trashed = files.trash(filesOf: detail.notePath)
        guard !trashed.isEmpty else { return }
        await updateDossier(at: praticaPath) { dossier in
            if !dossier.excluded.contains(messageID) { dossier.excluded.append(messageID) }
        }
        reload()

        register(undoName: "Escludi") { actions in
            actions.files.restore(trashed)
            await actions.updateDossier(at: praticaPath) { dossier in
                dossier.excluded.removeAll { $0 == messageID }
            }
            actions.reload()
            actions.register(undoName: "Escludi") { redo in
                await redo.exclude(entry, detail: detail)
            }
        }
    }

    /// R-31: the files move, and both dossiers are told - the source excludes the id
    /// (so its own sync never writes it back) and the destination includes it (so its
    /// own sync knows the message belongs there even outside a followed conversation).
    func move(
        _ entry: PraticaTimelineEntry, detail: PraticaRowDetail?, to destination: PraticaListItem
    ) async {
        guard let praticaPath = praticaPath(detail: detail),
              let messageID = entry.messageID,
              let detail
        else { return }

        let (moved, rewrites) = files.moveFiles(of: detail, to: destination.id)
        guard !moved.isEmpty else { return }
        await updateDossier(at: praticaPath) { dossier in
            if !dossier.excluded.contains(messageID) { dossier.excluded.append(messageID) }
        }
        await updateDossier(at: destination.id) { dossier in
            if !dossier.included.contains(messageID) { dossier.included.append(messageID) }
        }
        reload()

        register(undoName: "Sposta") { actions in
            let restored = actions.files.moveBack(moved)
            if let root = actions.vault.root,
               restored.contains(root.appending(path: detail.notePath, directoryHint: .notDirectory)) {
                actions.files.reverseContentRewrites(rewrites, notePath: detail.notePath)
            }
            await actions.updateDossier(at: praticaPath) { $0.excluded.removeAll { $0 == messageID } }
            await actions.updateDossier(at: destination.id) { $0.included.removeAll { $0 == messageID } }
            actions.reload()
            actions.register(undoName: "Sposta") { redo in
                await redo.move(entry, detail: detail, to: destination)
            }
        }
    }

    /// R-31: the files are copied, and **both** dossiers include the id - the message
    /// stays where it is and is now part of the other pratica as well.
    ///
    /// No undo block: this adds a file and changes nothing that was there, and
    /// «Escludi» on the copy is the way back. `UndoManager` would otherwise be carrying
    /// a step whose inverse is a deletion nobody asked for.
    func alsoAdd(
        _ entry: PraticaTimelineEntry, detail: PraticaRowDetail?, to destination: PraticaListItem
    ) async {
        guard let messageID = entry.messageID, let detail else { return }
        guard !files.copyFiles(of: detail, to: destination.id).isEmpty else { return }
        await updateDossier(at: destination.id) { dossier in
            if !dossier.included.contains(messageID) { dossier.included.append(messageID) }
        }
        reload()
    }

    /// «Rigenera…» (§D6's second exception, §D21): asks first, because the message
    /// file may hold edits made by hand. Unlike the old confirm-then-sync flow, the
    /// replacement text and its diff against what is on disk are acquired *before*
    /// anything is trashed - `prepareRegeneration` fills `pratiche.regeneration` with
    /// `.ready` once it resolves, or clears it and reports on failure.
    private func requestRegeneration(of entry: PraticaTimelineEntry, detail: PraticaRowDetail?) {
        guard let praticaPath = praticaPath(detail: detail),
              let messageID = entry.messageID, let detail
        else { return }
        guard entry.isInMail else {
            pratiche.report("«\(entry.subject)» non è più in Mail: non c'è nulla da cui rigenerarlo.")
            return
        }
        pratiche.regeneration = .preparing(notePath: detail.notePath, subject: entry.subject)
        Task { await pratiche.prepareRegeneration?(praticaPath, messageID) }
    }

    /// The regeneration itself, once the diff has been shown and agreed to (§D21.4):
    /// the current files go to the Trash first (recoverable, the only deletion
    /// convention this repo has), then the previewed replacement is committed - put
    /// back if that fails, so «Rigenera» never leaves the message file missing.
    func confirmRegeneration(_ plan: PraticaSyncEngine.RegenerationPlan) {
        pratiche.regeneration = nil
        let trashed = files.trash(filesOf: plan.notePath)
        guard !trashed.isEmpty else { return }
        Task {
            let succeeded = await pratiche.commitRegeneration?(plan) ?? false
            if !succeeded { files.restore(trashed) }
            reload()
        }
    }

    // MARK: - The tray (R-30)

    /// «Aggiungi»: the conversation is followed from now on, and the sync that runs
    /// straight after imports it - "follows and imports", in that order, because the
    /// import reads the dossier from disk.
    func follow(_ proposal: PraticaTrayModel.PraticaTrayProposal) async {
        guard let praticaPath = pratiche.selection else { return }
        await updateDossier(at: praticaPath) { dossier in
            dossier = PraticaTrayModel.following(conversationID: proposal.conversationID, in: dossier)
        }
        pratiche.dismissTrayProposal(proposal.conversationID, for: praticaPath, in: vault)
        await pratiche.refreshNow(praticaPath, in: vault)
    }

    /// «Ignora»: one key of this pratica's own dossier, and nothing else - another
    /// pratica following the same counterpart still gets to propose it.
    func ignore(_ proposal: PraticaTrayModel.PraticaTrayProposal) async {
        guard let praticaPath = pratiche.selection else { return }
        await updateDossier(at: praticaPath) { dossier in
            dossier = PraticaTrayModel.ignoring(conversationID: proposal.conversationID, in: dossier)
        }
        pratiche.dismissTrayProposal(proposal.conversationID, for: praticaPath, in: vault)
    }

    // MARK: - Writing

    /// `pratica.md`'s dossier keys, read from the file and written back through
    /// `VaultSession.write`. Byte-preserving on every key it does not own
    /// (`Dossier.merging`, §D12).
    ///
    /// `async` rather than a hop of its own (ADR-0043 §D2), and that is load-bearing for
    /// `follow(_:)` just below: "follows and imports, in that order, because the import
    /// reads the dossier from disk". A wrapper that returned before its write landed would
    /// let the sync read the file the follow had not written yet.
    func updateDossier(at praticaPath: String, _ change: (inout Dossier) -> Void) async {
        guard let session = vault.session else { return }
        if let message = await DossierWriter.update(at: praticaPath, session: session, change) {
            pratiche.report(message)
        }
    }

    /// One read-modify-write of a note, through the session so the index and the
    /// watcher stay in step - never `String.write(to:)`, which would leave the app
    /// looking at its own file as an external change.
    ///
    /// `expecting:` (ADR-0043 §D8, Task 9): identical shape to `DossierWriter.update`,
    /// identical reason.
    private func updateNote(at relativePath: String, _ change: (inout NoteDocument) -> Void) async {
        guard let session = vault.session else { return }
        do {
            let (record, text) = try session.read(relativePath)
            var document = NoteDocument.parse(text)
            let before = document
            change(&document)
            guard document != before else { return }
            try await session.write(document.serialized(), to: relativePath, expecting: record.contentHash)
        } catch let refusal as VaultSession.WriteRefusal {
            pratiche.report("«\(relativePath)» non è stato aggiornato: \(refusal.description)")
        } catch {
            pratiche.report("«\(relativePath)» non è stato aggiornato: \(error.localizedDescription)")
        }
    }

    // MARK: - Plumbing

    /// Which pratica a row belongs to: the folder its file sits in, never the current
    /// selection alone - a command invoked from a row is about that row.
    private func praticaPath(detail: PraticaRowDetail?) -> String? {
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
    ///
    /// The body is `async` since ADR-0043 §D2 and the hop is here, once, rather than inside
    /// each body: `registerUndo`'s handler is synchronous, and an undo that put its files
    /// back before writing the dossier they belong to has an order of its own to keep.
    private func register(
        undoName: String, _ body: @escaping @MainActor (PraticaCommandActions) async -> Void
    ) {
        guard let undoManager else {
            pratiche.report("operazione non annullabile: nessun gestore di undo disponibile")
            return
        }
        undoManager.setActionName(undoName)
        undoManager.registerUndo(withTarget: pratiche) { [vault, navigation, undoManager, onQuickLook] _ in
            MainActor.assumeIsolated {
                // Bound first rather than built inside the `Task`: a single-expression
                // `assumeIsolated` closure whose one expression is a `Task` leaves the
                // task's own result type to infer, and the initializer goes ambiguous.
                let actions = PraticaCommandActions(
                    pratiche: pratiche, vault: vault, navigation: navigation,
                    undoManager: undoManager, onQuickLook: onQuickLook
                )
                Task { @MainActor in await body(actions) }
            }
        }
    }
}
