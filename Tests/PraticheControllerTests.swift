import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 5 -
// R-17, R-18.
//
// Every declaration under test here (`PraticaWatcher`, `FullDiskAccessProbe`,
// `PraticheController`) is a tester-declared boundary (ADR-0155): the coder fills the
// bodies. `PraticaWatcher`'s decision methods are stubbed to wrong-but-safe constants
// (`true`/`false`/no-op) and `FullDiskAccessProbe.state(probing:)` is stubbed to
// always report `.granted` - both keep every test below red without ever crashing
// the process the way a `fatalError` stub would. No test here touches
// `~/Library/Mail`; `stateReadsEPERMAsNotGranted` and the `PraticheController` tests
// build their own throwaway, unreadable file instead.

@Suite(.serialized) struct PraticaWatcherTests {
    // MARK: - R-17: automatic triggers, throttle, debounce, closed-pratica escape hatch

    @Test func windowKeyTriggerIsThrottledToOncePerSixtySeconds() {
        var watcher = PraticaWatcher()
        let t0 = Date()

        #expect(watcher.decideWindowKeyTrigger(eligibility: .automatic, now: t0) == true)
        #expect(
            watcher.decideWindowKeyTrigger(eligibility: .automatic, now: t0.addingTimeInterval(30)) == false,
            "a second window-key sync inside the 60s throttle must not run"
        )
        #expect(
            watcher.decideWindowKeyTrigger(eligibility: .automatic, now: t0.addingTimeInterval(61)) == true,
            "past the 60s window, the next window-key sync runs again"
        )
    }

    @Test func fsEventsPulseFiresTenSecondsAfterTheLastPulseNotTheFirst() {
        var watcher = PraticaWatcher()
        let t0 = Date()

        watcher.registerFSEventsPulse(now: t0)
        #expect(watcher.isFSEventsFireDue(now: t0.addingTimeInterval(5)) == false)

        // A second pulse before the first one's debounce elapsed resets the window -
        // this is a debounce, not a throttle: a burst of writes collapses into one
        // sync 10s after the *last* pulse, not 10s after the first.
        watcher.registerFSEventsPulse(now: t0.addingTimeInterval(5))
        #expect(
            watcher.isFSEventsFireDue(now: t0.addingTimeInterval(12)) == false,
            "the second pulse should have pushed the debounce window out to t+15"
        )
        #expect(
            watcher.isFSEventsFireDue(now: t0.addingTimeInterval(16)) == true,
            "10s after the last pulse, the fire is due"
        )
    }

    @Test func closedPraticaSyncsOnlyThroughManualRefresh() {
        var watcher = PraticaWatcher()
        let now = Date()

        #expect(
            watcher.decideImmediateTrigger(.vaultOpen, eligibility: .manualOnly, now: now) == false,
            "status-archived/status-final must not sync on vault open"
        )
        #expect(
            watcher.decideWindowKeyTrigger(eligibility: .manualOnly, now: now) == false,
            "status-archived/status-final must not sync on window-key"
        )
        watcher.registerFSEventsPulse(now: now)
        #expect(
            watcher.isFSEventsFireDue(now: now.addingTimeInterval(11)) == false,
            "status-archived/status-final must not sync automatically, however long the debounce waits"
        )
        #expect(
            watcher.decideImmediateTrigger(.manualRefresh, eligibility: .manualOnly, now: now) == true,
            "«Aggiorna ora» always works, regardless of eligibility"
        )
    }

    @Test func activeOrWaitingPraticaSyncsOnVaultOpen() {
        let watcher = PraticaWatcher()
        #expect(watcher.decideImmediateTrigger(.vaultOpen, eligibility: .automatic, now: Date()) == true)
    }
}

// MARK: - R-18: Full Disk Access probe and banner

@Suite(.serialized) struct FullDiskAccessProbeTests {
    @Test func stateReadsEPERMAsNotGranted() throws {
        let unreadable = try Self.makeUnreadableFile()
        defer { Self.restoreAndRemove(unreadable) }

        #expect(FullDiskAccessProbe.state(probing: unreadable) == .notGranted)
    }

