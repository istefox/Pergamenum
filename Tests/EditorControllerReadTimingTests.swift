import AppKit
import SwiftUI
import Testing
@testable import Pergamenum

// ADR-0074 §D3, "a value is read when it is read today" (plan `pg-144-editor-coordinator-
// feature-controllers`, Task 6): the two block constructs whose parent-derived inputs are read at
// different moments. Both pins were written against the code before any state moved into
// `TableBlockController` / `ViewBlockController`, and must keep passing after.
//
// The move changed only the receivers below (`viewBlocks.hosts`, `tables.drawn`); the assertions are not.

private func timingFind<T>(_ type: T.Type, in value: Any, depth: Int = 0) -> T? {
    guard depth < 50 else { return nil }
    if let match = value as? T { return match }
    for child in Mirror(reflecting: value).children {
        if let match = timingFind(type, in: child.value, depth: depth + 1) { return match }
    }
    return nil
}

// MARK: - commitTable reads the current parent (ADR-0074 §D3)

@MainActor
@Suite struct TableCommitReadsTheCurrentParent {
    private static let note = "prima\n| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\ndopo\n"
    private static let headerOffset = 6

    private func parent(hidesMarkup: Bool) -> NoteTextView {
        NoteTextView(
            text: .constant(Self.note), theme: .emergency, noteTitles: [], tagSuggestions: [],
            hidesMarkup: hidesMarkup, onFollowLink: { _ in }
        )
    }

    /// `commitTable`'s first line reads `parent.hidesMarkup` when it runs (`+Tables.swift:58`), not a
    /// value captured when the grid was vended: replacing `coordinator.parent` with a
    /// `hidesMarkup: false` one refuses the commit and leaves the buffer alone, and replacing it
    /// back lets the same call through.
    @Test func aParentSwappedToHidesMarkupOffRefusesTheCommitAndSwappingBackAllowsIt() {
        let fixture = EmbedEditorFixtures.editor(
            text: Self.note, hidesMarkup: true, root: nil, thumbnails: nil
        )
        let coordinator = fixture.coordinator
        let textView = fixture.textView
        let edit = TableEdit.cell(row: 0, column: 0, text: "9")

        coordinator.parent = parent(hidesMarkup: false)
        let refused = coordinator.commitTable(edit, at: Self.headerOffset, in: textView)
        #expect(!refused, "the commit must read the parent as it is now, not as it was at vend time")
        #expect(textView.string == Self.note, "a refused commit writes nothing")

        coordinator.parent = parent(hidesMarkup: true)
        let allowed = coordinator.commitTable(edit, at: Self.headerOffset, in: textView)
        #expect(allowed, "the same call with the current parent on must go through")
        #expect(textView.string.contains("| 9 | 2 |"))
    }

    /// `TableBlockController.apply` asks its parent provider on every pass, not once at
    /// construction: a styling pass after `coordinator.parent` is swapped to `hidesMarkup: false`
    /// clears every drawn table, and swapping back draws it again.
    @Test func theTablePassReadsTheParentItIsRunWith() {
        let fixture = EmbedEditorFixtures.editor(
            text: Self.note, hidesMarkup: true, root: nil, thumbnails: nil
        )
        let coordinator = fixture.coordinator
        let textView = fixture.textView

        coordinator.applyStyling(to: textView, theme: .emergency)
        #expect(coordinator.tables.drawn[Self.headerOffset] != nil, "hidesMarkup on draws the table")

        coordinator.parent = parent(hidesMarkup: false)
        coordinator.applyStyling(to: textView, theme: .emergency)
        #expect(coordinator.tables.drawn.isEmpty, "the pass must read the parent as it is now")
        #expect(coordinator.tables.hiddenRows.isEmpty)

        coordinator.parent = parent(hidesMarkup: true)
        coordinator.applyStyling(to: textView, theme: .emergency)
        #expect(coordinator.tables.drawn[Self.headerOffset] != nil)
    }
}

// MARK: - A vended host keeps the onEditQuery it was vended with (ADR-0074 §D3)

@MainActor
@Suite(.serialized) struct ViewBlockHostKeepsItsVendedEditQuery {
    private static let note = "Before\n```pergamenum-view\nrender: table\n```\nAfter\n"

    private final class Sink {
        var requests: [ViewQueryEditRequest] = []
    }

    private func view(sending sink: Sink) -> NoteTextView {
        var view = NoteTextView(
            text: .constant(Self.note), theme: .emergency, noteTitles: [], tagSuggestions: [],
            hidesMarkup: true, onFollowLink: { _ in }
        )
        view.vault.onEditQuery = { sink.requests.append($0) }
        return view
    }

    /// `ViewBlockController.refresh` builds the `onEditQuery` closure (`vault.onEditQuery.map`) on
    /// each pass and stores it in the host's root view (`+ViewBlocks.swift:239-282`). So:
    /// - between a parent swap and the next pass, the host still carries the callback it was
    ///   vended with, and a click reaches the OLD parent's sink;
    /// - the next pass re-vends, and a click then reaches the NEW parent's sink.
    @Test func aHostClicksThroughItsVendedCallbackUntilTheNextPassRevendsIt() throws {
        let old = Sink()
        let new = Sink()
        let first = view(sending: old)
        let coordinator = first.makeCoordinator()
        let textView = CompletingTextView(usingTextLayoutManager: true)
        textView.delegate = coordinator
        textView.isRichText = false
        textView.frame = CGRect(x: 0, y: 0, width: 600, height: 800)
        textView.textContainer?.size = CGSize(width: 552, height: CGFloat.greatestFiniteMagnitude)
        coordinator.textView = textView
        textView.textContentStorage?.delegate = coordinator.decorations
        textView.textLayoutManager?.delegate = coordinator.decorations
        first.wire(textView, to: coordinator)
        textView.string = Self.note
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        coordinator.applyStyling(to: textView, theme: .emergency)

        func click() throws {
            let host = coordinator.viewBlocks.hosts.host(for: 0, in: textView)
            let rendered = try #require(timingFind(RenderedViewBlock.self, in: host.rootView))
            let callback = try #require(rendered.onEditQuery, "the styled host needs an edit action")
            callback()
        }

        coordinator.parent = view(sending: new)
        try click()
        #expect(old.requests.count == 1, "no pass ran since the swap: the host keeps its vended callback")
        #expect(new.requests.isEmpty)

        coordinator.applyStyling(to: textView, theme: .emergency)
        try click()
        #expect(old.requests.count == 1, "the second click must not reach the old parent")
        #expect(new.requests.count == 1, "the next pass re-vends the callback from the current parent")
    }
}
