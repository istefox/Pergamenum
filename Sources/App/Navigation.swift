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
        case tags
        /// The starred notes of ADR-0012 §D6. A place and not a filter: a row that only
        /// scrolled the note list to a section left the sidebar lit on «Note» and read
        /// like a click that had gone nowhere.
        case starred
        /// The saved views of ADR-0009, listed. A pane and not a section of the note
        /// list: a view is a question about the whole vault, and the note it is written
        /// in is where it lives rather than what it is about.
        case views
        /// The Plaud recordings of ADR-0032 §D15. A pane like the nine above and not a
        /// sheet reached from somewhere else: the list is a place a person comes back to
        /// while a transcription is running, which is what a destination is for.
        case recordings
        /// The pratiche of ADR-0036 §D-pane. Own list column (the pratiche tree, like
        /// Note owns `NoteListPane`), timeline and inspector - `PratichePane`, still the
        /// coder's body (Task 6/7). Appended, not inserted: `Navigation.Pane` is not
        /// itself an overrides-file key (`ShortcutCommand.rawValue` is), but the sidebar
        /// row order it drives is a placement fact this batch owns (plan Task 6, R-33),
        /// not Task 8's - Task 8 only measures `panePratiche`'s key against
        /// `com.apple.symbolichotkeys`.
        case pratiche

        var id: String { rawValue }

        var title: String {
            switch self {
            case .notes: "Note"
            case .workspace: "Workspace"
            case .today: "Oggi"
            case .diary: "Diario"
            case .tasks: "Attività"
            case .tags: "Tag"
            case .starred: "Preferite"
            case .views: "Viste"
            case .recordings: "Registrazioni"
            case .pratiche: "Pratiche"
            }
        }

        var symbol: String {
            switch self {
            case .notes: "doc.text"
            case .workspace: "square.on.square"
            case .today: "calendar"
            case .diary: "book.closed"
            case .tasks: "checklist"
            case .tags: "tag"
            case .starred: "star"
            case .views: "tablecells"
            case .recordings: "waveform"
            // Neither DESIGN.md nor UX-BLUEPRINT.md names an exact SF Symbol for the
            // sidebar row itself (both only draw/describe toolbar-button symbols inside
            // the pane - "plus", "arrow.clockwise", "sidebar.trailing"), so this is the
            // coordinator's own named fallback rather than a guess.
            case .pratiche: "folder.badge.person.crop"
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
            case .tags: .paneTags
            case .starred: .paneStarred
            case .views: .paneViews
            // Ctrl+Cmd+0, appended at the end of the catalogue (ADR-0032, ADR-0005 §D8):
            // the tenth pane takes the last free digit, and that exhausts them.
            case .recordings: .paneRecordings
            // Ctrl+Cmd+P, appended at the end of the catalogue (ADR-0036 §D8): the digits
            // are exhausted (`recordings` took the last one), so the eleventh pane takes
            // the next free letter on the same modifier pair instead.
            case .pratiche: .panePratiche
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

    /// Whether the Pratiche pane shows its inspector - `pratica.md`, which is the one
    /// place that file is edited (ADR-0036 §D13).
    ///
    /// A flag of its own rather than a second reader of `isShowingInspector`: the two
    /// panels hold different things, and a person who keeps the note pane's backlinks
    /// open has not asked to see a pratica's note beside every timeline. Closed by
    /// default, unlike the Note pane's, because the timeline is the pane's subject and
    /// the note is the thing you go and open (UX-BLUEPRINT "Navigation structure").
    ///
    /// Task 7 makes «Mostra/Nascondi nota della pratica» pane-aware in the Vista menu;
    /// the pane's own toolbar toggle (`pratiche-inspector-toggle`) reaches it today.
    var isShowingPraticaInspector = false

    /// «Nuova pratica…» (R-20) and «Aggiungi a pratica da Mail…» (R-21), each reached
    /// from a menu entry, a key and a button in the pane - three surfaces, one flag
    /// apiece, which is ADR-0023 §D1 applied to a command that opens a sheet.
    ///
    /// Here rather than as `@State` in `PratichePane`: the menu bar has no reference to
    /// a pane's private state, and the empty-state buttons of screen 1g are drawn by a
    /// pane that the Note pane's own focus mode can hide.
    var isShowingNuovaPratica = false
    var isShowingAddToPratica = false

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

    /// Whether the Workspace hides just its board-list pane (`WorkspaceBrowser`, the
    /// folder/board tree), leaving the tray and the rest of the chrome untouched.
    ///
    /// A pane of its own rather than folded into `isWorkspaceFocused`: that flag hides the
    /// tray along with the tree, and collapsing only the tree to free up board width is a
    /// narrower ask than "concentrazione" already covers. Here for the same reason
    /// `isShowingTray` is: the menu bar's Vista entry needs to reach it.
    var isWorkspaceTreeCollapsed = false

    /// The Note pane's own "concentrazione" (2026-08-28, toolbar parity chain): hides
    /// `NoteListPane` and the inspector, down to the editor alone. A flag of its own
    /// rather than reusing `isWorkspaceFocused` - the two sections are shown one at a
    /// time, but their chrome state must not leak into each other when the user
    /// switches back, the same reasoning `isWorkspaceFocused` already carries.
    var isNotesFocused = false

    /// Whether the Note pane hides just `NoteListPane`, leaving the editor and the
    /// inspector untouched. Mirrors `isWorkspaceTreeCollapsed`.
    var isNoteTreeCollapsed = false

    /// Text the Inserisci menu, or the insert-view command (R-04, ADR-0034 §D10), has asked
    /// the editor to put at the cursor.
    struct Insertion: Equatable, Sendable {
        var text: String
        /// How far to move the cursor back after inserting, so it lands inside the
        /// brackets of `[[]]` rather than after them.
        var cursorBack: Int
        /// Whether the editor should open the query builder on the fence this insertion
        /// just wrote, in the same gesture (ADR-0034 §D10). `false` for every ordinary
        /// insertion - only the insert-view command's stub sets it, through `insert`'s
        /// own defaulted parameter, so none of the other ten call sites change meaning.
        var opensQueryBuilder = false
    }

    /// A request rather than a call: the menu has no reference to the `NSTextView`,
    /// and giving it one would mean the menu stops working the moment the editor is
    /// rebuilt. The editor consumes this and clears it.
    private(set) var pendingInsertion: Insertion?

    func insert(_ text: String, cursorBack offset: Int = 0, opensQueryBuilder: Bool = false) {
        pendingInsertion = Insertion(text: text, cursorBack: offset, opensQueryBuilder: opensQueryBuilder)
        pane = .notes
    }

    func consumeInsertion() -> Insertion? {
        guard let insertion = pendingInsertion else { return nil }
        defer { pendingInsertion = nil }
        return insertion
    }

    /// The Aiuto entries of SPEC §10, and the Diario pane's own.
    var isShowingTaskSyntaxHelp = false
    var isShowingConventionsHelp = false
    var isShowingDiaryHelp = false

    /// The task `TaskCommand.linkBoard` opened `WorkspacePicker` for (ADR-0039 §D3).
    ///
    /// Held here rather than in `TasksView` (as `assigningWorkspaceFor` used to be): the
    /// command is reachable from the "Task collegati" panel too, which lives inside the
    /// Workspace pane where `TasksView` does not exist. `RootView` hosts the sheet, the one
    /// place every surface shares.
    var taskPickingBoard: TaskItem?

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

    /// A drag in the Outline pane asking to move a section (PG-019).
    ///
    /// A request and not a call, for the same reason `OutlineJump` is one: the sidebar has
    /// no reference to the editor's text view. `id` makes two identical moves two events,
    /// the same reason `OutlineJump.id` exists.
    struct OutlineMove: Equatable, Sendable {
        /// One range/text pair, wrapped only because a bare tuple has no `Equatable`
        /// Swift will synthesize - `OutlineMove.replacements` computes exactly what
        /// `NoteTextView.Coordinator.apply(_:to:)` already takes, in the order it requires.
        struct Replacement: Equatable, Sendable {
            var range: NSRange
            var text: String
        }
        var id: Int
        var replacements: [Replacement]
    }

    private(set) var outlineMove: OutlineMove?

    func moveOutlineSection(_ replacements: [(range: NSRange, text: String)]) {
        outlineMove = OutlineMove(
            id: (outlineMove?.id ?? 0) + 1,
            replacements: replacements.map { OutlineMove.Replacement(range: $0.range, text: $0.text) }
        )
        pane = .notes
    }

    // MARK: Folder reveal (2026-08-28, Note-pane breadcrumb chain)

    /// A folder `VaultTopBar`'s breadcrumb asked the Note tree to open and select.
    ///
    /// `id` makes two clicks on the same crumb two events, the same reason `OutlineJump`
    /// carries one - `NoteListPane`'s `.onChange` only fires on a value that actually
    /// changed, and clicking the same crumb twice in a row is a real request both times.
    struct FolderReveal: Equatable, Sendable {
        var id: Int
        /// `""` for the root crumb ("Note") - deselects the tree without touching the open
        /// note, the same spelling every path rule in this feature uses for the vault root.
        var folder: String
    }

    private(set) var folderReveal: FolderReveal?

    /// Not routed through `pane` the way `jumpToOutlineEntry` is: that jump can be asked
    /// for from outside the Note pane (a task row in the week), so it has to bring the
    /// pane with it. A breadcrumb crumb only exists inside the Note pane already showing.
    func revealFolder(_ folder: String) {
        folderReveal = FolderReveal(id: (folderReveal?.id ?? 0) + 1, folder: folder)
    }

    // Reading mode, the current index entry and the folds used to be stored here. They
    // are note state, not window state, and moved onto `NoteTab` when a window stopped
    // showing exactly one note (ADR-0012 D2). `VaultController` still exposes all three,
    // so the menus that reach them did not change.
}
