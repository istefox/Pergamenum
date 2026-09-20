# Fix: the Pratiche ledger is written only over the ledger it was loaded from (PG-172)

SPEC: `SPEC.md` (Approved 2026-09-20). Third of the ledger-integrity chain, after
`docs/plans/pg-pratica-ledger-orphaned-by-folder-move.md` (relocation),
`docs/plans/pg-pratica-relocation-mid-sync-stop.md` (the mid-run half) and
`docs/plans/pg-169-pratica-ledger-forgotten-on-folder-trash.md` (trash) - which is where
PG-172 and PG-173 were filed at `/build` close.

Read out of the worktree `Pergamenum.worktrees/main-2` at `9379990` (only `SPEC.md`
modified). Every line number, call-site list and count below was grepped in that tree.

## ADR outcome — new ADR: `docs/adr/0052-pratiche-ledger-marker-and-one-write-door.md`

Written, `proposed`, accepted when this branch merges. `0051` is the highest file under
`docs/adr/` and `git log --all -- 'docs/adr/0052*'` returns nothing, so the number is free
- checked, not assumed.

Why a new one rather than an amendment, given PG-169's own chain deliberately wrote none:
the three gates hold together here and did not there. The decision is **hard to reverse**
(`ledger` becomes `private(set)` and six writers become closures; going back means
re-opening all six), **surprising without context** (a future reader finds a read-only
`ledger`, a `LedgerOrigin` enum with an `.unreadable` case that refuses to write, and two
sibling comments elsewhere in this repo - `VaultController.pinnedTags:160`,
`PraticheController.ledger:95` - explaining why the opposite trade was taken), and it
rests on **real trade-offs the SPEC itself already weighed** (marker vs. eager hook, one
door vs. a per-writer helper, refusal vs. quarantine, per-path vs. per-claim tombstone).
Two overrides apply on top: it records an explicit **no** a future reader would undo (never
move an unreadable ledger aside), and it changes a **shared file compiled into `perg` and
`pergamenum-mcp`** (`Sources/Core/Pratiche/PraticaLedger.swift`, ADR-0007's constraint), so
the "additive only" reasoning has to be written down somewhere a connector author will look.
Follow-up chains in this repo take their own ADR when they change a mechanism rather than
apply an existing rule - ADR-0043 after ADR-0041, ADR-0046 after ADR-0043 §D8, ADR-0050
after ADR-0043's implementation notes. PG-169 was the other kind: ADR-0026 §D7 already held
its rule, so it amended.

ADR-0052 **extends ADR-0036 §D3** (the ledger file gains a loaded/missing/unreadable
distinction and a write door; format, path and schema untouched) and **amends ADR-0026 §D7
as amended 2026-09-19** (the tombstone's lifetime becomes per-path). Task 7 appends the
one dated bullet to ADR-0026 §D7; no other ADR body is edited.

## Decisions registered from the SPEC (settled, not reopened)

Marker plus lazy load, no eager hook; one door, not a check per writer; an unreadable
ledger file is never saved over and is reported once per file per session, with no
quarantine and no repair UI; the PG-169 `forgetLedgerState` heuristic collapses into the
marker; a change of vault resets the vault-scoped state; a tombstone falls per path. Out of
scope and not re-litigated: the ledger format, `IndexCache.schemaVersion`, the connectors,
the read side, PG-173's first half, PG-168.

## The SPEC's one open question, answered from the code (R-06)

> *«How the per-vault file watchers are stopped when the marker changes, and whether the
> controller already holds the handles to stop them or only drops them.»*

There is nothing to stop. `watchersByPraticaPath: [String: PraticaWatcher]`
(`PraticheController.swift:35`) holds **pure values**: `PraticaWatcher`
(`Sources/Features/Pratiche/PraticaWatcher.swift:15`) is a `struct: Equatable, Sendable`
carrying `lastWindowKeySyncAt`, `pendingFSEventsFireAt` and `lastKnownEligibility` - throttle
and debounce bookkeeping, no descriptor, no `Task`, no stream. `removeAll()` **is** stopping
them, and it is the whole of R-06's «watchers».

The three live resources on the controller are not per vault and must **not** be torn down:

| Member | Declared | Scope | Armed by |
|---|---|---|---|
| `mailStoreEvents: MailStoreEventStream?` | `PraticheController.swift:243` | `MailStoreLocation.resolve()` - Apple Mail's store, unchanged by a vault switch | `startWatching(_:)`, `+Triggers.swift:53-65` |
| `windowKeyObserver` | :244 | one `NSApplication.didBecomeActiveNotification` observer | same, :46-52 |
| `fsEventsFireTask` | :247 | the single FSEvents debounce task | `scheduleFSEventsFire(in:)`, :74-81 |

`startWatching(_:)` is idempotent *and* is called from exactly one place,
`PratichePane.swift:85` (the pane's `.task`). Tearing the three down on a vault change
would leave both automatic triggers disarmed until the person next opened the Pratiche
pane - a regression with no symptom. They stay. The closures capture `vault`, which is the
same `VaultController` instance for the life of the app (`PergamenumApp.init:124`; `open(_:)`
swaps `session` on it, `VaultController.swift:200`, and `close()` nils it, :223), so the
capture never goes stale either.

Recorded in ADR-0052 §D5 as well, because the next reader of that reset will ask again.

## Design

### The defect, as six writers rather than four

`SPEC.md` names four writers plus the trash path. Grepped, `PraticheController+Ledger.swift`
has **six** save sites:

| Writer | Line | Reads | Resolves the URL from |
|---|---|---|---|
| `persistTrayCount` (via `updateTray`) | :88-97 | `self.ledger` | `vault.session` |
| `markOpened` (via `select`) | :185-195 | `self.ledger` | `vault.session` |
| `recordSyncOutcome` | :230-301 | `self.ledger` **or** the file, by `isCurrentVault` | the explicit `session` |
| `moveLedgerState` | :334-383 | `self.ledger` | `vault.session` |
| `forgetLedgerState` | :426-475 | `self.ledger`, re-read when `== .empty` | `vault.session` |
| `remapLedgerConversations` | :655-668 | `self.ledger` | `vault.session` |

**SPEC reconciliation, not scope expansion.** The sixth, `remapLedgerConversations`, is not
mentioned anywhere in `SPEC.md`. It carries the same defect in its vault-switch half (it
mutates vault A's in-memory ledger and saves it under whatever session is live), and R-10
drags it in whether or not it is named: once `ledger` is `private(set)` it cannot compile
without the door. It is covered by R-02 and R-10 and is *not* an additional requirement;
§D7 of ADR-0052 records the one signature change it needs. The SPEC's own wording («each of
the four writers» in R-01/R-02) stays satisfiable as written - the extra writer only adds
coverage. **Recommendation for `/ship`: one line in `SPEC.md` correcting "four writers" to
"six save sites", rather than leaving the discrepancy in an approved document.**

`remapLedgerConversations`'s early guard is also load-bearing and must move: today
`guard !remap.isEmpty, var state = ledger.byPraticaPath[praticaPath] else { return }` reads
the **unloaded** ledger, finds nothing and returns - accidentally harmless in the
never-loaded case and harmful in the vault-switch one. Inside the door's closure it reads
the freshly loaded ledger and does its job.

### The marker, the door and the reset

All three land in `Sources/Features/Pratiche/PraticheController.swift`, beside the property
they guard. This is forced, not chosen: Swift confines a `private(set)` setter to the
declaring file, a stored property cannot live in an extension, and `+Ledger.swift` is a
different file. The repo has hit this wall twice before and taken the other branch -
`VaultController.pinnedTags:160` («Not `private(set)`: the one door onto it, `togglePin`,
is in `VaultController+Files.swift` and cannot write through a private setter from another
file») and `PraticheController.ledger:95` itself. Both comments must be corrected to point
here, or the next reader will "restore" the internal setter. Effective type-body size after
the addition: ~94 code lines today (comments and blanks excluded, measured) plus ~80, well
under SwiftLint's `type_body_length` warning at 250 and error at 350.

```swift
// PraticheController.swift

/// Which ledger file the in-memory `ledger` was read from (ADR-0052 §D1).
enum LedgerOrigin: Equatable, Sendable {
    case none                    // nothing read yet, or no vault open
    case loaded(URL)             // read from this file - decoded, or absent and therefore writable
    case unreadable(URL)         // there and unreadable: `ledger` is empty and nothing is saved over it
    var url: URL? { … }
    var allowsSaving: Bool { … } // false only for `.unreadable`
}

private(set) var ledger: PraticaLedger = .empty
private(set) var ledgerOrigin: LedgerOrigin = .none
/// R-04: one sentence per unreadable file per session, however many writers run.
private var reportedUnreadableLedgers: Set<URL> = []

enum LedgerTarget {
    case live(VaultSession?)     // the vault being shown; nil when none is open
    case stale(VaultSession)     // no longer live: its own file, never `self.ledger`
}
enum LedgerWrite: Equatable { case saved, unchanged, notPersisted, refused, failed }

@discardableResult
func updateLedger(_ target: LedgerTarget, _ change: (inout PraticaLedger) -> Void) -> LedgerWrite
```

`LedgerTarget` takes a `VaultSession?`, never a `VaultController`: `recordSyncOutcome` is
handed a session plus an `isCurrentVault` flag by its caller
(`PraticaLiveSync+Run.swift:315-317`) and holds no controller, and three existing tests
build it with a bare `VaultSession`
(`Tests/PraticaLiveSyncRecordOutcomeTests.swift:80-81,117-118,164`).

The door, in order:

1. `.stale(session)` → resolve the URL, `PraticaLedger.read(from:)`; `.unreadable` reports
   once and returns `.refused`; otherwise apply `change` to what the file holds
   (`.missing` → `.empty`) and save it back. **`self.ledger` and `ledgerOrigin` are never
   touched on this path** - `Tests/PraticaLiveSyncRecordOutcomeTests.swift:151-154` pins
   exactly that.
2. `.live(session)` → `ensureLedgerLoaded(from: session.map(Self.ledgerURL(for:)))`:
   - `ledgerOrigin.url == url` → nothing to do (this includes `.none` with no vault, and
     an `.unreadable` marker that stays refusing until a `load(from:)`);
   - otherwise, if `ledgerOrigin.url != nil` the target names a **different** vault → reset
     the vault-scoped state (below) - going from `.none` to a file is a first load, not a
     vault change, and resets nothing;
   - then adopt: `.loaded(l)` → `ledger = l`, marker `.loaded(url)`; `.missing` →
     `ledger = .empty`, marker `.loaded(url)` (a first write is a creation, R-03);
     `.unreadable` → `ledger = .empty`, marker `.unreadable(url)`, report once. A successful
     read drops the URL from `reportedUnreadableLedgers`, which is what makes R-05 work.
   - `url == nil` (no vault) → `ledger = .empty`, marker `.none`.
3. Refused (`!ledgerOrigin.allowsSaving`): apply `change` **in memory** so the session stays
   coherent, save nothing, return `.refused`.
4. Otherwise: `var copy = ledger; change(&copy)`; `guard copy != ledger else { return .unchanged }`;
   `ledger = copy`; no URL → `.notPersisted`; else `try copy.save(to: url)` → `.saved`, or
   report through the existing `problem` sentence and return `.failed`.

**The closure is applied to a local copy, never to `&self.ledger`.** Two writers mutate
other `self` properties from inside it (`forgetLedgerState` and `moveLedgerState` pass
`&forgottenPraticaPaths` / `&praticaPathRedirects` to `removeKeys`/`remapKeys`), and a
closure touching `self` while `self.ledger` is held `inout` is an exclusivity trap. The copy
is also what makes step 4's before/after comparison possible.

That comparison replaces two hand-written conditional saves and preserves both:
`persistTrayCount`'s «skipped when nothing changed, so a pratica with no tray and no ledger
entry does not get one created to say zero» (the closure returns without mutating) and
`forgetLedgerState`'s `removedLedgerKey` guard - which is what keeps
`Tests/PraticaLedgerFolderTrashTests.swift:291-320`
(`trashingAnUnrelatedFolderBeforeTheLedgerIsLoadedLeavesTheFileUntouched`) byte-identical.

### The reset, and what it deliberately leaves alone

```swift
private func resetVaultScopedState() {
    pratiche = []; trayProposals = [:]; trayCounts = [:]; watchersByPraticaPath = [:]
    selection = nil; selectedEntryID = nil; expansion = PraticaTimelineModel.ExpansionState()
    timeline = []; details = [:]; links = .empty
}
```

Not cleared, on purpose (ADR-0052 §D5): `praticaPathRedirects` and `forgottenPraticaPaths`
(owned by an in-flight run; `endSync`/`endRegeneration` release them, and a writer reaches
the marker-mismatch path *during* a run - `Tests/PraticaLiveSyncTrashedMidRunTests.swift:442`
pins the same rule for `load(from:)`), `syncingPraticaPath`, `regeneratingPraticaPaths`,
`regeneration`, `problem`, `fullDiskAccessState`, and the three live streams above.

`selection` is cleared by assignment, never through `select(nil, in:)` - that call marks a
pratica opened, rebuilds the list and reloads the timeline, all against the vault being left.

### Ordering: the door first, its siblings after

Three writers touch the ledger *and* sibling dictionaries in one pass, and the door can now
reset those dictionaries. The door is called **first** in each; the siblings follow.

- `updateTray` (:66-75): today `trayProposals[path] = …; trayCounts[path] = …` then
  `persistTrayCount`. Reversed: `persistTrayCount` (the door) first, then the two
  assignments, then the `listItems` rebuild. `persistTrayCount` reads only `count`, so
  nothing is lost by the move - but the old order silently drops the proposals a sync just
  computed the first time the marker mismatches.
- `moveLedgerState` (:334-383): the ledger remap goes inside the closure; the three other
  `remapKeys` calls, the `selection`/`syncingPraticaPath`/`regeneratingPraticaPaths` remaps
  and `requestSyncStopForVanishedPath?()` follow it. The trailing `try ledger.save` is
  deleted. `isInFlight` is still snapshotted before anything moves.
- `forgetLedgerState` (:426-475): the ledger `removeKeys` goes inside the closure (still
  passing `&forgottenPraticaPaths`), the other three and the `select(nil, in:)` follow.
  The `if ledger == .empty { reload }` block (:436-442) and the `removedLedgerKey` guard
  are deleted.

### The tombstone, per path (R-07, R-08)

```swift
func endSync() {
    let released = syncingPraticaPath
    syncingPraticaPath = nil; syncProgress = nil
    if let released { dropTombstoneIfUnclaimed(released) }
    pruneRedirectsIfIdle()
}

func endRegeneration(_ praticaPath: String) {
    let released: String
    switch destination(of: praticaPath) {
    case .same: released = praticaPath
    case .moved(let c), .forgotten(let c): released = c
    }
    regeneratingPraticaPaths.remove(released)
    dropTombstoneIfUnclaimed(released)
    if released != praticaPath { dropTombstoneIfUnclaimed(praticaPath) }
    pruneRedirectsIfIdle()
}

/// A tombstone outlives its own run only while something still claims THAT path; a claim on
/// another path is not its business (ADR-0052 §D6).
private func dropTombstoneIfUnclaimed(_ path: String) {
    guard path != syncingPraticaPath, !regeneratingPraticaPaths.contains(path) else { return }
    forgottenPraticaPaths.remove(path)
}
```

`pruneRedirectsIfIdle` is unchanged and still clears both collections when nothing at all is
in flight: it is a superset of the per-path drop, and `praticaPathRedirects` genuinely cannot
be pruned entry by entry (a chain can be shared by two claimants - review round 2's MINOR 2,
:547-554). `Tests/PraticaLiveSyncTrashedMidRunTests.swift:426`
(`theTombstoneIsDroppedWhenTheRunEndsSoARecreatedPraticaIsNotRefused`) stays green through
either route.

### How tests seed, now that there is no setter (R-09's mechanics)

- **A test that drives a writer against a real session seeds on disk.** Build a local
  `PraticaLedger`, `save(to: PraticheController.ledgerURL(for: session))`, then either let
  the door read it or call `load(from: vaultController)`. An in-memory seed is now discarded
  by the door's own read - which is the fix working, not a test problem.
- **A test with no session seeds through the door**:
  `controller.updateLedger(.live(nil)) { $0.byPraticaPath["01 Progetti/Tifone/X"] = state }`.
  Marker `.none`, target `nil`, equal → no read, no reset, memory only, returns
  `.notPersisted`. One mechanical line per site.

No `#if DEBUG` hatch, no test-only setter: the seam is the production door, which is what
keeps R-10 true.

---

## Tasks

### Task 1 — `PraticaLedger` tells «missing» from «unreadable» (R-04, R-05)

Declarations the tester writes first, so the target builds and the tests are red rather
than uncompilable: `PraticaLedger.Read` and `static func read(from:) -> Read`.

- `Sources/Core/Pratiche/PraticaLedger.swift` (148 lines) — the nested
  `enum Read: Equatable, Sendable { case loaded(PraticaLedger), missing, unreadable }` and
  `static func read(from url: URL) -> Read`. `missing` is `Data(contentsOf:)` throwing
  `CocoaError` `.fileReadNoSuchFile` / `.fileNoSuchFile`; **any other throw** (permissions,
  a directory at the path, an unreadable volume) and **any decode failure** are
  `unreadable`. `load(from:)` keeps its exact signature and answer, expressed through
  `read(from:)`. Foundation only - this file is in `sharedSources` (`Project.swift:88`) and
  compiles into `perg` and `pergamenum-mcp`.
  - Verify the `CocoaError` codes by running the test, not from memory: the classification
    is the whole decision, and a missing file mis-classified as `.unreadable` would refuse
    every first write (R-03).
- `Tests/PraticaLedgerTests.swift` (97 lines, room to spare) — beside
  `PraticaLedgerNotInStoreTests`:
  - `aMissingLedgerFileReadsAsMissing` — a URL in an empty temporary directory (R-03's
    precondition, and the classification R-04 depends on).
  - `aLedgerWrittenByThisBuildReadsAsLoaded` — round trip through `save(to:)`.
  - `CorruptJSONReadsAsUnreadable` — `Data("{ not json".utf8)` written at the URL.
  - `anEmptyFileReadsAsUnreadable` — zero bytes; `.empty` is not what an empty file means.
  - `aLegacyLedgerWithNoNotInStoreKeyStillReadsAsLoaded` — the lenient `PraticaState`
    decoder is what makes a *format* addition survive; only a genuinely undecodable file is
    `.unreadable` (guards against over-refusing, R-05's other side).
  - `loadStillAnswersEmptyForMissingAndForUnreadable` — the connector-facing signature is
    unchanged.

### Task 2 — The marker, the one door, and the reset (R-01, R-02, R-03, R-06, R-10)

Declarations the tester writes first: `PraticheController.LedgerOrigin`, `LedgerTarget`,
`LedgerWrite`, `private(set) var ledger`, `private(set) var ledgerOrigin`, and
`func updateLedger(_:_:) -> LedgerWrite`. Nothing else compiles until these exist.

- `Sources/Features/Pratiche/PraticheController.swift` — the two enums, the two
  `private(set)` properties, `reportedUnreadableLedgers`, `updateLedger(_:_:)`, and the
  private `ensureLedgerLoaded(from:)`, `adoptLedger(from:)`, `reportUnreadableLedger(_:)`,
  `resetVaultScopedState()` (Design, above). `reloadLedger(for:)` is `internal` so
  `load(from:)` in `+Ledger.swift` can call it (Task 4).
  - The doc comment on `ledger` (:95-99, «Not `private(set)`, on this property and every
    other one down to `ledger` below») is now wrong for `ledger` itself: correct it and
    point at ADR-0052 §D2 for why the door lives in this file rather than beside the rest of
    the ledger code.
  - The Italian refusal sentence names the file and is reported once per file per session:
    `"Il registro delle pratiche non è leggibile e non verrà sovrascritto: <path>. Ripara o elimina il file."`
    It must contain the substring `registro delle pratiche` - an existing assertion reads
    it (`Tests/PraticaLedgerFolderTrashEdgeTests.swift:179`).
- `Tests/PraticheLedgerDoorTests.swift` **(new file)** — `@MainActor @Suite(.serialized)`,
  a new file rather than an addition to `Tests/PraticheControllerTests.swift`, which is at
  968 lines against SwiftLint's `file_length` **error** at 1000 (ADR-0045's precedent, and
  PG-169's own Task 2 note):
  - `aWriterOnANeverLoadedControllerReadsTheFileFirstAndKeepsEveryOtherPratica` — seed two
    pratiche on disk, never call `load(from:)`, run the door once; assert both survive and
    only the intended field differs (R-01).
  - `aWriterForAnotherVaultLeavesTheFirstVaultsFileByteIdentical` — two `TemporaryVault`s,
    two `VaultSession`s, `.live(A)` then `.live(B)`; `Data(contentsOf:)` before/after on A
    (R-02).
  - `aWriterForAnotherVaultResetsTheVaultScopedState` — seed `trayCounts`, `trayProposals`,
    `watchersByPraticaPath`, `selection`, `timeline`, `details` for A, then a `.live(B)`
    write; assert all empty and `pratiche` holds no A entry (R-06).
  - `aClosedVaultClearsTheSameSet` — `.live(nil)` after `.live(A)` (R-06).
  - `aFirstWriteWithNoLedgerFileSavesRatherThanRefusing` — no file at all; assert `.saved`
    and a file on disk (R-03).
  - `anUnreadableLedgerIsNeverWrittenAndIsReportedOnce` — corrupt bytes at the URL, four
    door calls; bytes identical before/after, `problem` names the file, and after clearing
    `problem` by hand the remaining calls leave it `nil` (R-04).
  - `aRepairedLedgerSavesAgainAfterTheNextLoad` — repair the file, `reloadLedger(for:)`,
    write, assert `.saved` (R-05).
  - `aStaleSessionWriteNeverTouchesTheLiveLedgerOrItsMarker` — `.stale(B)` after `.live(A)`;
    `ledger` and `ledgerOrigin` unchanged, B's file written (R-02).
  - `theLedgerHasNoSetterOutsideItsOwnFile` — **no test**; R-10 is enforced by the compiler
    and verified by the build plus a read of the diff. Recorded here so the absence is
    deliberate rather than forgotten.

### Task 3 — All six writers move onto the door (R-01, R-02, R-03, R-04)

Declarations the tester writes first: `remapLedgerConversations(_:of:session:isCurrentVault:)`
(the one signature change), since its call site will not compile otherwise.

- `Sources/Features/Pratiche/PraticheController+Ledger.swift` — rewrite each writer as a
  closure through `updateLedger`, in this order, with the sibling-state ordering from the
  Design section:
  - `persistTrayCount` → `.live(vault.session)`, keeping the `guard state.trayCount != count`
    inside the closure; `updateTray` reordered so the door runs before the two dictionary
    assignments.
  - `markOpened` → `.live(vault.session)`.
  - `recordSyncOutcome` → the `.forgotten` early return and the `destination(of:)`
    resolution stay exactly where they are, *before* the door; then
    `updateLedger(isCurrentVault ? .live(session) : .stale(session))`. The
    `ledger = sessionLedger` assignment and both `try … save` blocks are deleted; the
    `attachmentProblems` composition stays outside, still gated on `isCurrentVault`.
  - `moveLedgerState` → ledger remap inside the closure, the rest after, trailing save
    deleted.
  - `forgetLedgerState` → the `ledger == .empty` reload heuristic (:436-442) and the
    `removedLedgerKey` guard deleted; ledger `removeKeys` inside the closure.
  - `remapLedgerConversations` → new signature; the `var state = ledger.byPraticaPath[…]`
    guard moves inside the closure (the `!remap.isEmpty` guard can stay outside).
- `Sources/Features/Pratiche/PraticaLiveSync+Run.swift:200` — the one call site:
  `session: context.session, isCurrentVault: vault.session === context.session`, matching
  `recordSyncOutcome`'s own call four lines of reasoning above it (:315-317).
- `Tests/PraticheLedgerDoorTests.swift` — one behavioural test per writer on a never-loaded
  controller, all four named by R-01 plus the two the SPEC does not name:
  `trayCountOnANeverLoadedControllerKeepsEveryOtherPratica`,
  `openedStampOnANeverLoadedControllerKeepsEveryOtherPratica`,
  `folderMoveOnANeverLoadedControllerKeepsEveryOtherPratica`,
  `syncOutcomeOnANeverLoadedControllerKeepsEveryOtherPratica`,
  `trashOnANeverLoadedControllerKeepsEveryOtherPratica`,
  `conversationRemapOnANeverLoadedControllerKeepsEveryOtherPratica` (R-01), plus
  `conversationRemapForAStaleSessionWritesItsOwnFile` (R-02).

### Task 4 — `load(from:)` goes through the same loader (R-06)

- `Sources/Features/Pratiche/PraticheController+Ledger.swift` — `load(from:)` (:112-145):
  - the session branch calls `reloadLedger(for: session)` (which always re-reads, and resets
    only when the marker named a *different* file) instead of assigning
    `ledger = PraticaLedger.load(…)`;
  - the no-session branch keeps its existing clears (`praticaPathRedirects`,
    `forgottenPraticaPaths`, and the comment at :122-131 explaining why they are cleared
    *here* and nowhere else) and adds `resetVaultScopedState()` so the tray state and the
    watchers go with them - today they survive a vault close.
  - the `listItems` rebuild, the selection check and `reloadTimeline` stay as they are.
- `Tests/PraticheLedgerDoorTests.swift`:
  - `loadingVaultBAfterVaultAClearsTrayWatchersSelectionTimelineAndDetails` — R-06 through
    the loader rather than the door.
  - `loadingTheSameVaultAgainKeepsTheTrayStateAndTheWatchers` — the trap this ordering
    exists to avoid: `load(from:)` runs after *every* pratica command
    (`PraticaCommandActions.swift:98,111,128`), and resetting there would wipe the tray on
    every rename (R-06).
  - `closingTheVaultClearsTheSameSet` (R-06).

### Task 5 — A tombstone falls per path (R-07, R-08)

Declarations the tester writes first: none - `dropTombstoneIfUnclaimed` is private and
`endSync`/`endRegeneration` keep their signatures.

- `Sources/Features/Pratiche/PraticheController+Ledger.swift` — `endSync` (:209-213),
  `endRegeneration` (:611-617) and the new private `dropTombstoneIfUnclaimed(_:)` beside
  `pruneRedirectsIfIdle` (:641-645), which is left exactly as it is.
- `Tests/PraticaLiveSyncTrashedMidRunTests.swift` (466 lines; the per-path rule belongs
  beside the all-or-nothing one it narrows) — beside
  `theTombstoneIsDroppedWhenTheRunEndsSoARecreatedPraticaIsNotRefused` (:426):
  - `endingXsSyncDropsXsTombstoneWhileAnotherPraticasClaimIsStillOpen` — `beginSync(X)`,
    `beginRegeneration(Y)`, trash X, `endSync()`; assert X's tombstone gone, Y's claim still
    open, and `praticaPath(continuing: X)` no longer throwing (R-07).
  - `aClaimStillOpenOnXKeepsXsTombstone` — `beginSync(X)` **and** `beginRegeneration(X)`,
    trash X, `endSync()`; assert the tombstone stays and `recordSyncOutcome` for X still
    writes nothing (R-08 - PG-169's behaviour, unchanged).
  - `endingARegenerationDropsOnlyItsOwnTombstone` — the regeneration twin, including the
    relocated-then-trashed chain (`destination(of:)` resolving to `.forgotten(current)`).

### Task 6 — Re-seed the existing suites; no assertion loosened (R-09, R-04)

37 lines across five test files assign the controller's ledger directly and stop compiling
(grep-verified counts): `PraticaLedgerFolderTrashTests` 14, `PraticheControllerTests` 11,
`PraticaLedgerFolderTrashEdgeTests` 7, `PraticaLiveSyncTrashedMidRunTests` 3,
`PraticaLiveSyncRelocatedMidRunTests` 2. Five more lines call
`try pratiche.ledger.save(to:)` (still legal, but part of the same seeding rewrite):
`PraticaLedgerFolderTrashTests:151,183,269`, `PraticaLedgerFolderTrashEdgeTests:104,143`.

- Each site moves onto the seam its own test needs (Design, «How tests seed»): the disk
  seam where a session exists, `updateLedger(.live(nil))` where none does. **No assertion
  text, expectation or message changes** - this is a setup rewrite and nothing else.
- `Tests/PraticaLedgerFolderTrashEdgeTests.swift:162-187`
  (`aLedgerThatCannotBeSavedIsReportedAndStillForgottenInMemory`) is the **one** test whose
  *arrangement* must change for a reason beyond the seam, and its four assertions stay
  verbatim. It forces a save failure by creating a **directory** at the ledger's URL, which
  Task 1 now classifies one step earlier as `.unreadable` - so the door refuses before
  attempting the save and the test would be asserting a path it no longer takes. Re-arrange:
  write a real, readable `ledger.json` holding both keys, then `chmod 0o500` on
  `PraticheController.stateDirectory(for: session)` (`FileManager.setAttributes(
  [.posixPermissions: 0o500], ofItemAtPath:)`), with a `defer` restoring `0o700` so the
  temporary directory can still be removed. Read of a known file name through an `r-x`
  directory succeeds; `createDirectory(withIntermediateDirectories: true)` on the existing
  directory is a successful no-op; the atomic write's temp-file creation inside it fails →
  the save throws → `problem` reports it and the memory is still cleaned. Verify the
  permission behaviour by running it, do not assume it.
- Add, in the same file, the case the old arrangement now describes:
  `aDirectoryAtTheLedgersOwnURLIsRefusedRatherThanSavedOver` — the trash path leaves it
  untouched and reports once (R-04).
- `Tests/PraticheConnectorTests.swift` and every `PraticaLedger.load(from:)` call site
  (1 production + 15 test) are untouched: the signature and the answer are unchanged.

### Task 7 — Documentation, bookkeeping, and the whole suite green (R-09, R-10)

- `docs/adr/0026-drag-and-drop-board-files-into-workspace.md` §D7 — one dated bullet
  (**Amended 2026-09-20**): the tombstone falls per path when no claim on *that* path
  remains, superseding «cleared in one go by `pruneRedirectsIfIdle`»; pointer to ADR-0052
  §D6. Nothing else in that ADR is edited.
- `docs/adr/0052-pratiche-ledger-marker-and-one-write-door.md` — status `proposed` →
  `accepted` when the branch merges (at `/ship`, not before).
- `CLAUDE.md` — one bullet under «Working agreements», in the shape of the two that are
  already there: *a ledger, cache or registry the app holds in memory and saves back must
  record which file it was read from; a writer that cannot prove it is writing over the file
  it loaded reads first, and never saves over a file it could not read* (ADR-0052 §D1/§D3).
  The «Chain decision index» gains its ADR-0052 line.
- `Sources/App/VaultController.swift:160` — correct the `pinnedTags` comment's claim that a
  cross-file door forces an internal setter, pointing at ADR-0052 §D2 for the other
  resolution. One sentence; the property itself is **not** changed (out of scope).
- Build all three targets (`Pergamenum`, `perg`, `pergamenum-mcp`) - the two tool targets
  are how ADR-0007's constraint is actually checked (R-09).
- `swiftlint` clean on the touched files; `.claude/test-cmd` green with nothing disabled,
  skipped or deleted (R-09, R-10).
- `scripts/uitests.sh --status` first, then a run if this tree is not already verified -
  before the merge to `main`, per CLAUDE.md. Nothing here touches a view, so `--affected`
  is expected to select little or nothing; ask `--status` rather than assume.
- `TODO.md` at `/ship`: close `PG-172` (#312), and close `PG-173`'s second half while
  leaving its first half open with a note that it is untouched here.

---

## Call sites of every contract this touches (grep-verified, so nobody discovers them late)

- **`PraticheController.ledger` assignment (the contract that changes).** Production: only
  `PraticheController+Ledger.swift:118,136,291,440,441`, all rewritten by Tasks 3 and 4.
  Tests: 37 lines in the five files listed in Task 6. **Reads** stay legal and are untouched:
  `PraticaLiveSync+Run.swift:72`, `PraticaLiveSync.swift:311`, `AddToPraticaSheet.swift:136`,
  `PraticheController+Ledger.swift` (`listItems`/`reloadTimeline`), plus every `#expect` in
  the suites.
- **`PraticaLedger.load(from:)`** — signature and answer unchanged, so nothing has to move:
  `Sources/Connector/VaultPratiche.swift:33` (both connector targets),
  `PraticheController+Ledger.swift:136,257,441` (rewritten for other reasons), and 15 test
  assertions across `PraticaLedgerFolderTrashTests`, `PraticaLedgerFolderTrashEdgeTests`,
  `PraticaLiveSyncTrashedMidRunTests`, `PraticaLiveSyncRecordOutcomeTests`,
  `PraticheControllerTests`.
- **`remapLedgerConversations` (the one signature change).** Production caller:
  `PraticaLiveSync+Run.swift:200`, and nothing else. No test references it by name.
- **`recordSyncOutcome`** — signature unchanged; callers `PraticaLiveSync+Run.swift:315`
  and `PraticaLiveSync.swift:425`. Tests asserting its behaviour, all of which must stay
  green: `PraticaLiveSyncRecordOutcomeTests.swift:94,126,138,173`,
  `PraticheControllerTests.swift:195,213,232,616,682,698`,
  `PraticaLiveSyncTrashedMidRunTests.swift:143-201`.
- **`endSync` / `endRegeneration`** — signatures unchanged. Production: `endSync` at
  `PraticaLiveSync+Run.swift:92` (a `defer`); `endRegeneration` at
  `PraticaLiveSync.swift:308,326,351,367,379,383,396,415,428,436` and
  `PraticaCommandActions.swift:276`. Tests reading `forgottenPraticaPaths` after either:
  `PraticaLiveSyncTrashedMidRunTests.swift:234,292,374,415-421,434,452,460`,
  `PraticaLiveSyncRecordOutcomeTests.swift:171`,
  `PraticaLedgerFolderTrashEdgeTests.swift:122`.
- **`updateTray`** — production caller `PraticaLiveSync+Run.swift:350` (reached only after
  `livePraticaPath(in:)` has proved the vault unchanged, so its `.live(vault.session)`
  target is always the run's own vault); `dismissTrayProposal` (:102-105) is the other.
- **`load(from:)`** — `PratichePane.swift:84`, `PraticheSettingsTab.swift:265,275`,
  `AddToPraticaSheet.swift:58`, `NuovaPraticaWizard+Actions.swift:182`,
  `PraticaCommandActions.swift:98,111,128`, `+Triggers.swift:111,121,128`. None changes; all
  of them now inherit the marker.

**Full suite, not just the touched modules.** `ledger`'s visibility and `load(from:)`'s
internals are a shared contract: run `.claude/test-cmd` over all of `PergamenumTests`, never
a `-only-testing:` on the pratiche suites alone.

## Risks, residuals and HITL gates

- **HITL — commit, push, merge.** Human decision, as always. `scripts/uitests.sh --status`
  before the merge to `main`, and a run if the tree is not already verified.
- **No externally provisioned resource.** No network, no new dependency, no env var, no
  port, no console, no consent flow. `IndexCache.schemaVersion` stays 4, the ledger file
  format is unchanged, and no migration exists to run.
- **Destructive-adjacent by nature.** The whole chain is about *not* overwriting a file; the
  new failure mode to watch for is the opposite one - refusing to write a ledger that is
  actually fine. Task 1's `missing` vs `unreadable` classification is the single point where
  that could go wrong, which is why it gets six tests of its own and why the `CocoaError`
  codes must be confirmed by running them.
- **A refused write is still applied in memory** (ADR-0052 §D3). Deliberate: a badge goes
  out, a tray count shows, and nothing becomes durable. It does mean `ledger` can differ
  from the (unreadable) file for the session - already true today after any failed save.
- **`forgetLedgerState` now reads the ledger file on the first folder trashed in a session,
  even when no pratica is involved.** One JSON read on a path whose own documentation calls
  a full reload «cheap enough to call from the pane's `.task`». Accepted.
- **A relocation that moves no ledger key no longer rewrites the file** (the before/after
  comparison). Strictly better, and no existing assertion depends on the write happening -
  `moveLedgerStatePersistsToDisk` (`PraticheControllerTests.swift:498`) moves a real key.
  Worth re-reading the diff for, since it is a silent behaviour change.
- **`PG-168`'s cooperative-cancel window is untouched.** A message being written at the
  instant of a move or trash can still land in the vacated folder. Unchanged by this chain.
- **PG-173's first half stays open** (a queued sync for a trashed pratica reporting «non ha
  un dossier leggibile»). It needs `SyncRunQueue`'s private state and a different mechanism;
  the SPEC excludes it and this plan does not touch it.
- **The marker compares `URL`s.** Both sides are built by `PraticheController.ledgerURL(for:)`
  from the same `session.state.directory`, so equality is stable. A future caller that
  standardises or resolves symlinks on one side only would silently make every write look
  like a vault change. One sentence of doc comment on `LedgerOrigin.url` is the whole
  mitigation, and it is worth writing.
- **My own assessment of scope:** the sixth writer and the `VaultController.pinnedTags`
  comment correction are additions to the SPEC's stated surface. Both are forced - the first
  by R-10's `private(set)`, the second because the comment tells the next reader to undo the
  design. Neither adds a requirement. The one genuine SPEC edit I recommend, and do not make
  here, is correcting «four writers» to «six save sites» in `SPEC.md`'s Objectives.

## TEST-CMD

`TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test`

`TEST-CMD MODE: brownfield` — the line is `.claude/test-cmd` verbatim. The suite exists and
runs today; the SPEC's seam is entirely inside `PergamenumTests`; and the
`-only-testing:PergamenumTests` restriction is load-bearing rather than tidy (CLAUDE.md:
the `Stop` hook runs this at the end of every turn, and letting the UI suite in there
terminated the app the person was using and left instances holding the global hot key).
Kept unchanged. The UI suite runs separately, through `scripts/uitests.sh`, before the merge.
