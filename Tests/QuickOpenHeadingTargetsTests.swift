import Testing
@testable import Pergamenum

/// R-22 (ADR-0083 §D5): Quick Open's heading query (`Nota#`) no longer takes the search's first hit
/// when the note part matches several notes' titles exactly; it keeps one target per note. With one
/// exact match, or none, it behaves as before.
@MainActor
@Suite struct QuickOpenHeadingTargets {
    @Test func aNotePartMatchingTwoTitlesExactlyGivesBothPaths() {
        let targets = QuickSwitcher.headingTargets(
            for: "Riunione",
            exact: { _ in ["Clienti/Riunione.md", "Progetti/Riunione.md"] },
            firstMatch: { _ in "Altro/Riunione settimanale.md" }
        )

        #expect(targets == ["Clienti/Riunione.md", "Progetti/Riunione.md"])
    }

    @Test func oneExactMatchGivesOnePath() {
        let targets = QuickSwitcher.headingTargets(
            for: "Unica",
            exact: { _ in ["Unica.md"] },
            firstMatch: { _ in "Altro/Unica bis.md" }
        )

        #expect(targets == ["Unica.md"])
    }

    @Test func noExactMatchFallsBackToTheSearchsFirst() {
        let targets = QuickSwitcher.headingTargets(
            for: "Riun", exact: { _ in [] }, firstMatch: { _ in "Clienti/Riunione.md" }
        )

        #expect(targets == ["Clienti/Riunione.md"])
    }

    @Test func nothingAtAllGivesNoTarget() {
        let targets = QuickSwitcher.headingTargets(for: "Zzz", exact: { _ in [] }, firstMatch: { _ in nil })

        #expect(targets.isEmpty)
    }

    @Test func theExactQueryIsAskedWithTheNotePart() {
        var asked: [String] = []
        _ = QuickSwitcher.headingTargets(
            for: "Riunione", exact: { asked.append($0); return [] }, firstMatch: { _ in nil }
        )

        #expect(asked == ["Riunione"])
    }
}
