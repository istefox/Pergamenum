import Foundation

/// A folder or board's own leaf name, as typed into a create/rename sheet - distinguished
/// from `FolderPath` so a same-typed (name, parent) pair can no longer be swapped by
/// position and still compile (PG-050).
struct FolderName: Equatable, Hashable, Sendable, ExpressibleByStringLiteral {
    var value: String
    init(_ value: String) { self.value = value }
    init(stringLiteral value: String) { self.value = value }

    /// Delegates to `NoteName.validate`: a folder name follows the same rules a note
    /// title does (`/` is already in `NoteName.forbiddenCharacters`).
    ///
    /// A delegation rather than a second rule set, deliberately: the sheets render the
    /// violations through `ConformanceText.lines`, so a folder that answered to
    /// different rules would produce violation text describing a rule the user has
    /// never seen anywhere else in the app. `.`/`..` are the one exception: reused as
    /// `.containsForbiddenCharacter` rather than a new `NoteName.Violation` case (PG-045).
    ///
    /// Moved here from `FolderFileOperations.validate`, which still forwards to it, so
    /// the connector's board door can apply the Workspace sheet's rule from the shared
    /// sources (ADR-0063 §D4.1). A board name answers to it too.
    static func validate(_ name: String) -> [NoteName.Violation] {
        var violations = NoteName.validate(name)
        if name == "." || name == ".." { violations.append(.containsForbiddenCharacter(".")) }
        return violations
    }
}

/// A vault-relative folder path: the parent a folder verb targets, or the folder/board
/// path a rename/delete/move acts on - root spelled `""`. Distinguished from `FolderName`
/// for the same reason (PG-050).
struct FolderPath: Equatable, Hashable, Sendable, ExpressibleByStringLiteral {
    var value: String
    init(_ value: String) { self.value = value }
    init(stringLiteral value: String) { self.value = value }
    var isEmpty: Bool { value.isEmpty }
}
