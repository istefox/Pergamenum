# Plan — Workspace UI: create, rename and delete a workspace from the sidebar

- **SPEC:** `/Users/stefer/Developer/Pergamenum/SPEC.md` (R-01 … R-15).
- **ADR:** `ADR-0022: Creating, renaming and deleting a workspace is a folder operation, performed
  outside the journal`, currently at
  `/Users/stefer/Developer/Pergamenum/docs/architecture/ADR-022-workspace-ui-creazione-board-toolbar-e-r.md`,
  **to be moved by the operator to
  `/Users/stefer/Developer/Pergamenum/docs/adr/0022-workspace-ui-creazione-board-toolbar-e-r.md`**
  before Task 1 (this project's ADRs all live under `docs/adr/`; the architect agent's write scope
  forbids that directory). Every reference below is to **ADR-0022** by name, never by path, so the
  move breaks nothing.
- **Branch:** `feature/adr-0022-workspace-folder-create-rename-delete`
- **Base:** `main` at `7ffd5fd`. Every line number quoted below was read at that commit.
- **Style:** TDD. Every task writes its failing test first, then the code that makes it pass.
  Swift Testing (`#expect`, `#require`), never XCTest, for everything new in `Tests/`.
- **Swift is compiled, so "red" has a precondition.** A task's test step must add the new type and
  signature declarations *together with* the failing tests — placeholder bodies returning `nil` /
  `[]` / the unchanged input, or `throw`ing an existing error case — so the target **builds** and
  the tests fail on their assertions. A batch that leaves `Pergamenum` unable to compile produces
  no red tests at all, only a build error. Never `fatalError()` and never a force-unwrap as a
  placeholder (`~/.claude/rules/swift.md`).
- **Harness:** this plan creates **no new harness script**, the same decision
  `2026-08-24-workspace-tasks-notes-integration.md` made. Verification is the two commands this
  project already trusts: `.claude/test-cmd` after every task, and `scripts/uitests.sh` once, at
  Task 8, before the merge to `main` (`CLAUDE.md`, working agreements — the UI suite is outside
  `test-cmd` on purpose and its state is unknown between deliberate runs, `PG-033`).
  **Every new or extended test file's header comment must name `ADR-0022` and this plan's basename
  `2026-08-25-workspace-ui-creazione-board-toolbar-e-r`** — that citation is the only link this
  repository keeps between a test and the decision that asked for it, and it is the anchor the
  coverage report reads.
- **After any task that adds a file:** `tuist generate --no-open`. The generated project lists files
  and does not regenerate itself; a build that fails naming the compiler rather than the missing
  file is the documented failure mode.
- **`Sources/Core/**` must not import SwiftUI or AppKit** (ADR-0001 §D1, enforced by the `perg` and
  `pergamenum-mcp` builds). This plan adds nothing to `Sources/Core/**` — if a task seems to need
  to, the design is wrong, not the rule.
- **`Project.swift` needs no edit.** The app target is `Sources/**` minus `Sources/CLI/**` and
  `Sources/MCPServer/**` (`Project.swift:139-141`), so every new file is in the app automatically.
  **Do not add the three new `Sources/Vault/` files to `sharedSources`** (`Project.swift:72-106`):
  ADR-0022 §D6 keeps folder operations out of both connectors on purpose, and that exclusion is
  enforced only by their absence from that list.
- **Known false positives, ignore them:** the pre-commit `weakening-scan.sh` reports every Swift
  Testing test as `zero-assertion-test` (its body scanner treats a line starting with `#` as a
  comment and `#expect(...)` starts with one); the secret scanner's `assigned-secret` rule fires on
  design-token lines. Both documented in `CLAUDE.md`. Do not restructure code to appease either; do
  still read the diff.

## Two things the SPEC says about this repository that are false

Read at `7ffd5fd`, before this plan was written. Do not rediscover them, and do not follow the
SPEC's wording where it contradicts them.

