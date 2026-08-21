import Foundation

/// Where in a note a line is, for the surfaces that know a line number and have to put
/// the caret on it.
///
/// A task knows the file it is in and the line it is on (`TaskItem.lineIndex`), which is
/// everything except the one thing the editor scrolls by: a character range. Until now
/// every "vai alla nota di origine" in the app opened the file and left the reader to
/// find the line themselves.
///
/// In `Core` and pure, beside `NoteOutline`, because it is the same conversion the
/// outline makes and it should be wrong in at most one place.
enum NoteJump {
    /// The range of a line, counting from zero, newline excluded.
    ///
    /// Nil when the note no longer has that many lines - which happens: the index is a
    /// snapshot and the file may have been edited since it was taken. Jumping to a line
    /// that is not there any more would put the caret at the end of the note and call it
    /// a hit.
    static func lineRange(_ index: Int, in text: String) -> Range<String.Index>? {
        guard index >= 0 else { return nil }

        var line = 0
        var start = text.startIndex
        while true {
            let end = text[start...].firstIndex(of: "\n") ?? text.endIndex
            if line == index { return start..<end }
            guard end < text.endIndex else { return nil }
            start = text.index(after: end)
            line += 1
        }
    }

    /// Which entry of the note's index a position sits under, for the reading view -
    /// which scrolls by block and cannot use a character range.
    ///
    /// The last entry that begins at or before the position, or zero for something above
    /// the first heading.
    static func ordinal(of position: String.Index, in text: String) -> Int {
        let entries = NoteOutline.entries(in: text)
        guard let last = entries.lastIndex(where: { $0.range.lowerBound <= position })
        else { return 0 }
        return last
    }
}
