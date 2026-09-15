# PG-143 — Pratiche structure refactor

- Issue: GitHub #243, `TODO.md` `PG-143` (P1, open). The issue body is the whole specification;
  the repo's root `SPEC.md` belongs to an unrelated shipped feature and is ignored.
- ADR: **`docs/adr/0045-pratiche-structure-refactor.md`** (new, proposed). Read §D1–§D8 before the
  first move — §D3 and §D4 are the two that a step can silently violate.
- Governing prior ADRs, registered and not reopened: **ADR-0036** (Pratiche — §D5 `pratica.md` has
  one editor, §D6 a sync rewrites a message file only in the named cases, §D14 sync is one actor
  and the connection never leaves it, §D19 the connectors are structurally unable to open the Mail
  store, §D21 the regeneration plan is opaque), **ADR-0040** (§D6's amendments, `AttachmentIntegrity`,
  `MessageAttachmentPatch`), **ADR-0042** (`MessageInlineImagePatch`, `pergamenum-mail-inline-pending`),
  **ADR-0001 §D1** and **ADR-0007** (shared sources / connector purity), **ADR-0032**
  (`ImportNaming.recordingNoteTitle` is protected).
- Baseline: `main` at `75d4db5`, clean tree, no open PRs, no unmerged pratiche branch — the issue's
  «after the current pratiche branch» precondition is satisfied.
- Branch: `refactor/pg-143-pratiche-structure` (Conventional Branch, per CLAUDE.md).

## Standing rules for every task

1. **This is refactor-only.** No behaviour change, no new feature, no signature change to anything
   a caller outside the moved file uses. If a move appears to require a behaviour change, stop and
   report it — do not absorb it.
2. **Green before and after each task.** Run `TEST-CMD` (below) once before Task 1 to establish the
   baseline, and after every task. The issue names `PraticaSyncTests`, `PraticheControllerTests` and
   `PraticheUITests` explicitly; the whole `PergamenumTests` target runs regardless, because a
   structural move can break a suite in an unrelated module.
3. **`tuist generate --no-open` before every build in a task that adds or removes a file.** The
   generated project lists files explicitly; skipping this produces an error that names the compiler
   and not the cause (CLAUDE.md).
4. **`swiftlint --quiet` after every task**, and record the before/after violation count for the
   files that task touched. A task is done when its named findings no longer appear.
5. **§D3's comment rule is not optional.** Every member widened from `private` to `internal` carries
   a comment naming the extension file that reads it, in `NoteListPane.swift:23-30`'s shape.
6. **One commit per task**, Conventional Commits, `refactor(pratiche): …`. Small and atomic.
7. `Project.swift` is **not** edited in any task: the app target globs `Sources/**` and
   `sharedSources` globs `Sources/Core/**`, so every new file is picked up automatically. Verified
   at `Project.swift:86-90` and `:219-222`.
8. **`scripts/uitests.sh` runs by hand before the merge to `main`**, not per task — twelve minutes
   per run, and this chain has eight of them. Per-task greenness is the unit suite.

---

## Task 1 — Take the two non-controller types out of `PraticheController.swift` (`structure-PraticheController.swift-7e1`)

Clears the **error**-level `file_length` violation on the largest file in the feature, and does it
with zero visibility change — checked: `PraticaLiveSync` reads only `internal` members of
`PraticheController` (ADR-0045 §D2).

**Create**
- `Sources/Features/Pratiche/PraticaRowModels.swift` ← `PraticaRowDetail` (`:597-621`) and
  `PraticaAttachmentRef` (`:623-631`), verbatim, with their doc comments.
- `Sources/Features/Pratiche/PraticaLiveSync.swift` ← `SyncRunQueue` (`:970-1015`), the
  `PraticaLiveSync` class (`:1017-1543`) and the `extension PraticheController { static func live(vault:) }`
  wiring (`:943-968`), verbatim.
- `Sources/Features/Pratiche/MailStoreEventStream.swift` ← `MailStoreEventStream` (`:1545-1649`).
  Its file-scope `private` drops to `internal` — the one widening in this task. Per §D3 it gets a
  comment naming `PraticheController+Triggers.swift` (Task 2) as its only construction site.

**Modify**
- `Sources/Features/Pratiche/PraticheController.swift` — the moved ranges are deleted. Expected
  result: 1649 → ~970 lines, under the 1000-line error. The two `type_body_length` warnings (`:21`
  at 325, `:1025` at 343) survive this task by design and are Task 2's and Task 3's.

