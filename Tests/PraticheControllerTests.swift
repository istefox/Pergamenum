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

    /// R-18/`FullDiskAccessProbe.swift`'s own doc comment: "Every other failure, ENOENT
    /// first among them, answers `.granted`" - a missing store is «Nessun archivio di
    /// Mail trovato», never the Full Disk Access banner. Converts
    /// `UITests/PraticheUITests.swift:192`
    /// (`testTheFullDiskAccessBannerIsAbsentWithAReadableMailStoreFixture`)'s own
    /// setup: a readable, empty temporary directory whose `Envelope Index` file was
    /// never written, exactly what that UI test's `mailStoreRoot` fixture is.
    @Test func stateReadsENOENTAsGranted() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-fda-probe-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = directory.appending(path: "Envelope Index", directoryHint: .notDirectory)

        #expect(FullDiskAccessProbe.state(probing: missing) == .granted)
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

// MARK: - R-30: `selectedTray`, the chosen pratica's own proposals

// plan `docs/plans/ui-suite-replacement.md` Task 5, PR 3: converts
// `UITests/PraticheUITests.swift:211` (`testTheTrayIsAbsentWithNoProposals`)'s own
// claim - a pratica with no tray proposals reads back an empty `selectedTray`, which
// is what makes `PraticaTrayStrip` (`PraticaTrayModel.isHidden(_:)`) absent - plus the
// two neighbouring shapes `selectedTray`'s own guard covers: no selection at all, and
// a selection that is not the only key `trayProposals` holds.
@MainActor
@Suite(.serialized) struct PraticheControllerSelectedTrayTests {
    private static func proposal(conversationID: Int = 1) -> PraticaTrayModel.PraticaTrayProposal {
        PraticaTrayModel.PraticaTrayProposal(
            conversationID: conversationID, subject: "Richiesta offerta", counterpart: "m.rossi@rossi-spa.it",
            dateRange: Date()...Date(), messageCount: 2
        )
    }

    @Test func selectedTrayIsEmptyWithNoSelectionEvenWhenSomeOtherPraticaHasProposals() {
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        controller.trayProposals["01 Progetti/Rossi/Offerta"] = [Self.proposal()]

        #expect(controller.selection == nil)
        #expect(controller.selectedTray.isEmpty, "no pratica is selected, so nothing is that pratica's own tray")
    }

    @Test func selectedTrayIsEmptyWhenTheSelectedPraticaHasNoProposals() {
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        controller.selection = "01 Progetti/Rossi/Offerta"

        #expect(controller.selectedTray.isEmpty)
    }

    @Test func selectedTrayReadsBackExactlyTheSelectedPraticasOwnProposalsNeverASiblings() {
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let mine = Self.proposal()
        controller.trayProposals["01 Progetti/Rossi/Offerta"] = [mine]
        controller.trayProposals["01 Progetti/Acme/Altra"] = [Self.proposal(conversationID: 2)]
        controller.selection = "01 Progetti/Rossi/Offerta"

        #expect(controller.selectedTray == [mine])
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
        await MailStoreOverride.acquire(settingRootTo: fixture.root)
        defer { MailStoreOverride.release() }

        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)

        let pratiche = PraticheController.live(vault: vaultController)
        await pratiche.trigger(praticaPath, kind: .manualRefresh, eligibility: .automatic)

