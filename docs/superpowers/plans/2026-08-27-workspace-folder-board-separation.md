# Plan — Workspace folder/board separation: a folder is a container, a board is a file

- **SPEC:** `/Users/stefer/Developer/Pergamenum/SPEC.md` (R-01 … R-18).
- **ADR:** `ADR-0025: A folder is a container, a board is a file, and neither is named after the
  other`, currently at
  `/Users/stefer/Developer/Pergamenum/docs/architecture/ADR-0025-workspace-folder-board-separation.md`,
  **to be moved by the operator to
  `/Users/stefer/Developer/Pergamenum/docs/adr/0025-workspace-folder-board-separation.md`** before
  Task 1 (this project's ADRs all live under `docs/adr/`; the architect agent's write scope forbids
  that directory). Every reference below is to **ADR-0025** by name, never by path, so the move
  breaks nothing.
- **Branch:** `refactor/adr-0025-workspace-folder-board-separation`
- **Base:** `93d3069`. Every line number quoted below was read at that commit.
- **Style:** TDD. Every task writes its failing test first, then the code that makes it pass.
  Swift Testing (`#expect`, `#require`), never XCTest, for everything new in `Tests/`; XCTest in
  `UITests/`, matching the suite that is already there.
- **Swift is compiled, so "red" has a precondition.** A task's **test step owns the interface**: it
  adds the new type, signature and enum-case declarations *together with* the failing tests —
  placeholder bodies returning `nil` / `[]` / the unchanged input — so the target **builds** and the
  tests fail on their assertions. The code step owns the body only. Never `fatalError()` and never a
  force-unwrap as a placeholder (`~/.claude/rules/swift.md`). **This plan has the sharper form of
  that rule in six of eight tasks:** they *remove* or *re-sign* members other files read
  (`CanvasStore.boardPath(forFolder:)`, `load(folder:)`, `save(_:folder:)`,
  `contents(ofFolder:board:)`, `WorkspaceTree.Node.Kind`'s two cases,
  `WorkspaceSelection.board(folder:)`, `WorkspaceController.open(folder:)`,
  `WorkspaceBrowserToolbar.canMutate(folder:)`). **A removal has no placeholder**, so each such task
  carries its call-site updates in the same batch, and the contract table below says which ones.
- **Harness:** this plan creates **no new harness script**, the same decision the four preceding
  Workspace plans made. Verification is the two commands this project already trusts:
  `.claude/test-cmd` after every task, and `scripts/uitests.sh` once, at Task 8, before the merge to
  `main` (`CLAUDE.md`, working agreements — the UI suite is outside `test-cmd` on purpose and its
  state is unknown between deliberate runs, `PG-033`). Do not re-specify that rule; cite it.
  **Every new or rewritten test file's header comment must name `ADR-0025` and this plan's basename
  `2026-08-27-workspace-folder-board-separation`** — that citation is the only link this repository
  keeps between a test and the decision that asked for it, and it is the anchor the coverage report
  reads. Preserve the existing `ADR-0024` / `2026-08-25-…` header lines where a file is *edited*
  rather than rewritten; add the new pair beside them, never in place of them.
- **After any task that adds a file:** `tuist generate --no-open`. The generated project lists files
  and does not regenerate itself; a build that fails naming the compiler rather than the missing file
  is the documented failure mode. **Tasks 4, 5 and 7 add files.** The same applies after any `git
  stash` / `git checkout` that adds or drops a file mid-chain.
- **`Project.swift` needs no edit and `sharedSources` gains nothing.** The app target is `Sources/**`
  minus `Sources/CLI/**` and `Sources/MCPServer/**` (`Project.swift:139-141`).
  `Sources/Vault/CanvasStore.swift` is **already** named in `sharedSources` (`Project.swift:80`) and
  `Sources/Core/**` is a glob there (`Project.swift:73`) — so Tasks 1 and 4 compile into `perg` and
  `pergamenum-mcp` automatically. `Sources/Vault/BoardFileOperations.swift` (Task 7) must **not** be
  added to `sharedSources`: that exclusion is ADR-0025 §D6 / ADR-0022 §D6 made a compile-time fact.
- **`Sources/Core/**` must not import SwiftUI or AppKit** (ADR-0001 §D1, enforced by the two tool
  builds). Task 4's addition to `WorkspaceBoardResolver` is Foundation-only.
- **Known false positives, ignore them:** the pre-commit `weakening-scan.sh` reports every Swift
  Testing test as `zero-assertion-test` (its body scanner treats a line starting with `#` as a
  comment and `#expect(...)` starts with one); the secret scanner's `assigned-secret` rule fires on
  design-token lines. Both documented in `CLAUDE.md`. Do not restructure code to appease either; do
  still read the diff.
- **Never disable or delete a test to make the suite pass** (`CLAUDE.md`). Two assertions in this
  chain *invert* rather than being removed — they are named in the contract table, and inverting one
  that is not named there is a mistake, not a shortcut.
- **The design-token rule is load-bearing.** «A view that uses a colour or a font without going
  through a token does not pass review» (`CLAUDE.md`). No task may introduce a hardcoded colour; the
  selected row keeps the system's own fill (ADR-0024 R-02) and the icon changes in Task 5 are SF
  Symbol changes only.
- **UI language is Italian; code, comments and commits are English.** New strings in this chain:
  «Nuova board», «Nuova cartella», «Rinomina board», «Elimina board», and the board-delete
  confirmation copy.

---

## Eight things this chain's SPEC says about the repository that are false or under-determined

Read at `93d3069`, before this plan was written. Do not rediscover them, and do not follow the
SPEC's wording where it contradicts them.

