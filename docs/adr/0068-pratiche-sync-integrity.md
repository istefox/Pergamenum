# ADR-0068: Pratiche sync integrity — every note operation through the session, nineteen edges closed

- Status: **accepted**. Merged to `main` via PR #609 (`519668ac`, 2026-09-27), closing
  `PG-257`/#571.
- Date: 2026-09-26. Written before the implementation, against `3fcde6f0` (tree clean apart from
  `SPEC.md`). `origin/main` is `1e09448e`, and its net difference from this tree is `TODO.md` alone.
  Every line number below was read from `3fcde6f0`. None is recalled from the ROADMAP, whose line
  numbers were taken at `0d6f34a` and have drifted by up to five lines.
- **Numbering note.** This ADR is the companion of ADR-0067 and takes the next number. The same
  recheck applies before the merge, and so does the same `git mv` plus register entry if either
  number is taken first (`docs/adr/README.md` rule 1).
- **Renumbering note (2026-09-27).** Written and committed as ADR-0067 (`34346cda`), with its
  companion as ADR-0066. PR #598 took ADR-0066 on `main` first, so the companion moved to 0067 and
  this record to 0068 before this branch merged.
- **Path note.** The ADR lives at `docs/adr/`, not `docs/architecture/` (see ADR-0067's path note).
- Source: `SPEC.md` (Approved 2026-09-26), issue **#571** (`PG-257`, Audit Fable chain 4),
  ROADMAP §Chain 4 items 1–19. Every item was re-verified present at `3fcde6f0`.
- **What this extends.** ADR-0036 §D3/§D4/§D6/§D10/§D21, ADR-0040 §D4/§D7, ADR-0049 §D7,
  ADR-0052 §D1/§D3 and ADR-0059 §D5/§D6.
- **What this amends.** One bullet of ADR-0052 §D5: `windowKeyObserver` is now cleared with the
  vault-scoped state (§D15).
- **Rests on ADR-0067.** Every move, trash, restore and write this ADR routes through the session
  reaches the editor through that ADR's one door. Without it, each would need a manual follow-up.
- **Reopens nothing else.** Principles 1 and 3 hold. There is no new on-disk format, no new
  frontmatter key, and `IndexCache.schemaVersion` stays 5. These are untouched:
  - `Dossier.render`, `VaultAPI.PraticaSummary`, `PraticaNaming.messageFileName`,
    `MessageDocument.isPendingAttachmentEntry` and `VaultBoundary.url(for:)`;
  - ADR-0052's one ledger door;
  - ADR-0036 §D21's "the diff shown is the bytes written";
  - ADR-0036 §D6's "a sync never deletes a file".

  The connectors build and behave unchanged. The session doors this ADR widens live in shared
  files, gain only defaulted parameters, and neither connector calls the new ones.

## Context

The ROADMAP's root cause holds as written. Three things in the Pratiche feature go around
`VaultSession`, or around the carry-over that keeps ADR-0049's links alive. Several
ledger and outcome paths throw away state on their early exits. Verification added two
corrections:

- **Item 9.** The engine already has its own cancellation flag, so the gap is only the
  publication phase before the engine exists.
- **Item 18.** The correctly fixed twin lives in `PraticaCommandActions.follow`/`ignore`
  (`:309-340`), not in the add-to-pratica sheet.

It also found the wider shape behind item 2. The two `try? text.write` calls are only the most
visible raw operations. At `3fcde6f0`, `PraticaFileOperations` still does all of these:

| Operation | Where | Raw call |
|---|---|---|
| Trash a message's files («Escludi», «Rigenera») | `PraticaFileOperations.swift:48` | `trashItem` |
| Restore them (undo of «Escludi», failed «Rigenera») | `:86` | `moveItem` |
| Move them («Sposta in…») | `:166` | `moveItem`, then a manual `relocateNoteIDs` (`:172`) |
| Rewrite the moved note's sidecar reference | `:276` | `try? text.write` |
| Copy them («Aggiungi anche a…») | `:231` | `copyItem` |
| Move them back (undo of «Sposta in…») | `:290` | `moveItem`, then a manual `relocateNoteIDs` (`:298`) |
| Rewrite attachment links | `+Attachments.swift:111` | `try? result.write` |

Since ADR-0064, a raw move of a note is exactly what the watcher reads as an external deletion
of the source. It closes the tab showing the note instead of following it. A raw write is
reported as an external change, and a dirty tab gets ADR-0001 §D3.4's prompt for the app's own
write. `try?` swallows the failure, so a move reports success while `pergamenum-mail-original`
names a missing `.eml`.

## Decision

### §D1 — A message note moves, copies, trashes and restores only through the session (item 2)

Only the `.md` goes through the session. The `.eml` sidecar and the attachments keep their raw
`FileManager` calls: the watcher ignores them, the index does not hold them, and the session has
no byte door (SPEC Out of scope).

- **«Sposta in…» (`moveFiles`).** The name reservation stays as it is today.
  1. The `.md` moves through `session.moveFile(from:to:)`.
  2. The `.eml` moves raw.
  3. The attachments are copied raw by `copyAttachments`, which now returns its renames and
     no longer patches a file.
  4. The sidecar reference and every attachment rename are composed into one new text by two
     pure functions (§D4). That text is written once through `session.write(_:to:expecting:)`,
     with `expecting:` set to the hash of the moved note as `session.read` returns it, and only
     when the text changed.

  The manual `relocateNoteIDs` goes: `moveFile` already relocates the id (ADR-0059 §D5). It also
  moves the star.
- **«Aggiungi anche a…» (`copyFiles`).** The attachments and the `.eml` are copied raw. The `.md`
  is never `copyItem`'d. Its text is read from the source through the session, composed as
  above, and written with `session.write(_:to:expectingAbsent: true)`. The copy is a new note, so
  it gets no id until a link asks for one (ADR-0059 §D2).
- **«Escludi» and «Rigenera» (`trash(filesOf:)`).** The `.md` goes through
  `session.trashFile(at:forgettingNoteID: false)`, which returns where the Trash put it (§D3).
  The `.eml` is trashed raw.
- **Restore (`restore`).** The `.md` comes back through `session.restoreFromOutside(_:to:)`
  (§D3), and the `.eml` through a raw `moveItem`, unchanged.
- **Undo of «Sposta in…» (`moveBack`, `reverseContentRewrites`).** The `.md` goes back through
  `session.moveFile(from:to:requiringExistingFolder: true)` (§D2), and the `.eml` through a raw
  `moveItem`, which already creates nothing. Then one guarded write restores the sidecar
  reference and every attachment link in one pass (§D4). Only a note actually put back is
  rewritten, for the reason `moveBack`'s doc comment gives.

Every failure is reported through `pratiche.report(_:)` with the file's name, never swallowed. A
refused rewrite says the move landed and the reference was not updated. The file operations
become `async`. `confirmRegeneration(_:)` stays synchronous for its caller and moves the trash
inside the `Task` it already opens. `restore` stays `static`, taking the session as an argument,
so its suite still needs no `VaultController`.

**Consequence.** «Rigenera» now closes a clean tab showing the message note it regenerates:
ADR-0067 announces the trash, and the rewrite then lands on a path no tab shows. A dirty tab is
asked instead. This is a change from today, where the tab silently kept the pre-regeneration
text. The old behaviour was worse, because that tab's next save would revert the regeneration.

### §D2 — `moveFile` can refuse to create a missing folder (PG-168)

`VaultSession.moveFile(from:to:)` gains `requiringExistingFolder: Bool = false`, and
`VaultDisk.moveFile` takes the same flag. With `true`, the disk step skips
`createDirectory(withIntermediateDirectories:)`, so a missing parent makes `moveItem` throw. The
note stays where it is and the failure is reported. That is PG-168's invariant: an undo whose
source pratica has since moved or gone to the Trash never recreates the vacated folder. The same
invariant already governs `write(…requiringExistingFolder:)` and `PraticaFileOperations.restore`'s
raw move (`:73-79`). Every existing caller keeps the default and behaves as today.

### §D3 — The trash can keep the note id and say where it went; a restore door exists

**The trash.**

- `VaultDisk.trashFile(at:)` passes a `resultingItemURL` and returns the Trash URL beside its
  mutation.
- `VaultSession.trashFile(at:forgettingNoteID: Bool = true)` becomes `@discardableResult async
  throws -> URL?`.
- With `forgettingNoteID: false`, it neither reads nor forgets the id, and the journal entry's
  `idBefore` is `nil`.

This is what keeps ADR-0059 §D6 true once Pratiche uses the session door. A trash forgets the
id, but a Pratiche trash does not: «Escludi» can be undone to the same path, and «Rigenera»
rewrites the same path in the same gesture. Every other caller keeps the default and forgets as
today. The connectors' `@discardableResult` call sites compile unchanged.

**The restore door.** `VaultSession.restoreFromOutside(_ source: URL, to relativePath: String) async
throws` lives in `VaultSession+LandedChanges.swift` (ADR-0067 §D1). It works in this order:

1. **Checks.** It refuses a destination the boundary rejects, a destination that exists, and a
   destination whose parent folder is missing. No directory is created, so PG-168 holds.
2. **Rehearsal.** It returns before the disk touch on a rehearsal.
3. **Provisional self-write.** It reads the source's bytes on the main actor before the hop and
   records their hash (`NoteStore.hash`, BOM-aware since ADR-0065) as a provisional self-write,
   as ADR-0041 §D10 requires of any door the watcher can race.
4. **Disk step.** It hops to a new `VaultDisk.restoreFile(from:to:)`, which moves the file, reads
   it once, and stamps the mutation from the path's own clock. `nextSequence` is private to
   `VaultDisk.swift`, so the primitive has to live there.
5. **Bookkeeping.** It reconciles the provisional sequence and applies the mutation.
6. **Announcement.** It announces `.written(result, origin: nil)`, where `result.text` is the
   decoded text.

It is not journalled, like the trash it undoes. It leaves the note-id registry alone, because a
Pratiche trash never forgot the id.

A restore whose original path is now taken is refused. The file stays in the Trash and the
existing sentence (`restoreFailureMessage(for:)`) is shown.

### §D4 — The undo applies every inverted rename in one pass (item 3)

`applyAttachmentRenames(_:toFileAt:)` becomes a pure `applyingAttachmentRenames(_:to:) ->
String`, with its single pass over the original text unchanged. `updateOriginalReference(at:to:)`
becomes a pure `updatingOriginalReference(in:to:) -> String`. The forward move and the undo each
compose one text from these two and write it once (§D1).

The undo passes all inverted renames (`to → from`) in one call. It never makes one call per
rename. The chained case is `q.pdf → q-2.pdf` then `q-2.pdf → q-3.pdf`: a second pass would
catch the first pass's output and put both tokens on `[[q.pdf]]`.

The inverted map's keys are the forward renames' target names. `copyAttachments` claims each
target once, so they are unique. The map keeps `uniqueKeysWithValues`, and its doc comment says
why that is safe.

### §D5 — Every full render carries the linked note over (item 1)

`commit` (`PraticaSyncEngine+Messages.swift:777`) applies
`carryingOverLinkedNote(from: existingOnDisk.text, into: prepared)` to every full render where a
file already exists and this is not a requested regeneration. The two cases are:

- a `pending` body that arrived;
- a `storeReferences` change.

Both previously rewrote `prepared.noteText` from Mail alone and dropped `pergamenum-mail-note`.

The requested regeneration is excluded on purpose. `regenerationPreview` (`:742`) already
carried the link into the plan whose diff was shown. Applying the carry-over again in `commit`
is idempotent today, but ADR-0036 §D21 is a guarantee about the path, not about idempotence.
`folder.messagesByID` records the carried document, so a later message in the same run reads the
link. The write keeps `expecting: nil` (ADR-0043 §D8 excluded the full render by name). That
residual is named in §D20.

### §D6 — «Non più in Mail» is decided with the ledger's help, and clears (item 4)

`noLongerInMail(request:reader:)` (`PraticaSyncEngine.swift:206`) handles an id on disk that the
candidates did not surface and the index cannot resolve (`.notResolvableFromIndex`, measured at
3.1%). It now falls back to `request.ledgerEntries`' recorded ROWID and `reader.row(rowID:)`,
the fallback `regeneratePending` already uses (`+Messages.swift:938-947`). Only an id neither
answers for is gone.

The same computation also yields the ids it did find. It returns them in a new defaulted
`SyncOutcome.seenInMail: [String] = []`, declared last so every construction site keeps
compiling (ADR-0040 §D10). `recordSyncOutcome` (`PraticheController+Ledger.swift:321`) then
subtracts `seenInMail` as well as `importedMessageIDs` from the marked set. A message marked
once and seen again loses the marker, whether or not it is re-imported. Before, only a
re-import cleared it, and a message already on disk is never re-imported.

**Known limit.** A ROWID reused by Mail after an index rebuild makes the fallback answer
"still in Mail" for a message that left. A row read from the index carries no `Message-ID` to
check against. That is the conservative failure: the SPEC's objective is never to say a message
left when the app could not tell, and `regeneratePending` has lived with the same property.

### §D7 — The Mail-file lookup has three answers (item 5)

`EMLXLocator.LocateResult` gains `.indeterminate(Reason)`, where `Reason` is `.budgetExhausted` or
`.unreadable`.

- `enumerate` passes an `errorHandler` that records any error and keeps walking, and it returns
  an internal three-way result: hit, complete miss, or indeterminate.
- A walk that exhausts its budget, or that met an unreadable directory and found nothing, is
  `.indeterminate`. Only a complete walk of a readable `Data/` directory that found nothing is
  `.notInStore`.
- `locate` gains `enumerationBudget: Int = defaultEnumerationBudget` (20 000, as today), so a test
  can exhaust it with a tiny tree.

**In the sync loop,** `.indeterminate` skips the message, as `.notInStore` and `.ruleFailed`
already do (`:633`). The message is never imported this run, stays a candidate, and so stays
pending for the next sync. Its id goes into a new defaulted `SyncOutcome.indeterminateLookups:
[String] = []`. The pane shows one sentence for a non-empty list, distinct from «Non più in
Mail»: «N messaggi non sono stati trovati nell'archivio di Mail questa volta: verranno cercati di
nuovo al prossimo aggiornamento.» It is joined with the run's other sentences (§D19). No marker
is recorded: «Non più in Mail» stays `noLongerInMail`'s alone.

**In `regenerationPreview`** (`:721`), `.indeterminate` throws a new
`RegenerationFailure.lookupIndeterminate`, with its own sentence in
`PraticaLiveSync.regenerationFailureMessage`. It is never `.notInStore`.

### §D8 — An unreadable message note still reserves its name (item 6)

`folderContext(of:)` (`PraticaSyncEngine+Folder.swift:55-68`) builds the folder context. A `.md`
in `email/` that cannot be read (iCloud-evicted, unreadable) now appends its file name to
`takenNoteNames`, with an empty message id, before the `continue` at `:61`. A file that reads but
does not parse already did (`:63`). `uniqueMessageFileName` then never hands the name to a new
import, and the unreadable file's bytes are never touched. The name comes from the directory
listing, not from a successful read.

The timeline's own silent skip of such a file (`PraticheController+TimelineRead.swift:129`,
`:135`) is not part of R-12 and is named in §D20.

