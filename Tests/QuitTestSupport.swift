import Foundation
import Testing
@testable import Pergamenum

// Shared by `TabSaveTests`, `QuitSaveTests`, `QuitCoordinatorTests`, `CloseTabRequestTests`
// (ADR-0073, plan Tasks 2, 3 and 5) and the `QuitConflict*`/`QuitReview*` suites of PG-336
// (ADR-0089): the `NoteTabTests` scaffolding -
// a real vault, a real `VaultController` - with three notes, two of them in one folder so the
// folder can be made read-only.

func quitNote(_ body: String) -> String {
    """
    ---
    date: 2026-09-29
    tags:
      - type-note
    ---

    \(body)
    """
}

@MainActor
func quitController(_ vault: borrowing TemporaryVault) async throws -> VaultController {
    try vault.write(quitNote("Nexion."), to: "Nexion.md")
    try vault.write(quitNote("Sospensione."), to: "Progetti/Sospensione.md")
    try vault.write(quitNote("Pressa."), to: "Progetti/Pressa.md")
    // Outside `Progetti`, and written before the vault opens: a file created afterwards
    // reaches the watcher late and can raise the banner on a tab already dirty.
    try vault.write(quitNote("Dopo."), to: "Dopo.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    return controller
}

/// Opens `path` in a tab of its own in column `column`, adding the second column when needed,
/// appends `addition` to its text and returns the tab's id. The column is left focused.
@MainActor
func openDirty(
    _ path: String, adding addition: String, inColumn column: Int, of controller: VaultController
) throws -> NoteTab.ID {
    if column == 1, controller.columns.count == 1 { controller.addColumn() }
    controller.focusColumn(column)
    controller.openNoteInNewTab(at: path)
    let id = try #require(controller.focusedTab?.id)
    #expect(controller.openNote?.relativePath == path)
    controller.updateOpenNoteText((controller.openNote?.text ?? "") + addition)
    return id
}

/// The file's text, or nil. Takes the root rather than the vault: `TemporaryVault` is
/// noncopyable and `#expect` wants a copy.
func quitOnDisk(_ root: URL, _ path: String) -> String? {
    try? String(contentsOf: root.appending(path: path), encoding: .utf8)
}

/// Makes a folder of the vault read-only for the duration of `body`, so a write into it fails
/// (the precedent is `Tests/RecordingsControllerTests.swift`); restored whatever happens.
@MainActor
func withReadOnlyFolder<T>(
    _ root: URL, _ folder: String, _ body: () async throws -> T
) async throws -> T {
    let path = root.appending(path: folder, directoryHint: .isDirectory).path(percentEncoded: false)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path) }
    return try await body()
}

// MARK: A conflicted board and a conflicted diary (PG-336, ADR-0089)

/// A board named «Bacheca» at the vault root, attached to `controller` (which makes it
/// `controller.openBoard`, a weak reference), opened, edited, and then refused into
/// `.conflicted` because another store saved a diverged document first
/// (`WorkspaceLifecycleTests.swift`'s `conflictedBoard` shape). The caller keeps the returned
/// controller alive: `openBoard` is weak.
@MainActor
func quitConflictedBoard(
    _ vault: borrowing TemporaryVault, in controller: VaultController
) throws -> (board: WorkspaceController, path: String) {
    let store = CanvasStore(root: vault.root)
    let path = try store.createBoard(named: "Bacheca", in: "")
    let board = WorkspaceController()
    board.attach(to: store, vault: controller)
    board.open(board: path)
    _ = board.addStickyNote("nota", at: .zero)

    let externalStore = CanvasStore(root: vault.root)
    var diverged = try externalStore.load(board: path)
    diverged.nodes.append(CanvasNode(
        id: "external", kind: .text("altro"), x: 400, y: 400, width: 100, height: 60
    ))
    try externalStore.save(diverged, board: path)

    board.flushPendingSave()
    guard case .conflicted = board.saveState else {
        board.detach()
        throw QuitSupportError.notConflicted("board: \(board.saveState)")
    }
    return (board, path)
}

