import AppKit
import PDFKit
import Testing
@testable import Pergamenum

// ADR-0018 §D6 probe 6, offscreen: whether an `NSTextAttachment` can sit on one character
// of a length-preserved, thirteen-character run inside a *substituted* paragraph - the
// same paragraph-substitution hook `EditorDecorationDelegate` already uses for headings
// and emphasis (`Tests/MarkupHidingTests.swift`) - and be drawn once, growing the line the
// way a picture should. Two independent answers, one per content type named by D3: an
// `NSImage` and a PDF's first page rendered the exact way `ThumbnailStore.renderPDF`
// already renders one for the Workspace card.
//
// The probe's first, unplanned finding, measured before the other five below could mean
// anything: D3's own wording - "applied to one character of the run" - reads as keeping
// the character and adding `.attachment` over it, and that reading is never recognised by
// TextKit 2 at all (`anAttachmentAttributeAloneOverTheKeptCharacterIsNeverRecognised`).
// What does work, still inside the same length-preserving constraint, is a one-for-one
// substitution: the *displayed* copy's character becomes `NSAttachmentCharacter` (U+FFFC)
// while the real backing store keeps "!" (or whatever the wikilink's own character was)
// untouched. Every test from the image one onward measures that mechanism, not the literal
// one D3 describes - a finding for whoever plans slice 3's actual delegate growth, not a
// silent substitution of the question.
//
// The delegate that substitutes the paragraph here is local to this file rather than a
// growth of `EditorDecorationDelegate`: the probe exists to decide whether that growth is
// even the right shape (D3's own fallback clause), so writing it into the production
// delegate before the question is answered would answer it by assuming it. Slice 3's own
// implementation, once planned, is what moves this mechanism there - or replaces it with
// the custom-fragment fallback, per content type.
//
// Four sub-questions the plan asked this probe to answer empirically, each named at its
// test below rather than only here: whether the attachment character also paints its own
// glyph, whether `attachmentBoundsForAttributes:...` is actually consulted for a
// substituted paragraph, whether a 0.01pt trailing newline still breaks the line, and
// whether `NSTextView.isRichText = false` (`NoteTextView.swift:98`) gets in the way.
//
// Extended for ADR-0019 D8 probe 1 (plan
// `docs/superpowers/plans/2026-08-23-ridimensionamento-maniglie-embed-editor.md`, Task 1):
// probe 6 above measured that `attachmentBounds(...)` *fires*; it never measured that a
// returned rect different from `image.size` is honoured. `LoggingAttachment.forcedBounds`
// stands in for `EmbedAttachment.attachmentBounds` answering
// `EmbedResize.resolved(written:natural:column:)` before either type exists, checked one
// content type at a time (R-01, R-09).

// MARK: - The instrument under test, local to the probe

/// Counts every call TextKit 2 makes to size and to paint the attachment, which is how
/// sub-questions 1 and 2 get an actual number rather than a guess.
private final class LoggingAttachment: NSTextAttachment, @unchecked Sendable {
    nonisolated(unsafe) private(set) var boundsQueries = 0
    nonisolated(unsafe) private(set) var imageQueries = 0
    /// ADR-0019 D8 probe 1: when set, `attachmentBounds(...)` answers this rect instead of
    /// asking `super`, standing in for `EmbedAttachment.attachmentBounds` answering
    /// `EmbedResize.resolved(written:natural:column:)` before that type exists.
    nonisolated(unsafe) var forcedBounds: CGSize?
    /// The bounds probe 1's second half checks: the same non-default rect must reach the
    /// paint call, not only the layout one.
    nonisolated(unsafe) private(set) var lastImageBounds: CGRect?

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        boundsQueries += 1
        if let forcedBounds {
            return CGRect(origin: .zero, size: forcedBounds)
        }
        return super.attachmentBounds(
            for: attributes, location: location, textContainer: textContainer,
            proposedLineFragment: proposedLineFragment, position: position
        )
    }

    override func image(
        for bounds: CGRect,
        attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?
    ) -> NSImage? {
        imageQueries += 1
        lastImageBounds = bounds
        return super.image(for: bounds, attributes: attributes, location: location, textContainer: textContainer)
    }
}

