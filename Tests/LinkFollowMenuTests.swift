import Foundation
import Testing
@testable import Pergamenum

// ADR-0083 §D3: the three link-at-caret items in Vista. A `Commands` body cannot be rendered in the
// unit suite without a menu bar, so the wiring is read off `MenuCommands.swift` as text, the shape
// `BurnDownResidueTests` uses for File, Modifica and Vista; what the items show is read off the
// store the buttons ask.

/// The source text of `struct ViewCommands` up to the next top-level `struct`, so a command found
/// there is in Vista and not merely in the same file.
private func viewMenuSource() throws -> Substring {
    let url = try resolvedRepoRoot().appendingPathComponent("Sources/App/MenuCommands.swift")
    let source = try String(contentsOf: url, encoding: .utf8)
    let start = try #require(source.range(of: "struct ViewCommands: Commands"), "no ViewCommands in MenuCommands.swift")
    let rest = source[start.upperBound...]
    let end = rest.range(of: "\nstruct ")?.lowerBound ?? rest.endIndex
    return rest[..<end]
}

@Test func vistaListsTheThreeLinkCommandsInCatalogueOrder() throws {
    let menu = try viewMenuSource()
    #expect(menu.contains("[ShortcutCommand.followLink, .followLinkInNewTab, .followLinkInOtherColumn]"))
}

@Test func eachLinkItemRunsShowsItsKeyAndIsDisabledWhenItCannotRun() throws {
    let menu = try viewMenuSource()
    let items = try #require(menu.range(of: "ShortcutCommand.followLink,"), "the link items left Vista")
    let body = menu[items.lowerBound...].prefix(400)
    #expect(body.contains("Button(command.title) { actions.run(command) }"))
    #expect(body.contains(".keyboardShortcut(shortcuts.shortcut(for: command))"))
    #expect(body.contains(".disabled(!actions.canRun(command))"))
}

@Test func theLinkItemsSitBetweenHistoryNavigationAndThePanes() throws {
    let menu = try viewMenuSource()
    let forward = try #require(menu.range(of: "actions.run(.goForward)"))
    let links = try #require(menu.range(of: "ShortcutCommand.followLink,"))
    let panes = try #require(menu.range(of: "Navigation.Pane.allCases"))
    #expect(forward.upperBound <= links.lowerBound)
    #expect(links.upperBound <= panes.lowerBound)
}

/// What the menu shows beside each item on a fresh install: Cmd+Opt+Return on «Segui il link»,
/// nothing on the two variants until the person binds one.
@MainActor
@Test func onAFreshInstallOnlyFollowLinkShowsAKey() throws {
    let name = "LinkFollowMenuTests-\(UUID().uuidString)"
    let defaults = ScratchDefaults.make()
    defer { defaults.removePersistentDomain(forName: name) }
    let store = ShortcutStore(defaults: defaults, isOverridden: false)

    #expect(store.shortcut(for: .followLink) != nil)
    #expect(store.shortcut(for: .followLinkInNewTab) == nil)
    #expect(store.shortcut(for: .followLinkInOtherColumn) == nil)
}
