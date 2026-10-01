import AppKit
import SwiftUI
import Testing
@testable import Pergamenum

// PG-354, PG-355 and the hand check's rounds (the mirror, then the readable column): the
// production row layout (`PraticaLaneRowLayout`) in a real `List(selection:)` with a day section,
// the timeline's own shape, built in a window that is never shown (`HostedViewSupport.swift`).
// A small stand-in card - a subject line closed by the production rows' own
// `.frame(maxWidth: .infinity, alignment: .leading)` - takes the message row's place, so the
// subject is where the card and the slot land and how wide the card is. The real-row tests host
// the real `PraticaMessageRow`, footer included.
//
// Measured here on macOS 27 / Xcode 27 (2026-10-01), and the reason `PraticaTimelineModel+Layout
// .swift` subtracts no inset: a row is laid out in exactly the row's content width - the `List`
// less 16 pt on each side (360 → 328, 428 → 396, 800 → 768), and less a further 17 pt while a
// legacy scroller is showing (428 → 379) - and the row starts 16 pt in. The readable column then
// caps that at 720 pt (`spacing.readable`), from the row's leading edge. Frames are read back
// through `FrameBox`/`report(_:into:)` (`HostedViewSupport.swift`).

@MainActor
@Suite(.serialized)
struct PraticaTimelineLaneHostedTests {
    fileprivate static let gutter: CGFloat = 16
    /// `theme.spacing(.l)`, the step `PraticaTimelineView` indents an anchored entry by.
    fileprivate static let indent = Theme.emergency.spacing(.l)
    /// `theme.spacing(.readable)`, the column `PraticaTimelineView` caps every row at.
    fileprivate static let readable = Theme.emergency.spacing(.readable)

    /// A message lane's width in a row `row` wide: the arithmetic on the readable column.
    fileprivate static func laneWidth(row: CGFloat, lane: PraticaLane) -> CGFloat {
        PraticaTimelineModel.laneWidth(
            container: PraticaTimelineModel.columnWidth(row: row, readable: readable),
            lane: lane, reservesSlot: lane != .entry, gutter: gutter
        )
    }

    /// The rows by name: a message on each side, an entry anchored to each, a free entry.
    private static let messageRows = ["received", "sent"]
    private static let anchoredRows = ["anchored-received", "anchored-sent"]

    /// A row's card in miniature: one subject line, the production rows' own fill.
    private struct Card: View {
        let name: String
        let box: FrameBox