/// A stand-in for the paragraph-substitution half of the future `EditorDecorationDelegate`
/// growth (ADR-0018 §D3): the same shape as `textContentStorage(_:textParagraphWith:)`, but
/// parameterised over exactly what probe 6 needs to vary rather than reading a table.
private final class AttachmentProbeDelegate: NSObject, NSTextContentStorageDelegate, @unchecked Sendable {
    let paragraphRange: NSRange
    let attachmentOffset: Int
    let attachment: NSTextAttachment
    let collapsedRange: NSRange
    /// Extra attributes on the attachment character itself, beyond `.attachment` - what
    /// sub-question 1 needs to add and remove.
    let attachmentCharacterAttributes: [NSAttributedString.Key: Any]
    /// Whether the *displayed* character at `attachmentOffset` is swapped for
    /// `NSAttachmentCharacter` (U+FFFC) in the substituted copy, leaving the real storage
    /// untouched - a second, harder question the first result in this file raised rather
    /// than one the plan asked for: D1's own framing is "the display may differ from the
    /// storage in attributes and never in length", silent on whether the *character* may
    /// also differ as long as the length does not move. Still a one-for-one substitution,
    /// never an insertion, so `NSTextContentManager.h:120`'s constraint holds either way.
    let usesObjectReplacementCharacter: Bool

    init(
        paragraphRange: NSRange,
        attachmentOffset: Int,
        attachment: NSTextAttachment,
        collapsedRange: NSRange,
        attachmentCharacterAttributes: [NSAttributedString.Key: Any] = [:],
        usesObjectReplacementCharacter: Bool = false
    ) {
        self.paragraphRange = paragraphRange
        self.attachmentOffset = attachmentOffset
        self.attachment = attachment
        self.collapsedRange = collapsedRange
        self.attachmentCharacterAttributes = attachmentCharacterAttributes
        self.usesObjectReplacementCharacter = usesObjectReplacementCharacter
    }

    func textContentStorage(
        _ textContentStorage: NSTextContentStorage, textParagraphWith range: NSRange
    ) -> NSTextParagraph? {
        guard range == paragraphRange, let storage = textContentStorage.textStorage else { return nil }
        let copy = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        let attachmentRange = NSRange(location: attachmentOffset, length: 1)
        if usesObjectReplacementCharacter {
            // A substitution, not an insertion: one character out, one in, `range.length`
            // unmoved. `replaceCharacters` drops the attributes at that index, so the
            // attachment (and any extra attribute) is (re-)applied straight after.
            copy.replaceCharacters(in: attachmentRange, with: "\u{FFFC}")
        }
        copy.addAttribute(.attachment, value: attachment, range: attachmentRange)
        for (key, value) in attachmentCharacterAttributes {
            copy.addAttribute(key, value: value, range: attachmentRange)
        }
        if collapsedRange.length > 0 {
            copy.addAttribute(.font, value: EditorDecorationDelegate.collapsedFont, range: collapsedRange)
        }
        return NSTextParagraph(attributedString: copy)
    }
}

// MARK: - Fixtures

@MainActor
private func syntheticImage(_ color: NSColor, size: CGSize = CGSize(width: 64, height: 48)) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()
    color.setFill()
    NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
    image.unlockFocus()
    return image
}

