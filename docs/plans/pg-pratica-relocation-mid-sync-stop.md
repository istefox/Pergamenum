# Fix: a folder relocation mid-sync must stop the run, not write under the vacated path

Follow-up to commit `ba09c06` (round-4 review finding). Branch `fix-pratiche-allegati`.

## Context

`ba09c06` fixed the reported defect: the pratica ledger, keyed by the pratica folder's
vault-relative path, was orphaned when a folder containing (or being) a pratica moved or
was renamed, stranding the attachment-retry data so pending attachments never resolved.
That fix publishes relocations from `VaultController.didRelocateFolders` and remaps every
path-keyed piece of Pratiche state, plus a `praticaPathRedirects` map so an in-flight
sync's completion cannot resurrect the orphaned key.

A fourth review round found the redirect map closes exactly **one** consumer,
`recordSyncOutcome`. `PraticaLiveSync` is `@MainActor`, so the relocation handler runs at
every suspension point, and `runExclusive` has four of them. After the first one (copying
Apple Mail's Envelope Index, seconds) the captured path is still used by six more
consumers — two of them ledger writes, four of them **disk paths**:

| Consumer | Site | Damage when the path moved |
|---|---|---|
| `remapLedgerConversations` | `+Run.swift:92` | `guard var state = ledger.byPraticaPath[path]` fails → conversation-ID remap silently dropped, losing the pratica's recovery data |
| `updateTray` → `persistTrayCount` | `+Run.swift:230`, `+Ledger.swift:31` | `ledger.byPraticaPath[path] = state` **re-inserts an entry at the orphaned path** — the original defect, recreated |
| `praticaNotePath` + read/write of `pratica.md` | `+Run.swift:93-114` | reads/writes the vacated path |
| `DossierWriter.update(at:)` | `+Run.swift:156` | writes the vacated path |
| `SyncRequest(praticaFolder:)` | `+Run.swift:188` | the folder the engine writes every message `.md` and attachment into, for the whole of `await engine.sync(...)` |
| `dossier(at:)` | `+Run.swift:223` | reads the vacated path |

Same shape in the regeneration pair: `prepareRegeneration` and `commitRegeneration` (via
`plan.praticaFolder`) both feed `SyncRequest(praticaFolder:)`.

### Why stop rather than adapt

Three verified facts decided this.

1. **`NoteStore.write` (`Sources/Vault/NoteStore.swift:143-144`) does
   `createDirectory(withIntermediateDirectories: true)`.** A write to the vacated path
   **recreates the folder**. Attachments and `.eml` do not even go through the session —
   `PraticaSyncEngine+Paths.directory(_:of:)` resolves them directly, same behaviour.
   `SyncRequest.praticaFolder` is frozen for the whole `engine.sync` call, so nothing
   inside the engine can follow a relocation. Adapting the *callers* cannot fix the
   largest window.

2. **Adapting would create permanently-missing messages.** Messages written to the old
   folder after the move still land in `outcome.importedMessageIDs`; a
   `recordSyncOutcome` that resolves the redirect records them under the **new** key, so
   the next sync's `onDisk` excludes them from `MembershipRule.candidates` and they are
   never re-imported. Files in one folder, counted as imported in another: the defect
   class this chain exists to close.

3. **Stopping is cheap.** `MailStorePreparation.prepare` publishes into
   `PraticheController.stateDirectory(for: session)` — per **vault**, not per pratica —
   and `MailStoreCopy.publish` returns `.unchanged` when the generation directory already
   exists. A re-run does not re-copy; it repays SQLite reads and a few small file reads.

And it is the codebase's own idiom: `vault.session === session` (`+Run.swift:206, 209,
213`; `PraticaLiveSync.swift:297, 308, 337`), `regenerationEngine === engine`
(`:287, 305`), `run(praticaPath:kind:)` dropping a dequeued request whose session changed
(`:167`). `RunContext`'s own doc already says every step must keep acting on the vault
this run started against; a relocated path is the same category of value with no guard.

**Counterweight, verified:** nothing re-triggers a sync on its own. The FSEvents stream
watches `~/Library/Mail`, not the vault; `scanGeneration` is not observed by Pratiche;
`PraticaWatcher` is a pure decision struct with no timer. So stopping *without* an
explicit re-enqueue would trade "wrong ledger key" for "silently never synced". The
re-enqueue is not optional.

## Design

### 1. The detection primitive — a resolver, not a predicate

`Sources/Features/Pratiche/PraticheController+Ledger.swift`, beside the existing
`resolvePraticaPathRedirect` (stays `private`, gains a second caller):

```swift
enum PraticaRunStop: Error {
    case vaultChanged
    case praticaRelocated(from: String, to: String)
}

/// The pratica folder an in-flight run captured, returned only while it is still where
/// that run left it. Throws `.praticaRelocated` otherwise: a run must not keep writing -
/// files or ledger keys - under a path a relocation has vacated. Carries the new path
/// because the caller that must stop is the caller that must ask for a fresh run there.
func praticaPath(continuing captured: String) throws -> String
```

A bare `hasRelocated(_:) -> Bool` is the `assertInsideVault(url)` shape CLAUDE.md's
working agreement forbids. Containment, per ADR-0041's `VaultBoundary.url(for:)`
precedent: in `PraticaLiveSync+Run.swift` rename `RunContext.praticaPath` to a **private**
`capturedPraticaPath` and add the one door

```swift
/// The ONLY way a step in this pipeline obtains the pratica folder it may touch: both
/// facts a step needs, behind one call. Session identity is checked FIRST, because
/// `praticaPathRedirects` describes the live vault only.
func livePraticaPath(in vault: VaultController) throws -> String
```

`RunContext` and its five steps are `private` to that extension, so after the rename
there is no way to spell a pratica path inside the pipeline other than this call. The
guards then land at the point of use automatically rather than being hand-placed, which
is what makes a future sixth `await` safe.

**Prerequisite:** move `controller.beginSync(praticaPath)` / `defer { controller.endSync() }`
from `+Run.swift:50-51` up to immediately after the `guard let controller, let session,
let root` on line 26, so the claim brackets the whole function. The primitive is only
meaningful while a claim is held (`moveLedgerState` records a redirect only for claimed
keys; `pruneRedirectsIfIdle` wipes the map at idle). Behaviour change on the happy path is
nil.

### 2. Where the guards go

All five steps in `PraticaLiveSync+Run.swift` become `throws`; `runExclusive` gets one
`do`/`catch`.

- `runExclusive:59`, right after the detached `prepare` returns and before
  `switch outcome`: the one hand-placed pre-flight guard, so nothing is derived from a
  copy about to be discarded.
- `applyConversationRemap`: resolve at the top, **outside** the existing `do`, so
  `PraticaRunStop` is not swallowed by the catch-all at `:120`.
- `evaluateCandidates`: resolve immediately before `DossierWriter.update`.
- `runEngine`: resolve before building `SyncRequest`, **and again after
  `await engine.sync(...)` returns** — on `.praticaRelocated`, return **without** calling
  `recordSyncOutcome` (see §5). The existing `vault.session === session` guards at
  `:206/:209/:213` stay exactly as they are: a vault switch still records, a relocation
  does not. Do **not** fold the two checks together at this one site; their consequences
  differ and `PraticaLiveSyncRecordOutcomeTests` pins the vault-switch half.
- `refreshTray`: resolve before `dossier(at:)` — this is the guard that closes the
  `persistTrayCount` re-insertion, the worst of the six.

`PraticaLiveSync.swift`, regeneration pair:

- `prepareRegeneration:286-300`: a third guard in the existing ladder, ordered **after**
  `regenerationEngine === engine` (a superseded attempt stays silent) and after
  `vault.session === session`. On relocation: `regeneration = nil`,
  `endRegeneration(praticaPath)` (already resolves), and an Italian sentence telling the
  person to reopen «Rigenera…» from the new position. No auto-retry — it is a per-message
  user action.
- `commitRegeneration:324-330`: refuse **before** the `do`, so nothing is written. `report`,
  `endRegeneration(plan.praticaFolder)`, `return false` — the `false` is what makes
  `PraticaCommandActions.confirmRegeneration` call `files.restore(trashed)`.

### 3. Re-enqueue, so the pratica is still synced

Inside `PraticaLiveSync`, not the controller: `performSync` is a closure, the controller
has no handle on the queue, and `SyncRunQueue` is the single owner of serialization.

- `runExclusive` returns `enum RunOutcome { case finished; case relocated(to: String) }`
  — the "echo the value back, not a bare bit" idiom `SyncRunQueue.request` already uses.
  Its `catch` maps `.praticaRelocated(_, let to)` to `.relocated(to:)` and
  `.vaultChanged` to `.finished`.
- In `run(praticaPath:kind:)`'s loop, on `.relocated(let newPath)` and **before**
  `queue.finished()`: `_ = queue.request(newPath)` (returns `nil` because `isRunning` is
  still `true`, so it lands in `pending` and is never dropped) plus
  `queuedRequests[newPath] = Self.coalesce(queuedRequests[newPath], with: QueuedRequest(session: currentSession, kind: currentKind))`.
  The existing `queue.finished()` dequeues it on the next iteration.
- Extract the decision as a pure static, this file's established idiom
  (`shouldRunQueuedRequest`, `coalescedKind`):
  `nonisolated static func requeue(after: RunOutcome, kind: PraticaWatcher.Trigger) -> (path: String, kind: PraticaWatcher.Trigger)?`
- Reuse `currentKind`, never a hard-coded `.manualRefresh`: that preserves R-17's
  closed-pratica rule (an `.automatic` requeue is revoked at dequeue by
  `shouldRunQueuedRequest` if the pratica closed meanwhile) and keeps a `.manualRefresh`
  sticky through `coalesce`.
- Livelock needs a second user-driven relocation landing inside the new run, so the chain
  is bounded in practice. Say so in the doc comment; add no counter.

### 4. Stop the engine at relocation time

Without this the guard after `await engine.sync(...)` bounds only the *ledger* damage: the
engine keeps writing into the vacated folder for the rest of the run.

- `PraticheController`: `@ObservationIgnored var requestSyncStopForRelocation: (@MainActor () -> Void)?`,
  same shape and justification as the existing `requestSyncCancellation`.
- Wired in `PraticheController.live(vault:)` to a new `PraticaLiveSync.stopForRelocation()`
  whose whole body is `guard let running else { return }; Task { await running.cancel() }`.
  Deliberately **not** `cancel()`, which also does `queue.cancelPending()` +
  `queuedRequests.removeAll()` and would discard queued requests for unrelated pratiche.
- Called from `moveLedgerState`, once, only when `isInFlight(oldPath)` matched via
  `syncingPraticaPath`.

### 5. Discard the partial outcome — the one contested decision

A relocation mid-`engine.sync` leaves some messages written before the move (they
travelled with the folder) and at most one after it (stranded), so the partial
`SyncOutcome` mixes two truths. Recording it would put the stranded message into
`importedMessageIDs` and make it **silently missing forever**. Discarding costs only
re-derivable work: messages already on disk are decoded and skipped by every future sync,
and this run's `bridge` triples / `notInStore` findings are recomputed by the next
successful one. Never a missing message. Record this reasoning in `runEngine`'s doc
comment so a future reader does not "fix" it back.

### 6. Three adjacent defects, independent of this race, included per Stefano's call

- **`applyConversationRemap` write ordering** (`+Run.swift:87-124`). The ledger is
  repointed at `:92`, `pratica.md` written at `:114`. If that write is refused
  (`expecting:` mismatch from a concurrent dossier edit) or throws, the ledger holds the
  new conversation id and the dossier the old one — and
  `MailStorePreparation.resolveFollowedConversations` recovers a renumbering by
  `ledgerEntries.filter { $0.conversationID == conversation }`, which is then empty, so no
  remap is ever recomputed, no recovery, no report. Permanent silent data loss, unrelated
  to relocation. Fix: note write first, `remapLedgerConversations` only on success, no
  ledger touch on any catch path — making the pair all-or-nothing and the failure
  retriable.
- **`PraticaCommandActions.follow`/`ignore`** (`:292-307`) capture `pratiche.selection`
  before `await updateDossier(...)` and use it after. Re-read it **after** the await:
  `selection` is live-remapped by `moveLedgerState`, so a post-await read is exact and
  needs no redirect entry. Also fixes `follow`'s trailing `refreshNow` firing at a path
  that no longer exists. This is CLAUDE.md's "act on state read after the `await`" rule
  applied literally.
- **`load(from:)`** (`+Ledger.swift:55`) rebuilds `ledger` on a vault change without
  clearing `praticaPathRedirects`. No live bug (pruning, plus `livePraticaPath`'s
  session-identity-first ordering), but one line makes the invariant local instead of
  inferred.

### 7. Named residual gap — `PG-168`, not fixed

`PraticaSyncEngine.cancel()` is cooperative, checked once per message, so even with §4 the
message being written at the instant of the move completes into the vacated path,
recreating that directory. What is left: a stray `<oldPath>/email/` (and possibly
`allegati/`) holding a valid message file for a pratica that now lives elsewhere, with no
`pratica.md` beside it — so `dossier(at:)` does not see it as a pratica and nothing in the
app lists or repairs it. `rescan()` indexes the note, so it shows in search as a stray
folder. Not corruption; orphan garbage to delete by hand. The requeued sync re-imports the
message correctly at the new path, so the stranded copy is a duplicate, never a loss.

Second sub-case for the same entry: «Rigenera» refused after a relocation leaves
`PraticaFileOperations.restore` failing, because it uses `moveItem`, which does **not**
create intermediate directories — the trashed note stays in the Trash with a reported
sentence. Worth saying so in Italian at the refusal site, since the files are recoverable
only if the person knows where to look.

Follows the ADR-0043/`PG-152` and ADR-0046/`PG-161` precedent. No new ADR: this is a
review-round finding on the same unmerged branch, folded in the way rounds 2 and 3 were.

## Sequencing

1. `PraticaRunStop` + `praticaPath(continuing:)` + tests 1-3.
2. Move `beginSync`/`defer endSync` to the top of `runExclusive`.
3. `RunContext.capturedPraticaPath` + `livePraticaPath(in:)` + the six call sites +
   `RunOutcome` + tests 4-6.
4. The re-enqueue in `run(praticaPath:kind:)` + the pure static + tests 7-8.
5. `requestSyncStopForRelocation` wired through `live(vault:)`, called from
   `moveLedgerState`.
6. The two regeneration guards + tests 9-10.
7. The three adjacent fixes of §6, each with its own test.
8. `PG-168` in `TODO.md`; a "review round 4" section appended to
   `docs/plans/pg-pratica-ledger-orphaned-by-folder-move.md`, superseding `ba09c06`'s
   "Known gap, not fixed here" paragraph.

## Tests

No test races a relocation against a real sync by timing — the recorded precedent
(`Tests/PraticaLiveSyncRecordOutcomeTests.swift`'s header, ADR-0046 §D2/§D11) forbids it,
and it is unnecessary: "a relocation has happened" is just an entry in
`praticaPathRedirects`, so each test installs it at the seam (`beginSync` /
`beginRegeneration`, then `followFolderRelocations`) and drives production code with the
stale path. Fully deterministic. Style of the existing `PraticaLedgerFolderRelocationTests`
and `PraticaRegenerationSupersededPreviewTests`: `@MainActor @Suite(.serialized)`,
`TemporaryVault`, `VaultController(recents: .volatile(), openTabs: .volatile())`,
`PraticaSyncFixtures`, the shared `waitUntil`.

In `PraticaLedgerFolderRelocationTests`:

1. `praticaPathContinuingReturnsTheCapturedPathWhenNothingRelocated`
2. `praticaPathContinuingRefusesAndNamesWhereThePraticaWent` — including the two-hop chain
3. `praticaPathContinuingIsOnlyMeaningfulWhileARunHoldsItsClaim` — after `endSync()`
   prunes, the resolver returns its input; documents the primitive's scope and locks in
   why the claim must bracket the whole of `runExclusive`

New file `Tests/PraticaLiveSyncRelocatedMidRunTests.swift` (keeps
`PraticheControllerTests.swift` under `file_length`):

4. `aRelocationMidSyncStopsTheRunInsteadOfWritingUnderTheVacatedPath` — the headline.
   `MailStoreFixture` + `MailStoreLocation.overrideKey`, `pratica.md` at both old and new
   paths so the pre-await reads succeed, then `await sync.runExclusive(praticaPath: old)`.
   Assert: no `<old>/email/*.md`; `ledger.byPraticaPath[old] == nil`;
   `ledger.byPraticaPath[new]` untouched; `trayCounts[old] == nil` and
   `trayProposals[old] == nil` (the `persistTrayCount` defect specifically).
5. `aRelocationMidSyncLeavesTheRelocatedLedgerEntryUntouched` — also pins that
   `remapLedgerConversations` is never reached with the stale key.
6. `runExclusiveReportsTheRelocationSoTheNewPathIsSyncedAgain`
7. `requeueAfterRelocationAsksForTheNewPathWithTheSameTriggerKind` — pure static
8. `aRequeuedRelocationRequestQueuesBehindTheAbortingRunInsteadOfBeingDropped` — pure
   `SyncRunQueue`
9. `commitRegenerationRefusesAfterTheRelocationInsteadOfWritingUnderTheVacatedPath` —
   expect `false`, nothing under `<old>`, `regeneratingPraticaPaths.isEmpty` (claim
   released exactly once), `problem != nil`
10. `anAbandonedRegenerationPreviewIsDroppedWhenItsPraticaRelocated` — the one place the
    round-3 `waitUntil` pin is the right tool (`prepareRegeneration` has exactly one
    `await`, claimed on its first line)
11. A no-relocation regression asserting an ordinary end-to-end sync still imports and
    still records — cheapest as an assertion added to an existing `PraticaSync*` test,
    proving the new resolver calls did not break the happy path

For §6: a test that `MailStorePreparation` recomputes **no** remap once the ledger is
repointed but the dossier is not (pure, `MailStoreFixture`, in the style of
`PraticaConversationRenumberingTests`) — this is what makes the write-ordering change
non-negotiable rather than a matter of taste; plus one test each for the
`follow`/`ignore` post-await re-read.

Extend `Tests/PraticaLiveSyncRecordOutcomeTests.swift`'s header comment to record the
consumer-side conclusion about interleaving tests, so a future review round does not
re-litigate it.

## Verification

1. `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test`
   — expect the current 3106 plus the new tests, 0 failures.
2. Full `xcodebuild ... build` (not just the test slice).
3. `swiftlint` — `PraticaLiveSync.swift` is already at the `type_body_length` line per
   `PG-160`, so the two regeneration guards go in without new helpers in that file, and
   the new suite goes in its own test file.
4. A fifth review round on the complete diff.
5. `scripts/uitests.sh` before merging to `main` (repo convention).

## Still pending after this, unchanged

The manual data repair on Stefano's real vault (back up `ledger.json`, remap the orphaned
`01 Progetti/Tifone/Relazioni TIfone` key to `Calendar/01 Progetti/Tifone/Relazioni
TIfone`, delete the two stale keys, trash the `Relazione tecnica Tifone` folder with
explicit confirmation immediately beforehand, then confirm the two reported attachments
resolve) is untouched by this plan and still to be done.
