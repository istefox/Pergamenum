import AppKit
import Foundation
import Testing
@testable import Pergamenum

// ADR-0098 §D1/§D2, plan docs/plans/pg-427-pg-428-underscore-concealment-daily-transclusions.md,
// Task 1 (PG-427).
//
// `_a_` and `__a__` delimiters are concealed and revealed exactly like `*a*` and `**a**`, on every
// surface that conceals `*`: the styler emits an `.emphasisMarker` over them (§D1), and the
// delegate's stale-entry re-check accepts a `_` marker (§D2). `nome_file_lungo` stays plain text:
// the parser's flanking rule (ADR-0077 §D5) keeps it out of emphasis, so no marker is ever emitted.
//
// The guards (the intraword cases, code, unclosed and empty runs, the stale entries, the revealed
// and setting-off arms) pin the cases the `_` markers must leave alone. The card fixture is
// `CardConcealmentTests`' own, copied rather than imported on this repo's per-file-fixture
// convention (`CardBlockMarkerTests.swift:8-9`).

private func emphasisMarkerSpellings(_ text: String) -> [String] {
    MarkdownStyler.spans(in: text)
        .filter { $0.span == .emphasisMarker }
        .map { String(text[$0.range]) }
}

private func markerKinds(_ markers: [HiddenMarker]) -> [HiddenMarker.Kind] { markers.map(\.kind) }

/// The range of the `occurrence`-th (0-based) `needle` in `text`, in UTF-16 units.
private func range(of needle: String, in text: String, occurrence: Int = 0) -> NSRange {
    var from = 0
    var found = NSRange(location: NSNotFound, length: 0)
    for _ in 0...occurrence {
        found = (text as NSString).range(
            of: needle, range: NSRange(location: from, length: (text as NSString).length - from)
        )
        from = NSMaxRange(found)
    }
    return found
}

// MARK: - The styler, pure

@MainActor
@Suite struct UnderscoreEmphasisStyler {
    @Test func anUnderscoreItalicRunYieldsTwoOneCharacterMarkers() {
        #expect(emphasisMarkerSpellings("testo _corsivo_ qui") == ["_", "_"])
    }

    @Test func aDoubleUnderscoreBoldRunYieldsTwoTwoCharacterMarkers() {
        #expect(emphasisMarkerSpellings("testo __forte__ qui") == ["__", "__"])
    }

    // The marker is emitted after the run span, the shape
    // `theEmphasisMarkerSpansComeAfterTheRunSpan` pins for `*`.
    @Test(arguments: [("testo _corsivo_ qui", MarkdownStyler.Span.italic), ("testo __forte__ qui", .bold)])
    func eachMarkerComesAfterItsRunSpan(_ text: String, _ run: MarkdownStyler.Span) throws {
        let ordered = MarkdownStyler.spans(in: text).map(\.span)
        let runIndex = try #require(ordered.firstIndex(of: run))
        let markerIndices = ordered.indices.filter { ordered[$0] == .emphasisMarker }
        #expect(markerIndices.count == 2, "\(ordered)")
        #expect(markerIndices.allSatisfy { runIndex < $0 }, "\(ordered)")
    }

    // Each marker maps to `.emphasis` through both tables.
    @Test(arguments: ["testo _corsivo_ qui", "testo __forte__ qui"])
    func eachMarkerMapsToEmphasisThroughBothHiddenKindTables(_ text: String) {
        let markers = MarkdownStyler.spans(in: text).filter { $0.span == .emphasisMarker }
        #expect(markers.count == 2, "\(text): \(markers.count) markers")
        for marker in markers {
            #expect(NoteTextView.Coordinator.hiddenKind(for: marker.span) == .emphasis)
            #expect(CardTextView.Coordinator.hiddenKind(for: marker) == .emphasis)
        }
    }

    // Green guards that must stay green: none of these carries an `.emphasisMarker`.
    @Test(arguments: [
        "nome_file_lungo",
        "file_name_here",
        "snake_case_name",
        "_lieve_mente",
        "a__b__ c",
        "[[nome_file_lungo]]",
        "[[20260811_Pergamenum_SpecApp]]",
        "testo `a_b_` qui",
        "```\n_x_\n```",
        "_solo",
        "_ a_",
        "____"
    ])
    func noMarkerIsEmittedWhereTheGrammarReadsPlainText(_ text: String) {
        let spans = MarkdownStyler.spans(in: text).map(\.span)
        #expect(!spans.contains(.emphasisMarker), "\(text.debugDescription): \(spans)")
    }
}

// MARK: - The delegate, driven directly

@MainActor
@Suite struct UnderscoreEmphasisDelegate {
    private static let note = "testo __forte__ e _lieve_\n"

