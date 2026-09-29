import Foundation
import Testing
@testable import Pergamenum

// ADR-0071 (Contenitore) §D1/§D2/§D5/§D7/§D12/§D13, plan docs/plans/contenitore.md, Task 2:
// the pure Core units and the index field (R-02, R-06, R-17, R-18, R-19, R-26).

@MainActor
private func lintingSession(root: URL, stateBase: URL) -> VaultSession {
    VaultSession(
        root: root, stateBase: stateBase,
        bundledVocabulary: Bundle.pergamenumResources.url(forResource: "vocabolari", withExtension: "json")
    )
}

private let importDay = CalendarDate(year: 2026, month: 9, day: 29)!
private let sampleHash = String(repeating: "ab", count: 32)

private func bundledVocabulary() throws -> Vocabulary {
    let url = try #require(Bundle.pergamenumResources.url(forResource: "vocabolari", withExtension: "json"))
    return try JSONDecoder().decode(Vocabulary.self, from: Data(contentsOf: url))
}

// MARK: - Scheda text (R-02)

@Test func aRenderedSchedaParsesBackToItsFacts() {
    let text = ContenitoreScheda.render(
        date: importDay, fileName: "20260929 preventivo.pdf", originalName: "preventivo \"v2\".pdf", sha256: sampleHash
    )
    let document = NoteDocument.parse(text)
    let facts = ContenitoreScheda.facts(in: document.frontmatter.foreignKeys)

    #expect(document.frontmatter.date == importDay)
    #expect(document.frontmatter.tags.map(\.description) == ["type-note", "status-inbox"])
    #expect(facts == ContenitoreFacts(
        fileName: "20260929 preventivo.pdf", originalName: "preventivo \"v2\".pdf",
        sha256: sampleHash, colour: nil, rawColour: nil
    ))
    #expect(text.contains("pergamenum-contenitore: 1\n"))
    #expect(text.contains("pergamenum-contenitore-file: \"[[20260929 preventivo.pdf]]\"\n"))
}

@MainActor
@Test func aRenderedSchedaPassesTheLinter() throws {
    let vault = try TemporaryVault()
    let session = lintingSession(root: vault.root, stateBase: vault.stateBase)
    let text = ContenitoreScheda.render(
        date: importDay, fileName: "20260929 preventivo.pdf", originalName: "preventivo.pdf", sha256: sampleHash
    )

    let violations = session.violations(
        path: "Contenitore/2026/20260929 preventivo.md", title: "20260929 preventivo", text: text
    )

    #expect(violations.isEmpty, "\(violations)")
}

@Test func settingAndClearingTheColourChangesOneLine() {
    let text = ContenitoreScheda.render(
        date: importDay, fileName: "20260929 a.pdf", originalName: "a.pdf", sha256: sampleHash
    ) + "\nDescrizione.\n"

    let coloured = ContenitoreScheda.settingColour(.giallo, in: text)
    let recoloured = ContenitoreScheda.settingColour(.viola, in: coloured)
    let cleared = ContenitoreScheda.settingColour(nil, in: recoloured)

    let before = text.components(separatedBy: "\n")
    let after = coloured.components(separatedBy: "\n")
    #expect(after.count == before.count + 1)
    #expect(Set(after).subtracting(before) == ["pergamenum-contenitore-color: giallo"])
    #expect(recoloured.components(separatedBy: "\n").count == after.count)
    #expect(ContenitoreScheda.facts(in: NoteDocument.parse(recoloured).frontmatter.foreignKeys)?.colour == .viola)
    #expect(cleared == text)
}

@Test func anUnrecognisedColourReadsAsNoColourAndIsKept() {
    let text = ContenitoreScheda.settingColour(.giallo, in: ContenitoreScheda.render(
        date: importDay, fileName: "20260929 a.pdf", originalName: "a.pdf", sha256: sampleHash
    )).replacingOccurrences(of: "color: giallo", with: "color: fucsia")
    let facts = ContenitoreScheda.facts(in: NoteDocument.parse(text).frontmatter.foreignKeys)

    #expect(facts?.colour == nil)
    #expect(facts?.rawColour == "fucsia")
}

