Status: Approved (2026-09-25)

# SPEC — External deletion reaches the Diario pane and the editor tabs, not just the index

## Destination

A SPEC handed to `/workplan`. Closes issue #511 (PG-234): `VaultDisk.reconcile` silently returns
`change: nil` when a watched path is missing, so an external deletion never produces an
`ExternalChange` — the #495/ADR-0057 §D8 wiring (`DiaryController.externalChange(at:)`) never
fires, and the same gap already existed for every open editor tab (`VaultController.reconcile`).
This SPEC widens the shared `ExternalChange` signal to represent deletion and gives both
consumers — the Diario pane and the editor tabs — real behavior for it, closing the whole
root cause rather than only the diary symptom named in the issue title.

## Objectives

- A clean Diario pane showing a day whose file was deleted by another process reloads to the
  empty-day state, as ADR-0057 §D8 already intended but could never reach.
- A clean editor tab showing a note deleted externally closes automatically, the same outcome
  an in-app "Sposta nel Cestino" already produces via `trashedNote(at:)`.
- A dirty editor tab showing a note deleted externally gets a conflict banner that makes sense
  for a missing file — not today's "Ricarica da disco", which has nothing left to reload.

## Scope and non-goals

In: `VaultDisk.reconcile`'s missing-path branch, `VaultSession.ExternalChange`'s shape,
`VaultController.reconcile`'s per-tab handling, `NoteTab.OpenNote`'s pending-change state,
`EditorColumn+Conflict.swift`'s banner. `DiaryController.externalChange(at:)` needs no change —
it already does the right thing once called.
Out: `WorkspaceController`/`.canvas` external-deletion handling (a different mechanism,
ADR-0054's own watcher-refusal decision, untouched); a "recently deleted" recovery UI; any new
self-write suppression bookkeeping for deletions (see Decisions).

## Decisions

- **Deletion becomes a real case of the shared signal, not a sentinel.** `ExternalChange` gains a
  `Content` enum (`.text(String)` / `.deleted`) instead of an unconditional `text: String`.
  Rejected: encoding deletion as `text: ""` — indistinguishable from a file genuinely emptied by
  another writer, which must still be adopted as text.
- **A clean editor tab auto-closes on external deletion**, mirroring `trashedNote(at:)`'s existing
  unconditional close for an in-app trash. Nothing is lost: the buffer already matched disk, which
  is now gone. Rejected: leaving the tab open with a "file missing" indicator — a new UI state and
  an open question about what a save would even mean, for no benefit over closing.
- **A dirty editor tab gets a banner with "Scarta ed elimina" (discard the edits, close the tab)
  and "Tieni la mia versione" (clear the conflict; the next ordinary save recreates the file).**
  "Tieni la mia versione" needs no new write precondition: `saveOpenNote()` already calls
  `session.write` unguarded (no `expecting:`), so it recreates a missing file exactly as it would
  overwrite an existing one. Rejected: keeping "Ricarica da disco" — there is no disk copy to
  reload.
- **No self-write suppression is added for the deletion signal**, unlike the hash-based
  suppression `selfWrittenHashes` gives text writes. An app-triggered trash already closes every
  tab showing the path synchronously, inside `trashedNote(at:)`, before the (async, FSEvents-
  driven) watcher's own `reconcile` can arrive for the same path — so the redundant deletion event
  finds no matching tab and is a no-op. Rejected: a parallel `selfDeletedPaths` bookkeeping set
  mirroring `selfWrittenHashes` — extra machinery for a race that already resolves itself by
  ordering; the one narrow remaining case (FSEvents firing between the physical trash and
  `trashedNote`'s synchronous close) is accepted as a cosmetic, already-tolerated class of race
  rather than engineered around.
- **The Diario side needs no new decision.** `DiaryController.reload()` already treats a missing
  file as the empty-day state (ADR-0057: "not writing a file for a day nobody wrote anything on").
  The only gap is that the signal never reaches `externalChange(at:)` to trigger it.

## Constraints

- **`VaultSession+Watching.swift` (where `ExternalChange` lives) is in `sharedSources`, compiled
  into `perg` and `pergamenum-mcp`.** Its shape may change but neither connector may gain new
  behavior or capability from it — origin: ADR-0007's shared-sources architecture.
- **`WorkspaceController`'s `.canvas` reconciliation is untouched** — origin: ADR-0054 §D7's own,
  separate watcher-refusal decision; not reopened here.
- **Never disable or delete a test to make a suite pass** — origin: global rules.
- **Work happens on a feature branch, `/workplan` and `/build` in separate sessions** — origin:
  user mandate (CLAUDE.md workflow invariants).

## Stack

Swift 6, existing `VaultDisk` / `VaultSession` / `VaultController` / `DiaryController` /
`NoteTab` / `EditorColumn+Conflict` types. Swift Testing. No new dependency.

## Data model

No schema or on-disk format change. The shared signal's shape widens:

```
struct ExternalChange: Equatable, Sendable {
    enum Content: Equatable, Sendable {
        case text(String)
        case deleted
    }
    let path: String
    let content: Content
}
```

`OpenNote.externalChangePending: String?` becomes an equivalent pending-content value (exact
type — a matching `Content?`, or two mutually-exclusive optionals — decided in `/workplan`) so a
dirty tab can carry "there's a conflict, and it's a deletion" rather than only "there's a
conflict, and here's the incoming text".

## API / interfaces

- `VaultDisk.reconcile`: the missing-path branch returns an `ExternalChange` with
  `content: .deleted` instead of `nil`, still advancing the path's clock exactly as today.
- `VaultSession.reconcile`: propagates the new case unchanged; no change to the self-write
  suppression path, which stays scoped to hash-matched text writes (Decisions).
- `VaultController.reconcile`: on `.deleted`, replaces the current blind `catchUp(to:)` call for
  that path with per-tab handling — a clean tab schedules a close, a dirty tab sets the new
  pending-deletion state — instead of applying text. `didChangeExternally?(path)` still fires
  unconditionally, as today; `DiaryController.externalChange(at:)`'s own `isSettled` guard already
  no-ops correctly when the pane has something owed.
- `NoteTab.OpenNote.catchUp(to:)` takes the new `Content` type; `.deleted` on a clean buffer signals
  "close this tab" to the caller rather than mutating `text`/`savedText`.
- `VaultController.acceptExternalChange()`: when the pending state is a deletion, discards the
  buffer and closes the tab instead of replacing `text` with (absent) incoming text.
- `VaultController.keepLocalVersion()`: when the pending state is a deletion, behaves as today —
  clears the pending flag; the tab's next ordinary save recreates the file.
- `EditorColumn+Conflict.swift`: the banner's copy and button pair branch on the pending kind —
  the existing "La nota è cambiata su disco…" / "Ricarica da disco" / "Tieni la mia versione" for
  a text change, new copy plus "Scarta ed elimina" / "Tieni la mia versione" for a deletion.

## Edge cases

- The file is deleted and then recreated by another process before the person reacts to a
  dirty-tab banner: out of scope, the same class of race every existing `ExternalChange` handling
  already tolerates — the banner reflects the state as of the `reconcile` call that produced it.
- The same deleted note is open in more than one tab, across both columns: every clean tab closes,
  every dirty tab gets its own banner independently — `updateTabs(showing:)`'s existing
  all-columns behavior (ADR-0056), unchanged by this SPEC.
- A preview tab (`isPreview`) versus a pinned tab: no distinction, same rule `trashedNote(at:)`
  already applies today.
- The diary file is deleted while its pane has something owed or is conflicted:
  `externalChange(at:)`'s `isSettled` guard already ignores the signal, unchanged (ADR-0057 §D8).

## Test seams

Existing door, no new architecture: `VaultController.reconcile(_:)` driven directly against a
`TemporaryVault`, the same pattern `Tests/DiaryWatcherReloadTests.swift` and
`Tests/VaultControllerReconcileTests.swift` already use for text changes. A deletion is simulated
by removing the file after a `TemporaryVault.write` (a small helper addition to
`Tests/TemporaryVaultSupport.swift`, decided in `/build`, not a new seam). No new GUI test: the
behavior is covered at the `VaultController`/`DiaryController` unit level, consistent with the
project's small, deliberately bounded GUI suite (CLAUDE.md working agreements).

## Success criteria

- [ ] R-01 — A clean Diario pane reloads to the empty-day state when its day's file is deleted
  externally, driven through `VaultController.reconcile(_:)` exactly as `DiaryWatcherReloadTests`
  drives a text change.
- [ ] R-02 — A dirty Diario pane is left untouched by an external deletion, same as it is today
  for a content change (`isSettled` guard).
- [ ] R-03 — A clean editor tab showing a note deleted externally closes automatically, in every
  column that shows it.
- [ ] R-04 — A dirty editor tab showing a note deleted externally shows a banner offering "Scarta
  ed elimina" and "Tieni la mia versione", never "Ricarica da disco".
- [ ] R-05 — "Tieni la mia versione" on a deleted-file conflict clears the pending state; the
  tab's next ordinary save recreates the file, verified through the existing unguarded
  `saveOpenNote()` write path.
- [ ] R-06 — "Scarta ed elimina" on a deleted-file conflict closes the tab without writing,
  discarding the unsaved text.
- [ ] R-07 — `VaultDisk.reconcile`'s missing-path branch produces an `ExternalChange` with
  `content: .deleted` instead of `nil`.
- [ ] R-08 — `perg` and `pergamenum-mcp` still build clean after `ExternalChange`'s shape change.
  (no-test: build verification, not a unit assertion — checked via the existing three-target
  build step already required before commit.)
- [ ] R-09 — No self-write suppression bookkeeping is added for deletions; an app-triggered trash
  still runs `trashedNote(at:)` synchronously ahead of the watcher's own `reconcile`, so the
  redundant signal is a no-op on an already-closed tab. (no-test: an ordering argument recorded
  as a Decision, not independently mechanized.)

## Not yet specified

- Exact Italian copy for the dirty-tab deletion banner's message and buttons — resolved in
  `/build` against the tone of the existing strings ("La nota è cambiata su disco mentre la
  stavi modificando.", "Ricarica da disco", "Tieni la mia versione").
- The exact `Content?` vs. two-optionals shape for `OpenNote`'s pending-deletion state — decided
  in `/workplan`, per the Data model note above.

## Out of scope

- **`WorkspaceController`/`.canvas` external-deletion handling** — a distinct mechanism under
  ADR-0054's own watcher-refusal decision, not reopened here.
- **A "recently deleted notes" recovery UI** — no such feature exists today and this SPEC does not
  introduce one; closing/emptying is the whole of the new behavior.
- **Self-write suppression bookkeeping for deletions** (a `selfDeletedPaths`-style set) — ruled out
  in Decisions as unnecessary given the existing close-before-watcher ordering.

## Domain terms

_none_
