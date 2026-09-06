import Foundation
import Testing
@testable import Pergamenum

/// ADR-0033 §D1 (plan `2026-09-06-pg-099-views-board-renderer-orphaned-by`, Task 1):
/// `MarkdownStyler` learns a `.viewBlockRun` span for a closed `pergamenum-view` fence -
/// opening backticks through closing ones, inclusive - so a later task can substitute it
/// for a live attachment (R-01/R-02/R-03/R-04). The classifier never reads `render:` and
/// never runs the query grammar: a fence whose body does not parse still gets a span here,
/// because R-08's fallback-to-raw-text refusal is Task 5's, not this one's - the styler
/// must not re-run `ViewBlock.parse` on every keystroke.
///
/// `MarkdownStyler.viewBlockRuns(in:outside:)` is a **TESTER STUB** for this task, returning
/// `[]` unconditionally (see its doc comment in `MarkdownStyler.swift`). Every assertion
/// below that expects a `.viewBlockRun` to exist is red until the coder fills that stub in;
/// the ones that expect none (unclosed fence, wrong language, the nested-fence case) are
/// already true against the stub, the same "some assertions are red, some are already true"
/// shape `Tests/TableRenderingTests.swift`'s own header documents for its Task 4 stub.
///
/// Contract-staleness: `Tests/MarkdownStylerTests.swift` is re-run in full and stays green
/// unmodified - its only two full-array assertions (`# Titolo`, `*corsivo*`) contain no
/// fence, so a red result there would mean the span is being emitted outside a fence.

private func spans(_ text: String) -> [MarkdownStyler.Span] {
    MarkdownStyler.spans(in: text).map(\.span)
}

private func styled(_ text: String, _ span: MarkdownStyler.Span) -> String? {
    guard let match = MarkdownStyler.spans(in: text).first(where: { $0.span == span }) else { return nil }
    return String(text[match.range])
}

/// Every `.viewBlockRun` span's own substring, in the order `spans(in:)` returns them -
/// document order, since `CodeFence.regions(in:)` walks the note top to bottom.
private func viewBlockRuns(_ text: String) -> [String] {
    MarkdownStyler.spans(in: text)
        .filter { $0.span == .viewBlockRun }
        .map { String(text[$0.range]) }
}

// MARK: - R-01: a closed `render: table` fence

private let tableViewNote = """
Prima del blocco.

```pergamenum-view
render: table
```

Dopo il blocco.
"""

@Test func aClosedViewFenceYieldsExactlyOneViewBlockRun() {
    // R-01: the opening backticks through the closing ones, inclusive - `.codeBlock`'s own
    // `aFenceIsStyledAsOneBlockIncludingItsBackticks` asserts the identical shape.
    #expect(viewBlockRuns(tableViewNote).count == 1)
    #expect(styled(tableViewNote, .viewBlockRun) == "```pergamenum-view\nrender: table\n```")
}

@Test func theSpanDoesNotSwallowProseOutsideTheFence() {
    // The rest of the note is untouched: this is the table's own
    // `whatIsOutsideTheFenceIsStillMarkdown` guard, restated for the new construct.
    #expect(styled(tableViewNote, .viewBlockRun)?.contains("Dopo il blocco") == false)
}

// MARK: - R-02/R-03/R-04: the span does not read `render:` at all

@Test(arguments: ["gallery", "calendar", "board"])
func aClosedViewFenceYieldsASpanRegardlessOfTheRenderKeyword(_ renderer: String) {
    // R-02 (gallery), R-03 (calendar), R-04 (board) - `render: table` is covered by
    // `aClosedViewFenceYieldsExactlyOneViewBlockRun` above. One span per keyword, since the
    // classifier decides purely from the fence's language, never from its body.
    let note = "```pergamenum-view\nrender: \(renderer)\n```"
    #expect(spans(note).filter { $0 == .viewBlockRun }.count == 1)
}

