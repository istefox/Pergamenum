import Foundation

// ADR-0084 §D4 (PG-386, N3 session A).

/// The reverse reason of the structural-link sheet: an editable mirror of the forward one.
///
/// It follows the forward reason as it is typed until the person edits it, and is never
/// overwritten after that - an edit that happens to equal the forward text is still an edit.
struct ReverseReasonMirror: Equatable, Sendable {
    private(set) var reverse: String = ""
    private(set) var isEdited: Bool = false

    mutating func forwardChanged(to forward: String) {
        guard !isEdited else { return }
        reverse = forward
    }

    mutating func reverseEdited(to text: String) {
        reverse = text
        isEdited = true
    }
}