        let ledgerAfterFirstSync = pratiche.ledger.byPraticaPath[praticaPath]
        #expect(
            ledgerAfterFirstSync?.entries.first?.conversationID == 112_409,
            "the first sync's own bridge triple must name the conversation as it is now"
        )
        // Round-4 review, test 11: the cheapest regression check that
        // `RunContext.livePraticaPath(in:)`'s new resolver calls, threaded through all
        // six of `runExclusive`'s steps, did not break the ordinary no-relocation path -
        // an import must still land and still be recorded when nothing ever moves.
        #expect(
            ledgerAfterFirstSync?.importedMessageIDs == ["<abc123@rossi-spa.it>"],
            "an ordinary sync must still import and still record, with every new `livePraticaPath` guard resolving to a no-op"
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
        await MailStoreOverride.acquire(settingRootTo: fixture.root)
        defer { MailStoreOverride.release() }

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
        await MailStoreOverride.acquire(settingRootTo: fixture.root)
        defer { MailStoreOverride.release() }

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

    /// PG-109/§D23.5: the ledger persistence and tray row the banner-only fix left
    /// out. Same fixture shape as the test above - a followed conversation whose one
    /// known member has vanished - but this one checks what survives past the run
    /// that found it, and what happens once the conversation is no longer empty.
    @Test func unrecoverableConversationsPersistToTheLedgerAndClearOnceRecovered() async throws {
        let praticaPath = "01 Progetti/Rossi/Offerta 2026"
        let vault = try TemporaryVault()
        try vault.write(dossierNote(conversations: [112_409]), to: "\(praticaPath)/pratica.md")

        let fixture = try MailStoreFixture.build(mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")], messages: [])
        await MailStoreOverride.acquire(settingRootTo: fixture.root)
        defer { MailStoreOverride.release() }

        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let session = try #require(vaultController.session)

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
            pratiche.ledger.byPraticaPath[praticaPath]?.unrecoverableConversations == [112_409],
            "the run that found it unrecoverable must persist it, not just report it once"
        )

        // The member is back (Mail's index rebuilt, or the message simply reappeared):
        // rebuilt in the SAME directory, exactly as `MailStoreFixture.build`'s own doc
        // comment describes for simulating a store change across two syncs.
        _ = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [
                .init(
                    rowID: 1, subject: "Re: Preventivo", senderAddress: "mario@rossi-spa.it",
                    mailboxRowID: 1, conversationID: 112_409, dateSent: Date(), dateReceived: Date()
                ),
            ],
            in: fixture.root
        )

        await pratiche.trigger(praticaPath, kind: .manualRefresh, eligibility: .automatic)

        #expect(
            pratiche.ledger.byPraticaPath[praticaPath]?.unrecoverableConversations == [],
            "recovered on its own the next sync - no dismiss action, no separate invalidation rule needed"
        )
    }
}

// ADR-0040 §D8 (R-08): a pending attachment entry (the bare name, no `[[…]]`) must not
// silently become an ordinary chip pointing at a file `allegati/` does not have.
// `readMessages` (`PraticheController.swift:738`) is the RED stub under test - it still
// maps the whole `attachments` list through `attachmentFileName(fromWikilink:)`
// unconditionally, so a pending entry there produces a `PraticaAttachmentRef` exactly
// like a linked one instead of landing in the new `pendingAttachments` list.

// MARK: - PG "allegati non si scaricano": a folder relocation must not orphan the ledger
//
// `PraticheController.moveLedgerState(from:to:in:)` (`PraticheController+Ledger.swift`)
// used to be an exact-key swap, reachable only from the pratica's own «Rinomina…». It is
// now subtree-aware and reachable from the generic ADR-0026 batch move/rename path too,
// via `VaultController.didRelocateFolders` → `followFolderRelocations(_:in:)`. The bug
// this fixes: a pratica that is a *descendant* of a moved or renamed ancestor folder
// never had its ledger key move, so `PraticaSyncEngine.regeneratePending`'s ledger
// fallback silently found nothing there forever.

@MainActor
@Suite(.serialized) struct PraticaLedgerFolderRelocationTests {
    @Test func moveLedgerStateRemapsExactKey() {
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        // No session in these tests, so the ledger is seeded through the door: marker `.none`,
        // target `nil`, memory only (ADR-0052 §D9).
        controller.updateLedger(.live(nil)) { $0.byPraticaPath["01 Progetti/Tifone/X"] = .empty }
        let vault = VaultController()

        controller.moveLedgerState(from: "01 Progetti/Tifone/X", to: "Calendar/01 Progetti/Tifone/X", in: vault)

        #expect(controller.ledger.byPraticaPath["01 Progetti/Tifone/X"] == nil)
        #expect(controller.ledger.byPraticaPath["Calendar/01 Progetti/Tifone/X"] != nil)
    }

