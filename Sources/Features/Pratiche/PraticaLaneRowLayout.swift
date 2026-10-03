import SwiftUI

// ADR-0049 §D8, PG-365, PG-366: one timeline row's two columns, the card and the note slot
// beside it on the side away from the lane's edge (`PraticaTimelineModel.slotSide`), laid out
// from `PraticaTimelineModel+Layout.swift`'s arithmetic inside the readable column. Its own view,
// not a part of `PraticaTimelineView.row(_:next:)`, so `Tests/PraticaTimelineLaneHostedTests.swift`
// can host the production layout in a real `List` with plain content instead of the whole pane.
struct PraticaLaneRowLayout<Lane: View, Slot: View>: View {
    /// The lane the row aligns to: `PraticaTimelineModel.hostLane(for:)`.
    let lane: PraticaLane
    /// A message, or an entry anchored to one: the row keeps the note slot's place on the same
    /// side, so the card's width is its message's (ADR-0076 §D3).
    let reservesSlot: Bool
    let gutter: CGFloat
    /// The readable column's width, `theme.spacing(.readable)`: the row lays out in at most this
    /// much of its width, from the leading edge (`PraticaTimelineModel.columnWidth`).
    let columnMaximum: CGFloat
    /// ADR-0079 §D5: the part of the rail this row draws (`PraticaTimelineModel.railPieces`).
    var rail: PraticaRailPiece = .none
    /// The anchored indent, `theme.spacing(.l)`: the rail runs in its middle.
    var railStep: CGFloat = 0
    @ViewBuilder let content: () -> Lane
    @ViewBuilder let slot: () -> Slot

    var body: some View {
        LaneRowArrangement(
            lane: lane, reservesSlot: reservesSlot, gutter: gutter, columnMaximum: columnMaximum,
            rail: rail, railStep: railStep
        ) {
            // First, so the rail sits beneath the card and the slot.
            if rail != .none {
                PraticaRailPart(lane: lane).layoutValue(key: PraticaRailPartKey.self, value: .bar)
                if rail != .start {
                    PraticaRailPart(lane: lane).layoutValue(key: PraticaRailPartKey.self, value: .hook)
                }
            }
            content()
            if reservesSlot {
                slot()
            }
        }
    }
}

extension VerticalAlignment {
    private enum PraticaEntryHeading: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat { context[.top] }
    }

    /// ADR-0079 §D5: the height the rail's hook meets an anchored entry at, set by
    /// `PraticaEntryRow` on its heading and read by `LaneRowArrangement` from the card's own
    /// dimensions.
    static let praticaEntryHeading = VerticalAlignment(PraticaEntryHeading.self)
}

/// Which part of the rail a subview of `LaneRowArrangement` is; nil for the card and the slot.
private enum PraticaRailPartKey: LayoutValueKey {
    enum Part { case bar, hook }
    static let defaultValue: Part? = nil
}

/// One straight stretch of the rail, filled with its lane's rail token (ADR-0079 §D6) at
/// whatever frame `LaneRowArrangement` places it in. Never hit-tested and hidden from
/// accessibility, so selection, menus, Backspace and the double-click/Return toggle reach the
/// row exactly as before (R-13).
private struct PraticaRailPart: View {
    @Environment(\.theme) private var theme
    let lane: PraticaLane

