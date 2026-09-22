# Fix: the Workspace autosave proves what it is writing over (PG-099 / #213)

No `SPEC.md` governs this task. The repo-root `SPEC.md`, `BRAINSTORM.md` and
`UX-BLUEPRINT.md` belong to the already-merged UI-suite-replacement feature (`PG-196`) and
are **not** this chain's inputs. The requirement ids below are declared by this plan and by
nothing else; every task cites the ones it satisfies and no task cites an id not in this
list.

Read out of the worktree `Pergamenum.worktrees/fix__pg-213` at `0b739d8f`, clean tree.
Every line number, call-site list and count below was grepped in that tree.

## ADR outcome — new ADR: `docs/adr/0054-board-origin-marker-and-canvas-write-preconditions.md`

Written, `proposed`, accepted when this branch merges.

**Path deviation, stated rather than silently taken.** The dispatch asked for
`docs/architecture/ADR-NNNN-<slug>.md`. That directory does not exist in this repo: all 53
ADRs live in `docs/adr/NNNN-<slug>.md`, `CLAUDE.md`'s "Chain decision index" links every one
of them there, and `.claude/protected-interfaces` and a dozen ADR bodies cross-reference that
path. A single ADR in a new directory would be invisible to every reader and every existing
index. It is written at `docs/adr/0054-…` accordingly; move it if the convention is meant to
change, but change it for all 54 rather than for one.

`0053` is the highest file under `docs/adr/`, `docs/architecture/` does not exist, and
`git log --all -- 'docs/adr/0054*'` returns nothing — the number is free, checked, not
assumed.

Why a new ADR and not a citation of ADR-0043/ADR-0046: all three gates hold. It is **hard to
reverse** (an origin marker with a base document on `WorkspaceController`, a third save
state, one write door replacing five copies — unwinding means touching all of it). It is
**surprising without context** (a future reader finds a `save()` that re-reads the file it is
about to write, a `CanvasDocument` held twice, and an existing comment three lines above
explaining why *no* guard was needed). And it rests on **real trade-offs** (flush vs.
precondition, two-way vs. three-way reconciliation, sync door vs. the session's async one,
watcher extension vs. no second event channel). Two overrides apply on top: it records an
explicit **no** a future reader would otherwise undo (never extend `VaultWatcher` to
`.canvas`, §D7) and it states a constraint invisible in the code (why the read-then-write
pair is safe in-process and not against another process, §D3).

ADR-0054 **extends ADR-0043 §D8 and ADR-0046 §D4/§D5** and **applies ADR-0052 §D1/§D3's
rule** to its second holder. It **amends nothing** — ADR-0025 §D6 and ADR-0026 §D10 stand
unchanged. No ADR body is edited by this chain.

## Requirements

| id | requirement |
|---|---|
| R-01 | An autosave never overwrites a `.canvas` whose bytes changed since the open board loaded them. |
| R-02 | A repoint that landed on disk while a board was open survives the board's next save, together with the user's unsaved edit, with no interaction. |
| R-03 | A repoint write refuses rather than clobbering a board save that landed between the plan's read and the write. |
| R-04 | A conflict the reconciliation rule cannot resolve is visible on the board itself and in the problem list, loses neither side, and is resolved only by an explicit user choice. |
| R-05 | The open board records which bytes its document came from; no code path writes the document without writing the origin. |
| R-06 | `flushPendingSave()` and its four synchronous callers stay synchronous. |
| R-07 | Board writes stay out of the journal, the index and both connectors (ADR-0025 §D6 unchanged). |
| R-08 | Refusals from the board and folder verbs reach the user the way ADR-0046 §D7's note refusals already do. |
| R-09 | Every comment or doc claim this change makes false is corrected in the same chain. *(no-test: documentation obligation, not assertable)* |
| R-10 | The race is pinned by a deterministic in-process test; no test sleeps, races a debounce or spawns a competing `Task` (ADR-0046 §D11). |

## How the tasks are split between tester and coder