### §D9 — The row bridge is recorded on every exit of the line-4 patch (item 10)

In `commit`'s row-4 branch (`:832-875`), the bridge triple (message id, ROWID, conversation id)
depends only on the resolved row. It is now appended when the branch is entered, before any of
its early returns (`:837`, `:842`, `:851`, `:855`). The main case is "patch equals disk", the
normal path for an attachment that keeps failing, which fires every sync. Before, the ledger's
ROWID went stale after a Mail index rebuild. A write that throws still aborts the run as before.
The bridge appended for it is lost with the rest of the outcome (§D20).

### §D10 — A quarantine failure is a problem, not an abort; «Apri» enforces it (item 11)

**In the engine.**

- `PraticaSyncEngine` gains an injectable `quarantine: @Sendable (URL) throws -> Void`, defaulted
  to `AttachmentQuarantine.apply(to:)` on both initialisers.
- `commit`'s two calls (`:802` for attachments, `:883` for the `.eml`) catch its failure and
  append one sentence to `outcome.attachmentProblems`.
- The file stays where it is, and the run continues and records its outcome. Every message
  decoded before the failure keeps its place in `importedMessageIDs`.

**At «Apri».** A new pure `AttachmentChipModel.openDecision(for:state:isQuarantined:applyQuarantine:)
-> OpenDecision` has three cases:

