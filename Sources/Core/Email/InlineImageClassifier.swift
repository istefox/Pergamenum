import Foundation
import ImageIO

// ADR-0036 §R-10 amendment (2026-09-11): the byte-weight-only heuristic dropped real
// content that happened to compress well (a screenshot, a small photo); combining it
// with pixel dimensions catches only what byte weight alone could not tell apart from
// a signature or logo.

/// A pasted inline image (`Content-ID` + `image/*`) is decorative — a signature or a
/// logo, not content worth keeping — only when it is light in bytes AND small in pixel
/// dimensions. Either signal alone can belong to real content: a heavily compressed
/// screenshot is light but large, an uncompressed icon is small but not tiny in bytes.
/// Requiring both is what keeps the case that actually loses content.
enum InlineImageClassifier {
    static let weightThreshold = 50 * 1024
    static let dimensionThreshold = 200

    static func isDecorative(_ bytes: Data) -> Bool {
        guard bytes.count < weightThreshold else { return false }
        // Dimensions unreadable (corrupt header, exotic format): never drop on a guess -
        // byte weight alone is not enough to call an image decorative.
        guard let size = pixelSize(of: bytes) else { return false }
        return size.width <= dimensionThreshold && size.height <= dimensionThreshold
    }

    private static func pixelSize(of bytes: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (width: width, height: height)
    }
}
