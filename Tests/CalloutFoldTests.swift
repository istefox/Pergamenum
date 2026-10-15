import AppKit
import Foundation
import Testing
@testable import Pergamenum

// ADR-0087 §D9, plan docs/plans/note-workflow-n5.md, Task 3 (R-38).
//
// Which callout bodies are hidden. `-` starts folded and `+` starts open, a tap flips either, no sign
// never folds; the hidden lines go into the same hidden-line set folded headings use (ADR-0078). The
// tab keeps the flips as the title offsets it toggled, model state like `foldedEntries`, never written
// to the file.

@Suite struct CalloutFoldRule {
    @Test func aFixedCalloutNeverFoldsWhateverIsToggled() { // R-38
        #expect(!CalloutFold.isFolded(.fixed, toggled: false))
        #expect(!CalloutFold.isFolded(.fixed, toggled: true))
    }

    @Test func aMinusStartsFoldedAndAToggleOpensIt() { // R-38
        #expect(CalloutFold.isFolded(.folded, toggled: false))
        #expect(!CalloutFold.isFolded(.folded, toggled: true))
    }

    @Test func aPlusStartsOpenAndAToggleFoldsIt() { // R-38
        #expect(!CalloutFold.isFolded(.open, toggled: false))
        #expect(CalloutFold.isFolded(.open, toggled: true))
    }
}

@Suite struct CalloutHiddenLines {
    /// `> [!avviso]- T` is 14 characters and its line ends at 15, so the body lines start at 15 and 19.
    private static let folded = "> [!avviso]- T\n> a\n> b"

    @Test func aFoldedCalloutHidesItsBodyLines() { // R-38
        #expect(CalloutFold.hiddenLines(in: Self.folded, toggled: []) == [15, 19])
    }

    @Test func togglingItsTitleOffsetShowsTheBodyAgain() { // R-38
        #expect(CalloutFold.hiddenLines(in: Self.folded, toggled: [0]).isEmpty)
    }

    @Test func aPlusCalloutHidesItsBodyOnlyOnceToggled() { // R-38
        let text = "> [!tip]+ T\n> a\n> b"
        #expect(CalloutFold.hiddenLines(in: text, toggled: []).isEmpty)
        #expect(CalloutFold.hiddenLines(in: text, toggled: [0]) == [12, 16])
    }

    @Test func aCalloutWithNoSignNeverHidesAnything() { // R-38
        let text = "> [!tip] T\n> a\n> b"
        #expect(CalloutFold.hiddenLines(in: text, toggled: []).isEmpty)
        #expect(CalloutFold.hiddenLines(in: text, toggled: [0]).isEmpty)
    }

    /// The offset is the title line's, wherever it is: a toggle is read fresh against the text, so a
    /// second callout is flipped by its own offset and not by the first one's.
    @Test func eachCalloutIsToggledByItsOwnTitleOffset() { // R-38
        let text = "> [!note]- A\n> a\n\n> [!tip]- B\n> b"
        let second = (text as NSString).range(of: "> [!tip]").location
        #expect(CalloutFold.hiddenLines(in: text, toggled: []).count == 2)
        let onlyFirstOpen = CalloutFold.hiddenLines(in: text, toggled: [0])
        #expect(onlyFirstOpen.count == 1)
        #expect(onlyFirstOpen.allSatisfy { $0 > second })
    }

    /// An entry that no longer matches a header is ignored (`NoteTab.toggledCallouts`' contract).
    @Test func aToggledOffsetThatIsNoHeaderIsIgnored() { // R-38
        #expect(CalloutFold.hiddenLines(in: Self.folded, toggled: [3, 999]) == [15, 19])
    }

    @Test func anUnknownTypeFoldsLikeAnyOther() { // R-38
        #expect(CalloutFold.hiddenLines(in: "> [!faq]- Q\n> r", toggled: []) == [12])
    }
}

@MainActor
@Suite struct CalloutToggleState {
    @Test func theTabStartsWithNoToggledCallouts() { // R-38
        let note = VaultController.OpenNote(relativePath: "a.md", title: "a", text: "x\n", savedText: "x\n")
        #expect(NoteTab(note: note).toggledCallouts.isEmpty)
    }