/// The diary day `testDay`, typed into, its first write held at `.willWrite` while another
/// writer creates `Diario/20260811.md`, then released: the write is refused and the diary is
/// `.conflicted` (`DiaryConflictTests.swift`'s `makeConflictedDiary` with no seed file). Takes
/// the root rather than the vault, so it stays callable after `quitController` has borrowed it.
@MainActor
func quitConflictedDiary(in controller: VaultController, root: URL) async throws -> DiaryController {
    let diary = DiaryController(vault: controller)
    diary.show(testDay)

    let gate = Gate()
    var held = false
    diary.testOnlyWriteHook = { phase in
        if case .willWrite = phase, !held {
            held = true
            await gate.wait()
        }
    }

    diary.prose += "Frase mia.\n"
    diary.flush()
    try await waitUntil { held }
    let url = root.appending(path: "Diario/20260811.md", directoryHint: .notDirectory)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try Data("---\ndate: 2026-08-11\ntags:\n  - type-note\n---\n\nScritto da un altro processo.\n".utf8)
        .write(to: url)
    gate.open()
    try await waitUntil {
        if case .conflicted = diary.saveState { return true }
        return false
    }
    return diary
}

enum QuitSupportError: Error {
    case notConflicted(String)
}

/// A few turns of the main actor, for the "nothing else happens" assertions.
@MainActor
func drain() async {
    for _ in 0..<20 { await Task.yield() }
    try? await Task.sleep(for: .milliseconds(50))
}

/// The problem lines a cancelled quit records for a board or diary day left conflicted
/// (ADR-0089 §D5), for `quitConflictedBoard` and `quitConflictedDiary`.
let boardProblem = "Uscita annullata: la board «Bacheca» ha un conflitto di salvataggio non risolto"
let diaryProblem =
    "Uscita annullata: il diario del giorno 11/08/2026 ha un conflitto di salvataggio non risolto"

/// Everything the coordinator hands to AppKit, recorded; every reveal goes into one ordered log.
/// Shared by `QuitConflictTests` and `QuitConflictLastCheckTests`.
@MainActor
final class ConflictProbe {
    enum Shown: Equatable {
        case note(NoteTab.ID?), board, diary, scheda(String?)
    }

    var replies: [Bool] = []
    var asked: [QuitReview] = []
    var shown: [Shown] = []
    var slept: [Duration] = []
    /// `slept` as it was when `ask` ran.
    var sleptWhenAsked: [Duration]?
    /// Durations whose sleep returns at once; every other one waits on its gate.
    var instant: Set<Duration> = []
    private var gates: [Duration: Gate] = [:]

    func gate(for duration: Duration) -> Gate {
        if let gate = gates[duration] { return gate }
        let gate = Gate()
        gates[duration] = gate
        return gate
    }

    func openAllGates() {
        gates.values.forEach { $0.open() }
    }

    func coordinator(
        _ controller: VaultController,
        diary: DiaryController?,
        answer: @escaping @MainActor (QuitReview) -> QuitReview.Answer
    ) -> QuitCoordinator {
        QuitCoordinator(
            vault: { controller },
            diary: { diary },
            contenitore: { nil },
            commitEditing: {},
            ask: { [unowned self] review in
                asked.append(review)
                sleptWhenAsked = slept
                return answer(review)
            },
            reply: { [unowned self] in replies.append($0) },
            reveal: { [unowned self] in shown.append(.note($0)) },
            revealContenitore: { [unowned self] in shown.append(.scheda($0)) },
            revealBoard: { [unowned self] in shown.append(.board) },
            revealDiary: { [unowned self] in shown.append(.diary) },
            sleep: { [unowned self] duration in
                slept.append(duration)
                if instant.contains(duration) { return }
                await gate(for: duration).wait()
            }
        )
    }
}

// MARK: Pure quit-review fixtures (PG-336, ADR-0089)

// Shared by `QuitReviewConflictTests` and `QuitReviewCoverageTests`: columns built by hand and
// the items by memberwise init, no vault.

func tab(
    _ path: String, title: String? = nil, text: String = "modificato", saved: String = "originale"
) -> NoteTab {
    NoteTab(note: VaultController.OpenNote(
        relativePath: path,
        title: title ?? (path as NSString).deletingPathExtension,
        text: text,
        savedText: saved
    ))
}

func boardItem(
    path: String = "Bacheca.canvas",
    nodes: [CanvasNode] = [CanvasNode(id: "a", kind: .text("uno"), x: 0, y: 0, width: 100, height: 60)]
) -> QuitReview.Board {
    QuitReview.Board(
        path: path, document: CanvasDocument(nodes: nodes, edges: [], unknown: [:])
    )
}

func diaryItem(
    day: CalendarDate = testDay, prose: String = "Frase mia.", entries: [DiaryEntry] = []
) -> QuitReview.DiaryDay {
    QuitReview.DiaryDay(day: day, prose: prose, entries: entries)
}
