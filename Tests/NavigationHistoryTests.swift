import Foundation
import Testing
@testable import Pergamenum

// The history of ADR-0015. Everything here is about the two rules that are easy to state and
// easy to get wrong - a step pushes and drift does not (§D3), and a replay records nothing
// (§D4) - plus the one that only shows up after a note is renamed (§D4's last paragraph).

/// Everything is reachable unless a test says otherwise, which is the ordinary case: a place
/// stops existing only when its note does.
private let anywhere: @Sendable (Destination) -> Bool = { _ in true }

private let friday = CalendarDate(iso: "2026-08-21")!

@MainActor
private func walked(_ destinations: [Destination]) -> NavigationHistory {
    let history = NavigationHistory()
    for destination in destinations { history.record(destination, as: .step) }
    return history
}

// MARK: - Steps

@MainActor
@Test func theFirstDestinationIsNotAStepFromAnywhere() {
    let history = NavigationHistory()
    history.record(.pane(.notes), as: .step)

    #expect(history.current == .pane(.notes))
    #expect(history.back.isEmpty)
    #expect(!history.canGoBack)
}

@MainActor
@Test func backAndForwardWalkTheSameOrder() {
    let visited: [Destination] = [.pane(.notes), .note("Note/lavoro.md"), .day(friday, .week)]
    let history = walked(visited)

    #expect(history.goBack(reachable: anywhere) == .note("Note/lavoro.md"))
    #expect(history.goBack(reachable: anywhere) == .pane(.notes))
    #expect(history.goBack(reachable: anywhere) == nil)
    #expect(!history.canGoBack)

    #expect(history.goForward(reachable: anywhere) == .note("Note/lavoro.md"))
    #expect(history.goForward(reachable: anywhere) == .day(friday, .week))
    #expect(history.goForward(reachable: anywhere) == nil)
}

@MainActor
@Test func arrivingSomewhereNewDropsTheWayForward() {
    let history = walked([.pane(.notes), .note("Note/lavoro.md"), .pane(.views)])
    _ = history.goBack(reachable: anywhere)
    #expect(history.canGoForward)

    // The replay is absorbed first, so this is the user going somewhere new from where back
    // left them - the branch that makes the abandoned future unreachable.
    history.record(.note("Note/lavoro.md"), as: .step)
    history.record(.pane(.tags), as: .step)

    #expect(!history.canGoForward)
    #expect(history.goBack(reachable: anywhere) == .note("Note/lavoro.md"))
}

@MainActor
@Test func standingStillIsNotAStep() {
    let history = walked([.pane(.notes)])
    history.record(.pane(.notes), as: .step)

    #expect(history.back.isEmpty)
}

// MARK: - Drift (§D3)

@MainActor
@Test func scrollingAWeekAtATimeLeavesOneEntry() {
    let history = walked([.note("Note/lavoro.md"), .day(friday, .week)])

    // Five presses of the week chevron. Back must leave the pane, not replay the scrolling.
    for step in 1...5 {
        history.record(.day(friday.adding(days: 7 * step), .week), as: .drift)
    }

    #expect(history.back == [.note("Note/lavoro.md")])
    #expect(history.current == .day(friday.adding(days: 35), .week))
    #expect(history.goBack(reachable: anywhere) == .note("Note/lavoro.md"))
}

@MainActor
@Test func aJumpToADateIsAStepAndDriftAfterItIsNot() {
    let history = walked([.day(friday, .day)])
    history.record(.day(CalendarDate(iso: "2026-12-24")!, .day), as: .step)
    history.record(.day(CalendarDate(iso: "2026-12-25")!, .day), as: .drift)

    #expect(history.goBack(reachable: anywhere) == .day(friday, .day))
}

// MARK: - Replaying (§D4)

@MainActor
@Test func aReplayIsNotRecorded() {
    let history = walked([.pane(.notes), .note("Note/lavoro.md")])
    let landing = history.goBack(reachable: anywhere)

    // What the observer sees once the window has moved. Recording it would push the place we
    // just left and back would walk in place.
    history.record(landing!, as: .step)

    #expect(history.current == .pane(.notes))
    #expect(history.back.isEmpty)
    #expect(history.goForward(reachable: anywhere) == .note("Note/lavoro.md"))
}

@MainActor
@Test func aReplayThatLandedElsewhereIsRecordedAsTheTruth() {
    let history = walked([.pane(.notes), .note("Note/lavoro.md")])
    _ = history.goBack(reachable: anywhere)

    // The window went somewhere other than what was asked for. Waiting for a change that will
    // never come would swallow the next real step instead.
    history.record(.pane(.tasks), as: .step)

    #expect(history.current == .pane(.tasks))
    #expect(history.back == [.pane(.notes)])
}

// MARK: - Places that stopped existing

@MainActor
@Test func aNoteThatIsGoneIsSkippedAndTheWalkContinues() {
    let history = walked([
        .pane(.notes), .note("Note/rinominata.md"), .note("Note/anche-questa.md"), .pane(.views),
    ])
    let survives: (Destination) -> Bool = { $0 != .note("Note/rinominata.md")
        && $0 != .note("Note/anche-questa.md") }

    #expect(history.goBack(reachable: survives) == .pane(.notes))
    // Dropped, not parked: a place that could not be applied is not one to come back to.
    #expect(history.goForward(reachable: survives) == .pane(.views))
}

@MainActor
@Test func aWalkWithNothingLeftToReachChangesNothing() {
    let history = walked([.note("Note/rinominata.md"), .pane(.views)])

    #expect(history.goBack(reachable: { $0 != .note("Note/rinominata.md") }) == nil)
    #expect(history.current == .pane(.views))
    #expect(!history.canGoBack)
}

// MARK: - The cap

@MainActor
@Test func theOldestEntriesFallOffTheEnd() {
    let history = NavigationHistory()
    for day in 0...NavigationHistory.limit + 10 {
        history.record(.note("Note/\(day).md"), as: .step)
    }

    #expect(history.back.count == NavigationHistory.limit)
    // Sixty-one notes were visited and one seeded `current`, so the oldest ten fell off the end.
    #expect(history.back.first == .note("Note/10.md"))
}
