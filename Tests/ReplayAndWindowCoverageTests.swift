import AppKit
import Foundation
import Testing
@testable import Pergamenum

// (coverage) Plan docs/plans/scoped-layout-followup.md, Task 7.
//
// Business logic the diff of ADR-0093 touches that no requirement test exercised on its own: the line
// reader the windowed renumbering is built on, the coordinator's call of the windowed form, the undo
// observations that replay the edit path, and the composed-text hook. Each asserts only what the
// plan, ADR-0093 or an existing caller already states; none of them is an R-id.

@MainActor
@Suite(.serialized) struct ReplayAndWindowCoverage {
    private func spinTheMainQueue() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
    }

    // MARK: LineScan.line(at:in:)

    // (coverage) The single-line reader answers what `lines(in:)` answers at the same line, from the
    // line's first character and from one inside it, whatever the terminator: the windowed renumbering
    // reads lines through it (ADR-0093 §D8) and must split the text where the whole-text form splits it.
    @Test(arguments: [
        "a\nb\n",
        "a\r\nb\r\nc",
        "a\rb\rc\r",
        "a\u{85}b\u{2028}c\u{2029}d",
        "\n\n  \n\t\nx",
        "",
        "no terminator at all",
    ])
    func theSingleLineReaderAgreesWithTheWholeTextScan(_ text: String) {
        let ns = text as NSString
        for line in LineScan.lines(in: ns) where line.start < ns.length {
            let indexes = [line.start] + (line.start + 1 < line.end ? [line.end - 1] : [])
            for index in indexes {
                let single = LineScan.line(at: index, in: ns)
                #expect(
                    (single.start, single.contentEnd, single.end) == (line.start, line.contentEnd, line.end),
                    "at \(index) in \(text.debugDescription)"
                )
            }
        }
    }

    // MARK: The coordinator's windowed renumbering

    private func twinPair(_ text: String) -> (incremental: ScrolledEditorFixture, full: ScrolledEditorFixture) {
        (
            ScrolledEditorFixture(text: text, forcesFullRestyle: false),
            ScrolledEditorFixture(text: text, forcesFullRestyle: true)
        )
    }

    private let fencedNote = "intro\n\n```\n1. a\n3. b\n```\n\n1. x\n2. y\n3. z\n"

    // (coverage) A digit typed on an ordered item that sits inside an open fence renumbers nothing, in
    // the editor that reads the window as in the one that reads the whole text: the window carries the
    // fence parity of its start (ADR-0093 §D8, the SPEC's edge case "renumbering across a fence").
    @Test func aDigitTypedInsideAFenceRenumbersNothingThroughTheWindow() throws {
        let (incremental, full) = twinPair(fencedNote)
        defer { incremental.window.orderOut(nil); full.window.orderOut(nil) }
        let digit = (fencedNote as NSString).range(of: "3. b")
        let edit = NSRange(location: digit.location, length: 1)

        incremental.type("7", over: edit)
        full.type("7", over: edit)

        let typedOnly = (fencedNote as NSString).replacingCharacters(in: edit, with: "7")
        #expect(incremental.textView.string == typedOnly, "the windowed editor renumbered a run inside a fence")
        #expect(full.textView.string == typedOnly)
        // Non-vacuity: the window the editor read had the fence open, and did not start at the top.
        let window = try #require(incremental.coordinator.restyleScope?.renumberWindow(before: edit.location))
        #expect(window.fenceOpen)
        #expect(window.start > 0)
    }

    // (coverage) The same edit in a list below the fence renumbers it, and the windowed editor's text
    // is the full-restyle editor's, which reads the scoped form.
    @Test func aDigitTypedInAListBelowAFenceRenumbersLikeTheScopedForm() throws {
        let (incremental, full) = twinPair(fencedNote)
        defer { incremental.window.orderOut(nil); full.window.orderOut(nil) }
        let digit = (fencedNote as NSString).range(of: "2. y")
        let edit = NSRange(location: digit.location, length: 1)

        incremental.type("5", over: edit)
        full.type("5", over: edit)

        let typedOnly = (fencedNote as NSString).replacingCharacters(in: edit, with: "5")
        #expect(incremental.textView.string == full.textView.string)
        #expect(incremental.textView.string != typedOnly, "nothing was renumbered after the keystroke")
        let window = try #require(incremental.coordinator.restyleScope?.renumberWindow(before: edit.location))
        #expect(!window.fenceOpen, "the fence above is closed again at the list")
    }

    // MARK: The undo observations (ADR-0093 §D7)

    // (coverage) The two observations follow `undoManager`: two on a manager, none on nil, the same two
    // on the same manager again, two on another, and none after the dismantle.
    @Test func theUndoObservationsFollowTheManagerAndEndWithTheDismantle() {
        let fixture = ScrolledEditorFixture(text: "Una riga di prosa.\n")
        defer { fixture.window.orderOut(nil) }
        let coordinator = fixture.coordinator
        let first = UndoManager()
        let second = UndoManager()

        coordinator.undoManager = first
        #expect(coordinator.undoObservers.count == 2)
        let kept = coordinator.undoObservers.map { ObjectIdentifier($0 as AnyObject) }
        coordinator.undoManager = first
        #expect(coordinator.undoObservers.map { ObjectIdentifier($0 as AnyObject) } == kept, "the same manager moved the observers")

        coordinator.undoManager = nil
        #expect(coordinator.undoObservers.isEmpty)
        coordinator.undoManager = second
        #expect(coordinator.undoObservers.count == 2)

        NoteTextView.dismantleNSView(fixture.scrollView, coordinator: coordinator)
        #expect(coordinator.undoObservers.isEmpty, "the dismantle left the observations standing")
    }

    // (coverage) A did-undo from the current manager replays the edit path while an edit is unstyled,
    // and from nowhere else: not from a manager the coordinator left, and not when nothing is unstyled
    // (the sidebar's move-undo shares the window's manager, ADR-0026 §D8).
    @Test func aDidUndoReplaysTheEditPathOnlyForTheCurrentManagerAndOnlyWhileUnstyled() throws {
        let bound = BoundText("Una riga di prosa.\n")
        let fixture = ScrolledEditorFixture(text: bound.value, bound: bound)
        defer { fixture.window.orderOut(nil) }
        let coordinator = fixture.coordinator
        let old = UndoManager()
        let current = UndoManager()
        coordinator.undoManager = old
        coordinator.undoManager = current
        let storage = try #require(fixture.textView.textStorage)

        // Nothing unstyled: the notification replays nothing.
        #expect(!coordinator.hasUnstyledEdits)
        let quiet = bound.writes
        NotificationCenter.default.post(name: .NSUndoManagerDidUndoChange, object: current)
        spinTheMainQueue()
        #expect(bound.writes == quiet, "a notification with nothing unstyled ran the edit path")

        // An edit the storage reported and nothing styled: the manager the coordinator left is not heard.
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "x")
        #expect(coordinator.hasUnstyledEdits, "premessa: the edit has to be unstyled")
        NotificationCenter.default.post(name: .NSUndoManagerDidUndoChange, object: old)
        spinTheMainQueue()
        #expect(coordinator.hasUnstyledEdits, "a manager the coordinator left replayed the edit path")
        #expect(bound.writes == quiet)

        // The current manager's did-undo and did-redo each replay it.
        NotificationCenter.default.post(name: .NSUndoManagerDidUndoChange, object: current)
        spinTheMainQueue()
        #expect(!coordinator.hasUnstyledEdits, "the current manager's did-undo did not replay the edit path")
        #expect(bound.writes == quiet + 1)
        #expect(bound.value == fixture.textView.string)

        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "y")
        #expect(coordinator.hasUnstyledEdits)
        NotificationCenter.default.post(name: .NSUndoManagerDidRedoChange, object: current)
        spinTheMainQueue()
        #expect(!coordinator.hasUnstyledEdits, "the current manager's did-redo did not replay the edit path")
    }

    // (coverage) A replay does not renumber: the text an undo restores was renumbered when it was
    // first written, and a renumber written after the undo would empty the redo stack (ADR-0093 §D7).
    @Test func aReplayLeavesAMisnumberedRunAsItFoundIt() throws {
        let misnumbered = "1. a\n5. b\n"
        let fixture = ScrolledEditorFixture(text: misnumbered)
        defer { fixture.window.orderOut(nil) }
        let storage = try #require(fixture.textView.textStorage)
        let location = (misnumbered as NSString).length

        storage.replaceCharacters(in: NSRange(location: location, length: 0), with: "6. c\n")
        #expect(fixture.coordinator.hasUnstyledEdits)
        fixture.coordinator.replayEditIfUnstyled(in: fixture.textView)

        #expect(fixture.textView.string == misnumbered + "6. c\n", "the replay rewrote the run")
        #expect(!fixture.coordinator.hasUnstyledEdits)
    }

    // MARK: The composed-text hook (ADR-0093 §D7)

    // (coverage) `setMarkedText` calls the hook once per step and leaves the marked range where `super`
    // put it: the hook is a notification, not a second owner of the composition.
    @Test func eachMarkedTextStepCallsTheHookOnceAndLeavesTheMarkedRangeAlone() {
        let fixture = ScrolledEditorFixture(text: "Una riga di prosa.\n")
        defer { fixture.window.orderOut(nil) }
        var calls = 0
        fixture.textView.onComposedTextChanged = { calls += 1 }

        fixture.textView.setMarkedText(
            "ñ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: 3, length: 0)
        )
        #expect(calls == 1)
        #expect(fixture.textView.hasMarkedText())
        #expect(fixture.textView.markedRange() == NSRange(location: 3, length: 1))

        fixture.textView.setMarkedText(
            "ñé", selectedRange: NSRange(location: 2, length: 0), replacementRange: fixture.textView.markedRange()
        )
        #expect(calls == 2)
        #expect(fixture.textView.markedRange() == NSRange(location: 3, length: 2))
    }

    // MARK: textDidChange of another view

    // (coverage) A coordinator answers the change notification of the view it drives and no other: AppKit
    // keys a delegate's registration by the view's address, so a registration that outlived its view
    // can be met by a new view at the same address, and the stale coordinator then restyled it with its
    // own baseline and took the storage's delegate slot from the live one. Found when the full unit suite
    // measured 50 KB prose at 700 ms a keystroke against 6 ms alone.
    @Test func aCoordinatorIgnoresTheChangeNotificationOfAnotherView() {
        let note = "alpha\n\nbeta\n\ngamma\n"
        let mine = ScrolledEditorFixture(text: note)
        let other = ScrolledEditorFixture(text: note)
        defer { mine.window.orderOut(nil); other.window.orderOut(nil) }
        let before = mine.coordinator.restyleLog
        let otherStorage = other.textView.textStorage

        mine.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: other.textView))

        #expect(mine.coordinator.restyleLog == before, "a notification of another view restyled this coordinator's note")
        #expect(otherStorage?.delegate === other.coordinator, "the other view's storage lost its delegate")

        mine.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: mine.textView))
        #expect(mine.coordinator.restyleLog != before, "the coordinator's own notification no longer runs the passes")
    }
}
