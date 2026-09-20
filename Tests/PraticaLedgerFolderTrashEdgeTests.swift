import Foundation
import Testing
@testable import Pergamenum

// PG-169, ADR-0026 §D7's 2026-09-19 amendment - the edge cases the SPEC names that the two
// batteries beside this file (`PraticaLedgerFolderTrashTests`, `PraticaLiveSyncTrashedMidRun
// Tests`) leave to a sentence rather than an assertion:
//
// - R-05, at the level of state rather than of the hook: a trash that was refused or failed
//   leaves the ledger key, the selection and the file on disk exactly where they were, with
//   the hook WIRED to the real Pratiche controller (the door-level tests only count calls).
// - "Ledger cannot be saved": reported through `problem`, memory still cleaned.
// - R-08 end to end: not just "the key is absent" but "the recreated pratica's first real
//   sync starts from nothing and still imports its message". The control half (hook unwired)
//   shows the stale ledger leaking, so the second half cannot pass by accident. See that
//   test's own header: the ticket's "messages silently skipped" symptom does not reproduce.
// - R-06's preview half: `prepareRegeneration`'s own guard on a trashed folder, and the one
//   sentence chooser both regeneration guards share.
// - A trash that reaches a sync AND a regeneration at once, each under a different pratica.

private let plainPratica = """
---
pergamenum-dossier: 1
pergamenum-dossier-counterparts:
  - m.rossi@rossi-spa.it
---

Appunti pratica.
"""

/// Follows its message BY `Message-ID` (`pergamenum-dossier-included`), not by conversation -
/// see the R-08 test's header for why that is the shape in which a stale `importedMessageIDs`
/// can silently skip a message at all.
private let followedPratica = """
---
date: 2026-09-01
tags:
  - type-note
  - topic-pratica
  - client-rossi
  - status-active
  - source-email
pergamenum-dossier: 1
pergamenum-dossier-counterparts:
  - m.rossi@rossi-spa.it
pergamenum-dossier-included:
  - "<abc123@rossi-spa.it>"
---

Appunti pratica.
"""

private func stateImporting(_ ids: String...) -> PraticaLedger.PraticaState {
    var state = PraticaLedger.PraticaState.empty
    state.importedMessageIDs = ids
    return state
}

private func listItem(_ path: String) -> PraticaListItem {
    PraticaListItem(
        id: path, title: "Tifone", client: "rossi", status: "active",
        lastActivity: Date(), messagesSinceLastOpen: 0, hasNonEmptyTray: false
    )
}

@MainActor
private func stop(continuing path: String, on controller: PraticheController) -> PraticaRunStop? {
    do {
        _ = try controller.praticaPath(continuing: path)
        return nil
    } catch {
        return error as? PraticaRunStop
    }
}

@MainActor
@Suite(.serialized) struct PraticaLedgerFolderTrashEdgeTests {
    private static let folder = PraticaSyncFixtures.praticaFolder

    // MARK: - R-05 at the level of state

