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
