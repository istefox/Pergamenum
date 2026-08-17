import Foundation
import Testing
@testable import Pergamenum

// Capture (ADR-0008): the one door the panel, the `pergamenum://capture` route,
// `perg capture` and the MCP tool all come through.
//
// Its own file rather than the end of `ConnectorTests`: that file is the guardrails and
// the payload shapes, and eleven more tests took it past the length the linter allows -
// which was the right complaint, not a threshold to raise.

private let note = """
---
date: 2026-08-11
tags:
  - type-note
---

Corpo, con un [[Link che non esiste]].

- [ ] Alfa >2026-08-20
"""

@MainActor
private func openVault(_ vault: borrowing TemporaryVault) async throws -> VaultSession {
    try vault.write(note, to: "Nota.md")
    let session = VaultSession(root: vault.root)
    await session.rescan()
    return session
}

@MainActor
@Test func captureReadsItsDestinationInBothLanguagesAndRefusesAnythingElse() throws {
    typealias Destination = VaultAPI.CaptureDestination

    #expect(try Destination.named("note", folder: nil) == .newNote(folder: nil))
    #expect(try Destination.named("nota", folder: "01 Progetti") == .newNote(folder: "01 Progetti"))
    #expect(try Destination.named("task", folder: nil) == .task)
    #expect(try Destination.named("oggi", folder: nil) == .today)
    #expect(try Destination.named("today", folder: nil) == .today)
    #expect(try Destination.named("note:Calendar/20260811.md", folder: nil)
        == .note("Calendar/20260811.md"))

    #expect(throws: ConnectorError.self) { try Destination.named("inventata", folder: nil) }
    // A path-shaped destination with no path is a typo, not the root note.
    #expect(throws: ConnectorError.self) { try Destination.named("note:", folder: nil) }
}

@MainActor
@Test func captureIntoTheDayMakesTodaysNoteWhenTheDayHasNoneYet() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)
    VaultAPI.arm(session, command: "capture", dryRun: false)

    let summary = try VaultAPI.capture(session, to: .today, text: "Deciso il fornitore")

    #expect(summary.applied)
    let path = session.dailyNotePath(for: .today)
    #expect(summary.path == path)
    let onDisk = try String(
        contentsOf: vault.root.appending(path: path), encoding: .utf8
    )
    #expect(onDisk.contains("Deciso il fornitore"))
    // Created through `dailyNote(for:)`, so it carries the conformant frontmatter and
    // not just the captured line.
    #expect(onDisk.contains("type-note"))
}

@MainActor
@Test func captureAsANoteTitlesItWithTheFirstLineAndKeepsTheRestAsTheBody() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)
    VaultAPI.arm(session, command: "capture", dryRun: false)

    let summary = try VaultAPI.capture(
        session,
        to: .newNote(folder: nil),
        text: "Mescola per il distretto\n\nProvata a 60 shore, tiene."
    )

    #expect(summary.applied)
    #expect(summary.path.hasPrefix("00 Inbox/"), "senza cartella la cattura va nell'inbox")
    let onDisk = try String(
        contentsOf: vault.root.appending(path: summary.path), encoding: .utf8
    )
    #expect(onDisk.contains("Provata a 60 shore"))
    // The first line titled the note; it is not repeated in the body.
    #expect(!onDisk.contains("\nMescola per il distretto"))
}

@MainActor
@Test func aTitleTheConventionsRefuseStopsTheCaptureInsteadOfBeingCorrected() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)
    VaultAPI.arm(session, command: "capture", dryRun: false)

    // Capture is a faster way to write a note, not a way around SPEC §4.2: the first
    // line goes through `NoteName.validate` like any other title.
    #expect(throws: ConnectorError.self) {
        try VaultAPI.capture(
            session, to: .newNote(folder: nil), text: "questo/non va\ncorpo qualsiasi"
        )
    }
    #expect(throws: ConnectorError.self) {
        try VaultAPI.capture(session, to: .newNote(folder: nil), text: "Relazione v2")
    }
    #expect(!session.exists("00 Inbox/Relazione v2.md"))
}