    @Test func stateReadsAnOrdinaryReadableFileAsGranted() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-fda-probe-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let readable = directory.appending(path: "Envelope Index", directoryHint: .notDirectory)
        try Data("fixture".utf8).write(to: readable)

        #expect(FullDiskAccessProbe.state(probing: readable) == .granted)
    }

    static func makeUnreadableFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-fda-probe-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "Envelope Index", directoryHint: .notDirectory)
        try Data("fixture".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path(percentEncoded: false))
        return file
    }

    /// Permissions restored before removal - a 000 file refuses its own deletion the
    /// same way `VaultStateTests`' 555 directories do.
    static func restoreAndRemove(_ file: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path(percentEncoded: false))
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }
}

@MainActor
@Suite(.serialized) struct PraticheControllerTests {
    @Test func fullDiskAccessBannerClearsOnTheNextTriggerWithNoRestart() async throws {
        let unreadable = try FullDiskAccessProbeTests.makeUnreadableFile()
        defer { FullDiskAccessProbeTests.restoreAndRemove(unreadable) }

        var syncCallCount = 0
        let controller = PraticheController(
            probe: { FullDiskAccessProbe.state(probing: unreadable) },
            performSync: { _, _ in syncCallCount += 1 }
        )

        // Real behaviour (R-18): the probe runs once at `init`, so an unreadable
        // store is reflected before any trigger fires at all.
        #expect(controller.fullDiskAccessState == .notGranted)

        await controller.trigger("01 Progetti/Rossi/Offerta", kind: .vaultOpen, eligibility: .automatic)
        #expect(syncCallCount == 0, "a sync must not run while the store is unreadable")

        // Grant access without restarting the app - the *next* trigger alone must
        // notice (R-18: "the probe is repeated per trigger").
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644], ofItemAtPath: unreadable.path(percentEncoded: false)
        )
        await controller.trigger("01 Progetti/Rossi/Offerta", kind: .vaultOpen, eligibility: .automatic)
        #expect(controller.fullDiskAccessState == .granted)
        #expect(syncCallCount == 1)
    }

    @Test func noSyncEverRunsWhileTheStoreStaysUnreadable() async throws {
        let unreadable = try FullDiskAccessProbeTests.makeUnreadableFile()
        defer { FullDiskAccessProbeTests.restoreAndRemove(unreadable) }

        var syncCallCount = 0
        let controller = PraticheController(
            probe: { FullDiskAccessProbe.state(probing: unreadable) },
            performSync: { _, _ in syncCallCount += 1 }
        )

        await controller.trigger("01 Progetti/Rossi/Offerta", kind: .vaultOpen, eligibility: .automatic)
        await controller.trigger("01 Progetti/Rossi/Offerta", kind: .windowKey, eligibility: .automatic)
        await controller.trigger("01 Progetti/Rossi/Offerta", kind: .manualRefresh, eligibility: .manualOnly)

        #expect(syncCallCount == 0)
        #expect(controller.fullDiskAccessState == .notGranted)
    }
}

// MARK: - §D23.2 - the bridge merges into the ledger, newest triple wins

// ADR §D23, plan docs/superpowers/plans/2026-09-10-pratiche-pg105-pg108.md, Task 1.
// `recordSyncOutcome`'s merge of `outcome.bridge` into `state.entries` is the coder's
// job (§D23.2) - `SyncOutcome.bridge` is declared but nothing appends to
// `PraticaLedger.PraticaState.entries` yet, so both tests below are red.
@MainActor
@Suite(.serialized) struct PraticaLedgerBridgeMergeTests {
    @Test func recordSyncOutcomeMergesBridgeEntriesNewestTripleWinsPerMessageID() throws {
        let vault = try TemporaryVault()
        let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let praticaPath = "01 Progetti/Rossi/Offerta 2026"

        let firstOutcome = PraticaSyncEngine.SyncOutcome(
            writtenFiles: [], importedMessageIDs: ["<a@rossi-spa.it>", "<b@rossi-spa.it>"],
            noLongerInMail: [], regeneratedPendingFiles: [], cancelled: false,
            bridge: [
                PraticaLedger.Entry(messageID: "<a@rossi-spa.it>", rowID: 1, conversationID: 112_409),
                PraticaLedger.Entry(messageID: "<b@rossi-spa.it>", rowID: 2, conversationID: 112_409),
            ]
        )
        controller.recordSyncOutcome(firstOutcome, for: praticaPath, session: session, isCurrentVault: true)

        let entriesAfterFirstSync = (controller.ledger.byPraticaPath[praticaPath]?.entries ?? [])
            .sorted { $0.messageID < $1.messageID }
        #expect(
            entriesAfterFirstSync == [
                PraticaLedger.Entry(messageID: "<a@rossi-spa.it>", rowID: 1, conversationID: 112_409),
                PraticaLedger.Entry(messageID: "<b@rossi-spa.it>", rowID: 2, conversationID: 112_409),
            ],
            "the very first sync's own triples must already be recorded"
        )

