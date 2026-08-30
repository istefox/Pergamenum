# SPEC — PG-066: deduplicate OperationError across Note/Folder/Board file operations

**Topic slug:** pg-066-dedupe-operationerror

## Objective

`NoteFileOperations.swift`, `FolderFileOperations.swift` and `BoardFileOperations.swift` each
independently declare a nested `enum OperationError: Error, CustomStringConvertible` with the
cases `invalidTitle([NoteName.Violation])`, `alreadyExists(String)`, `missing(String)`,
`failed(String)`, and a matching `description` implementation — verified byte-for-byte identical
between `NoteFileOperations` and `BoardFileOperations`. `FolderFileOperations`'s copy carries one
additional case, `wouldNest(String)` (ADR-0026 §D1/§D5, folder-into-itself/descendant refusal),
with a matching extra `description` branch. Replace the three nested enums with one shared
top-level type.

## Scope

**In scope:** the `OperationError` triplication only. One new top-level type,
`FileOperationError`, replacing all three nested `OperationError` declarations and every
construction/catch/test site that names them.

**Out of scope, verified and explicitly rejected:** TODO.md's PG-066 entry also claimed
`RenamePlan`/`RenameOutcome`-shaped DTOs are "near-identical" across the same three files. Read
directly this session: `NoteFileOperations.RenamePlan` (`newPath`, `noteChanges`, `boardChanges`,
`failures`) has no separate `RenameOutcome` counterpart at all;
`FolderFileOperations.RenameOutcome` carries a `movedNotes: [(old: String, new: String)]` field
neither of the other two has; `BoardFileOperations.RenameOutcome` carries only `newPath` and
`failures`. The three types' own doc comments explain deliberately different rewrite behavior per
file kind (which reference classes each rewrites, per ADR-0021/ADR-0022/ADR-0025). These are
structurally similar, not semantically identical — forcing one shared type would conflate three
distinct, deliberately-differentiated behaviors. Not touched by this chain.

`WorkspaceItemKind`, `BoardPath`/`FolderPath` (PG-065) and any other type unrelated to
`OperationError` are untouched.

## Stack

Swift 6, no new dependency, no schema/index change. Type-only refactor: renaming and relocating
an existing error type, no behavior change to any catch site's logic.

## Architecture

**New file `Sources/Core/Vault/FileOperationError.swift`:**
```swift
enum FileOperationError: Error, CustomStringConvertible {
    case invalidTitle([NoteName.Violation])
    case alreadyExists(String)
    case missing(String)
    case failed(String)
    case wouldNest(String)

    var description: String {
        switch self {
        case .invalidTitle(let violations): "titolo non conforme: \(violations)"
        case .alreadyExists(let path): "esiste già: \(path)"
        case .missing(let path): "non esiste: \(path)"
        case .failed(let reason): reason
        case .wouldNest(let path): "\(path) non può essere spostata dentro sé stessa"
        }
    }
}
```

