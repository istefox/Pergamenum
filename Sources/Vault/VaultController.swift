import Foundation
import Observation
import SwiftUI

/// Owns the open vault: settings, index, watcher, and the read/write path the editor
/// goes through.
@MainActor
@Observable
final class VaultController {
    private(set) var root: URL?
    private(set) var settings = VaultSettings.default
    private(set) var vocabulary = Vocabulary.empty
    let index = NoteIndex()

    private(set) var isScanning = false
    /// Problems worth showing: an unreadable note, a settings file that would not
    /// parse, a vocabulary that could not be loaded.
    private(set) var problems: [String] = []

    /// The note currently open in the editor.
    private(set) var openNote: OpenNote?
    /// Set by the New Note command; the browser shows the naming sheet when true.
    var isCreatingNote = false
    /// Set by the Anteprima rapida command (SPEC §10, Vista menu). The Workspace
    /// watches it so the panel can be opened from the menu as well as the spacebar.
    var isShowingQuickLook = false
    /// Set by the quick switcher command.
    ///
    /// Both live here rather than as view state because their shortcuts are menu
    /// commands: `onKeyPress` only fires when the view holds focus, so Cmd+O did
    /// nothing while the cursor was in the editor, which is exactly when it is wanted.
    var isShowingQuickSwitcher = false

    /// Hashes the app itself wrote, keyed by path. A watcher event whose file hashes
    /// to the recorded value is the app's own write coming back and is ignored.
    private var selfWrittenHashes: [String: String] = [:]

    private var watcher: VaultWatcher?
    private var store: NoteStore?

    struct OpenNote: Equatable, Sendable {
        var relativePath: String
        var title: String
        /// The text as the editor has it, which may differ from disk while editing.
        var text: String
        /// The text as last read from or written to disk.
        var savedText: String
        /// An external change arrived while this note had unsaved edits. The editor
        /// must ask rather than merging or discarding either side (ADR-0001 §D3.4).
        var externalChangePending: String?

        var hasUnsavedChanges: Bool { text != savedText }
    }

    // MARK: Opening

    func open(_ url: URL) async {
        watcher?.stop()
        watcher = nil
        problems = []

        root = url
        store = NoteStore(root: url)
        loadSettings(from: url)
        loadVocabulary(from: url)
        await rescan()
        startWatching(url)
    }

    func close() {
        watcher?.stop()
        watcher = nil
        root = nil
        store = nil
        openNote = nil
        selfWrittenHashes.removeAll()
        index.replaceAll(with: .init(records: [], failures: []), duration: .zero)
    }

    /// Full rebuild from disk. Cheap by design, and the answer to any doubt about the
    /// index being stale (SPEC §12, "rigenera indice").
    func rescan() async {
        guard let root else { return }
        isScanning = true
        defer { isScanning = false }

        let clock = ContinuousClock()
        let start = clock.now
        let outcome = await Task.detached(priority: .userInitiated) {
            VaultScanner(root: root).scan()
        }.value
        index.replaceAll(with: outcome, duration: clock.now - start)
    }

    // MARK: Notes

    func openNote(at relativePath: String) {
        guard let store else { return }
        do {
            let (record, text) = try store.read(relativePath)
            openNote = OpenNote(
                relativePath: relativePath,
                title: record.title,
                text: text,
                savedText: text,
                externalChangePending: nil
            )
            index.update(record, at: relativePath)
        } catch {
            problems.append("\(relativePath): \(error)")
        }
    }

    func updateOpenNoteText(_ text: String) {
        openNote?.text = text
    }

    enum CreationError: Error, CustomStringConvertible {
        case invalidTitle([NoteName.Violation])
        case alreadyExists(String)

        var description: String {
            switch self {
            case .invalidTitle(let violations): "titolo non conforme: \(violations)"
            case .alreadyExists(let path): "esiste già: \(path)"
            }
        }
    }

