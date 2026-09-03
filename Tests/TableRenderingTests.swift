import AppKit
import Testing
@testable import Pergamenum

/// ADR-0029 §D4/§D5/§D6 (plan `2026-09-02-editor-wysiwyg-unification`, Task 4): a GFM
/// table's header paragraph is substituted for a `TableAttachment`, its delimiter and body
/// rows leave the layout entirely, and the grid `TableGridStore` vends survives every
/// styling pass so first responder is never lost mid-edit.
///
/// Driven against the real `EditorDecorationDelegate` offscreen, on the model of
/// `Tests/EmbedDrawingTests.swift` and `Tests/MarkupHidingTests.swift`: what is under test
/// here is a new branch on the same `NSTextContentStorageDelegate`/
/// `NSTextContentManagerDelegate` hooks, not a new mechanism.
///
/// `tableParagraph(at:storage:)` is stubbed to return `nil` unconditionally (Task 4,
/// tester) - the coder's own deliverable is reading a `.table` marker back, re-validating
/// it against a fresh `GFMTable.parse` of the live characters, and drawing the real
/// `TableAttachment` from `tableViews[range.location]`. Every positive assertion below is
/// red until that lands; the negative ones (hidden markup off, a stale marker) are true
/// with the stub already, the same shape `Tests/GFMTableTests.swift`'s own header comment
/// describes for Task 3's stubs.

@MainActor
private func substitutedParagraph(
    _ delegate: EditorDecorationDelegate, note: String, at location: Int
) -> NSTextParagraph? {
    let storage = NSTextContentStorage()
    storage.textStorage?.setAttributedString(NSAttributedString(string: note))
    let range = (note as NSString).paragraphRange(for: NSRange(location: location, length: 0))
    return delegate.textContentStorage(storage, textParagraphWith: range)
}

/// The UTF-16 offsets of every paragraph a real layout pass actually lays out - what a
/// table's own `shouldEnumerate` refusal must remove the delimiter and body rows from,
/// the same measured-frames approach `Tests/MarkupHidingTests.swift`'s own `frames(...)`
/// helper already uses for folding.
@MainActor
private func laidOutOffsets(of delegate: EditorDecorationDelegate, text: String) -> Set<Int> {
    let content = NSTextContentStorage()
    let layout = NSTextLayoutManager()
    content.addTextLayoutManager(layout)
    let container = NSTextContainer(size: CGSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    layout.textContainer = container
    content.delegate = delegate

    content.textStorage?.setAttributedString(
        NSAttributedString(
            string: text,
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)]
        )
    )
    layout.ensureLayout(for: layout.documentRange)

    var offsets: Set<Int> = []
    layout.enumerateTextLayoutFragments(from: layout.documentRange.location, options: [.ensuresLayout]) { fragment in
        offsets.insert(content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location))
        return true
    }
    return offsets
}

@MainActor
private func laidOutOffsets(text: String, tableRows: Set<Int>) -> Set<Int> {
    let delegate = EditorDecorationDelegate()
    delegate.apply(tableRows: tableRows)
    return laidOutOffsets(of: delegate, text: text)
}

/// A two-column, two-body-row table: `"prima\n| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\ndopo\n"`.
private enum TableFixture {
    static let note = "prima\n| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\ndopo\n"
    /// "prima\n" is six characters; the header paragraph starts right after it.
    static let headerOffset = 6
    /// "| a | b |\n" is ten characters.
    static let delimiterOffset = headerOffset + 10
    /// "|---|---|\n" is ten characters.
    static let bodyRow1Offset = delimiterOffset + 10
    /// "| 1 | 2 |\n" is ten characters.
    static let bodyRow2Offset = bodyRow1Offset + 10
    /// "| 3 | 4 |\n" is ten characters; "dopo\n" starts right after it.
    static let afterOffset = bodyRow2Offset + 10
    /// Every row the grid draws over: the delimiter and the two body rows, never the
    /// header - it stays in the layout, carrying the attachment.
    static let hiddenRows: Set<Int> = [delimiterOffset, bodyRow1Offset, bodyRow2Offset]
    /// "| a | b |" - the header line's own pipe syntax, nine characters, relative to its
    /// own paragraph's start (ADR §D4's anchoring convention, the same `.list`/`.blockquote` use).
    static let marker = HiddenMarker(range: NSRange(location: 0, length: 9), kind: .table)
    static var headerParagraphLength: Int {
        (note as NSString).paragraphRange(for: NSRange(location: headerOffset, length: 0)).length
    }
}

