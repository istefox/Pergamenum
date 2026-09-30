import Foundation
import Testing
@testable import Pergamenum

// ADR-0076 §D6 (PG-338), plan docs/plans/pratiche-message-anchored-entries.md, Task 5: the undo
// of «Sposta in…», `PraticaEntryCarry.carryBack`, branch by branch. The move itself is in
// `PraticaEntryCarryTests.swift`, whose `CarryHarness` this suite shares; its own file because
// that one had reached SwiftLint's file_length and type_body_length limits.

/// Every carry step the hook saw, so a test can prove that none ran.
@MainActor
private final class PhaseLog {
    var phases: [PraticaEntryCarry.Phase] = []
}

@MainActor
@Suite(.serialized) struct PraticaEntryCarryBackTests {
    private typealias Rig = CarryHarness

    private static func anchoredCount(in text: String) -> Int {
        PraticaEntryEdit.blocks(anchoredTo: Rig.messageID, in: text).count
    }

    // MARK: - Per branch

    /// `.appendedOnly` after a PARTIAL removal: between the move's append and its removal the
    /// first block was edited in the source, so the removal took the second one only. The undo
    /// puts back in the source what the source no longer holds before it empties the destination:
    /// the second block returns, and so does the first block's old version, beside the edit
    /// (§D6's accepted cost). No text is in neither file.
    @Test func aPartialRemovalsUndoPutsBackWhatTheSourceLostBeforeEmptyingTheDestination() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        let root = vault.root
        let edited = Rig.first.replacingOccurrences(of: "Prima voce collegata.", with: "Prima voce, corretta a mano.")
        harness.pratiche.testOnlyCarryHook = { phase in
            guard phase == .willAppend(notePath: Rig.destinationNote),
                  let text = try? String(contentsOf: root.appending(path: Rig.sourceNote), encoding: .utf8)
            else { return }
            try? Rig.write(text.replacingOccurrences(of: Rig.first, with: edited), to: Rig.sourceNote, under: root)
        }

        try await harness.move()

