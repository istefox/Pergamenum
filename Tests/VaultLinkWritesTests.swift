import Foundation
import Testing
@testable import Pergamenum

// ADR-0084 §D3 («Collega» writes the link the person was shown) and §D4 (a path, and a way
// back), SPEC R-26 and R-27, plan docs/plans/note-workflow-n3.md Task 1.
//
// The session's three new doors, `planLinkMention`, `linkMention` and `removeStructuralLink`,
// and the changed label of `addStructuralLink`. The refusal of a second write is proved the way
// `VaultUnguardedWriteGuardTests` proves it for `addStructuralLink`: a symlink makes one file's
// own write stale the other's `expecting:`, deterministically, with no timing.

private func note(_ body: String = "Corpo.", aliases: [String] = []) -> String {
    let aliasLines = aliases.isEmpty ? "" : "aliases:\n" + aliases.map { "  - \($0)\n" }.joined()
    return "---\ndate: 2026-10-07\ntags:\n  - type-note\n\(aliasLines)---\n\n\(body)\n"
}

/// `text` carrying one structural link to `title`, built with the same pure writer the session uses.
private func linked(_ text: String, to title: String, selfTitle: String) throws -> String {
    try RelatedLink.add(target: title, reason: "motivo", to: text, selfTitle: selfTitle)
}

@MainActor
private func openSession(_ vault: borrowing TemporaryVault) async -> VaultSession {
    let session = VaultSession(
        root: vault.root,
        stateBase: vault.stateBase,
        bundledVocabulary: Bundle.pergamenumResources.url(forResource: "vocabolari", withExtension: "json")
    )
    await session.rescan()
    return session
}

private func onDisk(_ vault: borrowing TemporaryVault, _ path: String) throws -> String {
    try String(contentsOf: vault.root.appending(path: path), encoding: .utf8)
}

// MARK: - planLinkMention / linkMention

@MainActor
@Test func linkMentionWritesTheBareLinkOnceAndOnlyTheFirstMention() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "Curva.md")
    try vault.write(note("Prima la Curva e poi ancora Curva."), to: "Altra.md")
    let session = await openSession(vault)
    let before = try onDisk(vault, "Altra.md")
    let plan = try #require(session.planLinkMention(in: "Altra.md", to: "Curva"))

    let outcome = await session.linkMention(in: "Altra.md", to: "Curva", expecting: plan.hash)

    guard case .linked(let result) = outcome else {
        Issue.record("atteso .linked, ottenuto \(outcome)")
        return
    }
    #expect(result.path == "Altra.md")
    let after = try onDisk(vault, "Altra.md")
    #expect(result.text == after)
    #expect(after.contains("Prima la [[Curva]] e poi ancora Curva."), "solo la prima menzione diventa un link")
    #expect(after.components(separatedBy: "[[").count == 2, "un solo link scritto")
    #expect(after != before)
    #expect(session.problems.isEmpty)
}

@MainActor
@Test func linkMentionKeepsTheTextAsWrittenWhenItDiffersFromTheTitle() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "Curva.md")
    try vault.write(note("Parliamo della curva di sempre."), to: "Altra.md")
    let session = await openSession(vault)
    let plan = try #require(session.planLinkMention(in: "Altra.md", to: "Curva"))

    _ = await session.linkMention(in: "Altra.md", to: "Curva", expecting: plan.hash)

    #expect(try onDisk(vault, "Altra.md").contains("Parliamo della [[Curva|curva]] di sempre."))
}

@MainActor
@Test func linkMentionOfAnAliasWritesTheTitleWithTheAliasAsDisplay() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(aliases: ["Tornante"]), to: "Curva.md")
    try vault.write(note("Il Tornante è difficile."), to: "Altra.md")
    let session = await openSession(vault)
    let plan = try #require(session.planLinkMention(in: "Altra.md", to: "Curva"))

    _ = await session.linkMention(in: "Altra.md", to: "Curva", expecting: plan.hash)

    // `[[Tornante]]` alone would dangle: aliases are not resolved, only titles (ADR-0084 §D3).
    #expect(try onDisk(vault, "Altra.md").contains("Il [[Curva|Tornante]] è difficile."))
}

