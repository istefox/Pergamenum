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
        case notes
        case workspace
        case today
        case diary
        case tasks
        case conformance
        case tags

        var id: String { rawValue }

        var title: String {
            switch self {
            case .notes: "Note"
            case .workspace: "Workspace"
            case .today: "Oggi"
            case .diary: "Diario"
            case .tasks: "Attività"
            case .conformance: "Conformità"
            case .tags: "Tag"
            }
        }

        var symbol: String {
            switch self {
            case .notes: "doc.text"
            case .workspace: "square.on.square"
            case .today: "calendar"
            case .diary: "book.closed"
            case .tasks: "checklist"
            case .conformance: "checkmark.seal"
            case .tags: "tag"
            }
        }

        /// The catalogue entry holding this pane's shortcut.
        ///
        /// Through the catalogue rather than as a literal here, so the Vista menu and
        /// the Scorciatoie settings pane read the same value and the user can change
        /// it. The panes used to share Cmd+T with the File menu's "Nota di oggi": two
        /// commands on one key, one of which never fired.
        var shortcut: ShortcutCommand {
            switch self {
            case .notes: .paneNotes
            case .workspace: .paneWorkspace
            case .today: .paneToday
            // Sixth key for the fourth row on purpose: the raw values of
            // `ShortcutCommand` are the keys of the overrides file, so renumbering the
            // panes to close the gap would silently move a binding the user had
            // changed. The Diario pane sits beside Oggi, where it belongs, and takes
            // the next free key.
            case .diary: .paneDiary
            case .tasks: .paneTasks
            case .conformance: .paneConformance
            case .tags: .paneTags
            }
        }
    }

    var pane: Pane = .notes

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
        pane = .notes
    }

    func consumeInsertion() -> (text: String, cursorBack: Int)? {
        guard let text = pendingInsertion else { return nil }
        defer {
            pendingInsertion = nil
            pendingCursorOffset = 0
        }
        return (text, pendingCursorOffset)
    }

    /// The Aiuto entries of SPEC §10, and the Diario pane's own.
    var isShowingTaskSyntaxHelp = false
    var isShowingConventionsHelp = false
    var isShowingDiaryHelp = false

    /// Set by the Modifica menu; the editor opens its find bar when it sees it.
    var isFindRequested = false
    var isReplaceRequested = false
    /// Cmd+G and Cmd+Shift+G, as a running total rather than a flag: pressing the same key
    /// twice has to be two steps, and a Bool set twice is one. The editor consumes the
    /// difference and writes back what it consumed.
    var findStep: Int?

    // MARK: The outline (M8)

    /// A jump the index in the sidebar has asked for.
    ///
    /// A request and not a call, for the same reason `pendingInsertion` is one: the
    /// sidebar has no reference to the editor, and giving it one would break the moment
    /// the editor is rebuilt. `id` makes two clicks on the same entry two events.
    struct OutlineJump: Equatable, Sendable {
        var id: Int
        /// The heading's line, for the editor, which scrolls by character.
        var range: NSRange
        /// The entry's position in the index, for the reading view, which scrolls by
        /// block. The two surfaces count differently and this ordinal is the bridge.
        var ordinal: Int
    }

    private(set) var outlineJump: OutlineJump?

    func jumpToOutlineEntry(range: NSRange, ordinal: Int) {
        outlineJump = OutlineJump(id: (outlineJump?.id ?? 0) + 1, range: range, ordinal: ordinal)
        pane = .notes
    }

    // Reading mode, the current index entry and the folds used to be stored here. They
    // are note state, not window state, and moved onto `NoteTab` when a window stopped
    // showing exactly one note (ADR-0012 D2). `VaultController` still exposes all three,
    // so the menus that reach them did not change.
}