**Call sites** — none change. Verified by grep across `Sources/`, `Tests/`, `UITests/`:
`SyncRunQueue` is used by `Tests/SyncRunQueueTests.swift`; `PraticaLiveSync` by `MailSeedPicker.swift`,
`PraticheSettingsTab.swift`, `Tests/PraticaLiveSyncRecordOutcomeTests.swift`,
`Tests/PraticheControllerTests.swift`, `Tests/SyncRunQueueTests.swift`; `PraticaRowDetail` by
`PraticaCommandActions.swift`, `PraticaEntryRow.swift`, `PraticaMessageRow.swift`;
`PraticaAttachmentRef` by `AttachmentChip.swift`, `PraticaCommandActions.swift`,
`Tests/AttachmentChipTests.swift`, `Tests/PraticheControllerTests.swift`,
`Tests/VaultBoundaryCallSiteTests.swift`; `MailStoreEventStream` by `PraticheController.swift` alone.
All reference these by bare or already-qualified name, so a same-module file move is invisible to
every one of them.

**Green before and after:** full `PergamenumTests`. Named suites that must not move:
`PraticheControllerTests`, `SyncRunQueueTests`, `PraticaLiveSyncRecordOutcomeTests`,
`PraticaSyncTests`, `AttachmentChipTests`, `VaultBoundaryCallSiteTests`, `PraticheIsolationTests`.

---

## Task 2 — Bring `PraticheController`'s own body under the warning line (`structure-PraticheController.swift-7e1`, completion)

`type_body_length` counts only the class declaration, never its extensions (ADR-0045, Context fact 1),
and `file_length` counts every line — so this is three extension files, not three extensions.

**Create** (each an `extension PraticheController`, members moved verbatim with their doc comments)
- `Sources/Features/Pratiche/PraticheController+TimelineRead.swift` ← the whole
  `// MARK: - Reading the vault (pure, no @MainActor state)` extension (`:633-941`): `TimelineRead`,
  `listItems`, `folderPath`, `clientName`, `unnamedClient`, `readTimeline`, `readMessages`,
  `readManualEntries`, `parseEntryHeading`, `attachmentFileName`, `firstLine`, `dossier`,
  `entryHeadingFormatter`, `entryIDFormatter`. Its `private` members stay `private`: they move as
  one block, so the enclosing-file scope is preserved.
- `Sources/Features/Pratiche/PraticheController+Triggers.swift` ← `trigger` (`:48-72`),
  `startWatching`, `scheduleFSEventsFire`, `fireDueFSEventsPulses`, `syncAll`, `refreshNow`,
  `eligibility(of:)` (`:354-452`).
- `Sources/Features/Pratiche/PraticheController+Ledger.swift` ← `updateTray`, `persistTrayCount`,
  `dismissTrayProposal` (`:183-225`); `load`, `select`, `reloadTimeline`, `markOpened` (`:293-352`);
  `beginSync`…`remapLedgerConversations` (`:456-582`); `ledgerURL`, `stateDirectory` (`:586-594`).

**Modify**
- `PraticheController.swift` — keeps the `@Observable` declaration, its stored properties (which
  cannot move), `RegenerationState`, the `nonisolated static let` path names, `cancelSync`,
  `selectedPratica`, `filteredTimeline`, `selectedTray`, `senderAddresses`, `init`. Expected: ~330
  lines, class body under 100.

**Visibility:** nothing widens. `markOpened` and `persistTrayCount` are `private` and stay `private`
because their only callers (`select`, `updateTray`) move into the same file — §D3 rule 3.

**Watch for:** the `@Observable` macro instruments stored properties only. Computed properties moved
into an extension in another file keep working because they read instrumented stored properties;
`@ObservationIgnored` closures (`prepareRegeneration`, `commitRegeneration`, `requestSyncCancellation`)
are stored and must stay in the main declaration.

**Green before and after:** full `PergamenumTests`, especially `PraticheControllerTests`,
`PraticaTimelineTests`, `PraticaTrayTests`, `PraticaLedgerTests`, `PraticheIsolationTests`,
`PraticheConnectorTests`.

---

