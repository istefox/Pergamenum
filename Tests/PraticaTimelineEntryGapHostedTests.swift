import AppKit
import SwiftUI
import Testing
@testable import Pergamenum

// Hand check round 5: «Telefonata · Rossi» 20:22, anchored to a sent message, looked like it had
// a card's height of empty space under it, and «Telefonata · Mario Rossi» 09:16, anchored to a
// received one, did not. In the hand-check vault the first is the last row of its day (9 June) and
// the second is followed by a message of the same day: the space is the `List`'s own section break
// before the next day's header, the same under any section's last row. Measured here with the real
// `PraticaEntryRow` in `PraticaTimelineView.row`'s shape, in a window never shown
// (`HostedViewSupport.swift`, which also holds `FrameBox` and `report(_:into:)`).

@MainActor
@Suite(.serialized)
struct PraticaTimelineEntryGapHostedTests {
    private static let gutter = Theme.emergency.spacing(.m)
    private static let indent = Theme.emergency.spacing(.l)
    private static let readable = Theme.emergency.spacing(.readable)

    /// A bodiless call anchored to a `host` message, as the timeline reads one the app wrote.
    private static func anchoredCall(host: MessageDocument.Direction) -> PraticaTimelineEntry {
        var entry = PraticaTimelineEntry(
            id: "pratica.md#call-\(host)", kind: .call, date: Date(timeIntervalSince1970: 1_788_000_000),
            direction: nil, senderDisplayName: "", subject: "Telefonata · Rossi",
            bodyPreview: "", hasAttachments: false, messageID: nil, isInMail: true
        )
        entry.anchor = "<\(host)@example.com>"
        entry.placement = .anchored(messageID: "<\(host)@example.com>")
        entry.hostDirection = host
        return entry
    }

    /// The real entry row in `PraticaTimelineView.row`'s shape: its message's lane, the slot's place
    /// kept and empty, the indent on the lane's own edge.
    private struct AnchoredCallRow: View {
        let host: MessageDocument.Direction
        let box: FrameBox

        var body: some View {
            let entry = PraticaTimelineEntryGapHostedTests.anchoredCall(host: host)
            let lane = PraticaTimelineModel.hostLane(for: entry)
            let indent = PraticaTimelineModel.anchoredIndent(
                lane: lane, isAnchored: true, step: PraticaTimelineEntryGapHostedTests.indent
            )
            PraticaLaneRowLayout(
                lane: lane, reservesSlot: true, gutter: PraticaTimelineEntryGapHostedTests.gutter,
                columnMaximum: PraticaTimelineEntryGapHostedTests.readable
            ) {
                PraticaEntryRow(entry: entry, detail: nil, isExpanded: false, onToggle: { _ in })
                    .report("\(host)-call-card", into: box)
                    .padding(.leading, indent.leading)
                    .padding(.trailing, indent.trailing)
            } slot: {
                Color.clear.frame(height: 0)
            }
            .report("\(host)-call-row", into: box)
            .listRowSeparator(.hidden)
            .tag("\(host)-call")
        }
    }

    @Test(arguments: [428.0, 1200.0])
    func anAnchoredCallIsAsTallAsItsCardAndASectionBreakIsTheSameOnEitherSide(width: Double) async throws {
        let box = FrameBox()
        let size = CGSize(width: width, height: 700)
        let host = HostedView(
            List(selection: .constant(nil as String?)) {
                // The hand-check vault's shape: a day ending in a call under a sent message, a day
                // ending in a call under a received one, then a third day.
                Section { AnchoredCallRow(host: .sent, box: box) } header: { Text("9 giugno") }
                Section { AnchoredCallRow(host: .received, box: box) } header: { Text("10 giugno") }
                Section {
                    // Taller than the list's minimum row height, so its top is the row's top.
                    Color.gray.frame(height: 40).report("next", into: box).listRowSeparator(.hidden).tag("next")
                } header: { Text("11 giugno") }
            }
            .scrollContentBackground(.hidden)
            .frame(width: size.width, height: size.height)
            .environment(\.theme, .emergency),
            size: size
        )
        defer { host.tearDown() }
        await host.settle()
        #expect(host.neverShown && host.refusals.isEmpty)

        let sentRow = try #require(box.frames["sent-call-row"])
        let sentCard = try #require(box.frames["sent-call-card"])
        let receivedRow = try #require(box.frames["received-call-row"])
        let receivedCard = try #require(box.frames["received-call-card"])
        let next = try #require(box.frames["next"])
        // No row is taller than its card: the empty slot adds no height on either side.
        #expect(abs(sentRow.height - sentCard.height) <= 0.5, "sent: row \(sentRow), card \(sentCard)")
        #expect(
            abs(receivedRow.height - receivedCard.height) <= 0.5, "received: row \(receivedRow), card \(receivedCard)"
        )
        #expect(abs(sentCard.height - receivedCard.height) <= 0.5)
        // The space under each section's last row, down to the next section's first row, is the
        // section break - and the same under a sent host's call as under a received host's.
        let underSent = receivedRow.minY - sentRow.maxY
        let underReceived = next.minY - receivedRow.maxY
        #expect(underSent > 0 && underReceived > 0)
        #expect(abs(underSent - underReceived) <= 0.5, "under sent \(underSent), under received \(underReceived)")
    }
}
