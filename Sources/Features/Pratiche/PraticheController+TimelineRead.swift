import Foundation

// MARK: - Reading the vault (pure, no `@MainActor` state)

extension PraticheController {
    struct TimelineRead: Sendable {
        var entries: [PraticaTimelineEntry]
        var details: [String: PraticaRowDetail]
    }

    /// Every pratica of the open vault: a folder holding a `pratica.md` whose
    /// frontmatter carries a readable `pergamenum-dossier` (R-01). The dossier and not
    /// the file name alone - a note called `pratica.md` that somebody wrote by hand is
    /// a note, not a pratica.
    static func listItems(
        in vault: VaultController,
        ledger: PraticaLedger,
        trayCounts: [String: Int],
        rootFolder: String
    ) -> [PraticaListItem] {
        let notes = vault.index.allNotes
        // The index names the candidates, the file decides. Reading the dossier off
        // `frontmatter.foreignKeys` looks equivalent and is not: the cache keeps no
        // `pergamenum-*` key, so every record a scan reused from it - all of them, from
        // the second scan of a vault onward - would answer "not a pratica" and empty
        // this list (`Dossier.parse(praticaFileAt:)`'s own note). Only the handful of
        // paths ending in `pratica.md` are opened, never the whole index.
        let root = vault.root
        let dossierNotes = notes.filter { note in
            guard note.relativePath.hasSuffix("/\(praticaFileName)"), let root else { return false }
            let url = root.appending(path: note.relativePath, directoryHint: .notDirectory)
            return Dossier.parse(praticaFileAt: url) != nil
        }
        let folders = Set(dossierNotes.map { folderPath(ofPraticaNote: $0.relativePath) })

        // One pass over the index rather than one filter per pratica: a vault with
        // thousands of notes and a dozen pratiche would otherwise walk the whole index
        // a dozen times on every load.
        var messagesByFolder: [String: [NoteRecord]] = [:]
        for note in notes {
            guard let separator = note.relativePath.range(of: "/\(messagesDirectoryName)/") else { continue }
            let folder = String(note.relativePath[..<separator.lowerBound])
            guard folders.contains(folder) else { continue }
            messagesByFolder[folder, default: []].append(note)
        }

        return dossierNotes.map { note in
            let folder = folderPath(ofPraticaNote: note.relativePath)
            let messages = messagesByFolder[folder] ?? []
            let lastOpenedAt = ledger.byPraticaPath[folder]?.lastOpenedAt
            return PraticaListItem(
                id: folder,
                title: (folder as NSString).lastPathComponent,
                client: clientName(ofPraticaFolder: folder, rootFolder: rootFolder),
                // The bare suffix, `active` when the note carries no `status-*` at all
                // - a pratica with no status is an open one, not an invisible one.
                status: note.frontmatter.tags.first { $0.namespace == .status }?.value ?? "active",
                lastActivity: max(note.modifiedAt, messages.map(\.modifiedAt).max() ?? .distantPast),
                // Counted on the message files' own write times rather than on their
                // header dates: what «new since you last looked» means here is what
                // arrived in the folder, and the index already knows that without
                // opening a single file. Never opened yet counts nothing - a pratica
                // created five minutes ago would otherwise announce its whole history
                // as unread.
                messagesSinceLastOpen: lastOpenedAt.map { since in
                    messages.filter { $0.modifiedAt > since }.count
                } ?? 0,
                hasNonEmptyTray: (trayCounts[folder] ?? 0) > 0
            )
        }
    }

    /// `01 Progetti/Rossi/Offerta/pratica.md` → `01 Progetti/Rossi/Offerta`.
    static func folderPath(ofPraticaNote relativePath: String) -> String {
        String(relativePath.dropLast(praticaFileName.count + 1))
    }

    /// SPEC "Sidebar": the client is the pratica folder's parent, under the configured
    /// root. A pratica sitting straight in the root has no client folder to take a
    /// name from, and says so rather than borrowing the root's name.
    static func clientName(ofPraticaFolder folder: String, rootFolder: String) -> String {
        let components = folder.split(separator: "/").map(String.init)
        guard components.count >= 2 else { return unnamedClient }
        let parent = components[components.count - 2]
        return parent == rootFolder ? unnamedClient : parent
    }

    /// From `PraticaNaming`, which `Sources/Connector` can see and this file cannot be
    /// seen from: `VaultAPI.pratiche(_:)` says the same words for the same folder.
    static let unnamedClient = PraticaNaming.unnamedClient

