import Foundation
import Testing
@testable import Pergamenum

// ADR-0026: A row is dragged into a folder, and several rows are chosen first.
// Plan: docs/superpowers/plans/2026-08-27-drag-and-drop-board-files-into-workspace.md,
// Task 4.
//
// `VaultItemDrag` is the payload one dragged row carries (ADR-0026 §D3): the whole
// effective drag set under a structured, exported-UTType `CodableRepresentation`, and —
// on the same pasteboard item — the plain name `CompletingTextView.performDragOperation`
// has always read as a bare `String` via `ProxyRepresentation(exporting: \.dragName)`
// (SPEC §7.2 "collegamento assistito", `CompletingTextView+Pasteboard.swift:106-111`).
// The whole point of the two representations is that adding the first one costs the
// second one nothing — this file's job is to prove the JSON side round-trips faithfully
// and that the note contract (`dragName == NoteRecord.title`, not the relative path, not
// a wrapped string) is exactly what a future call site is expected to build.
//
// The runtime check that `UTType.pergamenumVaultItem.identifier` reads back the declared
// string rather than a synthesized `dyn.` one depends on the `Project.swift` infoPlist
// entry, which is Task 4's code step, not this file's — not covered here.

private func note(_ path: String, title: String? = nil) -> NoteRecord {
    let name = title ?? (path as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "")
    return NoteRecord(
        relativePath: path, title: name,
        frontmatter: .empty, linkTargets: [], tasks: [],
        modifiedAt: .distantPast, byteSize: 0, contentHash: "-"
    )
}

// MARK: - JSON round-trip preserves paths, kinds and order

@Test func jsonRoundTripPreservesEachItemsPathAndKind() throws {
    let items = [
        VaultItemRef(path: "A/x.canvas", kind: .board),
        VaultItemRef(path: "B/Nota.md", kind: .note),
    ]
    let drag = VaultItemDrag(items: items, dragName: "x")

    let data = try JSONEncoder().encode(drag)
    let decoded = try JSONDecoder().decode(VaultItemDrag.self, from: data)

    #expect(decoded == drag)
    #expect(decoded.items[0].path == "A/x.canvas")
    #expect(decoded.items[0].kind == .board)
    #expect(decoded.items[1].path == "B/Nota.md")
    #expect(decoded.items[1].kind == .note)
}

@Test func jsonRoundTripPreservesItemOrderNotJustMembership() throws {
    let items = [
        VaultItemRef(path: "c", kind: .folder),
        VaultItemRef(path: "a", kind: .folder),
        VaultItemRef(path: "b", kind: .folder),
    ]
    let drag = VaultItemDrag(items: items, dragName: "c")

    let data = try JSONEncoder().encode(drag)
    let decoded = try JSONDecoder().decode(VaultItemDrag.self, from: data)

    #expect(decoded.items.map(\.path) == ["c", "a", "b"])
}

@Test func jsonRoundTripPreservesDragName() throws {
    let drag = VaultItemDrag(items: [VaultItemRef(path: "A/x.canvas", kind: .board)], dragName: "x")

    let data = try JSONEncoder().encode(drag)
    let decoded = try JSONDecoder().decode(VaultItemDrag.self, from: data)

    #expect(decoded.dragName == "x")
}

// MARK: - A set of three items round-trips as three (the multi-selection drag, ADR-0026 §D4)

@Test func jsonRoundTripOfThreeItemsYieldsThreeItemsBack() throws {
    let items = [
        VaultItemRef(path: "A/x.canvas", kind: .board),
        VaultItemRef(path: "B/Nota.md", kind: .note),
        VaultItemRef(path: "C", kind: .folder),
    ]
    let drag = VaultItemDrag(items: items, dragName: "x")

    let data = try JSONEncoder().encode(drag)
    let decoded = try JSONDecoder().decode(VaultItemDrag.self, from: data)

    #expect(decoded.items.count == 3)
    #expect(Set(decoded.items) == Set(items))
}

// MARK: - dragName for a note is NoteRecord.title, the SPEC §7.2 payload

@Test func dragNameForANoteBuiltFromANoteRecordEqualsTheRecordsTitle() {
    // A title with a space and an accented letter: if the payload were ever built from
    // something other than the bare title — the relative path, a slugified form, a
    // JSON-wrapped string — this would no longer read back byte-identical, and
    // `CompletingTextView.performDragOperation`'s `noteTitles.contains(title)` check
    // (`CompletingTextView+Pasteboard.swift:108`) would stop matching.
    let record = note("01 Progetti/Trasmissibilità reale.md", title: "Trasmissibilità reale")
    let ref = VaultItemRef(path: record.relativePath, kind: .note)

    let drag = VaultItemDrag(items: [ref], dragName: record.title)

    #expect(drag.dragName == record.title)
    #expect(drag.dragName != record.relativePath)
}

// MARK: - VaultItemRef is Hashable: it keys the drop handlers' state (ADR-0026 §D4/§D5)

@Test func vaultItemRefIsHashableAndCanKeyASet() {
    let a = VaultItemRef(path: "A/x.canvas", kind: .board)
    let b = VaultItemRef(path: "B/y.canvas", kind: .board)
    let aAgain = VaultItemRef(path: "A/x.canvas", kind: .board)

    var dragging: Set<VaultItemRef> = [a, b]

    #expect(dragging.contains(aAgain))
    #expect(dragging.count == 2)

    dragging.remove(aAgain)
    #expect(dragging == [b])
}

@Test func vaultItemRefIsHashableAndCanKeyADictionary() {
    let board = VaultItemRef(path: "A/x.canvas", kind: .board)
    let folder = VaultItemRef(path: "A", kind: .folder)

    let highlighted: [VaultItemRef: Bool] = [board: true, folder: false]

    #expect(highlighted[VaultItemRef(path: "A/x.canvas", kind: .board)] == true)
    #expect(highlighted[VaultItemRef(path: "A", kind: .folder)] == false)
}