@MainActor
@Suite struct TableRendering {
    @Test func aRegisteredTableMarkerSubstitutesTheAttachmentAndKeepsTheLengthIdentical() throws {
        let delegate = EditorDecorationDelegate()
        delegate.apply(hiddenMarkers: [TableFixture.headerOffset: [TableFixture.marker]], hidingMarkup: true)
        delegate.apply(tableViews: [TableFixture.headerOffset: TableGridView()])

        let paragraph = try #require(
            substitutedParagraph(delegate, note: TableFixture.note, at: TableFixture.headerOffset)
        )
        let attributed = paragraph.attributedString
        #expect(attributed.length == TableFixture.headerParagraphLength)
        #expect((attributed.string as NSString).character(at: 0) == 0xFFFC)
        let attachment = attributed.attribute(.attachment, at: 0, effectiveRange: nil) as? TableAttachment
        #expect(attachment != nil)
        // The rest of the header line collapses the same way a heading/emphasis/embed
        // marker does - never a second, competing mechanism for the same paragraph.
        let font = attributed.attribute(.font, at: 1, effectiveRange: nil) as? NSFont
        #expect(font == EditorDecorationDelegate.collapsedFont)
    }

    /// D9: `hidesMarkup` off restores today's editor exactly - the pipes stay text, no
    /// attachment is made.
    @Test func theTableBranchIsInertWhenHidingMarkupIsOff() {
        let delegate = EditorDecorationDelegate()
        delegate.apply(hiddenMarkers: [TableFixture.headerOffset: [TableFixture.marker]], hidingMarkup: false)
        delegate.apply(tableViews: [TableFixture.headerOffset: TableGridView()])

        #expect(substitutedParagraph(delegate, note: TableFixture.note, at: TableFixture.headerOffset) == nil)
    }

    /// The `stillSpells` re-check contract's own fifth kind (D8's reload guard applied to
    /// drawing, not only to a commit): a `.table` entry whose characters no longer spell a
    /// table draws nothing - the same race `aStaleTableEntryDoesNotCollapseProse` checks
    /// for a heading marker.
    @Test func aStaleTableMarkerDrawsNothing() {
        let delegate = EditorDecorationDelegate()
        delegate.apply(hiddenMarkers: [0: [TableFixture.marker]], hidingMarkup: true)
        delegate.apply(tableViews: [0: TableGridView()])

        #expect(substitutedParagraph(delegate, note: "corpo\ndopo\n", at: 0) == nil)
    }
}

// MARK: - The table rows leave the layout (ADR §D4/§D5)

@MainActor
@Suite struct TableRowHiding {
    @Test func theDelimiterAndBodyRowsLeaveTheLayoutAndTheHeaderAndFollowingLineDoNot() {
        let laidOut = laidOutOffsets(text: TableFixture.note, tableRows: TableFixture.hiddenRows)

        for offset in TableFixture.hiddenRows {
            #expect(!laidOut.contains(offset), "la riga a \(offset) è ancora nel layout")
        }
        #expect(laidOut.contains(TableFixture.headerOffset), "l'intestazione non è più nel layout")
        #expect(laidOut.contains(TableFixture.afterOffset), "la riga dopo la tabella non è più nel layout")
    }

    /// D5's own union rule: `apply(tableRows:)` is a fifth input, never merged into
    /// `hiddenLineOffsets` - registering an empty fold set must not clear a table's own
    /// hidden rows. This is the assertion that stops the fifth input being quietly merged
    /// into the second.
    @Test func applyingFoldedHeadingsWithAnEmptySetDoesNotClearTheTableRows() {
        let delegate = EditorDecorationDelegate()
        delegate.apply(tableRows: TableFixture.hiddenRows)
        delegate.apply(hiddenLines: [], foldedHeadings: [:])

        let laidOut = laidOutOffsets(of: delegate, text: TableFixture.note)
        for offset in TableFixture.hiddenRows {
            #expect(
                !laidOut.contains(offset),
                "apply(hiddenLines:foldedHeadings:) con un set vuoto ha cancellato le righe della tabella"
            )
        }
    }

    /// The reverse direction: registering an empty table-row set must not clear a fold
    /// already in place.
    @Test func applyingTableRowsWithAnEmptySetDoesNotClearAFoldedLine() {
        let delegate = EditorDecorationDelegate()
        delegate.apply(hiddenLines: [TableFixture.afterOffset], foldedHeadings: [TableFixture.headerOffset: 1])
        delegate.apply(tableRows: TableFixture.hiddenRows)
        delegate.apply(tableRows: [])

        let laidOut = laidOutOffsets(of: delegate, text: TableFixture.note)
        #expect(!laidOut.contains(TableFixture.afterOffset), "apply(tableRows:) con un set vuoto ha cancellato la piega")
    }
}

