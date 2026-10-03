import Foundation
import Testing
@testable import Pergamenum

// ADR-0079 §D3 (PG-369), plan docs/plans/pg-369-pratiche-timeline-rail-and-excluded.md, Task 4 -
// R-05, R-06, R-02, R-03. An entry anchored to a message the pratica excluded is placed
// `.excluded` by the shared rule and dropped once, where `reloadTimeline` stores `timeline`
// (`PraticaTimelineModel.hidingExcluded`), so every consumer starts from rows that cannot include
// it. The text stays in `pratica.md`; nothing is written.

@Suite struct PraticaExcludedEntriesTests {
    /// 2026-06-10 10:00:00 UTC.
    private static let start = Date(timeIntervalSince1970: 1_781_085_600)

    private static func at(day: Int, minute: Int = 0) -> Date {
        start.addingTimeInterval(TimeInterval(day * 86_400 + 60 * minute))
    }

    private static func message(_ id: String, day: Int, messageID: String) -> PraticaTimelineEntry {
        PraticaTimelineEntry(
            id: id, kind: .message, date: at(day: day), direction: .received, senderDisplayName: "Mario Rossi",
            senderAddress: "mario@rossi.it", subject: "Oggetto \(id)", bodyPreview: "", hasAttachments: false,
            messageID: messageID, isInMail: true
        )
    }

    private static func entry(
        _ id: String, day: Int, ordinal: Int, anchor: String? = nil, subject: String = "Nota · Mario Rossi",
        text: String = "voce"
    ) -> PraticaTimelineEntry {
        PraticaTimelineEntry(
            id: id, kind: .note, date: at(day: day, minute: 5), direction: nil, senderDisplayName: "Mario Rossi",
            subject: subject, bodyPreview: text, hasAttachments: false, messageID: nil, isInMail: true,
            anchor: anchor, fileOrdinal: ordinal
        )
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    /// Day 0 message, day 2 an entry anchored to an excluded id (alone in its day), day 4 a free
    /// entry between two messages, day 5 a message, day 6 an orphan.
    private static let placed = PraticaTimelineModel.ordered([
        message("M1", day: 0, messageID: "<m1>"),
        entry("EXC", day: 2, ordinal: 0, anchor: "<out>", subject: "Nota · Nascosta", text: "segreto nascosto"),
        entry("FREE", day: 4, ordinal: 1),
        message("M2", day: 5, messageID: "<m2>"),
        entry("ORPH", day: 6, ordinal: 2, anchor: "<gone>"),
    ], excluded: ["<out>"])

    private static let visible = PraticaTimelineModel.hidingExcluded(placed)

    @Test func hidingExcludedRemovesTheExcludedRowsOnlyAndKeepsTheOrder() {
        #expect(Self.placed.map(\.id) == ["M1", "EXC", "FREE", "M2", "ORPH"], "precondition: the rule placed it")
        #expect(Self.placed.first { $0.id == "EXC" }?.placement == .excluded(messageID: "<out>"))
        #expect(Self.visible.map(\.id) == ["M1", "FREE", "M2", "ORPH"])
        #expect(Self.visible.map(\.placement) == [.message, .free, .message, .orphaned(messageID: "<gone>")])
    }

    @Test func hidingExcludedKeepsAnAnchoredEntryWhoseMessageIsPresentEvenIfListed() {
        let rows = PraticaTimelineModel.ordered([
            Self.message("M", day: 0, messageID: "<m>"),
            Self.entry("E", day: 1, ordinal: 0, anchor: "<m>"),
        ], excluded: ["<m>"])
        #expect(PraticaTimelineModel.hidingExcluded(rows).map(\.id) == ["M", "E"])
    }

    @Test func hidingNothingIsTheIdentity() {
        let rows = PraticaTimelineModel.ordered([
            Self.message("M", day: 0, messageID: "<m>"), Self.entry("F", day: 1, ordinal: 0),
        ])
        #expect(PraticaTimelineModel.hidingExcluded(rows) == rows)
        #expect(PraticaTimelineModel.hidingExcluded([]).isEmpty)
    }

    // MARK: - R-05: no section, neighbour, filter hit or delete target

    @Test func aDayHoldingOnlyAHiddenRowMakesNoSection() {
        let withHidden = PraticaTimelineModel.daySections(of: Self.placed, calendar: Self.utc)
        let withoutHidden = PraticaTimelineModel.daySections(of: Self.visible, calendar: Self.utc)
        #expect(withHidden.count == 5, "precondition: the excluded entry would have drawn a day header")
        #expect(withoutHidden.map { $0.entries.map(\.id) } == [["M1"], ["FREE"], ["M2"], ["ORPH"]])
        let hiddenDay = Self.utc.startOfDay(for: Self.at(day: 2, minute: 5))
        #expect(!withoutHidden.contains { $0.day == hiddenDay })
    }

    @Test func insertHereNeverNamesAHiddenRowAsANeighbour() {
        let next = PraticaTimelineModel.nextRows(in: Self.visible)
        #expect(next["M1"]?.id == "FREE", "the gap after M1 is bounded by FREE, not by the hidden row")
        #expect(!next.keys.contains("EXC"))
        #expect(!next.values.contains { $0.id == "EXC" })
    }

    @Test func aTextFilterMatchingAHiddenEntrysBodyOrSubjectDoesNotBringItBack() {
        for text in ["segreto", "Nascosta", "nota"] {
            let shown = PraticaTimelineModel.filtered(Self.visible, by: PraticaTimelineFilter(text: text))
            #expect(!shown.contains { $0.id == "EXC" }, "text \(text)")
        }
        // The same filter over the unhidden rows would have matched, so the test can fail.
        let unhidden = PraticaTimelineModel.filtered(Self.placed, by: PraticaTimelineFilter(text: "segreto"))
        #expect(unhidden.contains { $0.id == "EXC" })
    }

    @Test func backspaceNeverTargetsAHiddenEntryOrWhateverIsNotAVisibleMessage() {
        #expect(PraticaTimelineModel.deleteKeyTarget(selectedID: "EXC", in: Self.visible) == nil)
        #expect(PraticaTimelineModel.deleteKeyTarget(selectedID: "FREE", in: Self.visible) == nil)
        #expect(PraticaTimelineModel.deleteKeyTarget(selectedID: "M1", in: Self.visible)?.id == "M1")
    }
}

// MARK: - Over a vault: the exclusion is read from the bytes the entries are parsed from

@MainActor
@Suite(.serialized) struct PraticaExcludedEntriesReloadTests {
    private static let praticaPath = "Rossi/Offerta"
    private static let notePath = "Rossi/Offerta/pratica.md"
    private static let excludedID = "<escluso@rossi-spa.it>"
    private static let presentID = "<presente@rossi-spa.it>"
    private static let goneID = "<sparito@rossi-spa.it>"

