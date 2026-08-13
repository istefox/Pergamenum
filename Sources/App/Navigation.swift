import Foundation
import Observation

/// Which pane the window is showing, and what the editor has been asked to insert.
///
/// Both live here rather than in the views that own them because the menu bar needs
/// to reach them: a Vista menu that cannot change the pane, or an Inserisci menu that
/// cannot reach the editor, would be a menu that does nothing (SPEC §10).
@MainActor
@Observable
final class Navigation {
    /// The panes of the sidebar.
    enum Pane: String, CaseIterable, Identifiable, Hashable, Sendable {
        case vault
        case workspace
        case today
        case tasks
        case conformance

        var id: String { rawValue }

        var title: String {
            switch self {
            case .vault: "Vault"
            case .workspace: "Workspace"
            case .today: "Oggi"
            case .tasks: "Attività"
            case .conformance: "Conformità"
            }
        }

        var symbol: String {
            switch self {
            case .vault: "books.vertical"
            case .workspace: "square.on.square"
            case .today: "calendar"
            case .tasks: "checklist"
            case .conformance: "checkmark.seal"
            }
        }

        /// The Vista menu's shortcut, where §10 gives one.
        var shortcut: Character? {
            switch self {
            case .today: "t"
            default: nil
            }
        }
    }

    var pane: Pane = .vault

    /// Whether the Vault shows the note rendered rather than as source.
    ///
    /// Here rather than in `VaultBrowser` because SPEC §10 puts the switch in the
    /// Vista menu, on Cmd+Shift+E, and a menu that cannot reach the state it names
    /// is a menu that does nothing - which is what the shortcut hung on the picker
    /// did, silently.
    var isReadingMode = false

    /// Text the Inserisci menu has asked the editor to put at the cursor.
    ///
    /// A request rather than a call: the menu has no reference to the `NSTextView`,
    /// and giving it one would mean the menu stops working the moment the editor is
    /// rebuilt. The editor consumes this and clears it.
    private(set) var pendingInsertion: String?
    /// How far to move the cursor back after inserting, so it lands inside the
    /// brackets of `[[]]` rather than after them.
    private(set) var pendingCursorOffset = 0

    func insert(_ text: String, cursorBack offset: Int = 0) {
        pendingInsertion = text
        pendingCursorOffset = offset
        pane = .vault
    }

    func consumeInsertion() -> (text: String, cursorBack: Int)? {
        guard let text = pendingInsertion else { return nil }
        defer {
            pendingInsertion = nil
            pendingCursorOffset = 0
        }
        return (text, pendingCursorOffset)
    }

    /// The two Aiuto entries of SPEC §10.
    var isShowingTaskSyntaxHelp = false
    var isShowingConventionsHelp = false

    /// Set by the Modifica menu; the editor opens its find bar when it sees it.
    var isFindRequested = false
    var isReplaceRequested = false
}