@MainActor
@Test func thePlannedAfterIsExactlyWhatLandsAndBeforeIsWhatWasThere() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "Curva.md")
    try vault.write(note("Una curva qui."), to: "Altra.md")
    let session = await openSession(vault)
    let onDiskBefore = try onDisk(vault, "Altra.md")

    let plan = try #require(session.planLinkMention(in: "Altra.md", to: "Curva"))
    #expect(plan.before == onDiskBefore)
    let readHash = try session.read("Altra.md").record.contentHash
    #expect(plan.hash == readHash, "l'hash è quello con cui addStructuralLink calcola il proprio expecting:")

    _ = await session.linkMention(in: "Altra.md", to: "Curva", expecting: plan.hash)

    #expect(try onDisk(vault, "Altra.md") == plan.after)
}

@MainActor
@Test func theNoteIsInTheBacklinksRightAfterTheWrite() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "Curva.md")
    try vault.write(note("Parla di Curva."), to: "Altra.md")
    let session = await openSession(vault)
    try #require(session.index.backlinks(toTitle: "Curva").isEmpty)
    let plan = try #require(session.planLinkMention(in: "Altra.md", to: "Curva"))

    _ = await session.linkMention(in: "Altra.md", to: "Curva", expecting: plan.hash)

    #expect(session.index.backlinks(toTitle: "Curva").map(\.relativePath) == ["Altra.md"])
}

@MainActor
@Test func aHashThatNoLongerMatchesIsMovedOnAndTheFileIsUntouched() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "Curva.md")
    try vault.write(note("Parla di Curva."), to: "Altra.md")
    let session = await openSession(vault)
    let plan = try #require(session.planLinkMention(in: "Altra.md", to: "Curva"))
    // Somebody else writes the note after the diff was shown.
    let changed = note("Parla di Curva.\n\nUna riga aggiunta da un altro scrittore.")
    try vault.write(changed, to: "Altra.md")

    let outcome = await session.linkMention(in: "Altra.md", to: "Curva", expecting: plan.hash)

    #expect(outcome == .movedOn)
    #expect(try onDisk(vault, "Altra.md") == changed, "nulla è stato scritto")
}

@MainActor
@Test func anInventedHashIsMovedOnToo() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "Curva.md")
    let text = note("Parla di Curva.")
    try vault.write(text, to: "Altra.md")
    let session = await openSession(vault)

    let outcome = await session.linkMention(in: "Altra.md", to: "Curva", expecting: "non-un-hash")

    #expect(outcome == .movedOn)
    #expect(try onDisk(vault, "Altra.md") == text)
}

@MainActor
@Test func noMentionLeftIsNoMentionAndNothingIsWritten() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "Curva.md")
    let text = note("Questa nota non nomina l'argomento.")
    try vault.write(text, to: "Altra.md")
    let session = await openSession(vault)
    let hash = try session.read("Altra.md").record.contentHash

    #expect(session.planLinkMention(in: "Altra.md", to: "Curva") == nil)
    let outcome = await session.linkMention(in: "Altra.md", to: "Curva", expecting: hash)

    #expect(outcome == .noMention)
    #expect(try onDisk(vault, "Altra.md") == text)
}

@MainActor
@Test func aNoteThatAlreadyLinksTheTitleHasNoMentionLeft() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "Curva.md")
    try vault.write(note("Già [[Curva]] qui."), to: "Altra.md")
    let session = await openSession(vault)

    #expect(session.planLinkMention(in: "Altra.md", to: "Curva") == nil)
}

// MARK: - addStructuralLink(toNoteAt:)

@MainActor
@Test func addStructuralLinkLinksTheNoteNamedByPathWhenTwoShareATitle() async throws {
    let vault = try TemporaryVault()
    try vault.write(note("Origine."), to: "Origine.md")
    try vault.write(note("Prima gemella."), to: "A/Gemello.md")
    try vault.write(note("Seconda gemella."), to: "B/Gemello.md")
    let session = await openSession(vault)
    let untouched = try onDisk(vault, "A/Gemello.md")

    let (created, written) = await session.addStructuralLink(
        from: "Origine.md", toNoteAt: "B/Gemello.md", reason: "usa i dati", reverseReason: "fornisce i dati"
    )

    #expect(created)
    #expect(written.map(\.path) == ["Origine.md", "B/Gemello.md"])
    #expect(try onDisk(vault, "B/Gemello.md").contains("- [[Origine]] — fornisce i dati"))
    #expect(try onDisk(vault, "A/Gemello.md") == untouched, "la prima corrispondenza per titolo non va mai scelta")
}

