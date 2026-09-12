import SwiftUI

/// The create/rename sheets' decision logic, kept out of the view bodies so it is
/// testable without a view (ADR-0022 §D11).
enum WorkspaceNameField {
    /// What the sheet's "Crea"/"Rinomina" button reads to decide whether it is
    /// enabled, and what the inline violation text renders.
    enum State: Equatable {
        case invalid([NoteName.Violation])
        case taken
        case ok
    }

    /// `name` validated against `NoteName.validate`, then checked against the
    /// collision predicate `available` - `FolderFileOperations.nameIsAvailable`
    /// reached through `vault`, in the GREEN implementation (ADR-0022 §D11).
    ///
    /// The predicate is injected rather than reached from here so this stays a pure
    /// function of its arguments; its parameters are `(name, parent)`, in that order,
    /// which is `nameIsAvailable(_:in:)`'s own.
    ///
    /// The two failures are ordered rather than merged, deliberately: a name carrying a
    /// `/` is not meaningfully "taken", and asking the file system about it would be
    /// asking about a path the user never typed.
    static func state(
        name: FolderName, parent: FolderPath, available: (FolderName, FolderPath) -> Bool
    ) -> State {
        let violations = FolderFileOperations.validate(name.value)
        guard violations.isEmpty else { return .invalid(violations) }
        guard available(name, parent) else { return .taken }
        return .ok
    }
}

/// The create sheet's parent-folder picker options.
enum WorkspaceFolderSheets {
    /// The parent-folder picker's options: the vault's folders themselves, root first
    /// (`""`) and deduplicated.
    ///
    /// Fed `CanvasStore.allFolders()` (ADR-0025 §D1), which is what closes ADR-0022
    /// §D11's objection rather than working around it. That decision derived the options
    /// from the *board* list, recovering each board path's ancestors, because a board was
    /// then the only evidence a folder existed at all - and the recovery could only ever
    /// see a folder something *below* it held a board in. A folder holding only
    /// subfolders, or only a board of its own, was silently unpickable, so a user could
    /// not create a sibling of what they were looking at. `allFolders()` walks the
    /// directories, so every folder is an entry in its own right and nothing is inferred.
    ///
    /// The incoming order is preserved rather than re-sorted: `allFolders()` sorts with
    /// `localizedStandardCompare`, which is the order both sidebars are read in ("9 Note"
    /// before "10 Note"), and a plain `sorted()` here would undo exactly that.
    static func parentOptions(from folders: [FolderPath]) -> [FolderPath] {
        var seen: Set<FolderPath> = [""]
        var options: [FolderPath] = []
        for folder in folders where seen.insert(folder).inserted {
            options.append(folder)
        }
        return [""] + options
    }
}

/// Which of the two things a sheet is about (ADR-0025 §D7): a board file or a folder.
///
/// One sheet carrying a case, never two sheets: the parent picker, the name rules, the
/// violation wording and the accessibility identifiers are one question asked about a
/// file or about a directory, and a second sheet would be a second creation dialect
/// (ADR-0022 §D11). The rename sheet asks the same question of the same two kinds, so it
/// reads this enum too rather than growing a parallel one.
enum WorkspaceItemKind: String, Identifiable, Sendable {
    /// A `.canvas` file, written by `CanvasStore.createBoard(named:in:)` - anywhere, under
    /// any name, beside as many others as the folder already holds (R-02).
    case board
    /// A directory, made by `CanvasStore.createFolder(named:in:)`, with **no board
    /// written inside it**, which is the whole of R-01.
    case folder

    var id: String { rawValue }

    var creationTitle: String {
        switch self {
        case .board: "Nuova board"
        case .folder: "Nuova cartella"
        }
    }

    /// The line under the title: what the thing being made is, in the words the sidebar
    /// now uses for its two kinds of row.
    var creationExplanation: String {
        switch self {
        case .board:
            "Una board è un file .canvas. Può stare in qualsiasi cartella, con qualsiasi nome."
        case .folder:
            "Una cartella contiene board e altre cartelle. Nessuna board viene creata dentro."
        }
    }

