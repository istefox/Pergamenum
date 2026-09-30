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
            theme: .emergency,
            noteTitles: model.tick.isMultiple(of: 2) ? [] : ["x"],
            tagSuggestions: [],
            onFollowLink: { _ in },
            vault: .init(notePath: model.notePath),
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
}
