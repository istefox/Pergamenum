import Foundation

// ADR-0049 (Pratiche links to notes, tasks and boards), plan
// docs/plans/pratiche-note-task-workspace-links.md, Task 7 - R-01, R-02, R-03, R-10, §D12.

/// Reading and writing a pratica's links to notes, tasks and boards, and a single
/// message's linked note (§D12).
///
/// `VaultPratiche.swift`'s header rule applies here verbatim, and is repeated rather
/// than assumed: **no `MailStore`, `EMLXReader` or `SQLite3` name may appear in this
/// file** (ADR-0036 R-36) - every byte read here was written to the vault by a sync
/// that already ran, or by a person, never read from Mail directly.
///
/// Mirrors, rather than calls, `PraticaCommandActions`' app-side functions
/// (`Sources/Features/Pratiche/PraticaCommandActions+Links.swift`) for the same reason
/// `VaultPratiche.swift`'s own header states for `pratiche(_:)`: that file imports
/// AppKit/SwiftUI and is not in `sharedSources`, so the read-modify-write shape is
/// reproduced here over the same `Sources/Core` primitives, never called into.
extension VaultAPI {
    /// One resolved reference (R-08's three-state shape, carried onto the wire):
    /// `path` is the resolved target only when `state` is `unique` - an ambiguous or
    /// missing reference has nothing a client could safely open.
    struct PraticaLinkTarget: Encodable {
        let reference: String
        let state: String
        let path: String?
    }

    /// `pratica <title|path> links` → the three general relations, each reference
    /// resolved against the vault as it is now (SPEC "Connectors").
    struct PraticaLinksPayload: Encodable {
        let path: String
        let notes: [PraticaLinkTarget]
        let tasks: [PraticaLinkTarget]
        let boards: [PraticaLinkTarget]
    }

    // MARK: - Reading

    @MainActor
    static func praticaLinks(_ session: VaultSession, _ reference: String) throws -> PraticaLinksPayload {
        let folder = try pratica(session, reference).path
        let url = session.root.appending(
            path: PraticaNaming.praticaNotePath(of: folder), directoryHint: .notDirectory
        )
        let links = PraticaLinks.parse(praticaFileAt: url)
        let boards = CanvasStore(root: session.root).allBoards()

        return PraticaLinksPayload(
            path: folder,
            notes: links.notes.map { noteTarget($0, session: session) },
            tasks: links.tasks.map { taskTarget($0, session: session) },
            boards: links.boards.map { boardTarget($0, boards: boards) }
        )
    }

    /// The per-message relation of one timeline entry, resolved the same way - `nil`
    /// when the message carries no `pergamenum-mail-note` at all, which is a different
    /// thing from a broken one (R-08's own distinction).
    @MainActor
    static func praticaMessageLink(_ session: VaultSession, at relativePath: String) throws -> PraticaLinkTarget? {
        guard session.exists(relativePath) else { throw ConnectorError("«\(relativePath)» non esiste") }
        let (_, text) = try session.read(relativePath)
        guard let linkedNote = MessageDocument.parse(text)?.frontmatter.linkedNote else { return nil }
        guard case let .wikilink(title) = PraticaLinkReference(parsing: linkedNote) else { return nil }
        return noteTarget(title, session: session)
    }

    /// Not `private` (ADR-0045 §D2): `VaultPratiche.swift`'s `messageRows` resolves a
    /// message's own linked note the same way, and `private` is file-scoped.
    @MainActor
    static func noteTarget(_ title: String, session: VaultSession) -> PraticaLinkTarget {
        let resolution = PraticaLinkResolver.note(candidates: session.index.resolve(title: title))
        return PraticaLinkTarget(
            reference: PraticaLinkReference.wikilink(title).rendered,
            state: state(of: resolution), path: path(of: resolution)
        )
    }

    private static func boardTarget(_ fileName: String, boards: [String]) -> PraticaLinkTarget {
        let resolution = PraticaLinkResolver.board(fileName, boards: boards)
        return PraticaLinkTarget(
            reference: PraticaLinkReference.wikilink(fileName).rendered,
            state: state(of: resolution), path: path(of: resolution)
        )
    }

