import AppKit
import SwiftUI
import Testing
@testable import Pergamenum

// ADR-0071 §D3, "a value is read when it is read today" (plan `pg-144-editor-coordinator-
// feature-controllers`, Task 7, tester half): the remaining sites, beside the two block constructs
// `EditorControllerReadTimingTests` already pins. Written against the code before folding, reveal,
// transclusion, embed resize and the request ledger moved into controllers, and driven through the
// Coordinator's forwards (`unfold`, `applyReveal`, `openTransclusion`, `resizeEmbed`,
// `textViewDidChangeSelection`, `apply(_:to:)`, `alreadyApplied(_:)`), whose names the move kept.
// The state they assert on was re-pointed at its owner after the move (`coordinator.reveal.*`,
// `coordinator.embedResize.*`).
//
// Each controller is `lazy` on the Coordinator, so a pin builds the controller it reads through
// *before* the parent swap: a controller first built after the swap would see the new parent even
// if it captured `parent.X` at `init`, and the pin could not tell.
//
// The overlay theme is observable in-process (through a `Mirror` on the overlay's private
// `style`), so H7 is not needed for it.

@MainActor
private func swapped(
    _ coordinator: NoteTextView.Coordinator, text: String,
    theme: Theme = .emergency,
    configure: (inout NoteTextView) -> Void = { _ in }
) {
    var view = NoteTextView(
        text: .constant(text), theme: theme, noteTitles: [], tagSuggestions: [],
        hidesMarkup: true, onFollowLink: { _ in }
    )
    configure(&view)
    coordinator.parent = view
}

// MARK: - openTransclusion reads onFollowLink on the click (TransclusionController.open)

@MainActor
@Suite struct TransclusionClickReadsTheCurrentParent {
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

    @Test func aClickAfterAParentSwapCallsTheNewOnFollowLink() throws {
        var old: [String] = []
        var new: [String] = []
        let first = NoteTextView(
            text: .constant(Self.host), theme: .emergency, noteTitles: [], tagSuggestions: [],
            onFollowLink: { old.append($0) }, vault: .init(transclusions: Self.source())
        )
        let coordinator = first.makeCoordinator()
        let textView = CompletingTextView(usingTextLayoutManager: true)
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.frame = CGRect(x: 0, y: 0, width: 600, height: 800)
        textView.textContainer?.size = CGSize(width: 552, height: CGFloat.greatestFiniteMagnitude)
        textView.textContentStorage?.delegate = coordinator.decorations
        textView.textLayoutManager?.delegate = coordinator.decorations
        textView.string = Self.host
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyTransclusions(to: textView, theme: .emergency)

        let manager = try #require(textView.textLayoutManager)
        manager.ensureLayout(for: manager.documentRange)
        var drawn: CGRect = .null
        manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: [.ensuresLayout]) {
            if let fragment = $0 as? TranscludedLineFragment { drawn = fragment.renditionFrame }
            return true
        }
        #expect(drawn.height > 0)
        let origin = textView.textContainerOrigin
        let inside = CGPoint(x: drawn.midX + origin.x, y: drawn.midY + origin.y)

        coordinator.parent = NoteTextView(
            text: .constant(Self.host), theme: .emergency, noteTitles: [], tagSuggestions: [],
            onFollowLink: { new.append($0) }, vault: .init(transclusions: Self.source())
        )
        #expect(coordinator.openTransclusion(at: inside, in: textView))
        #expect(new == ["Prove"], "the click reads onFollowLink as it is now")
        #expect(old.isEmpty)
    }
}

// MARK: - unfold reads onToggleFold on the click (NoteTextView.Coordinator.unfold(at:in:))

@MainActor
@Suite struct UnfoldReadsTheCurrentParent {
    private static let note = "# Uno\ncorpo uno\ncorpo due\n\n# Due\ncorpo tre\n"