@MainActor
@Test func addStructuralLinkToAPathThatDoesNotExistIsANamedProblem() async throws {
    let vault = try TemporaryVault()
    let text = note("Origine.")
    try vault.write(text, to: "Origine.md")
    let session = await openSession(vault)

    let (created, written) = await session.addStructuralLink(
        from: "Origine.md", toNoteAt: "Cartella/Inesistente.md", reason: "a", reverseReason: "b"
    )

    #expect(!created)
    #expect(written.isEmpty)
    #expect(session.problems.contains { $0.contains("Cartella/Inesistente.md") })
    #expect(try onDisk(vault, "Origine.md") == text)
}

@MainActor
@Test func addStructuralLinkTakesAPathNotATitle() async throws {
    let vault = try TemporaryVault()
    let origine = note("Origine.")
    let destinazione = note("Destinazione.")
    try vault.write(origine, to: "Origine.md")
    try vault.write(destinazione, to: "Altrove/Destinazione.md")
    let session = await openSession(vault)

    // «Destinazione» is a title that exists and a path that does not: the label says path.
    let (created, written) = await session.addStructuralLink(
        from: "Origine.md", toNoteAt: "Destinazione", reason: "a", reverseReason: "b"
    )

    #expect(!created)
    #expect(written.isEmpty)
    #expect(try onDisk(vault, "Origine.md") == origine)
    #expect(try onDisk(vault, "Altrove/Destinazione.md") == destinazione)
}

// MARK: - removeStructuralLink

@MainActor
@Test func removeStructuralLinkTakesTheLinkOutOfBothNotes() async throws {
    let vault = try TemporaryVault()
    try vault.write(try linked(note("Origine."), to: "Destinazione", selfTitle: "Origine"), to: "Origine.md")
    try vault.write(try linked(note("Destinazione."), to: "Origine", selfTitle: "Destinazione"), to: "Destinazione.md")
    let session = await openSession(vault)
    try #require(session.index.backlinks(toTitle: "Destinazione").map(\.relativePath) == ["Origine.md"])

    let (removed, written) = await session.removeStructuralLink(from: "Origine.md", toNoteAt: "Destinazione.md")

    #expect(removed)
    #expect(written.map(\.path) == ["Origine.md", "Destinazione.md"])
    let source = try onDisk(vault, "Origine.md")
    let target = try onDisk(vault, "Destinazione.md")
    #expect(NoteDocument.parse(source).frontmatter.related.isEmpty)
    #expect(NoteDocument.parse(target).frontmatter.related.isEmpty)
    #expect(!source.contains("[[Destinazione]]"), "anche il punto elenco sotto «Note correlate» se ne va")
    #expect(!target.contains("[[Origine]]"))
    #expect(session.problems.isEmpty)
    #expect(session.index.backlinks(toTitle: "Destinazione").isEmpty)
    #expect(session.index.backlinks(toTitle: "Origine").isEmpty)
}

@MainActor
@Test func aSideHoldingNothingIsSkippedAndTheOtherIsStillWritten() async throws {
    let vault = try TemporaryVault()
    let holder = try linked(note("Origine."), to: "Destinazione", selfTitle: "Origine")
    let plain = note("Destinazione.")
    try vault.write(holder, to: "Origine.md")
    try vault.write(plain, to: "Destinazione.md")
    let session = await openSession(vault)

    let (removed, written) = await session.removeStructuralLink(from: "Origine.md", toNoteAt: "Destinazione.md")

    #expect(removed)
    #expect(written.map(\.path) == ["Origine.md"], "il lato che non tiene il legame non si scrive")
    let source = try onDisk(vault, "Origine.md")
    #expect(!source.contains("[[Destinazione]]"))
    #expect(try onDisk(vault, "Destinazione.md") == plain)
    #expect(session.problems.isEmpty)
}

