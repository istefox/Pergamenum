import AppKit
import Testing
@testable import Pergamenum

// `HiddenBlockLines` and `CaretRescue` (ADR-0074 §D8): the line walk `applyTables` and
// `applyViewBlocks` share, and the rescue rule the table, view-block and fold passes share.
//
// Selection semantics pinned here are the ones the three callers (`TableBlockController.caretRescue`,
// `ViewBlockController.caretRescue`, `FoldController.rescueCaret`) agree on: only `selection.location` is read, its
// length is ignored, and a location past the end of the text is left alone.

@Suite struct HiddenBlockLinesWalk {
    private func lines(_ source: String, anchor: Int = 0, kind: HiddenMarker.Kind = .table) -> HiddenBlockLines {
        let text = source as NSString
        let run = EditorDecorationDelegate.tableRun(in: text, atParagraphStart: anchor)
        let range = run?.range ?? NSRange(location: anchor, length: text.length - anchor)
        return HiddenBlockLines(text: text, anchor: anchor, range: range, kind: kind)
    }

    @Test func twoLineTableHidesTheDelimiterAndTheBodyRowStarts() {
        let source = "| a |\n| - |\n| 1 |\n"
        let walked = lines(source)
        #expect(walked.starts == [6, 12])
        #expect(walked.marker == HiddenMarker(range: NSRange(location: 0, length: 5), kind: .table))
    }

    @Test func tableAtTheEndOfTextWithoutATrailingNewlineStillListsItsLastRow() {
        let source = "| a |\n| - |\n| 1 |"
        let walked = lines(source)
        #expect(walked.starts == [6, 12])
        #expect(walked.lines.last?.contentsEnd == (source as NSString).length)
    }

    @Test func crlfTableGivesTheStartsAfterEachTwoCharacterBreak() {
        let source = "| a |\r\n| - |\r\n| 1 |\r\n"
        let walked = lines(source)
        #expect(walked.starts == [7, 14])
        #expect(walked.marker == HiddenMarker(range: NSRange(location: 0, length: 5), kind: .table))
        #expect(walked.lines.map(\.contentsEnd) == [12, 19])
    }

    @Test func markerAndLinesAreAnchoredAtTheAnchorParagraphNotAtTheTextStart() {
        let source = "intro\n| a |\n| - |\n"
        let walked = lines(source, anchor: 6)
        #expect(walked.starts == [12])
        #expect(walked.marker == HiddenMarker(range: NSRange(location: 0, length: 5), kind: .table))
    }

    @Test func anEmptyAnchorParagraphHasNoMarker() {
        let source = "\nbody\n"
        let text = source as NSString
        let walked = HiddenBlockLines(
            text: text, anchor: 0, range: NSRange(location: 0, length: text.length), kind: .viewBlock
        )
        #expect(walked.marker == nil)
    }

    @Test func aViewBlockFenceListsItsBodyAndClosingLine() {
        let source = "```pergamenum-view\nwhere x\n```\n"
        let text = source as NSString
        let run = EditorDecorationDelegate.viewBlockRun(in: text, atParagraphStart: 0)
        let walked = HiddenBlockLines(
            text: text, anchor: 0, range: run?.range ?? NSRange(location: 0, length: 0), kind: .viewBlock
        )
        #expect(walked.starts == [19, 27])
        #expect(walked.marker == HiddenMarker(range: NSRange(location: 0, length: 18), kind: .viewBlock))
    }
}

@Suite struct CaretRescueTarget {
    private let text = "head\nrow one\nrow two\nafter\n" as NSString

    @Test func aCaretOnAHiddenLineGoesToItsOwnersTarget() {
        let target = CaretRescue.target(
            for: NSRange(location: 8, length: 0), hidden: [5, 13], in: text, owner: { $0 == 5 ? 0 : nil }
        )
        #expect(target == 0)
    }

    @Test func aCaretOnAVisibleLineStays() {
        let target = CaretRescue.target(
            for: NSRange(location: 22, length: 0), hidden: [5, 13], in: text, owner: { _ in 0 }
        )
        #expect(target == nil)
    }

    @Test func aHiddenLineWhoseOwnerNamesNothingStays() {
        let target = CaretRescue.target(
            for: NSRange(location: 8, length: 0), hidden: [5], in: text, owner: { _ in nil }
        )
        #expect(target == nil)
    }

    @Test func noHiddenLinesMeansNoRescue() {
        let target = CaretRescue.target(
            for: NSRange(location: 8, length: 0), hidden: [], in: text, owner: { _ in 0 }
        )
        #expect(target == nil)
    }

    @Test func aCaretPastTheEndOfTheTextStays() {
        let target = CaretRescue.target(
            for: NSRange(location: text.length + 1, length: 0), hidden: [5], in: text, owner: { _ in 0 }
        )
        #expect(target == nil)
    }

