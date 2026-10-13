import AppKit

/// The gutter's arithmetic (ADR-0081): the band at the left of the text column that block markers
/// hang in, and the one definition of "the column" every full-width decoration reads. Pure and
/// AppKit-only, so it is tested without a window (`Tests/EditorGutterTests.swift`).
enum EditorGutter {
    /// How far one level of quote nesting steps in, as a multiple of the point size (ADR-0081 §D3;
    /// G1, 2026-10-07: 0.75 em per level).
    static let quoteStepInEms: CGFloat = 0.75

    /// The horizontal `textContainerInset` once the gutter is part of the paragraph indent
    /// (ADR-0081 §D1): `max(0, readableInset - gutter)`. The content column stays at
    /// `readableInset` wherever that is at least the gutter, and is the gutter itself below it.
    static func containerInset(readableInset: CGFloat, gutter: CGFloat) -> CGFloat {
        max(0, readableInset - gutter)
    }

    /// The column a full-width decoration draws in (ADR-0081 §D7): the leading offset and the
    /// width between the paragraph style's `headIndent` and `-tailIndent`, inside a container of
    /// `containerWidth` whose line fragments hang `padding` in from each side. A `nil` style is the
    /// whole container less its padding.
    ///
    /// `leading` is what the tests assert a drawn column against, not what a draw site adds:
    /// TextKit already places a paragraph's layout fragment at `padding + headIndent`, so a
    /// fragment's drawing origin is the column's start and its sites read only the `width`
    /// (`aFragmentStartsAtTheColumnNotAtTheContainersEdge`).
    ///
    /// `headIndent` and not `firstLineHeadIndent`: a hanging paragraph's wrapped lines are where
    /// its column starts. A positive `tailIndent` is a fixed line width measured from the leading
    /// edge, not an inset (`NSParagraphStyle.h`), and is read as no tail inset here: no editor
    /// style sets one.
    static func columnSpan(
        containerWidth: CGFloat, padding: CGFloat, style: NSParagraphStyle?
    ) -> (leading: CGFloat, width: CGFloat) {
        let head = max(0, style?.headIndent ?? 0)
        let tail = max(0, -(style?.tailIndent ?? 0))
        return (padding + head, max(0, containerWidth - 2 * padding - head - tail))
    }

    /// Where a quote's content starts at nesting `level` (ADR-0081 §D3):
    /// `gutter + quoteStepInEms * font.pointSize * level`.
    static func quoteColumn(level: Int, font: NSFont, gutter: CGFloat) -> CGFloat {
        gutter + quoteStepInEms * font.pointSize * CGFloat(max(level, 0))
    }
}

/// The measured width of a run a marker hangs by, per (run, face) (ADR-0081 §D2): a page lays out
/// the same runs (`• `, `- `, `>> `, `## `) on every layout pass, so each is measured once.
///
/// Bounded, not a few entries by nature: an ordered list adds one run per ordinal (`1. ` to
/// `999. `), a quote one per depth, and a theme change one per run in the new face, for the
/// lifetime of the view. Past `capacity` the memo is emptied and refills from what is on screen,
/// which costs one measurement per run again and nothing else.
///
/// A lock-guarded box rather than a dictionary on the delegate (the `ViewBlockHeightBox` shape,
/// ADR-0035): `EditorDecorationDelegate` is not `@MainActor` and TextKit calls it from its layout
/// pass, so a bare `nonisolated(unsafe)` dictionary would be a data race the compiler cannot see.
final class MarkerRunWidths: @unchecked Sendable {
    private struct Key: Hashable {
        let run: String
        let font: NSFont
    }

    /// How many (run, face) entries the memo holds before it starts over.
    static let capacity = 256

    private let lock = NSLock()
    private var widths: [Key: CGFloat] = [:]

    /// How many entries the memo holds now, for the tests that pin its bound.
    var count: Int { lock.withLock { widths.count } }

    func width(of run: String, in font: NSFont) -> CGFloat {
        let key = Key(run: run, font: font)
        if let known = lock.withLock({ widths[key] }) { return known }
        // Measured outside the lock: two threads measuring the same run agree, and the second
        // write stores the same number.
        let measured = (run as NSString).size(withAttributes: [.font: font]).width
        lock.withLock {
            if widths.count >= Self.capacity { widths.removeAll(keepingCapacity: true) }
            widths[key] = measured
        }
        return measured
    }
}
