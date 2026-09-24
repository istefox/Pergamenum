import Foundation
@testable import Pergamenum

/// The diary's controller against a real vault on disk: what it writes, when it writes
/// it, and the days it leaves alone.
///
/// Moved here from `Tests/DiaryControllerTests.swift` and `Tests/DiaryComposerTests.swift`
/// (ADR-0051 §D2), where it was declared `private`, byte-identical, in both files. Shared
/// rather than copied a third and fourth time by `Tests/DiaryWriteDoorTests.swift`,
/// `Tests/DiaryWriteGuardTests.swift` and `Tests/DiaryConflictTests.swift`.
@MainActor
func makeDiary(_ vault: borrowing TemporaryVault) async throws -> (DiaryController, VaultController) {
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    let diary = DiaryController(vault: controller)
    diary.show(testDay)
    return (diary, controller)
}

/// Takes the root rather than the vault: `TemporaryVault` is noncopyable, and a `#expect`
/// or `#require` that borrows one does not compile - the macro's autoclosure wants a
/// copy.
func diaryOnDisk(_ root: URL) -> String? {
    try? String(contentsOf: root.appending(path: "Diario/20260811.md"), encoding: .utf8)
}
