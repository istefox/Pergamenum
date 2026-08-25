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
        /// The starred notes of ADR-0012 §D6. A place and not a filter: a row that only
        /// scrolled the note list to a section left the sidebar lit on «Note» and read
        /// like a click that had gone nowhere.
        case starred
        /// The saved views of ADR-0009, listed. A pane and not a section of the note
        /// list: a view is a question about the whole vault, and the note it is written
        /// in is where it lives rather than what it is about.
        case views

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
            case .starred: "Preferite"
            case .views: "Viste"
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
            case .starred: "star"
            case .views: "tablecells"
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
            case .starred: .paneStarred
            case .views: .paneViews
            }
        }
    }

    var pane: Pane = .notes

    /// Whether the Note pane shows its inspector - backlinks, linked tasks, and the
    /// unlinked mentions of ADR-0012 D9.
    ///
    /// Here rather than as `@State` in `VaultBrowser`, where it started: a `@State` is
    /// reachable by the toolbar button beside it and by nothing else, so the panel that
    /// holds three of the app's answers had no key and no menu entry.
    var isShowingInspector = true

    /// Whether the Workspace shows its tray - unplaced items, linked tasks, and the
    /// board dashboard of ADR-0021 §D7.
    ///
    /// Here for the same reason `isShowingInspector` is: it started as `@State` in
    /// `WorkspaceView`, where the toolbar toggle beside it was the only thing that
    /// could reach it, so the Vista menu had no way to offer «Pannello Workspace».
    var isShowingTray = true

    /// Whether the Workspace hides its three chrome panels - the app sidebar, the board
    /// list and the tray - down to the board and its vertical tool column.
    ///
    /// Here for the same reason `isShowingTray` is: the menu bar's Vista entry needs to
    /// reach it. Hides rather than turns off: `isShowingTray` is untouched while this is
    /// on, so leaving the mode returns the tray to whatever state it was actually in.
    var isWorkspaceFocused = false

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

    /// The same jump, asked for by something that is not the outline: a task row in the
    /// week, which knows the line it wants and not the heading above it.
    ///
    /// A second name rather than a second mechanism. The editor has one way of being
    /// told where to go, and a view that invented another would be a second place for
    /// the caret to land wrong.
    func jumpToLine(range: NSRange, ordinal: Int) {
        jumpToOutlineEntry(range: range, ordinal: ordinal)
    }

    // Reading mode, the current index entry and the folds used to be stored here. They
    // are note state, not window state, and moved onto `NoteTab` when a window stopped
    // showing exactly one note (ADR-0012 D2). `VaultController` still exposes all three,
    // so the menus that reach them did not change.
}
