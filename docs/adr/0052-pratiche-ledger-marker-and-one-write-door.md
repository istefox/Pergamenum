# ADR-0052: The Pratiche ledger is written only over the ledger it was loaded from

- Status: accepted, with the branch implementing `SPEC.md` (Approved 2026-09-20, PG-172)
  merging to `main`.
- Date: 2026-09-20. Written on the worktree `Pergamenum.worktrees/main-2` at `9379990`
  (only `SPEC.md` modified). Every signature, line reference and call-site count below was
  read out of that tree, not recalled.
- **Numbering note:** `0051` is the highest file under `docs/adr/`, and
  `git log --all -- 'docs/adr/0052*'` returns nothing, so no `0052` exists in any commit
  reachable from any ref. Checked, not assumed.
- Source: `TODO.md` **`PG-172`** → issue **#312** (P2, correctness), filed by the PG-169
  chain at its own `/build` close, which fixed the same defect in `forgetLedgerState`
  alone and recorded that closing it properly «means a «ledger loaded for URL X» marker, a
  design decision, not a per-call guard». This is that decision. It also closes the second
  half of **`PG-173`** (P3), the tombstone that outlives its own claim.
- **Extends ADR-0036 §D3 (the ledger file) and amends ADR-0026 §D7 as amended 2026-09-19
  (the tombstone's lifetime).** The ledger's on-disk format, its path, its schema and what
  `VaultAPI.pratiche(_:)` reads out of it are untouched; what changes is who may write it
  and when. The tombstone keeps its meaning - a claim on a trashed path is stale and is
  refused - and loses only its all-or-nothing lifetime.
- **Reopens nothing else.** No SPEC §14 decision, no on-disk format, no frontmatter key,
  no `IndexCache.schemaVersion` bump (stays 4), no protected-interface signature
  (`PraticaNaming.messageFileName`, `Dossier.render`, `VaultAPI.PraticaSummary`,
  `MessageDocument.isPendingAttachmentEntry` are all untouched), no MCP tool surface, no
  CLI flag. No test is disabled, skipped or deleted.
- **Adds no exception to CLAUDE.md principle 2.** Nothing here gains a network path.

---

## Context

### The defect, read out of the code rather than off the ticket

`PraticheController.ledger` (`Sources/Features/Pratiche/PraticheController.swift:123`)
starts as `.empty` and is filled by exactly one function, `load(from:)`
(`PraticheController+Ledger.swift:112-145`). That function is called from the Pratiche
pane's `.task` (`PratichePane.swift:84`), the settings tab
(`PraticheSettingsTab.swift:265,275`), `AddToPraticaSheet.swift:58`,
`NuovaPraticaWizard+Actions.swift:182` and after every pratica command
(`PraticaCommandActions.swift:98,111,128`). **The app never calls it at launch**, and
`PergamenumApp.init` builds the controller with `PraticheController.live(vault:)` without
opening anything.

Six functions in `PraticheController+Ledger.swift` mutate that property and save it
straight back:

| Writer | Line | Save |
|---|---|---|
| `persistTrayCount` (behind `updateTray`) | :88-97 | `ledger.save(to: ledgerURL(for: session))` |
| `markOpened` (behind `select`) | :185-195 | same |
| `recordSyncOutcome` | :230-301 | `sessionLedger.save(to: url)` |
| `moveLedgerState` | :334-383 | same as the first two |
| `forgetLedgerState` | :426-475 | same, guarded by `removedLedgerKey` |
| `remapLedgerConversations` | :655-668 | same |

Five of the six read `self.ledger`, mutate it and write the result over
`…/vaults/<id>/pratiche/ledger.json`. Two consequences, neither hypothetical:

1. **Never loaded.** `VaultController.didRelocateFolders` and `didTrashFolder` are wired
   app-wide (`PergamenumApp.init:126-133`) and fire for *any* folder moved or trashed
   through the note list or the Workspace browser. A person who renames a folder, or whose
   first sync completes, before ever opening the Pratiche pane gets the `.empty` starting
   value written over the real file - losing every pratica's `importedMessageIDs`, bridge
   `entries`, `notInStore`, `lastOpenedAt` and `trayCount`. None of those is derivable from
   the folder on disk; `notInStore` and the §D3 bridge are not derivable at all.
2. **Loaded for another vault.** `VaultController.open(_:)` swaps `session` on the same
   `VaultController` instance (`VaultController.swift:200`) and `close()` sets it to `nil`
   (:223); the `PraticheController` and every path-keyed dictionary on it survive the
   switch untouched. A writer that resolves its URL from the *live* session while holding
   vault A's in-memory ledger writes A's entries into B's file. `recordSyncOutcome` is the
   only writer that already defends against this, through an `isCurrentVault` flag its
   caller computes (`PraticaLiveSync+Run.swift:315-317`); the other five do not.

`forgetLedgerState` carries a partial fix from the PG-169 chain (:436-442): *if the
in-memory ledger is `.empty`, read the file first*. It is a heuristic - a genuinely empty
ledger is indistinguishable from an unloaded one - it covers exactly one of six writers,
and it does nothing about the vault-switch variant.

### Two neighbours that share the cause or the hook

- **Vault-scoped state that never resets.** Only the no-session branch of `load(from:)`
  clears anything, and it clears `pratiche`, `timeline`, `details`, `links`, `ledger`, the
  redirect map and the tombstone set - not `trayCounts`, not `trayProposals`, not
  `watchersByPraticaPath`. A pratica path that exists in two vaults (`01 Progetti/Tifone`
  is not an unusual name) inherits vault A's badge, A's tray proposals and A's
  window-key/FSEvents throttle marks.
- **A tombstone outlives its own claim.** `forgottenPraticaPaths` is cleared only by
  `pruneRedirectsIfIdle` (:641-645), which requires `syncingPraticaPath == nil` **and**
  `regeneratingPraticaPaths.isEmpty`. An open «Rigenera…» sheet on an unrelated pratica
  therefore keeps the tombstone of a *different*, recreated pratica alive, and
  `praticaPath(continuing:)` refuses that healthy pratica's sync with `.praticaTrashed`.
  That is PG-173's second half.

### What «per-vault file watcher» turned out to mean (the SPEC's one open question)

`SPEC.md` left one thing for this document to settle by reading the code: how the
per-vault file watchers are stopped when the marker changes, and whether the controller
holds handles or only drops them. Read out of `PraticheController.swift:35`,
`PraticaWatcher.swift` and `PraticheController+Triggers.swift`:

- `watchersByPraticaPath: [String: PraticaWatcher]` holds **pure values**. `PraticaWatcher`
  is a `struct: Equatable, Sendable` carrying `lastWindowKeySyncAt`,
  `pendingFSEventsFireAt` and `lastKnownEligibility`: throttle and debounce bookkeeping,
  no file descriptor, no `Task`, no FSEvents stream, nothing to stop. Dropping the entry
  *is* stopping it.
- The three live resources on the controller are **not** per vault:
  `mailStoreEvents: MailStoreEventStream?` watches `MailStoreLocation.resolve()` - Apple
  Mail's own store, which does not change when the vault does; `windowKeyObserver` is one
  `NSApplication.didBecomeActiveNotification` observer; `fsEventsFireTask` is the single
  debounce task. All three are armed once by `startWatching(_:)`, which is idempotent and
  is called only from `PratichePane`'s `.task` - so tearing them down on a vault change
  would silently disarm both automatic triggers until the person next opened the pane.

So R-06's «watchers» is satisfied by `watchersByPraticaPath.removeAll()` and by nothing
else, and the three streams are deliberately left running. Recorded here because the
question will be asked again by the next reader of that reset.

---

## Decision

### §D1 - The marker: one value that says which file the memory came from

`PraticheController` gains one piece of state beside `ledger`:

```swift
enum LedgerOrigin: Equatable, Sendable {
    case none                 // nothing read yet, or no vault open
    case loaded(URL)          // read from this file - decoded, or absent and therefore writable
    case unreadable(URL)      // this file is there and could not be read: never written over
}
private(set) var ledger: PraticaLedger = .empty
private(set) var ledgerOrigin: LedgerOrigin = .none
```

One enum, not a `URL?` beside an `isWritable: Bool` - ADR-0024 §D2's rule (two variables
that can disagree become one that cannot), applied again.