    @Test func moveLedgerStateRemapsDescendantPraticheUnderMovedAncestor() {
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        var state = PraticaLedger.PraticaState.empty
        state.importedMessageIDs = ["<a@rossi-spa.it>"]
        controller.updateLedger(.live(nil)) { $0.byPraticaPath["01 Progetti/Tifone/X"] = state }
        let vault = VaultController()

        // The actual bug shape: the pratica itself is not the moved item, an ANCESTOR of
        // it is.
        controller.moveLedgerState(from: "01 Progetti", to: "Calendar/01 Progetti", in: vault)

        #expect(
            controller.ledger.byPraticaPath["01 Progetti/Tifone/X"] == nil,
            "the orphaned old key must not linger once the remap has run"
        )
        let moved = controller.ledger.byPraticaPath["Calendar/01 Progetti/Tifone/X"]
        #expect(
            moved?.importedMessageIDs == ["<a@rossi-spa.it>"],
            "the pratica's own state - not just an empty key - must travel with the remap"
        )
    }

    @Test func moveLedgerStateLeavesSiblingPrefixAlone() {
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        controller.updateLedger(.live(nil)) { $0.byPraticaPath["01 Progetti-altro"] = .empty }
        let vault = VaultController()

        controller.moveLedgerState(from: "01 Progetti", to: "Calendar/01 Progetti", in: vault)

        #expect(
            controller.ledger.byPraticaPath["01 Progetti-altro"] != nil,
            "a sibling whose name merely starts with the same characters is not a descendant"
        )
        #expect(controller.ledger.byPraticaPath["Calendar/01 Progetti-altro"] == nil)
    }

    @Test func moveLedgerStateCarriesTrayCountsSelectionWatchersAndSyncingPath() {
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let oldPath = "01 Progetti/Tifone/X"
        let newPath = "Calendar/01 Progetti/Tifone/X"
        controller.updateLedger(.live(nil)) { $0.byPraticaPath[oldPath] = .empty }
        controller.trayCounts[oldPath] = 3
        controller.trayProposals[oldPath] = []
        controller.watchersByPraticaPath[oldPath] = PraticaWatcher()
        controller.selection = oldPath
        controller.syncingPraticaPath = oldPath
        let vault = VaultController()

        controller.moveLedgerState(from: oldPath, to: newPath, in: vault)

        #expect(controller.trayCounts[newPath] == 3)
        #expect(controller.trayCounts[oldPath] == nil, "the old key must not linger once its count travelled")
        #expect(controller.trayProposals[newPath] != nil)
        #expect(controller.watchersByPraticaPath[newPath] != nil, "a stale watcher never fires for the new path")
        #expect(controller.watchersByPraticaPath[oldPath] == nil)
        #expect(controller.selection == newPath, "the open pratica must stay selected across its own relocation")
        #expect(
            controller.syncingPraticaPath == newPath,
            "an in-flight sync's completion must land on the new path, not resurrect the orphaned key"
        )
    }

    @Test func moveLedgerStatePersistsToDisk() async throws {
        let vault = try TemporaryVault()
        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let session = try #require(vaultController.session)

        let pratiche = PraticheController.live(vault: vaultController)
        // On disk and not in memory (ADR-0052 §D9): a session exists, so the door reads the file.
        var seeded = PraticaLedger.empty
        seeded.byPraticaPath["01 Progetti/Tifone/X"] = .empty
        try seeded.save(to: PraticheController.ledgerURL(for: session))

        pratiche.moveLedgerState(
            from: "01 Progetti/Tifone/X", to: "Calendar/01 Progetti/Tifone/X", in: vaultController
        )

        let onDisk = PraticaLedger.load(from: PraticheController.ledgerURL(for: session))
        #expect(onDisk.byPraticaPath["01 Progetti/Tifone/X"] == nil)
        #expect(
            onDisk.byPraticaPath["Calendar/01 Progetti/Tifone/X"] != nil,
            "the remap must be saved, not only held in memory"
        )

        vaultController.close()
    }

    @Test func undoOfFolderMoveRestoresLedgerKey() async throws {
        let vault = try TemporaryVault()
        let root = vault.root
        try vault.write(
            "---\ndate: 2026-09-17\ntags:\n  - type-note\n---\n\nCorpo.\n", to: "F/pratica.md"
        )
        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(root)
        // `PergamenumApp.init`'s own wiring (this plan's own note): not going through
        // `PergamenumApp` in a test, so the hook is set by hand.
        let pratiche = PraticheController.live(vault: vaultController)
        vaultController.didRelocateFolders = { [weak pratiche] moved in
            pratiche?.followFolderRelocations(moved, in: vaultController)
        }
        let session = try #require(vaultController.session)
        var seeded = PraticaLedger.empty
        seeded.byPraticaPath["F"] = .empty
        try seeded.save(to: PraticheController.ledgerURL(for: session))
        let manager = UndoManager()

        let outcome = await vaultController.moveItems(
            [VaultItemRef(path: "F", kind: .folder)], into: "Dest", undo: manager
        )

        #expect(outcome.didMove)
        #expect(pratiche.ledger.byPraticaPath["F"] == nil, "the forward move must not leave the old key behind")
        #expect(
            pratiche.ledger.byPraticaPath["Dest/F"] != nil,
            "the forward move must carry the ledger key to the new path"
        )

        manager.undo()
        try await waitUntil { pratiche.ledger.byPraticaPath["F"] != nil }

        #expect(pratiche.ledger.byPraticaPath["F"] != nil, "the undo must carry the ledger key back")
        #expect(pratiche.ledger.byPraticaPath["Dest/F"] == nil)

        vaultController.close()
    }

    @Test func renameOfAncestorFolderRemapsLedgerKey() async throws {
        let vault = try TemporaryVault()
        let root = vault.root
        try vault.write(
            "---\ndate: 2026-09-17\ntags:\n  - type-note\n---\n\nCorpo.\n", to: "01 Progetti/Tifone/pratica.md"
        )
        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(root)
        let pratiche = PraticheController.live(vault: vaultController)
        vaultController.didRelocateFolders = { [weak pratiche] moved in
            pratiche?.followFolderRelocations(moved, in: vaultController)
        }
        let session = try #require(vaultController.session)
        var seeded = PraticaLedger.empty
        seeded.byPraticaPath["01 Progetti/Tifone"] = .empty
        try seeded.save(to: PraticheController.ledgerURL(for: session))

        let newPath = vaultController.renameFolder(at: "01 Progetti", to: "Calendar")

        #expect(newPath == "Calendar")
        #expect(
            pratiche.ledger.byPraticaPath["01 Progetti/Tifone"] == nil,
            "renaming the ancestor must not leave the descendant pratica's key behind"
        )
        #expect(
            pratiche.ledger.byPraticaPath["Calendar/Tifone"] != nil,
            "renaming an ancestor folder orphans a descendant pratica the same way a move does"
        )

        vaultController.close()
    }

    /// The actual race, not just the redirect map's own bookkeeping (that is what
    /// `moveLedgerStateCarriesTrayCountsSelectionWatchersAndSyncingPath` above already
    /// covers): a sync captures `praticaPath` before its own `await`s
    /// (`PraticaLiveSync+Run.swift`'s `runExclusive`), a relocation runs on the main
    /// actor while that sync is still in flight, and only THEN does the sync's outcome
    /// arrive, still carrying the pre-move path. `recordSyncOutcome` must fold it into
    /// wherever the ledger key now actually lives, never resurrect the orphaned one.
    @Test func recordSyncOutcomeFoldsIntoRelocatedPathAndNeverResurrectsTheOldKey() throws {
        let vault = try TemporaryVault()
        let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let oldPath = "01 Progetti/Tifone/X"
        let newPath = "Calendar/01 Progetti/Tifone/X"
        controller.updateLedger(.live(nil)) { $0.byPraticaPath[oldPath] = .empty }
        // Mirrors `beginSync(praticaPath)`, called before `runExclusive`'s own `await`s.
        controller.beginSync(oldPath)
        let vaultController = VaultController()

        // The relocation - drag-and-drop, or a rename of an ancestor - runs on the main
        // actor while the sync above is still in flight (ADR-0043 §D7's window).
        controller.followFolderRelocations([MovedNote(old: oldPath, new: newPath)], in: vaultController)
        #expect(controller.ledger.byPraticaPath[oldPath] == nil, "the relocation itself must not leave the old key behind")

        // The in-flight sync's own outcome lands afterwards, still keyed by the path it
        // captured before the relocation ran.
        let outcome = PraticaSyncEngine.SyncOutcome(
            writtenFiles: [], importedMessageIDs: ["<a@rossi-spa.it>"],
            noLongerInMail: [], regeneratedPendingFiles: [], cancelled: false, bridge: []
        )
        controller.recordSyncOutcome(outcome, for: oldPath, session: session, isCurrentVault: true)

        #expect(
            controller.ledger.byPraticaPath[oldPath] == nil,
            "a sync outcome arriving after the relocation must not resurrect the orphaned key"
        )
        #expect(
            controller.ledger.byPraticaPath[newPath]?.importedMessageIDs == ["<a@rossi-spa.it>"],
            "the outcome must fold into wherever the pratica's ledger now actually lives"
        )
    }

    // MARK: - Review round 2: two MINORs in `praticaPathRedirects` itself

    /// MINOR 1: the old `remapKeys` inserted a `praticaPathRedirects` entry for EVERY
    /// relocated key unconditionally, even when nothing was mid-sync/mid-regeneration
    /// for it - and nothing ever pruned an entry nobody was ever going to read. Fixed
    /// by gating the insert on `syncingPraticaPath`/`regeneratingPraticaPaths`: a
    /// relocation with nothing in flight for this pratica must leave no redirect at
    /// all, not just an eventually-pruned one.
    @Test func moveLedgerStateLeavesNoRedirectWhenNothingIsInFlight() {
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let oldPath = "01 Progetti/Tifone/X"
        let newPath = "Calendar/01 Progetti/Tifone/X"
        controller.updateLedger(.live(nil)) { $0.byPraticaPath[oldPath] = .empty }
        let vault = VaultController()

        controller.moveLedgerState(from: oldPath, to: newPath, in: vault)

        #expect(controller.ledger.byPraticaPath[newPath] != nil, "the remap itself must still happen")
        #expect(
            controller.praticaPathRedirects.isEmpty,
            "nothing was syncing or regenerating this pratica, so the relocation must not leave a redirect entry nothing will ever read"
        )
    }

    /// MINOR 2's exact shape: an ordinary sync AND a "Rigenera…" commit both captured
    /// `oldPath` before the SAME relocation ran - `PraticaLiveSync`'s `SyncRunQueue`
    /// only serializes ordinary syncs against each other, never against a
    /// regeneration for the same pratica. The old `resolveAndConsumePraticaPathRedirect`
    /// destructively removed the entry on its first read, so the first of the two
    /// callers to land would consume it and the second fell through to the stale key,
    /// resurrecting it exactly as before the whole fix. Both must now resolve to the
    /// relocated path, and neither may resurrect `oldPath`.
    @Test func recordSyncOutcomeResolvesForTwoConcurrentInFlightCallersOfTheSamePath() throws {
        let vault = try TemporaryVault()
        let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let oldPath = "01 Progetti/Tifone/X"
        let newPath = "Calendar/01 Progetti/Tifone/X"
        controller.updateLedger(.live(nil)) { $0.byPraticaPath[oldPath] = .empty }
        // Both callers captured `oldPath` before the relocation below, exactly like
        // `beginSync` (`runExclusive`) and `beginRegeneration` (`prepareRegeneration`)
        // do in production, before either one's own `await`s.
        controller.beginSync(oldPath)
        controller.beginRegeneration(oldPath)
        let vaultController = VaultController()

        controller.followFolderRelocations([MovedNote(old: oldPath, new: newPath)], in: vaultController)
        #expect(controller.ledger.byPraticaPath[oldPath] == nil, "the relocation itself must not leave the old key behind")
        #expect(
            controller.praticaPathRedirects[oldPath] == newPath,
            "with two in-flight callers claiming this path, the relocation must leave a redirect for it (MINOR 1's other side)"
        )

        // The ordinary sync's own outcome lands first, still keyed by the pre-move path.
        controller.recordSyncOutcome(
            PraticaSyncEngine.SyncOutcome(
                writtenFiles: [], importedMessageIDs: ["<a@rossi-spa.it>"],
                noLongerInMail: [], regeneratedPendingFiles: [], cancelled: false, bridge: []
            ),
            for: oldPath, session: session, isCurrentVault: true
        )
        #expect(
            controller.ledger.byPraticaPath[oldPath] == nil,
            "the first of two concurrent callers must not resurrect the old key"
        )
        #expect(controller.ledger.byPraticaPath[newPath]?.importedMessageIDs == ["<a@rossi-spa.it>"])

        // The regeneration's own outcome lands second, carrying the SAME pre-move path -
        // MINOR 2's actual race, since the old code would have already consumed the
        // redirect above and left nothing for this second caller to resolve through.
        controller.recordSyncOutcome(
            PraticaSyncEngine.SyncOutcome(
                writtenFiles: [], importedMessageIDs: ["<b@rossi-spa.it>"],
                noLongerInMail: [], regeneratedPendingFiles: ["<b@rossi-spa.it>"], cancelled: false, bridge: []
            ),
            for: oldPath, session: session, isCurrentVault: true
        )

        #expect(
            controller.ledger.byPraticaPath[oldPath] == nil,
            "the second of two concurrent callers must not resurrect the old key either"
        )
        #expect(
            controller.ledger.byPraticaPath[newPath]?.importedMessageIDs.sorted() == ["<a@rossi-spa.it>", "<b@rossi-spa.it>"],
            "both callers' outcomes must fold into the SAME relocated key"
        )

        // Once both callers actually finish (their own `defer`/completion path in
        // production), the redirect this relocation left is safe to drop - proving the
        // chosen "prune once idle" design, not just that resolution itself is safe.
        controller.endSync()
        #expect(
            controller.praticaPathRedirects[oldPath] != nil,
            "the regeneration is still claimed, so the redirect must not be pruned yet"
        )
        controller.endRegeneration(oldPath)
        #expect(
            controller.praticaPathRedirects.isEmpty,
            "once nothing anywhere is still in flight, the redirect this relocation left must be pruned"
        )
    }

    // MARK: - Round-4 review, §1: `praticaPath(continuing:)`, the one door
    // `PraticaLiveSync+Run.swift`'s `RunContext.livePraticaPath(in:)` goes through -
    // after this, there is no way to spell a pratica path inside that pipeline other
    // than through this resolver.

    @Test func praticaPathContinuingReturnsTheCapturedPathWhenNothingRelocated() throws {
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })

        let resolved = try controller.praticaPath(continuing: "01 Progetti/Tifone/X")

        #expect(resolved == "01 Progetti/Tifone/X", "nothing relocated it, so the captured path is still the live one")
    }

    @Test func praticaPathContinuingRefusesAndNamesWhereThePraticaWent() throws {
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let oldPath = "01 Progetti/Tifone/X"
        let newPath = "Calendar/01 Progetti/Tifone/X"
        controller.praticaPathRedirects[oldPath] = newPath

        do {
            _ = try controller.praticaPath(continuing: oldPath)
            Issue.record("expected praticaPath(continuing:) to throw .praticaRelocated")
        } catch let stop as PraticaRunStop {
            #expect(stop == .praticaRelocated(from: oldPath, to: newPath))
        } catch {
            Issue.record("expected PraticaRunStop, got \(error)")
        }

        // The two-hop chain: relocated twice before this caller ever asked - the same
        // multi-hop walk `destination(of:)` already does for
        // `recordSyncOutcome`, reused here rather than forked.
        let secondPath = "Calendar/02 Progetti/Tifone/X"
        controller.praticaPathRedirects[newPath] = secondPath

        do {
            _ = try controller.praticaPath(continuing: oldPath)
            Issue.record("expected praticaPath(continuing:) to throw .praticaRelocated across both hops")
        } catch let stop as PraticaRunStop {
            #expect(
                stop == .praticaRelocated(from: oldPath, to: secondPath),
                "the caller must be told where the pratica lives NOW, not the first hop"
            )
        } catch {
            Issue.record("expected PraticaRunStop, got \(error)")
        }
    }

    @Test func praticaPathContinuingIsOnlyMeaningfulWhileARunHoldsItsClaim() throws {
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let oldPath = "01 Progetti/Tifone/X"
        let newPath = "Calendar/01 Progetti/Tifone/X"
        controller.updateLedger(.live(nil)) { $0.byPraticaPath[oldPath] = .empty }
        controller.beginSync(oldPath)
        let vault = VaultController()

        controller.followFolderRelocations([MovedNote(old: oldPath, new: newPath)], in: vault)
        #expect(controller.praticaPathRedirects[oldPath] == newPath, "a claimed path in flight must leave a redirect")

        // The claim ends (the run's own `defer { controller.endSync() }`), and with
        // nothing else in flight `pruneRedirectsIfIdle` wipes the whole map - documents
        // why `beginSync`/`endSync` must bracket the WHOLE of `runExclusive`: the
        // resolver is only meaningful while a run still holds its claim.
        controller.endSync()
        #expect(controller.praticaPathRedirects.isEmpty)

        let resolved = try controller.praticaPath(continuing: oldPath)
        #expect(
            resolved == oldPath,
            "once nothing is left to redirect through, the resolver returns its input rather than throwing"
        )
    }
}

