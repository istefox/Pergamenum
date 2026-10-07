import Foundation
import Testing
@testable import Pergamenum

// PG-384 (N1 seams), ADR-0080 §D3 and §D4: `CaptureTitle.derive`, `CaptureTitle.typedLine`
// and `ImportNaming.truncatedAtSpace`. Pure functions, a fixed clock and a UTC calendar.

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// 2026-10-04 14:30 UTC.
private let fixedNow: Date = {
    var parts = DateComponents()
    parts.year = 2026
    parts.month = 10
    parts.day = 4
    parts.hour = 14
    parts.minute = 30
    parts.timeZone = TimeZone(identifier: "UTC")
    return utc.date(from: parts)!
}()

private func derive(_ typed: String) -> CaptureTitle {
    CaptureTitle.derive(fromTypedLine: typed, now: fixedNow, calendar: utc)
}

// MARK: - derive: the table

// (n1-seams R-03)
@Test func aLegalLineIsTheTitleUnchanged() {
    #expect(
        derive("Mescola per il distretto")
            == CaptureTitle(title: "Mescola per il distretto", differsFromTyped: false)
    )
}

// (n1-seams R-03, R-04)
@Test(arguments: [
    ("Idea: usare i token anche per i font?", "Idea usare i token anche per i font"),
    ("questo/non va", "questo non va"),
    ("3/10 prove", "3 10 prove"),
    ("Relazione v2", "Relazione"),
    ("Bozza v2 v3", "Bozza"),
    (".nascosta", "nascosta"),
])
func aLineTheConventionsRefuseGetsADerivedTitle(typed: String, expected: String) {
    let result = derive(typed)

    #expect(result.title == expected)
    #expect(result.differsFromTyped, "«\(typed)» → «\(result.title)» non è segnato come diverso")
}

// MARK: - derive: the cut

// (n1-seams R-03)
@Test func aLongSentenceIsCutAtTheLastSpaceWithinSixtyCharacters() {
    // 90 characters, spaces every few letters so a cut inside a word is possible.
    let sentence = "alfa beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma"
    #expect(sentence.count > 60)

    let result = derive(sentence)

    #expect(result.differsFromTyped)
    #expect(result.title.count <= NoteName.maximumLength)
    // The last space at or before offset 60: nothing longer fits, nothing shorter is taken.
    let window = sentence.prefix(NoteName.maximumLength + 1)
    let lastSpace = window.lastIndex(of: " ")
    let expected = lastSpace.map { String(window[..<$0]) }
    #expect(result.title == expected)
}

// (n1-seams R-03)
@Test func aSingleSeventyCharacterWordIsCutAtSixty() {
    let word = String(repeating: "a", count: 70)

    let result = derive(word)

    #expect(result.title == String(repeating: "a", count: 60))
    #expect(result.differsFromTyped)
}

// (n1-seams R-03)
@Test func aCutThatExposesAVersionTokenIsRepairedOnTheNextPass() {
    // 55 letters, a space, then `v2`: the cut at the last space within 60 lands right after
    // `v2`, which is now the trailing token, and the next pass removes it.
    let head = String(repeating: "a", count: 55)
    let typed = "\(head) v2 coda lunga che non entra"

    let result = derive(typed)

    #expect(result.title == head)
    #expect(NoteName.validate(result.title).isEmpty)
}

// (n1-seams R-03)
@Test func aCutAtASpaceNeverLeavesTheSpaceOnTheTitle() {
    // The sixtieth character is a space: the title is what came before it.
    let head = String(repeating: "b", count: 59)
    let typed = "\(head) \(String(repeating: "c", count: 20))"

    let result = derive(typed)

    #expect(result.title == head)
    #expect(result.title == result.title.trimmingCharacters(in: .whitespaces))
    #expect(NoteName.validate(result.title).isEmpty)
}

// MARK: - derive: nothing left

// (n1-seams R-03)
@Test func aLineOfNothingButForbiddenCharactersGetsTheTimestampTitle() {
    let result = derive("???")

    #expect(result.title == "20261004 1430 Cattura")
    #expect(result.differsFromTyped)
    #expect(NoteName.validate(result.title).isEmpty)
}

// (n1-seams R-03)
@Test func aBareVersionTokenGetsTheTimestampTitle() {
    #expect(derive("v2").title == "20261004 1430 Cattura")
}

// (n1-seams R-03)
@Test func theFallbackReadsTheCalendarAndTimeZoneItIsGiven() {
    var rome = Calendar(identifier: .gregorian)
    rome.timeZone = TimeZone(identifier: "Europe/Rome")!

    // 14:30 UTC is 16:30 in Rome in October (CEST).
    let result = CaptureTitle.derive(fromTypedLine: "???", now: fixedNow, calendar: rome)

    #expect(result.title == "20261004 1630 Cattura")
}

// MARK: - derive: every title it returns is one `createNote` accepts