    var renameTitle: String {
        switch self {
        case .board: "Rinomina board"
        case .folder: "Rinomina cartella"
        }
    }

    /// What follows the thing being renamed, which is the half users get wrong: a board
    /// carries its own name and a folder no longer renames one (ADR-0025 §D6, R-09).
    var renameExplanation: String {
        switch self {
        case .board:
            "Il file .canvas viene rinominato; i task e le card che lo nominavano seguono."
        case .folder:
            "La cartella viene rinominata e le card che puntavano dentro seguono. "
                + "Le board che contiene mantengono il loro nome."
        }
    }
}

// MARK: - The sheets

/// Creating a board or a folder: a name, and the folder it goes in (R-01, R-02, R-03,
/// R-04).
///
/// `RenameNoteSheet`'s five elements, in its order - title, explanation, field, inline
/// violations, confirm disabled until they are gone - plus the parent picker, which is
/// the one thing File → «Nuova board» does not ask and this door does (ADR-0022 §D11,
/// §A5).
///
/// `kind` is the only difference between the two doors: it says what the sheet is called
/// and which collision the caller's predicate asks about
/// (`CanvasStore.boardNameIsAvailable` for a board, `FolderFileOperations.nameIsAvailable`
/// for a folder). The three identifiers below - `workspace-new-sheet`,
/// `workspace-new-name`, `workspace-new-parent` - are the same for both, because it is the
/// same sheet.
struct NewWorkspaceSheet: View {
    @Environment(\.theme) private var theme

    /// What is being created (ADR-0025 §D7).
    let kind: WorkspaceItemKind
    /// Every folder that can hold a new one, root first: `parentOptions(from:)` over the
    /// folder list the browser already has.
    let parents: [FolderPath]
    let isNameAvailable: (FolderName, FolderPath) -> Bool
    /// The chosen name and the chosen parent, in that order.
    let onConfirm: (FolderName, FolderPath) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var parent: FolderPath

    init(
        kind: WorkspaceItemKind,
        parents: [FolderPath],
        initialParent: FolderPath,
        isNameAvailable: @escaping (FolderName, FolderPath) -> Bool,
        onConfirm: @escaping (FolderName, FolderPath) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.kind = kind
        self.parents = parents
        self.isNameAvailable = isNameAvailable
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        // A selection that matches no tag leaves the picker showing an empty row. Every
        // real folder is an option now that they come from `allFolders()` rather than
        // from board paths, so the miss this guards is a suggested parent the walk no
        // longer sees - one renamed or trashed since the last scan. The root always is.
        _parent = State(initialValue: parents.contains(initialParent) ? initialParent : "")
    }

    private var state: WorkspaceNameField.State {
        WorkspaceNameField.state(name: FolderName(name), parent: parent, available: isNameAvailable)
    }

    private var canCreate: Bool { state == .ok }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text(kind.creationTitle).themedText(.title)
            Text(kind.creationExplanation)
                .themedText(.caption, color: .textSecondary)

            TextField("Nome", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if canCreate { onConfirm(FolderName(name), parent) } }
                .accessibilityIdentifier("workspace-new-name")

            Picker("Dentro", selection: $parent) {
                ForEach(parents, id: \.self) { folder in
                    Text(folder.isEmpty ? "(radice)" : folder.value).tag(folder)
                }
            }
            .accessibilityIdentifier("workspace-new-parent")

            // Nothing is wrong with a field nobody has typed in yet: the violations show
            // up as soon as there is something to violate them, rather than greeting the
            // sheet with «Il titolo è vuoto».
            if !name.isEmpty {
                WorkspaceNameProblems(state: state, parent: parent)
            }

