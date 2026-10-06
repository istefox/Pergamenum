import XCTest

/// The one GUI test of PG-260 (Audit Fable chain 7, SPEC R-17): on a vault large enough for a
/// search to take visible time, the search progress indicator is drawn while the search runs,
/// and text typed during the search reaches the field before the results arrive.
///
/// **Why a GUI test (the justification CLAUDE.md asks of every one).** The search reads the
/// vault on the main actor (ADR-0041 §D12) and stays responsive only because it pauses between
/// chunks (`CooperativeLoop.pause`). The in-process tests prove the pause is called and that
/// cancellation stops the loop; whether a pause actually gives the run loop a turn to draw the
/// spinner and take a keystroke is exactly what they cannot observe - no run loop under
/// pressure, no real drawing. Chain 7 has no ADR, so this comment and the PR body carry the
/// justification. The chain adds exactly this one GUI test.
///
/// Controls are found by `accessibilityIdentifier` only (`vault-note-count`, `search-field`,
/// `search-progress`, `search-results`, `search-result-<path>`), and the one value read is the
/// note count this test's own fixture sets.
final class GlobalSearchUITests: PergamenumUITestCase {
    /// Filler notes, deterministic prose with no needle in it. Sized so one search over the
    /// vault takes visible time on the development machine; the measured duration is recorded
    /// as an activity of every run. First green run (2026-09-28, Debug build, this Mac):
    /// 17.5 s for the search, 42.5 s for the whole test.
    private static let fillerCount = 4000
    /// Paragraphs per filler note, about 160 bytes each.
    private static let paragraphsPerNote = 100
    private static let needle = "quadrifoglio"

    override func setUpWithError() throws {
        try super.setUpWithError()
        try makeTemporaryVault(prefix: "GlobalSearchUITest")
        try writeFixture()

        launchApp()
    }

    /// `element(_:)`'s lookup (`PergamenumUITestCase`), scoped to the search sheet's own subtree
    /// rather than the whole app.
    ///
    /// Its `app.descendants(matching: .any)` walks every element of every kind in
    /// every window, including the sidebar behind the sheet - on this fixture, a 4001-row note
    /// list. `waitForExistence` re-runs that walk on every poll for the length of its timeout,
    /// so while the cooperative search holds the main actor in short chunks (`CooperativeLoop`),
    /// each poll's own AX round-trip has to be serviced by that same main thread and competes
    /// with it - measured to turn a ~15s search into one that never finished inside 120s+70s of
    /// GUI wall time, though the identical query against the identical fixture finishes in
    /// ~14-15s run in-process with no AX traffic at all (root-caused for PG-260's R-17 fix).
    /// `.sheet` is its own attached window in the AX tree, so scoping the walk to it is a
    /// strictly smaller, still-real query - not a looser assertion - over exactly the subtree
    /// the sheet's own controls live in.
    private func sheetElement(_ identifier: String) -> XCUIElement {
        app.sheets.firstMatch.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Words with no `quadri` in them, cycled by index so every note differs and every run
    /// writes the same vault.
    private static let words = [
        "isolatore", "frequenza", "propria", "eccitazione", "rapporto", "smorzamento", "gomma",
        "rigidezza", "carico", "statico", "dinamico", "supporto", "vibrazione", "attenua",
        "amplifica", "curva", "trasmissibilità", "montaggio", "flangia", "boccola",
    ]

    private func writeFixture() throws {
        let front = "---\ndate: 2026-08-11\ntags:\n  - type-note\n---\n\n"
        for note in 0..<Self.fillerCount {
            var body = front
            for paragraph in 0..<Self.paragraphsPerNote {
                let line = (0..<20).map { Self.words[(note * 7 + paragraph * 3 + $0) % Self.words.count] }
                body += line.joined(separator: " ") + ".\n\n"
            }
            try body.write(
                to: vault.appending(path: String(format: "Nota %04d.md", note), directoryHint: .notDirectory),
                atomically: false, encoding: .utf8
            )
        }
        try (front + "Un \(Self.needle) nel prato.\n").write(
            to: vault.appending(path: "Bersaglio.md", directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )
    }

    /// `4001` as `4[^0-9]?001`: the digits in groups of three from the right, any single
    /// separator (or none) between them.
    private static func digitGroupsPattern(_ number: Int) -> String {
        var digits = String(number)
        var groups: [String] = []
        while digits.count > 3 {
            groups.insert(String(digits.suffix(3)), at: 0)
            digits.removeLast(3)
        }
        groups.insert(digits, at: 0)
        return groups.joined(separator: "[^0-9]?")
    }

    func testTheSpinnerDrawsAndTypingIsAcceptedWhileASearchRuns() throws {
        // The first scan of a fresh state is not cached: searching before it ends would search
        // a half-built index and measure nothing. The count label is drawn only once it has.
        // The app groups thousands the way its locale does (`4.001 note`) while this runner's
        // locale may not, and a static text carries the string in `value`: so the digits are
        // matched with any separator between groups, in either attribute.
        let count = element("vault-note-count")
        let expected = ".*\(Self.digitGroupsPattern(Self.fillerCount + 1)) note.*"
        let scanned = NSPredicate(format: "label MATCHES %@ OR value MATCHES %@", expected, expected)
        let scanDone = XCTNSPredicateExpectation(predicate: scanned, object: count)
        XCTAssertEqual(XCTWaiter.wait(for: [scanDone], timeout: 180), .completed, "la prima scansione non è finita")

        app.typeKey("f", modifierFlags: [.command, .shift])
        let field = sheetElement("search-field")
        XCTAssertTrue(field.waitForExistence(timeout: 10), "il foglio della ricerca non si è aperto")
        field.click()

        // R-17a: the spinner is drawn while the search runs.
        field.typeText("quadri")
        let progress = sheetElement("search-progress")
        XCTAssertTrue(progress.waitForExistence(timeout: 10), "l'indicatore della ricerca non è comparso")
        let started = Date()

        // R-17b: typed while the search runs, the text reaches the field before any result.
        XCTAssertTrue(progress.exists, "la ricerca è finita prima che si potesse scrivere")
        field.typeText("foglio")
        let results = sheetElement("search-results")
        XCTAssertEqual(field.value as? String, Self.needle, "il testo scritto durante la ricerca non è nel campo")
        XCTAssertFalse(results.exists, "i risultati sono arrivati prima del testo scritto durante la ricerca")

        XCTAssertTrue(results.waitForExistence(timeout: 120), "i risultati non sono arrivati")
        let elapsed = Date().timeIntervalSince(started)
        XCTContext.runActivity(named: String(format: "ricerca sul fixture: %.1f s", elapsed)) { _ in }

        let target = results.descendants(matching: .any)
            .matching(identifier: "search-result-Bersaglio.md").firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 5), "manca la riga di Bersaglio")
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: progress)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed, "l'indicatore è rimasto dopo i risultati")
    }
}