    var body: some View {
        if let token = PraticaTimelineModel.railToken(for: lane) {
            Rectangle()
                .fill(theme.color(token))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

extension View {
    /// The row chrome `PraticaTimelineView.list` applies to every timeline row, one modifier so
    /// the hosted rail test (`PraticaTimelineRailHostedTests`) measures the production shape.
    /// The selected state is the card's (`praticaCardSelection`), not the row's. Measured on
    /// macOS 27 (hand check round 4): the row view draws its selection highlight into its own
    /// layer, and a row background is a subview spanning the whole row above it, so an opaque
    /// one in the pane's own colour hides the highlight and looks like no background.
    /// `List(selection:)`, its focus, `.onDeleteCommand`, `primaryAction` and every context menu
    /// are untouched: only the drawing changes.
    func praticaTimelineRowChrome() -> some View {
        modifier(PraticaTimelineRowChrome())
    }
}

private struct PraticaTimelineRowChrome: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .listRowSeparator(.hidden)
            .listRowBackground(theme.color(.backgroundPrimary))
    }
}

/// The row's arrangement, inside a leading column `min(row, readable)` wide: a mirror,
/// `[card][gutter][slot]......` for a received message and `......[slot][gutter][card]` for a
/// sent one, each card flush with its own edge of the column, so an empty slot (nothing linked,
/// nothing drawn) leaves no gap between the card and that edge, and at a wide window the free
/// space falls to the right of the column, never between two messages.
///
/// Every card takes its lane's whole width (`laneWidth`: 70 % of what the slot leaves, widening
/// toward 91 % in a narrow timeline - `laneShare(of:)`; DESIGN.md "Binding decisions", the third
/// carrier of direction beside the glyph and the lane's token, R-25): uniform widths read as a
/// column, where cards at their content's widths read as scattered notes (the hand check).
///
/// A `Layout` rather than an `HStack` of frames: the row's width is the `List`'s row width
/// (`bounds.width`, see `PraticaTimelineModel+Layout.swift`), and the column, the gutter and the
/// slot come out of it in the same arithmetic, never left for a stack to discover - without that
/// a card at its widest claims the slot's space and the two draw on top of each other (the trap
/// ADR-0049 §D8 names). The arrangement fills the row, so a sent card is placed at the column's
/// trailing edge rather than at the leading edge the way a bare `List` row would put it (PG-365).
private struct LaneRowArrangement: Layout {
    let lane: PraticaLane
    let reservesSlot: Bool
    let gutter: CGFloat
    let columnMaximum: CGFloat
    let rail: PraticaRailPiece
    let railStep: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // The rail is left out: it is drawn outside the row's measured height, so no row
        // changes height because it carries one (ADR-0079 §D5, R-09).
        let content = subviews.filter { $0[PraticaRailPartKey.self] == nil }
        guard !content.isEmpty else { return .zero }
        // A width offered is the row's, and the arrangement fills it; an ideal-size query (no
        // width offered) answers the readable column itself.
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? columnMaximum
        return CGSize(width: width, height: height(of: content, in: columns(rowWidth: width)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let content = subviews.filter { $0[PraticaRailPartKey.self] == nil }
        guard let card = content.first else { return }
        let columns = columns(rowWidth: bounds.width)
        let cardProposal = ProposedViewSize(width: columns.cardWidth, height: nil)
        card.place(
            at: CGPoint(x: bounds.minX + columns.cardX, y: bounds.minY), anchor: .topLeading,
            proposal: cardProposal
        )
        if let slotX = columns.slotX, content.count > 1 {
            content[1].place(
                at: CGPoint(x: bounds.minX + slotX, y: bounds.minY), anchor: .topLeading,
                proposal: ProposedViewSize(width: columns.slotWidth, height: nil)
            )
        }
        // The card is measured again only when a rail is drawn: most rows carry none.
        if rail != .none {
            placeRail(subviews, in: bounds, columns: columns, card: card.dimensions(in: cardProposal))
        }
    }

    /// ADR-0079 §D5: the rail's bar and hook, from the row's own arithmetic. Each piece covers
    /// its own row only, reaching `PraticaTimelineModel.railRowInset` past the row's measured
    /// bounds: the `List`'s own space between two cards, which lies inside each row view (gate
    /// M1), so the pieces of consecutive rows meet without a break.
    private func placeRail(
        _ subviews: Subviews, in bounds: CGRect, columns: PraticaRowColumns, card: ViewDimensions
    ) {
        let geometry = PraticaTimelineModel.railGeometry(columns: columns, lane: lane, step: railStep)
        let line = PraticaTimelineModel.railLineWidth
        let inset = PraticaTimelineModel.railRowInset
        let lineX = bounds.minX + geometry.x - line / 2
        let hookY = bounds.minY + card[.praticaEntryHeading]
        let barTop: CGFloat, barBottom: CGFloat
        switch rail {
        case .none: return
        case .start: (barTop, barBottom) = (bounds.minY + card.height, bounds.maxY + inset)
        case .through: (barTop, barBottom) = (bounds.minY - inset, bounds.maxY + inset)
        case .last: (barTop, barBottom) = (bounds.minY - inset, hookY + line / 2)
        }
        let hookStart = bounds.minX + min(geometry.x - line / 2, geometry.hookEnd)
        let hookEnd = bounds.minX + max(geometry.x + line / 2, geometry.hookEnd)
        for part in subviews {
            switch part[PraticaRailPartKey.self] {
            case .bar:
                part.place(
                    at: CGPoint(x: lineX, y: barTop), anchor: .topLeading,
                    proposal: ProposedViewSize(width: line, height: max(0, barBottom - barTop))
                )
            case .hook:
                part.place(
                    at: CGPoint(x: hookStart, y: hookY - line / 2), anchor: .topLeading,
                    proposal: ProposedViewSize(width: max(0, hookEnd - hookStart), height: line)
                )
            case nil:
                continue
            }
        }
    }

    /// The row's columns, computed on the readable column rather than on the whole row.
    private func columns(rowWidth: CGFloat) -> PraticaRowColumns {
        PraticaTimelineModel.rowColumns(
            container: PraticaTimelineModel.columnWidth(row: rowWidth, readable: columnMaximum),
            lane: lane, reservesSlot: reservesSlot, gutter: gutter
        )
    }

    /// The taller of the card at its width and the slot at its width, both top-aligned.
    private func height(of subviews: [LayoutSubview], in columns: PraticaRowColumns) -> CGFloat {
        var height = subviews[0].sizeThatFits(ProposedViewSize(width: columns.cardWidth, height: nil)).height
        if columns.slotX != nil, subviews.count > 1 {
            let slot = subviews[1].sizeThatFits(ProposedViewSize(width: columns.slotWidth, height: nil))
            height = max(height, slot.height)
        }
        return height
    }
}

extension View {
    /// The selected state drawn on the card itself (the hand check): an outline in
    /// `PraticaTimelineModel.selectionBorder`'s token, at the card's own corner radius, over the
    /// card's lane colour, so the text keeps its own tokens and stays as readable as unselected.
    /// Applied to the card, inside any anchored indent, never to the whole row.
    func praticaCardSelection(isSelected: Bool) -> some View {
        modifier(PraticaCardSelection(isSelected: isSelected))
    }
}

private struct PraticaCardSelection: ViewModifier {
    @Environment(\.theme) private var theme
    let isSelected: Bool

    func body(content: Content) -> some View {
        content.overlay {
            if let token = PraticaTimelineModel.selectionBorder(isSelected: isSelected) {
                RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                    .strokeBorder(theme.color(token), lineWidth: 2)
                    .accessibilityHidden(true)
            }
        }
    }
}
