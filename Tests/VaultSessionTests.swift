import Foundation
import Testing
@testable import Pergamenum

/// `VaultSession` driven with no `VaultController` anywhere in sight.
///
/// This is the point of ADR-0007 §D3 stated as a test. The rest of the suite reaches
/// the session through the facade, which proves the app still works but not the thing
/// the connector depends on: that a process with no SwiftUI, no editor and no observed
/// state can open a vault and do the whole job. `perg` and `pergamenum-mcp` will hold
/// exactly what these tests hold.
@MainActor
private func openSession(_ root: URL) async -> VaultSession {
    let session = VaultSession(
        root: root,
        bundledVocabulary: Bundle.pergamenumResources.url(forResource: "vocabolari", withExtension: "json")
    )
    await session.rescan()
    return session
}

// MARK: - Notes

@MainActor
@Test func aSessionCreatesAConformantNoteWithNoControllerInvolved() async throws {
    let vault = try TemporaryVault()
    let session = await openSession(vault.root)

    let path = try session.createNote(
        title: "Nota nuova",
        in: "01 Progetti",
        date: CalendarDate(iso: "2026-08-11")!,
        topics: [Tag("topic-acoustics")!]
    ).path
    #expect(path == "01 Progetti/Nota nuova.md")

    let text = try String(contentsOf: vault.root.appending(path: path), encoding: .utf8)
    #expect(text == "---\ndate: 2026-08-11\ntags:\n  - type-note\n  - topic-acoustics\n---\n\n")

    // The note it just wrote must satisfy the rules it will later be judged by, and
    // the linter has to reach the same verdict without an open editor to ask about.
    let violations = try #require(session.violations(forRecordAt: path))
    #expect(violations.isEmpty, "\(violations)")

    // The index knows about it without a rescan: the write path updates it.
    #expect(session.index.note(at: path) != nil)
}

@MainActor
@Test func aSessionRefusesANonConformantTitleRatherThanFixingIt() async throws {
    let vault = try TemporaryVault()
    let session = await openSession(vault.root)

    #expect(throws: VaultSession.CreationError.self) {
        try session.createNote(title: "Nota/con/slash", date: CalendarDate(iso: "2026-08-11")!)
    }
    #expect(throws: VaultSession.CreationError.self) {
        try session.createNote(title: "Relazione v2", date: CalendarDate(iso: "2026-08-11")!)
    }
}

@MainActor
@Test func aSessionRenamesANoteAndTheLinksPointingAtIt() async throws {
    let vault = try TemporaryVault()
    try vault.write("---\ndate: 2026-08-11\ntags:\n  - type-note\n---\n\nVedi [[Beta]].\n", to: "Alfa.md")
    try vault.write("---\ndate: 2026-08-11\ntags:\n  - type-note\n---\n\n", to: "Beta.md")
    let session = await openSession(vault.root)

    let outcome = try session.renameNote(at: "Beta.md", to: "Gamma")
    #expect(outcome.newPath == "Gamma.md")

    let alfa = try String(contentsOf: vault.root.appending(path: "Alfa.md"), encoding: .utf8)
    #expect(alfa.contains("[[Gamma]]"), "il link non ha seguito la nota: \(alfa)")
}

// MARK: - Tasks

@MainActor
@Test func aSessionCapturesATaskIntoAnInboxItCreates() async throws {
    let vault = try TemporaryVault()
    let session = await openSession(vault.root)

    let result = try #require(session.captureTask(
        VaultSession.TaskDraft(text: "Consegnare la relazione", due: CalendarDate(iso: "2026-08-20"))
    ))
    #expect(result.path == VaultSession.TaskDestination.inboxPath)
    #expect(result.text.contains("- [ ] Consegnare la relazione !2026-08-20"))

    // The inbox is born with a frontmatter block rather than as a bare list, and
    // carries the tags `NoteCategory.capture` calls for (tag.md 5.1).
    #expect(result.text.hasPrefix("---\n"))
    #expect(result.text.contains("- status-inbox"))

    // And the linter agrees. This assertion is the point of #30: the app used to write a
    // file its own conformance pane flagged, because the `topic-*` exemption of SPEC §4.7
    // was reachable only when a note was created and never when it was judged.
    let violations = try #require(session.violations(forRecordAt: result.path))
    #expect(violations.isEmpty, "la nota inbox che l'app scrive da sé non è conforme: \(violations)")
}

@MainActor
@Test func aSessionCompletesATaskByRewritingItsLine() async throws {
    let vault = try TemporaryVault()
    try vault.write("---\ndate: 2026-08-11\ntags:\n  - type-note\n---\n\n- [ ] Alfa\n", to: "T.md")
    let session = await openSession(vault.root)

    let task = try #require(session.index.allTasks.first)
    guard case .written(let result) = session.apply(.state(.done), to: task) else {
        Issue.record("la scrittura non è avvenuta: \(session.problems)")
        return
    }
    #expect(result.text.contains("- [x] Alfa"))

    // On disk, not only in the returned value: the file is the truth (SPEC §3).
    let onDisk = try String(contentsOf: vault.root.appending(path: "T.md"), encoding: .utf8)
    #expect(onDisk.contains("- [x] Alfa"))
}

