import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 6 -
// R-23, R-24, R-25, R-26, R-32, R-33, R-39.

@Suite struct PraticaTimelineModelTests {
    // MARK: - R-23: ordering, with the received-date fallback

    @Test func sortDateFallsBackToReceivedWhenTheHeaderDateDidNotParse() {
        let received = Date(timeIntervalSince1970: 1_700_000_000)
        let frontmatter = Self.frontmatter(date: .distantPast, received: received)

        // Real behaviour (R-23): "fallback received date" applies exactly when the
        // primary `pergamenum-mail-date` could not be parsed - `MessageDocument.
        // parse` defaults that case to `.distantPast`.
        #expect(PraticaTimelineModel.sortDate(of: frontmatter) == received)
    }

    @Test func sortDateIsThePrimaryDateWhenItParsed() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let frontmatter = Self.frontmatter(date: date, received: date.addingTimeInterval(30))
        #expect(PraticaTimelineModel.sortDate(of: frontmatter) == date)
    }

    @Test func entriesAreOrderedAscendingByDateInterleavingMessagesAndManualEntries() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let message = Self.entry(id: "m1", kind: .message, date: t0.addingTimeInterval(120))
        let call = Self.entry(id: "c1", kind: .call, date: t0)
        let note = Self.entry(id: "n1", kind: .note, date: t0.addingTimeInterval(60))

        let ordered = PraticaTimelineModel.ordered([message, note, call])
        #expect(ordered.map(\.id) == ["c1", "n1", "m1"], "oldest first, mixing kinds by date alone")
    }

    // MARK: - R-24: expansion state

    @Test func aRowIsCollapsedByDefault() {
        let state = PraticaTimelineModel.ExpansionState()
        #expect(state.isExpanded("m1") == false)
    }

    @Test func theChevronTogglesExactlyOneRow() {
        var state = PraticaTimelineModel.ExpansionState()
        state.toggle("m1")
        #expect(state.isExpanded("m1") == true)
        #expect(state.isExpanded("m2") == false)

        state.toggle("m1")
        #expect(state.isExpanded("m1") == false)
    }

    @Test func optClickOnAnyChevronExpandsOrCollapsesEveryRow() {
        var state = PraticaTimelineModel.ExpansionState()
        let ids = ["m1", "m2", "m3"]

        // Real behaviour (R-24): with everything collapsed, Opt+click expands all.
        state.toggleAll(ids)
        #expect(ids.allSatisfy { state.isExpanded($0) }, "opt+click should have expanded every row")

        // A second Opt+click, with everything now expanded, collapses all.
        state.toggleAll(ids)
        #expect(ids.allSatisfy { !state.isExpanded($0) }, "opt+click should have collapsed every row again")
    }

    @Test func expansionStateIsAFreshValueNotSharedAcrossWindows() {
        // R-24: "expansion state is per window and not persisted" - a fresh
        // `ExpansionState()` must not remember another window's toggles. This is
        // trivially true of a value type, and stands as the pinned contract a future
        // `PraticheController` reaching for a shared/persisted store would break.
        var first = PraticaTimelineModel.ExpansionState()
        first.toggle("m1")

        let second = PraticaTimelineModel.ExpansionState()
        #expect(second.isExpanded("m1") == false)
    }

    // MARK: - R-25, R-39: lane, direction, and the redundant glyph/label/colour

    @Test func aReceivedMessageSitsInTheReceivedLane() {
        let entry = Self.entry(id: "m1", kind: .message, date: .now, direction: .received)
        #expect(PraticaTimelineModel.lane(for: entry) == .received)
    }

    @Test func aSentMessageSitsInTheSentLane() {
        let entry = Self.entry(id: "m1", kind: .message, date: .now, direction: .sent)
        #expect(PraticaTimelineModel.lane(for: entry) == .sent)
    }

    @Test func aManualEntryIsAlwaysInTheEntryLaneRegardlessOfDirection() {
        let note = Self.entry(id: "n1", kind: .note, date: .now, direction: nil)
        #expect(PraticaTimelineModel.lane(for: note) == .entry)
    }

    @Test func directionIsCarriedByGlyphAndLabelAsWellAsColour() {
        // R-25: "always redundant" - glyph, label and colour must each distinguish
        // the three lanes, never leaving two lanes reading identically without colour.
        let glyphs = Set([PraticaLane.received, .sent, .entry].map(PraticaTimelineModel.laneGlyph))
        let labels = Set([PraticaLane.received, .sent, .entry].map(PraticaTimelineModel.laneLabel))
        #expect(glyphs.count == 3, "each lane needs its own glyph")
        #expect(labels.count == 3, "each lane needs its own label")
        #expect(glyphs.allSatisfy { !$0.isEmpty })
        #expect(labels.allSatisfy { !$0.isEmpty })
    }

    @Test func eachLaneReadsThroughItsOwnColorToken() {
        // R-39: the three tokens declared on `ColorToken`, one per lane, never two
        // lanes sharing a token (or colour would stop being redundant with anything).
        #expect(PraticaTimelineModel.laneColorToken(.received) == .surfaceReceived)
        #expect(PraticaTimelineModel.laneColorToken(.sent) == .surfaceSent)
        #expect(PraticaTimelineModel.laneColorToken(.entry) == .surfaceEntry)
    }

    // MARK: - R-26: subject link

    @Test func subjectLinkResolvesToAMessageURLWhenStillInMail() throws {
        let (url, caption) = PraticaTimelineModel.subjectLink(
            messageID: "<abc@rossi-spa.it>", isInMail: true
        )
        let expected = try #require(MailURL.forMessageID("<abc@rossi-spa.it>"))
        #expect(url == expected)
        #expect(caption == nil)
    }

    @Test func subjectLinkIsPlainTextWithACaptionWhenNoLongerInMail() {
        let (url, caption) = PraticaTimelineModel.subjectLink(
            messageID: "<abc@rossi-spa.it>", isInMail: false
        )
        #expect(url == nil)
        #expect(caption == "non più in Mail")
    }

    // MARK: - R-32: filters

    @Test func theTextFilterNarrowsBySubjectSenderAndBody() {
        let matching = Self.entry(id: "m1", kind: .message, date: .now, subject: "Offerta staffe")
        let other = Self.entry(id: "m2", kind: .message, date: .now, subject: "Fattura")

        let filtered = PraticaTimelineModel.filtered(
            [matching, other], by: PraticaTimelineFilter(text: "staffe")
        )
        #expect(filtered.map(\.id) == ["m1"])
    }

    @Test func theTextFilterCanHideAManualEntry() {
        // R-32: "manual entries are hidden only by the text filter" - so an active
        // text filter that a manual entry does not match must remove it.
        let call = Self.entry(id: "c1", kind: .call, date: .now, subject: "", senderDisplayName: "Rossi")
        let filtered = PraticaTimelineModel.filtered(
            [call], by: PraticaTimelineFilter(text: "staffe")
        )
        #expect(filtered.isEmpty, "a manual entry that does not match the text filter must be hidden")
    }

    @Test func theSenderMenuAndAttachmentsOnlyFiltersNeverHideAManualEntry() {
        let call = Self.entry(id: "c1", kind: .call, date: .now, hasAttachments: false)

        let bySender = PraticaTimelineModel.filtered(
            [call], by: PraticaTimelineFilter(sender: "m.rossi@rossi-spa.it")
        )
        #expect(bySender.contains { $0.id == "c1" }, "the sender filter must never hide a manual entry")

        let byAttachments = PraticaTimelineModel.filtered(
            [call], by: PraticaTimelineFilter(attachmentsOnly: true)
        )
        #expect(byAttachments.contains { $0.id == "c1" }, "«Solo con allegati» must never hide a manual entry")
    }

    @Test func attachmentsOnlyFilterNarrowsToMessagesCarryingAttachments() {
        let withAttachment = Self.entry(id: "m1", kind: .message, date: .now, hasAttachments: true)
        let without = Self.entry(id: "m2", kind: .message, date: .now, hasAttachments: false)

        let filtered = PraticaTimelineModel.filtered(
            [withAttachment, without], by: PraticaTimelineFilter(attachmentsOnly: true)
        )
        #expect(filtered.map(\.id) == ["m1"])
    }

    // MARK: - Fixtures

    private static func frontmatter(date: Date, received: Date?) -> MessageDocument.MailFrontmatter {
        MessageDocument.MailFrontmatter(
            schemaVersion: 1,
            messageID: "<abc@rossi-spa.it>",
            conversationID: 1,
            direction: .received,
            date: date,
            received: received,
            from: "Mario Rossi <m.rossi@rossi-spa.it>",
            to: [],
            cc: [],
            subject: "Richiesta offerta",
            attachments: [],
            body: .complete,
            original: nil
        )
    }

    private static func entry(
        id: String,
        kind: PraticaTimelineEntry.Kind,
        date: Date,
        direction: MessageDocument.Direction? = nil,
        subject: String = "",
        senderDisplayName: String = "",
        hasAttachments: Bool = false
    ) -> PraticaTimelineEntry {
        PraticaTimelineEntry(
            id: id,
            kind: kind,
            date: date,
            direction: kind == .message ? (direction ?? .received) : nil,
            senderDisplayName: senderDisplayName,
            subject: subject,
            bodyPreview: "",
            hasAttachments: hasAttachments,
            messageID: kind == .message ? "<\(id)@rossi-spa.it>" : nil,
            isInMail: true
        )
    }
}

