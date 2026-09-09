import Foundation

// ADR-0036 (Pratiche), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 7 -
// R-31, R-34; UX-BLUEPRINT.md's menu bar map, "Pratica" row.
//
// One command a pratica row offers, named once so the row's context menu, the "Vista >
// Pratica" submenu and the list-column toolbar (ADR-0023 §D1) read the same catalogue
// instead of three hand-kept lists that can drift apart.
///
/// `import Foundation` only, deliberately: a pure catalogue a test can read without
/// pulling in SwiftUI, matching `CardCommand`'s own header. Not in `sharedSources` -
/// the connectors have no pratica-row UI (SPEC "AI connector" boundary, R-36).
///
/// Every declaration below is a tester-declared boundary (ADR-0155 §D1): `available`
/// is stubbed to `[]`, the same wrong-but-safe constant `CardCommand`'s own RED phase
/// used, never `fatalError`.
enum PraticaCommand: String, CaseIterable, Sendable {
    case open
    case rename
    /// R-34: swaps `status-active` ↔ `status-archived`. Split into two cases rather
    /// than one dynamically-labelled command, mirroring `CardCommand`'s own
    /// `.fitToCrop`/`.removeCrop` pair - `available(isActive:)` offers exactly one of
    /// the two, never both.
    case close
    case reopen
    case refresh
    case revealInFinder
    /// R-34: moves the folder to the Trash via `FileManager.trashItem`. The only
    /// alert in the feature («Elimina pratica») guards this one (plan Task 7).
    case delete

    /// The Italian label both surfaces draw for this command, pinned to
    /// UX-BLUEPRINT.md's menu bar map ("Pratica" row) and its keyboard-shortcuts table.
    var title: String {
        switch self {
        case .open: "Apri"
        case .rename: "Rinomina…"
        case .close: "Chiudi"
        case .reopen: "Riapri"
        case .refresh: "Aggiorna ora"
        case .revealInFinder: "Mostra nel Finder"
        case .delete: "Elimina…"
        }
    }

    /// The SF Symbol both surfaces draw for this command - one table, so the toolbar's
    /// icon and the menu's icon cannot disagree (`CardCommand.symbol`'s own reasoning,
    /// R-13's shape applied to this cluster).
    var symbol: String {
        switch self {
        case .open: "arrow.up.forward.square"
        case .rename: "pencil"
        case .close: "tray.and.arrow.down"
        case .reopen: "tray.and.arrow.up"
        case .refresh: "arrow.clockwise"
        case .revealInFinder: "folder"
        case .delete: "trash"
        }
    }

    /// The commands a pratica row offers, given whether it is currently
    /// `status-active`/`status-waiting` (`isActive == true`) or
    /// `status-archived`/`status-final` (R-34, `PraticheSidebarGrouping.isClosed`).
    ///
    /// RED stub: always `[]` - every applicability assertion below fails until the
    /// coder fills this in for real.
    static func available(isActive: Bool) -> [PraticaCommand] {
        []
    }

    /// The one stable AX identifier for this command's control, shared by the toolbar
    /// and the row's own context menu (matching `CardCommand.identifier`'s reasoning).
    var identifier: String {
        "pratiche-command-\(rawValue)"
    }
}