    /// Reads one pratica's folder into timeline rows: every `email/*.md` through
    /// `MessageDocument.parse`, plus `pratica.md`'s own manual-entry headings.
    ///
    /// `nonisolated` and taking a `URL` rather than a `VaultController`: it touches no
    /// observable state, so it can move off the main actor the day a pratica gets big
    /// enough to need it.
    ///
    /// `notInStore` (plan Task 7/8's "R-16/R-26 gap left by batch 4", ADR follow-up
    /// "Task 5/6 implementation notes"): the `Message-ID`s
    /// `PraticaLedger.PraticaState.notInStore` records for this pratica, defaulted to
    /// `[]` so every existing call site keeps compiling unchanged. The tester declares
    /// the parameter; `readMessages` below is the RED stub - it still hardcodes
    /// `isInMail: true` and ignores it, so a test that seeds this set and expects
    /// `isInMail == false` fails on the assertion until the coder reads it for real.
    nonisolated static func readTimeline(
        praticaPath: String, vaultRoot: URL, notInStore: Set<String> = []
    ) -> TimelineRead {
        let folder = vaultRoot.appending(path: praticaPath, directoryHint: .isDirectory)
        var read = TimelineRead(entries: [], details: [:])
        readMessages(in: folder, praticaPath: praticaPath, notInStore: notInStore, into: &read)
        readManualEntries(in: folder, praticaPath: praticaPath, into: &read)
        return read
    }

    private nonisolated static func readMessages(
        in folder: URL, praticaPath: String, notInStore: Set<String>, into read: inout TimelineRead
    ) {
        let messages = folder.appending(path: messagesDirectoryName, directoryHint: .isDirectory)
        // ADR-0041 §D2: an attachment entry is a *name* out of a message note's
        // frontmatter, which is generated from an `.emlx` whose file name Apple Mail
        // chose - not trusted input. The boundary is rooted at `allegati/` rather than at
        // the vault, and deliberately so: `<pratica>/allegati/../../../secret.pdf`
        // standardises back to a path *inside* the vault root, so a vault-level check
        // would wave it through while it names a file this pratica does not own.
        let attachments = VaultBoundary(
            root: folder.appending(path: attachmentsDirectoryName, directoryHint: .isDirectory)
        )
        let names = (try? FileManager.default.contentsOfDirectory(
            atPath: messages.path(percentEncoded: false)
        )) ?? []

        for name in names.sorted() where name.hasSuffix(".md") {
            let url = messages.appending(path: name, directoryHint: .notDirectory)
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  let document = MessageDocument.parse(text)
            else { continue }

            let id = "\(praticaPath)/\(messagesDirectoryName)/\(name)"
            let sender = EmailHeaderParser.parseAddress(document.frontmatter.from)
            read.entries.append(PraticaTimelineEntry(
                id: id,
                kind: .message,
                date: PraticaTimelineModel.sortDate(of: document.frontmatter),
                direction: document.frontmatter.direction,
                senderDisplayName: sender?.displayText ?? document.frontmatter.from,
                senderAddress: sender?.address,
                subject: document.frontmatter.subject,
                bodyPreview: firstLine(of: document.newText),
                hasAttachments: !document.frontmatter.attachments.isEmpty
                    || !document.frontmatter.storeReferences.isEmpty,
                messageID: document.frontmatter.messageID,
                // R-16/R-26: the ledger's own outcome, never a locator miss (§D4). A
                // message the sync found gone from the store loses its link and gains
                // «non più in Mail» through
                // `PraticaTimelineModel.subjectLink(messageID:isInMail:)`; its files
                // are untouched, which is the whole of R-16.
                isInMail: !notInStore.contains(document.frontmatter.messageID)
            ))
            read.details[id] = PraticaRowDetail(
                notePath: id,
                body: document.newText,
                quotedHistory: document.quotedHistory,
                signature: document.signature,
                // A name the boundary refuses is omitted from the row rather than failing
                // the whole read: the other attachments, and the message itself, are
                // still worth showing.
                attachments: document.frontmatter.linkedAttachmentNames.compactMap { fileName in
                    guard let url = try? attachments.url(for: fileName) else { return nil }
                    return PraticaAttachmentRef(name: fileName, url: url)
                },
                storeReferences: document.frontmatter.storeReferences,
                isPending: document.frontmatter.body == .pending,
                senderAddress: sender?.address,
                pendingAttachments: document.frontmatter.pendingAttachmentNames
            )
        }
    }

