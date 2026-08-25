# Plan — Universal command surface parity: toolbar and context menu for every command

- **SPEC:** `/Users/stefer/Developer/Pergamenum/SPEC.md` (R-01 … R-14).
- **ADR:** `ADR-0023: A command is named once and rendered twice`, currently at
  `/Users/stefer/Developer/Pergamenum/docs/architecture/ADR-0023-universal-command-surface-parity.md`,
  **to be moved by the operator to
  `/Users/stefer/Developer/Pergamenum/docs/adr/0023-universal-command-surface-parity.md`**
  before Task 1 (this project's ADRs all live under `docs/adr/`; the architect agent's write
  scope forbids that directory). Every reference below is to **ADR-0023** by name, never by
  path, so the move breaks nothing.
- **Branch:** `feature/adr-0023-universal-command-surface-parity`
- **Base:** `main`. Every line number quoted below was read at `b477209`.
- **Style:** TDD. Every task writes its failing test first, then the code that makes it pass.
  Swift Testing (`#expect`, `#require`), never XCTest, for everything new in `Tests/`.
- **Swift is compiled, so "red" has a precondition.** A task's test step must add the new type
  and signature declarations *together with* the failing tests — placeholder bodies returning
  `nil` / `[]` / the unchanged input — so the target **builds** and the tests fail on their
  assertions. A batch that leaves `Pergamenum` unable to compile produces no red tests at all,
  only a build error. Never `fatalError()` and never a force-unwrap as a placeholder
  (`~/.claude/rules/swift.md`).
- **Harness:** this plan creates **no new harness script**, the same decision
  `2026-08-25-workspace-ui-creazione-board-toolbar-e-r.md` and
  `2026-08-24-workspace-tasks-notes-integration.md` both made. Verification is the two commands
  this project already trusts: `.claude/test-cmd` after every task, and `scripts/uitests.sh`
  once, at Task 9, before the merge to `main` (`CLAUDE.md` working agreements — the UI suite is
  outside `test-cmd` on purpose and its state is unknown between deliberate runs, `PG-033`).
  **Every new or extended test file's header comment must name `ADR-0023` and this plan's
  basename `2026-08-25-universal-command-surface-parity`** — that citation is the only link this
  repository keeps between a test and the decision that asked for it, and it is the anchor the
  coverage report reads.
- **After any task that adds a file:** `tuist generate --no-open`. The generated project lists
  files and does not regenerate itself; a build that fails naming the compiler rather than the
  missing file is the documented failure mode.
- **`Sources/Core/**` and `Sources/Connector/**` must not import SwiftUI or AppKit** (ADR-0001
  §D1, enforced by the `perg` and `pergamenum-mcp` builds — R-14 asserts it explicitly). This
  plan adds **no file** to either. The single shared file it edits,
  `Sources/Vault/CanvasStore.swift`, is already in `sharedSources` (`Project.swift:80`) and the
  function added to it is Foundation-only.
- **`Project.swift` needs no edit at all.** The app target is `Sources/**` minus
  `Sources/CLI/**` and `Sources/MCPServer/**` (`Project.swift:139-141`), so every new file below
  is in the app automatically, and no new file goes into `sharedSources`.
- **No new dependency, no `Tuist/Package.swift` edit, no `tuist install`.**
- **Known false positives, ignore them:** the pre-commit `weakening-scan.sh` reports every Swift
  Testing test as `zero-assertion-test` (its body scanner treats a line starting with `#` as a
  comment and `#expect(...)` starts with one); the secret scanner's `assigned-secret` rule fires
  on design-token lines. Both documented in `CLAUDE.md`. Do not restructure code to appease
  either; do still read the diff.

## Three things the SPEC says about this repository that are false

Read at `b477209`, before this plan was written. Do not rediscover them, and do not follow the
SPEC's wording where it contradicts them. **None of them changes what gets built** — they change
what the code may cite as its reason.

| SPEC says | Truth | Consequence for this plan |
|---|---|---|
| Architecture, cluster 4: the new buttons are hidden when no card is selected, *"matching how Anteprima rapida already behaves in that toolbar"* | Anteprima is `.disabled(workspace.selectedFileURLs.isEmpty)` — **shown and greyed**, not hidden (`WorkspaceView.swift:259-264`). Its condition is *file* cards, not any card: a text card selected leaves it greyed. | Implement R-07 exactly as R-07 words it (hidden, not disabled) — §D8 gets it for free, since the bar exists only when there is a selection. **Do not cite Anteprima as the precedent** in a comment. The precedent that does exist is `BoardPenControls`, which appears and disappears with the Disegno tool in the same slot (`BoardChrome.swift:126-173`, `WorkspaceView.swift:334-345`). |
| Edge cases: *"Root-folder row (cluster 1): Rinomina/Elimina are absent from its context menu entirely"* | **There is no vault-root folder row.** `NoteTree.build(fromPaths:)` creates a folder node only for a real path component (`NoteTree.swift:56-66`); the root board is a top-level `.note` leaf. No folder node can carry an empty id. | R-02 is satisfied by construction. Task 4 still gates the entries on `WorkspaceBrowserToolbar.canMutate(folder:)` (one rule, two surfaces, ADR-0023 §D1) and **asserts the construction** rather than assuming it. |
| Architecture, cluster 1: the context menu is a second entry point, ADR-0022 §D8 revisited | Correct, but the reason §D8 gave does not transfer, and the reason that *does* bite is a different one. A `.contextMenu`'s items are `NSMenuItem`s outside the view hierarchy, so no container identifier can reach them. What **does** propagate is a modifier on the folder row's `DisclosureGroup`, which reaches every disclosed descendant (`WorkspaceBrowser.swift:359-367`). | Task 4 attaches the menu to the folder row's **label `HStack`** — the view that already carries `.contentShape`, `.onTapGesture` and the row identifier — never to the `DisclosureGroup`. Attached there, right-clicking a nested board row would offer to delete its parent folder. |

