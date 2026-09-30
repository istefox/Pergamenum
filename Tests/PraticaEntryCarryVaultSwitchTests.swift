import Foundation
import Testing
@testable import Pergamenum

// ADR-0076 §D6 (PG-338), plan docs/plans/pratiche-message-anchored-entries.md, Task 5: the
// forward carry's vault guard. `PraticaEntryCarry.step` asks `vault.session === session` before
// its read and again after the test hook, with no `await` between that check and the write: a
// vault switched during a step leaves `session` writing into a vault no longer on screen, so the
// step refuses and the move reports where the entries are. The hook is where the switch happens,
// and the other vault holds a same-named `pratica.md` at both paths, the file a careless write
// would reach. On `PraticaEntryCarryTests.swift`'s `CarryHarness`; its own file because that one
// is at SwiftLint's file_length limit. The undo's vault guard is in `PraticaEntryCarryBackTests`.

/// Every carry step the hook saw, so a test can prove which ran.
@MainActor
private final class PhaseLog {
    var phases: [PraticaEntryCarry.Phase] = []
}

@MainActor
@Suite(.serialized) struct PraticaEntryCarryVaultSwitchTests {
    private typealias Rig = CarryHarness

    private static let otherBody = Rig.frontmatter + "\nAltro vault.\n"

    /// A second vault with a `pratica.md` at both of the harness's paths.
    private static func otherVault() throws -> TemporaryVault {
        let other = try TemporaryVault()
        try Rig.write(otherBody, to: Rig.sourceNote, under: other.root)
        try Rig.write(otherBody, to: Rig.destinationNote, under: other.root)
        return other
    }

    private static func bytes(_ relativePath: String, under root: URL) throws -> Data {
        try Data(contentsOf: root.appending(path: relativePath, directoryHint: .notDirectory))
    }

    private static func anchoredCount(in text: String) -> Int {
        PraticaEntryEdit.blocks(anchoredTo: Rig.messageID, in: text).count
    }

    /// The switch lands between the append's read and its write: nothing is appended anywhere,
    /// the removal never starts (a refused append ends the carry), the entries stay in the
    /// source and the move says so.
    @Test func aVaultSwitchBeforeTheAppendCarriesNothingAndWritesNoVault() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        let other = try Self.otherVault()
        let controller = harness.controller
        let log = PhaseLog()
        harness.pratiche.testOnlyCarryHook = { phase in
            log.phases.append(phase)
            guard phase == .willAppend(notePath: Rig.destinationNote) else { return }
            await controller.open(other.root)
        }
        let destinationBody = Rig.body(try harness.text(Rig.destinationNote))

        try await harness.move()

        try #require(controller.root == other.root, "the hook switched the vault")
        #expect(log.phases == [.willAppend(notePath: Rig.destinationNote)], "no removal after a refused append")
        for notePath in [Rig.sourceNote, Rig.destinationNote] {
            #expect(try Self.bytes(notePath, under: other.root) == Data(Self.otherBody.utf8), "\(notePath)")
        }
        #expect(harness.exists("\(Rig.destination)/\(Rig.messageFile)"), "the message moved")
        #expect(Self.anchoredCount(in: try harness.text(Rig.sourceNote)) == 2)
        #expect(Self.anchoredCount(in: try harness.text(Rig.destinationNote)) == 0)
        #expect(Rig.body(try harness.text(Rig.destinationNote)) == destinationBody)
        #expect(harness.pratiche.problem == PraticaEntryCarry.sentence(
            for: .notCarried, source: Rig.source, destination: Rig.destination
        ))
        controller.close()
    }

    /// The switch lands between the removal's read and its write: the append already landed in
    /// the original vault, the removal refuses, the blocks are in both of its files and the
    /// other vault is untouched.
    @Test func aVaultSwitchBeforeTheRemovalLeavesTheBlocksInBothFilesAndWritesNoOtherVault() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        let other = try Self.otherVault()
        let controller = harness.controller
        harness.pratiche.testOnlyCarryHook = { phase in
            guard phase == .willRemove(notePath: Rig.sourceNote) else { return }
            await controller.open(other.root)
        }

        try await harness.move()

        try #require(controller.root == other.root, "the hook switched the vault")
        for notePath in [Rig.sourceNote, Rig.destinationNote] {
            #expect(try Self.bytes(notePath, under: other.root) == Data(Self.otherBody.utf8), "\(notePath)")
            #expect(Self.anchoredCount(in: try harness.text(notePath)) == 2, "\(notePath)")
        }
        #expect(harness.exists("\(Rig.destination)/\(Rig.messageFile)"), "the message moved")
        let problem = try #require(harness.pratiche.problem)
        #expect(problem == PraticaEntryCarry.sentence(
            for: .appendedOnly(count: 2, missing: 2), source: Rig.source, destination: Rig.destination
        ), "\(problem)")
        #expect(problem.contains("sia in «\(Rig.sourceNote)» sia in «\(Rig.destinationNote)»"), "\(problem)")
        controller.close()
    }

    /// The switch lands before a step begins (the move's dossier writes are suspensions too):
    /// the entry check refuses before the step reads or reaches the hook, so no step runs,
    /// neither vault is written and the carry is `.notCarried`.
    @Test func aCarryStartedAfterAVaultSwitchRunsNoStepAndWritesNoVault() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        let controller = harness.controller
        let movedSession = try #require(controller.session)
        let blocks = PraticaEntryEdit.blocks(anchoredTo: Rig.messageID, in: try harness.text(Rig.sourceNote))
        try #require(blocks.count == 2)
        let sourceBefore = try Self.bytes(Rig.sourceNote, under: vault.root)
        let destinationBefore = try Self.bytes(Rig.destinationNote, under: vault.root)
        let other = try Self.otherVault()
        await controller.open(other.root)
        try #require(controller.session !== movedSession)
        let log = PhaseLog()
        harness.pratiche.testOnlyCarryHook = { log.phases.append($0) }

        let outcome = await PraticaEntryCarry(pratiche: harness.pratiche, vault: controller).carry(
            PraticaEntryCarry.Transfer(
                blocks: blocks, messageID: Rig.messageID, source: Rig.source, destination: Rig.destination
            ),
            in: movedSession
        )

        #expect(outcome == .notCarried)
        #expect(log.phases.isEmpty, "no step ran in a session no longer current")
        #expect(try Self.bytes(Rig.sourceNote, under: vault.root) == sourceBefore)
        #expect(try Self.bytes(Rig.destinationNote, under: vault.root) == destinationBefore)
        for notePath in [Rig.sourceNote, Rig.destinationNote] {
            #expect(try Self.bytes(notePath, under: other.root) == Data(Self.otherBody.utf8), "\(notePath)")
        }
        controller.close()
    }
}
