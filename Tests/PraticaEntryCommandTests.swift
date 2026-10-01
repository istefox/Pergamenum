import Foundation
import Testing
@testable import Pergamenum

// ADR-0076 §D5/§D7/§D8 (PG-338), plan docs/plans/pratiche-message-anchored-entries.md, Task 6 -
// R-02, R-03, R-11, R-12, R-18: the two catalogues, the anchored insert, the anchor/unanchor
// door and the picker's pure model. The vault fixtures are `CarryHarness`'s
// (`PraticaEntryCarryTests.swift`): a pratica with two messages, two entries anchored to one of
// them, one anchored elsewhere and one free entry, last.

@Suite struct PraticaEntryCatalogueTests {
    // MARK: - R-02

    @Test func addNoteAndAddCallAreOfferedOnEveryMessageRowAndCarryNoArgument() {
        for hasAttachments in [true, false] {
            for hasLinkedNote in [true, false] {
                let commands = MessageCommand.available(hasAttachments: hasAttachments, hasLinkedNote: hasLinkedNote)
                #expect(commands.contains(.addNote))
                #expect(commands.contains(.addCall))
                let spoken = MessageCommand.accessibilityCommands(
                    hasAttachments: hasAttachments, hasLinkedNote: hasLinkedNote
                )
                #expect(spoken.contains(.addNote))
                #expect(spoken.contains(.addCall))
                #expect(!spoken.contains(.moveTo))
                #expect(!spoken.contains(.alsoAddTo))
                #expect(spoken == commands.filter { !$0.carriesArgument })
            }
        }
        #expect(!MessageCommand.addNote.carriesArgument)
        #expect(!MessageCommand.addCall.carriesArgument)
        #expect(MessageCommand.addNote.identifier == "pratiche-message-command-addNote")
    }

    // MARK: - R-12

    @Test func unlinkMessageIsOfferedOnlyOnAnEntryWithAnAnchor() {
        #expect(PraticaEntryCommand.available(hasAnchor: false) == [.linkMessage])
        #expect(PraticaEntryCommand.available(hasAnchor: true) == [.linkMessage, .unlinkMessage])
    }

    @Test func entryCommandsHaveTheirItalianTitlesAndStableIdentifiers() {
        #expect(PraticaEntryCommand.linkMessage.title == "Collega a un messaggio…")
        #expect(PraticaEntryCommand.unlinkMessage.title == "Scollega dal messaggio")
        for command in PraticaEntryCommand.allCases {
            #expect(command.identifier == "pratiche-entry-command-\(command.rawValue)")
        }
    }

    // MARK: - R-11: the picker's rows

    private func message(
        _ id: String?, sender: String, subject: String, minute: Double
    ) -> PraticaTimelineEntry {
        PraticaTimelineEntry(
            id: "P/email/\(subject).md", kind: .message, date: Date(timeIntervalSince1970: minute * 60),
            direction: .received, senderDisplayName: sender, subject: subject, bodyPreview: "",
            hasAttachments: false, messageID: id, isInMail: true
        )
    }

    @Test func pickerRowsListMessagesOnlyInTimelineOrderAndSkipAnEmptyMessageID() {
        let note = PraticaTimelineEntry(
            id: "P#entry-1", kind: .note, date: Date(timeIntervalSince1970: 30), direction: nil,
            senderDisplayName: "Mario", subject: "Nota · Mario", bodyPreview: "", hasAttachments: false,
            messageID: nil, isInMail: true
        )
        let timeline = [
            message("<a@x>", sender: "Mario Rossi", subject: "Offerta", minute: 1),
            note,
            message("", sender: "Vuoto", subject: "Senza id", minute: 2),
            message(nil, sender: "Nessuno", subject: "Nil", minute: 3),
            message("<b@x>", sender: "Luigi Verdi", subject: "Consegna", minute: 4),
            message("<a@x>", sender: "Mario Rossi", subject: "Copia", minute: 5),
            message("<c-->x>", sender: "Arrow", subject: "Freccia", minute: 6),
            message("<d\r@x>", sender: "Cr", subject: "Ritorno", minute: 7),
            message("<e\n@x>", sender: "Lf", subject: "Acapo", minute: 8),
        ]
        let rows = PraticaMessagePickerModel.rows(from: timeline, filter: "", currentAnchor: "<b@x>")
        #expect(rows.map(\.messageID) == ["<a@x>", "<b@x>"])
        #expect(rows.map(\.isCurrent) == [false, true])
        #expect(rows.first?.subject == "Offerta")
        #expect(rows.first?.sender == "Mario Rossi")
    }

