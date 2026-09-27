import Foundation
import Testing
@testable import Pergamenum

// ADR-0068 §D1/§D2/§D3/§D4 (Pratiche sync integrity), plan
// docs/plans/pg-257-pratiche-sync-integrity-and-post-write-door.md, Task 3 - R-08, R-09.
//
// Today `PraticaFileOperations`' `.md` operations still go straight through
// `FileManager` (`trashItem`/`moveItem`/`copyItem`), never through the session's own
// doors - so the watcher sees a raw move as an external deletion of the source
// (ADR-0064) rather than as this app's own write, and an open tab on the moved note
// closes instead of following it. Red until Task 4 routes the `.md` half of each
// operation through `session.moveFile`/`trashFile(forgettingNoteID:)`/
// `restoreFromOutside`/`write(expectingAbsent:)`.
//
// **Ambiguity not tested, reported instead of guessed (tester instruction).** The
// plan's bullet "a copy onto a taken name is reported, not swallowed - use a
// pre-existing target that forces the `expectingAbsent` refusal" cannot be reached
// through the documented path: `PraticaFileOperations.reservedBaseName(for:in:)`
// already walks `-2`, `-3`, ... until it finds a name neither extension holds, and it
// runs synchronously, in-process, immediately before the write it guards - there is
// no way for a test to insert a colliding file between that check and the write
// without either racing (impossible in-process, single-threaded Swift Testing) or
// bypassing `reservedBaseName` entirely, which neither SPEC R-08/R-09 nor ADR-0068
// §D1 describes as a way to reach this scenario. R-08's own governing sentence is
// "a failure reported (never swallowed)" (not "a name collision forces a refusal"),
// and ADR-0068 §D1 says only "Every failure is reported through `pratiche.report(_:)`
// with the file's name, never swallowed" - neither sentence privileges the
// `expectingAbsent` refusal over any other write failure as the one this sub-bullet
// must exercise. Writing a test that forces the refusal through some other means
// (deleting `reservedBaseName`'s own collision loop, or calling `session.write`
// directly instead of through `copyFiles`) would be testing a scenario the documents
// never describe, not verifying one they do - so it is left unwritten here, per the
// tester's own instruction to report rather than invent when the documents do not
// decide it.

private let noteWithAttachmentTokens = """
---
date: 2026-09-01
tags:
  - type-note
pergamenum-mail-message-id: "<msg@rossi-spa.it>"
pergamenum-mail-attachments:
  - "[[q-2.pdf]]"
  - "[[q-3.pdf]]"
---

Corpo.
"""

private func praticaDetail(notePath: String) -> PraticaRowDetail {
    PraticaRowDetail(
        notePath: notePath, body: "", quotedHistory: nil, signature: nil, attachments: [],
        storeReferences: [], isPending: false, senderAddress: nil, linkedNote: nil
    )
}

@MainActor
@Suite(.serialized) struct PraticaFileOperationsSessionTests {
    // MARK: - "Sposta in..." (R-08): self-written, index in step, an open tab follows

    /// Red: today's raw `FileManager.moveItem` leaves the destination unrecognised as
    /// a self-write, so `session.reconcile` reports it as an external change - and the
    /// source path's disappearance closes the open tab instead of the door following
    /// it to its new home (ADR-0064/ADR-0067).
    @Test func moveFilesIsSelfWrittenAndAnOpenTabFollowsIt() async throws {
        let vault = try TemporaryVault()
        try vault.write(noteWithAttachmentTokens, to: "Rossi/email/msg.md")
        try vault.write("da: a@b.it", to: "Rossi/email/msg.eml")

        let controller = VaultController(recents: .volatile(), openTabs: .volatile())
        await controller.open(vault.root)
        controller.openNote(at: "Rossi/email/msg.md")
        let session = try #require(controller.session)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let ops = PraticaFileOperations(vault: controller, pratiche: pratiche)

        _ = await ops.moveFiles(of: praticaDetail(notePath: "Rossi/email/msg.md"), to: "Bianchi")

        let changes = await session.reconcile(["Bianchi/email/msg.md"])
        #expect(changes.isEmpty, "the move must be recorded as this session's own write, not an external change")

        let stillOpen = controller.columns[controller.focusedColumnIndex].tabs
            .contains { $0.note.relativePath == "Bianchi/email/msg.md" }
        #expect(stillOpen, "an open tab on the moved note must follow it to its new path, not close")
    }

