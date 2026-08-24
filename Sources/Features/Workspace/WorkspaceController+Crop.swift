import CoreGraphics
import Foundation

/// ADR-0020 D5: entering, dragging and leaving crop mode. Transient controller state
/// (`croppingNodeID`, `cropOriginal`, `cropDraft`, `cropDrawnSize`, `cropHandle`), owned
/// here for the same reason `WorkspaceController+Gestures`'s resize state is - an
/// extension cannot hold stored properties.
extension WorkspaceController {
    /// Starts crop mode on `nodeID`. `drawnSize` is the image's current drawn point size,
    /// supplied by the card view - the only place that knows it (D7 draws at `node.width`
    /// while cropping). Entering on a second card confirms whatever crop was already in
    /// progress on the first, the same as a click outside it would (D5).
    func beginCrop(nodeID: String, drawnSize: CGSize) {
        guard drawnSize.width > 0, drawnSize.height > 0,
              !BoardGeometry.drawsPlaceholder(at: zoom),
              let node = document.node(id: nodeID),
              case .file(let path, _) = node.kind, CanvasCrop.isCroppable(path: path)
        else { return }
        if let existing = croppingNodeID, existing != nodeID { endCrop(confirm: true) }

        let existingCrop = CanvasCrop.read(from: node) ?? CanvasCrop(x: 0, y: 0, width: 1, height: 1)
        croppingNodeID = nodeID
        cropDrawnSize = drawnSize
        cropOriginal = existingCrop.rect(in: drawnSize)
        cropDraft = cropOriginal
        cropHandle = .bottomRight
    }

    /// Re-arms `cropOriginal` from the current draft, at the start of every individual
    /// grip or move drag - the crop's own equivalent of `beginResize` re-snapshotting
    /// `resizeOriginalFrame` on each new gesture rather than once per session. Without
    /// this, a second grip drag would measure its translation from where the *session*
    /// started rather than from where the *first* drag left off, and would jump back.
    func beginCropGesture() {
        guard croppingNodeID != nil else { return }
        cropOriginal = cropDraft ?? cropOriginal
    }

    /// A grip drag, in the image's own point space (D5). `lockAspect` is the Shift
    /// modifier, meaning here exactly what it means on a card's own resize, because the
    /// same `BoardGeometry.resized` runs the arithmetic. `translation` is the drag's
    /// total offset from `beginCropGesture()`, not a per-frame delta.
    func updateCrop(handle: BoardGeometry.Handle, translation: CGSize, lockAspect: Bool) {
        guard croppingNodeID != nil, cropDrawnSize.width > 0, cropDrawnSize.height > 0 else { return }
        cropHandle = handle
        let minimum = CGSize(
            width: cropDrawnSize.width * CanvasCrop.minimumFraction,
            height: cropDrawnSize.height * CanvasCrop.minimumFraction
        )
        let resized = BoardGeometry.resized(
            cropOriginal, handle: handle, by: translation, lockAspect: lockAspect, minimum: minimum
        )
        cropDraft = clampedToImage(resized)
    }

    /// An inside-the-rectangle drag, which moves the crop without resizing it.
    /// `translation` is, like `updateCrop`'s, the total offset from `beginCropGesture()`.
    func moveCrop(translation: CGSize) {
        guard croppingNodeID != nil else { return }
        cropDraft = clampedToImage(cropOriginal.offsetBy(dx: translation.width, dy: translation.height))
    }

    /// Whether the draft has not moved from where the current gesture (or the session,
    /// before any gesture) started - the signal the crop editor uses to know its first,
    /// approximate `drawnSize` is still safe to refine without discarding an edit.
    var cropIsUntouched: Bool { cropDraft == cropOriginal }

    /// Refines `cropDrawnSize` (and the rect it is expressed in) once the editor has
    /// measured the image's real drawn size, without disturbing an edit already in
    /// progress. `beginCrop` is called with a synchronous estimate - the card's own
    /// frame - because the accurate figure is only known once the picture has loaded
    /// and the overlay has been laid out, both of which happen after crop mode has
    /// already been entered from the context menu.
    func primeCropDrawnSize(_ drawnSize: CGSize, for nodeID: String) {
        guard croppingNodeID == nodeID, cropIsUntouched, drawnSize.width > 0, drawnSize.height > 0,
              let node = document.node(id: nodeID)
        else { return }
        let existingCrop = CanvasCrop.read(from: node) ?? CanvasCrop(x: 0, y: 0, width: 1, height: 1)
        cropDrawnSize = drawnSize
        cropOriginal = existingCrop.rect(in: drawnSize)
        cropDraft = cropOriginal
    }

    /// Keeps a crop rectangle inside the drawn image, sliding rather than shrinking it
    /// when it has run past an edge - the same behaviour a move needs and a resize gets
    /// for free from `BoardGeometry.resized`'s own minimum floor.
    private func clampedToImage(_ rect: CGRect) -> CGRect {
        var result = rect
        result.size.width = min(result.width, cropDrawnSize.width)
        result.size.height = min(result.height, cropDrawnSize.height)
        result.origin.x = min(max(result.origin.x, 0), cropDrawnSize.width - result.width)
        result.origin.y = min(max(result.origin.y, 0), cropDrawnSize.height - result.height)
        return result
    }

    /// Leaves crop mode. `confirm: false` (Esc, or a stale draft after undo/redo) writes
    /// nothing at all - not even an empty `mutate` - so a cancelled crop leaves no undo
    /// step and no autosave (D5). `confirm: true` (Enter, a click outside, or one of the
    /// three exits ADR-0020's Consequences names) writes at most one key in one `mutate`
    /// (D6), and writes nothing when the result equals what was already there.
    @discardableResult
    func endCrop(confirm: Bool) -> Bool {
        let nodeID = croppingNodeID
        let draft = cropDraft
        let drawnSize = cropDrawnSize
        croppingNodeID = nil
        cropDraft = nil
        cropDrawnSize = .zero

        guard confirm, let nodeID, let draft, drawnSize.width > 0, drawnSize.height > 0,
              let node = document.node(id: nodeID)
        else { return false }

        let normalized = CanvasCrop.normalized(draft, in: drawnSize).clamped
        let existing = CanvasCrop.read(from: node)
        let unchanged = normalized.isWhole ? (existing == nil) : (existing == normalized)
        guard !unchanged else { return false }

        mutate { document in
            guard let index = document.nodes.firstIndex(where: { $0.id == nodeID }) else { return }
            if normalized.isWhole {
                document.nodes[index].unknown.removeValue(forKey: CanvasCrop.key)
            } else {
                document.nodes[index].unknown[CanvasCrop.key] = .string(normalized.formatted)
            }
        }
        return true
    }

    /// "Rimuovi ritaglio" outside crop mode: the same removal `endCrop` does when the
    /// draft comes back whole, without entering the mode first.
    func removeCrop(nodeIDs: Set<String>) {
        let affected = nodeIDs.filter { document.node(id: $0)?.unknown[CanvasCrop.key] != nil }
        guard !affected.isEmpty else { return }
        mutate { document in
            for index in document.nodes.indices where affected.contains(document.nodes[index].id) {
                document.nodes[index].unknown.removeValue(forKey: CanvasCrop.key)
            }
        }
    }

    /// The crop rectangle to draw for `nodeID`, in the image's own point space: the live
    /// draft while its card is being cropped, `nil` otherwise.
    func cropDisplayRect(for nodeID: String) -> CGRect? {
        guard nodeID == croppingNodeID else { return nil }
        return cropDraft ?? cropOriginal
    }
}
