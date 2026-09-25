import Foundation
import Testing
@testable import Pergamenum

/// ADR-0057 §D8 (#496): five read-then-write sites now carry `expecting:`/`expectingAbsent:`
/// so a writer landing between their own internal read and their own internal write is
/// refused rather than silently overwritten - `append`, `linkFromDailyNote`,
/// `addStructuralLink`'s pair, `moveOnBoard`, and `captureTask`'s creation case.
///
/// **Coverage note, stated rather than left implicit.** Every one of these five reads and
/// writes inside a single `await`-bounded function with no test-only gate (unlike the diary's
/// `testOnlyWriteHook`, ADR-0057 §D9) - `VaultWriteOrderingTests.swift`'s own comment
/// ("needs a test-controlled gate at the actor boundary... a sleep or a race against
/// `Task.yield()`" is explicitly rejected as insufficient) is this codebase's own stated
/// position on exactly this shape of test, and no such gate was in scope to add here (only
/// `WorkspaceController`'s seams were authorized for this task). Two of the five refusals
/// below are still proven **deterministically**, without timing:
///   - `addStructuralLink`'s "half-written" case, via a symlink that makes the *target* path
///     resolve through the *source* path's bytes, so the source's own (legitimate, guarded)
///     write is what staled the target's `expecting:` hash - no race, no sleep.
///   - `captureTask`'s creation case, via a file that exists but fails to parse as UTF-8, so
///     `try? read` finds nothing (`existing == nil`, the same branch a genuine in-between
///     creation would take) while `expectingAbsent` still sees a file that is really there.
/// `append`, `linkFromDailyNote` and `moveOnBoard` below are covered for the happy path only
/// - each touches exactly one path with exactly one internal read, so neither trick applies,
/// and a genuine refusal test for them needs the gate this task did not add. Reported as a
/// gap, not fabricated with a flaky race.

private typealias VaultTag = Pergamenum.Tag

private func note(_ body: String = "Corpo.", tags: [String] = ["type-note"]) -> String {
    "---\ndate: 2026-09-20\ntags:\n" + tags.map { "  - \($0)\n" }.joined() + "---\n\n\(body)\n"
}

@MainActor
private func guardSession(_ vault: borrowing TemporaryVault) async -> VaultSession {
    let session = VaultSession(
        root: vault.root,
        stateBase: vault.stateBase,
        bundledVocabulary: Bundle.pergamenumResources.url(forResource: "vocabolari", withExtension: "json")
    )
    await session.rescan()
    return session
}

// MARK: - `append(text:to:)` (`VaultSession+Watching.swift`) - happy path

@MainActor
@Test func appendStillAppendsWhenNothingRacedIt() async throws {
    let vault = try TemporaryVault()
    try vault.write(note("Corpo iniziale."), to: "Giorno.md")
    let session = await guardSession(vault)

    let outcome = await session.append(text: "Riga catturata.", to: "Giorno.md")

    guard case .written(let result) = outcome else {
        Issue.record("expected .written, got \(outcome)")
        return
    }
    #expect(result.text.contains("Corpo iniziale."))
    #expect(result.text.contains("Riga catturata."))
    #expect(try session.read("Giorno.md").text == result.text)
}

// MARK: - `linkFromDailyNote` (`VaultSession+EventNotes.swift`, private) - happy path via `eventNote`

@MainActor
@Test func eventNoteCreationStillLinksFromTheDailyNoteWhenNothingRacedIt() async throws {
    let vault = try TemporaryVault()
    let session = await guardSession(vault)
    let day = CalendarDate(iso: "2026-09-20")!

    let created = try #require(await session.eventNote(for: "Sopralluogo", on: day))

    #expect(created.dailyNote != nil, "il collegamento dalla nota del giorno deve essere scritto")
    let daily = try session.read(created.dailyNote!.path).text
    #expect(daily.contains("Sopralluogo".lowercased()) || daily.contains("sopralluogo"))
    #expect(session.problems.isEmpty)
}

// MARK: - `addStructuralLink`'s pair (`VaultSession+Notes.swift`) - the half-written refusal