    // MARK: - "Escludi" (R-08): the trash goes through the session and still reaches the watcher

    /// ADR-0064 §D6: an in-app trash stays visible to the watcher on purpose - no absence
    /// marker is recorded for a trash, unlike a move (`ExternalDeletionReconcileTests
    /// .aTrashedPathIsStillReportedDeleted`). What must be true instead, per ADR-0068's
    /// amended acceptance bullet, is that the trash actually went *through the session*:
    /// the index no longer holds the note, and the session announced `.trashed` for the
    /// vacated path - not that reconciling the path reports nothing.
    @Test func excludeTrashGoesThroughTheSessionAndStillReachesTheWatcher() async throws {
        let vault = try TemporaryVault()
        try vault.write(noteWithAttachmentTokens, to: "Rossi/email/msg.md")
        try vault.write("da: a@b.it", to: "Rossi/email/msg.eml")

        let controller = VaultController(recents: .volatile(), openTabs: .volatile())
        await controller.open(vault.root)
        let session = try #require(controller.session)
        var recorded: [VaultSession.LandedChange] = []
        session.landedChangeSubscriber = { recorded.append($0) }
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let ops = PraticaFileOperations(vault: controller, pratiche: pratiche)

        let trashed = await ops.trash(filesOf: "Rossi/email/msg.md")
        #expect(!trashed.isEmpty, "setup: the files must actually have been trashed")

        #expect(
            session.index.note(at: "Rossi/email/msg.md") == nil,
            "the trash must have gone through the session, which drops the note from its own index"
        )
        #expect(
            recorded.contains(.trashed("Rossi/email/msg.md")),
            "the session must announce the trash, exactly as trashFile(forgettingNoteID:) does"
        )

        let changes = await session.reconcile(["Rossi/email/msg.md"])
        #expect(
            changes == [VaultSession.ExternalChange(path: "Rossi/email/msg.md", content: .deleted)],
            "ADR-0064 §D6: an in-app trash still reaches the watcher as .deleted, no absence marker"
        )
    }

    /// Guard, not red: nothing today ever calls `session.trashFile`, so nothing ever
    /// forgets the note id either - the registry is simply untouched by the raw
    /// `FileManager.trashItem` call, which happens to already satisfy ADR-0059 §D6's
    /// "a Pratiche trash keeps the id" by omission. Recorded here so Task 4's real
    /// `trashFile(forgettingNoteID: false)` wiring cannot silently regress it.
    @Test func excludeTrashKeepsTheNoteId() async throws {
        let vault = try TemporaryVault()
        try vault.write(noteWithAttachmentTokens, to: "Rossi/email/msg.md")
        try vault.write("da: a@b.it", to: "Rossi/email/msg.eml")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let seedID = "3f2c9a4e-8b1d-4c67-9e2a-5d1b7c0e4f13"
        let registryFile = vault.root.appending(path: ".pergamenum/note-ids.json", directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: registryFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(NoteIDRegistry(version: 1, notes: [seedID: "Rossi/email/msg.md"])).write(to: registryFile)

        let controller = VaultController(recents: .volatile(), openTabs: .volatile())
        await controller.open(vault.root)
        let session = try #require(controller.session)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let ops = PraticaFileOperations(vault: controller, pratiche: pratiche)

        _ = await ops.trash(filesOf: "Rossi/email/msg.md")

        #expect(
            session.lookUpNote(id: seedID) == .found("Rossi/email/msg.md"),
            "ADR-0059 §D6: a Pratiche trash must keep the id, unlike an ordinary trash"
        )
    }

    // MARK: - Undo with chained attachment renames (R-09/§D4)

    /// Red: `reverseContentRewrites` applies one `FileManager` read-modify-write PER
    /// rename (`renameAttachmentReference(in:from:to:)`, called in a loop) rather
    /// than composing every inverted rename into one pass over the original text.
    /// Processed in this adversarial order - B's inverse rewrite runs first and
    /// recreates the exact token A's inverse rewrite is about to match - the second
    /// call catches the first call's own output and both attachments end up pointing
    /// at the same file, exactly the collision §D4 exists to prevent.
    @Test func undoOfChainedAttachmentRenamesLeavesEachLinkPointingAtItsOwnFile() async throws {
        let vault = try TemporaryVault()
        try vault.write(
            """
            ---
            date: 2026-09-01
            tags:
              - type-note
            pergamenum-mail-attachments:
              - "[[q-2.pdf]]"
              - "[[q-3.pdf]]"
            ---

            Corpo.
            """,
            to: "Rossi/email/msg.md"
        )
        let controller = VaultController(recents: .volatile(), openTabs: .volatile())
        await controller.open(vault.root)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let ops = PraticaFileOperations(vault: controller, pratiche: pratiche)

        // `attachmentRenames` holds the FORWARD renames (`from` = original name, `to` =
        // assigned name): A was `q.pdf -> q-2.pdf`, B was `q-2.pdf -> q-3.pdf`. The
        // adversarial order lists B before A, so B's inverse (q-3.pdf -> q-2.pdf) is
        // produced before A's inverse (q-2.pdf -> q.pdf) - a per-rename loop would then
        // recreate the exact token A's inverse is about to match, and
        // `reverseContentRewrites` must not depend on the order at all.
        let rewrites = PraticaFileOperations.ContentRewrites(
            originalBaseName: "msg", renamedBaseName: "msg",
            attachmentRenames: [
                .init(from: "q-2.pdf", to: "q-3.pdf"),
                .init(from: "q.pdf", to: "q-2.pdf"),
            ]
        )

        await ops.reverseContentRewrites(rewrites, notePath: "Rossi/email/msg.md")

        let text = try String(contentsOf: vault.root.appending(path: "Rossi/email/msg.md"), encoding: .utf8)
        #expect(text.contains("[[q.pdf]]"), "the first attachment must be restored to its own original name")
        #expect(
            text.contains("[[q-2.pdf]]"),
            """
            the second attachment must be restored to ITS own original name, distinct from the first - \
            red when a per-rename cascade collapses both onto the same token
            """
        )
    }

    // MARK: - Restore onto a taken path (R-08)

    /// Guard: today's raw `FileManager.moveItem(at:to:)` already refuses to overwrite
    /// an existing destination, so the file stays in the Trash and is reported as not
    /// restored - `restoreFailureMessage(for:)` already gives the sentence. Recorded
    /// so Task 4's `restoreFromOutside` keeps this property once it takes over.
    @Test func restoreOntoATakenPathIsRefusedAndTheFileStaysInTheTrash() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "restore-taken-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "Rossi/email", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let original = folder.appending(path: "msg.md", directoryHint: .notDirectory)
        // Something else now occupies the original path - a new message reusing the
        // same on-disk name after the original went to the Trash.
        try Data("occupied".utf8).write(to: original)
        let inTrash = root.appending(path: "trash-msg.md", directoryHint: .notDirectory)
        try Data("trashed".utf8).write(to: inTrash)
        let file = PraticaFileOperations.TrashedFile(original: original, inTrash: inTrash, relativePath: "Rossi/email/msg.md")
        let session = VaultSession(root: root, stateBase: root.appending(path: "state", directoryHint: .isDirectory))

        let failures = await PraticaFileOperations.restore([file], session: session)

        #expect(failures == [file])
        #expect(try Data(contentsOf: original) == Data("occupied".utf8), "the occupying file must be untouched")
        #expect(FileManager.default.fileExists(atPath: inTrash.path(percentEncoded: false)), "and the original stays recoverable in the Trash")
        #expect(PraticaFileOperations.restoreFailureMessage(for: failures) != nil)
    }
}
