# PG-080 — deduplicate the moved-note tuple across outcome types

**Topic slug:** pg-080-dedupe-moved-note-tuple

## Objectives

`FolderFileOperations.RenameOutcome`, `FolderFileOperations.MoveOutcome` and
`VaultSession+Move.swift`'s `MoveBatchOutcome` each independently declare the same anonymous
tuple shape, `[(old: String, new: String)]`, to record a note that moved as the side effect of a
folder-level rename or move. Replace all three with one shared named type, `MovedNote`, reused
as-is at every site. Type-only refactor, no behavior change.

This is the surviving half of TODO.md's PG-080 entry. The other half — two near-identical
`OperationError` enums across `BoardFileOperations`/`FolderFileOperations` — was already resolved
this session by PG-066, which unified all three file-operations types' `OperationError` enums
(Note, Folder, Board) into one shared `FileOperationError` at
`Sources/Core/Vault/FileOperationError.swift`. That work is out of scope here.

## Scope

**In scope:**
- New type `MovedNote` (struct, fields `old: String`, `new: String`) at
  `Sources/Core/Vault/MovedNote.swift`.
- Replace the anonymous tuple in three declarations:
  - `Sources/Vault/FolderFileOperations.swift:226` — `RenameOutcome.movedNotes`
  - `Sources/Vault/FolderFileOperations+Move.swift:69` — `MoveOutcome.movedNotes`
  - `Sources/Vault/VaultSession+Move.swift:31` — `MoveBatchOutcome.movedNotes`
- Update every construction and read site (see Architecture below for the full enumeration).

**Out of scope:**
- `OperationError` dedup — already done by PG-066.
- `RenameOutcome.rewrittenPaths` (a separate, unrelated field noted in TODO.md's PG-070, not
  touched here).
- Any behavior change to how notes are discovered, moved, or reported.

## Stack

Swift 6, no new dependency. Follows the exact precedent of PG-065 (`BoardPath`/`FolderPath`
wrapper types) and PG-066 (`FileOperationError`) from this same session.

## Architecture

**New file `Sources/Core/Vault/MovedNote.swift`:**
```swift
struct MovedNote {
    var old: String
    var new: String
}
```
Lives under `Sources/Core/**`, already covered by `Project.swift`'s `sharedSources` glob — no
`Project.swift` edit needed, same placement pattern as `FileOperationError.swift` (PG-066) and
`BoardPath.swift` (PG-065). Both current call sites are under `Sources/Vault/`, which is app-only
today; placing the shared type under `Sources/Core/Vault/` makes it reachable from
`perg`/`pergamenum-mcp` as well, consistent with the session's established convention for shared
vault-layer types.

No `Equatable`/`Hashable` conformance — verified this session that no test or call site compares
a `MovedNote` value for equality; every read site pattern-matches on `.old`/`.new` via closures
or keypaths (`$0.old == ...`, `.map(\.old)`), which works identically whether the type conforms to
`Equatable` or not.

**Change the three declarations** from `[(old: String, new: String)]` to `[MovedNote]`:
- `FolderFileOperations.RenameOutcome.movedNotes`
- `FolderFileOperations.MoveOutcome.movedNotes` (in `FolderFileOperations+Move.swift`)
- `VaultSession+Move.swift`'s `MoveBatchOutcome.movedNotes`

**Construction sites** (tuple literals become `MovedNote(...)`):
- `Sources/Vault/FolderFileOperations.swift:253` — `.map { (old: $0, new: ...) }` → `.map { MovedNote(old: $0, new: ...) }`
- `Sources/Vault/FolderFileOperations+Move.swift:92` — same pattern
- `Sources/Vault/VaultSession+Move.swift:88` — `outcome.movedNotes.append((old: ..., new: ...))` → `outcome.movedNotes.append(MovedNote(old: ..., new: ...))`

