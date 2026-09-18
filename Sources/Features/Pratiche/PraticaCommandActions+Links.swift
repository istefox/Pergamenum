import Foundation

// ADR-0049 (Pratiche links to notes, tasks and boards), plan
// docs/plans/pratiche-note-task-workspace-links.md, Task 4 - R-01, R-02, R-03,
// §D10/§D11.
//
// Pure extension split (ADR-0045 §D2, PG-143's shape): `PraticaCommandActions.swift`
// crossed `type_body_length` the moment these functions were added, and this section
// has no second responsibility to justify a new type - it is the same picker-to-write
// plumbing the primary file already hosts, including the message-note relation itself
// (`linkNote(_:toMessageAt:)`, moved here once the primary file crossed its ceiling a
// second time - both of its call sites already lived in this file). `reload()` and
// `praticaPath(detail:)` widen from `private` to `internal` there for this file to
// reach them (`private` is file-scoped).

extension PraticaCommandActions {
    /// `.linkNote`/`.linkTask`/`.linkBoard` share this: same scope, same request shape,
    /// only the `Kind` and the context tags (a note is the only target that reads
    /// `praticaContextTags`) differ. Kept out of `run(_:on:)`'s own switch to keep that
    /// function's complexity down (was 3 separate cases, each with its own literal).
    /// Not `private` in the primary file (ADR-0045 §D2): moved here once the primary
    /// file's `type_body_length` crossed its ceiling, and `run(_:on:)` there still
    /// calls it.
    func requestLink(_ command: PraticaCommand, for pratica: PraticaListItem) {
        let kind: PraticaLinkRequest.Kind
        switch command {
        case .linkNote: kind = .note
        case .linkTask: kind = .task
        case .linkBoard: kind = .board
        default: return
        }
        navigation.praticaLinkRequest = PraticaLinkRequest(
            kind: kind, scope: .pratica(path: pratica.id), contextTitle: pratica.title,
            contextTags: kind == .note ? praticaContextTags(at: pratica.id) : []
        )
    }

    /// `.linkNote`/`.unlinkNote` share this: both are the message's one relation
    /// (§D6), one opening the picker, one writing directly. Kept out of
    /// `run(_:on:detail:)`'s own switch to keep that function's complexity down. Same
    /// widening reason as `requestLink` above.
    func handleNoteLink(_ command: MessageCommand, entry: PraticaTimelineEntry, detail: PraticaRowDetail?) {
        switch command {
        case .linkNote:
            guard let detail, let praticaPath = praticaPath(detail: detail) else { return }
            navigation.praticaLinkRequest = PraticaLinkRequest(
                kind: .note, scope: .message(notePath: detail.notePath),
                contextTitle: entry.subject, contextTags: praticaContextTags(at: praticaPath)
            )
        case .unlinkNote:
            guard let detail else { return }
            Task { @MainActor in await linkNote(nil, toMessageAt: detail.notePath) }
        default:
            break
        }
    }

    /// The pratica's own `topic-pratica`/`client-<slug>` tags (R-03), for a note
    /// created from context - the two `NuovaPraticaWizard+Actions.tags(for:)` computes
    /// for a manual timeline entry that are not specific to that entry's own kind. Same
    /// widening reason as `requestLink` above.
    func praticaContextTags(at praticaPath: String) -> [Tag] {
        [
            Tag("topic-pratica"),
            PraticaNaming.clientTag(forPraticaAt: praticaPath, root: vault.settings.pratiche.rootFolder),
        ].compactMap { $0 }
    }

    /// R-02: the note linked to a single message (`pergamenum-mail-note`), written
    /// through the same one-line surgery ADR-0042 §D8 generalized for exactly this
    /// reason - every other byte of the file stays untouched. `reference` is the
    /// wikilink text (`PraticaLinkReference.wikilink(_:).rendered`); `nil` unlinks,
    /// removing the key rather than writing an empty value, the behaviour
    /// `MessageFrontmatterPatch` already has.
    ///
    /// Not a sync trigger (ADR §D6, ADR-0036 §D6 stays at four): this is a person's
    /// explicit action on one file, run once, from a command.
    func linkNote(_ reference: String?, toMessageAt relativePath: String) async {
        guard let session = vault.session else { return }
        do {
            let (record, text) = try session.read(relativePath)
            let line = reference.map(MessageDocument.noteLine(for:))
            guard let patched = MessageFrontmatterPatch.applying(
                line: line, forKey: MessageDocument.noteKey,
                before: [MessageDocument.storeReferencesKey, "pergamenum-mail-body"], to: text
            ) else {
                pratiche.report("«\(relativePath)» non è stato aggiornato: frontmatter non valido.")
                return
            }
            guard patched != text else { return }
            try await session.write(patched, to: relativePath, expecting: record.contentHash)
            reload()
        } catch let refusal as VaultSession.WriteRefusal {
            pratiche.report("«\(relativePath)» non è stato aggiornato: \(refusal.description)")
        } catch {
            pratiche.report("«\(relativePath)» non è stato aggiornato: \(error.localizedDescription)")
        }
    }

