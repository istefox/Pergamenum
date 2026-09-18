import Foundation
import Testing
@testable import Pergamenum

// ADR-0050: the gesture travels with the task that writes, not with the session. What these
// tests pin is the one interleaving `PG-152` (issue #281) described - two transactions open at
// once from two tasks - forced deterministically with gates rather than hoped for with timing
// (ADR-0043 §D9's rule), plus the two edges of the binding's scope: an unstructured task
// started inside a gesture inherits it, and a write on the calling task once the gesture has
// closed belongs to none.

private func note(_ body: String) -> String {
    "---\ndate: 2026-09-18\ntags:\n  - type-note\n  - topic-prove\n---\n\n\(body)\n"
}

@MainActor
private func armedSession(_ vault: borrowing TemporaryVault) async throws -> VaultSession {
    try vault.write(note("Uno."), to: "Uno.md")
    try vault.write(note("Due."), to: "Due.md")
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    session.journal = session.journalOnDisk
    return session
}

/// A one-shot latch on the main actor: `wait()` suspends until `open()` has been called, and
/// returns at once afterwards. Being `@MainActor` it needs no lock, and being explicit it makes
/// the order the two tasks run in a fact the test states rather than a coincidence it observes.
@MainActor
private final class Gate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        opened = true
        let resumed = waiters
        waiters.removeAll()
        resumed.forEach { $0.resume() }
    }

    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

// MARK: - §D2: two gestures open at once, each on its own task

@MainActor
@Test func twoGesturesOpenAtOnceFromTwoTasksKeepTheirOwnIDsAndCommands() async throws {
    let vault = try TemporaryVault()
    let session = try await armedSession(vault)
    let firstIsInside = Gate()
    let secondIsDone = Gate()

    // The first gesture writes once, then holds itself open across a suspension. Before
    // ADR-0050 this is the moment `currentOperation` sat on the session with the first id in
    // it, waiting for whatever the main actor ran next.
    let first = Task { @MainActor in
        await session.transaction("primo") {
            try? await session.write(note("Uno, prima."), to: "Uno.md")
            firstIsInside.open()
            await secondIsDone.wait()
            try? await session.write(note("Uno, dopo."), to: "Uno.md")
        }
    }
    await firstIsInside.wait()

    // The whole of the second gesture runs while the first is open and suspended. This is the
    // interleaving itself, not a race that may or may not happen: the gates order it.
    await Task { @MainActor in
        await session.transaction("secondo") {
            try? await session.write(note("Due, riscritta."), to: "Due.md")
        }
    }.value
    secondIsDone.open()
    await first.value

    let entries = session.journalOnDisk.entries()
    let uno = entries.filter { $0.path == "Uno.md" }
    let due = entries.filter { $0.path == "Due.md" }
    #expect(uno.count == 2, "il primo gesto ha perso una scrittura")
    #expect(due.count == 1)

    // Both of the first gesture's writes - the one before the second gesture ran and the one
    // after - carry the first id and the first command. Before the fix the second one carried
    // `nil`: the second transaction's `defer` had cleared the shared property under it.
    let firstID = try #require(uno.first?.operation)
    #expect(uno.allSatisfy { $0.operation == firstID }, "le due scritture del primo gesto hanno id diversi")
    #expect(uno.allSatisfy { $0.command == "primo" })

    // The second gesture's write is its own gesture, not a stowaway in the first one.
    let secondID = try #require(due.first?.operation)
    #expect(secondID != firstID, "la scrittura del secondo gesto si è unita al primo")
    #expect(due.first?.command == "secondo")

    // And `undo` sees two gestures of the right size, which is what the ids are for.
    #expect(session.journalOnDisk.entries(operation: firstID).count == 2)
    #expect(session.journalOnDisk.entries(operation: secondID).count == 1)
    #expect(session.currentOperation == nil)
}

@MainActor
@Test func aWriteOnTheOutsideTaskWhileAGestureIsOpenElsewhereBelongsToNoGesture() async throws {
    let vault = try TemporaryVault()
    let session = try await armedSession(vault)
    session.journalCommand = "da sola"
    let gestureIsInside = Gate()
    let outsideIsDone = Gate()

    let gesture = Task { @MainActor in
        await session.transaction("gesto") {
            try? await session.write(note("Uno, nel gesto."), to: "Uno.md")
            gestureIsInside.open()
            await outsideIsDone.wait()
        }
    }
    await gestureIsInside.wait()

    // The test's own task is not inside the transaction, however open it is on the other one:
    // this write is a plain write with the session's standing command.
    #expect(session.currentOperation == nil)
    #expect(session.journalCommand == "da sola")
    try await session.write(note("Due, fuori."), to: "Due.md")
    outsideIsDone.open()
    await gesture.value

    let due = try #require(session.journalOnDisk.entries().first { $0.path == "Due.md" })
    #expect(due.operation == nil, "una scrittura fuori dal gesto ha preso il suo id")
    #expect(due.command == "da sola")
    let uno = try #require(session.journalOnDisk.entries().first { $0.path == "Uno.md" })
    #expect(uno.operation != nil)
    #expect(uno.command == "gesto")
}

// MARK: - §D3: the binding's scope

@MainActor
@Test func aTaskStartedInsideAGestureWritesUnderThatGesture() async throws {
    let vault = try TemporaryVault()
    let session = try await armedSession(vault)

    await session.transaction("gesto") {
        try? await session.write(note("Uno, dal gesto."), to: "Uno.md")
        // An unstructured task created inside the binding inherits it: a write it issues is
        // part of the gesture, exactly as one issued by the body directly.
        await Task { @MainActor in
            try? await session.write(note("Due, dal task figlio."), to: "Due.md")
        }.value
    }

    let ids = Set(session.journalOnDisk.entries().compactMap(\.operation))
    #expect(session.journalOnDisk.entries().count == 2)
    #expect(ids.count == 1, "il task avviato dentro il gesto ha scritto sotto un altro id")
}

@MainActor
@Test func theGestureClosesWithTheBodyAndTheStandingCommandWasNeverTouched() async throws {
    let vault = try TemporaryVault()
    let session = try await armedSession(vault)
    session.journalCommand = "quello di prima"

    await session.transaction("gesto") {
        #expect(session.currentOperation != nil)
        #expect(session.journalCommand == "gesto")
    }

    #expect(session.currentOperation == nil, "la transazione non si è chiusa")
    #expect(session.journalCommand == "quello di prima")
    try await session.write(note("Uno, dopo."), to: "Uno.md")
    let entry = try #require(session.journalOnDisk.entries().last)
    #expect(entry.operation == nil)
    #expect(entry.command == "quello di prima")
}

@MainActor
@Test func aGestureWhoseBodyThrowsStillClosesAndRethrows() async throws {
    let vault = try TemporaryVault()
    let session = try await armedSession(vault)

    await #expect(throws: FileOperationError.self) {
        try await session.transaction("gesto") {
            try await session.moveFile(from: "Mai-esistita.md", to: "Altrove.md")
        }
    }
    #expect(session.currentOperation == nil, "un corpo che lancia ha lasciato il gesto aperto")
}