    /// Creates a note with a conformant frontmatter block already in place.
    ///
    /// The generated block is the closed four-key schema in fixed order, with the tag
    /// set the note's category requires (SPEC §4.3, tag.md 5.1): a daily note gets
    /// `type-note` alone, an inbox capture adds `status-inbox`, and an ordinary note
    /// gets `type-note` plus whatever topic the caller supplies.
    ///
    /// Refuses rather than sanitising silently: a title the rules reject is a decision
    /// for the user, and quietly renaming their note is how a vault fills with titles
    /// nobody chose.
    @discardableResult
    func createNote(
        title: String,
        in folder: String = "",
        date: CalendarDate,
        category: NoteCategory = .note,
        topics: [Tag] = []
    ) throws -> String {
        guard let store else { throw CreationError.alreadyExists("nessun vault aperto") }

        let violations = category == .daily
            ? NoteName.validateDaily(title)
            : NoteName.validate(title)
        guard violations.isEmpty else { throw CreationError.invalidTitle(violations) }

        let fileName = NoteName.fileName(for: title)
        let relativePath = folder.isEmpty ? fileName : "\(folder)/\(fileName)"
        guard !FileManager.default.fileExists(
            atPath: store.url(for: relativePath).path(percentEncoded: false)
        ) else { throw CreationError.alreadyExists(relativePath) }

        var frontmatter = Frontmatter.empty
        frontmatter.date = date
        frontmatter.tags = TagRules.ordered([Tag(namespace: .type, value: "note")] + topics + (
            category == .capture ? [Tag(namespace: .status, value: "inbox")] : []
        ))

        let text = FrontmatterSerializer.render(frontmatter) + "\n"
        let hash = try store.write(text, to: relativePath)
        selfWrittenHashes[relativePath] = hash

        index.update(try store.read(relativePath).record, at: relativePath)
        openNote(at: relativePath)
        return relativePath
    }

    /// Opens today's daily note, creating it if it does not exist (SPEC §8.1).
    @discardableResult
    func openDailyNote(for date: CalendarDate) throws -> String {
        guard let store else { throw CreationError.alreadyExists("nessun vault aperto") }
        let relativePath = settings.dailyFolder.isEmpty
            ? NoteName.dailyFileName(for: date)
            : "\(settings.dailyFolder)/\(NoteName.dailyFileName(for: date))"

        if FileManager.default.fileExists(atPath: store.url(for: relativePath).path(percentEncoded: false)) {
            openNote(at: relativePath)
            return relativePath
        }
        return try createNote(
            title: date.compactForm,
            in: settings.dailyFolder,
            date: date,
            category: .daily
        )
    }

    /// Writes the open note. Files first, index second: a crash between the two must
    /// leave the file correct, never the cache (ADR-0001 §D2.3).
    func saveOpenNote() {
        guard let store, var note = openNote, note.hasUnsavedChanges else { return }
        do {
            let hash = try store.write(note.text, to: note.relativePath)
            selfWrittenHashes[note.relativePath] = hash
            note.savedText = note.text
            note.externalChangePending = nil
            openNote = note

            let record = try store.read(note.relativePath).record
            index.update(record, at: note.relativePath)
        } catch {
            problems.append("\(note.relativePath): \(error)")
        }
    }

    /// Resolves an external change the user chose to accept, replacing the buffer.
    func acceptExternalChange() {
        guard var note = openNote, let incoming = note.externalChangePending else { return }
        note.text = incoming
        note.savedText = incoming
        note.externalChangePending = nil
        openNote = note
    }

    /// Keeps the in-app version and clears the prompt. The next save overwrites disk.
    func keepLocalVersion() {
        openNote?.externalChangePending = nil
    }

    // MARK: Watching

    private func startWatching(_ url: URL) {
        let watcher = VaultWatcher(root: url) { [weak self] paths in
            Task { @MainActor [weak self] in
                self?.reconcile(paths)
            }
        }
        watcher.start()
        self.watcher = watcher
    }