    /// The four delimiters, derived from the string and never hand-counted.
    private static var strongOpen: HiddenMarker { marker("__", occurrence: 0) }
    private static var strongClose: HiddenMarker { marker("__", occurrence: 1) }
    private static var emphasisOpen: HiddenMarker { marker("_lieve_", occurrence: 0, length: 1) }
    private static var emphasisClose: HiddenMarker {
        let run = range(of: "_lieve_", in: note)
        return HiddenMarker(range: NSRange(location: NSMaxRange(run) - 1, length: 1), kind: .emphasis)
    }
    private static var all: [HiddenMarker] { [strongOpen, strongClose, emphasisOpen, emphasisClose] }

    private static func marker(_ needle: String, occurrence: Int, length: Int? = nil) -> HiddenMarker {
        let found = range(of: needle, in: note, occurrence: occurrence)
        return HiddenMarker(range: NSRange(location: found.location, length: length ?? found.length), kind: .emphasis)
    }

    private static func isCollapsed(_ paragraph: NSTextParagraph, at index: Int) -> Bool {
        let font = paragraph.attributedString.attribute(.font, at: index, effectiveRange: nil) as? NSFont
        return font == EditorDecorationDelegate.collapsedFont
    }

    @Test func theDerivedOffsetsAreWhereTheDelimitersAre() {
        let text = Self.note as NSString
        for marker in Self.all {
            let spelled = text.substring(with: marker.range)
            #expect(spelled == "_" || spelled == "__", "\(marker.range): \(spelled)")
        }
        #expect(Self.all.map(\.range.length) == [2, 2, 1, 1])
    }

    // At rest the paragraph is substituted, and keeps its length.
    @Test func atRestAParagraphWithUnderscoreMarkersIsSubstitutedAtTheSameLength() throws {
        let displayed = try #require(
            MarkupHidingFixture.displayedParagraph(Self.note, markers: Self.all),
            "the delegate refused the `_` markers as stale"
        )
        #expect(displayed.attributedString.length == (Self.note as NSString).length)
        for marker in Self.all {
            #expect(Self.isCollapsed(displayed, at: marker.range.location), "\(marker.range) is not collapsed")
        }
    }

    // Green: a revealed paragraph is drawn as stored.
    @Test func aRevealedParagraphIsNotSubstituted() {
        #expect(MarkupHidingFixture.displayedParagraph(Self.note, markers: Self.all, revealed: [0]) == nil)
    }

    // Green: the setting off leaves the hook inert.
    @Test func withTheSettingOffNothingIsSubstituted() {
        #expect(MarkupHidingFixture.displayedParagraph(Self.note, markers: Self.all, hidesMarkup: false) == nil)
    }

    // With `__forte__` revealed, only `_lieve_`'s markers collapse.
    @Test func withTheStrongRunRevealedOnlyTheEmphasisRunsMarkersCollapse() throws {
        let strongSpan = range(of: "__forte__", in: Self.note)
        let displayed = try #require(
            MarkupHidingFixture.displayedParagraph(
                Self.note, markers: Self.all, revealed: [0], spans: [0: [strongSpan]], revealsInlineSpans: true
            ),
            "no paragraph: the delegate refused the `_` markers as stale"
        )
        #expect(displayed.attributedString.length == (Self.note as NSString).length)
        #expect(!Self.isCollapsed(displayed, at: Self.strongOpen.range.location))
        #expect(!Self.isCollapsed(displayed, at: Self.strongClose.range.location))
        #expect(Self.isCollapsed(displayed, at: Self.emphasisOpen.range.location))
        #expect(Self.isCollapsed(displayed, at: Self.emphasisClose.range.location))
    }

    // Green guards: an `.emphasis` entry that no longer spells one or two copies of one delimiter
    // collapses nothing.
    @Test(arguments: [
        ("a *_b_* c\n", "*_"),   // mixed
        ("a ___b___ c\n", "___"),  // three
        ("corpo dopo\n", "co")     // two prose letters
    ])
    func aStaleEmphasisEntryDoesNotCollapseProse(_ text: String, _ stale: String) {
        let found = range(of: stale, in: text)
        #expect(found.location != NSNotFound)
        let entry = HiddenMarker(range: found, kind: .emphasis)
        #expect(MarkupHidingFixture.displayedParagraph(text, markers: [entry]) == nil, "\(stale)")
    }
}

// MARK: - The hosted note editor

@MainActor
@Suite struct UnderscoreEmphasisNoteEditor {
    private static let text = "testo _corsivo_ e __forte__\naltro\n"

    private static func delimiterRanges(in text: String) -> [NSRange] {
        let single = range(of: "_corsivo_", in: text)
        let double = range(of: "__forte__", in: text)
        return [
            NSRange(location: single.location, length: 1),
            NSRange(location: NSMaxRange(single) - 1, length: 1),
            NSRange(location: double.location, length: 2),
            NSRange(location: NSMaxRange(double) - 2, length: 2)
        ]
    }

    private func place(_ editor: ScrolledEditorFixture, caretAt location: Int) {
        editor.textView.setSelectedRange(NSRange(location: location, length: 0))
        editor.coordinator.applyReveal(to: editor.textView)
    }

    private func substituted(_ editor: ScrolledEditorFixture) -> NSTextParagraph? {
        MarkupHidingFixture.substitutedParagraph(editor.coordinator.decorations, note: editor.textView.string)
    }

