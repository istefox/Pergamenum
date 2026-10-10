import Foundation
import Testing
@testable import Pergamenum

/// R-21 (ADR-0083 §D1): `VaultController.openNote(at:how:)` and `openNoteInOtherColumn(at:)`, the
/// two doors a followed link reaches once its target is a path. `.replace` and `.newTab` keep
/// today's behaviour; `.otherColumn` is a new one and is not `splitEditor`.
@MainActor
@Suite struct LinkOpeningControllerTests {
    private static func controller(_ vault: borrowing TemporaryVault) async throws -> VaultController {
        try vault.write(LinkFixtures.note("Alfa."), to: "Alfa.md")
        try vault.write(LinkFixtures.note("Beta."), to: "Beta.md")
        try vault.write(LinkFixtures.note("Gamma."), to: "Gamma.md")
        let controller = VaultController(recents: .volatile(), openTabs: .volatile())
        await controller.open(vault.root)
        return controller
    }

    private static func paths(_ column: EditorColumn) -> [String] {
        column.tabs.map(\.note.relativePath)
    }

    /// Alfa on the left, Gamma on the right, the focus on the left.
    private static func twoColumns(_ controller: VaultController) {
        controller.openNote(at: "Alfa.md")
        controller.splitEditor()
        controller.openNote(at: "Gamma.md")
        controller.focusColumn(0)
    }

    // MARK: Today's behaviour

    @Test func replaceShowsTheTargetInTheTabThatWasThere() async throws {
        let vault = try TemporaryVault()
        let controller = try await Self.controller(vault)
        controller.openNote(at: "Alfa.md")

        controller.openNote(at: "Beta.md", how: .replace)

        #expect(controller.columns.count == 1)
        #expect(Self.paths(controller.columns[0]) == ["Beta.md"])
        #expect(controller.openNote?.relativePath == "Beta.md")
        controller.close()
    }

    @Test func newTabOpensTheTargetBesideTheCurrentOne() async throws {
        let vault = try TemporaryVault()
        let controller = try await Self.controller(vault)
        controller.openNote(at: "Alfa.md")

        controller.openNote(at: "Beta.md", how: .newTab)

        #expect(controller.columns.count == 1)
        #expect(Self.paths(controller.columns[0]) == ["Alfa.md", "Beta.md"])
        #expect(controller.openNote?.relativePath == "Beta.md")
        #expect(controller.focusedTab?.isPreview == false)
        controller.close()
    }

    @Test func otherColumnThroughTheHowIsTheSameDoorAsTheNamedOne() async throws {
        let vault = try TemporaryVault()
        let controller = try await Self.controller(vault)
        controller.openNote(at: "Alfa.md")

        controller.openNote(at: "Beta.md", how: .otherColumn)

        #expect(controller.columns.count == 2)
        #expect(controller.focusedColumnIndex == 1)
        #expect(controller.openNote?.relativePath == "Beta.md")
        controller.close()
    }

    // MARK: One column

    @Test func otherColumnWithOneColumnAddsTheSecondWithOnlyTheTarget() async throws {
        let vault = try TemporaryVault()
        let controller = try await Self.controller(vault)
        controller.openNote(at: "Alfa.md")

        controller.openNoteInOtherColumn(at: "Beta.md")

        try #require(controller.columns.count == 2)
        #expect(controller.focusedColumnIndex == 1)
        // Not `splitEditor`, which would have put the source note on the right too.
        #expect(Self.paths(controller.columns[1]) == ["Beta.md"])
        #expect(controller.columns[1].active?.note.relativePath == "Beta.md")
        controller.close()
    }

    @Test func otherColumnLeavesTheSourceColumnUntouched() async throws {
        let vault = try TemporaryVault()
        let controller = try await Self.controller(vault)
        controller.openNote(at: "Alfa.md")
        let before = controller.columns[0]

        controller.openNoteInOtherColumn(at: "Beta.md")

        #expect(controller.columns.count == 2)
        #expect(controller.columns[0] == before)
        #expect(controller.columns[0].active?.note.relativePath == "Alfa.md")
        controller.close()
    }