// MARK: - An unclosed fence yields no span (ADR §D6, C5)

@Test func anUnclosedViewFenceAtTheEndOfANoteYieldsNoSpan() {
    // C5: `CodeFence.regions(in:)` runs an unclosed fence to the end of the text by design
    // (the state every note is briefly in while someone types the opening backticks) - a
    // `.viewBlockRun` must not follow it there, or typing `pergamenum-view` alone would take
    // the rest of the note out of the layout mid-keystroke.
    let note = "Testo.\n\n```pergamenum-view\nrender: table"
    #expect(!spans(note).contains(.viewBlockRun))
}

@Test func aFenceClosedOnItsOwnNextLineIsStillClosed() {
    // The boundary case for the "closed" guard: a fence with an empty body still counts as
    // closed, since a genuine closing line follows it - the state right after the slash
    // menu writes an empty `pergamenum-view` fence.
    let note = "```pergamenum-view\n```"
    #expect(viewBlockRuns(note).count == 1)
}

// MARK: - A fence in another language yields no span

@Test func aSwiftFenceYieldsNoViewBlockRun() {
    let note = "```swift\nlet a = 1\n```"
    #expect(!spans(note).contains(.viewBlockRun))
}

// MARK: - Nested fence: whatever `CodeFence.regions` answers, not assumed from intuition

@Test func aViewFenceQuotedInsideAnotherFenceFollowsCodeFencesOwnAlternatingGrammar() {
    // ADR Consequences: `CodeFence.regions(in:)` toggles open/closed on *every* line that
    // starts with three backticks, with no concept of nesting - exactly the grammar
    // `ViewCatalogue.locations(in:)` already relies on for this identical fixture
    // (`Tests/SidebarTests.swift`'s `aViewFenceQuotedInsideAnotherBlockIsNotAView`). The
    // quoted `` ```pergamenum-view `` opener at line 4 closes the *outer* `markdown` fence
    // instead of opening its own - the outer fence's own declared language ("markdown") is
    // what the region carries, not the closing line's text - so only the real view below
    // survives. Documented here rather than asserted from intuition.
    let note = """
    # Come si scrive una vista

    ```markdown
    ```pergamenum-view
    render: table
    ```
    ```

    ## Quella vera

    ```pergamenum-view
    render: list
    ```
    """
    let runs = viewBlockRuns(note)
    #expect(runs.count == 1)
    #expect(runs.first == "```pergamenum-view\nrender: list\n```")
}

// MARK: - Two fences in one note (SPEC Edge cases)

@Test func twoViewFencesInOneNoteYieldTwoSpansInDocumentOrder() {
    let note = """
    ```pergamenum-view
    render: table
    ```

    Testo in mezzo.

    ```pergamenum-view
    render: board
    ```
    """
    let runs = viewBlockRuns(note)
    #expect(runs.count == 2)
    #expect(runs == [
        "```pergamenum-view\nrender: table\n```",
        "```pergamenum-view\nrender: board\n```",
    ])
}

// MARK: - R-08: a malformed body still yields a span here

@Test func aFenceWithAnUnparseableBodyStillYieldsASpanHere() {
    // R-08's refusal to render happens in Task 5's `applyViewBlocks`, never in the styler:
    // running `ViewBlock.parse` on every keystroke is exactly what the classifier must not
    // do. A garbage body still gets classified as one whole `.viewBlockRun`; falling back to
    // raw text for it is a later task's job.
    let note = """
    ```pergamenum-view
    questo non è affatto un where valido !!!
    ```
    """
    #expect(spans(note).filter { $0 == .viewBlockRun }.count == 1)
}

// MARK: - Spell-check suppression (M8's own rule, restated for the new construct)

@Test func theViewBlockRunSpanSuppressesSpellCheck() {
    #expect(MarkdownStyler.suppressesSpellCheck(.viewBlockRun))
}
