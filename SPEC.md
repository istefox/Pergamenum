# SPEC: Vault write ordering — ADR-0043 implementation

**Topic slug:** vault-write-ordering-adr-0043

## Objective

Implement the fix decided by `docs/adr/0043-vault-write-ordering-concurrency-races.md` (ADR-0043,
status "decided, not implemented" at the time of writing). ADR-0043 is a follow-up to ADR-0041,
raised by an independent post-implementation review that found four concurrency defects in the
vault write path: the per-path write-ordering guard (§D11 of ADR-0041) covers only one of the
vault's six index writers, two overlapping async writes can record the same journal "before", a
`canOperate` precondition checked before an `await` does not survive the suspension it is meant to
guard, and a read-then-write call site has no staleness check at all.

This SPEC does not re-derive the design — ADR-0043 already decided it in full (§D1–§D8). This SPEC
turns that decision into requirement criteria a plan and an implementation can be checked against,
and states what "done" means for this chain, including the acceptance rule ADR-0043 §D9 states
explicitly: **tests that force the interleaving deterministically are the acceptance criterion,
never a green suite alone.**

Verified against the current working tree (2026-09-13, branch `emdash/strict-steaks-argue-n6z2c`,
ADR-0041 on `main` via PR #254) before writing this SPEC: every file and line ADR-0043 cites was
read again and matches byte-for-byte what the ADR quotes. Nothing in PRs #255–#258 (merged after
#254) touched any of the nine files this SPEC's requirements name. The four races are current, not
historical.

## Scope

In scope — the whole of ADR-0043 §D1 through §D8, as one chain (confirmed with the operator: the
four races are not independently shippable per the ADR's own "Negative consequences" section —
splitting them means building the shared clock twice):

- One clock stamped inside `VaultDisk`; every file-touching operation (write, non-note `writeFile`,
  `moveFile`, `trashFile`) moves inside the actor and returns an `IndexMutation`.
- `VaultSession.apply` becomes the only door onto the index; `updateIndex(_:at:)` is deleted.
- The synchronous `write(_:to:) throws` door and `writeSynchronously` are deleted; `saveOpenNote()`,
  `restoreVersion(_:)`, their production call sites and the seven dependent test files convert to
  `async`.
- The watcher's `reconcile(_:)` becomes `async`, reads inside the actor, and takes a stamp.
- `readForEditing` (`VaultController+Tabs.swift`) stops writing the index.
- The journal's "before" (`hashBefore`/`textBefore`) is read inside the actor, where the bytes it
  describes are written, not on the main actor beforehand.
- `selfWrittenHashes` becomes a per-path, sequence-tagged list, pruned by the clock rather than by a
  cap.
- `PraticaEntryComposer.handOff` stops unconditionally reloading from disk; `syncOpenNote(with:)`'s
  dirty branch raises ADR-0001 §D3.4's conflict prompt instead of silently doing nothing, at all
  nine `syncOpenNote` call sites.
- `write` gains an opt-in `expecting: String?` precondition (§D8); the plan names which read-then-
  write call sites adopt it.
- Interleaving tests: one deterministic test per race — a sync writer racing an async writer (§D1,
  §D2), two overlapping writes with diverging journal entries (§D5), a reconciliation racing two
  writes (§D3, §D6), a buffer dirtied between a write and its hand-off (§D7), a stale expected-hash
  (§D8) — none of them relying on real timing to reproduce.

Out of scope (ADR-0043 §D10, restated here so the plan does not reopen it):

- No on-disk format change, no `IndexCache.schemaVersion` bump.
- No change to the five task views, the board addressing rule, JSON Canvas round-trip, the
  pratiche sync rewrite policy, or the MCP tool surface (`tools/list` answers unchanged;
  `scripts/mcp-smoke.py` must still pass unmodified).
- No new user-visible feature, no new setting.
- No change to ADR-0007 §D6's three write guardrails (`--allow-write` gating, `dryRun` default,
  journal recording path/hash-before/hash-after/previous-text) beyond §D5 making the third more
  accurate.
