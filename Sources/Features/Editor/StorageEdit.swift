import Foundation

/// One character edit of the note's text storage, as `textStorage(_:willProcessEditing:range:changeInLength:)`
/// reports it (ADR-0091 §D2, C4).
///
/// `range` is in the text as it now is, and `delta` is the change in length, so the replaced old
/// range is `range.location ..< range.location + range.length - delta`. The three rules below are
/// the ones every offset-keyed holder applies (ADR-0091 §D2, §D5, §D6): a thing after the old range
/// moves by `delta`, one before it stays, one that contains it stretches, and one that lies partly
/// inside it is lost. `shiftedKeys` applies them to a table keyed by offset.
///
/// Foundation only (ADR-0091 §D1).
struct StorageEdit: Equatable, Sendable {
    var range: NSRange
    var delta: Int

    /// The range the edit replaced, in the text as it was.
    var oldRange: NSRange {
        NSRange(location: range.location, length: range.length - delta)
    }

    /// Where an offset goes: unchanged before the old range, moved by `delta` at or after its end.
    /// An offset strictly inside the old range has no image; it lands at the end of the new range.
    func shifted(_ offset: Int) -> Int {
        let old = oldRange
        if offset <= old.location { return offset }
        if offset >= NSMaxRange(old) { return offset + delta }
        return NSMaxRange(range)
    }

    /// Where a range goes: unchanged before the old range, moved after it, stretched when it
    /// contains it, and nil when it lies partly or wholly inside it. A range that was exactly the
    /// text a deletion removed is wholly inside it, and is lost rather than left empty.
    func shifted(_ range: NSRange) -> NSRange? {
        let old = oldRange
        let end = NSMaxRange(range)
        if end <= old.location { return range }
        if range.location >= NSMaxRange(old) {
            return NSRange(location: range.location + delta, length: range.length)
        }
        if range.location <= old.location, end >= NSMaxRange(old), range.length + delta > 0 {
            return NSRange(location: range.location, length: range.length + delta)
        }
        return nil
    }

    /// Where an offset used as a key goes: `shifted(_:)` for an offset outside the old range, and
    /// nil for one strictly inside it, whose line the edit rewrote.
    func shiftedKey(_ key: Int) -> Int? {
        let old = oldRange
        if key <= old.location { return key }
        if key >= NSMaxRange(old) { return key + delta }
        return nil
    }

    /// A table keyed by offset, re-keyed by `shiftedKey(_:)`. Where a key that moved lands on one
    /// that stayed (a deletion that starts at a line and ends at the next one), the moved key wins:
    /// it names the line that now starts there.
    func shiftedKeys<Value>(_ table: [Int: Value]) -> [Int: Value] {
        let old = oldRange
        var result: [Int: Value] = [:]
        result.reserveCapacity(table.count)
        var moved: [(key: Int, value: Value)] = []
        for (key, value) in table {
            if key <= old.location {
                result[key] = value
            } else if key >= NSMaxRange(old) {
                moved.append((key + delta, value))
            }
        }
        for entry in moved { result[entry.key] = entry.value }
        return result
    }

    /// A set of offsets, each moved by `shiftedKey(_:)`.
    func shiftedKeys(_ offsets: Set<Int>) -> Set<Int> {
        Set(offsets.compactMap(shiftedKey))
    }

    /// What is left of a range once the old range is cut out: the whole range moved the way
    /// `shifted(_:)` moves it, or only its parts outside the old range when it crosses an end.
    func clipped(_ range: NSRange) -> [NSRange] {
        if let whole = shifted(range) { return [whole] }
        let old = oldRange
        var parts: [NSRange] = []
        if range.location < old.location {
            parts.append(NSRange(location: range.location, length: old.location - range.location))
        }
        let end = NSMaxRange(range)
        if end > NSMaxRange(old) {
            parts.append(NSRange(location: NSMaxRange(self.range), length: end - NSMaxRange(old)))
        }
        return parts
    }
}
