import Foundation

// PG-354, PG-355: the arithmetic of a timeline row's two columns - which side the lane sits
// on, which side of it the note slot sits on (mirrored: beside the lane, away from the lane's
// edge), how wide the lane is, how wide the note slot is (ADR-0049 §D8) - pure, so the
// numbers are pinned by `Tests/PraticaTimelineLayoutTests.swift` rather than by eye. A sibling
// of `PraticaTimelineModel.swift` (`Type+Aspect.swift`, ADR-0045) so neither file outgrows
// SwiftLint's size limits. `PraticaLaneRowLayout` is the one view that reads it.
//
// `container` is the width a row in the timeline's `List` is laid out in, which
// `PraticaLaneRowLayout`'s arrangement reads off its own bounds (`containerRelativeFrame` reported
// the same number when it carried the layout): measured on macOS 27
// (`Tests/PraticaTimelineLaneHostedTests.swift`), that is already the row's content width - the
// `List`'s width less its 16 pt row inset on each side, and less the scroller when a legacy
// scroller is showing - so nothing here subtracts an inset of its own. The hand check's
// "readable column" caps it first (`columnWidth`): every row lays out in at most
// `spacing.readable` (720 pt, ADR-0030 §D7), leading-aligned, and every width below is taken
// out of that column, never out of the whole row.

/// The side a lane sits on (DESIGN.md "Binding decisions"). Not SwiftUI's `Alignment`: this
/// file stays a pure model, and the view maps the two cases.
enum PraticaLaneSide: Equatable, Sendable {
    case leading
    case trailing
}

/// One row's columns, in points from the row's leading edge (`PraticaTimelineModel.rowColumns`).
struct PraticaRowColumns: Equatable, Sendable {
    var cardX: CGFloat
    var cardWidth: CGFloat
    /// Nil when the row reserves no note slot.
    var slotX: CGFloat?
    var slotWidth: CGFloat
}

extension PraticaTimelineModel {
    /// Received on the leading side, sent on the trailing side (PG-354). A free manual entry
    /// takes the whole column, so its side only decides where it starts: leading.
    static func laneAlignment(_ lane: PraticaLane) -> PraticaLaneSide {
        switch lane {
        case .received, .entry: .leading
        case .sent: .trailing
        }
    }

    /// ADR-0076 §D3 (R-09): how far an anchored entry's box stands in, as leading and trailing
    /// padding, from its lane's own edge - the edge its message's card is flush with - so it
    /// reads as nested under the message on either side and its far edge lines up with the
    /// message's inner edge: received `[0, L]` gives the entry `[step, L]`, sent `[C-L, C]`
    /// gives `[C-L, C-step]`. Nothing for a row that is not anchored.
    static func anchoredIndent(
        lane: PraticaLane, isAnchored: Bool, step: CGFloat
    ) -> (leading: CGFloat, trailing: CGFloat) {
        guard isAnchored else { return (0, 0) }
        switch laneAlignment(lane) {
        case .leading: return (step, 0)
        case .trailing: return (0, step)
        }
    }

    /// Which side of the lane the note slot sits on: the mirror of `laneAlignment`, so a row
    /// reads `[lane][gutter][slot]` from the leading edge for a received message and
    /// `[slot][gutter][lane]` up to the trailing edge for a sent one, each card flush with its
    /// own edge. The slot's content aligns toward the lane, which is `laneAlignment` itself.
    static func slotSide(_ lane: PraticaLane) -> PraticaLaneSide {
        switch laneAlignment(lane) {
        case .leading: .trailing
        case .trailing: .leading
        }
    }

    /// ADR-0049 §D8's note slot, on either side of the lane (`slotSide`): `BoardTray`'s 200 pt
    /// at most, and never more than 27 % of the column once the gutter is taken out (PG-355), so
    /// a narrow timeline does not hand the slot most of what the message needs. In the timeline
    /// `container` is the readable column (`columnWidth`), never more than 720 pt, so the slot
    /// tops out at (720 - 16) × 27 % = 190.08 pt there: the 200 pt cap is reached only by a
    /// container of about 757 pt or more, which this function accepts and the timeline never
    /// passes.
    static func noteSlotWidth(container: CGFloat, gutter: CGFloat) -> CGFloat {
        max(0, min(noteSlotMaximum, (container - gutter) * noteSlotShare))
    }