Swift is compiled: a batch that leaves the target unable to build produces no red tests at
all. So in every task below, **the tester's commit carries the type and signature
declarations** (with bodies that `fatalError()` or return a placeholder) together with the
red tests; **the coder's commit carries the bodies only**. Where a task lists "Declarations"
and "Bodies" separately that is the split; where it lists only tests, nothing new is
declared.

`tuist generate --no-open` after any task that adds a file, before building — the generated
project does not know about a file `Project.swift` was not regenerated for.

---

### Task 1 — The reconciliation rule, pure (R-02, R-10)

**Files**
- new `Sources/Core/Canvas/CanvasReconciliation.swift`
- `Project.swift` (nothing to add: `Sources/Core/**` is a glob in both `sharedSources`
  (`:88`) and the app target — confirm, do not edit)
- new `Tests/CanvasReconciliationTests.swift`

**Declarations (tester)**

```swift
extension CanvasDocument {
    enum Reconciliation: Equatable {
        case adopted(CanvasDocument)
        case diverged([String])
    }
    static func reconcile(mine: Self, base: Self, theirs: Self) -> Reconciliation
}
```

**Bodies (coder)** — ADR-0054 §D4. Difference `base` against `theirs`; if every difference is
the `path`/`subpath` of a `.file` node whose id is also in `mine`, apply exactly those paths
to `mine` and answer `.adopted`; otherwise `.diverged` with the node ids and top-level
`unknown` keys that could not be spoken for. `base == theirs` answers `.adopted(mine)` (the
refusal came from bytes that re-encode differently, not from a content change).

Import Foundation only. **No SwiftUI import** — a file under `Sources/Core` that imports
SwiftUI breaks both tool builds (CLAUDE.md, ADR-0001 §D1).

**Tests** — all pure, no disk, no controller:
- a repoint of one `.file` node between `base` and `theirs`, with `mine` holding an unrelated
  new sticky note → `.adopted`, carrying both;
- a repoint of a node `mine` deleted → `.adopted`, the deletion kept, the vanished id not
  resurrected;
- `theirs` adds a node → `.diverged` naming it;
- `theirs` removes a node → `.diverged` naming it;
- `theirs` changes a node's text / geometry → `.diverged`;
- `theirs` changes an edge or a top-level `unknown` key → `.diverged` naming it;
- `base == theirs` → `.adopted(mine)`;
- `mine == base` (nothing unsaved) and `theirs` repointed → `.adopted(theirs)`.

---

### Task 2 — `CanvasStore`: a read that returns its hash, a guarded save, one repoint door (R-01, R-03, R-07)

**Files**
- `Sources/Vault/CanvasStore.swift` (`load` `:53-59`, `save` `:61-70`)
- `Tests/CanvasStoreTests.swift`

**Declarations (tester)**

```swift
func read(board: String) throws -> (document: CanvasDocument, hash: String)
@discardableResult
func save(_ document: CanvasDocument, board: String, expecting: String? = nil) throws -> String
func writeRepoint(_ change: VaultFileChange) throws
```

**Bodies (coder)** — ADR-0054 §D3/§D6.
- `read(board:)` reads the bytes once and returns the decoded document beside
  `NoteStore.hash(data)` — the hash of the *bytes on disk*, not of a re-encoding.
  `load(board:)` keeps its exact signature and behaviour and is re-expressed as
  `try read(board: board).document`, so its 16 call sites are untouched.
