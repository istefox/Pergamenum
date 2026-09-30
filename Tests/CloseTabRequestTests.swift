import AppKit
import Foundation
import Testing
@testable import Pergamenum

// ADR-0073 §D11, plan Task 5 (R-15): Cmd+W asks before closing a dirty tab, as ADR-0012 §D3
// always said it should, and still closes a clean one at once.

@MainActor
@Test func cmdWClosesACleanTabAtOnce() async throws {
    let vault = try TemporaryVault()
    let controller = try await quitController(vault)
    controller.openNote(at: "Nexion.md")
    let id = try #require(controller.focusedTab?.id)

    controller.requestCloseFocusedTab()

    #expect(controller.tab(withID: id) == nil)
    #expect(controller.closeRequest == nil)
    controller.close()
}

@MainActor
@Test func cmdWOnADirtyTabLeavesItOpenAndRequestsTheDialog() async throws {
    let vault = try TemporaryVault()
    let controller = try await quitController(vault)
    let id = try openDirty("Nexion.md", adding: "\nNon chiudere.\n", inColumn: 0, of: controller)

    controller.requestCloseFocusedTab()

    #expect(controller.tab(withID: id)?.note.hasUnsavedChanges == true)
    #expect(controller.closeRequest == id)
    // The column holding the tab takes the request; the other column does not.
    controller.addColumn()
    #expect(controller.takeCloseRequest(forColumn: 1) == nil)
    #expect(controller.closeRequest == id)
    #expect(controller.takeCloseRequest(forColumn: 0)?.id == id)
    #expect(controller.closeRequest == nil)
    controller.close()
}

@MainActor
@Test func cmdWWithNoTabDoesNothing() async throws {
    let vault = try TemporaryVault()
    let controller = try await quitController(vault)

    controller.requestCloseFocusedTab()

    #expect(controller.closeRequest == nil)
    #expect(controller.columns[0].tabs.isEmpty)
    controller.close()
}

@MainActor
@Test func theCloseTabCommandLeavesADirtyTabOpen() async throws {
    let vault = try TemporaryVault()
    let controller = try await quitController(vault)
    let id = try openDirty("Nexion.md", adding: "\nAncora qui.\n", inColumn: 0, of: controller)
    let calendarStore = EventKitStore()
    let actions = CommandActions(
        navigation: Navigation(),
        vault: controller,
        day: DayController(store: calendarStore, vault: controller),
        calendar: calendarStore,
        capturePanel: CapturePanel(
            controller: CaptureController(),
            session: { controller.session },
            theme: { ThemeEngine().current },
            shortcutCaption: { nil }
        ),
        history: NavigationHistory(),
        pasteboard: .volatile()
    )

    actions.run(.closeTab)

    #expect(controller.tab(withID: id) != nil)
    #expect(controller.closeRequest == id)
    controller.close()
}

// The editor column that answers `closeRequest` lives on the Note pane only, so Cmd+W on a dirty
// tab from any other pane must bring the person there; a clean tab closes without moving them.
@MainActor
@Test func theCloseTabCommandOnADirtyTabSwitchesToTheNotePane() async throws {
    let vault = try TemporaryVault()
    let controller = try await quitController(vault)
    _ = try openDirty("Nexion.md", adding: "\nDa un altro pane.\n", inColumn: 0, of: controller)
    let navigation = Navigation()
    navigation.pane = .tasks
    let actions = closeTabActions(navigation: navigation, controller: controller)

    actions.run(.closeTab)

    #expect(navigation.pane == .notes)
    controller.close()
}

@MainActor
@Test func theCloseTabCommandOnACleanTabStaysOnThePane() async throws {
    let vault = try TemporaryVault()
    let controller = try await quitController(vault)
    controller.openNote(at: "Nexion.md")
    let id = try #require(controller.focusedTab?.id)
    let navigation = Navigation()
    navigation.pane = .tasks
    let actions = closeTabActions(navigation: navigation, controller: controller)

    actions.run(.closeTab)

    #expect(controller.tab(withID: id) == nil)
    #expect(navigation.pane == .tasks)
    controller.close()
}

@MainActor
private func closeTabActions(navigation: Navigation, controller: VaultController) -> CommandActions {
    let calendarStore = EventKitStore()
    return CommandActions(
        navigation: navigation,
        vault: controller,
        day: DayController(store: calendarStore, vault: controller),
        calendar: calendarStore,
        capturePanel: CapturePanel(
            controller: CaptureController(),
            session: { controller.session },
            theme: { ThemeEngine().current },
            shortcutCaption: { nil }
        ),
        history: NavigationHistory(),
        pasteboard: .volatile()
    )
}
