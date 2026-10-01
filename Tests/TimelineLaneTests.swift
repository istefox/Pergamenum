import Foundation
import Testing
@testable import Pergamenum

// PG-339: overlapping events share the day grid's width instead of stacking.

private func lane(_ index: Int, of count: Int) -> TimelineLane {
    TimelineLane(index: index, count: count)
}

@Test func anEventThatOverlapsNothingKeepsTheFullWidth() {
    #expect(TimelineLane.assign([(start: 540, end: 600)]) == [.full])
    #expect(TimelineLane.assign([]) == [])
}

@Test func twoOverlappingEventsSitSideBySide() {
    // The case seen by hand: a shift from 07:00 to 13:00 over the last morning of a
    // multi-day event running until 10:00.
    let lanes = TimelineLane.assign([(start: 420, end: 780), (start: 0, end: 600)])
    #expect(lanes == [lane(1, of: 2), lane(0, of: 2)])
}

@Test func eventsThatOnlyTouchDoNotShareTheWidth() {
    let lanes = TimelineLane.assign([(start: 540, end: 600), (start: 600, end: 660)])
    #expect(lanes == [.full, .full])
}

@Test func aFreedColumnIsReusedWithinTheSameGroup() {
    // 09-12 spans the group; 09-10 and 10-11 follow each other in the second column.
    let lanes = TimelineLane.assign([
        (start: 540, end: 720), (start: 540, end: 600), (start: 600, end: 660),
    ])
    #expect(lanes == [lane(0, of: 2), lane(1, of: 2), lane(1, of: 2)])
}

@Test func aGroupIsAsWideAsItsBusiestMoment() {
    let lanes = TimelineLane.assign([
        (start: 540, end: 660), (start: 570, end: 630), (start: 600, end: 690),
    ])
    #expect(lanes == [lane(0, of: 3), lane(1, of: 3), lane(2, of: 3)])
}

@Test func separateGroupsAreLaidOutIndependently() {
    // A morning clash does not narrow an afternoon event that overlaps nothing.
    let lanes = TimelineLane.assign([
        (start: 540, end: 600), (start: 570, end: 630), (start: 900, end: 960),
    ])
    #expect(lanes == [lane(0, of: 2), lane(1, of: 2), .full])
}

@Test func theLongerOfTwoEventsStartingTogetherTakesTheLeftColumn() {
    let lanes = TimelineLane.assign([(start: 540, end: 570), (start: 540, end: 720)])
    #expect(lanes == [lane(1, of: 2), lane(0, of: 2)])
}