// (n1-seams R-03, R-06)
@Test(arguments: [
    "Idea: usare i token anche per i font?",
    "questo/non va",
    "3/10 prove",
    "Relazione v2",
    "Bozza v2 v3",
    ".nascosta",
    "???",
    "v2",
    "  ..  :: v10",
    "a/b\\c:d*e?f\"g<h>i|j#k^l[m]n",
    "Nota_v12",
    "Nota-V3",
    String(repeating: "parola ", count: 30),
    String(repeating: "x", count: 200),
])
func everyDerivedTitleIsAcceptedByTheNameRule(typed: String) {
    let result = derive(typed)

    #expect(
        NoteName.validate(result.title).isEmpty,
        "«\(typed)» → «\(result.title)»: \(NoteName.validate(result.title))"
    )
}

// (n1-seams R-03)
@Test func deriveIsAFixedPointOnItsOwnOutput() {
    for typed in ["Idea: usare i token?", "Relazione v2", ".nascosta", String(repeating: "parola ", count: 15)] {
        let once = derive(typed)
        #expect(once.differsFromTyped, "«\(typed)» è un titolo illegale e deve essere derivato")
        let twice = derive(once.title)
        #expect(twice.title == once.title, "«\(typed)» non si stabilizza")
        #expect(!twice.differsFromTyped, "il titolo derivato di «\(typed)» non è già legale")
    }
}

// MARK: - typedLine

// (n1-seams R-03)
@Test func theTypedLineStopsAtTheFirstLineBreakOfAnyKind() {
    #expect(CaptureTitle.typedLine(of: "A\r\nB") == "A")
    #expect(CaptureTitle.typedLine(of: "A\nB") == "A")
    #expect(CaptureTitle.typedLine(of: "A\rB") == "A")
}

// (n1-seams R-03)
@Test func theTypedLineIsTrimmedOfOuterSpaces() {
    #expect(CaptureTitle.typedLine(of: "   Mescola per il distretto  \nCorpo") == "Mescola per il distretto")
    #expect(CaptureTitle.typedLine(of: "solo") == "solo")
    #expect(CaptureTitle.typedLine(of: "   ") == "")
    #expect(CaptureTitle.typedLine(of: "") == "")
}

// MARK: - truncatedAtSpace (R-06)

// (n1-seams R-06)
@Test func truncatedAtSpaceLeavesATextShorterThanTheLimitAlone() {
    #expect(ImportNaming.truncatedAtSpace("uno due tre", toFit: 60) == "uno due tre")
}

// (n1-seams R-06)
@Test func truncatedAtSpaceKeepsATextThatFitsExactly() {
    #expect(ImportNaming.truncatedAtSpace("uno due tre", toFit: 11) == "uno due tre")
}

// (n1-seams R-06)
@Test func truncatedAtSpaceCutsAtTheLastSpaceThatKeepsItWithinTheLimit() {
    // "uno due" is 7, "uno due tre" is 11.
    #expect(ImportNaming.truncatedAtSpace("uno due tre", toFit: 10) == "uno due")
    #expect(ImportNaming.truncatedAtSpace("uno due tre", toFit: 7) == "uno due")
    #expect(ImportNaming.truncatedAtSpace("uno due tre", toFit: 8) == "uno due")
}

// (n1-seams R-06)
@Test func truncatedAtSpaceCutsInsideAWordOnlyWhenTheFirstWordIsLonger() {
    #expect(ImportNaming.truncatedAtSpace("abcdefghij klm", toFit: 4) == "abcd")
    #expect(ImportNaming.truncatedAtSpace(String(repeating: "z", count: 70), toFit: 60)
        == String(repeating: "z", count: 60))
}

// MARK: - truncatedAtWordBoundary with a separator (ADR-0088 §D1)

// (note-workflow R-02) One cutting loop: the space-separated cut is the slug cut with a
// different separator, so `truncatedAtSpace` can be a wrapper over it.
@Test func theWordBoundaryTruncatorCutsAtTheGivenSeparator() {
    #expect(ImportNaming.truncatedAtWordBoundary("uno due tre", toFit: 7, separator: " ") == "uno due")
}

// (note-workflow R-02) It never cuts inside a word: a first word over the budget gives "",
// and `truncatedAtSpace` is what turns that into a hard cut.
@Test func theWordBoundaryTruncatorReturnsNothingWhenTheFirstWordExceedsTheBudget() {
    #expect(ImportNaming.truncatedAtWordBoundary("abcdefghij klm", toFit: 4, separator: " ") == "")
}

// (note-workflow R-02) The default separator is today's hyphen, which the two protected
// names rely on.
@Test func theWordBoundaryTruncatorStillSplitsOnHyphensByDefault() {
    #expect(ImportNaming.truncatedAtWordBoundary("uno-due-tre", toFit: 7) == "uno-due")
}