            HStack {
                Spacer()
                Button("Annulla", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Crea") { onConfirm(FolderName(name), parent) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
        }
        .padding(theme.spacing(.l))
        .frame(width: 460)
        .background(theme.color(.surfaceCard))
        // `children: .contain` alongside the identifier, the pairing the browser's header
        // uses and `UITests/WorkspaceIntegrationUITests.swift` proves keeps a child's own
        // identifier reachable (`workspace-filter` inside `workspace-browser-header`).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workspace-new-sheet")
    }
}

/// Renaming a board or a folder: the thing's name, seeded from the selection (R-05,
/// ADR-0025 §D6).
///
/// The parent is not editable here - moving a board or a folder under a different parent
/// is out of this feature's scope (SPEC, «Out of scope»), so the sheet asks the one
/// question a rename is.
struct RenameWorkspaceSheet: View {
    @Environment(\.theme) private var theme

    /// Which of the two is being renamed - what the title and the explanation say, and
    /// the only thing this sheet does with it. Which collision to ask about is the
    /// caller's `isNameAvailable`, as it already was.
    let kind: WorkspaceItemKind
    /// The vault-relative path of what is being renamed, a board's **without** its
    /// `.canvas` extension: a rename asks for a name, and the extension belongs to
    /// `BoardFileOperations`, which is the one place that spells it (ADR-0025 §D6).
    let path: String
    let isNameAvailable: (FolderName, FolderPath) -> Bool
    let onConfirm: (FolderName) -> Void
    let onCancel: () -> Void

    @State private var name: String

    init(
        kind: WorkspaceItemKind,
        path: String,
        isNameAvailable: @escaping (FolderName, FolderPath) -> Bool,
        onConfirm: @escaping (FolderName) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.kind = kind
        self.path = path
        self.isNameAvailable = isNameAvailable
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _name = State(initialValue: (path as NSString).lastPathComponent)
    }

    private var currentName: String { (path as NSString).lastPathComponent }
    private var parent: FolderPath { FolderPath((path as NSString).deletingLastPathComponent) }

    private var state: WorkspaceNameField.State {
        WorkspaceNameField.state(name: FolderName(name), parent: parent, available: isNameAvailable)
    }

    /// Unchanged is not an error, it is a no-op: the button is off rather than red, the
    /// same way `RenameNoteSheet` treats a title nobody edited.
    private var canRename: Bool { state == .ok && name != currentName }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text(kind.renameTitle).themedText(.title)
            Text(kind.renameExplanation)
                .themedText(.caption, color: .textSecondary)

            TextField("Nome", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if canRename { onConfirm(FolderName(name)) } }
                .accessibilityIdentifier("workspace-rename-name")

            if name != currentName {
                WorkspaceNameProblems(state: state, parent: parent)
            }

            HStack {
                Spacer()
                Button("Annulla", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Rinomina") { onConfirm(FolderName(name)) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canRename)
            }
        }
        .padding(theme.spacing(.l))
        .frame(width: 460)
        .background(theme.color(.surfaceCard))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workspace-rename-sheet")
    }
}

/// What is wrong with the name being typed, in the wording the rest of the app uses.
///
/// `ConformanceText.lines` renders a `NoteName.Violation` exactly as `RenameNoteSheet`
/// renders it for a note title - one rename dialect, not two (ADR-0022 §D11). The
/// collision has no `ConformanceText` case because nothing else in the app blocks on one
/// inline, so it gets its sentence here.
private struct WorkspaceNameProblems: View {
    let state: WorkspaceNameField.State
    let parent: FolderPath

    var body: some View {
        ForEach(lines, id: \.self) { line in
            Text(line).themedText(.caption, color: .taskOverdue)
        }
    }

    private var lines: [String] {
        switch state {
        case .invalid(let violations):
            ConformanceText.lines(NoteViolations(
                name: violations, frontmatter: [], tags: [],
                relatedMissingInSection: [], relatedMissingInFrontmatter: []
            ))
        case .taken:
            ["Esiste già un elemento con questo nome in \(parent.isEmpty ? "«(radice)»" : "«\(parent.value)»")"]
        case .ok:
            []
        }
    }
}