## Task 3 — Decompose `runExclusive`, and give the Envelope-Index block one home (`structure-PraticheController.swift-95b`, `structure-PraticheController.swift-bea`)

Clears `runExclusive`'s two **errors** (body 119 > 100, complexity 21 > 10) and the `prepare`
warnings (body 53, complexity 14). Implements ADR-0045 §D6.

**Create**
- `Sources/Features/Pratiche/MailStorePreparation.swift` — the `Prepared` and `Preparation` types
  (`PraticaLiveSync.swift:1162-1191` after Task 1), `prepare(mailRoot:stateDirectory:dossier:ledgerEntries:proposalWindow:)`
  verbatim, and one new `static func reader(mailRoot:stateDirectory:) -> ReaderOutcome` holding the
  publish + `Envelope Index` + `MailStoreReader` block with its three existing Italian sentences.
  `prepare` itself is split into four `nonisolated static` steps along the comment blocks already in
  its body: resolve `messagesByID` from the dossier and ledger; resolve followed conversations with
  §D23.3 recovery; collect the tray's unfollowed conversations; assemble `Prepared`.
  `Sources/Features/`, not `Sources/Core/` — ADR-0045 §D6 gives the reason (ADR-0036 §D19).

**Modify**
- `Sources/Features/Pratiche/PraticaLiveSync.swift` — `runExclusive` becomes a sequence of five
  named `private` methods in the same file (so nothing widens), cut at the boundaries its own
  comments already mark: `applyConversationRemap(_:praticaPath:session:)` (the §D23.4 dossier
  rewrite), `reportPreparationProblems(_:)` (the two §D23.5/§D24.4 reports),
  `evaluateCandidates(dossier:prepared:onDisk:praticaPath:session:)` (the §D22.3 double evaluation),
  `runEngine(...)` (engine construction, progress task, `sync`, `recordSyncOutcome`, the two catch
  arms), `refreshTray(...)`. `prepareRegeneration`'s own publish block is replaced by
  `MailStorePreparation.reader(...)`.
- `Sources/Features/Pratiche/MailSeedPicker.swift` — its `private enum ReaderOutcome` and
  `private nonisolated static func reader(mailRoot:stateDirectory:)` (`:141-163`) are deleted and
  the one call site uses `MailStorePreparation.reader(...)`. This is the duplicate the finding names.
- `Sources/Features/Settings/PraticheSettingsTab.swift` — `sentSenderAddresses(mailRoot:stateDirectory:)`
  (`:187-195`) routes through `MailStorePreparation.reader(...)` and keeps swallowing both failure
  cases into `[]` at its own call site. **Behaviour here must not change** (ADR-0045 §D6): Settings
  shows nothing on failure today and shows nothing on failure after.

**Contract note:** `PraticaLiveSync.shouldRunQueuedRequest`, `coalescedKind`, `SyncRunQueue.request`,
`.finished()`, `.cancelPending()` are the pure rules `Tests/SyncRunQueueTests.swift` and
`Tests/PraticheControllerTests.swift` drive directly. Their signatures do not change.

**Green before and after:** full `PergamenumTests`, especially `SyncRunQueueTests`,
`PraticaLiveSyncRecordOutcomeTests`, `PraticheControllerTests`, `PraticheSettingsTests`,
`PraticaWizardTests`, `PraticaSyncTests`.

---

## Task 4 — Split `PraticaSyncEngine` along its own MARK sections (`structure-PraticaSyncEngine.swift-186`, `structure-PraticaSyncEngine.swift-6c9`)

Three **errors**: file 1144, actor body 695, `prepare` body 169. ADR-0045 §D4 governs what must not
move, and it is the one line in this plan that a reasonable person would get wrong.

**Create** (every one an `extension PraticaSyncEngine`; nested types declared in an extension keep
their `PraticaSyncEngine.X` spelling, so no call site changes)
- `PraticaSyncEngine+Payloads.swift` ← `SyncRequest`, `SyncOutcome` (+ `.empty`), `Progress`
  (`:22-119`). These are the types `PraticheController`, `PraticaLiveSync`, `PratichePane` and
  `PraticaSyncTests` all spell as `PraticaSyncEngine.Progress` / `.SyncOutcome` / `.SyncRequest`;
  the spelling is unchanged.
