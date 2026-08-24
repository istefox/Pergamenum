import Foundation
import Testing
@testable import Pergamenum

// ADR-0021 ("A task carries its Workspace and its place in a project as caret markers in
// its own line, and nothing new is stored anywhere else"), §D1 and §D2. Plan
// `docs/superpowers/plans/2026-08-24-workspace-tasks-notes-integration.md`, Task 1: the three
// caret markers `^[[<canvas>.canvas]]`, `^id(<N>)` and `^parent(<N>)`, pure - no index, no
// vault, no disk, matching `Tests/TaskTests.swift`'s own split from the rewriting and
// view-sorting tests beside it.
//
// `Sources/Core/Tasks/TaskItem.swift` carries only the three defaulted properties this file
// references, and `Sources/Core/Tasks/TaskParser.swift`'s `nextLocalID(in:)` is a
// signature-only stub as of this commit (ADR-0155 §D1 style): every test below is expected
// to fail red on its assertions, not to fail to compile - the coder's Task 1 work fills in
// the marker recognition, the `links`/`text` filtering and `nextLocalID`'s scan that this
// file already encodes as assertions. Two tests are guards rather than new-behaviour
// assertions and are expected to already be green: the backward-compatibility case
// (`^[[Nota]]`, no `.canvas`) and the plain-link case that mirrors
// `Tests/TaskTests.swift:37-40`.

private func task(_ line: String, in path: String = "Nota.md", at index: Int = 0) -> TaskItem {
    TaskParser.parse(line: line, sourcePath: path, lineIndex: index)!
}

// MARK: - `^[[<canvas>.canvas]]` — the Workspace marker (R-02, R-04)

@Test func workspaceMarkerIsReadAndExcludedFromLinks() {
    let t = task("- [ ] Verifica disegno ^[[vibrofer-emea.canvas]]")
    #expect(t.workspacePath == "vibrofer-emea.canvas")
    #expect(!t.links.contains("vibrofer-emea.canvas"))
}

@Test func aCaretedLinkWithoutDotCanvasStaysAnOrdinaryWikilinkBackwardCompatible() {
    // Today's behaviour, unchanged (ADR-0021 D1): a caret in front of a link to a note
    // with no `.canvas` suffix is not a Workspace marker at all. This is the guard for
    // the backward-compatibility argument and it is expected to already be green.
    let t = task("- [ ] Vedi ^[[Nota]]")
    #expect(t.workspacePath == nil)
    #expect(t.links == ["Nota"])
}

@Test func aPlainCanvasLinkWithoutACaretIsNotAWorkspaceAssignment() {
    // Guards Tests/TaskTests.swift:37-40 (`tasks[7].links == ["Progetto X.canvas"]`),
    // which must stay green untouched: a plain wikilink to a board is still just a
    // link, independent of the new caret mechanism (R-04's other half).
    let t = task("- [ ] Task con canvas collegato, vedi [[Progetto X.canvas]]")
    #expect(t.workspacePath == nil)
    #expect(t.links.contains("Progetto X.canvas"))
}

@Test func theCanvasSuffixDetectionIsCaseInsensitive() {
    // ADR-0021 D1: "the target ends in `.canvas` (case-insensitively)".
    let t = task("- [ ] Verifica ^[[vibrofer-emea.CANVAS]]")
    #expect(t.workspacePath == "vibrofer-emea.CANVAS")
}

@Test func aSecondWorkspaceMarkerIsIgnoredTheFirstWins() {
    // ADR-0021 D1: "A second occurrence of any of the three is ignored and the first
    // wins", the same rule `marker(in:prefix:)` already applies to a line carrying two
    // `>` dates.
    let t = task("- [ ] Verifica ^[[vibrofer-emea.canvas]] ^[[altro-progetto.canvas]]")
    #expect(t.workspacePath == "vibrofer-emea.canvas")
    #expect(!t.links.contains("vibrofer-emea.canvas"))
    #expect(!t.links.contains("altro-progetto.canvas"))
}

// MARK: - `^id(<N>)` and `^parent(<N>)` (ADR-0021 D1, D2)

