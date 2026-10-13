import Foundation
import Testing
@testable import Pergamenum

// ADR-0093 §D8, plan docs/plans/scoped-layout-followup.md, Task 5 (R-10, R-11, R-12).
//
// The windowed renumbering reads the lines around an edit instead of the note. Three pieces are pinned
// here: the facts of a styler line (`facts(ofLine:in:)`), the window a `RestyleScope` hands out
// (`renumberWindow(before:)`), and the cost of the windowed form (R-11: the same local structure costs
// the same lines read at the end of a 50 KB note and of a 1 MB one). The equality with the scoped form
// over random notes is in `ListRenumberWindowPropertyTests`.
//
// The facts count a line's fence delimiters and say whether it ends every run, the window names where
// a read may start and the fence parity there, and the read reports the lines it covered. A line is given to `facts` as its styler line, terminator included, which is the range
// `StructureMap` holds for it (`start ..< lineEnd`).

private let nel = "\u{85}"
private let lineSeparator = "\u{2028}"
private let paragraphSeparator = "\u{2029}"

/// The facts of the whole of `line`, taken to be one styler line of its own.
private func facts(of line: String) -> ListContinuation.LineFacts {
    let text = line as NSString
    return ListContinuation.facts(ofLine: NSRange(location: 0, length: text.length), in: text)
}

// MARK: - facts: fence delimiters

private let delimiterCases: [(line: String, count: Int)] = [
    ("```\n", 1),
    ("```swift\n", 1),
    ("~~~\n", 1),
    ("~~~ruby\n", 1),
    ("   ```\n", 1),
    ("\t~~~\n", 1),
    ("  \t```js\n", 1),
    ("prosa\n", 0),
    ("1. voce\n", 0),
    ("testo ``` dentro\n", 0),
    ("``\n", 0),
    ("```\r```\n", 2),
    ("```\(nel)```\n", 2),
    ("```\(lineSeparator)```\n", 2),
    ("```\(paragraphSeparator)```\n", 2),
    ("~~~\r```\n", 2),
    ("```\r1. voce\n", 1),
    ("prosa\(lineSeparator)   ```\n", 1),
]

// (R-10) A fence delimiter is a line, after its indentation, that starts with three backticks or
// three tildes; a styler line holding several lines (split by a lone CR, NEL, U+2028 or U+2029, which
// the styler does not split on) holds one per piece.
@Test(arguments: delimiterCases.indices)
func aStylerLineHoldsOneFenceDelimiterPerFenceLine(_ index: Int) {
    let item = delimiterCases[index]
    #expect(facts(of: item.line).fenceDelimiters == item.count, "\(item.line.debugDescription)")
}

// MARK: - facts: lines that end every run

private let endsCases: [(line: String, ends: Bool)] = [
    ("\n", true),
    ("   \n", true),
    ("\t\n", true),
    ("- bullet\n", true),
    ("* bullet\n", true),
    ("- [ ] attivita\n", true),
    ("prosa\n", true),
    ("# Titolo\n", true),
    ("prosa\r\n", true),
    ("1. voce\n", false),
    ("12) voce\n", false),
    ("  1. voce\n", false),
    ("    1. voce\n", false),
    ("\t1. voce\n", false),
    ("  - bullet\n", false),
    ("  prosa\n", false),
    // Only the last line of a styler line counts: it is the one the next styler line follows.
    ("1. voce\(lineSeparator)\n", true),
    ("1. voce\(lineSeparator)   \n", true),
    ("- voce\(paragraphSeparator)\n", true),
    ("1. voce\r\n", false),
    ("- voce\(lineSeparator)1. altra\n", false),
    ("- voce\r1. altra\n", false),
    ("1. voce\(nel)prosa\n", true),
    ("1. voce\r  1. annidata\n", false),
]

// (R-10) A line ends every run when its last line is blank, or sits at column 0 and is not an ordered
// item: such a line is a boundary whatever level the run is at. An ordered item and anything indented
// is not.
@Test(arguments: endsCases.indices)
func aStylerLineEndsEveryRunByItsLastLine(_ index: Int) {
    let item = endsCases[index]
    #expect(facts(of: item.line).endsEveryRun == item.ends, "\(item.line.debugDescription)")
}

// (R-10) The last styler line of a text has no terminator, and the empty text is one empty line.
@Test func theLastLineOfATextHasNoTerminator() {
    #expect(!facts(of: "1. voce").endsEveryRun)
    #expect(facts(of: "prosa").endsEveryRun)
    #expect(facts(of: "").endsEveryRun)
    #expect(facts(of: "```").fenceDelimiters == 1)
}

