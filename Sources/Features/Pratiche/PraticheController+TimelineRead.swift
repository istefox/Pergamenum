import Foundation

// MARK: - Reading the vault (pure, no `@MainActor` state)

extension PraticheController {
    struct TimelineRead: Sendable {
        var entries: [PraticaTimelineEntry]
        var details: [String: PraticaRowDetail]
        /// ADR-0076 §D3: `NoteStore.hash` over the `pratica.md` bytes the entries were parsed
        /// from; nil when the file could not be read.
        var praticaNoteHash: String?
        /// ADR-0079 §D2: the pratica's `pergamenum-dossier-excluded`, read from the same bytes
        /// as the entries and their hash; empty when the file could not be read.
        var excluded: Set<String> = []
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
        // Through the boundary, built once for the whole list (PG-360).
        let boundary = vault.root.map { VaultBoundary(root: $0) }
        let dossierNotes = notes.filter { note in
            guard note.relativePath.hasSuffix("/\(praticaFileName)"),
                  let url = try? boundary?.url(for: note.relativePath) else { return false }
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
        var read = TimelineRead(entries: [], details: [:])
        // Through the boundary (PG-368): a refused folder reads as an empty timeline, as a
        // missing one does.
        guard let folder = try? VaultBoundary(root: vaultRoot).url(for: praticaPath) else { return read }
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
                pendingAttachments: document.frontmatter.pendingAttachmentNames,
                linkedNote: document.frontmatter.linkedNote
            )
        }
    }

    /// `pratica.md`'s manual entries: `## YYYY-MM-DD HH:MM <Kind> · <Controparte>` and
    /// everything under it up to the next heading (SPEC "Manual entries"), parsed by the one
    /// shared parser, `PraticaManualEntries.parse` (ADR-0076 §D1).
    ///
    /// Read-only here, deliberately: the timeline's writes are `PraticaEntryComposer`'s, and
    /// this pane never binds a text view to a range of `pratica.md` (ADR-0036 §D5).
    ///
    /// The bytes are read once: the same `Data` is hashed with `NoteStore.hash` and decoded
    /// with `NoteStore.decodedText`, so `praticaNoteHash` is the hash of exactly what was
    /// parsed and equals `session.read(notePath).record.contentHash` for an unchanged file.
    private nonisolated static func readManualEntries(
        in folder: URL, praticaPath: String, into read: inout TimelineRead
    ) {
        let url = folder.appending(path: praticaFileName, directoryHint: .notDirectory)
        guard let data = try? Data(contentsOf: url), let text = NoteStore.decodedText(data) else { return }
        read.praticaNoteHash = NoteStore.hash(data)
        read.excluded = PraticaTimelineOrder.excludedMessageIDs(inPraticaNote: text)
        let notePath = "\(praticaPath)/\(praticaFileName)"

        for parsed in PraticaManualEntries.parse(text) {
            // The id is today's, byte for byte: selection, expansion and `details` are keyed
            // on it. `occurrence` disambiguates two headings sharing a minute
            // (`entryIDFormatter`'s own resolution); it is a function of position in the
            // file, so it is stable across reloads like the timestamp it disambiguates.
            var id = "\(praticaPath)#entry-\(entryIDFormatter.string(from: parsed.date))"
            if parsed.occurrence > 0 { id += "-\(parsed.occurrence)" }
            read.entries.append(PraticaTimelineEntry(
                id: id,
                kind: parsed.kind == .call ? .call : .note,
                date: parsed.date,
                direction: nil,
                senderDisplayName: parsed.counterpart,
                subject: parsed.subject,
                bodyPreview: firstLine(of: parsed.body),
                hasAttachments: false,
                messageID: nil,
                isInMail: true,
                anchor: parsed.anchor,
                fileOrdinal: parsed.ordinal,
                sourceHash: read.praticaNoteHash
            ))
            read.details[id] = PraticaRowDetail(
                notePath: notePath, body: parsed.body, quotedHistory: nil, signature: nil,
                attachments: [], storeReferences: [], isPending: false, senderAddress: nil
            )
        }
    }

    nonisolated static func firstLine(of text: String) -> String {
        text
            .components(separatedBy: "\n")
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    /// The dossier of one pratica, read from disk rather than from the index: a sync
    /// must act on the file as it is now, not as the last scan saw it. Through the boundary
    /// (PG-368): a refused path is no pratica, as an unreadable `pratica.md` is not.
    static func dossier(at praticaPath: String, vaultRoot: URL) -> Dossier? {
        let praticaNote = PraticaNaming.praticaNotePath(of: praticaPath)
        guard let url = try? VaultBoundary(root: vaultRoot).url(for: praticaNote) else { return nil }
        return Dossier.parse(praticaFileAt: url)
    }

    /// The timestamp the row's accessibility identifier carries
    /// (`pratiche-entry-<timestamp>`, UX-BLUEPRINT's checklist).
    ///
    /// GMT, and kept GMT on purpose when PG-367 moved the heading's own digits to the writer's
    /// zone: the id is derived from the heading's instant (`PraticaManualEntry.date`, the digits
    /// less the heading's offset), so one entry has one identifier wherever the Mac is standing,
    /// and every entry written before PG-367 keeps the identifier it already had.
    nonisolated static let entryIDFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHHmm"
        return formatter
    }()
}
