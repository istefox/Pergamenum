import AppKit
import PDFKit
import Testing
@testable import Pergamenum

/// ADR-0018 slice 3, Step 3: the delegate branch that draws an embed's own picture in
/// place of its `![[…]]`/`![alt](…)` syntax - offscreen, on the model of
/// `MarkupHidingTests.swift`'s own `substitutedParagraph(_:note:)`, since what is under
/// test here is a new branch on the same `NSTextContentStorageDelegate` hook, not a new
/// mechanism: probe 6 (`EmbedAttachmentProbeTests`) already measured that the mechanism
/// itself - a substituted paragraph's own character swapped for `NSAttachmentCharacter` -
/// is what TextKit 2 recognises.
@MainActor
private func substitutedParagraph(
    _ delegate: EditorDecorationDelegate, note: String, at location: Int
) -> NSTextParagraph? {
    let storage = NSTextContentStorage()
    storage.textStorage?.setAttributedString(NSAttributedString(string: note))
    let range = (note as NSString).paragraphRange(for: NSRange(location: location, length: 0))
    return delegate.textContentStorage(storage, textParagraphWith: range)
}

/// A tiny real image, the same way `EmbedAttachmentProbeTests.syntheticImage` and
/// `EmbedResolutionTests.writeImage` build one for their own fixtures.
@MainActor
private func syntheticImage(size: CGSize = CGSize(width: 64, height: 48)) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.systemTeal.setFill()
    NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
    image.unlockFocus()
    return image
}

@MainActor
@Suite struct EmbedDrawing {
    private static let note = "prima\n![[foto.png]]\ndopo\n"
    /// "prima\n" is six characters; the embed's own paragraph starts right after it.
    private static let embedOffset = 6
    /// "![[foto.png]]", the embed's whole run - thirteen characters - relative to its own
    /// paragraph's start (ADR-0018 slice 3, Step 3, item 1: never the trailing newline).
    private static let marker = HiddenMarker(range: NSRange(location: 0, length: 13), kind: .embed)
    /// The embed's own paragraph, newline included - what the substituted copy's length
    /// must still equal.
    private static var embedParagraphLength: Int {
        (Self.note as NSString).paragraphRange(for: NSRange(location: Self.embedOffset, length: 0)).length
    }

    @Test func aDrawnRenditionSubstitutesTheAttachmentAndKeepsTheLengthIdentical() throws {
        let delegate = EditorDecorationDelegate()
        delegate.apply(hiddenMarkers: [Self.embedOffset: [Self.marker]], hidingMarkup: true)
        delegate.apply(embeds: [Self.embedOffset: .drawn(syntheticImage())])

        let paragraph = try #require(substitutedParagraph(delegate, note: Self.note, at: Self.embedOffset))
        let attributed = paragraph.attributedString
        #expect(attributed.length == Self.embedParagraphLength)
        #expect((attributed.string as NSString).character(at: 0) == 0xFFFC)
        let attachment = attributed.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment
        #expect(attachment?.image != nil)
        // The rest of the run collapses the same way a heading/emphasis marker does -
        // never a second, competing mechanism for the same paragraph.
        let font = attributed.attribute(.font, at: 1, effectiveRange: nil) as? NSFont
        #expect(font == EditorDecorationDelegate.collapsedFont)
    }

