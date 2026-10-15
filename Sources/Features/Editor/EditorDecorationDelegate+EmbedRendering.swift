import AppKit

/// What a drawn embed's attachment shows for each rendition, and the broken-image glyph a `.missing`
/// one is drawn with. Its own file because the main one sits against its length cap (plan N5,
/// Realignment 8); `embedParagraph(at:storage:)` keeps the substitution itself.
extension EditorDecorationDelegate {
    /// Sets `attachment` up for `rendition`; `run` is the embed's run as `stillSpellsAnEmbed` re-read it.
    func configure(_ attachment: EmbedAttachment, for rendition: EmbedRendition, run: String) {
        switch rendition {
        case .drawn(let image):
            attachment.image = image
            // The written size and the handle are both a *picture's* affordances, and they
            // are set in the one branch that has a picture. A `.missing` placeholder is
            // refused by the same `guard case .drawn` the hit test uses, so the paint, the
            // hit target and the drawn size cannot disagree (ADR-0019 §D8) - and a note
            // that says `![[foto.png|900]]` about a file the vault no longer has draws the
            // 28-point broken-image glyph at 28 points, not that glyph blown up to 900.
            // `natural` for this branch is the placeholder's own size, and a `written` of
            // nil is what makes `EmbedResize.resolved` hand it back untouched.
            attachment.written = EmbedResize.written(inRun: run)
            attachment.handleColor = handleColor
        case .missing:
            attachment.image = Self.missingEmbedImage
        case .pending(let name):
            // The box the picture will land in, at its written size and with no handle (ADR-0087 §D9).
            attachment.written = EmbedResize.written(inRun: run)
            attachment.placeholder = constructStyle.placeholder(named: name)
        }
        attachment.natural = attachment.image?.size ?? .zero
    }

    /// A minimal placeholder for a `.missing` embed - already decided for this slice: a
    /// file the vault does not have is drawn as broken, not left as raw syntax, which
    /// already means "still rendering" everywhere else in the delegate. `secondaryLabelColor`
    /// for the same reason `badgeColor` defaults to it: a themed tint can replace this
    /// later without this delegate gaining a dependency it does not otherwise need.
    static let missingEmbedImage: NSImage = {
        let size = NSSize(width: 28, height: 28)
        guard let symbol = NSImage(systemSymbolName: "photo.badge.exclamationmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 20, weight: .regular))
        else { return NSImage(size: size) }
        symbol.isTemplate = true
        let tinted = NSImage(size: size)
        tinted.lockFocus()
        symbol.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)
        NSColor.secondaryLabelColor.set()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        return tinted
    }()
}
