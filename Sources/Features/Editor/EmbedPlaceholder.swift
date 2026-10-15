import AppKit

/// The size an embed reserves before its thumbnail loads, and the box drawn in it (ADR-0087 §D9):
/// the written `|W` or `|WxH`, else a default, so the page does not jump when the picture lands.
enum EmbedPlaceholder {
    /// The size reserved for an embed with no written size: the width an unsized embed is rendered
    /// at (`EmbedTable.renderWidth`), at 16:9. The column clamps it, as it clamps the picture.
    static let defaultSize = CGSize(width: EmbedTable.renderWidth, height: EmbedTable.renderWidth * 9 / 16)

    /// The reserved size in a column `column` wide: `EmbedResize`'s own answer, unaltered, for no size,
    /// a width and a `WxH` alike, so a `|300` placeholder is as wide as the picture it holds the place of
    /// and a `|900x300` one is as tall as the picture will be (ADR-0019 §D3 leaves a written height free
    /// of the column and of the ratio). Any rule of its own here would make the line jump when the
    /// thumbnail lands.
    static func size(written: EmbedResize.Written?, column: CGFloat) -> CGSize {
        EmbedResize.resolved(written: written, natural: defaultSize, column: column)
    }

    /// What the delegate hands the attachment: the file's name, the two colours and the font, finished
    /// values read from the theme by the styling pass (`EditorConstructStyle`), never a `Theme` here.
    struct Look: Equatable {
        var name: String
        /// `color.surface.sunken`.
        var fill: NSColor
        /// `color.text.tertiary`.
        var text: NSColor
        /// `font.caption`.
        var font: NSFont
        var radius: CGFloat
    }

    /// A rounded box of `size` in `look.fill` with the file name centred in `look.text`.
    static func image(of look: Look, size: CGSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            look.fill.setFill()
            NSBezierPath(roundedRect: rect, xRadius: look.radius, yRadius: look.radius).fill()
            let name = NSAttributedString(string: look.name, attributes: [
                .font: look.font,
                .foregroundColor: look.text,
            ])
            let measured = name.size()
            let width = min(measured.width, max(0, rect.width - 16))
            name.draw(with: CGRect(
                x: rect.midX - width / 2, y: rect.midY - measured.height / 2, width: width, height: measured.height
            ), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            return true
        }
    }
}