Lives under `Sources/Core/**` — already covered by `Project.swift`'s `sharedSources` glob, no
manifest edit needed (same placement pattern as PG-065's `BoardPath.swift`). This matters because
only `NoteFileOperations.swift` is itself in `sharedSources` today (reachable from `perg`/
`pergamenum-mcp`); `FolderFileOperations.swift` and `BoardFileOperations.swift` are app-only. A
shared top-level error type under `Sources/Core/**` is reachable from all three call sites
regardless of which target compiles which file, and from both connectors.

**`wouldNest` stays a case on the single shared enum, never split into a separate type
(conversion, not collapse — same principle as PG-065's four discriminated unions).**
`NoteFileOperations` and `BoardFileOperations` simply never construct `.wouldNest` — nothing
enforces that at the type level (Swift has no way to remove a case per call site without a second
type), and that is an accepted, explicit trade-off given the alternative (a generic wrapper plus a
separate per-file-kind case) is more machinery for one extra case.

**Site changes:**
- Delete the three nested `enum OperationError { ... }` declarations from `NoteFileOperations.swift`,
  `FolderFileOperations.swift`, `BoardFileOperations.swift`.
- Every unqualified `OperationError.xxx` construction inside those three files (and
  `FolderFileOperations+Move.swift`, which throws `OperationError.wouldNest`/`.missing`/
  `.alreadyExists`/`.failed` today) becomes `FileOperationError.xxx` — unqualified reference
  works identically since the type is now top-level and in scope everywhere `Sources/Core/**` is
  visible.
- Every external qualified reference — `NoteFileOperations.OperationError`,
  `FolderFileOperations.OperationError`, `BoardFileOperations.OperationError` — becomes
  `FileOperationError`, at every catch site, throw site and test site.

**Known call sites requiring the qualified-name change** (grepped exhaustively this session,
`grep -rn` across `Sources/` and `Tests/` for `OperationError` — the full list, not a sample):
- `Sources/Connector/VaultWrites.swift:117,137,150` — `catch let refusal as NoteFileOperations.OperationError`
- `Sources/Vault/VaultSession+Journal.swift:60,62,73,108,121,162` — `throw NoteFileOperations.OperationError.xxx`
- `Tests/BoardFileOperationsTests.swift:101,111,235,310` — `#expect(throws: BoardFileOperations.OperationError.self)` / `catch BoardFileOperations.OperationError.alreadyExists`
- `Tests/FolderFileOperationTests.swift:178,188,196,299,483,499,514` — `#expect(throws: FolderFileOperations.OperationError.self)` / `catch FolderFileOperations.OperationError.alreadyExists` / `.wouldNest`
- `Tests/VaultSessionJournalTests.swift:111,166,169` — `#expect(throws: NoteFileOperations.OperationError.self)`
- `Tests/NoteFileOperationTests.swift:182,195,221,244` — `#expect(throws: NoteFileOperations.OperationError.self)`

As with PG-065, an exhaustive grep is the starting enumeration, not the completeness guarantee: a
full `xcodebuild build` after the edits is the actual oracle for a type-only refactor, since a
missed site is a compile error, not a silent gap.

**Tests:** no new test file needed — this is a rename/relocation of an existing type with
identical cases and identical `description` text; every existing assertion on `OperationError`
values keeps passing unchanged once the type name at the assertion site is updated to
`FileOperationError`. If any existing test constructs the type directly for setup (not just
catches it), update that construction site the same way.

## Data model

No new data on disk, no schema change, no index bump. `FileOperationError`'s five cases carry
exactly the same associated values the three original enums carried between them.

## API

No public API surface change for either connector — `VaultWrites.swift`'s catch clauses change
which type name they name, not what they catch or how they translate it to a connector-facing
payload.

## Edge cases

- **A future fourth file-operations type adding its own case:** out of scope for this chain: adds
  a case to `FileOperationError` when it happens, following the same "conversion not collapse"
  pattern already established.
- **`wouldNest` unreachable from Note/Board:** accepted (see Architecture above) — not a defect,
  documented trade-off.

## Success criteria

- [ ] R-01 — `Sources/Core/Vault/FileOperationError.swift` exists with one top-level
      `FileOperationError` enum carrying exactly the five cases (`invalidTitle`, `alreadyExists`,
      `missing`, `failed`, `wouldNest`) and their `description` text unchanged from today's three
      originals.
- [ ] R-02 — `NoteFileOperations.swift`, `FolderFileOperations.swift`, `BoardFileOperations.swift`
      no longer declare a nested `OperationError` enum.
- [ ] R-03 — every throw site in `NoteFileOperations.swift`, `FolderFileOperations.swift`,
      `BoardFileOperations.swift`, `FolderFileOperations+Move.swift` constructs
      `FileOperationError`, not a removed nested type.
- [ ] R-04 — every external catch/assertion site (`VaultWrites.swift`, `VaultSession+Journal.swift`,
      and the five test files listed in Architecture) references `FileOperationError`, not
      `NoteFileOperations.OperationError`/`FolderFileOperations.OperationError`/
      `BoardFileOperations.OperationError`.
- [ ] R-05 — `tuist generate --no-open` succeeds with no `Project.swift` edit, confirming
      `Sources/Core/**`'s existing glob picks up the new file (no-test: this is a build-tooling
      confirmation step, not an assertion a unit test can make — verified by running the command
      and observing its exit code, ADR-0138).
- [ ] R-06 — `xcodebuild ... -only-testing:PergamenumTests test` passes 100%, with zero behavior
      change to any existing assertion beyond the type name referenced.
- [ ] R-07 — `RenamePlan`/`RenameOutcome`-shaped types across the three files remain untouched,
      per the explicit scope decision above (no-test: this is a negative/scope-boundary
      confirmation — verified by diff review showing no changes to those three struct
      declarations, not by a unit test asserting an absence of change, ADR-0138).

## Definition of Done

Unit tests only (`.claude/test-cmd`, `-only-testing:PergamenumTests`), no manual/UI verification —
same precedent as PG-065: a type-only refactor with no behavior change, where a build failure is
the primary and sufficient signal of a missed call site.