- `PraticaSyncEngine+Folder.swift` ← `ExistingMessage`, `FolderContext`, `folderContext(of:)`,
  `repairCorruptAttachments` (`:291-434`). `ExistingMessage` and `FolderContext` widen `private` →
  `internal` (§D4's explicit exception, with the §D3 comment).
- `PraticaSyncEngine+Messages.swift` ← **one file, and it stays one file**: `PreparedAttachment`,
  `PreparedMessage`, `prepare`, `locate` (`:435-728`); `RegenerationPlan`, `RegenerationFailure`,
  `regenerationPreview`, `commitRegeneration` (`:729-832`); `commit`, `regeneratePending`,
  `writeAtomically` (`:833-996`). The `fileprivate` on `PreparedMessage`, `PreparedAttachment` and
  `RegenerationPlan.prepared` is **unchanged**. Expected ~560 lines, keeping a `file_length` warning
  on purpose — see §D4, and put a header comment in the file saying so, or the next reader will
  split it.
- `PraticaSyncEngine+Attachments.swift` ← `place`, `uniqueAttachmentName`, `storePath`, `digest`
  (`:998-1050`). All `private static`; nothing widens.
- `PraticaSyncEngine+Decoding.swift` ← `headerText`, `bodyText`, `normalised`, `addresses`,
  `headerForm`, `time`, `tags` (`:1051-1114`). All `private static`; nothing widens.
- `PraticaSyncEngine+Paths.swift` ← `directory(_:of:)`, `fileNames(in:)`, the five constants
  (`:1115-1144`).

**Modify**
- `PraticaSyncEngine.swift` — keeps the `actor` declaration, its stored properties, both `init`s,
  `sync`, `cancel`, `progressStream`, the progress channel, `openedReader`, `noLongerInMail`.
  Expected ~190 lines, actor body under 60.

**Visibility, exactly and no wider (§D3):** the members the moved extensions reach are
`vaultRoot`, `boundary`, `write`, `cancelled`, `emit(_:)`, `directory(_:of:)`, `openedReader()` and
the constants. Widen precisely the set the compiler names and no more — start by moving, build, and
widen only what errors. `mailStoreURL`, `progressChannel` and `reader` stay `private` if nothing in
the moved files reads them; confirm rather than assume. `prepare` also needs its own 169-line body
cut to under 100: split along its existing internal comment blocks (locate + read `.emlx`; resolve
`Message-ID` and the exclusion recheck; MIME walk and body reduction; attachment and inline-image
resolution; assemble `PreparedMessage`), all as `private` methods **inside
`PraticaSyncEngine+Messages.swift`**, so the `fileprivate` cluster stays whole.

**Invariants that must survive, from ADR-0036/0040/0042 — verify by reading, not by the suite alone:**
ADR-0036 §D14 (the `MailStoreConnection` never leaves the actor — no moved member may return or
capture `reader` across an isolation boundary), §D6 plus ADR-0040 §D5 and ADR-0042's widening (which
rewrites `commit` is allowed to perform), ADR-0040's `AttachmentIntegrity` gate before every
attachment write, §D21's preview-equals-commit guarantee (§D4).

**Green before and after:** full `PergamenumTests`, especially `PraticaSyncTests` (2250 lines, the
whole sync algorithm), `MailStoreReaderTests`, `PraticheControllerTests`, `PraticaTimelineTests`.
Also build both connectors this task (see TEST-CMD notes) — `PraticaSyncEngine` is app-only, but
this is the first task whose blast radius reaches files the connectors compile.

---

## Task 5 — Extract `PraticaFileOperations` from `PraticaCommandActions` (`structure-PraticaCommandActions.swift-7cd`)

Clears the struct-body **error** (498 > 350) and the file warning (823). This is one of ADR-0045
§D2's two new types, because the finding names a genuine second responsibility: «a 483-line struct
mixing command dispatch with filesystem plumbing».

**Create**
- `Sources/Features/Pratiche/PraticaFileOperations.swift` — a `struct PraticaFileOperations` with
  two stored properties, `let vault: VaultController` and `let pratiche: PraticheController`, holding
  the whole `// MARK: - Files` block (`:328-678`): `TrashedFile`, `MovedFile`, `trash(filesOf:)`,
  `restore(_:)`, `moveFiles`, `reverseContentRewrites`, `copyFiles`, `reservedBaseName`,
  `updateOriginalReference`, `renameAttachmentReference`, `applyAttachmentRenames`, `copyAttachments`,
  `reservedAttachmentName`, `moveBack`, `contentsMatch`, and `messageFilePaths(of:)` (`:682-684`).
  Verified: this block reaches for exactly `vault.root` and `pratiche.report(_:)`, both already
  `internal`, so nothing widens. `TrashedFile`, `MovedFile`, `ContentRewrites` and `AttachmentRename`
  are referenced nowhere outside `PraticaCommandActions.swift` — grepped across `Sources/`, `Tests/`,
  `UITests/`.
