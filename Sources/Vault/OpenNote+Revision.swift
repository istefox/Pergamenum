import Foundation

/// The read side of the open-note buffer's revisions (ADR-0095 §D2 and §D3, PG-406).
///
/// The three writers that link `savedRevision` to `revision` (`adopt(_:)`, `recordWrite(_:)`,
/// `settleUnsavedMark()`) live beside the stored properties in `NoteTab.swift`: the setters are
/// `private(set)`, and Swift reaches a private setter only from the declaring file. Keeping them
/// private is what keeps the invariant, `savedRevision == revision` implies `text == savedText`,
/// out of reach of every other call site.
extension VaultController.OpenNote {
    /// The exact answer: what save, close and quit decide on. Constant time for a buffer the mark
    /// calls clean, the whole compare only for one it calls dirty.
    var differsFromSaved: Bool {
        revision == savedRevision ? false : text != savedText
    }

    /// Equality by revision, never by text (ADR-0095 §D2): constant in the note's size. Two buffers
    /// holding the same text compare unequal, which for SwiftUI means one more body evaluation,
    /// never a wrong one.
    static func == (lhs: VaultController.OpenNote, rhs: VaultController.OpenNote) -> Bool {
        lhs.revision == rhs.revision && lhs.savedRevision == rhs.savedRevision
            && lhs.relativePath == rhs.relativePath && lhs.title == rhs.title
            && lhs.externalChangePending == rhs.externalChangePending
    }
}
