## Coder Report

### Files modified

- `Sources/Vault/NoteStore.swift` — `url(for:)` now returns `try boundary.url(for:)` instead of a
  bare `root.appending(path:)`. This one line is what arms the guard at 31 call sites, including
  `VaultSession.moveFile`/`trashFile` and all three raw-bytes writers.
- `Sources/Vault/CanvasStore.swift` — gains `let boundary: VaultBoundary` (delegation, `root` is now
  `boundary.root`); `load(board:)`, `save(_:board:)` and `createBoard(named:in:)` resolve through it.
- `Sources/Vault/ThumbnailStore.swift` — stored `root: URL` becomes `boundary: VaultBoundary`;
  `thumbnail(for:width:)` answers a `Task` whose value is `nil` before any file is read or memoised.
- `Sources/Features/Workspace/WorkspaceController+Files.swift` — `fileURL(for:)` resolves a node's
  `file` through `store.boundary` and answers `nil` on violation.
- `Sources/Features/Workspace/BoardCardMenu.swift` — `BoardCardActions.resolvedOpenURL(for:root:)`
  (the tester's extracted seam) implemented as `try? VaultBoundary(root: root).url(for: path)`.
- `Sources/Features/Pratiche/PraticheController.swift` — `readMessages` resolves every attachment
  name through a `VaultBoundary` rooted at `allegati/`; a refused name is omitted from the row.
- `Sources/Features/Pratiche/PraticaSyncEngine.swift` — gains `boundary`; `directory(_:of:)` becomes
  `throws` and resolves through it, `folderContext(of:)` propagates, `regenerationPreview`'s note
  read resolves through the boundary.

### Sub-steps

- `CanvasStore.load(board:)` / `save(_:board:)` throw on an escaping path, nothing written there: **done**.
- `VaultSession.moveFile(from:to:)` throws on `../` on either side, source stays: **done** (via
  `NoteStore.url(for:)`; the escaping *source* is refused one step earlier by `exists(oldPath)`,
  which the tester already made answer `false` on a violation).
- `VaultSession.trashFile(at:)` throws, nothing reaches the Trash: **done** (same mechanism).
- `ThumbnailStore.thumbnail(for:width:)` answers `nil`, file not read: **done**.
- `WorkspaceController.fileURL(for:)` answers `nil`: **done**.
- `BoardCardMenu` open-in-Finder branch answers `nil`: **done**.
- `PraticheController.readTimeline` omits an escaping attachment: **done**.
- `PraticaSyncEngine.regenerationPreview` + `directory(_:of:)` refuse, escaped file never read: **done**.
- The three raw-bytes writers (`FolderFileOperations.swift:322`, `BoardFileOperations.swift:172`,
  `:286`) record a failure and write nothing outside the root: **done** (the tester's `try
  store.url(for: change.path)` now actually throws; each sits inside a `do/catch` that appends to
  `failures`). `moveBoard`'s destination move throws before the loop, as the test asserts.
- `CanvasStore.url(forBoard:)` itself made throwing: **left out** — see Plan deviations.

### Key decisions

1. **`CanvasStore.url(forBoard:)` keeps its non-throwing signature.** The ADR's Context table names
   it as a guarded site, but `Tests/CanvasDuplicateTests.swift:167` calls it without `try`, and the
   test-authoring scope restriction forbids me touching `Tests/`. Making it `throws` would not
   compile the test target. Instead every operation that actually reads or writes bytes through it
   (`load`, `save`, `createBoard`) resolves through `boundary` directly, and the accessor carries a
   doc comment saying it is a "would-be" path for existence probes only. Its four surviving callers
   (`WindowPlace.swift:69`, `WorkspaceView+FolderVerbs.swift:198`, and two inside `CanvasStore`) are
   all `fileExists` probes, never a read or a write. Net effect on security is nil; the residual
   risk is that a future caller uses the accessor to obtain a URL it then reads. Flagged for a
   follow-up task that may edit the test.
2. **`CanvasStore.boundary` is internal, not `private` like `NoteStore.boundary`.**
   `WorkspaceController.fileURL(for:)` resolves a node's `file` against the same store, and the ADR
   is explicit that a second boundary built beside the first is the drift this chain removes.
3. **`PraticheController`'s attachment boundary is rooted at `allegati/`, not at the vault.** This
   is the one non-mechanical decision in the task. `<pratica>/allegati/../../../secret.pdf`
   standardises back to a path *inside* the vault root, so a vault-rooted check accepts it and the
   test (`$0.name.contains("..")`) still fails. An attachment entry is a file *name*, so the
   directory that bounds it is `allegati/`, and rooting the resolver there refuses anything leaving
   it. Reasoning is in the code comment.
4. **`directory(_:of:)` builds one relative string** (`"\(folder)/\(name)"`, with an `isEmpty`
   guard) rather than two appends. Verified with a scratch script that `standardizedFileURL`
   collapses a `//` from a trailing-slash `praticaFolder`; the only remaining difference is the
   trailing slash on the returned directory URL, which no caller reads (`contentsOfDirectory(atPath:)`
   and `.appending(path:)` are indifferent). Both `SyncRequest` construction sites pass a
   tree-derived `praticaPath` with no trailing slash anyway.
5. **`ThumbnailStore` now resolves symlinks on its root**, which `VaultBoundary.init` does and the
   old raw `root` did not. A rendered file URL may now be the symlink-resolved spelling. This is
   the behaviour `NoteStore` has always had for every note; no test moved.
6. **No test file touched**, and no test found contradicting the ADR/plan. The 11 tests were taken
   as authoritative throughout.

### Verification

- command: `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -derivedDataPath ".build/DerivedData" -only-testing:PergamenumTests test`
- exit_code: 0
- result: **PASS — 2878 tests in 136 suites, 0 failures.** All 11 `VaultBoundaryCallSiteTests` pass
  (each confirmed individually by name in the log, not inferred from the total). Nothing regressed:
  no pre-existing red test was observed in this worktree.
- Preceded by `tuist install && tuist generate --no-open` — required because a fresh agent worktree
  has no `Tuist/.build`, so there is no `.xcworkspace` to build until it has run once. No file was
  added, removed or moved; `Project.swift` is untouched.
- Additional builds, because `NoteStore.swift` and `CanvasStore.swift` are in `sharedSources` and a
  change there can break the connectors (CLAUDE.md, ADR-0007 §D2):
  - `xcodebuild -workspace Pergamenum.xcworkspace -scheme perg -destination 'platform=macOS' build` → **BUILD SUCCEEDED**
  - `xcodebuild -workspace Pergamenum.xcworkspace -scheme pergamenum-mcp -destination 'platform=macOS' build` → **BUILD SUCCEEDED**
- The UI suite was not run (out of scope for a task-level dispatch; CLAUDE.md requires it before the
  merge to `main`, not per task).

### Drafted commit

```
fix(vault): route every guarded call site through VaultBoundary

NoteStore.url(for:) resolves through the boundary instead of joining a
caller-supplied path onto the root by hand, which arms the guard at all
31 of its call sites at once - including VaultSession.moveFile/trashFile
and the three raw-bytes writers in FolderFileOperations/BoardFileOperations
that bypass NoteStore.write, the tenth gap ADR-0041's Context section names
separately.

The sites whose enclosing function cannot throw refuse by answering
nothing, per ADR-0041 §D2: ThumbnailStore.thumbnail(for:width:) yields a
task whose value is nil before the file is read or memoised, and
WorkspaceController.fileURL(for:) answers nil. BoardCardMenu's
open-in-Finder branch refuses through BoardCardActions.resolvedOpenURL(
for:root:), a pure function extracted from open(_:) because driving
NSWorkspace is not a testable seam.

CanvasStore gains its own VaultBoundary by delegation - it already
resolved its root - and load/save/createBoard go through it.
PraticaSyncEngine's directory(_:of:) becomes throwing, so a praticaFolder
escaping the vault is refused before the directory is listed rather than
after something has been read out of it.

PraticheController.readTimeline bounds an attachment name at allegati/
rather than at the vault, deliberately: <pratica>/allegati/../../../x.pdf
standardises back to a path inside the vault root, so a vault-level check
would wave through a name the pratica does not own. A refused name is
omitted from the row; the message still shows.

Refs ADR-0041 §D2, R-01, R-02, PG-122.
```

### Cleanup

- `/private/tmp/claude-501/.../scratchpad/task2-test.log` — kept, in the session scratchpad outside
  the project. Not in the repository.
- `/private/tmp/claude-501/.../scratchpad/slash.swift` — scratch script written to verify that
  `standardizedFileURL` collapses `//`. Kept in the scratchpad, outside the project.
- `.build/DerivedData/` — build output in the worktree, already gitignored (`git status` is clean
  apart from the seven modified sources).
- No debug print, no `TODO`, no temporary branch, no stash entry created. `git status --porcelain`
  shows exactly the seven `M` lines and nothing untracked.

### Plan deviations

1. **`CanvasStore.url(forBoard:)` was not made `throws`**, though the ADR's Context table lists it.
   Blocked by the test-authoring scope restriction: `Tests/CanvasDuplicateTests.swift:167` calls it
   without `try`. Resolution taken: guard the three byte-touching operations instead. Minimal
   follow-up if the orchestrator wants the accessor itself closed: the tester adds `try` at that one
   line, then the accessor becomes `throws` and its four probe callers take `try?`.
2. **Two adjacent gaps observed and deliberately not fixed** (not in the ADR's table, not in the
   brief's list, so fixing them would be scope creep — reporting rather than silently widening):
   - `WorkspaceController+Files.swift:44`, `loadEmailHeaders(for:)`, reads a `.canvas` node's `file`
     with a raw `store.root.appending(path:)`. That is the *same untrusted input* as
     `fileURL(for:)` on line 12, which this task did guard — the two sit 30 lines apart in one file.
     My assessment: this is worth closing, and it is a one-line change of exactly the shape this
     task used. It belongs in this chain rather than in a later one.
   - The vault layer still has ~35 raw `root.appending(path:)` joins (`grep -rn "root\.appending(path:" Sources/`),
     most of them *directory*-level: `FolderFileOperations.swift:295/300/352` and
     `FolderFileOperations+Move.swift:108` move and trash whole folders from a caller-supplied
     folder path. ADR-0041's table counts nine *file* sites; the directory-level joins are the same
     class of gap and are covered by no task in this plan that I can see. Worth an explicit decision
     by the architect: either a `VaultBoundary.directoryURL(for:)` sibling in a later task, or a
     stated reason the folder paths are trusted by provenance.

### Pattern classification

| # | Pattern | Target |
|---|---|---|
| 1 | REPLACE | `NoteStore.swift:76` boundary resolve ← tester's placeholder hand-join |
| 2 | REPLACE | `CanvasStore.swift:19-31` `boundary` property + delegated `root` ← bare `resolvingSymlinksInPath` |
| 3 | REPLACE | `CanvasStore.swift:48` `load` boundary resolve ← `url(forBoard:)` |
| 4 | REPLACE | `CanvasStore.swift:57` `save` boundary resolve ← `url(forBoard:)` |
| 5 | REPLACE | `CanvasStore.swift:135` `createBoard` boundary resolve ← `url(forBoard:)` |
| 6 | REPLACE | `ThumbnailStore.swift:18` `boundary` ← stored `root: URL` |
| 7 | REPLACE | `ThumbnailStore.swift:29` `VaultBoundary(root:)` ← `self.root = root` |
| 8 | ADD | `ThumbnailStore.swift:45` `guard ... else { return Task { nil } }` |
| 9 | REPLACE | `WorkspaceController+Files.swift:17` `store.boundary.url(for:)` ← `store.root.appending` |
| 10 | REPLACE | `BoardCardMenu.swift:174` `VaultBoundary(root:).url(for:)` ← `root.appending(path:)` |
| 11 | REPLACE | `PraticheController.swift:750` `allegati/`-rooted boundary ← bare attachments URL |
| 12 | REPLACE | `PraticheController.swift:795` `compactMap` + resolve ← unchecked `map` |
| 13 | ADD | `PraticaSyncEngine.swift:128` `boundary` property |
| 14 | REPLACE | `PraticaSyncEngine.swift:1049` `directory(_:of:) throws` ← double raw append |
| 15 | MODIFY | `PraticaSyncEngine.swift:298,313` `folderContext` throws, two `try` added |
| 16 | MODIFY | `PraticaSyncEngine.swift:159,755` `try folderContext(of:)` at both callers |
| 17 | REPLACE | `PraticaSyncEngine.swift:759` `boundary.url(for: notePath)` ← `vaultRoot.appending` |
| 18 | MODIFY | `PraticaSyncEngine.swift:801,866` `try directory(...)` in `commit` |
| 19 | ADD | `.claude/dispatch/task2-coder-report.md` this report |