- `save(_:board:expecting:)`: when `expecting` is non-nil, read the file's current bytes
  immediately before the atomic write and throw `VaultWriteRefusal.movedOn(board)` on a
  mismatch, writing nothing. `nil` is the pre-existing unconditional write. No `await` between
  the read and the write (§D3's in-process atomicity argument depends on it).
- `writeRepoint(_:)`: compare the current bytes against `change.expectedHash`
  (`VaultFileChange+ExpectedHash.swift:11`), throw `VaultWriteRefusal.movedOn(change.path)` on
  a mismatch, otherwise write `change.after` atomically at `change.path`.

`CanvasStore.swift` is named in `sharedSources` (`Project.swift:105`): the three members must
compile in `perg` and `pergamenum-mcp`. `VaultWriteRefusal` is in `Sources/Core/Vault/`, so it
is already visible there; refer to it **unqualified**, never `Pergamenum.VaultWriteRefusal`
(ADR-0046 §D4's rule — the tool targets compile these files under another module name).

**Tests**
- `save(expecting:)` with a matching hash writes; with a stale hash throws
  `VaultWriteRefusal.movedOn` and leaves the file byte-identical; with `nil` writes
  unconditionally over changed bytes.
- `save(expecting:)` against a board that no longer exists refuses (`nil` current bytes never
  equal a non-nil expectation) rather than re-creating it.
- `read(board:)`'s hash equals `NoteStore.hash` of the file's bytes and round-trips through
  `save`'s return value.
- `writeRepoint` writes on a fresh `VaultFileChange`, refuses on a stale one, and the refusal
  lands in `VaultPlanApplication.apply(_:writing:)`'s `refusals` rather than `failures`.
- `writeRepoint` refuses a `change.path` escaping the vault (it must go through `boundary`;
  the sibling assertion already exists at `Tests/VaultBoundaryCallSiteTests.swift:70-101`).

---

### Task 3 — `WorkspaceController` records which bytes it loaded (R-05, R-06)

**Files**
- `Sources/Features/Workspace/WorkspaceController.swift`
- `Tests/WorkspaceControllerTests.swift`

**Declarations (tester)**

```swift
enum BoardOrigin: Equatable {
    case none
    case loaded(board: String, hash: String, document: CanvasDocument)
}
private(set) var origin: BoardOrigin = .none
private func replaceDocument(_ document: CanvasDocument, origin: BoardOrigin)
```

**Bodies (coder)** — ADR-0054 §D2. `replaceDocument` is the **only** writer of `document` and
always writes `origin` with it. Route the five existing writers through it: `attach` (`:187`,
`.none`), `load` (`:276`, `.loaded` from `store.read(board:)`), `select` (`:327`, `.none`),
`detach` (`:214`, `.none`), `apply` (`:408`, origin unchanged — undo/redo moves memory, not
disk). `mutate` (`:375-388`) keeps mutating `document` in place and does **not** touch
`origin`.

`load(board:)` switches from `store.load(board:)` to `store.read(board:)` so the hash comes
from the same read as the document; the failure branch and `recordProblem` are unchanged.

`flushPendingSave()`, `load`, `select` and `detach` stay synchronous (R-06) — nothing in this
task introduces an `await`.

**Tests**
- opening a board sets `.loaded` with the hash of the file's bytes;
- `attach`, `select(nil)`, `select(.folder(…))` and `detach` each leave `.none`;
- a `mutate` leaves `origin` untouched while `document` changes;
- undo/redo leaves `origin` untouched;
- a `load` that throws leaves the previous board's `origin` intact (the existing
  "a board nothing could load must not become a board on screen" rule, `:256-257`).

---

### Task 4 — `save()` refuses, reconciles and retries once (R-01, R-02, R-06)

**Files**
- `Sources/Features/Workspace/WorkspaceController.swift` (`save()` `:591-606`,
  `scheduleSave()` `:574-581`, `flushPendingSave()` `:585-589`)
- new `Tests/WorkspaceAutosaveRaceTests.swift`

**Bodies (coder)** — ADR-0054 §D3/§D4. `save()` passes the origin's hash as `expecting:`. On
success it advances `origin` to the hash `save` returns and to the document just written. On
`VaultWriteRefusal`:

1. `store.read(board:)` → `theirs`;
2. `CanvasDocument.reconcile(mine: document, base: origin's document, theirs: theirs.document)`;
3. `.adopted(merged)` → `replaceDocument(merged, origin: .loaded(board:, hash: theirs.hash,
   document: theirs.document))`, then retry the save **once**; a second refusal is treated as
   `.diverged`;
4. `.diverged(reasons)` → Task 5's conflicted state; nothing written, nothing discarded.

An origin of `.none`, or one naming a different board than `board`, writes with
`expecting: nil` — there is nothing to prove and forcing a refusal would make the board
unsavable.

Any other error keeps the existing behaviour verbatim: `recordProblem("salvataggio di
\(board): \(error)")`, dirty flag left on, retried on the next edit.

**Tests (R-10 — deterministic, no sleeps, no competing `Task`)**
- **The race, Direction A** — the test the ticket asks for: `openedWorkspaceController`,
  place a `.file` card, let it save; edit again (`addStickyNote`, so a debounce is pending);
  write the *repointed* `.canvas` to disk directly with `CanvasStore.save` on a second store
  instance — exactly the bytes `BoardFileOperations.renameBoard` would have written; call
  `flushPendingSave()`; assert the file on disk holds **both** the repointed node path **and**
  the sticky note, and that `saveState == .saved`.
- the same with the external write happening *before* the edit (the stale-forever case
  §D1.1 names): the next `mutate` + `flushPendingSave()` still preserves the repoint.
- the retry happens at most once: a second external write between the reconcile and the retry
  leaves the board conflicted, not looping.
- an external write that adds a node leaves the file byte-identical and `document` intact.
- `expecting` is not passed when `origin` is `.none` (a board saved right after `attach`
  without a load still writes).

---

### Task 5 — The conflicted state, and the two verbs that resolve it (R-04)

**Files**
- `Sources/Features/Workspace/WorkspaceController.swift`
- new `Sources/Features/Workspace/WorkspaceController+Conflict.swift` (an extension, not the
  body — `WorkspaceController.swift` is at 607 lines and `PG-202` is open for the
  `type_body_length` error on a neighbouring Workspace file)
- `Sources/Features/Workspace/BoardChrome.swift` (`:30,35,36`)
- `Tests/WorkspaceAutosaveRaceTests.swift`

**Declarations (tester)**

```swift
enum SaveState: Equatable { case saved, pending, conflicted(reason: String) }
private(set) var saveState: SaveState = .saved
var hasUnsavedChanges: Bool { saveState != .saved }   // was a stored `private(set) var` (:120)
func keepLocalBoard()        // adopt the disk hash as the expectation; document untouched
func reloadBoardFromDisk()   // replace document and origin with disk; the edit is dropped, by choice
```

**Bodies (coder)** — ADR-0054 §D5.
- `mutate` (`:386`) and `apply` (`:415`) set `.pending`; a successful save (`:600`) sets
  `.saved`; `attach` (`:198`) and `load` (`:281`) set `.saved`; §D4's `.diverged` sets
  `.conflicted(reason:)` and calls `recordProblem` **once per entry into the state**, carrying
  `VaultWriteRefusal.movedOn(board).description` plus the diverged ids.
- while `.conflicted`, `save()` returns early: it neither writes nor retries. `scheduleSave()`
  may still be called; it must not turn into a refusal per second.
- `keepLocalBoard()` reads disk, sets `origin` to those bytes without touching `document`, sets
  `.pending` and saves — so the person's version wins deliberately.
- `reloadBoardFromDisk()` is `replaceDocument(theirs, origin: .loaded(…))`, `.saved`, plus
  `refreshContents()` and a `selection` intersection with the live ids (the shape `apply`
  already uses at `:413-414`).
- **`detach()` does not flush — it cancels** (`:206-207`), and the flush that should have
  happened is `WorkspaceView`'s `.onDisappear` (`WorkspaceView.swift:88`), which now returns
  early for a conflicted board before `detach()` runs (`WorkspaceView.swift:183`). That is the
  one path where the work still disappears, so `detach()` gains a `recordProblem` naming the
  board and the unresolved conflict. It does not block the close.
- `BoardChrome.swift:30,35,36` renders the third state: «Conflitto», `exclamationmark.triangle`,
  with the two verbs attached to the label. Non-modal. **Tokens only** — no hardcoded colour or
  font (CLAUDE.md's binding design-system rule). Italian UI strings; identifiers
  `board-save-indicator`, `board-conflict-keep-local`, `board-conflict-reload`.

**Tests**
- `hasUnsavedChanges` still answers `true`/`false` exactly as before for `.pending`/`.saved`
  (the four existing assertions must pass untouched — see "Call sites" below);
- a diverged save sets `.conflicted` and records exactly one problem, not one per subsequent
  edit;
- while conflicted, an edit does not write to disk;
- `keepLocalBoard()` writes the in-memory document and returns to `.saved`;
- `reloadBoardFromDisk()` replaces the document, returns to `.saved` and drops ids from
  `selection` that no longer exist;
- `detach()` on a conflicted board records a problem.

**GUI tests: none** (ADR-0054's head note). Every assertion above is in-process.

---

### Task 6 — The five remaining `.canvas` writers adopt the door, and refusals reach the user (R-03, R-08)

**Files**
- `Sources/Vault/BoardFileOperations.swift` (`:167-169`, `:280-282`, plus `RenameOutcome`
  `:126-129` and `MoveOutcome` `:241-244`)
- `Sources/Vault/FolderFileOperations.swift` (`:404-406`, plus `RenameOutcome` `:340-345`)
- `Sources/Vault/FolderFileOperations+Move.swift` (`:119-121`, plus `MoveOutcome` `:67-72`)
- `Sources/Vault/NoteFileOperations.swift` (`:237-239` — the board half only; the note half at
  `:231-233` is ADR-0054 §D8's out-of-scope follow-up)
- `Sources/Vault/VaultSession+Tasks.swift` (`:196-202`)
- `Sources/App/VaultController+Folders.swift` (the four verbs' reporting loops, `:45`, `:102`)
- `Sources/Core/Vault/VaultPlanApplication.swift` (doc comment `:16-19` only)
- `Tests/BoardFileOperationsTests.swift`, `Tests/FolderFileOperationTests.swift`,
  `Tests/VaultSessionTests.swift`

**Declarations (tester)** — `var refusals: [String] = []` added **after** `failures` on
`BoardFileOperations.RenameOutcome`/`MoveOutcome` and
`FolderFileOperations.RenameOutcome`/`MoveOutcome`, so every memberwise call stays valid and
synthesised `Equatable` keeps existing comparisons green (ADR-0046 §D4's compatibility rule).

**Bodies (coder)**
- each `VaultPlanApplication.apply(plan.boardChanges) { try Data($0.after.utf8).write(…) }`
  becomes `apply(plan.boardChanges, writing: canvas.writeRepoint)`;
- each outcome carries `boards.refusals` alongside `boards.failures`;
- `VaultSession+Tasks.writeTaskSource`'s board branch reads the board through
  `canvasStore.read(board:)` and saves with `expecting: hash`, so the read-modify-write cannot
  straddle an open board's save;
- `VaultController+Folders`'s `renameFolder`, `trashFolder`, `renameBoard` and the board move
  path gain the refusal loop, copied verbatim from `VaultController+Files.swift:49-51`:
  `for refusal in outcome.refusals { recordProblem(VaultWriteRefusal.movedOn(refusal).description) }`.

`BoardFileOperations.swift` and `FolderFileOperations.swift` stay **out** of `sharedSources` —
do not add them (ADR-0025 §D6/A10, R-07).

**Tests** (drive the production seam, never a re-spelling of it — ADR-0046 §D11)
- `renameBoard`/`moveBoard`/`renameFolder`/folder-move each report a refusal, not a failure,
  when a sibling board's bytes moved on between the plan and the write, and each leaves that
  board byte-identical while still repointing the others (the loop does not stop — ADR-0046 §D3);
- a board-sourced task toggle refuses rather than clobbering a board written since it read it;
- **no timing-based interleaving test**: the staleness is produced by writing the file between
  the `…Plan` call and the perform call, in one synchronous test body.

---

### Task 7 — Correct every claim this change makes false, and file what it leaves open (R-09)

**Files**
- `Sources/Features/Workspace/WorkspaceController.swift:594-598` — «The hash is deliberately
  dropped… there is nothing for a recorded hash to be recognised against» is now the opposite
  of what the code does;
- `Sources/Vault/VaultSession+Tasks.swift:186-188` — «a board write goes through `CanvasStore`,
  never `write(_:to:)`, so the precondition has nothing to attach to there and is simply
  unused» is now false;
- `Sources/Core/Vault/VaultPlanApplication.swift:16-19` — «The eight `store.write`-level
  callers of the synchronous overload below can never populate this: `store.write` cannot
  throw `VaultWriteRefusal`» is now false for the five that switched to `writeRepoint`;
- `Sources/App/VaultController+Folders.swift:92-96` — «a `.canvas` is not a file the editor can
  hold unsaved edits to» is true of the editor and false of the app; say which;
- `Sources/Features/Workspace/WorkspaceController.swift:344-358` (`refreshContents`) — its
  reasoning cites the `.md`-only watcher; add the pointer to ADR-0054 §D7 so the next reader
  does not re-propose extending it;
- `CLAUDE.md` — one bullet in "Working agreements" and one line in the "Chain decision index";
- `TODO.md` — close `PG-099`, and open the two follow-ups ADR-0054 §D8 names:
  (a) the **note** half of the board and folder verbs writes through an unguarded
  `store.write` (`BoardFileOperations.swift:160-162`, `FolderFileOperations.swift:398-400`,
  `NoteFileOperations.swift:231-233`), so a folder rename can clobber a dirty editor buffer
  and `syncOpenNote` never sees it; (b) `NoteFileOperations.rename(_:to:knownPaths:)` and
  `move(_:toFolder:)` have no caller in `Sources/` — a second, unguarded implementation of
  note rename reachable only from `Tests/NoteFileOperationTests.swift` and
  `Tests/NoteRenameCharacterizationTests.swift`.

No ADR body is edited. No `docs/adr/NNNN` head note is added: ADR-0054 amends nothing.

---

## Call sites of the changed contracts (grepped, not left for the coder to find)

**`CanvasStore.save(_:board:)`** — gains a defaulted parameter, so all ten sites compile
unchanged; each is listed because each is now a place where a precondition *could* belong and
deliberately does not:

- `Sources/Features/Workspace/WorkspaceController.swift:599` — **gains `expecting:`** (Task 4)
- `Sources/Vault/VaultSession+Tasks.swift:202` — **gains `expecting:`** (Task 6)
- `Tests/VaultBoundaryCallSiteTests.swift:101`, `Tests/VaultSessionTests.swift:146,170,177`,
  `Tests/CanvasStoreTests.swift:42`, `Tests/CardRoundTripTests.swift:168`,
  `Tests/VaultTests.swift:104,107` — unchanged, and that is the point: the default keeps the
  unconditional write available for a test that is setting up a fixture.

**`CanvasStore.load(board:)`** — signature and behaviour untouched; 16 sites
(`Sources/Vault/VaultSession+Tasks.swift:173,197`, `Sources/Vault/CanvasStore.swift:53`, plus
13 in `Tests/`). Only `WorkspaceController.load` switches to `read(board:)`.

**`WorkspaceController.hasUnsavedChanges`** — stored → computed, same name, same type, same
meaning. Readers: `Sources/Features/Workspace/BoardChrome.swift:30,35,36`,
`Tests/WorkspaceControllerTests.swift:47`, `Tests/WorkspaceControllerToolsTests.swift:192,199`,
`Tests/CardFoldTests.swift:236`. Writers to remove:
`WorkspaceController.swift:198,281,386,415,600` (each becomes a `saveState` write).
**Update tests and call-sites asserting the old behaviour:** the six reads above must stay
green untouched — if any needs editing, `hasUnsavedChanges` changed meaning and Task 5 is
wrong.

**The four outcome structs** gaining `refusals` —
`BoardFileOperations.RenameOutcome`/`MoveOutcome`,
`FolderFileOperations.RenameOutcome`/`+Move.MoveOutcome`. No test constructs any of them
memberwise (grepped `RenameOutcome(`/`MoveOutcome(` across `Tests/`: no hits); the
`Equatable` comparisons in `Tests/VaultBatchMoveTests.swift:122` and
`Tests/FolderFileOperationTests.swift` compare `.failures` and whole outcomes that will carry
an empty `refusals` on both sides. **Update tests and call-sites asserting the old behaviour:**
readers of `.failures` in `Sources/App/VaultController+Folders.swift:45,102` and
`Sources/App/VaultController+Files.swift:42,71` must not start seeing refusals folded into
`failures` — that is precisely the distinction ADR-0046 §D4 bought.

**`VaultPlanApplication.apply(_:writing:)`, synchronous overload** — five of its eight callers
start being able to throw `VaultWriteRefusal`. Callers:
`BoardFileOperations.swift:160,167`, `FolderFileOperations.swift:398,404`,
`FolderFileOperations+Move.swift:119`, `NoteFileOperations.swift:231,237`. The `.noteChanges`
ones (`:160`, `:398`, `:231`) keep the unguarded `store.write` — ADR-0054 §D8.

**Run the full suite, not just the new files.** `CanvasStore`, `VaultPlanApplication` and the
four outcome structs are read by the vault, task, pratiche and connector suites; a contract
change here can go red in a module this chain never opens. `PergamenumTests` in full, plus the
two tool builds (`perg`, `pergamenum-mcp`), before the branch is considered done.

---

## Risks & HITL gates

- **HITL — commit, push, PR, merge.** None of them is this chain's to take. `main` is never
  committed to directly (CLAUDE.md); the branch is `fix/pg-213`, already correct.
- **HITL — `TODO.md` and `CLAUDE.md` edits** (Task 7) change the project's own record; show the
  diff before writing (global rule: never overwrite an existing file without showing the diff).
- **HITL — closing issue #213 on GitHub** is a human action at merge, not a step in the plan.
- **Risk: the async cascade, if §D3 is quietly reopened.** If the coder decides mid-task to
  route the board save through `VaultSession.writeFile` after all, `flushPendingSave` becomes
  `async` and its four callers follow — two of them SwiftUI view code
  (`WorkspaceView+FolderVerbs.swift:257`, `WorkspaceView.swift:88`), which reaches seven
  verbs. ADR-0043 measured this exact shape at 3-4x its own estimate. If it looks necessary,
  stop and re-open §D3 explicitly rather than letting the diff grow.
- **Risk: `type_body_length`.** `WorkspaceController.swift` is at 607 lines before this chain
  and Task 5 adds state to it. The conflict verbs go in `WorkspaceController+Conflict.swift`
  for that reason. SwiftLint is **not** on CI (ADR-0044), so nothing will say so — run it by
  hand. `PG-202` is the open ticket for the same limit on a neighbouring file.
- **Risk: a false `.diverged`.** If `CanvasDocument.encoded()` is not stable for an unchanged
  document (key ordering, number formatting), `base` and `theirs` could differ where nothing
  changed. Task 1's `base == theirs → .adopted(mine)` case covers the byte-level variant; the
  coder should confirm `encoded()` is deterministic before relying on it, since
  `CanvasTests.roundTripsAnObsidianCanvas` pins the format but not necessarily the ordering.
- **Risk: `pergamenum-` prefixed keys.** A `.canvas` node carries `pergamenum-crop`
  (ADR-0020) and `pergamenum-*` text properties (ADR-0027) inside `unknown`. Task 1 treats an
  `unknown` difference as `.diverged`; confirm a repoint write does not re-serialise those keys
  differently, or every repoint on a cropped board will read as a conflict.
- **Risk: `detach()` on a conflicted board.** This is the one path where work can still be
  lost — the window closes and the in-memory document goes with it. Task 5 records a problem;
  it does not block the close, and deliberately so. Flag it for a hand check.
- **No externally provisioned resource is needed.** No network, no API key, no OAuth, no new
  env var, no port, no cloud console. Everything runs against a throwaway directory
  (`CanvasTemporaryRoot`, `Tests/CanvasTestSupport.swift`).
- **Dependency on nothing new.** No SPM package, no `Tuist/Package.swift` edit, no
  `tuist install`. `tuist generate --no-open` is needed only because Tasks 1 and 5 add files.
- **Hand check before merge** (not automatable, and the ticket was found by hand):
  open a board, edit a text card, and within the one-second window rename a note that board
  references from the Note sidebar. The wikilink rewrite must survive, the card edit must
  survive, and no problem must be recorded. Then repeat with the rename happening ten seconds
  before the next card drag — the stale-forever case, which is the half a flush would miss.
- **`scripts/uitests.sh --affected` at merge**, per CLAUDE.md's merge-gate rule. It is
  advisory and does not block. No GUI test is added by this chain.

---

TEST-CMD CANDIDATE: `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test`
TEST-CMD MODE: brownfield