- `Sources/Features/Pratiche/PraticaMenuItems.swift` ← the `// MARK: - The two surfaces` block
  (`:735-830`): `PraticaMenuItems`, `MessageMenuItems`, and the
  `extension PraticaCommandActions { func praticaPathForMenu(of:) }` at `:814-820`. These are already
  top-level types; this is a pure file move.

**Modify**
- `Sources/Features/Pratiche/PraticaCommandActions.swift` — gains
  `private var files: PraticaFileOperations { PraticaFileOperations(vault: vault, pratiche: pratiche) }`
  and the call sites in `exclude`, `move`, `alsoAdd` become `files.trash(…)` etc. The struct's own
  public surface (`commands(for:)` ×2, `destinations(besides:)`, `run(_:on:)` ×2, `exclude`, `move`,
  `alsoAdd`, `follow`, `ignore`, `confirmDeletion`, `confirmRename`, `confirmRegeneration`,
  `updateDossier`) is untouched — it has twelve call sites across `Sources/Features/Pratiche/` and
  `Tests/DossierWriterTests.swift`.

**Green before and after:** full `PergamenumTests`, especially `PraticaCommandTests`,
`DossierWriterTests`, `PraticaSyncTests` (it asserts the trashed-file digest exclusion),
`PraticheControllerTests`.

---

## Task 6 — Split the two `View`s (`structure-NuovaPraticaWizard.swift-ec2`, `structure-PratichePane.swift-bb8`)

`NuovaPraticaWizard`'s struct body is an **error** (390 > 350); `PratichePane`'s is a warning
(293 > 250). Both are SwiftUI `View`s, so §D3's widening is unavoidable here and nowhere else in
this plan: a `View`'s `@State`/`@Environment` are stored properties and cannot move to an extension.
`NoteListPane.swift:23-30` is the precedent to copy, comment and all.

**Create**
- `Sources/Features/Pratiche/NuovaPraticaWizard+Steps.swift` ← `nameAndClient`, `knownClients`,
  `seed`, `seedSummary`, `chip`, `addTypedAddress`, `proposals`, `tick`, `newCounterparts`,
  `newCounterpartRow`, `wroteDetail`, `cappedCandidates`, `newCounterpartOverflowCount`,
  `newCounterpartTick`, `footer`, `step(by:)` (`:84-320`).
- `Sources/Features/Pratiche/NuovaPraticaWizard+Actions.swift` ← `seedFromMailSelection`,
  `resolveSeed`, `adopt`, `loadProposals`, `performLoadProposals`, `create`, `performCreate`,
  `tags(for:)`, `title(of:)` (`:321-485`).
- `Sources/Features/Pratiche/PratichePane+Sheets.swift` ← `deletionAlert`, `renameRequest`,
  `regenerationBinding`, `renameSheet`, `regenerationSheet`, `regenerationPreparingSheet`,
  `regenerationReadySheet` (`:129-245`).
- `Sources/Features/Pratiche/PratichePane+Inspector.swift` ← `inspector`, `praticaNotePath`,
  `loadInspector`, `openPraticaNote`, `syncProgress`, `emptyState` (`:286-385`).

**Modify**
- `NuovaPraticaWizard.swift` (keeps its `@State`/`@Environment`, `body`, and `content`) and
  `PratichePane.swift` (keeps its `@State`/`@Environment`, `body`, `actions`, `composer`,
  `newPratica`, `content`). Every `@State`/`@Environment` the moved files read drops `private` and
  gains the §D3 comment naming the sibling file — one contiguous comment per run, as `NoteListPane`
  does, not one per line.

**Behaviour risk, and the mitigation:** this is the only task where a wrong move changes what is on
screen, because SwiftUI view identity is structural. Keep the `body` in the original file and move
only the computed sub-views it composes — do **not** turn a step into a new `View` struct, which
would change identity and re-run `@State` initialisation. If a step looks like it wants to become
its own `View`, stop: ADR-0045's first rejected alternative covers exactly that and defers it.