## Contract changes, and the call sites already grepped

| Change | Call sites (grepped at `b477209`) | Action |
|---|---|---|
| `WorkspaceTreeRow` gains `onRename`/`onDelete` closures | `WorkspaceBrowser.swift:191`, `:214`, `:335` — **all three**, all inside that one file (`grep -rn "WorkspaceTreeRow(" Sources Tests UITests`). It is a `private struct`; nothing outside can construct it. | Update all three in Task 4's own batch. |
| `MiniCalendar` gains `onNewEvent`/`onNewReminder` closures | `DayMonthSection.swift:31` — **the only one** (`grep -rn "MiniCalendar(" Sources Tests UITests`). | Update it in Task 7's own batch. Required parameters, **not** defaulted no-ops: a defaulted closure is a menu entry that silently does nothing at the next call site. |
| `CommandActions` gains `run(_:on:)` and `canRun(_:on:)` | Additive overloads; `run(_:)`/`canRun(_:)` unchanged. Existing callers: `MenuCommands.swift`, `PergamenumApp.swift`, `Tests/CommandActionTests.swift`. | Nothing to update. If a task finds itself changing `run(_:)`'s signature, stop — the design is wrong. |
| `TaskDraft` gains `static func subtask(of:)`; `CommandActions.addSubtaskToSelectedTask` rewritten to call it | `addSubtaskToSelectedTask` is `private` with one caller (`CommandActions.swift:236`). `TaskDraft` is in `Sources/Vault/VaultSession+Tasks.swift:41`, a `sharedSources` file — Foundation-only addition, no connector impact. | Behaviour must be **byte-identical**; Task 6's test asserts the two entry points produce the same value. |
| `CanvasID` gains `generate(avoiding:using:)`; `generate()` **unchanged** | `generate()`: `DrawingSVG.swift:37,104`, `WorkspaceController+Drawing.swift:71`, `WorkspaceController.swift:371,385,394,405,414`, `Tests/CanvasTests.swift:279,285`. | Purely additive. **Do not change `generate()`** — `Tests/CanvasTests.swift:279-285` pins its shape, and ADR-0023 §D11 depends on the 16-hex form for Obsidian parity. |
| `CompletingTextView` gains `onEmbedMenu` and overrides `menu(for:)` | No existing override; `grep -n "menu(for" Sources/Features/Editor/*.swift` returns nothing. | Additive, but it changes **observable right-click behaviour in the whole editor**. `super.menu(for: event)` on every non-embed point is the guard; it is in Task 8's test list and in Task 9's manual pass. |
| `BoardContentLayer`'s card context-menu entry list is rebuilt from `CardCommand` and gains «Duplica» | `grep -rn "Ritaglia\|\"Colore\"\|Ridimensiona\|Adatta al ritaglio\|Rimuovi ritaglio" UITests Tests` returns **nothing** — no test anywhere asserts a card menu title. | The item titles must still be preserved verbatim (they are a user-facing contract even without a test on them). Task 3 changes *where the list comes from*, not what is in it, plus one new entry. |
| New AX identifiers only; **no existing identifier changes** | `workspace-filter`, `workspace-board-*` asserted at `UITests/WorkspaceIntegrationUITests.swift:150,155`; `workspace-tray-toggle`, `board-tray`, `board-assigned-tasks*`, `board-referenced-note*`, `month-cell-*`, `month-open-day-*`, `week-column-*`, `week-open-day-*`, `mini-calendar`, `due-dot-*`, `task-row`, `note-tree`, `note-flat-list`, `folder-*`, `starred-note`. | Preserve every one exactly. New identifiers go **beside** them, never renaming one. |