    /// Commits the picker's chosen existing note - a pratica's general link (§D1), or
    /// (message scope) the message's single `pergamenum-mail-note`, which replaces
    /// rather than appends (R-02).
    func linkExistingNote(titled title: String, for request: PraticaLinkRequest) async {
        switch request.scope {
        case .message(let notePath):
            await linkNote(PraticaLinkReference.wikilink(title).rendered, toMessageAt: notePath)
        case .pratica(let praticaPath):
            await updateLinks(at: praticaPath) { links in
                guard !links.notes.contains(title) else { return }
                links.notes.append(title)
            }
        }
    }

    /// R-01: the pratica-only board relation.
    func linkExistingBoard(at path: String, for request: PraticaLinkRequest) async {
        guard case .pratica(let praticaPath) = request.scope else { return }
        let name = WorkspaceBoardResolver.fileName(of: path)
        await updateLinks(at: praticaPath) { links in
            guard !links.boards.contains(name) else { return }
            links.boards.append(name)
        }
    }

    /// R-01, ADR §D3: the pratica-only task relation - allocates a `^id` first when
    /// the chosen task does not carry one yet.
    func linkExistingTask(_ task: TaskItem, for request: PraticaLinkRequest) async {
        guard case .pratica(let praticaPath) = request.scope,
              let (noteTitle, localID) = await ensuringLocalID(for: task)
        else { return }
        await updateLinks(at: praticaPath) { links in
            guard !links.tasks.contains(where: { $0.noteTitle == noteTitle && $0.localID == localID }) else { return }
            links.tasks.append(.init(noteTitle: noteTitle, localID: localID))
        }
    }

    /// R-03: creates a note pre-filled from `request`'s context, then links it -
    /// create first, link second, so a link never points at a note that failed to be
    /// created.
    func createAndLinkNote(titled rawTitle: String, for request: PraticaLinkRequest) async {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        do {
            _ = try await vault.createNote(title: title, in: "", date: .today, topics: request.contextTags)
            await linkExistingNote(titled: title, for: request)
        } catch {
            pratiche.report("nota non creata: \(error)")
        }
    }

    /// R-03: creates a task through the existing capture path, allocates its `^id`
    /// (`ensuringLocalID`) and links it - create, allocate, link, in that order.
    func createAndLinkTask(texted rawText: String, for request: PraticaLinkRequest) async {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let session = vault.session else { return }
        guard let result = await session.captureTask(.init(text: text)) else {
            pratiche.report("task non creato")
            return
        }
        guard let created = TaskParser.tasks(in: result.text, sourcePath: result.path).last else { return }
        await linkExistingTask(created, for: request)
    }

    /// R-03: creates a board through ADR-0022's existing creation flow
    /// (`CanvasStore.createBoard(named:in:)`, unchanged) and links it immediately
    /// after it returns.
    func createAndLinkBoard(named name: String, in parent: String, for request: PraticaLinkRequest) async {
        guard let root = vault.root else { return }
        do {
            let created = try CanvasStore(root: root).createBoard(named: name, in: parent)
            await vault.rescan()
            await linkExistingBoard(at: created, for: request)
        } catch {
            pratiche.report("nuova board: \(error)")
        }
    }

    /// Allocates `task`'s `^id` when it does not have one yet (ADR §D3 - the same
    /// guarded rewrite `TaskParser.insertingSubtask` already performs for a fresh
    /// child, applied here to an existing, unrelated task), and answers the note
    /// title and id a link entry needs either way.
    private func ensuringLocalID(for task: TaskItem) async -> (noteTitle: String, localID: Int)? {
        let noteTitle = NoteName.title(fromFileName: (task.sourcePath as NSString).lastPathComponent)
        if let localID = task.localID { return (noteTitle, localID) }
        guard let session = vault.session else { return nil }
        do {
            let (record, text) = try session.read(task.sourcePath)
            let localID = TaskParser.nextLocalID(in: text)
            let newLine = TaskParser.line(for: task, assigningLocalID: localID)
            guard let updated = TaskParser.rewrite(text, at: task.lineIndex, expecting: task.rawLine, with: newLine)
            else {
                pratiche.report("il task non è più dove risultava: \(task.sourcePath)")
                return nil
            }
            try await session.write(updated, to: task.sourcePath, expecting: record.contentHash)
            return (noteTitle, localID)
        } catch let refusal as VaultSession.WriteRefusal {
            pratiche.report("«\(task.sourcePath)» non è stato aggiornato: \(refusal.description)")
            return nil
        } catch {
            pratiche.report("«\(task.sourcePath)» non è stato aggiornato: \(error.localizedDescription)")
            return nil
        }
    }

    /// One read-modify-write of a pratica's general links, `PraticaLinksWriter`'s own
    /// shape - reported the same way every other write in this file is.
    private func updateLinks(at praticaPath: String, _ change: (inout PraticaLinks) -> Void) async {
        guard let session = vault.session else { return }
        if let message = await PraticaLinksWriter.update(at: praticaPath, session: session, change) {
            pratiche.report(message)
        }
        reload()
    }
}