    /// The column a timeline row lays out in: the row's width, capped at the readable column
    /// (`spacing.readable`, ADR-0030 §D7), so at a wide window the free space falls to the right
    /// of the column instead of between a received and a sent message. Every other width here
    /// is computed on this column (`container`).
    static func columnWidth(row: CGFloat, readable: CGFloat) -> CGFloat {
        max(0, min(row, readable))
    }

    /// Where a row's card and note slot go, from the row's leading edge, in a column
    /// `container` wide: the card flush with its lane's edge at the full `laneWidth` - uniform,
    /// so cards line up as a column rather than scattering at their content's widths - and the
    /// slot beside it, `gutter` away, on `slotSide`. `slotX` is nil for a row that reserves no
    /// slot (a free entry, which takes the whole column). An anchored entry's card is its
    /// message's lane, and its `anchoredIndent` padding insets the box inside it.
    static func rowColumns(
        container: CGFloat, lane: PraticaLane, reservesSlot: Bool, gutter: CGFloat
    ) -> PraticaRowColumns {
        let card = laneWidth(container: container, lane: lane, reservesSlot: reservesSlot, gutter: gutter)
        let slot = reservesSlot ? noteSlotWidth(container: container, gutter: gutter) : 0
        switch laneAlignment(lane) {
        case .leading:
            return PraticaRowColumns(
                cardX: 0, cardWidth: card, slotX: reservesSlot ? card + gutter : nil, slotWidth: slot
            )
        case .trailing:
            let cardX = container - card
            return PraticaRowColumns(
                cardX: cardX, cardWidth: card, slotX: reservesSlot ? cardX - gutter - slot : nil, slotWidth: slot
            )
        }
    }

    /// The lane's width in a column `container` wide: a message card's width (`rowColumns`). A
    /// row that reserves the note slot (a message, an anchored entry) leaves the gutter and
    /// `noteSlotWidth` out first, in this same arithmetic, so a card and the slot never draw on
    /// top of each other (ADR-0049 §D8). A free entry (`.entry`) may take everything left; a message lane takes
    /// 70 % of it, widening toward 91 % as what is left narrows (`laneShare(of:)`).
    static func laneWidth(
        container: CGFloat, lane: PraticaLane, reservesSlot: Bool, gutter: CGFloat
    ) -> CGFloat {
        let reserved = reservesSlot ? gutter + noteSlotWidth(container: container, gutter: gutter) : 0
        let available = max(0, container - reserved)
        return lane == .entry ? available : available * laneShare(of: available)
    }

    /// 70 % (DESIGN.md "Binding decisions") when `available` is at least `wideLaneSpace`, 91 %
    /// at or below `narrowLaneSpace`, and a straight line between, so a window being resized
    /// never makes the lane jump. In row widths (`container`, not the timeline's own width): a
    /// default 428 pt timeline gives a 396 pt row, or 379 pt beside a legacy scroller, which
    /// leaves 277 or 265 pt - the narrow end, so the lane is at least 240 pt. An 800 pt timeline
    /// gives a 768 pt row (751 with the scroller), which the readable column caps at 720 pt, as
    /// it does every wider one: 720 - 16 - 190.08 leaves 513.92 pt - the wide end, so the lane is
    /// 70 %, 359.74 pt. 91 % rather than a round 90 %: at 379 pt, 90 % is 238.5.
    static func laneShare(of available: CGFloat) -> CGFloat {
        if available >= wideLaneSpace { return wideLaneShare }
        if available <= narrowLaneSpace { return narrowLaneShare }
        let progress = (wideLaneSpace - available) / (wideLaneSpace - narrowLaneSpace)
        return wideLaneShare + (narrowLaneShare - wideLaneShare) * progress
    }

    /// The hand check's "selection on the card, not the row": the colour token a selected
    /// row's card is outlined in (`View.praticaCardSelection`), nil when the row is not selected.
    /// The `List`'s own full-row highlight would light the empty column space beside a card
    /// while the card itself stayed as it was.
    static func selectionBorder(isSelected: Bool) -> ColorToken? {
        isSelected ? .accentPrimary : nil
    }

    static let noteSlotMaximum: CGFloat = 200
    static let noteSlotShare: CGFloat = 0.27
    static let wideLaneShare: CGFloat = 0.7
    static let narrowLaneShare: CGFloat = 0.91
    static let wideLaneSpace: CGFloat = 500
    static let narrowLaneSpace: CGFloat = 300
}
