# Plan — Drag-and-drop board and note files into folders

- **SPEC:** `/Users/stefer/Developer/Pergamenum/SPEC.md` (R-01 … R-15).
- **ADR:** `ADR-0026: A row is dragged into a folder, and several rows are chosen first`, currently
  at
  `/Users/stefer/Developer/Pergamenum/docs/architecture/ADR-0026-drag-and-drop-board-files-into-workspace.md`,
  **to be moved by the operator to
  `/Users/stefer/Developer/Pergamenum/docs/adr/0026-drag-and-drop-board-files-into-workspace.md`**
  before Task 1 (this project's ADRs all live under `docs/adr/`; the architect agent's write scope
  forbids that directory). Every reference below is to **ADR-0026** by name, never by path, so the
  move breaks nothing.
- **Branch:** `feature/adr-0026-sidebar-drag-move`
- **Base:** `b429ee6`. Every line number quoted below was read at that commit.
- **Style:** TDD. Every task writes its failing test first, then the code that makes it pass.
  Swift Testing (`#expect`, `#require`), never XCTest, for everything new in `Tests/`; XCTest in
  `UITests/`, matching the suite that is already there.
- **Swift is compiled, so "red" has a precondition.** A task's **test step owns the interface**: it
  adds the new type, signature and enum-case declarations *together with* the failing tests —
  placeholder bodies returning `nil` / `[]` / `.refused([])` / the unchanged input — so the target
  **builds** and the tests fail on their assertions. The code step owns the body only. Never
  `fatalError()` and never a force-unwrap as a placeholder (`~/.claude/rules/swift.md`). **This
  chain removes nothing and re-signs two things** (the two `List(selection:)` bindings, Tasks 5 and
  6); those two have no placeholder form, so each carries its own call-site updates in the same
  batch and the contract table says which.
- **Harness:** this plan creates **no new harness script**, the same decision the five preceding
  Workspace/Note plans made. Verification is the two commands this project already trusts:
  `.claude/test-cmd` after every task, and `scripts/uitests.sh` once, at Task 8, before the merge to
  `main` (`CLAUDE.md`, working agreements — the UI suite is outside `test-cmd` on purpose and its
  state is unknown between deliberate runs, `PG-033`). Do not re-specify that rule; cite it.
  **Every new or rewritten test file's header comment must name `ADR-0026` and this plan's basename
  `2026-08-27-drag-and-drop-board-files-into-workspace`** — that citation is the only link this
  repository keeps between a test and the decision that asked for it, and it is the anchor the
  coverage report reads. Preserve the existing `ADR-00xx` / `2026-…` header lines where a file is
  *edited* rather than rewritten; add the new pair beside them, never in place of them.
- **After any task that adds a file:** `tuist generate --no-open`. The generated project lists files
  and does not regenerate itself; a build that fails naming the compiler rather than the missing
  file is the documented failure mode. **Tasks 1, 3, 4, 5 and 7 add files.** The same applies after
  any `git stash` / `git checkout` that adds or drops a file mid-chain.
- **`Project.swift` is edited once, at Task 4, and `sharedSources` gains nothing.** The app target
  is `Sources/**` minus `Sources/CLI/**` and `Sources/MCPServer/**` (`Project.swift:139-141`), so
  every new file under `Sources/App`, `Sources/Vault` and `Sources/Features` compiles into the app
  automatically. Task 4 adds a `UTExportedTypeDeclarations` entry to the app target's
  `infoPlist` (`Project.swift:118-135`) and nothing else. **Do not add
  `Sources/Vault/BoardFileOperations.swift`, `Sources/Vault/FolderFileOperations.swift`,
  `Sources/Vault/VaultMoveBatch.swift` or `Sources/Vault/VaultSession+Move.swift` to
  `sharedSources`**: that exclusion is ADR-0022 §D6 / ADR-0025 §D6 / ADR-0026 §D1 made a
  compile-time fact — a write that `--dry-run` cannot rehearse and the connector `undo` cannot
  reverse must stay unreachable from `perg` and `pergamenum-mcp`. After Task 4, run **both** tool
  builds once (`-scheme perg`, `-scheme pergamenum-mcp`) to confirm they are unaffected.
- **`Sources/Core/**` must not import SwiftUI or AppKit** (ADR-0001 §D1, enforced by the two tool
  builds). **This chain adds nothing to `Sources/Core/**`.** `WorkspaceBoardResolver` is read, not
  changed.
- **Known false positives, ignore them:** the pre-commit `weakening-scan.sh` reports every Swift
  Testing test as `zero-assertion-test` (its body scanner treats a line starting with `#` as a
  comment and `#expect(...)` starts with one); the secret scanner's `assigned-secret` rule fires on
  design-token lines. Both documented in `CLAUDE.md`. Do not restructure code to appease either; do
  still read the diff.
- **Never disable or delete a test to make the suite pass** (`CLAUDE.md`). **No assertion in this
  chain inverts.** Anything that turns red is a regression, not a migration — in particular the
  eight `app.staticTexts["…"]` lookups in `UITests/NoteTreeAndShortcutsUITests.swift:54-90`, which
  Task 6 is under orders not to disturb (see the contract table).
- **The design-token rule is load-bearing.** «A view that uses a colour or a font without going
  through a token does not pass review» (`CLAUDE.md`). The drop-target highlight uses
  `theme.color(.accentPrimary)` through the same `RoundedRectangle(...).stroke(...)` overlay
  `TaskDropTarget` (`TaskDrag.swift:69-72`) and `ColumnDropTarget`
  (`ViewBoardRenderer.swift:221-226`) already draw. No new colour, no hardcoded one.
- **UI language is Italian; code, comments and commits are English.** New strings in this chain:
  «Sposta in», «(radice)», and the collision dialog's title and body.

---

## Nine things this chain's SPEC says about the repository that are false, incomplete or under-determined

Read at `b429ee6`, before this plan was written. Do not rediscover them, and do not follow the
SPEC's wording where it contradicts them.

