import Foundation
import Testing
@testable import Pergamenum

// Note names and recording note titles (ADR-0032 §D5).
// Split out of ConventionsTests.swift (PG-148, ADR-0051): the file had passed 800 lines across
// eleven MARK sections and no @Suite, so each section moved whole and none was edited.

// MARK: - Note names

@Test(arguments: ["Nota/sbagliata", "Nota:sbagliata", "Nota#sbagliata", "Nota[1]", "Nota|alt"])
func rejectsForbiddenCharactersInTitles(_ title: String) {
    #expect(NoteName.validate(title).contains { if case .containsForbiddenCharacter = $0 { true } else { false } })
}

@Test func rejectsOverlongTitles() {
    let title = String(repeating: "a", count: 61)
    #expect(NoteName.validate(title).contains(.tooLong(count: 61)))
    #expect(NoteName.validate(String(repeating: "a", count: 60)).isEmpty)
}

@Test(arguments: ["Relazione di calcolo v2", "Relazione_v10", "Relazione-V3"])
func rejectsVersionSuffixes(_ title: String) {
    #expect(NoteName.validate(title).contains { if case .hasVersionSuffix = $0 { true } else { false } })
}

@Test func acceptsTitlesWithAccentsAndSpaces() {
    #expect(NoteName.validate("Trasmissibilità e rapporto di frequenza").isEmpty)
}

@Test func acceptsAWordThatMerelyStartsWithV() {
    // "v" followed by digits is a version; "vibrazioni" is not.
    #expect(NoteName.validate("Analisi delle vibrazioni").isEmpty)
}

@Test func requiresTheCompactFormForDailyNotes() {
    #expect(NoteName.validateDaily("20260811").isEmpty)
    #expect(!NoteName.validateDaily("2026-08-11").isEmpty)
}

@Test func sanitizesArbitraryTextIntoAUsableTitle() {
    let sanitized = NoteName.sanitized("  Offerta: supporti [rev 2] / EMEA  ")
    #expect(!sanitized.contains(where: NoteName.forbiddenCharacters.contains))
    #expect(sanitized == sanitized.trimmingCharacters(in: .whitespaces))
}

@Test func classifiesDailyNotesByFolder() {
    #expect(NoteName.category(forFileName: "20260811.md", dailyFolder: "Calendar", path: "Calendar/20260811.md") == .daily)
    // Same name outside the daily folder is an event note, not a daily note.
    #expect(NoteName.category(forFileName: "20260811.md", dailyFolder: "Calendar", path: "01 Progetti/20260811.md") == .note)
    #expect(NoteName.category(forFileName: "Titolo.md", dailyFolder: "Calendar", path: "Titolo.md") == .note)
}

// MARK: - Recording note titles (ADR-0032 §D5, plan Task 4, R-05)
//
// `ImportNaming.recordingNoteTitle(recordedAt:name:)` is additive (this file compiles
// into `perg` and `pergamenum-mcp` too, Foundation-only). Its production body is a
// tester-declared stub (see `ImportNaming.swift`) - every test below is red until the
// coder implements the four rules the ADR names.

@Test func derivesATitleFromAColonBearingHumanNameWithNoForbiddenCharacters() throws {
    // Measured live on 2026-09-05 (ADR-0032 M1): a recording's `name` can be a long
    // human title with a colon in it, neither of which `NoteName` accepts as-is.
    let recordedAt = try #require(PlaudTimestamp.parse("2026-09-04T11:48:07"))
    let name = "09-04 Riunione: Preparazione revisione trimestrale con cliente - Diagramma di Flusso Componenti"

    let title = ImportNaming.recordingNoteTitle(recordedAt: recordedAt, name: name)

    #expect(title.hasPrefix("20260904_Registrazione_"))
    #expect(NoteName.validate(title).isEmpty, "\(NoteName.validate(title))")
}

@Test func derivesATitleFromTheOldTimestampFormName() throws {
    // Measured live (ADR-0032 M1): one recording still carries `name` as the raw
    // timestamp the SPEC originally documented for all of them.
    let recordedAt = try #require(PlaudTimestamp.parse("2026-09-04T11:44:51"))
    let name = "2026-09-04 13:44:51"

    let title = ImportNaming.recordingNoteTitle(recordedAt: recordedAt, name: name)

    #expect(title.hasPrefix("20260904_Registrazione_"))
    #expect(NoteName.validate(title).isEmpty, "\(NoteName.validate(title))")
}

