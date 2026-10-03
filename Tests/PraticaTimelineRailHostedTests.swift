import AppKit
import SwiftUI
import Testing
@testable import Pergamenum

// ADR-0079 §D5 (PG-369), gate M1 of plan docs/plans/pg-369-pratiche-timeline-rail-and-excluded.md,
// Task 6 - R-08, R-09: the rail is drawn one piece per `List` row, each reaching
// `PraticaTimelineModel.railRowInset` past its row's measured bounds, and it reads as one line only
// if a cell may draw into the `List`'s own space between two cards. This file is the measurement
// that picked that path and its pinned witness: a message row and two anchored rows with the real
// `PraticaEntryRow`, `PraticaLaneRowLayout` and the production chrome (`praticaTimelineRowChrome`),
// at 428, 800 and 1600 pt, with and without enough filler rows for a scroller, received and sent,
// in a window never shown (`HostedViewSupport.swift`).
//
// Measured on macOS 27 (ADR-0079 implementation notes): row views abut, each `NSTableRowView` clips
// to its bounds, and a row's content sits 4 pt in from its row view's top and bottom, so the 8 pt
// between two cards belongs half to each row; the snapshot renders the table's content. The
// snapshot is colour-managed (the light rail token #6189B4 reads back as about #7C9ABD), so a rail
// pixel is compared with a swatch of the token drawn in a row of the same `List`, not with the
// token's own components.

@MainActor
@Suite(.serialized)
struct PraticaTimelineRailHostedTests {
    private static let gutter = Theme.emergency.spacing(.m)
    private static let step = Theme.emergency.spacing(.l)
    private static let readable = Theme.emergency.spacing(.readable)

    private static func rows(host: MessageDocument.Direction) -> [PraticaTimelineEntry] {
        let messageID = "<\(host)@example.com>"
        var message = PraticaTimelineEntry(
            id: "email/\(host).md", kind: .message, date: Date(timeIntervalSince1970: 1_788_000_000),
            direction: host, senderDisplayName: "Mario Rossi", subject: "Offerta",
            bodyPreview: "", hasAttachments: false, messageID: messageID, isInMail: true
        )
        message.placement = .message
        let entries = (1...2).map { index in
            var entry = PraticaTimelineEntry(
                id: "pratica.md#\(host)-\(index)", kind: index == 1 ? .note : .call,
                date: Date(timeIntervalSince1970: 1_788_000_000 + Double(index) * 600),
                direction: nil, senderDisplayName: "", subject: "Voce \(index) · Rossi",
                bodyPreview: "Testo della voce", hasAttachments: false, messageID: nil, isInMail: true
            )
            entry.anchor = messageID
            entry.placement = .anchored(messageID: messageID)
            entry.placementDate = message.date
            entry.hostDirection = host
            return entry
        }
        return [message] + entries
    }

    /// One timeline row in `PraticaTimelineView.row`'s shape, the message card a plain block.
    private struct RailRow: View {
        let entry: PraticaTimelineEntry
        let rail: PraticaRailPiece
        let box: FrameBox
        /// The entry whose card is outlined, and whether the rows are expanded (a taller stand-in
        /// message card, the real entry row expanded).
        var selectedID: String?
        var expanded = false

        var body: some View {
            let lane = PraticaTimelineModel.hostLane(for: entry)
            let indent = PraticaTimelineModel.anchoredIndent(
                lane: lane, isAnchored: entry.kind != .message, step: PraticaTimelineRailHostedTests.step
            )
            PraticaLaneRowLayout(
                lane: lane, reservesSlot: true, gutter: PraticaTimelineRailHostedTests.gutter,
                columnMaximum: PraticaTimelineRailHostedTests.readable,
                rail: rail, railStep: PraticaTimelineRailHostedTests.step
            ) {
                if entry.kind == .message {
                    Theme.emergency.color(lane == .sent ? .surfaceSent : .surfaceReceived)
                        .frame(height: expanded ? 160 : 60)
                        .report("\(entry.id)-card", into: box)
                } else {
                    PraticaEntryRow(entry: entry, detail: nil, isExpanded: expanded, onToggle: { _ in })
                        .praticaCardSelection(isSelected: selectedID == entry.id)
                        .report("\(entry.id)-card", into: box)
                        .padding(.leading, indent.leading)
                        .padding(.trailing, indent.trailing)
                }
            } slot: {
                Color.clear.frame(height: 0)
            }
            .report("\(entry.id)-row", into: box)
            .praticaTimelineRowChrome()
            .tag(entry.id)
        }
    }

