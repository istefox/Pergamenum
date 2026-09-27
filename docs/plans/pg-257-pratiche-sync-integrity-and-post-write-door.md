# Plan: one post-write door, and Pratiche sync integrity (`PG-257`, #571)

- SPEC: `SPEC.md` (Approved 2026-09-26). The authority for scope, decisions and R-01..R-26.
- ADRs (both `proposed`, numbers rechecked before merge):
  - `docs/adr/0067-one-door-onto-the-editor-after-a-landed-change.md`: the post-write door.
  - `docs/adr/0068-pratiche-sync-integrity.md`: the nineteen Pratiche items and the note operations
    routed through the session.
- Base: `3fcde6f0`. `origin/main` at `1e09448e` differs by `TODO.md` only. Every line number below
  was read from `3fcde6f0`.
- One PR, one branch (`fix/pratiche-sync-integrity-post-write-door`, or the kepler branch this
  session runs on).

## SPEC decisions registered, not reopened

These are settled in SPEC §Decisions and carried into the ADRs as they stand:

- one PR, two ADRs, all nineteen items in scope;
- the hook is pulled forward and is the only door;
- it covers write, move and trash but not `.canvas`;
- the editor's save keeps ADR-0058 §D3;
- a dry run notifies nothing;
- the connectors are unaffected;
- item 2 widens to every raw note operation;
- restore gets a session door;
- item 5 has three outcomes plus a notice;
- item 4 is reversible;
- item 11 keeps the file and gates «Apri»;
- item 13 records first;
- item 14 is a throttled appearance plus a weak observer removed on close;
- item 15 is a per-path write generation;
- item 17 accepts a strict subfolder only;
- item 16 uses one predicate;
- items 7/8/18 re-read after the await;
- item 12 releases the engine and classifies EPERM;
- item 19 joins its sentences.

## What reading the code added (the coder must know these)

1. **ADR-0059 §D6 vs "trash through the session door".** `VaultSession.trashFile` forgets the note
   id. ADR-0059 §D6 says a Pratiche trash must not, because «Escludi» is undoable to the same path.
   Resolved in ADR-0068 §D3 with `trashFile(at:forgettingNoteID: Bool = true)`, which Pratiche
   calls with `false`.
2. **PG-168 vs `moveFile`.** `VaultDisk.moveFile` (`VaultDisk.swift:397`) creates intermediate
   directories. The undo of «Sposta in…» must never recreate a vacated pratica folder. Resolved in
   ADR-0068 §D2 with `moveFile(…requiringExistingFolder: Bool = false)`, which the undo calls with
   `true`.
3. **Item 12's release point.** `confirmRegeneration` closes the sheet (`regeneration = nil`)
   *before* `commitRegeneration` runs, and the commit needs the engine. Release happens on dismiss
   and at every exit of the commit, guarded by `regenerationEngine === engine` (ADR-0068 §D11).
4. **Item 6.** A file that reads but does not parse already reserves its name
   (`PraticaSyncEngine+Folder.swift:63`). Only the failed read at `:61` skips the reservation.
5. **`.vaultOpen` becomes unfired by the app** (ADR-0068 §D15). The case stays, because
   `PraticaWatcher` and its tests name it.
6. **Item 4's ROWID fallback** can answer "still in Mail" for a ROWID Mail reused after an index
   rebuild. This is the conservative failure, and it is accepted (ADR-0068 §D6).
7. **A test premise changes under a synchronous door.** The test is
   `composerHandOffPreservesEditsMadeAfterTheWriteReturned`
   (`Tests/VaultWriteOrderingBatch3Tests.swift:155`). Text typed after the write returned is now
   typed on a buffer already caught up, so no prompt is owed. The prompt case becomes "dirty
   before the write lands". Per the user's rule, this is explained in chat before the assertion is
   changed. It is never disabled.

## Standing rules for every task

- **Tooling.** `tuist install` once per fresh worktree, then `tuist generate --no-open` after any
  file is added or `Project.swift` changes. Never edit `.xcodeproj`/`.xcworkspace`.
- **Tester owns the signatures, coder owns the bodies.** A tester task adds every declaration with
  a body that preserves today's behaviour, so the target builds and the new tests fail for the
  intended reason: a no-op, today's return value, or an arm mapping a new enum case to today's
  outcome. It also makes the mechanical `await` or argument edits a signature change forces at
  existing call sites. The coder task that follows replaces those bodies. Only then do the reds
  go green.
- **Keep the build green.** Every task ends with the app building, `perg` and `pergamenum-mcp`
  building, and `PergamenumTests` green, apart from the reds the tester task declared.
- **Tests.** Never disable or delete a test. An assertion that must change is explained in chat
  first. The known ones are listed in each task.
- **UI.** Strings are Italian. Colours and fonts go through tokens (`CLAUDE.md` binding rule),
  which covers the settings refusal line and the chip's refusal alert. There are no GUI tests in
  this chain (SPEC Constraints).
- **Protected interfaces stay untouched.** A diff touching `Dossier.render`,
  `VaultAPI.PraticaSummary`, `PraticaNaming.messageFileName`,
  `MessageDocument.isPendingAttachmentEntry` or `VaultBoundary.url(for:)` is a defect.

---

## Task 1 — (tester) Declare the post-write door and write its red suite (R-01, R-02, R-03, R-05, R-06)