        var body: some View {
            Text("Offerta 118")
                .lineLimit(1)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red)
                .report("\(name)-card", into: box)
        }
    }

    private struct Timeline: View {
        let box: FrameBox
        /// Enough extra rows to make the `List` scroll, so a legacy scroller (when the machine
        /// is set to show one) takes its width from the rows too.
        let fillerRows: Int

        var body: some View {
            List(selection: .constant(nil as String?)) {
                Section {
                    row("received", lane: .received, reservesSlot: true)
                    row("sent", lane: .sent, reservesSlot: true)
                    // An entry anchored to each: its message's lane, its slot's place kept.
                    row("anchored-received", lane: .received, reservesSlot: true)
                    row("anchored-sent", lane: .sent, reservesSlot: true)
                    row("entry", lane: .entry, reservesSlot: false)
                    ForEach(0..<fillerRows, id: \.self) { index in
                        Color.gray.frame(height: 20).tag("filler-\(index)")
                    }
                } header: {
                    Text("Oggi")
                }
            }
            .scrollContentBackground(.hidden)
            .report("list", into: box)
        }

        private func row(_ name: String, lane: PraticaLane, reservesSlot: Bool) -> some View {
            PraticaLaneRowLayout(
                lane: lane, reservesSlot: reservesSlot, gutter: PraticaTimelineLaneHostedTests.gutter,
                columnMaximum: PraticaTimelineLaneHostedTests.readable
            ) {
                // The production indent: from the lane's own edge, for an anchored entry only.
                let indent = PraticaTimelineModel.anchoredIndent(
                    lane: lane, isAnchored: name.hasPrefix("anchored-"), step: PraticaTimelineLaneHostedTests.indent
                )
                Card(name: name, box: box)
                    .padding(.leading, indent.leading)
                    .padding(.trailing, indent.trailing)
            } slot: {
                Color.blue.frame(height: 40).report("\(name)-slot", into: box)
            }
            .report("\(name)-row", into: box)
            .listRowSeparator(.hidden)
            .tag(name)
        }
    }

    /// 360/428 pt timelines keep PG-355's behaviour (all column, a lane of at least 240 pt at
    /// 428, nothing overlapping at 360); 800/1200/1600 pt timelines lay out in the 720 pt
    /// readable column, leading, with the free space to its right.
    @Test(arguments: [360.0, 428.0, 800.0, 1200.0, 1600.0], [0, 60])
    func everyRowLaysOutInTheReadableColumnWithUniformWidths(width: Double, fillerRows: Int) async throws {
        let box = FrameBox()
        let size = CGSize(width: width, height: 600)
        let host = HostedView(
            Timeline(box: box, fillerRows: fillerRows)
                .frame(width: size.width, height: size.height)
                .environment(\.theme, .emergency),
            size: size
        )
        defer { host.tearDown() }
        await host.settle()

        let list = try #require(box.frames["list"])
        for name in Self.messageRows + Self.anchoredRows {
            try checkSlotRow(name, width: width, in: box, list: list)
        }

        // A free entry takes the whole column, from the leading edge, and draws no slot.
        let entryRow = try #require(box.frames["entry-row"])
        let entry = try #require(box.frames["entry-card"])
        let column = PraticaTimelineModel.columnWidth(row: entryRow.width, readable: Self.readable)
        #expect(abs(entry.minX - entryRow.minX) <= 0.5)
        #expect(abs(entry.width - column) <= 0.5, "free entry \(entry.width), column \(column)")
        #expect(box.frames["entry-slot"] == nil)

        #expect(host.neverShown)
        #expect(host.refusals.isEmpty)
    }

    /// One row that reserves a note slot: everything inside the readable column, a message card
    /// exactly its lane, flush with its side of the column, the slot next to the card's edge; an
    /// anchored entry's box its message's lane less the indent, on the lane's own edge.
    private func checkSlotRow(_ name: String, width: Double, in box: FrameBox, list: CGRect) throws {
        let isSent = name.hasSuffix("sent")
        let row = try #require(box.frames["\(name)-row"])
        let card = try #require(box.frames["\(name)-card"])
        let slot = try #require(box.frames["\(name)-slot"])
        let column = PraticaTimelineModel.columnWidth(row: row.width, readable: Self.readable)
        let columnMaxX = row.minX + column
        let lane = Self.laneWidth(row: row.width, lane: isSent ? .sent : .received)
        let context = "\(name) at \(width) pt: row \(row), card \(card), slot \(slot), column \(column)"
        // Nothing past the column, nothing before the row.
        #expect(row.minX >= list.minX - 0.5 && row.maxX <= list.maxX + 0.5, "\(context)")
        #expect(card.minX >= row.minX - 0.5 && card.maxX <= columnMaxX + 0.5, "card past the column - \(context)")
        #expect(slot.minX >= row.minX - 0.5 && slot.maxX <= columnMaxX + 0.5, "slot past the column - \(context)")
        let expectedSlot = PraticaTimelineModel.noteSlotWidth(container: column, gutter: Self.gutter)
        #expect(abs(slot.width - expectedSlot) <= 0.5, "slot \(slot.width), expected \(expectedSlot) - \(context)")
        // The card's own span: the lane, or the lane less the indent for an anchored entry.
        let inset = name.hasPrefix("anchored-") ? Self.indent : 0
        let expected: ClosedRange<CGFloat> = isSent
            ? (columnMaxX - lane)...(columnMaxX - inset)
            : (row.minX + inset)...(row.minX + lane)
        #expect(abs(card.minX - expected.lowerBound) <= 0.5, "card starts off - \(context), expected \(expected)")
        #expect(abs(card.maxX - expected.upperBound) <= 0.5, "card ends off - \(context), expected \(expected)")
        // The slot beside the lane's inner edge, `gutter` away (the mirror).
        if isSent {
            #expect(abs(slot.maxX + Self.gutter - (columnMaxX - lane)) <= 0.5, "slot not leading - \(context)")
        } else {
            #expect(abs(row.minX + lane + Self.gutter - slot.minX) <= 0.5, "slot not trailing - \(context)")
        }
        // PG-355's acceptance, on the row the list really hands out.
        if width == 428 {
            #expect(lane >= 240, "lane \(lane) pt in a \(row.width) pt row")
        }
    }
}

