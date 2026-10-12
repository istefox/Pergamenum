import AppKit
import Foundation
import Testing
@testable import Pergamenum

// ADR-0093 §D1, §D2, §D4, plan docs/plans/scoped-layout-followup.md, Task 3 (R-07).
//
// The record alone: a plain text view whose storage holds the text an edit is heard in, and edits
// reported by hand in the post-fixing range `didProcessEditing` gives: what it owes after each, and what
// a settle lays out and leaves owed.

private let note = "Prima riga di prosa.\nSeconda riga di prosa.\nTerza riga di prosa.\nQuarta riga di prosa.\n"

/// A content storage that can be told to fail every offset conversion, the way a layout manager whose
/// content moved on from the storage's length does.
private final class RefusingContentStorage: NSTextContentStorage {
    var refuses = false

    override func location(_ location: any NSTextLocation, offsetBy offset: Int) -> (any NSTextLocation)? {
        refuses ? nil : super.location(location, offsetBy: offset)
    }
}

@MainActor
@Suite struct LayoutDebtRecord {
    /// A text view holding `text`, and a record that has settled once, so nothing is owed.
    private func settledEditor(_ text: String = note) -> (view: NSTextView, debt: LayoutDebt) {
        let view = NSTextView(usingTextLayoutManager: true)
        view.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        view.string = text
        let debt = LayoutDebt()
        debt.settle(view, delegateIsCoordinator: true, forcesWhole: false)
        return (view, debt)
    }

    private func storage(of view: NSTextView) throws -> NSTextStorage {
        try #require(view.textStorage)
    }

    // MARK: Nothing, everything, ranges

    // (R-07) A record starts owing everything, and settling pays it.
    @Test func itStartsOwingEverythingAndSettlingPaysIt() throws {
        let view = NSTextView(usingTextLayoutManager: true)
        view.string = note
        let debt = LayoutDebt()
        #expect(debt.owed == .everything)

        debt.settle(view, delegateIsCoordinator: true, forcesWhole: false)

        #expect(debt.owed == .ranges([]), "settling left \(debt.owed) owed")
        #expect(debt.log.whole == 1)
        #expect(debt.log.lastWholeReason == .everythingOwed)
    }

    // (R-07) A typed character owes the range the storage reported for it.
    @Test func aTypedCharacterOwesItsRange() throws {
        let (view, debt) = settledEditor()
        debt.hear(StorageEdit(range: NSRange(location: 3, length: 1), delta: 1), in: try storage(of: view))
        #expect(debt.owed == .ranges([NSRange(location: 3, length: 1)]))
    }

    // (R-07) A later edit moves the ranges already owed, by its delta when it lies before them.
    @Test func aLaterEditShiftsTheRangeOwedBeforeIt() throws {
        let (view, debt) = settledEditor()
        let storage = try storage(of: view)
        debt.hear(StorageEdit(range: NSRange(location: 30, length: 1), delta: 1), in: storage)
        debt.hear(StorageEdit(range: NSRange(location: 3, length: 2), delta: 2), in: storage)
        #expect(debt.owed == .ranges([NSRange(location: 3, length: 2), NSRange(location: 32, length: 1)]))
    }

    // (R-07) An edit after a range leaves it where it is.
    @Test func aLaterEditAfterTheRangeLeavesItAlone() throws {
        let (view, debt) = settledEditor()
        let storage = try storage(of: view)
        debt.hear(StorageEdit(range: NSRange(location: 3, length: 1), delta: 1), in: storage)
        debt.hear(StorageEdit(range: NSRange(location: 40, length: 2), delta: 2), in: storage)
        #expect(debt.owed == .ranges([NSRange(location: 3, length: 1), NSRange(location: 40, length: 2)]))
    }