A writer resolves its target URL from the session it is writing for and compares it with
`ledgerOrigin.url`. Equal: the memory already describes that file, mutate it. Different -
including `.none`, which is «never loaded» - read the file first, then mutate. This covers
«never loaded» and «loaded for another vault» with one rule, and it depends on no caller
remembering to call anything.

### §D2 - One door, and `ledger` is `private(set)`

`ledger` and `ledgerOrigin` become `private(set)`, and the single mutation entry point is
declared **in `PraticheController.swift`**, the file that declares the property, because
Swift confines a `private(set)` setter to the declaring file and a stored property cannot
live in an extension:

```swift
enum LedgerTarget {
    case live(VaultSession?)   // the vault the controller is showing; nil when none is open
    case stale(VaultSession)   // a session that is no longer live: its own file, never `ledger`
}
@discardableResult
func updateLedger(_ target: LedgerTarget, _ change: (inout PraticaLedger) -> Void) -> LedgerWrite
```

The door: resolves the URL, checks the marker, reloads and resets if it mismatches,
refuses if the file is unreadable, applies `change` to a **local copy**, compares it with
what was there, assigns and saves only if it differs, and reports a save failure through
the existing `problem` channel. A writer becomes the closure it always was, with no
knowledge of loading, marker or saving.

This is ADR-0041's shape a second time: `VaultBoundary.url(for:) throws -> URL` replaced a
private `assertInsideVault(url)` precisely because *«a security or invariant check exposed
as a separately-callable assertion gets skipped by the next call site, not maliciously -
just by omission»* (CLAUDE.md working agreement). Six writers, five of them skipping the
check, is that sentence with numbers on it. A seventh writer cannot forget a check it
cannot reach.

