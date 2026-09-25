# ADR-0060: ADR-0057's remaining follow-ups — five write sites, quit flush, board navigation

## Status

Accepted.

## Context

ADR-0057 gave the diary a write guard: `readDiary` returns the disk state it read,
`writeDiary(over:)` is mandatory, `VaultSession.write` gained an `expectingAbsent:`
precondition, and a refused write becomes a non-modal `.conflicted` state with «Mantieni le
mie modifiche» / «Ricarica dal disco». Its §D8 deliberately scoped four things out and filed
each one as a GitHub issue: #495, #496, #497, #498.

#495 (the Diario pane picking up an external change) landed separately, on another branch, as
`docs/adr/0058-in-process-writes-reach-every-tab.md`'s companion PR #503, while this chain was
already in progress — `VaultController.didChangeExternally` fanned out to a new
`DiaryController.externalChange(at:)` that reloads a clean pane and leaves a dirty one for the
next write's own precondition to catch. This ADR does not reopen that decision; it closes the
remaining three.

## Decision

### D1 · #496 — guard the five remaining read-then-write sites

`append(text:to:)` (`VaultSession+Watching.swift`), `linkFromDailyNote`
(`VaultSession+EventNotes.swift`), the `addStructuralLink` pair (`VaultSession+Notes.swift`),
`moveOnBoard` (`VaultSession+BoardDrop.swift`) and `captureTask`'s creation case
(`VaultSession+Tasks.swift`) each now pass `expecting:` the hash of the read they built their
write on, using the same `VaultSession.write(_:to:expecting:expectingAbsent:)`/
`VaultWriteRefusal` machinery the diary's own adoption already exercises. A writer landing
between the read and the write is refused, never silently overwritten.

`addStructuralLink`'s doc comment, which claimed the two-file link was atomic, is corrected:
with `expecting:` on both writes, a refusal on the *second* can leave the first already
landed. Rolling back is not safer — the rollback is one more guarded write that can itself be
refused — so the half-written state is reported by name (both file paths, in Italian) rather
than silently reconciled. All-or-nothing in the decision, best-effort in the execution
(ADR-0046 §D3's rule, applied here). This function's signature had already changed on `main`
to `(created: Bool, written: [WriteResult])` (ADR-0058 §D5, landed independently) so the
editor's tab catch-up sees whatever wrote before a refusal; the guard keeps appending to
`written` before checking each write's outcome, so both behaviours compose rather than
compete.

`captureTask`'s creation case also gains `expectingAbsent: existing == nil`. This is stricter
on purpose: `existing` comes from a `try?` read, so a file that exists but fails to parse
previously took the creation branch and was silently overwritten. `expectingAbsent:` tests
existence, not readability, so that file is now refused instead. The superseded "§D8 excludes
creation by name" comment is rewritten — that exclusion covers "make the file say this"
writes, not a read-modify-write whose read came back empty.

`moveOnBoard` now catches `VaultSession.WriteRefusal` explicitly and surfaces its own
`.description`, rather than falling through to `error.localizedDescription`, which for this
type yields Foundation's generic string, not the refusal's Italian sentence.

`append`'s one caller (`VaultAPI.appendToNote`, `Sources/Connector/VaultWrites.swift`) now
switches on the full `WriteOutcome` including the new `.stale` case, reporting the refusal's
own sentence instead of `problems.last` — a refusal records no problem of its own (the file is
intact), so `problems.last` would have named an unrelated failure.

### D2 · #497 — the quit flush actually lands

`DiaryView`'s flush on `willTerminateNotification` raced the process: that notification fires
after the decision to exit, so nothing awaited the write it started. `AppDelegate` gains
`applicationShouldTerminate(_:)`, the one hook that can legitimately delay termination:
settled → `.terminateNow`; otherwise `.terminateLater`, racing two independent tasks — one
awaiting a new `DiaryController.settle()` (`flush()` then loop on `runner` until the write
queue drains), one a 2-second timeout — whichever finishes first calls `NSApp.reply
(toApplicationShouldTerminate:)`, guarded so only the first reply counts. Two independent
tasks rather than a `TaskGroup`, because `settle()` awaits a write that ignores cancellation:
a group would wait out a hung write, defeating the timeout's purpose. `AppDelegate` reaches
the controller the same way it already reaches `vault`: a `weak var diary` set in the same
`.onAppear`. The now-redundant `willTerminateNotification` hook in `DiaryView` is removed —
the new hook strictly precedes it and does strictly more.

Named, not fixed: `WorkspaceController` has the same shape (a debounced autosave) and no
terminate hook at all. Out of #497's scope, which names the diary; filed as a new issue
(#506) rather than folded in silently.

### D3 · #498 — refuse navigation away from a conflicted board

`WorkspaceController.load(board:)` and `select(_:)` both gain a guard,
`refusesToLeaveConflictedBoard()`, mirroring `DiaryController.show(_:)`/`load()`'s one-line
guard for the same shape of conflict: `flushPendingSave()` already skips a conflicted board by
design (ADR-0054 §D5), so navigating away used to replace `document`/`origin` and silently
drop the unresolved conflict along with whatever edit prompted it. Refused and reported
instead, in the diary's own non-modal style. `detach()` stays unguarded on purpose — it
already reports the loss and is the vault-closing path, which must not be blockable.

A second defect, found while implementing this guard rather than named in the original plan:
`select(nil)` sets `board = ""` and `origin = .none` while leaving `saveState == .conflicted`,
so `BoardChrome` stops drawing and both resolution verbs become unreachable against a board
that no longer has a path. The `select(_:)` guard closes this too — the state is now
unreachable — since it runs before the folder/`nil` branch as well as the `.board` one.

A third defect, also found during implementation: the sidebar's rename/move/trash verbs
(`WorkspaceView+FolderVerbs.swift`) still performed their disk operation on a conflicted open
board even after the navigation guards above landed — the file moved, `board` kept naming the
old path, and neither resolution verb could read it any longer, turning a recoverable conflict
into an unrecoverable one. `WorkspaceController.canLeaveOpenBoardForVerb()` (a public wrapper
over the same private guard) is checked in `moveItems(_:into:)`, `performFolderVerb` and
`performBoardVerb`, right after `flushBoard()` and before the disk operation — so the file
never moves out from under an unresolved conflict.

## Consequences

- Five more read-then-write sites in `Sources/Vault` are guarded the same way the diary
  already was; `Sources/Connector` and `Sources/Vault` remain shared sources with `perg`/
  `pergamenum-mcp`, both confirmed building against the new signatures.
- A quit with unsaved diary text now waits up to 2 seconds for the write rather than losing it
  outright.
- A conflicted Workspace board can no longer be silently abandoned through the sidebar tree or
  through a rename/move/trash verb; the only unguarded exit is closing the vault.
- New tests: `Tests/VaultUnguardedWriteGuardTests.swift`, `Tests/DiarySettleTests.swift`, plus
  two additions to `Tests/WorkspaceAutosaveRaceTests.swift`.
- Out of scope, filed separately: `WorkspaceController`'s own quit-flush gap (#506), the same
  shape as #497 but for boards.
- No on-disk format, schema, or protected interface touched.

Extends ADR-0057, amends none.