| SPEC says | Truth at `b429ee6` | Consequence for this plan |
|---|---|---|
| Architecture → Move operation: *"The Note sidebar needs the equivalent for notes: either a new `NoteFileOperations.movePlan` mirroring `BoardFileOperations`'s shape, or reuse if an equivalent already exists — the architect confirms which"* | **It exists, all the way to the user interface.** `NoteFileOperations.movePlan(_:toFolder:)` (`:146-158`) and `.move(_:toFolder:)` (`:274-294`, board node repoint included at `:292`); `VaultSession.moveNote` inside `transaction("note move")` (`VaultSession+Files.swift:52-73`); `VaultController.moveNote(at:toFolder:)` (`VaultController+Files.swift:41-55`) with `canOperate(on:)` and `movedNote(from:to:)`; and a shipped **«Sposta in»** menu on every note row (`NoteRowMenu.swift:30-36`). | **Add nothing to `NoteFileOperations` and nothing to `VaultSession+Files`.** R-03 is a UI wiring onto an existing journalled verb (ADR-0026 §D2). `NoteFileOperations.swift` is in `sharedSources` (`Project.swift:81`) — a signature change there would break both tool builds for no reason. Task 3 dispatches to it; Task 6 wires the rows. |
| Architecture → *"Marker and link consequences of a move (**no new rewriting**)"*, with a three-bullet list of what is unaffected | **Incomplete, and the omission is a real break.** A `.canvas` node addresses its file by **path** (`.file(path:subpath:)`), so a moved note/board/folder that is a card on any board leaves that card pointing at nothing. `NoteFileOperations` documents finding exactly this on a real vault (`:11-19`) and already fixes it for a note move (`:292`). | Both new operations run `FolderFileOperations.repointBoardsPlan(from:to:)` (`:180-229`), which ADR-0025 §D6 made non-private precisely so a file path and a folder path share one loop: exact-path arm for a moved board that is itself a card, `<old>/` prefix arm for everything inside a moved folder, `writePath` substitution for a board carried along by the folder. **No third copy of that loop.** Task 2. The SPEC's three bullets (wikilinks, `^[[x.canvas]]` markers, `tasks(assignedToWorkspace:)`) are all correct and stay untouched. |
| Architecture → Drag/drop UI mechanics: the collision affordance is *"architect's call, whichever the chosen drag API makes straightforward"* | **Neither API makes any of it straightforward.** `.dropDestination(for:action:isTargeted:)` has **no validation closure**: `action` runs after the drop, `isTargeted` is handed a `Bool` and never the payload. The older `DropDelegate.validateDrop(info:)` gets `NSItemProvider`s that can only be read **asynchronously**, so it cannot inspect the payload either. | The only way a hovered row can know what is over it is that the **source** stored the drag set at drag start — legitimate here only because every drag is intra-app (Finder in/out is out of scope). Cycle → no highlight (pure path arithmetic, free per hover). Collision → accept, then a dialog naming the conflicts (R-07 requires the name to be *shown*, and the check is a `fileExists` burst per hover). ADR-0026 §D5. Tasks 5 and 6. |
| Scope: *"Drag-and-drop of note rows (`.md`) and folder rows within the Note sidebar tree"* — silent about what those rows already carry | **The note rows are already drag sources.** `.draggable(note.title)` at `NoteListPane.swift:197` and `.draggable(node.name)` at `:346`, consumed by `CompletingTextView.performDragOperation` (`CompletingTextView+Pasteboard.swift:102-112`) **only when the string is a real note title** (`noteTitles.contains(title)`), which appends `[[title]]` to the task line under the cursor — SPEC §7.2. A view carries one `.draggable`; replacing the payload makes the drop fall through to `NSTextView`, which pastes the raw payload into the note as text. | One `Transferable` with **two** representations: `CodableRepresentation(contentType: .pergamenumVaultItem)` for the move payload and `ProxyRepresentation(exporting: \.dragName)` for the plain title, byte-identical to today's. **`CompletingTextView+Pasteboard.swift` is not edited by any task in this plan** (R-09). ADR-0026 §D3. Task 4. |
| Architecture → Undo: *"the … editor/canvas … already owns its own undo stack for text/canvas edits — the two undo domains must not collide"* | **There is one domain, not two.** `NoteTextView.swift:114` sets `textView.allowsUndo = true`; an `NSTextView` registers on `NSResponder.undoManager`, which resolves to the **window's** `NSUndoManager`. `@Environment(\.undoManager)` is that same object. Confirmed separately: zero occurrences of `UndoManager`/`NSUndoManager`/`registerUndo` anywhere in `Sources/`, so the SPEC is right that this is the first registration. | Register on `@Environment(\.undoManager)`, passed **as a parameter** into the controller call (the controller never reaches for `NSApp`). One window, one stack, shared with the editor by design. `MenuCommands.swift` replaces `.textEditing`, `.help`, `.pasteboard`, `.sidebar`, `.toolbar` and **not** `.undoRedo`, so Edit ▸ Annulla is already wired. ADR-0026 §D8. Task 3. |
| Edge cases, last bullet: *"R-11 (no-test: requires a scripted multi-step undo race …) covers this by manual verification"* | **Wrong id.** R-11 (line 215) is *"dragging a row that is part of an active multi-row selection moves every selected row"* — fully testable, and tested. The untestable scenario described (undo after unrelated intervening edits) belongs to **R-12**'s manual half. | R-11 keeps full unit **and** UI coverage (Tasks 1, 5, 6, 7). The manual-verification item is booked under R-12 in Task 8. Do not treat R-11 as exempt from testing. |
| UI flows 1: *"the moved board (if it was the open board) stays open and selected at its new location"* — silent about how | Achievable, but not free. `WorkspaceView+FolderVerbs` brackets every existing folder/board verb with **`flushBoard()` first** (`:136-141`, `:180-187`): the board autosaves ~1s after a change and that write would otherwise land on the pre-move path and recreate the file the move just relocated (ADR-0022 §F10, already paid for once by rename and delete). | The move verb goes through the same bracket, flush first, and lands through a new **pure** rule `WorkspaceFolderActions.boardAfterMove(open:moves:)` beside the four already there (`WorkspaceFolderActions.swift:67-109`), tested where they are tested. Tasks 3 and 5. |
| Scope: *"Drop targets: an existing folder row (move inside it), or the root area of the tree"* | The "root area" is not a row and has no owner. `WorkspaceTree` synthesizes no root row (ADR-0025 §D2) and `NoteTree` makes none either; the empty space below the last row belongs to the `List`. | `.dropDestination` on the `List` itself, with the rows' own destinations inside it — SwiftUI hit-tests innermost-first, so a row drop reaches the row and only a background drop reaches the list. **This is the one part of the design asserted by hand rather than by construction**, which is why «Sposta in ▸ (radice)» exists as a second, certain surface for R-05. ADR-0026 §D11. Tasks 5, 6, 8. |
| Stack: *"`List(selection:)` inside `WorkspaceBrowser.swift` and `NoteListPane.swift`"* | True, and both are **single**-selection `Binding<String?>` — `WorkspaceBrowser.treeSelection` (`:357-375`), `NoteListPane.selectedPath` (`:221-232`). The SPEC never says how a second multi-selection set coexists with them. | Both bindings become `Binding<Set<String>>` and the set **is** the multi-selection; "open" is derived by the collapse rule of ADR-0026 §D4. **No gesture is added to any row** — the reason is `WorkspaceBrowser.swift:713-732`, where a row-wide recognizer starved `List(selection:)` intermittently. Tasks 5 and 6. |