    @Test func aBadgeClickAfterAParentSwapCallsTheNewOnToggleFold() throws {
        var old: [Int] = []
        var new: [Int] = []
        let ranges = NoteOutline.entries(in: Self.note).map { NSRange($0.range, in: Self.note) }
        func view(_ sink: @escaping (Int) -> Void) -> NoteTextView {
            NoteTextView(
                text: .constant(Self.note), theme: .emergency, noteTitles: [], tagSuggestions: [],
                onFollowLink: { _ in },
                outline: .init(outlineRanges: ranges, foldedEntries: [0], onToggleFold: sink)
            )
        }
        let coordinator = view { old.append($0) }.makeCoordinator()
        let textView = CompletingTextView(usingTextLayoutManager: true)
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.frame = CGRect(x: 0, y: 0, width: 600, height: 800)
        textView.textContainer?.size = CGSize(width: 552, height: CGFloat.greatestFiniteMagnitude)
        textView.textContentStorage?.delegate = coordinator.decorations
        textView.textLayoutManager?.delegate = coordinator.decorations
        textView.string = Self.note
        coordinator.applyStyling(to: textView, theme: .emergency)
        coordinator.applyFolding(to: textView, folded: [0], theme: .emergency)
        let manager = try #require(textView.textLayoutManager)
        manager.ensureLayout(for: manager.documentRange)
        var badge: CGRect = .null
        manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: [.ensuresLayout]) {
            if let fragment = $0 as? FoldedHeadingFragment { badge = fragment.badgeFrameInContainer }
            return true
        }
        #expect(!badge.isNull)
        let origin = textView.textContainerOrigin
        let point = CGPoint(x: badge.midX + origin.x, y: badge.midY + origin.y)

        coordinator.parent = view { new.append($0) }
        #expect(coordinator.unfold(at: point, in: textView))
        #expect(new == [0], "the click reads onToggleFold as it is now")
        #expect(old.isEmpty)
    }
}

// MARK: - applyReveal reads matches, currentMatch, revealsInlineSpans (RevealController.apply)

@MainActor
@Suite struct RevealReadsTheCurrentParent {
    private static let note = "# Titolo\n\ncorpo **grassetto** fine\n\nultimo paragrafo\n"
    private static var lastParagraph: Int { (note as NSString).range(of: "ultimo").location }
    private static var boldSpanParagraph: Int { (note as NSString).range(of: "corpo").location }

    private func editor(caret: Int) -> (NSTextView, NoteTextView.Coordinator) {
        let fixture = EmbedEditorFixtures.editor(text: Self.note, hidesMarkup: true, root: nil, thumbnails: nil)
        fixture.coordinator.applyStyling(to: fixture.textView, theme: .emergency)
        fixture.textView.setSelectedRange(NSRange(location: caret, length: 0))
        // Built under the first parent, before any swap (see the file header).
        _ = fixture.coordinator.reveal
        return (fixture.textView, fixture.coordinator)
    }

    @Test func aFindMatchAddedByASwappedParentRevealsItsParagraph() {
        let (textView, coordinator) = editor(caret: 0)
        coordinator.applyReveal(to: textView)
        #expect(!coordinator.reveal.lastRevealed.contains(Self.lastParagraph))

        swapped(coordinator, text: Self.note) {
            $0.find.matches = [NSRange(location: Self.lastParagraph, length: 6)]
            $0.find.currentMatch = 0
        }
        coordinator.applyReveal(to: textView)
        #expect(
            coordinator.reveal.lastRevealed.contains(Self.lastParagraph),
            "matches and currentMatch are read from the parent as it is now"
        )
    }

    @Test func aMatchListWithNoCurrentMatchRevealsNothingExtra() {
        let (textView, coordinator) = editor(caret: 0)
        swapped(coordinator, text: Self.note) {
            $0.find.matches = [NSRange(location: Self.lastParagraph, length: 6)]
            $0.find.currentMatch = nil
        }
        coordinator.applyReveal(to: textView)
        #expect(!coordinator.reveal.lastRevealed.contains(Self.lastParagraph))
    }

    @Test func revealsInlineSpansIsReadFromTheParentAsItIsNow() {
        let caret = (Self.note as NSString).range(of: "grassetto").location + 2
        let (textView, coordinator) = editor(caret: caret)
        coordinator.applyReveal(to: textView)
        #expect(coordinator.reveal.lastRevealedSpans.isEmpty, "the first parent has the setting off")

        swapped(coordinator, text: Self.note) { $0.revealsInlineSpans = true }
        coordinator.applyReveal(to: textView)
        #expect(coordinator.reveal.lastRevealedSpans[Self.boldSpanParagraph]?.isEmpty == false)

        swapped(coordinator, text: Self.note) { $0.revealsInlineSpans = false }
        coordinator.applyReveal(to: textView)
        #expect(
            coordinator.reveal.lastRevealedSpans.isEmpty,
            "a caret held still still redraws when only the setting flips"
        )
    }
}

