import Foundation
import Testing
@testable import Pergamenum

// ADR-0084 §D3 and §D4, connector parity (SPEC R-26 and R-27, mandatory), plan
// docs/plans/note-workflow-n3.md Task 1.
//
// `VaultAPI.linkMention` and `VaultAPI.removeStructuralLink` are what `perg note link-mention`,
// `perg note unlink-related` and the two MCP tools call. A rehearsal returns the diff and changes
// no byte; a real write is applied and journaled; a half-done removal is a summary with a note,
// not a thrown error that hides the half that landed.

private func note(_ body: String, aliases: [String] = []) -> String {
    let aliasLines = aliases.isEmpty ? "" : "aliases:\n" + aliases.map { "  - \($0)\n" }.joined()
    return "---\ndate: 2026-10-07\ntags:\n  - type-note\n\(aliasLines)---\n\n\(body)\n"
}

private func linked(_ text: String, to title: String) throws -> String {
    try RelatedLink.add(target: title, reason: "motivo", to: text, selfTitle: "Terza")
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

private func bytes(_ vault: borrowing TemporaryVault, _ path: String) throws -> Data {
    try Data(contentsOf: vault.root.appending(path: path))
}

@MainActor
private func vaultWithAMention(_ vault: borrowing TemporaryVault) async throws -> VaultSession {
    try vault.write(note("Corpo.", aliases: ["Tornante"]), to: "Curva.md")
    try vault.write(note("Si parla di Curva e del tornante."), to: "Altra.md")
    return await openSession(vault)
}

@MainActor
private func vaultWithAStructuralPair(_ vault: borrowing TemporaryVault) async throws -> VaultSession {
    try vault.write(try linked(note("Origine."), to: "Destinazione"), to: "Origine.md")
    try vault.write(try linked(note("Destinazione."), to: "Origine"), to: "Destinazione.md")
    return await openSession(vault)
}

// MARK: - linkMention

@MainActor
@Test func aLinkMentionRehearsalReturnsTheDiffAndChangesNoByte() async throws {
    let vault = try TemporaryVault()
    let session = try await vaultWithAMention(vault)
    let before = try bytes(vault, "Altra.md")
    let journalBefore = session.journalOnDisk.entries().count

    VaultAPI.arm(session, command: "link_mention", dryRun: true)
    let summary = try await VaultAPI.linkMention(session, in: "Altra.md", title: "Curva")

    #expect(summary.path == "Altra.md", "il percorso è la nota scritta, il titolo è quello del bersaglio")
    #expect(!summary.applied)
    #expect(try #require(summary.diff).contains("+Si parla di [[Curva]] e del tornante."))
    #expect(try bytes(vault, "Altra.md") == before)
    #expect(session.journalOnDisk.entries().count == journalBefore, "una prova non lascia traccia nel journal")
}

@MainActor
@Test func aRealLinkMentionWritesTheLinkAndJournalsIt() async throws {
    let vault = try TemporaryVault()
    let session = try await vaultWithAMention(vault)
    let journalBefore = session.journalOnDisk.entries().count

    VaultAPI.arm(session, command: "link_mention", dryRun: false)
    let summary = try await VaultAPI.linkMention(session, in: "Altra.md", title: "Curva")

    #expect(summary.applied)
    #expect(summary.path == "Altra.md")
    let text = try String(contentsOf: vault.root.appending(path: "Altra.md"), encoding: .utf8)
    #expect(text.contains("Si parla di [[Curva]] e del tornante."))
    #expect(session.journalOnDisk.entries().count > journalBefore, "una scrittura vera si può annullare")
}

@MainActor
@Test func aLinkMentionOfAnAliasUsesTheTargetsTitle() async throws {
    let vault = try TemporaryVault()
    try vault.write(note("Corpo.", aliases: ["Tornante"]), to: "Curva.md")
    try vault.write(note("Solo il tornante qui."), to: "Altra.md")
    let session = await openSession(vault)

    VaultAPI.arm(session, command: "link_mention", dryRun: false)
    _ = try await VaultAPI.linkMention(session, in: "Altra.md", title: "Curva")

    let text = try String(contentsOf: vault.root.appending(path: "Altra.md"), encoding: .utf8)
    #expect(text.contains("Solo il [[Curva|tornante]] qui."))
}

@MainActor
@Test func aLinkMentionWithNothingToLinkThrowsTheNamedSentenceAndWritesNothing() async throws {
    let vault = try TemporaryVault()
    try vault.write(note("Corpo."), to: "Curva.md")
    try vault.write(note("Niente da collegare."), to: "Altra.md")
    let session = await openSession(vault)
    let before = try bytes(vault, "Altra.md")

    VaultAPI.arm(session, command: "link_mention", dryRun: false)
    let error = await #expect(throws: ConnectorError.self) {
        _ = try await VaultAPI.linkMention(session, in: "Altra.md", title: "Curva")
    }

    #expect(error?.description.contains("nessuna menzione non collegata di «Curva» in «Altra.md»") == true)
    #expect(try bytes(vault, "Altra.md") == before)
}

