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
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    return session
}

@MainActor
@Test func captureReadsItsDestinationInBothLanguagesAndRefusesAnythingElse() throws {
    typealias Destination = VaultAPI.CaptureDestination

    #expect(try Destination.named("note", folder: nil) == .newNote(folder: nil))
    #expect(try Destination.named("nota", folder: "01 Progetti") == .newNote(folder: "01 Progetti"))
    #expect(try Destination.named("task", folder: nil) == .task(note: nil))
    #expect(try Destination.named("task:00 Inbox/Capture.md", folder: nil)
        == .task(note: "00 Inbox/Capture.md"))
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

    let summary = try await VaultAPI.capture(session, to: .today, text: "Deciso il fornitore")

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

    let summary = try await VaultAPI.capture(
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

// PG-384 (N1 seams), ADR-0080 §D3: capture derives a title instead of refusing the first line.
//
// Before ADR-0080, a capture whose first line the conventions refused (`questo/non va`,
// `Relazione v2`) threw. ADR-0080 §D3 reverses that for capture only; `VaultSession.createNote`
// still refuses (`VaultSessionTests.aSessionRefusesANonConformantTitleRatherThanFixingIt`).
// The two tests below pin the file each of those lines now writes.

private func bodyOf(_ text: String) -> String {
    NoteDocument.parse(text).body.trimmingCharacters(in: .whitespacesAndNewlines)
}

// (n1-seams R-03, R-04)
@MainActor
@Test func aFirstLineWithAForbiddenCharacterBecomesADerivedTitleAndKeepsEveryWordInTheBody() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)
    VaultAPI.arm(session, command: "capture", dryRun: false)

    let summary = try await VaultAPI.capture(
        session, to: .newNote(folder: nil), text: "questo/non va\ncorpo qualsiasi"
    )

    #expect(summary.applied)
    #expect(summary.path == "00 Inbox/questo non va.md")
    let onDisk = try String(contentsOf: vault.root.appending(path: summary.path), encoding: .utf8)
    // The title differs from the line, so nothing the person typed is lost: the first line
    // goes to the body as well.
    let body = bodyOf(onDisk)
    #expect(body.contains("questo/non va"))
    #expect(body.contains("corpo qualsiasi"))
}

// (n1-seams R-03, R-04)
@MainActor
@Test func aFirstLineEndingInAVersionTokenLosesTheTokenFromTheTitleOnly() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)
    VaultAPI.arm(session, command: "capture", dryRun: false)

    let summary = try await VaultAPI.capture(session, to: .newNote(folder: nil), text: "Relazione v2")

    #expect(summary.path == "00 Inbox/Relazione.md")
    let onDisk = try String(contentsOf: vault.root.appending(path: summary.path), encoding: .utf8)
    #expect(bodyOf(onDisk) == "Relazione v2")
}

// (n1-seams R-03)
@MainActor
@Test func aLegalFirstLineIsTheTitleAndIsNotRepeatedInTheBody() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)
    VaultAPI.arm(session, command: "capture", dryRun: false)

    let summary = try await VaultAPI.capture(
        session, to: .newNote(folder: nil), text: "Mescola per il distretto\nProvata a 60 shore."
    )

    #expect(summary.path == "00 Inbox/Mescola per il distretto.md")
    let onDisk = try String(contentsOf: vault.root.appending(path: summary.path), encoding: .utf8)
    #expect(bodyOf(onDisk) == "Provata a 60 shore.")
}

// (n1-seams R-04)
@MainActor
@Test func aDerivedTitleAlreadyTakenIsRefusedAndWritesNothing() async throws {
    let vault = try TemporaryVault()
    let taken = "---\ndate: 2026-08-11\ntags:\n  - type-note\n---\n\nGià qui.\n"
    try vault.write(taken, to: "00 Inbox/questo non va.md")
    let session = try await openVault(vault)
    VaultAPI.arm(session, command: "capture", dryRun: false)

    let error = await #expect(throws: ConnectorError.self) {
        try await VaultAPI.capture(
            session, to: .newNote(folder: nil), text: "questo/non va\ncorpo qualsiasi"
        )
    }

    // The refusal is the "already exists" one, exactly as a typed title would get, and not
    // the old "titolo non conforme" for the line the person typed.
    #expect(error?.description.contains("esiste già") == true, "\(String(describing: error))")
    let onDisk = try String(
        contentsOf: vault.root.appending(path: "00 Inbox/questo non va.md"), encoding: .utf8
    )
    #expect(onDisk == taken)
    let siblings = try FileManager.default.contentsOfDirectory(
        atPath: vault.root.appending(path: "00 Inbox").path(percentEncoded: false)
    )
    #expect(siblings == ["questo non va.md"])
}

// (n1-seams R-04)
@MainActor
@Test func anEmptyOrWhitespaceOnlyCaptureAsANoteIsRefusedAndWritesNothing() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)
    VaultAPI.arm(session, command: "capture", dryRun: false)

    for text in ["", "   ", "\n\n  \n"] {
        await #expect(throws: ConnectorError.self) {
            try await VaultAPI.capture(session, to: .newNote(folder: nil), text: text)
        }
    }
    #expect(!FileManager.default.fileExists(
        atPath: vault.root.appending(path: "00 Inbox").path(percentEncoded: false)
    ))
}