**Full-suite rule.** Tasks 3, 5, 6 and 8 change behaviour other modules observe (the card menu's
item list, `CommandActions`' dispatch, the sub-task draft, right-click in the editor). Run the
whole `PergamenumTests` bundle after each of them — `.claude/test-cmd` already does exactly that
— never just the new file's tests.

---

### Task 1 — `CardCommand`: one catalogue for everything a card offers (R-06, R-13)

**RED.** New `Tests/CardCommandTests.swift` (header names ADR-0023 and this plan's basename),
plus the declaration of the new type so the target builds:

- `CardCommand.available(for:isCroppable:hasCrop:)` on a `.file` PNG node with
  `isCroppable: true, hasCrop: false` returns, **in this order**:
  `[.open, .copyLink, .color, .resize, .crop, .duplicate, .delete]`.
- With `hasCrop: true` it also carries `.fitToCrop` and `.removeCrop`, each in the position the
  existing menu draws it (`BoardContentLayer.swift:66-87`: `fitToCrop` inside the resize group,
  `removeCrop` after `crop`).
- With `isCroppable: false` (a `.text` card, a `.link` card, a `.md` file card, or **any** node
  at a zoom where `BoardGeometry.drawsPlaceholder(at:)` is true) none of `.crop`, `.removeCrop`,
  `.fitToCrop` appear — and `.open`, `.copyLink`, `.color`, `.resize`, `.duplicate`, `.delete`
  still do. (R-06)
- Every case has a non-empty Italian `title`, and the titles are **exactly** the strings the
  card menu draws today: `Apri`, `Copia link Pergamenum`, `Colore`, `Ridimensiona`,
  `Adatta al ritaglio`, `Ritaglia`, `Rimuovi ritaglio`, `Elimina`, plus the new `Duplica`.
- Every case has a `symbol`, asserted against a table written in the test — this is R-13 made an
  assertion rather than a review item. Reuse what the app already names for the same command:
  `trash` for `.delete` (`WorkspaceBrowserToolbar.swift:35`), `eye` is *not* one of these,
  `doc.on.doc` for `.duplicate` (no prior use — a new command may choose one), and each
  remaining choice is recorded in a comment naming where it came from. (R-13)

**GREEN.** New `Sources/Features/Workspace/CardCommand.swift`: `enum CardCommand: String,
CaseIterable` with `title`, `symbol`, and `static func available(for node: CanvasNode,
isCroppable: Bool, hasCrop: Bool) -> [CardCommand]`. **`import Foundation` and
`import CoreGraphics` only** — no SwiftUI, so the file stays a pure catalogue a test can read.
Not in `sharedSources` (ADR-0023 §A6: the connectors have no board-editing surface).

The two `private static let` tables `BoardContentLayer` holds — `colorNames`
(`:230`) and `sizePresets` (`:233-238`) — **stay where they are**. They are the submenus'
contents, not the command list; moving them is churn this task does not need.

- Budget: `Sources/Features/Workspace/CardCommand.swift`, `Tests/CardCommandTests.swift`
  (~180 lines)

### Task 2 — Duplicating a card: a new node, a new id, and no file written (R-10, R-11)

**RED.** New `Tests/CanvasDuplicateTests.swift` (header names ADR-0023 and this plan's basename):

- `CanvasID.generate(avoiding:using:)` returns the stub generator's value when it is free;
  returns the **third** value when the stub yields two ids already in `avoiding`; and still
  returns an id outside `avoiding` when the stub **always** collides — the deterministic escape
  of ADR-0023 §D11, which must terminate rather than loop. `CanvasID.generate()` with no
  arguments is untouched and `Tests/CanvasTests.swift:279-285` still passes.
- `WorkspaceController.duplicate(nodeIDs:)` on a board with one `.file` node: `document.nodes`
  gains exactly one entry; the copy's `id` differs from every id already in the document
  (**nodes and edges both**); `kind`, `width`, `height`, `color` and `unknown` are equal to the
  original's; `x` and `y` are the original's plus `WorkspaceController.gridStep`. (R-10)
- `document.edges` is unchanged by a duplicate of a node that has an edge on it (§D11).
- A node carrying ADR-0020's `pergamenum-crop` in `unknown` duplicates **with** the crop, since
  `unknown` is copied wholesale — assert the key survives by value. (R-11's rendering premise)
- **R-10's real content:** the folder on disk holds exactly the same file names before and
  after, and the `.canvas` is the only file whose bytes changed. Snapshot
  `FileManager.contentsOfDirectory` before and after and compare the sorted lists.
- **R-11:** a `.file` node whose path does not exist on disk duplicates just the same — same
  `kind`, no throw, no file created, node count +1.
- Round-trip: `CanvasStore.save(document, folder:)` then `load(folder:)` returns two nodes with
  **distinct** ids and the **same** `file` path.
- `workspace.selection` after the call is exactly the set of new ids, so a second Duplica
  cascades rather than re-duplicating the original.

**GREEN.**
- `Sources/Vault/CanvasStore.swift` (already in `sharedSources`, `Project.swift:80`, Foundation
  only): `static func generate(avoiding taken: Set<String>, using make: () -> String = { generate() }) -> String`.
  Bounded random retry (16 attempts), then a deterministic suffix walk over
  `0...(taken.count)` candidates of the form `String(base.prefix(12)) + String(format: "%04x", counter)`
  — with more candidates than `taken` holds, one is free, so it terminates and cannot return a
  taken id. Comment must say that; a reader should not have to derive it.
- New `Sources/Features/Workspace/WorkspaceController+Duplicate.swift`:
  `@discardableResult func duplicate(nodeIDs: Set<String>) -> [String]`. One `mutate` for the
  whole call (one undo step regardless of how many cards), **`creatingOnDisk: nil`** — nothing
  is created on disk, and claiming otherwise would make `BoardHistory` block the undo
  (`WorkspaceController.swift:231-233`). Copies appended in `document.nodes` order.
  `refreshContents()` after, as `addNode` does.

- Budget: `Sources/Vault/CanvasStore.swift`,
  `Sources/Features/Workspace/WorkspaceController+Duplicate.swift`,
  `Tests/CanvasDuplicateTests.swift` (~220 lines)

### Task 3 — The card bar over the board, and the same catalogue in the context menu (R-06, R-07, R-13)

**RED.** Extend `Tests/CardCommandTests.swift`:

- `BoardCardControls.isShown(selection:)` is `true` for a selection of exactly one id, `false`
  for an empty selection and `false` for two — R-07's rule as a pure function, so "hidden, not
  disabled" is testable without a window. (R-07)
- `CardCommand.identifier` (or the equivalent) yields `board-card-duplicate`,
  `board-card-copyLink`, … one stable AX identifier per command, derived from the `rawValue` so
  a new command cannot ship without one. (R-06)

**GREEN.**
- New `Sources/Features/Workspace/BoardCardControls.swift`: a capsule in the same trailing
  `VStack` as `BoardPenControls`/`BoardZoomControls` (`WorkspaceView.swift:334-345`), **above**
  the pen row so the zoom controls stay where they are. Placed there and nowhere else
  (ADR-0023 §D7). Same face as its neighbours: `theme.color(.surfaceRaised)`, `Capsule()`,
  `.themedShadow(.card)`, `theme.spacing(...)`, `.buttonStyle(.plain)` — **no hardcoded colour
  anywhere** (CLAUDE.md, binding rule). Container identifier `board-card-bar`, one identifier
  per button from `CardCommand`. `Colore`, `Ridimensiona` and `Ritaglia` are `Menu`s with the
  same submenu contents the context menu builds.
- `WorkspaceView.board` renders it under `if BoardCardControls.isShown(selection: workspace.selection)`.
- `BoardContentLayer.contextMenu` rebuilt as a loop over
  `CardCommand.available(for:isCroppable:hasCrop:)`, each case switching to the action it
  already performs. **Every action body is moved, not rewritten** — `targets(_:)`,
  `fitToCrop(_:)`, `copyLink(to:)`, `open(_:)`, `workspace.setColor/resize/beginCrop/removeCrop/delete`
  keep their current bodies and their current call arguments. Gains one entry: `Duplica`, calling
  `workspace.duplicate(nodeIDs: targets(node))`.
- `isCroppable(node)` (`BoardContentLayer.swift:242-245`) is what feeds `available`'s
  `isCroppable:` argument, unchanged — including its `drawsPlaceholder` clause.

Watch the file length: `BoardContentLayer.swift` is 297 lines and SwiftLint warns at 400. If the
menu builder pushes it over, extract the menu into
`Sources/Features/Workspace/BoardCardMenu.swift` rather than reaching for a
`swiftlint:disable` — this codebase contains none.

- Budget: `Sources/Features/Workspace/BoardCardControls.swift`,
  `Sources/Features/Workspace/BoardContentLayer.swift`,
  `Sources/Features/Workspace/WorkspaceView.swift`, `Tests/CardCommandTests.swift` (~260 lines)

### Task 4 — The Workspace folder row's own Rinomina and Elimina (R-01, R-02)

**RED.** Extend `Tests/WorkspaceBrowserToolbarTests.swift`:

- **R-02 as a property of the tree, not of a guard:** build
  `NoteTree.build(fromPaths: ["Labs.canvas", "01 Progetti/a/a.canvas", "01 Progetti/b/b.canvas"])`,
  take `WorkspaceBrowser.allFolders(in:)`, and assert (i) the set is exactly
  `["01 Progetti", "01 Progetti/a", "01 Progetti/b"]`, (ii) `""` is **not** in it, and (iii)
  `WorkspaceBrowserToolbar.canMutate(folder:)` is true for every member. That is the SPEC
  correction pinned: there is no root folder row to hide anything from, and the guard agrees
  with the tree rather than contradicting it. (R-02)
- `WorkspaceBrowserToolbar.canMutate(folder: "")` and `canMutate(folder: "/")` stay false — the
  existing assertions, re-run as the regression they now also are. (R-02)

**GREEN.** `Sources/Features/Workspace/WorkspaceBrowser.swift`:

- `WorkspaceTreeRow` gains `let onRename: (String) -> Void` and `let onDelete: (String) -> Void`,
  passed down at all three construction sites (`:191`, `:214`, `:335` — the recursion included).
- `folderRow`'s **label `HStack`** gains a `.contextMenu`, placed after
  `.accessibilityIdentifier("workspace-folder-\(node.id)")` and on that same view. **Never on the
  `DisclosureGroup`** — the comment at `:359-367` says why, and the failure mode is a board row
  offering to delete its parent folder.
- Contents, in order: the two existing tree commands are **not** duplicated here (they live on
  the `List`, `:202-205`, and stay). The menu is
  `Button("Rinomina…") { selected = node.id; onRename(node.id) }` and
  `Button("Elimina…", role: .destructive) { selected = node.id; onDelete(node.id) }`, both inside
  `if WorkspaceBrowserToolbar.canMutate(folder: node.id)`. The selection is set first because
  `RenameWorkspaceSheet` is seeded from `targetFolder` (`:74-84`, ADR-0023 §D4).
- `WorkspaceBrowser` passes `onRename: { _ in isRenamingWorkspace = true }` and
  `onDelete: { confirmDelete(of: $0) }` — **the same two closures the toolbar buttons call**
  (`:113-115`). No second code path, no second confirmation dialog.
- Symbols: none. `NoteRowMenu` draws plain titles and so does the folder row's menu — R-13's
  "the same symbol" includes the same absence of one (ADR-0023 §D1). The toolbar keeps its
  `pencil`/`trash`.

**Manual check in Task 9, because no unit test can reach it:** right-click a *board* row and
confirm it offers nothing new; right-click a nested folder inside an expanded parent and confirm
the menu names the nested folder.

- Budget: `Sources/Features/Workspace/WorkspaceBrowser.swift`,
  `Tests/WorkspaceBrowserToolbarTests.swift` (~140 lines)

### Task 5 — The note row's Copia link, Cronologia and Applica template (R-03, R-04)

**RED.** New `Tests/RowCommandTests.swift` (header names ADR-0023 and this plan's basename),
built on `TemporaryVault` and the `VaultController` shape `Tests/CommandActionTests.swift:14-30`
already uses — **always a temporary state base**, never the real Application Support directory
(CLAUDE.md principle 3):

- With `a.md` open and `b.md` not, `actions.run(.noteHistory, on: "b.md")` leaves
  `vault.openNote?.relativePath == "b.md"` **and** `vault.isShowingHistory == true`. That single
  assertion pair is R-04: the open happened, and it happened *before* the action. (R-04)
- The same for `.applyTemplate` (`vault.isChoosingTemplate == true`) and for `.copyLink` (the
  pasteboard holds `PergamenumLink.note(path: "b.md")`'s absolute string). (R-03, R-04)
- Invoked on the **already-open** note, `run(.noteHistory, on: "a.md")` does not change
  `vault.focusedTab`'s id — no re-open. This is `openNote(at:)`'s own short-circuit
  (`VaultController+Tabs.swift:286-289`) asserted, not new behaviour. (R-04)
- `canRun(.applyTemplate, on: "b.md")` is false with no `Templates/` folder in the fixture and
  true with one holding a note — the same condition `canRunOnOpenNote` applies
  (`CommandActions.swift:344-347`), reached without needing the note open first. (R-03)
- `canRun(.copyLink, on:)` and `canRun(.noteHistory, on:)` are true for any row path: a row
  always names a note. (R-03)
- **Negative control**, in the spirit of this file's existing header: `run(_:on:)` called with a
  command that does not act on a note (say `.newBoard`) must not open the note — assert
  `vault.openNote` is unchanged. The guard is an `assertionFailure` in Debug plus a no-op.

**GREEN.**
- `Sources/App/CommandActions.swift`: `func run(_ command: ShortcutCommand, on notePath: String)`
  — opens the note through `vault.openNote(at:)`, then `run(command)` — and
  `func canRun(_ command: ShortcutCommand, on notePath: String) -> Bool`. Both restricted to the
  three commands of cluster 2 (`.copyLink`, `.noteHistory`, `.applyTemplate`); anything else
  trips the same `assertionFailure` pattern the file already uses and does nothing.
- `Sources/Features/Editor/NoteRowMenu.swift`: `@Environment(CommandActions.self) var actions`
  and three entries after «Rinomina…»/«Sposta in», before the «Rivela nel Finder» divider:
  `Copia link Pergamenum`, `Cronologia…`, `Applica un template…` — **titles taken from
  `ShortcutCommand.copyLink.title`, `.noteHistory.title`, `.applyTemplate.title`**, not retyped,
  so the row and the menu bar cannot be reworded apart. `.disabled(!actions.canRun(command, on: note.relativePath))`
  on each, matching what the File and Vista menus do beside the same commands.

`CommandActions` is injected at `PergamenumApp.swift:149` and `NoteRowMenu`'s three call sites
are all inside `NoteListPane`, which is inside `VaultBrowser` in the main window
(`VaultBrowser.swift:17`) — so the environment value is present at every one. The two sheets
these commands raise are attached in that same container (`VaultBrowser.swift:44-47`,
`VaultBrowser+History.swift:52-62`), so no pane switch is needed.

- Budget: `Sources/App/CommandActions.swift`, `Sources/Features/Editor/NoteRowMenu.swift`,
  `Tests/RowCommandTests.swift` (~200 lines)

### Task 6 — The task row's «Aggiungi sotto-task» (R-05)

**RED.** Extend `Tests/RowCommandTests.swift`:

- `VaultSession.TaskDraft.subtask(of: task)` has `parent == task` and
  `destination == .note(task.sourcePath)`, and every other field at its default. That is
  `addSubtaskToSelectedTask`'s body (`CommandActions.swift:356-361`) turned into a value.
- **The two entry points are one value:** with `vault.selectedTask = task`,
  `actions.run(.taskAddSubtask)` leaves `vault.taskDraft == VaultSession.TaskDraft.subtask(of: task)`.
  `TaskDraft` is `Equatable` (`VaultSession+Tasks.swift:41`), so this is a single `#expect`. (R-05)
- With no task selected, `run(.taskAddSubtask)` still leaves `vault.taskDraft` nil — the existing
  guard, re-asserted so the extraction cannot quietly drop it.

**GREEN.**
- `Sources/Vault/VaultSession+Tasks.swift`: `static func subtask(of parent: TaskItem) -> Self` on
  `TaskDraft`. Foundation only; the file is already in `sharedSources` and gains no import.
- `Sources/App/CommandActions.swift`: `addSubtaskToSelectedTask()` becomes
  `guard let parent = vault.selectedTask else { return }; vault.taskDraft = .subtask(of: parent)`.
  **No behaviour change** — the destination comment there (why `.note(parent.sourcePath)` is set
  even though `captureTask` ignores it for a draft with a parent) moves onto the factory.
- `Sources/Features/Tasks/TasksView.swift`: `contextMenu(_:)` gains
  `Button("Aggiungi sotto-task")` — title from `ShortcutCommand.taskAddSubtask.title` — placed
  after «Completa»/«Riapri» and its divider, mirroring the Task menu's own order
  (`PergamenumApp.swift:253-263`). Its body sets `selectedTaskID = task.id`,
  `vault.selectedTask = task`, then `vault.taskDraft = .subtask(of: task)`: the row the user
  right-clicked becomes the selected row, so the four rescheduling keys act on it too
  (ADR-0023 §D6).

- Budget: `Sources/Vault/VaultSession+Tasks.swift`, `Sources/App/CommandActions.swift`,
  `Sources/Features/Tasks/TasksView.swift`, `Tests/RowCommandTests.swift` (~130 lines)

### Task 7 — «Nuovo evento» and «Nuovo promemoria» on all three calendar day cells (R-09, R-13)

**RED.** New `Tests/CalendarDayMenuTests.swift` (header names ADR-0023 and this plan's basename):

- `CalendarDayCommand.entries(eventAccess: true, reminderAccess: true)` returns exactly two
  entries, in the order `[.newEvent, .newReminder]`, both `isEnabled`. (R-09)
- With `eventAccess: false` the first is present and **disabled**, not absent — ADR-0023 §D10's
  decision as an assertion, since "disabled rather than hidden" is the one place this cluster
  could reasonably have gone either way. Same for `reminderAccess: false` and the second.
- The two titles are `ShortcutCommand.newEvent.title` and `ShortcutCommand.newReminder.title`
  **by identity**, not by literal — assert `entries[0].title == ShortcutCommand.newEvent.title`.
  That is what makes R-09's "identici alle versioni del menu bar" and R-13 hold under a future
  rewording of either. (R-09, R-13)
- The list does not depend on the date: `entries(...)` takes no `CalendarDate`, so all three
  surfaces cannot differ (R-09's "identici tra loro").

**GREEN.**
- New `Sources/Features/Today/CalendarDayCommand.swift`: the enum, `title`, `symbol`
  (`calendar.badge.plus` / `bell.badge`, both recorded with a comment naming where they came
  from), and `static func entries(eventAccess:reminderAccess:) -> [Entry]` where
  `Entry` is `(command, title, symbol, isEnabled)`. Foundation only.
- New `Sources/Features/Today/CalendarDayMenuItems.swift`: a small `View` reading
  `@Environment(EventKitStore.self)`, taking the date and two closures, rendering the entries as
  `Button`s with `.disabled(!entry.isEnabled)`. Injected at `PergamenumApp.swift:142`, so the
  environment value is present in all three surfaces.
- `MonthView.menu(for:)` and `WeekView.menu(for:)` each gain `Divider()` +
  `CalendarDayMenuItems(...)` at the bottom, with `onNewEvent: { controller.show(column.day); controller.isCreatingEvent = true }`
  and the reminder twin. The **existing three entries are left byte-identical** (ADR-0023 §A8 —
  their duplication between the two files is out of scope and now documented).
- `MiniCalendar` gains `let onNewEvent: (CalendarDate) -> Void` and
  `let onNewReminder: (CalendarDate) -> Void`, **required, not defaulted**, and appends the same
  view to its own `.contextMenu` (`:118-123`). `DayMonthSection.swift:31` — the only call site —
  is updated in this batch, wiring both through the `DayController` it already holds.

Each action does `controller.show(date)` **before** setting the flag, so the composer opens on
the day that was right-clicked rather than on the anchor day. Not `actions.run(.newEvent)`: that
sets `navigation.pane = .today` and acts on the *current* day (`CommandActions.swift:251-256`),
which is right for the menu bar and wrong for a cell that names its own date.

- Budget: `Sources/Features/Today/CalendarDayCommand.swift`,
  `Sources/Features/Today/CalendarDayMenuItems.swift`, `Sources/Features/Today/MonthView.swift`,
  `Sources/Features/Today/WeekView.swift`, `Sources/Features/Today/MiniCalendar.swift`,
  `Sources/Features/Today/DayMonthSection.swift`, `Tests/CalendarDayMenuTests.swift` (~230 lines)

### Task 8 — The drawn embed's own context menu (R-08)

**RED.** New `Tests/EmbedContextMenuTests.swift` (header names ADR-0023 and this plan's basename),
beside `Tests/EmbedNavigationTests.swift` and using the same fixtures:

- **R-08's real content, asserted as an equality rather than as a description:** for a run at the
  start of the text, a run in the middle, and a run at the very end with no trailing newline,
  `EmbedContextMenu.deletionRange(forRun:textLength:)` equals
  `EmbedNavigation.deletionRange(selection: NSRange(location: NSMaxRange(run), length: 0), direction: .backward, drawnRuns: [run], textLength:)`.
  The menu's delete **is** the Backspace path; the test says so by comparing against it, not by
  restating its rule. (R-08)
- `EmbedContextMenu.items()` returns exactly one entry, titled `Elimina`.
- `deletionRange` returns nil for a run whose end exceeds `textLength` — the stale-range case
  `replaceAtomically` already guards, refused one step earlier so the menu never asks for a bad
  write.

**GREEN.**
- New `Sources/Features/Editor/EmbedContextMenu.swift`: the pure part — `items()` and
  `deletionRange(forRun:textLength:)`, the latter **calling** `EmbedNavigation.deletionRange`
  rather than reimplementing it. `import Foundation` only.
- `Sources/Features/Editor/CompletingTextView.swift`: `var onEmbedMenu: ((CGPoint) -> NSMenu?)?`,
  documented beside `onClickInMargin`, `claimsCommand` and `onEmbedResize` as the fourth closure
  of that shape.
- `Sources/Features/Editor/CompletingTextView+Pasteboard.swift` (the file whose header is already
  *"what arrives in the editor from outside the keyboard"*):
  `override func menu(for event: NSEvent) -> NSMenu?` converting the point and asking
  `onEmbedMenu`, **falling through to `super.menu(for: event)` when it answers nil**. That
  fallback is what keeps the standard editor context menu — spelling, substitutions, cut, copy,
  paste — on every point that is not a drawn embed. It is the single most likely regression in
  this whole plan.
- `Sources/Features/Editor/NoteTextView+EmbedCaret.swift`: `func embedMenu(at point: CGPoint, in textView: NSTextView) -> NSMenu?`
  reusing `selectEmbed(at:in:)`'s geometry — `decorations.hidesMarkup`, the
  `decoration(at:in:claimedBy:)` walk, `drawnEmbedRange(atParagraphStart:in:)`,
  `Self.drawnPictureFrame(at:in:)`, `Self.inContainer(point, of:)` — refactored so the "which run
  does this point hit" half is asked once and used by both, exactly as
  `NoteTextView+EmbedResize.swift:54-96` already does with `grabbedEmbed(at:in:)`. It selects the
  run first (so the menu visibly names something), then builds a one-item `NSMenu` whose action
  calls `replaceAtomically(range, with: "", in: textView)` with the range
  `EmbedContextMenu.deletionRange` returned.
- `NoteTextView.wire(_:to:)` sets `textView.onEmbedMenu` beside the other three, closed over
  `[weak textView]` for the same reason they are.

**Do not** touch `EmbedNavigation`, `EmbedResize` or `replaceAtomically`. A diff to any of them
in this task is a design error: this task adds a caller, not a rule.

- Budget: `Sources/Features/Editor/EmbedContextMenu.swift`,
  `Sources/Features/Editor/CompletingTextView.swift`,
  `Sources/Features/Editor/CompletingTextView+Pasteboard.swift`,
  `Sources/Features/Editor/NoteTextView+EmbedCaret.swift`,
  `Sources/Features/Editor/NoteTextView.swift`, `Tests/EmbedContextMenuTests.swift` (~230 lines)

### Task 9 — The connector builds, the UI suite, and the manual pass (R-12, R-14)

No new automated test. Both requirements are work all the same.

1. **`.claude/test-cmd` green, whole bundle** (R-14, first half). Not one file's tests: four of
   the eight tasks above change behaviour other modules observe.
2. **Both connector builds green** (R-14, second half) — this is the mechanical proof that no
   SwiftUI import reached `Sources/Core` or `Sources/Connector` (ADR-0001 §D1):
   ```
   xcodebuild -workspace Pergamenum.xcworkspace -scheme perg -destination 'platform=macOS' build
   xcodebuild -workspace Pergamenum.xcworkspace -scheme pergamenum-mcp -destination 'platform=macOS' build
   ```
   Both are expected to pass untouched: this plan adds no file to either target and edits exactly
   one shared file (`Sources/Vault/CanvasStore.swift`, Foundation-only addition). If either fails,
   a file went somewhere it should not have.
3. **`scripts/uitests.sh` with no arguments, once, before the merge to `main`** (`CLAUDE.md` —
   three of sixty-seven UI tests had been red for a whole milestone the last time this rule was
   bought, `PG-033`). An argument **replaces** the selection rather than adding to it; do not
   pass one. Expect every identifier in the contract table above to still pass untouched.
4. **Manual QA pass over the running app** (R-12), reported in the chain's summary as a
   checklist, each line ticked by hand. Use a throwaway vault via `-recentVaults '("/path")'` —
   the plist array form, or no vault is reopened at launch (`CLAUDE.md`):
   - Workspace: right-click a nested folder row → Rinomina and Elimina name **that** folder, and
     the sheet/dialog agree; right-click a **board** row → nothing new appears; the toolbar's
     Rinomina/Elimina still work and still grey out as before.
   - Note list: the three new entries on a row that is **not** open (opens, then acts) and on the
     row that **is** open (acts, no tab flicker); «Applica un template…» greyed with no
     `Templates/` folder.
   - Attività: «Aggiungi sotto-task» from a row that was not selected — the composer's parent
     header names the row that was right-clicked, and the four rescheduling keys now act on it.
   - Board: select one card → the bar appears; deselect → it disappears (not greys); select two →
     it does not appear and the context menu still acts on both; Duplica from the bar and from
     the menu; Duplica a cropped card (the copy is cropped) and a card whose file was deleted in
     the Finder (the copy shows the same placeholder); Cmd+Z undoes a duplicate in one step.
   - **Editor, the regression that matters most:** right-click on ordinary prose still shows the
     system editor menu with spelling and paste; right-click on a drawn image shows only
     «Elimina»; that Elimina removes exactly what Backspace removes and one Cmd+Z puts it back;
     with reading mode on (no `hidesMarkup`) the ordinary menu is back.
   - Calendario: the two new entries on a Mese cell, a Settimana column and a MiniCalendar cell —
     each opens the composer on **that** day; both greyed if EventKit access is revoked in System
     Settings.
5. **The record.** Add a paragraph to `docs/20260811_Pergamenum_SpecApp.md` §10 in the document's
   own Italian voice: every command listed there is now reachable from its row's context menu as
   well as from the menu bar or toolbar, and a card can be duplicated on the board without
   duplicating the file it points at. Then update `PROJECT_BRIEF.md`'s Status line if this closes
   a milestone item.

- Budget: `docs/20260811_Pergamenum_SpecApp.md`, `PROJECT_BRIEF.md` (~30 lines)

---

## Risks, dependencies and HITL gates

**Risks**

- **The editor's right-click, replaced rather than extended.** `menu(for:)` returning a menu on a
  point that is not a drawn embed, or returning nil where `super` would have returned the system
  menu, silently takes spelling, substitutions and paste away from the whole editor. Nothing
  errors; the menu is simply poorer. The `super.menu(for:)` fallthrough is the guard, and
  Task 9.4's editor line is the only thing that can see it.
- **A context menu on the wrong view in the Workspace tree.** Attached to the `DisclosureGroup`
  instead of to the label, Rinomina/Elimina appear on every disclosed descendant and name the
  parent folder — a delete of the wrong thing, reachable by right-clicking a board row.
  `WorkspaceBrowser.swift:359-367` records the propagation; Task 4 states the attachment point;
  Task 9.4 is where it is seen.
- **`canRun(_:on:)` drifting from `canRun(_:)`.** `CommandActionTests.swift`'s own header calls
  itself the negative control against exactly this class of change, in exactly this file. A row
  entry enabled at a moment the menu bar disables the same command is a silent inconsistency,
  not a crash.
- **A duplicate that claims to have created a file.** `duplicate` must pass
  `creatingOnDisk: nil`. Passing a path would make `BoardHistory` refuse the undo with the
  "«…» è stata creata su disco" message (`WorkspaceController.swift:231-233`) for a card that
  created nothing — an undo that stops working, explained by a sentence that is not true.
- **The card bar over the pen controls.** Four floating clusters now share the board's
  bottom-trailing corner (card bar, pen controls, zoom controls, and the crop editor's grips
  elsewhere on the card). On a short window with the Disegno tool active they stack; check the
  order on screen rather than trusting the `VStack`.
- **An id collision in a hand-edited canvas.** `generate(avoiding:)` protects the duplicate, but a
  `.canvas` a person edited by hand can already contain two nodes with the same id; this feature
  does not repair that and must not pretend to. The duplicate's id avoids **every** id present,
  including a repeated one.
- **A stale generated project.** Six new files across three feature directories;
  `tuist generate --no-open` after every task that adds one, or the build fails naming the
  compiler rather than the file.
- **File length.** `BoardContentLayer.swift` (297), `TasksView.swift` (504 — already over),
  `CommandActions.swift` (401) and `WorkspaceBrowser.swift` (394) all sit at or past what
  SwiftLint reports. Extract rather than suppress; this codebase contains no
  `swiftlint:disable` anywhere and this feature must not introduce the first one.

**Dependencies**

- None external. No new package, no `Tuist/Package.swift` edit, no `tuist install`. GRDB does not
  exist in this repository and nothing here needs it.
- ADR-0023 must be moved to `docs/adr/0023-universal-command-surface-parity.md` by the operator
  before Task 1, so the test-file citations point at a file that exists.
- Task order: 1 → 2 → 3 is serial (3 consumes both). 4, 5, 6, 7 and 8 are independent of each
  other and of 1-3 — they touch disjoint files and may be written in any order or in parallel.
  9 is last and needs all of them.
- `.claude/protected-interfaces` declares `IndexCache.schemaVersion` and
  `VaultAPI.LintFinding`. **Neither is touched by any task here**, and a diff reaching either is
  a sign the design went wrong, not a reason to edit that file.

**HITL gates**

- **Gate 2 (now):** approve ADR-0023, the branch name, the three SPEC corrections above, and the
  two proposals below.
- **Before the commit of each task:** `.claude/test-cmd` green, whole bundle, not one file.
- **Before the merge to `main`:** `scripts/uitests.sh` green (Task 9.3), both connector builds
  green (Task 9.2), and the manual checklist ticked (Task 9.4). All three human-confirmed, not
  agent-asserted.
- **Commit, push and PR** are the human's, as always. No force-push, no direct commit to `main`.
- **No deletion of any existing test or file** in this chain. If one looks wrong, say so in chat.

---

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -derivedDataPath "/Users/stefer/Developer/Pergamenum/.build/DerivedData" -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield

CODER-MODEL CANDIDATE: opus