    /// `pratica.md`'s manual entries: `## YYYY-MM-DD HH:MM <Kind> · <Controparte>` and
    /// everything under it up to the next heading (SPEC "Manual entries").
    ///
    /// Read-only here, deliberately: Task 7 owns writing them
    /// (`PraticaEntry.insert(kind:at:in:)`), and this pane never writes a text range
    /// of `pratica.md` - editing goes to the inspector (ADR §D5).
    private nonisolated static func readManualEntries(
        in folder: URL, praticaPath: String, into read: inout TimelineRead
    ) {
        let url = folder.appending(path: praticaFileName, directoryHint: .notDirectory)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let notePath = "\(praticaPath)/\(praticaFileName)"

        var current: (entry: PraticaTimelineEntry, body: [String])?
        // Disambiguates two manual entries whose heading shares the same
        // to-the-minute timestamp (`entryIDFormatter`'s own resolution) - without
        // this, the second overwrote the first's `read.details` entry and SwiftUI saw
        // two rows claiming one identity. The occurrence count is stable across
        // reloads: it is a function of position in the file, exactly like the
        // timestamp it disambiguates.
        var occurrencesByID: [String: Int] = [:]
        func flush() {
            guard let open = current else { return }
            let body = open.body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            var entry = open.entry
            entry.bodyPreview = firstLine(of: body)
            let occurrence = occurrencesByID[entry.id, default: 0]
            occurrencesByID[entry.id] = occurrence + 1
            if occurrence > 0 { entry.id += "-\(occurrence)" }
            read.entries.append(entry)
            read.details[entry.id] = PraticaRowDetail(
                notePath: notePath, body: body, quotedHistory: nil, signature: nil,
                attachments: [], storeReferences: [], isPending: false, senderAddress: nil
            )
            current = nil
        }

        for line in NoteDocument.parse(text).body.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                flush()
                if let heading = parseEntryHeading(line, praticaPath: praticaPath) { current = (heading, []) }
                continue
            }
            current?.body.append(line)
        }
        flush()
    }

    /// `## 2026-06-10 14:06 Telefonata · Mario Rossi`. Anything else under `##` is an
    /// ordinary heading of the note and is left alone.
    private nonisolated static func parseEntryHeading(
        _ line: String, praticaPath: String
    ) -> PraticaTimelineEntry? {
        let rest = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
        let parts = rest.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 3, let date = entryHeadingFormatter.date(from: "\(parts[0]) \(parts[1])")
        else { return nil }

        let tail = String(parts[2])
        let kind: PraticaTimelineEntry.Kind = tail.hasPrefix("Telefonata") ? .call : .note
        let counterpart = tail
            .components(separatedBy: " · ")
            .dropFirst()
            .joined(separator: " · ")

        return PraticaTimelineEntry(
            id: "\(praticaPath)#entry-\(entryIDFormatter.string(from: date))",
            kind: kind,
            date: date,
            direction: nil,
            senderDisplayName: counterpart,
            subject: tail,
            bodyPreview: "",
            hasAttachments: false,
            messageID: nil,
            isInMail: true
        )
    }

    /// `[[20260610_offerta.pdf]]` → `20260610_offerta.pdf`, alias form included.
    nonisolated static func attachmentFileName(fromWikilink wikilink: String) -> String {
        var name = wikilink.trimmingCharacters(in: .whitespaces)
        if name.hasPrefix("[[") { name.removeFirst(2) }
        if name.hasSuffix("]]") { name.removeLast(2) }
        return name.components(separatedBy: "|").first ?? name
    }

    nonisolated static func firstLine(of text: String) -> String {
        text
            .components(separatedBy: "\n")
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    /// The dossier of one pratica, read from disk rather than from the index: a sync
    /// must act on the file as it is now, not as the last scan saw it.
    static func dossier(at praticaPath: String, vaultRoot: URL) -> Dossier? {
        Dossier.parse(praticaFileAt: vaultRoot
            .appending(path: praticaPath, directoryHint: .isDirectory)
            .appending(path: praticaFileName, directoryHint: .notDirectory))
    }

    /// `en_US_POSIX`, GMT and a fixed pattern: the heading is a file format, not a
    /// presentation, and a person whose Mac is set to another locale still has to be
    /// able to read their own pratica in Obsidian.
    ///
    /// The time zone matches `PraticaEntry.headingFormatter`'s, and has to: that is the
    /// formatter that *writes* the heading this one reads back, and a zone difference
    /// between them would shift every manual entry by the machine's own offset
    /// (`Tests/PraticaEntryTests.swift` pins the pattern and the locale of the pair).
    private nonisolated static let entryHeadingFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    /// The timestamp the row's accessibility identifier carries
    /// (`pratiche-entry-<timestamp>`, UX-BLUEPRINT's checklist).
    ///
    /// GMT beside the two heading formatters above, and for the same reason: the id is
    /// derived from a heading's own digits, so a zone difference would give one entry
    /// two identifiers depending on where the Mac is standing.
    nonisolated static let entryIDFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHHmm"
        return formatter
    }()
}