/// Deterministic, not raced: `Destinazione.md` is a symlink onto `Origine.md`'s own bytes, so
/// the *first* (guarded, legitimate) write to the source is exactly what makes the *second*
/// write's `expecting:` (captured from the target's read, before either write) stale - the
/// same shape a genuine interloper landing between the target's read and its own write would
/// produce, without timing.
@MainActor
@Test func addStructuralLinkLeavesTheFirstWriteLandedWhenTheSecondIsRefused() async throws {
    let vault = try TemporaryVault()
    let shared = note("Corpo condiviso.")
    try vault.write(shared, to: "Origine.md")
    try FileManager.default.createSymbolicLink(
        at: vault.root.appending(path: "Destinazione.md"),
        withDestinationURL: vault.root.appending(path: "Origine.md")
    )
    let session = await guardSession(vault)
    let problemsBefore = session.problems.count

    let succeeded = await session.addStructuralLink(
        from: "Origine.md", to: "Destinazione",
        reason: "usa i dati", reverseReason: "fornisce i dati"
    )

    #expect(!succeeded, "il secondo scrittore deve essere rifiutato, non l'intera operazione silenziosamente riuscita")
    // The first write landed: the source (read through its own real path) carries the link.
    #expect(try session.read("Origine.md").text.contains("- [[Destinazione]] — usa i dati"))
    // The refusal is named, not swallowed: both paths appear in the recorded problem.
    #expect(session.problems.count == problemsBefore + 1)
    let problem = try #require(session.problems.last)
    #expect(problem.contains("scritto a metà"))
    #expect(problem.contains("Origine.md"))
    #expect(problem.contains("Destinazione.md"))
}

// MARK: - `moveOnBoard` (`VaultSession+BoardDrop.swift`) - happy path

@MainActor
@Test func moveOnBoardStillWritesWhenNothingRacedIt() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(tags: ["type-note", "project-presse"]), to: "Carta.md")
    let session = VaultSession(
        root: vault.root, stateBase: vault.stateBase,
        bundledVocabulary: Bundle.pergamenumResources.url(forResource: "vocabolari", withExtension: "json")
    )
    await session.rescan()
    let tagFrom = try #require(VaultTag("project-presse"))
    let tagTo = try #require(VaultTag("project-forni"))

    let outcome = await session.moveOnBoard("Carta.md", from: tagFrom, to: tagTo)

    #expect(outcome.didWrite)
    #expect(outcome.problem == nil)
    #expect(try session.read("Carta.md").text.contains("  - project-forni"))
}

// MARK: - `captureTask`'s creation case (`VaultSession+Tasks.swift`) - the deterministic refusal

/// Deterministic, not raced: the destination already exists on disk but is not valid UTF-8, so
/// `try? read` inside `captureTask` finds nothing (`existing == nil`, the same branch a
/// genuine in-between creation takes) while the file is, in fact, there - which is exactly what
/// `expectingAbsent` (checked on existence, not readability, ADR-0057 §D3) is for.
@MainActor
@Test func captureTaskRefusesWhenTheDestinationExistsButWasNotFoundByTheCreationRead() async throws {
    let vault = try TemporaryVault()
    let path = VaultSession.TaskDestination.inboxPath
    let url = try vault.write("placeholder", to: path)
    // Not valid UTF-8: `NoteStore.read` throws `StoreError.notUTF8`, so `try? read` above is nil.
    try Data([0xFF, 0xFE, 0x00, 0xD8]).write(to: url)
    let session = await guardSession(vault)

    let result = await session.captureTask(VaultSession.TaskDraft(text: "Non deve sovrascrivere"))

    #expect(result == nil, "una creazione rifiutata non deve restituire un risultato scritto")
    #expect(session.problems.contains { $0.contains("cambiato nel frattempo") })
    // The existing (unreadable) bytes on disk are untouched - not overwritten by the template.
    #expect(try Data(contentsOf: url) == Data([0xFF, 0xFE, 0x00, 0xD8]))
}

@MainActor
@Test func captureTaskStillCreatesTheInboxWhenItIsGenuinelyAbsent() async throws {
    let vault = try TemporaryVault()
    let session = await guardSession(vault)

    let result = try #require(await session.captureTask(
        VaultSession.TaskDraft(text: "Prima cattura")
    ))

    #expect(result.path == VaultSession.TaskDestination.inboxPath)
    #expect(result.text.contains("- [ ] Prima cattura"))
}

// MARK: - `VaultAPI.appendToNote` (`Sources/Connector/VaultWrites.swift`) - happy path

/// `.stale`'s own branch (thrown with `VaultWriteRefusal.movedOn(path).description` rather
/// than folded into `session.problems.last` the way `.failed`/`.unchanged` are - the specific
/// defect the `VaultWrites.swift` diff names) needs the same unavailable internal race as
/// `append` above to produce a `.stale` outcome in the first place, so it is not pinned here.
/// What is pinned: the ordinary path through the new `switch` still returns a summary, not a
/// throw, exactly as the old `guard case .written` did.
@MainActor
@Test func appendToNoteStillSummarisesAnOrdinaryWrite() async throws {
    let vault = try TemporaryVault()
    try vault.write(note("Originale."), to: "N.md")
    let session = await guardSession(vault)
    VaultAPI.arm(session, command: "append_to_note", dryRun: false)

    let summary = try await VaultAPI.appendToNote(session, at: "N.md", text: "Aggiunta.")

    #expect(summary.path == "N.md")
    let onDisk = try String(contentsOf: vault.root.appending(path: "N.md"), encoding: .utf8)
    #expect(onDisk.contains("Originale."))
    #expect(onDisk.contains("Aggiunta."))
}
