import Foundation
import Testing
@testable import Pergamenum

// PG-383: the dossier side of «Sposta in…»'s undo, keyed on whether `moveBack` returned the
// message note. Shares `PraticaEntryCarryTests.swift`'s `CarryHarness`; its own file because
// `PraticaEntryCarryBackTests.swift` had reached SwiftLint's type_body_length warning.

@MainActor
@Suite(.serialized) struct PraticaEntryCarryBackUndoTests {
    private typealias Rig = CarryHarness

    /// PG-383: the source excludes the message for as long as its note is away, and the
    /// destination includes it for as long as its note is there. An undo whose `moveBack` could
    /// not return the note (its old path is taken) lifts neither, or the entries left in the
    /// source go from hidden to orphaned (ADR-0079) and the two pratiche describe the note
    /// inconsistently.
    @Test func anUndoThatDidNotRestoreTheMessageKeepsTheSourceExclusionAndTheDestinationInclusion() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        try await harness.move()
        #expect(try harness.text(Rig.sourceNote).contains("pergamenum-dossier-excluded"))
        #expect(try harness.text(Rig.destinationNote).contains("pergamenum-dossier-included"))
        // The message note's old path is taken: `moveBack` refuses, the note stays in the destination.
        try Rig.write("occupato", to: "\(Rig.source)/\(Rig.messageFile)", under: vault.root)

        harness.show(Rig.source)
        harness.manager.undo()
        // `moveBack`'s report comes before the dossier steps; the pause lets them run, as
        // `PraticaEntryCarryBackTests.anUndoThatDidNotRestoreTheMessageLeavesTheEntriesWithIt` does.
        try await waitUntil { harness.pratiche.problem?.contains("non è tornato al suo posto") == true }
        try await Task.sleep(for: .milliseconds(300))

        #expect(harness.exists("\(Rig.destination)/\(Rig.messageFile)"), "the note stayed in the destination")
        #expect(try harness.text(Rig.sourceNote).contains("pergamenum-dossier-excluded"),
                "the message is still away, so the source still excludes it")
        #expect(try harness.text(Rig.destinationNote).contains("pergamenum-dossier-included"),
                "the note is still in the destination, so the destination still includes it")
        harness.controller.close()
    }

    /// PG-383, the shape the ledger names: the carry was refused, so the entries stayed in the
    /// source, hidden by its exclusion of the message. The undo that cannot bring the note back
    /// must leave them hidden, not turn them into orphans.
    @Test func anUndoThatDidNotRestoreTheMessageLeavesTheEntriesLeftInTheSourceHiddenNotOrphaned() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        let root = vault.root
        harness.pratiche.testOnlyCarryHook = { phase in
            guard phase == .willAppend(notePath: Rig.destinationNote) else { return }
            let foreign = Rig.frontmatter + Rig.destinationBody + "Scritto da un altro.\n"
            try? Rig.write(foreign, to: Rig.destinationNote, under: root)
        }
        try await harness.move()
        harness.pratiche.testOnlyCarryHook = nil
        #expect(try harness.carriedBlocks().count == 2, "the entries stayed in the source")
        try FileManager.default.removeItem(
            at: vault.root.appending(path: "\(Rig.destination)/\(Rig.messageFile)", directoryHint: .notDirectory)
        )

        harness.show(Rig.source)
        harness.manager.undo()
        // `moveBack`'s report comes before the dossier steps; the pause lets them run, as
        // `PraticaEntryCarryBackTests.anUndoThatDidNotRestoreTheMessageLeavesTheEntriesWithIt` does.
        try await waitUntil { harness.pratiche.problem?.contains("non è tornato al suo posto") == true }
        try await Task.sleep(for: .milliseconds(300))

        #expect(!harness.exists("\(Rig.source)/\(Rig.messageFile)"))
        let read = PraticheController.readTimeline(praticaPath: Rig.source, vaultRoot: harness.root)
        let placed = PraticaTimelineModel.ordered(read.entries, excluded: read.excluded).map(\.placement)
        #expect(placed.filter { $0 == .excluded(messageID: Rig.messageID) }.count == 2,
                "the entries left in the source stay hidden by the exclusion")
        #expect(!placed.contains(.orphaned(messageID: Rig.messageID)))
        harness.controller.close()
    }

    /// (coverage) The other side of PG-383's condition: an undo that DID restore the note lifts
    /// the source's exclusion and the destination's inclusion.
    @Test func anUndoThatRestoredTheMessageLiftsTheSourceExclusionAndTheDestinationInclusion() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        try await harness.move()
        #expect(try harness.text(Rig.sourceNote).contains("pergamenum-dossier-excluded"))

        harness.show(Rig.source)
        harness.manager.undo()
        try await waitUntil {
            harness.exists("\(Rig.source)/\(Rig.messageFile)")
                && (try? harness.text(Rig.destinationNote))?.contains("pergamenum-dossier-included") == false
                && (try? harness.text(Rig.sourceNote))?.contains("pergamenum-dossier-excluded") == false
        }

        #expect(!(try harness.text(Rig.sourceNote)).contains("pergamenum-dossier-excluded"))
        #expect(!(try harness.text(Rig.destinationNote)).contains("pergamenum-dossier-included"))
        harness.controller.close()
    }
}