@MainActor
@Test func aLinkMentionOnANoteThatDoesNotExistThrows() async throws {
    let vault = try TemporaryVault()
    let session = try await vaultWithAMention(vault)

    VaultAPI.arm(session, command: "link_mention", dryRun: false)
    await #expect(throws: ConnectorError.self) {
        _ = try await VaultAPI.linkMention(session, in: "Assente.md", title: "Curva")
    }
}

// MARK: - removeStructuralLink

@MainActor
@Test func aRemoveStructuralLinkRehearsalReturnsBothDiffsAndChangesNoByte() async throws {
    let vault = try TemporaryVault()
    let session = try await vaultWithAStructuralPair(vault)
    let origine = try bytes(vault, "Origine.md")
    let destinazione = try bytes(vault, "Destinazione.md")

    VaultAPI.arm(session, command: "remove_structural_link", dryRun: true)
    let summaries = try await VaultAPI.removeStructuralLink(session, from: "Origine.md", to: "Destinazione.md")

    #expect(summaries.map(\.path) == ["Origine.md", "Destinazione.md"])
    #expect(summaries.allSatisfy { !$0.applied })
    #expect(summaries.allSatisfy { !($0.diff ?? "").isEmpty }, "una prova mostra entrambi i diff")
    #expect(try bytes(vault, "Origine.md") == origine)
    #expect(try bytes(vault, "Destinazione.md") == destinazione)
}

@MainActor
@Test func aRealRemoveStructuralLinkWritesBothNotesAndJournalsThem() async throws {
    let vault = try TemporaryVault()
    let session = try await vaultWithAStructuralPair(vault)
    let journalBefore = session.journalOnDisk.entries().count

    VaultAPI.arm(session, command: "remove_structural_link", dryRun: false)
    let summaries = try await VaultAPI.removeStructuralLink(session, from: "Origine.md", to: "Destinazione.md")

    #expect(summaries.map(\.path) == ["Origine.md", "Destinazione.md"], "un riepilogo per ogni file scritto")
    #expect(summaries.allSatisfy { $0.applied })
    let source = try String(contentsOf: vault.root.appending(path: "Origine.md"), encoding: .utf8)
    let target = try String(contentsOf: vault.root.appending(path: "Destinazione.md"), encoding: .utf8)
    #expect(NoteDocument.parse(source).frontmatter.related.isEmpty)
    #expect(NoteDocument.parse(target).frontmatter.related.isEmpty)
    #expect(session.journalOnDisk.entries().count >= journalBefore + 2)
}

@MainActor
@Test func aRemoveStructuralLinkWithNoLinkAnywhereThrowsAndWritesNothing() async throws {
    let vault = try TemporaryVault()
    try vault.write(note("Origine."), to: "Origine.md")
    try vault.write(note("Destinazione."), to: "Destinazione.md")
    let session = await openSession(vault)
    let origine = try bytes(vault, "Origine.md")

    VaultAPI.arm(session, command: "remove_structural_link", dryRun: false)
    let error = await #expect(throws: ConnectorError.self) {
        _ = try await VaultAPI.removeStructuralLink(session, from: "Origine.md", to: "Destinazione.md")
    }

    #expect(error?.description.contains("nessun legame strutturale") == true)
    #expect(try bytes(vault, "Origine.md") == origine)
}

@MainActor
@Test func aRemoveStructuralLinkTargetIsAPathNeverATitle() async throws {
    let vault = try TemporaryVault()
    let session = try await vaultWithAStructuralPair(vault)
    let origine = try bytes(vault, "Origine.md")

    VaultAPI.arm(session, command: "remove_structural_link", dryRun: false)
    await #expect(throws: ConnectorError.self) {
        _ = try await VaultAPI.removeStructuralLink(session, from: "Origine.md", to: "Destinazione")
    }

    #expect(try bytes(vault, "Origine.md") == origine, "un titolo non è un percorso: nessuna scrittura")
}

