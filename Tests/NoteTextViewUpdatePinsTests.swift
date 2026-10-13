import AppKit
import Observation
import SwiftUI
import Testing
@testable import Pergamenum

// PG-144 Task 5, R-10: characterization pins for the one-shot and note-switch bookkeeping of
// `NoteTextView.updateNSView`, green against the code as it was before the input grouping.
//
// `NSViewRepresentable.Context` cannot be built in a test, so a real `updateNSView` is driven by
// hosting the view through `HostedView` and changing a model between two updates. The window is
// never shown and never key (R-15); nothing here activates the app.
//
// Task 5 regroups the construction labels only: `EditorRoot.editor()` is the single place a
// label is spelled, so a re-point touches it and no assertion.
//
// Focus is observed through `window.firstResponder`. `HostedView`'s window refuses key status
// but still answers `makeFirstResponder`, so `takeFocus()` running is visible as the text view
// becoming first responder; the pins resign it between updates to see it taken again.

@MainActor @Observable
private final class UpdateModel {
    var text = "hello world"
    var notePath = "a.md"
    var replacements: [(range: NSRange, text: String)]?
    var focusRequest = 0
    /// The inputs a styling reads, for the restyle pins below (R-08). Defaults are what the editor
    /// was built with before they were model state, so no other pin changes.
    var theme: Theme = .emergency
    var hidesMarkup = false
    var revealsInlineSpans = false
    var thumbnails: ThumbnailStore?
    var scrollRequest: Navigation.OutlineJump?
    var matchJump: NSRange?
    /// Bumped to force an update that changes no input under test.
    var tick = 0
    @ObservationIgnored var replacementsApplied = 0
    @ObservationIgnored var scrollApplied = 0
}

private struct EditorRoot: View {
    let model: UpdateModel

    var body: some View {
        editor()
    }

    /// The one place the inputs are spelled out; Task 5's grouping re-points labels here only.
    private func editor() -> NoteTextView {
        _ = model.tick
        let model = model
        return NoteTextView(
            text: Binding(get: { model.text }, set: { model.text = $0 }),
            theme: model.theme,
            noteTitles: model.tick.isMultiple(of: 2) ? [] : ["x"],
            tagSuggestions: [],
            hidesMarkup: model.hidesMarkup,
            revealsInlineSpans: model.revealsInlineSpans,
            onFollowLink: { _ in },
            vault: .init(notePath: model.notePath, thumbnails: model.thumbnails),
            find: .init(
                replacements: model.replacements,
                onReplacementsApplied: { model.replacementsApplied += 1 },
                matchJump: model.matchJump
            ),
            focusRequest: model.focusRequest,
            outline: .init(
                scrollRequest: model.scrollRequest,
                onScrollApplied: { model.scrollApplied += 1 }
            )
        )
    }
}

@MainActor
private struct Harness {
    let model = UpdateModel()
    let host: HostedView<EditorRoot>

    init() {
        host = HostedView(EditorRoot(model: model), size: CGSize(width: 600, height: 700))
    }

    var textView: CompletingTextView? { Self.find(in: host.hosting) }

    /// Runs one more update that changes nothing under test.
    func update() async {
        model.tick += 1
        await host.settle()
    }

    func settle() async { await host.settle() }

    private static func find(in view: NSView) -> CompletingTextView? {
        if let scroll = view as? NSScrollView, let text = scroll.documentView as? CompletingTextView {
            return text
        }
        for sub in view.subviews {
            if let found = find(in: sub) { return found }
        }
        return nil
    }
}

@MainActor
@Suite struct NoteTextViewUpdatePinsTests {
    /// Builds the harness and lets the first update (which records `lastNotePath`) run.
    private func started() async throws -> (Harness, CompletingTextView) {
        let harness = Harness()
        await harness.settle()
        await harness.update()
        let textView = try #require(harness.textView)
        return (harness, textView)
    }

    // MARK: PG-093 replacement replay guard