| SPEC says | Truth | Consequence for this plan |
|---|---|---|
| R-06: after a folder rename "every wikilink (`[[...]]`) … that pointed to a note under the renamed folder is rewritten to the new path" | A wikilink names a note by **title**, not by path. `IndexSnapshot.resolve(title:)` is a lowercased title index (`IndexSnapshot.swift:99-102`); `NoteFileOperations.move` says so in code: *"a wikilink names a note by title, not by path (wikilink.md W-01)"* (`NoteFileOperations.swift:270-273`). A folder rename changes no title. | **Rewrite no ordinary wikilink.** R-06 is satisfied against the two reference classes that really break — `.canvas` node file paths and the board's own file name (ADR-0022 §D2) — plus a regression test proving a `[[Nota interna]]` link is byte-identical after the rename. |
| Scope: "no `WriteJournal` entry — this mirrors the existing single-note delete, which is not journaled either" | The single-note delete **is** journalled: `trashNote` runs inside `transaction("note trash")` and `trashFile` records a `.removal` carrying the whole text (`VaultSession+Journal.swift:106-140`, ADR-0016 §D3). | The conclusion still holds, for a different reason: a **directory** has no journal representation (a `.move` entry can never pass `preflightMove`, `VaultSession+Journal.swift:236-245`). No `transaction`, no journal entry, for either folder verb (ADR-0022 §D6). Do not cite the note delete as the precedent in a comment. |

## Contract changes, and the call sites already grepped

| Change | Call sites (grepped at `7ffd5fd`) | Action |
|---|---|---|
| `WorkspaceBrowser` gains a `actions: WorkspaceFolderActions` parameter | `Sources/Features/Workspace/WorkspaceView.swift:43` — **the only one**. `grep -rn "WorkspaceBrowser(" Sources/ Tests/ UITests/` returns one line. | Update it in Task 7, in the same batch that adds the parameter. |
| `CanvasStore` gains nothing; `createFolder(named:in:)` is reused unchanged | `WorkspaceController.swift:425`, `WorkspaceView.swift:483`, `Tests/CanvasTests.swift:242,256,271` | Nothing to update. If a task finds itself changing this signature, stop — the design is wrong. |
| New AX identifiers only; **no existing identifier changes** | `workspace-filter` and `workspace-board-<path>` are asserted at `UITests/WorkspaceIntegrationUITests.swift:150,155` | Preserve `workspace-filter`, `workspace-board-*`, `workspace-folder-*`, `workspace-tree`, `workspace-flat-list`, `workspace-browser-header` exactly. Task 5 adds new ones beside them, never renames one. |
| `NoteRename` — **not changed** (ADR-0022 §D3) | `NoteFileOperations.swift:132,255`, `Tests/NoteFileOperationTests.swift` (7 tests) | Reuse as-is. A diff touching `Sources/Core/Conventions/NoteRename.swift` in this chain is a design error. |

