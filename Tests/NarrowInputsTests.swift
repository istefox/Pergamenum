import Foundation
import Testing
@testable import Pergamenum

// ADR-0095 §D8, plan docs/plans/no-whole-note-term-on-the-update-path-pg-406.md, Task 4 (PG-406, R-04).
//
// The tab bar's chip draws a title, a path, a preview style and a dot, and was handed the whole `NoteTab`,
// so a keystroke that changed only the note's text invalidated every chip. `NoteTab.ChipFace` is what the
// chip draws and nothing else: it is equal across keystrokes while the dot stays on, and it moves with what
// the chip shows. `NoteDocument.frontmatter(in:)` is covered by `BoundedFrontmatterTests`. Red until
// Task 5: the red-phase face is a constant with an empty title.

@MainActor
private func makeTab(text: String = "corpo", savedText: String = "corpo", preview: Bool = false) -> NoteTab {
    var tab = NoteTab(
        note: VaultController.OpenNote(relativePath: "Area/Nota.md", title: "Nota", text: text, savedText: savedText)
    )
    tab.isPreview = preview
    return tab
}

@MainActor
@Suite struct ChipFaceTests {
    @Test func theFaceCarriesWhatTheChipDraws() {
        let tab = makeTab(preview: true)
        let face = tab.chipFace
        #expect(face.id == tab.id)
        #expect(face.title == "Nota")
        #expect(face.relativePath == "Area/Nota.md")
        #expect(face.isPreview)
        #expect(!face.isUnsaved)
    }

    @Test func aSecondKeystrokeLeavesTheFaceEqualAndTheDotOn() {
        var tab = makeTab()
        tab.note.text = "corpo x"
        let afterFirst = tab.chipFace
        #expect(afterFirst.isUnsaved, "a first edit puts the dot on")

        tab.note.text = "corpo xy"
        let afterSecond = tab.chipFace
        #expect(afterSecond == afterFirst, "typing changed what the chip draws")
        #expect(afterSecond.isUnsaved)
    }

    @Test func theFaceDoesNotReadTheText() {
        var one = makeTab()
        var two = one
        one.note.text = "primo testo molto diverso"
        two.note.text = "un altro testo"
        // Two different dirty buffers of one tab draw the same chip.
        #expect(one.chipFace == two.chipFace)
        #expect(one.chipFace.isUnsaved)
    }

    @Test func aRenameChangesTheFace() {
        var tab = makeTab()
        let before = tab.chipFace
        tab.note.relativePath = "Area/Altro.md"
        tab.note.title = "Altro"
        let after = tab.chipFace
        #expect(after != before)
        #expect(after.title == "Altro")
        #expect(after.relativePath == "Area/Altro.md")
        #expect(after.id == before.id, "a rename keeps the tab")
    }

    @Test func thePreviewStyleAndTheSaveBothChangeTheFace() {
        var tab = makeTab(text: "corpo x")
        let dirty = tab.chipFace
        #expect(dirty.isUnsaved)

        tab.note.recordWrite(tab.note.text)
        #expect(tab.chipFace != dirty)
        #expect(!tab.chipFace.isUnsaved)

        tab.isPreview = true
        #expect(tab.chipFace.isPreview)
    }

    @Test func throughTheControllerTwoKeystrokesDrawTheSameChip() async throws {
        let vault = try TemporaryVault()
        try vault.write("corpo\n", to: "Nota.md")
        let controller = VaultController(recents: .volatile(), openTabs: .volatile(), typingPause: ManualPauseScheduler())
        await controller.open(vault.root)
        controller.openNote(at: "Nota.md")
        let before = try #require(controller.columns.first?.active).chipFace
        #expect(!before.isUnsaved)

        controller.updateOpenNoteText("corpo\nx")
        let first = try #require(controller.columns.first?.active).chipFace
        controller.updateOpenNoteText("corpo\nxy")
        let second = try #require(controller.columns.first?.active).chipFace
        #expect(first.isUnsaved)
        #expect(second == first)
        #expect(first != before)
    }
}