/// The exact call `ThumbnailStore.renderPDF` makes on a document's first page
/// (`Sources/Vault/ThumbnailStore.swift`), replicated here on a one-page PDF built from a
/// synthetic image rather than a file on disk - there is no fixture PDF in this suite yet
/// and this probe needs no more than one page.
@MainActor
private func syntheticPDFFirstPageThumbnail(_ color: NSColor, width: CGFloat = 96) -> NSImage? {
    guard let sourcePage = PDFPage(image: syntheticImage(color, size: CGSize(width: 200, height: 140))) else {
        return nil
    }
    let document = PDFDocument()
    document.insert(sourcePage, at: 0)
    guard let page = document.page(at: 0) else { return nil }
    let pageSize = page.bounds(for: .mediaBox).size
    guard pageSize.width > 0 else { return nil }
    let scale = width / pageSize.width
    let target = CGSize(width: width, height: max(1, pageSize.height * scale))
    return page.thumbnail(of: target, for: .mediaBox)
}

// MARK: - The offscreen stack

private struct Fragment {
    let offset: Int
    let layout: NSTextLayoutFragment
}

@MainActor
private func layoutFragments(
    text: String, delegate: NSTextContentStorageDelegate?
) -> (fragments: [Fragment], length: Int) {
    let content = NSTextContentStorage()
    let layout = NSTextLayoutManager()
    content.addTextLayoutManager(layout)
    let container = NSTextContainer(size: CGSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    layout.textContainer = container
    content.delegate = delegate

    content.textStorage?.setAttributedString(
        NSAttributedString(
            string: text,
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)]
        )
    )
    layout.ensureLayout(for: layout.documentRange)

    var collected: [Fragment] = []
    layout.enumerateTextLayoutFragments(from: layout.documentRange.location, options: [.ensuresLayout]) { fragment in
        let offset = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
        collected.append(Fragment(offset: offset, layout: fragment))
        return true
    }
    return (collected, content.textStorage?.length ?? -1)
}

/// Renders a fragment alone into a white-backed bitmap the size of its own
/// `layoutFragmentFrame`, for sub-question 1: whether the character carrying `.attachment`
/// paints anything besides the attachment's own image. A glyph painted in the default
/// text colour on white leaves dark pixels; the attachment fill and the white background
/// do not, by construction, produce any as long as the fill colour is chosen with high
/// channels (see `hasDarkPixel`).
@MainActor
private func rasterize(_ fragment: NSTextLayoutFragment) -> NSBitmapImageRep? {
    let size = fragment.layoutFragmentFrame.size
    let scale: CGFloat = 4
    let width = max(1, Int(size.width * scale))
    let height = max(1, Int(size.height * scale))
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: scale, y: scale)
    NSColor.white.setFill()
    CGRect(origin: .zero, size: size).fill()
    fragment.draw(at: .zero, in: context.cgContext)
    return bitmap
}

/// Whether any pixel of `bitmap` is dark enough to be ink rather than the white background
/// or a fully-saturated, high-channel fill colour such as pure red or pure green.
private func hasDarkPixel(_ bitmap: NSBitmapImageRep, threshold: CGFloat = 0.45) -> Bool {
    for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
        for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            let brightest = max(color.redComponent, color.greenComponent, color.blueComponent)
            if color.alphaComponent > 0.1, brightest < threshold { return true }
        }
    }
    return false
}

// MARK: - Suite

@MainActor
@Suite struct EmbedAttachmentProbe {
    /// Thirteen characters: the `!` that will carry `.attachment` plus the twelve of
    /// `"foto-1-2.jpg"`, the same run length D6's probe 6 names.
    private static let run = "!foto-1-2.jpg"
    private static let note = "prima\n\(run)\ndopo\n"
    /// The twelve characters after the attachment one, relative to the paragraph's own
    /// start - the shape `HiddenMarker.range` already uses.
    private static let collapsedRange = NSRange(location: 1, length: 12)

    private static var embedParagraphRange: NSRange {
        let text = note as NSString
        let start = text.range(of: run).location
        return text.paragraphRange(for: NSRange(location: start, length: 0))
    }

    private static var embedOffset: Int { (note as NSString).range(of: run).location }

    // MARK: The naive reading of D3, measured first because it changes what the other
    // five tests below have to check

