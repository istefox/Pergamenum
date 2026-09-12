import CoreGraphics
import Foundation

/// A crop rectangle over an image card's own file, in the file's normalised coordinates
/// (ADR-0020 D1). Stored on the node as one prefixed, scalar key -
/// `"pergamenum-crop": "x y w h"` - never as a stored property of `CanvasNode`: see D2 for
/// why the codec (`Sources/Core/Canvas/JSONCanvas.swift`) is not touched.
struct CanvasCrop: Equatable, Sendable {
    /// The prefixed key the value lives under, on `CanvasNode.unknown`.
    static let key = "pergamenum-crop"

    /// A crop below this fraction of the image on either axis has nothing left to show
    /// and no grip left to grab it with (ADR-0020 D5's floor).
    static let minimumFraction: CGFloat = 0.02

    /// How close to the whole image counts as "no crop at all" (D6): a value inside this
    /// epsilon of `"0 0 1 1"` removes the key rather than writing a no-op rectangle.
    static let wholeEpsilon: CGFloat = 0.0005

    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    // MARK: Reading

    /// The crop written on `node`, or `nil` when the key is absent, malformed, or out of
    /// range. A malformed value is never corrected or removed here - D2's own rule is that
    /// nothing reads out of `unknown` ever mutates it - the card simply draws whole, the
    /// same way a missing key does.
    static func read(from node: CanvasNode) -> CanvasCrop? {
        guard case .string(let raw)? = node.unknown[key] else { return nil }
        return parse(raw)
    }

    static func parse(_ raw: String) -> CanvasCrop? {
        let parts = raw.split(separator: " ")
        guard parts.count == 4 else { return nil }
        let numbers = parts.compactMap { Double($0) }
        guard numbers.count == 4 else { return nil }
        let (x, y, width, height) = (numbers[0], numbers[1], numbers[2], numbers[3])
        guard x >= 0, y >= 0, width > 0, height > 0, x + width <= 1.0001, y + height <= 1.0001 else {
            return nil
        }
        return CanvasCrop(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
    }

    // MARK: Writing

    /// Four decimals, space separated (D1) - stable under the encoder's own formatting so a
    /// file that did not change in content does not change on disk.
    var formatted: String {
        [x, y, width, height].map { String(format: "%.4f", $0) }.joined(separator: " ")
    }

    /// Whether this crop is the whole image within `wholeEpsilon` - the case D6 says must
    /// remove the key rather than write `"0.0000 0.0000 1.0000 1.0000"`.
    var isWhole: Bool {
        abs(x) < Self.wholeEpsilon && abs(y) < Self.wholeEpsilon
            && abs(width - 1) < Self.wholeEpsilon && abs(height - 1) < Self.wholeEpsilon
    }

    /// Clamped into the unit square with `minimumFraction` as the floor on each axis - the
    /// commit-time rule D6 applies before a crop is written.
    var clamped: CanvasCrop {
        var w = min(max(width, Self.minimumFraction), 1)
        var h = min(max(height, Self.minimumFraction), 1)
        var newX = min(max(x, 0), 1 - w)
        var newY = min(max(y, 0), 1 - h)
        // Guard the floor a second time: clamping `x`/`y` above can leave `w`/`h` still
        // exceeding what remains of the unit square when the original rectangle started
        // past the far edge.
        w = min(w, 1 - newX)
        h = min(h, 1 - newY)
        newX = min(newX, 1 - w)
        newY = min(newY, 1 - h)
        return CanvasCrop(x: newX, y: newY, width: w, height: h)
    }

    // MARK: Point-space conversion

    /// The crop rectangle in the drawn image's own point space (D5: the gesture runs in
    /// points, not normalised space, so `lockAspect` means a literal square on screen).
    func rect(in drawnSize: CGSize) -> CGRect {
        CGRect(
            x: x * drawnSize.width, y: y * drawnSize.height,
            width: width * drawnSize.width, height: height * drawnSize.height
        )
    }

    /// The inverse of `rect(in:)` - a point-space rectangle normalised back against the
    /// drawn image's size, at commit time.
    static func normalized(_ rect: CGRect, in drawnSize: CGSize) -> CanvasCrop {
        guard drawnSize.width > 0, drawnSize.height > 0 else { return CanvasCrop(x: 0, y: 0, width: 1, height: 1) }
        return CanvasCrop(
            x: rect.minX / drawnSize.width, y: rect.minY / drawnSize.height,
            width: rect.width / drawnSize.width, height: rect.height / drawnSize.height
        )
    }

    // MARK: Croppable files

    /// Raster image extensions only (D8): `svg` is excluded because it is this app's own
    /// editable drawing, and PDFs are excluded because SPEC §6.5 gives them a page selector
    /// instead. This is the single answer `isCroppable` gives; the two other, disagreeing
    /// extension lists in this repository (`NodeCard.symbol(for:)`,
    /// `ViewGridRenderers`) are a recorded, deliberate divergence (D8), not a bug to fix here.
    static func isCroppable(path: String) -> Bool {
        let extensions: Set<String> = ["png", "jpg", "jpeg", "heic", "gif"]
        return extensions.contains((path as NSString).pathExtension.lowercased())
    }
}