@MainActor
@Test func aSessionReportsAStaleLineRatherThanRewritingWhateverSitsThere() async throws {
    let vault = try TemporaryVault()
    try vault.write("---\ndate: 2026-08-11\ntags:\n  - type-note\n---\n\n- [ ] Alfa\n", to: "T.md")
    let session = await openSession(vault.root)
    let task = try #require(session.index.allTasks.first)

    // Someone else edits the file: the line the index remembers is now a different one.
    try vault.write("---\ndate: 2026-08-11\ntags:\n  - type-note\n---\n\n- [ ] Beta\n", to: "T.md")

    guard case .stale = session.apply(.state(.done), to: task) else {
        Issue.record("una riga cambiata sotto deve dare .stale, non una riscrittura")
        return
    }
    // Nothing was written: rewriting by line number alone would have completed Beta.
    let onDisk = try String(contentsOf: vault.root.appending(path: "T.md"), encoding: .utf8)
    #expect(onDisk.contains("- [ ] Beta"))
}

// MARK: - The day

@MainActor
@Test func aSessionBlocksOutADayCreatingTheDailyNote() async throws {
    let vault = try TemporaryVault()
    let session = await openSession(vault.root)
    let day = CalendarDate(iso: "2026-08-11")!

    let placed = try #require(session.addTimeBlock(title: "Collaudo", on: day, startMinutes: 9 * 60))
    #expect(placed.block.startMinutes == 9 * 60)

    // Read back through the parser rather than by string matching, so the test says
    // the block round-trips rather than that some text appeared.
    #expect(session.timeBlocks(on: day).map(\.title) == ["Collaudo"])

    // A second block at the same hour moves on rather than overlapping.
    let second = try #require(session.addTimeBlock(title: "Riunione", on: day, startMinutes: 9 * 60))
    #expect(second.block.startMinutes > placed.block.startMinutes)
}

@MainActor
@Test func aSessionLeavesADayAloneWhenThereIsNothingToWrite() async throws {
    let vault = try TemporaryVault()
    let session = await openSession(vault.root)
    let day = CalendarDate(iso: "2026-08-11")!

    // No blocks and no note: `unchanged` rather than a file created for nothing.
    guard case .unchanged = session.setTimeBlocks([], on: day) else {
        Issue.record("un giorno vuoto senza nota non deve creare un file")
        return
    }
    #expect(!session.exists(session.dailyNotePath(for: day)))
}

@MainActor
@Test func aSessionWritesAndReadsBackADiaryDay() async throws {
    let vault = try TemporaryVault()
    let session = await openSession(vault.root)
    let day = CalendarDate(iso: "2026-08-11")!

    let entry = DiaryEntry(startMinutes: 10 * 60, durationMinutes: 45, title: "Sopralluogo")
    guard case .written = session.writeDiary(prose: session.emptyDiaryNote(for: day), entries: [entry], on: day) else {
        Issue.record("il diario non è stato scritto: \(session.problems)")
        return
    }

    let read = try #require(session.readDiary(on: day))
    #expect(read.entries.map(\.title) == ["Sopralluogo"])
    #expect(read.entries.map(\.startMinutes) == [10 * 60])
}

// MARK: - Search and the watcher

@MainActor
@Test func aSessionSearchesTheVaultByWordAndByTag() async throws {
    let vault = try TemporaryVault()
    try vault.write(
        "---\ndate: 2026-08-11\ntags:\n  - type-note\n  - topic-acoustics\n---\n\nLa curva di trasmissibilità.\n",
        to: "Alfa.md"
    )
    try vault.write("---\ndate: 2026-08-11\ntags:\n  - type-note\n---\n\nAltro.\n", to: "Beta.md")
    let session = await openSession(vault.root)

    #expect(session.search(SearchQuery("trasmissibilità")).map(\.path) == ["Alfa.md"])
    #expect(session.search(SearchQuery("tag:topic-acoustics")).map(\.path) == ["Alfa.md"])
    // The excerpt is the line the word is on, which is what makes a result readable.
    #expect(session.search(SearchQuery("trasmissibilità")).first?.excerpt == "La curva di trasmissibilità.")
}