// MARK: - The grid survives every styling pass (ADR §D6)

@MainActor
@Suite struct TableGridStoreIdentity {
    /// **Red on purpose.** `TableGridStore.view(for:in:)` is stubbed to never cache (Task
    /// 4, tester), so this fails until the coder keeps a real `[Int: TableGridView]` (or
    /// equivalent) and returns the same instance back - the assertion that keeps first
    /// responder alive across a styling pass: a grid rebuilt on every restyle would lose
    /// it on every keystroke, which through `textDidChange` is every keystroke.
    @Test func theSameIdentityReturnsTheSameViewInstanceAndADifferentIdentityADifferentOne() {
        let store = TableGridStore()
        let textView = NSTextView(usingTextLayoutManager: true)

        let first = store.view(for: TableFixture.headerOffset, in: textView)
        let second = store.view(for: TableFixture.headerOffset, in: textView)
        #expect(first === second, "due richieste per la stessa tabella devono restituire la stessa view")

        let third = store.view(for: TableFixture.bodyRow1Offset, in: textView)
        #expect(third !== first, "un'identità diversa deve restituire una view diversa")
    }
}

// MARK: - The grid reaches the accessibility tree (ADR §D6, R-05)

@MainActor
@Suite struct TableGridAccessibility {
    /// The gap between "drawn" and "reachable", which every other test in this file was on
    /// the wrong side of: R-05's UI test failed while the grid was on screen, in the
    /// window, at 286×96, because `NSTextView` answers `accessibilityChildren()` from its
    /// *text* and a view hosted by `NSTextAttachmentViewProvider` lives inside the private
    /// `_NSTextViewportElementView` TextKit 2 makes per laid-out fragment - nothing
    /// promotes a subview of one into the editor's accessibility subtree. Measured:
    /// `super.accessibilityChildren()` came back empty on the very pass that had the grid
    /// hosted, and XCUITest's snapshot showed the whole `TextView` node as a leaf.
    ///
    /// **What this can and cannot measure.** A window that is never ordered in has an empty
    /// visible rect, so `NSTextViewportLayoutController` builds no rendering surfaces and
    /// TextKit never hosts the attachment's view - measured, with `ensureLayout` and an
    /// explicit `layoutViewport()` both called and the grid's `superview` still nil, while
    /// the text view carried its usual `_NSTextContentView`. So the hosting half is the UI
    /// test's to prove (`DesignAndReadingUITests`, R-05), and what is checked here is the
    /// rule the fix actually states: a grid TextKit has *not* placed is not offered, and the
    /// same grid placed in the hierarchy - which is all TextKit does when the fragment
    /// enters the viewport - is.
    @Test func aHostedTableGridIsOfferedAsAnAccessibilityChildOfTheEditor() throws {
        let fixture = EmbedEditorFixtures.editor(
            text: TableFixture.note, hidesMarkup: true, root: nil, thumbnails: nil
        )
        fixture.coordinator.applyStyling(to: fixture.textView, theme: .emergency)
        let grid = try #require(fixture.coordinator.decorations.tableViews[TableFixture.headerOffset])

        #expect(
            childGrids(of: fixture.textView).isEmpty,
            "una griglia che TextKit non ha ancora piazzato non deve essere offerta"
        )

        fixture.textView.addSubview(grid)
        let offered = childGrids(of: fixture.textView)
        #expect(offered == [grid], "la griglia disegnata non è tra i figli accessibili dell'editor")
        #expect(
            offered.first?.accessibilityIdentifier() == "editor-table",
            "la griglia esposta non porta l'identificatore che la suite UI cerca"
        )
    }

    private func childGrids(of textView: NSTextView) -> [TableGridView] {
        (textView.accessibilityChildren() ?? []).compactMap { $0 as? TableGridView }
    }
}
