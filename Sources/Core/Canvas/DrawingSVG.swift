import CoreGraphics
import Foundation

/// Freehand strokes, stored as an SVG file beside the board.
///
/// JSON Canvas has no node type for ink, so SPEC §6.2 stores the strokes as an SVG
/// referenced by an ordinary `file` node: Obsidian shows it as an image and the
/// canvas stays spec-conformant. The same section requires a stroke to remain
/// editable in Pergamenum, which is why this parses its own output back rather than
/// treating the SVG as a write-only export.
struct Drawing: Equatable, Sendable {
    var strokes: [Stroke]
    /// The area the strokes occupy, used for the `viewBox` and the node's frame.
    var bounds: CGRect {
        let points = strokes.flatMap(\.points)
        guard let first = points.first else { return .zero }
        var rect = CGRect(origin: first, size: .zero)
        for point in points.dropFirst() {
            rect = rect.union(CGRect(origin: point, size: .zero))
        }
        // Half the widest stroke on each side, so a thick line is not clipped.
        let padding = (strokes.map(\.width).max() ?? 2) / 2 + 2
        return rect.insetBy(dx: -padding, dy: -padding)
    }

    struct Stroke: Equatable, Sendable, Identifiable {
        var id: String
        var points: [CGPoint]
        /// Hex colour, so a theme token can be resolved to a fixed value at draw time
        /// and the file stays readable outside the app.
        var color: String
        var width: CGFloat
        /// Highlighter strokes are drawn under the text with reduced opacity.
        var opacity: Double

        init(
            id: String = CanvasID.generate(),
            points: [CGPoint],
            color: String,
            width: CGFloat = 2,
            opacity: Double = 1
        ) {
            self.id = id
            self.points = points
            self.color = color
            self.width = width
            self.opacity = opacity
        }
    }

    static let empty = Drawing(strokes: [])
}

enum DrawingSVG {
    /// Renders the strokes as an SVG document.
    ///
    /// Coordinates are written relative to the drawing's bounds and the `viewBox`
    /// carries the offset, so the file is self-contained: an SVG whose content sits at
    /// x = -700 renders as an empty image in most viewers.
    static func encode(_ drawing: Drawing) -> String {
        let bounds = drawing.bounds
        let width = max(bounds.width, 1)
        let height = max(bounds.height, 1)

        var lines = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<svg xmlns=\"http://www.w3.org/2000/svg\" "
                + "width=\"\(number(width))\" height=\"\(number(height))\" "
                + "viewBox=\"\(number(bounds.minX)) \(number(bounds.minY)) "
                + "\(number(width)) \(number(height))\">",
            // The generator tag is how the app knows an SVG is one of its own and can
            // be reopened for editing rather than treated as an imported image.
            "  <metadata>pergamenum-drawing</metadata>",
        ]

        for stroke in drawing.strokes {
            guard !stroke.points.isEmpty else { continue }
            lines.append(
                "  <path id=\"\(stroke.id)\" d=\"\(pathData(stroke.points))\" "
                    + "fill=\"none\" stroke=\"\(stroke.color)\" "
                    + "stroke-width=\"\(number(stroke.width))\" "
                    + "stroke-opacity=\"\(number(CGFloat(stroke.opacity)))\" "
                    + "stroke-linecap=\"round\" stroke-linejoin=\"round\"/>"
            )
        }
        lines.append("</svg>")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Reads back a drawing this app wrote.
    ///
    /// Returns nil for any other SVG: an imported illustration is an image, and
    /// offering to edit its paths as if they were pen strokes would mangle it.
    static func decode(_ text: String) -> Drawing? {
        guard text.contains("pergamenum-drawing") else { return nil }

        var strokes: [Drawing.Stroke] = []
        for element in elements(named: "path", in: text) {
            guard let data = attribute("d", in: element) else { continue }
            let points = parsePathData(data)
            guard !points.isEmpty else { continue }

            strokes.append(Drawing.Stroke(
                id: attribute("id", in: element) ?? CanvasID.generate(),
                points: points,
                color: attribute("stroke", in: element) ?? "#000000",
                width: attribute("stroke-width", in: element).flatMap { CGFloat(Double($0) ?? 2) } ?? 2,
                opacity: attribute("stroke-opacity", in: element).flatMap(Double.init) ?? 1
            ))
        }
        return Drawing(strokes: strokes)
    }

    /// `M x y L x y L x y …`, the only path grammar this app writes.
    static func pathData(_ points: [CGPoint]) -> String {
        guard let first = points.first else { return "" }
        var parts = ["M \(number(first.x)) \(number(first.y))"]
        for point in points.dropFirst() {
            parts.append("L \(number(point.x)) \(number(point.y))")
        }
        return parts.joined(separator: " ")
    }

    static func parsePathData(_ data: String) -> [CGPoint] {
        var points: [CGPoint] = []
        var numbers: [CGFloat] = []

        for token in data.split(whereSeparator: { $0 == " " || $0 == "," }) {
            if let value = Double(token) {
                numbers.append(CGFloat(value))
                if numbers.count == 2 {
                    points.append(CGPoint(x: numbers[0], y: numbers[1]))
                    numbers.removeAll(keepingCapacity: true)
                }
            } else {
                // A command letter; only M and L are produced, and anything else means
                // the file is not ours, which `decode` has already established.
                numbers.removeAll(keepingCapacity: true)
            }
        }
        return points
    }

    // MARK: Minimal XML reading

    /// Self-closing elements of one name. Enough for a file this app wrote, and
    /// deliberately not a general XML parser.
    private static func elements(named name: String, in text: String) -> [String] {
        var results: [String] = []
        var cursor = text.startIndex

        while let open = text.range(of: "<\(name) ", range: cursor..<text.endIndex) {
            guard let close = text.range(of: ">", range: open.upperBound..<text.endIndex) else { break }
            results.append(String(text[open.lowerBound..<close.upperBound]))
            cursor = close.upperBound
        }
        return results
    }

    /// Reads one attribute, anchored on the space that precedes it.
    ///
    /// Without the anchor, looking for `d="` finds the `d="` inside `id="…"`, which
    /// returned the stroke id as the path data and silently dropped every stroke.
    private static func attribute(_ name: String, in element: String) -> String? {
        guard let start = element.range(of: " \(name)=\"") else { return nil }
        guard let end = element.range(of: "\"", range: start.upperBound..<element.endIndex) else { return nil }
        return String(element[start.upperBound..<end.lowerBound])
    }

    /// Trims trailing zeros so the file stays small and diffs stay readable.
    private static func number(_ value: CGFloat) -> String {
        let rounded = (value * 100).rounded() / 100
        return rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.2f", rounded)
    }

    /// File name for a new drawing, per SPEC §6.2.
    static func fileName(for date: CalendarDate, sequence: Int) -> String {
        String(format: "disegno-%@-%03d.svg", date.compactForm, sequence)
    }
}
