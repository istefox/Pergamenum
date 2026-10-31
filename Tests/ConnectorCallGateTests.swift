import Foundation
import Testing
@testable import Pergamenum

// PG-438: connector calls run one at a time, in the order they arrived.
//
// `VaultHost` (the MCP target) is not reachable from this suite, so what is tested here is the
// two halves it is made of: `ConnectorCallGate`, which keeps calls apart, and the write path
// underneath it, which is why they have to be kept apart (ADR-0007 §D6 puts the dry-run switch,
// the journal and the command name on the one session). That `VaultHost` actually routes `call`,
// `resources(after:)` and `resource(at:)` through the gate is covered by `scripts/mcp-smoke.py`
// (`concurrent_writes`, and the new listing check in `resources`), which drives a real server.

// MARK: - Support

private struct GateTestError: Error {}

/// What the bodies under test did, in order, plus the continuations the test holds them on.
@MainActor
private final class GateRecorder {
    var events: [String] = []
    private var held: [String: CheckedContinuation<Void, Never>] = [:]

    /// Records `name start`, suspends until `release(name)`, records `name end`.
    func hold(_ name: String) async {
        events.append("\(name) start")
        await withCheckedContinuation { held[name] = $0 }
        events.append("\(name) end")
    }

    /// Records both ends without suspending between them.
    func pass(_ name: String) {
        events.append("\(name) start")
        events.append("\(name) end")
    }

    func release(_ name: String) {
        held.removeValue(forKey: name)?.resume()
    }

    /// Lets the main actor run everything that is ready to, so a task just created has
    /// reached the gate (or its first suspension) before the test looks. A positive check
    /// polls; a negative one ("has not started") can only false-pass, never flake red.
    static func settle() async {
        for _ in 0..<50 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(20))
    }

    func waitFor(_ event: String) async {
        for _ in 0..<2_000 where !events.contains(event) { await Task.yield() }
    }
}

// MARK: - The gate

@MainActor
@Test func aSecondCallWaitsForTheFirstAndRunsAfterItIsReleased() async {
    let gate = ConnectorCallGate()
    let recorder = GateRecorder()

    let first = Task { await gate.run { await recorder.hold("A") } }
    await recorder.waitFor("A start")
    let second = Task { await gate.run { recorder.pass("B") } }
    await GateRecorder.settle()

    #expect(recorder.events == ["A start"], "B must not start while A holds the gate")

    recorder.release("A")
    await first.value
    await second.value
    #expect(recorder.events == ["A start", "A end", "B start", "B end"])
}

@MainActor
@Test func callsRunInTheOrderTheyArrivedWhateverTheyAre() async {
    let gate = ConnectorCallGate()
    let recorder = GateRecorder()

    let first = Task { await gate.run { await recorder.hold("A") } }
    await recorder.waitFor("A start")
    // Each is given time to reach the gate before the next is created, so arrival order is
    // the creation order and the assertion below is about the queue, not the scheduler.
    let second = Task { await gate.run { await recorder.hold("B") } }
    await GateRecorder.settle()
    let third = Task { await gate.run { recorder.pass("C") } }
    await GateRecorder.settle()
    #expect(recorder.events == ["A start"])

    recorder.release("A")
    await recorder.waitFor("B start")
    await GateRecorder.settle()
    // B holds the gate now; C is still behind it.
    #expect(recorder.events == ["A start", "A end", "B start"])

    recorder.release("B")
    await first.value
    await second.value
    await third.value
    #expect(recorder.events == ["A start", "A end", "B start", "B end", "C start", "C end"])
}

@MainActor
@Test func aCallThatArrivesAsTheGateIsReleasedQueuesBehindTheWaiterNotAheadOfIt() async {
    let gate = ConnectorCallGate()
    let recorder = GateRecorder()

    // The same task calls again the moment its first call returns, with no suspension in
    // between: the shape that would jump the line if release cleared the flag and left the
    // waiter to wake up later, instead of handing the turn to it.
    let first = Task {
        await gate.run { await recorder.hold("A") }
        await gate.run { recorder.pass("A2") }
    }
    await recorder.waitFor("A start")
    let second = Task { await gate.run { recorder.pass("B") } }
    await GateRecorder.settle()

    recorder.release("A")
    await first.value
    await second.value
    #expect(recorder.events == ["A start", "A end", "B start", "B end", "A2 start", "A2 end"])
}

@MainActor
@Test func aBodyThatThrowsLetsTheNextCallThroughAndTheErrorReachesItsCaller() async {
    let gate = ConnectorCallGate()
    let recorder = GateRecorder()

    let first = Task { () -> Bool in
        do {
            try await gate.run {
                await recorder.hold("A")
                throw GateTestError()
            }
            return false
        } catch is GateTestError {
            return true
        } catch {
            return false
        }
    }
    await recorder.waitFor("A start")
    let second = Task { await gate.run { recorder.pass("B") } }
    await GateRecorder.settle()
    #expect(recorder.events == ["A start"])

    recorder.release("A")
    #expect(await first.value, "the error is thrown to the caller whose body threw it")
    await second.value
    #expect(recorder.events == ["A start", "A end", "B start", "B end"])

    // And the gate is free afterwards: a call that arrives later does not wait.
    await gate.run { recorder.pass("C") }
    #expect(recorder.events.suffix(2) == ["C start", "C end"])
}