**Read sites** (unaffected — `.old`/`.new` field access, `.map(\.old)`, `.contains { $0.old == ... }`
all continue to compile unchanged against a named struct with the same field names):
- `Sources/Vault/VaultController+Move.swift:163`
- `Sources/Vault/VaultController+Folders.swift:44`
- `Sources/Vault/VaultSession+Folders.swift:29`
- `Sources/Vault/VaultSession+Move.swift:102,105` (the aggregation loop and `append(contentsOf:)`
  pass-through between `MoveOutcome`/`RenameOutcome` and `MoveBatchOutcome` — this is the site
  that most benefits from the shared type, since today it silently relies on both tuples having
  identical shape)

**Test sites** (assertions on `.old`/`.new` unaffected; only the local `var outcome`/pattern-match
declarations that name the tuple type explicitly, if any, would need updating — grep did not find
any such explicit type annotation, only inferred usage via `.contains { $0.old == ... }` and
`.map(\.old)`):
- `Tests/VaultMoveTests.swift:155`
- `Tests/FolderFileOperationTests.swift:414,441,442`
- `Tests/VaultSessionFolderOperationsTests.swift:80,81`

As with PG-065/PG-066, this grep-based enumeration is the starting list, not the completeness
guarantee — `xcodebuild build` after the edits is the actual oracle for a type-only refactor: a
missed site is a compile error, not a silent gap.

## Data model

```swift
struct MovedNote {
    var old: String
    var new: String
}
```

## API

No public API surface — `MovedNote` is used internally by `FolderFileOperations`/
`VaultSession+Move` and their callers (`VaultController+Move`, `VaultController+Folders`,
`VaultSession+Folders`). No connector-facing (`VaultAPI`) change.

## Edge cases

- **`FolderFileOperations.MoveOutcome` and `RenameOutcome` are structurally similar but not
  identical** (verified this session for the earlier PG-066 scope decision): `MoveOutcome` also
  carries `rewrittenPaths: [String]`, which `RenameOutcome` does not. This refactor touches only
  the `movedNotes` field each declares independently — it does not unify the two outcome types
  themselves, which remain distinct (out of scope, matches PG-066's precedent of not merging
  `RenameOutcome`/`MoveOutcome` types wholesale).
- **`VaultSession+Move.swift:105`'s `append(contentsOf:)` pass-through** already assumes
  `FolderFileOperations`'s `movedNotes` and `VaultSession`'s own `movedNotes` are the same array
  element type — today this works only because both are the exact same anonymous tuple shape
  `(old: String, new: String)`, which is fragile (a field reorder or rename on one side would
  silently break `Array.append(contentsOf:)`'s type inference, or fail loudly with a confusing
  error at a distant call site). This is the concrete risk the shared `MovedNote` type removes.

## Success criteria

- [ ] R-01 — `Sources/Core/Vault/MovedNote.swift` declares `struct MovedNote { var old: String; var new: String }`, reachable from both `perg` and `pergamenum-mcp` via the existing `sharedSources` glob with no `Project.swift` edit
- [ ] R-02 — `FolderFileOperations.RenameOutcome.movedNotes` is typed `[MovedNote]`
- [ ] R-03 — `FolderFileOperations.MoveOutcome.movedNotes` (in `FolderFileOperations+Move.swift`) is typed `[MovedNote]`
- [ ] R-04 — `VaultSession+Move.swift`'s `MoveBatchOutcome.movedNotes` is typed `[MovedNote]`
- [ ] R-05 — every construction site builds a `MovedNote(old:new:)` value instead of an anonymous tuple literal
- [ ] R-06 — every read site (`VaultController+Move.swift`, `VaultController+Folders.swift`, `VaultSession+Folders.swift`, and `VaultSession+Move.swift`'s own aggregation loop) compiles unchanged against the new named type
- [ ] R-07 — `.claude/test-cmd` (`-only-testing:PergamenumTests`) builds clean and passes 100%
- [ ] R-08 — `tuist generate --no-open` confirms the new file is picked up by the existing `Sources/Core/**` glob with no `Project.swift` edit
