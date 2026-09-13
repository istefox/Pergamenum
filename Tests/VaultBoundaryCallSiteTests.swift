import AppKit
import Foundation
import PDFKit
import Testing
@testable import Pergamenum

// ADR-0041 §D2, Task 2 (R-01, R-02): one adversarial test per guarded call site named in
// the ADR's Context table, plus the "tenth gap" it names separately - the three raw-bytes
// writers that bypass `NoteStore.write` entirely. Task 1's `Tests/VaultBoundaryTests.swift`
// already covers `NoteStore.read`/`write` themselves; this file is the other nine, plus the
// gap, for ten guarded sites in total (the SPEC's R-02, stated exactly).
//
// **Tester-only signature cascade (ADR-0155).** `NoteStore.url(for:)` becoming `throws` is
// declared here, mechanically, at every one of its 31 call sites (`try`/`try?` added, no
// behaviour changed) so the whole target still compiles; the four `Bool`/`URL?`-returning
// sites answer `false`/`nil` on a violation, per the plan's own decision. None of that wiring
// routes anything through `VaultBoundary` for real - every test below is red until the coder
// does that. `BoardCardActions.resolvedOpenURL(for:root:)` is a new, `nonisolated`, pure
// function extracted from `open(_:)` for the same reason the brief allows it: there is no
// other seam that does not drive `NSWorkspace` for real.
//
// Every test asserts on the file system (or the returned value, where nothing could have
// been written), not only on the thrown error - a guard that throws after writing is not a
// guard.

// MARK: - Shared fixture

/// A vault root nested two levels inside a throwaway container, so a `../../name` path
/// names a location the fixture also owns and cleans up - never a shared system directory.
/// Mirrors `Tests/VaultBoundaryTests.swift`'s own `BoundaryFixture`, which this file cannot
/// reuse (that one is `private` to its file).
private struct CallSiteFixture: ~Copyable {
    let container: URL
    let root: URL
    let stateBase: URL

    init() throws {
        let container = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-callsite-\(UUID().uuidString)", directoryHint: .isDirectory)
            .resolvingSymlinksInPath().standardizedFileURL
        let root = container.appending(path: "level/vault", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let stateBase = container.appending(path: "state", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: stateBase, withIntermediateDirectories: true)

        self.container = container
        self.root = root
        self.stateBase = stateBase
    }

    deinit {
        try? FileManager.default.removeItem(at: container)
    }

    @discardableResult
    func seed(_ data: Data, at url: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: url)
        return url
    }

    @discardableResult
    func seed(_ text: String, at url: URL) throws -> URL {
        try seed(Data(text.utf8), at: url)
    }
}

// MARK: - `CanvasStore.load(board:)` / `save(_:board:)`

@Test func canvasStoreLoadRefusesAPathEscapingTheVault() throws {
    let fixture = try CallSiteFixture()
    var sentinel = CanvasDocument()
    sentinel.nodes.append(CanvasNode(id: "a", kind: .text("outside sentinel"), x: 0, y: 0, width: 100, height: 100))
    // Two levels up from `container/level/vault` is `container` itself.
    let outside = fixture.container.appending(path: "evil.canvas")
    try fixture.seed(try sentinel.encoded(), at: outside)
    let store = CanvasStore(root: fixture.root)

    do {
        let loaded = try store.load(board: "../../evil.canvas")
        Issue.record(
            "load(board:) must refuse ../../evil.canvas; instead it read \(loaded.nodes.count) node(s) from outside the vault"
        )
    } catch {
        // Any thrown error is the refusal this test asks for - `CanvasStore.url(forBoard:)`
        // does not yet route through a boundary, so today nothing throws at all.
    }
}

@Test func canvasStoreSaveRefusesAPathEscapingTheVaultAndWritesNothingThere() throws {
    let fixture = try CallSiteFixture()
    let outside = fixture.container.appending(path: "evil-save.canvas")
    #expect(!FileManager.default.fileExists(atPath: outside.path(percentEncoded: false)))
    let store = CanvasStore(root: fixture.root)
    var document = CanvasDocument()
    document.nodes.append(CanvasNode(id: "a", kind: .text("must not land outside"), x: 0, y: 0, width: 100, height: 100))

    do {
        _ = try store.save(document, board: "../../evil-save.canvas")
        Issue.record("save(_:board:) must refuse ../../evil-save.canvas")
    } catch {
        // refusal
    }
    #expect(
        !FileManager.default.fileExists(atPath: outside.path(percentEncoded: false)),
        "save(_:board:) must never create a file outside the vault, even when it also fails to throw"
    )
}

// MARK: - `VaultSession.moveFile(from:to:)`

