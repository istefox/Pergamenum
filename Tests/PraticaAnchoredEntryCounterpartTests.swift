import Foundation
import Testing
@testable import Pergamenum

// ADR-0076 §D1/§D7 (PG-338), plan docs/plans/pratiche-message-anchored-entries.md, Task 6 -
// R-03 and plan interpretation 3: who an anchored entry's heading names, branch by branch, and
// the message-row verbs reaching the composer with the right kind. The received-message case
// is `PraticaEntryVerbTests.insertAnchoredAppendsHeadingAnchorAndBodyLineInOneWriteAndMirrorsToday`
// (`PraticaEntryCommandTests.swift`); this file holds the other branches, kept apart for
// SwiftLint's file length. The vault is `CarryHarness`'s (`PraticaEntryCarryTests.swift`).

@MainActor
@Suite(.serialized) struct PraticaAnchoredEntryCounterpartTests {
    private typealias Rig = CarryHarness

    /// The dossier's first counterpart: the fallback when the message names nobody, distinct
    /// from the client folder's name («Rossi») so the two fallbacks cannot be confused.
    private static let dossierCounterpart = "ufficio@rossi-spa.it"
    private static let dossierFrontmatter = "---\ndate: 2026-06-10\npergamenum-dossier: 1\n"
        + "pergamenum-dossier-counterparts:\n  - \(dossierCounterpart)\n---\n"
    private static let freeMessagePath = "\(Rig.source)/\(Rig.freeMessageFile)"

    /// The harness, with a dossier naming one counterpart, the person's own address set and
    /// the pratica list loaded.
    private func open(_ root: URL) async throws -> CarryHarness {
        let harness = try await Rig.open(root)
        try Rig.write(Self.dossierFrontmatter + Rig.sourceBody, to: Rig.sourceNote, under: root)
        harness.controller.updateSettings {
            $0.pratiche.ownAddresses = ["IO@studio.it"]
            $0.pratiche.mirrorsToDailyNote = false
        }
        harness.pratiche.load(from: harness.controller)
        harness.show(Rig.source)
        return harness
    }

    /// A sent message file carrying `Rig.freeMessageID`, written over the harness's own.
    private func writeSentMessage(to: [String], cc: [String], under root: URL) throws {
        let date = Date(timeIntervalSince1970: 1_780_905_600)
        let document = MessageDocument(
            frontmatter: MessageDocument.MailFrontmatter(
                schemaVersion: 1, messageID: Rig.freeMessageID, conversationID: 1, direction: .sent,
                date: date, received: date, from: "io@studio.it", to: to, cc: cc,
                subject: "Saluti", attachments: [], body: .complete, original: nil
            ),
            newText: "Testo.", quotedHistory: nil, signature: nil
        )
        let text = MessageDocument.render(document, tags: [Tag(namespace: .type, value: "email")])
        try Rig.write(text, to: Self.freeMessagePath, under: root)
    }

    /// Inserts a note anchored to the free message and answers the heading's counterpart.
    private func insertAndReadCounterpart(
        _ harness: CarryHarness, row: (entry: PraticaTimelineEntry, detail: PraticaRowDetail?)
    ) async throws -> String {
        let composer = PraticaEntryComposer(
            pratiche: harness.pratiche, vault: harness.controller, navigation: Navigation()
        )
        await composer.insertAnchored(.note, on: row.entry, detail: row.detail)
        #expect(harness.pratiche.problem == nil)
        let written = try #require(PraticaManualEntries.parse(try harness.text(Rig.sourceNote)).last)
        #expect(written.anchor == Rig.freeMessageID)
        return written.counterpart
    }

    private static func display(_ raw: String) throws -> String {
        try #require(EmailHeaderParser.parseAddress(raw)?.displayText)
    }

    // MARK: - A sent message