- No protected-interface addition (ADR-0043 explicitly declines one, deliberately, until this
  chain's own signatures settle).

## Stack

Swift 6, strict concurrency, macOS 26 SDK. No new dependency. Touches `Sources/Vault`,
`Sources/App` (`VaultController+*`), `Sources/Features/Pratiche/PraticaEntryComposer.swift`, and
seven files under `Tests/`. `Sources/Connector` (`perg`, `pergamenum-mcp`) absorbs the async
signature changes with no structural edit — both are already async end-to-end since ADR-0041 §D9.

## Architecture

As decided in ADR-0043 §D1–§D8 — restated here only as the requirement list a plan must satisfy,
not re-derived:

- **§D1 — one clock, one index door.** `VaultDisk.IndexMutation { path, record, sequence }`,
  sequence taken inside the actor immediately after the disk operation lands (never issued by the
  caller before the hop — Swift publishes no enqueue-order guarantee for an actor's jobs).
  `VaultSession.apply(_ mutations: [VaultDisk.IndexMutation]) -> Int` is the only writer to `index`.
- **§D2 — one write door.** `write(_:to:) throws` and `writeSynchronously` deleted; the ~20
  `Sources/Vault` wrappers, `saveOpenNote()`, `restoreVersion(_:)`, their four production call
  sites, and the seven dependent test files (`VaultTests`, `NoteHistoryTests`, `NoteTabTests`,
  `VaultSessionTests`, `GuardrailTests`, `NoteTemplateTests`, `RelatedLinkTests`,
  `ConnectorTests`) become `async`.
- **§D3 — reconciliation inside the actor.** `VaultSession.reconcile(_:)` becomes `async`, delegates
  its per-path read to `VaultDisk`, compares against `selfWrittenHashes` (§D6), advances that
  path's clock, returns the `IndexMutation` plus the `ExternalChange` list.
- **§D4 — `readForEditing` stops writing the index.** Removed and replaced by nothing; every other
  change is now stamped by a writer, and a stale row is repaired by the cold scan.
- **§D5 — the journal's "before" moves inside the actor.** `VaultSession.write` passes only a
  `Sendable` descriptor (command, operation id, entry id, timestamp); `VaultDisk.write` reads the
  current bytes itself, immediately before writing the new ones, and fills `hashBefore`/
  `textBefore`. `isDryRun` still short-circuits before the hop.
- **§D6 — `selfWrittenHashes` becomes `[String: [(sequence: UInt64, hash: String)]]`.** A
  reconciliation that matches a hash drops every entry at or below that sequence.
- **§D7 — a guard before an `await` is a filter, not a guarantee.** `handOff` keeps the
  `WriteResult` and hands it to `syncOpenNote(with:)` instead of calling `reloadFocusedNote()`;
  `syncOpenNote`'s dirty branch sets `note.externalChangePending = result.text`, raising ADR-0001
  §D3.4's prompt, at all nine call sites (`VaultController+TimeBlocks` ×3, `+TaskDrop`, `+Diary`,
  `+Routes`, `+Tasks` ×2, the composer's). `canOperate(on:)` stays as a cheap early refusal; the
  comment inferring safety from it is deleted.
- **§D8 — opt-in `expecting: String?` precondition.** `write(_:to:, expecting:)` throws
  `WriteRefusal.movedOn(relativePath)` without writing when the actor's current hash differs from
  `expecting`. Default `nil`. The plan names, by grep (`session.read(` followed by `session.write(`
  in the same function, across `Sources/App`, `Sources/Features`, `Sources/Connector`), which call
  sites adopt it and why.

## Data model

No schema change. `VaultDisk.IndexMutation` and the widened `selfWrittenHashes` container are
in-memory types local to `Sources/Vault`, not persisted.

## API

No MCP tool surface change (`tools/list` unchanged, `scripts/mcp-smoke.py` must pass unmodified).
`VaultSession.write`'s public signature gains one optional parameter (`expecting:`); every other
signature change (`saveOpenNote()`, `reconcile(_:)`, etc.) is an internal `async` conversion with
no change to what the call means.

## UI flows

One user-visible change, explicitly called out by ADR-0043 as a consequence, not a new feature:
ADR-0001 §D3.4's "keep mine / take theirs" conflict prompt now fires at the nine `syncOpenNote`
call sites when the app writes a note out from under a dirty buffer — previously silent. No new
setting, no new screen.

## Edge cases

- A pratica insert and a Cmd+S save racing on the same note (Race 1 — the concrete failure the ADR
  gives first).
- A trash racing an in-flight write to the same path (Race 1).
- An external (Obsidian) edit racing the watcher's reconciliation and a session write (Race 1,
  Race 3's cousin).
- Two `Task`-wrapped saves to the same path started from the main actor, interleaving their
  synchronous prefixes around the actor hop (Race 2 — journal "before" divergence).
- `PraticaEntryComposer.insert`'s two writes (pratica note, daily note mirror) racing a keystroke
  in the open tab on the same note (Race 3 — the one with a reported user-visible symptom: lost
  typing, no prompt, nothing in the journal).
- A second writer landing at the actor between a read and a write derived from that read, with no
  expected-hash guard adopted at that call site (Race 4 — plain lost update).
- FSEvents coalescing several of this session's own writes into one callback (tests that
  `selfWrittenHashes` pruning stays exact, not a heuristic cap).

## Success criteria

- [ ] R-01 — `VaultDisk.IndexMutation { path, record, sequence }` exists and every file-touching
  operation inside `VaultDisk` (write, `writeFile`, `moveFile`, `trashFile`) returns one; a move
  returns two, each stamped from its own path's clock.
- [ ] R-02 — `VaultSession.apply(_ mutations: [VaultDisk.IndexMutation]) -> Int` is the only
  function in `Sources/` that calls `index.update`; `updateIndex(_:at:)` no longer exists.
- [ ] R-03 — `write(_:to:) throws` and `writeSynchronously` no longer exist in `VaultSession.swift`;
  every former call site (`saveOpenNote()`, `restoreVersion(_:)`, their production callers, and the
  seven named test files) compiles and passes as `async`.
- [ ] R-04 — `VaultSession.reconcile(_:)` is `async`, reads the changed path's bytes inside
  `VaultDisk`, and stamps its `IndexMutation` from the same clock as every writer.
- [ ] R-05 — `readForEditing` (`VaultController+Tabs.swift`) no longer calls `updateIndex`/
  `session.updateIndex`.
- [ ] R-06 — `VaultSession.write`'s journal entry has its `hashBefore`/`textBefore` read inside
  `VaultDisk`, immediately before the new bytes are written, not on the main actor before the hop.
- [ ] R-07 — `selfWrittenHashes` is keyed per path to a list of `(sequence, hash)` pairs; a matched
  reconciliation drops every entry at or below the matched sequence.
- [ ] R-08 — `PraticaEntryComposer.handOff` calls `vault.syncOpenNote(with:)` and never calls
  `reloadFocusedNote()` on the just-written note's tab.
- [ ] R-09 — `syncOpenNote(with:)`'s dirty-buffer branch sets `note.externalChangePending =
  result.text` instead of returning silently; behaviour verified from at least one of the nine
  named call sites (`VaultController+TimeBlocks`, `+TaskDrop`, `+Diary`, `+Routes`, `+Tasks`, the
  composer's).
- [ ] R-10 — `VaultSession.write(_:to:, expecting:)` exists, defaults `expecting` to `nil`, and
  throws `WriteRefusal.movedOn(relativePath)` without writing when the actor's current hash
  disagrees with a non-nil `expecting`; the plan states explicitly which read-then-write call sites
  (composer, task/timeblock writers, pratiche sync) adopt it, and why.
- [ ] R-11 — `Tests/VaultWriteOrderingTests` (or an extension of it) contains a deterministic test
  that calls `apply`/`VaultDisk` methods directly to force a sync-write-vs-async-write inversion on
  one path (§D1/§D2), independent of real timing.
- [ ] R-12 — a deterministic test demonstrates that two overlapping writes to the same path produce
  two journal entries whose `hashBefore` values differ and each correctly describes the transition
  that actually occurred (§D5).
- [ ] R-13 — a deterministic test demonstrates a reconciliation interleaved between two writes to
  the same path applies in clock order, not call order (§D3, §D6).
- [ ] R-14 — a deterministic test demonstrates that dirtying the editor buffer between a session
  write and its hand-off raises the conflict prompt (`externalChangePending` set) rather than
  silently discarding the user's unsaved edit (§D7).
- [ ] R-15 — a deterministic test demonstrates that `write(_:to:, expecting:)` throws
  `WriteRefusal.movedOn` and performs no write when the file has moved on since the caller's read
  (§D8).
- [ ] R-16 — `scripts/mcp-smoke.py` passes unmodified against the built `pergamenum-mcp` binary
  (no MCP tool surface change).
- [ ] R-17 — the full `PergamenumTests` suite passes; **R-11 through R-15 passing is the acceptance
  criterion for this chain, not R-17 alone** — a green suite without the five interleaving tests
  demonstrates nothing about this feature (ADR-0043 §D9).
- [ ] R-18 — ADR-0043's header status is updated from "proposed — decided, not implemented" to
  reflect implementation, once R-01 through R-17 hold. (no-test: this is a documentation edit to a
  markdown file's header line, not something a unit test asserts against)
- [ ] R-19 — GitHub issue #259 is closed once this chain's PR merges. (no-test: an operator/GitHub
  action taken after merge, not a behavior a test in this repository can assert)
- [ ] R-20 — `TODO.md`'s `PG-150` entry is updated to reflect completion, consistent with how prior
  `PG-` entries in this chain family were closed (e.g. `PG-149`). (no-test: a project-ledger edit,
  not application behavior)

## Definition of Done

R-01–R-17 implemented and verified in-session (build green, full unit suite green, the five
interleaving tests in R-11–R-15 present and passing, `scripts/mcp-smoke.py` unmodified and passing).
R-18–R-20 completed as part of this chain's own closing steps (ADR status line, issue close,
TODO.md entry) — not deferred to a future session, since they are the record of this fix having
landed, not application work.
