import Foundation
import Testing
@testable import Pergamenum

// The rules the renderers of M11 slice 4 read. The views themselves are looked at on screen;
// what is testable here is what they decide before they draw.

// MARK: - Le colonne quando il blocco non le dice

@Test func eachRendererHasItsOwnDefaultColumns() throws {
    #expect(try ViewBlock.parse("render: table").effectiveColumns == [.title, .tags, .modified])
    #expect(try ViewBlock.parse("render: list").effectiveColumns == [.title, .tags, .modified])
    #expect(try ViewBlock.parse("render: gallery").effectiveColumns == [.title])
    #expect(try ViewBlock.parse("render: calendar").effectiveColumns == [.title])
    #expect(try ViewBlock.parse("render: board\ngroup: tag(\"status-*\")").effectiveColumns == [.title, .tags])
}

@Test func aBlockThatNamesItsColumnsKeepsThemInOrder() throws {
    let block = try ViewBlock.parse("render: table\ncolumns: [modified, title]")
    #expect(block.effectiveColumns == [.modified, .title])
}

// MARK: - Il giorno su cui un calendario posa una riga

/// The choice approved with the mockups: the first date-valued column, and `date` when the
/// block names none. No eighth key was added for it (§D3 holds the grammar at seven).
@Test func theCalendarPlacesRowsByTheFirstDatedColumn() throws {
    #expect(try ViewBlock.parse("render: calendar").calendarField == .date)
    #expect(try ViewBlock.parse("render: calendar\ncolumns: [title]").calendarField == .date)
    #expect(try ViewBlock.parse("render: calendar\ncolumns: [title, deadline.next]").calendarField
        == .deadlineNext)
    #expect(try ViewBlock.parse("render: calendar\ncolumns: [modified, scheduled.next]").calendarField
        == .modified)
}

@Test func onlyTheFourDateFieldsCountAsDated() {
    #expect(ViewField.allCases.filter(\.isDated) == [.date, .modified, .deadlineNext, .scheduledNext])
}

// MARK: - Come si legge un valore

@Test func aValueWithNothingInItHasNoText() {
    #expect(ViewValueText.text(.absent, of: .date) == nil)
    #expect(ViewValueText.text(.text(""), of: .folder) == nil)
    #expect(ViewValueText.text(.list([]), of: .tags) == nil)
}

@Test func aDayIsWrittenTheWayTheRestOfTheInterfaceWritesOne() {
    let day = CalendarDate(iso: "2026-08-19")!
    #expect(ViewValueText.text(.day(day), of: .modified) == "19/08/2026")
}

@Test func aListIsJoinedAndACountIsItself() {
    #expect(ViewValueText.text(.list(["a", "b"]), of: .links) == "a, b")
    #expect(ViewValueText.text(.number(3), of: .tasksOpen) == "3")
}

/// `size` is the one number that is not a count, and reading it in bytes is reading it wrong.
@Test func sizeIsReadAsAFileSize() {
    let text = try? #require(ViewValueText.text(.number(24_000), of: .size))
    #expect(text?.contains("kB") == true || text?.contains("KB") == true)
}

// MARK: - I nomi

@Test func everyFieldAndEveryRendererHasAName() {
    for field in ViewField.allCases {
        #expect(!field.label.isEmpty)
        // A label left to fall back on the raw value would read `tasks.open` in a header.
        #expect(field.label != field.rawValue)
    }
    #expect(ViewBlock.Renderer.allCases.map(\.title) == ["tabella", "board", "gallery", "calendario", "lista"])
}