**Green before and after:** full `PergamenumTests`, especially `PraticaWizardTests`,
`PraticheControllerTests`, `PraticheSettingsTests`. **Plus `scripts/uitests.sh PraticheUITests`
at the end of this task specifically** — it is the only task in this plan whose failure mode the
unit suite cannot see, and twelve minutes here is cheaper than finding it at the merge gate.

---

## Task 7 — The three de-duplications (`structure-PraticaCommandActions.swift-697`, `structure-MessageDocument.swift-3ab`, `structure-MessageDocument.swift-27f`, `structure-PraticaNaming.swift-942`)

The only task that touches `Sources/Core/**`, therefore the only one that changes what `perg` and
`pergamenum-mcp` compile. Implements ADR-0045 §D5 and §D7.

**Modify**
- `Sources/Core/Conventions/ImportNaming.swift` — `truncatedAtWordBoundary(_:toFit:)` (`:162-175`)
  drops `private`. Its doc comment gains the sentence naming both protected callers it now feeds
  (`ImportNaming.recordingNoteTitle`, `PraticaNaming.messageFileName`), so the coupling is visible
  where somebody would edit it. Nothing else in this file changes.
- `Sources/Core/Pratiche/PraticaNaming.swift` — `truncated(_:toFit:)` (`:64-77`) is **deleted**; its
  one call site at `:36` calls `ImportNaming.truncatedAtWordBoundary(…)`. Gains
  `static let praticaFileName = "pratica.md"` and
  `static func praticaNotePath(of praticaPath: String) -> String`, moved verbatim from
  `PraticaCommandActions.praticaNotePath` (`:686-690`). `messageFileName`'s signature and behaviour
  are unchanged — it is a protected interface.
- `Sources/Core/Pratiche/MessageDocument.swift` — `splitTopLevel(_:)` (`:293-322`) is **deleted**;
  its call sites call `splitOutsideQuotes(_:on: ",")` (`:361-387`). Compare the two bodies statement
  by statement before deleting and record in the commit message that the escape handling matches —
  it does today, and the commit is the place that fact is preserved.
- **Call-site updates for `praticaNotePath`** — grepped, five sites, all
  `PraticaCommandActions.praticaNotePath(of:)` → `PraticaNaming.praticaNotePath(of:)`:
  `NuovaPraticaWizard.swift:452`, `PraticaEntryComposer.swift:56`, `PraticheController.swift:1239`
  (now inside `PraticaLiveSync.swift` after Task 1), `DossierWriter.swift:28`,
  `PraticaCommandActions.swift:83`. `PratichePane.swift:360/366/378` uses a *different, private*
  computed property of the same name — leave it alone.
- Optional within this task, and only if it costs nothing: repoint
  `PraticheController.praticaFileName` and `Sources/Connector/VaultPratiche.swift:291`'s
  `praticaFileName` at `PraticaNaming.praticaFileName` as aliases rather than third and fourth
  spellings of `"pratica.md"`. Do not delete either alias — that would be a call-site change beyond
  this chain's scope.

**Guards that already cover this task, relied on rather than added:**
`Tests/SharedSourcesPurityTests.noCoreOrConnectorFileImportsAppKitOrSwiftUI` (no `Sources/Core` file
here gains a SwiftUI/AppKit import — none of these edits adds an import at all);
`Tests/PraticaNamingTests.swift` (exact-string and 40-character-budget assertions on
`messageFileName`); `Tests/ConventionsTests.swift:464-545` (five assertions on `recordingNoteTitle`,
including the long-token and short-token truncation boundaries). Read all three before the edit and
confirm they cover the truncation edges; if the «budget ≤ 0» or «one word longer than the budget»
case is not asserted on both sides, add it — that is a missing pin, not a new test to make a red
one green.

**Green before and after:** full `PergamenumTests`, especially `PraticaNamingTests`,
`ConventionsTests`, `PraticaSyncTests`, `PraticheConnectorTests`, `DrawingAndImportTests`,
`RecordingsControllerTests`. **Plus both connector builds** (`perg`, `pergamenum-mcp`) — this task
edits shared sources and ADR-0001 §D1's enforcement is a build failure, not a test failure.

---