@MainActor
@Test func theOtherSideAloneIsWrittenWhenOnlyTheTargetHoldsTheLink() async throws {
    let vault = try TemporaryVault()
    let plain = note("Origine.")
    try vault.write(plain, to: "Origine.md")
    try vault.write(try linked(note("Destinazione."), to: "Origine", selfTitle: "Destinazione"), to: "Destinazione.md")
    let session = await openSession(vault)

    let (removed, written) = await session.removeStructuralLink(from: "Origine.md", toNoteAt: "Destinazione.md")

    #expect(removed)
    #expect(written.map(\.path) == ["Destinazione.md"])
    #expect(try onDisk(vault, "Origine.md") == plain)
    let target = try onDisk(vault, "Destinazione.md")
    #expect(!target.contains("[[Origine]]"))
}

@MainActor
@Test func neitherSideHoldingTheLinkIsAProblemAndNothingIsWritten() async throws {
    let vault = try TemporaryVault()
    let origine = note("Origine.")
    let destinazione = note("Destinazione.")
    try vault.write(origine, to: "Origine.md")
    try vault.write(destinazione, to: "Destinazione.md")
    let session = await openSession(vault)

    let (removed, written) = await session.removeStructuralLink(from: "Origine.md", toNoteAt: "Destinazione.md")

    #expect(!removed)
    #expect(written.isEmpty)
    #expect(session.problems.contains { $0.contains("nessun legame strutturale fra «Origine» e «Destinazione»") })
    #expect(try onDisk(vault, "Origine.md") == origine)
    #expect(try onDisk(vault, "Destinazione.md") == destinazione)
}

@MainActor
@Test func aPathThatDoesNotExistRemovesNothingAndIsNamed() async throws {
    let vault = try TemporaryVault()
    let origine = try linked(note("Origine."), to: "Destinazione", selfTitle: "Origine")
    try vault.write(origine, to: "Origine.md")
    let session = await openSession(vault)

    let (removed, written) = await session.removeStructuralLink(from: "Origine.md", toNoteAt: "Assente.md")

    #expect(!removed)
    #expect(written.isEmpty)
    #expect(session.problems.contains { $0.contains("Assente.md") })
    #expect(try onDisk(vault, "Origine.md") == origine)
}

/// Deterministic, not raced (`VaultUnguardedWriteGuardTests`): `Destinazione.md` is a symlink onto
/// `Origine.md`'s bytes, and those bytes hold both links, so the first (guarded, legitimate)
/// write to the source is what makes the second write's `expecting:` stale.
@MainActor
@Test func theSecondWriteRefusedLeavesTheFirstLandedAndNamesBothNotes() async throws {
    let vault = try TemporaryVault()
    var shared = try linked(note("Corpo condiviso."), to: "Destinazione", selfTitle: "Terza")
    shared = try linked(shared, to: "Origine", selfTitle: "Terza")
    try vault.write(shared, to: "Origine.md")
    try FileManager.default.createSymbolicLink(
        at: vault.root.appending(path: "Destinazione.md"),
        withDestinationURL: vault.root.appending(path: "Origine.md")
    )
    let session = await openSession(vault)
    let problemsBefore = session.problems.count

    let (_, written) = await session.removeStructuralLink(from: "Origine.md", toNoteAt: "Destinazione.md")

    #expect(written.map(\.path) == ["Origine.md"], "`written` tiene la scrittura che è arrivata, non l'altra")
    let landed = try onDisk(vault, "Origine.md")
    #expect(!landed.contains("- [[Destinazione]]"), "la prima scrittura è arrivata")
    #expect(landed.contains("- [[Origine]]"), "il ritorno resta: la seconda è stata rifiutata")
    #expect(session.problems.count == problemsBefore + 1)
    let problem = try #require(session.problems.last)
    #expect(problem.contains("legame strutturale tolto a metà"))
    #expect(problem.contains("Origine"))
    #expect(problem.contains("Destinazione"))
}

// MARK: - (coverage) guards the plan and the doors state but no other test exercised