@MainActor
@Test func moveFileRefusesAnEscapingSourceAndLeavesTheOutsideFileInPlace() async throws {
    let fixture = try CallSiteFixture()
    let outside = fixture.container.appending(path: "level/outside-source.md")
    try fixture.seed("outside sentinel", at: outside)
    let session = VaultSession(root: fixture.root, stateBase: fixture.stateBase)

    var threw = false
    do {
        try session.moveFile(from: "../outside-source.md", to: "inside.md")
    } catch {
        threw = true
    }
    #expect(threw, "moveFile must refuse a source path escaping the vault")
    #expect(
        FileManager.default.fileExists(atPath: outside.path(percentEncoded: false)),
        "the file outside the vault must not have moved away from its original location"
    )
    #expect(!session.exists("inside.md"), "nothing must have landed inside the vault either")
}

@MainActor
@Test func moveFileRefusesAnEscapingDestinationAndLeavesTheSourceInPlace() async throws {
    let fixture = try CallSiteFixture()
    let session = VaultSession(root: fixture.root, stateBase: fixture.stateBase)
    try fixture.seed("inside sentinel", at: fixture.root.appending(path: "inside.md"))
    let outside = fixture.container.appending(path: "level/outside-destination.md")

    var threw = false
    do {
        try session.moveFile(from: "inside.md", to: "../outside-destination.md")
    } catch {
        threw = true
    }
    #expect(threw, "moveFile must refuse a destination path escaping the vault")
    #expect(session.exists("inside.md"), "the source must still be inside the vault")
    #expect(
        !FileManager.default.fileExists(atPath: outside.path(percentEncoded: false)),
        "nothing must have been written outside the vault"
    )
}

// MARK: - `VaultSession.trashFile(at:)`

@MainActor
@Test func trashFileRefusesAnEscapingPathAndLeavesTheSentinelOutOfTheTrash() async throws {
    let fixture = try CallSiteFixture()
    let outside = fixture.container.appending(path: "level/x.md")
    try fixture.seed("outside sentinel", at: outside)
    let session = VaultSession(root: fixture.root, stateBase: fixture.stateBase)

    var threw = false
    do {
        try session.trashFile(at: "../x.md")
    } catch {
        threw = true
    }
    #expect(threw, "trashFile must refuse a path escaping the vault")
    #expect(
        FileManager.default.fileExists(atPath: outside.path(percentEncoded: false)),
        "the sentinel outside the vault must still be exactly where it was, not moved to the Trash"
    )
}

// MARK: - `ThumbnailStore.thumbnail(for:width:)`

@Test func thumbnailAnswersNilForAPathEscapingTheVaultEvenWhenARealFileSitsThere() async throws {
    let fixture = try CallSiteFixture()
    // Two levels up from `container/level/vault` lands on `container/Pictures/x.pdf`.
    let outside = fixture.container.appending(path: "Pictures/x.pdf")

    let image = NSImage(size: NSSize(width: 10, height: 10))
    image.lockFocus()
    NSColor.red.setFill()
    NSRect(x: 0, y: 0, width: 10, height: 10).fill()
    image.unlockFocus()
    guard let page = PDFPage(image: image) else {
        Issue.record("could not build the PDFPage fixture")
        return
    }
    let document = PDFDocument()
    document.insert(page, at: 0)
    guard let data = document.dataRepresentation() else {
        Issue.record("could not encode the PDFPage fixture")
        return
    }
    try fixture.seed(data, at: outside)

    let cacheDirectory = fixture.container.appending(path: "cache", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    let store = ThumbnailStore(root: fixture.root, directory: cacheDirectory)

    // A real, PDFKit-renderable file (not the brief's literal `.png`, to avoid depending on
    // the QuickLook XPC service being reachable inside the test process) sits exactly where
    // "../../Pictures/x.pdf" resolves - which is what makes this adversarial rather than
    // merely absent: the unfixed store finds it and renders it with PDFKit synchronously.
    let task = await store.thumbnail(for: "../../Pictures/x.pdf", width: 200)
    let rendered = await task.value
    #expect(rendered == nil, "a path escaping the vault must never be rendered, even when a real file sits there")
}

// MARK: - `WorkspaceController.fileURL(for:)`

@MainActor
@Test func workspaceControllerFileURLAnswersNilForANodeWhoseFileEscapesTheVault() throws {
    let fixture = try CallSiteFixture()
    let store = CanvasStore(root: fixture.root)
    let controller = WorkspaceController()
    controller.attach(to: store)
    let node = CanvasNode(
        id: "a", kind: .file(path: "../../etc/passwd", subpath: nil), x: 0, y: 0, width: 100, height: 100
    )

    #expect(controller.fileURL(for: node) == nil, "a node whose file escapes the vault must resolve to no URL at all")
}

// MARK: - `BoardCardMenu`'s open-in-Finder branch

// `BoardCardActions.open(_:)` itself drives `NSWorkspace.shared.open`, a real Finder/app
// launch with no return value to assert on - not a testable seam. `resolvedOpenURL(for:
// root:)` is the pure decision `open(_:)` now delegates to (declared by this task's tester,
// per the brief's own "extract a testable pure function" allowance); it still reproduces
// `open(_:)`'s exact prior behaviour, so this test is red until the coder wires it through
// `VaultBoundary`.
@Test func resolvedOpenURLAnswersNilForAPathEscapingTheVault() {
    let root = URL(fileURLWithPath: "/tmp/pergamenum-fixture-vault-\(UUID().uuidString)", isDirectory: true)

    #expect(
        BoardCardActions.resolvedOpenURL(for: "../../etc/passwd", root: root) == nil,
        "a card's file path escaping the vault must resolve to no URL for NSWorkspace to open"
    )
}

