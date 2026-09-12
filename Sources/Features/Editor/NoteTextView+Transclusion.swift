import AppKit
import OSLog
import SwiftUI

/// The editor's half of a transclusion (ADR-0010 §D3): the space under the source line, and
/// what goes in it.
///
/// The two halves of the mechanism live apart on purpose. Here, on the main actor, the note
/// is read, styled and measured; the delegate that draws it cannot be `@MainActor` at all -
/// Swift 6 refuses the conformance - so it receives finished values and nothing else.
extension NoteTextView.Coordinator {
    /// Reserves the space and hands the drawing over.
    ///
    /// Called after `applyStyling`, which rewrites every attribute on each keystroke and
    /// would otherwise wipe the paragraph style this sets.
    func applyTransclusions(to textView: NSTextView, theme: Theme) {
        let occurrences = Transclusion.occurrences(in: textView.string)
        // An ordinary note pays one scan and stops here, which is the same bargain folding
        // makes.
        guard !occurrences.isEmpty || !lastRenditions.isEmpty else { return }

        let containerWidth: CGFloat
        if let container = textView.textContainer {
            containerWidth = max(0, container.size.width - container.lineFragmentPadding * 2)
        } else {
            containerWidth = textView.bounds.width
        }
        let width = TranscludedRendition.bodyWidth(inContainerOf: containerWidth)
        var renditions: [Int: TranscludedRendition] = [:]
        for occurrence in occurrences {
            guard let rendition = rendition(for: occurrence, width: width, theme: theme) else { continue }
            renditions[occurrence.lineOffset] = rendition
        }

        // Re-applied on every pass, never guarded by "has it changed": `applyStyling` runs
        // immediately before this one and rewrites *every* attribute on the note, the
        // paragraph style included. Reserving once and skipping afterwards is exactly the
        // first version of this, and it drew nothing at all - the space was bought and then
        // wiped by the next update.
        reserveSpace(in: textView, for: renditions, theme: theme)
        Logger.folding.notice(
            "transclusioni: \(occurrences.count, privacy: .public) righe, \(renditions.count, privacy: .public) rese"
        )

        guard renditions != lastRenditions else { return }
        lastRenditions = renditions
        decorations.apply(renditions: renditions)
        if let manager = textView.textLayoutManager {
            manager.invalidateLayout(for: manager.documentRange)
        }
    }

    /// The paragraph style that buys the height, set on the source line itself.
    ///
    /// Measured before it was designed (`TransclusionLayoutTests`): the reserved space lands
    /// inside that line's own layout fragment, and the note's text is not touched - an
    /// attribute is not the file, and what reaches the disk is `textView.string`.
    private func reserveSpace(
        in textView: NSTextView,
        for renditions: [Int: TranscludedRendition],
        theme: Theme
    ) {
        guard let storage = textView.textStorage else { return }
        let text = storage.string as NSString
        storage.beginEditing()
        for (offset, rendition) in renditions where offset < text.length {
            let range = text.paragraphRange(for: NSRange(location: offset, length: 0))
            // Composed onto the style already on the line, never a fresh one (ADR-0030 §D5):
            // `applyStyling` runs immediately before this and puts `font.prose`'s line-height
            // multiple on every paragraph, so overwriting the style here would buy the
            // transclusion's height at the cost of the page's own line height on that one line.
            let existing = storage.attribute(.paragraphStyle, at: offset, effectiveRange: nil)
                as? NSParagraphStyle
            let style = NSMutableParagraphStyle()
            style.setParagraphStyle(ProseTypography.paragraphStyle(theme, basedOn: existing))
            style.paragraphSpacing = rendition.reservedHeight
            storage.addAttribute(.paragraphStyle, value: style, range: range)
        }
        storage.endEditing()
    }

    /// One rendition, from the cache when the note behind it has not moved.
    ///
    /// Without the cache this would be a file read per keystroke per transclusion, which
    /// would make the editor the first thing in the app to touch the disk while typing.
    private func rendition(
        for occurrence: Transclusion.Occurrence,
        width: CGFloat,
        theme: Theme
    ) -> TranscludedRendition? {
        guard let source = parent.transclusions else { return nil }
        let key = "\(occurrence.reference)#\(occurrence.section ?? "")@\(source.generation)|\(Int(width))"
        if let cached = renditionCache[key] { return cached }

        guard let resolved = source.resolve(occurrence.reference),
              let excerpt = Transclusion.excerpt(of: resolved.text, section: occurrence.section)
        else { return nil }

        let (body, isCut) = Self.fitted(excerpt, theme: theme, width: width)
        let caption = TranscludedRendition.captionHeight
        let rendition = TranscludedRendition(
            title: occurrence.section.map { "\(resolved.title) › \($0)" } ?? resolved.title,
            reference: occurrence.reference,
            body: body,
            isCut: isCut,
            reservedHeight: TranscludedRendition.padding * 2
                + caption
                + TranscludedRendition.height(of: body, width: width)
                + (isCut ? caption : 0),
            ruleColor: NSColor(theme.color(.accentPrimary)).withAlphaComponent(0.35),
            captionColor: NSColor(theme.color(.textTertiary))
        )
        renditionCache[key] = rendition
        return rendition
    }