    @Test func sameReplacementsBatchIsAppliedOnce() async throws {
        let (harness, textView) = try await started()
        // A batch whose replay would show: "hello" -> "hello!!" run twice gives "hello!!!!".
        harness.model.replacements = [(range: NSRange(location: 0, length: 5), text: "hello!!")]
        await harness.settle()
        #expect(textView.string == "hello!! world")
        #expect(harness.model.replacementsApplied == 1)

        // The owner has not yet cleared `replacements`; further updates carry the same batch.
        await harness.update()
        await harness.update()
        #expect(textView.string == "hello!! world")
        #expect(harness.model.replacementsApplied == 1)
        #expect(harness.host.refusals.isEmpty)
        #expect(harness.host.neverShown)
        harness.host.tearDown()
    }

    @Test func aDifferentBatchIsAppliedAfterTheFirst() async throws {
        let (harness, textView) = try await started()
        harness.model.replacements = [(range: NSRange(location: 0, length: 5), text: "hi")]
        await harness.settle()
        harness.model.replacements = [(range: NSRange(location: 0, length: 2), text: "yo")]
        await harness.settle()
        #expect(textView.string == "yo world")
        #expect(harness.model.replacementsApplied == 2)
        #expect(harness.host.refusals.isEmpty)
        #expect(harness.host.neverShown)
        harness.host.tearDown()
    }

    @Test func anOutOfBoundsBatchIsRecordedBeforeItIsRefused() async throws {
        let (harness, textView) = try await started()
        let stale = [(range: NSRange(location: 100, length: 3), text: "X")]
        harness.model.replacements = stale
        await harness.settle()
        // Refused (text untouched) but still reported as applied, once.
        #expect(textView.string == "hello world")
        #expect(harness.model.replacementsApplied == 1)

        // Record-before-validate: the same batch must not be retried, even once the text has
        // grown so that its range would now be valid.
        harness.model.text = String(repeating: "abcdefghij", count: 12)
        await harness.settle()
        #expect(textView.string.count == 120)
        await harness.update()
        #expect(textView.string.count == 120)
        #expect(!textView.string.contains("X"))
        #expect(harness.model.replacementsApplied == 1)
        #expect(harness.host.refusals.isEmpty)
        #expect(harness.host.neverShown)
        harness.host.tearDown()
    }

    // MARK: Focus

    @Test func focusRequestTakesFocusOncePerIncrement() async throws {
        let (harness, textView) = try await started()
        let window = harness.host.window
        window.makeFirstResponder(nil)
        #expect(window.firstResponder !== textView)

        harness.model.focusRequest = 1
        await harness.settle()
        #expect(window.firstResponder === textView)

        // Unchanged request: another update must not take focus back.
        window.makeFirstResponder(nil)
        await harness.update()
        #expect(window.firstResponder !== textView)

        // Incremented request: taken again.
        harness.model.focusRequest = 2
        await harness.settle()
        #expect(window.firstResponder === textView)
        #expect(harness.host.refusals.isEmpty)
        #expect(harness.host.neverShown)
        harness.host.tearDown()
    }

    // MARK: Scroll and match jump

    @Test func sameScrollRequestIdScrollsOnce() async throws {
        let (harness, textView) = try await started()
        let jump = Navigation.OutlineJump(id: 7, range: NSRange(location: 6, length: 5), ordinal: 0)
        harness.model.scrollRequest = jump
        await harness.settle()
        #expect(textView.selectedRange() == NSRange(location: 6, length: 0))
        #expect(harness.model.scrollApplied == 1)

        textView.setSelectedRange(NSRange(location: 1, length: 0))
        await harness.update()
        #expect(textView.selectedRange() == NSRange(location: 1, length: 0))
        #expect(harness.model.scrollApplied == 1)

        harness.model.scrollRequest = Navigation.OutlineJump(
            id: 8, range: NSRange(location: 3, length: 2), ordinal: 0
        )
        await harness.settle()
        #expect(textView.selectedRange() == NSRange(location: 3, length: 0))
        #expect(harness.model.scrollApplied == 2)
        #expect(harness.host.refusals.isEmpty)
        #expect(harness.host.neverShown)
        harness.host.tearDown()
    }