// MARK: - `PraticheController.readTimeline`

@Test func readTimelineNeverResolvesAnAttachmentNameEscapingTheVault() throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "pergamenum-pratica-callsite-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let praticaPath = "Rossi/Offerta"
    let messagesFolder = root.appending(
        path: "\(praticaPath)/\(PraticheController.messagesDirectoryName)", directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: messagesFolder, withIntermediateDirectories: true)

    let document = MessageDocument(
        frontmatter: MessageDocument.MailFrontmatter(
            schemaVersion: 1, messageID: "<escape@rossi-spa.it>", conversationID: 1, direction: .received,
            date: Date(timeIntervalSince1970: 1_749_557_170), received: nil,
            from: "m.rossi@rossi-spa.it", to: [], cc: [], subject: "Offerta",
            attachments: ["[[../../../secret.pdf]]"], body: .complete, original: nil
        ),
        newText: "Testo del messaggio.", quotedHistory: nil, signature: nil
    )
    let text = MessageDocument.render(document, tags: [Tag(namespace: .type, value: "email")])
    try text.write(
        to: messagesFolder.appending(path: "20260610_1406_Rossi_offerta.md", directoryHint: .notDirectory),
        atomically: true, encoding: .utf8
    )

    let read = PraticheController.readTimeline(praticaPath: praticaPath, vaultRoot: root)

    // Either acceptable outcome the brief names: the read refuses the row entirely, or the
    // row is produced with the escaping attachment omitted. Silently resolving it into a
    // `PraticaAttachmentRef` (today's behaviour: `linkedAttachmentNames` unwraps the
    // wikilink verbatim and hands it straight to `attachments.appending(path:)`) is neither.
    if let entry = read.entries.first {
        let detail = try #require(read.details[entry.id])
        #expect(
            !detail.attachments.contains { $0.name.contains("..") },
            "an attachment name escaping the vault must never be resolved into a PraticaAttachmentRef"
        )
    }
}

// MARK: - `PraticaSyncEngine.regenerationPreview`

