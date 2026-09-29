import CryptoKit
import Foundation

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D4 and §D5, plan
// docs/plans/contenitore.md, Task 4 - R-01 to R-08, R-26 (engine half).
//
// App-only (§D14): ingest runs only while the app is open, and neither connector can reach it.

/// Something one observation has to tell the person, beside what it imported.
enum ContenitoreNotice: Equatable, Sendable {
    /// The file's hash equals an existing scheda's (R-05); `existing` is that scheda's path. The
    /// file stays in the drop folder.
    case duplicate(file: String, existing: String)
    /// The import failed and was rolled back, or could not be (R-07); `reason` says which.
    case failed(file: String, reason: String)
    /// An iCloud placeholder: the file is not on this Mac yet (R-08).
    case placeholder(file: String)
    /// A folder inside the drop folder, never descended into (R-08), reported once per name.
    case subfolder(name: String)
    /// The drop folder cannot be listed (R-26), reported once until it can be again.
    case unreadableDropFolder
    /// A dropped `.md` or `.canvas`, refused (gate G3): a `.md` would share its scheda's name, a
    /// `.canvas` would pass for a board and split the pair.
    case refusedNote(file: String)
    /// Text extraction failed for an imported document (Task 5's queue raises it, R-11).
    case extractionFailed(file: String)
}

/// What one observation did.
struct IngestReport: Equatable, Sendable {
    /// The vault-relative path of each scheda written, in import order.
    var imported: [String] = []
    /// The drop folder names seen for the first time or still changing (R-03).
    var waiting: [String] = []
    var notices: [ContenitoreNotice] = []
}

/// Imports what lands in the drop folder, one observation per call (ADR-0071 §D4).
///
/// The order is the ADR's: list, wait for stability, hash off the main actor, refuse a duplicate,
/// name the pair, move the file in, write the scheda, and roll the file back on any failure after
/// the move. Nothing here sleeps: the caller (Task 6's controller) decides when to observe again,
/// and a test simply calls `observe()` twice.
@MainActor
final class ContenitoreIngestEngine {
    private let session: VaultSession
    private let settings: ContenitoreSettings
    private let home: URL
    private let today: () -> CalendarDate
    private let onImported: (String) -> Void

    private var listing = DropFolderListing()
    /// Subfolder names already reported, for the life of the engine (§D4 step 1).
    private var reportedSubfolders: Set<String> = []
    /// Whether the unreadable-folder notice has been raised since the folder was last readable.
    private var reportedUnreadable = false
    /// Size and date of each file this engine has already answered without importing it: refused
    /// as a duplicate, or rolled back after the move (§D4 steps 4 and 8). Either way the file is
    /// in the drop folder afterwards with the very signature `DropFolderListing` already holds as
    /// stable, so without this memory the next observation would find it ready and try again -
    /// hashing every leftover duplicate each time, and moving a file whose import keeps failing
    /// in and out of the vault. The file is left alone until its size or date changes.
    private var declined: [String: DeclinedSignature] = [:]

    private struct DeclinedSignature: Equatable {
        let size: Int64
        let modified: Date
    }

    /// Called after the file has moved in and before the scheda is written, with the scheda's
    /// vault-relative path. A named seam in ADR-0046 §D2's sense and nothing else: a test uses
    /// it to put a file at that path, so the write's real `expectingAbsent` refusal and the
    /// rollback after it run end to end (R-07). The app never sets it.
    var beforeSchedaWrite: ((String) throws -> Void)?

    /// `onImported` receives the vault-relative path of each scheda written, once it is on disk.
    init(
        session: VaultSession,
        settings: ContenitoreSettings,
        home: URL,
        today: @escaping () -> CalendarDate,
        onImported: @escaping (String) -> Void
    ) {
        self.session = session
        self.settings = settings
        self.home = home
        self.today = today
        self.onImported = onImported
    }

    /// Runs one observation of the drop folder.
    func observe() async -> IngestReport {
        var report = IngestReport()
        let dropFolder = settings.resolvedDropFolder(home: home)
        guard let entries = listEntries(of: dropFolder, into: &report) else { return report }
        // A name that left the folder starts over if it is dropped again.
        let present = Set(entries.map(\.name))
        declined = declined.filter { present.contains($0.key) }

        for (entry, classification) in listing.classify(entries) {
            switch classification {
            case .hidden:
                continue
            case .subfolder:
                if reportedSubfolders.insert(entry.name).inserted {
                    report.notices.append(.subfolder(name: entry.name))
                }
            case .placeholder(let name):
                report.notices.append(.placeholder(file: name))
            case .refused:
                report.notices.append(.refusedNote(file: entry.name))
            case .waiting:
                report.waiting.append(entry.name)
            case .ready:
                await importReady(entry, from: dropFolder, into: &report)
            }
        }
        return report
    }

