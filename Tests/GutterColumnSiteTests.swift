import AppKit
import Testing
@testable import Pergamenum

// (coverage) tests for the places ADR-0081 §D7 and §D2 touch that no other suite reaches
// directly (plan `docs/plans/pg-385-n2-page.md`, Task 8): the embed's column, the transcluded
// note's column in the fragment and in the controller that reserves its height. The marker-width
// memo and the inline-span reveal live in `GutterBlockRevealCoverageTests.swift`.
// Each asserts what the code's own documentation, the plan or an existing caller already states;
// none invents an entry point. The pin is `(n2-page coverage)` rather than an R-id.

// MARK: - EmbedResize.column (ADR-0081 §D7, ADR-0019 §D3)

@MainActor
@Suite struct GutterEmbedColumn {
    /// Everything `NSTextContainer.textLayoutManager` and `NSTextContentStorage.delegate` hold weakly,
    /// kept together so the caller keeps them alive for as long as it reads the column.
    private struct Built {
        let container: NSTextContainer
        let content: NSTextContentStorage
        let layout: NSTextLayoutManager
        let decorations: EditorDecorationDelegate?
    }

    private static let width: CGFloat = 600
    private static let padding: CGFloat = 5

    private static func built(
        width: CGFloat = 600, padding: CGFloat = 5, gutter: CGFloat?
    ) -> Built {
        let content = NSTextContentStorage()
        let layout = NSTextLayoutManager()
        content.addTextLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = padding
        layout.textContainer = container
        var decorations: EditorDecorationDelegate?
        if let gutter {
            let delegate = EditorDecorationDelegate()
            delegate.gutter = gutter
            content.delegate = delegate
            decorations = delegate
        }
        return Built(container: container, content: content, layout: layout, decorations: decorations)
    }

    @Test func aContainerWhoseContentStorageHasNoDecorationDelegateIsTheContainerLessItsPadding() {
        // (n2-page coverage)
        let built = Self.built(gutter: nil)
        withExtendedLifetime(built) {
            #expect(built.container.textLayoutManager != nil, "fixture: the container lost its layout manager")
            #expect(EmbedResize.column(of: built.container) == Self.width - 2 * Self.padding)
        }
    }

    @Test func theDecorationDelegatesGutterComesOffBothSides() {
        // (n2-page coverage) ADR-0081 §D7: a drawn embed as wide as the container would run past
        // the column into the margin, so the limit drops by the gutter on each side.
        let built = Self.built(gutter: 48)
        withExtendedLifetime(built) {
            #expect(EmbedResize.column(of: built.container) == Self.width - 2 * Self.padding - 2 * 48)
        }
    }

    @Test func aDelegateAtGutterZeroIsTheCardAndKeepsTheFullColumn() {
        // (n2-page coverage) ADR-0081 §D6: a card has no gutter.
        let built = Self.built(gutter: 0)
        withExtendedLifetime(built) {
            #expect(EmbedResize.column(of: built.container) == Self.width - 2 * Self.padding)
        }
    }

    @Test func theColumnIsTheOneTheEditorsBaseStyleSpans() {
        // (n2-page coverage) The embed limit and the paragraph it sits in must agree on the column:
        // the base style `applyStyling` gives every paragraph, spanned by `EditorGutter.columnSpan`.
        let gutter = Theme.emergency.spacing(.gutter)
        #expect(gutter > 0, "fixture: the emergency theme carries no gutter")
        let built = Self.built(gutter: gutter)
        let style = MarkdownAttributedText.base(theme: .emergency, gutter: gutter)[.paragraphStyle]
            as? NSParagraphStyle
        withExtendedLifetime(built) {
            let span = EditorGutter.columnSpan(containerWidth: Self.width, padding: Self.padding, style: style)
            #expect(EmbedResize.column(of: built.container) == span.width)
        }
    }

    @Test func noContainerOrAnUnboundedOneIsUnbounded() {
        // (n2-page coverage) `attachmentBounds` is asked during passes where the container is nil;
        // answering 0 there would draw every picture at the floor for one frame.
        #expect(EmbedResize.column(of: nil) == .greatestFiniteMagnitude)
        let unbounded = Self.built(width: .greatestFiniteMagnitude, gutter: 48)
        withExtendedLifetime(unbounded) {
            #expect(EmbedResize.column(of: unbounded.container) == .greatestFiniteMagnitude)
        }
    }
}

// MARK: - TranscludedLineFragment's column (ADR-0081 §D7)

@MainActor
@Suite struct GutterTranscludedLineFragmentColumn {
    private static let containerWidth: CGFloat = 600
    private static let padding: CGFloat = 5
    private static let gutter: CGFloat = 48

    private final class FragmentDelegate: NSObject, NSTextLayoutManagerDelegate, @unchecked Sendable {
        nonisolated(unsafe) var made: TranscludedLineFragment?

        func textLayoutManager(
            _ textLayoutManager: NSTextLayoutManager,
            textLayoutFragmentFor location: NSTextLocation,
            in textElement: NSTextElement
        ) -> NSTextLayoutFragment {
            let fragment = TranscludedLineFragment(textElement: textElement, range: textElement.elementRange)
            made = fragment
            return fragment
        }
    }