- `.open(URL)`;
- `.refuse(sentence:reveal:)`;
- `.unavailable`, today's `openURL == nil`.

For a `.file` attachment `openURL` would open, it checks `AttachmentQuarantine.isApplied(to:)`.
If the attribute is missing, it tries to apply it. That also covers attachments placed before
PG-123. If applying fails, it refuses with «Impossibile aprire «nome» in sicurezza: il volume
non accetta l'attributo di quarantena.» and offers «Mostra nel Finder». `AttachmentChip`
presents the refusal as an alert with those two buttons.

A `.storeReference` opens as today. A file in Mail's own store is never written by this app
(ADR-0036), and Mail stamps its own downloads. Quick Look (`previewURL`) executes nothing and is
unchanged.

### §D11 — The regeneration engine is released; a permission failure is named (item 12)

**Releasing the engine.** `PraticaLiveSync` gains `releaseRegenerationEngine()`. `PraticheController`
gains a `releaseRegeneration: (() -> Void)?` closure, wired in `PraticaLiveSync.live` beside the
four it already wires. `dismissRegeneration()` («Annulla»/«Chiudi» on the sheet) calls it.

`commitRegeneration(_:)` needs the engine after the sheet closes on «Conferma»
(`confirmRegeneration` sets `regeneration = nil` before the commit runs). So it releases the
engine itself on every exit, and only when `regenerationEngine === engine`. That keeps the
round-3 identity rule, so an abandoned attempt never releases a newer one. An internal
read-only `holdsRegenerationEngine` lets a test observe it. Today about 355 MB stays alive after
the first «Rigenera».

