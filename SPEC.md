Status: Approved (2026-09-19)

# SPEC — Forget a pratica's per-path state when its folder is trashed (PG-169)

## Destination

A SPEC to hand off to `/workplan`: a small fix lane, no new feature. Reaching the end means
that trashing a pratica folder, or any ancestor of one, leaves no path-keyed Pratiche state
behind, from every place the app can trash a folder.

## Objectives

Pratiche keeps per-pratica state keyed by the pratica folder's vault-relative path: the import
ledger (`importedMessageIDs`, pending entries, not-in-store list, tray count, bridge entries),
the tray proposals and counts, the file watcher, the selection, and the in-flight sync or
regeneration claim. Trashing the folder today leaves all of it in place. Recreating a pratica
with the same name then inherits the old one's history: the stale `importedMessageIDs`, the
«non più in Mail» list, the bridge entries, `lastOpenedAt` and the tray count. Corrected
2026-09-19 after testing: the first reading of this ticket said `workItems` would refuse to
re-queue those messages, but `MailStoreReader.rows` builds every row with `messageID: nil`, so
stale ids alone do not filter anything and the engine's own on-disk `Message-ID` scan decides.
The defect is state leaking into a folder that never earned it, with no error to show for it.

This is the deletion twin of the folder-relocation orphaning already fixed (ADR-0026 §D7,
`didRelocateFolders`): same state, same key, same shape of hazard, opposite verb. The fix
mirrors that one so the two cannot drift.

## Scope and non-goals

In scope:
- One hook on the vault's single folder-trash door, fired after a successful trash, carrying
  the trashed folder's vault-relative path.
- Pratiche subscribes and drops every piece of path-keyed state equal to or nested under it.
- An in-flight sync or regeneration for an affected pratica is stopped and its outcome
  discarded rather than written back.
- Removal of the `TODO` comment in the pratica delete command that this defect left there.

Non-goals (detail under Out of scope): pruning ledger keys orphaned by deletions the app did
not perform, undoing a ledger removal, connector changes, any change to the on-disk ledger format.

## Decisions