// (n1-seams R-03, R-04)
@MainActor
@Test func aLineOfNothingButForbiddenCharactersBecomesTheTimestampedCaptureTitle() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)
    VaultAPI.arm(session, command: "capture", dryRun: false)

    let summary = try await VaultAPI.capture(session, to: .newNote(folder: nil), text: "???")

    // The title reads the clock (`VaultAPI.capture` has no clock parameter), so only its
    // shape is pinned: `YYYYMMDD HHmm Cattura`, in the inbox.
    let shape = #"^00 Inbox/\d{8} \d{4} Cattura\.md$"#
    #expect(
        summary.path.range(of: shape, options: .regularExpression) != nil,
        "«\(summary.path)» non ha la forma del titolo di ripiego"
    )
    let onDisk = try String(contentsOf: vault.root.appending(path: summary.path), encoding: .utf8)
    #expect(bodyOf(onDisk) == "???", "il testo digitato deve restare nel corpo")
}

@MainActor
@Test func leadingBlankLinesDoNotBecomeTheTitle() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)
    VaultAPI.arm(session, command: "capture", dryRun: false)

    // A panel that has just been opened often carries a newline the user did not mean.
    // Trimming first means the first *written* line titles the note, which is what
    // somebody typing into a box believes will happen.
    let summary = try await VaultAPI.capture(
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
    await #expect(throws: ConnectorError.self) {
        try await VaultAPI.capture(session, to: .today, text: "Nota", due: "2026-08-25")
    }
    await #expect(throws: ConnectorError.self) {
        try await VaultAPI.capture(
            session, to: .newNote(folder: nil), text: "Titolo", scheduled: "2026-08-25"
        )
    }
    // On a task they are exactly what they say.
    let summary = try await VaultAPI.capture(
        session, to: .task(note: nil), text: "Richiamare Rossi", scheduled: "2026-08-20", due: "2026-08-25"
    )
    let onDisk = try String(
        contentsOf: vault.root.appending(path: summary.path), encoding: .utf8
    )
    #expect(onDisk.contains("- [ ] Richiamare Rossi >2026-08-20 !2026-08-25"))
}

@MainActor
@Test func aTaskCapturedWithANoteGoesThereInsteadOfTheInbox() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)
    VaultAPI.arm(session, command: "capture", dryRun: false)

    let summary = try await VaultAPI.capture(
        session, to: .task(note: "Nota.md"), text: "Ricontrollare la curva"
    )
    #expect(summary.path == "Nota.md")
    let onDisk = try String(contentsOf: vault.root.appending(path: "Nota.md"), encoding: .utf8)
    #expect(onDisk.contains("- [ ] Ricontrollare la curva"))
}

@MainActor
@Test func captureIntoANoteThatIsNotThereIsRefusedAndNotInvented() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)
    VaultAPI.arm(session, command: "capture", dryRun: false)

    await #expect(throws: ConnectorError.self) {
        try await VaultAPI.capture(session, to: .note("Mai/Esistita.md"), text: "x")
    }
    #expect(!session.exists("Mai/Esistita.md"))
}

@MainActor
@Test func anEmptyCaptureIsRefusedBeforeAnythingIsOpened() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)
    VaultAPI.arm(session, command: "capture", dryRun: false)

    await #expect(throws: ConnectorError.self) {
        try await VaultAPI.capture(session, to: .today, text: "   \n  \n")
    }
    // Nothing was created on the way to finding out.
    #expect(!session.exists(session.dailyNotePath(for: .today)))
}

@MainActor
@Test func aRehearsedCaptureShowsTheDiffAndLeavesTheDayAlone() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)
    VaultAPI.arm(session, command: "capture", dryRun: true)

    let summary = try await VaultAPI.capture(session, to: .note("Nota.md"), text: "Aggiunta")

    #expect(!summary.applied)
    #expect(try #require(summary.diff).contains("+Aggiunta"))
    let onDisk = try String(contentsOf: vault.root.appending(path: "Nota.md"), encoding: .utf8)
    #expect(!onDisk.contains("Aggiunta"), "una prova non deve toccare il file")
    #expect(try VaultAPI.journalLog(at: vault.root, base: vault.stateBase, limit: nil).isEmpty)
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
    let summary = try await VaultAPI.capture(session, to: .today, text: "Appunto")

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

    _ = try await VaultAPI.capture(session, to: .note("Nota.md"), text: "Aggiunta")
    let id = try #require(try VaultAPI.journalLog(at: vault.root, base: vault.stateBase, limit: nil).last?.id)
    _ = try await VaultAPI.undo(session, id: id)

    let onDisk = try String(contentsOf: vault.root.appending(path: "Nota.md"), encoding: .utf8)
    #expect(!onDisk.contains("Aggiunta"))
}

