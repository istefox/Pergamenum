# Fix: pratica ledger orphaned by folder move/rename (PG "allegati non si scaricano")

## Context

Stefano reported that pratica attachments never resolve even after re-downloading them
in Apple Mail. Live inspection of his real vault (`.../Vaults/Pergamena/Calendar/01
Progetti/Tifone/Relazioni TIfone`) found the true cause has nothing to do with Mail:

- The pratica ledger (`~/Library/Application Support/it.stefer.pergamenum/vaults/<uuid>/
  pratiche/ledger.json`, `PraticaLedger.byPraticaPath: [String: PraticaState]`,
  `Sources/Core/Pratiche/PraticaLedger.swift:92`) is keyed by the pratica folder's
  **vault-relative path**.
- At some point the whole `01 Progetti` subtree was moved under a new `Calendar/`
  folder (drag-and-drop, ADR-0026). The pratica itself (`Relazioni TIfone`) is a
  **descendant** of the moved folder, not the moved item.
- The ledger key never followed: `ledger.json` now has BOTH the orphaned
  `01 Progetti/Tifone/Relazioni TIfone` (63 entries, 63 imported message IDs,
  `lastOpenedAt: 2026-09-16`) AND a fresh, empty
  `Calendar/01 Progetti/Tifone/Relazioni TIfone` (0 entries, `lastOpenedAt:
  2026-09-17`).
- `PraticaSyncEngine.regeneratePending` (`Sources/Features/Pratiche/
  PraticaSyncEngine+Messages.swift:704-745`, the every-sync no-cap retry for pending
  attachments, ADR-0040 §D5) resolves a message's ROWID either from the live Mail
  index or, when the index can't resolve it (~3% of messages, per the code's own
  comment), from `request.ledgerEntries` — scoped to the *current* path. With that
  ledger entry empty, the fallback silently does nothing (`guard let rowID =
  rowIDByMessageID[messageID] ... else { continue }`): no write, no error, forever.
  Two message notes in the pratica still carry a bare (pending) attachment name in
  `pergamenum-mail-attachments`, untouched since Sep 12 despite a sync having run
  today.

A near-identical mechanism, `PraticheController.moveLedgerState(from:to:in:)`
(`Sources/Features/Pratiche/PraticheController+Ledger.swift:205-221`), already exists
and does the right single-key swap — but its only call site is the pratica's own
«Rinomina…» command (`PraticaCommandActions.confirmRename`,
`PraticaCommandActions.swift:113-124`). The generic ADR-0026 batch move/rename path
(`VaultController.moveItems` → `VaultSession.moveItems`'s `.folder` branch, and
`VaultController.renameFolder`) never calls it, and `VaultController` has no reference
to `PraticheController` (dependency direction runs the other way).

Goal: any folder move or rename that carries a pratica along — whether the pratica
itself or an ancestor of it — keeps that pratica's ledger (and related per-path state)
attached, both forward and through undo/redo. Plus a one-time manual repair of
Stefano's already-orphaned ledger and cleanup of two stale/duplicate ledger entries
found during triage.

## Design

Reviewed by an independent Plan pass; adopting its choke-point instead of my first
(UI-layer) draft, since it also covers rename and undo/redo for free.

1. **`Sources/Vault/VaultSession+Move.swift`** — add
   `var movedFolders: [MovedNote] = []` to `MoveBatchOutcome` (next to `movedNotes`,
   ~line 31). Populate it in the `.folder` branch (~line 133-144) alongside the
   existing `outcome.movedNotes.append(contentsOf: folder.movedNotes)`:
   `outcome.movedFolders.append(MovedNote(old: move.item.path, new: folder.newPath))`
   — `folder.newPath` is `FolderFileOperations.MoveOutcome`'s own field
   (`FolderFileOperations+Move.swift:68`), disk truth, no re-derivation of the
   landing-path arithmetic.