The door takes a `VaultSession?`, never a `VaultController`: `recordSyncOutcome` is handed
a session and a flag by its caller and holds no controller
(`PraticaLiveSync+Run.swift:315`), and three existing tests construct it with a bare
`VaultSession` and no `VaultController` at all.

### §D3 - A file that exists and cannot be read is never saved over

`PraticaLedger.load(from: URL) -> PraticaLedger` answers `.empty` for a missing file and
for a corrupt one alike (`PraticaLedger.swift:117-122`), so a writer cannot tell «fresh,
saving is fine» from «present, unreadable, saving destroys it». It gains a sibling:

```swift
enum Read: Equatable, Sendable { case loaded(PraticaLedger), missing, unreadable }
static func read(from url: URL) -> Read
```

`missing` is `Data(contentsOf:)` failing with `CocoaError.fileReadNoSuchFile` /
`.fileNoSuchFile`; anything else that throws, and any decode failure, is `unreadable`. The
existing `load(from:)` stays, expressed through `read(from:)` and answering exactly what it
answers today - it has one production caller outside this controller,
`Sources/Connector/VaultPratiche.swift:33`, and fifteen test call sites. **Additive, so
`perg` and `pergamenum-mcp`, which compile `Sources/Core/**` through `sharedSources`
(`Project.swift:88`), keep compiling and keep reading what they read** (ADR-0007).

On `.unreadable` the marker becomes `.unreadable(url)`, the in-memory ledger is `.empty`,
every writer's save is skipped, and **one** sentence naming the file is reported for the
whole session however many writers run (a `Set<URL>` of already-reported files, cleared
per file when a later read of it succeeds). The person repairs or deletes the file by
hand; the next `load(from:)` returns to normal saving.

A refused change is still applied **in memory**, so the session stays coherent (a badge
goes out, a tray count shows) - it is simply never durable. The marker's contract is «this
memory came from that file», never «this memory equals that file»; a failed save already
broke the latter today.

### §D4 - The PG-169 special case collapses into the marker

`forgetLedgerState`'s «if the in-memory ledger is `.empty`, read the file first» heuristic
(:436-442) is deleted. It is what the marker replaces, and it is wrong in the other
direction too: a vault whose ledger is genuinely empty would re-read the file on every
single trashed folder forever.

