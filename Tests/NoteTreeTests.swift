import Foundation
import Testing
@testable import Pergamenum

// MARK: - Folder tree

/// A record with nothing filled in but its path: the tree reads the path and the
/// title and ignores everything else about a note.
private func note(_ path: String) -> NoteRecord {
    NoteRecord(
        relativePath: path,
        title: (path as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: ""),
        frontmatter: .empty, linkTargets: [], tasks: [],
        modifiedAt: .distantPast, byteSize: 0, contentHash: "-"
    )
}

@Test func notesAtTheRootStayAtTheRoot() {
    let tree = NoteTree.build(from: [note("Appunti.md"), note("Idee.md")])
    #expect(tree.map(\.name) == ["Appunti", "Idee"])
    #expect(tree.allSatisfy { $0.kind == .note })
    // Nil rather than empty: a leaf must draw no disclosure triangle.
    #expect(tree.allSatisfy { $0.children == nil })
}

@Test func aNoteInAFolderGetsAFolderAboveIt() {
    let tree = NoteTree.build(from: [note("01 Progetti/Trasmissibilità.md")])
    #expect(tree.count == 1)
    #expect(tree[0].kind == .folder)
    #expect(tree[0].name == "01 Progetti")
    #expect(tree[0].id == "01 Progetti")
    #expect(tree[0].children?.map(\.name) == ["Trasmissibilità"])
    #expect(tree[0].children?[0].id == "01 Progetti/Trasmissibilità.md")
}

@Test func foldersNestAsDeeplyAsThePathDoes() throws {
    let tree = NoteTree.build(from: [note("01 Progetti/Vibrofer/Sito/Brief.md")])
    let progetti = try #require(tree.first)
    let vibrofer = try #require(progetti.children?.first)
    let sito = try #require(vibrofer.children?.first)
    #expect(vibrofer.id == "01 Progetti/Vibrofer")
    #expect(sito.id == "01 Progetti/Vibrofer/Sito")
    #expect(sito.children?.map(\.name) == ["Brief"])
}

@Test func foldersComeBeforeNotesAtEveryLevel() {
    // "Zeta" sorts after "Alfa" alphabetically and still comes second: a folder is
    // never mixed in among the notes, which is what makes the tree scannable.
    let tree = NoteTree.build(from: [note("Alfa.md"), note("Zeta/Nota.md")])
    #expect(tree.map(\.kind) == [.folder, .note])
    #expect(tree.map(\.name) == ["Zeta", "Alfa"])
}

@Test func namesSortTheWayTheFinderSortsThem() {
    // Plain string ordering puts "10" before "9". A folder list that does that is
    // read as broken, because every other file browser on the Mac does not.
    let tree = NoteTree.build(from: [
        note("10 Archivio/A.md"), note("9 Attivi/B.md"), note("02 Aree/C.md"),
    ])
    #expect(tree.map(\.name) == ["02 Aree", "9 Attivi", "10 Archivio"])
}

@Test func aFolderCountsEveryNoteBelowIt() throws {
    let tree = NoteTree.build(from: [
        note("01 Progetti/A.md"),
        note("01 Progetti/Sotto/B.md"),
        note("01 Progetti/Sotto/C.md"),
        note("Fuori.md"),
    ])
    let progetti = try #require(tree.first)
    #expect(progetti.noteCount == 3)
    #expect(progetti.children?.first(where: { $0.name == "Sotto" })?.noteCount == 2)
}

@Test func twoNotesWithTheSameNameInDifferentFoldersStayApart() {
    // The identity is the path, not the title: with the title as id the outline would
    // collapse the two into one row and select both at once.
    let tree = NoteTree.build(from: [note("A/Nota.md"), note("B/Nota.md")])
    #expect(tree.count == 2)
    #expect(tree.flatMap { $0.children ?? [] }.map(\.id) == ["A/Nota.md", "B/Nota.md"])
}

@Test func theAncestorsOfANoteAreTheFoldersToOpenToSeeIt() {
    #expect(NoteTree.ancestors(of: "01 Progetti/Vibrofer/Brief.md")
        == ["01 Progetti", "01 Progetti/Vibrofer"])
    // A note at the root needs nothing opened.
    #expect(NoteTree.ancestors(of: "Appunti.md").isEmpty)
}

// MARK: - `NoteTree.build(fromPaths:)` (ADR-0021 "A task carries its Workspace and its place in
// a project as caret markers in its own line, and nothing new is stored anywhere else", §D10, R-01).
// Plan `docs/superpowers/plans/2026-08-24-workspace-tasks-notes-integration.md`, Task 6: the
// Workspace folder browser's second entry point over the same private `Builder`, exercised here
// with `.canvas` paths rather than `NoteRecord`s. Every test above this mark uses `build(from:)`
// and is left untouched - it is the guard that the `Builder` refactor this task asks for does not
// change the note tree's existing behaviour.
//
// `NoteTree.build(fromPaths:)` is a signature-only stub returning `[]` as of this commit: every
// test below is expected to fail red on its assertions, not to fail to compile.