// MARK: - The real message row

// The same suite, in an extension so the struct body stays under SwiftLint's `type_body_length`.
extension PraticaTimelineLaneHostedTests {
    /// Not in Mail, so the header carries «non più in Mail» and a row with `actions: nil` draws
    /// no footer at all - the reference the footer tests subtract.
    private static let entry = PraticaTimelineEntry(
        id: "email/messaggio.md", kind: .message, date: Date(timeIntervalSince1970: 1_788_000_000),
        direction: .received, senderDisplayName: "Mario Rossi", subject: "Offerta 118",
        bodyPreview: "Buongiorno", hasAttachments: false, messageID: "<hug@example.com>", isInMail: false
    )

    /// With a linked note the header gains the link glyph and «Altro» trades nothing: «Scollega
    /// nota» joins «Collega nota…» there.
    private static func detail(linkedNote: String?) -> PraticaRowDetail {
        PraticaRowDetail(
            notePath: "email/messaggio.md", body: "Buongiorno", quotedHistory: nil, signature: nil,
            attachments: [], storeReferences: [], isPending: false, senderAddress: nil,
            pendingAttachments: [], linkedNote: linkedNote
        )
    }

    private func messageRow(linkedNote: String?, actions: PraticaCommandActions?) -> PraticaMessageRow {
        PraticaMessageRow(
            entry: Self.entry, detail: Self.detail(linkedNote: linkedNote), isExpanded: false,
            onToggle: { _ in }, onQuickLook: { _ in }, actions: actions
        )
    }

    private func makeActions(root: URL) async -> PraticaCommandActions {
        let controller = VaultController(recents: .volatile(), openTabs: .volatile())
        await controller.open(root)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        return PraticaCommandActions(pratiche: pratiche, vault: controller, navigation: Navigation())
    }

    /// The fitting height of `content` laid out at exactly `width`, in a window never shown.
    private func fittingHeight(of content: some View, width: CGFloat) async -> CGFloat {
        let host = HostedView(
            content.frame(width: width).environment(\.theme, .emergency),
            size: CGSize(width: width, height: 300)
        )
        defer { host.tearDown() }
        await host.settle()
        #expect(host.neverShown)
        #expect(host.refusals.isEmpty)
        return host.hosting.fittingSize.height
    }