| SPEC says | Truth at `93d3069` | Consequence for this plan |
|---|---|---|
| Architecture → Controller/views: *"the 'ambiguous board file name' case in ADR-0022 … is removed, since there is no more one board per folder to disambiguate"*, restated in R-09 as *"(that case no longer applies)"* | **The reasoning is wrong and the conclusion is half wrong.** The ambiguity is not a property of the folder↔board rule; it is a property of the `^[[<name>.canvas]]` marker grammar, which carries a bare **file name** (ADR-0021 §D1/§D5) matched case-insensitively by `WorkspaceBoardResolver.matches` (`Sources/Core/Tasks/WorkspaceBoardResolver.swift:29-32`) and `IndexSnapshot.tasks(assignedToWorkspace:)` (`Sources/Index/IndexSnapshot.swift:186-188`). This chain makes duplicate board file names **easier** to create, not impossible. | R-09 is satisfied because a folder rename no longer renames any `.canvas` and so has no file name to rewrite markers for — **Task 7 deletes `FolderFileOperations`' whole name-level pass (`:159-197`)**. ADR-0022 §D4's guard is **relocated**, not deleted: Task 7 reimplements it on **board** rename (ADR-0025 §D6). Do not write a test asserting "ambiguity no longer exists"; write the one asserting the guard fires on board rename. |
| Architecture → Data model: *"`createFolder(named:in:)` is unchanged and no longer implicitly calls `save(.empty, folder:)` after it"* | `CanvasStore.createFolder` (`CanvasStore.swift:139-147`) **never called `save`**. The implicit board write is one line in a view extension: `try store.save(.empty, folder: created)`, `Sources/Features/Workspace/WorkspaceView+FolderVerbs.swift:32`. | The line to delete is in `WorkspaceView+FolderVerbs.swift`, not in `CanvasStore`. That single deletion is most of R-01. Task 6. |
| R-07 / UI flows: *"continues to exclude only the file of the currently-open board"* **and** *"Sibling `.canvas` files in the same folder are NOT surfaced as tray cards"* | **Mutually exclusive.** `contents(ofFolder:board:)` excludes exactly one path (`CanvasStore.swift:92`) and filters nothing by extension, so a sibling `.canvas` **already reaches the tray today** and can be dropped as a file card. | Implement the second clause: `contents(ofBoard:document:)` excludes **every** entry with the `canvas` extension (ADR-0025 §D10). Assert the second clause; do not assert the first. Task 1. |
| Architecture → Tree model: *"The tree is built from folders plus `.canvas` files"* — with no statement of how | **Under-determined, and the obvious route does not work.** `NoteTree.build(fromPaths:)`'s private `Builder` creates a folder node only from a leaf's path components (`Sources/Vault/NoteTree.swift:99-105, 110-132`), so an empty folder produces no node. And `Sources/Vault/NoteTree.swift` is named in `sharedSources` (`Project.swift:84`) — extending it changes a type the note sidebar and both connectors read. | `WorkspaceTree.build(folders:boards:)` gets **its own two-list builder**, and must replicate `NoteTree`'s ordering rule exactly (folders first, then leaves, each group by `localizedStandardCompare`). Pinned by a test. `NoteTree` gains nothing (ADR-0025 A4). Task 2. |
| R-17: *"SPEC §6.1 (lines 189-190) and §6.4 tool 4 (Cartella) … are amended"* | Lines **189** and **190** are correct (verified). But **line 194** («Rinomina ed eliminazione cartella») also states the board-file rename and the ambiguity skip that Task 7 removes, and §6.4 tool 4 is line **227**. | R-17's amendment touches **four** places, not two: `docs/20260811_Pergamenum_SpecApp.md` lines **189, 190, 194, 227**. Task 8. |
| Architecture → Controller/views: *"`WorkspaceController.open(folder:)` becomes `open(board:)`; its `folder` property is derived"* — silent about `attach` | `attach` calls `load(folder: "")` (`WorkspaceController.swift:173`), loading a root board that has no successor concept under path addressing. Nothing needs it: `WorkspaceView` draws the board only `if workspace.isShowingBoard` (`:136`), which is `current?.hasBoard ?? false`, and `current` is `nil` after `attach`. | `attach` loads **nothing**: `board = ""`, `document = .empty`, `current = nil` (ADR-0025 §D4). `Tests/CanvasTests.swift:357`'s breadcrumb-after-`attach` assertion is about `current` and **passes unchanged**. Task 3. |
| R-05: *"Double-clicking a folder row … expands or collapses that row and never opens a board"* | **There is no double-click handler on any tree row today.** The row selects on a single click through `List(selection:)`; the chevron toggles through its own `.onTapGesture` (`WorkspaceBrowser.swift:692-701`). This is a behaviour to be **added**, into the exact structure ADR-0024 already got bitten by once (`.combine` swallowed the chevron's gesture and made a row click land on the triangle — `WorkspaceBrowser.swift:626-648`, measured from a failing run's event coordinates). | `.simultaneousGesture(TapGesture(count: 2))`, never `.onTapGesture(count: 2)` (which consumes the click and starves `List(selection:)`), applied **before** the `.tag` that must stay last. **Unit-untestable**; verified by hand at Task 8 with the fallback ADR-0025 §D9 names. Task 5. |
| Scope: *"`BoardTopBar` breadcrumb"* | The type is `BoardTopBar` and the file is `Sources/Features/Workspace/BoardChrome.swift:15`. There is no `BoardTopBar.swift`. | Cosmetic. Noted so the coder does not think a file is missing. |

**A ninth item, not false but easy to get backwards:** `UITests/WorkspaceOpenStateUITests.swift:146-147`
currently asserts that a folder owning a board must **not** also have a `workspace-folder-` row —
the literal statement of ADR-0024 §D2, and exactly what this chain reverses. That assertion
**inverts** in Task 8. Inverting a green assertion is correct here and is also the shape of a
mistake, which is why it is written down rather than left to a diff.

---

## Contract changes, and the call sites already grepped

Grepped at `93d3069` across `Sources/`, `Tests/` and `UITests/`. **A removal has no placeholder:
each row's call sites are updated in the same task that makes the change**, or the target does not
build and the task produces no red.