    private struct Built {
        let fragment: TranscludedLineFragment
        let content: NSTextContentStorage
        let layout: NSTextLayoutManager
        let delegate: FragmentDelegate
    }

    /// A one-line transclusion source whose paragraph carries the gutter's indents (or none).
    private static func built(gutter: CGFloat) -> Built {
        let content = NSTextContentStorage()
        let layout = NSTextLayoutManager()
        content.addTextLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: containerWidth, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = padding
        layout.textContainer = container
        let delegate = FragmentDelegate()
        layout.delegate = delegate

        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        ]
        if gutter > 0 {
            let style = NSMutableParagraphStyle()
            style.firstLineHeadIndent = gutter
            style.headIndent = gutter
            style.tailIndent = -gutter
            attributes[.paragraphStyle] = style
        }
        content.textStorage?.setAttributedString(NSAttributedString(string: "![[N]]", attributes: attributes))
        layout.ensureLayout(for: layout.documentRange)
        guard let made = delegate.made else { fatalError("layout never asked the delegate for a fragment") }
        return Built(fragment: made, content: content, layout: layout, delegate: delegate)
    }

    private static func rendition() -> TranscludedRendition {
        TranscludedRendition(
            title: "N", reference: "N", body: NSAttributedString(string: "x"), isCut: false,
            reservedHeight: 40, ruleColor: .red, captionColor: .black
        )
    }

    /// The left and right edge of the pure red the fragment draws (the rule bar of the rendition),
    /// in bitmap pixels, or nil when no red was drawn. Drawn at the fragment's own origin, the
    /// `point` TextKit hands `draw(at:in:)`, so a pixel is a point of the text container.
    private static func redBar(of fragment: TranscludedLineFragment) -> (minX: Int, maxX: Int)? {
        let width = Int(containerWidth)
        let height = 160
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        fragment.draw(at: fragment.layoutFragmentFrame.origin, in: graphics.cgContext)
        NSGraphicsContext.restoreGraphicsState()

        var minX = Int.max
        var maxX = Int.min
        for y in 0..<height {
            for x in 0..<width {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if color.alphaComponent > 0.5, color.redComponent > 0.8,
                   color.greenComponent < 0.3, color.blueComponent < 0.3 {
                    minX = min(minX, x)
                    maxX = max(maxX, x + 1)
                }
            }
        }
        return minX == Int.max ? nil : (minX, maxX)
    }

    @Test func theColumnIsTheContainerLessItsPaddingAndTheParagraphsIndents() {
        // (n2-page coverage) `containerWidth` is `columnSpan`'s width on the source line's own style.
        let built = Self.built(gutter: Self.gutter)
        withExtendedLifetime(built) {
            #expect(built.fragment.containerWidth == Self.containerWidth - 2 * Self.padding - 2 * Self.gutter)
        }
    }

    @Test func aParagraphWithNoIndentsKeepsTheWholeColumn() {
        // (n2-page coverage) Gutter zero is the transcluded picture's own copy and every harness.
        let built = Self.built(gutter: 0)
        withExtendedLifetime(built) {
            #expect(built.fragment.containerWidth == Self.containerWidth - 2 * Self.padding)
        }
    }

    @Test func theClickTargetStartsAtTheColumnAndSpansItsWidth() {
        // (n2-page coverage) `renditionFrame` is the drawn note's area: it starts at the column's
        // leading edge and is as wide as the column, so a click on the gutter is not a click on it.
        // TextKit already places the fragment at padding + headIndent (measured: 53 pt at 600 pt,
        // `aFragmentStartsAtTheColumnNotAtTheContainersEdge`), so the column's start is the
        // fragment's own `minX`, pinned here at padding + gutter.
        let built = Self.built(gutter: Self.gutter)
        withExtendedLifetime(built) {
            built.fragment.rendition = Self.rendition()
            let frame = built.fragment.renditionFrame
            let start = built.fragment.layoutFragmentFrame.minX
            #expect(!frame.isNull)
            #expect(abs(start - (Self.padding + Self.gutter)) <= 0.5, "il frammento comincia a \(start)")
            #expect(frame.minX == start)
            #expect(frame.width == Self.containerWidth - 2 * Self.padding - 2 * Self.gutter)
        }
    }

    @Test func theRenderingSurfaceReachesTheColumnsRightEdge() {
        // (n2-page coverage) A surface narrower than the column clips the drawn body (the
        // fragment's own header says why it widens itself). The surface is in the fragment's own
        // coordinates, which start at the column, so it must reach the column's width from that
        // origin (its left edge sits a few points left of it), and placed at the fragment's origin
        // it reaches the column's right edge, short of the gutter.
        let built = Self.built(gutter: Self.gutter)
        withExtendedLifetime(built) {
            built.fragment.rendition = Self.rendition()
            let bounds = built.fragment.renderingSurfaceBounds
            let right = built.fragment.layoutFragmentFrame.minX + bounds.maxX
            #expect(
                bounds.maxX >= Self.containerWidth - 2 * Self.padding - 2 * Self.gutter,
                "la superficie va da \(bounds.minX) a \(bounds.maxX)"
            )
            #expect(right >= Self.containerWidth - Self.padding - Self.gutter - 0.5, "la superficie finisce a \(right)")
        }
    }

    @Test func theRuleBarIsDrawnAfterTheGutterNotAtTheContainersEdge() {
        // (n2-page coverage) The picture starts at the column and its own 16 pt band follows it
        // (ADR-0081 §D7): drawn where TextKit draws it, at the fragment's origin, the bar sits at
        // padding + gutter + 16. With no gutter the same fragment draws it at padding + 16 - the
        // contrast is what proves the offset.
        let guttered = Self.built(gutter: Self.gutter)
        let plain = Self.built(gutter: 0)
        withExtendedLifetime((guttered, plain)) {
            guttered.fragment.rendition = Self.rendition()
            plain.fragment.rendition = Self.rendition()

            let band = TranscludedRendition.gutter
            let withGutter = Self.redBar(of: guttered.fragment)
            let without = Self.redBar(of: plain.fragment)

            #expect(withGutter != nil, "nessuna barra disegnata")
            #expect(without != nil, "nessuna barra disegnata senza grondaia")
            if let withGutter {
                #expect(
                    abs(CGFloat(withGutter.minX) - (Self.padding + Self.gutter + band)) <= 2,
                    "la barra parte a \(withGutter.minX)"
                )
            }
            if let without {
                #expect(
                    abs(CGFloat(without.minX) - (Self.padding + band)) <= 2,
                    "la barra senza grondaia parte a \(without.minX)"
                )
            }
        }
    }
}

