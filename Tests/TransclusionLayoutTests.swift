import AppKit
import Testing

/// The one fact ADR-0010 rests on: an embed line can reserve vertical space under itself
/// without the note gaining a character.
///
/// This is a test of the SDK rather than of this app's code, and it is kept for exactly
/// that reason. ADR-0010 §D3 decides that the editor draws a transclusion under a source
/// line that stays visible, and the only evidence that this is possible at all is the
/// measurement below. If a macOS release changes it, this goes red while the decision is
/// still on paper, which is when it is cheap to revisit.
///
/// The mechanism is `NSTextContentStorageDelegate`, whose substituted paragraph may change
/// attributes but never length (`docs/20260817_TextKit2_live_editing.md`). A paragraph
/// style is an attribute, so the space is bought with one and the file is untouched.
///
/// Offscreen, and honest about it: a live `NSTextView` with a scroller and an ongoing edit
/// is a different stack, and the ADR says so in its Consequences.

private final class SpacingDelegate: NSObject, NSTextContentStorageDelegate, @unchecked Sendable {
    nonisolated(unsafe) var spacedOffset: Int?
    nonisolated(unsafe) var spacing: CGFloat = 0

    func textContentStorage(
        _ textContentStorage: NSTextContentStorage,
        textParagraphWith range: NSRange
    ) -> NSTextParagraph? {
        guard let spacedOffset, range.location == spacedOffset,
              let original = textContentStorage.textStorage?.attributedSubstring(from: range)
        else { return nil }
        let copy = NSMutableAttributedString(attributedString: original)
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = spacing
        copy.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: copy.length))
        return NSTextParagraph(attributedString: copy)
    }
}

private struct Frame {
    let offset: Int
    let frame: CGRect
}

@MainActor
private func frames(spacing: CGFloat, at spacedOffset: Int?) -> (frames: [Frame], length: Int) {
    let text = "# Titolo\ncorpo prima\n![[Altra nota]]\ncorpo dopo\nultima riga"

    let content = NSTextContentStorage()
    let layout = NSTextLayoutManager()
    content.addTextLayoutManager(layout)
    let container = NSTextContainer(size: CGSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    layout.textContainer = container

    let delegate = SpacingDelegate()
    delegate.spacedOffset = spacedOffset
    delegate.spacing = spacing
    content.delegate = delegate

    content.textStorage?.setAttributedString(
        NSAttributedString(
            string: text,
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)]
        )
    )
    layout.ensureLayout(for: layout.documentRange)

    var collected: [Frame] = []
    layout.enumerateTextLayoutFragments(from: layout.documentRange.location, options: [.ensuresLayout]) { fragment in
        let offset = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
        collected.append(Frame(offset: offset, frame: fragment.layoutFragmentFrame))
        return true
    }
    // The length is the whole point: the file must not gain a character.
    return (collected, content.textStorage?.length ?? -1)
}

@MainActor
@Suite struct TransclusionLayout {
    /// The offset of `![[Altra nota]]`, the third line of the note above.
    private static let embedOffset = ("# Titolo\ncorpo prima\n" as NSString).length
    private static let reserved: CGFloat = 200

    @Test func aSubstitutedParagraphReservesSpaceWithoutAddingACharacter() {
        let base = frames(spacing: 0, at: nil)
        let spaced = frames(spacing: Self.reserved, at: Self.embedOffset)

        // Measured 2026-08-17: 59 and 59. The whole design rests on this line.
        #expect(base.length == spaced.length)
        #expect(base.frames.count == spaced.frames.count)
    }

    @Test func theReservedSpaceBelongsToTheEmbedLinesOwnFragment() {
        let base = frames(spacing: 0, at: nil)
        let spaced = frames(spacing: Self.reserved, at: Self.embedOffset)

        // 16.0 -> 216.0. This is the half that matters: the space is inside the fragment
        // of the line that asked for it, so a custom NSTextLayoutFragment draws into its
        // own frame rather than overflowing into the next line's.
        let baseEmbed = base.frames.first { $0.offset == Self.embedOffset }?.frame
        let spacedEmbed = spaced.frames.first { $0.offset == Self.embedOffset }?.frame
        #expect(baseEmbed != nil)
        #expect(spacedEmbed?.height == (baseEmbed?.height ?? 0) + Self.reserved)
    }

    @Test func nothingAboveTheEmbedMovesAndEverythingBelowShiftsByExactlyTheReservedHeight() {
        let base = frames(spacing: 0, at: nil)
        let spaced = frames(spacing: Self.reserved, at: Self.embedOffset)

        for (before, after) in zip(base.frames, spaced.frames) {
            let expected = before.offset > Self.embedOffset
                ? before.frame.minY + Self.reserved
                : before.frame.minY
            #expect(after.frame.minY == expected)
        }
    }
}
