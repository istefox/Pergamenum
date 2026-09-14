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
        let path = Self.praticaNotePath(of: pratica.id)
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

        let trashed = trash(filesOf: detail.notePath)
        guard !trashed.isEmpty else { return }
        await updateDossier(at: praticaPath) { dossier in
            if !dossier.excluded.contains(messageID) { dossier.excluded.append(messageID) }
        }
        reload()

        register(undoName: "Escludi") { actions in
            actions.restore(trashed)
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

        let (moved, rewrites) = moveFiles(of: detail, to: destination.id)
        guard !moved.isEmpty else { return }
        await updateDossier(at: praticaPath) { dossier in
            if !dossier.excluded.contains(messageID) { dossier.excluded.append(messageID) }
        }
        await updateDossier(at: destination.id) { dossier in
            if !dossier.included.contains(messageID) { dossier.included.append(messageID) }
        }
        reload()

        register(undoName: "Sposta") { actions in
            let restored = actions.moveBack(moved)
            if let root = actions.vault.root,
               restored.contains(root.appending(path: detail.notePath, directoryHint: .notDirectory)) {
                actions.reverseContentRewrites(rewrites, notePath: detail.notePath)
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
        guard !copyFiles(of: detail, to: destination.id).isEmpty else { return }
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
        let trashed = trash(filesOf: plan.notePath)
        guard !trashed.isEmpty else { return }
        Task {
            let succeeded = await pratiche.commitRegeneration?(plan) ?? false
            if !succeeded { restore(trashed) }
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
    private func updateNote(at relativePath: String, _ change: (inout NoteDocument) -> Void) async {
        guard let session = vault.session else { return }
        do {
            var document = NoteDocument.parse(try session.read(relativePath).text)
            let before = document
            change(&document)
            guard document != before else { return }
            try await session.write(document.serialized(), to: relativePath)
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

    /// One `[[oldName]] -> [[newName]]` attachment-link rewrite made inside a moved/
    /// copied `.md`, so `moveBack` can put it back in the reverse direction.
    private struct AttachmentRename {
        var from: String
        var to: String
    }

    /// Everything a transfer's undo needs beyond the file paths themselves: the
    /// collision-driven content rewrites `moveFiles` and `copyAttachments` made
    /// *inside* the moved `.md` - restoring paths alone would leave the restored
    /// message pointing at a sidecar/attachment name that only made sense at the
    /// destination it was forced to collide at.
    private struct ContentRewrites {
        var originalBaseName: String
        /// `nil` when no `.md`/`.eml` collision happened at all.
        var renamedBaseName: String?
        var attachmentRenames: [AttachmentRename] = []
    }

    private func moveFiles(
        of detail: PraticaRowDetail, to destination: String
    ) -> (files: [MovedFile], rewrites: ContentRewrites) {
        let originalBaseName = (detail.notePath as NSString).lastPathComponent
            .replacingOccurrences(of: ".md", with: "")
        var rewrites = ContentRewrites(originalBaseName: originalBaseName, renamedBaseName: nil)
        guard let root = vault.root else { return ([], rewrites) }
        let folder = root
            .appending(path: destination, directoryHint: .isDirectory)
            .appending(path: PraticheController.messagesDirectoryName, directoryHint: .isDirectory)
        guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil
        else {
            pratiche.report("«\(folder.lastPathComponent)» non è stata creata.")
            return ([], rewrites)
        }
        // Reserved once, for BOTH the `.md` and its `.eml` sidecar: a collision on
        // either extension alone would otherwise rename just that one file, leaving
        // `pergamenum-mail-original` pointing at a sidecar name that no longer exists.
        let baseName = Self.reservedBaseName(for: detail.notePath, in: folder)
        var moved: [MovedFile] = []
        var movedMD: URL?
        for relativePath in Self.messageFilePaths(of: detail.notePath) {
            let source = root.appending(path: relativePath, directoryHint: .notDirectory)
            guard FileManager.default.fileExists(atPath: source.path(percentEncoded: false)) else { continue }
            let ext = (relativePath as NSString).pathExtension
            let target = folder.appending(path: "\(baseName).\(ext)", directoryHint: .notDirectory)
            do {
                try FileManager.default.moveItem(at: source, to: target)
                moved.append(MovedFile(from: source, to: target))
                if ext == "md" { movedMD = target }
            } catch {
                pratiche.report("«\(relativePath)» non è stato spostato: \(error.localizedDescription)")
            }
        }
        if let movedMD, baseName != originalBaseName {
            Self.updateOriginalReference(at: movedMD, to: "\(baseName).eml")
            rewrites.renamedBaseName = baseName
        }
        // The attachments are copied rather than moved for the same reason «Escludi»
        // leaves them alone: one file in `allegati/` can be several messages'
        // attachment, and this one is only taking its own copy with it.
        rewrites.attachmentRenames = copyAttachments(of: detail, to: destination, patching: movedMD)
        return (moved, rewrites)
    }

    /// The inverse of `moveFiles`'s `rewrites`: put the moved `.md`'s OWN text back
    /// to what it said before the transfer, once `moveBack` has put the files back
    /// at their original paths. Order matters no more than `moveFiles`'s own two
    /// independent rewrites did - the sidecar reference and each attachment link are
    /// disjoint pieces of text.
    private func reverseContentRewrites(_ rewrites: ContentRewrites, notePath: String) {
        guard let root = vault.root else { return }
        let mdURL = root.appending(path: notePath, directoryHint: .notDirectory)
        if rewrites.renamedBaseName != nil {
            Self.updateOriginalReference(at: mdURL, to: "\(rewrites.originalBaseName).eml")
        }
        for rename in rewrites.attachmentRenames {
            Self.renameAttachmentReference(in: mdURL, from: rename.to, to: rename.from)
        }
    }

    private func copyFiles(of detail: PraticaRowDetail, to destination: String) -> [URL] {
        guard let root = vault.root else { return [] }
        let folder = root
            .appending(path: destination, directoryHint: .isDirectory)
            .appending(path: PraticheController.messagesDirectoryName, directoryHint: .isDirectory)
        guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil
        else {
            pratiche.report("«\(folder.lastPathComponent)» non è stata creata.")
            return []
        }
        let baseName = Self.reservedBaseName(for: detail.notePath, in: folder)
        var copied: [URL] = []
        var copiedMD: URL?
        for relativePath in Self.messageFilePaths(of: detail.notePath) {
            let source = root.appending(path: relativePath, directoryHint: .notDirectory)
            guard FileManager.default.fileExists(atPath: source.path(percentEncoded: false)) else { continue }
            let ext = (relativePath as NSString).pathExtension
            let target = folder.appending(path: "\(baseName).\(ext)", directoryHint: .notDirectory)
            do {
                try FileManager.default.copyItem(at: source, to: target)
                copied.append(target)
                if ext == "md" { copiedMD = target }
            } catch {
                pratiche.report("«\(relativePath)» non è stato copiato: \(error.localizedDescription)")
            }
        }
        if let copiedMD, baseName != (detail.notePath as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "") {
            Self.updateOriginalReference(at: copiedMD, to: "\(baseName).eml")
        }
        copyAttachments(of: detail, to: destination, patching: copiedMD)
        return copied
    }

    /// One free basename for BOTH extensions, checked together - `ImportNaming
    /// .uniqueFileName` only ever frees one file's own name, which is exactly the gap
    /// `moveFiles`/`copyFiles` used to fall into when only the `.md` or only the
    /// `.eml` collided.
    private static func reservedBaseName(for notePath: String, in folder: URL) -> String {
        let stem = (notePath as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "")
        var candidate = stem
        var suffix = 2
        func taken(_ ext: String) -> Bool {
            FileManager.default.fileExists(
                atPath: folder.appending(path: "\(candidate).\(ext)", directoryHint: .notDirectory)
                    .path(percentEncoded: false)
            )
        }
        while taken("md") || taken("eml") {
            candidate = "\(stem)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    /// A byte-preserving patch of one scalar line, the same discipline
    /// `Dossier.merging` already applies to keys it does not own - re-rendering the
    /// whole document through `MessageDocument.render` would need the note's `tags`/
    /// `related`/`aliases` this function never had a reason to load.
    private static func updateOriginalReference(at mdURL: URL, to emlFileName: String) {
        guard var text = try? String(contentsOf: mdURL, encoding: .utf8) else { return }
        guard let range = text.range(
            of: #"pergamenum-mail-original:\s*"[^"]*""#, options: .regularExpression
        ) else { return }
        text.replaceSubrange(range, with: "pergamenum-mail-original: \"\(emlFileName)\"")
        try? text.write(to: mdURL, atomically: true, encoding: .utf8)
    }

    /// Renames every `[[oldName]]`/`![[oldName]]` reference to `attachment` inside the
    /// transferred message to `newName` - the other half of resolving a same-name,
    /// different-bytes collision (the file itself already got the new name).
    private static func renameAttachmentReference(in mdURL: URL?, from oldName: String, to newName: String) {
        applyAttachmentRenames([AttachmentRename(from: oldName, to: newName)], toFileAt: mdURL)
    }

    /// Every rename applied in ONE pass over the file's ORIGINAL text, keyed by the
    /// bracketed name each `[[...]]` token actually names - never as a sequence of
    /// `replacingOccurrences` calls. Two renames chained that way can cascade: once
    /// `quote.pdf` becomes `quote-2.pdf`, a SEPARATE `quote-2.pdf -> quote-2-2.pdf`
    /// pass would catch that just-rewritten text too, redirecting both attachments
    /// onto the same final name. Reading the map against the untouched original
    /// text is what keeps each token's rewrite independent of every other one's.
    private static func applyAttachmentRenames(_ renames: [AttachmentRename], toFileAt mdURL: URL?) {
        guard let mdURL, !renames.isEmpty, let text = try? String(contentsOf: mdURL, encoding: .utf8)
        else { return }
        let map = Dictionary(uniqueKeysWithValues: renames.map { ($0.from, $0.to) })
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#) else { return }
        let nsText = text as NSString
        var result = ""
        var lastEnd = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            result += nsText.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
            let name = nsText.substring(with: match.range(at: 1))
            result += "[[\(map[name] ?? name)]]"
            lastEnd = match.range.location + match.range.length
        }
        result += nsText.substring(from: lastEnd)
        guard result != text else { return }
        try? result.write(to: mdURL, atomically: true, encoding: .utf8)
    }

    @discardableResult
    private func copyAttachments(
        of detail: PraticaRowDetail, to destination: String, patching mdURL: URL?
    ) -> [AttachmentRename] {
        guard !detail.attachments.isEmpty, let root = vault.root else { return [] }
        let folder = root
            .appending(path: destination, directoryHint: .isDirectory)
            .appending(path: PraticheController.attachmentsDirectoryName, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            pratiche.report("«\(folder.lastPathComponent)» non è stata creata: \(error.localizedDescription)")
            return []
        }
        let existingOnDisk = Set(
            (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        )
        // Every destination name reserved BEFORE any copy or rewrite happens, in one
        // planning pass - deciding a later attachment's unique name only after an
        // earlier one has already claimed (or been copied to) its own target is what
        // let two distinct attachments collide onto the same new name (:506).
        struct Plan { var attachment: PraticaAttachmentRef; var targetName: String; var reused: Bool }
        var claimed = existingOnDisk
        var plans: [Plan] = []
        // Two references sharing the same name are the SAME attachment (its `.name` is
        // its `Identifiable` id) referenced twice, not two distinct files that happen to
        // collide - planning a second `AttachmentRename` for a name already planned
        // would give `applyAttachmentRenames` a duplicate `from` key, which crashes
        // `Dictionary(uniqueKeysWithValues:)` AFTER the first copy already landed on
        // disk (:530). One plan per name; the single rename it produces already covers
        // every `[[name]]` occurrence in the note.
        var plannedNames: Set<String> = []
        for attachment in detail.attachments {
            guard plannedNames.insert(attachment.name).inserted else { continue }
            guard FileManager.default.fileExists(atPath: attachment.url.path(percentEncoded: false))
            else { continue }
            // The same name is the same attachment only when it is ALREADY on disk
            // (bytes to compare against) AND no earlier attachment in this same
            // batch has already claimed it as ITS OWN target - a name only reserved
            // so far, with nothing written yet, has no bytes this one could match.
            if existingOnDisk.contains(attachment.name), plans.allSatisfy({ $0.targetName != attachment.name }) {
                let target = folder.appending(path: attachment.name, directoryHint: .notDirectory)
                if Self.contentsMatch(attachment.url, target) {
                    plans.append(Plan(attachment: attachment, targetName: attachment.name, reused: true))
                    continue
                }
            }
            let targetName = claimed.contains(attachment.name)
                ? Self.reservedAttachmentName(attachment.name, avoiding: claimed)
                : attachment.name
            claimed.insert(targetName)
            plans.append(Plan(attachment: attachment, targetName: targetName, reused: false))
        }
        var renames: [AttachmentRename] = []
        for plan in plans where !plan.reused {
            let target = folder.appending(path: plan.targetName, directoryHint: .notDirectory)
            do {
                try FileManager.default.copyItem(at: plan.attachment.url, to: target)
                if plan.targetName != plan.attachment.name {
                    renames.append(AttachmentRename(from: plan.attachment.name, to: plan.targetName))
                }
            } catch {
                pratiche.report("«\(plan.attachment.name)» non è stato copiato: \(error.localizedDescription)")
            }
        }
        Self.applyAttachmentRenames(renames, toFileAt: mdURL)
        return renames
    }

    /// `ImportNaming.uniqueFileName`'s own rule (`-2`, `-3`, ...), but checked
    /// against a batch's in-flight reservations rather than the filesystem alone -
    /// the filesystem has nothing to check yet for a name this same call is about to
    /// claim for an earlier attachment.
    private static func reservedAttachmentName(_ proposed: String, avoiding reserved: Set<String>) -> String {
        let stem = (proposed as NSString).deletingPathExtension
        let ext = (proposed as NSString).pathExtension
        var suffix = 2
        var candidate = ext.isEmpty ? "\(stem)-\(suffix)" : "\(stem)-\(suffix).\(ext)"
        while reserved.contains(candidate) {
            suffix += 1
            candidate = ext.isEmpty ? "\(stem)-\(suffix)" : "\(stem)-\(suffix).\(ext)"
        }
        return candidate
    }

    /// Returns the `from` URL of every file actually restored - the caller must not
    /// rewrite content back into a path whose restore failed, since that path may by
    /// now hold an unrelated note that merely reused the same name.
    @discardableResult
    private func moveBack(_ files: [MovedFile]) -> Set<URL> {
        var restored: Set<URL> = []
        for file in files {
            do {
                try FileManager.default.moveItem(at: file.to, to: file.from)
                restored.insert(file.from)
            } catch {
                pratiche.report(
                    "«\(file.to.lastPathComponent)» non è tornato al suo posto: \(error.localizedDescription)"
                )
            }
        }
        return restored
    }

    /// Byte comparison, never a size/date *equality* shortcut: two attachments genuinely
    /// can share a size by coincidence, and this decides whether a destination file gets
    /// reused or renamed. Unequal sizes are the one thing a stat can settle, since they
    /// rule a match out outright.
    private static func contentsMatch(_ lhs: URL, _ rhs: URL) -> Bool {
        // Two files of different sizes cannot hold the same bytes, and a size is a stat
        // rather than a read of two attachments into memory. Every other case - equal
        // sizes, or a size that cannot be read at all - still goes to the byte comparison,
        // which stays the thing that decides.
        if let lhsSize = try? lhs.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           let rhsSize = try? rhs.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           lhsSize != rhsSize {
            return false
        }
        guard let a = try? Data(contentsOf: lhs), let b = try? Data(contentsOf: rhs) else { return false }
        return a == b
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
                    Task { @MainActor in
                        switch command {
                        case .moveTo: await actions.move(entry, detail: detail, to: destination)
                        case .alsoAddTo: await actions.alsoAdd(entry, detail: detail, to: destination)
                        default: break
                        }
                    }
                }
            }
        }
    }
}

extension PraticaCommandActions {
    /// The folder a row's file sits in, for the destinations submenu - the same
    /// arithmetic `praticaPath(detail:)` does, reachable from the menu builder.
    func praticaPathForMenu(of detail: PraticaRowDetail?) -> String {
        guard let notePath = detail?.notePath,
              let range = notePath.range(of: "/\(PraticheController.messagesDirectoryName)/")
        else { return pratiche.selection ?? "" }
        return String(notePath[..<range.lowerBound])
    }
}
