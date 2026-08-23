import AppKit

/// The rectangle drawn while a drawn embed is being dragged to a new size (ADR-0019 "A
/// drawn embed is resized by dragging it, and the size is written into the note", §D7:
/// "nothing is written until `mouseUp`"). Plan
/// `docs/superpowers/plans/2026-08-23-ridimensionamento-maniglie-embed-editor.md`, Task 6.
///
/// A subview of the text view itself and not of the scroll view, so it scrolls with the
/// text for free. It is added at `.began`, its frame is rewritten at every `.moved` and it
/// is removed at `.ended` - all three from `NoteTextView+EmbedResize.swift`, which owns the
/// gesture; this file owns nothing but the drawing.
///
/// **What it cannot do is the whole of why a drag costs nothing per frame** (§D7):
/// `NSTextStorage` is never touched here, the layout is never invalidated and
/// `ThumbnailStore` is never called. R-02's "the source text does not change during the
/// drag" is a property of this view having no way to change it rather than a rule somebody
/// has to keep.
///
/// It is paint and never a responder: `hitTest(_:)` answers nil, so every `mouseDragged`
/// goes on reaching the text view underneath even while the pointer sits over the
/// rectangle it is dragging.
final class EmbedResizeOverlay: NSView {
    /// The colours and the face this view draws with, handed over at construction from
    /// `parent.theme` - the same shape `TranscludedRendition` receives `ruleColor` and
    /// `captionColor` in (`NoteTextView+Transclusion.swift`), and for the same reason: a
    /// view that takes a colour without a token does not pass review, and this one is
    /// built by a `Coordinator` that has the theme rather than reaching for a global.
    ///
    /// One struct rather than five parameters, which is also what keeps `init` inside the
    /// parameter count SwiftLint caps this project at.
    struct Style {
        /// The pending rectangle's own border.
        var border: NSColor
        /// The `W × H` readout, and the pill it is drawn on so that it stays legible over
        /// an arbitrary photograph.
        var label: NSColor
        var labelBackground: NSColor
        var font: NSFont
        var cornerRadius: CGFloat
    }

    private let style: Style

    /// The border's own width and the padding around the readout. Constants rather than
    /// tokens, the company `EmbedResize.minimumSide` already keeps: a hairline is
    /// geometry, not a colour.
    private static let lineWidth: CGFloat = 1.5
    private static let labelPadding = NSSize(width: 6, height: 2)

    init(frame: CGRect, style: Style) {
        self.style = style
        super.init(frame: frame)
    }

    /// Never loaded from a nib - this view exists for the length of one drag and is built
    /// by hand each time - so the required initialiser answers nil rather than carrying a
    /// second, styleless construction path nothing would keep current.
    required init?(coder: NSCoder) { nil }

    /// The text view above is flipped, and so is this, so that `frame.origin` means the
    /// picture's top-left corner in both and the two never have to be reconciled.
    override var isFlipped: Bool { true }

    /// Paint, never a responder (§D7). Answering nil here is what keeps the gesture
    /// working at all: the pointer spends the whole drag *inside* this rectangle, and a
    /// view that accepted the hit would take `mouseDragged` away from the text view whose
    /// `mouseDown` started the drag.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// A resize is a size change on every frame, and AppKit does not redraw a view for
    /// one by itself - without this the rectangle would keep the readout it was born with
    /// all the way through the drag.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let border = bounds.insetBy(dx: Self.lineWidth / 2, dy: Self.lineWidth / 2)
        guard border.width > 0, border.height > 0 else { return }
        style.border.setStroke()
        let path = NSBezierPath(
            roundedRect: border, xRadius: style.cornerRadius, yRadius: style.cornerRadius
        )
        path.lineWidth = Self.lineWidth
        path.stroke()
        drawLabel()
    }

    /// The pending size as `W × H`, on a pill at the rectangle's own middle.
    ///
    /// Rounded to whole points because whole points are what the commit writes:
    /// `EmbedResize.suffix(for:natural:)` formats integers (§D7), and a readout saying
    /// `301` for a note that ends up carrying `300` would be a readout of something else.
    private func drawLabel() {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: style.font,
            .foregroundColor: style.label,
        ]
        let text = "\(Int(bounds.width.rounded())) × \(Int(bounds.height.rounded()))" as NSString
        let size = text.size(withAttributes: attributes)
        let pill = CGRect(
            x: bounds.midX - size.width / 2 - Self.labelPadding.width,
            y: bounds.midY - size.height / 2 - Self.labelPadding.height,
            width: size.width + Self.labelPadding.width * 2,
            height: size.height + Self.labelPadding.height * 2
        )
        // A rectangle too small to hold its own readout gets none rather than a clipped
        // one. `EmbedResize.minimumSide` makes that hard to reach rather than impossible:
        // the face comes from the theme, and a theme is free to set `font.caption` large.
        guard bounds.contains(pill) else { return }
        style.labelBackground.setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        text.draw(
            at: CGPoint(x: pill.minX + Self.labelPadding.width, y: pill.minY + Self.labelPadding.height),
            withAttributes: attributes
        )
    }
}