// MARK: - resizeEmbed(.began) builds its overlay from the current theme (EmbedResizeController.beginResize)

@MainActor
@Suite struct ResizeOverlayReadsTheCurrentTheme {
    /// The overlay's `style` is `private`, but a `Mirror` reads stored properties regardless of
    /// access, so the theme the overlay was built from IS observable in-process.
    private func border(of overlay: EmbedResizeOverlay) -> NSColor? {
        let style = Mirror(reflecting: overlay).children.first { $0.label == "style" }?.value
        return style.flatMap { Mirror(reflecting: $0).children.first { $0.label == "border" }?.value as? NSColor }
    }

    private func themeWithAccent(_ hex: String) throws -> Theme {
        let json = """
        { "color": { "accent": { "primary": { "$value": "\(hex)" } } } }
        """
        let document = try DesignTokenDocument(data: Data(json.utf8), fallbackName: "pin")
        return Theme(document: document, id: "pin", inheriting: .emergency)
    }

    @Test func theOverlayTakesItsBorderFromTheParentThemeAtBegan() async throws {
        let root = try EmbedEditorFixtures.makeTempVaultRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (fixture, box) = try await EmbedEditorFixtures.landedEmbed(root: root)
        defer { fixture.window.orderOut(nil) }
        let textView = fixture.textView
        let coordinator = fixture.coordinator
        let other = try themeWithAccent("#FF0000")
        #expect(NSColor(other.color(.accentPrimary)) != NSColor(Theme.emergency.color(.accentPrimary)))
        // Built under the original theme, before the swap (see the file header): otherwise
        // `.began` below would be the first to build it, after the swap, and a controller that
        // captured `parent.theme` at `init` would pass.
        _ = coordinator.embedResize.embedDrag

        swapped(coordinator, text: textView.string, theme: other)
        let hit = EmbedResize.handleHitRect(in: box)
        #expect(coordinator.resizeEmbed(.began(CGPoint(x: hit.midX, y: hit.midY)), in: textView))
        let overlay = try #require(coordinator.embedResize.embedDrag?.overlay)
        let drawn = try #require(border(of: overlay))
        #expect(drawn == NSColor(other.color(.accentPrimary)), "the overlay reads parent.theme as it is now")
        _ = coordinator.resizeEmbed(.ended(CGPoint(x: hit.midX, y: hit.midY)), in: textView)
    }
}

// MARK: - The outline-entry callback fires only when the entry changes (RequestLedger.claimOutlineEntry)

@MainActor
@Suite struct OutlineEntryCallbackFiresOnChangeOnly {
    private static let note = "prosa iniziale\n# Uno\ncorpo uno\n# Due\ncorpo due\n"