    @Test func matchJumpAtTheSameLocationMovesTheCaretOnce() async throws {
        let (harness, textView) = try await started()
        harness.model.matchJump = NSRange(location: 6, length: 5)
        await harness.settle()
        #expect(textView.selectedRange() == NSRange(location: 6, length: 0))

        textView.setSelectedRange(NSRange(location: 1, length: 0))
        await harness.update()
        #expect(textView.selectedRange() == NSRange(location: 1, length: 0))

        // A different location jumps again, and so does the same one after the bar closed.
        harness.model.matchJump = NSRange(location: 2, length: 1)
        await harness.settle()
        #expect(textView.selectedRange() == NSRange(location: 2, length: 0))

        harness.model.matchJump = nil
        await harness.settle()
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        harness.model.matchJump = NSRange(location: 2, length: 1)
        await harness.settle()
        #expect(textView.selectedRange() == NSRange(location: 2, length: 0))
        #expect(harness.host.refusals.isEmpty)
        #expect(harness.host.neverShown)
        harness.host.tearDown()
    }

    // MARK: Note switch

    @Test func newTextWithANewNotePathPutsTheCaretAtZero() async throws {
        let (harness, textView) = try await started()
        textView.setSelectedRange(NSRange(location: 5, length: 0))
        harness.model.notePath = "b.md"
        harness.model.text = "a different note entirely"
        await harness.settle()
        #expect(textView.string == "a different note entirely")
        #expect(textView.selectedRange() == NSRange(location: 0, length: 0))
        #expect(harness.host.refusals.isEmpty)
        #expect(harness.host.neverShown)
        harness.host.tearDown()
    }

    @Test func newTextWithTheSameNotePathKeepsTheCaretClamped() async throws {
        let (harness, textView) = try await started()
        textView.setSelectedRange(NSRange(location: 8, length: 0))
        harness.model.text = "hello world, edited elsewhere"
        await harness.settle()
        #expect(textView.selectedRange() == NSRange(location: 8, length: 0))

        harness.model.text = "abc"
        await harness.settle()
        #expect(textView.string == "abc")
        #expect(textView.selectedRange() == NSRange(location: 3, length: 0))
        #expect(harness.host.refusals.isEmpty)
        #expect(harness.host.neverShown)
        harness.host.tearDown()
    }

    // MARK: R-08, the styling that follows a keystroke

    /// The coordinator the hosted text view reports to.
    private func coordinator(of textView: CompletingTextView) throws -> NoteTextView.Coordinator {
        try #require(textView.delegate as? NoteTextView.Coordinator)
    }

    private func darkTheme() throws -> Theme {
        let url = try #require(Bundle.pergamenumResources.tokenFileURL(named: "pergamenum-dark"))
        let document = try DesignTokenDocument(data: try Data(contentsOf: url), fallbackName: "pergamenum-dark")
        return Theme(document: document, id: "pergamenum-dark", inheriting: .emergency)
    }

    // (per-paragraph-restyle R-08) A keystroke is styled once. `textDidChange` styles the dirty range,
    // SwiftUI then runs `updateNSView`, and the styling `runPasses` asks for over the same text is
    // counted as skipped and not run again.
    @Test func theStylingAfterAKeystrokeIsSkipped() async throws {
        let (harness, textView) = try await started()
        let coordinator = try coordinator(of: textView)
        let before = coordinator.restyleLog

        textView.setSelectedRange(NSRange(location: 5, length: 0))
        textView.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        await harness.settle()

        #expect(textView.string == "hellox world")
        #expect(harness.model.text == "hellox world", "the keystroke did not reach the model, so no update followed it")
        let after = coordinator.restyleLog
        #expect(after.incremental == before.incremental + 1, "the keystroke was not styled by the dirty range: \(after)")
        #expect(after.skipped == before.skipped + 1, "the styling after the keystroke was not skipped: \(after)")
        #expect(after.full == before.full, "something styled the whole note: \(after)")
        #expect(harness.host.refusals.isEmpty)
        #expect(harness.host.neverShown)
        harness.host.tearDown()
    }

