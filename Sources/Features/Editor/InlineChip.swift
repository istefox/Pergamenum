import AppKit

// ADR-0087 §D5 and §D6, plan docs/plans/note-workflow-n5.md, Tasks 3 and 4 (R-36, R-42).

extension NSAttributedString.Key {
    /// Marks a run the editor draws as a pill: inline code, a highlight, a tag, a date, an inline
    /// embed's name. The value is an `InlineChip.Style`. Never written to the file.
    static let pergamenumChip = NSAttributedString.Key("pergamenumChip")
}

/// The look of one pill and how a tag or a date splits into the part read in the secondary colour and
/// the part read in the accent.
enum InlineChip {
    struct Style: Equatable {
        var background: NSColor
        var leading: NSColor? = nil
        var trailing: NSColor? = nil
        var symbolName: String? = nil
    }

    /// The room either side of a pill and the radius of its corners, from the theme's tokens
    /// (`spacing.xs`, `radius.control`). Handed to the decoration delegate as finished values, the
    /// way its faces and colours are: it is not `@MainActor` and cannot read a `Theme`.
    struct Metrics: Equatable, Sendable {
        var padding: CGFloat = 4
        var radius: CGFloat = 6
        /// The side of an embed chip's file-type symbol, the caption face's size.
        var symbol: CGFloat = 11

        init() {}

        init(_ theme: Theme) {
            padding = theme.spacing(.xs)
            radius = theme.radius(.control)
            symbol = theme.nsFont(.caption).pointSize
        }
    }

    /// How many UTF-16 units of a chip's text go in the leading colour and how many in the trailing one.
    struct Parts: Equatable, Sendable {
        var leading: Int
        var trailing: Int
    }

    /// `#client-acme-srl` is namespace and dash in the leading part and the value in the trailing one;
    /// a tag outside SPEC §4.4's pattern is the `#` only, then the accent.
    static func tagParts(_ tag: some StringProtocol) -> Parts? {
        let text = String(tag)
        guard text.hasPrefix("#"), text.utf16.count > 1 else { return nil }
        let total = text.utf16.count
        guard let parsed = Tag(text) else { return Parts(leading: 1, trailing: total - 1) }
        let leading = 1 + parsed.namespace.rawValue.utf16.count + 1
        return Parts(leading: leading, trailing: total - leading)
    }

    /// `>2026-10-14 10:30` is the `>` in the leading part and the rest in the trailing one; a bare
    /// ISO date is no chip.
    static func dateParts(_ token: some StringProtocol) -> Parts? {
        let text = String(token)
        guard text.hasPrefix(">"), CalendarDate(iso: String(text.dropFirst().prefix(10))) != nil else { return nil }
        return Parts(leading: 1, trailing: text.utf16.count - 1)
    }

    /// The two colours of a tag or a date chip over its parts, and the `.kern` room on the
    /// characters either side of it (ADR-0087 §D5): the tag's own last character, and the one before
    /// the chip when it is on the same line. Nothing is concealed on a tag or a date, so the padding
    /// cannot ride on a delimiter the way a code span's does. Called after the span's own attributes
    /// are down, so the chip's style is already on `range`; every other span is left alone.
    static func finish(_ span: MarkdownStyler.Span, _ range: NSRange, in storage: NSTextStorage, padding: CGFloat) {
        switch span {
        case .tag, .scheduled: break
        case .embedChipMarker: return finishEmbed(closingAt: range, in: storage)
        default: return
        }
        guard range.length > 0, NSMaxRange(range) <= storage.length,
              let style = storage.attribute(.pergamenumChip, at: range.location, effectiveRange: nil) as? Style,
              style.leading != nil || style.trailing != nil
        else { return }
        let source = (storage.string as NSString).substring(with: range)
        if let parts = tagParts(source) ?? dateParts(source), parts.leading + parts.trailing == range.length {
            if let leading = style.leading {
                storage.addAttribute(.foregroundColor, value: leading,
                                     range: NSRange(location: range.location, length: parts.leading))
            }
            if let trailing = style.trailing, parts.trailing > 0 {
                storage.addAttribute(.foregroundColor, value: trailing,
                                     range: NSRange(location: range.location + parts.leading, length: parts.trailing))
            }
        }
        storage.addAttribute(.kern, value: padding, range: NSRange(location: NSMaxRange(range) - 1, length: 1))
        let before = range.location - 1
        if before >= 0, let scalar = UnicodeScalar((storage.string as NSString).character(at: before)),
           !CharacterSet.newlines.contains(scalar) {
            storage.addAttribute(.kern, value: padding, range: NSRange(location: before, length: 1))
        }
    }

    /// An embed chip is one pill from its `![[` to its `]]`, the name included, with the file
    /// type's symbol (ADR-0087 §D9). Done when the closing marker is down: the opening one is the
    /// nearest `![[` before it on the same line.
    private static func finishEmbed(closingAt range: NSRange, in storage: NSTextStorage) {
        let text = storage.string as NSString
        guard range.length >= 2, NSMaxRange(range) <= text.length,
              text.substring(with: range).hasSuffix("]]"),
              let style = storage.attribute(.pergamenumChip, at: range.location, effectiveRange: nil) as? Style
        else { return }
        let line = text.lineRange(for: NSRange(location: range.location, length: 0))
        let opening = text.range(
            of: "![[", options: .backwards,
            range: NSRange(location: line.location, length: range.location - line.location)
        )
        guard opening.location != NSNotFound else { return }
        let run = NSRange(location: opening.location, length: NSMaxRange(range) - opening.location)
        let nameStart = NSMaxRange(opening)
        let name = text.substring(with: NSRange(location: nameStart, length: range.location - nameStart))
        var finished = style
        finished.symbolName = EmbedPresentation.symbolName(forTarget: name)
        storage.addAttribute(.pergamenumChip, value: finished, range: run)
    }
}
