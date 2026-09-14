# SPEC — Vault layer consistency and security chain

**Topic slug:** vault-layer-consistency-and-security-cha

## Objective

Close a path-traversal security gap in the vault layer, deduplicate three drifted
implementations of the same directory-walk/apply-plan pattern, remove redundant
disk I/O in the rename/move code paths, and move synchronous disk work off the
main actor on every save, selection change and keystroke — all four issues share
overlapping files and a fix ordering already recorded in TODO.md's Deep Refactor
Roadmap, so they are designed and implemented together in one pass.

Source items: PG-122 (GH #222, security, P1), PG-145 (GH #245, structure, P2),
PG-140 (GH #240, perf, P3), PG-137 (GH #237, perf, P2).

## Scope

**In scope:**

1. Extract the vault-boundary guard (`NoteStore.assertInsideVault`) into a shared,
   pure type in `Sources/Core`, and apply it to every call site in the vault layer
   that joins a caller-supplied relative path onto the vault root without a check:
   `CanvasStore.swift`, `VaultSession+Journal.swift`, `ThumbnailStore.swift`,
   `WorkspaceController+Files.swift`, `BoardCardMenu.swift`,
   `PraticheController.swift`, `PraticaSyncEngine.swift`.
2. Extract the vault directory walk and the "apply plan" loop (currently three and
   six drifted copies respectively) into shared pure helpers in `Sources/Core`,
   covering both sharedSources call sites (`CanvasStore`, `NoteFileOperations`,
   `VaultScanner`) and app-only call sites (`FolderFileOperations`,
   `BoardFileOperations`, `VaultSession+BoardDrop`). Replace the `rename` that
   re-implements `renamePlan` with a call to the shared helper.
3. Move `VaultController.swift` from `Sources/Vault/` to `Sources/App/`, matching
   the existing convention for SwiftUI-dependent app-shell facades
   (`PergamenumApp`, `RootView`, `CommandActions`, `VaultCommands`). Update all
   ~112 references. No behavior change — file relocation only.
4. Batch the per-item reads/writes in the rename/move code paths
   (`NoteStore.swift`, `VaultSession+Move.swift`, `VaultSession+Journal.swift`,
   `VaultSession+Starred.swift`, `VaultScanner.swift`) into a single per-batch
   plan: one vault walk, one frontmatter parse per file, one starred-file rewrite
   per batch rather than per moved note.
5. Move the disk work in `VaultSession`'s read/write path off the main actor onto
   a background actor, reporting results back to the main actor for index/journal/
   history updates, preserving ADR-0001's invariant that the index is updated
   immediately after every write and is never itself the source of truth. Apply
   the same pattern to the five tail call sites: `WorkspaceController+Files.swift`,
   `BoardCardMenu.swift`, `PraticheController.swift`, `PraticaSyncEngine.swift`,
   `RecordingsController.swift`, `MCPServer/VaultHost.swift`, and update
   `Tests/ReleasePipelineTests.swift` accordingly.

**Out of scope:**

- Any other Deep Refactor Roadmap finding not listed above (e.g. `PG-124`,
  `structure-NoteExport.swift-c0f`, `PergamenumURL.swift` route refusal) —
  separate chains.
- Changing the on-disk format, frontmatter schema, or `.canvas` JSON Canvas
  compatibility.
- Adding new user-facing UI or settings.

## Stack

Swift 6 strict concurrency, SwiftUI (macOS 26 SDK only where explicitly UI-facing),
Foundation, Swift Testing. No new dependency. Affects `Sources/Core`,
`Sources/Vault`, `Sources/App`, `Sources/Connector`, `Sources/Index`,
`Sources/Features/Workspace`, `Sources/Features/Pratiche`,
`Sources/Features/Recordings`, `Sources/MCPServer`, `Tests/`.

## Architecture

### Boundary guard (PG-122)

- New pure type in `Sources/Core` (e.g. `VaultPathGuard`), holding the resolved
  vault root and exposing a function that resolves a relative path against the
  root and throws when the result escapes it — the same logic currently private
  to `NoteStore.assertInsideVault`, generalized so both `Sources/Core`-only
  callers and app-only callers (not in sharedSources) can reach it without a
  second copy.
- `NoteStore` is refactored to delegate to this shared type rather than keep its
  own private copy.
- Every one of the 9 call sites listed in Scope item 1 is updated to call the
  shared guard before touching disk. Where the enclosing function is not
  currently `throws`, it becomes `throws`, and its callers are updated to
  propagate or handle the new error — this is a deliberate signature change, not
  an oversight, per the confirmed answer that a boundary violation must fail
  loudly (`throw`), never silently log-and-continue, since the untrusted input
  in these paths originates from wikilinks and the `pergamenum://` URL scheme.

### Walk / apply-plan dedup (PG-145)

- A second pure type or set of functions in `Sources/Core` (alongside the
  boundary guard, same file or same small file group) replacing the three
  drifted vault-walk implementations and the six drifted apply-plan-loop
  implementations. The walk helper composes with the boundary guard: every path
  it yields has already passed the guard, so callers cannot reintroduce the gap
  PG-122 closes by walking around it.
- `rename` (wherever it duplicates `renamePlan`) is replaced with a call to
  `renamePlan` plus the shared apply-plan helper.
- `VaultController.swift` moves from `Sources/Vault/` to `Sources/App/`
  (Scope item 3) — a pure relocation, no logic change, done in the same chain
  because it is the same "vault layer should not carry UI-only files" finding
  that PG-145 raised, and because the boundary/walk refactor above already
  touches import lines across the Vault directory.

### Redundant I/O (PG-140)

- The batch move/rename path gains a single per-batch plan: one vault walk (via
  the new shared helper), one frontmatter parse per file (not two), one
  `NoteStore.text(_:)`-style accessor for read paths that only need the body,
  one starred-file rewrite per batch (not once per moved note), one
  root-path-standardization per batch (not once per file).
- Failure mode is best-effort per item, confirmed: each note in a batch is
  attempted independently; the caller receives which items succeeded and which
  failed. No simulated all-or-nothing transaction across file-system renames —
  "file over app" means a note that already moved successfully is never rolled
  back artificially to satisfy an all-or-nothing contract the file system does
  not itself provide.

### Main-actor I/O (PG-137)

- `VaultSession`'s write path (and the equivalent read path) delegates the disk
  work — read, write, hash — to a background actor. The main actor awaits the
  result and then performs the index update, journal entry, and history record
  in the existing order and on the existing thread, preserving ADR-0001's
  "index updated immediately after write, cache is never truth" invariant:
  nothing about *when* the index updates relative to the write changes, only
  *where the disk bytes move* changes.
- The five tail call sites (`WorkspaceController+Files`, `BoardCardMenu`,
  `PraticheController` x2, `PraticaSyncEngine`, `RecordingsController`,
  `MCPServer/VaultHost`) adopt the same background-actor-then-main-actor-report
  pattern rather than being left synchronous, per the confirmed decision to
  fold the full PG-137 scope into this chain (same architectural seam, avoids a
  second round of testing on the same pattern). `Tests/ReleasePipelineTests.swift`
  is updated for the new async surface.
- Explicitly rejected: `Task.detached` fire-and-forget per call, which would let
  two writes to the same file race out of order and let the UI observe a stale
  index after a write it just triggered.

## Data model

No changes to `NoteRecord`, `Frontmatter`, `.canvas` JSON Canvas schema, or any
persisted format. This chain is internal-implementation-only: same data in, same
data out, on-disk representation untouched.

## API

- `Sources/Core`: two new pure types/functions (boundary guard, walk/apply-plan
  helper), both `Sendable`, both usable from `Sources/Vault`, `Sources/Connector`,
  `Sources/Features/*`, `Sources/MCPServer`, `Sources/CLI` alike, since
  `Sources/Core/**` is already a full sharedSources glob and requires no
  `Project.swift` edit.
- `NoteStore`, `CanvasStore`, `VaultScanner`, `FolderFileOperations`,
  `BoardFileOperations`, `VaultSession+BoardDrop` delegate to the new `Sources/Core`
  helpers instead of each holding a private/duplicated implementation.
- Several currently non-throwing functions across the 9 PG-122 call sites become
  `throws` (see Architecture — Boundary guard). Their callers are updated in the
  same chain; this is not left as a follow-up.
- `VaultSession`'s write/read surface gains `async` where disk work moves to a
  background actor; callers on the main actor `await` as needed. No new public
  type is introduced for this — the existing `VaultSession` API becomes async at
  the touched entry points.
- `VaultController` moves package/file location only (`Sources/Vault` →
  `Sources/App`); its public interface to views is unchanged.

## UI flows

None. This chain changes no UI. The move/rename/save/keystroke UI flows exercised
by the app must continue to behave identically to a user — indistinguishable
except for main-thread responsiveness, which should improve (PG-137) or stay the
same, never regress.

## Edge cases

- A relative path containing `../` reaching any of the 9 newly-guarded call
  sites via wikilink, URL scheme, or drag-and-drop must be rejected before any
  disk access, not merely logged.
- A batch move where item 3 of 10 hits a boundary violation or a file-system
  error: items 1-2 that already succeeded stay moved; items 4-10 are still
  attempted; the caller sees a per-item result, not a single aggregate
  success/failure boolean.
- Two rapid saves to the same note (fast typing, autosave) after PG-137's
  background-actor move: the second save's disk write must not start before the
  first's index/journal/history update has completed on the main actor, or the
  watcher's self-write-hash bookkeeping (`selfWrittenHashes`) could see writes
  out of order and misattribute an external edit as the app's own, or vice
  versa. Ordering is guaranteed by serializing disk operations for a given
  relative path through the background actor (an actor is inherently
  serial for its own isolated state), not by the main actor's await ordering
  alone.
- Symlinked vault root: the boundary guard must keep resolving symlinks once at
  construction (existing `NoteStore.init` behavior) — the shared `Sources/Core`
  type preserves this, since the existing comment in `NoteStore.swift` documents
  a prior regression from resolving at each comparison instead.
- `VaultController` move: any file that imports it by relative/module path
  assumption (none currently, since Swift target-internal imports don't need a
  path) is unaffected; only the ~112 call sites that simply reference the type
  are checked to still compile after the file moves target-internally within the
  same `Pergamenum` app target (VaultController is not in sharedSources, so no
  CLI target is affected by the move).

## Success criteria

- [ ] R-01 — `Sources/Core` contains one boundary-guard type used by `NoteStore`
      and by all 9 additional call sites named in Scope item 1; no call site in
      the vault layer joins a relative path onto the vault root without going
      through it.
- [ ] R-02 — An adversarial test exists per guarded call site (10 total,
      including the pre-existing `NoteStore` coverage) asserting that a
      relative path containing `../` throws/fails rather than reading or
      writing outside the vault root.
- [ ] R-03 — `Sources/Core` contains one shared vault-walk helper and one shared
      apply-plan helper; the three drifted walk copies and six drifted
      apply-plan copies named in PG-145 are replaced by calls to these helpers,
      and the `rename` that re-implemented `renamePlan` now calls it directly.
- [ ] R-04 — `VaultController.swift` lives at `Sources/App/VaultController.swift`;
      `Sources/Vault/` contains no `import SwiftUI`.
- [ ] R-05 — The batch move/rename path performs one vault walk, one frontmatter
      parse per file, and one starred-file rewrite per batch (not per moved
      note), verified by a test asserting call counts on a batch of N > 1 notes.
- [ ] R-06 — A batch operation where one item fails still completes the
      remaining items and reports success/failure per item, verified by a test
      that fails one item deliberately (e.g. a boundary violation) inside a
      batch of at least 3.
- [ ] R-07 — `VaultSession`'s write path performs its disk I/O off the main
      actor and reports the result back to the main actor for index/journal/
      history updates, in the pre-existing order, verified by a
      concurrency-safe test exercising two rapid writes to the same relative
      path.
- [ ] R-08 — The five PG-137 tail call sites (`WorkspaceController+Files`,
      `BoardCardMenu`, `PraticheController` x2, `PraticaSyncEngine`,
      `RecordingsController`, `MCPServer/VaultHost`) adopt the same
      background-actor pattern; `Tests/ReleasePipelineTests.swift` is updated
      and passes.
- [ ] R-09 — `perg` and `pergamenum-mcp` both build successfully after the
      `Sources/Core` extraction (no new SwiftUI/AppKit import reaches
      sharedSources).
- [ ] R-10 — `scripts/mcp-smoke.py` is re-run manually against
      `pergamenum-mcp` and completes without regression (no-test: manual
      operational verification against a running stdio server, not a
      Swift Testing assertion).
- [ ] R-11 — A manual `perg` CLI pass against a scratch vault confirms
      rename/move/journal commands still work end to end after the
      `Sources/Core` extraction (no-test: manual CLI verification against a
      real vault, not an automated assertion).
- [ ] R-12 — The four TODO.md items (`PG-122`, `PG-145`, `PG-140`, `PG-137`) and
      their GitHub issues (#222, #245, #240, #237) are closed/checked off with a
      reference to the ADR and PR that fixed them (no-test: ledger/issue-tracker
      bookkeeping, not a code assertion).