/// (coverage) `mentionPlan`'s own guard: a note never mentions itself, so its own title in its
/// own prose is no mention to link (the inspector's list skips it the same way).
@MainActor
@Test func aNoteNeverMentionsItselfSoNothingIsPlannedOrWritten() async throws {
    let vault = try TemporaryVault()
    let text = note("La Curva si descrive qui, nella nota Curva stessa.")
    try vault.write(text, to: "Curva.md")
    let session = await openSession(vault)
    let hash = try session.read("Curva.md").record.contentHash

    #expect(session.planLinkMention(in: "Curva.md", to: "Curva") == nil)
    let outcome = await session.linkMention(in: "Curva.md", to: "Curva", expecting: hash)

    #expect(outcome == .noMention)
    #expect(try onDisk(vault, "Curva.md") == text)
}

/// (coverage) `linkMention`'s first guard: a path that cannot be read is a named failure, not a
/// crash and not a write.
@MainActor
@Test func linkMentionOnAPathThatCannotBeReadFailsAndWritesNothing() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "Curva.md")
    let session = await openSession(vault)

    let outcome = await session.linkMention(in: "Assente.md", to: "Curva", expecting: "qualsiasi")

    guard case .failed(let reason) = outcome else {
        Issue.record("atteso .failed, ottenuto \(outcome)")
        return
    }
    #expect(reason.contains("Assente.md"))
    #expect(session.planLinkMention(in: "Assente.md", to: "Curva") == nil)
    #expect(!FileManager.default.fileExists(atPath: vault.root.appending(path: "Assente.md").path))
}

/// (coverage) `removeStructuralLink`'s self guard: a note has no structural link to itself.
@MainActor
@Test func removingTheStructuralLinkOfANoteFromItselfIsAProblemAndWritesNothing() async throws {
    let vault = try TemporaryVault()
    let origine = try linked(note("Origine."), to: "Destinazione", selfTitle: "Origine")
    try vault.write(origine, to: "Origine.md")
    try vault.write(note("Destinazione."), to: "Destinazione.md")
    let session = await openSession(vault)
    let problemsBefore = session.problems.count

    let (removed, written) = await session.removeStructuralLink(from: "Origine.md", toNoteAt: "Origine.md")

    #expect(!removed)
    #expect(written.isEmpty)
    #expect(session.problems.count == problemsBefore + 1)
    #expect(try onDisk(vault, "Origine.md") == origine)
}

/// R-26: only what the diff showed is written. The hash covers the note's bytes, the mention also
/// depends on the target's aliases in the index: an alias that goes between the diff and the
/// confirm would change which mention is linked, and that is `.movedOn` with nothing written.
@MainActor
@Test func anAliasChangeBetweenThePlanAndTheWriteIsMovedOnAndNothingIsWritten() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(aliases: ["Tornante"]), to: "Curva.md")
    let text = note("Il Tornante è difficile, la Curva no.")
    try vault.write(text, to: "Altra.md")
    let session = await openSession(vault)
    let plan = try #require(session.planLinkMention(in: "Altra.md", to: "Curva"))
    #expect(plan.after.contains("[[Curva|Tornante]]"))
    // The alias goes after the diff was shown; the note's own bytes do not move.
    try vault.write(note(), to: "Curva.md")
    await session.rescan()

    let outcome = await session.linkMention(in: "Altra.md", to: "Curva", expecting: plan.hash)

    #expect(outcome == .movedOn)
    #expect(try onDisk(vault, "Altra.md") == text)
}

// MARK: - Both ends of a structural link are indexed notes