@Test func buildFromPathsProducesTheSameFolderShapeBuildFromNotesUses() {
    let tree = NoteTree.build(fromPaths: [
        "Appunti.canvas",
        "01 Progetti/vibrofer-emea/vibrofer-emea.canvas",
        "01 Progetti/altro.canvas",
        "9 Attivi/nine.canvas",
        "10 Archivio/ten.canvas",
    ])

    // Hand-written expected tree: folders before leaves at every level (never mixed
    // in among them, `foldersComeBeforeNotesAtEveryLevel` above), Finder-style sort
    // ("9 Attivi" before "10 Archivio", `namesSortTheWayTheFinderSortsThem` above),
    // `id` is the vault-relative path, `name` is the file name with its extension
    // stripped, and a leaf carries `children == nil` so the outline draws no
    // disclosure triangle on it - every one of these is a property `build(from:)`
    // already has, and `build(fromPaths:)` is asked to have the identical shape.
    let expected: [NoteTree.Node] = [
        NoteTree.Node(
            id: "01 Progetti", name: "01 Progetti", kind: .folder,
            children: [
                NoteTree.Node(
                    id: "01 Progetti/vibrofer-emea", name: "vibrofer-emea", kind: .folder,
                    children: [
                        NoteTree.Node(
                            id: "01 Progetti/vibrofer-emea/vibrofer-emea.canvas",
                            name: "vibrofer-emea", kind: .note, children: nil, noteCount: 1
                        ),
                    ],
                    noteCount: 1
                ),
                NoteTree.Node(
                    id: "01 Progetti/altro.canvas", name: "altro", kind: .note, children: nil, noteCount: 1
                ),
            ],
            noteCount: 2
        ),
        NoteTree.Node(
            id: "9 Attivi", name: "9 Attivi", kind: .folder,
            children: [
                NoteTree.Node(id: "9 Attivi/nine.canvas", name: "nine", kind: .note, children: nil, noteCount: 1),
            ],
            noteCount: 1
        ),
        NoteTree.Node(
            id: "10 Archivio", name: "10 Archivio", kind: .folder,
            children: [
                NoteTree.Node(id: "10 Archivio/ten.canvas", name: "ten", kind: .note, children: nil, noteCount: 1),
            ],
            noteCount: 1
        ),
        NoteTree.Node(id: "Appunti.canvas", name: "Appunti", kind: .note, children: nil, noteCount: 1),
    ]

    #expect(tree == expected)
}

@Test func buildFromPathsOnAnEmptyListYieldsAnEmptyTree() {
    #expect(NoteTree.build(fromPaths: []) == [])
}

@Test func buildFromPathsNeverExtendsNodeKind() {
    // ADR-0021 D10: a board row is a `.note` leaf, not a new `Kind` case - extending
    // the enum would force every `switch` over `Kind` in `NoteListPane` to grow a case
    // for something that can never appear there.
    let tree = NoteTree.build(fromPaths: ["Board.canvas"])
    #expect(tree.map(\.kind) == [.note])
}

// MARK: - NoteListPane.opening(from:to:currentlyOpen:isComposingNote:) (ADR-0026 §D4)
// Plan `docs/superpowers/plans/2026-08-27-drag-and-drop-board-files-into-workspace.md`,
// Task 6: the Note pane's own collapse rule, extracted as a RED-placeholder
// `nonisolated static` on `NoteListPane` (`Sources/Features/Editor/NoteListPane.swift`,
// beside `selectedPath`) by this test step, per Task 6's dispatch brief - the code step
// wires the real body into the `Binding<Set<String>>` `selectedPath` becomes.
//
// Adapted from `WorkspaceBrowser.opening(from:to:currently:in:)` (Task 5,
// `Tests/WorkspaceMultiSelectionTests.swift`): no `WorkspaceSelection` and no tree
// lookup here (a `Set<String>` member already *is* the note's own vault-relative path),
// and one extra fact Workspace's boards/folders have no equivalent of -
// `isComposingNote` - because the same "one id, already open" case means two different
// things here depending on it: `.leaveComposer` or nothing, never a bare `String?`
// return (the shape a caller could not use to tell those two apart without redoing the
// comparison the rule already made).
//
// RED: the placeholder returns `nil` unconditionally - "do nothing" - which is the
// *correct* answer for §D4's two-or-more-ids row, its empty-set row, and a re-clicked
// already-visible row (composer not covering), so
// `openingLeavesTheOpenNoteAloneForTwoOrMoreSelectedIds_R10`,
// `openingDoesNothingOnAnEmptySet_D4Row4` and
// `openingDoesNothingForAnAlreadyVisibleRowReclickedWithNoComposerToLeave` pass by
// accident, while the two "opens a different note" tests and the two composer tests are
// red on their `#expect`, never on a build error.

// §D4 Row 1: exactly one id, different from what is open - that note opens.

