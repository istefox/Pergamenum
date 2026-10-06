import Foundation

// ADR-0045's `Type+Aspect.swift` convention: the row's accessibility identifiers, split out
// of `PraticaMessageRow.swift` for its own file length - moved verbatim, nothing widened.

extension PraticaMessageRow {
    // MARK: - Identifiers

    /// `pratiche-message-<messageIDHash>` (UX-BLUEPRINT's checklist).
    static func identifier(for entry: PraticaTimelineEntry) -> String {
        "pratiche-message-\(hash(of: entry))"
    }

    /// A `Message-ID` is an arbitrary string with `<`, `@` and `.` in it - unusable as
    /// an identifier and unstable to read. This is FNV-1a written out rather than
    /// `hashValue`, which is seeded per process and would give a UI test a different
    /// answer on every launch.
    static func hash(of entry: PraticaTimelineEntry) -> String {
        var value: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in Array((entry.messageID ?? entry.id).utf8) {
            value ^= UInt64(byte)
            value &*= 0x0000_0100_0000_01b3
        }
        return String(value, radix: 16)
    }
}
