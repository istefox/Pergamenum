import Foundation
import Testing
@testable import Pergamenum

// ADR-0076 (PG-338), plan docs/plans/pratiche-message-anchored-entries.md - gaps found when the
// red suites of Tasks 2, 3 and 5 were checked against the SPEC: R-01 ("compared byte for byte"),
// R-04/R-08 (entry ids past nine same-minute entries), R-14 (the destination already holds
// entries anchored to the same message).

@Suite struct PraticaAnchorByteForByteTests {
    private static let start = Date(timeIntervalSince1970: 1_780_000_000)

    @Test func anAnchorDifferingOnlyInCaseNamesNoMessage() throws {
        typealias Item = PraticaTimelineOrder.Item
        let items = [
            Item(kind: .message(messageID: "<Offerta@Rossi.it>", tieKey: "a"), date: Self.start),
            Item(kind: .entry(anchor: "<offerta@rossi.it>", ordinal: 0), date: Self.start.addingTimeInterval(60)),
        ]
        let placed = PraticaTimelineOrder.arrange(items)
        let entry = try #require(placed.first { $0.index == 1 })

        #expect(entry.placement == .orphaned(messageID: "<offerta@rossi.it>"))
    }

    @Test func anAnchorLineKeepsTheIDVerbatimIncludingCase() {
        let source = "## 2026-06-10 14:06 Nota · Mario Rossi\n<!-- pergamenum-message: <AbC@Rossi.IT> -->\ncorpo\n"

        #expect(PraticaManualEntries.parse(source).first?.anchor == "<AbC@Rossi.IT>")
    }
}

@MainActor
@Suite(.serialized) struct PraticaEntryIDPastNineTests {
    @Test func theTenthSameMinuteEntryKeepsTodaysIDAndFileOrder() throws {
        let vault = try TemporaryVault()
        var text = "---\ndate: 2026-06-10\n---\n\n"
        for index in 0..<11 {
            let anchor = index % 2 == 0 ? "" : "<!-- pergamenum-message: <x@y.it> -->\n"
            text += "## 2026-06-10 14:06 Nota · Mario Rossi\n\(anchor)voce \(index)\n\n"
        }
        try vault.write(text, to: "Rossi/Offerta/pratica.md")

        let read = PraticheController.readTimeline(praticaPath: "Rossi/Offerta", vaultRoot: vault.root)

        let expected = ["Rossi/Offerta#entry-202606101406"]
            + (1...10).map { "Rossi/Offerta#entry-202606101406-\($0)" }
        #expect(read.entries.map(\.id) == expected)
        #expect(read.entries.map(\.fileOrdinal) == Array(0...10))
        #expect(read.entries.map(\.bodyPreview) == (0..<11).map { "voce \($0)" })
        #expect(read.entries.map(\.anchor) == (0..<11).map { $0 % 2 == 0 ? nil : "<x@y.it>" })
    }
}

@MainActor
@Suite(.serialized) struct PraticaEntryCarryIntoExistingGroupTests {
    private typealias Rig = CarryHarness

    @Test func entriesAlreadyAnchoredAtTheDestinationStayAndAllSitUnderTheMessage() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        let earlier = "## 2026-06-01 09:00 Nota · Mario Rossi\n"
            + "<!-- pergamenum-message: <offerta@rossi-spa.it> -->\nGia copiata qui.\n"
        try Rig.write(
            Rig.frontmatter + Rig.destinationBody + "\n" + earlier, to: Rig.destinationNote, under: vault.root
        )
        harness.show(Rig.source)

        try await harness.move()

        let destination = try harness.text(Rig.destinationNote)
        #expect(Rig.body(destination) == Rig.destinationBody + "\n" + earlier + "\n" + Rig.first + "\n" + Rig.second)
        #expect(harness.entryPlacements(in: Rig.destination) == [
            .anchored(messageID: Rig.messageID), .anchored(messageID: Rig.messageID),
            .anchored(messageID: Rig.messageID),
        ])
        #expect(harness.pratiche.problem == nil)
        // The source no longer holds any block of the moved message.
        #expect(PraticaEntryEdit.blocks(anchoredTo: Rig.messageID, in: try harness.text(Rig.sourceNote)).isEmpty)
        harness.controller.close()
    }
}