// MARK: - A lone carriage return ends the typed line (PG-327, ADR-0080 §D3)

// (coverage) `CaptureTitle.endsTypedLine` is the one place capture decides where the first
// line stops; `captureAsNote` splits its body at the same character.
@Test func theTypedLineEndsAtEveryKindOfBreakAndNowhereElse() {
    #expect(CaptureTitle.endsTypedLine("\n"))
    #expect(CaptureTitle.endsTypedLine("\r"))
    #expect(CaptureTitle.endsTypedLine("\r\n"))
    #expect(!CaptureTitle.endsTypedLine("a"))
    #expect(!CaptureTitle.endsTypedLine(" "))
}

// (coverage) A lone "\r" after a legal title splits like any break and loses no text.
@MainActor
@Test func aLoneCarriageReturnAfterALegalTitleSplitsTheTitleOffAndKeepsTheBody() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)
    VaultAPI.arm(session, command: "capture", dryRun: false)

    let summary = try await VaultAPI.capture(
        session, to: .newNote(folder: nil), text: "Relazione fornitore\runo\rdue"
    )

    #expect(summary.path == "00 Inbox/Relazione fornitore.md")
    #expect(!summary.path.unicodeScalars.contains("\r"))
    let onDisk = try String(contentsOf: vault.root.appending(path: summary.path), encoding: .utf8)
    #expect(onDisk.contains("uno"))
    #expect(onDisk.contains("due"))
    #expect(!onDisk.contains("Relazione fornitore\r"))
}

// (coverage) The case the lone "\r" would have lost text in: a derived title sends the whole
// text to the body, so the line after the "\r" must be there.
@MainActor
@Test func aLoneCarriageReturnAfterARefusedTitleKeepsTheTextAfterItInTheBody() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)
    VaultAPI.arm(session, command: "capture", dryRun: false)

    let summary = try await VaultAPI.capture(
        session, to: .newNote(folder: nil), text: "questo/non va\rcorpo qualsiasi"
    )

    #expect(summary.path == "00 Inbox/questo non va.md")
    let onDisk = try String(contentsOf: vault.root.appending(path: summary.path), encoding: .utf8)
    let body = bodyOf(onDisk)
    #expect(body.contains("questo/non va"))
    #expect(body.contains("corpo qualsiasi"))
}

// (coverage) The same for a CRLF break: no "\r" on the derived title, no text lost.
@MainActor
@Test func aCRLFAfterARefusedTitleKeepsTheTextAfterItInTheBody() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)
    VaultAPI.arm(session, command: "capture", dryRun: false)

    let summary = try await VaultAPI.capture(
        session, to: .newNote(folder: nil), text: "questo/non va\r\ncorpo qualsiasi"
    )

    #expect(summary.path == "00 Inbox/questo non va.md")
    #expect(!summary.path.unicodeScalars.contains("\r"))
    let body = bodyOf(try String(contentsOf: vault.root.appending(path: summary.path), encoding: .utf8))
    #expect(body.contains("questo/non va"))
    #expect(body.contains("corpo qualsiasi"))
}

// (coverage) A rehearsal of a capture with a derived title names the derived title and
// writes nothing, the dry-run branch of `captureAsNote`.
@MainActor
@Test func aDryRunCaptureWithADerivedTitleNamesItAndWritesNothing() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)
    VaultAPI.arm(session, command: "capture", dryRun: true)

    let summary = try await VaultAPI.capture(
        session, to: .newNote(folder: nil), text: "questo/non va\ncorpo qualsiasi"
    )

    #expect(!summary.applied)
    #expect(summary.path == "00 Inbox/questo non va.md")
    #expect(summary.note?.contains("il corpo verrebbe aggiunto") == true)
    #expect(!session.exists(summary.path))
    #expect(!FileManager.default.fileExists(
        atPath: vault.root.appending(path: "00 Inbox").path(percentEncoded: false)
    ))
}

// (coverage) The panel's caption and the file the capture writes come from one function:
// for every text, the caption (or, with none, the typed line) is the file's name.
@MainActor
@Test(arguments: [
    "Idea: usare i token\rcorpo",
    "questo/non va\r\ncorpo",
    "  \n  a/b  ",
    "Relazione v2",
    "Mescola per il distretto\rProvata.",
])
func theCaptionAndTheFileNameOfACaptureAgree(text: String) async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)
    VaultAPI.arm(session, command: "capture", dryRun: false)
    let controller = CaptureController()
    controller.destination = .note
    controller.text = text

    let summary = try await VaultAPI.capture(session, to: .newNote(folder: nil), text: text)

    let stem = try #require(summary.path.split(separator: "/").last.map { String($0.dropLast(3)) })
    let typed = CaptureTitle.typedLine(of: text.trimmingCharacters(in: .whitespacesAndNewlines))
    let shown = controller.titleCaption().map { String($0.dropFirst("Titolo: ".count)) } ?? typed
    #expect(stem == shown, "«\(text)»: il file è «\(stem)», la didascalia dice «\(shown)»")
}
