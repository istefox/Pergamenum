import AppKit
import SwiftUI
import Testing
@testable import Pergamenum

/// ADR-0074 G2 H5: a cell edit made in the drawn grid reaches the note. `TableEditTests` drives
/// `Coordinator.commitTable` directly; this file drives the path in front of it - the grid the
/// real styling pass vends (`TableGridStore.view(for:in:)` through `applyStyling`), its
/// `NSTextFieldDelegate` methods (`TableGridView+CellCommit.swift`) and the `onCommit` closure
/// `TableBlockController.apply` wires - so a regression in the wiring between them shows here.
///
/// The fixture is `TableGridHostedAttachmentTests`' (text view inside a real `NSScrollView` in an
/// offscreen window that is never ordered front, R-15). Nothing is sent through the window: the
/// delegate methods are called the way AppKit calls them, and first responder is moved with
/// `makeFirstResponder`, which needs no event.

/// The model the editor's binding reads and writes, so `parent.text` follows the buffer the way
/// it does in the app (`textDidChange` writes back through it). `commitTable`'s D8 guard compares
/// the two, and a `.constant` binding would refuse every commit after the first.
@MainActor
private final class NoteBox {
    var text: String
    init(_ text: String) { self.text = text }
}

@MainActor
private struct HostedTable {
    let box: NoteBox
    let textView: CompletingTextView
    let coordinator: NoteTextView.Coordinator
    let window: NSWindow
    let grid: TableGridView
}

private let note = "prima\n| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\ndopo\n"
/// "prima\n" is six characters; the table's header paragraph starts right after it.
private let headerOffset = 6

@MainActor
private func hostedTable() throws -> HostedTable {
    let box = NoteBox(note)
    let view = NoteTextView(
        text: Binding(get: { box.text }, set: { box.text = $0 }), theme: .emergency, noteTitles: [], tagSuggestions: [],
        hidesMarkup: true, onFollowLink: { _ in }
    )
    let coordinator = view.makeCoordinator()
    let textView = CompletingTextView(usingTextLayoutManager: true)
    textView.delegate = coordinator
    textView.isRichText = false
    textView.allowsUndo = true
    textView.textContainerInset = NSSize(width: 24, height: 20)
    textView.isVerticallyResizable = true
    textView.autoresizingMask = [.width]
    textView.frame = CGRect(x: 0, y: 0, width: 600, height: 700)
    textView.textContainer?.size = CGSize(width: 552, height: CGFloat.greatestFiniteMagnitude)
    coordinator.textView = textView
    textView.textContentStorage?.delegate = coordinator.decorations
    textView.textLayoutManager?.delegate = coordinator.decorations
    view.wire(textView, to: coordinator)
    textView.string = note

    let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 600, height: 700))
    scroll.documentView = textView
    scroll.hasVerticalScroller = true
    let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 600, height: 700),
        styleMask: [.titled], backing: .buffered, defer: false
    )
    window.contentView = scroll
    window.layoutIfNeeded()

    coordinator.applyStyling(to: textView, theme: .emergency)
    let layout = try #require(textView.textLayoutManager)
    layout.ensureLayout(for: layout.documentRange)
    textView.layoutSubtreeIfNeeded()
    layout.textViewportLayoutController.layoutViewport()

    let grid = try #require(coordinator.decorations.tableViews[headerOffset], "nessuna griglia costruita")
    return HostedTable(box: box, textView: textView, coordinator: coordinator, window: window, grid: grid)
}

@MainActor
private func endEditing(_ field: NSTextField, in grid: TableGridView) {
    grid.controlTextDidEndEditing(
        Notification(name: NSControl.textDidEndEditingNotification, object: field)
    )
}

@MainActor
@Suite struct TableGridCommit {
    /// H5: the grid `applyStyling` vended is the one wired to the note - a cell edited and ended
    /// commits through `onCommit` into `commitTable`, rewriting the note's own source, and the
    /// note is restored by one undo. That undo half catches a missing undo registration, not a split
    /// within one event (event grouping merges those in production too).
    @Test func anEditedCellCommitsToTheNoteSourceAndOneUndoRestoresTheNote() throws {
        let fixture = try hostedTable()
        defer { fixture.window.orderOut(nil) }
        let undo = try #require(fixture.textView.undoManager)
        // Row 0 of `fields` is the header, so the first body cell is `fields[1][0]`.
        let field = try #require(fixture.grid.fields.dropFirst().first?.first)
        #expect(field.stringValue == "1")

        field.stringValue = "9"
        endEditing(field, in: fixture.grid)

        #expect(fixture.textView.string.contains("| 9 | 2 |"))
        #expect(fixture.textView.string.hasPrefix("prima\n") && fixture.textView.string.hasSuffix("dopo\n"))

        undo.undo()

        #expect(fixture.textView.string == note)
        #expect(!undo.canUndo, "one undo must have consumed the whole commit")
    }

