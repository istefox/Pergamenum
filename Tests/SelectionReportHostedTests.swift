import AppKit
import Observation
import SwiftUI
import Testing
@testable import Pergamenum

// PG-387 (N4), ADR-0085 §D8 and ADR-0086 §D4, plan docs/plans/pg-387-n4-birth-of-note.md, Task 4 -
// R-13 (and R-08 for the caret request): a hosted `NoteTextView` reports a non-empty selection once
// per change and nil once when it collapses; moving a bare caret, and typing with one, report
// nothing; a `caretRequest` places the caret at its offset once and calls `onCaretApplied`.
//
// Built the way `NoteTextViewUpdatePinsTests` builds it: `NSViewRepresentable.Context` cannot be
// made in a test, so a real `updateNSView` runs by hosting the view through `HostedView` and
// changing a model between two updates. The window is never shown and never key (R-15); the
// selection is moved with `setSelectedRange`, not by an event.

/// A non-empty selection in a hosted `NoteTextView` makes the editor show its format bar over the
/// window, which orders the hosted window front (measured 2026-10-12: `neverShown` false, R-15). The
/// bar is withheld inside a code fence, so every non-empty selection here is inside one: the
/// selection report does not depend on where the selection sits.
private enum SelectionRanges {
    static let note = "Intro\n\n```\nuno due tre quattro cinque\n```\n\nFine"
    static let first = (note as NSString).range(of: "due")
    static let second = (note as NSString).range(of: "quattro")
    static let bareA = (note as NSString).range(of: "Intro").location + 2
    static let bareB = (note as NSString).range(of: "Fine").location + 1
}

@MainActor @Observable
private final class SelectionModel {
    var text = SelectionRanges.note
    var caretRequest: NoteTextView.SelectionInputs.CaretRequest?
    var tick = 0
    var notePath = "a.md"
    @ObservationIgnored var reports: [NSRange?] = []
    /// What the tab showing each note would hold: `VaultController.recordSelection` writes a report
    /// to the front tab, i.e. to whichever note is current when the report arrives.
    @ObservationIgnored var tabSelection: [String: NSRange] = [:]
    @ObservationIgnored var caretApplied = 0
    /// Whether `onCaretApplied` clears `caretRequest`, as `EditorColumnView` does. Off by default so
    /// the tests that present one request twice still reach the ledger with it.
    @ObservationIgnored var clearsCaretOnApply = false
    /// The last id handed out by `requestCaret(at:)`: `EditorColumnView.caretRequestCount`.
    @ObservationIgnored var caretRequestCount = 0
    /// The front tab, when a test has two tabs on one note, and what each of them would hold: a
    /// report goes to whichever tab is in front when it arrives, whatever the note path says.
    var tabID: UUID?
    @ObservationIgnored var selectionByTab: [UUID: NSRange] = [:]
    /// The index entry each tab would hold, and every report in order: `recordOutlineEntry` writes
    /// to whichever tab is in front when the report arrives.
    @ObservationIgnored var outlineByTab: [UUID: Int?] = [:]
    @ObservationIgnored var outlineReports: [Int?] = []

    /// A caret request numbered the way the column numbers it, from its own counter rather than
    /// from `caretRequest`, which the column clears once the request is applied.
    func requestCaret(at offset: Int) {
        caretRequestCount += 1
        caretRequest = .init(id: caretRequestCount, offset: offset)
    }
}

private struct SelectionRoot: View {
    let model: SelectionModel

    var body: some View {
        _ = model.tick
        let model = model
        return NoteTextView(
            text: Binding(get: { model.text }, set: { model.text = $0 }),
            theme: .emergency,
            noteTitles: [],
            tagSuggestions: [],
            onFollowLink: { _ in },
            vault: .init(notePath: model.notePath, tabID: model.tabID),
            selection: .init(
                caretRequest: model.caretRequest,
                onCaretApplied: {
                    model.caretApplied += 1
                    if model.clearsCaretOnApply { model.caretRequest = nil }
                },
                onSelectionChanged: { range in
                    model.reports.append(range)
                    model.tabSelection[model.notePath] = range
                    if let tab = model.tabID { model.selectionByTab[tab] = range }
                }
            ),
            // Restated for ADR-0096 §D6 and §D7 (PG-406, plan Task 5): `OutlineInputs` no longer carries the
            // entries' ranges. The coordinator's own store, built from the same text, answers the caret's
            // entry; the scenario and its expected reports are unchanged.
            outline: .init(
                onOutlineEntryChanged: { entry in
                    model.outlineReports.append(entry)
                    if let tab = model.tabID { model.outlineByTab[tab] = .some(entry) }
                }
            )
        )
    }
}