// MARK: - R-33: sidebar grouping

@Suite struct PraticheSidebarGroupingTests {
    @Test func praticheAreGroupedByClientOrderedByMostRecentActivity() {
        let now = Date()
        let rossiOld = Self.item(id: "01/Rossi/Vecchia", client: "Rossi", lastActivity: now.addingTimeInterval(-100))
        let rossiNew = Self.item(id: "01/Rossi/Nuova", client: "Rossi", lastActivity: now)
        let bianchi = Self.item(id: "01/Bianchi/Quadro", client: "Bianchi", lastActivity: now.addingTimeInterval(-10))

        let (open, closed) = PraticheSidebarGrouping.grouped([rossiOld, rossiNew, bianchi])

        #expect(closed.isEmpty)
        #expect(open.map(\.client) == ["Rossi", "Bianchi"], "the client with the most recent activity leads")
        #expect(
            open.first { $0.client == "Rossi" }?.pratiche.map(\.id) == ["01/Rossi/Nuova", "01/Rossi/Vecchia"],
            "inside a client, the most recently active pratica leads"
        )
    }

    @Test func oldestFirstReversesTheClientGroupsAndThePraticheInsideThem() {
        let now = Date()
        let rossiOld = Self.item(id: "01/Rossi/Vecchia", client: "Rossi", lastActivity: now.addingTimeInterval(-100))
        let rossiNew = Self.item(id: "01/Rossi/Nuova", client: "Rossi", lastActivity: now)
        let bianchi = Self.item(id: "01/Bianchi/Quadro", client: "Bianchi", lastActivity: now.addingTimeInterval(-10))

        let (open, _) = PraticheSidebarGrouping.grouped([rossiOld, rossiNew, bianchi], order: .oldestFirst)

        // A group ranks by the pratica that leads it as ordered: Rossi now leads with its
        // oldest (-100), Bianchi with its only one (-10), so Rossi comes first.
        #expect(open.map(\.client) == ["Rossi", "Bianchi"])
        #expect(
            open.first { $0.client == "Rossi" }?.pratiche.map(\.id) == ["01/Rossi/Vecchia", "01/Rossi/Nuova"],
            "inside a client, the least recently active pratica leads"
        )
    }

    @Test func oldestFirstFlipsTheGroupRankingNotJustTheRows() {
        let now = Date()
        // One pratica per client, so the group order is the whole story.
        let recent = Self.item(id: "01/Recente/A", client: "Recente", lastActivity: now)
        let stale = Self.item(id: "01/Datato/A", client: "Datato", lastActivity: now.addingTimeInterval(-1_000))

        #expect(PraticheSidebarGrouping.grouped([recent, stale]).open.map(\.client) == ["Recente", "Datato"])
        #expect(
            PraticheSidebarGrouping.grouped([recent, stale], order: .oldestFirst).open.map(\.client)
                == ["Datato", "Recente"]
        )
    }

    @Test func oldestFirstReversesChiuseAndLeavesItsMembershipAlone() {
        let now = Date()
        let newer = Self.item(id: "01/Rossi/Nuova", client: "Rossi", status: "archived", lastActivity: now)
        let older = Self.item(id: "01/Bianchi/Vecchia", client: "Bianchi", status: "final", lastActivity: now.addingTimeInterval(-50))
        let active = Self.item(id: "01/Rossi/Attiva", client: "Rossi", status: "active", lastActivity: now)

        let newestFirst = PraticheSidebarGrouping.grouped([newer, older, active])
        let oldestFirst = PraticheSidebarGrouping.grouped([newer, older, active], order: .oldestFirst)

        #expect(newestFirst.closed.map(\.id) == ["01/Rossi/Nuova", "01/Bianchi/Vecchia"])
        #expect(oldestFirst.closed.map(\.id) == ["01/Bianchi/Vecchia", "01/Rossi/Nuova"])
        #expect(oldestFirst.open.flatMap(\.pratiche).map(\.id) == ["01/Rossi/Attiva"])
    }

    @Test func theTieBreakStaysAlphabeticalInBothDirections() {
        let instant = Date()
        // Same second, as a sync writing several files produces: the title decides, and
        // flipping the direction must not reshuffle them.
        let beta = Self.item(id: "01/Rossi/Beta", client: "Rossi", lastActivity: instant)
        let alfa = Self.item(id: "01/Rossi/Alfa", client: "Rossi", lastActivity: instant)

        for order in ChronologicalOrder.allCases {
            let (open, _) = PraticheSidebarGrouping.grouped([beta, alfa], order: order)
            #expect(open.first?.pratiche.map(\.id) == ["01/Rossi/Alfa", "01/Rossi/Beta"])
        }
    }

    @Test func closedPraticheCollapseUnderChiuseInsteadOfTheirClientGroup() {
        let now = Date()
        let active = Self.item(id: "01/Rossi/Attiva", client: "Rossi", status: "active", lastActivity: now)
        let archived = Self.item(id: "01/Rossi/Vecchia", client: "Rossi", status: "archived", lastActivity: now.addingTimeInterval(-1))
        let final = Self.item(id: "01/Bianchi/Conclusa", client: "Bianchi", status: "final", lastActivity: now.addingTimeInterval(-2))

        let (open, closed) = PraticheSidebarGrouping.grouped([active, archived, final])

        #expect(open.flatMap(\.pratiche).map(\.id) == ["01/Rossi/Attiva"])
        #expect(Set(closed.map(\.id)) == Set(["01/Rossi/Vecchia", "01/Bianchi/Conclusa"]))
    }

    @Test func theBadgeAndTheTrayDotAreCarriedThroughUnchanged() throws {
        let item = Self.item(id: "01/Rossi/Offerta", client: "Rossi", lastActivity: .now, messagesSinceLastOpen: 3, hasNonEmptyTray: true)
        let (open, _) = PraticheSidebarGrouping.grouped([item])

        let grouped = try #require(open.first?.pratiche.first)
        #expect(grouped.messagesSinceLastOpen == 3)
        #expect(grouped.hasNonEmptyTray == true)
    }

    private static func item(
        id: String,
        client: String,
        status: String = "active",
        lastActivity: Date,
        messagesSinceLastOpen: Int = 0,
        hasNonEmptyTray: Bool = false
    ) -> PraticaListItem {
        PraticaListItem(
            id: id,
            title: (id as NSString).lastPathComponent,
            client: client,
            status: status,
            lastActivity: lastActivity,
            messagesSinceLastOpen: messagesSinceLastOpen,
            hasNonEmptyTray: hasNonEmptyTray
        )
    }
}