### §D5 - A change of vault resets what belongs to the vault

When the marker names a file and the target is a *different* file - or no file, the vault
having been closed - the door and `load(from:)` both clear, together with the ledger:
`pratiche`, `trayProposals`, `trayCounts`, `watchersByPraticaPath`, `selection`,
`selectedEntryID`, `expansion`, `timeline`, `details`, `links`.

Deliberately **not** cleared, and this is the part a future reader will be tempted to
"complete":

- `praticaPathRedirects` and `forgottenPraticaPaths`. They belong to an in-flight run, and
  `endSync`/`endRegeneration` are the only correct owners of their release. A writer can
  reach the marker-mismatch path *in the middle of a run* - a controller that never loaded
  plus a sync finishing is exactly R-01's case - and clearing a tombstone there would
  resurrect the ledger key the trash just removed. `Tests/PraticaLiveSyncTrashedMidRunTests
  .swift:442` (`loadingTheSameVaultKeepsATombstoneAnInFlightRunStillNeeds`) pins the same
  rule for `load(from:)` on the same vault.
- `syncingPraticaPath`, `regeneratingPraticaPaths`, `regeneration`: same reason, and the
  run's own `defer` releases them.
- `mailStoreEvents`, `windowKeyObserver`, `fsEventsFireTask`: per Mail store and per
  controller, not per vault (Context, above).

Going from `.none` to a file is **not** a vault change and resets nothing: nothing held at
that point describes another vault, and resetting would wipe a watcher a trigger created
moments earlier.

### §D6 - A tombstone is dropped per path, not all-or-nothing

`endSync` and `endRegeneration` drop the tombstone of the path *they* release, whenever no
sync and no regeneration still claims that path - regardless of claims on other paths.
`pruneRedirectsIfIdle` keeps its wholesale clear of both collections for the case where
nothing at all is in flight (it is a superset of the per-path drop, and the redirect map
still needs it: a redirect chain can be shared by two claimants and cannot be pruned entry
by entry). A tombstone on a path still claimed stays, and that claim's outcome is still
discarded - PG-169's behaviour, unchanged.

### §D7 - `remapLedgerConversations` takes a session, like `recordSyncOutcome`