**Declarations** (ADR-0067 §D1, §D2, §D3, §D6):

- `Sources/Vault/VaultSession.swift`:
  - in the class body, `@ObservationIgnored var landedChangeSubscriber: (@MainActor
    (LandedChange) -> Void)?` and `private(set) var landedGenerations: [String: UInt64] = [:]`
    (observed);
  - `write(_:to:expecting:expectingAbsent:requiringExistingFolder:origin: UUID? = nil)`, with the
    new parameter last and defaulted.
- `Sources/Vault/VaultSession+LandedChanges.swift` (**new, shared**). It holds `enum LandedChange:
  Equatable, Sendable { case written(WriteResult, origin: UUID?); case moved(from: String, to:
  String); case trashed(String) }`, an internal `announce(_:)` (stub: no-op) and
  `landedGeneration(at:) -> UInt64` (stub: `landedGenerations[path] ?? 0`).
- `Project.swift`: add `"Sources/Vault/VaultSession+LandedChanges.swift"` to `sharedSources` beside
  the other `VaultSession+*.swift` entries (`:129-150`), then run `tuist generate --no-open`.
- `Sources/App/VaultController+TabFollowUps.swift`: `func landed(_ change:
  VaultSession.LandedChange)` (stub: empty).
- `VaultSession.WriteResult` is already `Equatable, Sendable` (`VaultSession.swift:265`), so
  `LandedChange` can be too, with no change to it.

**Red suite.** Create `Tests/VaultControllerLandedChangeTests.swift`. Use a real `VaultController`
on `TemporaryVault`, with both columns where the case needs it. Reuse the helpers of
`Tests/VaultControllerWriteCatchUpTests.swift`.

- `session.write` with no controller call reaches:
  - a clean tab in the other column;
  - a clean background tab in the same column;
  - a dirty tab, which gets `.text(result.text)` pending and keeps its text (R-01).
- The writer's save:
  - a real `saveOpenNote()` gives the writer no prompt;
  - `landed(.written(result, origin: writerID))` after typing keeps the typed text unsaved with
    no prompt (R-02). This is ADR-0058 test 12's shape.
  - Some R-02 cases are green before and after; mark them "guard".
- `session.moveFile` re-points a clean tab in both columns and keeps a dirty tab's buffer.
  `session.trashFile` closes a clean tab, asks a dirty one, and a following external `.deleted`
  reconcile closes nothing more (R-03).
- On a bare `VaultSession` with a recording subscriber:
  - a dry-run write, move and trash announce nothing;
  - a refused write (stale `expecting:`) announces nothing;
  - `landedGeneration(at:)` advances on a write, on both ends of a move and on a trash, and not
    on a rehearsal (R-05, ADR-0067 §D6).
- After `open(_:)` onto a second vault, a write on the first session reaches no tab of the second
  (ADR-0067 §D4).
- **One test per ADR-0058 §D7 writer family, plus a Pratiche link write.** Each has the note open
  in a clean tab, performs the write through the writer's own entry point, and expects the tab
  caught up with no explicit call (R-06):
  - `VaultSession.renameNote`'s link rewrite in a linking note;
  - `renameTag`;
  - `undoJournalledWrites`, with `session.journal = session.journalOnDisk`;
  - `moveOnBoard`;
  - `PraticaCommandActions+Links` `ensuringLocalID` (`:195`) or the link write at `:91`;
  - `PraticaEntryComposer`'s diary mirror (`:103`);
  - the Plaud re-import write (`RecordingsController+Import.swift:65`).

  If a writer's entry point cannot be reached without its live service (the Plaud loopback),
  drive the write through the helper that entry point calls, and say so in the test's comment.

**Done when:** the suite compiles, the new behavioural tests are red, the guards are green, and
the rest of `PergamenumTests` is green.

## Task 2 — (coder) Implement the door and the handler, delete the eighteen sites, update the tests that asserted them (R-01, R-02, R-03, R-04, R-05, R-06)

**Session** (ADR-0067 §D1):

- `announce(_:)` bumps `landedGenerations` for every path the change touches, then calls
  `landedChangeSubscriber`.
- `write` announces `.written(result, origin:)` after `apply([mutation])`, before `return`
  (`VaultSession.swift:581-642`). The dry-run and refusal paths return or throw earlier.
- `moveFile` and `trashFile` (`VaultSession+Journal.swift:71`, `:141`) announce last, after the
  journal record.