        // A second sync that re-imports nothing new: what is already recorded must
        // stay exactly as it is.
        let secondOutcome = PraticaSyncEngine.SyncOutcome(
            writtenFiles: [], importedMessageIDs: [],
            noLongerInMail: [], regeneratedPendingFiles: [], cancelled: false, bridge: []
        )
        controller.recordSyncOutcome(secondOutcome, for: praticaPath, session: session, isCurrentVault: true)

        let entriesAfterSecondSync = (controller.ledger.byPraticaPath[praticaPath]?.entries ?? [])
            .sorted { $0.messageID < $1.messageID }
        #expect(
            entriesAfterSecondSync == [
                PraticaLedger.Entry(messageID: "<a@rossi-spa.it>", rowID: 1, conversationID: 112_409),
                PraticaLedger.Entry(messageID: "<b@rossi-spa.it>", rowID: 2, conversationID: 112_409),
            ],
            "a sync that imports nothing new must leave `entries` unchanged"
        )

        // A regeneration of `<a@…>` under a new ROWID replaces THAT message's triple
        // alone (§D23.2's own "newest triple wins"), leaving `<b@…>` untouched.
        let regenerationOutcome = PraticaSyncEngine.SyncOutcome(
            writtenFiles: [], importedMessageIDs: [],
            noLongerInMail: [], regeneratedPendingFiles: ["\(praticaPath)/email/richiesta.md"], cancelled: false,
            bridge: [PraticaLedger.Entry(messageID: "<a@rossi-spa.it>", rowID: 99, conversationID: 112_409)]
        )
        controller.recordSyncOutcome(regenerationOutcome, for: praticaPath, session: session, isCurrentVault: true)

        let entries = controller.ledger.byPraticaPath[praticaPath]?.entries ?? []
        #expect(entries.first { $0.messageID == "<a@rossi-spa.it>" }?.rowID == 99, "the regenerated message's triple is replaced")
        #expect(entries.first { $0.messageID == "<b@rossi-spa.it>" }?.rowID == 2, "an untouched message's triple is left alone")
        #expect(entries.count == 2, "a regeneration replaces a triple, it never adds a second one for the same Message-ID")
    }
}

// MARK: - §D23.3/§D23.4/§D23.6 - recovery, repointing and the renumbering round-trip

// Full end-to-end coverage through `PraticheController.live(vault:)` +
// `PraticaLiveSync`, the same production wiring `PergamenumApp` uses - `prepare`'s
// conversation loop (§D23.3), `remapLedgerConversations` (§D23.4) and the
// `controller.report(_:)` banner (§D23.5) are all coder work still to land, so every
// assertion below that depends on them is red; `MailStoreLocation`'s `-mailStoreRoot`
// override (already implemented, `Tests/MailStoreReaderTests.swift`'s own pattern)
// points the real sync at a `MailStoreFixture`-built store, never at
// `~/Library/Mail`.
private func dossierNote(conversations: [Int], counterparts: [String] = ["m.rossi@rossi-spa.it"]) -> String {
    let counterpartLines = counterparts.map { "  - \($0)" }.joined(separator: "\n")
    let conversationsList = conversations.map(String.init).joined(separator: ", ")
    return """
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
    \(counterpartLines)
    pergamenum-dossier-conversations: [\(conversationsList)]
    ---

    Appunti pratica.
    """
}

