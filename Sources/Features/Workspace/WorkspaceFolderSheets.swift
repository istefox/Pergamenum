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
    static func state(name: String, parent: String, available: (String, String) -> Bool) -> State {
        let violations = FolderFileOperations.validate(name)
        guard violations.isEmpty else { return .invalid(violations) }
        guard available(name, parent) else { return .taken }
        return .ok
    }
}

/// The create sheet's parent-folder picker options.
enum WorkspaceFolderSheets {
    /// The parent-folder picker's options, derived from the browser's own board list
    /// (`CanvasStore.allBoards()`) rather than from `vault.folders` - which is
    /// note-derived and would omit a folder holding only boards (ADR-0022 §D11).
    /// Root first (`""`), deduplicated, every ancestor folder included.
    ///
    /// The ancestors matter as much as the folders themselves: `01 Progetti/a/a.canvas`
    /// is the only evidence that `01 Progetti` exists at all when nothing else lives in
    /// it, and a user who cannot pick it cannot create a sibling of `a`.
    static func parentOptions(from boards: [String]) -> [String] {
        var seen: Set<String> = [""]
        var folders: [String] = []
        for board in boards {
            var folder = (board as NSString).deletingLastPathComponent
            while !folder.isEmpty {
                if seen.insert(folder).inserted { folders.append(folder) }
                folder = (folder as NSString).deletingLastPathComponent
            }
        }
        return [""] + folders.sorted()
    }
}

// MARK: - The sheets

/// Creating a workspace: a name, and the folder it goes in (R-02, R-03, R-04).
///
/// `RenameNoteSheet`'s five elements, in its order - title, explanation, field, inline
/// violations, confirm disabled until they are gone - plus the parent picker, which is
/// the one thing File → «Nuova board» does not ask and this door does (ADR-0022 §D11,
/// §A5).
struct NewWorkspaceSheet: View {
    @Environment(\.theme) private var theme

    /// Every folder that can hold a new one, root first: `parentOptions(from:)` over the
    /// board list the browser already has.
    let parents: [String]
    let isNameAvailable: (String, String) -> Bool
    /// The chosen name and the chosen parent, in that order.
    let onConfirm: (String, String) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var parent: String

    init(
        parents: [String],
        initialParent: String,
        isNameAvailable: @escaping (String, String) -> Bool,
        onConfirm: @escaping (String, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.parents = parents
        self.isNameAvailable = isNameAvailable
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        // A selection that matches no tag leaves the picker showing an empty row, and the
        // suggested parent is a folder that may hold no board and therefore not be in the
        // list. The root always is.
        _parent = State(initialValue: parents.contains(initialParent) ? initialParent : "")
    }

    private var state: WorkspaceNameField.State {
        WorkspaceNameField.state(name: name, parent: parent, available: isNameAvailable)
    }

    private var canCreate: Bool { state == .ok }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text("Nuova workspace").themedText(.title)
            Text("Una workspace è una cartella del vault, con la sua board dentro.")
                .themedText(.caption, color: .textSecondary)

            TextField("Nome", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if canCreate { onConfirm(name, parent) } }
                .accessibilityIdentifier("workspace-new-name")

            Picker("Dentro", selection: $parent) {
                ForEach(parents, id: \.self) { folder in
                    Text(folder.isEmpty ? "(radice)" : folder).tag(folder)
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
                Button("Crea") { onConfirm(name, parent) }
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

/// Renaming a workspace: the folder's name, seeded from the selection (R-05).
///
/// The parent is not editable here - moving a workspace under a different parent is out
/// of this feature's scope (SPEC, «Out of scope»), so the sheet asks the one question a
/// rename is.
struct RenameWorkspaceSheet: View {
    @Environment(\.theme) private var theme

    /// The vault-relative path of the folder being renamed.
    let folder: String
    let isNameAvailable: (String, String) -> Bool
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @State private var name: String

    init(
        folder: String,
        isNameAvailable: @escaping (String, String) -> Bool,
        onConfirm: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.folder = folder
        self.isNameAvailable = isNameAvailable
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _name = State(initialValue: (folder as NSString).lastPathComponent)
    }

    private var currentName: String { (folder as NSString).lastPathComponent }
    private var parent: String { (folder as NSString).deletingLastPathComponent }

    private var state: WorkspaceNameField.State {
        WorkspaceNameField.state(name: name, parent: parent, available: isNameAvailable)
    }

    /// Unchanged is not an error, it is a no-op: the button is off rather than red, the
    /// same way `RenameNoteSheet` treats a title nobody edited.
    private var canRename: Bool { state == .ok && name != currentName }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text("Rinomina workspace").themedText(.title)
            Text("La cartella e la sua board vengono rinominate insieme; i task e le card che le nominavano seguono.")
                .themedText(.caption, color: .textSecondary)

            TextField("Nome", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if canRename { onConfirm(name) } }
                .accessibilityIdentifier("workspace-rename-name")

            if name != currentName {
                WorkspaceNameProblems(state: state, parent: parent)
            }

            HStack {
                Spacer()
                Button("Annulla", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Rinomina") { onConfirm(name) }
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
    @Environment(\.theme) private var theme
    let state: WorkspaceNameField.State
    let parent: String

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
            ["Esiste già un elemento con questo nome in \(parent.isEmpty ? "«(radice)»" : "«\(parent)»")"]
        case .ok:
            []
        }
    }
}