    /// D3 reads, most literally, as "add `.attachment` over the existing character" -
    /// keep the "!" , add the attribute, done. Measured: TextKit 2 never asks this
    /// attachment for its bounds or its image when the character underneath is not
    /// itself `NSAttachmentCharacter` (U+FFFC, `NSTextAttachment.h:19`). The attribute
    /// alone is not the signal that fires the attachment path on this stack, any more
    /// than it was on TextKit 1's `NSAttributedString(attachment:)` convenience, whose
    /// own header calls out building "an attributed string containing attachment using
    /// NSAttachmentCharacter as the base character" rather than the attribute alone.
    /// This is why the five tests that follow use the object-replacement-character
    /// variant instead: measuring probe 6 against a mechanism that is never engaged
    /// would answer every one of them by accident.
    @Test func anAttachmentAttributeAloneOverTheKeptCharacterIsNeverRecognised() {
        let baseline = layoutFragments(text: Self.note, delegate: nil)
        let attachment = LoggingAttachment(data: nil, ofType: nil)
        attachment.image = syntheticImage(.systemRed, size: CGSize(width: 64, height: 48))
        let delegate = AttachmentProbeDelegate(
            paragraphRange: Self.embedParagraphRange, attachmentOffset: 0, attachment: attachment,
            collapsedRange: Self.collapsedRange
        )
        let embedded = layoutFragments(text: Self.note, delegate: delegate)
        let baselineFragment = baseline.fragments.first { $0.offset == Self.embedOffset }?.layout
        let embeddedFragment = embedded.fragments.first { $0.offset == Self.embedOffset }?.layout

        #expect(attachment.boundsQueries == 0)
        #expect(embeddedFragment?.layoutFragmentFrame.height == baselineFragment?.layoutFragmentFrame.height)
        if let embeddedFragment {
            _ = rasterize(embeddedFragment)
            #expect(attachment.imageQueries == 0)
        }
        // And sub-question 1, answered directly for this configuration: since the
        // attachment path never engages, what paints is the ordinary "!" glyph at its
        // ordinary size - the next test measures that ink is really there.
    }

    /// Sub-question 1's direct answer for the naive reading above: the kept character
    /// draws its own glyph, in ink, exactly as an ordinary "!" would - and that ink goes
    /// away under the same shield a hidden marker already uses, if a future design ever
    /// needs to keep the real character visible-to-storage but invisible-to-the-eye.
    @Test func theKeptCharacterPaintsItsOwnGlyphAndAShieldRemovesIt() throws {
        let fill = NSColor.systemYellow
        let attachment = LoggingAttachment(data: nil, ofType: nil)
        attachment.image = syntheticImage(fill, size: CGSize(width: 64, height: 48))
        let delegate = AttachmentProbeDelegate(
            paragraphRange: Self.embedParagraphRange, attachmentOffset: 0, attachment: attachment,
            collapsedRange: Self.collapsedRange
        )
        let fragment = try #require(
            layoutFragments(text: Self.note, delegate: delegate).fragments
                .first { $0.offset == Self.embedOffset }?.layout
        )
        #expect(hasDarkPixel(try #require(rasterize(fragment))))