    @Test func aSentMessageNamesTheFirstRecipientThatIsNotOneOfTheOwnAddresses() async throws {
        let vault = try TemporaryVault()
        let recipient = "Luigi Verdi <l.verdi@verdi.it>"
        let harness = try await open(vault.root)
        defer { harness.controller.close() }
        try writeSentMessage(
            to: ["io@studio.it", recipient], cc: ["Anna Bianchi <a.bianchi@bianchi.it>"], under: vault.root
        )
        harness.show(Rig.source)

        let counterpart = try await insertAndReadCounterpart(harness, row: try harness.row(Rig.freeMessageID))

        #expect(counterpart == (try Self.display(recipient)))
    }

    @Test func aSentMessageAddressedOnlyToTheOwnAddressNamesTheFirstCc() async throws {
        let vault = try TemporaryVault()
        let copied = "Anna Bianchi <a.bianchi@bianchi.it>"
        let harness = try await open(vault.root)
        defer { harness.controller.close() }
        try writeSentMessage(to: ["io@studio.it"], cc: [copied, "Carlo Neri <c.neri@neri.it>"], under: vault.root)
        harness.show(Rig.source)

        let counterpart = try await insertAndReadCounterpart(harness, row: try harness.row(Rig.freeMessageID))

        #expect(counterpart == (try Self.display(copied)))
    }

    // MARK: - The fallback to the dossier

    @Test func aMessageThatNamesNobodyFallsBackToTheDossiersFirstCounterpart() async throws {
        let vault = try TemporaryVault()
        let harness = try await open(vault.root)
        defer { harness.controller.close() }
        try writeSentMessage(to: ["io@studio.it"], cc: [], under: vault.root)
        harness.show(Rig.source)

        let counterpart = try await insertAndReadCounterpart(harness, row: try harness.row(Rig.freeMessageID))

        #expect(counterpart == Self.dossierCounterpart)
    }

    enum Damage: String, CaseIterable { case removed, unparsable, notUTF8 }

    /// The row was read while the file was fine; by the time the verb runs it is gone or no
    /// longer a message the composer can read.
    @Test(arguments: Damage.allCases)
    func aMessageFileThatCannotBeReadFallsBackToTheDossiersFirstCounterpart(damage: Damage) async throws {
        let vault = try TemporaryVault()
        let harness = try await open(vault.root)
        defer { harness.controller.close() }
        let row = try harness.row(Rig.freeMessageID)
        try #require(row.detail?.notePath == Self.freeMessagePath)
        let url = vault.root.appending(path: Self.freeMessagePath, directoryHint: .notDirectory)
        switch damage {
        case .removed: try FileManager.default.removeItem(at: url)
        case .unparsable: try Data("Non è un messaggio.\n".utf8).write(to: url)
        case .notUTF8: try Data([0xFF, 0xFE, 0x00, 0xC3, 0x28]).write(to: url)
        }

        let counterpart = try await insertAndReadCounterpart(harness, row: row)

        #expect(counterpart == Self.dossierCounterpart)
    }

    // MARK: - The message-row verbs (R-03)

    @Test(arguments: [(MessageCommand.addNote, PraticaEntry.Kind.note), (.addCall, .call)])
    func runAddNoteAndAddCallWriteAnEntryOfTheirKindAnchoredToTheMessage(
        command: MessageCommand, kind: PraticaEntry.Kind
    ) async throws {
        let vault = try TemporaryVault()
        let harness = try await open(vault.root)
        defer { harness.controller.close() }
        let before = PraticaManualEntries.parse(try harness.text(Rig.sourceNote)).count
        let (message, detail) = try harness.row(Rig.freeMessageID)

        harness.actions.run(command, on: message, detail: detail)
        try await waitUntil {
            (try? harness.text(Rig.sourceNote)).map { PraticaManualEntries.parse($0).count } == before + 1
        }

        let written = try #require(PraticaManualEntries.parse(try harness.text(Rig.sourceNote)).last)
        #expect(written.kind == kind)
        #expect(written.anchor == Rig.freeMessageID)
        #expect(harness.pratiche.problem == nil)
    }
}