@Test func aSchemaValueOtherThanOneIsNotAScheda() {
    let text = ContenitoreScheda.render(
        date: importDay, fileName: "20260929 a.pdf", originalName: "a.pdf", sha256: sampleHash
    ).replacingOccurrences(of: "pergamenum-contenitore: 1", with: "pergamenum-contenitore: 2")

    #expect(ContenitoreScheda.facts(in: NoteDocument.parse(text).frontmatter.foreignKeys) == nil)
    #expect(NoteDocument.parse(text).serialized() == text)
}

// MARK: - Stem rules (R-06, name half)

@Test func theStemCarriesTheDatePrefixAndLosesForbiddenCharacters() {
    #expect(ContenitoreNaming.stem(forOriginal: "preventivo#1: Rossi?.pdf", importDate: importDay)
        == "20260929 preventivo1 Rossi")
}

@Test func aTrailingVersionTokenIsDropped() {
    #expect(ContenitoreNaming.stem(forOriginal: "offerta finale v2.pdf", importDate: importDay)
        == "20260929 offerta finale")
    #expect(ContenitoreNaming.stem(forOriginal: "offerta_v10.pdf", importDate: importDay) == "20260929 offerta")
}

@Test func aLongNameIsCutAtASpaceLeavingRoomForASuffix() {
    let long = "Preventivo fornitura guarnizioni in gomma per linea di confezionamento automatica nord.pdf"
    let stem = ContenitoreNaming.stem(forOriginal: long, importDate: importDay)

    #expect(stem.count <= NoteName.maximumLength - ContenitoreNaming.suffixReserve)
    #expect(long.hasPrefix(String(stem.dropFirst(9))))
    #expect(long.dropFirst(stem.count - 9).first == " ")
    #expect(NoteName.validate(stem + "-99").isEmpty)
}

@Test func anEmptyNameFallsBackToDocumentoAndIsNeverADailyNote() {
    let stem = ContenitoreNaming.stem(forOriginal: "###.pdf", importDate: importDay)
    #expect(stem == "20260929 documento")
    #expect(NoteName.category(forFileName: "\(stem).md", dailyFolder: nil, path: "\(stem).md") == .note)
    #expect(ContenitoreNaming.stem(forOriginal: "v2.pdf", importDate: importDay) == "20260929 documento")
}

@Test func aDotInsideTheNameIsKept() {
    let original = "fattura 2026.01.pdf"
    #expect(ContenitoreNaming.stem(forOriginal: original, importDate: importDay) == "20260929 fattura 2026.01")
    #expect((original as NSString).pathExtension == "pdf")
}

// MARK: - Pair uniqueness (R-06)

@Test func aStemTakenByEitherFileOrByATitleGetsOneSuffixForThePair() {
    let stem = "20260929 preventivo"
    #expect(ContenitoreNaming.uniquePairStem(stem, extension: "pdf", takenFileNames: [], takenTitles: []) == stem)
    #expect(ContenitoreNaming.uniquePairStem(
        stem, extension: "pdf", takenFileNames: ["20260929 preventivo.pdf"], takenTitles: []
    ) == "\(stem)-2")
    #expect(ContenitoreNaming.uniquePairStem(
        stem, extension: "pdf", takenFileNames: ["20260929 Preventivo.md", "20260929 preventivo-2.PDF"], takenTitles: []
    ) == "\(stem)-3")
    #expect(ContenitoreNaming.uniquePairStem(
        stem, extension: "pdf", takenFileNames: [], takenTitles: ["20260929 preventivo"]
    ) == "\(stem)-2")
}

// MARK: - Colours (R-17)

@Test func thereAreExactlySixColoursInPresetOrderWithTheStickyTokens() {
    #expect(ContenitoreColour.allCases.map(\.rawValue) == ["rosso", "arancio", "giallo", "verde", "ciano", "viola"])
    #expect(ContenitoreColour.allCases.map(\.canvasPreset) == [1, 2, 3, 4, 5, 6])
    #expect(ContenitoreColour.allCases.map(\.token)
        == [.stickyPink, .stickyOrange, .stickyYellow, .stickyGreen, .stickyBlue, .stickyPurple])
    #expect(ContenitoreColour.allCases.map(\.token) == (1...6).map(StickyPreset.token(for:)))
    #expect(BoardContentLayer.colorNames == ContenitoreColour.allCases.map(\.displayName))
    #expect(ContenitoreColour(canvasPreset: 7) == nil)
}

