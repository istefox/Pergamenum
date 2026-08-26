# Plan — Workspace board tree: one selection, one row, one meaning

- **SPEC:** `/Users/stefer/Developer/Pergamenum/SPEC.md` (R-01 … R-16).
- **ADR:** `ADR-0024: One selection, one row, one meaning`, currently at
  `/Users/stefer/Developer/Pergamenum/docs/architecture/ADR-0024-workspace-board-tree-single-selection.md`,
  **to be moved by the operator to
  `/Users/stefer/Developer/Pergamenum/docs/adr/0024-workspace-board-tree-single-selection.md`**
  before Task 1 (this project's ADRs all live under `docs/adr/`; the architect agent's write scope
  forbids that directory). Every reference below is to **ADR-0024** by name, never by path, so the
  move breaks nothing.
- **Branch:** `refactor/adr-0024-workspace-single-selection`
- **Base:** `5041d5c`. Every line number quoted below was read at that commit.
- **Style:** TDD. Every task writes its failing test first, then the code that makes it pass.
  Swift Testing (`#expect`, `#require`), never XCTest, for everything new in `Tests/`; XCTest in
  `UITests/`, matching the suite that is already there.
- **Swift is compiled, so "red" has a precondition.** A task's test step must add the new type and
  signature declarations *together with* the failing tests — placeholder bodies returning `nil` /
  `[]` / the unchanged input — so the target **builds** and the tests fail on their assertions. A
  batch that leaves `Pergamenum` unable to compile produces no red tests at all, only a build error.
  Never `fatalError()` and never a force-unwrap as a placeholder (`~/.claude/rules/swift.md`).
  **This plan has a second, sharper form of that rule:** three tasks *remove* a member other files
  read (`hasOpenBoard`, `closeBoard()`, `WorkspaceBrowser`'s parameters). A removal has no
  placeholder. Each such task therefore carries its call-site updates **in the same batch**, and the
  contract table below says which ones.
- **Harness:** this plan creates **no new harness script**, the same decision the three preceding
  Workspace plans made. Verification is the two commands this project already trusts:
  `.claude/test-cmd` after every task, and `scripts/uitests.sh` once, at Task 7, before the merge to
  `main` (`CLAUDE.md`, working agreements — the UI suite is outside `test-cmd` on purpose and its
  state is unknown between deliberate runs, `PG-033`).
  **Every new or rewritten test file's header comment must name `ADR-0024` and this plan's basename
  `2026-08-25-workspace-board-tree-single-selection`** — that citation is the only link this
  repository keeps between a test and the decision that asked for it, and it is the anchor the
  coverage report reads.
- **After any task that adds a file:** `tuist generate --no-open`. The generated project lists files
  and does not regenerate itself; a build that fails naming the compiler rather than the missing
  file is the documented failure mode. Tasks 1 and 6 add files.
- **`Sources/Core/**` must not import SwiftUI or AppKit** (ADR-0001 §D1, enforced by the `perg` and
  `pergamenum-mcp` builds). This plan adds nothing to `Sources/Core/**`.
- **`Project.swift` needs no edit and `sharedSources` gains nothing.** The app target is `Sources/**`
  minus `Sources/CLI/**` and `Sources/MCPServer/**` (`Project.swift:139-141`), so the two new files
  under `Sources/Features/Workspace/` enter it automatically. The Workspace sidebar is not a
  connector capability (ADR-0022 §D6); do not add either file to `sharedSources`
  (`Project.swift:72-106`).
- **Known false positives, ignore them:** the pre-commit `weakening-scan.sh` reports every Swift
  Testing test as `zero-assertion-test` (its body scanner treats a line starting with `#` as a
  comment and `#expect(...)` starts with one); the secret scanner's `assigned-secret` rule fires on
  design-token lines. Both documented in `CLAUDE.md`. Do not restructure code to appease either; do
  still read the diff.
- **The design-token rule is load-bearing in this feature.** «A view that uses a colour or a font
  without going through a token does not pass review» (`CLAUDE.md`). Every colour this plan *removes*
  goes to the system's own row-fill highlight; no task may replace one hardcoded condition with
  another hardcoded colour.

---

## Five things the SPEC says about this repository that are false or under-determined

Read at `5041d5c`, before this plan was written. Do not rediscover them, and do not follow the
SPEC's wording where it contradicts them.

| SPEC says | Truth | Consequence for this plan |
|---|---|---|
| Decision 7 and R-10: *"The vault already saves which board was open and reopens it at launch"*, and R-10's *"no regression from the persistence behavior shipped in commit `5041d5c`"* | **No such persistence exists.** `VaultSettings` (`Sources/Vault/VaultSettings.swift`) carries `boardShowsGrid` and `boardSnapsToGrid` and no board path of any kind; `WorkspaceController.attach` calls `open(folder: "", markOpen: false)` (`WorkspaceController.swift:133`) — loaded, not chosen. `5041d5c` shipped the **opposite** ("no board open until chosen") and its own UI test is named `testLeavingAndReturningToTheWorkspacePaneForgetsTheOpenBoard`. | **Add no persistence** (ADR-0024 A7). R-10 is satisfied as: the pane still opens with nothing selected after `attach`, and a board opened from a source outside the tree (route, breadcrumb, folder card, editor hand-off) lights exactly its own row. Task 2 pins the first half as a unit test, Task 6 the second half in the UI suite. Do not delete or weaken `testLeavingAndReturningToTheWorkspacePaneForgetsTheOpenBoard`; port it. |
| R-05: *"Clicking a board-less folder's name/row **only** expands or collapses it"* | Cannot be read literally beside Decision 3 (*"Its row can still be selected … without opening anything"*) and flow 2 (*"The clicked folder's row lights up"*) and flow 3 (*"Click a board-less folder's disclosure triangle … does not change selection"*). Three statements, not all true together. | Resolved by ADR-0024 §D5, which is ADR-0022 §D9's existing split kept: **the chevron toggles expansion, the rest of the row selects.** R-05's operative content is its second clause — no board is opened, no creation prompt appears. Assert *that*, never "the row does not light". |
| Architecture: *"Replace the hand-rolled `List` (`:191`, no `selection:`)"* | The `List` is at `WorkspaceBrowser.swift:195`; `:191` is a `// MARK: Rows` comment. Every other line reference in the SPEC checks out (`:131-135`, `:365-373`, `:419-437`, `:379`, `:439`, `NoteListPane.swift:156`, `:221-232`, `:290-309`). | Cosmetic. Noted so the coder does not think the file moved under them. |
| R-07: click-blank-space-to-deselect *"using `List(selection:)`'s native behavior"* | **Unverified in this repository.** Nothing here exercises it: `NoteListPane` never deselects, `RootView`'s sidebar has no empty area, and the `.onTapGesture` being removed (`WorkspaceBrowser.swift:212, 244`) was written when the list had **no** selection binding at all — its own comment says so. | Implement as written (no hand-rolled gesture). **Verify by hand at Task 7.** If it does not fire, restore exactly one `.onTapGesture { onSelect(nil) }` on the `List`, with a comment recording the finding — the fallback ADR-0024 A9 names, with a trigger, not a hedge. Do not decide this from memory of SwiftUI behaviour either way. |
| R-13: VoiceOver distinguishes a selected row *"through its accessibility label or trait"* | The **label** half is fully under our control and testable. Whether `.accessibilityAddTraits(.isSelected)` on custom `List` row content reaches XCUITest's `isSelected` on macOS is **unverified here**. | Do both (ADR-0024 §D9), but make the **label suffix** the thing any assertion depends on. The trait is belt-and-braces and must never be the sole carrier of R-13. |

**A sixth item, not false but easy to misread:** the SPEC's reference model is `NoteListPane`, and it
is a reference for its **row structure** as much as for its binding. Its folder rows are flat
recursive rows with manual indent (`NoteListPane.swift:290-322`), **not** `DisclosureGroup`s. Copying
the binding without copying the structure produces a binding no row can satisfy — see ADR-0024 §D1
and the twenty-minute silent failure recorded at `RootView.swift:205-208`.

---

## Contract changes, and the call sites already grepped

Grepped at `5041d5c` across `Sources/`, `Tests/` and `UITests/`. **A removal has no placeholder:
each row's call sites are updated in the same task that makes the change**, or the target does not
build and the task produces no red.

| Change | Call sites (grepped) | Task |
|---|---|---|
| `WorkspaceController.hasOpenBoard` (stored) **removed** → `isShowingBoard` (computed) | `WorkspaceView.swift:77, 131, 167, 235, 258`; internal writes at `WorkspaceController.swift:80, 148, 176, 201`; `Tests/WorkspaceOpenStateTests.swift:5, 22, 31, 41` | **Task 2** (all of them, one batch) |
| `WorkspaceController.closeBoard()` **removed** → `select(nil)` | `WorkspaceView.swift:69` — the only one, inside the `onDeselect:` closure | **Task 2** |
| `WorkspaceController.open(folder:markOpen:)` → `open(folder:)` | Only `WorkspaceController.swift:133` (`attach`) ever passed `markOpen:`. The other nine callers use the default and are **unaffected**: `BoardChrome.swift:28`, `BoardCardMenu.swift:118`, `WorkspaceController+Viewport.swift:81`, `WorkspaceView.swift:67, 131, 219, 248, 264`, `Tests/CanvasTests.swift:359, 374, 379, 758`, `Tests/WorkspaceOpenStateTests.swift:30, 39` | **Task 2** |
| `WorkspaceController.breadcrumb` derives from `current?.folder`, not `folder` | `BoardChrome.swift:24, 32`; `Tests/CanvasTests.swift:357, 360, 361` — **these three assertions pass unchanged** (nil after `attach` → `["Workspace"]`; `.board(F)` after `open(folder: F)` → the same trail `folder` gave) | **Task 2** writes it, **Task 5** consumes it |
| `WorkspaceBrowser(openBoardPath:actions:onOpen:onDeselect:)` → `(selectedFolder:actions:onSelect:)` | `WorkspaceView.swift:63` — **the only one**. `grep -rn "WorkspaceBrowser(" Sources Tests UITests` returns one line. | **Task 3** |
| `WorkspaceView.openBoardPath` (private computed) **deleted** | `WorkspaceView.swift:64` (its only reader) and `:166-169` (its definition) | **Task 3** |
| `WorkspaceBrowser.selectedFolder` (`@State`) **deleted** | `WorkspaceBrowser.swift:42, 132, 200, 212, 234, 244, 261, 262`; `WorkspaceTreeRow.selected` binding at `:322, 358, 369, 377, 407, 412, 425` — all inside the one file | **Task 3** |
| Tree rows stop being `Button`s (ADR-0024 §D1, §D2) — element type changes | `UITests/WorkspaceIntegrationUITests.swift:155` uses `descendants(matching: .any).matching(identifier:)` → **survives**. `UITests/WorkspaceOpenStateUITests.swift:39` uses `app.buttons["workspace-board-…"]` → **breaks**, and is rewritten by R-14 in the same feature. | **Task 6** |
| AX identifier `workspace-folder-<path>` disappears from a folder that **owns** a board (merged into one row) | `grep -rn "workspace-folder-" Tests UITests` → **zero call sites**. | none |
| AX identifiers `workspace-board-<boardPath>`, `workspace-filter`, `workspace-tree`, `workspace-flat-list`, `workspace-browser-header`, `workspace-browser-toolbar`, `workspace-new/rename/delete/expand-all/collapse-all`, `workspace-delete-confirm` — **all preserved byte-identical** | `workspace-board-*`: `UITests/WorkspaceIntegrationUITests.swift:155`, `UITests/WorkspaceOpenStateUITests.swift:39`. `workspace-filter`: `WorkspaceIntegrationUITests.swift:150`, `WorkspaceOpenStateUITests.swift:27` | preserve — a task that renames one is a task that went wrong |
| `WorkspaceBrowserToolbar` — **signature unchanged**, `canMutate(folder:)` unchanged | `WorkspaceBrowser.swift:117-126`; `Tests/WorkspaceBrowserToolbarTests.swift` | none — only what is passed as `target:` changes (Task 4) |
| `WorkspaceFolderActions` — **unchanged**, both static rules unchanged | `WorkspaceView.swift:196-202, 241, 260`; `Tests/WorkspaceFolderNavigationTests.swift` | none |
| `CanvasStore`, `CanvasDocument`, `NoteTree`, `IndexCache.schemaVersion` — **unchanged** | `IndexCache.swift:schemaVersion` is a declared protected interface (`.claude/protected-interfaces`) | none — a diff touching it in this chain is a design error |

**Full-suite rule.** Tasks 2, 3 and 5 change contracts other modules observe (the controller's public
surface, the browser's initializer, the breadcrumb). Run the whole `PergamenumTests` bundle after
each of them — `.claude/test-cmd` already does exactly that — never just the new file's tests. A
selection model touched by five files is exactly the shape that breaks a test in a module nobody
was looking at.

---

### Task 1 — The two pure types: `WorkspaceSelection` and the merged tree (R-01, R-03, R-05)

Nothing in this task imports SwiftUI, and that is the point: everything the feature *decides* is
decided here, where a test can ask it without a view.

**RED.** New `Tests/WorkspaceTreeTests.swift` (header names ADR-0024 and this plan's basename), plus
the two declarations so the target builds:

- `WorkspaceSelection.folder` returns the folder path for both cases; `.hasBoard` is true only for
  `.board`. Two lines of test, and they are the contract every later task reads.
- `WorkspaceTree.build(boards:boardPath:)` **folds a folder and the board named after it into one
  node** (R-01). Fixture:
  `["Labs.canvas", "01 Progetti/01 Progetti.canvas", "01 Progetti/a/a.canvas", "01 Progetti/b/b.canvas", "01 Progetti/b/altro.canvas", "Vuota/dentro/dentro.canvas"]`
  with `boardPath` stubbed as the real rule (`"" → "Labs.canvas"`, otherwise
  `"\(f)/\(f.lastComponent).canvas"`). Assert:
  - the top level is `["01 Progetti", "Vuota", ""]` by `id` — folders first then leaves, `NoteTree`'s
    own order, and **the root board is the row for folder `""`** with `name == "Labs"` (F7 of
    ADR-0024: `NoteTree` emits no root node, so this transform synthesises it);
  - `"01 Progetti"` is `.workspace(board: "01 Progetti/01 Progetti.canvas")` and its children are
    `["01 Progetti/a", "01 Progetti/b"]` — **no `01 Progetti/01 Progetti.canvas` row among them**;
  - `"Vuota"` is `.workspace(board: nil)` with one child `"Vuota/dentro"` — a board-less folder is a
    node, not an omission (R-05, Decision 3);
  - `"01 Progetti/b"`'s children are exactly one `.foreignBoard("01 Progetti/b/altro.canvas")` —
    a `.canvas` not named after its folder survives as a node of its own (ADR-0024 §D3);
  - `boardCount` on `"01 Progetti"` is 4, carried through from `NoteTree.Node.noteCount` unchanged.
- `WorkspaceTree.folders(in:)` returns every `.workspace` id **including `""`**, and no
  `.foreignBoard` path. This is what Task 4's stale-selection drop asks, and `""` is the case that
  makes the naive `allFolders(in:)` wrong for the new model.
- `WorkspaceTree.flattened(_:)` returns every node depth-first with its depth, root row included —
  the filtered list's input (R-09).
- `WorkspaceTree.node(withID:in:)` finds `""`, a nested folder, and returns nil for a
  `.foreignBoard` path — the setter's lookup in Task 3.

**GREEN.** Two new files:

- `Sources/Features/Workspace/WorkspaceSelection.swift` — `enum WorkspaceSelection: Equatable,
  Sendable { case board(folder: String); case folder(String) }` with `var folder: String` and
  `var hasBoard: Bool`. Its doc comment states ADR-0024 §D4's rule: this is the *only* value that
  says which row is lit **and** whether a board is drawn, and anything that reads one of those two
  facts reads this.
- `Sources/Features/Workspace/WorkspaceTree.swift` — `enum WorkspaceTree` with `struct Node`
  (`id`, `name`, `kind`, `children`, `boardCount`), `enum Node.Kind { case workspace(board: String?);
  case foreignBoard(path: String) }` and the five functions above. `build` runs
  `NoteTree.build(fromPaths: boards)` and folds it; **`boardPath` is a closure so the rule is asked,
  never restated** (ADR-0024 §D2) — the caller passes `CanvasStore.boardPath(forFolder:)` itself.

Then `tuist generate --no-open`.

- Budget: `Sources/Features/Workspace/WorkspaceSelection.swift`,
  `Sources/Features/Workspace/WorkspaceTree.swift`, `Tests/WorkspaceTreeTests.swift` (~260 lines)

### Task 2 — The controller holds one optional; `hasOpenBoard` and `closeBoard()` go (R-04, R-10, R-11, R-14 unit half)

This task **removes two members five files read**, so it carries every call site with it. Nothing
here touches a view's layout; the sidebar still renders exactly as it did when this task is green.

**RED.** Rewrite `Tests/WorkspaceOpenStateTests.swift` in full (R-14, unit half) — header names
ADR-0024 and this plan's basename, and states that it replaces the `hasOpenBoard` flag's tests from
`5041d5c`. New assertions, each against `current` and never against a boolean of its own:

- `attach` leaves `current == nil` and `isShowingBoard == false`, **and** loads the root board's
  document all the same — assert `controller.folder == ""` beside it, which is what makes «loaded,
  not chosen» a two-sided claim rather than a re-spelling of the flag. (R-10, first half)
- `open(folder: "")` gives `current == .board(folder: "")` and `isShowingBoard == true`. (R-04)
- `select(.folder("Progetti"))` after a board is open: `current == .folder("Progetti")`,
  `isShowingBoard == false` — **selecting a board-less folder closes the open board** (Decision 2,
  R-04) — and `selection` (the card set) is empty afterwards.
- `select(nil)` gives `current == nil` and `isShowingBoard == false`. This is what `closeBoard()` was.
  (R-11)
- `select(.board(folder: "A"))` twice in a row, with `zoom` and `pan` changed in between, leaves
  `zoom` and `pan` **as the user left them** — the no-op guard of ADR-0024 §D4. Without it,
  ADR-0023 §D4's context menu resets the board somebody is looking at. This assertion is the whole
  reason the guard exists; do not fold it into another test.
- `detach()` gives `current == nil`.
- `breadcrumb` after `select(.folder("01 Progetti/a"))` is
  `["Workspace", "01 Progetti", "a"]` — the trail follows the **selection**, not the loaded document
  (ADR-0024 §D8.1), which is the assertion that stops defect 5 having a new equivalent.

**GREEN.** `Sources/Features/Workspace/WorkspaceController.swift`:

- add `private(set) var current: WorkspaceSelection?`; delete `private(set) var hasOpenBoard`
  (`:80`) and `func closeBoard()` (`:197-203`);
- add `var isShowingBoard: Bool { if case .board = current { true } else { false } }`;
- split the body of `open(folder:markOpen:)` (`:167-191`) into `private func load(folder:)` (endCrop,
  flushPendingSave, folder/selection/pan/zoom reset, `store.load`, `refreshContents`,
  `hasUnsavedChanges = false`, `history.reset()`) and `func open(folder:)` = `load` then
  `current = .board(folder:)`. **`markOpen:` disappears**;
- add `func select(_ new: WorkspaceSelection?)`: `guard new != current else { return }`; `.board(f)`
  → `open(folder: f)`; `.folder`/`nil` → `endCrop(confirm: true)`, `flushPendingSave()`,
  `selection = []`, `current = new` — the same leaving-a-board obligations `load` discharges
  (ADR-0020 §D5), because leaving a board for the empty state is still leaving a board;
- `attach` (`:128-134`) → `load(folder: "")` with `current = nil`;
- `detach` (`:136-150`) → `current = nil` in place of `hasOpenBoard = false`;
- `breadcrumb` (`:153-161`) walks `current?.folder ?? ""` instead of `folder`.

`Sources/Features/Workspace/WorkspaceController+Viewport.swift:81`: the route guard
`if folder != self.folder { open(folder: folder) }` becomes
`if current != .board(folder: folder) { open(folder: folder) }`. With a board-less folder selected,
`self.folder` still names the last *loaded* board, so the old comparison would decline to open the
board the link named and the route would silently do nothing.

`Sources/Features/Workspace/WorkspaceView.swift` — five call sites, no behaviour change:
`:77` and `:235` and `:258` `hasOpenBoard` → `isShowingBoard`; `:167` (inside `openBoardPath`, still
present until Task 3) → `isShowingBoard`; `:131`'s
`if !workspace.hasOpenBoard || workspace.folder != folder { workspace.open(folder: folder) }` →
`workspace.select(.board(folder: folder))`, which now guards itself; `:69`'s
`onDeselect: { workspace.closeBoard() }` → `onDeselect: { workspace.select(nil) }`.

- Budget: `Sources/Features/Workspace/WorkspaceController.swift`,
  `WorkspaceController+Viewport.swift`, `WorkspaceView.swift`, `Tests/WorkspaceOpenStateTests.swift`
  (~230 lines)

### Task 3 — One merged row, flat and recursive, inside `List(selection:)` — both lists (R-01, R-02, R-03, R-05, R-07, R-08, R-09, R-13)

The largest task, and it cannot be split: the row type, the two `List`s and the browser's parameters
are one compile unit. `WorkspaceView.swift:63` changes in the same batch.

**RED.** This is view code and mostly not unit-testable; its red lives in Task 6's UI suite. Two
things here **are** pure and get assertions in `Tests/WorkspaceTreeTests.swift`:

- `WorkspaceBrowser.rows(matching:in:)` — the filtered list's input (R-09): over the Task 1 fixture,
  filtering `"a"` returns the `.workspace` rows whose `id` **or** `name` contains it, case-insensitively,
  and the root row (whose `id` is `""`) is reachable by its **name**, which is the case a
  path-only filter loses.
- `WorkspaceBrowser.identifier(for:)` — `workspace-board-<boardPath>` for a `.workspace` with a board,
  `workspace-folder-<id>` for one without, `workspace-foreign-board-<path>` for a `.foreignBoard`.
  Pure, and the only place the three identifier spellings exist (ADR-0024 §D10). Assert the root
  row's identifier is `workspace-board-Labs.canvas` — the string
  `UITests/WorkspaceOpenStateUITests.swift:39` builds today.

Both are `static` and internal, widened the same way `WorkspaceBrowser.allFolders(in:)` already was
for `Tests/WorkspaceBrowserToolbarTests.swift` (`WorkspaceBrowser.swift:274-278`).

**GREEN.** `Sources/Features/Workspace/WorkspaceBrowser.swift`:

- **Parameters** (ADR-0024 §D6): `openBoardPath`/`onOpen`/`onDeselect` → `selectedFolder: String?`
  and `onSelect: (WorkspaceSelection?) -> Void`. Delete `@State private var selectedFolder` (`:42`).
- **The binding**, built locally because only this view holds the tree:
  ```
  get: selectedFolder
  set: nil → onSelect(nil)
       id  → onSelect(WorkspaceTree.node(withID: id, in: tree)?.board == nil
                       ? .folder(id) : .board(folder: id))
  ```
  A `.foreignBoard` is never in the tag namespace, so the lookup cannot land on one.
- **`folderTree`** (`:194-217`) and **`flatList`** (`:222-245`) both become
  `List(selection: <that binding>)`. **Delete both `.onTapGesture { selectedFolder = nil;
  onDeselect() }`** (`:212`, `:244`) — R-07, with the fallback the SPEC-claims table names if the
  hand check at Task 7 finds nothing native. `flatList` renders
  `WorkspaceTree.flattened(rows(matching: filter, in: tree))` at depth 0 — the **same row view and
  the same binding**, which is R-09 read as "not a second implementation".
- **`WorkspaceTreeRow` → `WorkspaceRow`**, `NoteTreeRow`'s shape (ADR-0024 §D1, `NoteListPane.swift:
  290-322`): a `@ViewBuilder` `body` emitting the row and then, as a **sibling**,
  `if isExpanded { ForEach(children) { WorkspaceRow(node: $0, depth: depth + 1, …) } }`. No
  `DisclosureGroup` anywhere in the file.
  - the chevron is `Image(systemName: "chevron.right").rotationEffect(.degrees(isExpanded ? 90 : 0))`
    with its **own** `.onTapGesture { toggle() }`, drawn only when the node has children, and a
    same-size clear spacer when it does not so the names line up;
  - depth is `.padding(.leading, CGFloat(depth) * Self.indent)` with `indent = 14`, `NoteTreeRow`'s
    own constant;
  - the icon is `rectangle.3.group` for a row with a board, `folder`/`folder.fill` for one without,
    `rectangle.3.group` dimmed for a `.foreignBoard`. **No icon and no text is conditioned on the
    selection any more** (R-02, and the unconditional `.accentPrimary` of `:367` goes with it): the
    icon is `.textSecondary`, the name `.textPrimary`, the count `.textTertiary`, and the system
    draws the selected row's fill;
  - the count is drawn only when the node has children, which is the set of rows that showed one
    before;
  - `.tag(node.id)` **only** on a `.workspace` node, and **last in the modifier chain** — `RootView
    .swift:205-208` records this repository's own twenty minutes lost to a modifier applied after
    `.tag` silently dropping it. A `.foreignBoard` row carries no tag and is therefore
    structurally unselectable (ADR-0024 §D3).
- **Accessibility** (R-13, ADR-0024 §D9): `.accessibilityElement(children: .combine)`,
  `.accessibilityLabel(…)` with the state spelled in words — `"Workspace \(name), aperta"` /
  `"Cartella \(name), \(count) Workspace, selezionata"` / plain when not selected — plus
  `.accessibilityAddTraits(.isSelected)` when `selectedFolder == node.id`. The **label** is what
  Task 6 asserts on; the trait is belt-and-braces (SPEC-claims table, R-13 row). A `.foreignBoard`
  row's label says it: `"Board \(name), non apribile da Pergamenum"`.
- **The context menu** stays where ADR-0023 §D2 put it — on the row's own `HStack`, gated by
  `WorkspaceBrowserToolbar.canMutate(folder: node.id)`, and its two buttons set the selection first
  (ADR-0023 §D4) through `onSelect`, then call `onRename`/`onDelete`. There is no `DisclosureGroup`
  left for it to leak out of, so §D2's conclusion now holds by construction — say so in the comment
  and delete the fifteen lines of propagation warning at `:380-397`, which no longer describe the
  code.
- `reveal(_:)` (`:269-272`) now takes a **folder** path; `NoteTree.ancestors(of:)` is already right
  for it (it drops the last component, which for a folder is the folder itself, leaving its strict
  ancestors). `.onChange(of: openBoardPath)` (`:67`) becomes `.onChange(of: selectedFolder)`.

`Sources/Features/Workspace/WorkspaceView.swift`: the one call site (`:63-70`) becomes
`WorkspaceBrowser(selectedFolder: workspace.current?.folder, actions: folderActions,
onSelect: { workspace.select($0) })`; **delete the `openBoardPath` computed property** (`:166-169`).

- Budget: `Sources/Features/Workspace/WorkspaceBrowser.swift`,
  `Sources/Features/Workspace/WorkspaceView.swift`, `Tests/WorkspaceTreeTests.swift` (~420 lines)

### Task 4 — The toolbar's target is the selection, with no fallback (R-06)

**RED.** Extend `Tests/WorkspaceBrowserToolbarTests.swift` (its header gains a line naming ADR-0024
and this plan's basename beside the ADR-0022 lines already there — the file now serves two chains):

- `WorkspaceBrowser.target(for:)` returns `""` for `nil`, `"A"` for `.folder("A")` and `"A"` for
  `.board(folder: "A")` — **one expression, no branch on which case it is**, because R-06's content
  is that the toolbar cannot aim anywhere but at the visible row.
- `WorkspaceBrowserToolbar.canMutate(folder: WorkspaceBrowser.target(for: nil))` is `false` — with
  nothing selected the two destructive verbs are disabled. This is the behaviour ADR-0022 §D9
  deliberately avoided and ADR-0024 §D7 deliberately accepts; the test is what makes the reversal
  a decision on the record rather than a regression.
- `WorkspaceTree.folders(in:)` **contains `""`** and a selection of `""` therefore survives
  `rebuild()`'s stale-selection drop. The naive `allFolders(in: tree)` does not contain it (there is
  no folder node for the root), so the root row would be deselected on every rescan.

**GREEN.** `Sources/Features/Workspace/WorkspaceBrowser.swift`: `targetFolder` (`:131-135`) becomes
`Self.target(for: selection)` with the fallback branch deleted; `rebuild()`'s drop (`:261-263`) tests
against `WorkspaceTree.folders(in: tree)` and calls `onSelect(nil)`. `WorkspaceBrowserToolbar` and
`canMutate(folder:)` are **not** modified — one rule, two surfaces (ADR-0023 §D1).

- Budget: `Sources/Features/Workspace/WorkspaceBrowser.swift`,
  `Tests/WorkspaceBrowserToolbarTests.swift` (~70 lines)

### Task 5 — The breadcrumb says «you are here» the way the tree now does (R-12)

**RED.** Extend `Tests/WorkspaceOpenStateTests.swift` — the breadcrumb is a controller property, so
this is where it is asked:

- with `current == nil` the trail is `[("Workspace", "")]` and nothing else;
- with `current == .folder("Vuota")` the trail is `["Workspace", "Vuota"]` — a board-less selection
  still moves the breadcrumb, which is the half `folder` could not express;
- `Tests/CanvasTests.swift:357-361` must still pass **unmodified**. If it does not, `breadcrumb`'s
  derivation is wrong, not the test.

**GREEN.** `Sources/Features/Workspace/BoardChrome.swift`, `BoardTopBar` (`:18-46`), ADR-0024 §D8:
the last segment is a `Text` with `.textPrimary`, not a `Button` — you are already there, and
clicking it today re-runs `open(folder:)` on the open folder and resets `zoom` and `pan`
(`WorkspaceController.swift:178-179`). Ancestor segments stay `Button` + `.textSecondary`. **No
`.accentPrimary` anywhere in the breadcrumb**, so after this change that token has exactly one
meaning left in this pane's chrome: the save indicator (`:21`), which is untouched. No new token, no
new colour, nothing hardcoded (`CLAUDE.md`, design system).

- Budget: `Sources/Features/Workspace/BoardChrome.swift`, `Tests/WorkspaceOpenStateTests.swift`
  (~60 lines)

### Task 6 — The UI suite, rewritten onto the new model (R-14, and R-01/R-02/R-04/R-05/R-10 observed)

**RED.** Rewrite `UITests/WorkspaceOpenStateUITests.swift` in full — header names ADR-0024 and this
plan's basename, keeps `-disableCalendar YES` and the `-recentVaults '("…")'` array form
(`CLAUDE.md`), and finds every control by `accessibilityIdentifier`, never by its words. Its two
existing tests are **ported, not deleted**:

- `testThePaneOpensEmptyAndFillsInOnlyAfterAClick` — same assertions, with
  `app.descendants(matching: .any).matching(identifier: "workspace-board-<vault>.canvas")` in place
  of `app.buttons[…]` (the row is no longer a `Button`, contract table). (R-10 first half)
- `testLeavingAndReturningToTheWorkspacePaneForgetsTheOpenBoard` — unchanged in intent, same
  substitution. **This is the test the SPEC's Decision 7 contradicts; it stays green.**

New tests, each naming its requirement:

- **R-01** — the fixture folder that owns a board yields **one** row, not two: the identifier
  `workspace-board-<folder>/<folder>.canvas` exists and `workspace-folder-<folder>` does **not**.
- **R-02/R-03** — after clicking a nested board's row, exactly one row in `workspace-tree` reports
  the selected state. Assert on the **label suffix** (`", aperta"` / `", selezionata"`), counting
  matches — not on `isSelected`, per the SPEC-claims table's R-13 row.
- **R-04** — with a board open, clicking a board-less folder's row (`workspace-folder-…`) brings
  «Nessuna board aperta» back and leaves that row as the only one reporting selection.
- **R-05** — clicking a board-less folder's row opens no board and raises no sheet: «Nessuna board
  aperta» is still there and no dialog exists afterwards.
- **R-14** — no assertion in either file refers to `selectedFolder` or `hasOpenBoard`. Enforced by
  the rewrite itself; the header says so.

The fixture needs a folder with its own board, a nested board, and a **board-less** grouping folder
(a directory whose only content is a subfolder that has a board). Build it in `setUpWithError`, the
way this suite already builds vaults.

**GREEN.** No production change is expected. If one is needed, it is a defect Tasks 1-5 missed:
fix it there, in its own file, and say so in the report.

Then `tuist generate --no-open` (`UITests/**` is a glob at `Project.swift:173`, but the file list is
still generated).

- Budget: `UITests/WorkspaceOpenStateUITests.swift` (~230 lines)

### Task 7 — Generate, both suites, and the two behaviours nobody here can assert (R-07, R-15, R-16)

Not a code task. In order:

1. `tuist generate --no-open`, then
   `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' build`.
2. `.claude/test-cmd` — the **whole** `PergamenumTests` bundle, not the new files' tests.
3. Build both connectors: `xcodebuild … -scheme perg build` and `… -scheme pergamenum-mcp build`.
   Nothing here should reach them (no `sharedSources` change), and that is exactly why the build is
   the cheapest possible proof of it (ADR-0001 §D1 enforcing itself).
4. `scripts/uitests.sh` — **once, before the merge to `main`**, no argument (an argument *replaces*
   the selection). Twelve minutes, and `CLAUDE.md` makes it the price of `test-cmd` being restricted
   to the unit bundle.
5. **The two hand checks, on a Debug build over a throwaway vault** — neither is assertable from
   here and both carry a requirement:
   - **R-07** — click the blank area below the last row. If the selection clears, R-07 is met by the
     native behaviour and nothing is added. If it does **not**, add exactly one
     `.onTapGesture { onSelect(nil) }` on each `List` with a comment recording what was observed,
     and say so in the report. This is ADR-0024 A9's fallback with its trigger, not a licence to add
     it pre-emptively.
   - **R-13** — VoiceOver over two rows, one selected: confirm the selected one is announced
     differently. The label suffix is the carrier; the trait is a bonus.
   - While there: **R-08**, arrow keys move the highlight; **R-10 second half**, open a board from
     the breadcrumb and from a `pergamenum://canvas` link and confirm the tree lights that folder's
     row and no other.
6. **R-15** — confirm ADR-0024 sits at `docs/adr/0024-workspace-board-tree-single-selection.md`, that
   its Status block names ADR-0022 §D9 as superseded, and add the cross-reference **into
   ADR-0022 §D9 itself** («superseded by ADR-0024») plus the one-line entry in `CLAUDE.md`'s *Chain
   decision index*, beside the four already there. An ADR that supersedes another and is not
   mentioned by it is an ADR the next reader will not find.

---

## Risks, dependencies and HITL gates

- **The two unverified SwiftUI behaviours are the plan's real risk** (R-07 native deselection, R-13's
  `isSelected` trait). Both are handled by making the *assertable* half carry the requirement and
  the unverified half a hand check with a named fallback. Neither may be asserted from memory of how
  SwiftUI behaves — this repository's rule and, twice already, its scar tissue.
- **A silently dropped `.tag` is the failure this feature is most likely to ship**
  (`RootView.swift:205-208`): the list lights nothing, swallows every click, and no test fails
  because nothing throws. Task 3 puts `.tag` last in the chain; Task 6's R-02 test is the net under
  it, and it is the one test in this plan that must not be skipped for time.
- **Three chains have now edited these four files in eight days** (ADR-0021, ADR-0022, ADR-0023,
  and `5041d5c` on top). Confirm before Task 1 that the working tree carries no uncommitted work
  from the `workspace-ui-…` (step 5) or `universal-command-surface-parity` (step 7) chains, both of
  which are open in `MEMORY.md`. Two chains rewriting `WorkspaceBrowser.swift` at once is a merge
  nobody wants to resolve by hand.
- **The UI-test instance outlives its run** and holds a vault under
  `~/Library/Containers/it.stefer.pergamenum.uitests.xctrunner/…` (`CLAUDE.md`). Any manual check at
  Task 7 that shows notes nobody created is reaching one of those: `ps -Ao pid,command | grep
  Pergamenum.app/Contents/MacOS` first, and `scripts/uitests.sh` kills stale instances itself.
- **`.claude/test-cmd` runs at the end of every turn** through the `Stop` hook. Tasks 2 and 3 leave
  the target non-compiling *within* a batch; that is expected and the batch ends green or it is not
  done.
- **HITL gates:** Gate 2 approval of ADR-0024 before Task 1 (and the operator's move of the file into
  `docs/adr/`); the commit at the end of the chain; the merge to `main`, which is also the moment
  `scripts/uitests.sh` must have been run. No schema change, no migration, no deletion of user data
  anywhere in this plan — the only removals are three source members and two test files' contents,
  and the test files are rewritten rather than dropped.
- **Nothing here is exposed to `perg` or `pergamenum-mcp`**, deliberately (ADR-0022 §D6). Step 3 of
  Task 7 is what proves it.

---

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -derivedDataPath "/Users/stefer/Developer/Pergamenum/.build/DerivedData" -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield

CODER-MODEL CANDIDATE: opus