The sixth writer (§D23.4's conversation repointing, `PraticaLiveSync+Run.swift:200`) runs
after an `await session.write` and today resolves its URL from the *live* vault while
mutating the in-memory ledger. Its signature becomes
`(_ remap:of:session:isCurrentVault:)`, mirroring `recordSyncOutcome`, so a vault switch
landing inside that window writes the repointing into the run's **own** session's file
instead of dropping it. Dropping it is not free: the note has already been rewritten with
the new conversation id at that point, and the comment at :192-199 records that a ledger
left holding the old id is «a permanent silent loss unrelated to relocation».

### §D8 - Ordering: the door runs before the sibling state it sits beside

`updateTray` sets `trayProposals`/`trayCounts` and then calls `persistTrayCount`;
`forgetLedgerState` and `moveLedgerState` touch the ledger and three other dictionaries in
one pass. Since the door can now *reset* those dictionaries, **the door is called first in
each of them** and the sibling assignments follow it. This is mechanical but load-bearing:
the reverse order silently drops the tray proposals a sync just computed.

*Amended 2026-09-24 (PG-191, #351).* `select(_:in:)` was the one writer that had not been
brought into this rule: it set `selection`/`expansion` and only then called `markOpened`,
whose `updateLedger(.live(vault.session))` can reset `selection` to `nil` when the marker
names another vault. The reverse order let that reset land right after `select` had just
set `selection` to the clicked row, on a vault switch - the click read as silently dropped.
Fixed by calling `markOpened` first, joining `updateTray`/`forgetLedgerState`/
`moveLedgerState` above. The same PG-191 report named a second, independent gap: `.stale`
(§D2) is decided by session identity by every caller (`recordSyncOutcome`'s
`isCurrentVault`), but a vault closed and reopened on the same root mid-run gets a new
`VaultSession` identity for the *same* file, so a genuinely-current write was landing on
disk without updating `ledger`, only to be overwritten by the next `.live` writer's older
memory - one re-sync lost, the shape §D1-§D7 exist to prevent. `updateLedger`'s `.stale`
case now compares `Self.ledgerURL(for: session)` against `ledgerOrigin.url` and reroutes to
`.live` when they match, since the marker is defined by the file (§D1), not by which
`VaultSession` object asked.

### §D9 - Acceptance is behavioural, and the tests seed from disk

`SPEC.md`'s seam is used as-is: `PraticheController` driven directly, a real `ledger.json`
under a temporary state base, read back after each writer. Two rules follow from
`private(set)` and are part of this decision, not incidental:

- a test that drives a writer **against a real session** seeds on **disk** and never in
  memory - an in-memory seed is now discarded by the door's own read, which is the whole
  point of the fix;
- a test with **no session** seeds through the door itself, `updateLedger(.live(nil)) { … }`
  - marker `.none`, target `nil`, no read, no save, memory only.

No `#if DEBUG` hatch and no test-only setter: the seam is the production door.

---

## Alternatives considered

- **Eager load on a vault-change hook** (`VaultController.didOpenVault`, beside
  `didRelocateFolders`). Rejected: it needs a new hook plus an ordering proof that the hook
  always runs before any writer, and a writer that still runs first - a queued sync
  completing during `open(_:)`'s own `await rescan()` - stays unprotected. It also does
  nothing for «never loaded», which needs the lazy read anyway, so it buys a second
  mechanism for a subset of one guarantee. The marker needs no hook and no ordering
  argument: the check is at the write, which is where the damage is.
- **Both (marker plus eager hook).** Rejected: more surface for exactly the same
  guarantee, and two mechanisms that can disagree about when memory is fresh.
- **An `ensureLedgerLoaded()` helper each writer calls first.** Rejected outright: this is
  the shape the code is *already in* - `forgetLedgerState` has precisely that helper
  inline, and the other five writers do not call it. CLAUDE.md's own working agreement
  («a separately-callable assertion gets skipped by the next call site, not maliciously -
  just by omission») was written about this exact failure, and ADR-0041 §D1 paid to remove
  the same shape from `NoteStore`.
- **A separate `PraticaLedgerStore` type owning the ledger.** Rejected: `PraticheController`
  is `@Observable`, and SwiftUI's Observation registers a dependency on the object whose
  property is read. `AddToPraticaSheet.swift:136` reads `pratiche.ledger` from a view body;
  moving the storage into a plain nested class would silently stop that view from
  redrawing, and making the store itself `@Observable` adds a second observable object and
  a second indirection to buy an encapsulation `private(set)` already gives. The property
  stays where the views see it; only its setter moves.
- **Moving an unreadable ledger aside automatically (quarantine), then starting fresh.**
  Rejected: it turns a refusal the person can see and act on into a silent policy, and
  leaves an orphan file nobody is told about. The ledger is rebuildable by design
  (CLAUDE.md principle 3 applied to derived state: a fresh one costs one re-sync), so the
  cost of doing nothing is bounded and the cost of guessing wrong is not.
- **Treating an unreadable file as missing** (i.e. leaving `load(from:)` as the only
  reader). Rejected: it is precisely the defect, one layer down - `.empty` for a corrupt
  file plus a save is the same data loss as `.empty` for an unloaded controller plus a
  save.
- **A per-claim identity token** (each sync/regeneration carries a token, and a tombstone
  is matched against the token rather than the path). Rejected for this chain: it
  distinguishes a recreated same-name pratica from a stale claim on it - strictly more
  precise - but it touches every caller of the path resolver, for a P3 cosmetic case whose
  symptom the per-path drop already removes.
- **Leaving the tombstone alone** (PG-173's second half stays open). Rejected: the reported
  symptom is a healthy sync refused because an unrelated «Rigenera…» sheet is open, and it
  rides on this chain's own `endSync`/`endRegeneration` edit for free.
- **Pruning ledger keys whose folder is missing from disk.** Not reconsidered, and
  deliberately still refused - ADR-0026 §D7's amendment already records why: a Finder move,
  an unmounted volume and a not-yet-scanned index all look exactly like a deleted pratica.

---

## Consequences

### Positive

- The two loss paths close by construction rather than by review: a writer cannot reach the
  file without the marker, and there is no setter to route around.
- A corrupt or foreign-schema `ledger.json` stops being a silent total loss on the next
  folder rename and becomes one visible sentence.
- `forgetLedgerState` loses a heuristic and six writers lose six copies of the same
  save-and-report block; `PraticheController+Ledger.swift` (681 lines) gets shorter.
- Vault A's badges, tray proposals and throttle marks stop appearing on a vault-B pratica
  with a colliding path.
- A healthy sync is no longer refused because an unrelated sheet is open.
- The connectors are untouched: same file, same format, same `load(from:)`.

### Negative

- `PraticheController.swift` grows a door (~80 lines with its documentation) that logically
  belongs beside the other ledger code in `+Ledger.swift`. This is a Swift access-control
  constraint, not a preference: the file that declares the stored property is the only file
  that can hold its setter. A comment at both ends says so, because the repo's existing
  `pinnedTags` and `ledger` comments say the opposite trade was taken elsewhere.
- Every writer now performs a file read on its first call after a vault change, and
  `forgetLedgerState` performs one on the first trashed folder of a session even when no
  pratica is involved. One JSON file, on a path `load(from:)` already calls «cheap enough
  to call from the pane's `.task`».
- Roughly 45 lines across six test files stop compiling (they assign `ledger` directly) and
  must be re-seeded. That churn is the *proof* that R-10 holds; it is also why the SPEC
  makes «no test is disabled or deleted» a constraint.
- One existing test changes its arrangement, not its assertions:
  `PraticaLedgerFolderTrashEdgeTests.aLedgerThatCannotBeSavedIsReportedAndStillForgottenInMemory`
  creates a *directory* at the ledger's URL to force a save failure, which under §D3 is now
  detected one step earlier as `.unreadable` and refused rather than attempted. The
  save-failure path it exists to pin is still real and still reachable (a readable ledger in
  a directory that cannot be written), so it is re-arranged rather than deleted.

### Neutral

- No on-disk change, no schema bump, no migration: an existing `ledger.json` is read and
  written exactly as before.
- `VaultSession.read`/`write`, `VaultDisk` and the journal are untouched - the ledger has
  never gone through the vault's write path (it is derived per-vault state under
  `…/vaults/<id>/`, ADR-0017), and this does not change that.
- The behaviour of a read before any load is unchanged and still lossless: an empty ledger
  shows no badge and filters no sync.
- `PraticaLiveSync`'s queue, cancellation and requeue rules are untouched.

---

## References

- `SPEC.md`, Approved 2026-09-20 - PG-172, requirements R-01…R-10.
- `docs/plans/pg-172-pratiche-ledger-marker.md` - the implementation plan this decision is
  carried out by.
- ADR-0036 §D3 (`docs/adr/0036-pratiche.md`) - the ledger file, its path and its contents.
- ADR-0026 §D7 (`docs/adr/0026-drag-and-drop-board-files-into-workspace.md`), as amended
  2026-09-17 (relocation) and 2026-09-19 (trash, PG-169) - amended again here, §D6.
- ADR-0041 §D1 (`docs/adr/0041-vault-layer-consistency-and-security-cha.md`) - the
  resolver-not-an-assertion precedent this door repeats.
- ADR-0007 (`docs/adr/0007-ai-connector-mcp-over-the-vault.md`) - why a change to
  `Sources/Core/Pratiche/PraticaLedger.swift` must stay additive.
- ADR-0024 §D2 (`docs/adr/0024-workspace-board-tree-single-selection.md`) - one derived
  enum rather than two variables that can disagree.
- ADR-0043 §D7 (`docs/adr/0043-vault-write-ordering-concurrency-races.md`) - «a
  precondition evaluated before an `await` is a filter, not a guard», the shape §D7 above
  answers for the conversation remap.
- `docs/plans/pg-169-pratica-ledger-forgotten-on-folder-trash.md`, §«Follow-ups decided at
  /build close» - where PG-172 and PG-173 were filed.
- `TODO.md` `PG-172` (#312), `PG-173`.