// MARK: - Review round 3: a stale «Rigenera…» preview must never clobber a superseding one

@MainActor
@Suite(.serialized) struct PraticaRegenerationSupersededPreviewTests {
    private typealias Fixtures = PraticaSyncFixtures

    /// A second, distinct message for the same pratica - `EmailFixtureCorpus` has no
    /// builder taking an arbitrary `Message-Id`, and this suite needs one message the
    /// index resolves as something other than the one `completeMessageRFC822` already
    /// is (`PraticaSyncRegressionRetryTests.threeAttachmentMessageRFC822`'s own reason
    /// for authoring its own body inline rather than reusing a fixed one).
    private static func secondMessageRFC822(messageID: String) -> String {
        """
        From: Mario Rossi <m.rossi@rossi-spa.it>\r
        To: Stefano Ferri <stefano@stefer.it>\r
        Subject: Conferma ordine\r
        Message-Id: \(messageID)\r
        Date: Thu, 11 Jun 2026 15:30:00 +0200\r
        \r
        Confermiamo la ricezione del suo ordine.\r
        """
    }

    /// Review round 3's MAJOR, introduced by round 2's own fix: `prepareRegeneration`
    /// captured `praticaPath` before its only `await` (`engine.regenerationPreview`), but
    /// nothing stopped an attempt abandoned by «Annulla» from resuming later and writing
    /// `.ready` over a DIFFERENT, still-current attempt's own state once dismissing the
    /// first no longer canceled anything in flight.
    ///
    /// End-to-end through `PraticheController.live(vault:)` + `PraticaLiveSync`, the
    /// same production wiring `PergamenumApp` uses - unlike the analogous `runExclusive`
    /// race `Tests/PraticaLiveSyncRecordOutcomeTests.swift` found unreproducible
    /// end-to-end (no controllable suspension point reachable from outside),
    /// `prepareRegeneration` has exactly one: the single `await
    /// engine.regenerationPreview(...)` call, with nothing before it in the function
    /// ever suspending. `waitUntil` on `regeneratingPraticaPaths` - set by the very first
    /// line of that unbroken synchronous prefix - therefore pins task A at that exact
    /// boundary deterministically, no sleep-against-the-actor guess needed.
    @Test func anAbandonedRegenerationPreviewNeverClobbersASupersedingOne() async throws {
        let praticaPath = Fixtures.praticaFolder
        let messageIDA = "<abc123@rossi-spa.it>"
        let messageIDB = "<def456@rossi-spa.it>"
        let dateA = Date(timeIntervalSince1970: 1_749_557_170)
        let dateB = Date(timeIntervalSince1970: 1_749_643_570)

        let vault = try TemporaryVault()
        try vault.write(dossierNote(conversations: [112_409]), to: "\(praticaPath)/pratica.md")

        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [
                .init(
                    rowID: 1, subject: "Richiesta offerta", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                    conversationID: 112_409, dateSent: dateA, dateReceived: dateA,
                    emlxBody: EmailFixtureCorpus.completeMessageRFC822
                ),
                .init(
                    rowID: 2, subject: "Conferma ordine", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                    conversationID: 112_409, dateSent: dateB, dateReceived: dateB,
                    emlxBody: Self.secondMessageRFC822(messageID: messageIDB)
                ),
            ]
        )
        await MailStoreOverride.acquire(settingRootTo: fixture.root)
        defer { MailStoreOverride.release() }

