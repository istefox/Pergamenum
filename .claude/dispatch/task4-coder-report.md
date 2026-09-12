# Task 4 — Three vault walks become one, built from the boundary (R-03)

## Coder Report

### Files modified

- `Sources/Core/Vault/VaultWalk.swift` — the tester's stub becomes the real walk: one
  `FileManager.enumerator(at:includingPropertiesForKeys:options:)` with
  `[.skipsPackageDescendants]` started at the boundary-resolved directory, `VaultLayout`-driven
  `skipDescendants()`, root prefix computed once in `init`, `keys`-gated metadata.
- `Sources/Vault/VaultScanner.swift` — `scan()` walks through `VaultWalk` (four keys); its own
  enumerator, exclusion branch and per-file `relativePath` calls are gone, its cache-reuse logic
  is untouched. `relativePath(of:under:)` kept, with a doc comment naming its one remaining
  caller.
- `Sources/Vault/CanvasStore.swift` — `walk()` collects folders and boards from a `VaultWalk`
  built on the store's own `boundary`.
- `Sources/Vault/FolderFileOperations.swift` — `walk(_:)` counts through a `VaultWalk` scoped with
  `subfolder:`; the folder path now resolves through the boundary, so one that escapes the vault
  returns `nil` instead of being walked.

No test file was touched. No file outside the four above changed.

### Sub-steps

| # | Sub-step | State |
| --- | --- | --- |
| 1 | One enumerator, `[.skipsPackageDescendants]`, rooted at `boundary.url(for: subfolder)` | done — `subfolder: ""` uses `boundary.root` directly, as the tester's stub documents (the resolver refuses `""`) |
| 2 | `VaultLayout.isExcludedDirectory` decides, walk calls `skipDescendants()` | done — an excluded directory is not yielded either, so nothing under it is ever seen |
| 3 | Root standardised once in `init`, relative paths by prefix-drop, `PG-140`/`perf-VaultScanner.swift-a0b` closed | done, with a correction — see Key decisions #1 |
| 4 | `keys` defaults to `[]`, no per-file `resourceValues`; `VaultScanner` passes its four | done — with `keys: []` the walk reads `isDirectory`/`name` off the URL and makes no `resourceValues` call at all |
| 5 | Three callers rewritten as calls; `VaultScanner` keeps its cache-reuse | done — `IndexCache.Entry`/`BoardEntry` reuse stayed in `VaultScanner`, nothing migrated into the walk |
| 6 | `relativePath(of:under:)`: check for external callers before deleting | done — `VaultWatcher.swift:82` calls it, so it stays unchanged; only its doc comment is new |

### Key decisions

1. **The root prefix comes from `.canonicalPathKey`, not from `root.path`.** Measured on this
   machine (three scratch probes, macOS 26): a walk started at
   `/var/folders/…/T/vault/` hands back `/private/var/folders/…` URLs, while both
   `URL.standardizedFileURL` and `URL.resolvingSymlinksInPath()` *strip* a `/private` prefix — so
   `VaultBoundary.root.path` and the enumerator's spelling disagree by exactly that prefix, in
   opposite directions. The old `relativePath(of:under:)` hid this by standardising **both** sides
   per file. A prefix-drop against `root.path` would therefore have matched nothing in any
   temporary-directory fixture and silently degraded every relative path to a bare file name.
   `boundary.root.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath` is the spelling the
   enumerator uses (verified for a plain temp dir, a symlinked root and a real home directory), it
   is read once in `init`, and it falls back to `root.path` when the root does not exist.
2. **`CanvasStore.walk()` and `FolderFileOperations.walk(_:)` keep passing
   `[.isDirectoryKey, .nameKey]`** rather than dropping to the new `[]` default. Those two only
   need `isDirectory` and `name`, which the walk can now derive from the URL for free — but
   `.isDirectoryKey` follows a *symlink to a directory* where the URL's own trailing separator does
   not. Switching them would have changed whether a symlinked subdirectory counts as a folder in
   the Workspace tree and in a delete dialog's count. That is behaviour beyond the frozen
   equivalence set, so it was left alone. The `keys: []` path is exercised by `VaultWalkTests`.
3. **`Entry.relativePath` keeps the enumerator's trailing separator for a directory**
   (`01 Progetti/`), and `CanvasStore` keeps its one-line strip with its original comment.
   Normalising it inside the walk would have been tidier, but no test constrains it and it is not
   in the plan.
4. **`VaultWalk.init` throws only from the boundary; `forEach` tolerates a nil enumerator by
   yielding nothing.** Measured: `FileManager.enumerator(at:)` is **not** nil for a missing path
   or for a plain file — it returns an enumerator that yields nothing. So every caller's old
   `guard let enumerator … else` branch was already dead, and each caller's `else` branch now
   guards the `try?` instead, unchanged in wording and in effect.
5. **`FolderFileOperations.walk(_:)` keeps its own `fileExists(_:isDirectory:)` check.** Given #4,
   that check — not the enumerator — is the only thing that tells "the folder is gone" (`nil`,
   `PG-048`) from "the folder is empty" (`(0, 0)`). Moving it into the walk would have flipped
   `VaultScanner`'s answer for a vanished vault from an empty outcome to a failure row.
