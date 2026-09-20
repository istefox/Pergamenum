Status: Approved (2026-09-20)

# SPEC — Pratiche ledger is only written over the ledger it was loaded from (PG-172)

## Destination

A SPEC to hand off to `/workplan`: one fix chain, no new feature. Reaching the end means no
Pratiche writer can save a ledger that was never loaded for the vault it is saving into, an
unreadable ledger file is never overwritten, the in-memory Pratiche state of one vault never
survives into another, and a trashed pratica's tombstone no longer outlives its own claim.

> Correction from `/workplan` (2026-09-20): reading the code shows six ledger save sites, not four
> (`remapLedgerConversations` in `PraticheController+Ledger.swift` has the same vault-switch half of
> the defect). Every «four writers» below means all six save sites; R-02 and R-10 already cover it.

## Objectives

`PraticheController` keeps an in-memory copy of the per-vault ledger. It starts empty and only
`load(from:)` fills it, which the Pratiche pane, the settings tab and two sheets call; the app
never calls it at launch. Four writers (the tray count, «opened» stamp, folder-move remap and
sync-outcome record) mutate that copy and save it straight back. A folder move or a sync outcome
that happens before the pane was ever opened therefore overwrites the real ledger with an empty or
partial one, and loses every pratica's imported ids, bridge entries, not-in-store list, last-opened
date and tray count, none of which is recoverable from disk. The second variant is the same defect
across a vault switch: a ledger loaded for vault A is saved into vault B's file. Confirmed by
reading the writers, not yet reproduced at runtime.

Two neighbouring defects share the cause or the hook and ride along: other in-memory Pratiche state
(tray counts, tray proposals, file watchers) is never reset when the vault changes, and a
tombstone left by a trashed pratica (PG-169) is only dropped when nothing at all is in flight.

## Scope and non-goals

In scope:
- A «ledger loaded for this file» marker on the controller, and one door through which every
  ledger mutation and save goes.
- A ledger file that exists but cannot be read is left untouched by every writer.
- When the marker shows a different vault, the vault-scoped in-memory state is reset.
- The tombstone of a trashed pratica is dropped per path, when no claim on that path remains.

Non-goals: the ledger's on-disk format, the connectors, the read side (a read before any load
still sees an empty ledger, which loses nothing), the other half of PG-173 (a queued sync for a
trashed pratica reporting «non ha un dossier leggibile»), PG-168, and the unreadable-file recovery
UI (no quarantine, no repair action).

## Decisions

- **Marker plus lazy load, not an eager load at launch** — the controller remembers which ledger
  file its in-memory copy came from. A writer whose session points at a different file, or at none
  yet, reloads from disk first, then mutates. This covers "never loaded" and "loaded for another
  vault" with one rule and does not depend on any caller remembering to call `load(from:)`.
  Rejected: eager load on session change — needs a hook on the vault switch and an ordering proof,
  and still leaves a writer that runs before the hook unprotected. Rejected: both — more surface
  for the same guarantee.
- **One door, not a check in each writer** — the ledger becomes read-only outside the controller's
  own ledger code and is changed only through one method that verifies the marker, mutates and
  saves. A fifth writer cannot forget the check. Same shape as the vault-boundary resolver in
  ADR-0041 (a resolver callers cannot route around, not an assertion they can skip). Rejected: an
  `ensureLoaded` helper each writer calls — this is how the four writers reached the defect.
- **An unreadable ledger file is never saved over** — the load distinguishes «missing» (fresh,
  saving is fine) from «present but unreadable» (corrupt JSON or a schema this build does not
  know). For the second, every writer skips its save, the app works on an empty in-memory ledger
  for the session, and one message names the file, once per file per session. The person repairs or
  deletes the file by hand. Rejected: moving it aside automatically — leaves an orphan file nobody
  is told about, and turns a refusal into a silent policy.
- **The PG-169 special case in `forgetLedgerState` collapses into the same door** — its
  «if the in-memory ledger is empty, reload» heuristic is exactly what the marker replaces, and a
  heuristic that treats a genuinely empty ledger as «never loaded» would keep reloading needlessly.
- **A change of vault resets what belongs to the vault** — when the marker names a different file,
  the tray proposals, tray counts, file watchers, selection, timeline and details are cleared
  together with the ledger. Today only the no-vault branch of `load(from:)` clears anything, and it
  clears neither the tray state nor the watchers. Rejected: ledger only — leaves vault A's badges
  showing on any vault-B pratica with a colliding path.
- **A tombstone is dropped per path** — the tombstone for path X falls when no sync or
  regeneration that captured X is still in flight, regardless of claims on other paths. It is kept
  while a claim on X is open, since that claim is stale by definition and refusing it is correct.
  Rejected: a per-claim identity token — distinguishes a recreated same-name pratica from a stale
  claim on it, but touches every caller of the path resolver for a P3 cosmetic case. Rejected:
  leaving it — the refusal of a healthy sync by an unrelated open sheet is the reported symptom.

## Constraints

- **Ledger file format unchanged, `IndexCache.schemaVersion` unchanged** — origin: ADR-0036 §D3,
  and the connectors read this same file (`VaultAPI.pratiche`).