    private static func note(excluded: [String]) -> String {
        let list = excluded.isEmpty
            ? "" : "pergamenum-dossier-excluded:\n" + excluded.map { "  - \"\($0)\"\n" }.joined()
        return """
        ---
        date: 2026-06-10
        pergamenum-dossier: 1
        \(list)---

        Descrizione.

        ## 2026-06-10 10:00 Nota · Escluso
        <!-- pergamenum-message: \(excludedID) -->
        Testo nascosto.

        ## 2026-06-10 11:00 Nota · Presente
        <!-- pergamenum-message: \(presentID) -->
        Testo visibile.

        ## 2026-06-10 12:00 Nota · Sparito
        <!-- pergamenum-message: \(goneID) -->
        Voce orfana.

        ## 2026-06-10 13:00 Telefonata · Libera
        Voce libera.

        """
    }

    /// A vault with the pratica, the present message's file, and a controller showing it.
    private func open(
        _ vault: borrowing TemporaryVault, excluded: [String]
    ) async throws -> (VaultController, PraticheController) {
        try vault.write(Self.note(excluded: excluded), to: Self.notePath)
        try vault.write(
            CarryHarness.message(Self.presentID, subject: "Offerta", day: 9),
            to: "\(Self.praticaPath)/email/20260609_0800_offerta.md"
        )
        let controller = VaultController(recents: .volatile(), openTabs: .volatile())
        await controller.open(vault.root)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        pratiche.selection = Self.praticaPath
        pratiche.reloadTimeline(from: controller)
        return (controller, pratiche)
    }

    @Test func readTimelineFillsTheExcludedSetFromTheDossierAndKeepsEveryEntry() throws {
        let vault = try TemporaryVault()
        try vault.write(Self.note(excluded: [Self.excludedID, Self.presentID]), to: Self.notePath)

        let read = PraticheController.readTimeline(praticaPath: Self.praticaPath, vaultRoot: vault.root)

        #expect(read.excluded == [Self.excludedID, Self.presentID])
        #expect(read.entries.count == 4, "the read keeps the text of every entry; hiding is the reload's")
    }