    @Test func pickerRowsFilterOnSenderAndSubjectCaseInsensitively() {
        let timeline = [
            message("<a@x>", sender: "Mario Rossi", subject: "Offerta", minute: 1),
            message("<b@x>", sender: "Luigi Verdi", subject: "Consegna", minute: 2),
        ]
        #expect(PraticaMessagePickerModel.rows(from: timeline, filter: "rossi", currentAnchor: nil)
            .map(\.messageID) == ["<a@x>"])
        #expect(PraticaMessagePickerModel.rows(from: timeline, filter: "  CONSEGNA ", currentAnchor: nil)
            .map(\.messageID) == ["<b@x>"])
        #expect(PraticaMessagePickerModel.rows(from: timeline, filter: "nessuno", currentAnchor: nil).isEmpty)
    }
}

@MainActor
@Suite(.serialized) struct PraticaEntryVerbTests {
    private typealias Rig = CarryHarness

    private static let anchorOf = { (id: String) in PraticaEntryAnchor.line(for: id) ?? "" }

    /// The selected pratica's manual entry at `ordinal`, as the timeline placed it.
    private func entry(_ harness: CarryHarness, ordinal: Int) throws -> PraticaTimelineEntry {
        try #require(harness.pratiche.timeline.first { $0.kind != .message && $0.fileOrdinal == ordinal })
    }

    // MARK: - R-11, R-12

    @Test func anchorWritesTheLineOnAFreeEntryAndNothingElse() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        defer { harness.controller.close() }
        let before = try harness.text(Rig.sourceNote)

        await harness.actions.anchor(try entry(harness, ordinal: 3), to: Rig.freeMessageID)