    // (R-08) A theme change is a styling: the same update that would otherwise be skipped restyles.
    @Test func aThemeChangeIsAStyling() async throws {
        let (harness, textView) = try await started()
        let coordinator = try coordinator(of: textView)
        let before = coordinator.restyleLog

        harness.model.theme = try darkTheme()
        await harness.settle()

        let after = coordinator.restyleLog
        #expect(after.full + after.incremental == before.full + before.incremental + 1, "\(before) then \(after)")
        #expect(after.skipped == before.skipped, "the styling a new theme asks for was skipped: \(after)")
        #expect(harness.host.refusals.isEmpty)
        #expect(harness.host.neverShown)
        harness.host.tearDown()
    }

    // (R-08) Flipping `hidesMarkup` is a styling.
    @Test func aHidesMarkupFlipIsAStyling() async throws {
        let (harness, textView) = try await started()
        let coordinator = try coordinator(of: textView)
        let before = coordinator.restyleLog

        harness.model.hidesMarkup = true
        await harness.settle()

        let after = coordinator.restyleLog
        #expect(after.full + after.incremental == before.full + before.incremental + 1, "\(before) then \(after)")
        #expect(after.skipped == before.skipped, "the styling a `hidesMarkup` flip asks for was skipped: \(after)")
        #expect(harness.host.refusals.isEmpty)
        #expect(harness.host.neverShown)
        harness.host.tearDown()
    }

    // (R-08) Flipping `revealsInlineSpans` is a styling.
    @Test func aRevealsInlineSpansFlipIsAStyling() async throws {
        let (harness, textView) = try await started()
        let coordinator = try coordinator(of: textView)
        let before = coordinator.restyleLog

        harness.model.revealsInlineSpans = true
        await harness.settle()

        let after = coordinator.restyleLog
        #expect(after.full + after.incremental == before.full + before.incremental + 1, "\(before) then \(after)")
        #expect(after.skipped == before.skipped, "the styling a `revealsInlineSpans` flip asks for was skipped: \(after)")
        #expect(harness.host.refusals.isEmpty)
        #expect(harness.host.neverShown)
        harness.host.tearDown()
    }

    // (R-08) A new thumbnail store is a full styling, so the embed pass after it resolves the whole
    // note through the new store. The store is compared by identity: a second, distinct store over the
    // same vault root restyles in full too, and an update that keeps the store is skipped.
    @Test func aNewThumbnailStoreIsAStyling() async throws {
        let (harness, textView) = try await started()
        let coordinator = try coordinator(of: textView)
        let root = FileManager.default.temporaryDirectory.appending(path: "pergamenum-pins-\(UUID().uuidString)")
        let before = coordinator.restyleLog

        harness.model.thumbnails = ThumbnailStore(root: root, directory: root.appending(path: "cache"))
        await harness.settle()

        let after = coordinator.restyleLog
        #expect(after.full == before.full + 1, "a first thumbnail store was not a full styling: \(before) then \(after)")
        #expect(after.skipped == before.skipped, "the styling a new thumbnail store asks for was skipped: \(after)")

        // A distinct store over the same root, and the same cache directory: only its identity moved.
        let first = coordinator.restyleLog
        harness.model.thumbnails = ThumbnailStore(root: root, directory: root.appending(path: "cache"))
        await harness.settle()
        let second = coordinator.restyleLog
        #expect(second.full == first.full + 1, "a second, distinct store was not a full styling: \(first) then \(second)")
        #expect(second.incremental == first.incremental)

        // The same store again is not: the update after it is skipped.
        await harness.update()
        let again = coordinator.restyleLog
        #expect(again.full + again.incremental == second.full + second.incremental, "\(second) then \(again)")
        #expect(again.skipped > second.skipped, "the update that kept the store was not skipped: \(second) then \(again)")
        #expect(harness.host.refusals.isEmpty)
        #expect(harness.host.neverShown)
        harness.host.tearDown()
    }
}
