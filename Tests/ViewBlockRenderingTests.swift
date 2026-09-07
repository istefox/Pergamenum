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

/// The opening fence line's own `.viewBlock` marker - `"```pergamenum-view"`, eighteen
/// characters, relative to its own paragraph's start (Task 5, shared by every suite below
/// that needs a marker registered without caring about its exact fixture text).
private func viewBlockOpeningFenceMarker() -> HiddenMarker {
    HiddenMarker(range: NSRange(location: 0, length: ("```pergamenum-view" as NSString).length), kind: .viewBlock)
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

// MARK: - Attachment creation from a valid, closed fence (ADR §D7's positive case; Task 5)

/// R-13's first named case, one assertion per renderer keyword since the pass must not read
/// `render:` to decide layout (R-01, R-02, R-03). Driven through `substitutedParagraph` above
/// - the same full `textContentStorage(_:textParagraphWith:)` dispatcher
/// `Tests/TableRenderingTests.swift`'s own
/// `aRegisteredTableMarkerSubstitutesTheAttachmentAndKeepsTheLengthIdentical` uses - rather
/// than calling `viewBlockParagraph(at:storage:)` directly, so the assertion also covers
/// Task 5's own wiring of the call site into that chain, not only the method's body.
///
/// Red against the current stub for two independent, both expected, reasons:
/// `viewBlockParagraph(at:storage:)` returns `nil` unconditionally (Task 2's own stub,
/// this file's own header comment) and is not yet called from the dispatcher at all -
/// either gap alone already keeps every assertion below red until Task 5's coder closes both.
@MainActor
@Suite struct ViewBlockAttachmentSubstitution {
    private func openingFenceOffset(in note: String) -> Int {
        (note as NSString).range(of: "```pergamenum-view").location
    }

    /// Registers the marker and the host a real styling pass would have vended by now, then
    /// asserts the three things R-13's first named case names: an attachment at offset 0, the
    /// rest of the line collapsed, and the paragraph's own length unchanged
    /// (`NSTextContentManager.h:120`).
    private func assertSubstitutesAnAttachmentAtOffsetZeroAndKeepsTheParagraphLength(note: String) {
        let offset = openingFenceOffset(in: note)
        let delegate = EditorDecorationDelegate()
        delegate.apply(hiddenMarkers: [offset: [viewBlockOpeningFenceMarker()]], hidingMarkup: true)
        delegate.apply(viewBlockHosts: [offset: NSView()])

        let expectedLength = (note as NSString).paragraphRange(for: NSRange(location: offset, length: 0)).length
        let paragraph = substitutedParagraph(delegate, note: note, at: offset)

        #expect(paragraph != nil, "il fence valido non produce un paragrafo sostituito")
        guard let paragraph else { return }
        let attributed = paragraph.attributedString
        #expect(attributed.length == expectedLength, "la lunghezza del paragrafo è cambiata")
        #expect(
            attributed.attribute(.attachment, at: 0, effectiveRange: nil) is ViewBlockAttachment,
            "l'offset 0 non porta un ViewBlockAttachment"
        )
        if attributed.length > 1 {
            let restFont = attributed.attribute(.font, at: 1, effectiveRange: nil) as? NSFont
            #expect(restFont == EditorDecorationDelegate.collapsedFont, "il resto della riga non è collassato")
        }
    }

    @Test func aClosedTableFenceSubstitutesTheAttachment() {
        assertSubstitutesAnAttachmentAtOffsetZeroAndKeepsTheParagraphLength(
            note: "prima\n```pergamenum-view\nrender: table\n```\ndopo\n"
        )
    }

    @Test func aClosedGalleryFenceSubstitutesTheAttachment() {
        assertSubstitutesAnAttachmentAtOffsetZeroAndKeepsTheParagraphLength(
            note: "prima\n```pergamenum-view\nrender: gallery\n```\ndopo\n"
        )
    }

    @Test func aClosedCalendarFenceSubstitutesTheAttachment() {
        assertSubstitutesAnAttachmentAtOffsetZeroAndKeepsTheParagraphLength(
            note: "prima\n```pergamenum-view\nrender: calendar\n```\ndopo\n"
        )
    }

    /// `render: board` needs its own required `group:` key (§D1: "a board without `group` is
    /// a parse error, not a board with one column") - the other three keywords parse on
    /// `render:` alone, so only this fixture carries a second body line.
    @Test func aClosedBoardFenceSubstitutesTheAttachment() {
        assertSubstitutesAnAttachmentAtOffsetZeroAndKeepsTheParagraphLength(
            note: "prima\n```pergamenum-view\nrender: board\ngroup: tag(\"status-*\")\n```\ndopo\n"
        )
    }

    /// ADR §D7 follow-up (reverses R-08's original "no attachment, no error UI"): a fence that
    /// is structurally closed and would be recognised as a `.viewBlockRun` span, but whose body
    /// fails `ViewBlock.parse` - here, `render: board` with no `group:` - still substitutes an
    /// attachment. The host it carries renders the raw source, and `RenderedViewBlock` re-parses
    /// that source itself and draws its own `failed(_:)` error card, the same one already shown
    /// on the transclusion, export and Viste-pane surfaces - closing the asymmetry that let a
    /// syntax mistake look like the whole feature was broken with no reason ever shown.
    @Test func aClosedFenceWhoseBodyFailsToParseStillSubstitutesTheAttachment() {
        assertSubstitutesAnAttachmentAtOffsetZeroAndKeepsTheParagraphLength(
            note: "prima\n```pergamenum-view\nrender: board\n```\ndopo\n"
        )
        // Confirms this really is a §D7 case and not an accidental one: `render: board` alone
        // does fail to parse.
        #expect(throws: ViewBlockError.self) { try ViewBlock.parse("render: board") }
    }
}

