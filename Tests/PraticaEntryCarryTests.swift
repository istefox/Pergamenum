import Foundation
import Testing
@testable import Pergamenum

// ADR-0076 §D6 (PG-338), plan docs/plans/pratiche-message-anchored-entries.md, Task 5 -
// R-14, R-15, R-18, R-19: «Sposta in…» carries the entries anchored to the moved message.
// Two pratiche in one vault; the source holds the message, two entries anchored to it, one
// anchored to another message and one free entry, the free one last so a removal never touches
// the end of the file. R-13, R-16 and R-17 are in `PraticaEntryCarryPinnedTests.swift`; the
// undo's branches (`carryBack`) are in `PraticaEntryCarryBackTests.swift`.

/// The shared vault, the files it starts with and the controllers over it. Not `@MainActor`
/// as a whole, so its constants can be read from `@Test(arguments:)`; what touches a
/// controller is.
struct CarryHarness {
    static let source = "Rossi/Offerta"
    static let destination = "Bianchi/Fornitura"
    static let sourceNote = "Rossi/Offerta/pratica.md"
    static let destinationNote = "Bianchi/Fornitura/pratica.md"
    static let messageID = "<offerta@rossi-spa.it>"
    static let messageFile = "email/20260609_0800_offerta.md"
    static let freeMessageID = "<libero@rossi-spa.it>"
    static let freeMessageFile = "email/20260608_0800_libero.md"

    static let frontmatter = "---\ndate: 2026-06-10\npergamenum-dossier: 1\n---\n"
    static let intro = "\nDescrizione.\n\n"
    static let first = "## 2026-06-10 10:00 Nota · Mario Rossi\n"
        + "<!-- pergamenum-message: <offerta@rossi-spa.it> -->\nPrima voce collegata.\n"
    static let other = "## 2026-06-10 11:00 Nota · Luigi Verdi\n"
        + "<!-- pergamenum-message: <altro@verdi.it> -->\nVoce di un altro messaggio.\n"
    static let second = "## 2026-06-10 12:00 Telefonata · Mario Rossi\n"
        + "<!-- pergamenum-message: <offerta@rossi-spa.it> -->\nSeconda voce collegata.\n"
    static let free = "## 2026-06-10 13:00 Nota · Mario Rossi\nVoce libera.\n"
    static let sourceBody = intro + first + "\n" + other + "\n" + second + "\n" + free
    static let destinationBody = "\nDescrizione destinazione.\n"

    let root: URL
    let controller: VaultController
    let pratiche: PraticheController
    let actions: PraticaCommandActions
    let manager: UndoManager

    @MainActor
    static func open(_ root: URL, lineBreak: LineBreak = .lf) async throws -> CarryHarness {
        try write(lineBreak.normalised(frontmatter + sourceBody), to: sourceNote, under: root)
        try write(lineBreak.normalised(frontmatter + destinationBody), to: destinationNote, under: root)
        try write(message(messageID, subject: "Offerta", day: 9), to: "\(source)/\(messageFile)", under: root)
        try write(message(freeMessageID, subject: "Saluti", day: 8), to: "\(source)/\(freeMessageFile)", under: root)

        let controller = VaultController(recents: .volatile(), openTabs: .volatile())
        await controller.open(root)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let manager = UndoManager()
        let actions = PraticaCommandActions(
            pratiche: pratiche, vault: controller, navigation: Navigation(), undoManager: manager
        )
        let harness = CarryHarness(
            root: root, controller: controller, pratiche: pratiche, actions: actions, manager: manager
        )
        harness.show(source)
        return harness
    }