| Change | Call sites (grepped) | Task |
|---|---|---|
| `CanvasStore.boardPath(forFolder:)` **removed** | Code: `CanvasStore.swift:31, 92`; `BoardTray.swift:235`; `BoardCardMenu.swift:108`; `WorkspaceBrowser.swift:381`; `FolderFileOperations.swift:161, 163`. Tests: `Tests/CanvasTests.swift:176, 178, 179`; `Tests/WorkspaceBrowserToolbarTests.swift:74, 83, 105, 149` (the `testBoardPath(forFolder:)` stub); `Tests/WorkspaceTreeTests.swift:51-52, 63, 96, 109, 124, 142, 166` (the `fixtureBoardPath` stub). Comment-only, update the prose: `WorkspaceTree.swift:35`; `WorkspaceBrowser.swift:377`; `FolderFileOperations.swift:287, 382`; `UITests/WorkspaceIntegrationUITests.swift:410`; `UITests/WorkspaceBoardUITests.swift:181`; `UITests/WorkspaceOpenStateUITests.swift:66` | **1** (store + `BoardTray` + `BoardCardMenu`), **2** (`WorkspaceBrowser`/`WorkspaceTree`), **7** (`FolderFileOperations`) |
| `CanvasStore.url(forFolder:)` → `url(forBoard:)` | `CanvasStore.swift:38, 47`; `Tests/CanvasTests.swift:191`; `Tests/CanvasDuplicateTests.swift:169` | **1** |
| `CanvasStore.load(folder:)` → `load(board:)`, **and it now throws `StoreError.missing` instead of returning `.empty`** | `WorkspaceController.swift:230`; `Tests/CanvasTests.swift:187, 202, 232, 380`; `Tests/CanvasCropTests.swift:193`; `Tests/CanvasDuplicateTests.swift:226`. Prose: `BoardTray.swift:232`; `WorkspaceView+FolderVerbs.swift:22`; `FolderFileOperations.swift:288`; `Tests/WorkspaceOpenStateTests.swift:15` | **1** (store + tests), **3** (controller) |
| `CanvasStore.save(_:folder:)` → `save(_:board:)` | `WorkspaceController.swift:662`; **`WorkspaceView+FolderVerbs.swift:32` — this call site is deleted, not migrated** (R-01); `Tests/CanvasTests.swift:201, 230`; `Tests/CanvasCropTests.swift:213` | **1** (store + tests), **3** (controller), **6** (the deletion) |
| `CanvasStore.contents(ofFolder:board:)` → `contents(ofBoard:document:)`, excluding **every** `.canvas` | `WorkspaceController.swift:307` (`refreshContents`); `Tests/CanvasTests.swift:220, 233` | **1** (store + tests), **3** (controller) |
| `CanvasStore` **gains** `createBoard(named:in:)`, `boardNameIsAvailable(_:in:)`, `allFolders()`; `createFolder(named:in:)` unchanged | new | **1** |
| `WorkspaceTree.Node.Kind.workspace(board:)` / `.foreignBoard(path:)` → `.folder` / `.board(path:)` | `WorkspaceTree.swift:12-17, 50, 52, 57, 71, 82, 88, 99, 109, 133-143`; `WorkspaceBrowser.swift:265, 282, 287, 296, 306-313, 444, 464-478, 481-497, 571-573, 601-607, 666-675, 680-687, 718-740`; `Tests/WorkspaceTreeTests.swift:74, 80, 84-86, 130, 148, 154, 178-185`; prose only: `UITests/WorkspaceOpenStateUITests.swift:203-206` | **2** (type + tests), **5** (the view) |
| `WorkspaceTree.build(boards:boardPath:)` → `build(folders:boards:)` | `WorkspaceBrowser.swift:380-382`; `Tests/WorkspaceTreeTests.swift:63, 96, 109, 124, 142, 166`; `Tests/WorkspaceBrowserToolbarTests.swift:83, 105, 149` | **2** |
| `WorkspaceTree.folders(in:)` narrows to `.folder` ids; the stale-selection drop stops using it and asks `node(withID:in:) == nil` | `WorkspaceBrowser.swift:393` (the drop), `:439` (expand-all); `Tests/WorkspaceTreeTests.swift` | **2** (type), **5** (the two readers) |
| `WorkspaceSelection.board(folder:)` → `.board(path:)`; the `folder` property splits into `path` (the tag) + `folder` (the containing folder) | `WorkspaceBrowser.swift:180, 193, 309`; `WorkspaceController.swift:161 (breadcrumb), 250`; `WorkspaceController+Viewport.swift:156`; `WorkspaceView.swift:125, 180`; `Tests/WorkspaceTreeTests.swift:27, 28, 32, 33`; `Tests/WorkspaceBrowserToolbarTests.swift:124`; `Tests/WorkspaceOpenStateTests.swift:55, 103, 107` | **2** (type + its own tests), **3** (controller), **5** (browser/view) |
| `WorkspaceController.open(folder:)` → `open(board:)`; `folder` becomes derived from a new stored `board`; `attach` stops loading | `WorkspaceController.swift:173 (attach — the call is deleted), 217-251, 262-268`; `BoardChrome.swift:42`; `BoardCardMenu.swift:118`; `WorkspaceController+Viewport.swift:156`; `WorkspaceView+FolderVerbs.swift:33, 96`; `Tests/CanvasTests.swift:359, 374, 379, 758`; `Tests/WorkspaceOpenStateTests.swift:53, 66, 83, 120` | **3** (all of them, one batch), **4** (`BoardChrome`, `BoardCardMenu`) |
| `WorkspaceController.openRoute` stops taking `deletingLastPathComponent` of the route's path | `WorkspaceController+Viewport.swift:150-156`; `Tests/CanvasTests.swift:758` region | **3** |
| `WorkspaceBoardResolver` **gains** `board(inFolder:among:)` returning the existing `WorkspaceBoardResolution` | new; readers added at `BoardChrome.swift:42`, `BoardCardMenu.swift:118`, `WorkspaceView.swift:177-189` | **4** |
| `WorkspaceBrowserToolbar.canMutate(folder: String)` → `canMutate(_ selection: WorkspaceSelection?)` | `WorkspaceBrowserToolbar.swift:32, 36, 92-94`; `WorkspaceBrowser.swift:725`; `Tests/WorkspaceBrowserToolbarTests.swift` (rewritten) | **5** |
| `WorkspaceBrowser.target(for:)` / `targetFolder` now yield the **containing folder** of either case | `WorkspaceBrowser.swift:155, 157, 158, 179-194`; `Tests/WorkspaceBrowserToolbarTests.swift:124` | **5** |
| `WorkspaceFolderActions` gains `createFolder`, `renameBoard`, `deleteBoard` beside `create`/`rename`/`delete`/`recordDesync` | `WorkspaceFolderActions.swift:16-33`; `WorkspaceView+FolderVerbs.swift:6-13`; `WorkspaceBrowser.swift:112, 123, 142, 279, 287` | **6** (create half), **7** (board verbs) |
| `FolderFileOperations` loses `boardRename` and the whole name-level marker pass | `FolderFileOperations.swift:159-197` and the `FolderRenamePlan.boardRename` field; `Tests/` for folder rename | **7** |
| `VaultController` / `VaultSession` gain `renameBoard(at:to:)` / `trashBoard(at:)` | new, beside `renameFolder`/`trashFolder` in `VaultController+Folders.swift` and `VaultSession+Folders.swift` | **7** |
| AX identifier `workspace-foreign-board-<path>` **removed** | `Tests/WorkspaceTreeTests.swift:185` — **the only assertion**; zero UI-test call sites | **2** |
| AX identifier `workspace-new-folder` **added** | new; UI assertion added in Task 8 | **6** |
| AX identifiers `workspace-board-<boardPath>`, `workspace-folder-<folderPath>`, `workspace-filter`, `workspace-tree`, `workspace-flat-list`, `workspace-browser-header`, `workspace-browser-toolbar`, `workspace-new`, `workspace-rename`, `workspace-delete`, `workspace-expand-all`, `workspace-collapse-all`, `workspace-delete-confirm`, `workspace-new-sheet`, `workspace-new-name`, `workspace-new-parent` — **preserved byte-identical** | `workspace-board-*`: `UITests/WorkspaceIntegrationUITests.swift:155`; `UITests/WorkspaceBoardUITests.swift:218`; `UITests/WorkspaceOpenStateUITests.swift:70, 144, 155, 159, 204`. `workspace-folder-*`: `UITests/WorkspaceOpenStateUITests.swift:146-147, 168, 174, 183`. `workspace-filter`: `WorkspaceIntegrationUITests.swift:150`, `WorkspaceOpenStateUITests.swift:27` | preserve — a task that renames one is a task that went wrong |
| `UITests/WorkspaceOpenStateUITests.swift:146-147` — asserts a board-owning folder has **no** `workspace-folder-` row — **inverts** | that file only | **8** |
| `IndexCache.schemaVersion`, `VaultAPI.LintFinding` — **untouched** | both declared in `.claude/protected-interfaces`; `interface-check.sh` blocks a signature change | none — a diff touching either in this chain is a design error |
| `Sources/Connector/**`, `Sources/CLI/**`, `Sources/MCPServer/**` — **zero call sites** for any changed `CanvasStore` member | grepped; `CanvasStore.swift` is in `sharedSources` (`Project.swift:80`), so both tool builds must still succeed | **8** verifies (R-15) |

**Full-suite rule.** Tasks 1, 2, 3, 5 and 7 change contracts other modules observe. Run the whole
`PergamenumTests` bundle after each of them — `.claude/test-cmd` already does exactly that — never
just the touched file's tests. A store signature read by six files and seven test files is precisely
the shape that breaks a test in a module nobody was looking at.

---

### Task 1 — `CanvasStore` is told the board's path, and a missing board fails (R-02, R-04, R-06, R-07, R-11, R-14, R-15)

The whole chain rests on this task. Nothing here imports SwiftUI, and `CanvasStore.swift` is in
`sharedSources` (`Project.swift:80`), so the two tool builds are part of this task's definition of
done.

**RED.** Extend `Tests/CanvasTests.swift` (add the ADR-0025 / plan-basename header pair beside the
existing ones) and update `Tests/CanvasCropTests.swift` and `Tests/CanvasDuplicateTests.swift`'s call
sites in the same batch. Add the new signatures with placeholder bodies so the target builds.
Assertions:

- `load(board:)` on a path that does not exist **throws** `StoreError.missing`, and does **not**
  return `.empty`. This is the single most important assertion in the chain — F2 of ADR-0025, and
  ADR-0022's own «single most damaging failure mode». Write it first.