    @Test func toggleCalloutInsertsAndRemovesTheOffsetInTheFocusedTabWithoutDirtyingIt() async throws { // R-38
        let vault = try TemporaryVault()
        let controller = try await quitController(vault)
        controller.openNote(at: "Nexion.md")
        let id = try #require(controller.focusedTab?.id)
        #expect(controller.focusedTab?.toggledCallouts.isEmpty == true)

        controller.toggleCallout(12)
        #expect(controller.tab(withID: id)?.toggledCallouts == [12])
        controller.toggleCallout(40)
        #expect(controller.tab(withID: id)?.toggledCallouts == [12, 40])
        controller.toggleCallout(12)
        #expect(controller.tab(withID: id)?.toggledCallouts == [40])

        // A view of the note, not part of it: the file is not dirtied.
        #expect(controller.tab(withID: id)?.note.hasUnsavedChanges == false)
        controller.close()
    }
}

// The tab's flips are title offsets, so they move with the text like every offset-keyed holder (ADR-0091 §D6):
// typing above an opened `-` callout leaves it open, and above a folded `+` one leaves it folded.
@MainActor
@Suite(.serialized) struct CalloutFlipsFollowEdits {
    private static let minus = "intro\n\n> [!faq]- Domanda\n> risposta nascosta\n"
    private static let plus = "intro\n\n> [!faq]+ Domanda\n> risposta aperta\n"

    private static func fixture(_ note: String) async throws -> UpdatePathFixture {
        try await UpdatePathFixture(.init(bytes: 1024, variant: .prose), note: note)
    }

    private static func title(in note: String) -> Int { (note as NSString).range(of: "> [!faq]").location }

    @Test func typingAboveAnOpenedMinusCalloutLeavesItOpen() async throws { // R-38
        let fixture = try await Self.fixture(Self.minus)
        defer { fixture.tearDown() }
        let title = Self.title(in: Self.minus)
        try #require(fixture.coordinator.decorations.foldsCallouts, "the column wires no callout toggle")
        #expect(!fixture.coordinator.folding.lastFoldLayout.hiddenLineOffsets.isEmpty, "the `-` callout starts folded")

        fixture.vault.toggleCallout(title)
        fixture.host.hosting.layoutSubtreeIfNeeded()
        await fixture.host.settle()
        #expect(fixture.coordinator.folding.lastFoldLayout.hiddenLineOffsets.isEmpty, "the toggle did not open it")

        fixture.type("zz", at: 0)
        fixture.type("\n", at: 0)
        #expect(fixture.vault.focusedTab?.toggledCallouts == [title + 3], "the flip stayed on the old offset")
        #expect(fixture.coordinator.folding.lastFoldLayout.hiddenLineOffsets.isEmpty, "typing above re-folded it")
        let hidden = CalloutFold.hiddenLines(
            in: fixture.textView.string, toggled: fixture.vault.focusedTab?.toggledCallouts ?? []
        )
        #expect(hidden.isEmpty, "the note's own reading of the flips folds it")
        #expect(fixture.missedUpdates == 0)
    }

    @Test func typingAboveAFoldedPlusCalloutLeavesItFolded() async throws { // R-38
        let fixture = try await Self.fixture(Self.plus)
        defer { fixture.tearDown() }
        let title = Self.title(in: Self.plus)
        try #require(fixture.coordinator.decorations.foldsCallouts, "the column wires no callout toggle")
        #expect(fixture.coordinator.folding.lastFoldLayout.hiddenLineOffsets.isEmpty, "the `+` callout starts open")

        fixture.vault.toggleCallout(title)
        fixture.host.hosting.layoutSubtreeIfNeeded()
        await fixture.host.settle()
        #expect(!fixture.coordinator.folding.lastFoldLayout.hiddenLineOffsets.isEmpty, "the toggle did not fold it")

        fixture.type("zz", at: 0)
        #expect(fixture.vault.focusedTab?.toggledCallouts == [title + 2])
        #expect(!fixture.coordinator.folding.lastFoldLayout.hiddenLineOffsets.isEmpty, "typing above re-opened it")
        #expect(fixture.missedUpdates == 0)
    }