// (R-10) The facts of a line depend on its own range only, not on the lines around it.
@Test func theFactsAreReadFromTheLinesOwnRange() {
    let text = "```\n1. voce\n- bullet\n~~~\n" as NSString
    let second = text.range(of: "1. voce\n")
    let third = text.range(of: "- bullet\n")
    let fourth = text.range(of: "~~~\n")
    #expect(ListContinuation.facts(ofLine: second, in: text) == .init(fenceDelimiters: 0, endsEveryRun: false))
    #expect(ListContinuation.facts(ofLine: third, in: text) == .init(fenceDelimiters: 0, endsEveryRun: true))
    #expect(ListContinuation.facts(ofLine: fourth, in: text).fenceDelimiters == 1)
}

// MARK: - renumberWindow(before:)

private func start(of needle: String, in text: String) -> Int {
    let found = (text as NSString).range(of: needle)
    if found.location == NSNotFound { Issue.record("\(needle.debugDescription) is not in \(text.debugDescription)") }
    return found.location
}

private func window(_ text: String, editing needle: String) -> ListContinuation.Window? {
    RestyleScope(text: text).renumberWindow(before: start(of: needle, in: text))
}

/// One window case: the note, the line edited, the line the window should start at (nil: the first
/// line), and whether a fence is open there.
private struct WindowCase {
    let name: String
    let text: String
    let edit: String
    let start: String?
    let fenceOpen: Bool

    init(_ name: String, _ text: String, _ edit: String, _ start: String?, _ fenceOpen: Bool) {
        self.name = name
        self.text = text
        self.edit = edit
        self.start = start
        self.fenceOpen = fenceOpen
    }
}

private let windowCases: [WindowCase] = [
    // The nearest line whose previous line ends every run.
    .init("a blank line above the run", "1. a\n2. b\n\n3. c\n4. d\n5. e\n", "5. e", "3. c", false),
    .init("the second item of the run", "1. a\n2. b\n\n3. c\n4. d\n5. e\n", "4. d", "3. c", false),
    .init("column-0 prose above the run", "intro\n1. a\n2. b\n3. c\n", "3. c", "1. a", false),
    .init("a column-0 bullet above a nested run", "- x\n  1. a\n  2. b\n  3. c\n", "3. c", "  1. a", false),
    .init("an indented item does not end a run", "1. a\n  1. n\n  2. m\n2. b\n", "2. b", nil, false),
    .init("a spaces-only line above the run", "1. a\n   \n2. b\n3. c\n", "3. c", "2. b", false),
    .init("the first line", "1. a\n2. b\n", "1. a", nil, false),
    // Fence parity above the start.
    .init("after one fence", "```\ncode\n\n1. a\n2. b\n", "2. b", "1. a", true),
    .init("after one tilde fence", "~~~\n\n1. a\n2. b\n", "2. b", "1. a", true),
    .init("after two fences", "```\nx\n```\n\n1. a\n2. b\n", "2. b", "1. a", false),
    .init("after a fence opened behind a lone CR", "prosa\r```\n\n1. a\n2. b\n", "2. b", "1. a", true),
    .init("after two delimiters in one styler line", "```\r```\n\n1. a\n2. b\n", "2. b", "1. a", false),
    .init("after three fences", "```\n```\n```\n\n1. a\n2. b\n", "2. b", "1. a", true),
]

// (R-10) The window starts at the nearest line whose previous line ends every run (or at the first
// line), and says whether a fence is open there: the delimiters above it, mod 2.
@Test(arguments: windowCases.indices)
func theWindowStartsWhereAnEarlierLineEndedEveryRun(_ index: Int) throws {
    let item = windowCases[index]
    let found = try #require(window(item.text, editing: item.edit), "\(item.name): no window")
    let expectedStart = item.start.map { start(of: $0, in: item.text) } ?? 0
    #expect(found.start == expectedStart, "\(item.name): the window starts at \(found.start), not \(expectedStart)")
    #expect(found.fenceOpen == item.fenceOpen, "\(item.name): fenceOpen is \(found.fenceOpen)")
}

// (R-10) A scope that has just been built answers for any offset, the end of the text included.
@Test func aFreshScopeAnswersAtTheEndOfTheText() {
    let text = "1. a\n2. b\n"
    let scope = RestyleScope(text: text)
    #expect(scope.renumberWindow(before: (text as NSString).length) != nil)
    #expect(scope.renumberWindow(before: 0) == Window(start: 0, fenceOpen: false))
}

private typealias Window = ListContinuation.Window

// (R-10) After a wholesale replace the map describes a text that is gone, and the scope answers nothing
// until the full restyle it asks for rebuilds it.
@Test func aWholesaleReplaceLeavesNoWindow() {
    let old = "1. a\n2. b\n\n3. c\n"
    var scope = RestyleScope(text: old)
    #expect(scope.renumberWindow(before: 12) != nil, "a fresh scope gave no window")

    let replacement = "9. x\n8. y\n\n7. z\n6. w\n"
    let length = (replacement as NSString).length
    scope.record(StorageEdit(range: NSRange(location: 0, length: length), delta: length - (old as NSString).length),
                 in: replacement as NSString)

    #expect(scope.renumberWindow(before: 12) == nil)
}