@MainActor
private struct Harness {
    let model: SelectionModel
    let host: HostedView<SelectionRoot>

    init(caretRequest: NoteTextView.SelectionInputs.CaretRequest? = nil) {
        let model = SelectionModel()
        model.caretRequest = caretRequest
        self.init(model: model)
    }

    /// A host over a model that already exists: the text view, its coordinator and its ledger are
    /// new, the state above them is not - a column's text view rebuilt over the same state.
    init(model: SelectionModel) {
        self.model = model
        host = HostedView(SelectionRoot(model: model), size: CGSize(width: 600, height: 400))
    }

    var textView: CompletingTextView? { Self.find(in: host.hosting) }

    func settle() async { await host.settle() }

    func update() async {
        model.tick += 1
        await host.settle()
    }

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
private func started() async throws -> (Harness, CompletingTextView) {
    let harness = Harness()
    await harness.settle()
    await harness.update()
    let textView = try #require(harness.textView)
    harness.model.reports.removeAll()
    return (harness, textView)
}

@MainActor
private func finish(_ harness: Harness) {
    #expect(harness.host.neverShown)
    #expect(harness.host.refusals.isEmpty)
    harness.host.tearDown()
}

// MARK: - The selection report

@MainActor
@Test func aNonEmptySelectionIsReportedOnceAndRepeatedSelectionsAreNot() async throws {
    let (harness, textView) = try await started()

    textView.setSelectedRange(SelectionRanges.first)
    await harness.settle()
    textView.setSelectedRange(SelectionRanges.first)
    await harness.settle()

    #expect(harness.model.reports == [SelectionRanges.first]) // R-13: once per change
    finish(harness)
}

@MainActor
@Test func aChangedSelectionIsReportedAgain() async throws {
    let (harness, textView) = try await started()

    textView.setSelectedRange(SelectionRanges.first)
    await harness.settle()
    textView.setSelectedRange(SelectionRanges.second)
    await harness.settle()

    #expect(harness.model.reports == [SelectionRanges.first, SelectionRanges.second])
    finish(harness)
}

@MainActor
@Test func collapsingTheSelectionReportsNilOnce() async throws {
    let (harness, textView) = try await started()
    textView.setSelectedRange(SelectionRanges.first)
    await harness.settle()

    textView.setSelectedRange(NSRange(location: SelectionRanges.bareA, length: 0))
    await harness.settle()
    textView.setSelectedRange(NSRange(location: SelectionRanges.bareB, length: 0))
    await harness.settle()

    #expect(harness.model.reports == [SelectionRanges.first, nil]) // R-13: nil once, not per move
    finish(harness)
}

@MainActor
@Test func movingABareCaretReportsNothing() async throws {
    let (harness, textView) = try await started()

    textView.setSelectedRange(NSRange(location: SelectionRanges.bareA, length: 0))
    await harness.settle()
    textView.setSelectedRange(NSRange(location: SelectionRanges.bareB, length: 0))
    await harness.settle()

    #expect(harness.model.reports.isEmpty) // ADR-0085 §D8: written only when it changes
    finish(harness)
}

@MainActor
@Test func typingWithABareCaretReportsNothing() async throws {
    let (harness, textView) = try await started()
    textView.setSelectedRange(NSRange(location: SelectionRanges.bareA, length: 0))
    await harness.settle()

    textView.insertText("xyz", replacementRange: NSRange(location: NSNotFound, length: 0))
    await harness.settle()

    #expect(textView.string.contains("xyz"))
    #expect(harness.model.reports.isEmpty) // R-13: typing writes nothing to the tab
    finish(harness)
}

// MARK: - A note or tab switch

private let otherNote = SelectionRanges.note + "\n\nAltra nota"

/// One text view serves every tab of a column. The collapse a switch causes is reported while the
/// *new* tab is in front, so the old tab keeps its range unless coming back reports again.
@MainActor
@Test func aSelectionLeftBehindByATabSwitchIsClearedWhenTheTabComesBack() async throws {
    let (harness, textView) = try await started()
    textView.setSelectedRange(SelectionRanges.first)
    await harness.settle()
    #expect(harness.model.tabSelection["a.md"] == SelectionRanges.first)

    harness.model.notePath = "b.md"
    harness.model.text = otherNote
    await harness.settle()
    #expect(textView.selectedRange().length == 0)

    harness.model.notePath = "a.md"
    harness.model.text = SelectionRanges.note
    await harness.settle()

    #expect(textView.selectedRange().length == 0)
    #expect(harness.model.tabSelection["a.md"] == nil, "a bare caret must not leave a phantom range on the tab") // R-13
    finish(harness)
}

@MainActor
@Test func theSameRangeSelectedInTheNextNoteIsReported() async throws {
    let (harness, textView) = try await started()
    textView.setSelectedRange(SelectionRanges.first)
    await harness.settle()

    harness.model.notePath = "b.md"
    harness.model.text = otherNote
    await harness.settle()
    textView.setSelectedRange(SelectionRanges.first)
    await harness.settle()

    #expect(harness.model.tabSelection["b.md"] == SelectionRanges.first) // R-13
    finish(harness)
}

/// Two tabs of one note share a column's text view and identical text, so switching between them
/// is not a note switch by path. The front tab must still end up holding what the text view shows:
/// «Estrai in una nota» cuts out the tab's range, so a range it kept from when it was last in
/// front, under a different highlight on screen, would cut out a passage nobody can see selected.
@MainActor
@Test func aTabSwitchOnTheSameNoteLeavesTheFrontTabHoldingWhatIsOnScreen() async throws {
    let tabA = UUID()
    let tabB = UUID()
    let (harness, textView) = try await started()
    harness.model.tabID = tabA
    await harness.update()
    textView.setSelectedRange(SelectionRanges.first)
    await harness.settle()
    #expect(harness.model.selectionByTab[tabA] == SelectionRanges.first)

    harness.model.tabID = tabB
    await harness.update()
    textView.setSelectedRange(SelectionRanges.second)
    await harness.settle()
    #expect(harness.model.selectionByTab[tabB] == SelectionRanges.second)

    harness.model.tabID = tabA
    await harness.update()

    #expect(textView.selectedRange() == SelectionRanges.second)
    #expect(harness.model.selectionByTab[tabA] == SelectionRanges.second) // R-13: the range on screen
    finish(harness)
}

/// The same switch the other way round: the tab coming to the front kept no selection while the
/// text view shows one, which the tab must be told rather than left at nil.
@MainActor
@Test func aTabWithNoSelectionComingToTheFrontIsToldWhatTheTextViewShows() async throws {
    let tabA = UUID()
    let tabB = UUID()
    let (harness, textView) = try await started()
    harness.model.tabID = tabA
    await harness.update()
    textView.setSelectedRange(SelectionRanges.first)
    await harness.settle()

    harness.model.tabID = tabB
    await harness.update()

    #expect(harness.model.selectionByTab[tabB] == SelectionRanges.first) // R-13
    finish(harness)
}

@MainActor
@Test func aBareCaretAfterANoteSwitchWritesNothingToTheTab() async throws {
    let (harness, textView) = try await started()

    harness.model.notePath = "b.md"
    harness.model.text = otherNote
    await harness.settle()
    // The switch reports the new note's collapsed selection once, to the tab now in front.
    #expect(harness.model.reports == [nil])

    textView.setSelectedRange(NSRange(location: SelectionRanges.bareA, length: 0))
    await harness.settle()
    textView.setSelectedRange(NSRange(location: SelectionRanges.bareB, length: 0))
    await harness.settle()

    #expect(harness.model.reports == [nil]) // PG-401: a bare caret is write-free
    finish(harness)
}

/// The Outline highlight and «Piega sezione» act on the front tab's `currentOutlineEntry`. Switching
/// between two tabs of one note fires no selection notification (same text, same caret), so the
/// incoming tab has to be told the entry the shared view's caret is in by the switch itself.
private let outlineNote = "# Uno\n\ncorpo uno\n\n# Due\n\ncorpo due\n"

@MainActor
@Test func aTabSwitchOnTheSameNoteTellsTheFrontTabTheOutlineEntryOfTheCaret() async throws {
    let tabA = UUID()
    let tabB = UUID()
    let (harness, textView) = try await started()
    harness.model.text = outlineNote
    harness.model.tabID = tabA
    await harness.update()
    textView.setSelectedRange(NSRange(location: (outlineNote as NSString).range(of: "corpo due").location, length: 0))
    await harness.settle()
    #expect(harness.model.outlineByTab[tabA] == .some(1))

    harness.model.tabID = tabB
    await harness.update()

    #expect(harness.model.outlineByTab[tabB] == .some(1), "the incoming tab must not keep a stale entry") // R-13
    finish(harness)
}

@MainActor
@Test func typingInTheSameOutlineEntryReportsNoOutlineEntry() async throws {
    let tabA = UUID()
    let (harness, textView) = try await started()
    harness.model.text = outlineNote
    harness.model.tabID = tabA
    await harness.update()
    textView.setSelectedRange(NSRange(location: (outlineNote as NSString).range(of: "corpo due").location, length: 0))
    await harness.settle()
    harness.model.outlineReports.removeAll()

    textView.insertText("xyz", replacementRange: NSRange(location: NSNotFound, length: 0))
    await harness.settle()
    textView.insertText("abc", replacementRange: NSRange(location: NSNotFound, length: 0))
    await harness.settle()

    #expect(textView.string.contains("xyzabc"))
    #expect(harness.model.outlineReports.isEmpty) // PG-401: a keystroke is write-free
    finish(harness)
}

// MARK: - The caret request

@MainActor
@Test func aCaretRequestPlacesTheCaretOnceAndReportsItApplied() async throws {
    let (harness, textView) = try await started()
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    harness.model.caretRequest = .init(id: 1, offset: 9)
    await harness.settle()

    #expect(textView.selectedRange() == NSRange(location: 9, length: 0)) // R-08
    #expect(harness.model.caretApplied == 1)

    // The same request again, after the caret has moved on: it is not applied twice.
    textView.setSelectedRange(NSRange(location: 2, length: 0))
    await harness.update()
    #expect(textView.selectedRange() == NSRange(location: 2, length: 0))
    #expect(harness.model.caretApplied == 1)
    finish(harness)
}

@MainActor
@Test func aNewCaretRequestIsAppliedAgain() async throws {
    let (harness, textView) = try await started()

    harness.model.caretRequest = .init(id: 1, offset: 9)
    await harness.settle()
    harness.model.caretRequest = .init(id: 2, offset: 4)
    await harness.settle()

    #expect(textView.selectedRange() == NSRange(location: 4, length: 0)) // R-08
    #expect(harness.model.caretApplied == 2)
    finish(harness)
}

/// The column clears `caretRequest` once it is applied and numbers the next one from its own
/// counter: an id derived from the cleared value would restart at 1, which the ledger already
/// claimed, and a second note born in the same column would lose its caret.
@MainActor
@Test func aSecondCaretRequestAfterTheFirstWasClearedIsApplied() async throws {
    let (harness, textView) = try await started()
    harness.model.clearsCaretOnApply = true

    harness.model.requestCaret(at: 9)
    await harness.settle()
    #expect(textView.selectedRange() == NSRange(location: 9, length: 0))
    #expect(harness.model.caretRequest == nil)

    textView.setSelectedRange(NSRange(location: 0, length: 0))
    harness.model.requestCaret(at: 4)
    await harness.settle()

    #expect(textView.selectedRange() == NSRange(location: 4, length: 0)) // R-08
    #expect(harness.model.caretApplied == 2)
    #expect(harness.model.caretRequest == nil)
    finish(harness)
}

/// A rebuilt text view starts with an empty ledger, so a request still standing would be applied
/// again over wherever the person had moved the caret; cleared once applied, there is none left.
@MainActor
@Test func aClearedCaretRequestDoesNotReplayOnARebuiltView() async throws {
    let (harness, textView) = try await started()
    harness.model.clearsCaretOnApply = true
    harness.model.requestCaret(at: 9)
    await harness.settle()
    #expect(textView.selectedRange() == NSRange(location: 9, length: 0))
    #expect(harness.model.caretApplied == 1)
    finish(harness)

    let rebuilt = Harness(model: harness.model)
    await rebuilt.settle()
    let rebuiltView = try #require(rebuilt.textView)

    #expect(harness.model.caretApplied == 1) // R-08: applied once, not once per view
    #expect(rebuiltView.selectedRange() != NSRange(location: 9, length: 0))
    finish(rebuilt)
}

@MainActor
@Test func aCaretRequestPastTheEndOfTheTextIsClampedNotCrashed() async throws {
    let (harness, textView) = try await started()
    let length = (harness.model.text as NSString).length

    harness.model.caretRequest = .init(id: 1, offset: length + 500)
    await harness.settle()

    #expect(textView.selectedRange() == NSRange(location: length, length: 0))
    #expect(harness.model.caretApplied == 1)
    finish(harness)
}

/// The daily note's caret arrives with the column itself (`EditorColumnView` turns `pendingCaret`
/// into `caretRequest` on `initial: true`), so the request is already there on the text view's
/// very first update, before the view is in a window. Placing the selection works then; taking the
/// keyboard does not, and the claim has been spent - the first key went nowhere (R-08).
@MainActor
@Test func aCaretRequestPresentAtFirstRenderStillTakesTheKeyboard() async throws {
    let harness = Harness(caretRequest: .init(id: 1, offset: 9))
    await harness.settle()
    let textView = try #require(harness.textView)

    #expect(textView.selectedRange() == NSRange(location: 9, length: 0)) // R-08
    #expect(harness.model.caretApplied == 1)
    #expect(harness.host.window.firstResponder === textView) // R-08: the first key lands in the note
    finish(harness)
}
