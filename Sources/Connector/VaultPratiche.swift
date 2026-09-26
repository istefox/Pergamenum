import Foundation

/// Reading pratiche from outside the app (ADR-0036, SPEC "Connectors").
///
/// The same reasoning `VaultViews.swift` states for the query engine applies here:
/// `Sources/Core/Pratiche/**` is what makes this possible from a shell or a model, and
/// this file is thin on purpose - the shape of the answer, never a second copy of the
/// pratica-recognition or ordering rules.
///
/// **No `MailStore`/`EMLXReader`/`SQLite3` name may ever appear in this file** (R-36,
/// the structural half `Tests/SharedSourcesPurityTests.swift`'s Task 5 case checks):
/// a connector answers from whatever a sync already wrote to disk, never by opening
/// the Mail store or triggering one itself - TCC would attribute that access to the
/// terminal or the MCP client, not to Pergamenum.
extension VaultAPI {
    /// Every pratica of `session`'s vault (SPEC "Connectors": `pratiche` →
    /// `[{ path, title, client, status, counterparts, lastActivity, messageCount,
    /// trayCount }]`).
    ///
    /// Mirrors `PraticheController.listItems`'s own algorithm rather than calling it:
    /// `Sources/Features/Pratiche/PraticheController.swift` imports AppKit and is not in
    /// `sharedSources` (CLAUDE.md "AI connector"). Three things are read, all of them
    /// already on disk - the index's own `pratica.md` records (`Dossier.parse` decides
    /// which folder is a pratica, R-01), the `email/*.md` records under each of those
    /// folders, and the per-vault ledger for `trayCount`.
    ///
    /// `lastActivity` is the folder's newest write time, message files included, and is
    /// the one field that could tempt a re-count against Mail: it is deliberately read
    /// off what the last sync left behind, possibly stale, never wrong about not having
    /// looked (R-36 - "what they read is what is on disk").
    @MainActor
    static func pratiche(_ session: VaultSession) -> [PraticaSummary] {
        let ledger = PraticaLedger.load(from: PraticaLedger.url(inVaultState: session.state.directory))
        let rootFolder = session.settings.pratiche.rootFolder
        let notes = session.index.allNotes
        let found = praticaNotes(among: notes, vaultRoot: session.root)
        let messagesByFolder = messageNotes(among: notes, folders: Set(found.map(\.folder)))

        return found.map { pratica in
            let messages = messagesByFolder[pratica.folder] ?? []
            let newestMessage = messages.map(\.modifiedAt).max() ?? .distantPast
            let status = pratica.note.frontmatter.tags.first(where: { $0.namespace == .status })?.value
            return PraticaSummary(
                path: pratica.folder,
                title: praticaTitle(ofFolder: pratica.folder),
                client: clientName(ofPraticaFolder: pratica.folder, rootFolder: rootFolder),
                // A pratica with no `status-*` at all is an open one, not an invisible
                // one - `PraticheController.listItems`'s own fallback.
                status: status ?? "active",
                counterparts: pratica.dossier.counterparts,
                lastActivity: isoString(max(pratica.note.modifiedAt, newestMessage)),
                messageCount: messages.count,
                trayCount: ledger.byPraticaPath[pratica.folder]?.trayCount ?? 0
            )
        }
        .sorted { $0.path < $1.path }
    }

    /// Resolves `reference` - a pratica's folder path, or its title (the folder's own
    /// last path component) - and answers with its timeline as ordered entries (SPEC
    /// "Connectors": `pratica <title|path>` → `{ kind, date, direction, from, subject,
    /// attachments, body }`, plus the CLI's own printed transcript, which `perg`'s
    /// front end builds from this same payload).
    ///
    /// "Resolution of the argument reuses `VaultLookup`'s existing title/path rules"
    /// (SPEC) names the shape `VaultLookup.task(_:matching:)` already has for a task
    /// phrase: an exact `path:` match short-circuits everything else, and otherwise a
    /// title match that resolves to more than one pratica is refused rather than
    /// guessed at (the same ambiguity report `task(_:matching:)` gives, adapted from
    /// tasks to pratica folders).
    ///
    /// The folder is then read from disk - `pratica.md` plus `email/*.md` - and ordered
    /// ascending the same way `PraticaTimelineModel.sortDate(of:)`/`.ordered(_:)` order
    /// the app's own timeline (that type is not shared either, so the ordering rule is
    /// reproduced here rather than called).
    @MainActor
    static func pratica(_ session: VaultSession, _ reference: String) throws -> PraticaTimelinePayload {
        let folders = praticaNotes(among: session.index.allNotes, vaultRoot: session.root).map(\.folder)
        let folder = try praticaFolder(matching: reference, among: folders)
        return PraticaTimelinePayload(
            path: folder,
            title: praticaTitle(ofFolder: folder),
            entries: timeline(ofPraticaFolder: folder, session: session)
        )
    }
}