    private func editor(_ log: Log) -> (NSTextView, NoteTextView.Coordinator) {
        let ranges = NoteOutline.entries(in: Self.note).map { NSRange($0.range, in: Self.note) }
        let view = NoteTextView(
            text: .constant(Self.note), theme: .emergency, noteTitles: [], tagSuggestions: [],
            onFollowLink: { _ in },
            outline: .init(outlineRanges: ranges, onOutlineEntryChanged: { log.entries.append($0) })
        )
        let coordinator = view.makeCoordinator()
        let textView = CompletingTextView(usingTextLayoutManager: true)
        textView.frame = CGRect(x: 0, y: 0, width: 600, height: 800)
        textView.textContainer?.size = CGSize(width: 552, height: CGFloat.greatestFiniteMagnitude)
        textView.textContentStorage?.delegate = coordinator.decorations
        textView.textLayoutManager?.delegate = coordinator.decorations
        textView.string = Self.note
        return (textView, coordinator)
    }

    private final class Log { var entries: [Int?] = [] }

    private func move(_ caret: Int, in textView: NSTextView, _ coordinator: NoteTextView.Coordinator) {
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        coordinator.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: textView)
        )
    }

    @Test func theCallbackFiresOnAChangeAndNotOnARepeat() {
        let log = Log()
        let (textView, coordinator) = editor(log)
        let uno = (Self.note as NSString).range(of: "# Uno").location
        let due = (Self.note as NSString).range(of: "# Due").location

        move(uno + 1, in: textView, coordinator)
        #expect(log.entries == [0])
        move(uno + 3, in: textView, coordinator)
        move(uno + 12, in: textView, coordinator)
        #expect(log.entries == [0], "moving inside the same entry reports nothing")
        move(due + 2, in: textView, coordinator)
        #expect(log.entries == [0, 1])
        move(due + 4, in: textView, coordinator)
        #expect(log.entries == [0, 1])
    }

    @Test func aCaretBeforeTheFirstEntryReportsNilOnceAndThenReportsTheEntry() {
        // `Int??`: the first "no entry" is a change from "never reported", the second is not.
        let log = Log()
        let (textView, coordinator) = editor(log)
        move(2, in: textView, coordinator)
        move(5, in: textView, coordinator)
        #expect(log.entries.count == 1)
        #expect(log.entries.first == .some(nil))
        move((Self.note as NSString).range(of: "# Uno").location + 1, in: textView, coordinator)
        #expect(log.entries.count == 2)
        #expect(log.entries.last == .some(0))
    }
}

// MARK: - The replacement ledger records before it validates (ADR-0071 §D2, PG-093)

@MainActor
@Suite struct ReplacementLedgerKeepsItsOrder {
    private static let note = "uno due tre\n"

    @Test func aBatchRefusedForAStaleRangeIsStillRememberedAndNeverReplayed() {
        let fixture = EmbedEditorFixtures.editor(text: Self.note, hidesMarkup: false, root: nil, thumbnails: nil)
        let coordinator = fixture.coordinator
        let stale: [(range: NSRange, text: String)] = [(NSRange(location: 500, length: 3), "x")]

        #expect(!coordinator.alreadyApplied(stale))
        coordinator.apply(stale, to: fixture.textView)
        #expect(fixture.textView.string == Self.note, "a stale range writes nothing")
        #expect(coordinator.alreadyApplied(stale), "recorded before validation, so it is not replayed")
    }

    @Test func aBatchIsComparedByValueAndADifferentOneIsNew() {
        let fixture = EmbedEditorFixtures.editor(text: Self.note, hidesMarkup: false, root: nil, thumbnails: nil)
        let coordinator = fixture.coordinator
        let batch: [(range: NSRange, text: String)] = [(NSRange(location: 0, length: 3), "UNO")]

        coordinator.apply(batch, to: fixture.textView)
        #expect(fixture.textView.string.hasPrefix("UNO"))
        #expect(coordinator.alreadyApplied([(range: NSRange(location: 0, length: 3), text: "UNO")]))
        #expect(!coordinator.alreadyApplied([(range: NSRange(location: 0, length: 3), text: "Uno")]))
        #expect(!coordinator.alreadyApplied([(range: NSRange(location: 4, length: 3), text: "UNO")]))
    }
}