@Test func openingOpensADifferentNote_D4Row1() {
    let result = NoteListPane.opening(
        from: [], to: ["01 Progetti/Brief.md"], currentlyOpen: nil, isComposingNote: false
    )

    #expect(result == .open("01 Progetti/Brief.md"))
}

@Test func openingOpensADifferentNoteWhileAnotherIsAlreadyOpen_D4Row1() {
    let result = NoteListPane.opening(
        from: ["Appunti.md"], to: ["01 Progetti/Brief.md"],
        currentlyOpen: "Appunti.md", isComposingNote: false
    )

    #expect(result == .open("01 Progetti/Brief.md"))
}

// §D4 Row 2, the two behaviours the plan's Test step calls out as not cosmetic
// (`NoteListPane.swift:215-220`): the same single id as what is open means
// `.leaveComposer` while the composer covers it, and nothing at all while it does not.

// Behaviour (b): re-selecting the note underneath calls `leaveComposer()` rather than
// re-reading the note and discarding unsaved text. Asserted as a *distinct* signal, not
// as `.open(path)` for the same path - the whole reason this rule returns a
// `SelectionOutcome` instead of a bare `String?`: collapsing both branches into "the
// path that should now read as open" would erase exactly this distinction and silently
// turn a `leaveComposer()` back into a discarding re-read.
@Test func openingCallsLeaveComposerWhenTheCoveredNoteIsReselected() {
    let result = NoteListPane.opening(
        from: [], to: ["01 Progetti/Brief.md"],
        currentlyOpen: "01 Progetti/Brief.md", isComposingNote: true
    )

    #expect(result == .leaveComposer)
    // Never this - the bug the composer comment exists to prevent.
    #expect(result != .open("01 Progetti/Brief.md"))
}

// Behaviour (a): nothing is selected while the composer is up. That masking is
// `selectedPath`'s *get* side (`:216-220`), not this rule's - but it is what makes
// `from` read `[]` (rather than already containing this id) at the call site above, so
// the click reaches this rule as a *change* at all instead of being swallowed by
// `List` as a no-op before the setter ever runs. `old` is deliberately unread by this
// rule (mirroring `WorkspaceBrowser.opening` verbatim), so the masking's effect is
// visible only through that precondition, never through an argument this rule reads -
// asserted here by holding `to`/`currentlyOpen`/`isComposingNote` fixed at the values
// above and varying only `old`/`from`, which the previous test already set to the
// masked `[]`. A second `from` value - what an *unmasked* read would have produced,
// already containing this id - must answer identically, because this rule does not
// look at `from` at all.
@Test func openingIgnoresTheOldSetEntirely_R04() {
    let masked = NoteListPane.opening(
        from: [], to: ["01 Progetti/Brief.md"],
        currentlyOpen: "01 Progetti/Brief.md", isComposingNote: true
    )
    let unmasked = NoteListPane.opening(
        from: ["01 Progetti/Brief.md"], to: ["01 Progetti/Brief.md"],
        currentlyOpen: "01 Progetti/Brief.md", isComposingNote: true
    )

    #expect(masked == unmasked)
    #expect(masked == .leaveComposer)
}

@Test func openingDoesNothingForAnAlreadyVisibleRowReclickedWithNoComposerToLeave() {
    // Unreachable through the real binding while the composer is not up - `get` would
    // already read this id as selected, so `List` would report no change and the
    // setter would never run - answered anyway, defensively, for a function that has
    // to answer every input it can be given.
    let result = NoteListPane.opening(
        from: ["01 Progetti/Brief.md"], to: ["01 Progetti/Brief.md"],
        currentlyOpen: "01 Progetti/Brief.md", isComposingNote: false
    )

    #expect(result == nil)
}

// §D4 Row 3: two or more ids - nothing. The open note stays open (R-10), tested here as
// the general rule.

@Test func openingLeavesTheOpenNoteAloneForTwoOrMoreSelectedIds_R10() {
    let result = NoteListPane.opening(
        from: ["01 Progetti"], to: ["01 Progetti/Brief.md", "Appunti.md"],
        currentlyOpen: "Appunti.md", isComposingNote: false
    )

    #expect(result == nil)
}

@Test func openingLeavesTheOpenNoteOpenWhenTwoRowsAreSelectedWhileComposerIsUp_R10() {
    // The composer stays exactly where it is too - two rows lit answers only "what
    // would a drag carry" and never touches what is open (§D4).
    let result = NoteListPane.opening(
        from: [], to: ["01 Progetti/Brief.md", "Appunti.md"],
        currentlyOpen: "Appunti.md", isComposingNote: true
    )

    #expect(result == nil)
}

// §D4 Row 4: empty - nothing. `selectedPath`'s current setter already does nothing on
// deselect (`guard let path else { return }`, `:225`); this rule preserves that rather
// than introducing a "close the note" action that never existed.

@Test func openingDoesNothingOnAnEmptySet_D4Row4() {
    let result = NoteListPane.opening(
        from: ["Appunti.md"], to: [], currentlyOpen: "Appunti.md", isComposingNote: false
    )

    #expect(result == nil)
}