    /// A task reference's note half resolves like `noteTarget`; its `^id` half is then
    /// looked up among the `localID`s of whichever note that resolved to, exactly as
    /// `PraticaLinkResolver.task` asks for (it never reads a file itself).
    @MainActor
    private static func taskTarget(_ ref: PraticaLinks.TaskReference, session: VaultSession) -> PraticaLinkTarget {
        let candidates = session.index.resolve(title: ref.noteTitle)
        var localIDs: [Int] = []
        if candidates.count == 1, let text = try? session.read(candidates[0]).text {
            localIDs = TaskParser.tasks(in: text, sourcePath: candidates[0]).compactMap(\.localID)
        }
        let resolution = PraticaLinkResolver.task(
            localID: ref.localID, noteCandidates: candidates, localIDsInResolvedNote: localIDs
        )
        return PraticaLinkTarget(
            reference: PraticaLinkReference.task(noteTitle: ref.noteTitle, localID: ref.localID).rendered,
            state: state(of: resolution), path: path(of: resolution)
        )
    }

    private static func state(of resolution: PraticaLinkResolution) -> String {
        switch resolution {
        case .unique: "unique"
        case .ambiguous: "ambiguous"
        case .missing: "missing"
        }
    }

    private static func path(of resolution: PraticaLinkResolution) -> String? {
        if case let .unique(path) = resolution { path } else { nil }
    }

    // MARK: - Writing: the pratica's three general relations (R-01)

    @MainActor
    static func linkPraticaNote(
        _ session: VaultSession, pratica reference: String, title: String
    ) async throws -> WriteSummary {
        guard !title.isEmpty else { throw ConnectorError("serve il titolo della nota", usage: true) }
        let folder = try pratica(session, reference).path
        return try await updateLinks(session, at: folder) { links in
            guard !links.notes.contains(title) else { return }
            links.notes.append(title)
        }
    }

    @MainActor
    static func unlinkPraticaNote(
        _ session: VaultSession, pratica reference: String, title: String
    ) async throws -> WriteSummary {
        guard !title.isEmpty else { throw ConnectorError("serve il titolo della nota", usage: true) }
        let folder = try pratica(session, reference).path
        return try await updateLinks(session, at: folder) { links in
            links.notes.removeAll { $0 == title }
        }
    }

    @MainActor
    static func linkPraticaBoard(
        _ session: VaultSession, pratica reference: String, board: String
    ) async throws -> WriteSummary {
        guard !board.isEmpty else { throw ConnectorError("serve il nome della board", usage: true) }
        let folder = try pratica(session, reference).path
        let name = WorkspaceBoardResolver.fileName(of: board)
        return try await updateLinks(session, at: folder) { links in
            guard !links.boards.contains(name) else { return }
            links.boards.append(name)
        }
    }

    @MainActor
    static func unlinkPraticaBoard(
        _ session: VaultSession, pratica reference: String, board: String
    ) async throws -> WriteSummary {
        guard !board.isEmpty else { throw ConnectorError("serve il nome della board", usage: true) }
        let folder = try pratica(session, reference).path
        let name = WorkspaceBoardResolver.fileName(of: board)
        return try await updateLinks(session, at: folder) { links in
            links.boards.removeAll { $0 == name }
        }
    }

    /// R-01, ADR §D3: `needle` is resolved the same way `task change` already resolves
    /// one (`VaultLookup.task(_:matching:)`), then allocates a `^id` first when the
    /// chosen task does not carry one yet.
    @MainActor
    static func linkPraticaTask(
        _ session: VaultSession, pratica reference: String, task needle: String
    ) async throws -> WriteSummary {
        guard !needle.isEmpty else {
            throw ConnectorError("serve il testo del task, oppure percorso:riga", usage: true)
        }
        let folder = try pratica(session, reference).path
        let target = try task(session, matching: needle)
        let (noteTitle, localID) = try await ensuringLocalID(session, for: target)
        return try await updateLinks(session, at: folder) { links in
            guard !links.tasks.contains(where: { $0.noteTitle == noteTitle && $0.localID == localID }) else { return }
            links.tasks.append(.init(noteTitle: noteTitle, localID: localID))
        }
    }

    @MainActor
    static func unlinkPraticaTask(
        _ session: VaultSession, pratica reference: String, task needle: String
    ) async throws -> WriteSummary {
        guard !needle.isEmpty else {
            throw ConnectorError("serve il testo del task, oppure percorso:riga", usage: true)
        }
        let folder = try pratica(session, reference).path
        let target = try task(session, matching: needle)
        guard let localID = target.localID else {
            return WriteSummary(
                path: PraticaNaming.praticaNotePath(of: folder), applied: false, diff: nil,
                note: "il task non ha un ^id: non è collegato a nessuna pratica"
            )
        }
        let noteTitle = NoteName.title(fromFileName: (target.sourcePath as NSString).lastPathComponent)
        return try await updateLinks(session, at: folder) { links in
            links.tasks.removeAll { $0.noteTitle == noteTitle && $0.localID == localID }
        }
    }

