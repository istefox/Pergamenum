<!-- step5-brief-followup: plan=/Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md tasks=7 (type-mismatch follow-up) -->
# Step 5 Batch 3 Follow-up -- fix two assertions after selfWrittenHashes' type change

## Why this dispatch exists

The batch-3 coder implemented Task 7 (ADR-0043), which changes
`VaultSession.selfWrittenHashes` from `[String: String]` (one hash per path) to
`[String: [(sequence: UInt64, hash: String)]]` (a per-path, sequence-tagged list). This is the
declared API the batch-3 tests were written against and it is correct per the plan.

Two pre-existing tests in `Tests/VaultWriteOrderingTests.swift` (written during batch 2, before
Task 7 existed) compare the old shape directly against a `String` and no longer compile:

- Line 42: `#expect(session.selfWrittenHashes["N.md"] == NoteStore.hash(Data(second.utf8)))`
- Line 97: `#expect(session.selfWrittenHashes["N.md"] == NoteStore.hash(onDisk))`

Confirmed via `xcodebuild -only-testing:PergamenumTests build-for-testing`: exactly these two
compile errors, both `cannot convert value of type '[(sequence: UInt64, hash: String)]?' to
expected argument type 'String'`. Nothing else in the file is affected.

## What to do

**You may only edit `Tests/VaultWriteOrderingTests.swift`, and only at these two lines.** Change
each to compare the **last** entry's hash instead of the bare (now nonexistent) string value:

- Line 42: `#expect(session.selfWrittenHashes["N.md"]?.last?.hash == NoteStore.hash(Data(second.utf8)))`
- Line 97: `#expect(session.selfWrittenHashes["N.md"]?.last?.hash == NoteStore.hash(onDisk))`

Do not change any other line, any other assertion, or any other file. Do not weaken the
assertion (e.g. do not drop the check or replace it with a looser one) — this is a type-shape
fix only, preserving the exact same semantic check (the most recent recorded hash for this path
equals the expected hash).

## Verification

```bash
xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' \
  -only-testing:PergamenumTests test
```
(Codex sandbox note: if `xcodebuild` cannot run in your environment, report that plainly per the
usual pattern — do not guess at the result.)

**Done when:** the two lines are the only change, and (if you can verify) the full
`PergamenumTests` target compiles and passes.

## Guardrails

- Do not touch any file under `Sources/`.
- Do not touch any file under `Tests/` other than `VaultWriteOrderingTests.swift`.
- Do not change any assertion's meaning, only adapt it to the new tuple-list type.
- Commit is not your job; the orchestrator merges your worktree back.
