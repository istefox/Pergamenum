import Foundation
import Testing
@testable import Pergamenum

// ADR-0076 §D1/§D3 (PG-338), plan docs/plans/pratiche-message-anchored-entries.md, Task 3 -
// R-01, R-21. Beside `PraticaReadTimelinePendingAttachmentsTests`
// (`Tests/PraticheControllerTests.swift`) in spirit; its own file because that one is already
// past SwiftLint's file_length limit.

@MainActor
@Suite(.serialized) struct PraticaReadTimelineAnchorTests {
    private static let praticaPath = "Rossi/Offerta"
    private static let notePath = "Rossi/Offerta/pratica.md"

    private static let source = """
    ---
    date: 2026-06-10
    ---

    Descrizione della pratica.

    ## 2026-06-10 14:06 Nota · Mario Rossi
      <!-- pergamenum-message: <offerta@rossi-spa.it> -->
    Primo paragrafo.

    Secondo paragrafo.

    ## 2026-06-10 14:06 Telefonata · Mario Rossi
    Seconda voce, stesso minuto.

    ## 2026-06-11 09:00 Nota · Luigi Verdi
    Terza voce.
    <!-- pergamenum-message: <non-ancora@verdi.it> -->

    """

    private static func read(_ text: String) throws -> PraticheController.TimelineRead {
        let vault = try TemporaryVault()
        try vault.write(text, to: notePath)
        return PraticheController.readTimeline(praticaPath: praticaPath, vaultRoot: vault.root)
    }