    /// H5: an unchanged cell is not a write - ending an edit that changed nothing leaves the
    /// note, and the undo stack, alone.
    @Test func endingAnEditThatChangedNothingWritesNothing() throws {
        let fixture = try hostedTable()
        defer { fixture.window.orderOut(nil) }
        let undo = try #require(fixture.textView.undoManager)
        let field = try #require(fixture.grid.fields.dropFirst().first?.first)

        endEditing(field, in: fixture.grid)

        #expect(fixture.textView.string == note)
        #expect(!undo.canUndo)
    }

    /// H5: Tab out of the last cell and Enter in any cell both hand first responder back to the
    /// text view (`resignToTextView`), and a cell edited in a live field editor commits when that
    /// session ends - the single write path §D7 promises, reached through AppKit's own
    /// `textDidEndEditing` rather than by calling the delegate by hand.
    @Test func enterInAnEditedCellCommitsAndReturnsTheKeyboardToTheNote() throws {
        let fixture = try hostedTable()
        defer { fixture.window.orderOut(nil) }
        let field = try #require(fixture.grid.fields.dropFirst().first?.first)
        #expect(fixture.window.makeFirstResponder(field), "premessa: la cella deve poter prendere il fuoco")
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.string = "9"

        let handled = fixture.grid.control(
            field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))
        )

        #expect(handled)
        #expect(fixture.window.firstResponder === fixture.textView)
        #expect(fixture.textView.string.contains("| 9 | 2 |"))
    }

    @Test func tabLeavesTheGridOnlyFromTheLastCellAndShiftTabOnlyFromTheFirst() throws {
        let fixture = try hostedTable()
        defer { fixture.window.orderOut(nil) }
        let grid = fixture.grid
        let flat = grid.fields.flatMap { $0 }
        let first = try #require(flat.first)
        let last = try #require(flat.last)
        let editor = NSTextView()
        var resigned = 0
        grid.resignToTextView = { resigned += 1 }

        // A cell in the middle is AppKit's: Tab walks the key-view chain, nothing resigns.
        #expect(!grid.control(first, textView: editor, doCommandBy: #selector(NSResponder.insertTab(_:))))
        #expect(!grid.control(last, textView: editor, doCommandBy: #selector(NSResponder.insertBacktab(_:))))
        #expect(resigned == 0)

        #expect(grid.control(last, textView: editor, doCommandBy: #selector(NSResponder.insertTab(_:))))
        #expect(grid.control(first, textView: editor, doCommandBy: #selector(NSResponder.insertBacktab(_:))))
        #expect(resigned == 2)
    }

    /// H5: Tab from the last cell commits the edited cell and leaves the caret in the note,
    /// in the same order AppKit runs them (resign, which ends the field editor's session, which
    /// commits).
    @Test func tabFromTheLastCellCommitsItsEditAndLeavesTheGrid() throws {
        let fixture = try hostedTable()
        defer { fixture.window.orderOut(nil) }
        let last = try #require(fixture.grid.fields.flatMap { $0 }.last)
        #expect(last.stringValue == "4")
        #expect(fixture.window.makeFirstResponder(last), "premessa: la cella deve poter prendere il fuoco")
        let editor = try #require(last.currentEditor() as? NSTextView)
        editor.string = "8"

        let handled = fixture.grid.control(last, textView: editor, doCommandBy: #selector(NSResponder.insertTab(_:)))

        #expect(handled)
        #expect(fixture.window.firstResponder === fixture.textView)
        #expect(fixture.textView.string.contains("| 3 | 8 |"))
    }

    /// H5: the structural buttons rewrite the note. With no cell focused the anchor is the last
    /// row, so add-row appends after it and remove-row drops it.
    @Test func addRowAndRemoveRowRewriteTheNoteSource() throws {
        let fixture = try hostedTable()
        defer { fixture.window.orderOut(nil) }

        fixture.grid.addRowTapped()

        let lines = fixture.textView.string.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines.count == 8, "una riga in più nella tabella: \(fixture.textView.string.debugDescription)")
        #expect(lines.contains { $0.replacingOccurrences(of: " ", with: "") == "|||" })
        #expect(lines.first == "prima" && lines.dropLast().last == "dopo")

        fixture.grid.removeRowTapped()

        #expect(fixture.textView.string == note)
    }
}