2. **`Sources/App/VaultController.swift`** — add one closure property, matching this
   repo's existing dependency-injection idiom (`PraticheController.probe`/
   `performSync`): `var didRelocateFolders: (([MovedNote]) -> Void)?`. `VaultController`
   stays `@MainActor`/`@Observable` and gains no import of anything Pratiche-shaped.

3. **`Sources/App/VaultController+Move.swift`** — in `follow(_:)` (~line 182-187),
   before the `Task { await rescan() }`, call
   `if !outcome.movedFolders.isEmpty { didRelocateFolders?(outcome.movedFolders) }`.
   Because `follow(_:)` is the single choke point for forward moves *and* for
   `performInverse` (undo/redo, `VaultController+Move.swift:178`), this one hook
   covers both directions automatically — undo moving the pratica folder back
   re-triggers the same remap with old/new swapped.

4. **`Sources/App/VaultController+Folders.swift`** — in `renameFolder(at:to:)`
   (~line 41-57), after computing `outcome`, call
   `didRelocateFolders?([MovedNote(old: relativePath, new: outcome.newPath)])` before
   the `Task { await rescan() }`/`return`. This covers renaming an *ancestor* folder
   (e.g. renaming `01 Progetti` itself), which orphans a pratica the same way a move
   does and was not covered by `confirmRename`'s pratica-only call.

5. **`Sources/Features/Pratiche/PraticheController+Ledger.swift`** —
   - Generalize `moveLedgerState(from:to:in:)` to be **subtree-aware**: for every key
     in `ledger.byPraticaPath` equal to `oldPath` OR prefixed by `"\(oldPath)/"`
     (the exact convention `VaultMoveBatch.plan` already uses at
     `VaultMoveBatch.swift:63-70` to avoid mistaking `a-altro` for a descendant of
     `a`), replace the `oldPath` prefix with `newPath` and re-insert. Apply the same
     remap to `trayProposals`, `trayCounts`, `selection` (existing), plus
     `watchersByPraticaPath` and `syncingPraticaPath` (found during review — both are
     per-pratica-path state that would otherwise silently detach from the moved
     pratica: a stale watcher never fires for the new path, and an in-flight sync's
     completion could resurrect the orphaned key). One save at the end, unchanged.
   - Add `func followFolderRelocations(_ moved: [MovedNote], in vault: VaultController)`
     that loops `moved` and calls the generalized remap for each — the single place
     `didRelocateFolders` calls into.
   - Simplify `PraticaCommandActions.confirmRename` (`PraticaCommandActions.swift:118`)
     to drop its now-redundant direct `pratiche.moveLedgerState(...)` call: the
     generic hook in `renameFolder` already ran by the time `confirmRename` gets
     `newPath` back, so the explicit call would be a harmless but confusing no-op.

6. **`Sources/App/PergamenumApp.swift`** — in `init()` (~line 123), after
   `let pratiche = PraticheController.live(vault: vault)` (currently inlined directly
   into `_pratiche = State(initialValue: ...)`; pull it into a local `let` first),
   wire: `vault.didRelocateFolders = { [weak pratiche] moved in
   pratiche?.followFolderRelocations(moved, in: vault) }`, then
   `_pratiche = State(initialValue: pratiche)`.