@MainActor
@Suite(.serialized) struct PraticaConversationRenumberingTests {
    @Test func syncRenumbersAFollowedConversationWhoseIdMailHasChanged() async throws {
        let praticaPath = "01 Progetti/Rossi/Offerta 2026"
        let vault = try TemporaryVault()
        try vault.write(dossierNote(conversations: [112_409]), to: "\(praticaPath)/pratica.md")

        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Richiesta offerta", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1000),
                dateReceived: Date(timeIntervalSince1970: 1000),
                emlxBody: EmailFixtureCorpus.completeMessageRFC822
            )]
        )
        UserDefaults.standard.set(fixture.root.path(percentEncoded: false), forKey: MailStoreLocation.overrideKey)
        defer { UserDefaults.standard.removeObject(forKey: MailStoreLocation.overrideKey) }

        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)

        let pratiche = PraticheController.live(vault: vaultController)
        await pratiche.trigger(praticaPath, kind: .manualRefresh, eligibility: .automatic)

        let ledgerAfterFirstSync = pratiche.ledger.byPraticaPath[praticaPath]
        #expect(
            ledgerAfterFirstSync?.entries.first?.conversationID == 112_409,
            "the first sync's own bridge triple must name the conversation as it is now"
        )

        // Mail renumbers the conversation on a reindex: same ROWID, same Message-ID,
        // a brand new `conversation_id`. A short pause guarantees the source's own
        // modification date actually moves (`MailStoreCopy.publish`'s own millisecond
        // generation key), matching how the real Mail store never rewrites its index
        // twice inside the same millisecond either.
        try await Task.sleep(for: .milliseconds(50))
        _ = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Richiesta offerta", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 550_001, dateSent: Date(timeIntervalSince1970: 1000),
                dateReceived: Date(timeIntervalSince1970: 1000),
                emlxBody: EmailFixtureCorpus.completeMessageRFC822
            )],
            in: fixture.root
        )

        await pratiche.trigger(praticaPath, kind: .manualRefresh, eligibility: .automatic)

        let dossier = try #require(PraticheController.dossier(at: praticaPath, vaultRoot: vault.root))
        #expect(dossier.conversations == [550_001], "§D23.4: the renumbered id replaces the old one, in the same position")

        let ledgerAfterSecondSync = pratiche.ledger.byPraticaPath[praticaPath]
        #expect(
            ledgerAfterSecondSync?.entries.first?.conversationID == 550_001,
            "§D23.4: the ledger's own triple is repointed too, or the next renumbering has nothing to recover from"
        )
    }
}

@MainActor
@Suite(.serialized) struct PraticaConversationRecoveryReportingTests {
    @Test func aConversationWithNoRowsAndNoLedgerEntriesIsLeftAloneNoRecoveryNoBanner() async throws {
        let praticaPath = "01 Progetti/Rossi/Offerta 2026"
        let vault = try TemporaryVault()
        try vault.write(dossierNote(conversations: [112_409]), to: "\(praticaPath)/pratica.md")

        // The store has no message at all - nothing was ever imported for 112409, so
        // an empty result is not evidence of renumbering (§D23.3's own comment).
        let fixture = try MailStoreFixture.build(mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")], messages: [])
        UserDefaults.standard.set(fixture.root.path(percentEncoded: false), forKey: MailStoreLocation.overrideKey)
        defer { UserDefaults.standard.removeObject(forKey: MailStoreLocation.overrideKey) }

        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)

        let pratiche = PraticheController.live(vault: vaultController)
        await pratiche.trigger(praticaPath, kind: .manualRefresh, eligibility: .automatic)

        #expect(pratiche.problem == nil, "no ledger entries for 112409 means nothing to recover and nothing to report")
        let dossier = try #require(PraticheController.dossier(at: praticaPath, vaultRoot: vault.root))
        #expect(dossier.conversations == [112_409], "an empty, never-imported conversation is never touched")
    }

