import XCTest

/// The one end-to-end path through the "Vai a data" sheet: toolbar, picker, confirm,
/// header. Everything else this file used to cover — the sheet's own calendar chrome,
/// typed-date entry, the month's disclosure and divider, the header format, the
/// toolbar's task capture, the due-soon bell, the completed filter — retired per the
/// UI-suite-replacement census (stage 3, Task 6): each has an in-process replacement
/// named in `docs/plans/ui-suite-replacement-census.md`'s DayViewUITests entry.
final class DayViewUITests: PergamenumUITestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try makeTemporaryVault(prefix: "DayViewUITest")
        try """
        ---
        date: 2026-08-13
        tags:
          - type-note
        ---

        # Nota di prova
        """.write(
            to: vault.appending(path: "Nota di prova.md", directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )

        // Tasks for the day view's lists: one planned for today, one already done, one
        // falling due in three days. Written with today's dates so the views that
        // depend on "oggi" are exercised rather than merely rendered.
        try """
        ---
        date: 2026-08-13
        tags:
          - type-note
        ---

        - [ ] Task di oggi >\(isoToday())
        - [x] Task chiuso >\(isoToday()) @done(\(isoToday()))
        - [ ] Task in scadenza !\(isoToday(plus: 3)) 15:00
        """.write(
            to: vault.appending(path: "Attivita.md", directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )

        launchApp()
        waitForMainWindow()
        sidebarRow("pane-today").click()
    }

    /// In the machine's own zone, because `CalendarDate.today` is: formatted in GMT
    /// these helpers disagree with the app for the two hours after local midnight, and
    /// a test that only fails at night is worse than no test.
    private func isoToday(plus days: Int = 0) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: calendar.date(byAdding: .day, value: days, to: Date()) ?? Date())
    }

    /// Picking a day and confirming moves the day the pane shows, which is the only
    /// thing the sheet is for.
    func testVaiADataMovesTheDay() throws {
        let target = isoToday(plus: 2)
        app.toolbars.buttons["day-go-to-date"].click()
        XCTAssertTrue(app.textFields["go-to-date-field"].waitForExistence(timeout: 5))

        let day = app.descendants(matching: .any).matching(identifier: "day-\(target)").firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 5), "il giorno \(target) non è nel calendario")
        day.click()
        app.buttons["go-to-date-confirm"].click()

        let parts = target.split(separator: "-")
        let shown = "\(parts[2])/\(parts[1])/\(parts[0])"
        // `TodayView.header`'s date, by identifier and then by `value` - the string a plain
        // `Text` carries on macOS - so no other text reading the same date can answer.
        let header = app.staticTexts
            .matching(NSPredicate(format: "identifier == %@ AND value == %@", "today-header-date", shown))
            .firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 5), "la vista non si è spostata su \(shown)")
    }
}