/// A file that exists in the vault but is no note: both doors refuse it by name and write nothing,
/// on either end. `exists` alone accepts it, and the link would write frontmatter and a bullet
/// into a canvas or a settings file.
@MainActor
@Test(arguments: ["Lavagna.canvas", ".pergamenum/impostazioni.json"])
func bothStructuralLinkDoorsRefuseAFileThatIsNoNote(nonNote: String) async throws {
    let vault = try TemporaryVault()
    let origine = try linked(note("Origine."), to: "Destinazione", selfTitle: "Origine")
    let other = "{\"nodes\":[],\"edges\":[]}"
    try vault.write(origine, to: "Origine.md")
    try vault.write(other, to: nonNote)
    let session = await openSession(vault)
    try #require(session.index.note(at: nonNote) == nil)

    for (from, to) in [("Origine.md", nonNote), (nonNote, "Origine.md")] {
        let problemsBefore = session.problems.count

        let added = await session.addStructuralLink(from: from, toNoteAt: to, reason: "a", reverseReason: "b")
        #expect(!added.created)
        #expect(added.written.isEmpty)
        #expect(session.problems.count == problemsBefore + 1)
        #expect(session.problems.last?.contains("\(nonNote)") == true)
        #expect(session.problems.last?.contains("non è una nota del vault") == true)

        let removed = await session.removeStructuralLink(from: from, toNoteAt: to)
        #expect(!removed.removed)
        #expect(removed.written.isEmpty)
        #expect(session.problems.count == problemsBefore + 2)
        #expect(session.problems.last?.contains("\(nonNote)") == true)
        #expect(session.problems.last?.contains("non è una nota del vault") == true)
    }

    #expect(try onDisk(vault, nonNote) == other, "il file che non è una nota non è stato toccato")
    #expect(try onDisk(vault, "Origine.md") == origine)
}

// MARK: - mentionPlan names

/// The alias belongs to one note: with two notes sharing the title it is no unambiguous name for
/// either, so a homonym's alias is never read as a mention of the title (the inspector's one-subject
/// list does not use it either).
@MainActor
@Test func aHomonymsAliasIsNotAMentionOfTheTitleWhenTwoNotesShareIt() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(aliases: ["Compagno"]), to: "A/Collega.md")
    try vault.write(note(), to: "B/Collega.md")
    let text = note("Il Compagno di lavoro.")
    try vault.write(text, to: "Altra.md")
    let session = await openSession(vault)
    try #require(session.index.resolve(title: "Collega").count == 2)
    let hash = try session.read("Altra.md").record.contentHash

    #expect(session.planLinkMention(in: "Altra.md", to: "Collega") == nil)
    let outcome = await session.linkMention(in: "Altra.md", to: "Collega", expecting: hash)

    #expect(outcome == .noMention)
    #expect(try onDisk(vault, "Altra.md") == text)
}

/// The title itself still matches when two notes share it: only the aliases are dropped.
@MainActor
@Test func theTitleStillMatchesWhenTwoNotesShareItAndOnlyTheAliasesAreDropped() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(aliases: ["Compagno"]), to: "A/Collega.md")
    try vault.write(note(), to: "B/Collega.md")
    try vault.write(note("Il Compagno e il Collega."), to: "Altra.md")
    let session = await openSession(vault)

    let plan = try #require(session.planLinkMention(in: "Altra.md", to: "Collega"))

    #expect(plan.after.contains("il [[Collega]]"))
    #expect(!plan.after.contains("Compagno]]"))
}

// MARK: - A shown plan is remembered until it is consumed, replaced or forgotten

/// A cancelled diff forgets its plan, under the lowercased title the key folds to: the next
/// `linkMention` is then a caller that never planned, checked by the hash alone, and writes the
/// mention as it reads now rather than refusing against the abandoned diff.
@MainActor
@Test func aForgottenPlanLeavesTheNextLinkMentionCheckedByTheHashAlone() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(aliases: ["Tornante"]), to: "Curva.md")
    try vault.write(note("Il Tornante è difficile, la Curva no."), to: "Altra.md")
    let session = await openSession(vault)
    let plan = try #require(session.planLinkMention(in: "Altra.md", to: "Curva"))
    #expect(plan.after.contains("[[Curva|Tornante]]"))
    session.forgetLinkMentionPlan(in: "Altra.md", to: "curva")
    // The alias goes; with the plan still remembered this would be `.movedOn`.
    try vault.write(note(), to: "Curva.md")
    await session.rescan()

    let outcome = await session.linkMention(in: "Altra.md", to: "Curva", expecting: plan.hash)

    guard case .linked = outcome else {
        Issue.record("atteso .linked, ottenuto \(outcome)")
        return
    }
    let written = try onDisk(vault, "Altra.md")
    #expect(written.contains("la [[Curva]] no."))
    #expect(!written.contains("[[Curva|Tornante]]"))
}