    // MARK: Two columns

    @Test func otherColumnWithTwoColumnsFocusesTheOtherAndShowsTheTargetInFront() async throws {
        let vault = try TemporaryVault()
        let controller = try await Self.controller(vault)
        Self.twoColumns(controller)
        #expect(controller.focusedColumnIndex == 0)
        let left = controller.columns[0]

        controller.openNoteInOtherColumn(at: "Beta.md")

        #expect(controller.columns.count == 2)
        #expect(controller.focusedColumnIndex == 1)
        #expect(controller.columns[1].active?.note.relativePath == "Beta.md")
        #expect(Self.paths(controller.columns[1]).contains("Gamma.md"))
        #expect(controller.columns[0] == left)
        controller.close()
    }

    @Test func otherColumnFromTheRightColumnGoesToTheLeft() async throws {
        let vault = try TemporaryVault()
        let controller = try await Self.controller(vault)
        Self.twoColumns(controller)
        controller.focusColumn(1)

        controller.openNoteInOtherColumn(at: "Beta.md")

        #expect(controller.focusedColumnIndex == 0)
        #expect(controller.columns[0].active?.note.relativePath == "Beta.md")
        controller.close()
    }

    @Test func aTabAlreadyInTheOtherColumnIsFocusedAndNotOpenedAgain() async throws {
        let vault = try TemporaryVault()
        let controller = try await Self.controller(vault)
        Self.twoColumns(controller)
        let rightBefore = Self.paths(controller.columns[1])

        controller.openNoteInOtherColumn(at: "Gamma.md")

        #expect(controller.focusedColumnIndex == 1)
        #expect(Self.paths(controller.columns[1]) == rightBefore)
        #expect(controller.columns[1].active?.note.relativePath == "Gamma.md")
        controller.close()
    }

    // MARK: Where ADR-0015 reads

    @Test func theHistoryDestinationReadsTheColumnTheLinkLandedIn() async throws {
        let vault = try TemporaryVault()
        let controller = try await Self.controller(vault)
        Self.twoColumns(controller)
        let navigation = Navigation()
        let day = DayController(store: EventKitStore(), vault: controller)
        let place = WindowPlace(navigation: navigation, vault: controller, day: day)
        navigation.pane = .notes

        controller.openNoteInOtherColumn(at: "Beta.md")

        #expect(controller.focusedColumnIndex == 1)
        #expect(place.destination == .note("Beta.md"))
        controller.close()
    }

    // MARK: The caret's link

    @Test func theRecordedLinkIsResetWhenTheTabShowsAnotherNote() async throws {
        let vault = try TemporaryVault()
        let controller = try await Self.controller(vault)
        controller.openNote(at: "Alfa.md")
        controller.recordLinkAtCaret(LinkFixtures.url(for: "Beta"), inColumn: 0)
        #expect(controller.linkAtCaret == LinkFixtures.url(for: "Beta"))

        controller.openNote(at: "Gamma.md", how: .replace)

        #expect(controller.linkAtCaret == nil)
        controller.close()
    }

    @Test func recordingALinkWritesTheActiveTabOfThatColumnOnly() async throws {
        let vault = try TemporaryVault()
        let controller = try await Self.controller(vault)
        Self.twoColumns(controller)
        let url = LinkFixtures.url(for: "Beta")

        controller.recordLinkAtCaret(url, inColumn: 1)

        #expect(controller.columns[1].active?.linkAtCaret == url)
        #expect(controller.columns[0].active?.linkAtCaret == nil)
        // The focused column is the left one, so the facade does not see the right one's link.
        #expect(controller.linkAtCaret == nil)
        controller.close()
    }

    @Test func recordingNilClearsTheLink() async throws {
        let vault = try TemporaryVault()
        let controller = try await Self.controller(vault)
        controller.openNote(at: "Alfa.md")
        controller.recordLinkAtCaret(LinkFixtures.url(for: "Beta"), inColumn: 0)

        controller.recordLinkAtCaret(nil, inColumn: 0)

        #expect(controller.linkAtCaret == nil)
        controller.close()
    }
}