    @Test func aMissingRenditionDrawsAPlaceholderInstead() throws {
        let delegate = EditorDecorationDelegate()
        delegate.apply(hiddenMarkers: [Self.embedOffset: [Self.marker]], hidingMarkup: true)
        delegate.apply(embeds: [Self.embedOffset: .missing(name: "foto.png")])

        let paragraph = try #require(substitutedParagraph(delegate, note: Self.note, at: Self.embedOffset))
        let attributed = paragraph.attributedString
        #expect(attributed.length == Self.embedParagraphLength)
        #expect((attributed.string as NSString).character(at: 0) == 0xFFFC)
        let attachment = attributed.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment
        #expect(attachment?.image != nil)
        // The wikilink form carries no alt text of its own, so the label falls back to
        // the target name (ADR-0018 slice 3, Step 3, item 3). `.accessibilityAttachment`'s
        // value is this plain label string, not the `NSAccessibilityElement` VoiceOver
        // actually stops on - that element is built by
        // `CompletingTextView.accessibilityChildren()` from a real, on-screen text view
        // (`CompletingTextView+Accessibility.swift`), not by this offscreen delegate, and
        // `EmbedCaretTests` is where its own identifier and frame are asserted (ADR-0018
        // slice 3, Step 6 fix: an `NSAccessibilityElement` built right here, with
        // `parent: nil`, never actually reached VoiceOver - this test used to assert on
        // that orphan instead of on the thing a screen reader can find).
        let label = try #require(
            attributed.attribute(.accessibilityAttachment, at: 0, effectiveRange: nil) as? String
        )
        #expect(label == "foto.png")
    }

    /// D5's own deliberate exception to D2: a drawn embed does not reveal on caret the
    /// way a heading/emphasis marker does - the most important test in this file, since
    /// nothing else in the delegate would catch a regression that made the raw
    /// `![[foto.png]]` reappear the moment the caret reached its line.
    @Test func aRevealedParagraphStillDrawsTheEmbed() {
        let delegate = EditorDecorationDelegate()
        delegate.apply(hiddenMarkers: [Self.embedOffset: [Self.marker]], hidingMarkup: true)
        delegate.apply(embeds: [Self.embedOffset: .drawn(syntheticImage())])
        _ = delegate.apply(revealedParagraphs: [Self.embedOffset])

        #expect(substitutedParagraph(delegate, note: Self.note, at: Self.embedOffset) != nil)
    }

    /// `EmbedTable`'s render is still in flight (no cache hit yet): the offset is simply
    /// absent from the table, and the raw syntax stays on screen exactly as it does today.
    @Test func noRenditionYetLeavesTheParagraphUnchanged() {
        let delegate = EditorDecorationDelegate()
        delegate.apply(hiddenMarkers: [Self.embedOffset: [Self.marker]], hidingMarkup: true)

        #expect(substitutedParagraph(delegate, note: Self.note, at: Self.embedOffset) == nil)
    }

    /// A stale `.missing` rendition naming a different file than the one the line spells
    /// right now must not draw - the one identity check `stillSpellsAnEmbed` can make,
    /// since a `.drawn` rendition carries no name of its own to compare against.
    @Test func aMissingRenditionForADifferentTargetDoesNotDraw() {
        let delegate = EditorDecorationDelegate()
        delegate.apply(hiddenMarkers: [Self.embedOffset: [Self.marker]], hidingMarkup: true)
        delegate.apply(embeds: [Self.embedOffset: .missing(name: "altro.png")])

        #expect(substitutedParagraph(delegate, note: Self.note, at: Self.embedOffset) == nil)
    }

    @Test func aStaleMarkerAgainstPlainProseDoesNotDraw() {
        // The table still says an embed sits at this offset, but the text there has since
        // become plain prose - the last styling pass has not caught up with this layout
        // pass yet, the same race `MarkupHidingTests.aStaleTableEntryDoesNotCollapseProse`
        // checks for a heading marker.
        let delegate = EditorDecorationDelegate()
        delegate.apply(hiddenMarkers: [0: [Self.marker]], hidingMarkup: true)
        delegate.apply(embeds: [0: .drawn(syntheticImage())])

        #expect(substitutedParagraph(delegate, note: "corpo\ndopo\n", at: 0) == nil)
    }

    @Test func theEmbedBranchIsInertWhenHidingMarkupIsOff() {
        let delegate = EditorDecorationDelegate()
        delegate.apply(hiddenMarkers: [Self.embedOffset: [Self.marker]], hidingMarkup: false)
        delegate.apply(embeds: [Self.embedOffset: .drawn(syntheticImage())])

        #expect(substitutedParagraph(delegate, note: Self.note, at: Self.embedOffset) == nil)
    }
}

// MARK: - Coordinator-level, through a real render (ADR-0018 slice 3, Steps 2 and 3 together)

/// `EmbedTable.setRenditions` (Step 2, grown for Step 3) is what actually pushes a
/// resolved picture to `decorations` - both the synchronous pass `applyEmbeds` drives and
/// the asynchronous one `requestRender`'s own completion drives once a render lands.
/// Driven through a real `NSTextView`, like `EmbedResolutionTests`, because the fact under
/// test here is that wiring, not the delegate's own logic already covered above.
@MainActor
@Suite struct EmbedDrawingCoordinator {
    private static func makeTempVaultRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-embed-draw-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func writeImage(named name: String, in root: URL) throws {
        let image = NSImage(size: CGSize(width: 40, height: 30))
        image.lockFocus()
        NSColor.systemTeal.setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: 40, height: 30)).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: root.appending(path: name, directoryHint: .notDirectory))
    }

    private static func editor(
        text: String, root: URL?, thumbnails: ThumbnailStore?
    ) -> (NSTextView, NoteTextView.Coordinator) {
        let view = NoteTextView(
            text: .constant(text), theme: .emergency, noteTitles: [], tagSuggestions: [],
            hidesMarkup: true, onFollowLink: { _ in }, vaultRoot: root, notePath: "Nota.md",
            thumbnails: thumbnails
        )
        let coordinator = view.makeCoordinator()
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.textContentStorage?.delegate = coordinator.decorations
        textView.string = text
        return (textView, coordinator)
    }

    /// Polls until the delegate's own paragraph substitution starts returning the
    /// attachment, the same way `EmbedResolutionTests.waitForRendition` polls
    /// `embeds.renditions` - here the assertion is one level further down the pipeline,
    /// at the hook `EditorDecorationDelegate` actually draws from.
    private static func waitForSubstitution(
        offset: Int, in coordinator: NoteTextView.Coordinator, textView: NSTextView
    ) async -> NSTextParagraph? {
        for _ in 0..<100 {
            if let paragraph = substitutedParagraph(coordinator.decorations, note: textView.string, at: offset) {
                return paragraph
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    @Test func aRenderLandingAfterTheFirstPassStillReachesTheDelegate() async throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )

        let text = "testo\n![[foto.png]]\ndopo\n"
        let (textView, coordinator) = Self.editor(text: text, root: root, thumbnails: thumbnails)
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)

        let offset = (text as NSString).range(of: "![[foto.png]]").location
        // Nothing yet, synchronously: the first pass never blocks on the render, so the
        // delegate must still be drawing the raw syntax at this point.
        #expect(substitutedParagraph(coordinator.decorations, note: text, at: offset) == nil)

        let paragraph = await Self.waitForSubstitution(offset: offset, in: coordinator, textView: textView)
        let attributed = try #require(paragraph).attributedString
        #expect((attributed.string as NSString).character(at: 0) == 0xFFFC)
        #expect(attributed.attribute(.attachment, at: 0, effectiveRange: nil) != nil)
    }
}

