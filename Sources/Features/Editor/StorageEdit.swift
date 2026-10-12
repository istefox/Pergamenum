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

// MARK: - The window predicates and the end-anchored rule (ADR-0094 §D3)
//
// The step buffer's two shapes find the entries an edit reaches with these predicates, and hand each
// one to the rules above; `precedes` wins when both hold, as in `shifted(_:)` and `shiftedKeys`. A key
// is the empty range at its offset.

extension StorageEdit {
    /// Whether `range` ends at or before the old range's start, so the edit leaves it where it is.
    func precedes(_ range: NSRange) -> Bool {
        NSMaxRange(range) <= oldRange.location
    }

    /// Whether `range` starts at or after the old range's end, so the edit moves it by `delta`.
    func follows(_ range: NSRange) -> Bool {
        range.location >= NSMaxRange(oldRange)
    }

    /// `shifted(_:)`, except that a range that reached the end of the old text (`oldLength`) still
    /// reaches the end of the new one: an unclosed fence runs to the end of the note, whatever is typed
    /// after its last character. The structure map's fence rule, moved here from `StructureMap`.
    ///
    /// The new end is computed as `oldLength + delta`, where the removed `StructureMap` rule read the
    /// real new text length. The two agree only while `oldLength` is the length of the text the edit
    /// was made to, i.e. the new text's length minus `delta`. That holds today because every edit
    /// reaches the map through `RestyleScope.record`, in order, and `record` leaves on
    /// `.full(.wholesale)` before `applying` on a wholesale replace and on every edit after it, until
    /// a full restyle rebuilds the map. A caller that reaches this rule another way must establish it.
    func shifted(_ range: NSRange, anchoringTheEndOf oldLength: Int) -> NSRange? {
        if NSMaxRange(range) == oldLength, oldRange.location >= range.location {
            return NSRange(location: range.location, length: oldLength + delta - range.location)
        }
        return shifted(range)
    }
}
