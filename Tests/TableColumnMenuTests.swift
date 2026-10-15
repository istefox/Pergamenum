import AppKit
import SwiftUI
import Testing
@testable import Pergamenum

// ADR-0087 §D11, plan docs/plans/note-workflow-n5.md, Task 3 (R-41).
//
// A table column's menu changes its alignment by rewriting the delimiter row and sorts the rows by
// that column, each as one undo step. Pure first (the entries, their titles, the edit each makes),
// then through the real grid the styling pass vends, in `TableGridCommitTests`' fixture.

@Suite struct TableColumnMenuEntries {
    @Test func aLeftAlignedColumnOffersThreeAlignsWithLeftTickedThenTwoSorts() { // R-41
        let entries = TableColumnMenu.entries(current: .leading)
        #expect(entries.count == 5, "\(entries)")
        guard entries.count == 5 else { return }

        var aligns: [GFMTable.Alignment: Bool] = [:]
        for entry in entries.prefix(3) {
            guard case .align(let alignment, let isCurrent) = entry else {
                Issue.record("le prime tre voci devono essere allineamenti: \(entries)")
                return
            }
            aligns[alignment] = isCurrent
        }
        #expect(aligns == [.leading: true, .center: false, .trailing: false])

        var directions: Set<Bool> = []
        for entry in entries.suffix(2) {
            guard case .sort(let ascending) = entry else {
                Issue.record("le ultime due voci devono essere ordinamenti: \(entries)")
                return
            }
            directions.insert(ascending)
        }
        #expect(directions == [true, false])
    }

    @Test func theTickFollowsTheCurrentAlignment() { // R-41
        let entries = TableColumnMenu.entries(current: .trailing)
        let ticked = entries.compactMap { entry -> GFMTable.Alignment? in
            if case .align(let alignment, true) = entry { alignment } else { nil }
        }
        #expect(ticked == [.trailing])
    }

    @Test func theTitlesAreTheItalianLabels() { // R-41
        #expect(TableColumnMenu.title(of: .align(.trailing, isCurrent: false)) == "Allinea a destra")
        #expect(TableColumnMenu.title(of: .sort(ascending: true)) == "Ordina A→Z")
    }

    @Test func everyEntryHasAnOwnTitle() { // R-41
        let titles = TableColumnMenu.entries(current: .center).map(TableColumnMenu.title(of:))
        #expect(titles.allSatisfy { !$0.isEmpty })
        #expect(Set(titles).count == titles.count, "\(titles)")
    }

    @Test func choosingTheAlignmentTheColumnAlreadyHasIsNoEdit() { // R-41
        #expect(TableColumnMenu.edit(for: .align(.leading, isCurrent: true), column: 0) == nil)
    }

    @Test func choosingAnotherAlignmentOrASortIsTheMatchingTableEdit() { // R-41
        #expect(
            TableColumnMenu.edit(for: .align(.trailing, isCurrent: false), column: 1)
                == TableEdit.align(column: 1, .trailing)
        )
        #expect(
            TableColumnMenu.edit(for: .sort(ascending: false), column: 2) == TableEdit.sort(column: 2, ascending: false)
        )
    }
}

// MARK: - Through the grid

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

/// "prima\n" is six characters; the table's header paragraph starts right after it.
private let headerOffset = 6

@MainActor
private func hostedTable(_ note: String) throws -> HostedTable {
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

private func descendants(of view: NSView) -> [NSView] {
    view.subviews + view.subviews.flatMap(descendants(of:))
}

@MainActor
@Suite struct TableColumnMenuOnTheGrid {
    private static let alignNote = "prima\n| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\ndopo\n"
    private static let sortNote = "prima\n| k | v |\n|---|---|\n| 3 | x |\n| 1 | y |\ndopo\n"

    private static func rightClick(in window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(
            with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )!
    }

    /// The menu a right-click on the header cell of `column` opens.
    private static func headerMenu(_ fixture: HostedTable, column: Int) throws -> NSMenu {
        let header = try #require(fixture.grid.fields.first, "nessuna riga di intestazione")
        let field = try #require(header.indices.contains(column) ? header[column] : nil)
        return try #require(
            field.menu(for: rightClick(in: fixture.window)) ?? field.menu, "nessun menu sull'intestazione"
        )
    }

    private static func choose(_ title: String, in menu: NSMenu) throws {
        let item = try #require(
            menu.items.first { $0.title == title }, "nessuna voce «\(title)» in \(menu.items.map(\.title))"
        )
        let action = try #require(item.action)
        NSApp.sendAction(action, to: item.target, from: item)
    }

    @Test func choosingAlignRightOnColumnOneCommitsOnceAndRewritesTheDelimiterRow() throws { // R-41
        let fixture = try hostedTable(Self.alignNote)
        defer { fixture.window.orderOut(nil) }
        let undo = try #require(fixture.textView.undoManager)

        try Self.choose("Allinea a destra", in: Self.headerMenu(fixture, column: 1))

        #expect(fixture.textView.string == "prima\n| a | b |\n|---|--:|\n| 1 | 2 |\n| 3 | 4 |\ndopo\n")

        undo.undo()
        #expect(fixture.textView.string == Self.alignNote)
        #expect(!undo.canUndo, "un solo undo doveva annullare l'intera modifica")
    }

    @Test func choosingSortAscendingReordersTheRowsAndOneUndoRestoresTheNote() throws { // R-41
        let fixture = try hostedTable(Self.sortNote)
        defer { fixture.window.orderOut(nil) }
        let undo = try #require(fixture.textView.undoManager)

        try Self.choose("Ordina A→Z", in: Self.headerMenu(fixture, column: 0))

        #expect(fixture.textView.string == "prima\n| k | v |\n|---|---|\n| 1 | y |\n| 3 | x |\ndopo\n")

        undo.undo()
        #expect(fixture.textView.string == Self.sortNote)
        #expect(!undo.canUndo)
    }

    @Test func theColumnControlAndTheHeaderRightClickOfferTheSameEntries() throws { // R-41
        let fixture = try hostedTable(Self.alignNote)
        defer { fixture.window.orderOut(nil) }
        let expected = TableColumnMenu.entries(current: .leading).map(TableColumnMenu.title(of:))

        let controls = descendants(of: fixture.grid)
            .filter { $0.accessibilityIdentifier() == "editor-table-column-menu" }
        let control = try #require(controls.first, "nessun controllo editor-table-column-menu nella griglia")
        let controlTitles = (control.menu?.items ?? []).map(\.title).filter { !$0.isEmpty }
        let rightClickTitles = try Self.headerMenu(fixture, column: 0).items.map(\.title).filter { !$0.isEmpty }

        #expect(controlTitles == expected)
        #expect(rightClickTitles == expected)
    }
}
