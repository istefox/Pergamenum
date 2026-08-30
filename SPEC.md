# SPEC — PG-046: Equatable, Sendable conformance for Folder/Board rename and move plan/outcome types

**Topic slug:** pg-046-equatable-sendable-conformance

## Objectives

Close the `Equatable, Sendable` disparity between `NoteFileOperations`'s plan/outcome types
(`RenamePlan`, `MovePlan`, `FileChange`, `Outcome` — all `Equatable, Sendable`) and their
Folder/Board-layer siblings, which today declare no such conformance. Pure additive-conformance
change: no field renamed, reshaped or added; no behavior change.

TODO.md's PG-046 entry, verified stale on both cited facts before this chain started:
`FolderRenamePlan.boardRename` (the anonymous `(from: String, to: String)?` tuple it named) was
removed entirely by ADR-0025 — a folder rename no longer touches board files named after it.
`RenameOutcome.movedNotes` (the anonymous `[(old: String, new: String)]` tuple it named) was
already replaced by a named `MovedNote` struct in this session's PG-080 chain. The underlying
observation survives: none of the six Folder/Board-layer plan/outcome types below are `Equatable,
Sendable`, unlike every Note-layer sibling.

## Scope

**In scope** — add `Equatable, Sendable` to all six types:
- `Sources/Vault/FolderFileOperations.swift` — `FolderRenamePlan`, `RenameOutcome`
- `Sources/Vault/FolderFileOperations+Move.swift` — `MovePlan`, `MoveOutcome`
- `Sources/Vault/BoardFileOperations.swift` — `MovePlan`, `MoveOutcome`
- `Sources/Vault/VaultSession+Move.swift` — `MoveBatchOutcome`

Scope extended beyond TODO.md's original two-type claim (`FolderRenamePlan`/`RenameOutcome` only)
to all six by explicit user decision before this interview, closing the disparity with
`NoteFileOperations` everywhere in one pass rather than leaving four of six unresolved.

**Also in scope** — `Sources/Core/Vault/MovedNote.swift` gains `Equatable, Sendable`: it is a
stored-property field on `RenameOutcome`/`MoveOutcome`/`MoveBatchOutcome`, and Swift's automatic
`Equatable`/`Sendable` synthesis requires every stored property to itself conform. Confirmed by
interview — not optional.

**Out of scope:**
- No test file changes — existing unit tests continue to compile and pass unchanged; no test
  is converted from field-by-field assertion to whole-value `==` comparison (interview decision:
  keep existing tests as-is, matching PG-065/PG-066/PG-080 precedent of build/test-green as the
  sole completeness oracle).
- `NoteFileOperations.FileChange` and `VaultMove` — already `Equatable, Sendable`, no change
  needed; both are reused as field types by the six types above without modification.
- No restructuring of any field: every field on all six types is already a value composed
  entirely of `String`, `[String]`, `[NoteFileOperations.FileChange]` (already `Equatable,
  Sendable`), `[MovedNote]` (gaining it in this chain), or `[VaultMove]` (already `Equatable,
  Sendable`) — so no field needs to change shape for conformance to synthesize.
- `MoveBatchOutcome.didMove` is a computed property (`!moves.isEmpty`), not stored — irrelevant
  to synthesis, unaffected by this change.

## Stack

Swift 6, strict concurrency. `Equatable`/`Sendable` are compiler-synthesized when every stored
property already conforms — no manual `==`/`Sendable` implementation needed anywhere in this
change, matching the pattern already used by every `NoteFileOperations` sibling type.

## Architecture

Seven struct declarations gain a conformance clause; nothing else changes.

```swift
// Sources/Core/Vault/MovedNote.swift
struct MovedNote: Equatable, Sendable {
    var old: String
    var new: String
}

// Sources/Vault/FolderFileOperations.swift
struct FolderRenamePlan: Equatable, Sendable { ... }   // unchanged fields
struct RenameOutcome: Equatable, Sendable { ... }        // unchanged fields

// Sources/Vault/FolderFileOperations+Move.swift
struct MovePlan: Equatable, Sendable { ... }             // unchanged fields
struct MoveOutcome: Equatable, Sendable { ... }           // unchanged fields

// Sources/Vault/BoardFileOperations.swift
struct MovePlan: Equatable, Sendable { ... }             // unchanged fields
struct MoveOutcome: Equatable, Sendable { ... }           // unchanged fields

// Sources/Vault/VaultSession+Move.swift
struct MoveBatchOutcome: Equatable, Sendable { ... }      // unchanged fields
```

Note: `FolderFileOperations+Move.MovePlan`/`MoveOutcome` and `BoardFileOperations.MovePlan`/
`MoveOutcome` share names within their own enclosing types (`FolderFileOperations`,
`BoardFileOperations`) — this is pre-existing and unaffected; each pair is nested and distinct.

## Data model

No new stored fields anywhere. `MovedNote`'s two `String` fields (`old`, `new`) and every other
field on the six outcome/plan types are unchanged from their current declarations — only the
conformance clause changes.

## API

None — internal-only types, none reachable from `VaultAPI` or either connector (`perg`,
`pergamenum-mcp`). No `Sources/Connector/` change.

## Edge cases

- **Synthesis compiles or it does not — the build is the oracle.** If any field on any of the
  seven types were not already `Equatable`/`Sendable`-compatible, the build would fail at the
  conformance declaration, not silently produce a broken `==`. Verified before this SPEC: every
  field's type already conforms (`String`, `[String]`, `[NoteFileOperations.FileChange]`,
  `[MovedNote]` (once conforming), `[VaultMove]`).
- **Nesting inside an `extension` or an enclosing `struct` does not block conformance synthesis**
  — `NoteFileOperations.RenamePlan`/`MovePlan`/`Outcome`/`FileChange` are the existing proof:
  all four are nested inside `struct NoteFileOperations` and already `Equatable, Sendable`.
- **`Equatable` on a plan/outcome type used only for pass-through aggregation
  (`VaultSession+Move.swift:105`'s `outcome.movedNotes.append(contentsOf: folder.movedNotes)`)**
  has no observable effect on that call site — `append(contentsOf:)` does not require `Equatable`
  on its element type. The conformance is additive value, not a requirement anything currently
  needs to compile.

## Success criteria

- [ ] R-01 — `Sources/Core/Vault/MovedNote.swift`'s `MovedNote` declares `Equatable, Sendable`
- [ ] R-02 — `Sources/Vault/FolderFileOperations.swift`'s `FolderRenamePlan` declares `Equatable, Sendable`
- [ ] R-03 — `Sources/Vault/FolderFileOperations.swift`'s `RenameOutcome` declares `Equatable, Sendable`
- [ ] R-04 — `Sources/Vault/FolderFileOperations+Move.swift`'s `MovePlan` declares `Equatable, Sendable`
- [ ] R-05 — `Sources/Vault/FolderFileOperations+Move.swift`'s `MoveOutcome` declares `Equatable, Sendable`
- [ ] R-06 — `Sources/Vault/BoardFileOperations.swift`'s `MovePlan` declares `Equatable, Sendable`
- [ ] R-07 — `Sources/Vault/BoardFileOperations.swift`'s `MoveOutcome` declares `Equatable, Sendable`
- [ ] R-08 — `Sources/Vault/VaultSession+Move.swift`'s `MoveBatchOutcome` declares `Equatable, Sendable`
- [ ] R-09 — No field on any of the eight types above is renamed, reshaped, added or removed
- [ ] R-10 — .claude/test-cmd (-only-testing:PergamenumTests) builds clean and passes 100%
- [ ] R-11 — No test file is modified (existing tests compile and pass unchanged)