// MARK: - Classification (R-18)

@Test func classificationRefusesWhatTheSheetMustNotWrite() throws {
    let vocabulary = try bundledVocabulary()
    let inbox = [Tag("type-note")!, Tag("status-inbox")!]
    let topic = Tag("topic-guarnizioni")!

    #expect(ContenitoreClassification.classify(tags: inbox, topics: [], type: nil, vocabulary: vocabulary)
        == .failure(.noTopic))
    #expect(ContenitoreClassification.classify(tags: inbox, topics: [Tag("area-sales")!], type: nil, vocabulary: vocabulary)
        == .failure(.notATopic(Tag("area-sales")!)))
    #expect(ContenitoreClassification.classify(tags: inbox, topics: [topic], type: Tag("type-fattura")!, vocabulary: vocabulary)
        == .failure(.unknownType(Tag("type-fattura")!)))
    #expect(ContenitoreClassification.classify(
        tags: inbox + [Tag("type-invoice")!], topics: [topic], type: Tag("type-contract")!, vocabulary: vocabulary
    ) == .failure(.secondType([Tag("type-contract")!, Tag("type-invoice")!])))
    let many = (1...6).map { Tag("topic-t\($0)")! }
    guard case .failure(.tooManyTags) = ContenitoreClassification.classify(
        tags: inbox, topics: many + [topic], type: nil, vocabulary: vocabulary
    ) else {
        Issue.record("more than seven tags were accepted")
        return
    }
}

@MainActor
@Test func classificationRemovesInboxKeepsTypeNoteAndLintsClean() throws {
    let vault = try TemporaryVault()
    let session = lintingSession(root: vault.root, stateBase: vault.stateBase)
    let vocabulary = try bundledVocabulary()
    let result = ContenitoreClassification.classify(
        tags: [Tag("type-note")!, Tag("status-inbox")!], topics: [Tag("topic-guarnizioni")!],
        type: Tag("type-invoice")!, vocabulary: vocabulary
    )
    let tags = try result.get()
    #expect(tags.map(\.description) == ["type-invoice", "type-note", "topic-guarnizioni"])

    var document = NoteDocument.parse(ContenitoreScheda.render(
        date: importDay, fileName: "20260929 a.pdf", originalName: "a.pdf", sha256: sampleHash
    ))
    document.frontmatter.tags = tags
    let violations = session.violations(path: "Contenitore/2026/20260929 a.md", title: "20260929 a", text: document.serialized())
    #expect(violations.isEmpty, "\(violations)")
}

// MARK: - Container names (R-19, name rule)

@Test func aFourDigitContainerNameIsAYearName() {
    #expect(ContenitoreNaming.validateContainerName("2026") == .yearName)
    #expect(ContenitoreNaming.validateContainerName("Fornitori") == .valid)
    #expect(ContenitoreNaming.validateContainerName("Fornitori 2026") == .valid)
    #expect(ContenitoreNaming.validateContainerName("a/b") == .invalid([.containsForbiddenCharacter("/")]))
    #expect(ContenitoreNaming.isYearFolderName("2026"))
    #expect(!ContenitoreNaming.isYearFolderName("202"))
    #expect(ContenitoreNaming.yearFolder(for: importDay, in: "Contenitore/Fornitori") == "Contenitore/Fornitori/2026")
}

// MARK: - Settings (R-26, validation half)

@Test func theDropFolderIsRefusedAroundTheVaultHomeAndRoot() throws {
    let vault = try TemporaryVault()
    let home = vault.stateBase
    let root = vault.root

    #expect(ContenitoreSettings.validateDropFolder(root.path(percentEncoded: false), vaultRoot: root, home: home) == .vault)
    #expect(ContenitoreSettings.validateDropFolder(
        root.appending(path: "Drop").path(percentEncoded: false), vaultRoot: root, home: home
    ) == .insideVault)
    #expect(ContenitoreSettings.validateDropFolder(
        root.deletingLastPathComponent().path(percentEncoded: false), vaultRoot: root, home: home
    ) == .containsVault)
    #expect(ContenitoreSettings.validateDropFolder("~", vaultRoot: root, home: home) == .home)
    #expect(ContenitoreSettings.validateDropFolder("/", vaultRoot: root, home: home) == .filesystemRoot)
    #expect(ContenitoreSettings.validateDropFolder("Drop", vaultRoot: root, home: home) == .notAbsolute)
    #expect(ContenitoreSettings.validateDropFolder("~/Pergamenum Drop", vaultRoot: root, home: home) == nil)
}