    // MARK: - Writing: the message's one relation (R-02, §D6)

    @MainActor
    static func linkMessageNote(
        _ session: VaultSession, message relativePath: String, title: String
    ) async throws -> WriteSummary {
        guard !title.isEmpty else { throw ConnectorError("serve il titolo della nota", usage: true) }
        return try await updateMessageNote(
            session, at: relativePath, reference: PraticaLinkReference.wikilink(title).rendered
        )
    }

    @MainActor
    static func unlinkMessageNote(_ session: VaultSession, message relativePath: String) async throws -> WriteSummary {
        try await updateMessageNote(session, at: relativePath, reference: nil)
    }

    @MainActor
    private static func updateMessageNote(
        _ session: VaultSession, at relativePath: String, reference: String?
    ) async throws -> WriteSummary {
        guard session.exists(relativePath) else { throw ConnectorError("«\(relativePath)» non esiste") }
        do {
            let (record, text) = try session.read(relativePath)
            let line = reference.map(MessageDocument.noteLine(for:))
            guard let patched = MessageFrontmatterPatch.applying(
                line: line, forKey: MessageDocument.noteKey,
                before: [MessageDocument.storeReferencesKey, "pergamenum-mail-body"], to: text
            ) else {
                throw ConnectorError("«\(relativePath)»: frontmatter non valido")
            }
            guard patched != text else {
                return WriteSummary(path: relativePath, applied: false, diff: nil, note: "nessuna modifica")
            }
            let result = try await session.write(patched, to: relativePath, expecting: record.contentHash)
            return summarise(result, session: session)
        } catch let refusal as VaultSession.WriteRefusal {
            throw ConnectorError("«\(relativePath)» non è stato aggiornato: \(refusal.description)")
        }
    }

    // MARK: - Writing: create a target already linked (R-03)

    @MainActor
    static func createAndLinkPraticaNote(
        _ session: VaultSession, pratica reference: String, title: String, folder: String?
    ) async throws -> WriteSummary {
        guard !title.isEmpty else { throw ConnectorError("serve un titolo per la nota", usage: true) }
        let praticaFolder = try pratica(session, reference).path
        _ = try await session.createNote(
            title: title, in: folder ?? "", date: .today, topics: praticaContextTags(session, at: praticaFolder)
        )
        return try await linkPraticaNote(session, pratica: praticaFolder, title: title)
    }

    @MainActor
    static func createAndLinkPraticaTask(
        _ session: VaultSession, pratica reference: String, text: String
    ) async throws -> WriteSummary {
        guard !text.isEmpty else { throw ConnectorError("serve il testo del task", usage: true) }
        let praticaFolder = try pratica(session, reference).path
        guard let result = await session.captureTask(.init(text: text)) else {
            throw ConnectorError("non scritto: \(session.problems.last ?? "motivo sconosciuto")")
        }
        guard let created = TaskParser.tasks(in: result.text, sourcePath: result.path).last else {
            throw ConnectorError("il task appena creato non è stato trovato in «\(result.path)»")
        }
        let (noteTitle, localID) = try await ensuringLocalID(session, for: created)
        return try await updateLinks(session, at: praticaFolder) { links in
            guard !links.tasks.contains(where: { $0.noteTitle == noteTitle && $0.localID == localID }) else { return }
            links.tasks.append(.init(noteTitle: noteTitle, localID: localID))
        }
    }

    @MainActor
    static func createAndLinkPraticaBoard(
        _ session: VaultSession, pratica reference: String, name: String, folder: String?
    ) async throws -> WriteSummary {
        guard !name.isEmpty else { throw ConnectorError("serve un nome per la board", usage: true) }
        let praticaFolder = try pratica(session, reference).path
        do {
            let created = try CanvasStore(root: session.root).createBoard(named: name, in: folder ?? "")
            await session.rescan()
            return try await linkPraticaBoard(session, pratica: praticaFolder, board: created)
        } catch let error as CanvasStore.StoreError {
            throw ConnectorError("\(error)")
        }
    }