**Naming the permission failure.** `MailStoreCopy.PublishResult` gains `.permissionDenied`.
`attemptPublish` returns a three-way result instead of `Bool`, and classifies a failure to copy
the source index or its `-wal` as a permission failure when the error is:

- `CocoaError.fileReadNoPermission`;
- an underlying POSIX `EPERM`;
- an underlying POSIX `EACCES`.

A permission failure is not retried: a second copy two seconds later fails the same way.
`MailStorePreparation.reader` maps it to «Pergamenum non può leggere l'archivio di Mail: concedi
l'Accesso completo al disco in Impostazioni di Sistema › Privacy e sicurezza.» instead of «Mail
sta scrivendo…». `PublishResult` is compiled into both connectors, but neither switches over it.

### §D12 — «Escludi» records first, trashes second (item 13)

`DossierWriter.update` (`DossierWriter.swift:33`) returns a sentence when `Dossier.parse` fails:
«La pratica «X» non ha un dossier leggibile in pratica.md: nulla è stato modificato.» It no
longer returns `nil`, which every caller reads as success. `PraticaCommandActions.updateDossier`
returns `@discardableResult Bool` (the write landed or had nothing to do).

`exclude(_:detail:)` writes the exclusion first. If that returns `false`, nothing is trashed and
the problem is already on screen. If the exclusion landed and then no file could be trashed, the
exclusion is written back out and no undo is registered, so the dossier never claims an
exclusion the files contradict. This second half follows from reordering. Before, trash-first
made the state impossible.