- **Generic hook on the trash door, not a fix inside the pratica delete command** — the
  folder-trash door has three callers (the pratica «Elimina pratica» command, the note list's
  folder delete, the Workspace browser's folder delete). Trashing an ancestor such as a
  project folder orphans every descendant pratica the same way. A hook on the door covers all
  three and the ancestor case with one subscription, exactly as `didRelocateFolders` does for
  moves. Rejected: fixing only the pratica command as the ticket literally names it — leaves the
  same defect reachable from two other surfaces and from any ancestor deletion.
- **Subtree-aware removal** — a key equal to the trashed path or under `"<path>/"` is removed,
  with the trailing slash in the prefix so a sibling named `a-altro` is never taken for a
  descendant of `a` (the convention the move batch and `remappedPath` already use). Rejected:
  exact-key removal — misses descendant pratiche.
- **Every path-keyed piece of state goes, not only the ledger** — tray proposals, tray counts,
  the per-pratica watcher, and the selection travel with the ledger key, as they already do on
  relocation. A stale watcher or a dangling selection on a folder that no longer exists is the
  same class of leak. Rejected: ledger only — the ticket's wording, but it would leave the
  in-memory state disagreeing with the persisted one until the next launch.
- **An in-flight run is stopped and its outcome discarded** — reuses the cooperative stop the
  relocation path already requests, and makes a run whose path was deleted unable to write its
  outcome back. Without it `recordSyncOutcome` would recreate the key the hook just removed, and
  the engine would keep writing into a folder that was just trashed (ADR-0043 §D7's shape:
  a check made before the `await` is a filter, not a guard). Rejected: removing the key and
  ignoring the race — resurrects the very defect being fixed, only less often.
- **No pruning of orphaned keys on load** — a key with no folder on disk is not proof the
  pratica is gone: a Finder move, an unmounted volume or a not-yet-scanned index looks the same,
  and deleting the ledger for those is unrecoverable where an orphan is merely wasteful.
  Rejected: prune-on-load — would turn the relocation bug into silent history loss.
- **Ledger removal is not journalled and needs no undo** — assumption, see Edge cases: the sync
  engine matches messages already on disk by `Message-ID` before writing, so a folder restored
  from the Trash with no ledger entry re-reconciles rather than duplicating or overwriting.

## Constraints

- **Hook shape mirrors `didRelocateFolders`** — a closure on the vault controller, wired once in
  the app's `init`, so the vault controller gains no reference to anything Pratiche-shaped —
  origin: existing ADR-0026 §D7 and the dependency direction ADR-0007 fixes.
- **Fires only after a trash that succeeded** — a refused or failed trash (unsaved note in the
  folder, disk error) must leave the ledger untouched — origin: correctness, the state
  describes a folder that still exists.
- **No `IndexCache.schemaVersion` change, no ledger file-format change, no connector change** —
  origin: the ledger is a plain per-vault file both connectors read; removing a key needs neither.
- **No test is disabled or weakened**; new tests use Swift Testing and a temporary state base —
  origin: CLAUDE.md working agreements.

## Stack

Swift 6, the existing vault controller / Pratiche controller pair. No dependency added.

## Data model

Unchanged. The per-vault ledger maps a pratica folder path to its state; this work only
removes entries. Every in-memory dictionary keyed by the same path (tray proposals, tray
counts, watchers) is treated identically.

## API / interfaces

- The vault controller gains one optional closure, invoked with the vault-relative path of a
  folder that was just trashed, after the trash succeeded and before the rescan is scheduled.
- The Pratiche controller gains one entry point that the closure calls, and a removal routine
  that is the deletion counterpart of its existing relocation routine.
- The removal saves the ledger once, at the end, like the relocation routine does.

## UI flows

No visible change. «Elimina pratica» keeps its confirmation alert and its outcome.

## Edge cases

- **Ancestor trashed** — deleting a folder that merely contains one or more pratiche removes
  all their state; a sibling whose name shares a prefix is untouched.
- **A pratica selected inside the trashed subtree** — the selection is cleared and the timeline
  emptied, as the delete command already does for the pratica it deletes.
- **Sync or regeneration in flight for a pratica in the subtree** — stopped, outcome discarded,
  the key is not recreated, the folder is not recreated by the engine after the trash.
- **Restore from the Trash** — the folder returns without a ledger entry. Assumed safe because
  the engine reads the folder's existing message files by `Message-ID` before deciding what to
  write. This is the one claim resting on reading code rather than running it, so it needs a
  test that proves it (R-07), not just a hope.
- **Trash refused or failed** — no state is touched.
- **Ledger cannot be saved** — reported through the existing problem channel, as the
  relocation routine does; the in-memory state is still cleaned.
- **Delete, recreate under the same name, sync** — the new pratica starts from an empty
  ledger and imports every message that matches, which is the acceptance case for the ticket.

## Test seams

Two, both existing and both at the controller level, no UI test:
1. The Pratiche controller's own unit suite, where the relocation routine is already pinned
   (exact key, descendant under an ancestor, sibling prefix, tray/selection/watcher/in-flight
   path, persistence to disk, no redirect when idle). The removal routine gets the same battery.
2. The vault controller's folder-operation tests, for the hook itself: fires with the right path
   after a successful trash, does not fire on a refused or failed one.

The end-to-end shape (delete, recreate, sync imports everything) is asserted at seam 1 by
driving the same door the relocation tests already drive, not through the UI. The UI suite is
neither needed nor extended; `scripts/uitests.sh` is unaffected.

## Success criteria

- [ ] R-01 — Trashing a pratica folder removes its ledger key from memory and from the persisted
  ledger file.
- [ ] R-02 — Trashing an ancestor folder removes the ledger keys of every pratica nested inside
  it, and leaves a sibling folder whose name merely shares the prefix untouched.
- [ ] R-03 — The same removal applies to tray proposals, tray counts and the per-pratica watcher,
  and clears the selection when it points inside the trashed subtree.
- [ ] R-04 — The hook fires from all three callers of the folder-trash door, not only from the
  pratica delete command.
- [ ] R-05 — The hook does not fire, and no state changes, when the trash is refused or fails.
- [ ] R-06 — A sync or regeneration in flight for a trashed pratica is stopped, and its outcome
  does not recreate the ledger key.
- [ ] R-07 — A pratica folder restored from the Trash with no ledger entry re-syncs without
  duplicating or overwriting the message files already in it.
- [ ] R-08 — Deleting a pratica and creating another with the same name yields a ledger that
  starts empty, so the new pratica's first sync is not filtered by the old one's imported IDs.
- [ ] R-09 — The `TODO` comment in the pratica delete command describing this defect is removed
  and the ledger-orphaning note in the earlier fix's plan document is updated to point at the fix
  (no-test: a comment and a documentation obligation, nothing to assert).
- [ ] R-10 — Build, linter, and the unit suite are green with no test disabled.

## Not yet specified

_none_

## Out of scope

- **Ledger keys orphaned by deletions or moves outside the app** (Finder, another tool) — no
  pruning on load, for the reason in Decisions. Recorded so a later reader does not mistake the
  absence for an oversight. Stefano's own already-orphaned entries were repaired by hand under
  the earlier plan and need nothing here.
- **A stale ledger entry left by a pratica that stops being a pratica** (its `pratica.md` removed
  while the folder stays) — a different trigger, no folder trash involved.
- **Undo of a folder trash** — folder delete is not journalled (ADR-0022) and recovery is the
  Trash itself.
- **Connectors** — `perg` and `pergamenum-mcp` read the ledger but never delete a folder.
- **The wider async-write hazards** tracked under their own PG numbers.

## Domain terms

- **Ledger** — the per-vault file recording, per pratica folder path, what was imported from
  Mail. Not the source of truth for content, which is the files on disk (principle 3).
- **Folder-trash door** — the vault controller's single method that moves a folder to the
  Finder's Trash, whatever surface asked for it.