## Task 8 — The two remaining flagged files outside the pane (`structure-MailStoreReader.swift-27d`, `structure-RecordingsController.swift-bef`)

Both warning-level `file_length` only (412 and 624 against a 400 limit). Listed in the issue, so
they close with it.

**Create**
- `Sources/Core/Email/MailStoreReader+Paths.swift` ← the `// MARK: - Paths` block (`:363-411`):
  `mailRoot(forStoreAt:)`, `mailboxDirectory(for:under:)`, `storeDirectory(in:)`, `fanOut(forRowID:)`,
  **and `emlxPath(forRow:)` (`:279-288`), which moves with them** so all four `private static`
  helpers keep their `private` (§D3 rule 3). Foundation + SQLite3 only — no SwiftUI, no AppKit
  (§D7).
- `Sources/Features/Recordings/RecordingsController+Ledger.swift` ← the extension at `:437-518`
  (`noVaultMessage`, `reloadLedger`, `record`, `notePath`, `isolate`, `readableMessage`).
- `Sources/Features/Recordings/RecordingsController+Interface.swift` ← the extension at `:520-623`
  (`loadProposal`, `suppressedFingerprints`, `draft`, `saveDraft`, `clearDraft`, `updateDays`,
  `ensureStore`).

**Modify**
- `MailStoreReader.swift` → ~360 lines. `RecordingsController.swift` → ~440 lines; if it does not
  clear 400, move `// MARK: - Two-phase import (ADR §D13)` (`:283-436`) into a third file rather than
  trimming comments. Widen only what the compiler names, with §D3 comments.

**Watch for:** `RecordingsController`'s two existing extensions share `private` members with the main
declaration (`ensureStore` is used inside its own extension; `reloadLedger`/`record`/`notePath`
inside theirs). Move each extension whole and only widen across the new seam.

**Green before and after:** full `PergamenumTests`, especially `MailStoreReaderTests`,
`RecordingsControllerTests`, `PraticaSyncTests`, `PraticheConnectorTests`. **Plus both connector
builds** — `MailStoreReader.swift` is under `Sources/Core/**` and compiles into both.

---

## Definition of done for the chain

1. `swiftlint --quiet` reports **zero error-level findings** under `Sources/Features/Pratiche/`,
   `Sources/Core/Pratiche/`, `Sources/Core/Email/`, `Sources/Core/Conventions/` and
   `Sources/Features/Recordings/`. One deliberate `file_length` warning remains on
   `PraticaSyncEngine+Messages.swift` (ADR-0045 §D4) and is recorded in the PR body as deliberate.
2. All thirteen `structure-*` findings from issue #243 are addressed, each by the task that names it.
3. `xcodebuild … -only-testing:PergamenumTests test` green; `perg` and `pergamenum-mcp` both build.
4. `scripts/uitests.sh` run by hand, whole bundle, green — the merge gate, not optional.
5. `git diff main --stat` shows no change to any `.md` under `docs/` other than this plan and
   ADR-0045, no change to `Project.swift`, no change to `.swiftlint.yml`, no test deleted or skipped.
6. ADR-0045's status moves from `proposed — decided, not implemented` to `accepted`, and CLAUDE.md's
   «Chain decision index» gains its one-line entry.

---

## Risks, dependencies and HITL gates

**Risks**

- **The `fileprivate` cluster (Task 4) is the one move that can repeal an ADR silently.** Widening
  `PreparedMessage`/`RegenerationPlan.prepared` to `internal` would compile, would leave the suite
  green, and would quietly undo ADR-0036 §D21's preview-equals-commit guarantee. ADR-0045 §D4 says
  no; the reviewer should check this specific keyword rather than trusting the green.
- **Task 6 is the only task whose failure mode the unit suite cannot see.** SwiftUI view identity is
  structural; a step promoted to its own `View` would reset `@State` and the wizard would lose the
  name somebody typed on step 1. Hence the `PraticheUITests` run inside that task.
- **A green unit suite is not evidence for the UI suite.** CLAUDE.md records that
  `.claude/test-cmd`'s `-only-testing:PergamenumTests` restriction is load-bearing and that a suite
  outside it has unknown state between deliberate runs (`PG-033`). Do not read eight green turns as
  eight green UI runs.
- **`tuist generate` drift.** Any task that adds a file and is then bisected, stashed or
  branch-switched leaves the generated project listing files that are not there. Re-run
  `tuist generate --no-open` after every such git operation, not only after editing `Project.swift`.
