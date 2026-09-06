import AppKit
import Foundation
import Testing
@testable import Pergamenum

/// ADR-0033 (plan `2026-09-06-pg-099-views-board-renderer-orphaned-by`, Task 2): the
/// delegate's sixth hidden-line input, `apply(viewBlockLines:)`, and the `.viewBlock`
/// `HiddenMarker.Kind` it reads back.
///
/// Modelled line for line on `Tests/TableRenderingTests.swift` - its `substitutedParagraph`
/// and `laidOutOffsets` helpers are copied below, not imported, on that file's own precedent
/// (`EmbedDrawingTests.swift`/`MarkupHidingTests.swift`).
///
/// `apply(viewBlockLines:)` and `apply(viewBlockHosts:)` are **stubbed to do nothing** on
/// `EditorDecorationDelegate` (Task 2, tester's own declaration) - the coder's work is the
/// storage plus widening `textContentManager(_:shouldEnumerate:options:)` to consult it.
/// Every assertion below that depends on that widening is therefore red until the coder
/// fills it in; the ones that only exercise the *other* four already-working inputs
/// (folding, table rows) are green with the stub already, the same shape
/// `Tests/TableRenderingTests.swift`'s own header comment describes for `tableParagraph`.
/// `viewBlockParagraph(at:storage:)` is stubbed to return `nil` unconditionally - both tests
/// against it are green with the stub and are expected to stay green after Task 5.

@MainActor
private func substitutedParagraph(
    _ delegate: EditorDecorationDelegate, note: String, at location: Int
) -> NSTextParagraph? {
    let storage = NSTextContentStorage()
    storage.textStorage?.setAttributedString(NSAttributedString(string: note))
    let range = (note as NSString).paragraphRange(for: NSRange(location: location, length: 0))
    return delegate.textContentStorage(storage, textParagraphWith: range)
}

/// The UTF-16 offsets of every paragraph a real layout pass actually lays out - the same
/// measured-frames approach `Tests/TableRenderingTests.swift`'s own helper of this name uses.
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
private func laidOutOffsets(text: String, viewBlockLines: Set<Int>) -> Set<Int> {
    let delegate = EditorDecorationDelegate()
    delegate.apply(viewBlockLines: viewBlockLines)
    return laidOutOffsets(of: delegate, text: text)
}

/// A closed `pergamenum-view` fence, one body line, then an ordinary paragraph:
/// `"prima\n```pergamenum-view\nrender: table\n```\ndopo\n"`.
private enum ViewBlockFixture {
    static let note = "prima\n```pergamenum-view\nrender: table\n```\ndopo\n"
    /// "prima\n" is six characters; the opening fence paragraph starts right after it.
    static let openingFenceOffset = 6
    /// "```pergamenum-view\n" is nineteen characters.
    static let bodyLineOffset = openingFenceOffset + 19
    /// "render: table\n" is fourteen characters.
    static let closingFenceOffset = bodyLineOffset + 14
    /// "```\n" is four characters; "dopo\n" starts right after it.
    static let afterOffset = closingFenceOffset + 4
    /// Every line the fence draws over: the one body line and, unlike a table (C4), the
    /// closing fence line too - never the opening fence, which stays in the layout,
    /// carrying the attachment.
    static let hiddenLines: Set<Int> = [bodyLineOffset, closingFenceOffset]
    /// "```pergamenum-view" - the opening fence line's own run, eighteen characters,
    /// relative to its own paragraph's start (the same anchoring convention `.table` uses).
    static let marker = HiddenMarker(range: NSRange(location: 0, length: 18), kind: .viewBlock)
}

// MARK: - The body and closing-fence lines leave the layout (ADR §D4/§D5, C4)

@MainActor
@Suite struct ViewBlockLineHiding {
    @Test func theBodyAndClosingFenceLinesLeaveTheLayoutAndTheOpeningFenceAndFollowingLineDoNot() {
        let laidOut = laidOutOffsets(text: ViewBlockFixture.note, viewBlockLines: ViewBlockFixture.hiddenLines)

        for offset in ViewBlockFixture.hiddenLines {
            #expect(!laidOut.contains(offset), "la riga a \(offset) è ancora nel layout")
        }
        #expect(laidOut.contains(ViewBlockFixture.openingFenceOffset), "la riga di apertura non è più nel layout")
        #expect(laidOut.contains(ViewBlockFixture.afterOffset), "la riga dopo il blocco non è più nel layout")
    }

    /// C4: unlike a table, whose last hidden row is its own last body row, a fence has no
    /// equivalent - it ends at a line of backticks that must leave the layout too, or it
    /// would sit under the drawn attachment as stray text. Its own assertion, separate from
    /// the loop above, because this is the one place the arithmetic differs from a table's.
    @Test func theClosingFenceLineIsInTheSetAndIsNotLaidOut() {
        let laidOut = laidOutOffsets(text: ViewBlockFixture.note, viewBlockLines: ViewBlockFixture.hiddenLines)

        #expect(ViewBlockFixture.hiddenLines.contains(ViewBlockFixture.closingFenceOffset))
        #expect(!laidOut.contains(ViewBlockFixture.closingFenceOffset), "la riga di chiusura è ancora nel layout")
    }
}