// MARK: - The controller measures at the width the fragment draws at (ADR-0081 §D7)

@MainActor
@Suite struct GutterTransclusionWidth {
    private static let host = "# Ospite\n\n![[Prove]]\n\ncoda\n"

    private static func source() -> TransclusionSource {
        TransclusionSource(
            resolve: { reference in
                guard reference == "Prove" else { return nil }
                return TransclusionSource.Resolved(
                    title: "Prove", relativePath: "Prove.md", text: "# Prove\n\nTre serie di misure.\n"
                )
            },
            generation: 1
        )
    }

    /// The text view the app builds, minus SwiftUI: the fixture `TranscludedLine` uses, with the
    /// container at 552 pt inside a 24 pt inset.
    private static func editor() -> (NSTextView, NoteTextView.Coordinator) {
        let view = NoteTextView(
            text: .constant(host), theme: .emergency, noteTitles: [], tagSuggestions: [],
            onFollowLink: { _ in }, vault: .init(transclusions: source())
        )
        let coordinator = view.makeCoordinator()
        let textView = CompletingTextView(usingTextLayoutManager: true)
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.frame = CGRect(x: 0, y: 0, width: 600, height: 800)
        textView.textContainer?.size = CGSize(width: 552, height: CGFloat.greatestFiniteMagnitude)
        textView.textContentStorage?.delegate = coordinator.decorations
        textView.textLayoutManager?.delegate = coordinator.decorations
        textView.string = host
        return (textView, coordinator)
    }

    /// `reserveSpace` buys `reservedHeight` for the note laid out at one width and the fragment
    /// draws it at another if they disagree, which clips it (the fragment's own header). Both read
    /// the column ADR-0081 §D7 defines from the source line's own paragraph style, one in the
    /// storage and one in the displayed paragraph.
    @Test func theWidthTheNoteIsMeasuredAtIsTheWidthTheFragmentDrawsAt() throws {
        // (n2-page coverage)
        let (textView, coordinator) = Self.editor()
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyTransclusions(to: textView, theme: .emergency)

        let manager = try #require(textView.textLayoutManager)
        manager.ensureLayout(for: manager.documentRange)
        var found: TranscludedLineFragment?
        manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: [.ensuresLayout]) {
            if let fragment = $0 as? TranscludedLineFragment { found = fragment }
            return true
        }
        let fragment = try #require(found)
        let container = try #require(textView.textContainer)
        let gutter = Theme.emergency.spacing(.gutter)
        #expect(gutter > 0, "fixture: the emergency theme carries no gutter")

        let column = container.size.width - 2 * container.lineFragmentPadding - 2 * gutter
        #expect(fragment.containerWidth == column, "la colonna disegnata non esclude la grondaia")

        let width = TranscludedRendition.bodyWidth(inContainerOf: fragment.containerWidth)
        let keys = coordinator.transclusion.renditionCache.keys
        #expect(!keys.isEmpty)
        #expect(keys.allSatisfy { $0.hasSuffix("|\(Int(width))") }, "misurata a una larghezza diversa: \(keys)")

        let rendition = try #require(coordinator.transclusion.lastRenditions.values.first)
        let expected = TranscludedRendition.padding * 2 + TranscludedRendition.captionHeight
            + TranscludedRendition.height(of: rendition.body, width: width)
        #expect(rendition.reservedHeight == expected)
    }
}