// MARK: - Which folders are pratiche

private extension VaultAPI {
    /// One pratica as the index sees it: its folder, its `pratica.md` record and the
    /// dossier that makes it a pratica at all.
    struct PraticaNote {
        var folder: String
        var note: NoteRecord
        var dossier: Dossier
    }

    /// R-01: a folder holding a `pratica.md` whose frontmatter carries a readable
    /// `pergamenum-dossier`. The dossier and not the file name alone - a note somebody
    /// called `pratica.md` by hand is a note, not a pratica.
    ///
    /// The index names the candidates, the file decides - through the one reader the
    /// app's sidebar uses too (`Dossier.parse(praticaFileAt:)`, whose note records why
    /// the index cannot answer this). Reading the handful of `pratica.md` files the
    /// index already pointed at is also what R-36 asks for: a connector answers from
    /// what is on disk.
    static func praticaNotes(among notes: [NoteRecord], vaultRoot: URL) -> [PraticaNote] {
        notes.compactMap { note in
            guard note.relativePath.hasSuffix("/\(praticaFileName)") else { return nil }
            let url = vaultRoot.appending(path: note.relativePath, directoryHint: .notDirectory)
            guard let dossier = Dossier.parse(praticaFileAt: url) else { return nil }
            return PraticaNote(
                folder: String(note.relativePath.dropLast(praticaFileName.count + 1)),
                note: note,
                dossier: dossier
            )
        }
    }

    /// Every `email/*.md` record, grouped by the pratica folder holding it. One pass
    /// over the index rather than one filter per pratica, like `listItems`: a vault of
    /// thousands of notes and a dozen pratiche would otherwise be walked a dozen times.
    static func messageNotes(among notes: [NoteRecord], folders: Set<String>) -> [String: [NoteRecord]] {
        var grouped: [String: [NoteRecord]] = [:]
        for note in notes {
            guard let separator = note.relativePath.range(of: "/\(messagesDirectoryName)/") else { continue }
            let folder = String(note.relativePath[..<separator.lowerBound])
            guard folders.contains(folder) else { continue }
            grouped[folder, default: []].append(note)
        }
        return grouped
    }

    /// `VaultLookup.task(_:matching:)`'s shape, for a pratica: an exact path first,
    /// then the folder's own name, and an ambiguity reported rather than resolved by
    /// taking the first - printing somebody else's correspondence is silent, and
    /// whoever asked would not know it had happened.
    static func praticaFolder(matching reference: String, among folders: [String]) throws -> String {
        if folders.contains(reference) { return reference }

        let matches = folders.filter {
            praticaTitle(ofFolder: $0).localizedCaseInsensitiveCompare(reference) == .orderedSame
        }
        switch matches.count {
        case 0: throw ConnectorError("nessuna pratica si chiama «\(reference)»")
        case 1: return matches[0]
        default:
            let list = matches.sorted().map { "  \($0)" }.joined(separator: "\n")
            throw ConnectorError(
                "«\(reference)» corrisponde a \(matches.count) pratiche; indica il percorso\n\(list)",
                usage: true
            )
        }
    }

    static func praticaTitle(ofFolder folder: String) -> String {
        folder.split(separator: "/").last.map(String.init) ?? folder
    }

    /// SPEC "Sidebar", mirroring `PraticheController.clientName(ofPraticaFolder:
    /// rootFolder:)`: the client is the pratica folder's parent. A pratica sitting
    /// straight in the root has no client folder to take a name from, and says so
    /// rather than borrowing the root's name.
    static func clientName(ofPraticaFolder folder: String, rootFolder: String) -> String {
        let components = folder.split(separator: "/").map(String.init)
        guard components.count >= 2 else { return PraticaNaming.unnamedClient }
        let parent = components[components.count - 2]
        return parent == rootFolder ? PraticaNaming.unnamedClient : parent
    }
}

// MARK: - Reading one pratica's folder

private extension VaultAPI {
    /// A row before it is ordered: the payload entry plus the two keys the sort needs.
    /// `id` breaks a tie the same way `PraticaTimelineModel.ordered(_:)` does, so two
    /// messages carrying the same header second keep one stable order across runs.
    struct TimelineRow {
        var date: Date
        var id: String
        var entry: PraticaTimelinePayload.Entry
    }

    @MainActor
    static func timeline(ofPraticaFolder folder: String, session: VaultSession) -> [PraticaTimelinePayload.Entry] {
        // Through the boundary (ADR-0063 §D7). A pratica folder is never empty, since
        // `praticaNotes` admits only paths ending in `/pratica.md`, so the root never
        // reaches the resolver.
        guard let directory = try? session.store.url(for: folder) else { return [] }
        let rows = messageRows(in: directory, session: session) + manualEntryRows(in: directory)
        return rows
            .sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
            .map(\.entry)
    }