6. **`forEach` builds a fresh enumerator per call.** An enumerator is a reference type (a
   `Sendable` struct may not hold one) and is consumed by one pass; `VaultWalkTests` iterates the
   same walk twice, and a value that silently yields nothing the second time would be a trap.

### Verification

```
xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' \
  -derivedDataPath ".build/DerivedData" -only-testing:PergamenumTests test
```

- Exit code **0**, `** TEST SUCCEEDED **`.
- `✔ Test run with 2884 tests in 136 suites passed after 18.301 seconds.` Zero `✘` marks in the
  whole log.
- All six `VaultWalkTests` green (were 5 red / 1 green per the tester's report):
  `dotDirectoriesAreExcludedEntirelyIncludingTheirDescendants`,
  `subfolderScopingYieldsOnlyThatSubtreeWithRootMeasuredRelativePaths`,
  `subfolderEscapingTheVaultThrowsViaTheInheritedBoundary`,
  `symlinkedVaultRootYieldsCorrectRelativePathsAndNoEntryEscapes`,
  `emptyKeysYieldNilMetadataWhileTheFourKeySetPopulatesIt`,
  `newWalkMatchesVaultScannerIndexingBeforeThisTask`.
- `CanvasStoreTests` and `FolderFileOperationTests`: unchanged and still green, including the four
  `contentCounts…` tests that pin the `nil`-vs-empty and dot-directory behaviour. Neither file was
  edited.
- Extra check, not required by the brief: `xcodebuild -scheme perg … build` → `** BUILD SUCCEEDED **`
  (exit 0). `VaultWalk.swift` is Foundation-only and lands in `sharedSources` through the existing
  `Sources/Core/**` glob, so ADR-0001 §D1 is satisfied and no manifest edit was needed.

Project generation in this fresh worktree needed `tuist install` before `tuist generate --no-open`,
as always.

### Drafted commit

```
refactor(vault): unify the three vault walks into VaultWalk (ADR-0041 R-03)

VaultScanner.scan(), CanvasStore.walk() and FolderFileOperations.walk(_:) each
carried their own FileManager.enumerator, their own VaultLayout.isExcludedDirectory
check and their own call to skipDescendants(); two of the three said in a doc comment
that they mirrored a third, which is how they drifted. They now call one
Sources/Core/Vault/VaultWalk.swift, built from a VaultBoundary rather than from a bare
URL, so a walk can no longer be the way back into the vault layer around the guard.

The root is turned into a path prefix once in init and every entry's relativePath is
that prefix dropped, closing PG-140's perf-VaultScanner.swift-a0b: the old
VaultScanner.relativePath(of:under:) paid a standardizedFileURL per file of every scan.
The prefix is read from .canonicalPathKey, because the enumerator hands back the file
system's spelling (/private/var/...) while URL.standardizedFileURL strips exactly that
prefix - a mismatch the old per-file standardisation of both sides was hiding.

VaultScanner keeps its own cache-reuse logic, which was never a walk concern, and
VaultScanner.relativePath(of:under:) stays for VaultWatcher, whose paths arrive from
FSEvents and have not been canonicalised by anything.
```

### Cleanup

| Item | Disposition |
| --- | --- |
| `…/scratchpad/probe.swift`, `probe2.swift`, `probe3.swift` | kept in the session scratchpad (outside the repo, outside the worktree); they are the measurements behind Key decisions #1 and #4 and nothing in the repo references them |
| `…/scratchpad/test1.log`, `perg.log` | kept in the session scratchpad — build logs, outside the repo |
| `.build/DerivedData` (worktree) | kept, gitignored; the derived-data path the verification command was given |
| Temp branches | none created |
| Debug prints / `TODO`s added to sources | none |

`git status --porcelain` in the worktree lists exactly the four modified `Sources/` files and
nothing untracked.

### Plan deviations

One, and it is a correction rather than a departure: the plan says «the root path is standardised
once in `init`», which read literally means `root.standardizedFileURL`. That value does not match
what the enumerator yields (Key decisions #1), so the once-in-`init` computation is
`.canonicalPathKey` instead. The property the plan asks for — computed once, dropped as a prefix,
no `standardizedFileURL` per file — holds exactly.

Nothing else in the plan proved contradicted by the code.

### Pattern classification

| Pattern | Payload |
| --- | --- |
| REPLACE | Add: `Sources/Core/Vault/VaultWalk.swift:29` real enumerator walk \| Remove: `Sources/Core/Vault/VaultWalk.swift:29` tester stub whose `forEach` yielded nothing |
| REPLACE | Add: `Sources/Vault/VaultScanner.swift:39` `scan()` through `VaultWalk` \| Remove: `Sources/Vault/VaultScanner.swift:46` its own enumerator + exclusion + per-file `relativePath` |
| ADD | `Sources/Vault/VaultScanner.swift:182` doc comment for the surviving `relativePath(of:under:)` |
| REPLACE | Add: `Sources/Vault/CanvasStore.swift:212` `walk()` through `VaultWalk` \| Remove: `Sources/Vault/CanvasStore.swift:213` its own enumerator copy |
| REPLACE | Add: `Sources/Vault/FolderFileOperations.swift:91` `walk(_:)` through `VaultWalk` \| Remove: `Sources/Vault/FolderFileOperations.swift:102` its own enumerator copy |
| MODIFY | `Sources/Vault/FolderFileOperations.swift:78` doc comment: not "mirrors", the same walk |