/// The symlink fixture of `VaultUnguardedWriteGuardTests`: the first write lands, the second is
/// refused, and the connector answers with what landed and says which side was refused.
@MainActor
@Test func aHalfDoneRemovalReturnsTheLandedSummaryWithANoteNamingTheRefusedSide() async throws {
    let vault = try TemporaryVault()
    let shared = try linked(try linked(note("Corpo condiviso."), to: "Destinazione"), to: "Origine")
    try vault.write(shared, to: "Origine.md")
    try FileManager.default.createSymbolicLink(
        at: vault.root.appending(path: "Destinazione.md"),
        withDestinationURL: vault.root.appending(path: "Origine.md")
    )
    let session = await openSession(vault)

    VaultAPI.arm(session, command: "remove_structural_link", dryRun: false)
    let summaries = try await VaultAPI.removeStructuralLink(session, from: "Origine.md", to: "Destinazione.md")

    #expect(summaries.map(\.path) == ["Origine.md"], "il riepilogo è quello della scrittura arrivata")
    #expect(summaries.first?.applied == true)
    let summaryNote = try #require(summaries.first?.note)
    #expect(summaryNote.contains("Destinazione"), "la nota nomina il lato rifiutato")
    #expect(summaryNote.contains("legame strutturale tolto a metà"))
}

// MARK: - (coverage) the argument and title guards of the two connector doors

/// (coverage) A caller that omits the path or the title asked wrong: a usage error, nothing written.
@MainActor
@Test func aLinkMentionWithoutAPathOrATitleIsAUsageErrorAndWritesNothing() async throws {
    let vault = try TemporaryVault()
    let session = try await vaultWithAMention(vault)
    let before = try bytes(vault, "Altra.md")

    VaultAPI.arm(session, command: "link_mention", dryRun: false)
    let noPath = await #expect(throws: ConnectorError.self) {
        _ = try await VaultAPI.linkMention(session, in: "", title: "Curva")
    }
    let noTitle = await #expect(throws: ConnectorError.self) {
        _ = try await VaultAPI.linkMention(session, in: "Altra.md", title: "")
    }

    #expect(noPath?.isUsage == true)
    #expect(noTitle?.isUsage == true)
    #expect(try bytes(vault, "Altra.md") == before)
}

/// (coverage) A title no note answers to would write a dangling link: refused before any write.
@MainActor
@Test func aLinkMentionOfATitleNoNoteAnswersToIsRefusedAndWritesNothing() async throws {
    let vault = try TemporaryVault()
    try vault.write(note("Si parla di Fantasma qui."), to: "Altra.md")
    let session = await openSession(vault)
    let before = try bytes(vault, "Altra.md")

    VaultAPI.arm(session, command: "link_mention", dryRun: false)
    let error = await #expect(throws: ConnectorError.self) {
        _ = try await VaultAPI.linkMention(session, in: "Altra.md", title: "Fantasma")
    }

    #expect(error?.description.contains("nessuna nota si chiama «Fantasma»") == true)
    #expect(try bytes(vault, "Altra.md") == before)
}

/// (coverage) The removal's own argument guard, and the self case reaching it as a thrown sentence.
@MainActor
@Test func aRemoveStructuralLinkWithoutBothPathsOrOnItselfThrowsAndWritesNothing() async throws {
    let vault = try TemporaryVault()
    let session = try await vaultWithAStructuralPair(vault)
    let origine = try bytes(vault, "Origine.md")

    VaultAPI.arm(session, command: "remove_structural_link", dryRun: false)
    let empty = await #expect(throws: ConnectorError.self) {
        _ = try await VaultAPI.removeStructuralLink(session, from: "Origine.md", to: "")
    }
    await #expect(throws: ConnectorError.self) {
        _ = try await VaultAPI.removeStructuralLink(session, from: "Origine.md", to: "Origine.md")
    }

    #expect(empty?.isUsage == true)
    #expect(try bytes(vault, "Origine.md") == origine)
}

/// A title of another case resolves, and the link written is the note's own title (ADR-0084 §D3).
@MainActor
@Test func aLinkMentionWithATitleOfAnotherCaseWritesTheNotesOwnTitle() async throws {
    let vault = try TemporaryVault()
    try vault.write(note("Corpo."), to: "Curva.md")
    try vault.write(note("Si parla di Curva qui."), to: "Altra.md")
    let session = await openSession(vault)

    VaultAPI.arm(session, command: "link_mention", dryRun: false)
    let summary = try await VaultAPI.linkMention(session, in: "Altra.md", title: "curva")

    #expect(summary.applied)
    let written = try String(decoding: bytes(vault, "Altra.md"), as: UTF8.self)
    #expect(written.contains("Si parla di [[Curva]] qui."))
    #expect(!written.contains("[[curva"))
}

// MARK: - a path that exists but is not a note is refused by both doors

/// Two vault files that are readable UTF-8 and name «Curva», but are not notes.
private let nonNotePaths = ["Lavagna.canvas", ".pergamenum/appunti.json"]