// MARK: - Task 3 (ADR-0019, plan `2026-08-23-ridimensionamento-maniglie-embed-editor.md`):
// a wikilink embed's own `|W`/`|WxH` suffix drives what `attachmentBounds(…)` answers.

/// An `NSTextLocation` for a call to `attachmentBounds(for:location:textContainer:…)` made
/// outside a real layout pass. ADR-0019 §D2's own design never derives the resolved size
/// from `location` at all - only `textContainer` (the column) and the attachment's own
/// `written`/`natural` matter - so what this answers is never asserted on; it exists only
/// because the SDK's signature requires one.
@MainActor
private func anyTextLocation() -> any NSTextLocation {
    let storage = NSTextContentStorage()
    storage.textStorage?.setAttributedString(NSAttributedString(string: "x"))
    return storage.documentRange.location
}

@MainActor
private func makeTempVaultRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "pergamenum-embed-resize-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

/// A one-page PDF, written to disk so `ThumbnailStore`'s real PDF branch
/// (`ThumbnailStore.renderPDF`, `fileURL.pathExtension.lowercased() == "pdf"`) renders it,
/// the same way `EmbedResolutionTests.writeImage` writes a real PNG for `Attachment.resolve`
/// to read - R-09 asks that the feature work identically for image and PDF embeds, so this
/// test's rendition has to come from the PDF path, never a bare `NSImage` standing in for
/// one.
@MainActor
private func writePDF(named name: String, in root: URL, pageSize: CGSize = CGSize(width: 200, height: 140)) throws {
    guard let page = PDFPage(image: syntheticImage(size: pageSize)) else { throw CocoaError(.fileWriteUnknown) }
    let document = PDFDocument()
    document.insert(page, at: 0)
    guard let data = document.dataRepresentation() else { throw CocoaError(.fileWriteUnknown) }
    try data.write(to: root.appending(path: name, directoryHint: .notDirectory))
}

/// **Red on purpose.** `EditorDecorationDelegate.embedParagraph(at:storage:)` still builds
/// a plain `NSTextAttachment` (Task 3's own three-line change - constructing an
/// `EmbedAttachment`, parsing the suffix with `EmbedResize.written(inRun:)`, setting
/// `natural` - is the coder's half, not written here). So every `attachmentBounds(…)` call
/// below still answers the SDK default derived from `image.size`, never
/// `EmbedResize.resolved(written:natural:column:)`, and every `#expect` fails until that
/// wiring lands. The expected values are computed by calling `EmbedResize.resolved`
/// directly (Task 2, already merged and tested) rather than hardcoded, so this suite turns
/// green the moment the delegate's attachment actually consults it - no test-side change
/// required.
@MainActor
@Suite struct EmbedDrawingResize {
    private static let column: CGFloat = 400

