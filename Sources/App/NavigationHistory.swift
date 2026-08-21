import Foundation
import Observation

/// Where the window is, as one value (ADR-0015 §D1).
///
/// The same idea as `RootView.currentItem`, one level deeper: computed from the state the
/// window already holds, never a second copy of it. Three cases and not nine, because seven of
/// the panes have no anchor - the Viste pane shows every view in the vault, «Preferite» every
/// starred note, and going there is going to one place.
enum Destination: Equatable, Sendable {
    /// A pane with nothing to anchor it: tags, starred, views, tasks, conformance, diary, the
    /// Workspace, and the Note pane with no note open, which is a real place - it is what the
    /// window shows before the first note is opened.
    ///
    /// The Workspace is here rather than carrying its canvas because its folder lives on a
    /// `WorkspaceController` held as `@State` inside `WorkspaceView`: view state the window
    /// cannot read. ADR-0015 §D1 records that as a limit with a way out, not as a judgement.
    case pane(Navigation.Pane)
    /// The Note pane, by relative path.
    ///
    /// The path and not the tab id: back means «that note», and a tab closed and reopened is
    /// the same place, which a tab id would make a different one.
    case note(String)
    /// The Oggi pane, at a day and a scale. Both, because ADR-0013 §D4 makes the three scales
    /// three ways of looking at one anchor: the day alone would not say which one you were in.
    case day(CalendarDate, DayScale)
}

/// The places the window has been, and the way back to them (ADR-0015).
///
/// Values and two stacks, and nothing else: the applying lives in the view, which is what
/// keeps §D1's and §D3's rules testable rather than only observable.
@MainActor
@Observable
final class NavigationHistory {
    /// What a change to the destination means.
    enum Move {
        /// A place the user went to. Pushes, and drops the forward stack.
        case step
        /// A day scrolled past on the way to nowhere in particular (§D3). Replaces the top
        /// entry, so five presses of `Cmd+←` leave one entry and not five.
        case drift
    }

    /// Fifty, oldest dropped. A number rather than unbounded growth, and large enough that
    /// nobody reaches it deliberately.
    static let limit = 50

    private(set) var current: Destination?
    private(set) var back: [Destination] = []
    private(set) var forward: [Destination] = []

    /// The destination this history has just asked the window to go to, and therefore the one
    /// change it must not record (ADR-0015 §D4).
    ///
    /// **A value and not a boolean flag, and the difference is the whole reason this works.**
    /// The observer that feeds `record` runs on the next view update, not inside `goBack`, so
    /// a flag set and cleared around the apply would already be false by the time the change
    /// arrived and the replay would be recorded as a step. Holding what is expected instead
    /// makes the suppression self-clearing and independent of when the observer runs.
    private(set) var expected: Destination?

    var canGoBack: Bool { !back.isEmpty }
    var canGoForward: Bool { !forward.isEmpty }

    /// Notes where the window is now.
    ///
    /// Called from one place - the observer on the derived destination - rather than from the
    /// eleven methods that move the window (§D2). The first call seeds `current` without
    /// pushing anything: the window's first destination is not a step from anywhere.
    func record(_ destination: Destination, as move: Move) {
        if expected == destination {
            expected = nil
            current = destination
            return
        }
        // A replay that landed somewhere else means the destination could not be applied, and
        // the window moved on its own instead. Whatever is being recorded now is the truth, so
        // the expectation is dropped rather than kept for a change that will never come.
        expected = nil

        guard destination != current else { return }
        guard let previous = current, move == .step else {
            current = destination
            return
        }
        back.append(previous)
        if back.count > Self.limit { back.removeFirst(back.count - Self.limit) }
        forward.removeAll()
        current = destination
    }

    /// The previous place still worth going to, or nothing.
    ///
    /// `isReachable` is asked because a note visited an hour ago may have been renamed or
    /// trashed since. Such an entry is **dropped and the walk continues**, which is the rule
    /// `VaultController+Routes` already fixed for a `pergamenum://` link naming a note that is
    /// not there: silently doing nothing is worse than saying the note has moved. A dropped
    /// entry does not reach the forward stack - it is not somewhere to come back to.
    func goBack(reachable isReachable: (Destination) -> Bool) -> Destination? {
        step(from: &back, to: &forward, reachable: isReachable)
    }

    /// The place a `goBack` came from, by the same rules.
    func goForward(reachable isReachable: (Destination) -> Bool) -> Destination? {
        step(from: &forward, to: &back, reachable: isReachable)
    }

    private func step(
        from source: inout [Destination],
        to sink: inout [Destination],
        reachable isReachable: (Destination) -> Bool
    ) -> Destination? {
        while let candidate = source.popLast() {
            guard isReachable(candidate) else { continue }
            if let current { sink.append(current) }
            current = candidate
            expected = candidate
            return candidate
        }
        return nil
    }
}
