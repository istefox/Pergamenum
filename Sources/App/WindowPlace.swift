import Foundation

/// Where the window is, and how to put it back there (ADR-0015 §D1, §D2).
///
/// A value built from the three controllers the window already has, not a fourth place to
/// store what they say. `RootView` makes one per draw and throws it away; nothing here holds
/// state, which is what lets the history be a list of values with no knowledge of panes.
///
/// The observer that feeds `NavigationHistory` reads `destination`, and the two arrows call
/// `apply`. They are the same knowledge written twice - forwards and backwards - so they live
/// next to each other rather than at opposite ends of the view they serve.
@MainActor
struct WindowPlace {
    let navigation: Navigation
    let vault: VaultController
    let day: DayController

    /// The place the window is showing.
    ///
    /// The Oggi pane always answers `.day`, so the three scales are three places rather than
    /// one (ADR-0013 §D4 makes them three ways of looking at one anchor, and going from the
    /// week to the month is going somewhere). The Note pane answers `.note` only when a note
    /// is open; with none it is `.pane(.notes)`, which is what the window actually shows.
    var destination: Destination {
        switch navigation.pane {
        case .today:
            .day(day.day, day.scale)
        case .notes:
            vault.openNote.map { .note($0.relativePath) } ?? .pane(.notes)
        case .workspace:
            // Read the *requested* path before the real one confirms it (ADR-0015 §D1
            // amendment) - `vault.openBoardPath` only catches up once `WorkspaceView` has
            // mounted and consumed the route, a render pass later than `navigation.pane`
            // itself changing. Falling back to it only after `pendingCanvas` clears is what
            // keeps `destination` reading the same board throughout the hand-off, so an
            // observer never sees `.pane(.workspace)` as an intermediate, spurious step.
            (vault.routeState.pendingCanvas?.path ?? vault.openBoardPath)
                .map { .workspaceBoard($0) } ?? .pane(.workspace)
        default:
            .pane(navigation.pane)
        }
    }

    /// Whether a move is a day scrolled past rather than a place gone to (ADR-0015 §D3).
    ///
    /// Both halves are needed and the first one is the one that bites: `lastDayMoveWasDrift`
    /// stays true until the next jump, so leaving the Oggi pane straight after scrolling a
    /// week would otherwise be recorded as drift and **replace** the entry it should push -
    /// the pane just left would not be in the history at all. Drift can only ever collapse a
    /// day into a day at the same scale; changing the scale is going somewhere.
    func isDrift(from previous: Destination, to moved: Destination) -> Bool {
        guard case .day(_, let was) = previous, case .day(_, let now) = moved else { return false }
        return was == now && day.lastDayMoveWasDrift
    }

    /// Whether a place recorded earlier is still somewhere the window can go.
    ///
    /// Only a note can stop existing: a pane is always there, and a day is a day. The check is
    /// the one `VaultController+Routes` makes for a `pergamenum://` link, for the same reason -
    /// a promise to take you somewhere has to fail out loud or not be made.
    func isReachable(_ destination: Destination) -> Bool {
        switch destination {
        case .note(let path):
            guard let store, let url = try? store.url(for: path) else { return false }
            return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        case .workspaceBoard(let path):
            guard let root = vault.root else { return false }
            return FileManager.default.fileExists(
                atPath: CanvasStore(root: root).url(forBoard: path).path(percentEncoded: false)
            )
        default:
            return true
        }
    }

    /// Puts the window back where a destination says.
    ///
    /// The mirror of `RootView.choose(_:)`, which does the same thing for a sidebar row. Both
    /// set the pane first and the anchor second, because a pane that arrives after its anchor
    /// is a pane that draws once with the old one.
    func apply(_ destination: Destination) {
        switch destination {
        case .pane(let pane):
            navigation.pane = pane
        case .note(let path):
            navigation.pane = .notes
            vault.openNote(at: path)
        case .workspaceBoard(let path):
            navigation.pane = .workspace
            // The exact mechanism a board wikilink's own cmd+click already uses
            // (`CommandActions+LinkNavigation.swift`) - `WorkspaceView`'s existing
            // `.task`/`.onChange` pair for `pendingCanvas` opens it once mounted.
            vault.routeState.pendingCanvas = (path, nil)
        case .day(let date, let scale):
            navigation.pane = .today
            // `show` and not `move`: arriving at a day from the history is a jump, whatever
            // the gesture that first recorded it was (§D3).
            day.show(date)
            day.scale = scale
        }
    }

    private var store: NoteStore? { vault.store }
}