    /// The note cut to the cap, by lines.
    ///
    /// A binary search over the line count rather than a walk: a note is small, but a note
    /// nobody expected to be transcluded may not be, and dropping one line at a time from a
    /// four-thousand-line note would measure it four thousand times.
    private static func fitted(
        _ text: String,
        theme: Theme,
        width: CGFloat
    ) -> (body: NSAttributedString, isCut: Bool) {
        let whole = MarkdownAttributedText.attributed(text, theme: theme, links: false)
        guard TranscludedRendition.height(of: whole, width: width)
                > TranscludedRendition.maximumBodyHeight
        else { return (whole, false) }

        let lines = text.components(separatedBy: "\n")
        var low = 1
        var high = lines.count
        var best = MarkdownAttributedText.attributed(lines[0], theme: theme, links: false)
        while low <= high {
            let middle = (low + high) / 2
            let candidate = MarkdownAttributedText.attributed(
                lines.prefix(middle).joined(separator: "\n"), theme: theme, links: false
            )
            if TranscludedRendition.height(of: candidate, width: width)
                <= TranscludedRendition.maximumBodyHeight {
                best = candidate
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return (best, true)
    }

    /// Opens the note drawn under the caret's line, when a click landed on it.
    ///
    /// The fragment knows where it drew, so the hit test is a containment check against the
    /// area under the source line.
    func openTransclusion(at point: CGPoint, in textView: NSTextView) -> Bool {
        guard !lastRenditions.isEmpty else { return false }
        return decoration(in: textView) { (fragment: TranscludedLineFragment) in
            guard let rendition = fragment.rendition,
                  fragment.renditionFrame.contains(Self.inContainer(point, of: textView))
            else { return false }
            parent.onFollowLink(rendition.reference)
            return true
        }
    }

    /// Opens the section a folded heading is hiding, when the click landed on its badge
    /// (PG-021).
    ///
    /// Reports the fragment's own `headingOffset` straight to `onToggleFold`, with no
    /// `outlineRanges` lookup in between. `outlineRanges` is a snapshot taken at the last
    /// SwiftUI render, and joining it to a live layout offset by position is exactly the
    /// stale-index bug `FoldStateOrdinalIndexStalenessTests` pins: a click landing between a
    /// text change and the next render reconciling `outlineRanges` used to resolve against
    /// the wrong heading. `headingOffset` never goes stale, because it names *where in the
    /// text* the heading is rather than *which position it holds in some earlier scan*.
    func unfold(at point: CGPoint, in textView: NSTextView) -> Bool {
        guard decorations.isFolding, let onToggleFold = parent.onToggleFold else { return false }
        return decoration(in: textView) { (fragment: FoldedHeadingFragment) in
            guard fragment.badgeFrameInContainer.contains(Self.inContainer(point, of: textView))
            else { return false }
            onToggleFold(fragment.headingOffset)
            return true
        }
    }

    /// Walks the laid-out fragments of one kind and stops at the first that claims the
    /// click. Shared by every click decoration - folding, transclusion and, since
    /// ADR-0018 slice 3 Step 4, a drawn embed's own `selectEmbed(at:in:)` in
    /// `NoteTextView+EmbedCaret.swift` - because doing it twice is how they would end up
    /// disagreeing about coordinates. Not `private`: an embed's paragraph is a plain
    /// `NSTextLayoutFragment` rather than a dedicated subclass, so that caller
    /// instantiates `Fragment` as the base class itself and needs this from outside the
    /// file.
    func decoration<Fragment: NSTextLayoutFragment>(
        in textView: NSTextView,
        claimedBy claim: (Fragment) -> Bool
    ) -> Bool {
        guard let manager = textView.textLayoutManager else { return false }
        var handled = false
        let start = manager.documentRange.location
        manager.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
            guard let fragment = fragment as? Fragment, claim(fragment) else { return true }
            handled = true
            return false
        }
        return handled
    }

    /// A layout fragment's frame is in the text container's coordinates and a click arrives
    /// in the view's; between them sits `textContainerInset`, 24 by 20 here. The first
    /// version of the transclusion click compared the two directly, so the containment test
    /// could not succeed anywhere on the page. Not `private`, for the same reason as
    /// `decoration(in:claimedBy:)` above: `selectEmbed(at:in:)` needs the same
    /// conversion rather than a second one that could drift from it.
    static func inContainer(_ point: CGPoint, of textView: NSTextView) -> CGPoint {
        let origin = textView.textContainerOrigin
        return CGPoint(x: point.x - origin.x, y: point.y - origin.y)
    }
}