- `load(board:)` round-trips a document written by `save(_:board:)` at an arbitrary path,
  `A/qualsiasi-nome.canvas` included — a name with no relationship to its folder (R-06).
- `createBoard(named:in:)` writes an empty `.canvas` at `<parent>/<name>.canvas`, returns that path,
  and **throws `.alreadyExists`** for a name a `.canvas` in that folder already has (R-02). It does
  **not** create a folder and does not require one to exist beyond `parent` itself.
- `createBoard(named: "prova", in: "")` succeeds in a vault that already contains a **folder**
  called `prova`, and both survive (R-04) — a folder and a file may share a name in one directory.
- `boardNameIsAvailable(_:in:)` agrees with `createBoard`'s refusal, checked live and without
  writing. Same relationship `FolderFileOperations.nameIsAvailable` has to `createFolder`
  (ADR-0022 §D11).
- `allFolders()` returns every directory as a vault-relative path, **excluding** `.obsidian`,
  `.git`, `.trash`, `.pergamenum` and their descendants (the `VaultLayout.isExcludedDirectory` walk
  `allBoards()` already performs), and **including a folder holding no `.canvas` at all** (R-10's
  precondition, asserted here at the store level).
- `contents(ofBoard: "A/uno.canvas", document:)` derives the folder `A` and lists `A`'s real
  entries, so a dropped file still lands beside the open board (R-06).
- `contents(ofBoard:document:)` puts **no `.canvas` at all** in `unplaced`: neither the open board's
  own file nor a sibling `A/due.canvas` (R-07, ADR-0025 §D10). Assert the sibling explicitly —
  it appears in the tray today and this is the assertion that stops it.
- `createFolder(named:in:)` still creates a directory and **creates no `.canvas`** (R-01's store
  half; the view half is Task 6).

**GREEN.** `Sources/Vault/CanvasStore.swift` per ADR-0025 §D1's table: delete
`boardPath(forFolder:)`, re-sign `url`/`load`/`save`/`contents`, add
`createBoard`/`boardNameIsAvailable`/`allFolders`, add `StoreError.missing(String)` beside
`.alreadyExists` with its Italian `description`. `allFolders()` reuses `allBoards()`'s enumerator,
its `skipsPackageDescendants` option and its exclusion skip — collect directories where that walk
`continue`s today (`CanvasStore.swift:128-131`); do not write a second walk.

Carry the two non-test code call sites in the same batch, because a removal has no placeholder:
`BoardTray.boardFileName` (`:230-236`) becomes `(workspace.board as NSString).lastPathComponent` and
stops needing `workspace.store` at all; `BoardCardMenu.copyLink` (`:106-112`) passes
`workspace.board` straight to `PergamenumLink.canvas(path:nodeID:)`. Both get shorter.

`WorkspaceBrowser.swift:380-382` and `FolderFileOperations.swift:161-163` also call the deleted
member and are fixed in Tasks 2 and 7. To keep this task's batch buildable, this task may leave a
**temporary** local derivation at those two sites with a `// TODO(ADR-0025 Task 2/7)` comment —
never a re-added `boardPath` helper on `CanvasStore`, which is the thing being deleted.

**Verify:** `.claude/test-cmd` (full bundle), then both tool builds — R-15 is a real check here and
not at the end, because this is the task that changes a shared file:

```
xcodebuild -workspace Pergamenum.xcworkspace -scheme perg -destination 'platform=macOS' build
xcodebuild -workspace Pergamenum.xcworkspace -scheme pergamenum-mcp -destination 'platform=macOS' build
```

- Budget: `Sources/Vault/CanvasStore.swift`, `Sources/Features/Workspace/BoardTray.swift`,
  `Sources/Features/Workspace/BoardCardMenu.swift`, `Tests/CanvasTests.swift`,
  `Tests/CanvasCropTests.swift`, `Tests/CanvasDuplicateTests.swift` (~320 lines)

### Task 2 — Folders and boards are different rows, and the vault root is the list (R-01, R-03, R-04, R-10, R-11)

Pure types only. Nothing in this task imports SwiftUI, which is what lets the whole tree model be
asked by a test rather than looked at.