No new ADR: this is a bug fix under ADR-0026 (§D1/§D7, batch move) and ADR-0036
(pratica sync). Add one sentence to ADR-0026 §D7 noting that a folder relocation
publishes `movedFolders`/triggers `didRelocateFolders`, and that path-keyed feature
state (Pratiche's ledger today) must subscribe to it rather than assume its own path
is stable.

### Deliberately out of scope (found during review, not this bug)

- `PraticaCommandActions.confirmDeletion`/`trashFolder` never removes the ledger key:
  trashing a pratica and recreating one with the same name would inherit stale
  `importedMessageIDs`. Real, but a separate defect — filed as a TODO comment only,
  not fixed here.

## Manual data repair (after the code fix, before closing this out)

On Stefano's real vault/ledger (`~/Library/Application Support/it.stefer.pergamenum/
vaults/30A57D29-D869-484F-926E-7C15B1555621/pratiche/ledger.json`):

1. Back up `ledger.json` first (timestamped copy next to it).
2. Rename the orphaned key `01 Progetti/Tifone/Relazioni TIfone` to
   `Calendar/01 Progetti/Tifone/Relazioni TIfone` (merging into whatever the app has
   already recorded there since, if anything — the orphan's 63 entries are the ones
   worth keeping).
3. Delete the two stale keys entirely: `01 Progetti/Tifone/Relazione macchinari
   TIfone` (folder no longer exists on disk) and `01 Progetti/Tifone/Relazione tecnica
   TIfone` (folder still exists on disk under `Calendar/01 Progetti/Tifone/` but has
   no `pratica.md`, i.e. it is not a pratica any more — per Stefano, test data).
4. Move `Calendar/01 Progetti/Tifone/Relazione tecnica Tifone` (the folder itself, 63
   email notes + 3 attachments) to the Trash via Finder or `NSWorkspace`/
   `FileManager.trashItem` — not a hard delete — since Stefano confirmed only
   `Relazioni TIfone` should remain active in Pratiche. Confirm the exact trash
   action with Stefano immediately before running it (destructive-adjacent, per this
   session's own guardrails).
5. Quit and relaunch Pergamenum (or trigger a manual sync on `Relazioni TIfone`) and
   confirm the two previously-pending attachments
   (`20260519_OrdineFornitore_Nr_2026_OF_372.pdf`,
   `20260603_OrdineFornitore_Nr_2026_OF_372.pdf`) resolve to `[[name]]` links with
   files present under `allegati/`.

## Tests to add (Swift Testing, `#expect`)

- `Tests/VaultMoveTests.swift`:
  - `movingAFolderNamesItsOldAndNewPathInMovedFolders` — move a folder, assert
    `outcome.movedFolders == [MovedNote(old: ..., new: ...)]`.
  - `movingOnlyANoteLeavesMovedFoldersEmpty`.
- `Tests/PraticheControllerTests.swift` (uses the existing
  `PraticheController(probe:performSync:)` lightweight constructor for in-memory
  assertions, and `PraticheController.live(vault:)` + an opened `VaultController` —
  pattern already at lines 292-295 — for the on-disk save case):
  - `moveLedgerStateRemapsExactKey`
  - `moveLedgerStateRemapsDescendantPraticheUnderMovedAncestor` (the actual bug shape:
    remap `01 Progetti` → `Calendar/01 Progetti` and confirm a pratica at
    `01 Progetti/Tifone/X` lands at `Calendar/01 Progetti/Tifone/X`)
  - `moveLedgerStateLeavesSiblingPrefixAlone` (`01 Progetti-altro` must not be treated
    as a descendant of `01 Progetti`)
  - `moveLedgerStateCarriesTrayCountsSelectionWatchersAndSyncingPath`
  - `moveLedgerStatePersistsToDisk`
  - `undoOfFolderMoveRestoresLedgerKey` (drives `VaultController.moveItems` then its
    undo, via the existing `TemporaryVault`/`armedSession` helpers in
    `Tests/VaultMoveTests.swift`, and asserts the ledger key follows both ways)
  - `renameOfAncestorFolderRemapsLedgerKey`

## Verification

1. `tuist generate --no-open`
2. `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination
   'platform=macOS' build`
3. `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination
   'platform=macOS' test` (full suite — this touches shared vault-move code, not just
   Pratiche)
4. Manual: perform the data repair steps above on the real vault, then drag-and-drop
   move a throwaway pratica folder to a different parent in a running Debug build,
   confirm the pratica keeps its sync state (no re-import prompt, tray badge
   unchanged), then undo the move and confirm the ledger follows back.
5. `scripts/uitests.sh` before merging to `main` (repo convention).