@Test func dropsALeadingDateLikeTokenBeforeSlugging() throws {
    // ADR §D5 rule 1: six of eight measured names begin `09-04 ` or `2026-09-04 `, and
    // leaving it in would slug the date twice. Stripping it means the title is the same
    // whether or not the recording's own name repeats the day it was recorded on.
    let recordedAt = try #require(PlaudTimestamp.parse("2026-09-04T11:48:07"))
    let bare = ImportNaming.recordingNoteTitle(recordedAt: recordedAt, name: "Sopralluogo linea 4")
    let withShortToken = ImportNaming.recordingNoteTitle(
        recordedAt: recordedAt, name: "09-04 Sopralluogo linea 4"
    )
    let withLongToken = ImportNaming.recordingNoteTitle(
        recordedAt: recordedAt, name: "2026-09-04 Sopralluogo linea 4"
    )

    #expect(bare == withShortToken)
    #expect(bare == withLongToken)
    #expect(!bare.contains("09-04"))
}

@Test func truncatesTheSlugAtAWordBoundaryWithNoTrailingHyphen() throws {
    // ADR §D5 rule 2: `NoteName.maximumLength` is 60 and a measured name reaches 79 (in
    // fact the file this was measured against is a good deal longer once slugged), so the
    // slug must be cut at a whole word, never mid-word, and never leave a trailing `-`.
    let recordedAt = try #require(PlaudTimestamp.parse("2026-09-04T11:48:07"))
    let name = "Argomento molto lungo che supera abbondantemente il limite di sessanta caratteri per il titolo della nota di registrazione di oggi"

    let title = ImportNaming.recordingNoteTitle(recordedAt: recordedAt, name: name)

    #expect(title.count <= NoteName.maximumLength)
    #expect(!title.hasSuffix("-"))

    let prefix = "20260904_Registrazione_"
    guard title.hasPrefix(prefix) else {
        Issue.record("title \(title) does not start with the derived date prefix")
        return
    }
    let slug = title.dropFirst(prefix.count)
    let sourceWords = Set(ImportNaming.kebabCase(name, maximumWords: 999).split(separator: "-"))
    for word in slug.split(separator: "-") {
        #expect(sourceWords.contains(word), "\"\(word)\" is not a whole word from the source name")
    }
}

@Test func aSingleWordLongerThanTheBudgetLeavesTheBareStemWithNoSlugAtAll() throws {
    // ADR §D5 rule 2's own edge, spelled out in `ImportNaming.recordingNoteTitle`'s doc
    // comment: cutting inside the one word a slug is made of is what rule 2 forbids, so
    // a slug that is a single word already over budget keeps no slug at all - not a
    // truncated fragment of it.
    let recordedAt = try #require(PlaudTimestamp.parse("2026-09-04T11:48:07"))
    let oneHugeWord = String(repeating: "a", count: 80)

    let title = ImportNaming.recordingNoteTitle(recordedAt: recordedAt, name: oneHugeWord)

    #expect(title == "20260904_Registrazione")
}

@Test func truncatedAtWordBoundaryReturnsEmptyForANonPositiveBudget() {
    // ADR-0045 §D5: the shared truncator's own guard, pinned directly - neither
    // protected caller's budget arithmetic can reach it (`recordingNoteTitle`'s and
    // `PraticaNaming.messageFileName`'s budgets are both fixed and always positive),
    // so this edge needs its own assertion rather than one reached through a caller.
    #expect(ImportNaming.truncatedAtWordBoundary("qualcosa", toFit: 0).isEmpty)
    #expect(ImportNaming.truncatedAtWordBoundary("qualcosa", toFit: -5).isEmpty)
}

@Test func usesTheRecordingsOwnLocalDateNotTodays() throws {
    // ADR §D5 rule 4: a recording imported a week later is filed under the day it
    // happened, not the day somebody pressed "Elabora". The expected prefix is computed
    // from the same `CalendarDate(_:in:)` the production code has to use, rather than a
    // hardcoded literal, so this test is not itself timezone-dependent.
    let recordedAt = try #require(PlaudTimestamp.parse("2026-08-11T09:00:00"))
    let localDate = CalendarDate(recordedAt, in: .current)
    let title = ImportNaming.recordingNoteTitle(recordedAt: recordedAt, name: "Nota di prova")
    #expect(title.hasPrefix("\(localDate.compactForm)_Registrazione_"))
    // And distinct from "today" (this suite is not run on 2026-08-11 itself).
    #expect(localDate != .today)
}
