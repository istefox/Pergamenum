import Foundation
import Testing
@testable import Pergamenum

// `WindowPlace` (`Sources/App/WindowPlace.swift`, ADR-0015 §D1/§D2) reads three
// controllers into one place-and-move-back value and had no test of its own before this
// (plan Task 5 PR 6, R-12): `NavigationHistoryTests` owns the drift/step rule itself, but
// nothing pinned `destination`, `isDrift` or `apply`, the three members that connect that
// rule to the real window.

@MainActor
private func makePlace(
    _ vault: borrowing TemporaryVault
) async throws -> (place: WindowPlace, day: DayController, vault: VaultController, navigation: Navigation) {
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    let day = DayController(store: StubCalendarStore(), vault: controller)
    day.show(CalendarDate(iso: "2026-08-11")!)
    let navigation = Navigation()
    return (WindowPlace(navigation: navigation, vault: controller, day: day), day, controller, navigation)
}

// MARK: `destination`

@MainActor
@Test func destinationOnTheOggiPaneIsTheDayAndItsScale() async throws {
    let vault = try TemporaryVault()
    let (place, day, vaultController, navigation) = try await makePlace(vault)

    navigation.pane = .today
    #expect(place.destination == .day(day.day, day.scale))

    day.scale = .week
    #expect(place.destination == .day(day.day, .week))
    vaultController.close()
}

@MainActor
@Test func destinationOnTheNotePaneIsTheOpenNoteOrJustThePane() async throws {
    let vault = try TemporaryVault()
    try vault.write("---\ndate: 2026-08-11\ntags:\n  - type-note\n---\n", to: "Note/lavoro.md")
    let (place, _, vaultController, navigation) = try await makePlace(vault)

    navigation.pane = .notes
    #expect(place.destination == .pane(.notes), "senza nota aperta la destinazione è la pane, non `.note`")

    vaultController.openNote(at: "Note/lavoro.md")
    #expect(place.destination == .note("Note/lavoro.md"))
    vaultController.close()
}

@MainActor
@Test func destinationFallsBackToThePaneForEverythingElse() async throws {
    let vault = try TemporaryVault()
    let (place, _, vaultController, navigation) = try await makePlace(vault)

    for pane: Navigation.Pane in [.tags, .starred, .views, .recordings, .pratiche] {
        navigation.pane = pane
        #expect(place.destination == .pane(pane))
    }
    vaultController.close()
}

// MARK: `isDrift` (§D3)

@MainActor
@Test func isDriftOnlyWhenBothAreTheSameScaleAndTheControllerAgrees() async throws {
    let vault = try TemporaryVault()
    let (place, day, vaultController, _) = try await makePlace(vault)

    let before = Destination.day(day.day, day.scale)
    day.moveSpan(by: 1)
    let afterADrift = Destination.day(day.day, day.scale)
    #expect(place.isDrift(from: before, to: afterADrift))

    // A jump clears the flag `moveSpan` set, so the very next `.day`-to-`.day` move is a
    // step even though nothing about the two destinations looks different from a drift.
    day.show(CalendarDate(iso: "2026-09-01")!)
    let afterAJump = Destination.day(day.day, day.scale)
    #expect(!place.isDrift(from: afterADrift, to: afterAJump))

    // Different scale is never drift, whatever the controller last recorded: changing
    // scale is going somewhere (ADR-0013 §D4), not scrolling past it.
    day.scale = .week
    day.moveSpan(by: 1)
    let widerScale = Destination.day(day.day, day.scale)
    #expect(!place.isDrift(from: afterAJump, to: widerScale))

    // Neither side a `.day` case at all is never drift.
    #expect(!place.isDrift(from: .pane(.tags), to: afterAJump))
    vaultController.close()
}

// MARK: `apply` (the mirror of `RootView.choose(_:)`)

@MainActor
@Test func applyAPaneJustSwitchesToIt() async throws {
    let vault = try TemporaryVault()
    let (place, _, vaultController, navigation) = try await makePlace(vault)

    place.apply(.pane(.tags))
    #expect(navigation.pane == .tags)
    vaultController.close()
}

@MainActor
@Test func applyANoteSwitchesToNotesAndOpensIt() async throws {
    let vault = try TemporaryVault()
    try vault.write("---\ndate: 2026-08-11\ntags:\n  - type-note\n---\n", to: "Note/lavoro.md")
    let (place, _, vaultController, navigation) = try await makePlace(vault)

    place.apply(.note("Note/lavoro.md"))
    #expect(navigation.pane == .notes)
    #expect(vaultController.openNote?.relativePath == "Note/lavoro.md")
    vaultController.close()
}

@MainActor
@Test func applyADayIsAJumpNotAScroll() async throws {
    let vault = try TemporaryVault()
    let (place, day, vaultController, navigation) = try await makePlace(vault)

    // Left as drift on purpose: `apply` must clear it through `show`, since arriving from
    // the history is a jump whatever gesture first recorded the entry (§D3).
    day.moveSpan(by: 1)
    place.apply(.day(CalendarDate(iso: "2026-08-20")!, .week))

    #expect(navigation.pane == .today)
    #expect(day.day == CalendarDate(iso: "2026-08-20"))
    #expect(day.scale == .week)
    #expect(!day.lastDayMoveWasDrift)
    vaultController.close()
}

@MainActor
@Test func applyAWorkspaceBoardSwitchesToWorkspaceAndQueuesIt() async throws {
    let vault = try TemporaryVault()
    let (place, _, vaultController, navigation) = try await makePlace(vault)

    place.apply(.workspaceBoard("Board/prova.canvas"))
    #expect(navigation.pane == .workspace)
    #expect(vaultController.routeState.pendingCanvas?.path == "Board/prova.canvas")
    vaultController.close()
}