- **Roughly a dozen members become `internal` and therefore visible to `@testable import`.** No test
  should start reaching for them. Worth one grep at the end of the chain.
- **`Tests/PraticaSyncTests.swift` is an error-level violation (file 2250, type body 1665) that this
  plan deliberately leaves standing** (ADR-0045 §D8). Recommendation: file it as its own `PG-` entry
  before closing #243, so «PG-143 done» does not read as «the pratiche layer is clean». It is not.
- **`.claude/protected-interfaces` is convention, not a gate, in the current install.** No
  `interface-check.sh` exists in the lean hook set — checked. `PraticaNaming.messageFileName`,
  `ImportNaming.recordingNoteTitle`, `MessageDocument.isPendingAttachmentEntry` and `Dossier.render`
  are protected by review and by their own tests, and by nothing else. Task 7 touches two of those
  four files.
- **`git blame` on the moved code stops at each refactor commit.** Unavoidable; `--follow`/`-C`
  recover it. Worth one line in the PR body so the next archaeologist knows.

**Dependencies**

- Nothing external. No third-party API, no OAuth or consent flow, no cloud console, no new env var,
  no port. Everything runs offline against the working tree, which is CLAUDE.md principle 2 holding.
- `swiftlint 0.65.1` must be on the PATH (it is, at `/opt/homebrew/bin/swiftlint`) — used for
  verification, not for the build.
- Tuist 4 and the Xcode 26 toolchain, already required by every build here.
- `scripts/uitests.sh` needs no copy of the app open out of `/Applications` and no stale UI-test
  instance alive; it refuses and kills respectively, but a 60.2 s failure in its output names the
  launch timeout, not a defect.

**HITL gates — none of these are the implementing agent's to pass**

- **Each of the eight commits.** CLAUDE.md requires a human gate before every commit.
- **The push and the pull request.**
- **The merge to `main`**, which is also the gate `scripts/uitests.sh` must have run green before.
- **Approval of ADR-0045 itself**, before Task 1 starts: §D4 and §D5 are the two clauses that bind
  the coder's hands, and §D5 in particular creates a deliberate coupling between two protected
  file-naming paths. That is a decision for the human, not a plan detail.
- **Any deletion.** Tasks 3, 5 and 7 delete code (`MailSeedPicker.reader`, `PraticaNaming.truncated`,
  `MessageDocument.splitTopLevel`, `PraticaCommandActions.praticaNotePath`). Each is a deletion of a
  member whose behaviour survives elsewhere; each still needs the human's explicit yes, and the diff
  shown first.
- **Nothing in this plan authorises `swiftlint:disable`, a threshold change in `.swiftlint.yml`, or
  skipping a test.** If a task cannot reach its threshold without one, stop and report.

---

TEST-CMD CANDIDATE: `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -derivedDataPath "/Users/stefer/Developer/Pergamenum/.build/DerivedData" -only-testing:PergamenumTests test`

TEST-CMD MODE: brownfield

The line above is `.claude/test-cmd` verbatim and is deliberately unchanged: it runs through the
`Stop` hook at the end of **every** turn, and CLAUDE.md records why `-only-testing:PergamenumTests`
is load-bearing rather than tidy — with the UI suite in there, every turn terminated the app the
person at the keyboard was using and left an instance holding the global hot key, so the next launch
was refused.

Two verifications this refactor needs that the per-turn command does **not** cover, to be run at the
task gates named above and never wired into the `Stop` hook:

```bash
xcodebuild -workspace Pergamenum.xcworkspace -scheme perg           -destination 'platform=macOS' build
xcodebuild -workspace Pergamenum.xcworkspace -scheme pergamenum-mcp -destination 'platform=macOS' build
scripts/uitests.sh                       # whole bundle, before the merge; PraticheUITests alone at Task 6
```

The connector builds matter here because Tasks 4, 7 and 8 touch `Sources/Core/**`, which
`sharedSources` globs into both `.commandLineTool` targets: a file added there that imports SwiftUI
breaks both builds and nothing in `PergamenumTests` would say so (ADR-0001 §D1, CLAUDE.md «AI
connector»). CI (ADR-0044) builds all three targets on every PR, so it catches this too — but at PR
time, not at the task gate where the cause is still one commit wide.
