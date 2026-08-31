import Foundation

/// A folder or board's own leaf name, as typed into a create/rename sheet - distinguished
/// from `FolderPath` so a same-typed (name, parent) pair can no longer be swapped by
/// position and still compile (PG-050).
struct FolderName: Equatable, Hashable, Sendable, ExpressibleByStringLiteral {
    var value: String
    init(_ value: String) { self.value = value }
    init(stringLiteral value: String) { self.value = value }
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
