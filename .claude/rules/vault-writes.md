---
paths:
  - "Sources/**/*.swift"
---

# Vault write path and unsaved-state invariants

Moved verbatim from the `## Working agreements` section of `CLAUDE.md` on 2026-10-07; loaded only
when a file matching `paths:` is read.

- **A security or invariant check exposed as a separately-callable assertion gets skipped by the
  next call site, not maliciously — just by omission.** `NoteStore`'s vault-boundary check stayed
  `private` and reachable from exactly two of eleven call sites for this reason (ADR-0041). Expose
  it instead as the only way to obtain the value callers need (`VaultBoundary.url(for:) throws ->
  URL`, not `assertInsideVault(url)`) — a resolver a caller cannot route around, rather than a step
  a caller can forget.
- **A precondition evaluated before an `await` is a filter, not a guard.** Swift hands the main
  actor back to the run loop at every suspension point, so the state the precondition checked can
  change before the code it was meant to protect runs. `PraticaEntryComposer.insert`'s
  `canOperate(on:)` check, read once before two `await`s, is exactly this shape (ADR-0043 §D7) — by
  the time the write and its hand-off ran, the tab it refused to find dirty had become dirty. The
  guard belongs on the same side of the suspension as the action it protects: ask again after the
  `await`, or act on state read after it, never on a check made before it.
- **A ledger, cache or registry the app holds in memory and saves back must record which file it
  was read from.** A writer that cannot prove it is writing over the file it loaded reads first, and
  never saves over a file it could not read. `PraticheController.ledger` could be written back from
  the wrong memory two ways (a folder rename or a first sync before the pane was ever opened; a
  vault switch that left vault A's ledger in memory over vault B's file) because nothing tied the
  memory to a file — and a corrupt `ledger.json` was the same loss with a third trigger. The fix is a marker
  (`LedgerOrigin`) plus one write door (`updateLedger(_:_:)`) with `private(set)` on the property,
  so a new writer cannot route around it (ADR-0052 §D1/§D3).
- **A file `VaultWatcher` cannot see is a file no automatic reconciliation can start from.**
  `.canvas` paths never reach `VaultWatcher.handle(absolutePaths:)` (it discards everything but
  `.md`), so a Workspace board open in memory has no external signal telling it another writer
  touched the same file — the shape that let a rename/move's board-repoint write get silently
  clobbered by an open board's own pending autosave (`PG-099`). The fix is not extending the
  watcher; it is the ADR-0052 pattern applied to bytes instead of a ledger: `WorkspaceController`
  records a `BoardOrigin` (the hash of what it last read or saved), `CanvasStore.save(_:board:
  expecting:)` refuses a write whose bytes moved on since, a pure `.file`-node repoint reconciles
  automatically against that refusal, and anything reconciliation cannot decide surfaces as a
  named, non-modal `.conflicted` state on the board itself rather than an overwrite or a discard
  (ADR-0054 §D2/§D5/§D7).
- **A new holder of unsaved state reviews itself in `QuitCoordinator`, never in
  `willTerminateNotification`.** Every termination (Cmd+Q, the red button on the last window,
  logout, restart, shutdown) reaches `AppDelegate.applicationShouldTerminate(_:)`, which asks
  `QuitCoordinator` (ADR-0073 §D1): the board settles, the dirty note tabs of every column are asked
  about app-modally before anything replies, then the diary is awaited. `willTerminateNotification`
  fires after the decision to exit, so a flush started there is a write nothing waits for and a
  question asked there is too late (PG-326: Cmd+Q dropped every dirty note tab without asking). The
  coordinator owns the one reply; a new phase goes into its order, not beside it. One exception sits
  in the delegate on purpose: the unit-test host refuses every termination before the coordinator
  is asked (`AppDelegate.isTestHost`, PG-363), so the coordinator, which knows nothing of the
  process environment, is never consulted there. A conflicted board or diary day is named in that
  same question and never written by it: «Salva» cancels and shows its banner, only «Non salvare»
  lets it go (ADR-0089).
