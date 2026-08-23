import AppKit
import Testing
@testable import Pergamenum

/// The caret, Backspace/Delete and a click, taught a drawn embed's run (ADR-0018 slice
/// 3, Step 4). Driven through a real `NSTextView` offscreen and a real `ThumbnailStore`
/// render, the same way `EmbedDrawingCoordinator`/`EmbedResolutionTests` already are:
/// what is under test here is the wiring from a real rendition down to
/// `selectedRange`/the storage, not `EmbedNavigation`'s own arithmetic, already covered
/// offscreen in `EmbedNavigationTests`.
///
/// The fixtures live in `EmbedEditorFixtures` (`EmbedEditorTestSupport.swift`): ADR-0019's
/// handle, drag and commit tests grew this file past SwiftLint's `type_body_length` error
/// threshold and moved to `EmbedResizeGestureTests`/`EmbedResizeCommitTests`, which drive
/// the same scaffolding.
@MainActor
@Suite struct EmbedCaret {
    // MARK: - Deleting

    @Test func backspaceAtTheRightEdgeOfADrawnEmbedRemovesItWholeInOneUndoStep() async throws {
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try EmbedEditorFixtures.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = EmbedEditorFixtures.editor(
            text: EmbedEditorFixtures.note, hidesMarkup: true, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)
        _ = await EmbedEditorFixtures.waitForRendition(
            at: EmbedEditorFixtures.embedOffset, in: coordinator
        )

        textView.setSelectedRange(NSRange(
            location: EmbedEditorFixtures.embedOffset + EmbedEditorFixtures.runLength, length: 0
        ))
        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))

        #expect(textView.string == "prima\ndopo\n")
        textView.undoManager?.undo()
        #expect(textView.string == EmbedEditorFixtures.note)
    }

    @Test func deleteAtTheLeftEdgeOfADrawnEmbedRemovesItWhole() async throws {
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try EmbedEditorFixtures.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = EmbedEditorFixtures.editor(
            text: EmbedEditorFixtures.note, hidesMarkup: true, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)
        _ = await EmbedEditorFixtures.waitForRendition(
            at: EmbedEditorFixtures.embedOffset, in: coordinator
        )

        textView.setSelectedRange(NSRange(location: EmbedEditorFixtures.embedOffset, length: 0))
        textView.doCommand(by: #selector(NSResponder.deleteForward(_:)))

        #expect(textView.string == "prima\ndopo\n")
    }

    /// The most important test in this file (R4): with `hidesMarkup` off the run is raw
    /// text, and Backspace at the same position must remove exactly one character - not
    /// the twenty-seven of ADR-0018's own motivating defect. A regression here reads as
    /// file corruption, not as a missing feature.
    @Test func withHidingMarkupOffBackspaceRemovesOnlyOneCharacter() throws {
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try EmbedEditorFixtures.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = EmbedEditorFixtures.editor(
            text: EmbedEditorFixtures.note, hidesMarkup: false, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)

        textView.setSelectedRange(NSRange(
            location: EmbedEditorFixtures.embedOffset + EmbedEditorFixtures.runLength, length: 0
        ))
        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))

        #expect(textView.string == "prima\n![[foto.png]\ndopo\n")
    }

    // MARK: - Moving

    @Test func movingRightFromTheRunsLeftEdgeSkipsItInOneStep() async throws {
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try EmbedEditorFixtures.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = EmbedEditorFixtures.editor(
            text: EmbedEditorFixtures.note, hidesMarkup: true, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)
        _ = await EmbedEditorFixtures.waitForRendition(
            at: EmbedEditorFixtures.embedOffset, in: coordinator
        )

        textView.setSelectedRange(NSRange(location: EmbedEditorFixtures.embedOffset, length: 0))
        textView.doCommand(by: #selector(NSResponder.moveRight(_:)))

        #expect(textView.selectedRange() == NSRange(
            location: EmbedEditorFixtures.embedOffset + EmbedEditorFixtures.runLength, length: 0
        ))
    }

    @Test func movingLeftIntoTheRunFromTheRightEdgeSkipsItInOneStep() async throws {
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try EmbedEditorFixtures.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = EmbedEditorFixtures.editor(
            text: EmbedEditorFixtures.note, hidesMarkup: true, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)
        _ = await EmbedEditorFixtures.waitForRendition(
            at: EmbedEditorFixtures.embedOffset, in: coordinator
        )

        textView.setSelectedRange(NSRange(
            location: EmbedEditorFixtures.embedOffset + EmbedEditorFixtures.runLength, length: 0
        ))
        textView.doCommand(by: #selector(NSResponder.moveLeft(_:)))

        #expect(textView.selectedRange() == NSRange(
            location: EmbedEditorFixtures.embedOffset, length: 0
        ))
    }

    /// R4 for movement, symmetric to the Backspace test above: with `hidesMarkup` off
    /// the same arrow key must move one character, not skip the run.
    @Test func withHidingMarkupOffMovingRightIsOrdinary() throws {
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try EmbedEditorFixtures.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = EmbedEditorFixtures.editor(
            text: EmbedEditorFixtures.note, hidesMarkup: false, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)

        textView.setSelectedRange(NSRange(location: EmbedEditorFixtures.embedOffset, length: 0))
        textView.doCommand(by: #selector(NSResponder.moveRight(_:)))

        #expect(textView.selectedRange() == NSRange(
            location: EmbedEditorFixtures.embedOffset + 1, length: 0
        ))
    }

    // MARK: - Clicking

    @Test func aClickOnTheDrawnPictureSelectsItsWholeRun() async throws {
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try EmbedEditorFixtures.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = EmbedEditorFixtures.editor(
            text: EmbedEditorFixtures.note, hidesMarkup: true, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)
        _ = await EmbedEditorFixtures.waitForRendition(
            at: EmbedEditorFixtures.embedOffset, in: coordinator
        )
        textView.textLayoutManager?.ensureLayout(for: textView.textLayoutManager!.documentRange)

        let box = EmbedEditorFixtures.fragmentFrame(
            at: EmbedEditorFixtures.embedOffset, in: textView
        )
        #expect(box.width > 0)
        #expect(coordinator.selectEmbed(at: CGPoint(x: box.midX, y: box.midY), in: textView))
        #expect(textView.selectedRange() == NSRange(
            location: EmbedEditorFixtures.embedOffset, length: EmbedEditorFixtures.runLength
        ))
    }

    @Test func aClickOnOrdinaryProseDoesNotClaimAnything() async throws {
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try EmbedEditorFixtures.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = EmbedEditorFixtures.editor(
            text: EmbedEditorFixtures.note, hidesMarkup: true, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)
        _ = await EmbedEditorFixtures.waitForRendition(
            at: EmbedEditorFixtures.embedOffset, in: coordinator
        )
        textView.textLayoutManager?.ensureLayout(for: textView.textLayoutManager!.documentRange)

        let box = EmbedEditorFixtures.fragmentFrame(at: 0, in: textView) // "prima\n"
        #expect(box.width > 0)
        #expect(!coordinator.selectEmbed(at: CGPoint(x: box.midX, y: box.midY), in: textView))
    }

    /// R4 for the click, completing the guard already checked for Backspace and
    /// movement above: with `hidesMarkup` off the run is raw, unselected text, and a
    /// click there must behave exactly as ordinary text selection would - `selectEmbed`
    /// itself is what refuses (`guard decorations.hidesMarkup`), this only proves it.
    @Test func aClickOnAnUnrenderedRunDoesNotClaimAnything() async throws {
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try EmbedEditorFixtures.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = EmbedEditorFixtures.editor(
            text: EmbedEditorFixtures.note, hidesMarkup: false, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)
        _ = await EmbedEditorFixtures.waitForRendition(
            at: EmbedEditorFixtures.embedOffset, in: coordinator
        )
        textView.textLayoutManager?.ensureLayout(for: textView.textLayoutManager!.documentRange)

        let box = EmbedEditorFixtures.fragmentFrame(
            at: EmbedEditorFixtures.embedOffset, in: textView
        )
        #expect(box.width > 0)
        #expect(!coordinator.selectEmbed(at: CGPoint(x: box.midX, y: box.midY), in: textView))
    }

    // MARK: - Accessibility (ADR-0018 slice 3, Step 6 fix)

    /// The regression this whole fix exists for: a drawn embed used to have no stop at
    /// all in the accessibility tree, because `EditorDecorationDelegate` built its own
    /// `NSAccessibilityElement` with `parent: nil` and AppKit never adopted it. Lives
    /// here rather than in `EmbedDrawingTests`, which is entirely offscreen by
    /// construction - a bare `NSTextContentStorage`, no `NSTextView`, no window, nothing
    /// to grow a real accessibility tree from - and this is the one fixture in the suite
    /// that already builds a real `CompletingTextView` inside a real `NSWindow`
    /// (`EmbedEditorFixtures.editor(text:hidesMarkup:root:thumbnails:)`) with a landed
    /// render.
    @Test func aDrawnEmbedIsAReachableAccessibilityElement() async throws {
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try EmbedEditorFixtures.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = EmbedEditorFixtures.editor(
            text: EmbedEditorFixtures.note, hidesMarkup: true, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)
        _ = await EmbedEditorFixtures.waitForRendition(
            at: EmbedEditorFixtures.embedOffset, in: coordinator
        )
        textView.textLayoutManager?.ensureLayout(for: textView.textLayoutManager!.documentRange)

        let children = try #require(textView.accessibilityChildren())
        let embeds = children.compactMap { $0 as? NSAccessibilityElement }
            .filter { $0.accessibilityIdentifier() == "editor-embed" }
        let embed = try #require(embeds.first)
        #expect(embeds.count == 1)
        #expect(embed.accessibilityLabel() == "foto.png")
        #expect(embed.accessibilityFrame() != .zero)
    }

    /// R4's own accessibility half: with `hidesMarkup` off the raw `![[foto.png]]` stays
    /// plain text, so there is nothing for `CompletingTextView.accessibilityChildren()`
    /// to build an element for - `drawnEmbedRange`'s own `hidesMarkup` guard is what
    /// refuses, the same guard every other embed feature in this file already leans on.
    @Test func rawSyntaxWithHidingMarkupOffHasNoAccessibilityElement() async throws {
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try EmbedEditorFixtures.writeImage(named: "foto.png", in: root)
        let thumbnails = ThumbnailStore(
            root: root, directory: root.appending(path: "cache", directoryHint: .isDirectory)
        )
        let fixture = EmbedEditorFixtures.editor(
            text: EmbedEditorFixtures.note, hidesMarkup: false, root: root, thumbnails: thumbnails
        )
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        defer { fixture.window.orderOut(nil) }
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyEmbeds(to: textView)
        _ = await EmbedEditorFixtures.waitForRendition(
            at: EmbedEditorFixtures.embedOffset, in: coordinator
        )
        textView.textLayoutManager?.ensureLayout(for: textView.textLayoutManager!.documentRange)

        let children = textView.accessibilityChildren() ?? []
        let embeds = children.compactMap { $0 as? NSAccessibilityElement }
            .filter { $0.accessibilityIdentifier() == "editor-embed" }
        #expect(embeds.isEmpty)
    }
}
