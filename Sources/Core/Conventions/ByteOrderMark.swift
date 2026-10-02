import Foundation

/// The UTF-8 byte order mark, `EF BB BF`.
///
/// A BOM is a property of the file, not of its content (ADR-0065 §D4): one decode door strips
/// it, the hash skips it, and a write keeps whatever the file had. `NoteStore` applies the rule to
/// a note and `CanvasStore` to a `.canvas` (PG-280), both through these three helpers.
enum ByteOrderMark {
    static let utf8 = Data([0xEF, 0xBB, 0xBF])

    static func has(_ data: Data) -> Bool {
        data.starts(with: utf8)
    }

    /// `data` without its leading BOM, or `data` itself.
    static func stripping(_ data: Data) -> Data {
        has(data) ? data.dropFirst(utf8.count) : data
    }

    /// Whether the file at `url` starts with a BOM: reads three bytes, not the file, so a write
    /// pays one extra small read. A file that cannot be opened has none.
    static func starts(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: utf8.count)) == utf8
    }

    /// `data` with a leading BOM when the file at `url` has one and `data` does not, else `data`
    /// itself: a file that starts with one keeps it, a new file or one without never gains one.
    static func keeping(of url: URL, onto data: Data) -> Data {
        guard !has(data), starts(url) else { return data }
        return utf8 + data
    }
}
