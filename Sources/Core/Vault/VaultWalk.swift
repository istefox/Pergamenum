import Foundation

/// The one vault walk, replacing the three drifted copies in `VaultScanner.scan()`,
/// `CanvasStore.walk()` and `FolderFileOperations.walk(_:)` (ADR-0041 §D3, Task 4).
///
/// **Interface declared by the tester; body implemented by the coder.** `init` resolves
/// its starting directory through `VaultBoundary.url(for:)` — the boundary is the only
/// way in, which is what stops the walk from being a route around the guard `VaultBoundary`
/// exists to enforce. The real single-`FileManager.enumerator` walk, its
/// `VaultLayout.isExcludedDirectory` → `skipDescendants()` wiring, and the once-per-`init`
/// root standardisation are Task 4's coder work and are deliberately absent here: every
/// test in `Tests/VaultWalkTests.swift` that depends on them is red against this stub,
/// for that reason and no other.
struct VaultWalk: Sendable {
    struct Entry: Sendable {
        let url: URL
        let relativePath: String
        let name: String
        let isDirectory: Bool
        let byteSize: Int?
        let modifiedAt: Date?
    }

    /// `subfolder.isEmpty` deliberately skips `boundary.url(for:)`: that resolver refuses
    /// `""` (SPEC/`VaultBoundary` doc: "the vault directory is not one"), but an empty
    /// subfolder here means "walk the whole vault", not "resolve a file named nothing".
    /// A non-empty subfolder still goes through the boundary, which is what makes
    /// `subfolder: "../escape"` throw.
    init(boundary: VaultBoundary, subfolder: String = "", keys: Set<URLResourceKey> = []) throws {
        if !subfolder.isEmpty {
            _ = try boundary.url(for: subfolder)
        }
    }

    func forEach(_ body: (Entry) -> Void) {
        // Stub: yields nothing. The coder's real enumerator replaces this body.
    }
}