    @MainActor
    static func messageRows(in praticaFolder: URL, session: VaultSession) -> [TimelineRow] {
        let messages = praticaFolder.appending(path: messagesDirectoryName, directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(
            atPath: messages.path(percentEncoded: false)
        )) ?? []

        return names.sorted().compactMap { name -> TimelineRow? in
            guard name.hasSuffix(".md") else { return nil }
            let url = messages.appending(path: name, directoryHint: .notDirectory)
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  let document = MessageDocument.parse(text)
            else { return nil }

            let mail = document.frontmatter
            // `PraticaTimelineModel.sortDate(of:)`: the header `Date` governs, and the
            // received time stands in only when the header carried none.
            let date = mail.date == .distantPast ? (mail.received ?? mail.date) : mail.date
            return TimelineRow(date: date, id: name, entry: PraticaTimelinePayload.Entry(
                kind: "message",
                date: isoString(date),
                direction: mail.direction.rawValue,
                from: mail.from,
                subject: mail.subject,
                attachments: mail.attachments.map(attachmentName(ofWikilink:))
                    + mail.storeReferences.map(\.name),
                body: document.newText,
                // ADR-0049 §D12/R-05: the per-message relation, resolved the same way
                // `praticaLinks` resolves the general ones - `nil` when the message
                // carries no `pergamenum-mail-note` at all, a different thing from a
                // broken one.
                linkedNote: mail.linkedNote.flatMap { reference in
                    guard case let .wikilink(title) = PraticaLinkReference(parsing: reference) else { return nil }
                    return noteTarget(title, session: session)
                }
            ))
        }
    }

    /// `pratica.md`'s own manual entries: `## YYYY-MM-DD HH:MM <Tipo> · <Controparte>`
    /// and everything under it up to the next heading (SPEC "Manual entries"), read
    /// through the formatter that wrote them (`PraticaEntry.headingFormatter`).
    ///
    /// `direction` and `from` stay `nil`: a manual entry has neither, and the
    /// counterpart lives in the heading, which is the entry's `subject`.
    static func manualEntryRows(in praticaFolder: URL) -> [TimelineRow] {
        let url = praticaFolder.appending(path: praticaFileName, directoryHint: .notDirectory)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        var rows: [TimelineRow] = []
        var open: (date: Date, subject: String, body: [String])?

        func flush() {
            guard let entry = open else { return }
            rows.append(TimelineRow(
                date: entry.date,
                id: "\(praticaFileName)#\(rows.count)",
                entry: PraticaTimelinePayload.Entry(
                    kind: entry.subject.hasPrefix(PraticaEntry.Kind.call.label)
                        ? PraticaEntry.Kind.call.rawValue
                        : PraticaEntry.Kind.note.rawValue,
                    date: isoString(entry.date),
                    direction: nil,
                    from: nil,
                    subject: entry.subject,
                    attachments: [],
                    body: entry.body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
                    // SPEC "Out of scope": the per-message relation covers email rows
                    // only, never a manual entry.
                    linkedNote: nil
                )
            ))
            open = nil
        }

        for line in NoteDocument.parse(text).body.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                flush()
                open = entryHeading(line)
                continue
            }
            open?.body.append(line)
        }
        flush()
        return rows
    }

    /// `## 2026-06-10 14:06 Telefonata · Mario Rossi`. Anything else under `##` is an
    /// ordinary heading of the note and is left alone - the same rule
    /// `PraticheController.parseEntryHeading` applies on the app's side.
    static func entryHeading(_ line: String) -> (date: Date, subject: String, body: [String])? {
        let rest = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
        let parts = rest.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 3,
              let date = PraticaEntry.headingFormatter.date(from: "\(parts[0]) \(parts[1])")
        else { return nil }
        return (date: date, subject: String(parts[2]), body: [])
    }

    /// `[[20260610_offerta.pdf]]` → `20260610_offerta.pdf`, alias form included.
    static func attachmentName(ofWikilink wikilink: String) -> String {
        var name = wikilink.trimmingCharacters(in: .whitespaces)
        if name.hasPrefix("[[") { name.removeFirst(2) }
        if name.hasSuffix("]]") { name.removeLast(2) }
        return name.components(separatedBy: "|").first ?? name
    }

    /// The three names a pratica folder is made of, as `PraticheController` spells them
    /// on the app's side. Literals here rather than a shared constant: they are the
    /// folder's shape on disk, and this file may not import the type that owns them.
    static var praticaFileName: String { "pratica.md" }
    static var messagesDirectoryName: String { "email" }

    /// ISO 8601 with the offset, the same spelling `MessageDocument` writes into a
    /// message file. Built per call: `ISO8601DateFormatter` carries no `Sendable`
    /// conformance, so a shared static of it would not compile under strict concurrency
    /// (`PlaudTimestamp`'s own note).
    static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}
