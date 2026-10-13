import Foundation
import Synchronization

/// A change marker for the open-note buffer's text (ADR-0096 §D1, PG-406).
///
/// Opaque and equatable: two buffers that differ in text never share one, and every assignment
/// to a buffer's text draws a new one, so equality and change detection read this instead of the
/// whole `String`. Not the version history of ADR-0011.
///
/// Unique by one process-wide atomic counter: only uniqueness is read, so `.relaxed` is enough,
/// and 2^64 draws do not wrap in the life of a process.
struct TextRevision: Hashable, Sendable {
    private static let counter = Atomic<UInt64>(0)

    // Private, so the synthesized memberwise initializer is private too: only `next()` makes one.
    private let value: UInt64

    /// A revision no other call has answered.
    static func next() -> TextRevision {
        TextRevision(value: counter.wrappingAdd(1, ordering: .relaxed).newValue)
    }
}
