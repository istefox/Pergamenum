import Foundation

/// What the editor last wrote to its binding, and how many character edits the storage had reported
/// when it did, so `updateNSView` can tell "the model still holds what this view holds" without
/// comparing the whole note (ADR-0094 §D9, PG-406).
///
/// The compare it replaces, `textView.string != text`, is linear in the note and ran on every update
/// SwiftUI made after a keystroke: 37 ms at 1 MB in Debug, 2 ms at 50 KB. The record answers the same
/// question exactly, in two steps that each can only say yes when it is true:
///
/// - no character edit reached the storage since the binding was written, so the view still holds
///   the text it wrote;
/// - the model's text equals the text written. Both are the same `String` value on the path the app
///   takes (the setter stores what it was given), and Swift compares two values that share storage
///   without reading it. A model that was replaced from outside (an undo, a reload) is a different
///   value and falls through to the full compare, which is what decides it.
struct ModelSync {
    /// The text the last binding write handed over; nil until there is one.
    private var written: String?
    /// The storage's character-edit count at that write.
    private var editsAtWrite = 0
    /// Every character edit the storage has reported, counted with the kill switch on too.
    private var edits = 0

    /// How many times the fallback branch compared the whole text (ADR-0095 §D8, PG-406): a test seam
    /// that proves a keystroke compares nothing. Counted in every configuration.
    private(set) var compares = 0

    /// The fallback branch is about to compare `textView.string != text`.
    mutating func countCompare() { compares += 1 }

    /// A character edit the storage reported.
    mutating func heardEdit() { edits += 1 }

    /// The binding was just written with `text`, the view's own current text.
    mutating func wrote(_ text: String) {
        written = text
        editsAtWrite = edits
    }

    /// True only when the view's text is known to be `model`: written by the view, untouched since,
    /// and the model still holds exactly that value. False means "compare", never "differs".
    func viewHolds(_ model: String) -> Bool {
        guard let written, editsAtWrite == edits else { return false }
        return written == model
    }
}