@MainActor
private func vaultWithNonNotes(_ vault: borrowing TemporaryVault) async throws -> VaultSession {
    try vault.write(note("Corpo."), to: "Curva.md")
    try vault.write(
        #"{"nodes":[{"id":"a","type":"text","text":"Si parla di Curva.","x":0,"y":0,"width":200,"height":80}],"#
            + #""edges":[]}"#,
        to: "Lavagna.canvas"
    )
    try vault.write(#"{"testo": "Si parla di Curva."}"#, to: ".pergamenum/appunti.json")
    return await openSession(vault)
}

@MainActor
@Test(arguments: nonNotePaths)
func aLinkMentionIntoAFileThatIsNotANoteIsRefusedAndWritesNothing(path: String) async throws {
    let vault = try TemporaryVault()
    let session = try await vaultWithNonNotes(vault)
    let before = try bytes(vault, path)

    VaultAPI.arm(session, command: "link_mention", dryRun: false)
    let error = await #expect(throws: ConnectorError.self) {
        _ = try await VaultAPI.linkMention(session, in: path, title: "Curva")
    }

    #expect(error?.description.contains("«\(path)» non è una nota del vault") == true)
    #expect(try bytes(vault, path) == before)
}

@MainActor
@Test(arguments: nonNotePaths)
func aRemoveStructuralLinkWithAFileThatIsNotANoteOnEitherSideIsRefusedAndWritesNothing(
    path: String
) async throws {
    let vault = try TemporaryVault()
    let session = try await vaultWithNonNotes(vault)
    let file = try bytes(vault, path)
    let curva = try bytes(vault, "Curva.md")

    VaultAPI.arm(session, command: "remove_structural_link", dryRun: false)
    let asSource = await #expect(throws: ConnectorError.self) {
        _ = try await VaultAPI.removeStructuralLink(session, from: path, to: "Curva.md")
    }
    let asTarget = await #expect(throws: ConnectorError.self) {
        _ = try await VaultAPI.removeStructuralLink(session, from: "Curva.md", to: path)
    }

    #expect(asSource?.description.contains("«\(path)» non è una nota del vault") == true)
    #expect(asTarget?.description.contains("«\(path)» non è una nota del vault") == true)
    #expect(try bytes(vault, path) == file)
    #expect(try bytes(vault, "Curva.md") == curva)
}

@MainActor
@Test func aRemoveStructuralLinkWhoseTitleTwoNotesShareIsRefusedAndWritesNothing() async throws {
    let vault = try TemporaryVault()
    let origine = try linked(note("Origine."), to: "Destinazione")
    try vault.write(origine, to: "Origine.md")
    try vault.write(note("Prima."), to: "A/Destinazione.md")
    try vault.write(note("Seconda."), to: "B/Destinazione.md")
    let session = await openSession(vault)

    VaultAPI.arm(session, command: "remove_structural_link", dryRun: false)
    let error = await #expect(throws: ConnectorError.self) {
        _ = try await VaultAPI.removeStructuralLink(session, from: "Origine.md", to: "A/Destinazione.md")
    }

    #expect(error?.description.contains("«Destinazione»") == true)
    #expect(error?.description.contains("più note") == true)
    #expect(try bytes(vault, "Origine.md") == Data(origine.utf8))
    #expect(try bytes(vault, "A/Destinazione.md") == Data(note("Prima.").utf8))
}

/// The connector refuses a path that is no note in the session's own words.
@MainActor
@Test func theConnectorRefusesAMissingPathWithTheSessionsSentence() async throws {
    let vault = try TemporaryVault()
    let session = try await vaultWithAMention(vault)

    VaultAPI.arm(session, command: "link_mention", dryRun: false)
    let error = await #expect(throws: ConnectorError.self) {
        _ = try await VaultAPI.linkMention(session, in: "Assente.md", title: "Curva")
    }

    #expect(error?.description == session.linkEndRefusal("Assente.md"))
    #expect(error?.description == "nessuna nota in «Assente.md»")
}

/// A title two notes share is refused by name: the connector would otherwise write the spelling of
/// whichever note the index answered first, and a dry run writes nothing either.
@MainActor
@Test(arguments: [true, false])
func aLinkMentionOfATitleTwoNotesShareIsRefusedByNameAndWritesNothing(dryRun: Bool) async throws {
    let vault = try TemporaryVault()
    try vault.write(note("Prima."), to: "A/Curva.md")
    try vault.write(note("Seconda."), to: "B/CURVA.md")
    try vault.write(note("Si parla di Curva qui."), to: "Altra.md")
    let session = await openSession(vault)
    let before = try bytes(vault, "Altra.md")
    let journalBefore = session.journalOnDisk.entries().count

    VaultAPI.arm(session, command: "link_mention", dryRun: dryRun)
    let error = await #expect(throws: ConnectorError.self) {
        _ = try await VaultAPI.linkMention(session, in: "Altra.md", title: "curva")
    }

    #expect(error?.description.contains("«curva»") == true)
    #expect(error?.description.contains("più note") == true)
    #expect(error?.isUsage == false)
    #expect(try bytes(vault, "Altra.md") == before)
    #expect(session.journalOnDisk.entries().count == journalBefore)
}
