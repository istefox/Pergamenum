# Task 2 coder follow-up — two unguarded boundary sites

## Coder Report

### Files modified

- `Sources/Vault/CanvasStore.swift` — `url(forBoard:)` becomes `throws` and delegates to
  `boundary.url(for:)`; `boardNameIsAvailable` absorbs the new `throws`.
- `Sources/App/WindowPlace.swift` — `isReachable`'s `.workspaceBoard` branch absorbs the
  new `throws`.
- `Sources/Features/Workspace/WorkspaceView+FolderVerbs.swift` — `performFolderVerb`'s
  landing-file probe absorbs the new `throws`.
- `Sources/Features/Workspace/WorkspaceController+Files.swift` — `loadEmailHeaders(for:)`
  resolves through `store.boundary` instead of a raw `store.root.appending(path:)`.

### Sub-steps

**Fix 1 — `CanvasStore.url(forBoard:)` → `throws`: done.**

The accessor now delegates rather than duplicating the check:

```swift
func url(forBoard board: String) throws -> URL {
    try boundary.url(for: board)
}
```

`load`/`save`/`createBoard` were left calling `boundary.url(for:)` directly, exactly as the
main coder pass wired them — the brief asked for the accessor to delegate the same way, not
for the three to be re-routed through the accessor. Rewriting them would have been a
behaviour-neutral churn hunk outside the brief.

All call sites across `Sources/` (`grep -rn "url(forBoard"`), every one caught:

| Call site | Kind | Resolution |
|---|---|---|
| `CanvasStore.swift:153` (`boardNameIsAvailable`) | `Bool` probe, in-file | `try?` + `return false` |
| `App/WindowPlace.swift:66` (`isReachable`) | `Bool` probe | `try?` in the existing `guard`, `return false` |
| `Workspace/WorkspaceView+FolderVerbs.swift:197` | `Bool` probe in a `guard` | `try?` as a new `guard` clause, falls into the existing "nothing followed" branch |
| `Tests/CanvasDuplicateTests.swift:167` | test | already carried `try` (tester's follow-up) — untouched |

No connector (`Sources/CLI`, `Sources/MCPServer`) call site exists, so neither tool build's
signature surface changed.

**Fix 2 — `loadEmailHeaders(for:)`: done.** One line, plus a doc paragraph:

```swift
guard let fileURL = try? store.boundary.url(for: relativePath) else { return }
```

replacing `let fileURL = store.root.appending(path: relativePath, directoryHint: .notDirectory)`.
Signature untouched: the method already returns `Void` and already had two early `return`s
meaning "nothing to show for this card", so a boundary violation reuses that convention and
needs no `throws`. Its one caller (`NodeCard.swift:115`, inside a `.task`) is unchanged.

### Key decisions

1. **`boardNameIsAvailable` answers `false` on a violation, not `true`.** The `Bool` means
   "the creation sheet may accept this name". A name resolving outside the vault is one
   `createBoard` would refuse, so reporting it available would offer a name whose verb then
   throws. Both reasons for "no" collapse into the one `false` the signature already had.
2. **`loadEmailHeaders` reused `store.boundary`, not `fileURL(for:)`.** `fileURL(for:)` takes
   a `CanvasNode`; `loadEmailHeaders` takes the already-unwrapped `String` path. Reusing it
   would have meant changing the method's parameter or re-synthesising a node. Going straight
   to `store.boundary.url(for:)` is the same resolver through the same store — the shape
   `fileURL(for:)` itself uses one line up.
3. **No behaviour change for legitimate paths.** `CanvasStore.init` already sets
   `self.root = boundary.root`, so both fixes resolve against an identical root; the only
   delta for an in-vault path is `.standardizedFileURL`, which is a no-op on a plain relative
   path.

### Verification

Fresh worktree had no generated workspace, so setup ran first (no file was added, moved or
removed — this is the worktree's first generation, not a manifest change):

```
tuist install && tuist generate --no-open
```

Then:

```
xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum \
  -destination 'platform=macOS' -derivedDataPath ".build/DerivedData" \
  -only-testing:PergamenumTests test
```

**Exit code 0 — `** TEST SUCCEEDED **`.**
`✔ Test run with 2878 tests in 136 suites passed after 14.377 seconds.` Zero `✘` lines in the
whole log.

**On the expected count.** The brief expected ~2879, "one more than before from the tester's
follow-up". The tester's follow-up added **no test** — its own report states it only added
`try` to an existing call site inside the already-`throws`
`duplicatingChangesOnlyTheCanvasFilesBytesNotTheFolderListing`, and touched nothing else. So
2878 is the unchanged baseline, and it is the right number here, not a missing test. (A raw
`grep -c "✔ Test "` returns 2879 because Swift Testing's own summary line starts with `✔ Test
run with…` and matches the same prefix — that is likely where the off-by-one expectation came
from.)

Nothing was red before and nothing is red now, which is what this task wanted: two
already-passing-but-unguarded sites tightened without regression.

### Drafted commit

```
refactor(vault): guard two remaining board/email path resolutions

`CanvasStore.url(forBoard:)` resolved a board path by joining it onto the
root directly, so the "is there a board here" probe answered about a
different file than `load`/`save`/`createBoard` would touch — the only
three that went through `VaultBoundary`. It now delegates to the same
resolver and throws, and its three probe call sites (`boardNameIsAvailable`,
`WindowPlace.isReachable`, `WorkspaceView.performFolderVerb`) answer
"not available" / "not reachable" / "nothing followed" on a violation,
which is what each of their `Bool`s already meant.

`WorkspaceController.loadEmailHeaders(for:)` read a `.canvas` node's `file`
property — the same untrusted JSON `fileURL(for:)` guards one line above —
through a raw `root.appending(path:)`. It resolves through the store's
boundary too; a path escaping the vault memoises nothing and leaves the
card's header block empty, the early return the method already had for a
file it could not read.

No signature was widened beyond the accessor itself and no behaviour
changed for a path inside the vault.

Refs ADR-0041 §D2
```

### Cleanup

- `/private/tmp/.../scratchpad/test.log` — xcodebuild output, in the session scratchpad,
  outside the repo. Left there; it is not in the worktree.
- `Tuist/.build/` and `.build/DerivedData/` — generated by `tuist install` / `xcodebuild`,
  both gitignored (`git status --porcelain` lists only the four modified sources, no
  untracked entries).
- No temp branch created, so nothing to register with `temp-branch-reconcile.sh`.
- No debug print, no `TODO`, no scratch script added to the repo.

### Plan deviations

None. Both fixes landed as specified, no file added/removed/renamed, nothing under `Tests/`
touched, no commit made.

### Recommendation for the tester (not implemented — out of my scope)

`loadEmailHeaders(for:)` now refuses a boundary violation but has no adversarial test, unlike
its sibling `fileURL(for:)` (covered by
`workspaceControllerFileURLAnswersNilForANodeWhoseFileEscapesTheVault` in
`Tests/VaultBoundaryCallSiteTests.swift`). A test is warranted and cheap, and it would be
genuinely adversarial rather than trivially absent: seed a real `.eml` outside the vault,
call `loadEmailHeaders(for: "../../outside.eml")`, and assert
`controller.emailHeaders["../../outside.eml"] == nil` — the unfixed code maps and parses that
file for real, so the assertion fails against the old line and passes against the new one.
The same `CallSiteFixture` (nested `container/level/vault` root) that file already has is the
right fixture. `emailHeaders` is not `private(set)`, so it is readable from the test directly.

`CanvasStore.url(forBoard:)` needs no new test of its own: it is now literally
`try boundary.url(for:)`, and `canvasStoreLoadRefusesAPathEscapingTheVault` /
`canvasStoreSaveRefusesAPathEscapingTheVaultAndWritesNothingThere` already pin that resolver's
refusal through the same store.

### Pattern classification

| # | Pattern | Payload |
|---|---|---|
| 1 | `REPLACE` | Add: `Sources/Vault/CanvasStore.swift:39` `url(forBoard:) throws` delegating to `boundary.url(for:)` \| Remove: `Sources/Vault/CanvasStore.swift:39` unguarded `root.appending(path:)` resolution |
| 2 | `MODIFY` | `Sources/Vault/CanvasStore.swift:153` absorb the accessor's `throws` — a name resolving outside the vault is not available |
| 3 | `MODIFY` | `Sources/App/WindowPlace.swift:66` `.workspaceBoard` reachability absorbs the accessor's `throws`, mirroring the `.note` branch above it |
| 4 | `MODIFY` | `Sources/Features/Workspace/WorkspaceView+FolderVerbs.swift:197` landing-file probe absorbs the accessor's `throws`, same "nothing followed" branch |
| 5 | `REPLACE` | Add: `Sources/Features/Workspace/WorkspaceController+Files.swift:44` `store.boundary.url(for:)` guarded resolution \| Remove: `Sources/Features/Workspace/WorkspaceController+Files.swift:44` raw `store.root.appending(path:)` |
| 6 | `ADD` | `.claude/dispatch/task2-coder-followup-report.md:1` this report |