    /// The real row, hosted the way the timeline hosts it: `PraticaLaneRowLayout` in a received
    /// lane inside a `List(selection:)`, with `fillerRows` more rows to make a legacy scroller
    /// take its width. Returns the row's and the card's frames.
    private func hostRealRow(
        width: Double, fillerRows: Int, linkedNote: String?, actions: PraticaCommandActions
    ) async throws -> (row: CGRect, card: CGRect) {
        let box = FrameBox()
        let size = CGSize(width: width, height: 300)
        let host = HostedView(
            List(selection: .constant(nil as String?)) {
                PraticaLaneRowLayout(
                    lane: .received, reservesSlot: true, gutter: Self.gutter, columnMaximum: Self.readable
                ) {
                    messageRow(linkedNote: linkedNote, actions: actions).report("card", into: box)
                } slot: {
                    Color.blue.frame(height: 20)
                }
                .report("row", into: box)
                .tag("row")
                ForEach(0..<fillerRows, id: \.self) { index in
                    Color.gray.frame(height: 20).tag("filler-\(index)")
                }
            }
            .frame(width: size.width, height: size.height)
            .environment(\.theme, .emergency),
            size: size
        )
        defer { host.tearDown() }
        await host.settle()
        #expect(host.neverShown)
        #expect(host.refusals.isEmpty)
        return (try #require(box.frames["row"]), try #require(box.frames["card"]))
    }

    /// The hand check's decision (two primary verbs): the real footer is one line at the lane's
    /// width in a default 428 pt timeline and in an 800 pt one, beside a legacy scroller or not,
    /// with a linked note or without. Read off heights, since the footer cannot be looked up in
    /// process: the card less the same row without a footer, both at the card's own width, is
    /// one caption line plus the row's spacing - `ViewThatFits`' stacked fallback would be three.
    /// Measured 2026-10-01: the footer adds 18 pt on one line and 54 pt stacked, and stays one line
    /// down to a 197 pt card (stacks at 196); the lane is 241-252 pt at 428 and 360 pt (the
    /// readable column's) at 800.
    @Test(arguments: [428.0, 800.0], [0, 60])
    func theRealFooterStaysOnOneLineAtTheLaneWidth(width: Double, fillerRows: Int) async throws {
        let vault = try TemporaryVault()
        let actions = await makeActions(root: vault.root)
        let captionLine = await fittingHeight(of: Text("Apri in Mail").themedText(.caption), width: 200)
        #expect(captionLine > 0)

        for linkedNote in [nil, "[[Nota]]"] as [String?] {
            let split = MessageCommand.footerSplit(actions.commands(for: Self.detail(linkedNote: linkedNote)))
            #expect(split.primary == [.openInMail, .addNote])
            #expect(split.overflow.contains(.addCall), "«Aggiungi telefonata» is in «Altro»")
            #expect(split.overflow.contains(linkedNote == nil ? .linkNote : .unlinkNote))

            let (row, card) = try await hostRealRow(
                width: width, fillerRows: fillerRows, linkedNote: linkedNote, actions: actions
            )
            #expect(abs(card.width - Self.laneWidth(row: row.width, lane: .received)) <= 0.5)
            let withoutFooter = await fittingHeight(
                of: messageRow(linkedNote: linkedNote, actions: nil), width: card.width
            )
            let footer = card.height - withoutFooter
            let context = "\(width) pt, \(fillerRows) filler rows, linked \(linkedNote != nil): card "
                + "\(card.width)×\(card.height), \(withoutFooter) without the footer, caption \(captionLine)"
            #expect(footer >= captionLine, "no footer drawn - \(context)")
            #expect(footer < 2 * captionLine, "the footer stacked - \(context)")
        }
    }

    /// The real message card takes its lane's whole width, in the readable column: exactly
    /// `laneWidth` of `min(row, 720)`, flush leading, and nothing of it past the column.
    @Test(arguments: [428.0, 800.0, 1200.0, 1600.0])
    func theRealMessageCardIsExactlyItsLaneInTheReadableColumn(width: Double) async throws {
        let vault = try TemporaryVault()
        let actions = await makeActions(root: vault.root)
        let (row, card) = try await hostRealRow(width: width, fillerRows: 0, linkedNote: nil, actions: actions)
        let lane = Self.laneWidth(row: row.width, lane: .received)
        #expect(abs(card.width - lane) <= 0.5, "card \(card.width), lane \(lane) in a \(row.width) pt row")
        #expect(abs(card.minX - row.minX) <= 0.5)
        #expect(card.maxX <= row.minX + Self.readable + 0.5)
    }
}

// MARK: - The selected state on the card

extension PraticaTimelineLaneHostedTests {
    /// The hand check's "selection on the card": `praticaCardSelection` outlines the card in the
    /// accent token at its edge and leaves its middle - where the text is - as it was.
    @Test func aSelectedCardIsOutlinedAtItsEdgeAndUnchangedInside() async throws {
        let size = CGSize(width: 200, height: 60)
        func pixels(selected: Bool) async throws -> (edge: NSColor, middle: NSColor) {
            let host = HostedView(
                Color.white.praticaCardSelection(isSelected: selected)
                    .frame(width: size.width, height: size.height)
                    .environment(\.theme, .emergency),
                size: size
            )
            defer { host.tearDown() }
            await host.settle()
            #expect(host.neverShown && host.refusals.isEmpty)
            let snapshot = try #require(host.snapshot())
            let rep = try #require(NSBitmapImageRep(data: snapshot.png))
            let scale = CGFloat(rep.pixelsWide) / size.width
            let midY = Int(size.height / 2 * scale)
            let edge = try #require(rep.colorAt(x: Int(1 * scale), y: midY)?.usingColorSpace(.sRGB))
            let middle = try #require(rep.colorAt(x: Int(size.width / 2 * scale), y: midY)?.usingColorSpace(.sRGB))
            return (edge, middle)
        }
        let selected = try await pixels(selected: true)
        let plain = try await pixels(selected: false)
        let accent = try #require(NSColor(Theme.emergency.color(.accentPrimary)).usingColorSpace(.sRGB))
        func close(_ lhs: NSColor, _ rhs: NSColor, within tolerance: CGFloat) -> Bool {
            abs(lhs.redComponent - rhs.redComponent) < tolerance
                && abs(lhs.greenComponent - rhs.greenComponent) < tolerance
                && abs(lhs.blueComponent - rhs.blueComponent) < tolerance
        }
        // The outline's edge pixel is the accent blended a little with the card (measured
        // 0.22/0.48/0.79 against 0.04/0.40/0.76), hence the looser tolerance there.
        #expect(close(selected.edge, accent, within: 0.2), "the selected edge is \(selected.edge), accent \(accent)")
        #expect(!close(plain.edge, accent, within: 0.2), "an unselected card has no outline")
        #expect(close(selected.middle, plain.middle, within: 0.01), "selection leaves the card's inside unchanged")
    }