        let expectedFree = "## 2026-06-10 13:00 Nota · Mario Rossi\n"
            + Self.anchorOf(Rig.freeMessageID) + "\nVoce libera.\n"
        #expect(try harness.text(Rig.sourceNote)
            == Rig.frontmatter + Rig.intro + Rig.first + "\n" + Rig.other + "\n" + Rig.second + "\n" + expectedFree)
        #expect(before.hasPrefix(Rig.frontmatter))
        #expect(harness.pratiche.problem == nil)
        #expect(try entry(harness, ordinal: 3).placement == .anchored(messageID: Rig.freeMessageID))
    }

    @Test func anchorReplacesTheLineOnAnAnchoredEntry() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        defer { harness.controller.close() }

        await harness.actions.anchor(try entry(harness, ordinal: 0), to: Rig.freeMessageID)

        let replaced = "## 2026-06-10 10:00 Nota · Mario Rossi\n"
            + Self.anchorOf(Rig.freeMessageID) + "\nPrima voce collegata.\n"
        #expect(try harness.text(Rig.sourceNote)
            == Rig.frontmatter + Rig.intro + replaced + "\n" + Rig.other + "\n" + Rig.second + "\n" + Rig.free)
    }

    @Test func unanchorRemovesOnlyTheLine() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        defer { harness.controller.close() }

        await harness.actions.unanchor(try entry(harness, ordinal: 0))

        let freed = "## 2026-06-10 10:00 Nota · Mario Rossi\nPrima voce collegata.\n"
        #expect(try harness.text(Rig.sourceNote)
            == Rig.frontmatter + Rig.intro + freed + "\n" + Rig.other + "\n" + Rig.second + "\n" + Rig.free)
        #expect(try entry(harness, ordinal: 0).placement == .free)
    }

    @Test func runLinkMessageRaisesTheAnchorRequestForThatEntry() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        defer { harness.controller.close() }
        let free = try entry(harness, ordinal: 3)

        #expect(harness.actions.commands(forEntry: free) == [.linkMessage])
        #expect(harness.actions.commands(forEntry: try entry(harness, ordinal: 0)) == [.linkMessage, .unlinkMessage])
        harness.actions.run(.linkMessage, on: free)

        #expect(harness.pratiche.anchorRequest?.entry == free)
    }

    // MARK: - R-18

    @Test(arguments: [true, false])
    func bothVerbsRefuseWhilePraticaMdIsDirtyAndLeaveItByteIdentical(anchoring: Bool) async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        defer { harness.controller.close() }
        let before = try harness.text(Rig.sourceNote)
        let target = try entry(harness, ordinal: 0)
        harness.controller.openChosenNote(at: Rig.sourceNote)
        harness.controller.updateOpenNoteText(before + "\nNon salvato.\n")
        try #require(harness.controller.hasUnsavedTab(showing: Rig.sourceNote))

        if anchoring {
            await harness.actions.anchor(target, to: Rig.freeMessageID)
        } else {
            await harness.actions.unanchor(target)
        }

        #expect(harness.pratiche.problem == PraticaCommandActions.unsavedEntrySentence)
        #expect(try harness.text(Rig.sourceNote) == before)
    }

    @Test(arguments: [true, false])
    func bothVerbsRefuseAndReloadWhenTheFileChangedSinceTheTimelineRead(anchoring: Bool) async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        defer { harness.controller.close() }
        let target = try entry(harness, ordinal: 0)
        let external = try harness.text(Rig.sourceNote) + "\n## 2026-06-11 09:00 Nota · Altro\nScritta fuori.\n"
        try Rig.write(external, to: Rig.sourceNote, under: vault.root)

        if anchoring {
            await harness.actions.anchor(target, to: Rig.freeMessageID)
        } else {
            await harness.actions.unanchor(target)
        }

        #expect(harness.pratiche.problem == PraticaEntryCarry.staleTimelineSentence)
        #expect(try harness.text(Rig.sourceNote) == external)
        let session = try #require(harness.controller.session)
        #expect(harness.pratiche.timelineOrigin == (try session.read(Rig.sourceNote)).record.contentHash)
    }

    /// The picker holds its entry while the timeline reloads under it (a finished sync, the
    /// inspector's beat): `timelineOrigin` then names the changed file, so only the hash the
    /// entry carries can tell its ordinal is stale.
    @Test(arguments: [true, false])
    func bothVerbsRefuseAnEntryCapturedBeforeTheTimelineReloadedOverAChangedFile(anchoring: Bool) async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        defer { harness.controller.close() }
        let target = try entry(harness, ordinal: 0)
        let inserted = "## 2026-06-09 09:00 Nota · Nuova\nInserita fuori, prima di tutte.\n\n"
        let original = try harness.text(Rig.sourceNote)
        let external = original.replacingOccurrences(of: Rig.first, with: inserted + Rig.first)
        try #require(external != original)
        try Rig.write(external, to: Rig.sourceNote, under: vault.root)
        harness.pratiche.reloadTimeline(from: harness.controller)
        let session = try #require(harness.controller.session)
        try #require(harness.pratiche.timelineOrigin == (try session.read(Rig.sourceNote)).record.contentHash)

        if anchoring {
            await harness.actions.anchor(target, to: Rig.freeMessageID)
        } else {
            await harness.actions.unanchor(target)
        }

        #expect(harness.pratiche.problem == PraticaEntryCarry.staleTimelineSentence)
        #expect(try harness.text(Rig.sourceNote) == external)
    }

    // MARK: - R-03

    @Test func insertAnchoredAppendsHeadingAnchorAndBodyLineInOneWriteAndMirrorsToday() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        defer { harness.controller.close() }
        harness.pratiche.load(from: harness.controller)
        harness.show(Rig.source)
        try #require(harness.controller.settings.pratiche.mirrorsToDailyNote)
        let navigation = Navigation()
        let composer = PraticaEntryComposer(
            pratiche: harness.pratiche, vault: harness.controller, navigation: navigation
        )
        let (message, detail) = try harness.row(Rig.freeMessageID)
        let session = try #require(harness.controller.session)
        let generation = session.landedGeneration(at: Rig.sourceNote)
        let started = Date()

        await composer.insertAnchored(.call, on: message, detail: detail)

        let text = try harness.text(Rig.sourceNote)
        let written = try #require(PraticaManualEntries.parse(text).last)
        let sender = try #require(EmailHeaderParser.parseAddress("m.rossi@rossi-spa.it")?.displayText)
        #expect(written.kind == .call)
        #expect(written.anchor == Rig.freeMessageID)
        #expect(written.counterpart == sender)
        #expect(written.body.isEmpty)
        #expect(written.date >= started.addingTimeInterval(-60) && written.date <= Date())
        let heading = "## \(PraticaEntry.headingFormatter.string(from: written.date)) Telefonata · \(sender)"
        #expect(text.hasSuffix("\n\n" + heading + "\n" + Self.anchorOf(Rig.freeMessageID) + "\n\n"))
        #expect(session.landedGeneration(at: Rig.sourceNote) == generation + 1, "una sola scrittura")
        // The caret lands on the empty body line, under the anchor line.
        let jump = try #require(navigation.outlineJump)
        #expect(jump.range == NSRange(location: (text as NSString).length - 1, length: 0))
        // The entry reads back anchored, under its message.
        let placed = try #require(harness.pratiche.timeline.first { $0.kind == .call })
        #expect(placed.placement == .anchored(messageID: Rig.freeMessageID))
        // Today's daily note gained its line.
        let dailyPath = try await session.dailyNote(for: CalendarDate(Date()))
        #expect(try session.read(dailyPath).text.contains("- [[Offerta]] — Telefonata · \(sender)"))
    }

    // MARK: - Refusals that write nothing (R-03, R-11, R-12, R-18)

    /// A copy of a real message row whose Message-ID an anchor line cannot name.
    private func unnameable(_ entry: PraticaTimelineEntry, id: String?) -> PraticaTimelineEntry {
        PraticaTimelineEntry(
            id: entry.id, kind: entry.kind, date: entry.date, direction: entry.direction,
            senderDisplayName: entry.senderDisplayName, subject: entry.subject,
            bodyPreview: entry.bodyPreview, hasAttachments: entry.hasAttachments,
            messageID: id, isInMail: entry.isInMail
        )
    }

    @Test(arguments: ["<a-->b@x>", "<a\nb@x>", ""])
    func insertAnchoredOnAnUnnameableMessageIDReportsAndWritesNothing(badID: String) async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        defer { harness.controller.close() }
        harness.pratiche.load(from: harness.controller)
        harness.show(Rig.source)
        let composer = PraticaEntryComposer(
            pratiche: harness.pratiche, vault: harness.controller, navigation: Navigation()
        )
        let (message, detail) = try harness.row(Rig.messageID)
        let before = try harness.text(Rig.sourceNote)

        await composer.insertAnchored(.note, on: unnameable(message, id: badID), detail: detail)

        #expect(harness.pratiche.problem != nil)
        #expect(try harness.text(Rig.sourceNote) == before)
    }

    @Test func insertAnchoredRefusesWhilePraticaMdIsDirtyInATab() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        defer { harness.controller.close() }
        harness.pratiche.load(from: harness.controller)
        harness.show(Rig.source)
        let composer = PraticaEntryComposer(
            pratiche: harness.pratiche, vault: harness.controller, navigation: Navigation()
        )
        let (message, detail) = try harness.row(Rig.messageID)
        let before = try harness.text(Rig.sourceNote)
        harness.controller.openChosenNote(at: Rig.sourceNote)
        harness.controller.updateOpenNoteText(before + "\nNon salvato.\n")
        try #require(harness.controller.hasUnsavedTab(showing: Rig.sourceNote))

        await composer.insertAnchored(.note, on: message, detail: detail)

        #expect(try harness.text(Rig.sourceNote) == before)
    }

    @Test func anchoringToAnUnnameableMessageIDIsRefusedAndWritesNothing() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        defer { harness.controller.close() }
        let before = try harness.text(Rig.sourceNote)

        await harness.actions.anchor(try entry(harness, ordinal: 3), to: "<a-->b@x>")

        #expect(harness.pratiche.problem != nil)
        #expect(try harness.text(Rig.sourceNote) == before)
    }

    @Test func unanchoringAFreeEntryChangesNothing() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        defer { harness.controller.close() }
        let before = try harness.text(Rig.sourceNote)
        let session = try #require(harness.controller.session)
        let generation = session.landedGeneration(at: Rig.sourceNote)

        await harness.actions.unanchor(try entry(harness, ordinal: 3))

        #expect(try harness.text(Rig.sourceNote) == before)
        #expect(session.landedGeneration(at: Rig.sourceNote) == generation)
    }

    @Test func insertAnchoredWritesNoDiaryLineWithTheMirrorOff() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        defer { harness.controller.close() }
        harness.controller.updateSettings { $0.pratiche.mirrorsToDailyNote = false }
        harness.pratiche.load(from: harness.controller)
        harness.show(Rig.source)
        let composer = PraticaEntryComposer(
            pratiche: harness.pratiche, vault: harness.controller, navigation: Navigation()
        )
        let (message, detail) = try harness.row(Rig.messageID)

        await composer.insertAnchored(.note, on: message, detail: detail)

        #expect(PraticaManualEntries.parse(try harness.text(Rig.sourceNote)).last?.anchor == Rig.messageID)
        let session = try #require(harness.controller.session)
        let dailyPath = try await session.dailyNote(for: CalendarDate(Date()))
        #expect(!(try session.read(dailyPath).text.contains("[[Offerta]]")))
    }
}
