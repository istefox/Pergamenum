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
    @ViewBuilder let content: () -> Lane
    @ViewBuilder let slot: () -> Slot

    var body: some View {
        LaneRowArrangement(lane: lane, reservesSlot: reservesSlot, gutter: gutter, columnMaximum: columnMaximum) {
            content()
            if reservesSlot {
                slot()
            }
        }
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

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        // A width offered is the row's, and the arrangement fills it; an ideal-size query (no
        // width offered) answers the readable column itself.
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? columnMaximum
        return CGSize(width: width, height: height(of: subviews, in: columns(rowWidth: width)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let card = subviews.first else { return }
        let columns = columns(rowWidth: bounds.width)
        card.place(
            at: CGPoint(x: bounds.minX + columns.cardX, y: bounds.minY), anchor: .topLeading,
            proposal: ProposedViewSize(width: columns.cardWidth, height: nil)
        )
        if let slotX = columns.slotX, subviews.count > 1 {
            subviews[1].place(
                at: CGPoint(x: bounds.minX + slotX, y: bounds.minY), anchor: .topLeading,
                proposal: ProposedViewSize(width: columns.slotWidth, height: nil)
            )
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
    private func height(of subviews: Subviews, in columns: PraticaRowColumns) -> CGFloat {
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