// MARK: - An unclosed fence produces nothing at all (ADR §D6, C5; Task 5)

@MainActor
@Suite struct ViewBlockUnclosedFencePrecondition {
    /// C5: `CodeFence.regions(in:)` runs an unclosed fence to the end of the text on purpose
    /// (ADR §D6) - without this precondition, typing the opening backticks would take the rest
    /// of the note out of the layout mid-keystroke. `viewBlockRun(in:atParagraphStart:)` is the
    /// delegate's own re-read of that precondition, `tableRun`'s twin, and must refuse an
    /// unclosed fence exactly as Task 1's `MarkdownStyler.viewBlockRuns` already does at the
    /// span layer (`Tests/ViewBlockSpanTests.swift`) - the same precondition asserted one layer
    /// down, at the delegate's own re-validation.
    ///
    /// Already green with the stub (`viewBlockRun` returns `nil` unconditionally) and must stay
    /// green once Task 5's coder implements the real body.
    @Test func anUnclosedFenceYieldsNoRecognisedViewBlockRun() {
        let note = "prima\n```pergamenum-view\nrender: table"
        let offset = (note as NSString).range(of: "```pergamenum-view").location

        #expect(EditorDecorationDelegate.viewBlockRun(in: note as NSString, atParagraphStart: offset) == nil)
    }

    /// The same precondition reaching the substitution branch: an unclosed fence's opening
    /// line, even with a marker mistakenly already registered for it, substitutes nothing -
    /// source and layout both left alone (ADR §D6: "left entirely alone").
    @Test func anUnclosedFencesOpeningLineSubstitutesNothingEvenWithAMarkerRegistered() {
        let note = "prima\n```pergamenum-view\nrender: table"
        let offset = (note as NSString).range(of: "```pergamenum-view").location
        let delegate = EditorDecorationDelegate()
        delegate.apply(hiddenMarkers: [offset: [viewBlockOpeningFenceMarker()]], hidingMarkup: true)
        delegate.apply(viewBlockHosts: [offset: NSView()])

        #expect(substitutedParagraph(delegate, note: note, at: offset) == nil)
    }
}