    static func write(_ text: String, to relativePath: String, under root: URL) throws {
        let url = root.appending(path: relativePath, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// A received message file of June `day`, 08:00 UTC.
    static func message(_ id: String, subject: String, day: Int) -> String {
        let date = Date(timeIntervalSince1970: 1_780_905_600 + Double(day - 8) * 86_400)
        let document = MessageDocument(
            frontmatter: MessageDocument.MailFrontmatter(
                schemaVersion: 1, messageID: id, conversationID: 1, direction: .received,
                date: date, received: date, from: "m.rossi@rossi-spa.it", to: ["io@studio.it"], cc: [],
                subject: subject, attachments: [], body: .complete, original: nil
            ),
            newText: "Testo.", quotedHistory: nil, signature: nil
        )
        return MessageDocument.render(document, tags: [Tag(namespace: .type, value: "email")])
    }

    var destinationItem: PraticaListItem {
        PraticaListItem(
            id: Self.destination, title: "Fornitura", client: "Bianchi", status: "active",
            lastActivity: Date(), messagesSinceLastOpen: 0, hasNonEmptyTray: false
        )
    }

    func text(_ relativePath: String) throws -> String {
        try String(contentsOf: root.appending(path: relativePath, directoryHint: .notDirectory), encoding: .utf8)
    }

    func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(
            atPath: root.appending(path: relativePath, directoryHint: .notDirectory).path(percentEncoded: false)
        )
    }

    @MainActor
    func show(_ praticaPath: String?) {
        pratiche.selection = praticaPath
        pratiche.reloadTimeline(from: controller)
    }

    /// The selected pratica's message row carrying `id`, with its detail.
    @MainActor
    func row(_ id: String) throws -> (entry: PraticaTimelineEntry, detail: PraticaRowDetail?) {
        let entry = try #require(pratiche.timeline.first { $0.messageID == id })
        return (entry, pratiche.details[entry.id])
    }

    @MainActor
    func move(_ id: String = CarryHarness.messageID) async throws {
        let (entry, detail) = try row(id)
        await actions.move(entry, detail: detail, to: destinationItem)
    }

    /// The manual entries of `praticaPath`, as its timeline places them.
    @MainActor
    func entryPlacements(in praticaPath: String) -> [PraticaTimelineOrder.Placement] {
        show(praticaPath)
        return pratiche.timeline.filter { $0.kind != .message }.map(\.placement)
    }

    static func body(_ text: String) -> String { NoteDocument.parse(text).body }

    /// The frontmatter lines a move is allowed to leave alone: all but the dossier keys it
    /// writes (plan interpretation 1).
    static func untouchedFrontmatter(_ text: String) -> [String] {
        let document = NoteDocument.parse(text)
        let block = String(text.dropLast(document.body.count))
        return block.components(separatedBy: "\n").filter {
            !$0.hasPrefix("pergamenum-dossier-excluded") && !$0.hasPrefix("pergamenum-dossier-included")
                && !$0.hasPrefix("  - ")
        }
    }

    /// Every block anchored to the moved message, in either file.
    func carriedBlocks() throws -> [String] {
        try [Self.sourceNote, Self.destinationNote].flatMap {
            PraticaEntryEdit.blocks(anchoredTo: Self.messageID, in: try text($0))
        }
    }
}

@MainActor
@Suite(.serialized) struct PraticaEntryCarryTests {
    private typealias Rig = CarryHarness

    // MARK: - R-14

    @Test func moveAppendsBothBlocksThenRemovesThemAndUndoCarriesThemBack() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        let sourceBefore = try harness.text(Rig.sourceNote)
        let destinationBefore = try harness.text(Rig.destinationNote)

        try await harness.move()