@MainActor
@Test func aBodyThatThrowsWithNobodyWaitingLeavesTheGateFree() async {
    let gate = ConnectorCallGate()
    let recorder = GateRecorder()

    await #expect(throws: GateTestError.self) {
        try await gate.run { throw GateTestError() }
    }
    // Would never return if the throw had left the gate marked busy.
    await gate.run { recorder.pass("next") }
    #expect(recorder.events == ["next start", "next end"])
}

@MainActor
@Test func theBodysResultIsReturnedToItsOwnCaller() async {
    let gate = ConnectorCallGate()

    let first = Task { await gate.run { await Task.yield(); return 1 } }
    let second = Task { await gate.run { 2 } }
    #expect(await first.value == 1)
    #expect(await second.value == 2)
}

// (coverage) The doc comment's own contract: a waiter whose task is cancelled still takes its
// turn and runs its body, and the queue behind it still moves.
@MainActor
@Test func aCancelledWaiterStillTakesItsTurnAndDoesNotWedgeTheQueue() async {
    let gate = ConnectorCallGate()
    let recorder = GateRecorder()

    let first = Task { await gate.run { await recorder.hold("A") } }
    await recorder.waitFor("A start")
    let second = Task { await gate.run { recorder.pass("B") } }
    await GateRecorder.settle()
    let third = Task { await gate.run { recorder.pass("C") } }
    await GateRecorder.settle()

    second.cancel()
    recorder.release("A")
    await first.value
    await second.value
    await third.value
    #expect(recorder.events == ["A start", "A end", "B start", "B end", "C start", "C end"])
}

// MARK: - Why the calls must be kept apart (R-05 at the VaultAPI level)

/// What one connector call does on the host: arm the session, then write, inside the gate.
/// Without the gate this is the pre-fix shape: the second call's `arm` lands while the first
/// is suspended on the disk actor.
@MainActor
private func connectorCall(
    _ gate: ConnectorCallGate, _ session: VaultSession,
    command: String, dryRun: Bool, path: String, text: String
) async throws -> VaultAPI.WriteSummary {
    try await gate.run {
        VaultAPI.arm(session, command: command, dryRun: dryRun)
        return try await VaultAPI.appendToNote(session, at: path, text: text)
    }
}

@MainActor
@Test func aRehearsalInFlightWithARealWriteDoesNotTurnTheRealWriteIntoOne() async throws {
    let vault = try TemporaryVault()
    let session = try await openConnectorVault(vault)
    try vault.write("Altra nota.\n", to: "Altra.md")
    await session.rescan()
    let gate = ConnectorCallGate()

    // Started one after the other without awaiting in between: the real write suspends on
    // the disk actor, and the rehearsal reaches the session while it is suspended.
    let real = Task {
        try await connectorCall(
            gate, session, command: "append_to_note", dryRun: false,
            path: "Nota.md", text: "Aggiunta reale"
        )
    }
    let rehearsal = Task {
        try await connectorCall(
            gate, session, command: "rehearsed_append", dryRun: true,
            path: "Altra.md", text: "Aggiunta provata"
        )
    }
    let realSummary = try await real.value
    let rehearsalSummary = try await rehearsal.value

    #expect(realSummary.applied, "the write that reached the disk says so")
    #expect(realSummary.diff == nil)
    #expect(!rehearsalSummary.applied)
    #expect(try #require(rehearsalSummary.diff).contains("+Aggiunta provata"))

    let log = try VaultAPI.journalLog(at: vault.root, base: vault.stateBase, limit: nil)
    #expect(log.count == 1, "exactly the real write is journalled, the rehearsal not at all")
    #expect(log.first?.command == "append_to_note", "and under its own command, not the rehearsal's")
    #expect(log.first?.path == "Nota.md")

    let nota = try String(contentsOf: vault.root.appending(path: "Nota.md"), encoding: .utf8)
    #expect(nota.contains("Aggiunta reale"))
    let altra = try String(contentsOf: vault.root.appending(path: "Altra.md"), encoding: .utf8)
    #expect(altra == "Altra nota.\n", "a rehearsal leaves its file as it was")
}

@MainActor
@Test func aRealWriteQueuedBehindARehearsalIsStillAppliedAndJournalled() async throws {
    let vault = try TemporaryVault()
    let session = try await openConnectorVault(vault)
    try vault.write("Altra nota.\n", to: "Altra.md")
    await session.rescan()
    let gate = ConnectorCallGate()

    let rehearsal = Task {
        try await connectorCall(
            gate, session, command: "rehearsed_append", dryRun: true,
            path: "Altra.md", text: "Aggiunta provata"
        )
    }
    let real = Task {
        try await connectorCall(
            gate, session, command: "append_to_note", dryRun: false,
            path: "Nota.md", text: "Aggiunta reale"
        )
    }
    let rehearsalSummary = try await rehearsal.value
    let realSummary = try await real.value

    #expect(!rehearsalSummary.applied)
    #expect(realSummary.applied, "re-armed for itself: the rehearsal's switch did not carry over")
    let log = try VaultAPI.journalLog(at: vault.root, base: vault.stateBase, limit: nil)
    #expect(log.map(\.command) == ["append_to_note"])
    let nota = try String(contentsOf: vault.root.appending(path: "Nota.md"), encoding: .utf8)
    #expect(nota.contains("Aggiunta reale"))
}