@Test func theRootIsRefusedWhenEmptyHiddenOrTangledWithPratiche() {
    #expect(ContenitoreSettings.validateRoot("", praticheFolder: "01 Progetti") == .empty)
    #expect(ContenitoreSettings.validateRoot(".archivio", praticheFolder: "01 Progetti") == .hidden)
    #expect(ContenitoreSettings.validateRoot("01 Progetti/Contenitore", praticheFolder: "01 Progetti") == .insidePratiche)
    #expect(ContenitoreSettings.validateRoot("01 Progetti", praticheFolder: "01 Progetti") == .insidePratiche)
    #expect(ContenitoreSettings.validateRoot("Lavoro", praticheFolder: "Lavoro/Pratiche") == .containsPratiche)
    #expect(ContenitoreSettings.validateRoot("../fuori", praticheFolder: "01 Progetti") == .outsideVault)
    #expect(ContenitoreSettings.validateRoot("Contenitore", praticheFolder: "01 Progetti") == nil)
}

@Test func aTildeRelativeDropFolderRoundTripsUnchanged() throws {
    let settings = ContenitoreSettings(dropFolder: "~/Documenti da archiviare", root: "Archivio")
    let decoded = try JSONDecoder().decode(ContenitoreSettings.self, from: JSONEncoder().encode(settings))
    #expect(decoded == settings)
    #expect(try JSONDecoder().decode(ContenitoreSettings.self, from: Data("{}".utf8)) == .default)

    let home = URL(filePath: "/Users/qualcuno", directoryHint: .isDirectory)
    #expect(settings.resolvedDropFolder(home: home).path(percentEncoded: false).hasPrefix("/Users/qualcuno/Documenti da archiviare"))
    #expect(ContenitoreSettings.storedDropFolder(
        for: URL(filePath: "/Users/qualcuno/Documenti da archiviare", directoryHint: .isDirectory), home: home
    ) == "~/Documenti da archiviare")
}

// MARK: - Index facts

@MainActor
@Test func aSchedasFactsSurviveTheStoredRecordAndAReusedCache() async throws {
    let vault = try TemporaryVault()
    let text = ContenitoreScheda.settingColour(.verde, in: ContenitoreScheda.render(
        date: importDay, fileName: "20260929 a.pdf", originalName: "a.pdf", sha256: sampleHash
    ))
    try vault.write(text, to: "Contenitore/2026/20260929 a.md")
    try vault.write("---\ndate: 2026-09-29\ntags:\n  - type-note\n---\n", to: "Altra.md")

    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    let record = try #require(session.index.note(at: "Contenitore/2026/20260929 a.md"))
    let expected = ContenitoreFacts(
        fileName: "20260929 a.pdf", originalName: "a.pdf", sha256: sampleHash, colour: .verde, rawColour: "verde"
    )
    #expect(record.contenitore == expected)
    #expect(StoredRecord(record).record.contenitore == expected)
    #expect(session.index.note(at: "Altra.md")?.contenitore == nil)

    let relaunched = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await relaunched.rescan()
    await relaunched.rescan()
    #expect(relaunched.index.reusedFromCache > 0)
    #expect(relaunched.index.note(at: "Contenitore/2026/20260929 a.md")?.contenitore == expected)
    #expect(relaunched.index.schede(underRoot: "Contenitore").map(\.relativePath) == ["Contenitore/2026/20260929 a.md"])
    #expect(relaunched.index.schede(underRoot: "Altrove").isEmpty)
    #expect(relaunched.index.scheda(withSHA256: sampleHash.uppercased(), underRoot: "Contenitore/")?.relativePath
        == "Contenitore/2026/20260929 a.md")
}