    // (R-07, edge case) A deletion reports an empty range: it owes the paragraph the deletion joined,
    // and never an empty range.
    @Test func aDeletionOwesTheParagraphItJoined() throws {
        let (view, debt) = settledEditor()
        let storage = try storage(of: view)
        let joined = (storage.string as NSString).paragraphRange(for: NSRange(location: 25, length: 0))
        debt.hear(StorageEdit(range: NSRange(location: 25, length: 0), delta: -3), in: storage)

        #expect(debt.owed == .ranges([joined]), "owed \(debt.owed), the paragraph is \(joined)")
        if case .ranges(let owed) = debt.owed { #expect(owed.allSatisfy { $0.length > 0 }) }
    }

    // MARK: Merging

    // (R-07) Adjacent ranges merge.
    @Test func adjacentRangesMerge() throws {
        let (view, debt) = settledEditor()
        let storage = try storage(of: view)
        debt.hear(StorageEdit(range: NSRange(location: 3, length: 1), delta: 1), in: storage)
        debt.hear(StorageEdit(range: NSRange(location: 4, length: 2), delta: 2), in: storage)
        #expect(debt.owed == .ranges([NSRange(location: 3, length: 3)]))
    }

    // (R-07) An edit inside a range stretches it, and the edit's own range is already in it.
    @Test func anEditInsideARangeStretchesIt() throws {
        let (view, debt) = settledEditor()
        let storage = try storage(of: view)
        debt.hear(StorageEdit(range: NSRange(location: 10, length: 5), delta: 5), in: storage)
        debt.hear(StorageEdit(range: NSRange(location: 12, length: 3), delta: 3), in: storage)
        #expect(debt.owed == .ranges([NSRange(location: 10, length: 8)]))
    }

    // (R-07) An edit that cuts a range's end owes the part outside it, joined to the edit's own range.
    @Test func anOverlappingEditOwesTheOutsidePartAndItsOwnRange() throws {
        let (view, debt) = settledEditor()
        let storage = try storage(of: view)
        debt.hear(StorageEdit(range: NSRange(location: 10, length: 5), delta: 5), in: storage)
        // Replaces old {12, 6} with two characters: the owed {10, 5} is cut at 12.
        debt.hear(StorageEdit(range: NSRange(location: 12, length: 2), delta: -4), in: storage)
        #expect(debt.owed == .ranges([NSRange(location: 10, length: 4)]))
    }

    // (R-07) A range covering the whole text is everything.
    @Test func aRangeCoveringTheWholeTextIsEverything() throws {
        let (view, debt) = settledEditor()
        let storage = try storage(of: view)
        debt.hear(StorageEdit(range: NSRange(location: 0, length: storage.length), delta: storage.length), in: storage)
        #expect(debt.owed == .everything)
    }

    // (R-07) An attribute-only edit adds its range and shifts nothing.
    @Test func anAttributeEditAddsItsRangeAndShiftsNothing() throws {
        let (view, debt) = settledEditor()
        let storage = try storage(of: view)
        debt.hear(StorageEdit(range: NSRange(location: 3, length: 1), delta: 1), in: storage)
        debt.hear(StorageEdit(range: NSRange(location: 0, length: 10), delta: 0), in: storage)
        #expect(debt.owed == .ranges([NSRange(location: 0, length: 10)]), "the attribute edit over the range merges with it")
        debt.hear(StorageEdit(range: NSRange(location: 40, length: 5), delta: 0), in: storage)
        #expect(debt.owed == .ranges([NSRange(location: 0, length: 10), NSRange(location: 40, length: 5)]))
    }

    // MARK: Everything

    // (R-07) `oweEverything()` is what installing the delegate calls.
    @Test func oweEverythingOwesEverything() throws {
        let (view, debt) = settledEditor()
        debt.hear(StorageEdit(range: NSRange(location: 3, length: 1), delta: 1), in: try storage(of: view))
        debt.oweEverything()
        #expect(debt.owed == .everything)
    }

    // (R-08) The door owes everything and invalidates the layout.
    @Test func theDoorOwesEverything() throws {
        let (view, debt) = settledEditor()
        #expect(debt.owed == .ranges([]))

        debt.invalidateWholeDocument(of: view)

        #expect(debt.owed == .everything, "the door left \(debt.owed) owed")
    }

    // MARK: Settling

    // (R-02, R-05) What is owed is laid out as ranges, widened by a character on each side, and the
    // log says so; a second settle with nothing owed lays out nothing.
    @Test func settlingLaysOutTheOwedRangesThenNothing() throws {
        let (view, debt) = settledEditor()
        let before = debt.log
        debt.hear(StorageEdit(range: NSRange(location: 25, length: 1), delta: 1), in: try storage(of: view))

        debt.settle(view, delegateIsCoordinator: true, forcesWhole: false)

        #expect(debt.log.ranged == before.ranged + 1)
        #expect(debt.log.whole == before.whole)
        #expect(debt.owed == .ranges([]))
        let laid = debt.log.lastRanges
        #expect(!laid.isEmpty)
        // The owed range, or that range widened by a character on each side: what the log records.
        let owedRange = NSRange(location: 25, length: 1)
        let widened = NSRange(location: 24, length: 3)
        #expect(laid == [owedRange] || laid == [widened], "laid out \(laid), not \(owedRange) widened to \(widened)")

        debt.settle(view, delegateIsCoordinator: true, forcesWhole: false)
        #expect(debt.log.empty == before.empty + 1)
        #expect(debt.log.ranged == before.ranged + 1)
    }

    // (R-02) A foreign delegate vouches for nothing: the whole note, and the reason is named.
    @Test func aForeignDelegateMeansWholeLayout() throws {
        let (view, debt) = settledEditor()
        let before = debt.log
        debt.settle(view, delegateIsCoordinator: false, forcesWhole: false)
        #expect(debt.log.whole == before.whole + 1)
        #expect(debt.log.lastWholeReason == .foreignDelegate)
    }

    // (R-09) The kill switch lays out the whole note on every settle, owed or not.
    @Test func theKillSwitchMeansWholeLayout() throws {
        let (view, debt) = settledEditor()
        let before = debt.log
        debt.hear(StorageEdit(range: NSRange(location: 3, length: 1), delta: 1), in: try storage(of: view))
        debt.settle(view, delegateIsCoordinator: true, forcesWhole: true)
        debt.settle(view, delegateIsCoordinator: true, forcesWhole: true)
        #expect(debt.log.whole == before.whole + 2)
        #expect(debt.log.lastWholeReason == .killSwitch)
        #expect(debt.log.ranged == before.ranged)
    }

    // (R-07) A new container width is the third way a fragment loses its layout, and owes the note.
    @Test func aNewContainerWidthMeansWholeLayout() throws {
        let (view, debt) = settledEditor()
        let before = debt.log
        let container = try #require(view.textContainer)
        container.widthTracksTextView = false
        container.size = NSSize(width: 321.5, height: container.size.height)

        debt.settle(view, delegateIsCoordinator: true, forcesWhole: false)

        #expect(debt.log.whole == before.whole + 1)
        #expect(debt.log.lastWholeReason == .widthChanged)
    }

    // (R-02) A storage whose length is not the one the record last heard changed without being heard.
    @Test func aLengthTheRecordNeverHeardMeansWholeLayout() throws {
        let (view, debt) = settledEditor()
        let storage = try storage(of: view)
        debt.hear(StorageEdit(range: NSRange(location: 3, length: 1), delta: 1), in: storage)
        debt.settle(view, delegateIsCoordinator: true, forcesWhole: false)
        let before = debt.log
        // A change nothing reported: no delegate is installed on this storage.
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "Una riga in più.\n")

        debt.settle(view, delegateIsCoordinator: true, forcesWhole: false)

        #expect(debt.log.whole == before.whole + 1)
        #expect(debt.log.lastWholeReason == .lengthMismatch)
    }