// MARK: - The sixth input is isolated from the fold and the table (ADR §D1's own rule)

@MainActor
@Suite struct ViewBlockLineIsolation {
    /// `apply(viewBlockLines:)` with an empty set must not clear a fold already registered
    /// through `apply(hiddenLines:foldedHeadings:)` - green with the stub already: a no-op
    /// setter cannot interfere with anything, and a correct implementation must not either.
    @Test func applyingViewBlockLinesWithAnEmptySetDoesNotClearAFoldedLine() {
        let delegate = EditorDecorationDelegate()
        delegate.apply(
            hiddenLines: [ViewBlockFixture.afterOffset],
            foldedHeadings: [ViewBlockFixture.openingFenceOffset: 1]
        )
        delegate.apply(viewBlockLines: ViewBlockFixture.hiddenLines)
        delegate.apply(viewBlockLines: [])

        let laidOut = laidOutOffsets(of: delegate, text: ViewBlockFixture.note)
        #expect(!laidOut.contains(ViewBlockFixture.afterOffset), "apply(viewBlockLines:) con un set vuoto ha cancellato la piega")
    }

    /// The reverse direction: registering an empty fold set must not clear the view block's
    /// own hidden lines already in place - red until the coder's real storage and
    /// `shouldEnumerate` widening land, since nothing hides these offsets under the stub in
    /// the first place.
    @Test func applyingFoldedHeadingsWithAnEmptySetDoesNotClearViewBlockLines() {
        let delegate = EditorDecorationDelegate()
        delegate.apply(viewBlockLines: ViewBlockFixture.hiddenLines)
        delegate.apply(hiddenLines: [], foldedHeadings: [:])

        let laidOut = laidOutOffsets(of: delegate, text: ViewBlockFixture.note)
        for offset in ViewBlockFixture.hiddenLines {
            #expect(
                !laidOut.contains(offset),
                "apply(hiddenLines:foldedHeadings:) con un set vuoto ha cancellato le righe del blocco vista"
            )
        }
    }

    /// The third pair: a table's own rows, registered through `apply(tableRows:)`, must
    /// survive `apply(viewBlockLines:)` clearing its own set to empty - the sixth input is
    /// deliberately separate from the fifth, not only from the second (D5's rule extended).
    /// Green with the stub already, for the same reason the first test above is.
    @Test func applyingViewBlockLinesWithAnEmptySetDoesNotClearTableRows() {
        let delegate = EditorDecorationDelegate()
        delegate.apply(tableRows: [ViewBlockFixture.afterOffset])
        delegate.apply(viewBlockLines: ViewBlockFixture.hiddenLines)
        delegate.apply(viewBlockLines: [])

        let laidOut = laidOutOffsets(of: delegate, text: ViewBlockFixture.note)
        #expect(!laidOut.contains(ViewBlockFixture.afterOffset), "apply(viewBlockLines:) con un set vuoto ha cancellato le righe della tabella")
    }
}

// MARK: - `viewBlockParagraph(at:storage:)`'s stub (Task 2 tester, Task 5 coder)

@MainActor
@Suite struct ViewBlockParagraphStub {
    /// ADR §D12: with `hidesMarkup` off, `viewBlockParagraph(at:storage:)` returns `nil` -
    /// green with the stub, and must stay green after Task 5 implements the real body.
    @Test func withHidingMarkupOffViewBlockParagraphReturnsNil() {
        let delegate = EditorDecorationDelegate()
        delegate.apply(
            hiddenMarkers: [ViewBlockFixture.openingFenceOffset: [ViewBlockFixture.marker]],
            hidingMarkup: false
        )
        let storage = NSTextStorage(string: ViewBlockFixture.note)
        let range = (ViewBlockFixture.note as NSString).paragraphRange(
            for: NSRange(location: ViewBlockFixture.openingFenceOffset, length: 0)
        )

        #expect(delegate.viewBlockParagraph(at: range, storage: storage) == nil)
    }

    /// The `stillSpells` re-check contract's own sixth kind, applied to drawing: a
    /// `.viewBlock` entry whose characters no longer spell a fence draws nothing - the same
    /// race `Tests/TableRenderingTests.swift`'s `aStaleTableMarkerDrawsNothing` checks for a
    /// table marker. Green with the stub already, and must stay green after Task 5.
    @Test func aStaleViewBlockMarkerDrawsNothing() {
        let delegate = EditorDecorationDelegate()
        delegate.apply(hiddenMarkers: [0: [ViewBlockFixture.marker]], hidingMarkup: true)
        let text = "corpo\ndopo\n"
        let storage = NSTextStorage(string: text)
        let range = (text as NSString).paragraphRange(for: NSRange(location: 0, length: 0))

        #expect(delegate.viewBlockParagraph(at: range, storage: storage) == nil)
    }
}