@MainActor
@Test func aSessionAnswersTheOperatorsANoteCannotAnswerAboutItself() async throws {
    let vault = try TemporaryVault()
    let front = "---\ndate: 2026-08-11\ntags:\n  - type-note\n---\n\n"
    try vault.write(front + "Cita [[Beta]].\n", to: "Alfa.md")
    try vault.write(front + "Nessun link.\n", to: "Beta.md")
    try vault.write(front + "Sola.\n", to: "Gamma.md")
    let session = await openSession(vault.root)

    // `is:starred` reads the store of D6, `linked:` and `orphan:` the link graph. None
    // of the three is in the file the search reads, which is why they are applied
    // before it is opened rather than inside the match.
    session.setStar(true, for: "Beta.md")
    #expect(session.search(SearchQuery("is:starred")).map(\.path) == ["Beta.md"])
    #expect(session.search(SearchQuery("linked:Beta")).map(\.path) == ["Alfa.md"])
    #expect(session.search(SearchQuery("orphan:")).map(\.path) == ["Gamma.md"])
    // They narrow together with everything else.
    #expect(session.search(SearchQuery("is:starred orphan:")).isEmpty)
    #expect(session.search(SearchQuery("orphan: sola")).map(\.path) == ["Gamma.md"])
}

@MainActor
@Test func aSessionSearchesByRegularExpression() async throws {
    let vault = try TemporaryVault()
    let front = "---\ndate: 2026-08-11\ntags:\n  - type-note\n---\n\n"
    try vault.write(front + "# Titolo\n\n## Sezione\n\nCorpo.\n", to: "Alfa.md")
    try vault.write(front + "Solo prosa.\n", to: "Beta.md")
    let session = await openSession(vault.root)

    let hits = session.search(SearchQuery("regex:^##\\s"))
    #expect(hits.map(\.path) == ["Alfa.md"])
    // The excerpt is the line the pattern hit, as it is for a word.
    #expect(hits.first?.excerpt == "## Sezione")
    // A pattern that does not compile returns nothing rather than everything.
    #expect(session.search(SearchQuery("regex:[aperta")).isEmpty)
}

@MainActor
@Test func aSessionFindsTheNotesThatNameOneWithoutLinkingIt() async throws {
    let vault = try TemporaryVault()
    let front = "---\ndate: 2026-08-11\ntags:\n  - type-note\naliases:\n  - Curva\n---\n\n"
    try vault.write(front + "La mia curva.\n", to: "Curva di trasmissibilità.md")
    try vault.write("---\ndate: 2026-08-11\ntags:\n  - type-note\n---\n\nVedi [[Curva di trasmissibilità]].\n",
                    to: "Linkante.md")
    try vault.write("---\ndate: 2026-08-11\ntags:\n  - type-note\n---\n\nRifare la curva di trasmissibilità.\n",
                    to: "Menzionante.md")
    try vault.write("---\ndate: 2026-08-11\ntags:\n  - type-note\n---\n\nParla della Curva a modo suo.\n",
                    to: "PerAlias.md")
    try vault.write("---\ndate: 2026-08-11\ntags:\n  - type-note\n---\n\nCurvatura del profilo.\n",
                    to: "Estranea.md")
    let session = await openSession(vault.root)

    let mentions = session.unlinkedMentions(for: "Curva di trasmissibilità.md")

    // The note that links is already a backlink; the note that only shares a prefix is not a
    // mention; the note that uses the alias is one, because an alias never resolves a link
    // and so never produces the backlink that would remove it from here (F-07).
    #expect(mentions.map(\.path).sorted() == ["Menzionante.md", "PerAlias.md"])
    #expect(mentions.first(where: { $0.path == "Menzionante.md" })?.excerpt
        == "Rifare la curva di trasmissibilità.")
    // The note never mentions itself, whatever its own body says.
    #expect(!mentions.contains { $0.path == "Curva di trasmissibilità.md" })
}

@MainActor
@Test func aSessionKnowsItsOwnWriteFromSomebodyElsesEdit() async throws {
    let vault = try TemporaryVault()
    try vault.write("---\ndate: 2026-08-11\ntags:\n  - type-note\n---\n\nUno.\n", to: "N.md")
    let session = await openSession(vault.root)

    // Its own write comes back from the watcher and is not reported: the caller
    // already knows about it, and reporting it would raise a conflict against itself.
    try session.write("---\ndate: 2026-08-11\ntags:\n  - type-note\n---\n\nDue.\n", to: "N.md")
    #expect(session.reconcile(["N.md"]).isEmpty)

    // A second writer in the vault - which ADR-0007 puts there - is reported.
    try vault.write("---\ndate: 2026-08-11\ntags:\n  - type-note\n---\n\nTre.\n", to: "N.md")
    let changes = session.reconcile(["N.md"])
    #expect(changes.map(\.path) == ["N.md"])
    #expect(changes.first?.text.contains("Tre.") == true)

    // A file that went away leaves the index rather than lingering in it.
    try FileManager.default.removeItem(at: vault.root.appending(path: "N.md"))
    #expect(session.reconcile(["N.md"]).isEmpty)
    #expect(session.index.note(at: "N.md") == nil)
}