        // Both notes seeded directly (`PraticaRegenerationTests`'s own pattern) - a real
        // membership-rule sync is not what this race is about.
        let seedEngine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vault.root)
        let seedRequest = PraticaSyncEngine.SyncRequest(
            praticaFolder: praticaPath, dossier: Fixtures.sampleDossier(),
            candidates: [
                Fixtures.row(rowID: 1, messageID: messageIDA, date: dateA),
                Fixtures.row(rowID: 2, messageID: messageIDB, date: dateB),
            ],
            onDisk: [], settings: .default
        )
        _ = try await seedEngine.sync(seedRequest)

        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let pratiche = PraticheController.live(vault: vaultController)

        // «Rigenera…» on A - `PraticaCommandActions.requestRegeneration`'s own shape:
        // the sheet opens to `.preparing` before the async preview is even started.
        pratiche.regeneration = .preparing(notePath: "A", subject: "A", praticaPath: praticaPath)
        let taskA = Task { @MainActor in
            await pratiche.prepareRegeneration?(praticaPath, messageIDA)
        }
        try await waitUntil { pratiche.regeneratingPraticaPaths.contains(praticaPath) }

        // «Annulla», before A's own preview has resolved.
        pratiche.dismissRegeneration()
        #expect(pratiche.regeneration == nil)
        #expect(!pratiche.regeneratingPraticaPaths.contains(praticaPath), "dismissing A must release its claim")

        // «Rigenera…» on B, a different message in the same pratica - runs to completion
        // before A's abandoned preview ever resolves.
        pratiche.regeneration = .preparing(notePath: "B", subject: "B", praticaPath: praticaPath)
        await pratiche.prepareRegeneration?(praticaPath, messageIDB)

        guard case .ready(let planB) = pratiche.regeneration else {
            Issue.record("expected B's own preview to resolve to .ready, got \(String(describing: pratiche.regeneration))")
            // taskA still needs the override held by `defer { MailStoreOverride.release() }`
            // above - await it before returning, or this early exit releases the gate while
            // taskA is still resolving against it.
            _ = await taskA.value
            vaultController.close()
            return
        }
        #expect(planB.messageID == messageIDB)

        // A's stale, abandoned preview actually resolves only now.
        _ = await taskA.value

        guard case .ready(let planAfter) = pratiche.regeneration else {
            Issue.record(
                "A's resurfaced, superseded preview must never clobber B's - got \(String(describing: pratiche.regeneration))"
            )
            vaultController.close()
            return
        }
        #expect(planAfter.messageID == messageIDB, "A's stale preview must never resurface once B has superseded it")
        #expect(
            pratiche.regeneratingPraticaPaths.contains(praticaPath),
            "B's own claim must still be held - A's stale completion must not double-release it"
        )

        vaultController.close()
    }
}

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
