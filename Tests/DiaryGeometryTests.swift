import CoreGraphics
import Foundation
import Testing
@testable import Pergamenum

// ADR-0053 §D2 #8, plan `docs/plans/ui-suite-replacement.md` Task 5, PR 2: the diary's drag maths,
// duplicated across `DiaryTimeline.range(of:)`/`.minutes(at:)`/`.dragThreshold` and
// `DiaryEntryCard.snappedDelta`, moves onto the existing `DiaryGeometry` (`DiaryEntryCard.swift:7`,
// R-12: `DiaryGeometry` appears in no file under `Tests/` today) as `range(fromY:toY:)`,
// `creationDuration(dragged:translationHeight:)` and `snappedDelta(_:notBefore:)`, taking scalars
// rather than a `DragGesture.Value` so a test needs no real gesture.
//
// Converts `UITests/DiaryUITests.swift:177` (`testDraggingOverEmptyTimeBlocksItOut`) and `:205`
// (`testABlockIsMovedByDragging`). `:205`'s hard-coded 120 pt (two hours at sixty to the hour) is
// never repeated here as a literal: it is expressed as `geometry.height(ofMinutes:)`, the same
// conversion the timeline's own cards place themselves with.
//
// `:110` (rename) and `:163` (two blocks sharing an hour) convert separately, over
// `DiaryController`, not this seam - see `DiaryComposerTests.swift` and `DiaryControllerTests.swift`.
//
// RED: before the collapse, these assertions exercised functions that did not exist on
// `DiaryGeometry` at all, so the target failed to build rather than the test failing on an
// assertion; the seam landed with its declaration and the test together, per the plan's "what
// 'red first' means in Swift".

private let geometry = DiaryGeometry(firstHour: DiaryGrid.firstHour, hourHeight: 60, gutter: 52, width: 400)

// MARK: - `range(fromY:toY:)`, replacing `DiaryTimeline.range(of:)` (Diary :177)

@Test func aDragFromNineToElevenBlocksOutTheTwoHoursBetween() {
    let range = geometry.range(fromY: geometry.offset(ofMinute: 9 * 60), toY: geometry.offset(ofMinute: 11 * 60))

    #expect(range.start == 9 * 60)
    #expect(range.end == 11 * 60)
}

@Test func aDragUpwardsStillBlocksOutFromTheEarlierTime() {
    let range = geometry.range(fromY: geometry.offset(ofMinute: 11 * 60), toY: geometry.offset(ofMinute: 9 * 60))

    #expect(range.start == 9 * 60)
    #expect(range.end == 11 * 60)
}

@Test func aDragLandsOnTheTenMinuteGridWhereverItActuallyStarted() {
    let range = geometry.range(
        fromY: geometry.offset(ofMinute: 9 * 60 + 4), toY: geometry.offset(ofMinute: 9 * 60 + 26)
    )

    #expect(range.start == 9 * 60)
    #expect(range.end == 9 * 60 + 30)
}

@Test func aRangeNeverCollapsesBelowOneGridStep() {
    let y = geometry.offset(ofMinute: 9 * 60)

    let range = geometry.range(fromY: y, toY: y)

    #expect(range.end - range.start == DiaryGrid.step)
}

// MARK: - `creationDuration(dragged:translationHeight:)`, the click/drag threshold (Diary :177)

@Test func aDragPastTheThresholdKeepsTheDraggedSpan() {
    let dragged = (start: 9 * 60, end: 11 * 60)

    let duration = geometry.creationDuration(dragged: dragged, translationHeight: DiaryGeometry.dragThreshold + 1)

    #expect(duration == dragged.end - dragged.start)
}

@Test func aClickUnderTheThresholdBlocksOutAnHourRegardlessOfTheDraggedSpan() {
    let dragged = (start: 9 * 60, end: 11 * 60)

    let duration = geometry.creationDuration(dragged: dragged, translationHeight: 2)

    #expect(duration == 60)
}

@Test func theThresholdItselfStillCountsAsAClick() {
    let dragged = (start: 9 * 60, end: 11 * 60)

    let duration = geometry.creationDuration(dragged: dragged, translationHeight: DiaryGeometry.dragThreshold)

    #expect(duration == 60)
}

// MARK: - `snappedDelta(_:notBefore:)`, replacing `DiaryEntryCard.snappedDelta` (Diary :205)

@Test func aTwoHourDragMovesTheBlockByExactlyTwoHours() {
    // The GUI test dragged 120 points down at sixty points to the hour (`DiaryUITests.swift:221`);
    // the same drag is expressed here through the geometry's own conversion, so the two hours are
    // never spelled out as a magic number.
    let translation = geometry.height(ofMinutes: 2 * 60)

    let delta = geometry.snappedDelta(translation, notBefore: 9 * 60)

    #expect(delta == 2 * 60)
}

@Test func aDragRoundsToTheNearestTenMinuteMark() {
    let delta = geometry.snappedDelta(geometry.height(ofMinutes: 34), notBefore: 0)

    #expect(delta == 30)
}

@Test func aBlockNeverDragsBeforeTheStartOfTheDay() {
    let delta = geometry.snappedDelta(-geometry.height(ofMinutes: DiaryGrid.dayMinutes), notBefore: 90)

    #expect(delta == -90)
}