        let sourceAfter = try harness.text(Rig.sourceNote)
        let destinationAfter = try harness.text(Rig.destinationNote)
        #expect(Rig.body(sourceAfter) == Rig.intro + Rig.other + "\n" + Rig.free)
        #expect(Rig.body(destinationAfter) == Rig.destinationBody + "\n" + Rig.first + "\n" + Rig.second)
        #expect(Rig.untouchedFrontmatter(sourceAfter) == Rig.untouchedFrontmatter(sourceBefore))
        #expect(Rig.untouchedFrontmatter(destinationAfter) == Rig.untouchedFrontmatter(destinationBefore))
        #expect(harness.exists("\(Rig.destination)/\(Rig.messageFile)"))
        #expect(harness.pratiche.problem == nil)
        #expect(harness.entryPlacements(in: Rig.destination) == [
            .anchored(messageID: Rig.messageID), .anchored(messageID: Rig.messageID),
        ])

        harness.show(Rig.source)
        harness.manager.undo()
        try await waitUntil {
            harness.exists("\(Rig.source)/\(Rig.messageFile)")
                && (try? harness.text(Rig.destinationNote)).map(Rig.body) == Rig.destinationBody
        }

        #expect(Rig.body(try harness.text(Rig.sourceNote))
            == Rig.intro + Rig.other + "\n" + Rig.free + "\n" + Rig.first + "\n" + Rig.second)
        #expect(Rig.body(try harness.text(Rig.destinationNote)) == Rig.destinationBody)
        #expect(!harness.exists("\(Rig.destination)/\(Rig.messageFile)"))
        #expect(harness.entryPlacements(in: Rig.source) == [
            .anchored(messageID: Rig.messageID), .anchored(messageID: Rig.messageID),
            .orphaned(messageID: "<altro@verdi.it>"), .free,
        ])
        harness.controller.close()
    }

    // MARK: - R-15

    @Test func aRefusedDestinationWriteMovesTheMessageAndLeavesTheEntriesHiddenInTheSource() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        let root = vault.root
        let sourceBody = Rig.body(try harness.text(Rig.sourceNote))
        harness.pratiche.testOnlyCarryHook = { phase in
            guard phase == .willAppend(notePath: Rig.destinationNote) else { return }
            let foreign = Rig.frontmatter + Rig.destinationBody + "Scritto da un altro.\n"
            try? Rig.write(foreign, to: Rig.destinationNote, under: root)
        }

        try await harness.move()

        #expect(harness.exists("\(Rig.destination)/\(Rig.messageFile)"))
        #expect(Rig.body(try harness.text(Rig.sourceNote)) == sourceBody)
        #expect(Rig.body(try harness.text(Rig.destinationNote)) == Rig.destinationBody + "Scritto da un altro.\n")
        let problem = try #require(harness.pratiche.problem)
        #expect(problem.contains(Rig.sourceNote) && problem.contains(Rig.destinationNote), "\(problem)")
        #expect(try harness.carriedBlocks().count == 2, "no block is lost")
        #expect(harness.entryPlacements(in: Rig.source) == [.orphaned(messageID: "<altro@verdi.it>"), .free])
        harness.controller.close()
    }

    @Test func aRefusedSourceRemovalLeavesTheBlocksInBothFilesAndSaysSo() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        let root = vault.root
        harness.pratiche.testOnlyCarryHook = { phase in
            guard phase == .willRemove(notePath: Rig.sourceNote),
                  let text = try? String(contentsOf: root.appending(path: Rig.sourceNote), encoding: .utf8)
            else { return }
            try? Rig.write(text + "\nAggiunta esterna.\n", to: Rig.sourceNote, under: root)
        }

        try await harness.move()

        #expect(harness.exists("\(Rig.destination)/\(Rig.messageFile)"))
        for notePath in [Rig.sourceNote, Rig.destinationNote] {
            #expect(PraticaEntryEdit.blocks(anchoredTo: Rig.messageID, in: try harness.text(notePath)).count == 2)
        }
        let problem = try #require(harness.pratiche.problem)
        #expect(problem.contains(Rig.sourceNote) && problem.contains(Rig.destinationNote), "\(problem)")
        #expect(problem.contains("sia in"), "\(problem)")

        // §D6: the removal was refused as a whole, so the source still holds every block and the
        // undo only takes them out of the destination. That holds for a FULL refusal only: after a
        // partial removal the undo first puts back in the source what it lost
        // (`PraticaEntryCarryBackTests`).
        harness.pratiche.testOnlyCarryHook = nil
        harness.show(Rig.source)
        harness.manager.undo()
        try await waitUntil {
            harness.exists("\(Rig.source)/\(Rig.messageFile)")
                && (try? harness.text(Rig.destinationNote)).map(Rig.body) == Rig.destinationBody
        }
        #expect(PraticaEntryEdit.blocks(anchoredTo: Rig.messageID, in: try harness.text(Rig.sourceNote)).count == 2)
        harness.controller.close()
    }

    // MARK: - R-18

    @Test(arguments: [CarryHarness.sourceNote, CarryHarness.destinationNote])
    func aDirtyPraticaTabRefusesTheMoveBeforeAnythingMoves(_ dirtyNote: String) async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        let sourceBefore = try harness.text(Rig.sourceNote)
        let destinationBefore = try harness.text(Rig.destinationNote)
        harness.controller.openNote(at: dirtyNote)
        harness.controller.updateOpenNoteText((try harness.text(dirtyNote)) + "Non salvato.\n")
        try #require(harness.controller.hasUnsavedTab(showing: dirtyNote))

        try await harness.move()

        #expect(harness.exists("\(Rig.source)/\(Rig.messageFile)"))
        #expect(!harness.exists("\(Rig.destination)/\(Rig.messageFile)"))
        #expect(try harness.text(Rig.sourceNote) == sourceBefore)
        #expect(try harness.text(Rig.destinationNote) == destinationBefore)
        #expect(harness.pratiche.problem == PraticaEntryCarry.unsavedSentence(notePath: dirtyNote))
        harness.controller.close()
    }

    @Test func aSourceChangedSinceTheTimelineReadRefusesAndReloads() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        let changed = Rig.frontmatter + Rig.sourceBody + "\nScritto da un altro.\n"
        try Rig.write(changed, to: Rig.sourceNote, under: vault.root)

        try await harness.move()

        #expect(harness.exists("\(Rig.source)/\(Rig.messageFile)"))
        #expect(try harness.text(Rig.sourceNote) == changed)
        #expect(harness.pratiche.problem == PraticaEntryCarry.staleTimelineSentence)
        let session = try #require(harness.controller.session)
        #expect(harness.pratiche.timelineOrigin == (try session.read(Rig.sourceNote)).record.contentHash)
        harness.controller.close()
    }

    @Test func aMessageWithNoAnchoredEntryMovesWhilePraticaIsDirtyAsBefore() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        harness.controller.openNote(at: Rig.sourceNote)
        harness.controller.updateOpenNoteText((try harness.text(Rig.sourceNote)) + "Non salvato.\n")

        try await harness.move(Rig.freeMessageID)

        #expect(harness.exists("\(Rig.destination)/\(Rig.freeMessageFile)"))
        #expect(!harness.exists("\(Rig.source)/\(Rig.freeMessageFile)"))
        #expect(Rig.body(try harness.text(Rig.sourceNote)) == Rig.sourceBody)
        #expect(Rig.body(try harness.text(Rig.destinationNote)) == Rig.destinationBody)
        #expect(try harness.text(Rig.sourceNote).contains("pergamenum-dossier-excluded"))
        #expect(harness.pratiche.problem == nil)
        harness.controller.close()
    }

    // MARK: - R-19

    @Test func aCRLFDestinationAndSourceStayCRLF() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root, lineBreak: .crlf)

        try await harness.move()

        let source = try harness.text(Rig.sourceNote)
        let destination = try harness.text(Rig.destinationNote)
        for text in [source, destination] {
            #expect(!text.replacingOccurrences(of: "\r\n", with: "").contains("\n"), "\(text.debugDescription)")
        }
        #expect(Rig.body(source) == LineBreak.crlf.normalised(Rig.intro + Rig.other + "\n" + Rig.free))
        #expect(Rig.body(destination)
            == LineBreak.crlf.normalised(Rig.destinationBody + "\n" + Rig.first + "\n" + Rig.second))
        harness.controller.close()
    }

    // MARK: - A tab that turns dirty during the move (CLAUDE.md: a check before an `await` is a filter)

    @Test func aDestinationTabDirtiedBeforeTheAppendRefusesItAndLosesNoBlock() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        let controller = harness.controller
        let sourceBody = Rig.body(try harness.text(Rig.sourceNote))
        let root = vault.root
        harness.pratiche.testOnlyCarryHook = { phase in
            guard phase == .willAppend(notePath: Rig.destinationNote),
                  let text = try? String(contentsOf: root.appending(path: Rig.destinationNote), encoding: .utf8)
            else { return }
            controller.openNote(at: Rig.destinationNote)
            controller.updateOpenNoteText(text + "Non salvato.\n")
        }

        try await harness.move()
        try #require(controller.hasUnsavedTab(showing: Rig.destinationNote))

        #expect(harness.exists("\(Rig.destination)/\(Rig.messageFile)"))
        #expect(Rig.body(try harness.text(Rig.sourceNote)) == sourceBody, "the source still holds them")
        #expect(Rig.body(try harness.text(Rig.destinationNote)) == Rig.destinationBody, "nothing appended")
        #expect(try harness.carriedBlocks().count == 2, "no block is lost")
        let expected = PraticaEntryCarry.sentence(
            for: .notCarried, source: Rig.source, destination: Rig.destination
        )
        #expect(harness.pratiche.problem == expected)
        controller.close()
    }

    @Test func aSourceTabDirtiedBeforeTheRemovalLeavesTheBlocksInBothFilesAndSaysSo() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        let controller = harness.controller
        let root = vault.root
        harness.pratiche.testOnlyCarryHook = { phase in
            guard phase == .willRemove(notePath: Rig.sourceNote),
                  let text = try? String(contentsOf: root.appending(path: Rig.sourceNote), encoding: .utf8)
            else { return }
            controller.openNote(at: Rig.sourceNote)
            controller.updateOpenNoteText(text + "Non salvato.\n")
        }

        try await harness.move()
        try #require(controller.hasUnsavedTab(showing: Rig.sourceNote))

        #expect(harness.exists("\(Rig.destination)/\(Rig.messageFile)"))
        for notePath in [Rig.sourceNote, Rig.destinationNote] {
            #expect(PraticaEntryEdit.blocks(anchoredTo: Rig.messageID, in: try harness.text(notePath)).count == 2)
        }
        let expected = PraticaEntryCarry.sentence(
            for: .appendedOnly(count: 2, missing: 2), source: Rig.source, destination: Rig.destination
        )
        #expect(harness.pratiche.problem == expected)
        controller.close()
    }

    // MARK: - hasUnsavedTab

    @Test func hasUnsavedTabAnswersPerPathAndRecordsNothing() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        #expect(!harness.controller.hasUnsavedTab(showing: Rig.sourceNote))

        harness.controller.openNote(at: Rig.sourceNote)
        #expect(!harness.controller.hasUnsavedTab(showing: Rig.sourceNote), "open and clean is not unsaved")
        harness.controller.updateOpenNoteText((try harness.text(Rig.sourceNote)) + "Non salvato.\n")

        #expect(harness.controller.hasUnsavedTab(showing: Rig.sourceNote))
        #expect(!harness.controller.hasUnsavedTab(showing: Rig.destinationNote))
        #expect(harness.controller.problems.isEmpty)
        harness.controller.close()
    }
}
