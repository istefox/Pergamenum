import AppKit

/// Where a pill is painted: one rect per visual line the range crosses (ADR-0087 §D5). Every
/// fragment class the delegate hands back for a paragraph with pills calls `paint` before its
/// glyphs, so a pill sits behind the text of a plain line, a folded heading, a quote and a
/// callout title alike.
enum InlineChipPainter {
    /// One rect per line fragment `range` crosses, in the layout fragment's own coordinates.
    /// `range` is relative to the fragment's paragraph, the coordinate space of every line
    /// fragment's `characterRange`.
    ///
    /// The room a pill stands in is made by `.kern`, never by characters (§D5). Kern on the pill's
    /// own characters, a concealed backtick's or a tag's last character, is inside the measured
    /// run. Kern on the character before it, a tag's or a date's left room, is just outside: the
    /// rect starts `padding` further left when that character carries one.
    static func rects(for range: NSRange, in fragment: NSTextLayoutFragment, padding: CGFloat) -> [CGRect] {
        var rects: [CGRect] = []
        for line in fragment.textLineFragments {
            let crossed = NSIntersectionRange(line.characterRange, range)
            guard crossed.length > 0 else { continue }
            let text = line.attributedString
            let start = line.locationForCharacter(at: crossed.location).x
            let end = line.locationForCharacter(at: NSMaxRange(crossed)).x
            var room: CGFloat = 0
            if crossed.location == range.location, crossed.location > line.characterRange.location,
               let kern = text.attribute(.kern, at: crossed.location - 1, effectiveRange: nil) as? CGFloat, kern > 0 {
                room = padding
            }
            // The face of the run's middle character, never of its first: a concealed delimiter is
            // drawn at `collapsedFont`, which has no height to give a pill.
            let middle = min(crossed.location + crossed.length / 2, text.length - 1)
            let font = text.attribute(.font, at: middle, effectiveRange: nil) as? NSFont
                ?? .systemFont(ofSize: NSFont.systemFontSize)
            let baseline = line.typographicBounds.minY + line.glyphOrigin.y
            let inset: CGFloat = 1
            let rect = CGRect(
                x: line.typographicBounds.minX + min(start, end) - room,
                y: baseline - font.ascender - inset,
                width: abs(end - start) + room,
                height: font.ascender - font.descender + 2 * inset
            )
            if rect.width > 0, rect.height > 0 { rects.append(rect) }
        }
        return rects
    }

    /// Paints every `.pergamenumChip` run of `fragment`'s paragraph, behind the glyphs: called
    /// before `super.draw(at:in:)`.
    static func paint(
        _ fragment: NSTextLayoutFragment, at point: CGPoint, in context: CGContext, metrics: InlineChip.Metrics
    ) {
        guard let text = fragment.textLineFragments.first?.attributedString, text.length > 0 else { return }
        var pills: [(rect: CGRect, style: InlineChip.Style, isFirst: Bool)] = []
        text.enumerateAttribute(.pergamenumChip, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let style = value as? InlineChip.Style else { return }
            for (index, rect) in rects(for: range, in: fragment, padding: metrics.padding).enumerated() {
                pills.append((rect.offsetBy(dx: point.x, dy: point.y), style, index == 0))
            }
        }
        guard !pills.isEmpty else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        for pill in pills {
            let radius = min(metrics.radius, pill.rect.height / 2)
            pill.style.background.setFill()
            NSBezierPath(roundedRect: pill.rect, xRadius: radius, yRadius: radius).fill()
            if pill.isFirst, let name = pill.style.symbolName {
                drawSymbol(name, in: pill.rect, color: pill.style.leading ?? .secondaryLabelColor, metrics: metrics)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// An embed chip's file-type symbol, in the room its concealed `![[` leaves at the pill's
    /// leading edge (ADR-0087 §D9), tinted in the chip's leading colour.
    private static func drawSymbol(_ name: String, in pill: CGRect, color: NSColor, metrics: InlineChip.Metrics) {
        let configuration = NSImage.SymbolConfiguration(pointSize: metrics.symbol, weight: .regular)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: color))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        else { return }
        let side = metrics.symbol
        let scale = min(side / max(image.size.width, 1), side / max(image.size.height, 1), 1)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let frame = CGRect(
            x: pill.minX + metrics.padding / 2 + (side - size.width) / 2,
            y: pill.midY - size.height / 2, width: size.width, height: size.height
        )
        image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    /// Whether a displayed paragraph carries a pill at all, which is what earns it a chip-aware
    /// fragment rather than the standard one.
    static func carriesChips(_ text: NSAttributedString) -> Bool {
        var found = false
        text.enumerateAttribute(.pergamenumChip, in: NSRange(location: 0, length: text.length)) { value, _, stop in
            if value != nil {
                found = true
                stop.pointee = true
            }
        }
        return found
    }
}
