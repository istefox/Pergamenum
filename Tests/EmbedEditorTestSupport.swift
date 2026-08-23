import AppKit
import Testing
@testable import Pergamenum

/// The scaffolding every drawn-embed editor suite shares: a temporary vault root, a real
/// PNG on disk, a real `CompletingTextView` inside a real `NSWindow`, and the landed
/// render a gesture test starts from.
///
/// In a file of its own for the reason `DayTestSupport` is: three suites need it -
/// `EmbedCaret` (ADR-0018's caret, deletion, click and accessibility), `EmbedResizeGesture`
/// and `EmbedResizeCommit` (ADR-0019's handle, drag and commit) - and a copy in each is a
/// copy that drifts.
@MainActor
enum EmbedEditorFixtures {
    static func makeTempVaultRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-embed-caret-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// A tiny real PNG, the same way `EmbedResolutionTests.writeImage` builds one: the
    /// render has to be real for `EmbedTable` to resolve to `.drawn` rather than stall.
    static func writeImage(named name: String, in root: URL) throws {
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

    /// `editor(...)`'s three parts, named rather than a bare tuple: `window` is never
    /// read for its own sake, only kept alive so `textView.undoManager` resolves to
    /// something for the length of a test.
    struct Fixture {
        let textView: CompletingTextView
        let coordinator: NoteTextView.Coordinator
        let window: NSWindow
    }

    /// A real `CompletingTextView` with `claimsCommand` wired the same way
    /// `NoteTextView.wire(_:to:)` wires it, and a real, offscreen `NSWindow` so
    /// `undoManager` resolves to something - the same shape `InlineFormatTests` already
    /// uses for a text view built outside `makeNSView`. Never ordered front: the window
    /// exists only to complete the responder chain, not to be seen.
    static func editor(
        text: String, hidesMarkup: Bool, root: URL?, thumbnails: ThumbnailStore?
    ) -> Fixture {
        let view = NoteTextView(
            text: .constant(text), theme: .emergency, noteTitles: [], tagSuggestions: [],
            hidesMarkup: hidesMarkup, onFollowLink: { _ in }, vaultRoot: root, notePath: "Nota.md",
            thumbnails: thumbnails
        )
        let coordinator = view.makeCoordinator()
        let textView = CompletingTextView(usingTextLayoutManager: true)
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.frame = CGRect(x: 0, y: 0, width: 600, height: 800)
        textView.textContainer?.size = CGSize(width: 552, height: CGFloat.greatestFiniteMagnitude)
        textView.textContentStorage?.delegate = coordinator.decorations
        textView.textLayoutManager?.delegate = coordinator.decorations
        textView.string = text
        textView.claimsCommand = { [weak textView] selector in
            guard let textView else { return false }
            return coordinator.claimsEmbedCommand(selector, in: textView)
        }
        let window = NSWindow(
            contentRect: textView.frame, styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = textView
        return Fixture(textView: textView, coordinator: coordinator, window: window)
    }

    /// Polls `embeds.renditions` until the render lands, the same shape
    /// `EmbedResolutionTests.waitForRendition` already uses for the same real,
    /// asynchronous `ThumbnailStore` call.
    static func waitForRendition(
        at offset: Int, in coordinator: NoteTextView.Coordinator
    ) async -> EmbedRendition? {
        for _ in 0..<100 {
            if let rendition = coordinator.embeds.renditions[offset] { return rendition }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return coordinator.embeds.renditions[offset]
    }

    /// The fragment whose paragraph starts at `offset`, in the view's own coordinates -
    /// what a click carries. The same two-step conversion `FoldBadgeClickTests.badge`
    /// already does for a different decoration.
    static func fragmentFrame(at offset: Int, in textView: NSTextView) -> CGRect {
        guard let manager = textView.textLayoutManager, let content = manager.textContentManager
        else { return .null }
        var found: CGRect = .null
        let start = manager.documentRange.location
        manager.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
            let fragmentStart = content.offset(
                from: content.documentRange.location, to: fragment.rangeInElement.location
            )
            guard fragmentStart == offset else { return true }
            found = fragment.layoutFragmentFrame
            return false
        }
        guard !found.isNull else { return .null }
        let origin = textView.textContainerOrigin
        return found.offsetBy(dx: origin.x, dy: origin.y)
    }

    /// The shared setup every resize-drag test needs: a landed render, real layout, and
    /// the drawn picture's own frame - the same three steps the caret tests each repeat by
    /// hand (`waitForRendition` then `ensureLayout` then `fragmentFrame`), factored once
    /// here because the drag and commit suites add enough tests that copying it a further
    /// dozen times would grow them for no reason a reader would thank later.
    ///
    /// `text` defaults to `note` (the unsized embed every handle/drag test still wants);
    /// the commit tests pass `sizedNote` or a CommonMark spelling instead, always keeping
    /// the "prima\n" prefix so `embedOffset` stays valid for both.
    static func landedEmbed(
        root: URL, text: String = EmbedEditorFixtures.note
    ) async throws -> (fixture: Fixture, box: CGRect) {
        try writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = editor(text: text, hidesMarkup: true, root: root, thumbnails: thumbnails)
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)
        _ = await waitForRendition(at: embedOffset, in: coordinator)
        textView.textLayoutManager?.ensureLayout(for: textView.textLayoutManager!.documentRange)
        return (fixture, fragmentFrame(at: embedOffset, in: textView))
    }

    static let note = "prima\n![[foto.png]]\ndopo\n"
    /// "prima\n" is six characters; the embed's own paragraph starts right after it.
    static let embedOffset = 6
    /// "![[foto.png]]", the run's own length.
    static let runLength = 13
    /// An embed already carrying a written width - the commit tests start most of their
    /// gestures from here, so a drag's resolved width is `EmbedResize.resolved(
    /// written: .width(300), …)`'s exact, deterministic answer (`clamped(300, column)`,
    /// no dependence on whatever pixel size the real `QLThumbnailGenerator` render
    /// happens to come back as) rather than the unsized case's natural-image size, which
    /// is real and asynchronous and not a test's to predict.
    static let sizedNote = "prima\n![[foto.png|300]]\ndopo\n"
}