    private struct Measured {
        let rows: [PraticaTimelineEntry]
        let box: FrameBox
        let rowViews: [CGRect]
        let clips: Bool
        let rep: NSBitmapImageRep
        let scale: CGFloat
        /// The rail token as this bitmap renders it, read off the swatch row.
        let swatch: NSColor?
        /// Window (`.global`) y minus bitmap y: the title bar above the hosting view.
        let offset: CGFloat

        func frame(_ id: String, _ part: String) throws -> CGRect {
            try #require(box.frames["\(id)-\(part)"])
        }

        func color(x: CGFloat, globalY: CGFloat) -> NSColor? {
            rep.colorAt(x: Int((x * scale).rounded(.down)), y: Int(((globalY - offset) * scale).rounded(.down)))?
                .usingColorSpace(.sRGB)
        }
    }

    private func measure(
        width: Double, filler: Int, host: MessageDocument.Direction, selectedID: String? = nil, expanded: Bool = false
    ) async throws -> Measured {
        let rows = Self.rows(host: host)
        let pieces = PraticaTimelineModel.railPieces(in: rows)
        let box = FrameBox()
        let size = CGSize(width: width, height: 600)
        let hosted = HostedView(
            List(selection: .constant(nil as String?)) {
                Section {
                    Theme.emergency.color(host == .sent ? .railSent : .railReceived).frame(width: 24, height: 24)
                        .report("swatch", into: box).praticaTimelineRowChrome().tag("swatch")
                    ForEach(rows) { entry in
                        RailRow(
                            entry: entry, rail: pieces[entry.id] ?? .none, box: box, selectedID: selectedID,
                            expanded: expanded
                        )
                    }
                    ForEach(0..<filler, id: \.self) { index in
                        Text("riga \(index)").praticaTimelineRowChrome().tag("filler-\(index)")
                    }
                } header: { Text("giorno") }
            }
            .scrollContentBackground(.hidden)
            .defaultScrollAnchor(.top)
            .frame(width: size.width, height: size.height)
            .environment(\.theme, .emergency),
            size: size
        )
        defer { hosted.tearDown() }
        await hosted.settle()
        #expect(hosted.neverShown && hosted.refusals.isEmpty)

        func views(in view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views(in:)) }
        let rowViews = views(in: hosted.hosting).compactMap { $0 as? NSTableRowView }
        let frames = rowViews.map { $0.convert($0.bounds, to: hosted.hosting) }.sorted { $0.minY < $1.minY }
        let bounds = hosted.hosting.bounds
        let rep = try #require(hosted.hosting.bitmapImageRepForCachingDisplay(in: bounds))
        hosted.hosting.cacheDisplay(in: bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / bounds.width
        let offset = hosted.window.frame.height - bounds.height
        let swatch = try #require(box.frames["swatch"])
        return Measured(
            rows: rows, box: box, rowViews: frames, clips: rowViews.allSatisfy(\.clipsToBounds), rep: rep,
            scale: scale,
            swatch: rep.colorAt(x: Int(swatch.midX * scale), y: Int((swatch.midY - offset) * scale))?
                .usingColorSpace(.sRGB),
            offset: offset
        )
    }

    private static func matches(_ color: NSColor?, _ expected: NSColor?) -> Bool {
        guard let color, let expected else { return false }
        return abs(color.redComponent - expected.redComponent) < 0.02
            && abs(color.greenComponent - expected.greenComponent) < 0.02
            && abs(color.blueComponent - expected.blueComponent) < 0.02
    }

    /// One hosted configuration: the timeline's width, filler rows (60 make the `List` scroll, so a
    /// legacy scroller shows when the machine uses one) and the message's lane.
    struct Layout: Sendable, CustomTestStringConvertible {
        let width: Double
        let filler: Int
        let host: MessageDocument.Direction
        var testDescription: String { "\(Int(width)) pt, \(filler) filler rows, \(host)" }
    }

