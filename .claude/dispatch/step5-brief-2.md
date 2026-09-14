<!-- step5-brief: plan=/Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md tasks=4,5,6 lines=388-576 -->
# Step 5 Batch Brief -- 2026-09-13-vault-write-ordering-adr-0043.md -- tasks 4-6

## Task text (verbatim, plan lines 388-576)

## Task 4 — One clock, stamped where the bytes land; `apply` is the only index door (R-01, R-02, R-11)

Cross-refs: ADR-0043 §D1 and its rejected alternatives (caller-issued sequence, `Mutex`-guarded
clock, sync door bumping `appliedSequence` to a large value — all three rejected, do not revisit);
ADR-0041 §D11; `Sources/Vault/VaultDisk.swift:105-109` (`nextSequence(for:)`, the clock that already
exists and is kept).
Budget: `Sources/Vault/VaultDisk.swift`, `Sources/Vault/VaultSession.swift`,
`Sources/Vault/VaultSession+WriteOrdering.swift`, `Sources/Vault/VaultSession+Journal.swift`,
`Sources/App/VaultController+Tabs.swift`, `Tests/VaultWriteOrderingTests.swift`,
`Tests/VaultDiskTests.swift` (~400 lines)

**Tester declares:**

```swift
extension VaultDisk {
    struct IndexMutation: Sendable {
        let path: String
        let record: NoteRecord?   // nil: there is no file at this path any more
        let sequence: UInt64
    }

    func writeFile(_ text: String, to relativePath: String) async throws -> IndexMutation
    func moveFile(from oldPath: String, to newPath: String) async throws -> [IndexMutation]  // exactly two
    func trashFile(at relativePath: String) async throws -> IndexMutation
}

extension VaultSession {
    @discardableResult
    func apply(_ mutations: [VaultDisk.IndexMutation]) -> Int   // how many were newer than what we had
}
```

**Coder implements:**

1. `IndexMutation` as declared. `DiskWriteOutcome` keeps `hash` and `journalProblem` and carries
   its `IndexMutation` instead of the loose `record`/`sequence` pair.
2. `VaultDisk.writeFile`, `moveFile`, `trashFile`: the `FileManager.moveItem`, the `trashItem` and
   the non-note byte write move inside the actor, each taking its sequence from
   `nextSequence(for:)` **immediately after the disk operation lands** — never before the hop,
   never from the caller. A move returns two mutations, `(oldPath, nil, seq_old)` and
   `(newPath, record, seq_new)`, each stamped from its own path's clock, which is what makes a
   move orderable against a concurrent write to either end of it.
3. `VaultSession.apply(_ mutations:)` replaces `apply(_ outcome:at:)`. For each mutation: drop it
   unless `mutation.sequence > appliedSequence[mutation.path, default: 0]`, otherwise advance the
   counter and write the index. Return the count applied.
4. **Delete `updateIndex(_:at:)` rather than keeping it as a forwarder** (§D1 is explicit about
   this, and gives the reason: a guard a caller may route around is a guard the seventh call site
   will route around). Convert `+Journal:78`, `:86`, `:131` and `+Watching:27`, `:37` to route
   their mutations through `apply`; `+Watching` is finished in Task 5, so a temporary
   `apply([mutation])` with a sequence taken from the actor is acceptable here only if it compiles
   *and* Task 5 lands immediately after.
5. `VaultController+Tabs.swift:359` — see Task 5, which deletes it. If Task 4 must compile before
   Task 5, route it through `apply` temporarily; do not leave a raw `index.update`.
6. `VaultBoundary.url(for:)` is unchanged and every new actor entry point resolves through it
   (§D10), so ADR-0041 §D1's boundary holds by construction.

**Tester writes (R-11), red before step 1:**