@Test func regenerationPreviewRefusesAPraticaFolderEscapingTheVault() async throws {
    let fixture = try MailStoreFixture.build(
        mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
        messages: [.init(
            rowID: 1, subject: "Richiesta offerta", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
            conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1000),
            dateReceived: Date(timeIntervalSince1970: 1000), emlxBody: EmailFixtureCorpus.completeMessageRFC822
        )]
    )
    // Both `vaultRoot` and the `../evil` sibling this test plants below live inside one
    // UUID-named container, so the traversal fixture's own escape - and its cleanup - never
    // reaches outside a directory this test run alone owns (a bare `temporaryDirectory/evil`
    // sibling would collide with, and delete, another concurrent run's own fixture).
    let container = FileManager.default.temporaryDirectory
        .appending(path: "pergamenum-sync-callsite-\(UUID().uuidString)", directoryHint: .isDirectory)
    let vaultRoot = container.appending(path: "vault", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: vaultRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: container) }
    let engine = PraticaSyncEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot) { text, relativePath in
        let url = vaultRoot.appending(path: relativePath, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(text.utf8).write(to: url, options: .atomic)
    }
    let candidate = MailMessageRow(
        rowID: 1, indexMessageIDHash: nil, globalMessageID: nil,
        subject: "Richiesta offerta", sender: "m.rossi@rossi-spa.it",
        dateSent: Date(timeIntervalSince1970: 1000), dateReceived: Date(timeIntervalSince1970: 1000),
        mailbox: MailboxRef(rowID: 1, url: "ews://acct1/INBOX"),
        conversationID: 112_409, deleted: false, messageID: "<abc123@rossi-spa.it>"
    )
    let dossier = Dossier(
        schemaVersion: 1, counterparts: ["m.rossi@rossi-spa.it"], conversations: [112_409],
        keywords: [], included: [], excluded: [], ignored: []
    )
    let request = PraticaSyncEngine.SyncRequest(
        praticaFolder: "../evil", dossier: dossier, candidates: [candidate], onDisk: [], settings: .default
    )

    // Without this planted file, "../evil/email/…" does not exist, and today's unguarded
    // code (`vaultRoot.appending(path: request.praticaFolder)` in `directory(_:of:)`, then
    // `String(contentsOf:)` at the final read) throws `RegenerationFailure.fileMissing` for
    // an unrelated reason - a coincidental pass, not a demonstration of anything. Seeding a
    // real message file there, with the same `Message-ID` the candidate carries, makes
    // `regeneration.regenerating = messageID` match it as `existing` (`isRequestedRegeneration`
    // is true), which is how `prepared.fileName` becomes deterministic without duplicating
    // `PraticaNaming`'s slug/date logic in this test - and it is what makes today's read
    // actually succeed, reading the sentinel straight out of the escaped location.
    // `../evil` resolves to a sibling of `vault` inside `container` - the `defer` above
    // already owns and removes it, so no second cleanup is needed here.
    let escapedEmailDirectory = vaultRoot.appending(path: "../evil/email", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: escapedEmailDirectory, withIntermediateDirectories: true)
    let escapedDocument = MessageDocument(
        frontmatter: MessageDocument.MailFrontmatter(
            schemaVersion: 1, messageID: "<abc123@rossi-spa.it>", conversationID: 112_409, direction: .received,
            date: Date(timeIntervalSince1970: 1000), received: nil,
            from: "m.rossi@rossi-spa.it", to: [], cc: [], subject: "Richiesta offerta",
            attachments: [], body: .complete, original: nil
        ),
        newText: "SENTINEL: this text lives outside the vault and must never reach a RegenerationPlan.",
        quotedHistory: nil, signature: nil
    )
    let escapedText = MessageDocument.render(escapedDocument, tags: [Tag(namespace: .type, value: "email")])
    try escapedText.write(
        to: escapedEmailDirectory.appending(path: "sentinel.md", directoryHint: .notDirectory),
        atomically: true, encoding: .utf8
    )

    do {
        let plan = try await engine.regenerationPreview(request, messageID: "<abc123@rossi-spa.it>", rowID: nil)
        Issue.record(
            "regenerationPreview must refuse a praticaFolder escaping the vault, got a plan reading \(plan.notePath) with text \(plan.currentText)"
        )
    } catch {
        // A `RegenerationFailure` or a boundary violation are both acceptable refusals - the
        // brief's own wording. Silently reading whatever sits at "../evil/email/…" is not.
    }
}

// MARK: - The tenth gap: the three raw-bytes writers (`Data(...).write(to: store.url(for:…))`)

// `FolderFileOperations.swift:322`, `BoardFileOperations.swift:172` and `:286` all write a
// repointed board's re-encoded JSON straight to disk, bypassing `NoteStore.write` and, until
// the coder wires `NoteStore.url(for:)` through `VaultBoundary`, its guard too. Reaching one
// of those three lines specifically with a caller-controlled escaping `change.path` needs a
// board that references another board being renamed/moved - and every path that could name
// is validated upstream (`NoteName.validate` rejects "/" in a new name, which is what
// `renameFolder`/`renameBoard` take). `BoardFileOperations.moveBoard(at:toFolder:)` is the one
// entry point in this family whose destination (`toFolder`) is *not* run through
// `NoteName.validate` - only `Self.normalized` (a slash trim) - so it is the one place this
// task's ten guarded call sites reach the same class of unguarded write for real, by the move
// itself rather than by the board-content rewrite loop specifically. Both share the identical
// `try store.url(for: …)` shape this task adds throughout `BoardFileOperations.swift`.
@Test func moveBoardRefusesADestinationFolderEscapingTheVault() throws {
    let fixture = try CallSiteFixture()
    let boardPath = "board.canvas"
    try fixture.seed(#"{"nodes":[],"edges":[]}"#, at: fixture.root.appending(path: boardPath))
    let operations = BoardFileOperations(store: NoteStore(root: fixture.root))

    var threw = false
    do {
        _ = try operations.moveBoard(at: boardPath, toFolder: "../evil")
    } catch {
        threw = true
    }
    #expect(threw, "moveBoard must refuse a destination folder escaping the vault")
    #expect(
        FileManager.default.fileExists(atPath: fixture.root.appending(path: boardPath).path(percentEncoded: false)),
        "the board must still be inside the vault"
    )
    let escapedDestination = fixture.container.appending(path: "level/evil").appending(path: boardPath)
    #expect(
        !FileManager.default.fileExists(atPath: escapedDestination.path(percentEncoded: false)),
        "nothing must have been written to the escaping destination folder"
    )
}