**RED.** Rewrite `Tests/WorkspaceTreeTests.swift` in full (header names ADR-0025 and this plan's
basename, and records that it replaces the ADR-0024 fold's tests). Declare the new `Node.Kind` cases,
the new `build(folders:boards:)` signature and `WorkspaceSelection`'s new shape alongside the tests.
Fixture — deliberately the shapes R-03, R-04, R-10 and R-11 name:

```
folders: ["01 Progetti", "01 Progetti/a", "01 Progetti/b", "Vuota", "Vuota/dentro", "prova"]
boards:  ["Pergamena.canvas",
          "01 Progetti/01 Progetti.canvas",
          "01 Progetti/a/a.canvas",
          "01 Progetti/b/b.canvas", "01 Progetti/b/altro.canvas",
          "prova/prova.canvas"]
```

Assert:

- **No root row.** The top level is `["01 Progetti", "Vuota", "prova", "Pergamena.canvas"]` by `id`
  — folders first then leaves, `NoteTree`'s own order replicated (R-11), and **no node with
  `id == ""`** anywhere in the tree.
- `"Pergamena.canvas"` is `.board(path: "Pergamena.canvas")` with `name == "Pergamena"` and no
  children — an ordinary top-level board row, no synthesis (R-11).
- `"01 Progetti"` is `.folder` and its children are
  `["01 Progetti/a", "01 Progetti/b", "01 Progetti/01 Progetti.canvas"]` — the board it used to be
  folded into is now **a row of its own, beside its sibling folders** (R-01, the reversal of
  ADR-0024 §D2).
- `"01 Progetti/b"` has **two** board children, `b.canvas` and `altro.canvas`, both `.board` and
  both indistinguishable in kind (R-03) — and `altro.canvas` is no longer special in any way, which
  is ADR-0024 §D3's supersession stated as a test.
- `"Vuota/dentro"` exists as a `.folder` with **no children at all** (R-10) — the assertion that
  proves the tree is not built from `allBoards()` alone.
- `"prova"` is a `.folder` and `"prova/prova.canvas"` is its `.board` child; the two carry different
  `id`s and both resolve (R-04).
- Ordering: a fixture with `"9 Note"` and `"10 Note"` puts `9` first (`localizedStandardCompare`,
  `NoteTree.swift:123, 129`), and folders precede leaves at every depth.
- `boardCount` on `"01 Progetti"` is 4 and on `"Vuota"` is 0.
- `folders(in:)` returns `.folder` ids only, and **no** board path.
- `node(withID:in:)` finds a folder id, finds a board path, and returns `nil` for an id in neither —
  the stale-selection drop's question and the selection setter's lookup, one function.
- `WorkspaceSelection`: `.board(path: "A/x.canvas").path == "A/x.canvas"` and its
  `.folder == "A"`; `.board(path: "x.canvas").folder == ""`; `.folder("A/b").path == "A/b"` and
  `.folder("A/b").folder == "A/b"`; `hasBoard` true only for `.board`.
- `WorkspaceBrowser.identifier(for:)` gives `workspace-board-<path>` for a `.board` and
  `workspace-folder-<path>` for a `.folder`, and there is **no third spelling** —
  `workspace-foreign-board-` appears nowhere in the file (its only assertion,
  `Tests/WorkspaceTreeTests.swift:185`, is deleted here rather than inverted, because the concept is
  gone).

**GREEN.**

- `Sources/Features/Workspace/WorkspaceSelection.swift` — ADR-0025 §D3's enum, with `path` and
  `folder` and a doc comment stating that `.folder("")` is representable and never produced.
- `Sources/Features/Workspace/WorkspaceTree.swift` — rewritten. `Node.Kind` is `.folder` /
  `.board(path:)`; `build(folders:boards:)` walks the two flat lists into one nested structure with
  **its own builder**, not through `NoteTree.build(fromPaths:)` (see the false-claims table). Keep
  `flattened`, `folders(in:)` and `node(withID:in:)`; `node(withID:in:)` loses its `.foreignBoard`
  skip and now answers for every node.
- `WorkspaceBrowser.identifier(for:)` and `selection(for:)` re-cased (the rest of the browser is
  Task 5). `selection(for:)` no longer returns an optional: every row is selectable, so it returns
  `WorkspaceSelection` and the two `recordDesync` guards at `WorkspaceBrowser.swift:282-289` collapse
  to the one that survives — a `.tag`ed id the tree cannot resolve.
- Fix `WorkspaceBrowser.swift:380-382`'s call and delete Task 1's TODO there:
  `WorkspaceTree.build(folders: store.allFolders(), boards: boards)`.

Then `.claude/test-cmd` (full bundle).

- Budget: `Sources/Features/Workspace/WorkspaceTree.swift`,
  `Sources/Features/Workspace/WorkspaceSelection.swift`, `Tests/WorkspaceTreeTests.swift`
  (~340 lines)

### Task 3 — The controller opens a board by path; `attach` opens nothing (R-06, R-12)

Removes a stored property and re-signs the method five files call, so it carries every call site.

**RED.** Rewrite `Tests/WorkspaceOpenStateTests.swift` (header names ADR-0025 and this plan's
basename; keep its ADR-0024 lineage note). Update `Tests/CanvasTests.swift:357-381, 758` in the same
batch. Assertions, each against `current` and `board` and never a boolean of its own:

- `attach` leaves `current == nil`, `isShowingBoard == false`, `board == ""` **and
  `document == .empty`** — «loaded, not chosen» becomes «not loaded at all» (ADR-0025 §D4). This is
  the assertion the false-claims table's sixth row buys.
- `open(board: "A/x.canvas")` on an existing file: `current == .board(path: "A/x.canvas")`,
  `board == "A/x.canvas"`, `folder == "A"`, `isShowingBoard == true` (R-06).
- `open(board: "A/uno.canvas")` and then `open(board: "A/due.canvas")` — two boards in one folder,
  each loading its own document, `folder == "A"` for both. The assertion that proves board identity
  is the path and not the folder (R-06, R-03's controller half).
- **`open(board:)` on a path that does not exist selects nothing**: `current` unchanged,
  `isShowingBoard` unchanged, and a problem recorded. The successor to `load(folder:)`'s silent
  `.empty` (ADR-0025 §D1/§D4).
- `open(board: "A/x.canvas")` at the root — `open(board: "x.canvas")` — gives `folder == ""`.
- `select(.folder("Progetti"))` while a board is open: `current == .folder("Progetti")`,
  `isShowingBoard == false`, the card `selection` empty. `select(nil)` gives `current == nil`.
  Both survive from ADR-0024 §D4 and are re-asserted against the new cases.
- `select(.board(path:))` twice with the same value does not reload — ADR-0024 §D4's no-op guard,
  still load-bearing for ADR-0023 §D4's context menus and for the two Task 7 adds.
- **`breadcrumb`**: `nil` → `["Workspace"]` (this is `Tests/CanvasTests.swift:357`, which **passes
  unchanged**); `.board(path: "01 Progetti/vibrofer-emea/board.canvas")` →
  `["Workspace", "01 Progetti", "vibrofer-emea", "board"]` with the **last segment naming the board
  file, not the folder** (R-12's chrome half); `.folder("01 Progetti")` →
  `["Workspace", "01 Progetti"]`.
- **`openRoute(("A/altro.canvas", nil), viewport:)` opens `A/altro.canvas`**, not `A/A.canvas`
  (F6 of ADR-0025 — a defect this task closes; the `pergamenum://canvas` link finally honours the
  path it carries). R-12.

**GREEN.** `Sources/Features/Workspace/WorkspaceController.swift`: stored `board`, derived `folder`,
`open(board:)`, `load(board:)` returning `false` and recording the problem on a throw, `attach`
without its load, `breadcrumb` over `current`'s two cases, `refreshContents` calling
`store.contents(ofBoard: board, document: document)`, and the autosave at `:662` writing
`store.save(document, board: board)`. `WorkspaceController+Viewport.swift:150-156`: `open(board:
route.path)` and the guard against `current != .board(path: route.path)`.

Carry every remaining `open(folder:)` call in the same batch: `BoardChrome.swift:42`,
`BoardCardMenu.swift:118`, `WorkspaceView+FolderVerbs.swift:33, 96`. **Task 4 replaces the first two
with the resolver** — here they only need to compile, so give each the smallest correct call and a
`// TODO(ADR-0025 Task 4)`.

Then `.claude/test-cmd` (full bundle).

- Budget: `Sources/Features/Workspace/WorkspaceController.swift`,
  `Sources/Features/Workspace/WorkspaceController+Viewport.swift`,
  `Tests/WorkspaceOpenStateTests.swift`, `Tests/CanvasTests.swift` (~300 lines)

### Task 4 — One resolution for «which board does this folder mean» (R-05, R-06, R-12)

Adds a file under `Sources/Core/**`, which the two tool builds police for SwiftUI and AppKit imports
(ADR-0001 §D1). Foundation only.

**RED.** Extend `Tests/WorkspaceBoardResolverTests.swift` (add the ADR-0025 / plan-basename header
pair). Declare `board(inFolder:among:)` with a placeholder returning `.notFound`. Assertions:

- `board(inFolder: "A", among: ["A/x.canvas"])` → `.unique("A/x.canvas")`.
- `board(inFolder: "A", among: ["A/x.canvas", "A/y.canvas"])` → `.ambiguous` (R-03's navigation
  half).
- `board(inFolder: "A", among: ["A/b/x.canvas"])` → `.notFound` — a board in a **sub**folder is not
  this folder's board, so the match is on `deletingLastPathComponent` and never on `hasPrefix`.
- `board(inFolder: "", among: ["Pergamena.canvas", "A/x.canvas"])` → `.unique("Pergamena.canvas")` —
  the vault root is an ordinary folder to this function (R-11).
- `board(inFolder: "A", among: [])` → `.notFound`.
- The existing marker-resolution tests still pass untouched: one enum, two questions
  (ADR-0025 §D5).

**GREEN.** `Sources/Core/Tasks/WorkspaceBoardResolver.swift` gains the function. Then the three
callers, each following ADR-0025 §D5's one rule — `.unique` opens, `.ambiguous`/`.notFound` selects
the folder:

- `BoardChrome.swift:42` — a breadcrumb ancestor segment. The **root** segment («Workspace», index
  0, `folder == ""`) calls `select(nil)` instead, because `.folder("")` is never produced
  (ADR-0025 §D3). The last segment stays a `Text` (ADR-0024 §D8.2).
- `BoardCardMenu.open(_:)` at `:115-118` — a folder card's double click.
- `WorkspaceView.placePendingNote` at `:177-189` — the editor's hand-off, which **also** calls
  `vault.recordProblem` on `.ambiguous`/`.notFound`, because the other two are navigation and this
  one is a gesture that would otherwise land nowhere. This is the deletion of the last path by which
  the app writes a `.canvas` nobody asked for (ADR-0025 F8, ADR-0024 A5's remaining door).

All three read the board list they already have or fetch it once; **do not** call
`CanvasStore.allBoards()` inside a view body — it is an uncached full filesystem walk and
`WorkspaceBoardResolver`'s own doc comment says so.

Then `tuist generate --no-open` (no new file is added if the function goes into the existing
`WorkspaceBoardResolver.swift` — run it only if the coder chose to add one), `.claude/test-cmd`, and
both tool builds.

- Budget: `Sources/Core/Tasks/WorkspaceBoardResolver.swift`,
  `Sources/Features/Workspace/BoardChrome.swift`, `Sources/Features/Workspace/BoardCardMenu.swift`,
  `Sources/Features/Workspace/WorkspaceView.swift`, `Tests/WorkspaceBoardResolverTests.swift`
  (~180 lines)

### Task 5 — The sidebar draws two kinds of row, and the toolbar aims at either (R-01, R-03, R-05, R-08, R-10, R-11)

The view task. Most of `WorkspaceBrowser.swift`'s lower half changes; none of its identifiers do,
except the one Task 2 removed.

**RED.** Rewrite `Tests/WorkspaceBrowserToolbarTests.swift` (header names ADR-0025 and this plan's
basename), declaring `canMutate(_ selection: WorkspaceSelection?)` and the new `target(for:)`
alongside. Everything asserted here is a pure static, asked without a view — which is why
`canMutate` and `target(for:)` are statics in the first place (ADR-0022 §D8):

- `canMutate(nil) == false`; `canMutate(.board(path: "x.canvas")) == true`;
  `canMutate(.folder("A")) == true`; `canMutate(.folder("")) == false` and
  `canMutate(.folder("/")) == false` — ADR-0022 §D9's root exemption, kept even though the root is
  now unselectable by construction (ADR-0025 §D8).
- `target(for: nil) == ""`; `target(for: .folder("A")) == "A"`;
  `target(for: .board(path: "A/x.canvas")) == "A"` — a **board** row selected means the new board or
  folder is created **beside** it, in its containing folder (ADR-0025 §D7). This is the assertion
  that proves the toolbar reads `WorkspaceSelection.folder` and not `.path`.
- `WorkspaceBrowser.rows(matching:in:)` returns both kinds now, detached (`children: []`), and
  matches a board by its `name` and by its `id`: filtering «altro» finds
  `01 Progetti/b/altro.canvas` (R-03, R-09 of the sidebar's own filter). Keep the `nonisolated`
  keyword and the reason recorded at `WorkspaceBrowser.swift:456-463` — a `@MainActor` static
  passing a closure to `compactMap` traps the whole test process, not the test.

**GREEN.** `Sources/Features/Workspace/WorkspaceBrowser.swift` and
`Sources/Features/Workspace/WorkspaceBrowserToolbar.swift`:

- `WorkspaceRow.icon`: a direct `Kind` switch — `folder` / `folder.fill` for `.folder` (keeping the
  existing expanded/collapsed pair), `rectangle.3.group` for `.board`. No dimming, no `isForeign`;
  delete that computed property.
- `accessibilityLabel`: «Workspace \(name), aperta» / «Workspace \(name)» for a `.board`;
  «Cartella \(name), \(boardCount) Workspace» (+ «, selezionata») for a `.folder`. The `.foreignBoard`
  branch goes. Keep `.accessibilityElement(children: .contain)` — **never `.combine`**, for the two
  reasons written at `WorkspaceBrowser.swift:626-648`.
- **`.tag` stays the last modifier in the chain**, on every row now (nothing is unselectable any
  more, so `taggedRow`'s `switch` collapses to a single `.tag(node.id)`). A modifier applied after it
  drops it and the failure is silent (`RootView.swift:205-208`).
- **The double click** (R-05): `.simultaneousGesture(TapGesture(count: 2).onEnded { toggle() })` on
  a `.folder` row's content, **before** the `.tag`, and only when `hasChildren`. Not
  `.onTapGesture(count: 2)`. A `.board` row gets none — a single click already opens it.
- The row's `.contextMenu` offers Rinomina/Elimina for **both** kinds, gated by
  `WorkspaceBrowserToolbar.canMutate(selection)` alone (the `selection(for:) != nil` gate is gone
  with `.foreignBoard`), each setting the selection first (ADR-0023 §D4) and then calling the
  matching closure — `onRename`/`onDelete` for a `.folder`, `onRenameBoard`/`onDeleteBoard` for a
  `.board`. Task 7 implements the two new closures; here they may be no-ops on
  `WorkspaceFolderActions` so the batch builds.
- `targetFolder` becomes `Self.target(for: selection)`, and the browser is handed the whole
  `WorkspaceSelection?` rather than a `String?` — `WorkspaceView.swift:125` passes
  `workspace.current`. That is one fewer place where the case is thrown away and recovered
  (ADR-0024 §D6's shape, one parameter better).
- The stale-selection drop at `:393` asks `WorkspaceTree.node(withID: id, in: workspaceTree) == nil`.
  `expandableFolders` keeps asking `WorkspaceTree.folders(in:)`, which now yields folder ids only —
  a board row has nothing to expand.
- `reveal(_:)` takes the selection's `path`; `NoteTree.ancestors(of:)` is already right for both
  cases (it drops the last component, which for a board path is the file and for a folder path is
  the folder itself).
- Toolbar: identifiers `workspace-rename` / `workspace-delete` unchanged, `.help` and
  `.accessibilityLabel` switching between «… board» and «… cartella» on the selection's case.

Then `.claude/test-cmd` (full bundle).

- Budget: `Sources/Features/Workspace/WorkspaceBrowser.swift`,
  `Sources/Features/Workspace/WorkspaceBrowserToolbar.swift`,
  `Sources/Features/Workspace/WorkspaceView.swift`, `Tests/WorkspaceBrowserToolbarTests.swift`
  (~380 lines)

### Task 6 — Two creation verbs, and creating a folder creates a folder (R-01, R-02)

**RED.** New `Tests/WorkspaceCreationTests.swift` (header names ADR-0025 and this plan's basename).
`WorkspaceView`'s verbs are `@MainActor` view code, so assert what is pure and assert the rest
through the store — the split ADR-0022 §D11 already established for the sheet's predicate:

- `CanvasStore.createFolder(named:in:)` followed by `allBoards()` shows **no new `.canvas`** (R-01).
  The deletion of `WorkspaceView+FolderVerbs.swift:32` is what makes this true, and this is the test
  that pins it.
- After `createFolder`, `WorkspaceTree.build(folders: store.allFolders(), boards: store.allBoards())`
  contains a `.folder` node for the new path with **no children** (R-01's «appears in the tree as an
  expandable container with no board underneath»). Asserted through the tree, because a folder that
  exists on disk and not in the tree is the exact defect this chain removes.
- `createBoard(named:in:)` followed by the same build shows a `.board` node at the new path, inside
  the chosen folder, **and no new folder** (R-02).
- `WorkspaceFolderSheets.parentOptions(from:)` offers a folder holding only subfolders and a folder
  holding only boards — fed from `allFolders()` now rather than derived from board paths, which is
  ADR-0022 §D11's objection to `vault.folders` finally answerable.

**GREEN.**

- `Sources/Features/Workspace/WorkspaceView+FolderVerbs.swift`: `createWorkspace(named:in:)` splits
  into `createBoard(named:in:)` (→ `CanvasStore.createBoard`, then `workspace.open(board:)` on the
  returned path) and `createFolder(named:in:)` (→ `CanvasStore.createFolder`, then
  `workspace.select(.folder(created))`). **Delete `try store.save(.empty, folder: created)` at
  `:32`.** Both keep `flushBoard()` first (ADR-0022 §D10's ordering) and both `rescan()` after.
- `Sources/Features/Workspace/WorkspaceFolderActions.swift` gains `createFolder`; `create` is
  renamed `createBoard` for symmetry — one grep, five call sites, all in `WorkspaceBrowser.swift` and
  `WorkspaceView+FolderVerbs.swift`.
- `Sources/Features/Workspace/WorkspaceBrowserToolbar.swift`: «Nuova board» keeps `plus` and
  `workspace-new`; **new** «Nuova cartella», `folder.badge.plus`, identifier `workspace-new-folder`,
  placed beside it **inside the existing toolbar row** — never inside `header`, whose
  `.accessibilityElement(children: .contain)` would swallow its identifier (ADR-0022 §D8/§F9,
  ADR-0025 F12).
- `Sources/Features/Workspace/WorkspaceFolderSheets.swift`: `NewWorkspaceSheet` gains a `kind`
  (`.board` / `.folder`) switching its title and its `isNameAvailable` predicate
  (`CanvasStore.boardNameIsAvailable` vs `FolderFileOperations.nameIsAvailable`). **One sheet**, so
  there is one creation dialect (ADR-0022 §D11), and the identifiers `workspace-new-sheet`,
  `workspace-new-name`, `workspace-new-parent` are reused unchanged for both.
- `WorkspaceBrowser`'s `parentOptions` source becomes `store.allFolders()`.

Then `tuist generate --no-open` (a test file is added), `.claude/test-cmd`.

- Budget: `Sources/Features/Workspace/WorkspaceView+FolderVerbs.swift`,
  `Sources/Features/Workspace/WorkspaceFolderActions.swift`,
  `Sources/Features/Workspace/WorkspaceBrowserToolbar.swift`,
  `Sources/Features/Workspace/WorkspaceFolderSheets.swift`,
  `Sources/Features/Workspace/WorkspaceBrowser.swift`, `Tests/WorkspaceCreationTests.swift`
  (~300 lines)

### Task 7 — A board can be renamed and deleted; a folder rename stops touching boards (R-08, R-09)

The last code task, and the one that relocates ADR-0022 §D4 rather than deleting it. Read the
false-claims table's first row before starting.

**RED.** New `Tests/BoardFileOperationsTests.swift` (header names ADR-0025 and this plan's
basename), plus edits to whichever existing test covers `FolderFileOperations.renamePlan`. Declare
`BoardFileOperations`, its plan type and the two `VaultController` methods with placeholder bodies.
Assertions:

- **Rename** `A/vecchio.canvas` → `A/nuovo.canvas`: the file moves, its content is byte-identical,
  and the folder `A` is untouched (R-08).
- Rename refuses a name another `.canvas` in `A` already has, **before** writing anything.
- Rename rewrites `^[[vecchio.canvas]]` **and** `[[vecchio.canvas]]` to the new name in every note
  of the vault, through `NoteRename.rewritingLinks` unchanged (ADR-0021 §D3, ADR-0022 §D3 — no new
  code in `NoteRename`, and a test that asserts the caret survives).
- Rename **repoints** a `.canvas` node in another board whose `file` path is `A/vecchio.canvas`,
  decoded and re-encoded through `CanvasDocument` so a board Obsidian wrote keeps its unknown keys
  (ADR-0022 §D2.1's mechanism, reused).
- **The relocated guard:** with `B/vecchio.canvas` also present, renaming `A/vecchio.canvas` leaves
  **every** `^[[vecchio.canvas]]` marker untouched and returns a failure line naming the count. The
  path-level repoint still runs; it is unambiguous by construction. This is ADR-0022 §D4, on board
  rename (ADR-0025 §D6).
- An ordinary `[[Nota]]` wikilink is **byte-identical** after a board rename — the regression test
  ADR-0022 §D2 wrote for folder rename, restated here, because a wikilink names a note by title
  (`NoteFileOperations.swift:270-273`).
- **Delete** `A/x.canvas` returns a resulting Trash URL (proving `trashItem` and not `removeItem`,
  ADR-0022 §D7), removes the file, leaves `A` in place, and **rewrites no marker** — an orphaned
  `^[[x.canvas]]` is `WorkspaceBoardResolution.notFound`, which is a first-class outcome.
- **R-09, the folder side:** renaming folder `A` to `B` where an **unrelated** `A.canvas` exists
  beside it leaves `A.canvas` byte-identical and untouched, and renaming a folder that contains
  `A/A.canvas` leaves that file's **name** unchanged (it moves with the directory to `B/A.canvas` and
  nothing else). No failure line about ambiguity is produced by a folder rename at all.
- Folder rename still repoints `.canvas` node paths vault-wide by prefix (ADR-0022 §D2.1 —
  **unchanged**, and the test for it must still pass).

**GREEN.**

- New `Sources/Vault/BoardFileOperations.swift` — `FolderFileOperations`'s plan/perform shape and
  its `FileChange(path:before:after:)` vocabulary, writing directly through `FileManager` and
  `NoteStore` (ADR-0022 §F8). **Not added to `sharedSources`** (ADR-0025 §D6/A10, ADR-0022 §D6): a
  connector write that `--dry-run` cannot rehearse and `undo` cannot reverse breaks ADR-0007 §D6 for
  every caller. Reuse the vault-wide repoint loop that `FolderFileOperations.swift:223-260` already
  runs; do not write a third one.
- `Sources/Vault/VaultSession+Folders.swift` and `Sources/Vault/VaultController+Folders.swift` gain
  `renameBoard(at:to:)` / `trashBoard(at:)` beside the folder verbs. **No star remap and no tab
  follow-up** — a board is not a note, so `moveStar` and `movedNote(from:to:)` have nothing to do.
  Failures go through `recordProblem`, as the folder verbs' do.
- `Sources/Vault/FolderFileOperations.swift`: **delete** `boardRename` from `FolderRenamePlan`, the
  `hasBoard` branch, the ambiguity count and the whole name-level rewrite pass (`:159-197`), plus the
  two prose references at `:287` and `:382`. Delete Task 1's TODO at `:161-163`. A folder rename now
  does exactly one thing to boards: the prefix repoint of node paths.
- `WorkspaceView+FolderVerbs.swift`: `renameBoard` / `deleteBoard`, both through the existing
  `performFolderVerb` ordering (`flushBoard()` first — the ~1s autosave would otherwise land on the
  old path and recreate the file just renamed away, ADR-0022 §F10), landing rules: after a board
  rename, if the open board **is** the renamed one, `open(board: newPath)`; after a board delete, if
  the open board **was** the deleted one, `select(.folder(containing))`. Add both as static pure
  functions beside `folderAfterRename`/`folderAfterDelete` in `WorkspaceFolderActions` and test them
  there — that file's doc comment says why they are static.
- The browser's delete confirmation gains a board wording («La board va nel Cestino del Finder, ma
  l'app non può annullare l'operazione»), reusing `workspace-delete-confirm`.

Then `tuist generate --no-open` (two files added), `.claude/test-cmd` (full bundle), and both tool
builds — `FolderFileOperations.swift` is **not** in `sharedSources`, but `CanvasStore.swift` is, so
confirm nothing regressed.

- Budget: `Sources/Vault/BoardFileOperations.swift`, `Sources/Vault/FolderFileOperations.swift`,
  `Sources/Vault/VaultSession+Folders.swift`, `Sources/Vault/VaultController+Folders.swift`,
  `Sources/Features/Workspace/WorkspaceView+FolderVerbs.swift`,
  `Sources/Features/Workspace/WorkspaceFolderActions.swift`,
  `Sources/Features/Workspace/WorkspaceBrowser.swift`, `Tests/BoardFileOperationsTests.swift`
  (~450 lines)

### Task 8 — The UI suite, the documentation, and the two things only a person can check (R-13, R-14, R-15, R-16, R-17, R-18)

No production code. Four of this task's six requirements carry `(no-test: …)` in the SPEC and are
verified by a human reading a diff or driving the app — they still need doing, and they are why this
task exists rather than being folded into Task 7.

**UI suite (R-16).** Update the identifiers and the model assumptions in `UITests/`:

- `UITests/WorkspaceOpenStateUITests.swift:146-147` — **invert**. It asserts a board-owning folder
  has no `workspace-folder-` row; under ADR-0025 §D2 it must have one, beside the board's own row.
  This is the one green assertion this chain deliberately reverses.
- `:66`, `:203-206` — the prose about `boardPath(forFolder:)` and `.workspace(board:)` describes a
  model that no longer exists. Rewrite the comments; the `workspace-board-<vault>.canvas` identifier
  at `:70` and `:204` still resolves, now as an **ordinary top-level board row** rather than a
  synthesized root.
- `UITests/WorkspaceBoardUITests.swift:181` — its comment claims the app opens the root board on
  launch. That has been false since ADR-0024 made `attach` load-not-select, and is now false twice
  over (`attach` loads nothing). Check whether the test *depends* on it before editing the comment.
- `UITests/WorkspaceIntegrationUITests.swift:410` — same, prose only.
- **New assertions** for this chain's own requirements: a `workspace-new-folder` click produces a
  tree row and no board (R-01); two boards in one folder are two rows and each opens its own (R-03);
  an empty folder has a row (R-10); a root-level `.canvas` has a top-level row (R-11); a board row's
  context menu offers Rinomina and Elimina (R-08).
- **R-08's context-menu assertions cannot use the row's identifier.** A `.contextMenu`'s entries are
  `NSMenuItem`s outside the accessibility hierarchy: find them with `app.menuItems["Rinomina…"]`
  after a `.rightClick()` on the row, never through `descendants(matching:)` under the row's
  identifier (ADR-0025 F11).
- Every new UI-test file passes `-disableCalendar YES`, like all thirteen existing ones
  (`CLAUDE.md`). Find controls by `accessibilityIdentifier`, never by their words.
- Run `scripts/uitests.sh` with **no arguments**, once, before the merge to `main`, per `CLAUDE.md`'s
  binding rule — an argument *replaces* the selection rather than adding to it. This is a
  long-running command: launch it with `run_in_background: true` and collect it, or the 2-minute tool
  timeout discards its output (`~/.claude/rules/tools.md`).

**Manual verification, by a person (R-13, and R-05's gesture).**

- **R-13 — the real vault, on a disposable COPY, never the original.**
  `cp -R ~/Library/Mobile\ Documents/com~apple~CloudDocs/Vaults/Pergamena /tmp/pergamena-copy-$(date +%s)`
  then launch a Debug build against it with `-recentVaults '("/tmp/…")'` — **the plist array form; a
  bare path leaves `stringArray(forKey:)` nil and no vault is reopened** (`CLAUDE.md`). Find the
  latest build with `ls -dt …/Pergamenum-*/Build/Products/Debug/Pergamenum.app | head -1` — **`-t`,
  not plain `ls -d`**, which sorts by hash and can hand you a stale build showing an already-fixed
  regression (`CLAUDE.md`). Confirm: every existing board opens with its content, every folder
  appears, `prova/` and `prova.canvas` are two distinct rows, and nothing was converted or rewritten
  on disk (`git status` in the copy, if it is a repo, or a `find … -newer` check).
- **R-05's double click** (ADR-0025 §D9, the false-claims table's seventh row): confirm by hand that
  a double click on a folder row expands/collapses it **and** that a single click still selects. If
  the simultaneous gesture starves `List(selection:)`, apply the fallback ADR-0025 §D9 names — move
  the double-click onto the chevron's existing hit target — and record the finding in a comment.
  Do not decide this from memory of SwiftUI behaviour either way.
- Before any hand-check, `ps -Ao pid,command | grep Pergamenum.app/Contents/MacOS`: a UI-test
  instance outlives its run and a window showing notes nobody created is one of those
  (`CLAUDE.md`).

**R-15.** Both connector targets build:

```
xcodebuild -workspace Pergamenum.xcworkspace -scheme perg -destination 'platform=macOS' build
xcodebuild -workspace Pergamenum.xcworkspace -scheme pergamenum-mcp -destination 'platform=macOS' build
```

Zero call sites exist in either front end for any changed member, so a failure here means something
was added to `Sources/Core/**` or `sharedSources` that should not have been.

**R-14.** `.claude/test-cmd`, full bundle, green — with `WorkspaceTree`, `CanvasStore` and selection
tests **rewritten**, never disabled (`CLAUDE.md`).

**R-17.** Amend `docs/20260811_Pergamenum_SpecApp.md` at lines **189**, **190**, **194** and **227**
(the false-claims table's fifth row: the SPEC of this chain names only 189-190 and §6.4 tool 4):

- 189 «Gerarchia» — a board is no longer one per folder; a folder is a container and a `.canvas` is a
  free document; a double click on a folder card enters its board **when that folder holds exactly
  one** (ADR-0025 §D5).
- 190 «Mappatura su disco» — a board is addressed by its own path, any name, any count per folder;
  `prova/prova.canvas` keeps working and needs no conversion.
- 194 «Rinomina ed eliminazione cartella» — a folder rename no longer renames a board file and no
  longer rewrites markers; the ambiguity guard now belongs to **board** rename.
- 227 §6.4 tool 4 «Cartella» — the tool creates a directory and no board.

**R-18.** Add ADR-0025 to `CLAUDE.md`'s «Chain decision index» and a «Decisions from the …» section
in the established shape. **Step 3 of this chain edits `CLAUDE.md`, not this task's coder** — this
task's job is to confirm the ADR file itself is at `docs/adr/0025-workspace-folder-board-separation.md`
and that it names what it supersedes, which it does in its own «What is superseded, and why»
section.

- Budget: `UITests/WorkspaceOpenStateUITests.swift`, `UITests/WorkspaceBoardUITests.swift`,
  `UITests/WorkspaceIntegrationUITests.swift`, `docs/20260811_Pergamenum_SpecApp.md` (~300 lines)

---

## Requirement coverage

| R | Task(s) |
|---|---|
| R-01 | 2, 5, 6 |
| R-02 | 1, 6 |
| R-03 | 1, 2, 5 |
| R-04 | 1, 2 |
| R-05 | 4, 5 |
| R-06 | 1, 3, 4 |
| R-07 | 1 |
| R-08 | 5, 7 |
| R-09 | 7 |
| R-10 | 2, 5 |
| R-11 | 1, 2, 5 |
| R-12 | 3, 4 |
| R-13 *(no-test)* | 8 |
| R-14 | 1, 8 |
| R-15 | 1, 8 |
| R-16 *(no-test)* | 8 |
| R-17 *(no-test)* | 8 |
| R-18 *(no-test)* | 8 |

TEST-CMD CANDIDATE: none
TEST-CMD MODE: brownfield
