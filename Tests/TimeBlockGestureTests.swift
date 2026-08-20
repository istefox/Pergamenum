import Foundation
import Testing
@testable import Pergamenum

// Moving a block to another hour and pulling it longer (SPEC §8.3), the two gestures a
// block had no way of answering until a task could be dropped on an hour.

private let day = CalendarDate(iso: "2026-08-11")!

private func block(_ start: Int, _ duration: Int, _ title: String = "Blocco") -> TimeBlock {
    TimeBlock(day: day, startMinutes: start, durationMinutes: duration,
              title: title, sourceTaskID: nil, isPublished: false)
}

// MARK: - Muovere e allungare un blocco (SPEC §8.3)

@Test func aMovedBlockSnapsToTheQuarterHour() throws {
    let moved = try #require(TimeBlock.moved(block(15 * 60, 30), toStart: 16 * 60 + 37, among: []))

    #expect(moved.startMinutes == 16 * 60 + 30)
    #expect(moved.durationMinutes == 30)
    #expect(moved.title == "Blocco")
}

/// The same rule creation follows: a block is placed in free time rather than on top of
/// another, so the drop slides down to where there is room.
@Test func aMoveOntoAnOccupiedSlotSlidesToTheNextFreeStart() throws {
    let occupied = [block(16 * 60, 60, "Riunione")]

    let moved = try #require(TimeBlock.moved(block(9 * 60, 30), toStart: 16 * 60, among: occupied))

    // Past the whole of it, not into the middle: 16:30 is still inside the meeting.
    #expect(moved.startMinutes == 17 * 60)
}

/// A block always overlaps itself: the place it is leaving is not an obstacle, or every
/// move would be pushed down by the block's own length.
@Test func aBlockDoesNotCollideWithWhereItAlreadyIs() throws {
    let moved = try #require(TimeBlock.moved(block(9 * 60, 60), toStart: 9 * 60 + 15, among: []))

    #expect(moved.startMinutes == 9 * 60 + 15)
}

@Test func aMoveThatWouldRunPastMidnightIsRefused() {
    #expect(TimeBlock.moved(block(23 * 60, 60), toStart: 23 * 60 + 45, among: []) != nil)
    // Clamped inside the day rather than truncated: the block keeps its length.
    let clamped = TimeBlock.moved(block(23 * 60, 60), toStart: 23 * 60 + 45, among: [])
    #expect(clamped?.startMinutes == 23 * 60)
    // No room at all: the last hour is taken and the block is longer than what is left.
    #expect(TimeBlock.moved(block(9 * 60, 60), toStart: 23 * 60 + 30, among: [block(23 * 60, 60)]) == nil)
}

@Test func aResizedBlockNeverGoesUnderAQuarter() {
    let resized = TimeBlock.resized(block(9 * 60, 60), toDuration: 4, among: [])

    #expect(resized.durationMinutes == 15)
    #expect(resized.startMinutes == 9 * 60)
}

/// Pulling the bottom edge through the next block would open by hand the overlap that
/// `moved` refuses to create, so it stops where that block starts.
@Test func aResizeStopsAtTheBlockUnderneath() {
    let resized = TimeBlock.resized(block(9 * 60, 30), toDuration: 180, among: [block(10 * 60, 60)])

    #expect(resized.durationMinutes == 60)
    #expect(resized.endMinutes == 10 * 60)
}

@Test func aResizeStopsAtMidnight() {
    let resized = TimeBlock.resized(block(23 * 60, 30), toDuration: 180, among: [])

    #expect(resized.endMinutes == 24 * 60)
}