@MainActor
@Test func leadingBlankLinesDoNotBecomeTheTitle() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)
    VaultAPI.arm(session, command: "capture", dryRun: false)

    // A panel that has just been opened often carries a newline the user did not mean.
    // Trimming first means the first *written* line titles the note, which is what
    // somebody typing into a box believes will happen.
    let summary = try VaultAPI.capture(
        session, to: .newNote(folder: nil), text: "\n\n  Mescola per il distretto\nCorpo."
    )
    #expect(summary.path == "00 Inbox/Mescola per il distretto.md")
}

@MainActor
@Test func aDateOnAnythingButATaskIsRefusedRatherThanDropped() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)
    VaultAPI.arm(session, command: "capture", dryRun: false)

    // Silently ignoring it would leave the caller believing the deadline is there.
    #expect(throws: ConnectorError.self) {
        try VaultAPI.capture(session, to: .today, text: "Nota", due: "2026-08-25")
    }
    #expect(throws: ConnectorError.self) {
        try VaultAPI.capture(
            session, to: .newNote(folder: nil), text: "Titolo", scheduled: "2026-08-25"
        )
    }
    // On a task they are exactly what they say.
    let summary = try VaultAPI.capture(
        session, to: .task, text: "Richiamare Rossi", scheduled: "2026-08-20", due: "2026-08-25"
    )
    let onDisk = try String(
        contentsOf: vault.root.appending(path: summary.path), encoding: .utf8
    )
    #expect(onDisk.contains("- [ ] Richiamare Rossi >2026-08-20 !2026-08-25"))
}

@MainActor
@Test func captureIntoANoteThatIsNotThereIsRefusedAndNotInvented() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)
    VaultAPI.arm(session, command: "capture", dryRun: false)

    #expect(throws: ConnectorError.self) {
        try VaultAPI.capture(session, to: .note("Mai/Esistita.md"), text: "x")
    }
    #expect(!session.exists("Mai/Esistita.md"))
}

@MainActor
@Test func anEmptyCaptureIsRefusedBeforeAnythingIsOpened() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)
    VaultAPI.arm(session, command: "capture", dryRun: false)

    #expect(throws: ConnectorError.self) {
        try VaultAPI.capture(session, to: .today, text: "   \n  \n")
    }
    // Nothing was created on the way to finding out.
    #expect(!session.exists(session.dailyNotePath(for: .today)))
}

@MainActor
@Test func aRehearsedCaptureShowsTheDiffAndLeavesTheDayAlone() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)
    VaultAPI.arm(session, command: "capture", dryRun: true)

    let summary = try VaultAPI.capture(session, to: .note("Nota.md"), text: "Aggiunta")

    #expect(!summary.applied)
    #expect(try #require(summary.diff).contains("+Aggiunta"))
    let onDisk = try String(contentsOf: vault.root.appending(path: "Nota.md"), encoding: .utf8)
    #expect(!onDisk.contains("Aggiunta"), "una prova non deve toccare il file")
    #expect(VaultAPI.journalLog(at: vault.root, limit: nil).isEmpty)
}

@MainActor
@Test func aRehearsedCaptureIntoADayWithNoNoteYetStillShowsWhatWouldHappen() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)
    VaultAPI.arm(session, command: "capture", dryRun: true)

    // The gap this covers was found by running the MCP smoke test, not by reading:
    // a rehearsal creates nothing, so `dailyNote(for:)` hands back the path of a file
    // that is not there and the append refused it. Every other test here happened to
    // use a day that already had a note.
    let summary = try VaultAPI.capture(session, to: .today, text: "Appunto")

    #expect(!summary.applied)
    #expect(summary.path == session.dailyNotePath(for: .today))
    #expect(try #require(summary.diff).contains("+Appunto"))
    #expect(summary.note != nil, "il diff da solo non direbbe che la nota va creata prima")
    #expect(!session.exists(summary.path))
}

@MainActor
@Test func aRealCaptureIsRecordedAndCanBePutBack() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)
    VaultAPI.arm(session, command: "capture", dryRun: false)

    _ = try VaultAPI.capture(session, to: .note("Nota.md"), text: "Aggiunta")
    let id = try #require(VaultAPI.journalLog(at: vault.root, limit: nil).last?.id)
    _ = try VaultAPI.undo(session, id: id)

    let onDisk = try String(contentsOf: vault.root.appending(path: "Nota.md"), encoding: .utf8)
    #expect(!onDisk.contains("Aggiunta"))
}
