import CoreGraphics
import Foundation

/// The geometry of a board: what a marquee catches, where a resize handle takes a
/// card, which cards a group holds, and what is worth drawing at the current zoom.
///
/// Free functions over rectangles rather than methods on the controller, so every
/// rule here is checked directly instead of through a gesture that only a person can
/// perform (SPEC §6.3).
enum BoardGeometry {
    /// The eight grips of SPEC §6.3: four corners and four sides.
    enum Handle: String, CaseIterable, Sendable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

        var movesLeftEdge: Bool { self == .topLeft || self == .left || self == .bottomLeft }
        var movesRightEdge: Bool { self == .topRight || self == .right || self == .bottomRight }
        var movesTopEdge: Bool { self == .topLeft || self == .top || self == .topRight }
        var movesBottomEdge: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }

        /// Where the grip sits inside the card, as a unit point.
        var unitPoint: CGPoint {
            CGPoint(
                x: movesLeftEdge ? 0 : (movesRightEdge ? 1 : 0.5),
                y: movesTopEdge ? 0 : (movesBottomEdge ? 1 : 0.5)
            )
        }
    }

    /// A card cannot be made smaller than this or the grips overlap and it can never
    /// be grabbed again.
    static let minimumSize = CGSize(width: 40, height: 30)

    // MARK: Grip and frame sizing

    /// The size a grip is drawn at, and the size of the target around it, both in
    /// screen points.
    ///
    /// Screen points, not board units, and that is the whole point: the grips live
    /// inside the board's `scaleEffect`, so a size expressed in board units shrinks
    /// with the zoom. At 68% a 9-unit grip was 6 points across and at 25% it was 2,
    /// which is why the corners could not be grabbed. Every user of these divides by
    /// the zoom, so a grip stays the same size to the hand at every scale.
    static let handleScreenSize: CGFloat = 10
    /// Larger than what is drawn: 10 points is what the eye wants and 24 is what the
    /// hand needs. The difference is invisible and is the reason the grip is hittable.
    static let handleTargetScreenSize: CGFloat = 24
    /// How wide the band of a group's frame is, the only part of a group that
    /// responds to the pointer (SPEC §6.5).
    static let groupBandScreenWidth: CGFloat = 16

    /// Converts one of the sizes above into board units at the given zoom.
    static func boardUnits(_ screenPoints: CGFloat, at zoom: CGFloat) -> CGFloat {
        screenPoints / max(zoom, 0.01)
    }

    // MARK: Hit testing

    /// The card under a board point, used to decide where an arrow lands.
    ///
    /// The last match wins because later nodes are drawn on top. A group counts only
    /// when nothing else is there: a group covers every card it holds, so preferring
    /// it would make every arrow drawn inside one land on the container instead of
    /// the card the user aimed at.
    static func nodeID(
        at point: CGPoint,
        among nodes: [CanvasNode],
        excluding excluded: String? = nil
    ) -> String? {
        let candidates = nodes.filter { $0.id != excluded && $0.frame.contains(point) }
        return candidates.last(where: { !$0.isGroup })?.id ?? candidates.last?.id
    }

    // MARK: Resize

    /// Applies a resize drag to a rectangle, driven by one of the eight grips.
    ///
    /// `lockAspect` is the Shift modifier of SPEC §6.3. A side grip with Shift held
    /// scales the other dimension to match, which is what keeps an image from being
    /// stretched by a grip that only moves one edge. `minimum` defaults to a card's own
    /// floor (`minimumSize`) but is overridden by ADR-0020's crop rectangle, whose floor
    /// is a fraction of the image rather than 40x30 board units.
    static func resized(
        _ frame: CGRect,
        handle: Handle,
        by translation: CGSize,
        lockAspect: Bool = false,
        minimum: CGSize = minimumSize
    ) -> CGRect {
        var left = frame.minX
        var top = frame.minY
        var right = frame.maxX
        var bottom = frame.maxY

        if handle.movesLeftEdge { left = min(right - minimum.width, left + translation.width) }
        if handle.movesRightEdge { right = max(left + minimum.width, right + translation.width) }
        if handle.movesTopEdge { top = min(bottom - minimum.height, top + translation.height) }
        if handle.movesBottomEdge { bottom = max(top + minimum.height, bottom + translation.height) }

        var result = CGRect(x: left, y: top, width: right - left, height: bottom - top)
        guard lockAspect, frame.width > 0, frame.height > 0 else { return result }

        // The dimension the grip actually drives wins; the other follows it. Averaging
        // the two instead would make the card drift away from the pointer.
        let ratio = frame.height / frame.width
        let drivesWidth = handle.movesLeftEdge || handle.movesRightEdge
        if drivesWidth {
            result.size.height = max(minimum.height, result.width * ratio)
        } else {
            result.size.width = max(minimum.width, result.height / ratio)
        }
        // A grip on the top or left moves the origin, so the anchor stays put.
        if handle.movesLeftEdge { result.origin.x = frame.maxX - result.width }
        if handle.movesTopEdge { result.origin.y = frame.maxY - result.height }
        return result
    }

    // MARK: Selection

    /// The cards a marquee catches: any card the rectangle touches, not only those it
    /// contains entirely, which is how selection rectangles behave everywhere else.
    static func nodeIDs(in marquee: CGRect, among nodes: [CanvasNode]) -> Set<String> {
        Set(nodes.filter { $0.frame.intersects(marquee) }.map(\.id))
    }

    /// The rectangle between two points, in either direction: a marquee dragged up and
    /// to the left is still a rectangle.
    static func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x), y: min(start.y, end.y),
            width: abs(end.x - start.x), height: abs(end.y - start.y)
        )
    }

    /// Toggles one card in a selection, which is what Shift+click means.
    static func toggling(_ nodeID: String, in selection: Set<String>) -> Set<String> {
        var result = selection
        if result.contains(nodeID) { result.remove(nodeID) } else { result.insert(nodeID) }
        return result
    }

    // MARK: Groups

    /// The cards a group holds: those whose frame is entirely inside it (SPEC §6.5).
    ///
    /// Contained rather than merely touching, so a card that happens to overlap a
    /// group's edge is not dragged along by a group the user never put it in.
    static func nodeIDs(inside group: CanvasNode, among nodes: [CanvasNode]) -> Set<String> {
        guard case .group = group.kind else { return [] }
        return Set(
            nodes
                .filter { $0.id != group.id && group.frame.contains($0.frame) }
                .map(\.id)
        )
    }

    /// Expands a selection so that moving a group moves what it holds.
    static func expandingGroups(_ selection: Set<String>, among nodes: [CanvasNode]) -> Set<String> {
        var result = selection
        for group in nodes where selection.contains(group.id) {
            result.formUnion(nodeIDs(inside: group, among: nodes))
        }
        return result
    }

    // MARK: Alignment and grid

    /// A guide drawn while dragging, at a board coordinate.
    struct Guide: Equatable, Sendable {
        enum Axis: Sendable { case vertical, horizontal }
        var axis: Axis
        var position: CGFloat
    }

    /// Snaps a dragged frame to the cards around it, and to the grid when nothing is
    /// near enough to align to.
    ///
    /// Alignment wins over the grid: a user dragging a card next to another one is
    /// lining it up with that card, and letting the grid pull it half a step away
    /// would defeat the guide the app just drew.
    static func snapped(
        _ frame: CGRect,
        to others: [CGRect],
        threshold: CGFloat,
        gridStep: CGFloat? = nil
    ) -> (frame: CGRect, guides: [Guide]) {
        var result = frame
        var guides: [Guide] = []

        let horizontalCandidates = others.flatMap { [$0.minX, $0.midX, $0.maxX] }
        let verticalCandidates = others.flatMap { [$0.minY, $0.midY, $0.maxY] }

        if let (offset, position) = nearest(
            edges: [frame.minX, frame.midX, frame.maxX],
            candidates: horizontalCandidates, threshold: threshold
        ) {
            result.origin.x += offset
            guides.append(Guide(axis: .vertical, position: position))
        } else if let step = gridStep, step > 0 {
            result.origin.x = (frame.origin.x / step).rounded() * step
        }

        if let (offset, position) = nearest(
            edges: [frame.minY, frame.midY, frame.maxY],
            candidates: verticalCandidates, threshold: threshold
        ) {
            result.origin.y += offset
            guides.append(Guide(axis: .horizontal, position: position))
        } else if let step = gridStep, step > 0 {
            result.origin.y = (frame.origin.y / step).rounded() * step
        }

        return (result, guides)
    }

    /// The smallest move that brings one of `edges` onto one of `candidates`.
    private static func nearest(
        edges: [CGFloat],
        candidates: [CGFloat],
        threshold: CGFloat
    ) -> (offset: CGFloat, position: CGFloat)? {
        var best: (offset: CGFloat, position: CGFloat)?
        for edge in edges {
            for candidate in candidates {
                let distance = candidate - edge
                guard abs(distance) <= threshold else { continue }
                if best == nil || abs(distance) < abs(best!.offset) {
                    best = (distance, candidate)
                }
            }
        }
        return best
    }

    // MARK: Drawing

    /// The board rectangle currently on screen, from the viewport, pan and zoom.
    static func visibleRect(viewport: CGSize, pan: CGSize, zoom: CGFloat) -> CGRect {
        guard zoom > 0 else { return .infinite }
        return CGRect(
            x: -pan.width / zoom,
            y: -pan.height / zoom,
            width: viewport.width / zoom,
            height: viewport.height / zoom
        )
    }

    /// The cards worth drawing: those the viewport touches, with a margin so a card
    /// half off-screen does not pop in at its own edge (SPEC §6.3, culling).
    static func visibleNodes(
        _ nodes: [CanvasNode],
        in visible: CGRect,
        margin: CGFloat = 200
    ) -> [CanvasNode] {
        guard visible != .infinite else { return nodes }
        let expanded = visible.insetBy(dx: -margin, dy: -margin)
        return nodes.filter { $0.frame.intersects(expanded) }
    }

    /// Below this zoom a card is drawn as a plain placeholder: its content is
    /// illegible anyway and rendering it costs the frame rate the board needs while
    /// panning (SPEC §6.3).
    static let placeholderZoom: CGFloat = 0.25

    static func drawsPlaceholder(at zoom: CGFloat) -> Bool { zoom < placeholderZoom }
}