    @Test func aFollowedConversationWhoseEveryKnownMemberIsGoneReportsOnceAndStaysInTheDossier() async throws {
        let praticaPath = "01 Progetti/Rossi/Offerta 2026"
        let vault = try TemporaryVault()
        try vault.write(dossierNote(conversations: [112_409]), to: "\(praticaPath)/pratica.md")

        // The store holds no message at all any more - the ledger's one known member
        // of 112409 has vanished from Mail entirely.
        let fixture = try MailStoreFixture.build(mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")], messages: [])
        UserDefaults.standard.set(fixture.root.path(percentEncoded: false), forKey: MailStoreLocation.overrideKey)
        defer { UserDefaults.standard.removeObject(forKey: MailStoreLocation.overrideKey) }

        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let session = try #require(vaultController.session)

        // §D3's bridge, seeded directly into the ledger file rather than through a
        // real sync (`Tests/PraticheConnectorTests.swift`'s own seeding pattern) -
        // this pratica already imported `<vanished@rossi-spa.it>` under 112409 at
        // some point before this test begins.
        var ledger = PraticaLedger.empty
        ledger.byPraticaPath[praticaPath] = .empty
        ledger.byPraticaPath[praticaPath]?.entries = [
            PraticaLedger.Entry(messageID: "<vanished@rossi-spa.it>", rowID: 1, conversationID: 112_409),
        ]
        try ledger.save(to: PraticheController.ledgerURL(for: session))

        let pratiche = PraticheController.live(vault: vaultController)
        pratiche.load(from: vaultController)

        await pratiche.trigger(praticaPath, kind: .manualRefresh, eligibility: .automatic)

        #expect(
            pratiche.problem == "Una conversazione seguita non è più ricostruibile in Mail: 1.",
            "§D23.5: reported once, in the exact sentence the ADR spells out"
        )
        let dossier = try #require(PraticheController.dossier(at: praticaPath, vaultRoot: vault.root))
        #expect(dossier.conversations == [112_409], "R-14: an unrecoverable conversation is never dropped from the dossier")
    }
}

// ADR-0040 §D8 (R-08): a pending attachment entry (the bare name, no `[[…]]`) must not
// silently become an ordinary chip pointing at a file `allegati/` does not have.
// `readMessages` (`PraticheController.swift:738`) is the RED stub under test - it still
// maps the whole `attachments` list through `attachmentFileName(fromWikilink:)`
// unconditionally, so a pending entry there produces a `PraticaAttachmentRef` exactly
// like a linked one instead of landing in the new `pendingAttachments` list.

@Suite struct PraticaReadTimelinePendingAttachmentsTests {
    @Test func readTimelineSplitsOneLinkedAndOnePendingAttachmentIntoTheirOwnLists() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "pratica-pending-attachments-\(UUID().uuidString)", directoryHint: .isDirectory)
        let praticaPath = "Rossi/Offerta"
        let messagesFolder = root.appending(path: "\(praticaPath)/email", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: messagesFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let document = MessageDocument(
            frontmatter: MessageDocument.MailFrontmatter(
                schemaVersion: 1, messageID: "<offerta@rossi-spa.it>", conversationID: 1, direction: .received,
                date: Date(timeIntervalSince1970: 1_749_557_170), received: nil,
                from: "m.rossi@rossi-spa.it", to: [], cc: [], subject: "Offerta",
                attachments: ["[[offerta.pdf]]", "bozza.docx"], body: .complete, original: nil
            ),
            newText: "Testo del messaggio.", quotedHistory: nil, signature: nil
        )
        let text = MessageDocument.render(document, tags: [Tag(namespace: .type, value: "email")])
        try text.write(
            to: messagesFolder.appending(path: "20260610_1406_Rossi_offerta.md", directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )

        let read = PraticheController.readTimeline(praticaPath: praticaPath, vaultRoot: root)

        #expect(read.entries.count == 1)
        let detail = try #require(read.details[read.entries[0].id])
        #expect(
            detail.attachments.map(\.name) == ["offerta.pdf"],
            "only the linked `[[…]]` entry becomes a PraticaAttachmentRef"
        )
        #expect(
            detail.pendingAttachments == ["bozza.docx"],
            "the bare, still-pending entry must land in pendingAttachments, not attachments"
        )
    }
}
