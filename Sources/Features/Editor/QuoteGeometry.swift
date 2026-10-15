import CoreGraphics

/// Where a quoted paragraph's content and its bars sit (ADR-0087 §D7), measured from the column a
/// paragraph starts at. Not a second geometry: the indent is the part of
/// `EditorGutter.quoteColumn(level:font:gutter:)` past the gutter, `step` being
/// `EditorGutter.quoteStepInEms` of the prose size, and the reading view reads the same two numbers.
enum QuoteGeometry {
    /// How far a quote of `level` indents its content: one step per level.
    static func indent(level: Int, step: CGFloat) -> CGFloat {
        step * CGFloat(max(level, 0))
    }

    /// Where each level's bar starts, one per level, increasing: a third of a step into that level's
    /// own step, so a bar never touches the content after it.
    static func barOffsets(level: Int, step: CGFloat) -> [CGFloat] {
        (0..<max(level, 0)).map { step * CGFloat($0) + step / 3 }
    }

    /// A bar's width, in the editor and the reading view alike.
    static let barWidth: CGFloat = 2
}