### §D13 — State read before an `await` is re-read after it (items 7, 8, 18)

This is `CLAUDE.md`'s working agreement, applied three times.

- **Item 7.** The «Crea» wizard's write is extracted into `PraticaCreation.writeNote(…) async ->
  String?`, a new file under `Sources/Features/Pratiche/`. It writes `pratica.md` with
  `expectingAbsent: true`, the door `VaultSession+Diary.swift:81` and `+Tasks.swift:263` already
  use. `performCreate`'s `exists` check stays as the filter that gives the early sentence. The
  precondition is the guard, and a path created during the suspension is refused, never
  overwritten.
- **Item 8.** `syncAll(in:kind:)` (`PraticheController+Triggers.swift:117`) re-reads
  `pratiche.first(where:)` before each trigger, which is `fireDueFSEventsPulses`' own shape
  (`:90-98`). A pratica gone from the list is skipped. One closed during the pass is triggered
  with its current eligibility, `.manualOnly`, so it is not synced and its watcher gains no sync
  mark (`lastWindowKeySyncAt` unchanged). This ADR reads R-14's "its watcher records nothing" as
  "no sync mark". The watcher still learns `.manualOnly`, which is how a closed pratica refuses a
  later FSEvents pulse (ADR-0036 R-17).
- **Item 18.** The add-to-pratica tail moves out of `AddToPraticaSheet.add()` into
  `PraticaCommandActions.addToPratica(messageID:praticaPath:) async -> String?`. It writes the
  inclusion, then re-reads the target through `liveTarget(of:) -> String?`, which checks that its
  `pratica.md` still exists and it is still in the list. It returns the path to select, or `nil`.
  The sheet selects and refreshes only a non-`nil` result.

### §D14 — «Annulla» reaches the publication phase (item 9)

`PraticaLiveSync` gains a run-level `stopRequested` flag:

- `cancel()` sets it, before its existing `guard let running`.
- `runExclusive` clears it on entry.
- `runExclusive` checks it right after the preparation returns, beside the existing
  `livePraticaPath` guard (`+Run.swift:107`). A set flag returns `.finished` before
  `runEngine`, and the existing `defer` releases the claim.

The preparation itself is not interrupted. It is a detached synchronous copy with no checkpoint,
and `MailStoreCopy` already discards its staging directory. The engine's own `cancelled` flag
stays the stop inside the engine. No `Task.isCancelled` check is added, which is the SPEC's
correction to the ROADMAP.

The preparation step becomes an injectable stored closure, defaulted to today's `Task.detached {
MailStorePreparation.prepare(...) }.value`. A test holds the run inside the phase with a `Gate`
(ADR-0043 §D9), calls `cancel()`, opens the gate, and observes that the engine never started.

### §D15 — The pane's appearance is throttled; the activation observer follows the vault (item 14)

`PratichePane`'s appearance task calls a new `PraticheController.paneAppeared(in:) async`, which
runs `load`, `startWatching`, then `syncAll(kind: .windowKey)`. The per-pratica 60-second
throttle then applies, so two appearances inside the window trigger one sync. The task is keyed
on the vault's identity (`.task(id: vault.root)`), so switching vault while the pane is visible
re-runs it.

The app no longer fires `.vaultOpen`. The case stays, because `PraticaWatcher`'s decision table
and its tests name it. The first appearance after a vault opens still syncs at once: the throttle
marks are vault-scoped and emptied on a vault change (ADR-0052 §D5).

Both closures `startWatching` installs now capture the vault weakly: the activation observer and
the FSEvents stream. `resetVaultScopedState()` removes the activation observer and sets
`windowKeyObserver = nil`. This amends ADR-0052 §D5's "deliberately NOT cleared" bullet for this
one property. That bullet feared the automatic triggers staying disarmed until the pane was next
opened. With the task keyed on the vault, a switch while the pane is visible re-arms at once. A
switch while it is not visible stays disarmed until the pane is opened. That is the rule the app
applies at launch (ADR-0036 §D10, "nothing reads Mail until the pane was opened"), now per vault.
`mailStoreEvents` and `fsEventsFireTask` belong to the Mail store, not the vault, and stay armed.

### §D16 — The inspector reloads on any landed write to the selected `pratica.md` (item 15)

`PratichePane`'s inspector task (`:85`) is keyed on a new `PraticheController.InspectorKey`
(selection, generation). The generation is `session.landedGeneration(at:
PraticaNaming.praticaNotePath(of: selection))` (ADR-0067 §D6). `inspectorKey(for:)` builds the
key, so a test checks that a «Nota» or a «Chiudi»/«Riapri» write advances it without rendering
a view. Only landed writes through the session advance it. An external edit to `pratica.md` does
not (§D20).

### §D17 — «Anteprima allegato» has one predicate (item 16)

`PraticaCommandActions.previewURL(for:state:) -> URL?` returns the first attachment whose
`AttachmentChipModel.previewURL(for: .file(reference), state:)` is non-`nil`. `state` is the same
file-state function the chip passes. `commands(for:)` offers `.previewAttachment` exactly when it
is non-`nil`, and `.previewAttachment` opens exactly its result. A message whose only attachments
are over-threshold store references no longer offers a command that does nothing. This is
ADR-0023's shape.

### §D18 — The Pratiche folder must be a strict subfolder of the vault (item 17)

`PraticheSettingsTab.relativeRootFolder(chosen:vaultRoot:) -> String?` is static and pure, and
answers through `VaultBoundary(root:).contains(_:)`. The vault root itself and anything outside
it answer `nil`.

`VaultBoundary` resolves only its root, so the chosen URL is resolved the same way
(`resolvingSymlinksInPath().standardizedFileURL`) before the root's prefix is removed. `/var` and
`/private/var` would otherwise disagree.

`chooseRootFolder()` stores only a non-`nil` result. Otherwise it shows «Scegli una cartella
dentro la vault, non la vault stessa né una cartella esterna.» under the row, token-styled, and
the setting keeps its previous value.

### §D19 — Consecutive preparation problems are joined (item 19)

`reportPreparationProblems` (`+Run.swift:229`) reports once, through a pure
`preparationProblemSentence(unrecoverableConversations:recipientsUnsupported:) -> String?` that
joins its sentences with a space. `report(_:)` itself stays last-writer-wins, because other
callers rely on replacing a worse sentence with a better one
(`PraticaCommandActions.confirmRegeneration`'s comment). §D7's indeterminate sentence joins the
run's `attachmentProblems` sentence in the same single report, never a second call.

### §D20 — Named and not fixed

- **Partial outcomes.** A throwing engine step other than the quarantine (a failed note write, a
  failed `makeDirectory`) still aborts the run and loses the partial outcome, including a bridge
  already appended.
- **The timeline.** It still skips an unreadable `.md` silently
  (`PraticheController+TimelineRead.swift:129`, `:135`).
- **External edits.** The inspector does not reload on an external edit to `pratica.md`. The
  watcher does not announce (ADR-0067 §D1).
- **The full-render write** keeps `expecting: nil` while carrying a link read before the run's
  first `await` (§D5). A link written between the folder read and the render is lost. The window
  is narrow, and ADR-0043 §D8 excluded the full render by name.
- **Different reporters** still overwrite one another through `report(_:)`, for example the
  preparation sentence and a later outcome sentence.
- **Sidecars and attachment bytes** stay outside the session (SPEC Out of scope).

## Alternatives considered

1. **Fix item 2 locally with `session.write` and leave the raw moves, trashes and restores.**
   Rejected (SPEC Decisions). Since ADR-0064, each raw move is read as an external deletion and
   closes the tab. Each raw restore is an external creation the index learns late. The defect
   class would stay open in five of the seven rows of the Context table.
2. **Route the `.eml` and attachments through the session too.** Rejected (SPEC Out of scope).
   The session has no byte door, the watcher ignores non-`.md` files, and the index holds none.
   Adding a byte door is a separate decision with its own journal and dry-run questions.
3. **Let the Pratiche trash forget the id like any other trash.** Rejected: it would silently
   repeal ADR-0059 §D6. «Escludi» is undoable to the same path, and a forgotten id breaks every
   `note?id=` link to that message after an undo. A parameter keeps the rule where ADR-0059 put
   it, in the one trash door.
4. **Restore with `session.write(text, expectingAbsent: true)` and delete the Trash copy.**
   Rejected. It would rewrite the bytes (BOM, line endings) instead of putting the file back, and
   it deletes a file, which this app never does (ADR-0036 §D6's spirit, ADR-0022 §D7). A move
   keeps the original file, its creation date and its extended attributes.
5. **Item 5: retry the walk silently instead of saying "indeterminate".** Rejected (SPEC
   Decisions, the user's choice). A silent retry on a mailbox that always exhausts the budget
   never ends, and the person never learns why a message never arrives.
6. **Item 11: open normally, refuse every file without the attribute, or delete and stay
   pending.** Rejected (SPEC Decisions). Opening normally drops PG-123's guarantee. Refusing
   every file breaks every attachment placed before PG-123. Deleting on a volume without
   extended attributes means the attachment never arrives.
7. **Item 13: trash anyway and report.** Rejected (SPEC Decisions). It leaves files in the Trash
   and a dossier that would re-import them on the next sync.
8. **Item 14: no sync on appearance.** Rejected (SPEC Decisions). Opening the pane is the
   person's signal that they want the pratiche current. Only the unthrottled kind was wrong.
9. **Item 17: allow the vault root.** Rejected (SPEC Decisions). Every top-level folder would
   become a pratica candidate.

## Consequences

### Positive

- The index, the journal, the self-write bookkeeping and the tabs now see every Pratiche note
  operation as the app's own. A move follows the tab, a trash closes or asks, and a restore
  catches up.
- No sync removes a person's link or claims a message left Mail on a lookup it could not finish.
  No sync overwrites a file it could not read, or loses a run's outcome to a quarantine failure.
- «Annulla», «Escludi», «Anteprima allegato», «Apri», the inspector and the folder picker do what
  they say, or refuse with a sentence.
- The regeneration engine no longer pins about 355 MB after the first «Rigenera».

### Negative

- **Five `PraticaFileOperations` members become `async`.** `PraticaFileOperations.restore` takes a
  session. Their tests move with them (`Tests/NoteIDFollowTests.swift:350`, `:357`,
  `Tests/PraticaFileOperationsRestoreTests.swift:29`, `:39`).
- **«Rigenera» closes a clean tab showing the regenerated note** (§D1).
- **«Anteprima allegato» disappears** from messages whose only attachments are store references.
  It never worked there.
- **Two new sentences on the pane:** the indeterminate lookup and the Full Disk Access copy
  failure.
- **Switching vault while the pane is hidden** disarms the activation trigger until the pane is
  opened again (§D15).

### Neutral

- No format, schema, frontmatter key or protected interface changes. The connectors build and
  behave unchanged.

## Acceptance

**Zero GUI tests** (SPEC Constraints, `CLAUDE.md` merge-gate rule). Every behaviour here has a
seam one layer below the view, so this feature spends none of its two-or-three GUI-test budget.
Every test is in `PergamenumTests`.

- **File operations (R-08, R-09).** A new `Tests/PraticaFileOperationsSessionTests.swift`, on
  `TemporaryVault` plus a real `VaultController`, the harness `NoteIDFollowTests` uses:
  - Move, copy and restore each leave the index holding the note at its final path and the path
    recorded as self-written. The watcher's reconciliation of it reports nothing.
  - «Escludi» leaves the index without the note and announces `.trashed`. The watcher's
    reconciliation of the vacated path still reports `.deleted`: an in-app trash stays visible to
    the watcher (ADR-0064 §D6, R-09 there), which ADR-0067 §D3's "a trash reaches a tab twice"
    already assumes. No absence marker is recorded for a trash.
  - A refused or failed rewrite is reported.
  - An open tab follows the move.
  - Undo with `q→q-2`, `q-2→q-3` leaves every link on an existing file.
  - Undo into a vanished pratica creates nothing.
  - A restore onto a taken path is refused and the file stays outside.
- **The sync engine (R-07, R-10, R-12, R-16, R-17).** These run over `MailStoreFixture` in the
  existing sync suites. `PraticaSyncPendingTests` and `PraticaSyncAttachmentTests` gain the
  pending-body and store-reference link cases. `PraticaSyncIntegrityTests` gains the ledger
  fallback, the marker clearing, the unreadable name, the bridge on "patch equals disk" and the
  injected quarantine failure.
- **Pure units.**
  - A new `Tests/EMLXLocatorTests.swift` covers a tiny budget and an unreadable directory
    (R-11).
  - `MailStoreReaderTests` covers an unreadable source index giving `.permissionDenied` and the
    Full Disk Access sentence (R-18).
  - `AttachmentChipTests` covers `openDecision` (R-17).
  - `PraticaCommandTests` covers the preview predicate (R-22).
  - `PraticheSettingsTests` covers `relativeRootFolder` (R-23).
  - `DossierWriterTests` covers the parse-failure sentence (R-19).
  - `PraticaWizardTests` covers the absent precondition through `PraticaCreation` (R-13).
- **The controller (R-14, R-15, R-18, R-19, R-20, R-21, R-24, R-25).** These run in
  `PraticheControllerTests`, with the injected sync closure, or on `PraticaLiveSync` built
  directly:
  - the archived-mid-pass case, with the pratica closed from inside the injected sync closure;
  - «Annulla» in the publication phase, Gate-forced;
  - the engine released on dismiss and after commit;
  - «Escludi» on an unparseable dossier;
  - two appearances inside the throttle window;
  - the observer cleared and the vault released on close;
  - the inspector key advancing;
  - `liveTarget` after a move;
  - the joined preparation sentence.

## References

- `SPEC.md` (Approved 2026-09-26); issue #571 / `PG-257`; ROADMAP §Chain 4 items 1–19.
- ADR-0001 §D3.4; ADR-0022 §D7; ADR-0023 §D8; ADR-0036 §D3/§D4/§D6/§D10/§D21; ADR-0040
  §D4/§D7/§D10; ADR-0041 §D10; ADR-0043 §D8/§D9; ADR-0049 §D7; ADR-0052 §D1/§D3/§D5; ADR-0059
  §D2/§D5/§D6; ADR-0064 §D6; ADR-0065; ADR-0067 (companion).
- `CLAUDE.md` working agreements: "a precondition evaluated before an `await` is a filter"; "a
  ledger … must record which file it was read from"; PG-168's no-recreate rule.
