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