/// Forgetting what was never planned is a no-op: the next `linkMention` still writes.
@MainActor
@Test func forgettingAPlanNobodyMadeChangesNothing() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "Curva.md")
    try vault.write(note("Si parla di Curva."), to: "Altra.md")
    let session = await openSession(vault)
    session.forgetLinkMentionPlan(in: "Altra.md", to: "Curva")
    let plan = try #require(session.planLinkMention(in: "Altra.md", to: "Curva"))
    session.forgetLinkMentionPlan(in: "Nessuna.md", to: "Curva")

    let outcome = await session.linkMention(in: "Altra.md", to: "Curva", expecting: plan.hash)

    guard case .linked = outcome else {
        Issue.record("atteso .linked, ottenuto \(outcome)")
        return
    }
    #expect(try onDisk(vault, "Altra.md") == plan.after)
}

// MARK: - «Collega» never scans or rewrites a file that is no note

/// `planLinkMention` and `linkMention` take the same refusal as the structural-link doors: a
/// `.canvas` or a `.pergamenum/*.json` naming the title is not scanned and not rewritten, and the
/// plan a caller was shown for it is dropped.
@MainActor
@Test(arguments: ["Lavagna.canvas", ".pergamenum/impostazioni.json"])
func theMentionDoorsRefuseAFileThatIsNoNote(nonNote: String) async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "Curva.md")
    let other = "{\"testo\": \"Si parla di Curva.\"}"
    try vault.write(other, to: nonNote)
    let session = await openSession(vault)
    try #require(session.index.note(at: nonNote) == nil)

    #expect(session.planLinkMention(in: nonNote, to: "Curva") == nil)
    let outcome = await session.linkMention(in: nonNote, to: "Curva", expecting: "qualsiasi")

    guard case .failed(let reason) = outcome else {
        Issue.record("atteso .failed, ottenuto \(outcome)")
        return
    }
    #expect(reason.contains("\(nonNote)"))
    #expect(reason.contains("non è una nota del vault"))
    #expect(try onDisk(vault, nonNote) == other)
}

// MARK: - «Scollega» refuses an ambiguous title

/// The removal is by title: with two notes sharing the target's title, the entry found in the source
/// might point at the other one, so nothing is written and the problem names the title.
@MainActor
@Test func removeStructuralLinkRefusesATargetTitleTwoNotesShare() async throws {
    let vault = try TemporaryVault()
    let origine = try linked(note("Origine."), to: "Destinazione", selfTitle: "Origine")
    try vault.write(origine, to: "Origine.md")
    try vault.write(note("Prima."), to: "A/Destinazione.md")
    let seconda = try linked(note("Seconda."), to: "Origine", selfTitle: "Destinazione")
    try vault.write(seconda, to: "B/Destinazione.md")
    let session = await openSession(vault)
    try #require(session.index.resolve(title: "Destinazione").count == 2)

    let (removed, written) = await session.removeStructuralLink(from: "Origine.md", toNoteAt: "A/Destinazione.md")

    #expect(!removed)
    #expect(written.isEmpty)
    #expect(session.problems.last?.contains("«Destinazione»") == true)
    #expect(session.problems.last?.contains("più note") == true)
    #expect(try onDisk(vault, "Origine.md") == origine, "il legame verso B/ non è stato tolto")
    #expect(try onDisk(vault, "B/Destinazione.md") == seconda)
}

/// The same refusal when the source's title is the shared one.
@MainActor
@Test func removeStructuralLinkRefusesASourceTitleTwoNotesShare() async throws {
    let vault = try TemporaryVault()
    let uno = try linked(note("Uno."), to: "Destinazione", selfTitle: "Origine")
    try vault.write(uno, to: "A/Origine.md")
    try vault.write(note("Due."), to: "B/Origine.md")
    let destinazione = try linked(note("Destinazione."), to: "Origine", selfTitle: "Destinazione")
    try vault.write(destinazione, to: "Destinazione.md")
    let session = await openSession(vault)

    let (removed, written) = await session.removeStructuralLink(from: "A/Origine.md", toNoteAt: "Destinazione.md")

    #expect(!removed)
    #expect(written.isEmpty)
    #expect(session.problems.last?.contains("«Origine»") == true)
    #expect(try onDisk(vault, "A/Origine.md") == uno)
    #expect(try onDisk(vault, "Destinazione.md") == destinazione)
}