@Test func idMarkerSetsLocalID() {
    let t = task("- [ ] Capitolato ^id(3)")
    #expect(t.localID == 3)
    #expect(t.parentLocalID == nil)
}

@Test func parentMarkerSetsParentLocalID() {
    let t = task("- [ ] Sotto-task ^parent(1)")
    #expect(t.parentLocalID == 1)
    #expect(t.localID == nil)
}

@Test func allThreeMarkersAreNilWhenAbsent() {
    let t = task("- [ ] Task semplice")
    #expect(t.workspacePath == nil)
    #expect(t.localID == nil)
    #expect(t.parentLocalID == nil)
}

// MARK: - Order independence (R-04)

@Test(arguments: [
    // `^[[...]]`, then `^id`, then `^parent`.
    "- [ ] Verifica ^[[vibrofer-emea.canvas]] ^id(2) ^parent(1) "
        + ">2026-09-01 !2026-09-10 [[Nota A]] [[Nota B]] #project-x",
    // `^parent`, then `^[[...]]`, then `^id`.
    "- [ ] Verifica ^parent(1) ^[[vibrofer-emea.canvas]] ^id(2) "
        + ">2026-09-01 !2026-09-10 [[Nota A]] [[Nota B]] #project-x",
    // `^id`, then `^parent`, then `^[[...]]` at the very end.
    "- [ ] Verifica ^id(2) ^parent(1) "
        + ">2026-09-01 !2026-09-10 [[Nota A]] [[Nota B]] #project-x ^[[vibrofer-emea.canvas]]",
])
func allThreeMarkersParseInAnyOrderAlongsideExistingSyntax(_ line: String) {
    let t = task(line)
    #expect(t.workspacePath == "vibrofer-emea.canvas")
    #expect(t.localID == 2)
    #expect(t.parentLocalID == 1)
    #expect(t.scheduled == CalendarDate(iso: "2026-09-01"))
    #expect(t.due == CalendarDate(iso: "2026-09-10"))
    #expect(t.links == ["Nota A", "Nota B"])
    #expect(t.project == Tag("project-x"))
}

// MARK: - `text` strips all three markers cleanly

@Test func displayTextStripsAllThreeMarkersLeavingNoDoubleSpaceOrStrandedCaret() {
    let t = task("- [ ] Verifica ^[[vibrofer-emea.canvas]] disegno ^id(2) e ^parent(1) finale")
    #expect(!t.text.contains("^"))
    #expect(!t.text.contains("id("))
    #expect(!t.text.contains("parent("))
    #expect(!t.text.contains("[["))
    #expect(!t.text.contains("  "))
}

// MARK: - Fenced code blocks (the existing `codeRanges` skip still holds)

@Test func aCaretMarkerInsideAFencedCodeBlockIsNotATask() {
    let note = """
    - [ ] Vero task

    ```markdown
    - [ ] Esempio nella documentazione ^id(3)
    ```

    - [x] Altro vero task
    """
    let tasks = TaskParser.tasks(in: note, sourcePath: "x.md")
    #expect(tasks.map(\.text) == ["Vero task", "Altro vero task"])
}

// MARK: - `TaskParser.nextLocalID(in:)` (ADR-0021 D2)

@Test func nextLocalIDStartsAtOneForANoteWithNoIDs() {
    let note = """
    - [ ] Senza id
    - [ ] Ancora senza id ^parent(4)
    """
    #expect(TaskParser.nextLocalID(in: note) == 1)
}

@Test func nextLocalIDIsOneMoreThanTheHighestExistingID() {
    let note = """
    - [ ] Uno ^id(1)
    - [ ] Due ^id(5)
    - [ ] Tre ^id(3)
    """
    #expect(TaskParser.nextLocalID(in: note) == 6)
}

@Test func nextLocalIDCountsIDsOnEveryTaskLineNotOnlyOpenOnes() {
    let note = """
    - [x] Fatto ^id(7) @done(2026-08-11)
    - [-] Annullato ^id(2)
    - [>] Ripianificato ^id(9)
    """
    #expect(TaskParser.nextLocalID(in: note) == 10)
}