// MARK: - R-11, the cost does not follow the note

/// The ordered list the cost tests edit, as it is after an item was deleted: items 1 to 5 and 7 to 13
/// (twelve in all), a nested run under 7 that is misnumbered, a fence above, blank lines around.
private let localStructure = """

    ```sh
    npm run build
    ```

    1. uno
    2. due
    3. tre
    4. quattro
    5. cinque
    7. sette
       1. annidato uno
       3. annidato tre
    8. otto
    9. nove
    10. dieci
    11. undici
    12. dodici
    13. tredici

    Coda di prosa.

    """

/// A windowed read of the local structure behind a prefix: the note, the edit, the answer and the window.
private struct WindowedRead {
    let text: String
    let edited: NSRange
    let result: ListContinuation.Windowed
    let window: ListContinuation.Window
}

private func windowed(prefixBytes: Int) throws -> WindowedRead {
    let prefix = RestyleBudget.syntheticNote(bytes: prefixBytes, variant: .prose)
    let text = prefix + localStructure
    let edited = NSRange(location: (prefix as NSString).length + (localStructure as NSString).range(of: "7. sette").location, length: 0)
    let found = try #require(RestyleScope(text: text).renumberWindow(before: edited.location), "no window at \(prefixBytes) bytes")
    return WindowedRead(
        text: text, edited: edited,
        result: ListContinuation.renumbered(text as NSString, touching: edited, window: found), window: found
    )
}

private func applied(_ renumbering: ListContinuation.Renumbering, to text: String) -> String {
    (text as NSString).replacingCharacters(in: renumbering.range, with: renumbering.replacement)
}

// (R-11) The same local structure at the end of a 50 KB and of a 1 MB note: the windowed read covers
// the same lines, however many lie above it, and gives the same renumbering, offsets aside.
@Test func theSameEditReadsTheSameLinesInA50KBAndA1MBNote() throws {
    let small = try windowed(prefixBytes: 50 * 1024)
    let large = try windowed(prefixBytes: 1024 * 1024)

    #expect(small.result.linesRead > 0)
    #expect(small.result.linesRead == large.result.linesRead, "\(small.result.linesRead) lines in 50 KB, \(large.result.linesRead) in 1 MB")
    #expect(small.result.readRange.length > 0)
    #expect(small.result.readRange.length == large.result.readRange.length)
    #expect(small.result.linesRead < 100, "the read followed the note: \(small.result.linesRead) lines")
    #expect(NSMaxRange(small.result.readRange) <= (small.text as NSString).length)

    let one = try #require(small.result.renumbering, "no renumbering in the 50 KB note")
    let other = try #require(large.result.renumbering, "no renumbering in the 1 MB note")
    #expect(one.replacement == other.replacement)
    #expect(one.range.length == other.range.length)
    #expect(one.range.location - small.window.start == other.range.location - large.window.start)
    for step in 0...one.range.length {
        #expect(one.mapping(one.range.location + step) - one.range.location
                == other.mapping(other.range.location + step) - other.range.location, "mapping at +\(step)")
    }
}

// (R-11) And what it renumbers is right: the list counts on from 5 and the nested run is fixed, in both,
// and the windowed answer equals the scoped one.
@Test(arguments: [50 * 1024, 1024 * 1024])
func theWindowedRenumberingIsTheScopedOne(_ prefixBytes: Int) throws {
    let item = try windowed(prefixBytes: prefixBytes)
    let renumbering = try #require(item.result.renumbering)
    let text = applied(renumbering, to: item.text)

    #expect(text.hasSuffix("5. cinque\n6. sette\n   1. annidato uno\n   2. annidato tre\n7. otto\n8. nove\n9. dieci\n10. undici\n11. dodici\n12. tredici\n\nCoda di prosa.\n"))
    let scoped = try #require(ListContinuation.renumbered(item.text, touching: item.edited))
    #expect(renumbering.range == scoped.range)
    #expect(renumbering.replacement == scoped.replacement)
    #expect(item.result.readRange.location >= item.window.start)
    #expect(NSLocationInRange(renumbering.range.location, item.result.readRange))
}

// MARK: - R-12, the card keeps the whole-text form

// (R-12) The card's editor renumbers the whole text of its small buffer, as it always did: the one-argument
// form, never the windowed one. `CardFormattingTests` stays untouched, which is checked by `git diff` at
// review.
@Test func theCardEditorCallsTheWholeTextForm() throws {
    let root = try resolvedRepoRoot()
    let path = "Sources/Features/Workspace/CardTextView+ListEditing.swift"
    let source = try String(contentsOf: root.appending(path: path), encoding: .utf8)

    #expect(source.contains("ListContinuation.renumbered(textView.string)"), "\(path) no longer calls the one-argument form")
    #expect(!source.contains("window:"), "\(path) reads a window")
    #expect(!source.contains("renumberWindow"), "\(path) asks a scope for a window")
}