    // The styling pass fills the delegate's table with the four delimiters.
    @Test func theDelegateTableHoldsFourEmphasisEntriesAtTheDelimiterRanges() {
        let editor = ScrolledEditorFixture(text: Self.text)
        defer { editor.window.orderOut(nil) }

        let entries = (editor.coordinator.decorations.hiddenMarkers[0] ?? []).filter { $0.kind == .emphasis }
        // Sorted: the styler's order across constructs is unspecified ("in no particular order").
        let ranges = entries.map(\.range).sorted { $0.location < $1.location }
        #expect(ranges == Self.delimiterRanges(in: Self.text), "\(entries)")
    }

    // With the caret on the second line the first paragraph is concealed.
    @Test func withTheCaretElsewhereTheParagraphIsSubstituted() {
        let editor = ScrolledEditorFixture(text: Self.text)
        defer { editor.window.orderOut(nil) }

        place(editor, caretAt: range(of: "altro", in: Self.text).location)

        #expect(substituted(editor) != nil, "the paragraph is drawn raw")
    }

    // Green: ADR-0018 §D2, the caret inside `_corsivo_` reveals the paragraph.
    @Test func withTheCaretInsideTheRunTheParagraphIsNotSubstituted() {
        let editor = ScrolledEditorFixture(text: Self.text)
        defer { editor.window.orderOut(nil) }

        place(editor, caretAt: range(of: "corsivo", in: Self.text).location + 2)

        #expect(substituted(editor) == nil)
    }

    // Green guard: a filename-shaped paragraph gets no entry.
    @Test func anIntrawordUnderscoreParagraphGetsNoEmphasisEntry() {
        let editor = ScrolledEditorFixture(text: "nome_file_lungo\naltro\n")
        defer { editor.window.orderOut(nil) }

        let entries = (editor.coordinator.decorations.hiddenMarkers[0] ?? []).filter { $0.kind == .emphasis }
        #expect(entries.isEmpty, "\(entries)")
    }
}

// MARK: - The hosted card

@MainActor
private struct Card {
    let scrollView: NSScrollView
    let textView: FormattingTextView
    let coordinator: CardTextView.Coordinator

    /// What the delegate hands back for the paragraph containing `offset`, as AppKit asks it
    /// during a layout pass: `nil` is "draw the stored paragraph as it is".
    func displayed(paragraphAt offset: Int) -> NSTextParagraph? {
        guard let storage = textView.textContentStorage else { return nil }
        let paragraph = (textView.string as NSString).paragraphRange(for: NSRange(location: offset, length: 0))
        return coordinator.decorations.textContentStorage(storage, textParagraphWith: paragraph)
    }
}

@MainActor
private func makeCard(_ text: String, editable: Bool = false) throws -> Card {
    let view = CardTextView(
        text: .constant(text),
        theme: .emergency,
        style: CardTextStyle(color: nil, alignment: nil),
        isEditable: editable,
        hidesMarkup: true,
        revealsInlineSpans: false
    )
    let coordinator = view.makeCoordinator()
    let scrollView = FormattingTextView.scrollableTextView()
    let textView = try #require(
        scrollView.documentView as? FormattingTextView,
        "scrollableTextView() must hand back an instance of the receiving class"
    )
    textView.delegate = coordinator
    textView.textContentStorage?.delegate = coordinator.decorations
    textView.textLayoutManager?.delegate = coordinator.decorations
    textView.string = text
    coordinator.configure(textView, editable: editable)
    coordinator.applyStyling(to: textView)
    textView.setSelectedRange(NSRange(location: 0, length: 0))
    return Card(scrollView: scrollView, textView: textView, coordinator: coordinator)
}

@MainActor
@Suite struct UnderscoreEmphasisCard {
    private static let text = "_corsivo_ e __forte__"

    @Test func theCardsTableHoldsFourEmphasisEntries() throws {
        let card = try makeCard(Self.text)

        let entries = (card.coordinator.hiddenMarkers[0] ?? []).filter { $0.kind == .emphasis }
        #expect(entries.count == 4, "\(entries)")
        let spelled = entries.sorted { $0.range.location < $1.range.location }
            .map { (Self.text as NSString).substring(with: $0.range) }
        #expect(spelled == ["_", "_", "__", "__"])
    }

    @Test func anUneditableCardDrawsItsUnderscoreMarkersConcealed() throws {
        let card = try makeCard(Self.text, editable: false)

        let displayed = try #require(card.displayed(paragraphAt: 0), "the card paragraph is drawn raw")
        #expect(displayed.attributedString.length == (Self.text as NSString).length)
    }

    // Green guard: a filename-shaped card gets no entry.
    @Test func anIntrawordUnderscoreCardGetsNoEmphasisEntry() throws {
        let card = try makeCard("nome_file_lungo")

        let entries = (card.coordinator.hiddenMarkers[0] ?? []).filter { $0.kind == .emphasis }
        #expect(entries.isEmpty, "\(entries)")
    }
}
