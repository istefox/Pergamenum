import Foundation

// PG-387 (N4), ADR-0085 §D1/§D2, plan docs/plans/pg-387-n4-birth-of-note.md, Task 5 - R-01.

/// What «Da classificare» lists: the notes of the vault that carry `status-inbox`, a Contenitore
/// scheda included, as rows ordered by date (newest first), then modification time (newest
/// first), then title.
///
/// Pure over the index's records: the pane reads them per generation and never caches a row
/// (principle 3), so a filing elsewhere takes the row out at the next rescan.
enum UnfiledListModel {
    struct Row: Identifiable, Equatable {
        let id: String
        let title: String
        let folder: String
        let date: CalendarDate?
        let modifiedAt: Date?
        let isScheda: Bool
    }

    private static let inbox = ContenitoreListModel.inboxTag

    /// The rows for `records`, restricted to `folder` when it is not nil.
    static func rows(from records: [NoteRecord], folder: String?) -> [Row] {
        unfiled(records)
            .map { record in
                Row(
                    id: record.relativePath, title: record.title, folder: parentFolder(of: record.relativePath),
                    date: record.frontmatter.date, modifiedAt: record.modifiedAt,
                    isScheda: record.contenitore != nil
                )
            }
            .filter { folder == nil || $0.folder == folder }
            .sorted(by: precedes)
    }

    /// The folders the unclassified notes sit in, with how many each holds; empty when none.
    /// Ordered by folder name, the order the folder filter lists them in.
    static func folders(from records: [NoteRecord]) -> [(folder: String, count: Int)] {
        let counts = Dictionary(grouping: unfiled(records), by: { parentFolder(of: $0.relativePath) })
            .mapValues(\.count)
        return counts.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { ($0, counts[$0] ?? 0) }
    }

    /// The row to select once `removed` has left `rows`: the next one, else the previous, else nil.
    static func selection(after removed: String, in rows: [Row]) -> String? {
        guard let index = rows.firstIndex(where: { $0.id == removed }) else { return nil }
        if rows.indices.contains(index + 1) { return rows[index + 1].id }
        if index > 0 { return rows[index - 1].id }
        return nil
    }

    // MARK: - Pieces

    private static func unfiled(_ records: [NoteRecord]) -> [NoteRecord] {
        records.filter { $0.frontmatter.tags.contains(inbox) }
    }

    private static func parentFolder(of path: String) -> String {
        (path as NSString).deletingLastPathComponent
    }

    /// Date newest first, an undated row after every dated one; then the most recently modified;
    /// then the title.
    private static func precedes(_ lhs: Row, _ rhs: Row) -> Bool {
        if lhs.date != rhs.date {
            guard let left = lhs.date else { return false }
            guard let right = rhs.date else { return true }
            return left > right
        }
        if lhs.modifiedAt != rhs.modifiedAt {
            return (lhs.modifiedAt ?? .distantPast) > (rhs.modifiedAt ?? .distantPast)
        }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}