    /// Applies external changes, one path at a time.
    private func reconcile(_ paths: [String]) {
        guard let store else { return }

        for path in paths {
            let fileURL = store.url(for: path)
            guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
                index.update(nil, at: path)
                continue
            }
            guard let (record, text) = try? store.read(path) else { continue }

            // The app's own write coming back. Compared by content hash rather than
            // by a time window, so a real external edit is never mistaken for it.
            if selfWrittenHashes[path] == record.contentHash {
                selfWrittenHashes.removeValue(forKey: path)
                continue
            }

            index.update(record, at: path)

            guard var note = openNote, note.relativePath == path else { continue }
            if note.hasUnsavedChanges {
                // Never merge, never discard: ask.
                note.externalChangePending = text
                openNote = note
            } else {
                note.text = text
                note.savedText = text
                openNote = note
            }
        }
    }

    // MARK: Vault-private files

    private func privateDirectory(in root: URL) -> URL {
        root.appending(path: VaultLayout.privateDirectory, directoryHint: .isDirectory)
    }

    private func loadSettings(from root: URL) {
        let url = privateDirectory(in: root).appending(path: VaultLayout.settingsFile)
        guard let data = try? Data(contentsOf: url) else {
            settings = .default
            return
        }
        do {
            settings = try JSONDecoder().decode(VaultSettings.self, from: data)
        } catch {
            // Defaults rather than a failure to open: a damaged settings file must not
            // make the vault unreachable. It is not overwritten either, so the user
            // can repair it by hand.
            settings = .default
            problems.append("\(VaultLayout.settingsFile): \(error.localizedDescription); using defaults")
        }
    }

    /// Loads the vocabulary replica from the vault, seeding it from the bundled copy
    /// the first time (SPEC §4.6).
    private func loadVocabulary(from root: URL) {
        let directory = privateDirectory(in: root)
        let url = directory.appending(path: VaultLayout.vocabularyFile)

        if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            guard let bundled = Bundle.pergamenumResources.url(forResource: "vocabolari", withExtension: "json") else {
                problems.append("the bundled vocabolari.json is missing")
                return
            }
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: bundled, to: url)
            } catch {
                problems.append("vocabolari.json could not be created: \(error.localizedDescription)")
                return
            }
        }

        do {
            vocabulary = try JSONDecoder().decode(Vocabulary.self, from: try Data(contentsOf: url))
        } catch {
            vocabulary = .empty
            problems.append("\(VaultLayout.vocabularyFile): \(error.localizedDescription)")
        }
    }

    /// Re-imports the closed vocabularies from the harness-system checkout and writes
    /// the replica back into the vault.
    func importConventions(from repository: URL) {
        let conventions = repository.appending(path: "convenzioni", directoryHint: .isDirectory)
        let tagURL = conventions.appending(path: "tag.md")
        let namingURL = conventions.appending(path: "naming.md")

        guard let tagDocument = try? String(contentsOf: tagURL, encoding: .utf8),
              let namingDocument = try? String(contentsOf: namingURL, encoding: .utf8)
        else {
            problems.append("convenzioni/tag.md or naming.md could not be read at \(repository.path(percentEncoded: false))")
            return
        }

        let result = HarnessImporter.parse(tagDocument: tagDocument, namingDocument: namingDocument)
        problems.append(contentsOf: result.problems.map { "import: \($0)" })
        guard result.problems.isEmpty else { return }

        vocabulary = result.vocabulary
        guard let root else { return }
        let url = privateDirectory(in: root).appending(path: VaultLayout.vocabularyFile)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(result.vocabulary).write(to: url, options: .atomic)
        } catch {
            problems.append("vocabolari.json could not be written: \(error.localizedDescription)")
        }
    }

    /// Validates the open note against every convention rule, for the conformance view.
    func violations(for note: OpenNote) -> NoteViolations {
        let document = NoteDocument.parse(note.text)
        let category = NoteName.category(
            forFileName: (note.relativePath as NSString).lastPathComponent,
            dailyFolder: settings.dailyFolder,
            path: note.relativePath
        )
        let discrepancies = RelatedSection.discrepancies(
            frontmatterRelated: document.frontmatter.related,
            sectionLinks: RelatedSection.parse(from: document.body)
        )
        return NoteViolations(
            name: NoteName.validate(note.title),
            frontmatter: FrontmatterRules.validate(document),
            tags: TagRules.validate(document.frontmatter.tags, category: category, vocabulary: vocabulary),
            relatedMissingInSection: discrepancies.missingInSection,
            relatedMissingInFrontmatter: discrepancies.missingInFrontmatter
        )
    }
}

struct NoteViolations: Equatable, Sendable {
    var name: [NoteName.Violation]
    var frontmatter: [FrontmatterViolation]
    var tags: [TagViolation]
    var relatedMissingInSection: [String]
    var relatedMissingInFrontmatter: [String]

    var isEmpty: Bool {
        name.isEmpty && frontmatter.isEmpty && tags.isEmpty
            && relatedMissingInSection.isEmpty && relatedMissingInFrontmatter.isEmpty
    }

    var count: Int {
        name.count + frontmatter.count + tags.count
            + relatedMissingInSection.count + relatedMissingInFrontmatter.count
    }
}