- **The connectors keep reading exactly what they read** — origin: ADR-0007; a change to the
  shared ledger type must compile in `perg` and `pergamenum-mcp`.
- **Tests never resolve the real state directory** — origin: CLAUDE.md principle 3; every test
  passes a temporary state base.
- **No test is disabled or deleted; tests that assign the ledger directly move onto a test seam**
  — origin: CLAUDE.md working agreements.
- **PG-169's behaviour is preserved** — origin: ADR-0026 §D7 as amended; the folder-trash test
  files stay green unchanged in what they assert.

## Data model

One new piece of controller state: the ledger file the in-memory copy was loaded from, absent when
nothing is loaded. A ledger loaded from a file is one of three outcomes: loaded, missing (empty,
writable) or unreadable (empty in memory, not writable). The persisted ledger itself is untouched.

## API / interfaces

No connector, CLI or MCP change. Internally the controller's ledger stops being assignable from
outside its own ledger code; a single mutation entry point replaces the four direct save sites and
the special case in `forgetLedgerState`. `PraticaLedger`'s load gains a way to tell «missing» from
«unreadable»; its shared file compiles into both connector targets, so the change is additive.

## Edge cases

- Writer runs on a controller that never loaded, file present and readable: reload, mutate, save;
  every other pratica's state survives.
- Writer runs on a controller that never loaded, file missing: starts from empty, saves. That is
  a first-ever write, not a loss.
- Loaded for vault A, then a writer receives vault B's session: reload B's file, reset the
  vault-scoped state, mutate, save. A's file is not touched.
- Vault closed (no session): marker cleared, same reset as above.
- File unreadable: no write, one message per file per session, the app keeps working. Once the file
  is readable again, the next load returns to normal saving.
- A sync outcome for a vault that is no longer the live one already reads that vault's own file
  fresh; it goes through the same unreadable-file rule.
- Tombstone: a claim on another path stays open while X's own claim ends; X's tombstone drops. A
  claim on X still open keeps it.

## Test seams

One seam, at the level existing tests already use: `PraticheController` driven directly, with a
real `ledger.json` written under a temporary state base and read back after each writer runs. This
is where the folder-trash tests already sit, so no new seam is needed. The vault-switch case uses
two sessions on two temporary state bases. The tombstone case uses the controller's own claim
begin/end calls, as the PG-169 mid-run tests do. The «one door» guarantee is a type-system property.

## Success criteria

- [ ] R-01 — A controller that never loaded, with a readable ledger on disk, runs each of the four
  writers (tray count, opened stamp, folder move, sync outcome); afterwards the file still holds
  every pratica's prior state and only the intended change differs.
- [ ] R-02 — A controller loaded for vault A whose writer then receives vault B's session leaves
  A's file byte-identical, and B's file holds B's prior state plus the change and nothing from A.
- [ ] R-03 — With no ledger file at all, a writer starts from empty and saves; that first write is
  not treated as a refusal.
- [ ] R-04 — With an unreadable ledger file, none of the four writers nor the trash path alters the
  file (bytes identical before and after), and exactly one problem message naming that file is
  reported per session however many writers run.
- [ ] R-05 — After the unreadable file is repaired to a readable one and the ledger is loaded
  again, writers save normally.
- [ ] R-06 — Loading for vault B after vault A clears tray proposals, tray counts, watchers,
  selection, timeline and details; the pratiche list holds no A entry. Closing the vault clears the
  same set.
- [ ] R-07 — After X's claim ends, X's tombstone is gone even while a claim on another path is
  open; a fresh sync on a recreated X is not refused.
- [ ] R-08 — While a claim on X is still in flight, X's tombstone remains and that claim's outcome
  is still discarded (PG-169's behaviour).
- [ ] R-09 — The existing PG-169 folder-trash, mid-run-trash, relocation and record-outcome test
  files pass without loosening any assertion, and both connector targets still build.
- [ ] R-10 — The ledger cannot be assigned from outside the controller's ledger code. (no-test: enforced by the type system, verified by the build and by review of the diff)

## Not yet specified

- How the per-vault file watchers are stopped when the marker changes, and whether the controller
  already holds the handles to stop them or only drops them. For `/workplan` to read off the code;
  the outcome required is in R-06.

## Out of scope

- **Unreadable-file recovery UI** — the refusal is the whole behaviour here; a repair or quarantine
  action is a separate feature, and the ledger is rebuildable by design (a fresh one costs one
  re-sync).
- **PG-173 first half** — a queued sync reporting «non ha un dossier leggibile» for a trashed
  pratica; cosmetic, needs `SyncRunQueue`'s private state, a different mechanism.
- **PG-168 and #208** — relocation TOCTOU windows and a missing ledger write for an unrecoverable
  followed conversation; neither shares the loading defect.
- **The read side** — a read of the ledger before any load sees an empty one and loses nothing.

## Domain terms

- **Marker** — the record of which ledger file the in-memory ledger was loaded from.
- **Tombstone** — the entry in the forgotten-paths set left when a pratica folder is trashed
  while a sync or regeneration holds its path (PG-169).
- **Claim** — a sync or a «Rigenera…» attempt holding a pratica path as its own.