    @Test func aSelectionIsJudgedByItsStartAlone() {
        // Starts on a visible line and runs across a hidden one: not rescued.
        let startsVisible = CaretRescue.target(
            for: NSRange(location: 1, length: 15), hidden: [5, 13], in: text, owner: { _ in 0 }
        )
        #expect(startsVisible == nil)
        // Starts on a hidden line and runs out to a visible one: rescued.
        let startsHidden = CaretRescue.target(
            for: NSRange(location: 8, length: 15), hidden: [5, 13], in: text, owner: { _ in 0 }
        )
        #expect(startsHidden == 0)
    }

    @Test func theOwnerReceivesTheParagraphStartNotTheCaret() {
        var received: [Int] = []
        _ = CaretRescue.target(
            for: NSRange(location: 15, length: 0), hidden: [13], in: text, owner: { received.append($0); return 0 }
        )
        #expect(received == [13])
    }
}

@MainActor
@Suite struct CaretRescuePlace {
    private func plainTextView(_ text: String) -> NSTextView {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        view.string = text
        return view
    }

    @Test func placingAnOffsetMovesTheSelectionThere() {
        let view = plainTextView("abcdef")
        view.setSelectedRange(NSRange(location: 5, length: 0))
        CaretRescue.place(2, in: view)
        #expect(view.selectedRange() == NSRange(location: 2, length: 0))
    }

    @Test func placingNilLeavesTheSelectionAlone() {
        let view = plainTextView("abcdef")
        view.setSelectedRange(NSRange(location: 3, length: 1))
        CaretRescue.place(nil, in: view)
        #expect(view.selectedRange() == NSRange(location: 3, length: 1))
    }
}

// MARK: - The wiring, end to end

/// The rescue rule is pinned above on synthetic owners. These drive the real styling and
/// folding passes on a real `NSTextView`, so the owner each pass names and the `place` call
/// that follows it are pinned too. Offscreen, no window: nothing here takes the screen.
@MainActor
@Suite struct CaretRescueWiring {
    private static func editor(_ text: String) -> (NSTextView, NoteTextView.Coordinator) {
        let view = NoteTextView(
            text: .constant(text), theme: .emergency, noteTitles: [], tagSuggestions: [],
            hidesMarkup: true, onFollowLink: { _ in }
        )
        let coordinator = view.makeCoordinator()
        let textView = CompletingTextView(usingTextLayoutManager: true)
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.frame = CGRect(x: 0, y: 0, width: 600, height: 800)
        textView.textContainer?.size = CGSize(width: 552, height: CGFloat.greatestFiniteMagnitude)
        coordinator.textView = textView
        textView.textContentStorage?.delegate = coordinator.decorations
        textView.textLayoutManager?.delegate = coordinator.decorations
        textView.string = text
        return (textView, coordinator)
    }

    /// Header at 0, delimiter row at 6, body row at 12 ("| 1 |" spans 12 ..< 17).
    private static let table = "| a |\n| - |\n| 1 |\n"

    @Test func aCaretInATableBodyRowMovesToTheHeaderOffsetWhenTheRowsLeaveTheLayout() {
        let (textView, coordinator) = Self.editor(Self.table)
        // The caret is already in the body row when the rows are first hidden.
        textView.setSelectedRange(NSRange(location: 14, length: 0))
        coordinator.applyStyling(to: textView, theme: .emergency)

        #expect(coordinator.tables.hiddenRows == [6, 12])
        #expect(textView.selectedRange() == NSRange(location: 0, length: 0))
        #expect(coordinator.tables.pendingCaret == nil)
    }

    @Test func aCaretInATableHeaderStaysWhereItIs() {
        let (textView, coordinator) = Self.editor(Self.table)
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        coordinator.applyStyling(to: textView, theme: .emergency)

        #expect(coordinator.tables.hiddenRows == [6, 12])
        #expect(textView.selectedRange() == NSRange(location: 3, length: 0))
    }

    @Test func aCaretInsideAFoldedSectionMovesToTheHeadingThatSwallowedIt() {
        let note = "# Uno\ncorpo uno\ncorpo due\n\n# Due\ncorpo tre\n"
        let (textView, coordinator) = Self.editor(note)
        coordinator.applyStyling(to: textView, theme: .emergency)
        // "# Due" starts at 27 and "corpo tre" at 33; entry 1 is the second heading, so an
        // owner that fell back to the first one would answer 0 and not 27.
        textView.setSelectedRange(NSRange(location: 35, length: 0))
        coordinator.applyFolding(to: textView, folded: [1], theme: .emergency)

        #expect(textView.selectedRange() == NSRange(location: 27, length: 0))
    }
}