`Tests/VaultWriteOrderingTests.swift` — `theOlderMutationFromADifferentWriterIsDropped()`.
Deterministic, no real timing: build two `IndexMutation`s for one path by hand — one a write's
record at `sequence: 2`, one a trash's `record: nil` at `sequence: 1` — and hand them to `apply` in
the inverted order. Assert `apply([newer]) == 1`, then `apply([older]) == 0`, then that
`session.index.note(at: path)` still holds the newer record. **Assert on the drop count, not only
on the end state**, or the test passes by accident when the guard is missing — the existing test at
`:83` makes that point and it still holds. The "sync writer vs async writer" half of R-11 is proved
by the sync writer's *absence*: Task 10's harness greps that `index.update` appears exactly once in
`Sources/`, inside `apply`.

**Done when:** `grep -rn "index\.update" Sources/` returns exactly one line;
`grep -rn "updateIndex" Sources/ Tests/` returns nothing; R-11 green; full unit suite green.

## Task 5 — The watcher reconciles inside the actor, and `readForEditing` stops writing the index (R-04, R-05)

Cross-refs: ADR-0043 §D3, §D4; ADR-0001 §D2.1 (the index is disposable by construction — the whole
of §D4's argument) and §D3.3 (a self-write is recognised by content hash, never a time window).
Budget: `Sources/Vault/VaultSession+Watching.swift`, `Sources/Vault/VaultDisk.swift`,
`Sources/App/VaultController+Watching.swift`, `Sources/App/VaultController+Tabs.swift`,
`Tests/VaultSessionTests.swift`, `Tests/VaultDiskTests.swift` (~250 lines)

**Tester declares:**

```swift
extension VaultSession {
    func reconcile(_ paths: [String]) async -> [ExternalChange]
}

extension VaultDisk {
    /// Reads one changed path, compares against the hashes the session recorded for it,
    /// advances that path's clock, and says both what the index must become and whether
    /// anybody outside this process wrote it.
    func reconcile(
        _ relativePath: String, selfWritten: [(sequence: UInt64, hash: String)]
    ) async -> (mutation: IndexMutation, change: VaultSession.ExternalChange?, matchedSequence: UInt64?)
}
```

(`selfWritten`/`matchedSequence` are §D6's shape; in this task the session may pass `[]` and ignore
`matchedSequence` — Task 7 wires them. The tester declares the final signature now so Task 7 is a
body change, not a second signature migration.)

**Coder implements:**

1. `reconcile(_:)` becomes `async` and delegates each path's read to `VaultDisk`. The full
   `NoteStore.read` (parse, wikilink scan, transclusion scan, task parse, SHA-256) leaves the main
   actor, which is the same cost ADR-0041 §D9 removed from the write path and left on this one.
2. The reconciliation's `IndexMutation` is stamped from the **same clock as every writer**, taken
   inside the actor in the same serialized straight line as the read. This is deliberate and is
   what makes the guard total: the record describes the file as the actor saw it, a later write
   wins, an earlier one loses.
3. A missing path yields `IndexMutation(path:, record: nil, sequence:)` rather than a bare index
   removal.
4. `VaultController+Watching.swift:23` gains `await` — it is already inside
   `Task { @MainActor … }` (`:11`), so this costs no new asynchrony at the call site.
5. **`VaultController+Tabs.swift:359` is deleted and replaced by nothing.** The read at `:358`
   stays byte-for-byte. Update the doc comment at `:350-353`, which currently promises it «puts the
   index back in step».

**Tester writes:** `VaultSessionTests.swift:335-345` gains `await`; a new case asserts that opening
a note through `readForEditing` leaves `session.index` untouched (write a record, mutate the file
behind the session's back, open it for editing, assert the index still holds the recorded value —
the repair is the cold scan's job, not the tab's).

**Done when:** `grep -rn "session\.updateIndex\|updateIndex(" Sources/` returns nothing; full unit
suite green; both connector targets build.

## Task 6 — The journal's «before» is read where the bytes it describes are written (R-06, R-12)

Cross-refs: ADR-0043 §D5 and its rejected alternative (read the «before» from the index — rejected
because the index is a cache and Race 1 is an entire section about it being stale); ADR-0041 §D7
(`NoteStore.text(_:)`, `Sources/Vault/NoteStore+ReadSurface.swift:13`, added for exactly this class
of caller); ADR-0007 §D6 (the dry run must never reach the actor).
Budget: `Sources/Vault/VaultDisk.swift`, `Sources/Vault/VaultSession.swift`,
`Tests/VaultWriteOrderingTests.swift`, `Tests/VaultSessionJournalTests.swift` (~300 lines)

**Tester declares:**

```swift
extension VaultDisk {
    /// What only the main actor knows about a journal entry. Everything the entry says about
    /// the file — hashBefore, textBefore — is filled in inside the actor (§D5).
    struct JournalDescriptor: Sendable {
        let entryID: String
        let timestamp: Date
        let command: String
        let operation: String?
    }

    func write(
        _ text: String, to relativePath: String,
        precomputedHash: String,
        journalDescriptor: JournalDescriptor?,
        journal: WriteJournal?,
        recordsHistory: Bool
    ) async throws -> DiskWriteOutcome
}
```

**Coder implements:**

1. `VaultSession.write` stops calling `read(relativePath)` at the top (`VaultSession.swift:494`).
   It builds a `JournalDescriptor` when — and only when — a journal is armed and this is not a dry
   run, and hands it across. The condition travels with the descriptor rather than being
   re-derived inside the actor, so the actor never reads a file nobody is going to journal.
2. `VaultDisk.write` reads the current bytes itself with `store.text(relativePath)` (not
   `store.read`), hashes them with `NoteStore.hash`, and fills `hashBefore`/`textBefore`
   **immediately before writing the new ones**, inside the same isolation. A path that does not
   exist yet yields `nil` for both, which is what a creation means.
3. `isDryRun` still short-circuits **before** the hop — ADR-0007 §D6's first guardrail is untouched
   and the existing `aDryRunWriteNeverReachesDiskHistoryOrJournal` test must stay green unchanged.
4. Net effect on the main actor is a *reduction*: a full `NoteStore.read` disappears and is
   replaced by a `NoteStore.text` + one hash inside the actor. Do not add anything back.

**Tester writes (R-12), red before step 1:**

`twoOverlappingWritesRecordDifferentJournalBefores()` — deterministic, no real timing. Arm the
journal, then drive the two writes so their prefixes interleave around the hop without relying on
scheduling: the reliable form is to call `disk.write(...)` **directly** for write A, `await` it,
then call it directly for write B, and assert that B's recorded `hashBefore` equals A's
`hashAfter` — under today's code B's descriptor would have carried the pre-A hash because the read
happened on the main actor before A landed. To prove the interleaving rather than mere sequencing,
build both `JournalDescriptor`s up front (that is the whole of what the main actor contributes),
*then* perform the two actor calls; the descriptors provably predate both writes, so a passing
assertion can only come from the actor having read the file itself. Assert: two entries, two
different `hashBefore` values, `entryB.hashBefore == entryA.hashAfter`, and `entryA.textBefore !=
entryB.textBefore`.

**Done when:** R-12 green; `VaultSessionJournalTests` green; `journal undo` on the second of two
overlapping writes restores the first one's text, not the original.

## File map (from Budget: declarations, tasks 4-6)

- (none declared -- no task in this range carries a parseable Budget:)

No parseable Budget: for task(s): 4 5 6 (absent is not zero -- consult the task text above)

## Excluded tasks (not in this batch)

- Task 1 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md
- Task 2 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md
- Task 3 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md
- Task 7 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md
- Task 8 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md
- Task 9 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md
- Task 10 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md

Full plan: /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md

## Context documents (open only for the reason stated -- not read unconditionally)

- ADR: docs/adr/0043-vault-write-ordering-concurrency-races.md -- governing ADR for this chain
- SPEC: docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md -- task detail lives in the plan itself