**A tenth item, not false but easy to get backwards:** `UITests/NoteTreeAndShortcutsUITests.swift`
finds every folder and note **by the words on it** (`app.staticTexts["01 Progetti"]`, `:54-90`) —
a practice `CLAUDE.md` forbids for *new* tests and which those existing green tests depend on.
Task 6 adds `accessibilityIdentifier` to the note rows and **must not** add
`.accessibilityElement(children: .contain)`: regrouping the row would move those words out of
`staticTexts` and break eight assertions unrelated to this feature. The Workspace rows already
carry `.contain` (`WorkspaceBrowser.swift:780`) and are unaffected.

---

## Contract changes, and the call sites already grepped

Grepped at `b429ee6` across `Sources/`, `Tests/` and `UITests/`. **A re-signature has no
placeholder: each row's call sites are updated in the same task that makes the change**, or the
target does not build and the task produces no red.

| Change | Call sites (grepped) | Task |
|---|---|---|
| `VaultMoveBatch` / `VaultMove` / `VaultMoveOutcome` — **new** pure types in `Sources/Vault/VaultMoveBatch.swift` | new; readers added in Task 3 (`VaultSession+Move`, `VaultController+Move`) and Tasks 5-6 (the two drop handlers' highlight predicate) | **1** |
| `BoardFileOperations` **gains** `MovePlan`, `MoveOutcome`, `movePlan(_:toFolder:)`, `moveBoard(at:toFolder:)` | new; sole reader `VaultSession+Move.swift` (Task 3). File stays **out** of `sharedSources` | **2** |
| `FolderFileOperations` **gains** `MovePlan`, `MoveOutcome`, `movePlan(_:toParent:)`, `moveFolder(at:toParent:)`, and `OperationError.wouldNest(String)` | new; the added enum case needs one arm in the existing `description` switch (`FolderFileOperations.swift:28-35`) — that switch is the **only** exhaustive switch over this enum in the repository (grepped). Sole reader `VaultSession+Move.swift` (Task 3) | **2** |
| `FolderFileOperations.repointBoardsPlan(from:to:)` — **unchanged, reused** by both new operations | already non-private (`:180`), already called from `BoardFileOperations.renamePlan:131` and `FolderFileOperations.renamePlan:161` | **2** (new callers only) |
| `NoteFileOperations.movePlan` / `.move` — **unchanged, reused** | `VaultSession+Files.swift:53`. **In `sharedSources`** (`Project.swift:81`) — do not touch | **3** (new caller only) |
| `VaultSession` **gains** `moveItems(_:into:)` in a new `Sources/Vault/VaultSession+Move.swift` | new. **Not** added to `sharedSources` (unlike `VaultSession+Files.swift`, which is at `Project.swift:90`) | **3** |
| `VaultController` **gains** `moveItems(_:into:undo:)` and `movedItems(_:)` in a new `Sources/Vault/VaultController+Move.swift` | new; readers `WorkspaceView+FolderVerbs.swift` (Task 5), `NoteListPane.swift` + `NoteRowMenu.swift` (Task 6) | **3** |
| `WorkspaceFolderActions` **gains** `move: (_ items: [VaultItemRef], _ into: String) -> Void` and the static `boardAfterMove(open:moves:)` | `WorkspaceFolderActions.swift:17-56` (the struct's memberwise init has **one** call site: `WorkspaceView+FolderVerbs.swift:7-15`); `WorkspaceBrowser.swift:440-450` passes `actions` down to the row | **3** (rule), **5** (closure + wiring) |
| `VaultItemDrag` / `VaultItemRef` / `UTType.pergamenumVaultItem` — **new** in `Sources/App/VaultItemDrag.swift`. Name check: `SidebarItem` is **taken** (`Sources/App/SidebarItem.swift:23`, the app's left-rail row) — do not reuse it | new | **4** |
| `Project.swift` app-target `infoPlist` **gains** `UTExportedTypeDeclarations` | `Project.swift:118-135`. Followed by `tuist generate --no-open` **and** one build each of `-scheme perg` and `-scheme pergamenum-mcp` | **4** |
| `WorkspaceBrowser.treeSelection` re-signed `Binding<String?>` → `Binding<Set<String>>` | `WorkspaceBrowser.swift:357-375` (the binding), `:399` and `:429` (the two `List(selection:)` sites). `selection`/`onSelect` props (`:25-33`) and `WorkspaceView.swift:131-133` are **unchanged** — the open value stays a `WorkspaceSelection?` | **5** |
| `WorkspaceRow` gains `multiSelection`, `dragging`, `onMove`; `.draggable`/`.dropDestination` applied inside `content` **before** `taggedRow`'s `.tag` (`:733-735`, which stays last) | `WorkspaceBrowser.swift:439-451` (the `row(_:depth:)` factory), `:658-711` (the row struct + its recursive child call) | **5** |
| `NoteListPane.selectedPath` re-signed `Binding<String?>` → `Binding<Set<String>>`, with the composer behaviour preserved verbatim (`:216-232`: nothing selected while the composer is up; clicking the covered note calls `leaveComposer()`) | `NoteListPane.swift:156` and `:180` (the two `List(selection:)` sites) | **6** |
| `NoteListPane` note rows: `.tag` moved to **last** in the chain (today `.tag` precedes `.draggable` at `:345-346` and `:194-197`); `.draggable(node.name)` → `.draggable(VaultItemDrag(...))`; new `accessibilityIdentifier("note-row-<path>")`; **no** `.accessibilityElement(children: .contain)` | `NoteListPane.swift:182-201` (flat list), `:337-352` (tree row), `:291-309` (folder row gains the drop target) | **6** |
| `CompletingTextView+Pasteboard.swift` — **not edited by any task** | `:102-112` reads `draggingPasteboard.string(forType: .string)` and matches it against `noteTitles`. Task 4's `ProxyRepresentation` keeps that string byte-identical (R-09) | — |
| «Sposta in» menu: exists for note rows (`NoteRowMenu.swift:30-36`); **added** for Workspace board+folder rows and for Note-sidebar folder rows | `WorkspaceBrowser.swift:877-888` (`WorkspaceRow.menu`), `NoteListPane.swift:324-335` (`folderMenu`) | **5**, **6** |
| AX identifiers **preserved byte-identical**: `workspace-board-<path>`, `workspace-folder-<path>`, `workspace-tree`, `workspace-flat-list`, `workspace-filter`, `note-tree`, `note-flat-list`, `folder-<path>`, `note-filter`, `note-list-style` | `WorkspaceBrowser.swift:405, 435, 578-582`; `NoteListPane.swift:169, 204, 308`; asserted in `UITests/WorkspaceOpenStateUITests.swift`, `WorkspaceIntegrationUITests.swift`, `WorkspaceBoardUITests.swift`, `NoteTreeAndShortcutsUITests.swift` | preserve — a task that renames one is a task that went wrong |
| AX identifiers **added**: `note-row-<path>`, `sidebar-move-conflict`, `sidebar-move-conflict-ok`, `workspace-move-menu`, `note-move-menu` | new; asserted in Task 7 | **5**, **6**, **7** |

---

### Task 1 — The batch a drop would perform, decided before anything is written (R-05, R-06, R-11)

**Test step (owns the interface).** New `Tests/VaultMoveBatchTests.swift`, header naming ADR-0026
and this plan's basename. It declares, in `Sources/Vault/VaultMoveBatch.swift`, with placeholder
bodies that compile and fail on assertions:

```swift
enum VaultItemKind: Equatable, Sendable { case note, board, folder }
struct VaultItemRef: Equatable, Sendable, Hashable { let path: String; let kind: VaultItemKind }
struct VaultMove: Equatable, Sendable { let item: VaultItemRef; let from: String; let to: String }
enum VaultMoveBatch {
    enum Result: Equatable { case moves([VaultMove]); case refused([String]) }
    static func plan(_ items: [VaultItemRef], into destination: String,
                     exists: (String) -> Bool) -> Result
    static func inverse(of moves: [VaultMove]) -> [VaultMove]
}
```

`exists` is injected as a closure, not a `FileManager` call: it is the one impure input, and
injecting it is what lets every rule below be tested without a temp directory. Tests to write, all
of them `#expect` over pure values:

- a single board into a folder yields one `VaultMove` with `from` = its containing folder (R-05);
- the vault root spelled `""` is a legal destination and yields `to == ""` (R-05);
- a folder into itself, and into a descendant, is `.refused` — and `a-altro` is **not** a
  descendant of `a`, the prefix rule being `"\(folder)/"` and never `folder`
  (`FolderFileOperations.repointing:344-348`'s own rule) (R-06);
- a batch containing a folder **and** one of its descendants drops the descendant silently and
  moves the ancestor only — not an error, not a cycle (ADR-0026 §D6.1);
- an item already directly inside the destination is dropped from the batch, is not an error, and
  **does not appear in `inverse(of:)`** (ADR-0026 §D6.2, the SPEC's "not skipped in a way that
  would try to restore a no-op");
- a destination that already holds the name (`exists` says yes) is `.refused` with the conflicting
  name **in the reason string** (R-07's "shown to the user" starts here);
- two items in one batch that would land on the same name is `.refused` even though `exists` says
  no for both;
- `inverse(of:)` swaps `from`/`to` per move and preserves order, so applying it to a plan's own
  output yields the identity (R-11's undo half, exercised for real in Task 3).

**Code step.** Implement the five rules in `plan`, in the order §D6 lists them, and `inverse`.
Foundation only; no `FileManager`, no SwiftUI, no AppKit. **Do not add this file to
`sharedSources`.**

- Budget: `Sources/Vault/VaultMoveBatch.swift`, `Tests/VaultMoveBatchTests.swift` (~260 lines)

---

### Task 2 — A board and a folder can move, and the cards that pointed inside them still point at them (R-01, R-02, R-05, R-06, R-07, R-08, R-14)

**Test step (owns the interface).** Append to the two existing suites — `Tests/BoardFileOperationsTests.swift`
and `Tests/FolderFileOperationTests.swift` — under a new `// MARK: - ADR-0026 …` section, adding
the plan's header pair beside the existing ADR-0022/0025 lines rather than replacing them. Declare,
with placeholder bodies:

```swift
// BoardFileOperations
struct MovePlan { var newPath: String; var boardChanges: [NoteFileOperations.FileChange] = []; var failures: [String] = [] }
struct MoveOutcome { var newPath: String; var rewrittenPaths: [String] = []; var failures: [String] = [] }
func movePlan(_ relativePath: String, toFolder folder: String) throws -> MovePlan
func moveBoard(at relativePath: String, toFolder folder: String) throws -> MoveOutcome

// FolderFileOperations
struct MovePlan { var newPath: String; var boardChanges: [NoteFileOperations.FileChange] = []; var failures: [String] = [] }
struct MoveOutcome { var newPath: String; var movedNotes: [(old: String, new: String)] = []
                     var rewrittenPaths: [String] = []; var failures: [String] = [] }
func movePlan(_ relativePath: String, toParent parent: String) throws -> MovePlan
func moveFolder(at relativePath: String, toParent parent: String) throws -> MoveOutcome
// + OperationError.wouldNest(String), with its arm in the existing `description` switch (:28-35)
```

Tests, over the `~Copyable` temp-vault fixtures both files already have:

- moving `A/x.canvas` to `B` puts the file at `B/x.canvas` and leaves the **file name** untouched
  (R-01);
- a `^[[x.canvas]]` marker in a note is **byte-identical** after the move, and
  `WorkspaceBoardResolver.resolve("x.canvas", in: allBoards())` returns the same case before and
  after (R-08) — this is the test that proves ADR-0022 §D4's guard is never reached by a move;
- a card on `root.canvas` whose node is `.file(path: "A/x.canvas")` reads `B/x.canvas` afterwards
  (the SPEC's omission — ADR-0026 §D7);
- moving folder `A` (holding `A/n.md`, `A/x.canvas`, `A/sub/`) into `B` moves all of it, reports
  `movedNotes == [("A/n.md", "B/A/n.md")]`, and repoints a card pointing at `A/n.md` **and** a card
  pointing at `A/sub/y.canvas` by prefix (R-02);
- a board *inside* the moved folder that is itself a card on another board is repointed, and the
  board file that moved is written at its **new** path, not its old one (`repointBoardsPlan`'s
  `writePath`, `:209`);
- a collision at the destination throws `.alreadyExists` and **nothing on disk changed** — assert
  the source is still there (R-07);
- a folder into itself and into its own descendant throws `.wouldNest`, nothing changed (R-06);
- a move whose destination equals the current folder returns the unchanged path and writes nothing;
- moving to the vault root (`""`) works for both (R-05);
- `movePlan` writes nothing at all: call it, then assert the source is present and the destination
  is absent.

**Code step.** Both follow `renameBoard` / `renameFolder` exactly: plan first (validate, collide,
`wouldNest`, then `repointBoardsPlan(from:to:)`), then `FileManager.moveItem` with
`createDirectory(withIntermediateDirectories:)` on the parent, then the planned board writes as
bytes (`Data(change.after.utf8).write(..., options: .atomic)` — a `.canvas` is not a note).
`moveFolder` reads `walk(oldFolder).notePaths` **before** the move, as `renameFolder:264` does.
Neither file gains a `sharedSources` entry.

- Budget: `Sources/Vault/BoardFileOperations.swift`, `Sources/Vault/FolderFileOperations.swift`,
  `Tests/BoardFileOperationsTests.swift`, `Tests/FolderFileOperationTests.swift` (~420 lines)

---

### Task 3 — One move verb for three kinds of thing, one undo step for the whole batch (R-01, R-02, R-03, R-04, R-05, R-12, R-13)

**Test step (owns the interface).** New `Tests/VaultMoveTests.swift`, plus additions to
`Tests/WorkspaceFolderNavigationTests.swift`. Declares:

```swift
// Sources/Vault/VaultSession+Move.swift  (NOT in sharedSources)
extension VaultSession {
    struct MoveBatchOutcome { var moves: [VaultMove] = []; var movedNotes: [(old: String, new: String)] = []
                              var refusals: [String] = [] }
    func moveItems(_ items: [VaultItemRef], into destination: String) throws -> MoveBatchOutcome
}
// Sources/Vault/VaultController+Move.swift
extension VaultController {
    @discardableResult
    func moveItems(_ items: [VaultItemRef], into destination: String, undo: UndoManager?) -> Bool
}
// Sources/Features/Workspace/WorkspaceFolderActions.swift
static func boardAfterMove(open: String, moves: [VaultMove]) -> String
```

Tests:

- `boardAfterMove` — pure, beside the four rules already in `WorkspaceFolderNavigationTests`: the
  open board is a moved item (exact substitution); it sits inside a moved folder (prefix
  substitution, `"\(from)/"` never `from`); it is unrelated (unchanged); the batch is empty
  (unchanged) (R-13);
- `moveItems` with a note dispatches to the **existing** journalled path — assert a `WriteJournal`
  entry exists for it afterwards, which is what proves Task 3 did not reimplement `moveNote`
  (R-03);
- `moveItems` with a folder and a board in one call moves both and returns both in `moves` (R-01,
  R-02, R-04);
- a batch where one item collides commits **nothing** — assert every source is still where it was
  and `refusals` names the conflict (ADR-0026 §D6, all-or-nothing);
- **undo:** construct an `UndoManager`, call `moveItems(..., undo: manager)`, `#expect(manager
  .canUndo)`, call `manager.undo()`, assert every file is back at its original path in one step;
  then `#expect(manager.canRedo)`, `manager.redo()`, assert they are moved again (R-12). This is
  the requirement's real coverage — do not defer it to the UI suite;
- **undo whose target has moved on:** move, then rename the moved file out from under it, then
  `manager.undo()` — assert nothing is written, a problem is recorded, and `manager.canRedo` is
  **false** (ADR-0026 §D8, the SPEC's edge case);
- `undo: nil` still performs the move and records one problem line.

**Code step.** `VaultSession.moveItems` asks `VaultMoveBatch.plan` (with `exists` bound to
`FileManager` over `store.root`), refuses whole on `.refused`, then dispatches per item —
`moveNote` for `.note` (journalled, star-carrying), `boardOperations.moveBoard` for `.board`,
`folderOperations.moveFolder` for `.folder` — and carries stars for a folder's `movedNotes` exactly
as `renameFolder` does (`VaultSession+Folders.swift:29-31`).

`VaultController.moveItems` adds the three window-shaped things `VaultController+Folders` already
adds: `canOperate(on:)` / `canOperateOnFolder(_:)` before anything touches disk, `movedNote(from:to:)`
for every moved note, `Task { await rescan() }` after. Then it registers **one** block on `undo`:

```swift
undo?.setActionName("Sposta")
undo?.registerUndo(withTarget: self) { controller in
    controller.moveInverse(VaultMoveBatch.inverse(of: outcome.moves), undo: undo)
}
```

`moveInverse` performs the inverse batch and, only if it fully succeeded, re-registers the forward
batch — that recursion is the redo, and there is no custom redo code (ADR-0026 §D8). The block form
of `registerUndo` retains its target, which is why the target is the long-lived `VaultController`
and never a view.

- Budget: `Sources/Vault/VaultSession+Move.swift`, `Sources/Vault/VaultController+Move.swift`,
  `Sources/Features/Workspace/WorkspaceFolderActions.swift`, `Tests/VaultMoveTests.swift`,
  `Tests/WorkspaceFolderNavigationTests.swift` (~430 lines)

---

### Task 4 — One dragged item, two representations, and the editor's note-title drop still works (R-01, R-03, R-09)

**Test step (owns the interface).** New `Tests/VaultItemDragTests.swift`. Declares
`Sources/App/VaultItemDrag.swift`:

```swift
extension UTType { static let pergamenumVaultItem = UTType(exportedAs: "it.stefer.pergamenum.vault-item", conformingTo: .data) }
struct VaultItemDrag: Codable, Transferable, Equatable {
    let items: [VaultItemRef]   // the whole effective drag set (ADR-0026 §D4)
    let dragName: String        // the note's title / the row's name — the §7.2 payload
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .pergamenumVaultItem)
        ProxyRepresentation(exporting: \.dragName)
    }
}
```

Tests: JSON round-trip through `Codable` preserves paths, kinds and order; `dragName` for a note
built from a `NoteRecord` **equals `record.title`** — the assertion that pins SPEC §7.2's contract
and would fail the day somebody "simplifies" the payload; a set of three items round-trips as
three; `VaultItemRef` is `Hashable` so it can key the drop handlers' state.

**Code step.** Write the type. Add to `Project.swift`'s app-target `infoPlist` (`:118-135`):

```
"UTExportedTypeDeclarations": [[
    "UTTypeIdentifier": "it.stefer.pergamenum.vault-item",
    "UTTypeDescription": "Pergamenum vault item",
    "UTTypeConformsTo": ["public.data"],
    "UTTypeTagSpecification": [:],
]]
```

Then `tuist generate --no-open`, one app build, and **one build each of `-scheme perg` and
`-scheme pergamenum-mcp`** to confirm `sharedSources` is untouched. Verify at runtime, once, that
`UTType.pergamenumVaultItem.identifier` reads back the declared string rather than a dynamically
synthesized `dyn.` identifier — that is what says the Info.plist entry actually landed.

- Budget: `Sources/App/VaultItemDrag.swift`, `Project.swift`, `Tests/VaultItemDragTests.swift`
  (~180 lines)

---

### Task 5 — The Workspace tree: several rows chosen, one dragged, one folder lit (R-01, R-02, R-05, R-06, R-07, R-10, R-11, R-13)

**Test step (owns the interface).** New `Tests/WorkspaceMultiSelectionTests.swift` and additions to
`Tests/WorkspaceBrowserToolbarTests.swift`. The two rules that decide everything are extracted as
`nonisolated static` functions on `WorkspaceBrowser`, beside `selection(for:)`, `rows(matching:in:)`
and `identifier(for:)` — **and `nonisolated` is load-bearing**, for the reason
`WorkspaceBrowser.swift:543-550` spells out (a `@MainActor` static passing a closure to `compactMap`
traps `dispatch_assert_queue` and kills the whole test process):

```swift
nonisolated static func opening(from old: Set<String>, to new: Set<String>, currently: WorkspaceSelection?,
                               in tree: [WorkspaceTree.Node]) -> WorkspaceSelection??
nonisolated static func canDrop(_ dragging: [VaultItemRef], onFolder folder: String) -> Bool
```

`opening` returns the double optional deliberately: `.none` means "leave the open value alone"
(two or more selected), `.some(nil)` means "deselect", `.some(.some(x))` means "open x". Tests
cover the four rows of ADR-0026 §D4's table exactly, plus: selecting two rows leaves the open board
open (R-10), and `canDrop` refuses the dragged folder itself and its descendants and accepts a
sibling (R-06).

**Code step.** In `WorkspaceBrowser.swift`:

1. `treeSelection` becomes `Binding<Set<String>>` over a new `@State private var selectedRows:
   Set<String>`, kept in sync from the prop with `.onChange(of: selection) { _, new in selectedRows
   = new.map { [$0.path] } ?? [] }`; its setter applies `opening(...)` and calls `onSelect` only
   when the rule says so. The stale-selection drop in `rebuild()` (`:477-479`) also prunes
   `selectedRows` of ids no row carries.
2. `WorkspaceRow.content` gains, **before** `taggedRow`'s `.tag` (which stays last, `:733-735`):
   `.draggable { beginDrag() }` — the closure computes the effective set (`multiSelection.contains(
   node.id) ? multiSelection : [node.id]`), stores it in the browser's `@State dragging`, and
   returns the `VaultItemDrag`; and, on folder rows only, `.dropDestination(for: VaultItemDrag.self)`
   whose `isTargeted` sets a highlight **only when `canDrop`** and whose `action` calls
   `actions.move(...)` and returns `false` for a refused target.
3. The highlight is `RoundedRectangle(...).stroke(theme.color(.accentPrimary), lineWidth: 1)` as an
   `.overlay`, the shape `TaskDropTarget` (`TaskDrag.swift:69-72`) already uses. No new colour.
4. `folderTree` and `flatList` (`:398-436`) each gain a `.dropDestination` on the `List` itself for
   the root area (R-05).
5. A collision refusal raises a `.alert` naming every conflict, identifier
   `sidebar-move-conflict`, its OK button `sidebar-move-conflict-ok` (R-07).
6. `WorkspaceRow.menu` (`:877-888`) gains `Menu("Sposta in")` with «(radice)» plus every folder
   from the browser's own `folders` state (which is `CanvasStore.allFolders()`, `:461` — **not**
   `vault.folders`, which omits board-only folders), each entry `.disabled` for the row's current
   parent and for a folder that is the row or its descendant. Identifier `workspace-move-menu`.
7. `WorkspaceView+FolderVerbs.folderActions` gains `move:`, routed through the same
   **`flushBoard()`-first** bracket as `performBoardVerb` (`:180-199`) and landing through
   `boardAfterMove` (R-13). Passing `@Environment(\.undoManager)` down from `WorkspaceView` is part
   of this step.

**Not testable by unit test, verified by hand at Task 8:** that Cmd-click and Shift-click actually
extend the set in a live window, and that the drag begins at all. Both are on the manual list.

- Budget: `Sources/Features/Workspace/WorkspaceBrowser.swift`,
  `Sources/Features/Workspace/WorkspaceView+FolderVerbs.swift`,
  `Sources/Features/Workspace/WorkspaceView.swift`,
  `Tests/WorkspaceMultiSelectionTests.swift` (~520 lines)

---

### Task 6 — The Note tree: the same three things, and the editor's drop untouched (R-03, R-04, R-05, R-09, R-10, R-11)

**Test step (owns the interface).** Additions to `Tests/NoteTreeTests.swift` (or a new
`Tests/NoteListSelectionTests.swift` if the file has grown past the SwiftLint warning) for the
Note pane's own collapse rule, extracted as a `nonisolated static` on `NoteListPane` with the same
signature shape as Task 5's `opening` — including the two behaviours the current binding's comment
(`:216-220`) says are not cosmetic: nothing is selected while the composer is up, and re-selecting
the note underneath calls `leaveComposer()` rather than re-reading the note and discarding unsaved
text.

**Code step.** In `NoteListPane.swift`:

1. `selectedPath` becomes `Binding<Set<String>>` over `@State private var selectedRows`, synced by
   `.onChange(of: vault.openNote?.relativePath)` (the pane already has one at `:49`) **and**
   `.onChange(of: vault.isOpenNoteVisible)` — the second is what preserves "nothing selected while
   the composer is up".
2. Note rows: `.tag(node.id)` moves to **last** in the chain (today it precedes `.draggable`,
   `:345-346` and `:194-197`), `.draggable` carries the `VaultItemDrag` built with `dragName ==
   the note's title`, and each row gains `.accessibilityIdentifier("note-row-\(node.id)")`.
   **Do not add `.accessibilityElement(children: .contain)`** — `NoteTreeAndShortcutsUITests
   :54-90` finds rows by their words and eight assertions depend on it.
3. Folder rows (`:291-309`) become drag sources **and** drop targets, with the same `canDrop`
   predicate and the same accent-stroke overlay. The existing `.onTapGesture { toggle() }` on the
   whole folder row stays exactly as it is: it is not inside a `List(selection:)` tag chain (folder
   rows carry no `.tag` here) and is out of scope for this chain.
4. Both `List`s gain the root-area `.dropDestination` (R-05).
5. `folderMenu` (`:324-335`) gains «Sposta in», identifier `note-move-menu`, listing `vault.folders`
   — correct here, because the Note tree is built from note paths and shows no folder that
   `vault.folders` omits.
6. The drop calls `vault.moveItems(..., undo: undoManager)` with `@Environment(\.undoManager)`.

**After this task, run `UITests/NoteTreeAndShortcutsUITests.swift` alone** (`scripts/uitests.sh
NoteTreeAndShortcutsUITests` — one argument **replaces** the selection, which is what is wanted
here) before moving on. It is the file most likely to be broken by an accessibility change, and
finding that out at Task 8 costs the whole suite's twelve minutes to diagnose.

- Budget: `Sources/Features/Editor/NoteListPane.swift`, `Sources/Features/Editor/NoteRowMenu.swift`,
  `Tests/NoteListSelectionTests.swift` (~380 lines)

---

### Task 7 — The UI suite: the menu path always, the drag path if XCUITest can synthesize one (R-01, R-02, R-03, R-04, R-05, R-06, R-07, R-10, R-11, R-12, R-15)

**Spike first, and record the answer in this file before writing the rest of the task.** No test in
this repository has ever driven a `.draggable` → `.dropDestination` pasteboard drag: every existing
drag test (`DayViewUITests:166`, `WorkspaceBoardUITests:65-167`, `DiaryUITests:174`) drives a
`DragGesture`, which is a different machine. Write one throwaway test that does
`row.press(forDuration: 0.4, thenDragTo: folderRow)` in the Workspace tree and asserts the file
moved. Run it five times.

- **If it passes five out of five:** write the four drag tests R-15 names — single-row board drag,
  folder drag, multi-row drag, undo of a move.
- **If it does not:** do **not** loosen an assertion, add a retry loop, or mark anything as
  expected-to-fail. Write the drag tests anyway against the same helper, keep whichever ones are
  stable, and record the outcome in a new `## Findings` section at the bottom of this plan naming
  the exact failure. R-15's drag half then becomes a manual-verification item in Task 8 and the
  operator is told at the gate. That is a reported gap, not a silent one.

**Always, spike outcome notwithstanding.** New `UITests/SidebarMoveUITests.swift`, XCTest, header
naming ADR-0026 and this plan's basename, launched with the three arguments every file in this
suite uses — `-recentVaults '("…")'` in the plist array form, `-disableCalendar YES` (**every**
file passes it, `CLAUDE.md`), `-stateBase …` — and every element found by
`accessibilityIdentifier`, never by the words on it:

- «Sposta in ▸ B» on a board row moves the file and the tree shows it under `B` with no manual
  rescan (R-01);
- the same for a folder row (R-02) and for a note row and a Note-sidebar folder row (R-03, R-04);
- «Sposta in ▸ (radice)» moves to the vault root (R-05);
- a folder's own «Sposta in» menu does not offer itself or its descendants (R-06);
- a move into a folder that already holds the name raises the `sidebar-move-conflict` alert, and
  after dismissing it the file is still where it was (R-07);
- Cmd-click on a second row lights it while the open board's row stays lit and the board stays on
  screen (R-10) — `XCUIElement.click(forDuration:thenDragTo:)` is not needed; use
  `XCUIElement.click()` with `XCUIElement.perform(withKeyModifiers: .command) { … }`;
- a menu move performed with two rows selected moves both (R-11);
- Cmd+Z after a move restores both in one step, Cmd+Shift+Z reapplies (R-12).

- Budget: `UITests/SidebarMoveUITests.swift` (~450 lines)

---

### Task 8 — The full suite, the documentation, and the four things only a person can check (R-12, R-13, R-15)

1. **`.claude/test-cmd` green**, whole `PergamenumTests` bundle, not only the new files.
2. **`scripts/uitests.sh` with no arguments**, the whole bundle, once — the price of `test-cmd`
   being restricted to `-only-testing:PergamenumTests` (`CLAUDE.md`, `PG-033`). Read the seconds
   printed beside any failure before calling it a defect: a launch timeout is not one.
3. **Both connector builds** (`-scheme perg`, `-scheme pergamenum-mcp`) — the mechanical proof that
   nothing this chain added leaked into `sharedSources`.
4. **Manual verification, on a throwaway vault**, launched per `CLAUDE.md`'s recipe (`ls -dt
   .../Pergamenum-*/Build/Products/Debug/Pergamenum.app | head -1`, then `open -n … --args
   -recentVaults '("/path")'` — `open -n`, never `nohup … &`, which dies when the Bash call
   returns). Four items, and the first two are the ones this chain is least sure about:
   - Cmd+Z after typing in the editor and then again — the first undo is the typing, the second is
     the move. Confirm that reads as coherent rather than alarming (ADR-0026 §D8's admitted
     negative consequence, and the trigger for reconsidering alternative A6) (R-12).
   - A real mouse drag of a board row onto a folder row, and of a row onto the blank area below the
     last row (R-05's list-level destination is the one part of the design asserted by hand).
   - Dragging the row of the **open** board: the board must not flicker closed and reopened
     (R-13).
   - Cmd-click and Shift-click building a selection while a board stays open (R-10).
5. **Documentation.** Add ADR-0026 to `CLAUDE.md`'s «Chain decision index» and a «Decisions from
   the …» section in the established shape (the orchestrator's Step 3 edits `CLAUDE.md`, not this
   task's coder — this task confirms the ADR file is at
   `docs/adr/0026-drag-and-drop-board-files-into-workspace.md` and that its header names what it
   supersedes in part). Add one line to `docs/20260811_Pergamenum_SpecApp.md` §10, where the note
   context-menu operations are listed, recording that a sidebar row can also be moved by dragging
   it — the SPEC is the authoritative document and a shipped gesture that is nowhere in it is the
   kind of drift `CLAUDE.md`'s first working agreement is about.
6. If the Task 7 spike went badly, make sure its `## Findings` entry is written and say so in the
   report. **Do not** close the chain claiming R-15 is met when its drag half is not.

- Budget: `CLAUDE.md`, `docs/20260811_Pergamenum_SpecApp.md`, this plan's `## Findings`
  (~90 lines)

---

## Requirement coverage

| R | Task(s) |
|---|---|
| R-01 | 2, 3, 4, 5, 7 |
| R-02 | 2, 3, 5, 7 |
| R-03 | 3, 4, 6, 7 |
| R-04 | 3, 6, 7 |
| R-05 | 1, 2, 3, 5, 6, 7 |
| R-06 | 1, 2, 5, 7 |
| R-07 | 2, 5, 7 |
| R-08 | 2 |
| R-09 | 4, 6 |
| R-10 | 5, 6, 7 |
| R-11 | 1, 5, 6, 7 |
| R-12 | 3, 7, 8 |
| R-13 | 3, 5, 8 |
| R-14 | 2, 8 |
| R-15 | 7, 8 |

TEST-CMD CANDIDATE: none
TEST-CMD MODE: brownfield

`.claude/test-cmd` is already the trusted command for this project and is not re-proposed here:
`xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS'
-derivedDataPath "…/.build/DerivedData" -only-testing:PergamenumTests test`. The UI half runs
through `scripts/uitests.sh`, deliberately and by hand, at Task 8.

## Findings

**Task 8's manual R-12 check crashed the app, and the fix landed outside the Task 6/7 budget.**
Typing in a note, switching to the Workspace pane, dragging the open board's own row into a
folder, then pressing Cmd+Z twice: the first undo reverted the move, the second crashed with
`EXC_BAD_ACCESS` (SIGSEGV) in `-[_NSUndoStack popAndInvoke]`
(`~/Library/Logs/DiagnosticReports/Pergamenum-2026-08-28-140518.ips`).

Root cause: §D8's window-scoped `undoManager` is shared with `NoteTextView`'s typing undo, and
the Note/Workspace pane switch is a full SwiftUI rebuild (`RootView.swift`'s `switch pane`), not
a hide - it deallocates the `NSTextView` while its typing-undo action is still registered on
that shared stack. The second Cmd+Z then invoked an action targeting a dangling pointer. This is
worse than the "surprising but coherent" risk §D8's Negative Consequences already named and A6
was kept in reserve for - it is a crash, not a UX surprise.

Fix (not a reopening of A6): `NoteTextView` gained a `dismantleNSView` that purges every action
still targeting the text view or its text storage from the window's `undoManager` before SwiftUI
releases it. The window-scoped design of §D8 is unchanged; a pane switch now silently drops the
now-unreachable typing-undo step instead of leaving a dangling target on the stack. Reverified:
same repro sequence, no crash, second Cmd+Z is a no-op (the typing step was discarded on pane
switch), full unit suite and full UI suite green afterwards.

Files touched beyond the plan's own budget: `Sources/Features/Editor/NoteTextView.swift`,
`Sources/Features/Editor/NoteTextView+Coordinator.swift` (~20 lines).