    nonisolated static let cases: [Layout] = [428.0, 800.0, 1600.0].flatMap { width in
        [0, 60].flatMap { filler in
            [MessageDocument.Direction.received, .sent].map { Layout(width: width, filler: filler, host: $0) }
        }
    }

    @Test(arguments: cases)
    func rowViewsAbutClipAndSitFourPointsOutsideTheirContent(layout: Layout) async throws {
        let measured = try await measure(width: layout.width, filler: layout.filler, host: layout.host)
        #expect(measured.clips, "a row view no longer clips: a piece may draw into its neighbour")
        // The row view holding each of the three rows' content.
        var three: [CGRect] = []
        for entry in measured.rows {
            let row = try measured.frame(entry.id, "row").offsetBy(dx: 0, dy: -measured.offset)
            three.append(try #require(
                measured.rowViews.first { $0.contains(CGPoint(x: $0.midX, y: row.midY)) },
                "no row view holds \(entry.id) at \(row) among \(measured.rowViews)"
            ))
        }
        for (above, below) in zip(three, three.dropFirst()) {
            #expect(abs(above.maxY - below.minY) <= 0.5, "row views do not abut: \(above) \(below)")
        }
        for (rowView, entry) in zip(three, measured.rows) {
            let row = try measured.frame(entry.id, "row")
            let rowInBitmap = row.offsetBy(dx: 0, dy: -measured.offset)
            #expect(abs(rowInBitmap.minY - rowView.minY - PraticaTimelineModel.railRowInset) <= 0.5,
                    "\(entry.id): content \(rowInBitmap) in row view \(rowView)")
            #expect(abs(rowView.maxY - rowInBitmap.maxY - PraticaTimelineModel.railRowInset) <= 0.5,
                    "\(entry.id): content \(rowInBitmap) in row view \(rowView)")
            // R-09: the rail is outside the measured height - every row is exactly its card's.
            let card = try measured.frame(entry.id, "card")
            #expect(abs(row.height - card.height) <= 0.5, "\(entry.id): row \(row), card \(card)")
        }
    }

    @Test(arguments: cases)
    func theRailIsOneUnbrokenLineFromTheMessageToTheLastEntryWithAHookAtEachHeading(layout: Layout) async throws {
        try await assertUnbrokenRail(layout, expanded: false)
    }

    /// R-08 "drawn the same whether the message and each entry are collapsed or expanded".
    @Test(arguments: cases)
    func theRailIsUnbrokenWithTheMessageAndTheEntriesExpandedToo(layout: Layout) async throws {
        try await assertUnbrokenRail(layout, expanded: true)
    }

    /// R-08, R-09 at `layout`, collapsed or expanded: one x, no break from the message card to the
    /// last hook, nothing past the corner, inside the indent, and every row still its card's height.
    private func assertUnbrokenRail(_ layout: Layout, expanded: Bool) async throws {
        let host = layout.host
        let measured = try await measure(width: layout.width, filler: layout.filler, host: host, expanded: expanded)
        for entry in measured.rows {
            let row = try measured.frame(entry.id, "row"), card = try measured.frame(entry.id, "card")
            #expect(abs(row.height - card.height) <= 0.5, "\(entry.id) expanded \(expanded): row \(row), card \(card)")
        }
        let token = try #require(measured.swatch)
        // The swatch is the token, not the background: a blank snapshot would match anything.
        #expect(!Self.matches(token, measured.color(x: 2, globalY: measured.offset + 2)))
        let message = measured.rows[0]
        let row = try measured.frame(message.id, "row")
        let lane = PraticaTimelineModel.hostLane(for: message)
        let columns = PraticaTimelineModel.rowColumns(
            container: PraticaTimelineModel.columnWidth(row: row.width, readable: Self.readable),
            lane: lane, reservesSlot: true, gutter: Self.gutter
        )
        let geometry = PraticaTimelineModel.railGeometry(columns: columns, lane: lane, step: Self.step)
        let railX = row.minX + geometry.x
        let messageCard = try measured.frame(message.id, "card")
        let lastCard = try measured.frame(measured.rows[2].id, "card")

        // R-08: every sampled point at the rail's x, from just under the message card down to the
        // last entry's heading, is the rail - the gaps between rows included. Sampled every point.
        let firstHook = try hookY(in: measured.frame(measured.rows[1].id, "card"), x: row.minX + geometry.hookEnd,
                                  railX: railX, measured: measured, token: token)
        let lastHook = try hookY(in: lastCard, x: row.minX + geometry.hookEnd, railX: railX,
                                 measured: measured, token: token)
        let breaks = stride(from: messageCard.maxY + 0.5, through: lastHook, by: 1).filter {
            !Self.matches(measured.color(x: railX, globalY: $0), token)
        }
        #expect(breaks.isEmpty, "rail broken at y \(breaks) (message card \(messageCard), last hook \(lastHook))")
        #expect(firstHook < lastHook)
        // Nothing past the corner: below the last entry's hook the rail's x shows no rail.
        #expect(!Self.matches(measured.color(x: railX, globalY: lastCard.maxY + 2), token))
        // R-09: the line lies inside the indent, never over the entry card.
        let entryCardEdge = row.minX + geometry.hookEnd
        #expect(host == .sent ? railX > entryCardEdge : railX < entryCardEdge)
    }

    /// The y of the hook inside `card`, sampled halfway between the rail and the card's near edge;
    /// it must lie on the heading, the card's first line (ADR-0079 §D5).
    private func hookY(
        in card: CGRect, x hookEnd: CGFloat, railX: CGFloat, measured: Measured, token: NSColor
    ) throws -> CGFloat {
        let x = (railX + hookEnd) / 2
        let hits = stride(from: card.minY, through: card.maxY, by: 0.5).filter {
            Self.matches(measured.color(x: x, globalY: $0), token)
        }
        let first = try #require(hits.first, "no hook beside \(card)")
        let padding = Theme.emergency.spacing(.s)
        #expect(first > card.minY + padding && first < card.minY + padding + 22,
                "hook at \(first), card top \(card.minY): not on the heading line")
        return first
    }
}

