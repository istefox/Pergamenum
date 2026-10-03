import Foundation

// ADR-0079 §D5/§D6 (PG-369): the rail that ties an anchored entry to its message - which piece
// each drawn row carries, where the line and the hook go in the row's own arithmetic, and the
// token it draws in. Pure, so the pieces and the numbers are pinned by
// `Tests/PraticaTimelineRailTests.swift` rather than by eye; `PraticaLaneRowLayout` is the one
// view that reads it. A sibling of `PraticaTimelineModel.swift` (`Type+Aspect.swift`, ADR-0045).

/// The part of the rail one row draws. Each piece covers its own row's height only, so the
/// rail is never one view spanning rows the `List` may not have realised (ADR-0079
/// "Alternatives considered").
enum PraticaRailPiece: Equatable, Sendable {
    /// No rail in this row.
    case none
    /// A message with a visible anchored entry under it: from the card's bottom edge down.
    case start
    /// An anchored entry with another of its message's entries under it: the whole row, with
    /// a hook into the card at its heading.
    case through
    /// The last anchored entry of its message: from the row's top down to the hook, then the
    /// corner into the card.
    case last
}

/// Where a row's rail goes, in points from the row's leading edge.
struct PraticaRailGeometry: Equatable, Sendable {
    /// The vertical line's centre: the middle of the anchored indent.
    var x: CGFloat
    /// Where the hook ends: the anchored card's near edge.
    var hookEnd: CGFloat
}

extension PraticaTimelineModel {
    /// The piece each row of `rows` draws, in one pass over the rows the view draws
    /// (`filteredTimeline`). A message whose next row is anchored to its own Message-ID starts a
    /// group; each anchored entry of that group is `through` while the next row is anchored to
    /// the same id, `last` otherwise. An anchored entry whose message is not the row above its
    /// group draws nothing, so no rail ever hangs from a missing message. A row absent from the
    /// answer draws nothing: read it as `.none`.
    static func railPieces(in rows: [PraticaTimelineEntry]) -> [PraticaTimelineEntry.ID: PraticaRailPiece] {
        var pieces: [PraticaTimelineEntry.ID: PraticaRailPiece] = [:]
        var group: String?
        for (index, row) in rows.enumerated() {
            let nextAnchor = index + 1 < rows.count ? anchoredMessageID(of: rows[index + 1]) : nil
            if let anchor = anchoredMessageID(of: row) {
                guard anchor == group else { continue }
                pieces[row.id] = nextAnchor == anchor ? .through : .last
                if nextAnchor != anchor { group = nil }
            } else {
                group = nil
                guard row.kind == .message, let messageID = row.messageID, !messageID.isEmpty,
                      nextAnchor == messageID
                else { continue }
                pieces[row.id] = .start
                group = messageID
            }
        }
        return pieces
    }

    /// The line's x and the hook's end, from the row's columns and the indent step: the middle
    /// of the anchored indent on the lane's own edge, and the anchored card's near edge. A
    /// message row and its anchored rows share their columns (ADR-0079 F7), so the line has one
    /// x down the group, and it lies inside the indent, taking no width from a card or the note
    /// column (R-09).
    static func railGeometry(columns: PraticaRowColumns, lane: PraticaLane, step: CGFloat) -> PraticaRailGeometry {
        switch laneAlignment(lane) {
        case .leading:
            return PraticaRailGeometry(x: columns.cardX + step / 2, hookEnd: columns.cardX + step)
        case .trailing:
            let edge = columns.cardX + columns.cardWidth
            return PraticaRailGeometry(x: edge - step / 2, hookEnd: edge - step)
        }
    }

    /// The rail's colour, its message lane's own (ADR-0079 §D6, R-10); nil for `.entry`, which
    /// hosts no rail.
    static func railToken(for lane: PraticaLane) -> ColorToken? {
        switch lane {
        case .received: .railReceived
        case .sent: .railSent
        case .entry: nil
        }
    }

    /// The rail's width, the selection outline's own (`praticaCardSelection`).
    static let railLineWidth: CGFloat = 2

    /// How far a piece reaches past its row's measured bounds, above and below. Gate M1
    /// (ADR-0079 implementation notes), measured on macOS 27 in a hosted `List` with the
    /// production row chrome at 428 and 1600 pt, with and without a scroller: row views abut
    /// (vertical intercell spacing 0), each `NSTableRowView` clips to its bounds, and the row's
    /// content sits 4 pt in from its row view's top and bottom. A piece reaching 4 pt past its
    /// card therefore fills its own row view to the edge and never draws into a neighbour's.
    /// `PraticaTimelineRailHostedTests` pins the 4 pt.
    static let railRowInset: CGFloat = 4

    private static func anchoredMessageID(of row: PraticaTimelineEntry) -> String? {
        if case let .anchored(messageID) = row.placement { messageID } else { nil }
    }
}