    @Test func readTimelineOfAPraticaWithNoExclusionOrNoFileHasAnEmptySet() throws {
        let vault = try TemporaryVault()
        try vault.write(Self.note(excluded: []), to: Self.notePath)
        #expect(PraticheController.readTimeline(praticaPath: Self.praticaPath, vaultRoot: vault.root).excluded.isEmpty)
        #expect(PraticheController.readTimeline(praticaPath: "Altra/Pratica", vaultRoot: vault.root).excluded.isEmpty)
    }

    // R-05
    @Test func anEntryAnchoredToAnExcludedMessageIsInNeitherTimelineNorFilteredTimeline() async throws {
        let vault = try TemporaryVault()
        let (controller, pratiche) = try await open(vault, excluded: [Self.excludedID])

        #expect(!pratiche.timeline.contains { $0.anchor == Self.excludedID })
        #expect(!pratiche.filteredTimeline.contains { $0.anchor == Self.excludedID })
        pratiche.filter = PraticaTimelineFilter(text: "nascosto")
        #expect(!pratiche.filteredTimeline.contains { $0.anchor == Self.excludedID }, "body text")
        pratiche.filter = PraticaTimelineFilter(text: "Escluso")
        #expect(!pratiche.filteredTimeline.contains { $0.anchor == Self.excludedID }, "subject")
        pratiche.filter = PraticaTimelineFilter()

        // Not counted: the counts bar reads `timeline`, which holds the three visible manual entries.
        #expect(pratiche.timeline.filter { $0.kind != .message }.count == 3)
        controller.close()
    }

    // R-06 (the read half): hiding writes nothing
    @Test func hidingAnEntryWritesNothingToPraticaMd() async throws {
        let vault = try TemporaryVault()
        let before = Self.note(excluded: [Self.excludedID])
        let (controller, pratiche) = try await open(vault, excluded: [Self.excludedID])
        pratiche.reloadTimeline(from: controller)

        let after = try String(contentsOf: vault.root.appending(path: Self.notePath), encoding: .utf8)
        #expect(after == before)
        controller.close()
    }

    // R-02
    @Test func aListedIDWhoseMessageIsPresentIsAnchoredAndVisible() async throws {
        let vault = try TemporaryVault()
        let (controller, pratiche) = try await open(vault, excluded: [Self.excludedID, Self.presentID])

        let entry = try #require(pratiche.timeline.first { $0.anchor == Self.presentID })
        #expect(entry.placement == .anchored(messageID: Self.presentID))
        #expect(pratiche.filteredTimeline.contains { $0.id == entry.id })
        controller.close()
    }

    // R-03
    @Test func aDanglingUnlistedAnchorIsOrphanedWithTodaysCaption() async throws {
        let vault = try TemporaryVault()
        let (controller, pratiche) = try await open(vault, excluded: [Self.excludedID])

        let entry = try #require(pratiche.timeline.first { $0.anchor == Self.goneID })
        #expect(entry.placement == .orphaned(messageID: Self.goneID))
        #expect(PraticaTimelineModel.orphanCaption(for: entry) == PraticaTimelineModel.orphanCaptionText)
        controller.close()
    }

    @Test func removingTheIDFromTheListByHandTurnsTheEntryOrphanedAndVisible() async throws {
        let vault = try TemporaryVault()
        let (controller, pratiche) = try await open(vault, excluded: [Self.excludedID])
        #expect(!pratiche.timeline.contains { $0.anchor == Self.excludedID }, "precondition: hidden")

        try vault.write(Self.note(excluded: []), to: Self.notePath)
        pratiche.reloadTimeline(from: controller)

        let entry = try #require(pratiche.timeline.first { $0.anchor == Self.excludedID })
        #expect(entry.placement == .orphaned(messageID: Self.excludedID))
        #expect(pratiche.filteredTimeline.contains { $0.id == entry.id })
        controller.close()
    }

    @Test func listingTheIDAgainHidesTheEntryAgainWithNoOtherChange() async throws {
        let vault = try TemporaryVault()
        let (controller, pratiche) = try await open(vault, excluded: [])
        let before = pratiche.timeline.map(\.id)
        #expect(before.count == 5, "precondition: one message and four entries")

        try vault.write(Self.note(excluded: [Self.excludedID]), to: Self.notePath)
        pratiche.reloadTimeline(from: controller)

        #expect(pratiche.timeline.map(\.id) == before.filter { !$0.contains("entry-202606101000") })
        controller.close()
    }
}