    private static func container() -> NSTextContainer {
        let container = NSTextContainer(size: CGSize(width: column, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        return container
    }

    /// The `.attachment` attribute of an embed paragraph substituted through the real
    /// delegate, and the `CGRect` its `attachmentBounds(…)` answers against a container
    /// whose column is `Self.column` - the same "known width" the task names.
    private static func resolvedBounds(
        note: String, offset: Int, run: String, rendition: EmbedRendition
    ) throws -> CGRect {
        try Self.attachment(note: note, offset: offset, run: run, rendition: rendition).attachmentBounds(
            for: [:], location: anyTextLocation(), textContainer: Self.container(),
            proposedLineFragment: .zero, position: .zero
        )
    }

    /// The substituted paragraph's own `.attachment`, for the one case that has to assert
    /// against the rendition's picture rather than against a number typed here: the
    /// `.missing` placeholder's natural size is a private constant of the delegate, and a
    /// test that hardcoded 28 would go quietly wrong the day the glyph is drawn at another
    /// size.
    private static func attachment(
        note: String, offset: Int, run: String, rendition: EmbedRendition
    ) throws -> NSTextAttachment {
        let marker = HiddenMarker(range: NSRange(location: 0, length: (run as NSString).length), kind: .embed)
        let delegate = EditorDecorationDelegate()
        delegate.apply(hiddenMarkers: [offset: [marker]], hidingMarkup: true)
        delegate.apply(embeds: [offset: rendition])

        let paragraph = try #require(substitutedParagraph(delegate, note: note, at: offset))
        return try #require(
            paragraph.attributedString.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment
        )
    }

    @Test func aWidthOnlySuffixResolvesToTheWrittenWidthWithProportionalHeight() throws {
        let natural = CGSize(width: 64, height: 48)
        let note = "prima\n![[foto.png|300]]\ndopo\n"
        let bounds = try Self.resolvedBounds(
            note: note, offset: 6, run: "![[foto.png|300]]", rendition: .drawn(syntheticImage(size: natural))
        )
        let expected = EmbedResize.resolved(written: .width(300), natural: natural, column: Self.column)
        #expect(bounds.size == expected)
    }

    @Test func aWidthByHeightSuffixResolvesToBothWithAFreeAspectRatio() throws {
        let natural = CGSize(width: 64, height: 48)
        let note = "prima\n![[foto.png|300x200]]\ndopo\n"
        let bounds = try Self.resolvedBounds(
            note: note, offset: 6, run: "![[foto.png|300x200]]", rendition: .drawn(syntheticImage(size: natural))
        )
        let expected = EmbedResize.resolved(written: .both(300, 200), natural: natural, column: Self.column)
        #expect(bounds.size == expected)
    }

    /// No suffix (R-06) and a PDF-sourced rendition (R-09) together: the natural size comes
    /// from `ThumbnailStore`'s own PDF branch, rendered wide enough (720, the unsized-embed
    /// width ADR-0019 §D4 keeps) that the column actually clamps it, so this test would pass
    /// by accident if the clamp were simply skipped.
    @Test func aNoSuffixEmbedFromAPDFRenditionResolvesToTheNaturalSizeClampedToTheColumn() async throws {
        let root = try makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writePDF(named: "documento.pdf", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let natural = try #require(await thumbnails.thumbnail(for: "documento.pdf", width: 720).value)
        #expect(natural.size.width > Self.column) // the clamp below is meaningful, not a no-op

        let note = "prima\n![[documento.pdf]]\ndopo\n"
        let bounds = try Self.resolvedBounds(
            note: note, offset: 6, run: "![[documento.pdf]]", rendition: .drawn(natural)
        )
        let expected = EmbedResize.resolved(written: nil, natural: natural.size, column: Self.column)
        #expect(bounds.size == expected)
    }

    /// A suffix on an embed whose file the vault does not have (ADR-0019 §D5/§D8: only a
    /// picture is sized and only a picture gets a handle). The placeholder is a small fixed
    /// glyph, and stretching it to a width somebody wrote for the *photograph* draws a
    /// 20-point SF Symbol blown up some thirty times - which is what happened while
    /// `written` was set before the rendition was looked at, since the delegate had already
    /// re-read the run either way. The expectation is the placeholder's own picture, not a
    /// number: `attachment.image` is exactly what the delegate put there.
    @Test func aMissingRenditionIgnoresAWrittenSuffixAndKeepsThePlaceholdersNaturalSize() throws {
        let note = "prima\n![[assente.png|900]]\ndopo\n"
        let attachment = try Self.attachment(
            note: note, offset: 6, run: "![[assente.png|900]]", rendition: .missing(name: "assente.png")
        )
        let placeholder = try #require(attachment.image?.size)
        #expect(placeholder.width < EmbedResize.minimumSide) // a glyph, not a picture the clamp applies to
        let bounds = attachment.attachmentBounds(
            for: [:], location: anyTextLocation(), textContainer: Self.container(),
            proposedLineFragment: .zero, position: .zero
        )
        #expect(bounds.size == placeholder)
        // The size the suffix *would* have produced had it been read, named rather than
        // typed: with this suite's 400-point column it is the column clamp, not 900, so an
        // assertion against the literal 900 would have been green through the defect.
        let stretched = EmbedResize.resolved(written: .width(900), natural: placeholder, column: Self.column)
        #expect(bounds.size != stretched)
    }
}
