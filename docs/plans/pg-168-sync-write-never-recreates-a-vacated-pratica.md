# PG-168 (#313): a sync write never recreates a vacated pratica folder

Closes the residual gap named in `pg-pratica-relocation-mid-sync-stop.md` §7. No new ADR: a third
adoption of the ADR-0043 §D8 / ADR-0046 opt-in write-precondition family (the `PG-161` precedent,
not `PG-152`).

## Problem

`PraticaSyncEngine.cancel()` is cooperative, observed once per message. The message already past
that boundary when a pratica folder is moved or trashed finished writing, and every write on its
path created its own parent chain, so it brought the vacated folder back: a stray
`<vacatedPath>/email/` with a valid message and no `pratica.md`. Never a lost message, but orphan
garbage that `rescan()` indexes.

## Decision: containment, not winning the race

A sync is not entitled to bring a pratica folder into existence; only the wizard is. Once no write
on that path can create its own parent chain, the message in flight either lands where the folder
still is or fails loudly. The losing case is `ENOENT`, never a resurrected directory.

Verified first: every other write named by the TODO's "third case" already carries `expecting:`
(`applyConversationRemap`, `evaluateCandidates`, `follow`/`ignore` via `DossierWriter.update`,
`commitRegeneration`'s two patch writes). `VaultDisk.write` compares it with the file's current
bytes inside the actor, and a vanished file reads as `nil`, so it is already refused with
`movedOn`. Those four windows are closed by documentation (comments rewritten to say so), not code.

Exactly three writes could resurrect a folder, all in `PraticaSyncEngine+Messages.swift`: the
full-render note write (`expecting` is `nil` by ADR-0043 §D8's own exclusion), the attachment
bytes and the `.eml` sidecar (both `writeAtomically`, never through `VaultSession`).

## What changed

- `VaultWriteRefusal.folderVanished(path)`: carries the folder, not the file, because the folder is
  the actionable thing.
- `NoteStore.write(_:to:requiringExistingFolder:)`: purely suppressive, default `false`. Six callers
  exist and rename/move legitimately write into folders they just made, so the default stays
  creating. Flipping it is a non-goal and would need an ADR.
- `VaultDisk.write` and `VaultSession.write` take the same flag and refuse with `folderVanished`
  inside the actor, beside `expecting:` (ADR-0043 §D5). A second parameter, not an extension of
  `expecting:`, because §D8's exclusion of the full render stands.
- `PraticaSyncEngine.makeDirectory(_:of:)`: `email/` and `allegati/` are made only under a pratica
  that already has its `pratica.md`, one leaf at a time, no intermediates. `writeAtomically` no
  longer creates any directory. `commit` makes `email/` before any attachment, so a vacated folder
  costs zero bytes.
- The two production engine closures pass `requiringExistingFolder: true`.
- A `folderVanished` refusal caused by a relocation or trash is a `PraticaRunStop` (requeue or
  finish), not a «Sincronizzazione non riuscita» report.
- Leftovers already on disk, or bytes that landed just before a move, are reported by
  `PraticaRunStop.leftoverNotice(after:)` when the vacated path still exists. Never touched: an
  orphan is indistinguishable from a folder made by hand (File over app). A sweeper would be its
  own «Ripara…» command with a preview.
- «Rigenera» after a relocation: `PraticaFileOperations.restore` returns the files it could not put
  back instead of reporting, and does not create directories. `commitRegeneration` returns
  `PraticaRegenerationCommit` (`committed`/`refused`/`failed`), so a refusal keeps its actionable
  sentence («recuperabili da lì») instead of being overwritten by the generic one.

## Tests

`PraticaSyncVacatedFolderTests` (removed folder, folder without dossier, attachment, first sync
still creates `email/`/`allegati/`, no attachment means no `allegati/`, and the deterministic
mid-run regression: the write closure moves the whole folder after the first note),
door tests in `VaultWriteOrderingBatch3Tests`, `PraticaFileOperationsRestoreTests`. No timing
races. The fixtures' write closure no longer creates intermediates, so it cannot mask the
resurrection.

## Accepted residue

A move landing between `makeDirectory` and the note write can still leave attachment bytes under
the old path; the leftover notice reports it. The `.refused` restore edge (a stale empty directory
at the old path makes the restore succeed while the sentence mentions the Trash) is accepted.