    @Test func typingBelowAFlippedCalloutLeavesItsFlipWhereItWas() async throws { // R-38
        let fixture = try await Self.fixture(Self.minus)
        defer { fixture.tearDown() }
        let title = Self.title(in: Self.minus)
        fixture.vault.toggleCallout(title)
        fixture.host.hosting.layoutSubtreeIfNeeded()
        await fixture.host.settle()

        fixture.type("zz", at: (Self.minus as NSString).length)
        #expect(fixture.vault.focusedTab?.toggledCallouts == [title], "an edit below moved the flip")
    }
}

// N5 Realignment 4 (ADR-0091 §D6): the folded-callouts memo and the flips are offset-keyed holders, so an
// incremental editor and its full-restyle twin hold the same ones after every edit, above, inside, on
// and below a flipped callout. The flips are the tab's, one copy both editors read: the incremental
// editor reports where its edits moved them, as the app's tab hears it, and the full-restyle twin, which
// shifts nothing by itself but the flips (the kill switch, `recordStorageEdit`), reads the same copy and
// re-reads its callouts whole from the text: the oracle for the incremental editor's spliced memo.
@MainActor
@Suite(.serialized) struct CalloutStateTwin {
    private static let note = "intro\n\n> [!faq]- Domanda\n> risposta\n\n> [!tip]+ Aperta\n> corpo\n\nfine\n"

    private static func wire(_ twin: RestyleTwin, flipping title: Int) {
        let editors = [twin.incremental, twin.full]
        for editor in editors {
            editor.coordinator.parent.outline.onToggleCallout = { _ in }
            editor.coordinator.parent.outline.toggledCallouts = [title]
        }
        twin.incremental.coordinator.parent.outline.onCalloutsMoved = { flips in
            for editor in editors { editor.coordinator.parent.outline.toggledCallouts = flips }
        }
        twin.both { $0.runPasses() }
    }

    @Test func editsAroundAFlippedCalloutLeaveTheTwinsEqual() { // R-38
        let twin = RestyleTwin.plain(Self.note)
        let tip = (Self.note as NSString).range(of: "> [!tip]").location
        Self.wire(twin, flipping: tip)
        let start = twin.incremental.coordinator.derivedStateSnapshot()
        #expect(start.decorations.toggledCallouts == [tip])
        #expect(start.calloutFolds?.count == 2, "both callouts fold: the comparison compares nothing otherwise")
        #expect(twin.differences().isEmpty, "\(twin.differences())")

        func text() -> NSString { twin.incremental.textView.string as NSString }
        let edits: [(String, () -> Int)] = [
            ("zz", { 0 }),
            ("q", { text().range(of: "Domanda").location + 7 }),
            ("w", { text().range(of: "Aperta").location + 6 }),
            ("\n> altro", { text().range(of: "corpo").location + 5 }),
            ("y", { text().length }),
        ]
        for (typed, location) in edits {
            twin.type(typed, at: location())
            #expect(twin.differences().isEmpty, "after typing \(typed.debugDescription): \(twin.differences())")
        }
        let moved = twin.incremental.coordinator.derivedStateSnapshot().decorations.toggledCallouts
        #expect(moved == [text().range(of: "> [!tip]").location], "the flip did not follow its title")
        #expect(twin.incremental.coordinator.restyleLog.incremental > 0, "no edit took the incremental path")
    }

    @Test func theKillSwitchStillMovesAFlipAndReportsIt() { // R-38
        // A full restyle rebuilds the styling, never the tab's flips: with the kill switch on, typing above
        // a flipped callout must still move the flip and tell the tab, or the tab keeps a stale offset.
        let full = RestyleTwin.plain(Self.note).full
        #expect(full.coordinator.forcesFullRestyle)
        let tip = (Self.note as NSString).range(of: "> [!tip]").location
        var reported: [Set<Int>] = []
        full.coordinator.parent.outline.onToggleCallout = { _ in }
        full.coordinator.parent.outline.toggledCallouts = [tip]
        full.coordinator.parent.outline.onCalloutsMoved = { flips in
            reported.append(flips)
            full.coordinator.parent.outline.toggledCallouts = flips
        }
        full.runPasses()

        // In an undo group, as `RestyleTwin.edit` does: the fixture's manager does not group by event.
        full.undoManager?.beginUndoGrouping()
        full.type("zz", at: 0)
        full.undoManager?.endUndoGrouping()
        full.runPasses()
        #expect(reported == [[tip + 2]])
        #expect(full.coordinator.derivedStateSnapshot().decorations.toggledCallouts == [tip + 2])
    }
}