**Full-suite rule.** Tasks 3, 4 and 7 change behaviour that other modules observe (the index after a
rescan, the star set, the browser's initializer). Run the whole `PergamenumTests` bundle after each
of them — `.claude/test-cmd` already does exactly that — never just the new file's tests.

---

### Task 1 — The folder rules: validation, collision, content counts (R-03, R-04, R-10, R-13)

**RED.** New `Tests/FolderFileOperationTests.swift` (header names ADR-0022 and this plan's
basename), plus the declaration of the new type so the target builds:

- `FolderFileOperations.validate("Progetto/uno")` returns a violation; `validate("Ricerca 2026")`
  returns none. It delegates to `NoteName.validate` (`/` is already in `forbiddenCharacters`,
  `NoteName.swift:12`) — the test pins the delegation, not a second rule set. (R-04)
- `nameIsAvailable("Nuova", in: "01 Progetti")` is false when `01 Progetti/Nuova` exists as a
  directory, false when it exists as a *file*, true otherwise; case is compared the way the
  filesystem does, i.e. do not lowercase — assert that `Nuova` and `nuova` both report unavailable
  on this machine's case-insensitive volume by creating one and asking for the other. (R-03)
- `contentCounts(at: "01 Progetti/vibrofer")` returns `(notes: 4, subfolders: 2)` for a fixture with
  four `.md`, two subdirectories, one `.canvas` and one `.pdf` — notes are `.md` only, the board
  file is not a note, and `VaultLayout.isExcludedDirectory` (`VaultSettings.swift:257-259`) skips
  dot-directories and their descendants, exactly as `CanvasStore.allBoards()` does
  (`CanvasStore.swift:113-136`). (R-10)

**GREEN.** New `Sources/Vault/FolderFileOperations.swift`: `struct FolderFileOperations { let store:
NoteStore }`, with `static func validate(_:) -> [NoteName.Violation]`,
`func nameIsAvailable(_ name: String, in parent: String) -> Bool`, and
`func contentCounts(at folder: String) -> (notes: Int, subfolders: Int)`. Not in `sharedSources`.

- Budget: `Sources/Vault/FolderFileOperations.swift`, `Tests/FolderFileOperationTests.swift`
  (~170 lines)

### Task 2 — The rename plan: what a folder rename would change, computed off disk (R-06, R-07, R-13)

**RED.** Extend `Tests/FolderFileOperationTests.swift`. `renamePlan(_:to:knownPaths:)` returns a
`FolderRenamePlan` and touches nothing:

- `newPath` is the sibling path (`01 Progetti/vecchio` → `01 Progetti/nuovo`); it throws
  `.invalidTitle` for a name failing `validate`, `.alreadyExists` when the destination exists, and
  `.missing` when the source does not — the four guards `NoteFileOperations.renamePlan` has
  (`NoteFileOperations.swift:104-120`). (R-05 support, R-03, R-04)
- `boardRename` is `("01 Progetti/nuovo/vecchio.canvas", "01 Progetti/nuovo/nuovo.canvas")` — the
  **post-move** paths — when the folder has a board, and nil when it has none (ADR-0022 §D5).
- `noteChanges` rewrites a task line `- [ ] Fare ^[[vecchio.canvas]]` into `^[[nuovo.canvas]]`, and
  a plain `[[vecchio.canvas]]` link the same way, both through
  `NoteRename.rewritingLinks(in:from:"vecchio.canvas",to:"nuovo.canvas")` **called unmodified**
  (ADR-0022 §D3, ADR-0021 §D3). (R-07)
- **The regression that pins the SPEC correction:** a note containing `[[Nota interna]]`, pointing
  at a note *inside* the renamed folder, produces **no** `FileChange` at all. (R-06)
- `noteChanges[].path` for a note that lives inside the renamed folder is its **post-move** path
  (prefix substituted), because the performer moves the directory before writing.
- `boardChanges` repoints every `.canvas` node whose `file` begins with `01 Progetti/vecchio/` —
  including a board *outside* the renamed folder — and leaves a node pointing at
  `01 Progetti/vecchio-altro/x.md` alone (prefix match must be on `<old>/`, not on `<old>`). (R-06)
- Ambiguity: with `A/x/x.canvas` and `B/x/x.canvas` both present, renaming `A/x` produces **no**
  `noteChanges` for the marker and one `failures` line naming `x.canvas`; `boardChanges` are still
  produced (ADR-0022 §D4).

**GREEN.** Add `FolderRenamePlan` (`newPath`, `boardRename: (from: String, to: String)?`,
`noteChanges: [NoteFileOperations.FileChange]`, `boardChanges: [...]`, `failures: [String]`) and
`renamePlan(_:to:knownPaths:)` to `FolderFileOperations`. Reuse
`NoteFileOperations.FileChange` rather than declaring a twin. Decode/re-encode boards through
`CanvasDocument`, never as text (`NoteFileOperations.swift:296-299`).

- Budget: `Sources/Vault/FolderFileOperations.swift`, `Tests/FolderFileOperationTests.swift`
  (~220 lines)

### Task 3 — Performing it: rename on disk, delete to the Trash (R-05, R-06, R-07, R-11, R-13)

**RED.** Extend `Tests/FolderFileOperationTests.swift`:

- `renameFolder(at:to:knownPaths:)` moves the directory, renames the board file inside it, writes
  every planned change, and returns an outcome carrying `newPath`, `movedNotes: [(old, new)]`,
  `rewrittenPaths` and `failures`. After it: the old directory is gone, `<new>/<new>.canvas` exists
  and holds the old board's nodes, the marker in a note elsewhere reads `^[[nuovo.canvas]]`, and a
  card on the root board points at `01 Progetti/nuovo/Nota.md`. (R-05, R-06, R-07)
- Renaming a folder whose board file does not exist succeeds and rewrites no marker (ADR-0022 §D5).
- `trashFolder(at:)` returns a non-nil resulting URL, that URL exists, and the folder is gone from
  the vault. **The returned URL is how the test proves `trashItem` rather than `removeItem`** —
  `removeItem` could not produce one (ADR-0022 §D7). (R-11)
- `trashFolder` returns the trashed `.md` paths so the caller can close their tabs, and throws
  `.missing` for a folder that is not there.

**GREEN.** Add `renameFolder(at:to:knownPaths:)` and `trashFolder(at:)` to `FolderFileOperations`.
Order inside the rename, and it matters: **move the directory first, then rename the board file,
then write the texts** — the same argument `NoteFileOperations.rename` states
(`NoteFileOperations.swift:213-218`), one atomic operation before many fallible ones. Delete uses
`FileManager.default.trashItem(at:resultingItemURL:)` on the directory, passing a real out-pointer,
never `removeItem`.

- Budget: `Sources/Vault/FolderFileOperations.swift`, `Tests/FolderFileOperationTests.swift`
  (~200 lines)
- If `trashItem` misbehaves in the test environment (a temporary directory on a volume with no
  trash), do **not** switch to `removeItem` and do not delete the test: report it and ask. R-11 is
  the requirement, not the test's convenience.

### Task 4 — Session and facade: stars, tabs, the unsaved-buffer refusal, the rescan (R-05, R-11, R-12, R-13)

**RED.** New `Tests/VaultSessionFolderOperationsTests.swift` (header names ADR-0022 and this plan's
basename), built on `TemporaryVault` and the `VaultSession(root:stateBase:)` shape
`Tests/VaultSessionFileOperationsTests.swift:21-28` already uses — **always a temporary state base**,
never the real Application Support directory (`CLAUDE.md` principle 3):

- `session.renameFolder(at:to:)` carries the star of a note inside the folder to its new path
  (`moveStar`, `VaultSession+Starred.swift:37`); `session.trashFolder(at:)` forgets the stars of
  every note it removed. (R-05, R-11)
- Both return the moved/trashed note path lists the facade needs.
- **No journal entry is produced by either, even with the journal armed** (`session.journal =
  session.journalOnDisk`): `journalOnDisk.entries()` is empty afterwards. This is ADR-0022 §D6 made
  a test rather than a comment. (R-13)
- `VaultController.renameFolder(at:to:)` returns false and records a problem when the open note
  under that folder has unsaved edits — the folder-scoped twin of `canOperate(on:)`
  (`VaultController+Files.swift:14-19`).

**GREEN.** New `Sources/Vault/VaultSession+Folders.swift` and
`Sources/Vault/VaultController+Folders.swift`. No `transaction`. The facade calls `movedNote(from:
to:)` per moved note and `trashedNote(at:)` per removed one (`VaultController+Tabs.swift:310-332`),
then `Task { await rescan() }` — which bumps `scanGeneration` and is what makes the browser tree
rebuild (`WorkspaceBrowser.swift:43`). Neither file goes into `sharedSources`.

- Budget: `Sources/Vault/VaultSession+Folders.swift`, `Sources/Vault/VaultController+Folders.swift`,
  `Tests/VaultSessionFolderOperationsTests.swift` (~230 lines)

### Task 5 — The toolbar in the sidebar header, and the root exemption (R-01, R-09)

**RED.** New `Tests/WorkspaceBrowserToolbarTests.swift`: the toolbar's enablement is a pure
function, so make it one and test it — `WorkspaceBrowserToolbar.canMutate(folder:)` is false for
`""` and true for `"01 Progetti"` (R-09), and `WorkspaceBrowser.allFolders(in:)`, already private
and already used by «Espandi tutto», returns every folder id of a fixture tree (the toolbar's
expand-all button drives the same binding).

**GREEN.** New `Sources/Features/Workspace/WorkspaceBrowserToolbar.swift`: five buttons —
«+ Nuova workspace», «Rinomina», «Elimina», «Espandi tutto», «Comprimi tutto» — with
`accessibilityIdentifier`s `workspace-new`, `workspace-rename`, `workspace-delete`,
`workspace-expand-all`, `workspace-collapse-all`, and a container identifier
`workspace-browser-toolbar`. `WorkspaceBrowser` places it as a **second row below `header`, outside
that view's identified container** (ADR-0022 §D8 — an identifier on a macOS container propagates
onto its descendants, `WorkspaceBrowser.swift:195-203`), adds
`@State private var selectedFolder: String?` and passes selection down to `WorkspaceTreeRow`
(ADR-0022 §D9: a board row selects its parent folder and opens it; a folder row's label selects it).
The context menu keeps its two entries.

- Budget: `Sources/Features/Workspace/WorkspaceBrowserToolbar.swift`,
  `Sources/Features/Workspace/WorkspaceBrowser.swift`, `Tests/WorkspaceBrowserToolbarTests.swift`
  (~200 lines)

### Task 6 — The two sheets: name field, parent picker, inline blocking (R-02, R-03, R-04)

**RED.** Extend `Tests/WorkspaceBrowserToolbarTests.swift` with the sheets' decision logic, kept out
of the view bodies so it is testable: `WorkspaceNameField.state(name:parent:available:)` returns
`.invalid([violation])` for `Progetto/uno`, `.taken` when the collision predicate says so, `.ok`
otherwise; and `WorkspaceFolderSheets.parentOptions(from: boards)` maps
`["Labs.canvas", "01 Progetti/a/a.canvas", "01 Progetti/b/b.canvas"]` to `["", "01 Progetti",
"01 Progetti/a", "01 Progetti/b"]` — root first, deduplicated, ancestors included (ADR-0022 §D11:
**not** `vault.folders`, which is note-derived and omits a folder holding only boards).

**GREEN.** New `Sources/Features/Workspace/WorkspaceFolderSheets.swift` with `NewWorkspaceSheet`
(name + parent `Picker` + inline violations, «Crea» disabled until `.ok`) and
`RenameWorkspaceSheet` (name seeded from the selection, same validation, «Rinomina» disabled while
unchanged or not `.ok`). Both render violations through
`ConformanceText.lines(NoteViolations(...))` exactly as `RenameNoteSheet` does
(`NoteRowMenu.swift:74-80`). The collision predicate is `FolderFileOperations.nameIsAvailable` from
Task 1, reached through `vault`. Identifiers: `workspace-new-sheet`, `workspace-new-name`,
`workspace-new-parent`, `workspace-rename-sheet`, `workspace-rename-name`.

- Budget: `Sources/Features/Workspace/WorkspaceFolderSheets.swift`,
  `Sources/Features/Workspace/WorkspaceBrowser.swift`, `Tests/WorkspaceBrowserToolbarTests.swift`
  (~250 lines)

### Task 7 — Wiring the three verbs, the delete confirmation, and the navigation (R-02, R-05, R-08, R-10, R-12)

**RED.** New `Tests/WorkspaceFolderNavigationTests.swift`: the two navigation rules are pure and
belong in `WorkspaceFolderActions` as static functions —
`folderAfterRename(open:renamed:to:)` maps (`01 Progetti/a/sub`, `01 Progetti/a`, `01 Progetti/z`)
to `01 Progetti/z/sub`, leaves an unrelated open folder alone, and handles the exact-match case
(R-08); `folderAfterDelete(open:deleted:)` returns the deleted folder's parent when the open board
is it or under it, and the open folder unchanged otherwise (R-12). Include the root-parent case:
deleting `Ricerca` while it is open returns `""`.

**GREEN.** `WorkspaceView` gains a `WorkspaceFolderActions` value built from `vault` and
`workspace` and passes it into `WorkspaceBrowser` (the one call site,
`WorkspaceView.swift:43`). Each action, in order: `workspace.flushPendingSave()` **first**
(ADR-0022 §D10 — the ~1s autosave would otherwise land on the old path and recreate the directory),
then the `vault` call, then the navigation rule above. Create goes through
`CanvasStore.createFolder(named:in:)` unchanged and opens the new board (R-02). Delete opens a
`.confirmationDialog` seeded from `contentCounts` — «Verranno eliminate N note e M sottocartelle» —
with a `.destructive` confirm and `workspace-delete-confirm` as its identifier (R-10).

- Budget: `Sources/Features/Workspace/WorkspaceView.swift`,
  `Sources/Features/Workspace/WorkspaceBrowser.swift`,
  `Tests/WorkspaceFolderNavigationTests.swift` (~220 lines)

### Task 8 — The manual pass, the UI suite, and the record (R-14, R-15)

No new automated test — both requirements carry `(no-test:)` in the SPEC and are still work.

1. `scripts/uitests.sh` with no arguments, once, before the merge to `main` (`CLAUDE.md` — three of
   sixty-seven UI tests had been red for a whole milestone the last time this rule was bought,
   `PG-033`). An argument **replaces** the selection rather than adding to it; do not pass one.
   Expect `workspace-filter` and `workspace-board-*` assertions
   (`UITests/WorkspaceIntegrationUITests.swift:150,155`) to still pass untouched — if either fails,
   Task 5's toolbar was placed inside the identified header container and ADR-0022 §D8 was violated.
2. **Manual QA pass over the running app**, reported in the chain's summary as a checklist, each
   line ticked by hand (R-14): create under root and under a nested parent; a colliding name blocked
   inline; a name with `/` blocked inline; rename a folder whose board is open and watch the
   breadcrumb follow; a task assigned to that board still shows it in Attività afterwards; delete a
   folder containing the open board and land on its parent; the folder is in the Finder's Trash with
   its contents; «Rinomina» and «Elimina» disabled on the vault root row. Use a throwaway vault via
   `-recentVaults '("/path")'` — the plist array form, or no vault is reopened at launch
   (`CLAUDE.md`).
3. **`docs/20260811_Pergamenum_SpecApp.md` §6.1** gains a paragraph under **Mappatura su disco**
   (R-15): a folder's board can be created, renamed and deleted from the Workspace sidebar; renaming
   the folder renames its `.canvas` with it and rewrites every `^[[<board>.canvas]]` task marker and
   every board card that pointed inside it; deleting moves the whole folder to the system Trash;
   neither is undoable inside the app. Italian, in the document's own voice. Then update
   `PROJECT_BRIEF.md`'s Status line if this closes a milestone item.

- Budget: `docs/20260811_Pergamenum_SpecApp.md`, `PROJECT_BRIEF.md` (~40 lines)

---

## Risks, dependencies and HITL gates

**Risks**

- **A board that reads blank.** If the `.canvas` inside a renamed folder is not renamed with it
  (Task 3), `boardPath(forFolder:)` finds nothing and `load(folder:)` returns `.empty` **without
  failing** — the user sees an empty board and their content is still on disk. This is the failure
  this feature is most likely to ship with, because nothing errors. The Task 3 test asserting
  `<new>/<new>.canvas` holds the old nodes is the only thing standing in front of it.
- **The autosave recreating what was just removed.** `WorkspaceController` saves ~1s after a change;
  a rename or delete performed without `flushPendingSave()` first lets that write land on the old
  path afterwards, recreating the directory or resurrecting a trashed board. Task 7 orders the flush
  first for this reason; a reviewer should check that ordering specifically.
- **Identifier propagation making the toolbar invisible to UI tests.** ADR-0022 §D8. The symptom is
  a UI test that finds a button by identifier and gets the header instead; the cause is a button
  placed inside `workspace-browser-header`'s `children: .contain` container.
- **`trashItem` in the test environment.** The unit tests trash directories under
  `FileManager.default.temporaryDirectory`. If that volume has no trash, Task 3's test fails for a
  reason that is not the code. Do not "fix" it by switching to `removeItem` — that would silently
  make deletions unrecoverable, which is the one thing R-11 exists to prevent.
- **Ambiguous board names.** Two folders called `Ricerca` mean `Ricerca.canvas` names two boards and
  the marker rewrite is skipped with a warning (ADR-0022 §D4). A user who does not read the warning
  will find markers unchanged. Accepted; the alternative breaks correct references.
- **No undo.** Neither verb is journalled (ADR-0022 §D6). A misclicked rename is recovered by
  renaming back; a misclicked delete by the Finder's Trash. The confirmation dialog is therefore
  load-bearing, not decoration.
- **A stale generated project.** Six new files across two directories; `tuist generate --no-open`
  after every task that adds one, or the build fails naming the compiler rather than the file.

**Dependencies**

- None external. No new package, no `Tuist/Package.swift` edit, no `tuist install`. GRDB does not
  exist in this repo and nothing here needs it.
- ADR-0022 must be moved to `docs/adr/0022-workspace-ui-creazione-board-toolbar-e-r.md` by the
  operator before Task 1, so the test-file citations point at a file that exists.
- Task order is dependency order: 1 → 2 → 3 → 4 are strictly serial (each builds on the previous
  file's declarations); 5 and 6 may be written in either order but both precede 7; 8 is last.

**HITL gates**

- **Gate 2 (now):** approve ADR-0022, the branch name, and the two SPEC corrections above.
- **Before the commit of each task:** `.claude/test-cmd` green, whole bundle, not one file.
- **Before the merge to `main`:** `scripts/uitests.sh` green (Task 8.1) and the manual checklist
  ticked (Task 8.2). Both are human-confirmed, not agent-asserted.
- **Commit, push and PR** are the human's, as always. No force-push, no direct commit to `main`.
- **No deletion of any existing test or file** in this chain. If one looks wrong, say so in chat.

---

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -derivedDataPath "/Users/stefer/Developer/Pergamenum/.build/DerivedData" -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield

CODER-MODEL CANDIDATE: opus