    /// The native full-row highlight is hidden by the row background, the way `PraticaTimelineView`
    /// sets it. A measurement witness (hand check round 4, macOS 27): the selected row view draws
    /// its highlight into its own layer, and `.listRowBackground` adds a subview spanning the whole
    /// row, ordered before the cell - above the row's own drawing, below the content. If a future
    /// macOS draws the highlight elsewhere, this fails rather than the highlight silently returning.
    @Test func theRowBackgroundSitsAboveTheSelectedRowsOwnHighlight() async throws {
        let size = CGSize(width: 400, height: 200)
        let host = HostedView(
            List(selection: .constant("a" as String?)) {
                ForEach(["a", "b"], id: \.self) { id in
                    Text(id)
                        .listRowBackground(Theme.emergency.color(.backgroundPrimary))
                        .tag(id)
                }
            }
            .scrollContentBackground(.hidden)
            .frame(width: size.width, height: size.height),
            size: size
        )
        defer { host.tearDown() }
        await host.settle()
        func views(in view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views(in:)) }
        let rows = views(in: host.hosting).compactMap { $0 as? NSTableRowView }
        let selected = try #require(rows.first { $0.isSelected })
        let cellIndex = try #require(selected.subviews.firstIndex { $0 is NSTableCellView })
        let background = selected.subviews.prefix(cellIndex).first {
            !$0.isHidden && abs($0.frame.width - selected.bounds.width) <= 0.5
                && String(describing: type(of: $0)).hasPrefix("NSHostingView")
        }
        #expect(background != nil, "no full-row background under the cell: \(selected.subviews.map { type(of: $0) })")
        #expect(host.neverShown && host.refusals.isEmpty)
    }
}