        let shielded = LoggingAttachment(data: nil, ofType: nil)
        shielded.image = syntheticImage(fill, size: CGSize(width: 64, height: 48))
        let shieldedDelegate = AttachmentProbeDelegate(
            paragraphRange: Self.embedParagraphRange, attachmentOffset: 0, attachment: shielded,
            collapsedRange: Self.collapsedRange,
            attachmentCharacterAttributes: [
                .font: EditorDecorationDelegate.collapsedFont, .foregroundColor: NSColor.clear,
            ]
        )
        let shieldedFragment = try #require(
            layoutFragments(text: Self.note, delegate: shieldedDelegate).fragments
                .first { $0.offset == Self.embedOffset }?.layout
        )
        #expect(!hasDarkPixel(try #require(rasterize(shieldedFragment))))
    }

    // MARK: Image, D6 probe 6's first independent answer - the mechanism that works

    @Test func anImageAttachmentDrawsExactlyOnceAndGrowsTheLineViaTheObjectReplacementCharacter() {
        let baseline = layoutFragments(text: Self.note, delegate: nil)
        let attachment = LoggingAttachment(data: nil, ofType: nil)
        attachment.image = syntheticImage(.systemRed, size: CGSize(width: 64, height: 48))
        let delegate = AttachmentProbeDelegate(
            paragraphRange: Self.embedParagraphRange, attachmentOffset: 0, attachment: attachment,
            collapsedRange: Self.collapsedRange, usesObjectReplacementCharacter: true
        )
        let embedded = layoutFragments(text: Self.note, delegate: delegate)

        // Never a character added or removed from the *real* backing store - only the
        // substituted copy's own character changes, in the one paragraph the delegate
        // is asked to redraw.
        #expect(baseline.length == embedded.length)
        #expect(embedded.length == (Self.note as NSString).length)

        let baselineFragment = baseline.fragments.first { $0.offset == Self.embedOffset }?.layout
        let embeddedFragment = embedded.fragments.first { $0.offset == Self.embedOffset }?.layout
        #expect(baselineFragment != nil)
        #expect(embeddedFragment != nil)
        // Passes: the line grows to the picture (D3's "width is negotiated" claim, read
        // here on height since the container is wide and never wraps this run).
        let baselineHeight = baselineFragment?.layoutFragmentFrame.height ?? .infinity
        #expect((embeddedFragment?.layoutFragmentFrame.height ?? 0) > baselineHeight)

        // Sub-question 2: attachmentBoundsForAttributes:... does fire for an attachment
        // that lives only in the substituted paragraph, never in the real backing store.
        #expect(attachment.boundsQueries > 0)

        // "Drawn exactly once": one explicit draw pass asks the attachment for its image
        // exactly once, not zero (unrecognised) and not more than once (duplicated). And
        // the image alone paints - no separate placeholder glyph underneath it.
        if let embeddedFragment {
            let bitmap = rasterize(embeddedFragment)
            #expect(attachment.imageQueries == 1)
            if let bitmap { #expect(!hasDarkPixel(bitmap)) }
        }
    }

    // MARK: PDF first page, D6 probe 6's second, independent answer

    @Test func aPDFFirstPageAttachmentDrawsExactlyOnceAndGrowsTheLineViaTheObjectReplacementCharacter() throws {
        let thumbnail = try #require(syntheticPDFFirstPageThumbnail(.systemBlue))
        let baseline = layoutFragments(text: Self.note, delegate: nil)
        let attachment = LoggingAttachment(data: nil, ofType: nil)
        attachment.image = thumbnail
        let delegate = AttachmentProbeDelegate(
            paragraphRange: Self.embedParagraphRange, attachmentOffset: 0, attachment: attachment,
            collapsedRange: Self.collapsedRange, usesObjectReplacementCharacter: true
        )
        let embedded = layoutFragments(text: Self.note, delegate: delegate)

        #expect(baseline.length == embedded.length)

        let baselineFragment = baseline.fragments.first { $0.offset == Self.embedOffset }?.layout
        let embeddedFragment = embedded.fragments.first { $0.offset == Self.embedOffset }?.layout
        let baselineHeight = baselineFragment?.layoutFragmentFrame.height ?? .infinity
        #expect((embeddedFragment?.layoutFragmentFrame.height ?? 0) > baselineHeight)
        #expect(attachment.boundsQueries > 0)

        if let embeddedFragment {
            let bitmap = rasterize(embeddedFragment)
            #expect(attachment.imageQueries == 1)
            if let bitmap { #expect(!hasDarkPixel(bitmap)) }
        }
    }

    // MARK: Sub-question 3 - a 0.01pt trailing newline, under the mechanism that works

    @Test func aCollapsedTrailingNewlineIsMeasuredAgainstLeavingItAtFullSize() {
        // The paragraph's own `\n` sits right after the twelve-character run, at
        // `collapsedRange`'s far edge. `HiddenMarker` ranges from `MarkdownStyler` never
        // reach it (headings and emphasis markers sit inside the visible text), so this
        // is new ground for the embed's own delegate to get right.
        let excludingNewline = Self.collapsedRange
        let includingNewline = NSRange(location: 1, length: 13)
        #expect(NSMaxRange(includingNewline) == Self.embedParagraphRange.length)

        func fragments(collapsing range: NSRange) -> [Fragment] {
            let attachment = LoggingAttachment(data: nil, ofType: nil)
            attachment.image = syntheticImage(.systemGreen, size: CGSize(width: 64, height: 48))
            let delegate = AttachmentProbeDelegate(
                paragraphRange: Self.embedParagraphRange, attachmentOffset: 0, attachment: attachment,
                collapsedRange: range, usesObjectReplacementCharacter: true
            )
            return layoutFragments(text: Self.note, delegate: delegate).fragments
        }

        let excluded = fragments(collapsing: excludingNewline)
        let included = fragments(collapsing: includingNewline)

        let excludedFragment = excluded.first { $0.offset == Self.embedOffset }
        let includedFragment = included.first { $0.offset == Self.embedOffset }
        #expect(excludedFragment != nil)
        #expect(includedFragment != nil)

        // Measured, not assumed: the attachment (at full size, on the paragraph's own
        // first character) dominates the line's height either way, so whether the
        // newline is also shrunk makes no observable difference in this shape - unlike
        // `EditorDecorationDelegate`'s own comment about folding, which is about a line
        // with *no* full-size character left on it at all.
        let excludedHeight = excludedFragment?.layout.layoutFragmentFrame.height
        let includedHeight = includedFragment?.layout.layoutFragmentFrame.height
        #expect(excludedHeight == includedHeight)
        // Three paragraphs in, three fragments out, whichever way the newline was set -
        // an extra phantom row is the failure mode this guards.
        #expect(excluded.count == included.count)
    }

    // MARK: Sub-question 4 - textView.isRichText = false, under the mechanism that works

    /// `NoteTextView.swift:98` sets `isRichText = false` on the real editor. The
    /// substituted paragraph is never the real backing store, so in theory this should
    /// not matter - checked here against a real `NSTextView` rather than only the headless
    /// stack above, the way `MarkupCoordinator` and `TranscludedLine` already check their
    /// own mechanisms against one.
    @Test func isRichTextFalseStillLaysOutTheSubstitutedAttachment() {
        func fragment(isRichText: Bool) -> (LoggingAttachment, NSTextLayoutFragment?) {
            let textView = NSTextView(usingTextLayoutManager: true)
            textView.isRichText = isRichText
            let attachment = LoggingAttachment(data: nil, ofType: nil)
            attachment.image = syntheticImage(.systemPurple, size: CGSize(width: 64, height: 48))
            let delegate = AttachmentProbeDelegate(
                paragraphRange: Self.embedParagraphRange, attachmentOffset: 0, attachment: attachment,
                collapsedRange: Self.collapsedRange, usesObjectReplacementCharacter: true
            )
            textView.textContentStorage?.delegate = delegate
            textView.string = Self.note
            guard let manager = textView.textLayoutManager else { return (attachment, nil) }
            manager.ensureLayout(for: manager.documentRange)
            var found: NSTextLayoutFragment?
            manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: [.ensuresLayout]) {
                let offset = manager.offset(from: manager.documentRange.location, to: $0.rangeInElement.location)
                if offset == Self.embedOffset { found = $0 }
                return true
            }
            return (attachment, found)
        }

        let (richAttachment, richFragment) = fragment(isRichText: true)
        let (plainAttachment, plainFragment) = fragment(isRichText: false)

        #expect(richFragment != nil)
        #expect(plainFragment != nil)
        #expect(richAttachment.boundsQueries > 0)
        // The pass criterion: `isRichText = false` queries the attachment exactly as
        // `isRichText = true` does - the substituted paragraph is invisible to the
        // property that governs the real backing store.
        #expect(plainAttachment.boundsQueries > 0)
        #expect(plainFragment?.layoutFragmentFrame.height == richFragment?.layoutFragmentFrame.height)
    }

    // MARK: ADR-0019 D8 probe 1 - a non-default `attachmentBounds` return really sizes
    // the line (R-01, R-09), one content type each. Gates Tasks 3, 5 and 6: failing
    // either sends D2's rejected `attachment.bounds` route out next.

    @Test func aNonDefaultAttachmentBoundsReallySizesTheLineForAnImage() {
        let natural = CGSize(width: 64, height: 48)
        let forced = CGSize(width: 200, height: 150)

        func fragment(forcedBounds: CGSize?) -> (LoggingAttachment, NSTextLayoutFragment?) {
            let attachment = LoggingAttachment(data: nil, ofType: nil)
            attachment.image = syntheticImage(.systemRed, size: natural)
            attachment.forcedBounds = forcedBounds
            let delegate = AttachmentProbeDelegate(
                paragraphRange: Self.embedParagraphRange, attachmentOffset: 0, attachment: attachment,
                collapsedRange: Self.collapsedRange, usesObjectReplacementCharacter: true
            )
            let layout = layoutFragments(text: Self.note, delegate: delegate).fragments
                .first { $0.offset == Self.embedOffset }?.layout
            return (attachment, layout)
        }

        let (_, unforcedFragment) = fragment(forcedBounds: nil)
        let (forcedAttachment, forcedFragment) = fragment(forcedBounds: forced)

        // Measured: unforced (natural 64x48 image) fragment height == 51.0pt, forced
        // (200x150) fragment height == 153.0pt - both 3pt over the raw image height because
        // the layout fragment adds the paragraph's own line spacing on top of the attachment.
        let unforcedHeight = unforcedFragment?.layoutFragmentFrame.height ?? 0
        let forcedHeight = forcedFragment?.layoutFragmentFrame.height ?? 0
        #expect(forcedHeight > unforcedHeight)

        // Draw once so `image(for:bounds:...)` actually runs and records what it was handed.
        if let forcedFragment { _ = rasterize(forcedFragment) }
        #expect(forcedAttachment.lastImageBounds?.size == forced)
    }

    @Test func aNonDefaultAttachmentBoundsReallySizesTheLineForAPDFFirstPage() throws {
        let thumbnail = try #require(syntheticPDFFirstPageThumbnail(.systemBlue))
        let forced = CGSize(width: 200, height: 150)

        func fragment(forcedBounds: CGSize?) -> (LoggingAttachment, NSTextLayoutFragment?) {
            let attachment = LoggingAttachment(data: nil, ofType: nil)
            attachment.image = thumbnail
            attachment.forcedBounds = forcedBounds
            let delegate = AttachmentProbeDelegate(
                paragraphRange: Self.embedParagraphRange, attachmentOffset: 0, attachment: attachment,
                collapsedRange: Self.collapsedRange, usesObjectReplacementCharacter: true
            )
            let layout = layoutFragments(text: Self.note, delegate: delegate).fragments
                .first { $0.offset == Self.embedOffset }?.layout
            return (attachment, layout)
        }

        let (_, unforcedFragment) = fragment(forcedBounds: nil)
        let (forcedAttachment, forcedFragment) = fragment(forcedBounds: forced)

        // Measured: unforced (thumbnail natural 96x67.2) fragment height == 70.0pt, forced
        // (200x150) fragment height == 153.0pt - the same 3pt line-spacing addition as the
        // image test above, on top of a different natural height.
        let unforcedHeight = unforcedFragment?.layoutFragmentFrame.height ?? 0
        let forcedHeight = forcedFragment?.layoutFragmentFrame.height ?? 0
        #expect(forcedHeight > unforcedHeight)

        if let forcedFragment { _ = rasterize(forcedFragment) }
        #expect(forcedAttachment.lastImageBounds?.size == forced)
    }
}
