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
    /// `TransclusionController.apply(to:theme:scan:)`, kept here under the name `makeNSView`,
    /// `updateNSView` and `textDidChange` call (ADR-0074 §D5). The scan is the one-shot the styling
    /// pass before it left (ADR-0091 §D7); a call with no styling before it scans the whole note.
    func applyTransclusions(to textView: NSTextView, theme: Theme) {
        transclusion.apply(to: textView, theme: theme, scan: takeTransclusionScan())
    }

    /// `TransclusionController.open(at:in:)`, kept here under the name `wire(_:to:)`'s click
    /// closure calls (ADR-0074 §D5).
    func openTransclusion(at point: CGPoint, in textView: NSTextView) -> Bool {
        transclusion.open(at: point, in: textView)
    }

    /// Opens the section a folded heading is hiding, when the click landed on its badge
    /// (PG-021).
    ///
    /// Reports the fragment's own `headingOffset` straight to `onToggleFold`, with no ordinal
    /// lookup in between, not even in the outline store (`outlineStore(for:)`). Joining an
    /// ordinal to a live layout offset by position is the stale-index bug
    /// `FoldStateOrdinalIndexStalenessTests` pins: when the editor took the outline as ranges per
    /// render, a click between a text change and the next render hit the wrong heading.
    /// `headingOffset` never goes stale, because it names *where in the text* the heading is
    /// rather than *which position it holds in some earlier scan*.
    func unfold(at point: CGPoint, in textView: NSTextView) -> Bool {
        guard decorations.isFolding, let onToggleFold = parent.outline.onToggleFold else { return false }
        return Self.decoration(in: textView) { (fragment: FoldedHeadingFragment) in
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
    static func decoration<Fragment: NSTextLayoutFragment>(
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

// MARK: - The controller (ADR-0074 §D2/§D3)

/// The transclusion pass's state: the renditions drawn and the cache they come from, and
/// opening one on a click. `unfold` stays a Coordinator extension above: it owns no state.
@MainActor
final class TransclusionController {
    /// Read when a pass runs or a click lands, never captured earlier (ADR-0074 §D3):
    /// `vault.transclusions` per rendition, `onFollowLink` on the click.
    private let parent: () -> NoteTextView?
    private let decorations: EditorDecorationDelegate
    /// The layout record; its door is the one way this pass invalidates the layout (ADR-0093 §D3).
    private let layoutDebt: LayoutDebt

    /// The transcluded notes already drawn, so an unchanged set does not invalidate the
    /// layout on every view update.
    private(set) var lastRenditions: [Int: TranscludedRendition] = [:]
    /// Renditions by reference, section, index generation and width. Not unbounded in
    /// practice: a note names as many targets as it names, and the entries of an older
    /// generation are dropped when `renditionGeneration` moves.
    private(set) var renditionCache: [String: TranscludedRendition] = [:]
    /// The generation `renditionCache` was filled at. The index generation moves on every
    /// save, this note's own included (PG-328), so keeping older generations would grow
    /// the cache by one entry per transclusion per save.
    private(set) var renditionGeneration: Int?
    /// The range the last transclusion scan covered, or nil when it was the whole note (ADR-0091
    /// §D7). Read by `TransclusionScopeTests`.
    private(set) var lastScannedRange: NSRange?
    /// Every transclusion line the scans found, by line offset, shifted with the text: what a ranged
    /// scan merges into, and what a changed index generation resolves again without a scan.
    private var occurrences: [Int: Transclusion.Occurrence] = [:]
    /// The paragraph style each reserved line carried before its reservation, by line offset: what
    /// a line outside a ranged restyle is composed onto again, or gets back when its note stops
    /// resolving (ADR-0091 §D7).
    private var unreserved: [Int: NSParagraphStyle] = [:]

    init(parent: @escaping () -> NoteTextView?, decorations: EditorDecorationDelegate, layout: LayoutDebt) {
        self.parent = parent
        self.decorations = decorations
        layoutDebt = layout
    }

    /// What the styling pass before this one restyled, and so what this one scans (ADR-0091 §D7).
    enum Scan: Equatable {
        /// The whole note: a full restyle, or a call with no styling before it.
        case whole
        /// Only this range: the incremental restyle's dirty range.
        case range(NSRange)
        /// Nothing: the styling was skipped because nothing changed since the last one.
        case none

        /// What a pass still owes once a styling adds `later` to a scan not yet taken: a skip adds
        /// nothing, and two ranges, which may lie in two different texts, add up to the whole note.
        func then(_ later: Scan) -> Scan {
            switch (self, later) {
            case (.whole, _), (_, .whole): .whole
            case (.none, _): later
            case (_, .none): self
            case (.range, .range): .whole
            }
        }
    }

    /// Reserves the space and hands the drawing over.
    ///
    /// Called after `applyStyling`, which rewrites every attribute on each keystroke and
    /// would otherwise wipe the paragraph style this sets. `scan` follows what that styling
    /// rewrote (ADR-0091 §D7): the whole note, the dirty range, whose occurrences are merged into
    /// the shifted table, or nothing. A changed index generation resolves every occurrence again
    /// from the table, without reading the text.
    func apply(to textView: NSTextView, theme: Theme, scan: Scan = .whole) {
        let generationMoved = parent()?.vault.transclusions?.generation != renditionGeneration
        guard let resolving = scanOccurrences(scan, in: textView.string, moved: generationMoved) else { return }
        // An ordinary note pays one scan and stops here, which is the same bargain folding
        // makes.
        guard !occurrences.isEmpty || !lastRenditions.isEmpty else { return }

        // What the styling before this pass rewrote: nil for the whole note.
        let restyled: NSRange? = switch scan {
        case .whole: nil
        case .range(let dirty): dirty
        case .none: NSRange(location: 0, length: 0)
        }
        // A ranged pass keeps the renditions outside its range, which the shift moved, unless the
        // generation moved under all of them.
        var renditions: [Int: TranscludedRendition] = [:]
        if let restyled, !generationMoved {
            renditions = lastRenditions.filter { !NSLocationInRange($0.key, restyled) }
        }
        var resolved: [Int: TranscludedRendition] = [:]
        for occurrence in resolving {
            let width = TranscludedRendition.bodyWidth(
                inContainerOf: columnWidth(at: occurrence.lineOffset, in: textView, theme: theme)
            )
            guard let rendition = rendition(for: occurrence, width: width, theme: theme) else { continue }
            resolved[occurrence.lineOffset] = rendition
        }
        renditions.merge(resolved) { _, new in new }

        // Re-applied on every pass that restyled the lines, never guarded by "has it changed":
        // `applyStyling` runs immediately before this one and rewrites every attribute of what it
        // restyled, the paragraph style included. Reserving once and skipping afterwards is
        // exactly the first version of this, and it drew nothing at all - the space was bought
        // and then wiped by the next update. A line outside a ranged restyle kept its style, and
        // its reservation with it.
        reserveSpace(in: textView, for: resolved, theme: theme, restyled: restyled)
        if let restyled {
            // A line nothing restyled whose note no longer resolves gives its reservation back.
            let lost = lastRenditions.keys.filter { renditions[$0] == nil && !NSLocationInRange($0, restyled) }
            releaseSpace(in: textView, at: lost)
        }
        let lines = occurrences.count
        Logger.folding.debug(
            "transclusioni: \(lines, privacy: .public) righe, \(renditions.count, privacy: .public) rese"
        )

        guard renditions != lastRenditions else { return }
        lastRenditions = renditions
        decorations.apply(renditions: renditions)
        layoutDebt.invalidateWholeDocument(of: textView)
    }

    /// Scans what `scan` names into the occurrence table and answers the occurrences to resolve,
    /// or nil when there is nothing to do: a skipped styling under an unchanged generation. `moved`
    /// says the index generation moved, so every occurrence resolves again.
    private func scanOccurrences(_ scan: Scan, in text: String, moved: Bool) -> [Transclusion.Occurrence]? {
        switch scan {
        case .whole:
            let found = Transclusion.occurrences(in: text)
            occurrences = Dictionary(found.map { ($0.lineOffset, $0) }) { _, last in last }
            lastScannedRange = nil
            return found
        case .range(let dirty):
            let fragment = (text as NSString).substring(with: dirty)
            let found = Transclusion.occurrences(inFragment: fragment, offset: dirty.location)
            occurrences = occurrences.filter { !NSLocationInRange($0.key, dirty) }
            for occurrence in found { occurrences[occurrence.lineOffset] = occurrence }
            lastScannedRange = dirty
            return moved ? Array(occurrences.values) : found
        case .none:
            return moved ? Array(occurrences.values) : nil
        }
    }

    /// The width of the column `TranscludedLineFragment` draws the line at `offset` in (ADR-0081
    /// §D7): the container less its padding and the indents of that line's own paragraph style,
    /// read from the storage `applyStyling` has just written, so the reserved height is measured
    /// at the width the fragment draws at. The page's base style only when the line carries no
    /// style at all, built then and not on every pass.
    private func columnWidth(at offset: Int, in textView: NSTextView, theme: Theme) -> CGFloat {
        guard let container = textView.textContainer else { return textView.bounds.width }
        let storage = textView.textStorage
        let own = offset < (storage?.length ?? 0)
            ? storage?.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle
            : nil
        let style = own ?? {
            let base = MarkdownAttributedText.base(theme: theme, gutter: theme.spacing(.gutter))
            return base[.paragraphStyle] as? NSParagraphStyle
        }()
        return EditorGutter.columnSpan(
            containerWidth: container.size.width, padding: container.lineFragmentPadding, style: style
        ).width
    }

    /// The paragraph style that buys the height, set on the source line itself.
    ///
    /// Measured before it was designed (`TransclusionLayoutTests`): the reserved space lands
    /// inside that line's own layout fragment, and the note's text is not touched - an
    /// attribute is not the file, and what reaches the disk is `textView.string`.
    ///
    /// `restyled` is what the styling before this pass rewrote, nil for the whole note (ADR-0091
    /// §D7). A line it rewrote carries the styling's own paragraph style, which is recorded before
    /// the reservation goes on; a line it did not still carries its old reservation, so the style
    /// recorded for it then is the one composed onto.
    private func reserveSpace(
        in textView: NSTextView,
        for renditions: [Int: TranscludedRendition],
        theme: Theme,
        restyled: NSRange? = nil
    ) {
        guard let storage = textView.textStorage else { return }
        let text = storage.string as NSString
        if let restyled {
            unreserved = unreserved.filter { !NSLocationInRange($0.key, restyled) }
        } else {
            unreserved = [:]
        }
        storage.beginEditing()
        for (offset, rendition) in renditions where offset < text.length {
            let range = text.paragraphRange(for: NSRange(location: offset, length: 0))
            // Composed onto the style already on the line, never a fresh one (ADR-0030 §D5):
            // `applyStyling` runs immediately before this and puts `font.prose`'s line-height
            // multiple on every paragraph, so overwriting the style here would buy the
            // transclusion's height at the cost of the page's own line height on that one line.
            let current = storage.attribute(.paragraphStyle, at: offset, effectiveRange: nil)
                as? NSParagraphStyle
            let existing = unreserved[offset] ?? current
            if let existing { unreserved[offset] = existing }
            let style = NSMutableParagraphStyle()
            style.setParagraphStyle(ProseTypography.paragraphStyle(theme, basedOn: existing))
            style.paragraphSpacing = rendition.reservedHeight
            storage.addAttribute(.paragraphStyle, value: style, range: range)
        }
        storage.endEditing()
    }

    /// Puts back the style each of `offsets` carried before its reservation: the lines a skipped or
    /// ranged pass did not restyle, whose note stopped resolving when the index generation moved.
    private func releaseSpace(in textView: NSTextView, at offsets: [Int]) {
        guard !offsets.isEmpty, let storage = textView.textStorage else { return }
        let text = storage.string as NSString
        storage.beginEditing()
        for offset in offsets where offset < text.length {
            guard let style = unreserved.removeValue(forKey: offset) else { continue }
            let range = text.paragraphRange(for: NSRange(location: offset, length: 0))
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
        guard let source = parent()?.vault.transclusions else { return nil }
        if renditionGeneration != source.generation {
            renditionCache.removeAll()
            renditionGeneration = source.generation
        }
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
    func open(at point: CGPoint, in textView: NSTextView) -> Bool {
        guard !lastRenditions.isEmpty else { return false }
        return NoteTextView.Coordinator.decoration(in: textView) { (fragment: TranscludedLineFragment) in
            guard let rendition = fragment.rendition,
                  fragment.renditionFrame.contains(NoteTextView.Coordinator.inContainer(point, of: textView))
            else { return false }
            parent()?.onFollowLink(rendition.reference)
            return true
        }
    }
}

extension TransclusionController {
    /// Re-keys the renditions, the occurrences and the recorded styles past `edit` (ADR-0091 §D6).
    /// The delegate's copy of the renditions moves with `EditorDecorationDelegate.shift(by:)`.
    func shift(by edit: StorageEdit) {
        lastRenditions = edit.shiftedKeys(lastRenditions)
        unreserved = edit.shiftedKeys(unreserved)
        occurrences = edit.shiftedKeys(occurrences)
        for (offset, occurrence) in occurrences where occurrence.lineOffset != offset {
            occurrences[offset]?.lineOffset = offset
        }
    }
}