// MARK: - A selected entry

extension PraticaTimelineRailHostedTests {
    /// R-13 / the SPEC's "A selected entry": the outline is drawn on the card (`praticaCardSelection`),
    /// and the hook, which ends on the card's near edge, does not cover it - the pixel at the card's
    /// edge at the hook's own height is still the accent, for the middle entry (hook, line goes on)
    /// and the last (hook, corner).
    @Test(arguments: [428.0, 800.0, 1600.0], [MessageDocument.Direction.received, .sent])
    func aSelectedEntrysOutlineIsStillTheAccentWhereTheHookMeetsTheCard(
        width: Double, host: MessageDocument.Direction
    ) async throws {
        for index in [1, 2] {
            let selectedID = Self.rows(host: host)[index].id
            let measured = try await measure(width: width, filler: 0, host: host, selectedID: selectedID)
            let token = try #require(measured.swatch)
            let card = try measured.frame(selectedID, "card")
            let row = try measured.frame(measured.rows[0].id, "row")
            let lane = PraticaTimelineModel.hostLane(for: measured.rows[0])
            let columns = PraticaTimelineModel.rowColumns(
                container: PraticaTimelineModel.columnWidth(row: row.width, readable: Self.readable),
                lane: lane, reservesSlot: true, gutter: Self.gutter
            )
            let geometry = PraticaTimelineModel.railGeometry(columns: columns, lane: lane, step: Self.step)
            let railX = row.minX + geometry.x
            let hookHeight = try hookY(
                in: card, x: row.minX + geometry.hookEnd, railX: railX, measured: measured, token: token
            )

            // One point inside the card's near edge, in the 2 pt outline band.
            let edgeX = host == .sent ? card.maxX - 1 : card.minX + 1
            let edge = try #require(measured.color(x: edgeX, globalY: hookHeight))
            let accent = try #require(NSColor(Theme.emergency.color(.accentPrimary)).usingColorSpace(.sRGB))
            let distance = max(
                abs(edge.redComponent - accent.redComponent), abs(edge.greenComponent - accent.greenComponent),
                abs(edge.blueComponent - accent.blueComponent)
            )
            #expect(distance < 0.2, "\(host) \(width) pt, entry \(index): edge \(edge), accent \(accent)")
            #expect(!Self.matches(edge, token), "the hook has painted over the outline")
            // The outline sits on the card, so the card keeps exactly its height.
            let rowFrame = try measured.frame(selectedID, "row")
            #expect(abs(rowFrame.height - card.height) <= 0.5)
        }
    }
}
