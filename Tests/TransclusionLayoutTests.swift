import AppKit
import Testing
@testable import Pergamenum

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

/// Which way the space is bought.
///
/// `delegate` is what the probe used and what the SDK documents for a *displayed* paragraph
/// that must differ from the stored one. `storage` is the shortcut this editor can take,
/// and only because of a fact about this app: `applyStyling` already rewrites every
/// attribute of the text storage on each keystroke, and an attribute is not the file - what
/// is written to disk is `textView.string`. Asserted rather than assumed.
private enum Route { case delegate, storage }

@MainActor
private func frames(
    spacing: CGFloat,
    at spacedOffset: Int?,
    by route: Route = .delegate
) -> (frames: [Frame], length: Int) {
    let text = "# Titolo\ncorpo prima\n![[Altra nota]]\ncorpo dopo\nultima riga"

    let content = NSTextContentStorage()
    let layout = NSTextLayoutManager()
    content.addTextLayoutManager(layout)
    let container = NSTextContainer(size: CGSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    layout.textContainer = container

    let delegate = SpacingDelegate()
    if route == .delegate {
        delegate.spacedOffset = spacedOffset
        delegate.spacing = spacing
        content.delegate = delegate
    }

    content.textStorage?.setAttributedString(
        NSAttributedString(
            string: text,
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)]
        )
    )
    if route == .storage, let spacedOffset, let storage = content.textStorage {
        let line = (storage.string as NSString).paragraphRange(for: NSRange(location: spacedOffset, length: 0))
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = spacing
        storage.addAttribute(.paragraphStyle, value: style, range: line)
    }
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

    /// The same three facts, bought from the text storage instead of from the delegate.
    ///
    /// This is the route the editor takes (ADR-0010 §D3's slice): the paragraph style goes
    /// where the colours and the fonts already go, and the content storage delegate stays
    /// free for folding. It was an assumption until this test, and an assumption about an
    /// SDK is the kind this project does not spend.
    @Test func theSpaceCanBeBoughtFromTheTextStorageToo() {
        let base = frames(spacing: 0, at: nil, by: .storage)
        let spaced = frames(spacing: Self.reserved, at: Self.embedOffset, by: .storage)

        #expect(base.length == spaced.length)
        let baseEmbed = base.frames.first { $0.offset == Self.embedOffset }?.frame
        let spacedEmbed = spaced.frames.first { $0.offset == Self.embedOffset }?.frame
        #expect(spacedEmbed?.height == (baseEmbed?.height ?? 0) + Self.reserved)
        for (before, after) in zip(base.frames, spaced.frames) where before.offset > Self.embedOffset {
            #expect(after.frame.minY == before.frame.minY + Self.reserved)
        }
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

    // ADR-0030 §D5, plan 2026-09-04-editor-page-typography-noteplan, Task 3 (R-07).
    //
    // The composition regression `reserveSpace` (`NoteTextView+Transclusion.swift:54-68`) has
    // to satisfy once the coder changes it to build its style as a mutable copy of the style
    // already on the line, rather than a fresh `NSMutableParagraphStyle()`: the reserved
    // height and the page's own line-height multiple must both survive on the same source
    // line. `reserveSpace` is `private` and unreachable from this file, so - matching this
    // file's own idiom of recreating the SDK mechanism rather than calling into the app's
    // private internals - this builds the storage through the real, public
    // `MarkdownAttributedText.base(theme:)` (the actual production entry point this task adds
    // a `.paragraphStyle` to) and then performs the same "mutable copy of what's already
    // there" step `reserveSpace` is being asked to perform. What is genuinely under test is
    // `base(theme:)`'s own output: today it carries no `.paragraphStyle` at all, so `existing`
    // below is `nil`, the copy starts from a fresh style with `lineHeightMultiple == 0`, and
    // this goes red on that comparison alone - not on anything this test invents itself.
    //
    // Leaves the existing fixture (`frames(...)`, `:78`'s explicit monospaced 13pt font)
    // untouched, per the plan.
    @Test func theSourceLinesReservedSpaceKeepsTheProseLineHeightToo() throws {
        let theme = Theme.emergency
        let reserved: CGFloat = 200
        let text = "![[Altra nota]]\n"
        let storage = NSTextStorage(string: text, attributes: MarkdownAttributedText.base(theme: theme))

        let existing = storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let mutable = (existing?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        mutable.paragraphSpacing = reserved
        let wholeRange = NSRange(location: 0, length: (text as NSString).length)
        storage.addAttribute(.paragraphStyle, value: mutable, range: wholeRange)

        let result = try #require(storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(result.paragraphSpacing == reserved)
        #expect(
            result.lineHeightMultiple == ProseTypography.paragraphStyle(theme).lineHeightMultiple,
            "R-07: reserving the transclusion's height must not drop the page's own line height"
        )
    }
}
