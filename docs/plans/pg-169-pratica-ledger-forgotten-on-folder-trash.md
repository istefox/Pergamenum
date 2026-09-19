# Fix: a pratica's per-path state is forgotten when its folder is trashed (PG-169)

SPEC: `SPEC.md` (Approved 2026-09-19). Deletion twin of
`docs/plans/pg-pratica-ledger-orphaned-by-folder-move.md` (relocation) and
`docs/plans/pg-pratica-relocation-mid-sync-stop.md` (the mid-run half of it).

## ADR outcome — no new ADR; ADR-0026 §D7 governs, extended by one dated amendment

ADR-0026 §D7 already carries the rule this work is a second instance of, in its
**Amended 2026-09-17** bullet: a folder relocation publishes itself, and *path-keyed
feature state (Pratiche's ledger today) must subscribe rather than assume its own path is
stable*. Trashing is the same rule with the opposite verb and no destination, so a
separate ADR-0051 would split one rule across two documents — exactly the drift that
amendment exists to prevent, and the same reason the relocation fix itself (larger than
this one) wrote no ADR of its own.

Task 6 appends a second dated bullet to ADR-0026 §D7 (the ADR file's only change), which
also records the one deliberate **no** a future reader would otherwise be tempted to undo:
*no pruning of ledger keys that have no folder on disk, at load or anywhere else*. That no
is load-bearing — a Finder move, an unmounted volume or a not-yet-scanned index all look
identical to a deleted pratica, and pruning on that evidence turns the relocation bug this
chain just fixed into unrecoverable history loss. Everything else here is mechanism, and
lives in this document.

Verified, not assumed: the highest-numbered ADR on disk is `0050`, so a new file would have
been `0051`; none is written.

## Decisions registered from the SPEC (settled, not reopened)

A hook on the one folder-trash door rather than a fix in the pratica delete command; a
subtree-aware removal keyed with the trailing-slash prefix convention; every path-keyed
piece of state removed, not only the ledger; an in-flight run stopped with its outcome
discarded; no prune-on-load; no journal and no undo for the ledger removal.

## Design

### The two new seams

| Layer | New symbol | Shape it mirrors |
|---|---|---|
| `Sources/App/VaultController.swift` | `@ObservationIgnored var didTrashFolder: ((String) -> Void)?` | `didRelocateFolders` (:129) |
| `Sources/App/VaultController+Folders.swift` | one call in `trashFolder(at:)`, after the `trashedNote(at:)` loop, before `Task { await rescan() }` | `renameFolder`'s own `didRelocateFolders?(...)` call (:54) |
| `PraticheController+Ledger.swift` | `followFolderTrashing(_:in:)` | `followFolderRelocations(_:in:)` |
| `PraticheController+Ledger.swift` | `forgetLedgerState(under:in:)` | `moveLedgerState(from:to:in:)` |
| `PraticheController+Ledger.swift` | `static removeKeys(_:under:forgotten:isInFlight:)` | `static remapKeys(_:from:to:redirects:isInFlight:)` |
| `PraticheController.swift` | `var forgottenPraticaPaths: Set<String> = []` | `praticaPathRedirects` |
| `PraticheController+Ledger.swift` | `PraticaRunStop.praticaTrashed(path:)` | `.praticaRelocated(from:to:)` |

The published path is `relativePath.trimmingCharacters(in: .pathSlashes)` — the exact
normalization `canOperateOnFolder` performs one line above, so a caller that ever passes
`"F/"` cannot leave a key behind. (`didRelocateFolders` in `renameFolder` publishes the raw
`relativePath`; not changed here, its callers are the same tree rows.)

`trashFolder` fires the hook only after `try session.trashFolder(...)` returned. Every
failure path in `FolderFileOperations.trashFolder` **throws** (`la radice del vault non si
elimina`, `.missing`, a `trashItem` failure wrapped in `.failed`), and the
`canOperateOnFolder` refusal returns before the `do` — verified by reading
`Sources/Vault/FolderFileOperations.swift:415-439`. So "fired ⇒ the folder really went to
the Trash" holds by construction, which is R-05.

### One resolver, three answers — why the tombstone is not a second map read separately

Today `resolvePraticaPathRedirect` answers one question ("where did this key move?") for
three callers: `recordSyncOutcome`, `endRegeneration`, `praticaPath(continuing:)`. A
trashed pratica needs a second fact ("this key is gone"), and a second set read *beside*
the map is the `assertInsideVault(url)` shape CLAUDE.md's working agreement forbids — the
fourth caller would read one and forget the other.

So `resolvePraticaPathRedirect` becomes a private, file-scoped resolver returning one value:

```swift
private enum PraticaPathDestination { case same, moved(String), forgotten }
private func destination(of captured: String) -> PraticaPathDestination
```

Walk the redirect chain exactly as today (`visited` guard unchanged); if the final hop — or
the captured path itself when nothing moved — is in `forgottenPraticaPaths`, the answer is
`.forgotten`. All three existing callers switch on it:

- `praticaPath(continuing:)` — `.same` returns, `.moved` throws `.praticaRelocated` (as
  today), `.forgotten` throws the new `.praticaTrashed(path:)`.
- `recordSyncOutcome` — `.forgotten` (only when `isCurrentVault`, since both structures
  describe the live vault alone) **returns without writing anything**: no ledger key, no
  `problem` sentence, no `ledger` assignment. This is the one guard that closes the
  regeneration half of R-06, because `commitRegeneration` deliberately has no post-`await`
  re-check (`PG-168`'s third case).
- `endRegeneration` — `.moved` releases the remapped claim, `.same`/`.forgotten` release
  the path as given.

The enum stays `private` to `PraticheController+Ledger.swift`: all three callers live in
that file, and tests drive the behaviour through `praticaPath(continuing:)` and
`recordSyncOutcome`, never through the resolver.

### What `forgetLedgerState(under:in:)` does, in order

1. Snapshot `isInFlight` from `syncingPraticaPath`/`regeneratingPraticaPaths` **before**
   anything is mutated (`moveLedgerState`'s own first line, same reason).
2. `removeKeys` over `ledger.byPraticaPath`, `trayProposals`, `trayCounts`,
   `watchersByPraticaPath` — a key equal to `path` or prefixed by `"\(path)/"` is removed,
   and inserted into `forgottenPraticaPaths` only when `isInFlight(key)` (review round 2's
   MINOR 1 rule, kept: a deletion with nothing running records no tombstone, because
   nothing will ever read one).
3. Independently of the dictionaries: if `syncingPraticaPath` or any member of
   `regeneratingPraticaPaths` is equal to or under `path`, tombstone it too. This is not
   redundant — a pratica's **first** sync has no ledger entry yet (`?? .empty` never
   inserts one), so step 2 would not have seen it, and that is precisely R-08's shape.
4. If `syncingPraticaPath` was affected, call `requestSyncStopForVanishedPath?()`.
5. If `selection` is equal to or under `path`, clear it through the existing door,
   `select(nil, in: vault)`, so `expansion`, `timeline`, `details` and `links` follow
   exactly as they do when a person deselects — rather than assigning `selection = nil` and
   leaving four other properties describing a folder in the Trash.
6. Save the ledger once, at the end, reporting a failure through `problem` like the
   relocation routine does.

`syncingPraticaPath` and `regeneratingPraticaPaths` are **not** cleared. Unlike a
relocation, which remaps them, a deletion leaves the claim exactly where the run itself
will release it (`endSync`/`endRegeneration`) — clearing it here would let
`pruneRedirectsIfIdle` wipe the tombstone while the run it protects is still in flight.
`pruneRedirectsIfIdle` gains `forgottenPraticaPaths.removeAll()` beside the existing
`praticaPathRedirects.removeAll()`; `load(from:)`'s no-vault branch clears it the same way
and for the same reason.

### Stopping an in-flight run (R-06), by kind

- **Ordinary sync.** `RunContext.livePraticaPath(in:)` is already the only way a step in
  `runExclusive`'s pipeline can name a pratica folder, so the new `.praticaTrashed` throw
  lands at all six existing guard points with no new call site. `runExclusive`'s single
  exhaustive `switch stop` (`PraticaLiveSync+Run.swift:133`) gains one arm mapping
  `.praticaTrashed` to `.finished` — never `.relocated(to:)`. That matters: `.relocated`
  drives `Self.requeue`, and re-enqueueing a trashed pratica would dequeue into
  `runExclusive`'s "«…» non ha un dossier leggibile in pratica.md" report. `Self.requeue`
  itself is untouched (it already answers `nil` for anything that is not `.relocated`).
- **Engine.** `requestSyncStopForRelocation` is renamed `requestSyncStopForVanishedPath`
  and `PraticaLiveSync.stopForRelocation()` to `stopForVanishedPath()` — the path the run
  captured is gone, and whether it moved or went to the Trash does not change what the
  engine must do. Two Sources call sites, zero test call sites (verified by grep).
- **Regeneration.** `prepareRegeneration`'s and `commitRegeneration`'s existing
  `praticaPath(continuing:)` guards now also refuse a trashed pratica, with no code change
  at either site beyond the Italian sentence each reports; `recordSyncOutcome`'s
  `.forgotten` arm covers the window where the trash lands *during*
  `await engine.commitRegeneration(plan)`, which has no post-await re-check by design.

Residual, stated rather than hidden: `PraticaSyncEngine.cancel()` is cooperative and
checked once per message, so the message being written at the instant of the trash can
still complete into the trashed path and recreate the folder (`NoteStore.write`'s own
`createDirectory`). That is `PG-168`'s first case exactly, unchanged by this work: orphan
garbage with no `pratica.md` beside it, never a lost message, never a resurrected ledger
key. R-06's tests assert the stop request and the discarded outcome, not that zero bytes
land — the SPEC's edge-case wording ("the folder is not recreated by the engine") is true
for every message after the cancellation is observed, and this plan does not claim more.

### R-07 — verified by reading the engine, and then pinned by a test

`PraticaSyncEngine.folderContext(of:)` builds `messagesByID` by parsing every `.md` in
`<pratica>/email/` and keying it on the `Message-ID` in its own frontmatter — read off the
disk, with no reference to the ledger. `resolveContext` then returns `nil` for a candidate
whose file is already there unless one of three narrow conditions holds (the body was
written `pending` and has since arrived, this is the message an explicit «Rigenera» named,
or the file carries a pending attachment/inline-image entry). `nil` means `prepare` returns
nothing, `commit` never runs, nothing is written and nothing joins
`outcome.importedMessageIDs`. A message with no file gets a name from
`PraticaNaming.uniqueMessageFileName(..., existing: folder.takenNoteNames)`, which cannot
collide with a name already in the folder.

So the SPEC's assumption holds: a folder restored from the Trash with no ledger entry is
re-reconciled file by file, not re-imported. **The claim it does not support** — worth
saying plainly, since it is the honest cost of the "no prune, no undo" position: the
restored pratica's ledger stays empty for those messages (they are skipped, so they never
re-enter `importedMessageIDs`), so every later sync re-walks and re-decodes them, and the
`entries` bridge ADR-0040 §D5 uses for the ~3% of messages the index cannot resolve is gone
for good. Wasteful and degraded, never duplicated and never overwritten, which is what
R-07 asserts.

---

## Tasks

### Task 1 — The folder-trash door publishes what it trashed (R-04, R-05)

Declarations the tester writes first, so the target builds and the tests are red rather
than uncompilable: `@ObservationIgnored var didTrashFolder: ((String) -> Void)?` on
`VaultController`.

- `Sources/App/VaultController.swift` — the property, beside `didRelocateFolders` (:129),
  with the same doc-comment shape (wired once by `PergamenumApp.init`, `nil` in every test
  that builds a bare controller).
- `Sources/App/VaultController+Folders.swift` — one line in `trashFolder(at:)`, after the
  `trashedNote(at:)` loop and before `Task { await rescan() }`, publishing the trimmed
  path.
- `Tests/VaultSessionFolderOperationsTests.swift` (225 lines, room to spare), beside the
  existing `vaultControllerTrashesAFolderAndForgetsTheNoteItRemoved`:
  - `trashingAFolderPublishesItsPathExactlyOnce` — R-04 at the door.
  - `aRefusedTrashPublishesNothing` — reuse
    `vaultControllerRefusesToRenameAFolderWithAnUnsavedNoteUnderIt`'s setup verbatim
    (`openNote` + `updateOpenNoteText`), then `trashFolder`; assert `false`, a recorded
    problem, and zero hook calls (R-05).
  - `aFailedTrashPublishesNothing` — `trashFolder(at: "01 Progetti/mai-esistita")`; assert
    `false` and zero hook calls (R-05).

R-04 is proved at the **door**, not at a caller, on purpose: `vault.trashFolder(at:)` is
the single entry point all three surfaces use — the pratica command
(`PraticaCommandActions.swift:113`), the note list (`NoteListPane+FolderVerbs.swift:147`)
and the Workspace browser (`WorkspaceView+FolderVerbs.swift:133`) — and
`VaultSession.trashFolder` has exactly one caller in `Sources/`, this method (grep
verified). Neither view file is touched by this work, and neither is unit-testable without
the UI suite, which the SPEC excludes. Task 3 adds the one caller-level proof that *is*
reachable from a unit test.

### Task 2 — `forgetLedgerState(under:in:)`, the deletion twin of `moveLedgerState` (R-01, R-02, R-03)

Declarations the tester writes first: `forgetLedgerState(under:in:)`,
`followFolderTrashing(_:in:)` and `var forgottenPraticaPaths: Set<String> = []` (declared
now, populated in Task 4).

- `Sources/Features/Pratiche/PraticheController.swift` — `forgottenPraticaPaths`, doc'd
  the way `praticaPathRedirects` is.
- `Sources/Features/Pratiche/PraticheController+Ledger.swift` — `forgetLedgerState`
  (design steps 1, 2 without the tombstone, 5, 6), `followFolderTrashing`, and the
  `removeKeys` static beside `remapKeys`. `remappedPath`'s trailing-slash convention is
  reused, not re-derived: `removeKeys` removes a key exactly when
  `remappedPath(key, from: path, to: path)` would have matched it — express it as one
  shared `isInSubtree(_:of:)` predicate that both statics call, so the sibling-prefix rule
  cannot drift between the move and the delete twin.
- New file `Tests/PraticaLedgerFolderTrashTests.swift` — `@MainActor @Suite(.serialized)`,
  mirroring `PraticaLedgerFolderRelocationTests` test for test. A new file, not an addition
  to `Tests/PraticheControllerTests.swift`: that file is at 968 lines against SwiftLint's
  `file_length` **error** at 1000 (ADR-0045's own precedent for where a new battery goes).
  - `forgetLedgerStateRemovesTheExactKey` (R-01)
  - `forgetLedgerStateRemovesEveryDescendantUnderATrashedAncestor` (R-02)
  - `forgetLedgerStateLeavesASiblingPrefixAlone` — `01 Progetti-altro` survives trashing
    `01 Progetti` (R-02)
  - `forgetLedgerStateRemovesTrayProposalsCountsAndTheWatcher` (R-03)
  - `forgetLedgerStateClearsASelectionInsideTheTrashedSubtreeAndLeavesOneOutsideIt` (R-03)
  - `forgetLedgerStatePersistsTheRemovalToDisk` — `PraticaLedger.load(from:)` back off the
    real ledger URL, the shape `moveLedgerStatePersistsToDisk` already uses (R-01)

### Task 3 — Wire it in the app, and prove the pratica command inherits it (R-04, R-08)

- `Sources/App/PergamenumApp.swift` — beside the existing `didRelocateFolders` closure
  (:129), `vault.didTrashFolder = { [weak pratiche] path in pratiche?.followFolderTrashing(path, in: vault) }`.
- `Tests/PraticaLedgerFolderTrashTests.swift`:
  - `trashingAFolderThroughTheDoorForgetsTheLedgerKey` — `TemporaryVault`,
    `VaultController(recents: .volatile(), openTabs: .volatile())`,
    `PraticheController.live(vault:)`, hook wired by hand exactly as
    `undoOfFolderMoveRestoresLedgerKey` wires `didRelocateFolders` (R-04).
  - `deletingAPraticaThroughItsOwnCommandForgetsTheLedgerKey` — the one caller-level proof
    available to a unit test: `PraticaCommandActions(pratiche:vault:navigation:)`
    (constructible today, `Tests/PraticaLinkCommandTests.swift:47`) → `confirmDeletion(of:)`
    (R-04).
  - `aPraticaRecreatedUnderTheSameNameStartsFromAnEmptyLedger` — the ticket's acceptance
    case: seed `importedMessageIDs`, trash through the door, recreate the folder with the
    same name and a fresh `pratica.md`, `load(from: vault)`, assert the key is absent and
    `ledger.byPraticaPath[path]?.importedMessageIDs ?? []` is empty (R-08).

### Task 4 — An in-flight sync or regeneration is stopped, and its outcome is discarded (R-06)

Declarations the tester writes first: `PraticaRunStop.praticaTrashed(path: String)`, the
`PraticaPathDestination` enum and `destination(of:)`, and the two renames
(`requestSyncStopForVanishedPath`, `stopForVanishedPath()`) — the last two are what make
the target build at all once the call sites move.

- `Sources/Features/Pratiche/PraticheController+Ledger.swift` — the new `PraticaRunStop`
  case; `resolvePraticaPathRedirect` replaced by `destination(of:)`; the three callers
  switched over it; `recordSyncOutcome`'s `.forgotten` early return;
  `pruneRedirectsIfIdle` clearing the tombstones; `forgetLedgerState` gaining design steps
  2-tombstone, 3 and 4.
- `Sources/Features/Pratiche/PraticheController.swift` — the property rename and its doc
  comment (relocation **or** trash).
- `Sources/Features/Pratiche/PraticaLiveSync.swift` — the method rename (:161) and the
  `live(vault:)` wiring (:20).
- `Sources/Features/Pratiche/PraticaLiveSync+Run.swift` — the one new `switch stop` arm
  (:133), `.praticaTrashed` → `.finished`.
- `Sources/Features/Pratiche/PraticheController+Ledger.swift` — `load(from:)`'s no-vault
  branch also clears `forgottenPraticaPaths`.
- New file `Tests/PraticaLiveSyncTrashedMidRunTests.swift`, modelled on
  `Tests/PraticaLiveSyncRelocatedMidRunTests.swift` (492 lines — a new file, not an
  addition). No test races a real sync by timing: "a trash has happened" is an entry in
  `forgottenPraticaPaths`, installed at the same synchronous seam the relocation suite uses
  (`beginSync`/`beginRegeneration`, then `followFolderTrashing`), then production code is
  driven with the captured path. The precedent forbidding timing-based interleaving tests
  is `Tests/PraticaLiveSyncRecordOutcomeTests.swift`'s header and ADR-0046 §D2/§D11.
  - `praticaPathContinuingRefusesAPraticaThatWasTrashed` — `.praticaTrashed(path:)`
  - `aTrashedPraticaIsRefusedEvenAfterARelocationHop` — trash the *destination* of an
    earlier relocation; the chain must resolve to `.forgotten`, not `.moved`
  - `recordSyncOutcomeWritesNothingForATrashedPratica` — the headline for the regeneration
    half: seed a claim, trash, then call `recordSyncOutcome` with the captured path and
    assert the key is absent in memory **and** in the saved file
  - `runExclusiveReturnsFinishedForATrashedPraticaSoNothingIsRequeued` — never
    `.relocated`
  - `trashingAPraticaWithASyncInFlightAsksTheEngineToStop` — a spy on
    `requestSyncStopForVanishedPath`
  - `trashingAPraticaWithNoRunInFlightRecordsNoTombstone` — MINOR 1's rule, kept
  - `aFirstSyncWithNoLedgerEntryYetIsStillTombstoned` — design step 3, the R-08 race
  - `commitRegenerationRefusesAfterTheTrashAndWritesNothing`
  - one no-trash regression assertion added to an existing `PraticaLiveSync*` test,
    proving the resolver change did not break the ordinary record path

### Task 5 — A folder restored from the Trash re-syncs without duplicating or overwriting (R-07)

Test-only; the design section above records the code reading that predicts it, and this
task is what turns that reading into a fact.

- `Tests/PraticaSyncRetryTests.swift` (143 lines, already built on `MailStoreFixture` +
  `PraticaSyncFixtures`):
  - `aResyncWithAnEmptyLedgerLeavesTheMessageFilesExactlyAsTheyAre` — one fixture message,
    `engine.sync` with `onDisk: []`, then a **second** `engine.sync` with `onDisk: []`
    again (the restored-folder shape: files present, ledger empty). Assert
    `PraticaSyncFixtures.mdFiles(under:)` is unchanged in count and names, the note's bytes
    are byte-identical across the two runs, and the second outcome's `writtenFiles` and
    `importedMessageIDs` are both empty (R-07).

If the assertion does not hold, stop and report rather than adapting the test: the SPEC's
"no journal, no undo" decision rests on this claim, and a failure here reopens it.

### Task 6 — Remove the TODO and repoint the twin's plan document (R-09)

- `Sources/Features/Pratiche/PraticaCommandActions.swift` — delete the seven-line `TODO`
  in `confirmDeletion` (:106-112) and replace it with one sentence saying the ledger and
  the rest of the path-keyed state are forgotten by `VaultController.didTrashFolder`
  (ADR-0026 §D7, PG-169), the same way `confirmRename`'s comment points at
  `didRelocateFolders`. Drop the now-dead
  `if pratiche.selection == pratica.id { pratiche.select(nil, in: vault) }` line, which the
  hook has already performed — mirroring how `confirmRename` dropped its own redundant
  `moveLedgerState` call. Task 3's command-level test is what keeps that honest.
- `docs/plans/pg-pratica-ledger-orphaned-by-folder-move.md` — the "Deliberately out of
  scope" section names this defect as unfixed; add one sentence pointing at this document
  and at the fix, so the two twins cross-reference each other (R-09).
- `docs/adr/0026-drag-and-drop-board-files-into-workspace.md` §D7 — one **Amended
  2026-09-19** bullet after the 2026-09-17 one: the trash door publishes
  `didTrashFolder` too, path-keyed state must forget as well as follow, and a key whose
  folder is not on disk is never pruned on that evidence alone.
- `TODO.md` — `PG-169`'s entry is closed at ship time, not here.

### Task 7 — Build, lint and the unit suite green, nothing disabled (R-10)

1. `tuist generate --no-open` (two new test files are added to the target).
2. `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' build`
3. `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test`
   — the **whole** unit suite, not only the Pratiche files: `PraticheController`,
   `VaultController` and `PraticaRunStop` are shared, and a contract change is exactly what
   breaks a test in a module nobody was looking at.
4. `swiftlint` — `PraticheController+Ledger.swift` is at 494 lines (warning at 400, error
   at 1000) and gains roughly 60; `PraticaLiveSync.swift` is at `type_body_length`'s line
   per `PG-160`, so Task 4's changes there stay a rename plus a call, no new member.
5. `scripts/uitests.sh` before merging to `main` (repo convention). Not extended by this
   work and not run by any task above — `.claude/test-cmd` stays restricted to
   `-only-testing:PergamenumTests`.

---

## Call sites of every contract this touches (grep-verified, so nobody discovers them late)

- `PraticaRunStop` — one exhaustive `switch` at `Sources/Features/Pratiche/PraticaLiveSync+Run.swift:133`
  (adding a case is a compile error there, which is the point); pattern-matching call sites
  that stay green: `Sources/Features/Pratiche/PraticaLiveSync+Run.swift:313`,
  `Tests/PraticaLiveSyncRelocatedMidRunTests.swift:315`,
  `Tests/PraticheControllerTests.swift:752,767`.
- `requestSyncStopForRelocation` → `requestSyncStopForVanishedPath`:
  `Sources/Features/Pratiche/PraticheController.swift:259,263`,
  `Sources/Features/Pratiche/PraticheController+Ledger.swift:306`,
  `Sources/Features/Pratiche/PraticaLiveSync.swift:20`. No test references it.
- `stopForRelocation()` → `stopForVanishedPath()`:
  `Sources/Features/Pratiche/PraticaLiveSync.swift:20,161`. No test references it.
- `recordSyncOutcome` behaviour (new silent-discard arm) — production callers
  `Sources/Features/Pratiche/PraticaLiveSync+Run.swift:310` and
  `Sources/Features/Pratiche/PraticaLiveSync.swift:423`; tests asserting the *old*
  behaviour, all of which must stay green because none of their paths is tombstoned:
  `Tests/PraticaLiveSyncRecordOutcomeTests.swift:94,126,138`,
  `Tests/PraticheControllerTests.swift:195,213,232,616,682,698`.
- `VaultController.trashFolder` callers, unchanged by this work and inheriting the hook:
  `Sources/Features/Pratiche/PraticaCommandActions.swift:113`,
  `Sources/Features/Editor/NoteListPane+FolderVerbs.swift:147`,
  `Sources/Features/Workspace/WorkspaceView+FolderVerbs.swift:133`.

## Risks, residuals and HITL gates

- **HITL — commit, push, merge.** Human decision, as always. `scripts/uitests.sh` before the
  merge to `main`.
- **No externally provisioned resource.** No network, no new dependency, no env var, no
  schema change: `IndexCache.schemaVersion` stays 4 and the ledger file format is untouched
  (a removed key is a key that is not there).
- **Destructive-adjacent, by nature.** The routine deletes ledger entries. The blast radius
  is bounded by the trailing-slash subtree rule, which Task 2's sibling-prefix test pins,
  and by the hook firing only after a real `trashItem`. A folder trashed outside the app
  still leaves its key, deliberately (the no-prune decision).
- **`PG-168`'s cooperative-cancel window applies unchanged** — the message being written at
  the instant of the trash can still land in the trashed folder and recreate it. Orphan
  garbage, never a lost message, never a resurrected key.
- **Ledger save failure.** `forgetLedgerState` reports through `problem` and leaves memory
  clean, but `confirmDeletion`'s own `pratiche.load(from: vault)` immediately re-reads the
  file that failed to save and puts the removed keys back in memory. Accepted rather than
  papered over with a pending-removal queue: the next successful save of any kind, or the
  next deletion, clears it, and the visible symptom is the pre-existing one this ticket
  describes rather than a new failure mode.
- **A sync queued but not yet running for a pratica that gets trashed** is not covered, and
  my own assessment is that it should be filed rather than fixed here. `SyncRunQueue.pending`
  and `queuedRequests` are private to `PraticaLiveSync`, the tombstone is only recorded for
  something actually claimed, and `shouldRunQueuedRequest` runs a request whose pratica has
  vanished from the list; so the dequeued run reaches `runExclusive`'s
  `guard let dossier` and reports «"…" non ha un dossier leggibile in pratica.md» in the
  pane. Cosmetic and self-clearing, no state written, and it predates this work — worth a
  `P4` TODO line, not worth widening this lane's surface and adding a fourth closure.
- **A restored pratica's ledger never re-learns what is on disk** (design §R-07): each later
  sync re-decodes every message it skips, and ADR-0040 §D5's ROWID bridge is gone for that
  pratica. This is the accepted cost of "recovery is the Trash"; recorded so a future reader
  does not read the green R-07 test as "restore is free".

## TEST-CMD

`TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test`

`TEST-CMD MODE: brownfield` — the line is `.claude/test-cmd` verbatim; the suite exists,
runs today, and the SPEC's two test seams are both inside `PergamenumTests`.

## Follow-ups decided at /build close (2026-09-19), to register in TODO.md at /ship

- **P2, correctness:** `PraticheController.moveLedgerState`, `recordSyncOutcome` and `updateTray`
  save the ledger unconditionally, even when the in-memory ledger was never loaded (starts as
  `.empty`; only `load(from:)` fills it, and the app never calls it at launch). Same defect shape
  as the PG-169 review's MAJOR, fixed here only in `forgetLedgerState`. Second variant, reviewer
  confidence ~55: a ledger loaded for vault A and then written into vault B's `ledger.json` after
  a vault switch without opening the Pratiche pane. The fix is a design decision (a «ledger loaded
  for URL X» marker), not a per-call guard, so it is its own ticket.
- **P4, cosmetic:** a sync queued but not yet running for a trashed pratica reports «non ha un
  dossier leggibile in pratica.md»; and `forgottenPraticaPaths` survives until
  `pruneRedirectsIfIdle`, so a pratica recreated under the same name can be refused while an
  unrelated claim stays open. Both rare and self-clearing, neither loses data.
- **Declined:** splitting `PraticheController+Ledger.swift` (678 lines, warning only) into a
  `+Trash` extension. Left for a refactor lane.