    // A range that cannot be turned into an NSTextRange was not laid out, so it is not forgotten:
    // everything is owed again, the log counts it, and the next settle lays the note out whole.
    @Test func aRangeThatCannotBeConvertedKeepsTheNoteOwed() throws {
        let content = RefusingContentStorage()
        let layout = NSTextLayoutManager()
        content.addTextLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 400, height: 0))
        layout.textContainer = container
        let view = NSTextView(frame: CGRect(x: 0, y: 0, width: 400, height: 300), textContainer: container)
        view.string = note
        let debt = LayoutDebt()
        debt.settle(view, delegateIsCoordinator: true, forcesWhole: false)
        let storage = try #require(view.textStorage)
        debt.hear(StorageEdit(range: NSRange(location: 3, length: 1), delta: 0), in: storage)
        #expect(debt.owed == .ranges([NSRange(location: 3, length: 1)]))

        content.refuses = true
        debt.settle(view, delegateIsCoordinator: true, forcesWhole: false)

        #expect(debt.owed == .everything, "the unconverted range was dropped: \(debt.owed)")
        #expect(debt.log.unconverted == 1)

        content.refuses = false
        debt.settle(view, delegateIsCoordinator: true, forcesWhole: false)

        #expect(debt.log.lastWholeReason == .everythingOwed)
        #expect(debt.owed == .ranges([]))
    }
}