    @MainActor
    static func createAndLinkMessageNote(
        _ session: VaultSession, message relativePath: String, title: String
    ) async throws -> WriteSummary {
        guard !title.isEmpty else { throw ConnectorError("serve un titolo per la nota", usage: true) }
        guard session.exists(relativePath) else { throw ConnectorError("«\(relativePath)» non esiste") }
        let praticaFolder = try praticaFolder(ofMessageAt: relativePath)
        _ = try await session.createNote(
            title: title, in: "", date: .today, topics: praticaContextTags(session, at: praticaFolder)
        )
        return try await linkMessageNote(session, message: relativePath, title: title)
    }

    // MARK: - Plumbing

    /// One read-modify-write of a pratica's general links - `PraticaLinksWriter`'s
    /// shape, reproduced here (see this file's header) rather than called, turned into
    /// a `WriteSummary` so a dry run answers with a diff like every other connector
    /// write.
    @MainActor
    private static func updateLinks(
        _ session: VaultSession, at praticaPath: String, _ change: (inout PraticaLinks) -> Void
    ) async throws -> WriteSummary {
        let notePath = PraticaNaming.praticaNotePath(of: praticaPath)
        do {
            let (record, text) = try session.read(notePath)
            var document = NoteDocument.parse(text)
            let before = document
            var links = PraticaLinks.parse(document.frontmatter.foreignKeys)
            change(&links)
            document.frontmatter.foreignKeys = PraticaLinks.merging(links, into: document.frontmatter.foreignKeys)
            guard document != before else {
                return WriteSummary(path: notePath, applied: false, diff: nil, note: "nessuna modifica")
            }
            let result = try await session.write(document.serialized(), to: notePath, expecting: record.contentHash)
            return summarise(result, session: session)
        } catch let refusal as VaultSession.WriteRefusal {
            throw ConnectorError("«\(notePath)» non è stato aggiornato: \(refusal.description)")
        }
    }

    /// Allocates `task`'s `^id` when it does not have one yet (ADR §D3), mirroring
    /// `PraticaCommandActions.ensuringLocalID` on the app side (see this file's header
    /// for why it is reproduced rather than called).
    @MainActor
    private static func ensuringLocalID(
        _ session: VaultSession, for task: TaskItem
    ) async throws -> (noteTitle: String, localID: Int) {
        let noteTitle = NoteName.title(fromFileName: (task.sourcePath as NSString).lastPathComponent)
        if let localID = task.localID { return (noteTitle, localID) }
        do {
            let (record, text) = try session.read(task.sourcePath)
            let localID = TaskParser.nextLocalID(in: text)
            let newLine = TaskParser.line(for: task, assigningLocalID: localID)
            guard let updated = TaskParser.rewrite(text, at: task.lineIndex, expecting: task.rawLine, with: newLine)
            else {
                throw ConnectorError("il task non è più dove risultava: \(task.sourcePath)")
            }
            _ = try await session.write(updated, to: task.sourcePath, expecting: record.contentHash)
            return (noteTitle, localID)
        } catch let refusal as VaultSession.WriteRefusal {
            throw ConnectorError("«\(task.sourcePath)» non è stato aggiornato: \(refusal.description)")
        }
    }

    /// The pratica's own `topic-pratica`/`client-<slug>` tags (R-03), for a note
    /// created from context - `PraticaCommandActions.praticaContextTags`'s own
    /// computation, over the same `PraticaNaming.clientTag(forPraticaAt:root:)`.
    @MainActor
    private static func praticaContextTags(_ session: VaultSession, at praticaPath: String) -> [Tag] {
        [
            Tag("topic-pratica"),
            PraticaNaming.clientTag(forPraticaAt: praticaPath, root: session.settings.pratiche.rootFolder),
        ].compactMap { $0 }
    }

    /// Which pratica a message belongs to: the folder its file sits in - the same
    /// arithmetic `PraticaCommandActions.praticaPath(detail:)` performs on the app
    /// side, without that type's fallback to a UI selection, which a connector call
    /// has none of.
    private static func praticaFolder(ofMessageAt relativePath: String) throws -> String {
        // "email", `VaultPratiche.swift`'s own private `messagesDirectoryName` copy,
        // unreachable from this file (`private extension`) - the same duplicated
        // literal `PraticheController.messagesDirectoryName` already carries on the
        // app side.
        guard let range = relativePath.range(of: "/email/") else {
            throw ConnectorError("«\(relativePath)» non è il messaggio di una pratica (manca /email/)")
        }
        return String(relativePath[..<range.lowerBound])
    }
}
