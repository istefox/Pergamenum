import Foundation

/// The window-shaped half of a batch move (ADR-0026 §D8, §D10): `canOperate`/
/// `canOperateOnFolder` before anything touches disk, `flushBoard()` first so the
/// autosave cannot recreate what just moved (ADR-0022 §F10), every moved note followed
/// into tabs and RECENTI, a rescan afterwards, and **one** block registered on `undo`
/// for the whole batch - a six-row move is one undo step (R-12), and the block
/// re-registers itself with the arguments swapped, which is how `UndoManager` produces
/// redo with no custom redo code.
///
/// `Tests/VaultMoveTests.swift` (ADR-0026, this plan's Task 3) owns this signature; the
/// body here is a placeholder so the target builds - the real dispatch and the undo
/// registration are the code step's, not the test step's.
extension VaultController {
    @discardableResult
    func moveItems(_ items: [VaultItemRef], into destination: String, undo: UndoManager?) -> Bool {
        false
    }
}
