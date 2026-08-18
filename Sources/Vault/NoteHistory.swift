import Foundation

/// Every past version of a note, kept for a person to browse and restore (ADR-0011).
///
/// A second store beside `WriteJournal`, deliberately not the same one: that type is a
/// connector's own safety net and says so in its own header - "not a version history".
/// This one answers a different question, "show me this note five saves ago", and is
/// filled by every write to a note, app or connector alike.
///
/// Under `.pergamenum/`, with the rest of the disposable state, though "disposable" is
/// not quite the whole story: losing `.pergamenum/history/` loses the old versions and
/// nothing else, the same guarantee `WriteJournal` carries for its own directory - but
/// unlike `cache.db` it cannot be rebuilt from a vault scan, because nothing else on
/// disk remembers what a note looked like before its last save.
///
/// One file per snapshot, laid out under a directory that mirrors the note's own
/// relative path, rather than one JSONL keyed by a hash: text notes are small, so a
/// diff engine buys nothing a full copy does not already give for free (`WriteJournal`
/// made the identical call for `textBefore`), and a person looking at
/// `.pergamenum/history/` on disk can find a note's history by eye.
struct NoteHistory {
    let directory: URL

    init(root: URL) {
        directory = root
            .appending(path: VaultLayout.privateDirectory, directoryHint: .isDirectory)
            .appending(path: "history", directoryHint: .isDirectory)
    }

    /// One saved version of a note.
    struct Snapshot: Equatable, Sendable {
        let date: Date
        let text: String
    }

    private func noteDirectory(for relativePath: String) -> URL {
        directory.appending(path: relativePath, directoryHint: .isDirectory)
    }

    /// Writes a snapshot and thins what is left in that note's own directory.
    ///
    /// `date` defaults to now; a test names it, because thinning cannot be tested
    /// without naming the clock. A snapshot that fails to write is not a reason to fail
    /// the note write it came from - the same asymmetry `WriteJournal.record` keeps by
    /// returning a problem rather than throwing one.
    func record(_ text: String, for relativePath: String, at date: Date = Date()) {
        let noteDir = noteDirectory(for: relativePath)
        let file = noteDir.appending(path: Self.fileName(for: date))
        do {
            try FileManager.default.createDirectory(at: noteDir, withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
        } catch {
            return
        }
        thin(noteDir, now: date)
    }

    /// Every snapshot for a note, newest first. A filename that will not parse is
    /// skipped rather than failing the read - the same defensiveness `WriteJournal`
    /// keeps for a line that will not decode.
    func snapshots(for relativePath: String) -> [Snapshot] {
        let noteDir = noteDirectory(for: relativePath)
        guard let names = try? FileManager.default.contentsOfDirectory(
            atPath: noteDir.path(percentEncoded: false)
        ) else { return [] }
        return names
            .compactMap { name -> Snapshot? in
                guard let date = Self.date(from: name),
                      let text = try? String(contentsOf: noteDir.appending(path: name), encoding: .utf8)
                else { return nil }
                return Snapshot(date: date, text: text)
            }
            .sorted { $0.date > $1.date }
    }

    /// The date of every snapshot, newest first, without reading a single one's text.
    ///
    /// One directory listing where `snapshots(for:)` is one listing plus a file read per
    /// entry. The inspector shows how many versions a note has and when the last one
    /// was, on every pass of its body; doing that through the full read would open every
    /// version of the note to display two numbers.
    func snapshotDates(for relativePath: String) -> [Date] {
        let noteDir = noteDirectory(for: relativePath)
        guard let names = try? FileManager.default.contentsOfDirectory(
            atPath: noteDir.path(percentEncoded: false)
        ) else { return [] }
        return names.compactMap(Self.date(from:)).sorted(by: >)
    }

    // MARK: Thinning

    /// Keeps every snapshot from the last 24 hours, and at most one per calendar day
    /// before that. No expiry: the older set shrinks to one-per-day and stays there -
    /// text is cheap, unlike Time Machine's own original case.
    private func thin(_ noteDir: URL, now: Date) {
        guard let names = try? FileManager.default.contentsOfDirectory(
            atPath: noteDir.path(percentEncoded: false)
        ) else { return }
        let cutoff = now.addingTimeInterval(-86_400)
        let calendar = Calendar.current

        let older = names.compactMap { name -> (name: String, date: Date)? in
            guard let date = Self.date(from: name), date < cutoff else { return nil }
            return (name, date)
        }
        // Grouped by day first, so "the newest of this group" is one reduction rather
        // than a running comparison carried across the whole directory listing.
        let byDay = Dictionary(grouping: older, by: { calendar.startOfDay(for: $0.date) })
        let keep = Set(byDay.values.compactMap { group in group.max(by: { $0.date < $1.date })?.name })

        for entry in older where !keep.contains(entry.name) {
            try? FileManager.default.removeItem(at: noteDir.appending(path: entry.name))
        }
    }

    // MARK: Naming

    /// Reuses `WriteJournal.makeID` rather than a second formatter: the shape it needs
    /// is the same one that type already built - sortable, unique enough, a person can
    /// read it - for the identical reason.
    private static func fileName(for date: Date) -> String {
        WriteJournal.makeID(at: date) + ".md"
    }

    /// The inverse of `WriteJournal.makeID`'s own format, `yyyyMMdd-HHmmss` followed by
    /// a four-character suffix this reader ignores: only the first 15 characters carry
    /// a date at all.
    private static func date(from fileName: String) -> Date? {
        guard fileName.hasSuffix(".md") else { return nil }
        let base = String(fileName.dropLast(3))
        guard base.count > idDateFormat.count else { return nil }
        return idDateFormatter.date(from: String(base.prefix(idDateFormat.count)))
    }

    private static let idDateFormat = "yyyyMMdd-HHmmss"

    private static let idDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = idDateFormat
        formatter.timeZone = .current
        return formatter
    }()
}