- The app-only folder doors announce once per carried or trashed note:
  - `VaultSession+Folders.swift:24` (`renameFolder`), `.moved` per `outcome.movedNotes`;
  - `:43` (`trashFolder`), `.trashed` per `trashedNotePaths`;
  - `VaultSession+Move.swift:144` (`moveItems`' folder case), `.moved` per `folder.movedNotes`.
- `writeFile` (the `.canvas` door) is not touched.

**Controller** (ADR-0067 §D3, §D4, §D5):

- `landed(_:)`'s three branches:
  - `.written`: the writer by origin gets `savedText` only and its prompt cleared; every other tab
    gets `catchUp(to: .text(...))`.
  - `.moved`: recents follow; a clean tab gets a fresh `readForEditing(to)`; a dirty tab keeps
    `text`/`savedText`/`externalChangePending` and changes only `relativePath`/`title`.
  - `.trashed`: `catchUp(to: .deleted)` per tab, close the `.vanished` ones through
    `closeTabs(_:ofVanishedNote:)`, then `closeTabs([], ofVanishedNote:)` for the list cleanup.
    This mirrors `VaultController+Watching.swift`'s `reconcile`.
- Subscription:
  - `VaultController.open(_:)` clears the outgoing session's subscriber before replacing
    `session`, then installs `{ [weak self, weak session] change in guard let self, let session,
    self.session === session else { return }; self.landed(change) }`;
  - `close()` clears it.
- `saveOpenNote()` passes `origin: writer.id` and calls nothing after the write.

**Delete:**

- `syncOpenNote(with:)` and `syncOpenNote(with:savedBy:)` (`VaultController+Editing.swift:92`,
  `:113`);
- `movedNote(from:to:)` and `trashedNote(at:)` (`VaultController+TabFollowUps.swift:14`, `:25`);
- their doc comments, rewritten onto `landed(_:)`.

**Remove the call sites** (grepped at `3fcde6f0`):

- `syncOpenNote(with:)`:
  - `VaultController+TimeBlocks.swift:40`, `:61`, `:97`
  - `+Categories.swift:86`
  - `+Notes.swift:82` (the loop goes; `addStructuralLink`'s `(created:, written:)` return stays)
  - `+Diary.swift:35`
  - `+TaskDrop.swift:33`
  - `+Editing.swift:64`
  - `+Tasks.swift:20`, `:66`
  - `+Routes.swift:180` (the `session.read` feeding it goes too)
  - `Sources/Features/Pratiche/PraticaEntryComposer.swift:130`
- `syncOpenNote(with:savedBy:)`: `+Editing.swift:33`.
- Manual follow-ups:
  - `+Files.swift:54`, `:79` (keep `Task { await rescan() }`, drop only the call)
  - `+Files.swift:106`
  - `+Folders.swift:64`, `:89`
  - `+Move.swift:184` (in `follow`; `didRelocateFolders?` stays)
- `PraticaEntryComposer.handOff(_:notePath:result:)` loses `result:`. Update its caller at `:70`
  and its doc comment (`:113-127`).

### Update tests and call-sites asserting the old behaviour (Task 2)

Grepped at `3fcde6f0`. Every one moves to the new door; none is deleted.

- `Tests/VaultControllerWriteCatchUpTests.swift:110`, `:124`, `:144`, `:163`: move
  `controller.syncOpenNote(with: r)` to `controller.landed(.written(r, origin: nil))`.
- `Tests/VaultControllerWriteCatchUpTests.swift:243`, `:266`: move `syncOpenNote(with:savedBy:)`
  to `landed(.written(r, origin: writerID))`. Update the file header comment (`:8`) and the MARK
  at `:98`.
- `Tests/VaultWriteOrderingBatch3Tests.swift:129`, `:146`: move to `landed(.written(result,
  origin: nil))`, or drop the explicit call where the preceding `session.write` now delivers it.
  Keep the assertions.
- `Tests/VaultWriteOrderingBatch3Tests.swift:175`, `:200`: `handOff` without `result:`.
  - `:200` (`…UsesItsWriteResultInsteadOfRereadingDisk`) keeps its assertion: the door caught the
    tab up to `result.text` during `session.write`.
  - `:175` (`…PreservesEditsMadeAfterTheWriteReturned`) has the premise change from finding 7.
    Rewrite it to make the buffer dirty *before* `session.write` and expect the prompt. Add a
    sibling asserting that edits typed after the write are ordinary unsaved edits with no prompt.
    Explain this in chat before editing. Update the header comment at `:9`.
- `Tests/VaultControllerExternalDeletionTests.swift:238`, `:271`: `movedNote`/`trashedNote` calls
  after `session.moveFile`/`trashFile`. The door now delivers them, so drop the explicit calls, or
  replace them with `landed(.moved(...))`/`landed(.trashed(...))` where the test builds its own
  change. Keep the assertions.
- `Tests/VaultControllerReconcileTests.swift:163`, `:179`: same treatment.
- `Tests/NoteTabGestureTests.swift:217`, `:233`, `:388`, `:393`: move to
  `landed(.moved(from:to:))`/`landed(.trashed(_:))`. These call the follow-ups without a real move,
  so the hand-built change is the faithful replacement.
- `Tests/TaskComposerTests.swift:341`: a comment naming `syncOpenNote`. Reword it.

**Verification:**

- `rg -n "syncOpenNote|movedNote\(|trashedNote\(" Sources` returns nothing (R-04).
- `xcodebuild … -scheme perg build` and `… -scheme pergamenum-mcp build` succeed (R-05).
- The **full** `PergamenumTests` suite is green, not only the new file. A contract change can
  break unrelated suites that share it.

## Task 3 — (tester) Declare the Pratiche seams and write their red suites (R-07, R-08, R-09, R-10, R-11, R-12, R-13, R-14, R-15, R-16, R-17, R-18, R-19, R-20, R-21, R-22, R-23, R-24, R-25)

Declarations follow ADR-0068. Bodies preserve today's behaviour. Existing callers get only the
edits needed to compile.

**Session and disk (shared files):**

- `VaultSession+Journal.swift`:
  - `moveFile(from:to:requiringExistingFolder: Bool = false)`;
  - `@discardableResult trashFile(at:forgettingNoteID: Bool = true) async throws -> URL?`, with a
    stub returning `nil` and ignoring the flag.
- `VaultSession+LandedChanges.swift`: `restoreFromOutside(_ source: URL, to relativePath: String)
  async throws`, with a stub that throws `FileOperationError.failed("restore")`.
- `VaultDisk.swift`:
  - `moveFile(from:to:requiringExistingFolder: Bool = false)`;
  - `trashFile(at:)` returns the Trash URL beside its mutation (a small struct or tuple);
  - add `restoreFile(from:to:)`, stub throwing.
  - Update `Tests/VaultWriteOrderingTests.swift:240` (`let removed = try await
    disk.trashFile(at:)`) to the new return shape, keeping its assertion on the mutation.

**Pratiche file operations:**

- `PraticaFileOperations.swift`:
  - `trash(filesOf:) async`, `moveFiles(of:to:) async`, `copyFiles(of:to:) async`,
    `moveBack(_:) async`, `reverseContentRewrites(_:notePath:) async`;
  - `static func restore(_ files: [TrashedFile], session: VaultSession) async -> [TrashedFile]`;
  - `static func updatingOriginalReference(in text: String, to emlFileName: String) -> String`.
- `+Attachments.swift`: `static func applyingAttachmentRenames(_ renames: [AttachmentRename], to
  text: String) -> String`.
- Bodies keep the raw operations for now. Add `await` at the call sites in
  `PraticaCommandActions.swift`: `exclude` `:176`/`:190`, `move`, `alsoAdd`, and
  `confirmRegeneration` `:280`/`:291`. The last one moves its `trash` inside the existing `Task`.
- `PraticaCommandActions.swift`:
  - `@discardableResult func updateDossier(at:_:) async -> Bool`;
  - `func addToPratica(messageID: String, praticaPath: String) async -> String?`;
  - `func liveTarget(of praticaPath: String) -> String?`;
  - `static func previewURL(for detail: PraticaRowDetail?, state: (URL) ->
    AttachmentChipModel.FileState) -> URL?`.

**Engine, locator and copy:**

- `EMLXLocator.swift`:
  - `LocateResult.indeterminate(Reason)` with `enum Reason: Equatable, Sendable {
    budgetExhausted, unreadable }`;
  - `static let defaultEnumerationBudget = 20_000`;
  - `locate(predictedURL:fileManager:enumerationBudget: Int = defaultEnumerationBudget)`.
  - Add an arm for the new case to both switches (`PraticaSyncEngine+Messages.swift:634`, `:721`),
    mapped as `.notInStore` is today.
- `PraticaSyncEngine+Payloads.swift`: `var seenInMail: [String] = []`, `var indeterminateLookups:
  [String] = []`, both last and defaulted (ADR-0040 §D10).
- `PraticaSyncEngine.swift`: `quarantine: @escaping @Sendable (URL) throws -> Void = { try
  AttachmentQuarantine.apply(to: $0) }` on both initialisers (`:33`, `:52`), stored.
- The `RegenerationFailure.lookupIndeterminate` case, with its arm in
  `PraticaLiveSync.regenerationFailureMessage` (`PraticaLiveSync.swift:447`) returning today's
  `.notInStore` sentence as a placeholder.
- `MailStoreCopy.swift`: `PublishResult.permissionDenied`. Add the arm in
  `MailStorePreparation.reader` (`:32`), mapped to today's `.mailIsWriting` sentence as a
  placeholder.

**Live sync, controller and views:**

- `PraticaLiveSync.swift`:
  - `func releaseRegenerationEngine()` (stub: empty);
  - `var holdsRegenerationEngine: Bool { regenerationEngine != nil }`;
  - an injectable preparation step (stored closure, same inputs and result as today's
    `Task.detached { MailStorePreparation.prepare(...) }.value`), defaulted to exactly that call;
  - `nonisolated static func preparationProblemSentence(unrecoverableConversations: Int,
    recipientsUnsupported: Bool) -> String?`.
- `PraticheController.swift`: `@ObservationIgnored var releaseRegeneration: (() -> Void)?`.
- `PraticheController+Triggers.swift`: `func paneAppeared(in vault: VaultController) async`
  (stub: today's `load` + `startWatching` + `syncAll(kind: .vaultOpen)`).
- `struct InspectorKey: Hashable` and `func inspectorKey(for session: VaultSession?) ->
  InspectorKey` (stub: generation always 0).
- `Sources/Features/Pratiche/PraticaCreation.swift` (**new**, app target): `enum PraticaCreation {
  static func writeNote(at folder: String, document: NoteDocument, session: VaultSession) async
  -> String? }` (stub: today's write without `expectingAbsent`). `performCreate` calls it.
- `AttachmentChipModel.swift`: `enum OpenDecision: Equatable { case open(URL), refuse(sentence:
  String, reveal: URL), unavailable }` and `static func openDecision(for:state:isQuarantined:
  applyQuarantine:) -> OpenDecision` (stub: today's `openURL` mapped to `.open`/`.unavailable`).
- `PraticheSettingsTab.swift`: `static func relativeRootFolder(chosen: URL, vaultRoot: URL) ->
  String?` (stub: today's string replacement).
- Run `tuist generate --no-open` after adding `PraticaCreation.swift`.

**Red suites:**

- `Tests/PraticaFileOperationsSessionTests.swift` (**new**; `TemporaryVault` + real
  `VaultController`, the `NoteIDFollowTests` harness) (R-08, R-09):
  - After «Sposta in…», copy, «Escludi» and restore, each `.md` is in the index at its final
    path and self-written: the session's reconcile of that path reports no external change.
  - An open tab on the moved note follows it.
  - A copy onto a taken name is reported, not swallowed. Use a pre-existing target that forces
    the `expectingAbsent` refusal.
  - Undo with chained renames `q.pdf→q-2.pdf`, `q-2.pdf→q-3.pdf` leaves every `[[…]]` naming an
    existing file.
  - Undo into a pratica folder moved away creates no folder.
  - A restore onto a taken path is refused and the file stays at its outside location with the
    sentence.
  - The «Escludi» trash keeps the note id (ADR-0059 §D6).
- `Tests/PraticaFileOperationsRestoreTests.swift`: re-point `:29` and `:39` to `restore(_:session:)`
  over a `TemporaryVault`. Keep `restoreFailureMessage`'s cases (`:57-63`) untouched.
- Sync suites over `MailStoreFixture`:
  - `PraticaSyncPendingTests` and `PraticaSyncAttachmentTests`: a linked note survives a pending
    body arriving and a `storeReferences` change (R-07).
  - `PraticaSyncIntegrityTests` (R-10, R-12, R-16, R-17 engine half):
    - the ledger ROWID fallback suppresses the marker;
    - `seenInMail` clears it through `recordSyncOutcome`;
    - an unreadable `.md` (chmod 000) keeps its name, the same-stem import takes `-2`, and the
      unreadable bytes are unchanged;
    - the bridge is recorded on "patch equals disk";
    - an injected throwing `quarantine` leaves every earlier message in `importedMessageIDs` and
      one sentence in `attachmentProblems`.
- `Tests/EMLXLocatorTests.swift` (**new**) (R-11):
  - `enumerationBudget: 1` over a small tree gives `.indeterminate(.budgetExhausted)`;
  - a chmod-000 subdirectory with no hit gives `.indeterminate(.unreadable)`;
  - a complete readable miss gives `.notInStore`;
  - the engine records an indeterminate id in `indeterminateLookups` and no marker.
- `MailStoreReaderTests`: a chmod-000 source `Envelope Index` gives `.permissionDenied` with no
  retry delay, and `MailStorePreparation.reader`'s sentence names «Accesso completo al disco»
  (R-18, copy half).
- `AttachmentChipTests`: `openDecision` covers four cases (R-17, «Apri» half):
  - quarantined, which opens;
  - not quarantined with apply succeeding, which opens and was applied;
  - apply failing, which refuses with the reveal URL;
  - a store reference, unchanged.
- `PraticaCommandTests`: `previewURL(for:state:)` is non-`nil` exactly when a usable `.file`
  attachment exists. A message with only store references offers no `.previewAttachment` and
  opens nothing (R-22).
- `PraticheSettingsTests`: `relativeRootFolder` covers four cases, resolving `/var` vs
  `/private/var` (R-23):
  - a strict subfolder gives the relative path;
  - the root gives `nil`;
  - an outside folder gives `nil`;
  - a symlinked temp root gives the right answer.
- `DossierWriterTests`: `update` on a `pratica.md` whose dossier does not parse returns a sentence
  and writes nothing (R-19, writer half).
- `PraticaWizardTests`: `PraticaCreation.writeNote` over an existing `pratica.md` is refused and
  its bytes are unchanged (R-13).
- `PraticheControllerTests`, or `PraticaLiveSync` built directly with `sync.controller =
  pratiche`:
  - **Archived mid-pass.** `syncAll` over two pratiche, where the injected `performSync` closes the
    second pratica during the first call. The second is not synced and its watcher has no
    `lastWindowKeySyncAt` (R-14).
  - **«Annulla» in the preparation phase.** A `Gate` holds the injected preparation, `cancel()`
    runs, then the gate opens. The engine never started: no message file is written and
    `holdsRegenerationEngine`/`running` stay idle (R-15).
  - **Engine release.** `prepareRegeneration`, then `dismissRegeneration()`, gives
    `holdsRegenerationEngine == false`. After `commitRegeneration`, the same (R-18, release half).
  - **«Escludi» on an unparseable dossier.** It trashes nothing and reports (R-19).
  - **Pane appearance.** Two `paneAppeared(in:)` calls give one `performSync` per pratica (R-20).
  - **Observer teardown.** After a vault change (`reloadLedger(for: nil)`), `windowKeyObserver ==
    nil`. After `startWatching(v)` and releasing every strong reference to `v`, a `weak` reference
    is `nil` (R-20).
  - **Inspector key.** «Nota» and «Chiudi» writes to the selected `pratica.md` advance
    `inspectorKey(for:)` (R-21).
  - **Live target.** `addToPratica` lands, then the target folder is moved by hand, then
    `liveTarget(of:)` gives `nil`. The happy path returns the path (R-24).
  - **Preparation sentence.** `preparationProblemSentence(2, true)` contains both sentences
    (R-25).

**Done when:** everything compiles, every new behavioural test is red for its stated reason, and
the rest of `PergamenumTests` is green.

## Task 4 — (coder) Route the Pratiche note operations through the session; «Escludi» records first (R-08, R-09, R-19)

- `VaultDisk.swift`:
  - `moveFile` honours `requiringExistingFolder`, skipping `createDirectory`;
  - `trashFile` passes `resultingItemURL` and returns it;
  - `restoreFile(from:to:)` refuses an existing destination or a missing parent, moves, reads the
    file once, and stamps the mutation from the path's clock (ADR-0068 §D3).
- `VaultSession+Journal.swift`: `moveFile` passes the flag through. `trashFile` skips
  `existingNoteID`/`forgetNoteIDs` when `forgettingNoteID == false` and returns the Trash URL.
- `VaultSession+LandedChanges.swift`: `restoreFromOutside`. It runs checks, the rehearsal return,
  source bytes hashed before the hop as a provisional self-write, the hop, reconcile, `apply`, then
  announces `.written(…, origin: nil)`. No journal, no note-id change.
- `PraticaFileOperations.swift` and `+Attachments.swift` follow ADR-0068 §D1 and §D4 exactly:
  - The `.md` goes through `moveFile`/`trashFile(forgettingNoteID: false)`/`restoreFromOutside`/
    `write(expectingAbsent: true)`. The `.eml` and attachments stay raw.
  - `copyAttachments` returns renames without patching.
  - One composed text per transfer is written through `write(expecting:)`.
  - The undo applies all inverted renames in one call, and moves back with
    `requiringExistingFolder: true`.
  - Delete both manual `relocateNoteIDs` calls (`:172`, `:298`).
  - Every failure is reported with the file name. Remove both `try?` writes (`:276`,
    `+Attachments.swift:111`).
- `DossierWriter.swift`: return the parse-failure sentence (`:33`).
- `PraticaCommandActions.swift`:
  - `updateDossier` returns `Bool`.
  - `exclude` writes the exclusion first, trashes second. If nothing could be trashed, it writes
    the exclusion back out and registers no undo (ADR-0068 §D12).
  - The undo restores through `restore(_:session:)`.

### Update tests and call-sites asserting the old behaviour (Task 4)

- `Tests/NoteIDFollowTests.swift:339-357` calls `ops.moveFiles` and `ops.moveBack` synchronously.
  Make it `await`. Its assertions on the id following the note stay, and hold through `moveFile`
  now.
- `Tests/PraticaFileOperationsRestoreTests.swift` was re-pointed in Task 3. It goes green here.
- `Tests/DossierWriterTests.swift:30` and `Tests/PraticaLinksWriterTests.swift:58` expect `nil` on
  a parseable dossier. They stay green; confirm.
- `PraticaRegenerationTests` and `PraticaLedgerFolderTrash*Tests` exercise «Rigenera» and the
  trash. Run them. A clean tab on the regenerated note now closes (ADR-0068 §D1). An assertion
  that relied on the old silent staleness is explained in chat before it changes.
- `rg -n "trashItem|moveItem|copyItem|\.write\(to:" Sources/Features/Pratiche/PraticaFileOperations*.swift`
  may list only `.eml`/attachment operations afterwards.

## Task 5 — (coder) Sync engine and the Mail layer (R-07, R-10, R-11, R-12, R-16, R-17, R-18)

- **Item 1** (`PraticaSyncEngine+Messages.swift` `commit`, `:777`): apply `carryingOverLinkedNote(from:
  existingOnDisk.text, into:)` on every full render with an existing file and
  `!isRequestedRegeneration` (ADR-0068 §D5). Record the carried document in `folder.messagesByID`.
- **Item 4** (`PraticaSyncEngine.swift:206`): add the ledger ROWID fallback. The same computation
  fills `outcome.seenInMail`. `PraticheController+Ledger.swift:321`'s `recordSyncOutcome` also
  subtracts `seenInMail`.
- **Item 5:**
  - `EMLXLocator.enumerate` gets an `errorHandler` and a three-way internal result, plus the
    injectable budget.
  - `locate(_:reader:)` (`:633`) skips `.indeterminate` and appends the id to
    `outcome.indeterminateLookups`. It needs the outcome, so pass it or return the case.
  - `regenerationPreview` (`:721`) throws `.lookupIndeterminate`, with its own sentence in
    `regenerationFailureMessage`.
  - The pane sentence for a non-empty `indeterminateLookups` is joined into the same report as
    `attachmentProblems` (ADR-0068 §D7, §D19).
- **Item 6** (`PraticaSyncEngine+Folder.swift:61`): append `(name, "")` to `takenNoteNames` before
  the `continue` on a failed read.
- **Item 10** (`commit` row 4, `:832-875`): append the bridge on entry, before the early returns at
  `:837`, `:842`, `:851`, `:855`. Remove the late append at `:869`.
- **Item 11** (`:802`, `:883`): call the injected `quarantine`, catch, append one sentence to
  `outcome.attachmentProblems`, and continue.
- **Item 12, copy half** (`MailStoreCopy.swift:90-145`): `attemptPublish` returns a three-way
  result. Classify `CocoaError.fileReadNoPermission`, POSIX `EPERM` and POSIX `EACCES` on the
  source copies as permission-denied. Return `.permissionDenied` with no retry.
  `MailStorePreparation.reader` gets the Full Disk Access sentence from ADR-0068 §D11.

### Update tests and call-sites asserting the old behaviour (Task 5)

- `SyncOutcome` gains only defaulted trailing fields, so every existing construction compiles
  unchanged. This covers `PraticaLiveSyncRecordOutcomeTests`, `PraticaLiveSyncTrashedMidRunTests:45`
  and `PraticheLedgerDoorTests:70`.
- `PraticaSyncPendingTests.swift:114` expects `noLongerInMail == ["<abc123@…>"]` with no ledger
  entries and no row. It stays green, because the fallback finds nothing.
- `PraticaLedgerFolderTrashEdgeTests.aPraticaRecreatedUnderTheSameNameStartsCleanAndStillImportsItsMessage`
  (`:252`) has a control half that relies on an unresolvable stale id being marked. If that stale
  id has a ledger ROWID that now resolves to the new message's row, the fallback changes the
  control. Check it. If it changes, explain in chat before touching it (finding 6).
- `PraticaRegenerationTests.swift:183` expects `.notInStore` for a missing `.emlx` in a complete
  readable walk. It stays green.
- `MailStoreReaderTests` `publish` cases (`:117-218`) stay green. There is no exhaustive switch
  over `PublishResult` in the tests.

## Task 6 — (coder) Live sync, controller and the UI edges (R-13, R-14, R-15, R-17, R-18, R-20, R-21, R-22, R-23, R-24, R-25)

- **Item 7:** `PraticaCreation.writeNote` writes with `expectingAbsent: true` and maps the refusal
  to «“X” esiste già.». `NuovaPraticaWizard+Actions.swift:159-183` keeps its `exists` filter and
  calls the helper.
- **Item 8** (`PraticheController+Triggers.swift:117`): re-read `pratiche.first(where:)` before each
  trigger and use the current eligibility (ADR-0068 §D13).
- **Item 9** (`PraticaLiveSync.swift:148`, `+Run.swift:60-107`):
  - `cancel()` sets `stopRequested`;
  - `runExclusive` clears it on entry, runs the injectable preparation, and checks it beside the
    `livePraticaPath` guard at `:107`, returning `.finished` before `runEngine`.
- **Item 12, release half:** `releaseRegenerationEngine()`, wired as `controller.releaseRegeneration`
  in `PraticaLiveSync.live`. `dismissRegeneration()` (`PraticheController+Ledger.swift:674`) calls
  it. `commitRegeneration` releases on every exit when `regenerationEngine === engine`.
- **Item 14:**
  - `paneAppeared(in:)` uses `.windowKey`;
  - `PratichePane.swift:83` becomes `.task(id: vault.root) { await pratiche.paneAppeared(in: vault)
    }`;
  - `startWatching`'s two closures capture `[weak vault]`;
  - `resetVaultScopedState()` (`PraticheController.swift:594`) removes the activation observer and
    nils it. Rewrite that function's "deliberately NOT cleared" doc bullet (`:586-590`) to match
    ADR-0068 §D15.
- **Item 15:** `inspectorKey(for:)` reads `session.landedGeneration(at: praticaNotePath(of:
  selection))`. `PratichePane.swift:85` becomes `.task(id: pratiche.inspectorKey(for:
  vault.session)) { loadInspector() }`.
- **Item 16:** `commands(for:)` (`PraticaCommandActions.swift:50`) offers `.previewAttachment` iff
  `previewURL(for:state:) != nil`. `.previewAttachment` (`:148`) opens exactly that URL. `state` is
  the chip's own file-state function.
- **Item 11, «Apri» half:** `AttachmentChip.openWithDefaultApp` switches on `openDecision`. The
  refusal is an alert with «Mostra nel Finder» (`NSWorkspace.activateFileViewerSelecting`) and
  «OK». Token-styled; no hardcoded colours.
- **Item 17:** `relativeRootFolder` goes through `VaultBoundary.contains` with both sides resolved.
  `chooseRootFolder()` (`PraticheSettingsTab.swift:95`) stores only a non-`nil` result and
  otherwise shows the refusal line from ADR-0068 §D18. The setting is unchanged.
- **Item 18:** `AddToPraticaSheet.add()` (`:184-202`) calls `actions.addToPratica(…)` and only on a
  non-`nil` result sets the pane, selects and refreshes. `onClose()` always runs.
- **Item 19:** `reportPreparationProblems` (`+Run.swift:229`) reports
  `preparationProblemSentence(…)` once.

### Update tests and call-sites asserting the old behaviour (Task 6)

- `Tests/PraticaCommandTests.swift:92-110` tests `MessageCommand.available(hasAttachments:)`
  directly, so it stays green. The predicate change is in `PraticaCommandActions.commands(for:)`,
  covered by Task 3's new cases.
- `PraticaRegenerationTests.swift:113`, `:143` and `PraticheControllerTests.swift:1009` call
  `dismissRegeneration()`. They stay green; the release is additive.
- `grep -rn "vaultOpen" Sources` should find only `PraticaWatcher`, its `switch` in `trigger`, and
  `PraticaLiveSync` coalescing. None should be in `PratichePane`.

## Task 7 — Verification, documentation and the gates (R-04, R-05, R-26)

**Verification**, all of it, in this order:

1. `tuist generate --no-open`, then build the app, `perg` and `pergamenum-mcp`.
2. Run the **full** `PergamenumTests` suite through the test command below. Both ADRs change
   contracts shared across modules, so a module-local run is not enough.
3. `scripts/mcp-smoke.py` against a Release `pergamenum-mcp` (R-05: the connectors behave
   unchanged).
4. SwiftLint on the touched files. No new error-level `file_length`/`type_body_length`.
   `VaultSession+Journal.swift` is at 393 of 400 warning lines: the restore door lives in
   `VaultSession+LandedChanges.swift` for that reason.
5. `rg -n "syncOpenNote|movedNote\(|trashedNote\(" Sources` returns nothing (R-04).
6. `scripts/uitests.sh --status`, then `--affected` at merge. That run is non-blocking under the
   merge-gate rule, and no GUI test is added.
7. `scripts/check-merge-integrity.py --self-test` if the branch merges `main` in.

**Documentation** (R-26, `(no-test: documentation obligation)`):

- `ROADMAP.md` §Chain 4 (`:314-439`):
  - Mark items 1–19 absorbed by ADR-0068 / #571.
  - Correct item 9's fix line: the engine already has its own cancellation flag, and the gap is
    the publication phase only.
  - Correct item 18: the correctly fixed twin is `PraticaCommandActions.follow`/`ignore`, not a
    line of `AddToPraticaSheet.swift`.
- `ROADMAP.md` Chain 16 item 1 (`:982-986`): mark it absorbed by ADR-0067 / #571.
- `CLAUDE.md` "Chain decision index": add ADR-0067 and ADR-0068 entries after ADR-0065's, in the
  existing one-paragraph style.
- One dated line under the status line of each partly amended ADR, bodies untouched (ADR-0047's
  precedent):
  - `docs/adr/0058-in-process-writes-reach-every-tab.md`: §D6's `syncOpenNote` clause is retired
    and §D7 is closed by ADR-0067.
  - `docs/adr/0052-pratiche-ledger-marker-and-one-write-door.md`: §D5's `windowKeyObserver` bullet
    is amended by ADR-0068 §D15.
- Recheck the ADR numbers against `origin/main` immediately before the merge. If they are taken,
  `git mv` both files and add a register entry in `docs/adr/README.md`.
- After the merge, the first docs change flips both ADRs to `accepted` with the PR number, the
  `git log --first-parent main` merge hash and the date. That is not part of this PR.

---

## Requirement coverage

| R | Task(s) |
|---|---|
| R-01, R-02, R-03 | 1, 2 |
| R-04 | 2, 7 |
| R-05 | 1, 2, 7 |
| R-06 | 1, 2 |
| R-07 | 3, 5 |
| R-08, R-09 | 3, 4 |
| R-10, R-11, R-12, R-16 | 3, 5 |
| R-13, R-14, R-15 | 3, 6 |
| R-17 | 3, 5 (engine), 6 («Apri») |
| R-18 | 3, 5 (copy), 6 (release) |
| R-19 | 3, 4 |
| R-20, R-21, R-22, R-23, R-24, R-25 | 3, 6 |
| R-26 | 7 |

## Order and dependencies

The order is 1 → 2 → 3 → 4 → 5 → 6 → 7.

- Task 2 must land before Task 4, because the Pratiche moves rely on the door to follow tabs.
- Task 3 declares everything Tasks 4–6 implement, so they can run in any order among
  themselves. The order above follows risk: file operations first.
- Task 7 is last.

## Risks, dependencies and HITL gates

**Risks:**

- **Test re-pointing breadth.** Six test files call the four deleted methods. One premise changes
  (finding 7).
- **The `.moved` dirty-tab widening.** It changes behaviour only where no `canOperate` refusal
  existed, which is Pratiche.
- **`readForEditing` timing.** In the rename path it now runs before `rescan()` instead of after.
  The index already holds the new path after `moveFile`'s `apply`. Watch `NoteTabGestureTests` and
  `VaultSessionFileOperationsTests`.
- **Synchronous delivery.** A slow subscriber would slow every write. The handler is O(open tabs)
  (ADR-0067 Negative).
- **The weak-vault test (R-20)** may find another strong reference to `VaultController` (a `Task`
  from `open(_:)`). If so, the tester reports the retainer. The test is never weakened to pass.
- **`MailStoreEventStream` in tests.** `startWatching` arms it. `MailStoreLocation.resolve()` is
  test-aware, but confirm that it never watches the real `~/Library/Mail` from
  `PergamenumTests`.
- **chmod-based tests** (unreadable `.md`, unreadable directory, unreadable index) must restore
  permissions in a `defer`, or the temporary directory cannot be cleaned.
- **Item 4's ROWID reuse** (finding 6) and **«Rigenera» closing a clean tab** (ADR-0067/0067
  Negative) are accepted consequences, recorded in the ADRs.

**Dependencies:** no new package, no new external resource, no env var, no port. Full Disk Access
is not needed for any unit test, which all run on `MailStoreFixture`.

**HITL gates:**

- **G1 — ADR-0067 §D7.** "Many dirty tabs, one banner each" answers the product question ADR-0058
  §D7 left open. The SPEC's edge case implies it. Stefano confirms or overrides at review.
- **G2 — `Project.swift` edit** (`sharedSources` gains one file) and the `tuist generate` that
  follows. Config change.
- **G3 — Test assertions that change meaning:** finding 7, plus any found in Tasks 4–5. Each is
  explained in chat before the edit.
- **G4 — Commit and push.** Feature branch only, never `main`, Conventional Commits. The pre-push
  merge-integrity hook applies.
- **G5 — ADR renumbering check** immediately before the merge (`docs/adr/README.md` rule 1).
- There is no schema change, no deletion, no deploy and no release in this chain.

TEST-CMD CANDIDATE: `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test`
TEST-CMD MODE: brownfield