    /// The drop folder's entries, creating the folder at first use when missing (§D4); an
    /// existing folder is left as it is. Nil when it cannot be listed, with the notice raised
    /// once until it can be again (R-26).
    private func listEntries(of dropFolder: URL, into report: inout IngestReport) -> [DropFolderListing.Entry]? {
        do {
            if !FileManager.default.fileExists(atPath: dropFolder.path(percentEncoded: false)) {
                try FileManager.default.createDirectory(at: dropFolder, withIntermediateDirectories: true)
            }
            let entries = try DropFolderListing.read(dropFolder)
            reportedUnreadable = false
            return entries
        } catch {
            if !reportedUnreadable {
                reportedUnreadable = true
                report.notices.append(.unreadableDropFolder)
            }
            return nil
        }
    }

    /// Imports one stable file, unless this engine already answered it unchanged.
    private func importReady(
        _ entry: DropFolderListing.Entry, from dropFolder: URL, into report: inout IngestReport
    ) async {
        let signature = DeclinedSignature(size: entry.size, modified: entry.modified)
        // Already answered, unchanged since: its notice was raised once, when the answer
        // was given, and is not repeated (as with a subfolder's), so the file is
        // neither re-hashed nor tried again until it changes.
        if declined[entry.name] == signature { return }
        declined[entry.name] = nil

        let source = dropFolder.appending(path: entry.name, directoryHint: .notDirectory)
        switch await importFile(source, named: entry.name) {
        case .imported(let schedaPath):
            report.imported.append(schedaPath)
            onImported(schedaPath)
        case .notice(let notice, let declines):
            if declines { declined[entry.name] = signature }
            report.notices.append(notice)
        }
    }

    // MARK: - One file

    /// What importing one ready file came to. `declines` is true when the file is still in the
    /// drop folder and trying it again unchanged would only repeat the answer.
    private enum ImportOutcome {
        case imported(String)
        case notice(ContenitoreNotice, declines: Bool)
    }

    private func importFile(_ source: URL, named name: String) async -> ImportOutcome {
        // Step 3: streamed off the main actor, so a large scan never sits in memory.
        let hash: String
        do {
            hash = try await Self.sha256(of: source)
        } catch {
            return .notice(.failed(file: name, reason: "lettura: \(error.localizedDescription)"), declines: false)
        }

        // Step 4: the index answers, not a walk (§D2).
        let root = settings.root.trimmingCharacters(in: .pathSlashes)
        if let existing = session.index.scheda(withSHA256: hash, underRoot: root) {
            return .notice(.duplicate(file: name, existing: existing.relativePath), declines: true)
        }

        // Step 5 (§D5): unique as a pair in the year folder and as a title across the vault (G4).
        let date = today()
        let folder = ContenitoreNaming.yearFolder(for: date, in: root)
        let ext = (name as NSString).pathExtension
        let stem = ContenitoreNaming.uniquePairStem(
            ContenitoreNaming.stem(forOriginal: name, importDate: date),
            extension: ext,
            takenFileNames: Set(fileNames(inFolder: folder)),
            takenTitles: Set(session.index.allNotes.map(\.title))
        )
        let fileName = ContenitoreNaming.fileName(stem: stem, extension: ext)
        let filePath = "\(folder)/\(fileName)"
        let schedaPath = "\(folder)/\(NoteName.fileName(for: stem))"

        // Step 6: the file first. A failure here leaves it where it was.
        do {
            try await session.adoptFromOutside(source, to: filePath)
        } catch {
            return .notice(.failed(file: name, reason: String(describing: error)), declines: false)
        }

        // Step 7: the scheda, refused rather than written over anything that appeared meanwhile.
        do {
            try beforeSchedaWrite?(schedaPath)
            let text = ContenitoreScheda.render(date: date, fileName: fileName, originalName: name, sha256: hash)
            try await session.write(text, to: schedaPath, expectingAbsent: true)
            return .imported(schedaPath)
        } catch {
            // Step 8: the file goes back; nothing is ever deleted.
            let cause = String(describing: error)
            do {
                try await session.returnToOutside(filePath, to: source)
                return .notice(.failed(file: name, reason: cause), declines: true)
            } catch {
                return .notice(
                    .failed(file: name, reason: "\(cause); il file è rimasto in «\(filePath)»"), declines: false
                )
            }
        }
    }

    /// The names directly inside a vault folder, or none when it does not exist yet.
    private func fileNames(inFolder folder: String) -> [String] {
        guard let url = try? session.store.url(for: folder) else { return [] }
        return (try? FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false))) ?? []
    }

    /// The file's SHA-256 as 64 lowercase hex digits, read in 1 MiB chunks on a detached task at
    /// utility priority.
    nonisolated static func sha256(of url: URL) async throws -> String {
        try await Task.detached(priority: .utility) {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hasher = SHA256()
            while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
            return NoteStore.hexString(hasher.finalize())
        }.value
    }
}