    /// «Elimina pratica» on a folder holding an unsaved note is refused by the door. The
    /// hook is wired to a real controller, so this is the state-level twin of
    /// `aRefusedTrashPublishesNothing`: whatever the hook would have done, it must not have
    /// done it, and `confirmDeletion` (which no longer deselects by itself) must not have
    /// either.
    @Test func aRefusedDeletionThroughItsOwnCommandKeepsTheKeyTheSelectionAndTheFolder() async throws {
        let vault = try TemporaryVault()
        let path = "01 Progetti/Tifone"
        try vault.write(plainPratica, to: "\(path)/pratica.md")
        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let session = try #require(vaultController.session)
        let url = PraticheController.ledgerURL(for: session)
        let pratiche = PraticheController.live(vault: vaultController)
        var published: [String] = []
        vaultController.didTrashFolder = { [weak pratiche] trashed in
            published.append(trashed)
            pratiche?.followFolderTrashing(trashed, in: vaultController)
        }
        let item = listItem(path)
        pratiche.select(item.id, in: vaultController)
        // Through the door with the real session: memory and disk together, as this seed always was.
        // `select` has just loaded the ledger, so a file written beside it would leave memory behind.
        pratiche.updateLedger(.live(session)) { $0.byPraticaPath[path] = stateImporting("<a@rossi-spa.it>") }
        vaultController.openNote(at: "\(path)/pratica.md")
        vaultController.updateOpenNoteText(plainPratica + "\nModifica non salvata.\n")
        let actions = PraticaCommandActions(pratiche: pratiche, vault: vaultController, navigation: Navigation())

        actions.confirmDeletion(of: item)

        #expect(published.isEmpty, "precondition of the rest: the door refused, so nothing was published")
        #expect(
            pratiche.ledger.byPraticaPath[path]?.importedMessageIDs == ["<a@rossi-spa.it>"],
            "a refused trash must leave the ledger key, and what it recorded, alone"
        )
        #expect(PraticaLedger.load(from: url).byPraticaPath[path]?.importedMessageIDs == ["<a@rossi-spa.it>"])
        #expect(pratiche.selection == path, "the pratica is still there, so it is still the open one")
        #expect(
            FileManager.default.fileExists(atPath: vault.root.appending(path: path).path(percentEncoded: false)),
            "and so is the folder"
        )
        #expect(pratiche.forgottenPraticaPaths.isEmpty)

        vaultController.close()
    }

    /// A trash that THROWS inside the session (a folder that does not exist, the vault root)
    /// with the hook wired to the real controller: every pratica key stays, including the
    /// one whose folder is fine, and the in-memory tray state with it.
    @Test func aFailedTrashThroughTheDoorLeavesEveryPraticaKeyAlone() async throws {
        let vault = try TemporaryVault()
        try vault.write(plainPratica, to: "01 Progetti/Tifone/pratica.md")
        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let session = try #require(vaultController.session)
        let url = PraticheController.ledgerURL(for: session)
        let pratiche = PraticheController.live(vault: vaultController)
        vaultController.didTrashFolder = { [weak pratiche] trashed in
            pratiche?.followFolderTrashing(trashed, in: vaultController)
        }
        // Through the door with the real session: no trash reaches the hook here, so nothing else
        // would load the ledger, and the assertions below read it from memory as well as from disk.
        pratiche.updateLedger(.live(session)) {
            $0.byPraticaPath["01 Progetti/Tifone"] = stateImporting("<a@rossi-spa.it>")
        }
        pratiche.trayCounts["01 Progetti/Tifone"] = 4

        let missing = vaultController.trashFolder(at: "01 Progetti/mai-esistita")
        let root = vaultController.trashFolder(at: "")

        #expect(missing == false)
        #expect(root == false, "the vault root is refused outright, and its state is 'everything'")
        #expect(pratiche.ledger.byPraticaPath["01 Progetti/Tifone"]?.importedMessageIDs == ["<a@rossi-spa.it>"])
        #expect(pratiche.trayCounts["01 Progetti/Tifone"] == 4)
        #expect(PraticaLedger.load(from: url).byPraticaPath["01 Progetti/Tifone"] != nil)

        vaultController.close()
    }

    // MARK: - "Ledger cannot be saved"

    /// SPEC edge case: the failure goes through the existing problem channel, and the
    /// in-memory state is still cleaned. A READABLE ledger inside a state directory that
    /// refuses new files makes the atomic replace fail: the read succeeds, and the write,
    /// which needs a temporary file beside its target, does not.
    ///
    /// Not a directory at the ledger's own URL, this test's arrangement before ADR-0052: that
    /// is an unreadable ledger (§D3), refused before any save is attempted, and a different
    /// path from the one this test exists to pin.
    @Test func aLedgerThatCannotBeSavedIsReportedAndStillForgottenInMemory() async throws {
        let vault = try TemporaryVault()
        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let session = try #require(vaultController.session)
        var seeded = PraticaLedger.empty
        seeded.byPraticaPath["01 Progetti/Tifone"] = stateImporting("<a@rossi-spa.it>")
        seeded.byPraticaPath["01 Progetti-altro/Y"] = .empty
        try seeded.save(to: PraticheController.ledgerURL(for: session))
        let stateDirectory = PraticheController.stateDirectory(for: session).path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: stateDirectory)
        // Restored on every exit: a 0o500 directory refuses its own removal, which would leave the
        // temporary vault behind (`FullDiskAccessProbeTests.restoreAndRemove`'s reason).
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stateDirectory) }
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        pratiche.trayCounts["01 Progetti/Tifone"] = 2
        #expect(pratiche.problem == nil, "precondition")

        pratiche.forgetLedgerState(under: "01 Progetti", in: vaultController)

        #expect(
            pratiche.problem?.contains("registro delle pratiche") == true,
            "the save failure must reach the person through `problem`, not vanish"
        )
        #expect(pratiche.ledger.byPraticaPath["01 Progetti/Tifone"] == nil, "memory is cleaned anyway")
        #expect(pratiche.trayCounts["01 Progetti/Tifone"] == nil)
        #expect(pratiche.ledger.byPraticaPath["01 Progetti-altro/Y"] != nil, "and only the trashed subtree's")

        vaultController.close()
    }

    /// The arrangement `aLedgerThatCannotBeSavedIsReportedAndStillForgottenInMemory` used before
    /// ADR-0052, and the case it now describes (R-04): a directory at the ledger's own URL is a
    /// ledger that is THERE and cannot be read, so the trash path refuses it before any save is
    /// attempted, leaves it exactly as it found it, and says so once.
    @Test func aDirectoryAtTheLedgersOwnURLIsRefusedRatherThanSavedOver() async throws {
        let vault = try TemporaryVault()
        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let session = try #require(vaultController.session)
        let url = PraticheController.ledgerURL(for: session)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let marker = url.appending(path: "keep.txt", directoryHint: .notDirectory)
        try Data("kept".utf8).write(to: marker)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        #expect(pratiche.problem == nil, "precondition")

        pratiche.forgetLedgerState(under: "01 Progetti", in: vaultController)

        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory))
        #expect(isDirectory.boolValue, "the directory was not replaced by a ledger file")
        #expect(try Data(contentsOf: marker) == Data("kept".utf8), "and what was inside it is untouched")
        let sentence = try #require(pratiche.problem, "the refusal reaches the person through `problem`")
        #expect(sentence.contains("registro delle pratiche"))
        #expect(sentence.contains(url.path(percentEncoded: false)), "naming the file")

        // Once: a second trash reaches the same door and must stay silent.
        pratiche.problem = nil
        pratiche.forgetLedgerState(under: "01 Altro", in: vaultController)
        #expect(pratiche.problem == nil, "reported once per file per session")
        #expect(pratiche.ledgerOrigin == .unreadable(url))

        vaultController.close()
    }

    // MARK: - R-08 end to end

    /// The ticket's acceptance case, driven through the real pipeline instead of read off
    /// the ledger - and the one place this suite records that the ticket's stated SYMPTOM does
    /// not reproduce as written. A first version of this test used the ticket's own premise
    /// (a stale `importedMessageIDs` makes the recreated pratica skip a message) and failed its
    /// own control: a row read from the Mail index carries NO `Message-ID`
    /// (`MailStoreReader.rows` sets `messageID: nil`, even through `row(forMessageID:)`), and
    /// `MembershipRule.candidates` and `PraticaSyncPlan.workItems` subtract `onDisk` only from a
    /// row that has one. So a stale ledger never filters a message here: the engine's own scan
    /// of the folder decides, and an empty new folder writes it whatever the ledger says.
    ///
    /// What a stale ledger DOES do, and what this test pins, is leak the old pratica's history
    /// into the new one: an id the old pratica had imported that this Mail index cannot resolve
    /// is reported by `noLongerInMail` and lodged in `notInStore` (a message «non più in Mail»
    /// that the new pratica never had), and stays in `importedMessageIDs` beside the new
    /// message. The control shows that leak with the hook unwired (the app before this fix);
    /// the second half shows the trash through the wired door starting the recreated pratica
    /// clean while its first sync still imports the message.
    @Test func aPraticaRecreatedUnderTheSameNameStartsCleanAndStillImportsItsMessage() async throws {
        let messageID = "<abc123@rossi-spa.it>"
        let stale = "<vecchio@rossi-spa.it>"
        let date = Date(timeIntervalSince1970: 1_749_557_170)
        let vault = try TemporaryVault()
        try vault.write(followedPratica, to: "\(Self.folder)/pratica.md")
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Richiesta offerta", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: date, dateReceived: date,
                emlxBody: EmailFixtureCorpus.completeMessageRFC822
            )]
        )
        UserDefaults.standard.set(fixture.root.path(percentEncoded: false), forKey: MailStoreLocation.overrideKey)
        defer { UserDefaults.standard.removeObject(forKey: MailStoreLocation.overrideKey) }

        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let session = try #require(vaultController.session)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let sync = PraticaLiveSync(vault: vaultController)
        sync.controller = pratiche
        // What the OLD pratica at this path left in the ledger: a message this Mail index
        // has never heard of. Written to the file and loaded from it, as the pane does: `runExclusive`
        // reads `importedMessageIDs` off the controller's memory, and a value assigned there without
        // the file would be discarded by the door.
        var seeded = PraticaLedger.empty
        seeded.byPraticaPath[Self.folder] = stateImporting(stale)
        try seeded.save(to: PraticheController.ledgerURL(for: session))
        pratiche.load(from: vaultController)

        // Control, hook unwired: the old pratica's history is what the next sync inherits.
        _ = await sync.runExclusive(praticaPath: Self.folder)
        #expect(
            pratiche.ledger.byPraticaPath[Self.folder]?.notInStore.contains(stale) == true,
            "control: the leak is real - the old id is reported as gone from Mail by a pratica that never had it"
        )
        #expect(vaultController.trashFolder(at: Self.folder), "the trash without a subscriber")
        #expect(
            pratiche.ledger.byPraticaPath[Self.folder]?.importedMessageIDs.contains(stale) == true,
            "control: with nobody subscribed, the ledger outlives the folder - the defect"
        )

        // The fix, wired the way `PergamenumApp.init` wires it.
        vaultController.didTrashFolder = { [weak pratiche] trashed in
            pratiche?.followFolderTrashing(trashed, in: vaultController)
        }
        try vault.write(followedPratica, to: "\(Self.folder)/pratica.md")
        #expect(vaultController.trashFolder(at: Self.folder))
        #expect(pratiche.ledger.byPraticaPath[Self.folder] == nil, "the trash forgot the old ledger")
        try vault.write(followedPratica, to: "\(Self.folder)/pratica.md")
        pratiche.load(from: vaultController)

        _ = await sync.runExclusive(praticaPath: Self.folder)

        #expect(
            PraticaSyncFixtures.mdFiles(under: vault.root).count == 1,
            "the recreated pratica's first sync imports its message into the new folder"
        )
        let recreated = try #require(pratiche.ledger.byPraticaPath[Self.folder])
        #expect(recreated.importedMessageIDs == [messageID], "and its ledger holds that message alone")
        #expect(!recreated.notInStore.contains(stale), "nothing of the old pratica's history was inherited")

        vaultController.close()
    }

    // MARK: - R-06: the preview half and the shared sentence

    /// `prepareRegeneration`'s own guard, resuming from its `await`, on a folder that went to
    /// the Trash. A race cannot be driven from outside (`PraticaLiveSyncRelocatedMidRunTests`
    /// test 10 records why), so the tombstone is installed the way an in-flight ordinary sync
    /// installs one - `beginSync`, then the real trash hook - BEFORE the preview is asked for,
    /// and the real `prepareRegeneration` runs to completion against it: preview succeeds,
    /// guard refuses, sentence names the deletion, claim released, no sheet left behind.
    @Test func prepareRegenerationRefusesATrashedFolderAndLeavesNoSheetOrClaim() async throws {
        let messageID = "<abc123@rossi-spa.it>"
        let date = Date(timeIntervalSince1970: 1_749_557_170)
        let vault = try TemporaryVault()
        try vault.write(followedPratica, to: "\(Self.folder)/pratica.md")
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Richiesta offerta", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: date, dateReceived: date,
                emlxBody: EmailFixtureCorpus.completeMessageRFC822
            )]
        )
        UserDefaults.standard.set(fixture.root.path(percentEncoded: false), forKey: MailStoreLocation.overrideKey)
        defer { UserDefaults.standard.removeObject(forKey: MailStoreLocation.overrideKey) }
        let seedEngine = PraticaSyncFixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vault.root)
        _ = try await seedEngine.sync(PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.folder, dossier: PraticaSyncFixtures.sampleDossier(),
            candidates: [PraticaSyncFixtures.row(rowID: 1, messageID: messageID, date: date)],
            onDisk: [], settings: .default
        ))

        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let pratiche = PraticheController.live(vault: vaultController)
        pratiche.beginSync(Self.folder)
        pratiche.followFolderTrashing(Self.folder, in: vaultController)
        #expect(stop(continuing: Self.folder, on: pratiche) == .praticaTrashed(path: Self.folder), "precondition")

        await pratiche.prepareRegeneration?(Self.folder, messageID)

        #expect(pratiche.regeneration == nil, "no preview may be shown for a folder that is gone")
        #expect(pratiche.regeneratingPraticaPaths.isEmpty, "and the claim it took on entry is released")
        #expect(pratiche.problem?.contains("eliminata") == true, "the refusal names the deletion")
        #expect(pratiche.problem?.contains("spostata") == false, "not a move that has no new position to send anyone to")

        vaultController.close()
    }

    @Test func theRegenerationRefusalNamesTheTrashForATrashedFolderAndTheMoveForARelocatedOne() {
        let trashed = PraticaRunStop.regenerationRefusal(
            after: PraticaRunStop.praticaTrashed(path: Self.folder), of: Self.folder
        )
        let moved = PraticaRunStop.regenerationRefusal(
            after: PraticaRunStop.praticaRelocated(from: Self.folder, to: "Calendar/\(Self.folder)"), of: Self.folder
        )

        #expect(trashed.contains("eliminata"))
        #expect(!trashed.contains("spostata"))
        #expect(!trashed.contains("Rigenera…"), "there is no new position to reopen «Rigenera…» from")
        #expect(moved.contains("spostata"))
        #expect(moved.contains("Rigenera…"))
        #expect(!moved.contains("eliminata"))
        #expect(trashed.contains(Self.folder) && moved.contains(Self.folder), "both name the folder they refuse")
    }

    // MARK: - One ancestor, two kinds of run, one bystander

    /// An ancestor's trash reaches a sync under one pratica and a regeneration under another
    /// at once, and neither tombstone spills onto a claim under a sibling-prefix folder.
    @Test func anAncestorTrashTombstonesASyncAndARegenerationAndSparesABystanderClaim() {
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let syncing = "01 Progetti/Rossi/Offerta"
        let regenerating = "01 Progetti/Verdi/Contratto"
        let bystander = "01 Progetti-altro/Z"
        pratiche.beginSync(syncing)
        pratiche.beginRegeneration(regenerating)
        pratiche.beginRegeneration(bystander)

        pratiche.followFolderTrashing("01 Progetti", in: VaultController())

        #expect(pratiche.forgottenPraticaPaths == [syncing, regenerating])
        #expect(stop(continuing: syncing, on: pratiche) == .praticaTrashed(path: syncing))
        #expect(stop(continuing: regenerating, on: pratiche) == .praticaTrashed(path: regenerating))
        #expect(stop(continuing: bystander, on: pratiche) == nil, "a sibling-prefix folder's run is not this trash's")
        #expect(
            pratiche.regeneratingPraticaPaths == [regenerating, bystander],
            "no claim is cleared by a trash: each run releases its own"
        )
    }

    /// The same door twice for the same path (a second surface, a retry) is a no-op the second
    /// time, and never throws or touches a neighbour.
    @Test func forgettingTheSamePathTwiceIsHarmless() {
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        pratiche.updateLedger(.live(nil)) {
            $0.byPraticaPath["01 Progetti/Tifone"] = stateImporting("<a@rossi-spa.it>")
            $0.byPraticaPath["01 Progetti/Verdi"] = stateImporting("<b@rossi-spa.it>")
        }
        let vault = VaultController()

        pratiche.followFolderTrashing("01 Progetti/Tifone", in: vault)
        pratiche.followFolderTrashing("01 Progetti/Tifone", in: vault)

        #expect(pratiche.ledger.byPraticaPath["01 Progetti/Tifone"] == nil)
        #expect(pratiche.ledger.byPraticaPath["01 Progetti/Verdi"]?.importedMessageIDs == ["<b@rossi-spa.it>"])
        #expect(pratiche.forgottenPraticaPaths.isEmpty)
    }
}