        let sourceAfterMove = try harness.text(Rig.sourceNote)
        #expect(sourceAfterMove.contains(edited), "precondition: the edited block stayed")
        #expect(!sourceAfterMove.contains(Rig.second), "precondition: the second block was removed")
        #expect(Self.anchoredCount(in: try harness.text(Rig.destinationNote)) == 2)
        #expect(harness.pratiche.problem == PraticaEntryCarry.sentence(
            for: .appendedOnly(count: 2, missing: 1), source: Rig.source, destination: Rig.destination
        ))

        harness.pratiche.testOnlyCarryHook = nil
        harness.pratiche.problem = nil
        harness.show(Rig.source)
        harness.manager.undo()
        try await waitUntil {
            harness.exists("\(Rig.source)/\(Rig.messageFile)")
                && (try? harness.text(Rig.destinationNote)).map(Rig.body) == Rig.destinationBody
        }

        let source = try harness.text(Rig.sourceNote)
        #expect(source.contains(edited), "the edit stays")
        #expect(source.contains(Rig.second), "the block only the destination held came back first")
        #expect(source.contains(Rig.first), "the edited block's old version reappears beside it")
        #expect(Self.anchoredCount(in: source) == 3)
        #expect(Self.anchoredCount(in: try harness.text(Rig.destinationNote)) == 0)
        #expect(harness.pratiche.problem == nil)
        harness.controller.close()
    }

    /// `.notCarried`: the entries never left the source, so the undo runs no carry step at all.
    @Test func aNotCarriedUndoRunsNoStepAndLeavesTheEntriesInTheSource() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        let root = vault.root
        harness.pratiche.testOnlyCarryHook = { phase in
            guard phase == .willAppend(notePath: Rig.destinationNote) else { return }
            try? Rig.write(
                Rig.frontmatter + Rig.destinationBody + "Scritto da un altro.\n", to: Rig.destinationNote, under: root
            )
        }
        try await harness.move()
        #expect(harness.pratiche.problem == PraticaEntryCarry.sentence(
            for: .notCarried, source: Rig.source, destination: Rig.destination
        ))
        let sourceBody = Rig.body(try harness.text(Rig.sourceNote))
        let destinationBody = Rig.body(try harness.text(Rig.destinationNote))

        let log = PhaseLog()
        harness.pratiche.testOnlyCarryHook = { log.phases.append($0) }
        harness.pratiche.problem = nil
        harness.show(Rig.source)
        harness.manager.undo()
        try await waitUntil { harness.exists("\(Rig.source)/\(Rig.messageFile)") }
        try await Task.sleep(for: .milliseconds(300))

        #expect(log.phases.isEmpty, "no carry step ran")
        #expect(Rig.body(try harness.text(Rig.sourceNote)) == sourceBody)
        #expect(Rig.body(try harness.text(Rig.destinationNote)) == destinationBody)
        #expect(Self.anchoredCount(in: try harness.text(Rig.sourceNote)) == 2)
        #expect(harness.pratiche.problem == nil)
        harness.controller.close()
    }

    /// A destination tab already dirty when the undo starts: the entry check skips the whole
    /// carry back, no step runs, and the sentence names the tab and where the entries are.
    @Test func aDestinationTabDirtyBeforeTheUndoSkipsTheCarryBackAndSaysWhereTheEntriesAre() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        try await harness.move()
        #expect(harness.pratiche.problem == nil)
        harness.controller.openNote(at: Rig.destinationNote)
        harness.controller.updateOpenNoteText((try harness.text(Rig.destinationNote)) + "Non salvato.\n")
        try #require(harness.controller.hasUnsavedTab(showing: Rig.destinationNote))
        let log = PhaseLog()
        harness.pratiche.testOnlyCarryHook = { log.phases.append($0) }

        harness.show(Rig.source)
        harness.manager.undo()
        let expected = "Le voci collegate non sono state riportate indietro perché «\(Rig.destinationNote)» "
            + "ha modifiche non salvate: sono in «\(Rig.destinationNote)»."
        try await waitUntil { harness.pratiche.problem == expected }

        #expect(log.phases.isEmpty, "no carry step ran")
        #expect(harness.exists("\(Rig.source)/\(Rig.messageFile)"), "the message itself came back")
        #expect(Self.anchoredCount(in: try harness.text(Rig.sourceNote)) == 0)
        #expect(Self.anchoredCount(in: try harness.text(Rig.destinationNote)) == 2, "no block is lost")
        harness.controller.close()
    }

    // MARK: - The failure sentences

    @Test func aRefusedReturnToTheSourceLeavesTheEntriesInTheDestinationAndSaysSo() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        let root = vault.root
        try await harness.move()
        #expect(harness.pratiche.problem == nil)
        harness.pratiche.testOnlyCarryHook = { phase in
            guard phase == .willAppend(notePath: Rig.sourceNote),
                  let text = try? String(contentsOf: root.appending(path: Rig.sourceNote), encoding: .utf8)
            else { return }
            try? Rig.write(text + "\nScritto da un altro.\n", to: Rig.sourceNote, under: root)
        }

        harness.show(Rig.source)
        harness.manager.undo()
        let expected = "Le voci collegate sono rimaste in «\(Rig.destinationNote)»: "
            + "non è stato possibile riportarle in «\(Rig.sourceNote)»."
        try await waitUntil { harness.pratiche.problem == expected }

        let source = try harness.text(Rig.sourceNote)
        #expect(source.contains("Scritto da un altro."), "the other writer's text is kept")
        #expect(Self.anchoredCount(in: source) == 0)
        #expect(Self.anchoredCount(in: try harness.text(Rig.destinationNote)) == 2,
                "nothing removed after a failed return")
        harness.controller.close()
    }

    @Test func aRefusedRemovalFromTheDestinationLeavesThemInBothFilesAndSaysSo() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        let root = vault.root
        try await harness.move()
        #expect(harness.pratiche.problem == nil)
        harness.pratiche.testOnlyCarryHook = { phase in
            guard phase == .willRemove(notePath: Rig.destinationNote),
                  let text = try? String(contentsOf: root.appending(path: Rig.destinationNote), encoding: .utf8)
            else { return }
            try? Rig.write(text + "\nScritto da un altro.\n", to: Rig.destinationNote, under: root)
        }

        harness.show(Rig.source)
        harness.manager.undo()
        let expected = "Le voci collegate sono ora sia in «\(Rig.sourceNote)» sia in «\(Rig.destinationNote)»: "
            + "non è stato possibile toglierle da «\(Rig.destinationNote)»."
        try await waitUntil { harness.pratiche.problem == expected }

        for notePath in [Rig.sourceNote, Rig.destinationNote] {
            #expect(Self.anchoredCount(in: try harness.text(notePath)) == 2)
        }
        #expect(try harness.text(Rig.destinationNote).contains("Scritto da un altro."))
        harness.controller.close()
    }

    // MARK: - Moved from PraticaEntryCarryTests.swift (the debugger's undo tests)

    @Test func anUndoWhoseDestinationTabTurnsDirtyBeforeTheRemovalLeavesTheBlocksInBothFiles() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        let controller = harness.controller
        let root = vault.root
        try await harness.move()
        #expect(harness.pratiche.problem == nil)

        harness.pratiche.testOnlyCarryHook = { phase in
            guard phase == .willRemove(notePath: Rig.destinationNote),
                  let text = try? String(contentsOf: root.appending(path: Rig.destinationNote), encoding: .utf8)
            else { return }
            controller.openNote(at: Rig.destinationNote)
            controller.updateOpenNoteText(text + "Non salvato.\n")
        }
        harness.show(Rig.source)
        harness.manager.undo()
        try await waitUntil { harness.pratiche.problem != nil }

        for notePath in [Rig.sourceNote, Rig.destinationNote] {
            #expect(PraticaEntryEdit.blocks(anchoredTo: Rig.messageID, in: try harness.text(notePath)).count == 2)
        }
        let problem = try #require(harness.pratiche.problem)
        #expect(problem.contains("sia in"), "\(problem)")
        controller.close()
    }

    @Test func anUndoThatDidNotRestoreTheMessageLeavesTheEntriesWithIt() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        try await harness.move()
        let destinationAfter = try harness.text(Rig.destinationNote)
        // The message note is gone from where the undo would take it from: `moveBack` fails.
        try FileManager.default.removeItem(
            at: vault.root.appending(path: "\(Rig.destination)/\(Rig.messageFile)", directoryHint: .notDirectory)
        )
        let sourceAfter = try harness.text(Rig.sourceNote)

        harness.show(Rig.source)
        harness.manager.undo()
        try await waitUntil { harness.pratiche.problem != nil }
        try await Task.sleep(for: .milliseconds(300))

        #expect(!harness.exists("\(Rig.source)/\(Rig.messageFile)"))
        #expect(Rig.body(try harness.text(Rig.destinationNote)) == Rig.body(destinationAfter),
                "the entries stay with the message that did not come back")
        #expect(Rig.body(try harness.text(Rig.sourceNote)) == Rig.body(sourceAfter),
                "nothing appended to the source, no orphan")
        harness.controller.close()
    }

    @Test func aCarryBackAfterAVaultSwitchWritesNothingAndSaysWhereTheEntriesAre() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        let movedSession = try #require(harness.controller.session)
        try await harness.move()
        let sourceAfter = try harness.text(Rig.sourceNote)
        let destinationAfter = try harness.text(Rig.destinationNote)
        let blocks = PraticaEntryEdit.blocks(anchoredTo: Rig.messageID, in: destinationAfter)

        let other = try TemporaryVault()
        try Rig.write(Rig.frontmatter + "\nAltro vault.\n", to: Rig.sourceNote, under: other.root)
        try Rig.write(Rig.frontmatter + "\nAltro vault.\n", to: Rig.destinationNote, under: other.root)
        await harness.controller.open(other.root)
        let otherSession = try #require(harness.controller.session)
        try #require(otherSession !== movedSession)
        let otherSourceBefore = try String(
            contentsOf: other.root.appending(path: Rig.sourceNote), encoding: .utf8
        )

        await PraticaEntryCarry(pratiche: harness.pratiche, vault: harness.controller).carryBack(
            .carried(count: 2),
            PraticaEntryCarry.Transfer(
                blocks: blocks, messageID: Rig.messageID, source: Rig.source, destination: Rig.destination
            ),
            in: movedSession
        )

        #expect(try String(contentsOf: other.root.appending(path: Rig.sourceNote), encoding: .utf8)
            == otherSourceBefore)
        #expect(try harness.text(Rig.sourceNote) == sourceAfter)
        #expect(try harness.text(Rig.destinationNote) == destinationAfter)
        let problem = try #require(harness.pratiche.problem)
        #expect(problem.contains(Rig.destinationNote) && problem.contains("vault"), "\(problem)")
        harness.controller.close()
    }
}
