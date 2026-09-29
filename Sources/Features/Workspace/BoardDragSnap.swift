import CoreGraphics
import Foundation

// ADR-0072 §D10, plan docs/plans/pg-138-pg-141-pg-142-performance-debt.md, Task 6 - R-18.
//
// What a card drag snaps against, captured once when the drag begins: the anchor card's frame and
// the frames of every card not being dragged. `updateDrag` used to rebuild that list from the whole
// document on every pointer event of the gesture.

struct BoardDragSnap: Equatable {
    let anchorID: String
    let anchor: CGRect
    let others: [CGRect]

    /// The translation pulled onto whatever the moved anchor lines up with, and the guides to
    /// draw. `zoom` and `gridStep` are read by the caller on every tick, since both can change
    /// during a drag.
    func snapped(
        translation: CGSize, zoom: CGFloat, gridStep: CGFloat?
    ) -> (translation: CGSize, guides: [BoardGeometry.Guide]) {
        let proposed = anchor.offsetBy(dx: translation.width, dy: translation.height)
        // The threshold is in board units, so the pull is the same handful of pixels
        // whatever the zoom: a fixed board threshold would be imperceptible zoomed out
        // and would fight the pointer zoomed in.
        let (snapped, guides) = BoardGeometry.snapped(
            proposed, to: others, threshold: 6 / max(zoom, 0.01), gridStep: gridStep
        )
        return (CGSize(width: snapped.minX - anchor.minX, height: snapped.minY - anchor.minY), guides)
    }
}
