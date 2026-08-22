import AppKit
import Testing
@testable import Pergamenum

/// The caret, Backspace/Delete and a click, taught a drawn embed's run (ADR-0018 slice
/// 3, Step 4). Driven through a real `NSTextView` offscreen and a real `ThumbnailStore`
/// render, the same way `EmbedDrawingCoordinator`/`EmbedResolutionTests` already are:
/// what is under test here is the wiring from a real rendition down to
/// `selectedRange`/the storage, not `EmbedNavigation`'s own arithmetic, already covered
/// offscreen in `EmbedNavigationTests`.
@MainActor
@Suite struct EmbedCaret {
    private static func makeTempVaultRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-embed-caret-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// A tiny real PNG, the same way `EmbedResolutionTests.writeImage` builds one: the
    /// render has to be real for `EmbedTable` to resolve to `.drawn` rather than stall.
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

    /// `editor(...)`'s three parts, named rather than a bare tuple: `window` is never
    /// read for its own sake, only kept alive so `textView.undoManager` resolves to
    /// something for the length of a test.
    private struct Fixture {
        let textView: CompletingTextView
        let coordinator: NoteTextView.Coordinator
        let window: NSWindow
    }

    /// A real `CompletingTextView` with `claimsCommand` wired the same way
    /// `NoteTextView.wire(_:to:)` wires it, and a real, offscreen `NSWindow` so
    /// `undoManager` resolves to something - the same shape `InlineFormatTests` already
    /// uses for a text view built outside `makeNSView`. Never ordered front: the window
    /// exists only to complete the responder chain, not to be seen.
    private static func editor(
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
    private static func waitForRendition(
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
    private static func fragmentFrame(at offset: Int, in textView: NSTextView) -> CGRect {
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

    private static let note = "prima\n![[foto.png]]\ndopo\n"
    /// "prima\n" is six characters; the embed's own paragraph starts right after it.
    private static let embedOffset = 6
    /// "![[foto.png]]", the run's own length.
    private static let runLength = 13

    // MARK: - Deleting

    @Test func backspaceAtTheRightEdgeOfADrawnEmbedRemovesItWholeInOneUndoStep() async throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = Self.editor(
            text: Self.note, hidesMarkup: true, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)
        _ = await Self.waitForRendition(at: Self.embedOffset, in: coordinator)

        textView.setSelectedRange(NSRange(location: Self.embedOffset + Self.runLength, length: 0))
        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))

        #expect(textView.string == "prima\ndopo\n")
        textView.undoManager?.undo()
        #expect(textView.string == Self.note)
    }

    @Test func deleteAtTheLeftEdgeOfADrawnEmbedRemovesItWhole() async throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = Self.editor(
            text: Self.note, hidesMarkup: true, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)
        _ = await Self.waitForRendition(at: Self.embedOffset, in: coordinator)

        textView.setSelectedRange(NSRange(location: Self.embedOffset, length: 0))
        textView.doCommand(by: #selector(NSResponder.deleteForward(_:)))

        #expect(textView.string == "prima\ndopo\n")
    }

    /// The most important test in this file (R4): with `hidesMarkup` off the run is raw
    /// text, and Backspace at the same position must remove exactly one character - not
    /// the twenty-seven of ADR-0018's own motivating defect. A regression here reads as
    /// file corruption, not as a missing feature.
    @Test func withHidingMarkupOffBackspaceRemovesOnlyOneCharacter() throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = Self.editor(
            text: Self.note, hidesMarkup: false, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)

        textView.setSelectedRange(NSRange(location: Self.embedOffset + Self.runLength, length: 0))
        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))

        #expect(textView.string == "prima\n![[foto.png]\ndopo\n")
    }

    // MARK: - Moving

    @Test func movingRightFromTheRunsLeftEdgeSkipsItInOneStep() async throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = Self.editor(
            text: Self.note, hidesMarkup: true, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)
        _ = await Self.waitForRendition(at: Self.embedOffset, in: coordinator)

        textView.setSelectedRange(NSRange(location: Self.embedOffset, length: 0))
        textView.doCommand(by: #selector(NSResponder.moveRight(_:)))

        #expect(textView.selectedRange() == NSRange(location: Self.embedOffset + Self.runLength, length: 0))
    }

    @Test func movingLeftIntoTheRunFromTheRightEdgeSkipsItInOneStep() async throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = Self.editor(
            text: Self.note, hidesMarkup: true, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)
        _ = await Self.waitForRendition(at: Self.embedOffset, in: coordinator)

        textView.setSelectedRange(NSRange(location: Self.embedOffset + Self.runLength, length: 0))
        textView.doCommand(by: #selector(NSResponder.moveLeft(_:)))

        #expect(textView.selectedRange() == NSRange(location: Self.embedOffset, length: 0))
    }

    /// R4 for movement, symmetric to the Backspace test above: with `hidesMarkup` off
    /// the same arrow key must move one character, not skip the run.
    @Test func withHidingMarkupOffMovingRightIsOrdinary() throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = Self.editor(
            text: Self.note, hidesMarkup: false, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)

        textView.setSelectedRange(NSRange(location: Self.embedOffset, length: 0))
        textView.doCommand(by: #selector(NSResponder.moveRight(_:)))

        #expect(textView.selectedRange() == NSRange(location: Self.embedOffset + 1, length: 0))
    }

    // MARK: - Clicking

    @Test func aClickOnTheDrawnPictureSelectsItsWholeRun() async throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = Self.editor(
            text: Self.note, hidesMarkup: true, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)
        _ = await Self.waitForRendition(at: Self.embedOffset, in: coordinator)
        textView.textLayoutManager?.ensureLayout(for: textView.textLayoutManager!.documentRange)

        let box = Self.fragmentFrame(at: Self.embedOffset, in: textView)
        #expect(box.width > 0)
        #expect(coordinator.selectEmbed(at: CGPoint(x: box.midX, y: box.midY), in: textView))
        #expect(textView.selectedRange() == NSRange(location: Self.embedOffset, length: Self.runLength))
    }

    @Test func aClickOnOrdinaryProseDoesNotClaimAnything() async throws {
        let root = try Self.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = Self.editor(
            text: Self.note, hidesMarkup: true, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)
        _ = await Self.waitForRendition(at: Self.embedOffset, in: coordinator)
        textView.textLayoutManager?.ensureLayout(for: textView.textLayoutManager!.documentRange)

        let box = Self.fragmentFrame(at: 0, in: textView) // "prima\n"
        #expect(box.width > 0)
        #expect(!coordinator.selectEmbed(at: CGPoint(x: box.midX, y: box.midY), in: textView))
    }
}