// MARK: - `hidesMarkup` false registers nothing and clears what a previous pass left (ADR §D12; Task 5)

@MainActor
@Suite struct ViewBlockHidesMarkupGuard {
    /// D12, the `clearTables()` trap extended to the sixth input: with `hidesMarkup` off,
    /// `applyViewBlocks` must register no new `.viewBlock` marker.
    ///
    /// Green with the stub already (`applyViewBlocks` does nothing at all, so `markers` is
    /// untouched) and must stay green once Task 5's coder implements the real guard - the same
    /// shape `ViewBlockLineIsolation`'s own tests above already establish for the delegate's
    /// isolation, applied here to the Coordinator's own guard.
    @Test func withHidesMarkupFalseThePassAddsNoViewBlockMarker() {
        let note = "prima\n```pergamenum-view\nrender: table\n```\ndopo\n"
        let view = NoteTextView(
            text: .constant(note), theme: .emergency, noteTitles: [], tagSuggestions: [],
            hidesMarkup: false, onFollowLink: { _ in }
        )
        let coordinator = view.makeCoordinator()
        let textView = CompletingTextView(usingTextLayoutManager: true)
        textView.string = note
        var markers: [Int: [HiddenMarker]] = [:]

        coordinator.applyViewBlocks(
            to: textView, runs: [NSRange(location: 0, length: (note as NSString).length)], markers: &markers
        )

        #expect(markers.isEmpty, "con hidesMarkup=false è stato registrato un marcatore")
    }

    /// D12's other half: clearing what a previous, `hidesMarkup`-on pass left registered on
    /// `EditorDecorationDelegate` - the enumeration refusal has to be reached too, or the body
    /// lines would stay out of the layout with the backticks visible above them.
    ///
    /// **Cannot be meaningfully red or green yet, for a reason outside this task's own scope,
    /// recorded rather than hidden.** `EditorDecorationDelegate.apply(viewBlockLines:)` is
    /// still Task 2's own stub (`EditorDecorationDelegate.swift`'s `// Task 2, coder.`,
    /// verified against the working tree at dispatch time - `apply(viewBlockHosts:)` likewise)
    /// - it stores nothing at all, so there is no registered state for anything to clear, and
    /// this assertion is trivially true regardless of whether `applyViewBlocks`/
    /// `clearViewBlocks` do their job. Written against the target shape rather than skipped:
    /// once Task 2's real storage and the `shouldEnumerate` widening land, this starts
    /// exercising exactly what D12 requires, with no change needed here.
    @Test func withHidesMarkupFalseThePassClearsLinesAPreviousPassHid() {
        let note = "prima\n```pergamenum-view\nrender: table\n```\ndopo\n"
        let hiddenLines: Set<Int> = [
            (note as NSString).range(of: "render: table").location,
            (note as NSString).range(of: "```\ndopo").location,
        ]
        let view = NoteTextView(
            text: .constant(note), theme: .emergency, noteTitles: [], tagSuggestions: [],
            hidesMarkup: false, onFollowLink: { _ in }
        )
        let coordinator = view.makeCoordinator()
        coordinator.decorations.apply(viewBlockLines: hiddenLines)
        let textView = CompletingTextView(usingTextLayoutManager: true)
        textView.string = note
        var markers: [Int: [HiddenMarker]] = [:]

        coordinator.applyViewBlocks(
            to: textView, runs: [NSRange(location: 0, length: (note as NSString).length)], markers: &markers
        )

        let laidOut = laidOutOffsets(of: coordinator.decorations, text: note)
        for offset in hiddenLines {
            #expect(laidOut.contains(offset), "con hidesMarkup=false la riga a \(offset) è ancora nascosta")
        }
    }
}
