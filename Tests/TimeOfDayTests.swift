import Foundation
import Testing
@testable import Pergamenum

// PG-263 (burn-down 2026-10-03): `HH:mm` through `String(format:)` in thirteen places became
// one `TimeOfDay`. The plan's acceptance is that the strings the app writes do not change -
// several are file formats a parser reads back (`@remind(...)`, a message file name) - so the
// first suite compares `TimeOfDay` against the `String(format:)` it replaced over a wide range,
// and the second pins each call site's output.

@Suite struct TimeOfDayTests {
    @Test func twoDigitsPadsASingleDigitAndLeavesWiderNumbersAlone() {
        #expect(TimeOfDay.twoDigits(0) == "00")
        #expect(TimeOfDay.twoDigits(7) == "07")
        #expect(TimeOfDay.twoDigits(9) == "09")
        #expect(TimeOfDay.twoDigits(10) == "10")
        #expect(TimeOfDay.twoDigits(59) == "59")
        #expect(TimeOfDay.twoDigits(100) == "100", "a wider number is never truncated")
    }

    @Test func formattedPadsBothFieldsAndDefaultsTheMinuteToZero() {
        #expect(TimeOfDay.formatted(hour: 7, minute: 30) == "07:30")
        #expect(TimeOfDay.formatted(hour: 9, minute: 5) == "09:05")
        #expect(TimeOfDay.formatted(hour: 23, minute: 59) == "23:59")
        #expect(TimeOfDay.formatted(hour: 6) == "06:00")
    }

    @Test func midnightAndTheEndOfTheDayAreBothSpellable() {
        #expect(TimeOfDay.formatted(hour: 0, minute: 0) == "00:00")
        #expect(TimeOfDay.formatted(hour: 24) == "24:00", "ADR-0075: a block may end at 24:00, written as given")
        #expect(TimeOfDay.formatted(minutes: 0) == "00:00")
        #expect(TimeOfDay.formatted(minutes: 1440) == "24:00", "1440 reads 24:00, not 00:00")
    }

    @Test func formattedMinutesSplitsAtTheHour() {
        #expect(TimeOfDay.formatted(minutes: 59) == "00:59")
        #expect(TimeOfDay.formatted(minutes: 60) == "01:00")
        #expect(TimeOfDay.formatted(minutes: 450) == "07:30")
        #expect(TimeOfDay.formatted(minutes: 1439) == "23:59")
    }

    /// The writer does not validate (its own doc comment): an out-of-range value is written as
    /// given, which is what `String(format: "%02d")` did before it.
    @Test func outOfRangeInputIsWrittenAsGivenNotClamped() {
        #expect(TimeOfDay.formatted(hour: 25, minute: 61) == "25:61")
        #expect(TimeOfDay.formatted(minutes: 1500) == "25:00")
        #expect(TimeOfDay.twoDigits(-5) == "-5")
    }

    /// The acceptance contract of the whole chain item: byte-identical to what it replaced.
    @Test func matchesTheStringFormatItReplacedAcrossAWideRange() {
        for value in -100...1500 {
            #expect(TimeOfDay.twoDigits(value) == String(format: "%02d", value), "twoDigits(\(value))")
        }
        for hour in 0...24 {
            for minute in 0...59 {
                #expect(
                    TimeOfDay.formatted(hour: hour, minute: minute) == String(format: "%02d:%02d", hour, minute),
                    "\(hour):\(minute)"
                )
            }
        }
        for minutes in 0..<1440 {
            #expect(
                TimeOfDay.formatted(minutes: minutes)
                    == String(format: "%02d:%02d", minutes / 60, minutes % 60),
                "\(minutes) minutes"
            )
        }
    }
}

/// Every site that used to call `String(format:)` itself, pinned to the string it writes.
@Suite struct TimeOfDayCallSiteTests {
    @Test func aTaskTimeIsPadded() {
        #expect(TaskTime(hour: 0, minute: 0).text == "00:00")
        #expect(TaskTime(hour: 9, minute: 5).text == "09:05")
        #expect(TaskTime(hour: 23, minute: 59).text == "23:59")
    }

    @Test func aReminderIsRenderedWithAPaddedTimeThatParsesBack() throws {
        let reminder = TaskReminder(date: try #require(CalendarDate(iso: "2026-03-04")), hour: 7, minute: 5)
        #expect(reminder.rendered == "@remind(2026-03-04 07:05)")
    }

    @Test func theDiaryGridWritesTheEndOfTheDayAsTwentyFourHundred() {
        #expect(DiaryGrid.timeText(0) == "00:00")
        #expect(DiaryGrid.timeText(5) == "00:05")
        #expect(DiaryGrid.timeText(65) == "01:05")
        #expect(DiaryGrid.timeText(1439) == "23:59")
        #expect(DiaryGrid.timeText(DiaryGrid.dayMinutes) == "24:00")
    }

    @Test func anHourWindowLabelsItsHourLines() {
        #expect(HourWindow.label(0) == "00:00")
        #expect(HourWindow.label(6) == "06:00")
        #expect(HourWindow.label(19) == "19:00")
        #expect(HourWindow.label(24) == "24:00")
    }

    @Test func theRolloverMarkerPadsDayAndMonth() throws {
        // 3 March 2026 is a Tuesday: both fields are single digits.
        #expect(RolloverMarker.text(for: try #require(CalendarDate(iso: "2026-03-03"))) == "martedì 03/03")
        #expect(RolloverMarker.text(for: try #require(CalendarDate(iso: "2026-12-31"))) == "giovedì 31/12")
    }

    /// `PraticaNaming.messageFileName` is a protected interface: a changed clock field orphans
    /// every message already on disk.
    @Test func aMessageFileNamePadsTheClockFields() throws {
        let date = try #require(CalendarDate(iso: "2026-06-10"))
        #expect(
            PraticaNaming.messageFileName(
                date: date, time: TaskTime(hour: 0, minute: 5), counterpart: "Rossi", subject: "Offerta"
            ) == "20260610_0005_Rossi_offerta.md"
        )
        #expect(
            PraticaNaming.messageFileName(
                date: date, time: TaskTime(hour: 23, minute: 59), counterpart: "Rossi", subject: "Offerta"
            ) == "20260610_2359_Rossi_offerta.md"
        )
    }

    @Test func aRecordingDurationPadsItsMinutesOnlyBesideAnHour() {
        #expect(RecordingFormat.duration(milliseconds: 5 * 60_000) == "5 min", "no hour, no padding")
        #expect(RecordingFormat.duration(milliseconds: 60 * 60_000) == "1 h 00 min")
        #expect(RecordingFormat.duration(milliseconds: (60 + 7) * 60_000) == "1 h 07 min")
        #expect(RecordingFormat.duration(milliseconds: (2 * 60 + 45) * 60_000) == "2 h 45 min")
        #expect(RecordingFormat.duration(milliseconds: -5) == "0 min")
    }
}