    @Test func anAnchoredEntryReadsWithItsAnchorOrdinalAndABodyWithoutTheAnchorLine() throws {
        let read = try Self.read(Self.source)

        // Today's ids, byte for byte: selection, expansion and `details` are keyed on them.
        #expect(read.entries.map(\.id) == [
            "Rossi/Offerta#entry-202606101406",
            "Rossi/Offerta#entry-202606101406-1",
            "Rossi/Offerta#entry-202606110900",
        ])
        #expect(read.entries.map(\.anchor) == ["<offerta@rossi-spa.it>", nil, nil])
        #expect(read.entries.map(\.fileOrdinal) == [0, 1, 2])
        #expect(read.entries.map(\.kind) == [.note, .call, .note])
        #expect(read.entries.map(\.senderDisplayName) == ["Mario Rossi", "Mario Rossi", "Luigi Verdi"])

        let first = read.entries[0]
        #expect(first.bodyPreview == "Primo paragrafo.")
        #expect(read.details[first.id]?.body == "Primo paragrafo.\n\nSecondo paragrafo.")
        #expect(read.details[first.id]?.notePath == Self.notePath)
        for entry in read.entries {
            #expect(!entry.bodyPreview.contains("pergamenum-message"))
        }
        // Lower in an entry the line is body text, not an anchor (R-01).
        #expect(read.details[read.entries[2].id]?.body.contains("pergamenum-message") == true)
    }

    @Test func aCRLFPraticaReadsTheSameEntries() throws {
        let lf = try Self.read(Self.source)
        let crlf = try Self.read(Self.source.replacingOccurrences(of: "\n", with: "\r\n"))

        // `sourceHash` is the hash of the bytes each entry was read from, so it differs with the
        // line ending by design; everything the file says about the entry must not.
        func withoutHash(_ entries: [PraticaTimelineEntry]) -> [PraticaTimelineEntry] {
            entries.map { entry in
                var copy = entry
                copy.sourceHash = nil
                return copy
            }
        }
        #expect(withoutHash(crlf.entries) == withoutHash(lf.entries))
        #expect(crlf.entries.allSatisfy { $0.sourceHash == crlf.praticaNoteHash && $0.sourceHash != nil })
        #expect(lf.entries.allSatisfy { $0.sourceHash == lf.praticaNoteHash && $0.sourceHash != nil })
        #expect(crlf.entries.map { crlf.details[$0.id]?.body } == lf.entries.map { lf.details[$0.id]?.body })
        #expect(crlf.entries.allSatisfy { !$0.bodyPreview.contains("\r") && !$0.subject.contains("\r") })
    }

    @Test func theNoteHashEqualsTheSessionsContentHashAndReloadStoresIt() async throws {
        let vault = try TemporaryVault()
        try vault.write(Self.source, to: Self.notePath)
        let controller = VaultController(recents: .volatile(), openTabs: .volatile())
        await controller.open(vault.root)
        let session = try #require(controller.session)
        let contentHash = try session.read(Self.notePath).record.contentHash

        let read = PraticheController.readTimeline(praticaPath: Self.praticaPath, vaultRoot: vault.root)
        #expect(read.praticaNoteHash == contentHash)

        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        pratiche.selection = Self.praticaPath
        pratiche.reloadTimeline(from: controller)
        #expect(pratiche.timelineOrigin == contentHash)

        pratiche.selection = nil
        pratiche.reloadTimeline(from: controller)
        #expect(pratiche.timelineOrigin == nil, "no selection clears the origin")

        controller.close()
    }

    @Test func reloadPlacesAnAnchoredEntryUnderItsMessage() async throws {
        let vault = try TemporaryVault()
        try vault.write(Self.source, to: Self.notePath)
        let document = MessageDocument(
            frontmatter: MessageDocument.MailFrontmatter(
                schemaVersion: 1, messageID: "<offerta@rossi-spa.it>", conversationID: 1, direction: .sent,
                // 2026-06-09 08:00 UTC: the day before the entry's own heading.
                date: Date(timeIntervalSince1970: 1_780_992_000), received: nil,
                from: "io@studio.it", to: ["m.rossi@rossi-spa.it"], cc: [], subject: "Offerta",
                attachments: [], body: .complete, original: nil
            ),
            newText: "Testo.", quotedHistory: nil, signature: nil
        )
        try vault.write(
            MessageDocument.render(document, tags: [Tag(namespace: .type, value: "email")]),
            to: "\(Self.praticaPath)/email/20260609_0800_offerta.md"
        )
        let controller = VaultController(recents: .volatile(), openTabs: .volatile())
        await controller.open(vault.root)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        pratiche.selection = Self.praticaPath
        pratiche.reloadTimeline(from: controller)

        #expect(pratiche.timeline.map(\.id) == [
            "Rossi/Offerta/email/20260609_0800_offerta.md",
            "Rossi/Offerta#entry-202606101406",
            "Rossi/Offerta#entry-202606101406-1",
            "Rossi/Offerta#entry-202606110900",
        ])
        #expect(pratiche.timeline[1].placement == .anchored(messageID: "<offerta@rossi-spa.it>"))
        #expect(pratiche.timeline[1].hostDirection == .sent)
        #expect(pratiche.timeline[2].placement == .free)

        controller.close()
    }

    /// ADR-0052's cross-vault lesson applied to the origin: a hash read in the vault being
    /// left must not survive the reset into the next one.
    @Test func aVaultSwitchClearsTheTimelineOrigin() async throws {
        let first = try TemporaryVault()
        try first.write(Self.source, to: Self.notePath)
        let second = try TemporaryVault()
        let firstController = VaultController(recents: .volatile(), openTabs: .volatile())
        await firstController.open(first.root)
        let secondController = VaultController(recents: .volatile(), openTabs: .volatile())
        await secondController.open(second.root)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        pratiche.reloadLedger(for: firstController.session)
        pratiche.selection = Self.praticaPath
        pratiche.reloadTimeline(from: firstController)
        #expect(pratiche.timelineOrigin != nil, "precondition")

        pratiche.reloadLedger(for: secondController.session)

        #expect(pratiche.selection == nil)
        #expect(pratiche.timelineOrigin == nil, "the reset clears the origin with the selection")
        #expect(pratiche.timelineOriginPraticaPath == nil)

        firstController.close()
        secondController.close()
    }

    /// Plan interpretation 7 without the double parse: the inspector's beat reloads only when
    /// `pratica.md` (or the selected pratica) moved on since the timeline read it.
    @Test func theInspectorBeatReloadsOnlyWhenPraticaMdMovedOn() async throws {
        let vault = try TemporaryVault()
        try vault.write(Self.source, to: Self.notePath)
        let controller = VaultController(recents: .volatile(), openTabs: .volatile())
        await controller.open(vault.root)
        let session = try #require(controller.session)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        pratiche.selection = Self.praticaPath
        pratiche.reloadTimeline(from: controller)
        let origin = pratiche.timelineOrigin

        #expect(!pratiche.reloadTimelineIfStale(from: controller), "an unchanged file is not parsed again")
        #expect(pratiche.timelineOrigin == origin)

        let edited = Self.source + "\n## 2026-06-12 10:00 Nota · Anna Bianchi\nQuarta voce.\n"
        try await session.write(edited, to: Self.notePath)

        #expect(pratiche.reloadTimelineIfStale(from: controller), "an in-app save of pratica.md reloads")
        #expect(pratiche.timelineOrigin == (try session.read(Self.notePath)).record.contentHash)
        #expect(pratiche.timeline.count == 4)
        #expect(!pratiche.reloadTimelineIfStale(from: controller))

        // A selection remapped without a reload (a rename's remap) over byte-identical bytes.
        try vault.write(edited, to: "Rossi/Copia/pratica.md")
        pratiche.selection = "Rossi/Copia"
        #expect(pratiche.reloadTimelineIfStale(from: controller), "a selection that moved on reloads")
        #expect(pratiche.timeline.allSatisfy { $0.id.hasPrefix("Rossi/Copia#") })

        controller.close()
    }
}
