# Pergamenum code audit — 2026-10-30

Step 1 of a four-step audit (code → workflows → GUI → roadmap). Scope: every file under
`Sources/`, `Tests/`, `UITests/`, `scripts/`, `.github/`, the Tuist manifests, the theme and
vocabulary JSON and the `.claude/` config, read in full by 23 read-only reviewers on slices whose
coverage was proven by literal file lists (no file missing, none twice). Baseline `main` @
`54cf47e7` plus the uncommitted diff of `feat/pg-427-pg-428-underscore-concealment-daily-transclusions`
(findings there are marked `In flight: yes`). Static tools: Periphery 3.8.0 (twice: with and
without the test targets), SwiftLint 0.65.1. Every finding was deduplicated against `TODO.md`,
`ROADMAP.md` and `docs/deep-refactor/2026-09-11-pergamenum-audit.md`; already-tracked items are
listed per slice, not re-counted. Every P1 was re-read at its cited line by the coordinator.

Nothing in the repository was changed by this audit.

## Numbers

| Severity | Findings |
|---|---|
| P1 | 5 (3 distinct defects after merging duplicates, plus 2) |
| P2 | 27 (19 distinct after merging duplicates) |
| P3 | 227 |
| P4 | 122 |

By category: correctness 100, performance 40, dead-code 30, docs 29, test clarity 28, test
hygiene 24, flaky 21, duplicate test support 21, security 20, simplification 19, weakened tests
17, house-rules 16, assertion-free 8, test-only seams 6, pinned defects 2.

## P1 — fix first (all re-verified at the cited line)

1. **A hostile email copies an arbitrary local file into the vault** (SEC-01 = S05-01 = S11-01).
   The MIME attachment filename is appended unchecked under Mail's
   `Attachments/<rowID>/<part>/` (`PraticaSyncEngine+Messages.swift:115-117`,
   `+Attachments.swift:37-40`); when the inline part is empty (the ADR-0048 path) the sync reads
   that path and copies the bytes into `allegati/`, or records the path as `storePath`. A name
   like `../../../../.ssh/id_ed25519` needs only a message matching a pratica's rule. The vault
   may sync to iCloud and is served to a model by `pergamenum-mcp`. First raised in the
   2026-09-11 audit, never given a PG id. Fix: reduce to `lastPathComponent`, refuse `..`/`/`/NUL,
   and check the resolved URL stays inside the attachments directory; `SEC-02` (opening
   `storePath` from frontmatter without a containment check) closes with the same helper.
2. **A `settings.json` that fails to decode is replaced by defaults with a new vault id**
   (S02-01 = SEC-03). `readSettings` returns `.default` on a decode error
   (`VaultSession+Identity.swift:35-37`); `resolveIdentity` then mints a UUID and
   `writeSettings` overwrites the file (`:53-62`) — contradicting the doc comment at `:25-26`
   ("The file is not overwritten on a decode failure"). One stray comma loses every vault
   setting and orphans the state directory (index, journal, history).
3. **Leaving a board drops a conflict its own flush creates** (S10-workspace-01, regression of
   PG-230). `load(board:)` checks `refusesToLeaveConflictedBoard()` *before*
   `flushPendingSave()` (`WorkspaceController.swift:250-263`) and then sets
   `saveState = .saved`; selecting a folder strands the board in `.conflicted` with `board == ""`.
   Fix: re-check after the flush, as `settleForVerb()` already does (PG-288).
4. **MCP tool calls run concurrently on one session** (S06-01). `dryRun`, the write journal and
   the command name live on the shared session while the SDK may dispatch calls in parallel
   (`VaultHost.swift:52-55`, `main.swift:47`): a `dryRun: true` call can overlap a real write and
   change its mode. Fix: serialise tool calls on the host actor, or pass the guardrails per call.

## P2 — distinct defects

Security and safety:
- Symlinks inside the vault escape `VaultBoundary.url(for:)` (S03-01 = SEC-07): only the root is
  resolved, `standardizedFileURL` does not follow links; `perg`/MCP read through them, and the
  Contenitore files a dropped symlink as a link. Verified by the coordinator.
- The file-import «Nome file» field reaches `copyItem` without `VaultBoundary` (S01-02).
- Email link text can inject a second markdown link that bypasses `LinkPolicy` (S05-02, suspected).
- `DrawingSVG` accepts `inf`/NaN coordinates and traps on re-encode (S05-03).
- The Contenitore drop folder is read from the vault's own `settings.json`, so a synced vault can
  make the app move files out of any non-home folder (SEC-05, suspected).
- «Apri» in the Contenitore opens any imported file without a type gate or quarantine (S13-01,
  suspected).
- A theme dimension `"nan"`/`"inf"` reaches every layout (SEC-06, suspected).

Correctness:
- URL-scheme capture still raises the app: `.onOpenURL` skips `ForegroundHandBack` and batching
  (S01-04 = SEC-04, regression of PG-132); a URL batch before the vault opens keeps only the last
  route (S01-03).
- «Incolla come testo puro» wipes non-text clipboards (S01-01).
- `performUndo` drops the precondition its preflight computed (S02-02).
- Unpadded/truncated base64 is kept as raw text (S05-04).
- Reminders from a previous launch are never removed (S06-02); `TimeBlockSection` finds
  `## Timeline` by substring and overwrites a look-alike section (S06-03).
- A format-bar press rewrites the whole note, resetting every offset-keyed state (S08-01).
- An unreadable `plaud.json` is overwritten with an empty ledger (S12-01).
- The vault-escape refusal test cannot tell a boundary refusal from a staleness one (T01-tests-01).

Test hygiene that touches the person's real machine (T02-01, T02-02, T06-01, T06-02, T07-tests-01):
- **`~/Library/Preferences` holds 1,122,524 `pergamenum.tests.*.plist` files** (counted by T05;
  listing the folder takes over two minutes). Source: every `.volatile()` store
  (`RecentVaults.swift:36-38`, `OpenTabsStore.swift:47-49`, `PinnedTagsStore.swift:18`) creates a
  `pergamenum.tests.<UUID>` suite that is never removed, and the Stop hook runs the suite every
  turn. Fix in code: `removePersistentDomain(forName:)` on teardown, or an in-memory store.
  Cleaning the existing files is a destructive operation left to Stefano.
- **Unit tests put notes in the real Finder Trash** at nine sites (`trashItem` has no test
  branch, `VaultDisk.swift:440`); two `ContenitorePaneGapTests` sites then permanently delete from
  `~/.Trash` by a guessed name.
- Temp vault folders are never removed (1,488 `pergamenum-pratica-sync-vault-*` and 192
  `pergamenum-pratica-regen-vault-*` in the user temp dir, T05-01; more in T08).

## Cross-cutting themes (P3, worth one change each)

- **Silent read-then-overwrite of hand-editable JSON** (`settings.json`, `plaud.json`,
  `plaud-drafts.json`, theme files): the ADR-0052 "never save over a file you could not read"
  rule is applied to the ledger and boards but not to these stores.
- **Section lookup by substring** in three places (`EventNoteSection`, `TimeBlockSection`,
  Plaud transcript): the class ADR-0065 §D9.3 fixed for `RelatedSection`.
- **UTF-16 vs Character offsets** in wikilink completion (cards and notes): `[[😀…` replaces the
  wrong span.
- **Main-actor disk work per keystroke or redraw**: `saveDraft`, template composer, inspector
  history listing, month view (42 daily notes per reload), `Attachment.byName` whole-vault walk
  from computed properties, quick switcher section lookup, `.eml` drop decode.
- **Stale "RED"/"stub"/"Red until Task N" headers** in about 56 test files whose production code
  has shipped; the 2026-09-11 cleanup (PG-200) covered three.
- **Duplicated test helpers** despite ADR-0051: frontmatter `note(_:)` builder in 10 files,
  session opener in 7, `armedSession` in 4, pratica and recording fixtures (regression of PG-190).
- **Fixed sleeps and wall-clock waits** in about 20 tests (`VaultWatcherTests`,
  `WorkspaceLifecycleTests`, Recordings, `ReleasePipelineTests` watchdog — regression of PG-110).
- **Regressions of closed PG-266** (dead parameters/properties it listed): `PraticaSyncPlan`
  `settings`, `VaultTopBar.theme`, seven DesignGallery properties, `ShortcutCommand` narration.
- **`uitests.sh --affected` under-selects** (X01-01): Tasks changes never pick
  `ComposerUITests`; Diary/Workspace never pick `QuitReviewUITests`.
- **`mcp-smoke.py` without an argument runs another worktree's server** (X01-03).

## Dead code

- Periphery (production only, test targets excluded): 301 results; with tests included: 184.
  The **156-symbol delta is production code kept alive only by tests** (61 in the editor, 37 in
  Core, 19 in Vault, 13 in App). Full list: `2026-10-30-pergamenum-audit-periphery-delta.txt`.
  Most are `#if DEBUG`-less tallies and seams (`OffsetTable.tally`, `StepBuffer.isCounting`,
  `DerivedStateSnapshot`, `UpdaterConfiguration`, `VaultController+Conformance`), plus genuine
  orphans (`Glob.matches*`, `UnlinkedMentions.mentions`, `NoteTree.build`, `MailStoreReader
  .attachments(forMessage:)`, `IndexSnapshot.subtasks/progress`).
- `assignOnlyProperty` hits on Connector/MCP payload structs are mostly false positives
  (Encodable output); the slice reports say which are real.
- The DesignGallery (38 files, 8,534 lines) ships in Release behind Impostazioni ▸ Design
  System by ADR-0051 §D6 — a product decision to revisit, not a defect.
- `.claude/protected-interfaces` is read by nothing (its enforcing script is gone); leftovers of
  the retired chain remain under `.claude/`.

## Contrast (feeds step 3)

The light theme's faint grey `#9C968B` (`text.tertiary`, `task.done`, `task.cancelled`,
`code.comment`) is 2.43–2.94:1 on every background, under the 3:1 floor; the dark theme's
equivalent family is 2.38–2.83:1 on pratica entry backgrounds. Measured replacements:
`#756F65` (4.98:1 on white), `#6F6A61` (5.37:1). Full tables at the end of `2026-10-30-pergamenum-surface-inventory.md`.

## Confirmed sound

ADR-0036 (Mail index only copied and read; all SQL bound), PG-122…PG-129 Tier-1 fixes still in
place, network symbols only in Sparkle and `PlaudHTTPClient`, Sparkle checks only on the menu
action with `SUSendsSystemProfile` false and the checksum enforced, `release.sh` refusals real,
the 49 shared connector sources import Foundation only, no `import SwiftUI` in `Sources/Core`,
time blocks at 24:00 and DST days placed correctly, `vocabolari.json` valid against the tag
grammar, every UI test class sets the isolation flags.

## Appendices

- A: every finding, verbatim from the slice reports, grouped by severity (below).
- `2026-10-30-pergamenum-surface-inventory.md`: every pane, sheet, menu, toolbar and shortcut,
  plus the non-token colour/font/size tables and the UI-test map — input for steps 2 and 3.
- `2026-10-30-pergamenum-audit-periphery-delta.txt`: test-only-alive production symbols.


# Appendix A — all findings

## P1 (5)

### S02-01 — A `settings.json` that will not read or decode is silently replaced by defaults with a new vault id, orphaning the state directory
- Where: `Sources/Vault/VaultSession+Identity.swift:31-33`, `Sources/Vault/VaultSession+Identity.swift:35-37`, `Sources/Vault/VaultSession+Identity.swift:53-62`, `Sources/Vault/VaultSession.swift:248-252`
- Category: correctness
- Severity: P1 · Confidence: confirmed
- In flight: no
- What: `readSettings` answers `.default` both when the file cannot be read (31-33, with no problem recorded) and when it will not decode (35-37, problem recorded). `.default` carries `vaultID == nil`, so `resolveIdentity` mints a fresh UUID and `writeSettings` (60, 77-89) atomically overwrites `.pergamenum/settings.json` with the defaults plus the new id, and the session is built on that id (`VaultSession.swift:252`): `history/`, `ai-journal/`, `cache.db` and `thumbnails/` of the old state directory are orphaned (not deleted, but the non-rebuildable history and journal are no longer the vault's), and every per-vault setting the person typed (daily and diary folders, patron saint, Pratiche and Contenitore settings, inbox folder, daily template) is gone from disk. The doc comment at 25-26 promises the opposite ("The file is not overwritten on a decode failure, so the user can repair it by hand"), and `VaultSettings.swift:130-131` names orphaning the derived stores as the harm the id exists to prevent. Same shape as PG-261 items 1-2 (`CategoryRegistryStore`, `StarredStore`), in a file chain 8 does not list.
- Trigger: a hand edit the file is documented to invite (`VaultSettings.swift:249-250`) with one wrong type, e.g. `"rollover": "yes"` → `typeMismatch` thrown at `VaultSettings.swift:262` → the whole file is discarded → the next launch rewrites `settings.json` with defaults and a new `vaultID`; every note's version history is empty from then on and the configured folders are back to `Calendar`/`Diario`/`00 Inbox`. The same from `SpellCheck.init(from:)` on a non-string (`VaultSettings.swift:33`, against its own comment at 28-31), or from a transient read failure (iCloud eviction, permissions) at 31, which additionally reports nothing.
- Fix: make "exists but unreadable or undecodable" a state distinct from "absent" (the `NoteIDStore`/`CategoryRegistryStore.LoadedState` shape): in that state never call `writeSettings`, resolve the id from `pathDerivedID(for:)` (or decode `vaultID` alone, leniently) and record the problem; carry the state on the session so `updateSettings` (`VaultSession.swift:469-483`) refuses to write over a file that was not loaded (ADR-0052's marker); record a problem on the unreadable branch too.
- Tracked: none

### S05-01 — Raw MIME filename appended to Mail's `Attachments/` directory: arbitrary local file read into the vault
- Where: `Sources/Core/Email/MIMEDecoder.swift:72`, `Sources/Core/Email/EMLXReader.swift:114`, `Sources/Features/Pratiche/PraticaSyncEngine+Messages.swift:118`, `Sources/Features/Pratiche/PraticaSyncEngine+Attachments.swift:40`
- Category: security
- Severity: P1 · Confidence: confirmed
- In flight: no
- What: `MIMEDecoder.leaf` takes the `filename`/`name` parameter verbatim (RFC 2231 percent-decoded included) and, when the inline payload decodes to zero bytes (ADR-0048), `resolveExternalized` appends it unsanitised to `EMLXReader.attachmentsDirectory(...)` with `.appending(path: name, directoryHint: .notDirectory)` and then runs `resourceValues` and `Data(contentsOf:)` on the result. A `../` name escapes the part directory; an unknown extension gets `.usable` from `AttachmentIntegrity.verdict`, so the bytes are placed into the pratica's `allegati/` (under threshold), or the traversed path is written into the message note as a `StoreReference` `storePath` (over threshold: path disclosure). Previously described in the 2026-09-11 audit as P2 at the pre-split `PraticaSyncEngine.swift:758` ("ACTION REQUIRED — not auto-fixed"), never given a PG id; the code is unchanged after the file split.
- Trigger: a message that matches a pratica's `MembershipRule` (sender/mailbox bound by the user) carries a part `Content-Disposition: attachment; filename="../../../../../../../Users/<user>/.ssh/id_rsa"` (or `filename*=UTF-8''%2e%2e%2f...`) with an empty base64 body → the next automatic sync copies the private key into the vault (and, per principle 6, into iCloud Drive) as `YYYYMMDD_id_rsa`, with no user action.
- Fix: make `attachmentsDirectory` take the name and return the file URL: `lastPathComponent`, refuse `..`, `.`, empty and NUL after it, then a standardized-path prefix check against the part directory before any filesystem call, so no caller can route around it (`vault-writes.md` first rule). Sanitise at `MIMEDecoder` too.
- Tracked: none

### S06-01 — MCP tool calls run concurrently on one session, so `dryRun`, the journal and the command name are shared between calls in flight
- Where: `Sources/MCPServer/VaultHost.swift:52-55`, `Sources/MCPServer/VaultHost.swift:188`, `Sources/MCPServer/main.swift:47`, `Sources/Connector/VaultWrites.swift:30-34`, `Sources/Connector/VaultWrites.swift:45-48`
- Category: correctness
- Severity: P1 · Confidence: confirmed
- In flight: no
- What: The MCP SDK handles every incoming request in its own unstructured `Task` (`Server.swift:234-237`, its comment: "Handle request in a separate task to avoid blocking the receive loop"), and `main.swift:47` hands each one straight to `host.call`, which is `@MainActor` but suspends at `await session.rescan()` (`:53`) and inside every real write. `VaultAPI.arm` (`VaultWrites.swift:31-33`) stores `isDryRun`, `journalCommand` and `journal` on the one `VaultSession`, so a second call arming during the first call's suspension rewrites the first call's guardrails mid-flight: `VaultSession.write` (`VaultSession.swift:657`) and its journal descriptor (`:667-668`) read them per write, and `summarise` reads `isDryRun` after the write's `await` returns (`VaultWrites.swift:48`). Traced consequences: a real single write whose neighbour armed a rehearsal replies `applied: false` with an empty diff, so the model re-sends it (a duplicated append); a multi-file verb that started real (`rename_note`, `move_note`, `classify_note`, `undo_write` of an operation, every `pratica_create_*`) finishes as a rehearsal, its later files unwritten and unjournalled while the first ones changed, so `undo_write` cannot put it back. The opposite direction (a rehearsal whose later writes turn real under the other call's command name) needs a dry-run path that still awaits before its writes; not traced. ADR-0007 §D6's lock holds per call, not per session.
- Trigger: a client that batches tool calls (this harness does) sends `rename_note{path, title, dryRun:false}` and `add_task{…}` (dryRun omitted) in one turn → the second call's `arm` runs while the first awaits the disk actor → the rename's remaining link rewrites return a `WriteResult` without touching disk, nothing is journalled for them, and the reply reports the rename as not applied.
- Fix: serialize `VaultHost.call` (and `resources(after:)`/`resource(at:)`) behind one in-flight call at a time, an `AsyncSerialQueue`/`Task` chain owned by the host, since the SDK's per-request `Task` is the SDK's choice and the guardrails are session-global by design; or hand `dryRun`/`journal` down as a per-call context instead of session state. Add a `scripts/mcp-smoke.py` stage that fires two writes without waiting between them.
- Tracked: none

### S10-workspace-01 — Leaving a board drops a conflict that the leave's own flush creates
- Where: `Sources/Features/Workspace/WorkspaceController.swift:250`, `Sources/Features/Workspace/WorkspaceController.swift:262-263`, `Sources/Features/Workspace/WorkspaceController.swift:275`, `Sources/Features/Workspace/WorkspaceController.swift:309`, `Sources/Features/Workspace/WorkspaceController.swift:321-328`, `Sources/Features/Workspace/WorkspaceController+Saving.swift:29-33`
- Category: correctness
- Severity: P1 · Confidence: confirmed
- In flight: no
- What: `load(board:)` and `select(_:)` check `refusesToLeaveConflictedBoard()` first, then run `settleBoardEditing()` and `flushPendingSave()`. That flush is synchronous and can itself end in `enterConflicted` (refused write, reconcile says `.diverged`, `+Saving.swift:98-101`), but neither function checks again. `load` goes on to replace `document` with the new board and set `saveState = .saved` (`:275`), so the unsaved edits, including a card text draft that `settleBoardEditing()` only just committed, are dropped. A Problemi line is recorded, but the bytes are gone. `select`'s folder/nil branch is worse: it replaces `document` with `.empty` and sets `board = ""` while `saveState` stays `.conflicted`. `BoardTopBar` is always drawn (`WorkspaceView.swift:143`), so «Mantieni le mie modifiche» and «Ricarica dal disco» are still offered, but both call `store.read(board: "")` and fail (`+Conflict.swift:16`, `:34`). Every later `load`/`select` is refused by the guard, so the Workspace pane is stuck until the vault is detached or the app relaunches. `settleForVerb()` (`+Lifecycle.swift:119-124`) already re-checks after the flush for this reason (PG-288). `load`/`select` were not given the same re-check. PG-230 added the guard for a conflict that already exists, not for one created by the leave's own flush. Severity note for the merger: the loss needs a concurrent external writer to the same `.canvas` inside the unsaved window, and it is limited to edits since the last successful autosave plus the draft the settle commits. Regrade to P2 if a concurrent external writer is judged unlikely in daily use.
- Trigger: edit a card on board A (or leave a text card in edit), and within the ~1 s autosave window let another writer change `A.canvas` in a way reconciliation cannot merge (`pergamenum-mcp --allow-write`, `perg`, an iCloud sync, a second app). Then click board B in the tree: the edits on A are discarded and B opens showing "Salvato". Or click a folder row: the tool column and board disappear, the pane shows the empty state under a «Conflitto» top bar whose two buttons do nothing but add Problemi lines, and no board can be opened again.
- Fix: in both functions, check the guard again after `flushPendingSave()` and return before anything is replaced, the order `settleForVerb()` uses. For example, route both through `settleForVerb()`.
- Tracked: regression of PG-230

### SEC-01 — An email's attachment filename walks out of Mail's `Attachments/` folder, and the file it names is copied into the vault
- Where: `Sources/Features/Pratiche/PraticaSyncEngine+Messages.swift:115`, `Sources/Features/Pratiche/PraticaSyncEngine+Messages.swift:133`, `Sources/Features/Pratiche/PraticaSyncEngine+Messages.swift:179`, `Sources/Features/Pratiche/PraticaSyncEngine+Messages.swift:192`, `Sources/Features/Pratiche/PraticaSyncEngine+Messages.swift:261`, `Sources/Features/Pratiche/PraticaSyncEngine+Attachments.swift:37`, `Sources/Core/Email/EMLXReader.swift:114`, `Sources/Core/Email/MIMEDecoder.swift:72`
- Category: security
- Severity: P1 · Confidence: confirmed
- In flight: no
- What: `MIMEDecoder` takes the part's `filename`/`name` parameter verbatim (RFC 2231 `filename*` is percent-decoded, so `%2F` becomes `/` too) and `resolveAttachment` passes it as `name` to `resolveExternalized`, which appends it with `appending(path:)` under `Attachments/<rowID>/<part>/` and never checks the result stays there. When the inline payload decodes to zero bytes (verdict `.empty`, ADR-0048), the resolved path is stat'ed, read with `Data(contentsOf:)`, judged by `AttachmentIntegrity` (an unknown format is `.usable` on non-emptiness alone) and placed in the pratica's `allegati/` under a sanitised name; over the size threshold the escaped absolute path is recorded as `storePath` instead. Only the destination name is sanitised (`PraticaNaming.attachmentFileName`); the source path is not. The inline-image branch does the same with `part.filename ?? "\(contentID).png"`. The app holds Full Disk Access for Mail's store, so any file the user can read is reachable. Provenance: the 2026-09-11 audit raised the `storePath` half as `security-PraticaSyncEngine.swift-ce5` (`docs/deep-refactor/2026-09-11-pergamenum-audit.md:1034`, read as an excerpt) and it never received a PG id; ADR-0048's `resolveExternalized` has since turned a recorded path into a read-and-copy.
- Trigger: an email in a tracked thread with a part `Content-Disposition: attachment; filename="../../../../../../../../../Users/<u>/.ssh/id_ed25519"` and an empty base64 body → the next sync copies the private key into `<pratica>/allegati/<date>_id_ed25519`, inside a vault that may sync to iCloud and that the MCP connector serves to a model.
- Fix: reduce `name` to a single path component before it touches the filesystem (the same `lastPathComponent` + separator scrub `PraticaNaming.attachmentFileName` applies, or refuse a name containing `/`, `..` or NUL), and in both `resolveExternalized` and `storePath` assert the standardized result is inside `attachmentsDirectory(forMessageAt:rowID:part:)` (a `VaultBoundary`-shaped resolver rooted there).
- Tracked: none

## P2 (27)

### S01-01 — «Incolla come testo puro» replaces the clipboard with its own plain text, or with nothing
- Where: `Sources/App/CommandActions.swift:399-403`
- Category: correctness
- Severity: P2 · Confidence: confirmed
- In flight: no
- What: `pastePlain()` reads the pasteboard's `.string` representation, clears the whole pasteboard, writes that string back and only then sends `NSText.paste`. Every other representation on the clipboard (RTF, HTML, file URLs, an image) is destroyed by the clear, and when the clipboard holds no string at all the `?? ""` fallback wipes it and leaves an empty string behind, so the next ordinary Cmd+V in any app pastes nothing. `let plain = NSPasteboard.general.string(forType: .string) ?? ""` is the line.
- Trigger: copy an image in Anteprima, Cmd+Shift+Opt+V in a note → nothing is inserted and the clipboard now holds `""`; copy formatted text from Mail, Cmd+Shift+Opt+V → the note gets the text and every other app has lost the RTF.
- Fix: insert the string through the responder chain without touching the pasteboard (`NSTextView.insertText(_:replacementRange:)` on the first responder, as the format-bar commands already do), or at least `guard let plain = …string(forType: .string) else { return }` and restore the saved `pasteboardItems` after the paste.
- Tracked: none

### S01-02 — The import commit copies to a name the person can edit, resolved without `VaultBoundary`
- Where: `Sources/App/VaultController+Import.swift:55-65`, `Sources/App/FileImportSheet.swift:35`
- Category: security
- Severity: P2 · Confidence: confirmed
- In flight: no
- What: `commitImport` builds the destination as `directory.appending(path: proposal.proposedName, directoryHint: .notDirectory)` and hands it straight to `FileManager.createDirectory`/`copyItem`. Nothing resolves it through `VaultBoundary.url(for:)` (the only door the house rules allow for a vault-relative URL, ADR-0041, `.claude/rules/vault-writes.md`) and nothing re-sanitises the name after `proposeImport` proposed it through `ImportNaming.sanitizedFileName`/`uniqueFileName`, yet the sheet's `TextField("Nome file", text: $proposal.proposedName)` lets the person replace that name with anything. `createDirectory` creates the inbox folder, not the destination's parent, so a name with `..` components reaches `copyItem` and is resolved by the file system outside the inbox and outside the vault. The returned relative path (`"\(folder)/\(proposal.proposedName)"`) then names a file the vault does not contain.
- Trigger: File ▸ Importa file…, pick any file, change «Nome file» to `../../Desktop/x.pdf`, Importa → the file is written on the Desktop, nothing is recorded as a problem, the index never sees it.
- Fix: at commit, resolve `destination` with the session's `VaultBoundary` (`try boundary.url(for: "\(folder)/\(name)")`) and refuse a name containing a path separator or `..`; run the edited name through `ImportNaming.sanitizedFileName` again before building the URL, and keep `uniqueFileName` so an edited name cannot overwrite an existing file (`copyItem` fails on an existing destination today, which is the only guard left).
- Tracked: none

### S01-03 — A route that arrives before the vault is open is parked in a single slot, so a batch keeps only the last one
- Where: `Sources/App/VaultController+Routes.swift:43,203`, `Sources/App/VaultController.swift:326-327`, `Sources/App/PergamenumApp.swift:107-125`
- Category: correctness
- Severity: P2 · Confidence: confirmed
- In flight: no
- What: `perform` parks a route that arrives with no open vault (or while `isOpeningVault` is set) in `routeState.pending`, declared `var pending: PergamenumRoute?`, and `open(_:)` replays that one value. `application(_:open:)` receives the whole batch of URLs at once and performs them in a loop, so each parked route overwrites the previous one and only the last survives; the earlier ones are neither performed nor logged, and `perform` has already returned `true` for them.
- Trigger: app not running (the vault reopens from recents on launch), `open 'pergamenum://capture?text=a' 'pergamenum://capture?text=b'` or a Raycast script firing two captures → only `b` is captured, `a` is lost silently.
- Fix: make `pending` an array appended in arrival order and drained by `open(_:)` in that order, and log the parked count through `routeLog`.
- Tracked: none

### S01-04 — Two URL entry points, one hand-back: the `.onOpenURL` path skips `ForegroundHandBack` and batching, and the two comments contradict each other
- Where: `Sources/App/PergamenumApp.swift:6-11,107-125,415-422`
- Category: correctness
- Severity: P2 · Confidence: suspected
- In flight: no
- What: `pergamenum://` links are still handled in two places. The delegate's `application(_:open:)` parses the whole batch, performs it in one `Task` and, when every route says `raisesApp == false`, calls `foreground.handBack()` (PG-132). The scene's `.onOpenURL` (419-422) parses and performs one URL at a time with neither the batch nor the hand-back. The header comment (6-11) says the delegate is the path that runs; the comment above `.onOpenURL` (415-418) says the delegate "is never called in a SwiftUI app that has a WindowGroup", but the scene is `Window("Pergamenum", id: "main")` (346), not `WindowGroup`. Whichever path AppKit takes on macOS 27, one of the two is dead and the other may be the one without the hand-back, in which case a capture fired from another app raises Pergamenum, the SPEC §9 rule PG-132 was closed for. PG-132's own closing note records the hand check ("capture from another app leaves that app in front") as still owed.
- Trigger: with another app frontmost, fire `pergamenum://capture?text=x`; if the `.onOpenURL` branch is the live one, Pergamenum comes to the front. Not run in this audit (no builds, no hand checks).
- Fix: route both entry points through one `handle(urls:)` that parses, batches, performs and hands back, so `raisesApp` is consulted in one place; after the owed hand check, delete the entry point that does not fire and the comment that is wrong.
- Tracked: regression of PG-132

### S02-02 — `performUndo` writes without the precondition the preflight computed, so an undo can overwrite a save that landed between the check and the write
- Where: `Sources/Vault/VaultSession+Journal.swift:391`, `Sources/Vault/VaultSession+Journal.swift:393`, `Sources/Vault/VaultSession+Journal.swift:401`, `Sources/Vault/VaultSession+Journal.swift:312`, `Sources/Vault/VaultSession+TagRename.swift:137-140`
- Category: correctness
- Severity: P2 · Confidence: confirmed
- In flight: no
- What: `undo(operation:)` (293) and `undoJournalledWrites` (`+TagRename.swift:137-140`) run `preflightUndo` (312) over every entry on the main actor — hash still equals `hashAfter`, a removal's path still free — and then `performUndo` (376) writes each entry with `write(textBefore, to:)`/`writeFile(textBefore, to:)` and no `expecting:`/`expectingAbsent:` (391, 393, 401), although both doors take them (`+Journal.swift:237-239`, `VaultSession.swift:651`) and every other write site in the slice passes one. A check made before the `await` is a filter, not a guard (`.claude/rules/vault-writes.md`, ADR-0043 §D7); the doc at 374 accepts the window as "the same narrow window D4 accepts", but for a multi-entry gesture the window of the last entry spans every earlier write and journal append, and the hash that would close it is already in `entry.hashAfter`.
- Trigger: `perg undo <op>` (or the MCP `undo` tool) on a rename gesture while the app autosaves one of the rewritten notes: the preflight passes for all N entries, the app's save lands during the first k writes, entry k+1's `write(textBefore)` replaces the saved text with the journal's `textBefore` and the edit is lost. For a `.removal` entry, a note recreated at that path between check and write is overwritten. In-app «Annulla» of a task or board drop takes the same door (`+TagRename.swift:140`), with a narrower window.
- Fix: `.textReplacement` → `expecting: entry.hashAfter` on both doors; `.removal` → `expectingAbsent: true`; report the resulting `VaultWriteRefusal` in `failures` by entry, as `VaultPlanApplication.apply` already classifies it. `.move` has no precondition on `moveFile(from:to:)` (75-82) today; `FileManager.moveItem` refuses an occupied `pathBefore` and an edit made meanwhile travels with the file, so the two text kinds are the ones that lose data.
- Tracked: none

### S03-01 — `VaultBoundary.url(for:)` lets a symlink inside the vault reach outside it
- Where: `Sources/Core/Vault/VaultBoundary.swift:21`, `Sources/Core/Vault/VaultBoundary.swift:46-54`, `Sources/Core/Vault/VaultBoundary.swift:66-72`, `Sources/Core/Conventions/Attachment.swift:147-148`
- Category: security
- Severity: P2 · Confidence: confirmed
- In flight: no
- What: only the root is passed through `resolvingSymlinksInPath()` (`:21`); the candidate built in `url(for:)` is `standardizedFileURL`-ed, which collapses `..` but leaves a symlink in place, and `isInside` is a string-prefix test on that unresolved path. A symlink `vault/esc -> /outside` therefore makes `url(for: "esc/x.md")` pass the guard while reads and writes land outside the root. Verified with a ten-line Foundation script in the scratchpad (no repo build): the URL returned is `<root>/esc/target.txt`, `isInside` answers true, the real target is outside, and the bytes read came from the outside file. `Attachment.byName` (`:147-148`) does resolve its match before the same prefix test, so the two doors already disagree on what "inside" means; the type's own doc (`:26-28`) says the check exists so that user-supplied text (URL scheme, wikilinks) cannot write outside the vault.
- Trigger: a symlink planted in the vault (local write access, an unpacked archive, a folder someone linked in by hand) + `pergamenum://note?file=esc/x.md`, a `[[esc/x]]` link or a connector write to that path → the write goes to `/outside/x.md`, reported as inside the vault.
- Fix: decide the policy once: either resolve the candidate (`resolvingSymlinksInPath()`) before `isInside`, refusing a link that leaves the root, as `byName` already does; or document symlinked folders as deliberately part of the vault and make `byName` stop refusing them. Either way the two doors must agree.
- Tracked: none (`PG-261`, open, is the symlinked *root* and `VaultWatcher`, a different defect)

### S05-02 — Hostile `<a>` text injects a second markdown link that bypasses `LinkPolicy`
- Where: `Sources/Core/Email/HTMLTextReducer.swift:293`, `Sources/Core/Email/HTMLTextReducer.swift:319`, `Sources/Core/Markdown/MarkdownInline.swift:322`
- Category: security
- Severity: P2 · Confidence: suspected
- In flight: no
- What: `close("a")` checks `LinkPolicy.isOpenable(href)` on the href but emits the link text from `popBuffer()` unescaped as `[\(text)](\(href))`. The re-parser takes the first `]` as the label end (`rest.dropFirst().range(of: "]")`), so text containing `](scheme:...)` becomes the effective target and the policy check is void. The sink that opens it is the 2026-09-11 audit's `MarkdownBlocksView.swift:252` item (raw target, system open); whether it is still unfixed was not re-checked here, hence suspected. `appendImage` has the same shape with `alt` but its target is constrained to `cid:`.
- Trigger: email HTML `<a href="https://ok.example">x](pergamenum://...)</a>` → message note contains `[x](pergamenum://...)](https://ok.example)` → rendered as a link to `pergamenum://...`, which `LinkPolicy` would have refused.
- Fix: escape `\`, `[`, `]` in link text and alt, and `(`, `)`, spaces in href (or angle-bracket the target) at emission, per ADR-0077's "escape once, at emission".
- Tracked: none

### S05-03 — DrawingSVG accepts `inf`/huge/NaN coordinates and traps on re-encode
- Where: `Sources/Core/Canvas/DrawingSVG.swift:107`, `Sources/Core/Canvas/DrawingSVG.swift:129`, `Sources/Core/Canvas/DrawingSVG.swift:175`
- Category: security
- Severity: P2 · Confidence: confirmed
- In flight: no
- What: path tokens and `stroke-width` are parsed with `Double(token)`, which accepts `inf`, `-inf`, `nan` and `1e300`. `number()` then does `String(Int(rounded))` when `rounded == rounded.rounded()`: true for ±inf and for magnitudes beyond `Int.max`, and `Int(_:)` traps. NaN does not trap there (`nan == nan` is false, falls to `String(format:)`) but propagates into stroke bounds. Encode runs from `WorkspaceController+Drawing.swift:64` when the drawing is saved after an edit.
- Trigger: an `.svg` containing `pergamenum-drawing` with `M 0 0 L 1e300 5` dropped into the vault (e.g. received as an attachment) and opened on a board, then any stroke added → crash on save.
- Fix: reject non-finite and out-of-range values at decode (`guard value.isFinite, abs(value) < limit`), and make `number()` safe on its own (format through `Double` formatting, never `Int(_:)`).
- Tracked: none

### S05-04 — Unpadded or truncated base64 falls back to the raw encoded bytes
- Where: `Sources/Core/Email/MIMEDecoder.swift:214`
- Category: correctness
- Severity: P2 · Confidence: confirmed
- In flight: no
- What: `Data(base64Encoded: data, options: .ignoreUnknownCharacters) ?? data` returns the still-encoded text when Foundation refuses the input; Foundation returns nil for unpadded input and for a quantum cut mid-way (probe-checked). The attachment is then the base64 text itself (`.usable` for any format `AttachmentIntegrity` does not know), or a body of base64 garbage via `decodeText`. `EncodedWord.decodeToken` already normalises padding (ADR-0065 §D7.3); the body path does not.
- Trigger: a part whose base64 body lacks trailing `=` (common from some mailers) or a message truncated mid-line → a `.txt`/`.ics`/unknown attachment written into `allegati/` containing base64 text, or a message note whose body is base64.
- Fix: strip whitespace, pad to a multiple of 4 (drop a trailing lone char), decode; on failure return nil and let the integrity verdict mark the part pending/truncated rather than substitute raw bytes.
- Tracked: none

### S06-02 — Reminder requests from a previous launch are never removed, so a deleted or shifted task keeps its notification
- Where: `Sources/Calendar/ReminderScheduler.swift:207-211`, `Sources/Calendar/ReminderScheduler.swift:311`, `Sources/Core/Tasks/TaskItem.swift:82`
- Category: correctness
- Severity: P2 · Confidence: confirmed
- In flight: no
- What: `reschedule` removes only the identifiers in `scheduledIDs`, an in-memory set that is empty at every launch (`:210-211`), then adds one request per current task under `identifier: task.id` (`:311`). A request the previous process scheduled is replaced only if a task with the same id still exists, and `TaskItem.id` is `sourcePath#lineIndex` (`TaskItem.swift:82`): a task deleted, completed by another tool or merely shifted by one line while the app was closed leaves its old request pending, and the shifted one gets a second request under its new id. The launch-time `.task(id: reminderKey)` (`PergamenumApp.swift:393-404`) says the scheduler "replaces its pending notifications wholesale", which is true only within one process; `pendingCount` (`:238-241`) counts the orphans without naming them. Nothing in `Sources/` calls `removeAllPendingNotificationRequests` or seeds `scheduledIDs` from `pendingNotificationRequests()`.
- Trigger: `- [ ] Chiamare Rossi @remind(2026-11-02 09:00)` → quit → delete that line, or insert a line above it, in Obsidian or with `perg` → relaunch → at 09:00 the notification fires for a task that no longer exists (twice for the shifted one), and tapping it routes to a line that now holds something else.
- Fix: on a process's first `reschedule`, remove every pending request before adding (all pending requests are this scheduler's own: `removeAllPendingNotificationRequests()` on `ReminderRequestQueue`, or `pendingNotificationRequests()` filtered to ids absent from the new set), then keep the in-process diff as it is.
- Tracked: none (PG-270 and PG-353, closed, changed the reschedule key and the queue seam, not the cross-launch set)

### S06-03 — `TimeBlockSection` finds its section by substring, so `### Timeline` or `## Timeline riunione` is read as the plan and overwritten by it
- Where: `Sources/Calendar/TimeBlock.swift:139`, `Sources/Calendar/TimeBlock.swift:187`, `Sources/Calendar/TimeBlock.swift:201`
- Category: correctness
- Severity: P2 · Confidence: confirmed
- In flight: no
- What: `parse` and `write` locate the section with `body.range(of: heading)`, the first occurrence of the characters `## Timeline` anywhere in the note, not a heading line. A `### Timeline` sub-heading, a `## Timeline riunione` heading or the literal inside a code fence all match (`parse` never skips fences either). `parse` then reads that section's `- 10:00-11:00 …` lines as the day's blocks, and `write` replaces `sectionRange.lowerBound..<next heading` with the rendered plan (`:201`): the heading's suffix and whatever list stood under it are gone, and a `### Timeline` keeps a stray leading `#`. The author of `write` already met the "section ran to the end of the note" variant (PG-318, comment at `:182-185`); the anchor itself was not changed.
- Trigger: a daily note holding `## Timeline riunione` followed by `- 10:00-11:00 Kick-off cliente` and no real `## Timeline` section → drag a task onto the day → the note comes back with the meeting section replaced by `## Timeline` and the block list.
- Fix: anchor on a whole trimmed line equal to `## Timeline`, outside fenced blocks, in one shared range function that `parse` and `write` both use.
- Tracked: none

### S08-01 — A format-bar press rewrites the whole note, so every offset-keyed state inside it is dropped (callout flips revert)
- Where: `Sources/Features/Editor/CompletingTextView+FormatBar.swift:148`, `Sources/Features/Editor/CompletingTextView+FormatBar.swift:152-158`
- Category: correctness
- Severity: P2 · Confidence: confirmed
- In flight: no
- What: `applyFormat` hands `InlineFormat.toggled/wrapped`'s whole-note result to `replaceWholeText`, which calls `replaceCharacters(in: whole, …)`. The storage reports one edit whose old range is the entire note; `StorageEdit.shiftedKeys` drops every key strictly inside the old range, so `recordStorageEdit` → `folding.shiftFlips` (runs even under the kill switch) leaves only offset 0 in `toggledCallouts`, and `takeMovedFlips` reports that loss to the tab (`NoteTab.toggledCallouts`). The same edit empties `foldedHeadings`, `tableViews`, `viewBlockHosts`, `renditions` and `embedRenditions` in `EditorDecorationDelegate.shift(by:)` (`EditorDecorationDelegate.swift:939`), forcing a full restyle, a rebuild of every grid/view-block host (view-block queries re-run) and a re-measure of every transclusion: the ADR-0094 step model is bypassed on the one edit path that writes everything.
- Trigger: flip a callout's fold (title chevron), select a word anywhere else in the note, press Grassetto → the callout is back to its default fold state; a note with a `pergamenum-view` fence re-runs its query on every format-bar press.
- Fix: replace only the changed span (compute the common prefix/suffix of old and new text, or have `InlineFormat` return the edited range) inside one `shouldChangeText`/`didChangeText` pair, so undo stays one step and the storage edit is local.
- Tracked: none

### S11-01 — A raw MIME attachment name steers a Mail-store read outside the message's attachment directory, and is persisted as `storePath`
- Where: `Sources/Features/Pratiche/PraticaSyncEngine+Messages.swift:115-117,121,133,179`, `Sources/Features/Pratiche/PraticaSyncEngine+Attachments.swift:37-43`, `Sources/Features/Pratiche/AttachmentChipModel.swift:188`
- Category: security
- Severity: P2 · Confidence: confirmed
- In flight: no
- What: `resolveExternalized` appends the `Content-Disposition` filename verbatim (`Sources/Core/Email/MIMEDecoder.swift:72` → `MIMEParameter.value`, whose doc says the value "comes back verbatim") to `EMLXReader.attachmentsDirectory(...)`, stats it, and on `size > 0` reads it with `Data(contentsOf:)` and hands the bytes to the copy into `allegati/` under the sanitised name. Only the written name is reduced to `lastPathComponent` (`PraticaNaming.attachmentFileName`); the read path is not. `storePath(of:at:rowID:part:)` does the same append, keeps any path that exists, and the result is written into the note's `pergamenum-mail-store-references` and later turned into `URL(fileURLWithPath: reference.storePath)` for «Apri»/«Mostra nel Finder».
- Trigger: a message in a followed conversation whose part Mail externalised (the inline payload decodes to zero bytes, `:192-210`) and whose filename is `../../../../../../etc/passwd`, or `../../../../.ssh/id_rsa` relative to `…/Attachments/<row>/<part>/` → the sync copies that file's bytes into the pratica's `allegati/` as `YYYYMMDD_passwd` (if `AttachmentIntegrity.verdict` accepts the bytes for the declared type), or, over the size threshold, records the traversal path as the attachment's `storePath`. Not graded P1: the copy lands in the person's own vault and the app has no outbound channel; the 2026-09-11 audit graded the `storePath` half P2 (risk low) and it never received a ledger id.
- Fix: reduce `name` to `(name as NSString).lastPathComponent` (refusing an empty or `..` result) before both appends, and accept the resolved URL only when `url.standardizedFileURL.path` has the attachments directory as a prefix; one helper shared by `resolveExternalized` and `storePath`.
- Tracked: none (named in `docs/deep-refactor/2026-09-11-pergamenum-audit.md` as `security-PraticaSyncEngine.swift-ce5`, "ACTION REQUIRED — not auto-fixed", absent from TODO.md)

### S12-01 — A plaud.json that fails to decode is overwritten with an empty ledger plus one entry
- Where: `Sources/Features/Recordings/PlaudVaultStore.swift:151`, `Sources/Features/Recordings/PlaudVaultStore.swift:163`, `Sources/Features/Recordings/RecordingsController+Ledger.swift:21`, `Sources/Features/Recordings/RecordingsController+Ledger.swift:55`, `Sources/Features/Recordings/RecordingsController+Interface.swift:94`
- Category: correctness
- Severity: P2 · Confidence: confirmed
- In flight: no
- What: `loadLedger()` maps both "file absent" and "file present but undecodable/unreadable" to `.empty` (`guard let data = try? Data(contentsOf:), let ledger = try? JSONDecoder().decode(...) else { return .empty }`), contrary to its own doc comment (l.146-150) promising never to touch a corrupt file. The next `record(_:for:)` or `updateDays` calls `saveLedger(ledger)` with `.empty` plus one change, atomically replacing the file: every other recording's fingerprints, `pendingConfirmation`, status and `notePath` are lost, so already-imported tasks become importable again (duplicates) and pending confirmations are never sent. The file lives in `~/Library/Application Support/it.stefer.pergamenum/vaults/<id>/` (not iCloud), and the code explicitly says it is "meant to be readable and editable by hand" (l.58-60). `loadDrafts` (l.173-178) has the same shape for review drafts. The ADR-0052 load-origin pattern used for the Pratiche ledger is missing here.
- Trigger: hand-edit `plaud.json` leaving a trailing comma → open Registrazioni (ledger reads as empty) → import any recording or change «Giorni» → file rewritten with one entry; all prior import history gone.
- Fix: return a load outcome (absent / decoded / unreadable); remember it and refuse `saveLedger`/`saveDrafts` over a file that existed but did not decode, surfacing an Italian error (or move the bad file aside first).
- Tracked: none

### S13-01 — «Apri» hands any imported file to NSWorkspace with no type gate and no quarantine stamp
- Where: `Sources/Features/Contenitore/ContenitoreCommand.swift:290`
- Category: security
- Severity: P2 · Confidence: suspected
- In flight: no
- What: `open(_:)` (`:290-296`) resolves the companion and calls `contenitore.openFile(url)`, which is `NSWorkspace.shared.open` (`ContenitoreController.swift:94`). No `UTType` check exists anywhere in `Sources/Features/Contenitore` or `Sources/Core/Contenitore` except the extractor's, and nothing in the slice calls `AttachmentQuarantine`. Files arrive from an arbitrary drop folder (iCloud-synced supported: `DropFolderListing.swift:101-102` requests `.isUbiquitousItemKey`) and are moved in by `adoptFromOutside` (`VaultSession+Adopt.swift:43-56`, `moveItem`), so whatever xattrs they carried travel, none are added. A `.command` file written without quarantine (sync client, `cp` from a script, unzip tool) is launched by «Apri» or a double-click. Same shape as PG-123 (P1, Pratiche attachments; PG-155 the `.eml` sidecar, both closed). Whether the source xattr survives the move is not verifiable from source.
- Trigger: a file without `com.apple.quarantine` dropped in the drop folder, then «Apri» (or the grid's double-tap, `ContenitoreGrid.swift:88-89`).
- Fix: reuse `Sources/Core/Email/AttachmentQuarantine.swift` (stamp at import in `ContenitoreIngestEngine.importFile`) and gate «Apri» by type as `AttachmentChip.swift` does; record it in ADR-0071.
- Tracked: none

### SEC-02 — `storePath` read back from a message note's frontmatter is opened by `NSWorkspace` with no check that it lies in Mail's store
- Where: `Sources/Core/Pratiche/MessageDocument+Reading.swift:99`, `Sources/Features/Pratiche/AttachmentChipModel.swift:183`, `Sources/Features/Pratiche/AttachmentChipModel.swift:95`, `Sources/Features/Pratiche/AttachmentChip.swift:222`
- Category: security
- Severity: P2 · Confidence: confirmed
- In flight: no
- What: `storeReferences(in:)` parses `name`/`size`/`storePath` from the note's `pergamenum-mail-store-references` frontmatter with no path constraint, `targetURL` turns `storePath` into `URL(fileURLWithPath:)`, and «Apri»/double-click hands it to `NSWorkspace.shared.open` gated only by the UTI denylist in `refusesToOpen`. The note is an ordinary vault file: a hand edit, a synced copy, an MCP write with `--allow-write`, or SEC-01's over-threshold branch can point it anywhere on disk. The same untracked audit note (`security-PraticaSyncEngine.swift-ce5`) names the chip as the sink.
- Trigger: a message note whose frontmatter carries `storePath: "/Users/<u>/Library/…/something.fileloc"` (or any document type not on the denylist) → clicking the chip opens that file with its default handler.
- Fix: resolve `storePath` against `MailStoreLocation.resolve()` and refuse anything not under it (standardized, symlinks resolved), in `targetURL`, so every caller inherits the check.
- Tracked: none

### SEC-03 — A `settings.json` that fails to decode is replaced with defaults and a freshly minted vault id
- Where: `Sources/Vault/VaultSession+Identity.swift:34`, `Sources/Vault/VaultSession+Identity.swift:53`, `Sources/Vault/VaultSession+Identity.swift:77`, `Sources/Vault/VaultSession+Identity.swift:25`
- Category: correctness
- Severity: P2 · Confidence: confirmed
- In flight: no
- What: `readSettings` returns `.default` when the file exists but does not decode, `resolveIdentity` then finds no vault id, mints a UUID and `writeSettings` writes the defaults over the file. Every setting is lost, and the new id points the vault at a fresh state directory under Application Support (index, journal, history, ledgers orphaned). The doc comment at line 25 says the file is not overwritten in this case, which the code does not honour. ADR-0052/0065's rule (never save over a file you could not read) is not applied here.
- Trigger: a hand edit with a trailing comma, a half-synced iCloud copy, or a value of the wrong type in `.pergamenum/settings.json` → open the vault → the file is rewritten with defaults and a new `vaultID`.
- Fix: distinguish absent from unreadable (three-state read as `PraticaLedger.read(from:)` does), refuse to write over an unreadable file and surface the decode error, opening the vault read-only or with in-memory defaults that are never saved back.
- Tracked: none

### SEC-04 — A capture via the URL scheme still raises the app on the ordinary path: the hand-back sits only on the delegate entry point
- Where: `Sources/App/PergamenumApp.swift:419`, `Sources/App/PergamenumApp.swift:415`, `Sources/App/PergamenumApp.swift:107`, `Sources/App/ForegroundHandBack.swift:42`
- Category: correctness
- Severity: P2 · Confidence: suspected
- In flight: no
- What: PG-132 put `ForegroundHandBack` in `AppDelegate.application(_:open:)`, but the comment at lines 415-418 states that with a `WindowGroup` SwiftUI consumes the Apple Event and that delegate method is never called; the `.onOpenURL` handler that does run routes the URL and never hands the foreground back. SPEC §9's "capture must not raise the app" therefore holds only for a link arriving before any window exists. The two comments (line 114: "opening the URL already brings the app forward"; line 416: the delegate is never called) cannot both describe the live path; PG-132's own hand check is recorded as still owed.
- Trigger: Pergamenum running with a window, another app in front, `open 'pergamenum://capture?text=x'` → Pergamenum comes forward and stays there.
- Fix: apply the same `handsBackActivation(after:)` rule in the `.onOpenURL` closure (one shared function both entry points call), then do the hand check PG-132 left open.
- Tracked: regression of PG-132

### SEC-05 — The drop folder is read from the vault's own `settings.json`, so a synced or edited vault can make the app move files out of any non-home folder
- Where: `Sources/Core/Contenitore/ContenitoreSettings.swift:64`, `Sources/Core/Contenitore/ContenitoreSettings.swift:82`, `Sources/Features/Contenitore/ContenitoreController.swift:184`, `Sources/Features/Contenitore/ContenitoreIngestEngine.swift:94`, `Sources/Features/Contenitore/ContenitoreIngestEngine.swift:203`, `Sources/Vault/VaultSession+Adopt.swift:50`
- Category: security
- Severity: P2 · Confidence: suspected
- In flight: no
- What: `contenitore.dropFolder` lives in `VaultSettings`, i.e. in a file that travels with the vault ("stored `~`-relative … so it resolves on any Mac the vault syncs to"). `validateDropFolder` refuses only `/`, the home folder itself, the vault and its ancestors/descendants, so `~/Downloads`, `~/Desktop` or `~/Documents` pass, and every stable file there is then `moveItem`'d into the vault on launch, not copied. The person who chose the folder on Mac A is not asked again on Mac B, nor when the value changes underneath the app.
- Trigger: `"contenitore": {"dropFolder": "~/Documents"}` written into a vault's `.pergamenum/settings.json` by another Mac, a shared iCloud folder or a hand edit → next launch with Contenitore active → every top-level file in `~/Documents` leaves it for `Contenitore/<YYYY>/`.
- Fix: keep the drop folder per Mac (UserDefaults or the per-vault state directory under Application Support, which does not sync), or require a confirmation when the stored value differs from the one this Mac last accepted; refuse well-known user folders as well.
- Tracked: none

### SEC-06 — A theme dimension written as `"nan"` or `"inf"` parses to a non-finite value that reaches every layout
- Where: `Sources/DesignSystem/DesignTokenDocument.swift:146`, `Sources/DesignSystem/DesignTokenDocument.swift:141`, `Sources/DesignSystem/DesignTokenDocument.swift:159`
- Category: security
- Severity: P2 · Confidence: suspected
- In flight: no
- What: `dimension(_:)` strips `px`/`pt` and hands the rest to `Double(_:)`, which accepts `nan`, `inf`, `infinity` and overflows `1e400` to `+inf`; numbers and font sizes are taken as they come, negative or zero included. Nothing under `Sources/DesignSystem` checks `isFinite` or a range, so a token file in the vault's `.pergamenum/themes/` feeds NaN/inf into every `padding`, `frame`, corner radius and `NSFont` size the theme governs. JSON's own grammar keeps NaN out of a numeric value; the string form is the open door. The rest of the parser is careful to report a malformed value as a problem rather than accept it (ADR-0001 §D4), which this case escapes.
- Trigger: a synced or hand-edited `.pergamenum/themes/x.json` with `"spacing": {"m": {"$type": "dimension", "$value": "nanpx"}}` selected as the theme → non-finite geometry in SwiftUI/AppKit layout (at best "invalid frame dimension" faults and a broken window, at worst a CoreGraphics assertion).
- Fix: reject a dimension, font size or shadow component that is not finite (and a size that is not positive) in `Collector`, as a reported problem like a malformed colour.
- Tracked: none

### SEC-07 — Symlinks: the boundary does not resolve them, and the Contenitore ingests one as a link
- Where: `Sources/Core/Vault/VaultBoundary.swift:46`, `Sources/Core/Vault/VaultBoundary.swift:66`, `Sources/Features/Contenitore/DropFolderListing.swift:99`, `Sources/Vault/VaultSession+Adopt.swift:50`
- Category: security
- Severity: P2 · Confidence: suspected
- In flight: no
- What: `VaultBoundary.url(for:)` collapses `..` lexically with `standardizedFileURL` and checks the prefix, but never resolves symlinks of the candidate (only the root is resolved, line 21), so a symlink inside the vault pointing outside passes and every read/write through it lands outside. One way such a link appears: `DropFolderListing.read` lists a symlink as a regular entry (`isDirectory` false, size of the link), the engine hashes the target through `FileHandle`, and `moveItem` moves the link itself into `Contenitore/<YYYY>/`. P2 rather than P3: it needs local access to plant the link, but the sinks include `perg` and the MCP server, which serve the target's bytes to a model. Distinct from `PG-261`, which covers a symlinked vault root, not a link inside the vault.
- Trigger: `ln -s ~/.ssh/config "~/Pergamenum Drop/config"` (or a symlink arriving from an unpacked archive or a git checkout of the vault) → the vault holds a link to a file outside it, which the editor, `perg` and the MCP server will read and, for a `.md`, write through.
- Fix: in `isInside`, resolve the deepest existing ancestor of the candidate with `realpath` (as `ContenitoreSettings.canonicalComponents` already does) before the prefix check; skip or refuse `isSymbolicLinkKey` entries in the drop-folder listing.
- Tracked: none

### T01-tests-01 — the vault-escape refusal test cannot tell a boundary refusal from a staleness one
- Where: `Tests/CanvasStoreTests.swift:387-398`
- Category: disabled
- Severity: P2 · Confidence: confirmed
- In flight: no
- What: `writeRepointRefusesAPathEscapingTheVault` builds
  `VaultFileChange(path: "../../evil.canvas", before: "{}", after: "{}")`, calls `writeRepoint`,
  and catches **every** error with an empty body and the comment
  `// refusal - either a boundary violation or VaultWriteRefusal is acceptable.` Because `before:
  "{}"` matches no file on disk, `writeRepoint`'s own staleness check throws
  `VaultWriteRefusal.movedOn` for that path whether or not a vault-boundary check runs at all — so
  the test stays green with the boundary check deleted. It also never asserts that nothing was
  written outside the root. Its two immediate siblings do both of those things
  (`:340-355` and `:357-385` each assert the specific refusal case *and* that the file on disk is
  absent or untouched), so the weakening is local rather than a house convention. Since this
  project's merge gate is the unit suite, this is the only thing between a boundary regression and
  `main`. The production boundary itself was not audited here (it belongs to the Vault/Workspace
  slices); the audit doc's `:1039` entry on `CanvasStore` having no boundary check is the related
  production question.
- Trigger: remove or short-circuit the vault-boundary check in `CanvasStore.writeRepoint` → this
  test still passes, because `before: "{}"` is stale for a nonexistent path and the `catch` accepts
  any error.
- Fix: assert the specific refusal (`catch VaultWriteRefusal.outsideVault`/the boundary error case,
  with `Issue.record` on anything else, as `:340-355` does), give `before` the real current contents
  of an existing in-vault board so staleness cannot be what refuses, and add
  `#expect(!FileManager.default.fileExists(atPath: …))` for the escaped path.
- Tracked: none

### T02-01 — Two tests write into the person's real `~/.Trash`, then permanently delete from it by a guessed name
- Where: `Tests/ContenitorePaneGapTests.swift:177`, `Tests/ContenitorePaneGapTests.swift:361`
- Category: hygiene
- Severity: P2 · Confidence: confirmed
- In flight: no
- What: `harness.actions.trashContainer` reaches production `FileManager.default.trashItem`
  (`Sources/Vault/VaultDisk.swift:440`), which has no injectable seam, so the item lands in the real
  `~/.Trash` — the only two tests in the slice that touch a directory outside a temporary vault. Each
  then cleans up by *reconstructing* the path rather than reading it back:
  ```swift
  defer { try? FileManager.default.removeItem(at: FileManager.default.homeDirectoryForCurrentUser.appending(path: ".Trash/\(name)")) }
  ```
  `removeItem` on a Trash path is a permanent delete, not a trashing, and the guessed name misses the
  item whenever the Trash renamed it on collision — leaving debris; an aborted or crashed run leaves
  it too, since the `defer` never fires. Honest mitigation: `name` is
  `"Prova-\(UUID().uuidString.prefix(8))"` (lines 172, 353), so colliding with — and therefore
  permanently deleting — a file the person themselves trashed is implausible. The defect is the real
  write and the unverified delete, not a likely data loss.
- Trigger: n/a (hygiene). The debris path is concrete: a Trash that already holds `Prova-<same 8
  hex>` makes macOS rename the new item, the `defer` removes nothing, and the container stays in the
  person's Trash after the suite is green.
- Fix: take `resultingItemURL` from `trashItem(at:resultingItemURL:)` and remove exactly that URL; or
  give the Contenitore a trash seam in the shape of the four isolation flags the UI suite already has
  (`-disableContenitore`, `-mailStoreRoot`), so the unit suite never reaches `~/.Trash` at all.
- Tracked: none

### T02-02 — Two test helpers leave a `UserDefaults` suite plist in `~/Library/Preferences` per run, against the repo's own convention
- Where: `Tests/DesignSystemTests.swift:443`, `Tests/EditorColumnTests.swift:229`
- Category: hygiene
- Severity: P2 · Confidence: confirmed
- In flight: no
- What: both build a UUID-named suite and never remove its persistent domain.
  `DesignSystemTests.isolatedDefaults()` is called nine times (`:255, 261, 269, 286, 294, 320, 352,
  379, 404`) and the object is handed to `ThemeEngine`, which writes at
  `Sources/DesignSystem/ThemeEngine.swift:357` (`defaults.set(encoded, forKey:
  ThemeEngine.selectionKey)`); `EditorColumnTests` writes on its own face at `:230`. Each call
  therefore materialises one `pergamenum.tests.<uuid>.plist` in the user's preferences directory that
  nothing ever deletes — the suite accumulates them run after run. This is a deviation rather than a
  taste call because the same repo already does it correctly:
  `Tests/EditorRestyleSwitchTests.swift:17-21` declares `scratchDefaults()` and every one of its
  seven call sites (`:31, 41, 51, 91, 101, 112, 121`) pairs it with
  `defer { defaults.removePersistentDomain(forName: name) }`.
- Trigger: n/a
- Fix: adopt `EditorRestyleSwitchTests.scratchDefaults()`'s shape — return the name alongside the
  object and `removePersistentDomain(forName:)` in a `defer` — and promote that one helper to a
  shared support file under ADR-0051 §D4 rather than copying it a third time.
- Tracked: none

### T06-01 — Every `.volatile()` recents/tabs store leaves a plist in the real `~/Library/Preferences`
- Where: `Sources/Vault/RecentVaults.swift:36-38`, `Sources/Vault/OpenTabsStore.swift:47-49`, `Sources/Vault/PinnedTagsStore.swift:18`. In this slice they are called from `Tests/QuitTestSupport.swift`, `Tests/RowCommandTests.swift`, `Tests/RecordingsControllerTests.swift`, `Tests/QuickOpenCreationTests.swift`, `Tests/ReminderRescheduleKeyTests.swift`, `Tests/ReminderTapChainTests.swift`, `Tests/RelatedLinkTests.swift`, `Tests/PraticheLedgerDoorTests.swift`, `Tests/PraticheLedgerOrderingTests.swift`, `Tests/PraticheControllerTests+{Regeneration,FolderRelocation,Conversations,SyncIntegrity}.swift` and `Tests/QuitBoardLifetimeHostedTests.swift`
- Category: hygiene
- Severity: P2 · Confidence: confirmed
- In flight: no
- What: `volatile()` makes `UserDefaults(suiteName: "pergamenum.tests.<UUID>")` and nothing ever removes that domain. Each `VaultController(recents: .volatile(), openTabs: .volatile())` that opens a vault calls `recents.remember(url)` on open (`Sources/App/VaultController.swift:317`), so a `pergamenum.tests.<UUID>.plist` holding `recentVaults` → `$TMPDIR/pergamenum-vault-<UUID>/` lands in the user's real Preferences folder. That matches what T05 sampled (1.1M such files). The newest one on 2026-10-31, `pergamenum.tests.32E88355-….plist`, holds exactly `recentVaults` → `/var/folders/…/T/pergamenum-vault-B6792D2F-…/`. 102 test files build a controller this way, 14 of them in this slice. The explicit test helpers (`RecentVaultsTests`, `ShortcutTests`, `VaultControllerCacheCleanupTests`) do call `removePersistentDomain`. More decisively, `RecentVaultsTests` remembers `pergamenum-recents-<UUID>` directories (T06-04), while the leaked files point at `pergamenum-vault-<UUID>`, which is `TemporaryVault`'s prefix. So the leak comes from the production factory, whatever cfprefsd does on removal. This is P2 because it changes real user state and runs at the end of every turn through the Stop hook.
- Trigger: any unit-suite run.
- Fix: back `volatile()` with an in-memory store, or return a value that calls `removePersistentDomain(forName:)` when it is released (or have `VaultController.close()` do it). Keep the same UUID suite so tests stay isolated from each other. Cleaning up the existing files is the user's call.
- Tracked: none (T05's out-of-slice note pointed at `RecentVaultsTests`; it cleans up, the factory does not)

### T06-02 — Two tests put vault notes into the user's real Trash
- Where: `Tests/StarredTests.swift:132`, `Tests/RecordingsControllerTests.swift:294` (`delete(recordingID:)` → `vault.trashNote`)
- Category: hygiene
- Severity: P2 · Confidence: confirmed
- In flight: no
- What: `VaultSession.trashNote` reaches `VaultDisk.trashFile` (`Sources/Vault/VaultDisk.swift:437-443`), which calls `FileManager.default.trashItem`. For a `TemporaryVault` under `$TMPDIR` on the boot volume, that moves the file into the user's `~/.Trash`. `TemporaryVault`'s cleanup never reaches it, so every run adds `Sospensione.md` and a recording note to the person's Trash. 27 files across `Tests/` call a trash API, so the same leak is probably in other slices too.
- Trigger: any unit-suite run.
- Fix: inject the trash primitive into `VaultDisk`. Tests would get a move into `stateBase/Trash`; production keeps `trashItem`. Alternatively, remove `landed` in a `defer` inside each test, though that is easier to forget.
- Tracked: none

### T07-tests-01 — Unit tests put files in the user's real Finder Trash and never take them out
- Where: `Tests/VaultAsyncCascadeTests.swift:239`, `Tests/VaultControllerExternalDeletionTests.swift:287`, `Tests/VaultControllerExternalDeletionTests.swift:301`, `Tests/VaultControllerLandedChangeTests.swift:196`, `Tests/VaultControllerLandedChangeTests.swift:263`
- Category: hygiene
- Severity: P2 · Confidence: confirmed
- In flight: no
- What: each site completes a real trash: `session.trashFile`, the cascade `trash(...)`, or `controller.trashNote`. All of them reach `VaultDisk.trashFile`, which calls `FileManager.default.trashItem` (`Sources/Vault/VaultDisk.swift:440`) with no test-aware branch. The vault sits in the per-user temp dir on the home volume, so the file lands in the person's `~/.Trash`, and the Stop hook runs these tests every turn. `Tests/VaultDiskNonNoteMoveTests.swift:84-85` keeps the returned trash URL and removes it in a `defer`, and `Tests/ContenitorePaneGapTests.swift:177` cleans `~/.Trash/<name>` by hand. That shows the leak is known in two places and missed in these five. Leftovers are named `A.md`, `B.md` and `Board.canvas` with Finder's numeric suffixes, so they mix into the person's own Trash. The `~/.Trash` count was not checked: it is outside the session's scope.
- Trigger: any run of `PergamenumTests`.
- Fix: in the short term, keep the `trashURL` that `trashFile` returns and remove it in a `defer`, as `VaultDiskNonNoteMoveTests` does. `trashNote` and the cascade wrapper do not return the URL, so the fallback is structural: when `VaultState.isRunningUnderTest`, `VaultDisk` (and `FolderFileOperations`/`BoardFileOperations`'s `trashItem`) move to a trash directory under the state base, the same way `processDefaultBase()` already redirects state. That branch would be one more test-aware seam of the kind T07-tests-16 inventories, so prefer the `defer` where the URL is reachable.
- Tracked: none

## P3 (227)

### S01-05 — `vault`, `calendar` and `hotkey` are constructed twice at every launch
- Where: `Sources/App/PergamenumApp.swift:132,133,191,206-209,216-220`, `Sources/App/VaultController.swift:219-231`, `Sources/Calendar/CalendarService.swift:61-80`
- Category: performance
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: the three properties are declared with inline defaults (`@State private var vault = VaultController()`) and then built again in `init()` and assigned through `_vault = State(initialValue: vault)`. Swift runs every stored-property initialiser before the body of a designated `init`, so each launch constructs two `VaultController`s (each with its own `RecentVaults`, `OpenTabsStore`, `PinnedTagsStore`, `WorkspaceController` and outline stores), two `EventKitStore`s (each calling `refreshAccessStatus()` and starting the `for await` notification loops at 79-80, which keep running for the life of the process on the discarded instance, doing nothing on each EventKit notification) and two `GlobalHotkey`s. The other `@State` values assigned in `init()` (`navigation`, `history`, `day`, `diary`, …) are declared without a default and built once.
- Trigger: n/a
- Fix: drop the three inline defaults so the declarations match the rest of the `init()`-assigned state.
- Tracked: none

### S01-06 — Three doc comments say `columns` is written only by the tab doors; eleven other sites write it
- Where: `Sources/App/VaultController.swift:41`, `Sources/App/VaultController+Tabs.swift:148`, `Sources/App/VaultController+VaultSwitch.swift:31`
- Category: docs
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `VaultController.swift:41` ("**Written only by the doors in `VaultController+Tabs.swift`**") and `+Tabs.swift:148` ("written **only from here**") promise one place to audit for a tab or column mutation; `+VaultSwitch.swift:31` names itself and `close()` as the only exceptions. The source writes `columns` from `VaultController.swift:295,297,345`, `+VaultSwitch.swift:95`, `+ColumnClose.swift:77`, `+Callouts.swift:28`, `+LinkOpening.swift:47`, `+NoteBirth.swift:141,175,185`, `+UnsavedMarks.swift:18`, and from `+Tabs.swift:41` (`recordOutlineEntry`, not one of the doors). A reader trusting the comment audits one file and misses ten writers.
- Trigger: n/a
- Fix: either make `columns` `private(set)` with one `mutateTab(column:tab:_:)` door the per-tab writers call (the structural writers stay the doors), or rewrite the three comments to list the writers by kind.
- Tracked: none

### S01-07 — Four files are back over SwiftLint's `file_length` warning, two of them the ones PG-035 had brought under it
- Where: `Sources/App/PergamenumApp.swift:1` (536 lines), `Sources/App/CommandActions.swift:1` (405), `Sources/App/VaultController+Tabs.swift:1` (421), `Sources/App/VaultController.swift:1` (491)
- Category: simplification
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `.swiftlint.yml:45-47` keeps `file_length` at warning 400 (comment lines count) and records only seven *types* as known `type_body_length` debt (`VaultController` among them, lines 40-43); no file is recorded as accepted `file_length` debt. PG-035 (closed) had brought `PergamenumApp.swift` to 286 lines and `CommandActions.swift` to 344; they are at 536 and 405, and `VaultController+Tabs.swift` and `VaultController.swift` are over too. `PergamenumApp.swift` holds the `AppDelegate`, the `App`, the scene, `ReminderKey` and the whole `TaskCommands` menu (479-536), which is the natural split.
- Trigger: n/a
- Fix: `TaskCommands` to `MenuCommands+Tasks.swift` and `AppDelegate` to its own file (both are already separate types); the `flags` table and the `run*` sections of `CommandActions` into one more extension file; `VaultController+Tabs.swift`'s recent/preview helpers (342-420) into `+Recents.swift`.
- Tracked: regression of PG-035

### S01-08 — The theme picker is built twice, filter and rows included
- Where: `Sources/App/HistoryToolbar.swift:62-81`, `Sources/App/MenuCommands.swift:352-361`
- Category: simplification
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: the toolbar's `themeToggleToolbarItem` and Vista ▸ Tema build the same `Picker("Tema")`: the same three fixed rows and the same `engine.selectableThemes.filter { !$0.id.hasPrefix("pergamenum-") }` (70 and 357). PG-099 added the toolbar copy "mirroring `ThemeCommands`"; the filter and the row order now live twice and drift the next time a theme id convention or a row changes. Chain 9 (PG-262) lists the toolbar item's *coverage* (missing in Pratiche and Search), not this duplication.
- Trigger: n/a
- Fix: one `ThemePickerRows(engine:)` view, or an `engine.menuThemes` computed property holding the filter, used by both.
- Tracked: none

### S01-09 — A malformed `pergamenum://` URL is dropped without a line in Console
- Where: `Sources/App/PergamenumApp.swift:108,420`, `Sources/Core/URLScheme/PergamenumURL.swift:36`
- Category: correctness
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: both entry points discard what `PergamenumRoute.init?` refuses (`urls.compactMap(PergamenumRoute.init)` and `guard let route = PergamenumRoute(url) else { return }`), and `PergamenumURL.swift` has no `Logger` at all (zero matches). A link the app registered its scheme for is therefore dropped silently, while the same controller logs every *parsed* route's outcome through `routeLog` (`VaultController+Routes.swift:20-31`). A Raycast script with a typo in the host or a missing `file=` looks exactly like success.
- Trigger: `open 'pergamenum://note?file='` → nothing happens, nothing is logged.
- Fix: log the refused URL at both entry points (`routeLog.notice("route rifiutata: \(url.host ?? "", privacy: .public)")`, query `.private`), or make `PergamenumRoute` return a typed failure the entry points can log.
- Tracked: none

### S02-03 — Two creation writes skip `expectingAbsent:` after a read that found nothing
- Where: `Sources/Vault/VaultSession+TimeBlocks.swift:107`, `Sources/Vault/VaultSession+TimeBlocks.swift:113`, `Sources/Vault/VaultSession+SampleViews.swift:24`, `Sources/Vault/VaultSession+SampleViews.swift:29`
- Category: correctness
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `dailyNoteBody` reads the daily note (107) and, finding none, writes the frontmatter skeleton with a bare `write(text, to:)` (113); `installSampleViews` does the same for each sample (24, 29). A file created between the read and the write is overwritten rather than refused — the read-came-back-empty shape ADR-0057 §D3/§D8 closed for `captureTask` with `expectingAbsent: existing == nil` (`VaultSession+Tasks.swift:283`) and for `createNote` with `expectingAbsent: true` (`VaultSession+Notes.swift:71`).
- Trigger: a time block dropped on a day whose note does not exist yet while that daily note is being born by another writer (a connector capture, the «Oggi» template birth) → the skeleton replaces the just-created note. Narrow window; closing it costs one argument.
- Fix: `expectingAbsent: true` on both writes; on `VaultWriteRefusal` re-read and continue with the existing text (`dailyNoteBody` already returns the hash its caller writes against).
- Tracked: none

### S02-04 — `CanvasStore.writeRepoint` drops a board's leading BOM that `save` keeps
- Where: `Sources/Vault/CanvasStore.swift:115`, `Sources/Vault/CanvasStore.swift:95`
- Category: correctness
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `save` (82) writes `ByteOrderMark.keeping(of: fileURL, onto:)` (95, "the BOM belongs to the file", ADR-0065 §D4.3); `writeRepoint` (109), the one door every planned `.canvas` repoint takes (ADR-0054 §D6), writes `Data(change.after.utf8)` as is (115), so a board that starts with `EF BB BF` loses it on the first note or folder rename that repoints it. PG-280's close note says "`CanvasStore` keeps it on write"; it holds for one of the store's two write doors.
- Trigger: a `.canvas` written with a BOM by another tool, then rename a note one of its nodes embeds → the file's first three bytes change although only a `file` key was meant to.
- Fix: `ByteOrderMark.keeping(of: fileURL, onto: Data(change.after.utf8))` at 115, as at 95; the guard at 111-114 compares `NoteStore.hash`, which already skips the BOM.
- Tracked: regression of PG-280

### S02-05 — A thumbnail is keyed on path and size bucket only, so a file replaced in place keeps its old thumbnail until «Svuota cache»
- Where: `Sources/Vault/ThumbnailStore.swift:134-138`, `Sources/Vault/ThumbnailStore.swift:43`, `Sources/Vault/ThumbnailStore.swift:57`, `Sources/Vault/ThumbnailStore.swift:75`
- Category: correctness
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `cacheKey` is `sha256(relativePath).prefix(24)@bucket` (134-138): no modification date, size or content hash. The memoised task (43, 57) and the PNG on disk (75, read before the source file is looked at) therefore outlive the file's bytes. Nothing evicts them but `forgetAll()`/`clearCacheOnDisk()`, called only from `VaultController.clearCache` (`Sources/App/VaultController.swift:474-475`), and `VaultWatcher` delivers `.md` paths only (`VaultWatcher.swift:72`), so no external change can reach the store. ADR-0072's rule — one changing identity keys every derived cache — is not applied here; PG-131 covered the «Svuota cache» eviction, not staleness.
- Trigger: re-export `Contratto.pdf` over itself, or save a new image under the same name → every Workspace card showing it keeps the previous first page or image, across launches, until Impostazioni › Avanzate › «Svuota cache».
- Fix: fold the file's modification date and size (one `attributesOfItem`, in `thumbnail(for:width:)` on the actor) into the key, or compare them with a sidecar before `NSImage(contentsOf:)` at 75; the PNG under the previous key becomes garbage `clearCacheOnDisk` already collects.
- Tracked: none

### S02-06 — `FolderFileOperations` keeps two copies of the board-repoint loop, and the batched one has no production caller
- Where: `Sources/Vault/FolderFileOperations.swift:206-256`, `Sources/Vault/FolderFileOperations.swift:275-326`, `Sources/Vault/FolderFileOperations.swift:201-205`, `Sources/Vault/FolderFileOperations+Move.swift:3-12`
- Category: dead-code
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `repointBoardsPlan(from:to:)` (206) and `repointBoardsPlan(moves:)` (275) walk `canvas.allBoards()` (215, 284) with the same node-matching and re-encoding body. The batched form is called only from `Tests/VaultBatchMoveTests.swift:90-132`; the production multi-move path (`NoteFileOperations+Pairs.swift:126`) uses `NoteFileOperations.repointBoardsPlan(repoints:titleChanges:)` (`NoteFileOperations.swift:183-211`), a third variant of the loop that also carries title changes, so the comment at 201-205 ("there is no third copy of this loop in the repository") no longer holds. The file is 482 lines against SwiftLint's 400 warning, which the `+Move.swift` header (3-12) presents the move split as having cured.
- Trigger: n/a
- Fix: one pass taking `[(from, to)]` plus optional title changes, with the single-pair form a one-line call into it; or delete `moves:` and retarget its tests at the pass the batch move actually runs. `knownPaths` (167, forwarded from 358) goes with it.
- Tracked: none

### S02-07 — `NoteFileOperations.boardPaths()` is a hand-rolled vault walk beside `VaultWalk`, in a file both connectors compile
- Where: `Sources/Vault/NoteFileOperations.swift:20-38`, `Sources/Vault/NoteFileOperations.swift:188`
- Category: house-rules
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: the note rename/move repoint pass (188) lists boards through its own `FileManager.default.enumerator` with `.skipsHiddenFiles`/`.skipsPackageDescendants` and a `hasPrefix(rootPath)` trim (20-38), a second spelling of the exclusion rule, while `CanvasStore.allBoards()` (`CanvasStore.swift:229`) and `NoteFileOperations.filePaths(named:)` (`NoteFileOperations+Pairs.swift:189-199`) go through `VaultWalk`, the one walk ADR-0041 §D3 gives the layer — the same file already uses it for notes but not for boards. `FolderFileOperations.swift:78` records the earlier removal of exactly this mirror ("it is the same one").
- Trigger: n/a
- Fix: `CanvasStore(root:).allBoards()` (or `VaultWalk` directly) at 20-38; the `.pathSlashes` trim and `rootPath` prefix logic go away with it.
- Tracked: none

### S02-08 — Both `VaultDisk.writeFile` overloads derive a `NoteRecord` from board bytes that nothing applies
- Where: `Sources/Vault/VaultDisk.swift:338`, `Sources/Vault/VaultDisk.swift:376`, `Sources/Vault/VaultSession+Journal.swift:253-255`
- Category: performance
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: each `writeFile` runs `store.record(from:attributes:at:)` on the bytes it just wrote (338, 376) — the full note derivation (frontmatter, links, tasks) over a `.canvas` JSON document — and returns it in the `IndexMutation`; `VaultSession.writeFile` then applies nothing of it, by design ("a board is not a note", `+Journal.swift:253-255`), and keeps only the sequence. `moveFile` and `restoreFile` already gate the same derivation on `derivesNoteRecord` (426, 467, 474-476). Every board autosave and every repoint pays a parse whose result is discarded.
- Trigger: n/a
- Fix: gate on `Self.derivesNoteRecord(relativePath)` at 338 and 376 as 426/467 do, or return `record: nil` from both doors if `Tests/VaultWriteOrderingTests.swift` does not read it.
- Tracked: none

### S02-09 — `VaultWatcher` ignores the FSEvents flags, so a dropped-events burst and a moved vault root pass unnoticed, against the comment that credits `WatchRoot`
- Where: `Sources/Vault/VaultWatcher.swift:122`, `Sources/Vault/VaultWatcher.swift:72`, `Sources/Vault/VaultWatcher.swift:139-141`, `Sources/Vault/VaultWatcher.swift:10`
- Category: correctness
- Severity: P3 · Confidence: suspected
- In flight: no
- What: the callback discards `eventFlags` (122: `{ _, info, count, paths, _, _ in`). `kFSEventStreamEventFlagMustScanSubDirs` (with `UserDropped`/`KernelDropped`) is the system's one signal that events were lost and the subtree must be rescanned; unseen, the reconciler goes on believing it saw everything. `kFSEventStreamEventFlagRootChanged`, the event `kFSEventStreamCreateFlagWatchRoot` (141) exists to deliver, arrives with the root path and dies at the `.md` filter (72), while the stream keeps watching the old path string: the comment at 139-140 ("WatchRoot keeps the stream valid if the vault folder itself is moved") describes an effect FSEvents does not have and the handler would discard anyway. The `@unchecked Sendable` on the watcher itself (10) carries no justification, unlike `Sink`'s (44 and its doc); `stream`/`sinkInfo` are mutated only from `VaultController` on the main actor, so it hides no race today, but nothing says so.
- Trigger: a burst of external changes larger than the kernel's event buffer (a `git checkout` across a large vault, a first iCloud sync) → some `.md` edits never reach `reconcile`, open tabs keep stale text with no conflict shown; a Finder move of the open vault's folder → no event from then on. Not reproduced; from the FSEvents contract.
- Fix: read the flags: on `MustScanSubDirs` hand the reconciler the directory (or start `rescan()`), on `RootChanged` stop the stream and surface it; reword 139-140; one sentence on why `VaultWatcher` is `@unchecked Sendable`, or drop the conformance if `VaultController`'s isolation does not need it.
- Tracked: none

### S02-10 — `rescan` loads the whole SQLite cache synchronously on the main actor on every call, while the walk and the save are detached
- Where: `Sources/Vault/VaultSession.swift:401-402`
- Category: performance
- Severity: P3 · Confidence: suspected
- In flight: no
- What: `cache.load()` and `cache.loadBoardTasks()` run on the main actor (401-402), reading every cached row of a vault-sized table, before the scan is handed to a detached task; the save of the same table at the end of `rescan` is already detached, with its `IndexCache(url:)` built inside the task. `rescan` is started, unawaited, by every rename and move verb (the PG-374 comment inside `rescan` names `VaultController.renameNote` and `moveNote`), so the load's cost is paid per verb on the UI thread. ADR-0041 §D12 keeps note reads on the main actor; the cache is not a note read.
- Trigger: n/a (not measured)
- Fix: move the two loads inside the detached task with the scanner, as the save already is; the URL is captured, nothing else crosses.
- Tracked: none (PG-377 is the overlay cost after the scan, not the load before it)

### S02-11 — `WriteJournal.record` appends with seek-then-write, not `O_APPEND`, so two connector processes can clobber each other's lines
- Where: `Sources/Vault/WriteJournal.swift:128-131`, `Sources/Vault/WriteJournal.swift:150`
- Category: correctness
- Severity: P3 · Confidence: suspected
- In flight: no
- What: each append opens its own `FileHandle`, `seekToEnd()` and writes (128-131). Within one process the disk actor serialises the calls; across processes `perg` and `pergamenum-mcp` both arm the journal on the same vault (ADR-0007 §D6) and nothing serialises them, so two appends at the same instant seek to the same end and the second overwrites the first's bytes. `entries()` then skips the damaged line(s) silently (150, `try?` per line): the undo net losing an entry with nothing said.
- Trigger: a `perg` write from Terminal landing at the same instant as an MCP write from Claude Code on the same vault. Not reproduced; from the POSIX file-offset contract.
- Fix: open with `O_APPEND|O_CREAT` (`open(2)` wrapped in `FileHandle(fileDescriptor:closeOnDealloc:)`), one line per `write`; count the lines `entries()` skips so `undo` can say the journal is damaged rather than "non è un'operazione nel journal".
- Tracked: none

### S03-02 — `EventNoteSection.adding` finds its section by substring, so `## Note correlate` and any `## Note…` heading take the event link
- Where: `Sources/Core/Conventions/EventNote.swift:65`, `Sources/Core/Conventions/EventNote.swift:80`, `Sources/Core/Conventions/EventNote.swift:89-93`, `Sources/Vault/VaultSession+EventNotes.swift:80`
- Category: correctness
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `heading` is `"## Note"` and the section is located with `body.range(of: heading)` (`:80`), a substring search anywhere in the body. It matches the first occurrence inside `## Note correlate` (`RelatedSection.heading`, `Wikilink.swift:249`), `## Note varie`, `### Note`, or a `## Note` typed inside a fenced block, and the bullet is then appended at the end of *that* section (`:89-100`). Under `## Note correlate` the `- [[title]]` line becomes a structural link with no reason: `RelatedSection.parse` counts it (W-04/W-06 findings, the five-link cap). This is the class of defect ADR-0065 §D9.3/R-18 and `PG-278` closed for `RelatedSection.sectionRange` (anchored, fence-aware, exact line); the sibling writer kept the old search.
- Trigger: daily note whose body has `## Note correlate` (after «Collega») or `## Note varie` and no `## Note` section → create an event note from the calendar → the link lands at the end of the wrong section instead of a new `## Note` section.
- Fix: locate the heading as an exact line (`^## Note$` once a trailing `\r` is removed, outside fences), the rule `RelatedSection.sectionRange` already implements; share that line walk.
- Tracked: none

### S03-03 — `NoteRename.rewritingQuotedRelated` rewrites a `- "Old title"` bullet anywhere in the note, not only under `related:`
- Where: `Sources/Core/Conventions/NoteRename.swift:52-73`, `Sources/Core/Conventions/NoteRename.swift:17-21`, `Sources/Vault/NoteFileOperations.swift:120`, `Sources/Vault/NoteFileOperations+Pairs.swift:171`, `Sources/Vault/BoardFileOperations.swift:103`
- Category: correctness
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: the pass walks `text.components(separatedBy: "\n")` over the whole note (`:62`) and rewrites every line of the shape `- "X"` whose `X` folds to the old title (`:65-70`), with no bound to the frontmatter block or to the `related:` entry. Its doc (`:47-51`) describes it as the frontmatter-only spelling of F-06, and the `includeQuotedRelated` gate (`:17-21`) was added only for Workspace cards, assuming a note's quoted bullets live in frontmatter. The three note callers pass the default `true`, so a body bullet or a fenced line equal to the old title is silently changed on rename.
- Trigger: note body holds `- "Relazione tecnica"` (a quoted list item, or a line inside a code fence) → rename note `Relazione tecnica` to `Relazione 2026` → that body line becomes `- "Relazione 2026"`, counted as a rewritten link.
- Fix: bound the walk to the frontmatter block (`FrontmatterSource.closingDelimiterIndex(in:)`) and to the continuation lines of the `related:` key; `FrontmatterParser.keyName`/`isContinuation` already group them.
- Tracked: none (`PG-100`, closed, pinned only the card gate)

### S03-04 — `Wikilink.emphasisMarker` strips `**`, `~~`, `*` but not `_`/`__`, which ADR-0098 now conceals inside a link
- Where: `Sources/Core/Conventions/Wikilink.swift:45-49`, `docs/adr/0098-underscore-emphasis-is-concealed-and-the-daily-panes-draw-transclusions.md:195`
- Category: correctness
- Severity: P3 · Confidence: suspected
- In flight: yes
- What: `resolvedTitle`'s marker list (`:46`) is the pre-ADR-0098 set, so `[[_bozza_]]` keeps resolving to `_bozza_`. The in-flight ADR's Consequences (`:195`) record that such a link now *draws* as «bozza» "as `*` already does", but for `*` the navigation side was fixed too (`PG-107`): a link that looks like a link to `bozza` resolves to no note, and `NoteRename` (which matches on `resolvedTitle`) will not rewrite it when `bozza` is renamed. The branch commit `668067eb` touches no `Sources/Core` file.
- Trigger: type `[[_bozza_]]` in a note where `bozza.md` exists → editor shows «bozza» concealed like `[[*bozza*]]` → Cmd+click reports no note; rename `bozza` → the link is left behind.
- Fix: add `"__"` and `"_"` to the marker list (order: longer first), with the intraword rule the shared grammar applies; one test beside the `**` one from `PG-107`.
- Tracked: none

### S03-05 — Inline frontmatter lists are split on every comma, inside quotes and brackets too
- Where: `Sources/Core/Conventions/Frontmatter.swift:223-225`, `Sources/Core/Conventions/Frontmatter.swift:243-245`, `Sources/Core/Conventions/Frontmatter.swift:290-300`
- Category: correctness
- Severity: P3 · Confidence: suspected
- In flight: no
- What: `parseTags` and `parseStringList` take an inline `[…]` value and `split(separator: ",")` before unquoting, so `related: ["[[Pane, amore e fantasia]]"]` or `aliases: ["Rossi, Mario"]` read as two entries (`"[[Pane` and `amore e fantasia]]"`, quotes left attached). A comma is not in `NoteName.forbiddenCharacters`, so such a title is legal. Unchanged keys are re-emitted verbatim (ADR-0065), so the damage stays in memory until the key is rewritten: «Collega» rebuilds `related` through `canonicalLines` (`:290-300`) from the split values.
- Trigger: note with `related: ["[[Pane, amore e fantasia]]"]` → «Collega» towards another note → the rewritten `related:` block carries two broken entries; the original link is gone from the frontmatter.
- Fix: split the inline list with a quote- and bracket-aware scanner (`MessageDocument.splitTopLevel` is the same rule written for the message files), or refuse to rewrite a key whose inline value did not round-trip.
- Tracked: none

### S03-06 — `NoteName.sanitized` keeps a leading dot, so an imported `.name.pdf` lands as a hidden file the vault never shows
- Where: `Sources/Core/Conventions/NoteName.swift:76-83`, `Sources/Core/Conventions/NoteName.swift:40-46`, `Sources/Core/Conventions/ImportNaming.swift:209-218`, `Sources/App/VaultController+Import.swift:43`, `Sources/Features/Workspace/WorkspaceController+Import.swift:43`, `Sources/Core/Contenitore/ContenitoreNaming.swift:43`
- Category: correctness
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `validate` refuses a leading dot (`:44-46`, the `PG-272` rule: every vault walk skips hidden files) but `sanitized` only filters `forbiddenCharacters`, which has no `.`. `ImportNaming.sanitizedFileName` sanitizes the stem with it, so `.riservato.pdf` keeps the stem `.riservato`; the import copies a file the sidebar, the index and the embeds resolver (`.skipsHiddenFiles`) will never see.
- Trigger: drop `.riservato.pdf` (a dot-file from a Unix tool, or a name typed with a leading dot) on the note list or the Workspace → copied into the vault, invisible everywhere, found only in the Finder.
- Fix: strip leading dots in `sanitized` (and fall back to `file` as `sanitizedFileName` already does for an empty stem), so the three sanitizing callers agree with `validate`.
- Tracked: none

### S03-07 — `KeyBinding`'s lowercase invariant lives in `init(_:_:)` only; the synthesized decoder bypasses it
- Where: `Sources/Core/Shortcuts/KeyBinding.swift:13`, `Sources/Core/Shortcuts/KeyBinding.swift:38-49`, `Sources/App/ShortcutStore.swift:121-125`, `Sources/App/ShortcutStore.swift:65-70`
- Category: correctness
- Severity: P3 · Confidence: suspected
- In flight: no
- What: the doc (`:38-41`) says letters are stored lowercased so a binding compares equal to itself after a round trip, and `init(_:_:)` does it (`:47`). `Codable` is synthesized for the struct (only `Modifiers` has a custom decoder), so the overrides file decoded by `ShortcutStore.decode` through `JSONDecoder` hands back `key` as written. A hand-edited `"key": "N"` (the file is documented as meant to be readable) yields a binding unequal to `KeyBinding("n", .command)`: `conflicts(with:)` misses the collision with «Nuova nota».
- Trigger: edit the overrides file to `{"newReminder": {"key": "N", "modifiers": 1}}` → Impostazioni shows no conflict with `newNote` (Cmd+N) though both name the same keys.
- Fix: a custom `init(from:)` that routes through `init(_:_:)`, or normalise in `ShortcutStore.decode`.
- Tracked: none

### S03-08 — `UnifiedDiff.diff` allocates an `(old+1)×(new+1)` table of `Int`
- Where: `Sources/Core/UnifiedDiff.swift:51-54`, `Sources/Features/Pratiche/PraticaSyncEngine+Messages.swift:687`, `Sources/Connector/VaultWrites.swift:49`
- Category: performance
- Severity: P3 · Confidence: suspected
- In flight: no
- What: the LCS table is full and `Int`-typed: 5,000 lines on each side is 25M entries, 200 MB, transient, per diff. The doc (`:48-50`) accepts this "for a note"; the pratica regeneration preview (`:687`) diffs a pratica note that grows with every synced message, and the MCP dry-run path (`VaultWrites.swift:49`) diffs whatever a model sends.
- Trigger: n/a
- Fix: strip the common prefix and suffix before the table (edits are local, so the remaining n·m is small), or a `UInt32`/banded table; Myers O(ND) if ever needed.
- Tracked: none

### S03-09 — `Attachment.byName` walks the whole vault, and two SwiftUI views call it from a computed property in `body`
- Where: `Sources/Core/Conventions/Attachment.swift:114`, `Sources/Core/Conventions/Attachment.swift:128-152`, `Sources/Features/Editor/EmbeddedFileView.swift:31-34`, `Sources/Features/Views/ViewGridRenderers.swift:78-81`, `Sources/Features/Editor/NoteTextView+Embeds.swift:195-201`
- Category: performance
- Severity: P3 · Confidence: suspected
- In flight: no
- What: an embed that does not resolve beside the note falls through to `byName`, a `FileManager.enumerator` over the entire vault per call (`:138-150`), with no index behind it. `EmbedTable` caches hits *and misses* for exactly this reason (`:195-201`); `EmbeddedFileView.relativePath` and the gallery cell's `relativePath` are computed properties read in `body` (`.task(id: relativePath ?? target)`), so a missing file costs one vault walk per render of that view, per cell in a gallery.
- Trigger: n/a
- Fix: resolve once into `@State` in `.task`, or answer `byName` from the index (`IndexSnapshot` already knows every path) instead of the disk.
- Tracked: none

### S03-10 — `NoteClassification.classify`'s `vocabulary` parameter is dead, by its own admission
- Where: `Sources/Core/Conventions/NoteClassification.swift:13-20`
- Category: dead-code
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: Periphery's `NoteClassification.swift:19 vocabulary unused` is right: the body never reads it, and the doc (`:13-15`) says it is "kept for parity with `ContenitoreClassification.classify` and because the plan declares this signature". A parameter kept for a plan's sake is an argument every caller has to find a value for.
- Trigger: n/a
- Fix: drop the parameter at both classifiers, or make it do what the name promises (validate topics against the open family's known values) and say which in the doc.
- Tracked: none

### S04-01 — `NoteFrontmatter.range` is a second frontmatter-extent rule beside the one PG-276 made canonical
- Where: `Sources/Core/Markdown/NoteFrontmatter.swift:12,16`, `Sources/Core/Conventions/FrontmatterSource.swift:83,92,97-101`
- Category: correctness
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `FrontmatterSource.closingDelimiterIndex` (`:97-101`) calls itself "the one block-extent test every frontmatter reader uses": the first line is interpreted (BOM dropped, `:83`) and a delimiter is a line that trims to exactly `---` (`:92`). `NoteFrontmatter.range` keeps its own test, `hasPrefix("---")` on the raw first line (`:12`) and on each later line (`:16`), with no BOM strip, no trim and no exact match. Its callers are the token layer (`MarkdownTokens.swift:92`), the styler (`MarkdownStyler.swift:148,200`), `FenceChrome.swift:27`, `NoteFolding.swift:91`, `StructureMap.swift:296` and the frontmatter toggle (`NoteTabBar.swift:74`, `CommandActions+CanRun.swift:45`); `NoteDocument.parse` (index, linter, export, outline through `bodyStart`) uses the canonical one, so the editor and the rest of the app can disagree on the same note.
- Trigger: a note whose first line after the block is `----` or `--- fine`: the editor styles and folds lines 1..n as frontmatter, `NoteDocument.parse` returns no block (`missingBlock` from the linter, body from line 1, the outline reads `date:` as prose). A file starting with U+FEFF then `---`: the reverse, parse sees the block, the editor styles it as body and the frontmatter toggle is absent. ` ---` with a leading space closes the block for parse and not for the editor.
- Fix: keep the `LineBreak.isTerminator` walk in `NoteFrontmatter.range` and ask `FrontmatterSource.interpreted`/`isDelimiter` per line, or derive the range from `closingDelimiterIndex(inLines:)` over a lazy line sequence.
- Tracked: none (PG-276 closed covering `MessageFrontmatterPatch` and `ViewCatalogue`, not this reader)

### S04-02 — Three fence-delimiter rules in Core disagree on `~~~` and on a closing line that carries text
- Where: `Sources/Core/Markdown/CodeFence.swift:18-20`, `Sources/Core/Conventions/Wikilink.swift:148-154`, `Sources/Core/Editor/ListContinuation.swift:251-254`
- Category: correctness
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `CodeFence.marks` says a trimmed line starting with three backticks opens and closes a fence and tildes are prose (the comment at `:14-17` records that CommonMark's stricter close is "a decision, not a detail"). `WikilinkParser.marksCodeFence`/`fencedCodeRanges` say three backticks or three tildes open and only a bare delimiter closes. `ListContinuation.isFenceDelimiter` says backticks or tildes, and any such line toggles. The first feeds `CodeFence.regions` and through it the token layer (styler, reading view, HTML export, outline, folding, `UnlinkedMentions`); the second feeds the wikilink index, `TaskParser.tasks` (`TaskParser.swift:18`), `RelatedSection` and the restyle boundaries through `MarkdownLineSignature`; the third feeds Return and renumbering.
- Trigger: a `~~~` block holding `- [ ] chiama Rossi` and `# Log`: the editor draws a checkbox and the outline lists the heading, the Tasks pane and Oggi do not have the task, Return after the line does not continue the list. A closing line written "``` fine" closes the block for the editor and the export but keeps it open for the task and link index, so every task and link below it vanishes from the index until the next bare fence.
- Fix: one `marks` predicate and one close rule shared by the three walks; whichever rule wins is the decision the `CodeFence` comment names, but it has to be one.
- Tracked: none

### S04-03 — `LineFormat` recognises only `- ` as a bullet, so a `* ` or `+ ` item is stacked on instead of replaced
- Where: `Sources/Core/Editor/LineFormat.swift:79,141-151,166`
- Category: correctness
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `markerLength(of: .bullet)` (`:141-151`) matches only `"- "` (`:151`), so `anyMarkerLength` (`:166`) returns 0 for `* item` and `+ item` and the requested format is prepended, against the comment at `:79` ("replaced, never stacked"). The other marker readers in Core accept all three bullets (`ListContinuation.swift:296`, `ListNesting.markerWidth`, `MarkdownTokens.afterBullet`), so the editor draws `* item` as a bullet that the format bar cannot recognise.
- Trigger: paste `* uno`, press the bullet button → `- * uno`; press H1 → `# * uno`; the bullet button never lights on the line, so the list cannot be un-bulleted.
- Fix: match `- `, `* ` and `+ ` in `markerLength(of: .bullet)` (the checklist exclusion stays), the way `ListContinuation.marker` does.
- Tracked: none

### S04-04 — `Glob.Pattern.matchesPath` is a bare string prefix, broader than the documented "that folder and everything under it"
- Where: `Sources/Core/Query/Glob.swift:42,88`
- Category: correctness
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: a wildcard-free `path()` matches by `SearchQuery.fold(path).hasPrefix(folded)` (`:42`), a plain string prefix, while the doc at `:88` promises the folder and its descendants and ADR-0009's own example is `from: path("Clienti")`. `ViewEvaluator` uses it for the scope (`ViewEvaluator.swift:243`) and for the `path` term (`:309`).
- Trigger: `from: path("Clienti")` also scopes `Clienti-archivio/…` and `Clienti 2023/…`; `path("Note/Acme")` also takes `Note/Acme-2.md`; `path("Cli")` silently takes the whole folder.
- Fix: `folded == path || path.hasPrefix(folded + "/")`, accepting a pattern written with a trailing slash; one test with a sibling folder that shares the prefix.
- Tracked: none (chain 7 / PG-260 fixed the tag side only)

### S04-05 — A person's regular expression runs on the main actor with no bound, in Find and in `regex:` search
- Where: `Sources/Core/Editor/NoteFind.swift:121-125`, `Sources/Core/Search/SearchQuery+Matching.swift:43-45`, `Sources/Features/Editor/FindSession.swift:14,104`, `Sources/Vault/VaultSession+Search.swift:80`
- Category: performance
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: both sites compile the pattern as written into `NSRegularExpression` and run it on the main actor: Find on every query change (`FindSession` is `@MainActor`, `:104`), search inside chain 7's cooperative loop, which yields between chunks but cannot interrupt one match. ICU's matcher backtracks exponentially on nested quantifiers and neither site bounds the pattern or the input.
- Trigger: Find with regex on and the pattern `(a+)+$` over a note with a line of forty `a` and a `b`: the window freezes for seconds to minutes; `regex:(a+)+$` in global search does the same over the whole vault.
- Fix: cheapest, refuse nested quantifiers and cap the pattern length where `parseRegex` already validates by compiling; real one, run the regex pass off the main actor with a cancellation check, which revisits the residual ADR-0041 §D12 accepted for search.
- Tracked: none (chain 7's named residuals are `text()` and `unlinkedMentions`, not this)

### S04-06 — `NoteOutline.bodyStart` and `Transclusion.bodyStart` are one helper written twice, and both parse the whole document to find an index
- Where: `Sources/Core/Markdown/NoteOutline.swift:73-77`, `Sources/Core/Markdown/Transclusion.swift:172-176`
- Category: simplification
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: identical private helpers: `NoteDocument.parse(text)` then `text.index(text.endIndex, offsetBy: -document.body.count)`. `FrontmatterSource.document(from:)` splits the whole text with `components(separatedBy: "\n")` and joins the body back, two O(n) copies plus an O(n) index walk, to find one index on every `NoteOutline.entries` (`:39`) and every `Transclusion.occurrences(in:)` (`:137,144,197`; the whole-text form is called from `NoteTextView+Transclusion.swift:207`). `NoteFrontmatter.range` answers the same question without copying but with the other delimiter rule (S04-01), so today the outline and the styler can place the body start differently on the same note.
- Trigger: n/a
- Fix: one `NoteFrontmatter.bodyStart(in:)` on the canonical delimiter test, used by both; the two private helpers go.
- Tracked: none

### S04-07 — `MarkdownInlineParser` on a pathological delimiter run: unbounded recursion and a forward closing scan per opener
- Where: `Sources/Core/Markdown/MarkdownInline.swift:185`, `Sources/Core/Markdown/MarkdownInline+Emphasis.swift:53-55,87`
- Category: performance
- Severity: P3 · Confidence: suspected
- In flight: no
- What: `emphasis(at:)` (`:185`) recurses into its content for nested emphasis with no depth cap, and `closingRange` (`:53`) scans forward with `while let found = search.range(of: marker)` (`:55`), hopping nested strong runs through `nestedStrongEnd` (`:87`). An opener that finds no closer scans to the end of the paragraph; the scanner then advances one character and the next opener scans again, O(n²) over the paragraph for a run of unclosed openers, and a chain `*a *b *c …` recurses once per level. ADR-0091 restyles per touched paragraph, so a 1 MB single-line paragraph is the worst case; neither the time nor the stack depth of a 10 000-level nest was measured (the editor's pass runs on the main thread with an 8 MB stack, an index-side caller on a cooperative thread with 512 KB).
- Trigger: n/a (a line of `*a ` repeated 10 000 times is the shape)
- Fix: the CommonMark delimiter-stack algorithm is linear and iterative; short of that, draw a paragraph above a size threshold plain and give the recursion a depth cap.
- Tracked: none

### S04-08 — `TaskListOptions` justifies two mechanisms with "`sorted(by:)` is not stable", which the installed stdlib's own documentation contradicts
- Where: `Sources/Core/Tasks/TaskListOptions.swift:203,364`
- Category: docs
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: both comments state that `sorted(by:)` is not stable and justify on it the composite sort key (`:203`) and the `stableByStarred` partition instead of a comparator (`:364-367`). The toolchain disagrees: Xcode's `MacOSX.sdk/usr/lib/swift/Swift.swiftmodule/*.swiftdoc`, read 2026-10-30, documents the sorting algorithm as guaranteed to be stable. The code still works; the reason recorded for its shape is wrong, and the next reader keeps a partition for a guarantee the library already gives.
- Trigger: n/a
- Fix: correct both comments; optionally fold `stableByStarred` into the comparator with one test that pins the order among ties.
- Tracked: none

### S04-09 — `TaskParser.reminder` cites a settings-held reminder hour that does not exist
- Where: `Sources/Core/Tasks/TaskParser.swift:217-219`
- Category: docs
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: the comment says a time-less `@remind(date)` takes "the user's preferred hour" from the settings (SPEC §12); the code returns a hard-coded `hour: 9` (`:219`), `reminder(in:)` takes no settings, and no such setting exists (`VaultSettings.swift` and `Sources/Features/Settings` have no reminder hour; SPEC §12 has only `@remind(2026-08-15 09:00)` at `:359` and the UserNotifications row at `:373`).
- Trigger: n/a
- Fix: either the setting the comment promises (the hour becomes a parameter of `parse`) or a comment that says 09:00 is the default.
- Tracked: none

### S05-05 — `PraticaSyncPlan.workItems` still takes a `settings` parameter it never reads
- Where: `Sources/Core/Pratiche/PraticaSyncPlan.swift:47`
- Category: dead-code
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: ROADMAP chain 13 item 1 lists `PraticaSyncPlan.swift:47 settings` as genuinely dead; PG-266 closed that chain, but the parameter is still declared and passed by `PraticaSyncEngine.swift:122`. Periphery agrees.
- Trigger: n/a
- Fix: drop the parameter and the argument at the one caller.
- Tracked: regression of PG-266

### S05-06 — Unsigned integers above Int64.max wrap negative in `JSONValue`
- Where: `Sources/Core/Canvas/JSONValue.swift:31`
- Category: correctness
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: for an integral NSNumber whose double is not exact, the value is stored as `.integer(value.int64Value)`. JSONSerialization parses `18446744073709551615` and `9223372036854775808` as unsigned (`objCType "Q"`), whose `int64Value` is `-1` and `Int64.min` (probe-checked), so the canvas is re-saved with a different number. PG-279 promised big integers kept exact.
- Trigger: a `.canvas` with an extra key `"pergamenum-x": 18446744073709551615` (or a foreign tool's u64 id) → saved back as `-1`.
- Fix: keep unsigned values as `.unsigned(UInt64)` or preserve the literal text for any integer outside Int64.
- Tracked: regression of PG-279

### S05-07 — HTMLTokenizer is quadratic on `<` without a later `>`
- Where: `Sources/Core/Email/HTMLTextReducer.swift:65`, `Sources/Core/Email/HTMLTextReducer.swift:57`
- Category: performance
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: on each `<`, `firstIndex(of: ">", from: index, ...)` scans to the end; when there is none it appends one character and advances by one, so n unmatched `<` cost O(n²). The `<!` branch has the same shape through `end(of:)`. Input is external HTML.
- Trigger: an HTML part of a few MB of `<` characters (or a long comparison-heavy text with `<` and no `>`) → sync stalls on that message.
- Fix: once a search fails, remember that no `>` exists past that point and emit the rest as text.
- Tracked: none

### S05-08 — `EmailHeaderParser.parse` splits the whole text before stopping at the blank line
- Where: `Sources/Core/Email/EmailHeaders.swift:72`, `Sources/Core/Email/EmailHeaders.swift:53`
- Category: performance
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: the doc says only headers are read "so a message with a 20 MB attachment costs the same as an empty one", but line 72 runs `replacingOccurrences` and `components(separatedBy: .newlines)` over the entire input before the loop breaks. Three callers pass whole `.eml` text (`VaultController+Import.swift:38`, `WorkspaceController+Import.swift:38`, `WorkspaceController+Files.swift:58`).
- Trigger: importing or dropping a 30 MB `.eml` → two full copies plus a line array of the attachment base64 on the main actor.
- Fix: cut at the first blank line (`\r\n\r\n` / `\n\n`) before normalising, as `PraticaSyncEngine+Context` already does via `headerText(of:)`.
- Tracked: none

### S05-09 — Whole-message copies in EMLX and MIME parsing
- Where: `Sources/Core/Email/EMLXReader.swift:82`, `Sources/Core/Email/EMLXReader.swift:89`, `Sources/Core/Email/MIMEDecoder.swift:128`
- Category: performance
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `Array(rfc822)` for the separator search, `String(decoding: rfc822[body...])` for the body state and `Array(body)` per multipart level each copy the full message; nested multiparts copy again at each level. PG-141 fixed per-line allocations; these whole-buffer copies remain (the 2026-09-11 item `perf-MIMEDecoder.swift-33c` was skipped).
- Trigger: a 50 MB message with three multipart levels → several hundred MB transient during sync.
- Fix: search the `Data` directly (`range(of:)`) and pass slices/indices down instead of arrays.
- Tracked: none

### S05-10 — `attachmentFileName` has no length cap
- Where: `Sources/Core/Pratiche/PraticaNaming.swift:97`
- Category: correctness
- Severity: P3 · Confidence: suspected
- In flight: no
- What: the attachment name is sanitised (`lastPathComponent`, illegal set to `-`) but not shortened, unlike `messageFileName` (slug cap 40) and `ContenitoreNaming.stem`. A name over 255 bytes UTF-8 after the date prefix fails the atomic write with ENAMETOOLONG, which the engine reports as a problem sentence on every sync.
- Trigger: attachment `filename*=UTF-8''` with 120 accented characters → write fails each run, attachment never placed.
- Fix: cap the stem by UTF-8 byte length keeping the extension, as `ContenitoreNaming.stem` does.
- Tracked: none

### S05-11 — Unlisted charsets decode as UTF-8
- Where: `Sources/Core/Email/MailCharset.swift:30`
- Category: correctness
- Severity: P3 · Confidence: suspected
- In flight: no
- What: the table covers UTF-8, Latin-1/2/9, CP1252 and ASCII; everything else (`windows-1250`, `koi8-r`, `iso-2022-jp`, `gb2312`, `shift_jis`, `windows-1251`) reads as UTF-8 and becomes U+FFFD runs. `CFStringConvertIANACharSetNameToEncoding` would resolve them; ADR-0065 §D7 item 2 consolidated the table but does not exclude other charsets.
- Trigger: a message from a Czech or Russian correspondent in `windows-1250`/`koi8-r` → note body full of replacement characters.
- Fix: fall back to `CFStringConvertIANACharSetNameToEncoding` before defaulting to UTF-8.
- Tracked: none

### S05-12 — Duplicated pratiche frontmatter helpers
- Where: `Sources/Core/Pratiche/DossierYAML.swift:86`, `Sources/Core/Pratiche/MessageDocument+Reading.swift:78`, `Sources/Core/Pratiche/MessageFrontmatterPatch.swift:66`, `Sources/Core/Pratiche/MessageDocument.swift:230`, `Sources/Core/Pratiche/DossierYAML.swift:125`, `Sources/Core/Pratiche/PraticaTrayModel.swift:69`, `Sources/Core/Pratiche/PraticaSyncPlan.swift:115`, `Sources/Core/Pratiche/MembershipRule.swift:145`
- Category: simplification
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: the top-level-key predicate (`!hasPrefix(" ") && !hasPrefix("\t")`) exists three times, the scalar quote/unquote codec twice (`MessageDocument.quoted`/`+Reading.unquoted` and `DossierYAML.quoted/unquoted`), and the message `date(of:)` rule three times (`PraticaTrayModel` says it copies `MembershipRule`'s because that one is `private`). PG-275/PG-314 fixed escaping bugs that arose from exactly this split.
- Trigger: n/a
- Fix: one `PraticaYAMLScalar` codec and one internal `MembershipRule.date(of:)` shared by the three sites.
- Tracked: none

### S06-04 — The pratica create-and-link verbs rehearse and report one write while performing two or three
- Where: `Sources/Connector/VaultPraticheLinks.swift:276-286`, `Sources/Connector/VaultPraticheLinks.swift:389`, `Sources/Connector/VaultPraticheLinks.swift:263-267`, `Sources/Connector/VaultPraticheLinks.swift:322-326`
- Category: correctness
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `createAndLinkPraticaTask` writes the inbox note (`captureTask`, `:276`), may rewrite it again to assign a `^id` (`ensuringLocalID`, `:389`, whose `WriteResult` is discarded with `_ =`), then returns only `updateLinks`'s summary of `pratica.md` (`:283`). Under `dryRun` the reply shows the pratica diff and nothing of the task line that would be appended or of the `^id` suffix; `naming` (`:334-342`, ADR-0063 §D6) was added for the note and board verbs and not for the task one, and `pratica_link_task`/`perg pratica link-task` on a task without `^id` has the same hidden note rewrite in both modes. In a real run of the note and message verbs (`:263-267`, `:322-326`) a refusal from the link step after `createNote` succeeded names only the link, so the created note is not mentioned and a retry creates a second one.
- Trigger: `pratica_create_task{pratica:"Offerta 2026", text:"Chiamare Rossi"}` with `dryRun` omitted → a diff of `pratica.md` only; with `dryRun:false` → three writes, one reported.
- Fix: route the task verb through `naming` with the inbox path and the `^id` fact; let `ensuringLocalID` return its `WriteResult` so the summary carries the second diff; on a failed link after a successful create, prefix the refusal with «creato «path»».
- Tracked: none (ROADMAP Chain 16 item 1 names `ensuringLocalID` for the editor-sync problem absorbed by ADR-0067, not for this)

### S06-05 — A task needle containing `:` followed by digits is parsed as `path:line` and never text-matched
- Where: `Sources/Connector/VaultLookup.swift:58-61`
- Category: correctness
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `task(_:matching:)` treats any needle whose last `:` is followed by an integer as `percorso:riga`, so free text with a time in it becomes a path and a line number and the lookup refuses with «nessun task a …» instead of matching the task's text, which the doc comment at `:51` promises for "anything else".
- Trigger: `perg task done "riunione alle 10:30"` or `complete_task{task:"riunione alle 10:30"}` with exactly one such task → «nessun task a riunione alle 10:30».
- Fix: take the `path:line` route only when the path half names an indexed note (`session.index.notes[path] != nil`); otherwise fall through to the text match.
- Tracked: none

### S06-06 — Four connector reads turn every refusal into «non esiste»
- Where: `Sources/Connector/VaultReads.swift:20-21`, `Sources/Connector/VaultNoteBirth.swift:39`, `Sources/Connector/VaultNoteBirth.swift:76`, `Sources/Connector/VaultWrites.swift:331-332`
- Category: correctness
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `guard let (record, text) = try? session.read(path)` discards the thrown reason, so a `VaultBoundary.Violation` (`../x.md`, an absolute path), a file that does not decode and a missing file all come back as «non riesco a leggere», «non esiste» or «non c'è più». A model told that a note does not exist searches for it instead of fixing its path; `undo_write` reports an existing file that no longer decodes as gone. ADR-0063 made the connectors refuse with a sentence; these sites drop the sentence the vault layer already produced.
- Trigger: `read_note{path:"../../Desktop/x.md"}` → «non riesco a leggere «../../Desktop/x.md»» rather than that it is outside the vault; `classify_note` on a note with invalid UTF-8 → «non esiste».
- Fix: `do { try session.read(path) } catch { throw ConnectorError("\(error)") }`, keeping the missing-file sentence only for the missing case.
- Tracked: none

### S06-07 — `resources/list` answers from the index of the last tool call, never rescanned
- Where: `Sources/MCPServer/VaultHost.swift:292-293`, `Sources/MCPServer/VaultHost.swift:11-14`
- Category: correctness
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `call` rescans before every tool (`:53`), but `resources(after:)` reads `session.index.allNotes` as it was after the last rescan (`:293`) and the server has no watcher. A note created or renamed in the app after the model's last tool call is absent from, or stale in, `resources/list` until any `tools/call` happens, against the header comment "The vault is rescanned before every call" (`:11`). `resource(at:)` (`:318-326`) is fresh for content (`VaultAPI.note` reads the file) and stale only in the `NoteSummary` metadata.
- Trigger: start the server, create a note in the app, `resources/list` → not listed; any tool call, then `resources/list` → listed.
- Fix: make `resources(after:)` `async` and `await session.rescan()` on the first page (`cursor == nil`) so paging stays consistent, inside the same serialization as S06-01; or state the staleness in the header and in `instructions`.
- Tracked: none

### S06-08 — `VaultAPI.praticaMessageLink` is reachable from neither connector: tests are its only callers
- Where: `Sources/Connector/VaultPraticheLinks.swift:65-66`
- Category: dead-code
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: The per-message link read (R-08) is defined on `VaultAPI`, but no CLI command (`main.swift:111-121` routes `message` to writes only) and no MCP tool calls it; `Tests/PraticheLinksConnectorTests.swift` (eight call sites) is its only consumer and the app has its own path. It is a capability `Sources/Connector` holds that neither front end translates, the shape ADR-0007 §D3 cannot see from the front ends.
- Trigger: n/a
- Fix: expose it (`perg message link <percorso>`, MCP `message_link`, both read-only) or delete it with its tests; `pratica_links` already lists the pratica-level relations.
- Tracked: none

### S06-09 — `IndexSnapshot.allNotes` re-sorts the whole vault with `localizedStandardCompare` on every access, and 43 call sites read it, several per redraw
- Where: `Sources/Index/IndexSnapshot.swift:105-107`, `Sources/Index/IndexSnapshot.swift:65-67`
- Category: performance
- Severity: P3 · Confidence: suspected
- In flight: no
- What: `allNotes` is a computed property doing an ICU-collated sort of `notes.values` on each call. `update(_:at:)` already rebuilds every derived index on each change and bumps `generation` (`:65-67`), so a stored sorted array would cost nothing extra there; instead every reader repeats the sort: `TodayView.swift:68-69`, `EditorColumnView.swift:109-110` and `DiaryView.swift:52,114` read it twice in a row, `NoteListPane.swift:399,498,558,563` per filter or tree rebuild, `CategoryNotePicker.swift:74` sorts the vault to answer `.isEmpty`, and `list_notes`/`resources/list` (`VaultReads.swift:13`, `VaultHost.swift:293`) once per call. ADR-0072 keyed index-derived caches by `generation`; this, the most-read derived value, is the one left uncached. Not measured.
- Trigger: n/a
- Fix: a `private(set) var allNotes: [NoteRecord]` rebuilt in `rebuildDerivedIndexes()`, with emptiness answered from `notes` directly.
- Tracked: none (PG-138, closed by ADR-0072, materialised `allTasks` and `taskCounts`, not `allNotes`)

### S06-10 — `EventKitStore.fetch` dereferences `event.calendar` without a check
- Where: `Sources/Calendar/CalendarService.swift:196-197`, `Sources/Calendar/CalendarService.swift:310`
- Category: correctness
- Severity: P3 · Confidence: suspected
- In flight: no
- What: `EKEvent.calendar` is an implicitly unwrapped `EKCalendar!`; `fetch` reads `event.calendar.title` and `.allowsContentModifications` for every event the predicate returns, while `createEvent` guards the same property (`guard event.calendar != nil`, `:310`), so the code treats it as nullable in one place and not in the other. An event whose calendar goes away between `events(matching:)` and the map (an account signed out while the day loads) traps the app; the shape is the force-unwrap `rules/swift.md` forbids in production. Not reproduced.
- Trigger: n/a (not traced to an input)
- Fix: `event.calendar?.title ?? "(senza calendario)"` and `event.calendar?.allowsContentModifications ?? false`.
- Tracked: none

### S06-11 — Help texts and two comments still place the journal and the cache inside `.pergamenum/`
- Where: `Sources/CLI/Help.swift:145`, `Sources/MCPServer/main.swift:33-34`, `Sources/Index/IndexCache.swift:4`, `Sources/Index/IndexSnapshot.swift:23`
- Category: docs
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `perg help` and the MCP `instructions` say every write is recorded in `.pergamenum/ai-journal/`; the two index files say the cache is `.pergamenum/cache.db`. Since ADR-0017 (PG-004) both live under `~/Library/Application Support/it.stefer.pergamenum/vaults/<id>/` (`VaultState.journal`; `VaultWrites.swift:371-376` says so for the journal). A person following the help text to inspect or back up the journal looks in a folder that holds nothing of the kind.
- Trigger: n/a
- Fix: name the Application Support location in both help texts (or point at `perg journal log`), and fix the two comments.
- Tracked: none (PG-267, chain 14, closed, covered SPEC and ADR consistency, not these)

### S06-12 — The MCP `instructions` deny rename, move and trash tools the catalogue exposes
- Where: `Sources/MCPServer/main.swift:36-37`, `Sources/MCPServer/ToolCatalogue+Writing.swift:48-99`
- Category: docs
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: The text handed to every client says «Non ci sono: rinomina, spostamento ed eliminazione di note, che riscrivono i link in molte note in una volta e che il journal non copre per intero», while `rename_note`, `move_note` and `trash_note` are listed under `--allow-write` and the journal covers them as one operation (`Help.swift:146-148` says exactly that for `perg`). A model reading the instructions refuses or works around a tool it has.
- Trigger: n/a
- Fix: delete the sentence, keep the Calendar clause (still true, ADR-0007).
- Tracked: none

### S07-01 — «Riferimento dove sono» is a radio button nothing reads: every drop import copies
- Where: `Sources/Features/Settings/CanvasSettings.swift:26-33`, `Sources/Vault/VaultSettings.swift:67`, `Sources/App/VaultController+Import.swift:65`, `Sources/Features/Workspace/WorkspaceController+Import.swift:86`, `Sources/Vault/VaultSession+Notes.swift:159`
- Category: correctness
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: The Canvas tab's «File trascinati» picker writes `copyDroppedFiles` into `settings.json` and offers «Riferimento dove sono» (`.tag(false)`), but the setting's only readers are the picker's own getter and `VaultSettings`' encoder and decoder: `grep -rn copyDroppedFiles Sources` finds nothing else, and all three import sites call `FileManager.copyItem` unconditionally. SPEC line 265 says the drop is "copia secondo impostazione"; the setting is persisted and honoured by nobody, so the reference option yields a copy and the caption's warning about references breaking describes a behaviour the app cannot produce.
- Trigger: Impostazioni › Canvas › File trascinati = «Riferimento dove sono», then drop a file on a board or into the editor: the file is copied.
- Fix: Either implement the branch (the three import sites read the setting and write a reference instead of copying) or remove the picker and decode-and-ignore the key in `VaultSettings` for existing files, amending SPEC line 265. The second is one-sided and cheap; the choice belongs to the spec owner.
- Tracked: none

### S07-02 — A vault theme file named `pergamenum-light.json` replaces the bundled theme for the whole process and leaks into the next vault
- Where: `Sources/DesignSystem/ThemeEngine.swift:296-298`, `Sources/DesignSystem/ThemeEngine.swift:114`, `Sources/DesignSystem/ThemeEngine.swift:304-306`, `Sources/DesignSystem/ThemeEngine.swift:279-281`
- Category: correctness
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `loadUserThemes` keys a user theme on its file name (`:278`) and composes `themes = bundled.filter { !userIDs.contains($0.id) } + added` (`:298`), so a vault file named after a bundled id drops the genuinely bundled theme from `themes`, and nothing reloads the bundle after `init` (`:73`). `detachVault()` keeps every id with the `pergamenum-` prefix (`:114`), so that file survives into the next vault, where `base(for: .light)` resolves it by id (`:305`): every light rendering and every other user theme's inheritance base (`:288`) now come from the previous vault's file until relaunch, and the pickers filter the prefix out (`SettingsView.swift:113`, `MenuCommands.swift:357`, `HistoryToolbar.swift:70`), so the person sees a theme they cannot name or deselect. The comment at `:279-281` states the opposite of `:298` ("the bundled version is the inheritance base instead of being dropped from the list") and invites exactly this file name.
- Trigger: Put a valid partial `pergamenum-light.json` in `<vault>/.pergamenum/themes/`, open the vault, then open another vault.
- Fix: Hold the bundled pair in their own stored property and compose `themes = bundledThemes + userThemes` on every load; resolve `base(for:)` against the bundled pair only; have `detachVault()` reset to it; refuse (or suffix) a user id that collides with a bundled one and report it in `problems`. The comment at `:279-281` then becomes true.
- Tracked: none

### S07-03 — «Cartella daily» and «Cartella diario» trim on every keystroke, the defect the same file documents for the inbox field
- Where: `Sources/Features/Settings/SettingsView.swift:132-139`, `Sources/Features/Settings/SettingsView.swift:143-150`, `Sources/Features/Settings/SettingsView.swift:335-338`
- Category: correctness
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: Both setters write `value.trimmingCharacters(in: .whitespaces)` and the getter hands the trimmed value back to the field, so a trailing space vanishes before the next character arrives and a folder with an inner space («00 Daily», «Diario 2026») cannot be typed. `InboxFolderField` (`:339-348`) in the same file carries a comment (`:335-338`) explaining exactly this and stores as typed, trimming on read; ADR-0080 §D6 fixed the inbox field only and the two older fields were not brought in line.
- Trigger: Impostazioni › Convenzioni › Cartella daily, type `00 Daily`: the space is eaten.
- Fix: Store as typed in both setters and trim where the value is read, as the inbox field does; one test per field typing a two-word name through the binding.
- Tracked: none

### S07-04 — An emptied «I miei indirizzi» list is refilled from the Mail store on every visit, the opposite of what the comment promises
- Where: `Sources/Features/Settings/PraticheSettingsTab.swift:177-179`, `Sources/Features/Settings/PraticheSettingsTab.swift:190-202`
- Category: correctness
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: The doc comment says the prefill runs "only while the list is still empty - a person's own deletions (down to zero) must not be silently repopulated on every visit", but the first guard is `guard vault.settings.pratiche.ownAddresses.isEmpty else { return }` (`:191`): the function proceeds exactly when the list is empty, so removing every own address and reopening the tab publishes a copy of the Mail store again (`Task.detached` at `:200-202`, the 355 MB-scale read the comment itself names) and writes the addresses back. There is no "prefilled once" marker in the settings, so the comment's two sentences cannot both hold with this guard.
- Trigger: Impostazioni › Pratiche with full disk access granted and a vault open: «Rimuovi» every address, close and reopen the tab.
- Fix: Persist a `ownAddressesPrefilled` flag (or date) in the pratiche settings, set it after the first successful prefill and gate on it; or drop the second sentence of the comment and accept both the repopulation and the Mail-store copy per visit.
- Tracked: none

### S07-05 — A refused board undo is reported as done
- Where: `Sources/Features/Views/ViewBoardRenderer.swift:169-176`, `Sources/Features/Editor/ViewQuerySource+Live.swift:30`
- Category: correctness
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: The drop banner's «Annulla» runs `_ = await undo(id)` and then clears `lastDrop` and calls `onWrite()` whatever the result; the closure it discards is `vault.undoJournalledWrites([id]).failures.isEmpty` (`ViewQuerySource+Live.swift:30`), which is `false` when the journal refuses because the note moved on since the drop (ADR-0016's rule). The banner disappears and the board re-evaluates as if the move were undone while the file keeps the moved task; `TagBrowserView.swift:370-372` handles the same `failures` by recording them as problems.
- Trigger: Drop a task onto another column, change that note (in a tab or externally), press «Annulla» on the banner.
- Fix: Keep the result: on `false` show a refusal banner (`isRefusal: true`, "annullamento rifiutato: la nota è cambiata") and skip `onWrite()`, or route the failures through `vault.recordProblem` as the tag browser does.
- Tracked: none

### S08-02 — The composer reads the template file from disk and resolves it on every body evaluation
- Where: `Sources/Features/Editor/NewNoteComposer.swift:147`, `Sources/Features/Editor/NewNoteComposer.swift:211-212`
- Category: performance
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `fields` (inside `body`) calls `resolvedTemplate(at: Date())`, which does `try? vault.session?.read(template).text` (synchronous disk read on the main actor) plus `NoteTemplate.resolve`. With a template chosen, every keystroke in the title field (which feeds `trimmedTitle` and so the body) repeats the read and the resolve.
- Trigger: n/a
- Fix: cache the template text in `@State` keyed by the template path (`.task(id: template)`), resolve from the cached text; `create()` (`:265`) can re-read once.
- Tracked: none

### S08-03 — The scheda's topic field re-implements tag entry instead of `TagEntry`, with different refusals
- Where: `Sources/Features/Editor/ClassificaSheet.swift:166-193`, `Sources/Features/Editor/NoteClassificaForm.swift:131-148`, `Sources/Features/Editor/NewNoteComposer+Tags.swift:61-88`
- Category: simplification
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: the note face and the composer go through `TagEntry.completions`/`TagEntry.check` (vocabulary, date-tag and namespace refusals with their Italian sentences); the scheda face builds `Tag("topic-…")` by hand, prefix-filters `tagUsage()` itself and has its own message («… non è un argomento valido.»). A date-shaped topic is accepted into the chip row and refused only later by `ContenitoreClassification` (`dateTopic`), with a different sentence than the note face gives at entry. Two implementations of one rule, the drift ADR-0085 §D5 meant to avoid. All three faces also call `index.tagUsage()` (full pass + sort) per body evaluation, i.e. per keystroke in the field.
- Trigger: type `topic-2026-10-31` in the scheda's «Classifica» → accepted as a chip; the same text in the note's «Classifica…» is refused at entry.
- Fix: route `suggestions`/`addTopic` through `TagEntry.completions`/`TagEntry.check(allowing: [.topic])`, keep «Crea «X»» as the creation verb; hold `tagUsage()` in state keyed by `indexGeneration` (ADR-0072).
- Tracked: none

### S08-04 — «Nuova cartella» in the Note sidebar writes through `CanvasStore` from the view
- Where: `Sources/Features/Editor/NoteListPane+FolderVerbs.swift:92-100`
- Category: house-rules
- Severity: P3 · Confidence: suspected
- In flight: no
- What: rename and trash of a folder go through `VaultController` (`renameFolder`, `trashFolder`), but creation constructs `CanvasStore(root:)` in the view, writes, then fires `Task { await vault.rescan() }` without awaiting. ADR-0022 allows folder ops outside the journal, not outside the controller; the boundary check depends on `CanvasStore` (graded in S02/S10), and the name is validated only by the sheet (PG-047's note).
- Trigger: n/a
- Fix: a `VaultController.createFolder(named:in:)` beside its siblings, reused by `WorkspaceView+FolderVerbs`.
- Tracked: none

### S08-05 — Outline-move save is documented as awaited but is fire-and-forget
- Where: `Sources/Features/Editor/EditorColumn+Text.swift:185-187`
- Category: docs
- Severity: P3 · Confidence: confirmed
- In flight: yes
- What: the comment says «The save is awaited rather than fired and forgotten (ADR-0043 §D2): it has to complete before anything else touches the buffer», but the synchronous `replacementsApplied()` spawns `Task { @MainActor in await vault.saveOpenNote() }` and returns; nothing after it waits. Either the comment is wrong or the guarantee is missing (a keystroke can land between the move and the save, which then saves both, harmless; a tab switch in between is the case to check).
- Trigger: n/a (ordering not traced to a loss)
- Fix: correct the comment to what the code does, or make the caller async and await it.
- Tracked: none

### S08-06 — Two contradictory threading premises for the delegate's stores
- Where: `Sources/Features/Editor/EditorGutter.swift:55-58`, `Sources/Features/Editor/EditorDecorationDelegate.swift:190-269`, `Sources/Features/Editor/EditorDecorationDelegate+CalloutRendering.swift:128`
- Category: correctness
- Severity: P3 · Confidence: suspected
- In flight: yes
- What: `MarkerRunWidths` is a lock-guarded `@unchecked Sendable` box because "TextKit calls [the delegate] from its layout pass, so a bare `nonisolated(unsafe)` dictionary would be a data race". The delegate itself keeps ~30 bare `nonisolated(unsafe)` stores, and `calloutTitle(above:in:)` writes the `calloutRunHeads` memo from that same layout pass (`:128`) with no lock, while the main actor clears it through `hiddenMarkers`' `didSet` (`EditorDecorationDelegate.swift:223-224`). If layout can run off the main thread, the memo (and every store) is racy; if it cannot, the lock is dead weight and its comment is wrong. Every store write traced in this slice is on the main thread (`apply(…)`, `shift`, `splice`, all from the Coordinator); no off-main layout was found.
- Trigger: n/a
- Fix: pick one premise and apply it to every store: either assert main-thread layout (and drop the lock, fix the comment), or guard the layout-pass memos the way `MarkerRunWidths` is guarded.
- Tracked: none

### S08-07 — Every selection change with a non-empty selection parses all code fences of the note
- Where: `Sources/Features/Editor/CompletingTextView+FormatBar.swift:16`, `Sources/Features/Editor/CompletingTextView+FormatBar.swift:81-87`
- Category: performance
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `refreshFormatBar` runs on every selection change (the file's own comment: "every arrow key"); with a selection it calls `isInsideCodeFence`, which runs `CodeFence.regions(in: text)` over the whole note and converts each region to `NSRange`. Shift+arrow in a 1 MB note is a whole-note scan per key, the cost class PG-401 is removing from typing.
- Trigger: n/a
- Fix: read the fence state from the styling pass's spans already held by the Coordinator (the `.codeBlock` styled ranges), or cache regions per text revision (ADR-0096's revision).
- Tracked: none

### S08-08 — Each editor column walks the whole vault for board titles on every scan
- Where: `Sources/Features/Editor/EditorColumnView.swift:108-112`
- Category: performance
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `.task(id: vault.scanGeneration)` runs `CanvasStore(root:).allBoards()` (recursive `FileManager` walk, synchronous, main actor) per column; two columns walk twice, and `TodayView.swift:70` and `WorkspaceView+Board.swift:172` do the same walk for the same list. The audit-doc P1 (`perf-EditorColumn+Text.swift-8f5`) is fixed by moving it out of `body`, but the list still has no single owner.
- Trigger: n/a
- Fix: one board-title list on `VaultController` (or `WorkspaceController.wikilinkBoardTitles`) refreshed once per `scanGeneration`, read by every host.
- Tracked: none

### S08-09 — Layout-pass branches re-parse text per paragraph per layout
- Where: `Sources/Features/Editor/EditorDecorationDelegate+ListRendering.swift:183-186`, `Sources/Features/Editor/EditorDecorationDelegate+HeadingRendering.swift:56-59`, `Sources/Features/Editor/EditorDecorationDelegate+FenceRendering.swift:45-48`
- Category: performance
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `listParagraph` bridges the whole storage to a Swift `String` (`text as String`) and builds a `Range` from an `NSRange` (O(offset) in UTF-8) for every list paragraph laid out, then runs `ListNesting.level`; `titlelessHeadingRun` runs `MarkdownBlockParser.lineTokens` per heading marker per layout; the fence header copies the whole fence body string to count its lines. All three answers are already known to the styling pass. The list case is the audit-doc item `perf-MarkdownStyler.swift-c80` (marked skipped there), still present at a moved line.
- Trigger: n/a
- Fix: push list level, titleless-heading runs and fence line counts in with the hidden markers (same paragraph-keyed `OffsetTable`), so the layout branch only reads.
- Tracked: none

### S09-editor-b-01 — Every plain click walks every laid-out fragment of the note looking for a checkbox
- Where: `Sources/Features/Editor/NoteTextView+CheckboxClick.swift:29-56`
- Category: performance
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: the checkbox hit test enumerates layout fragments from the document start with `.ensuresLayout`, and for each one takes the paragraph substring and runs `checkboxStateOffset` before any test of whether the click's y falls inside that fragment. A click near the end of a long note forces layout of, and scans, every paragraph above it; `+FenceMenu.swift:49-55` (`clickedParagraph`) already finds the clicked fragment first.
- Trigger: a long note (thousands of lines, TextKit 2 laying out lazily), click in the last paragraph → layout ensured for the whole document and one substring + scan per paragraph on the main actor, per click.
- Fix: locate the fragment under the click (`textLayoutFragment(for:)` at the container point) and test only that paragraph.
- Tracked: none

### S09-editor-b-02 — Transclusion rendition cache keyed by width: every new column width re-reads the target from disk
- Where: `Sources/Features/Editor/NoteTextView+Transclusion.swift:309-318`, `Sources/Features/Editor/NoteTextView+Transclusion.swift:228-241`
- Category: performance
- Severity: P3 · Confidence: suspected
- In flight: no
- What: `rendition(for:width:theme:)` keys the cache `"\(reference)#\(section)@\(generation)|\(Int(width))"` and clears it only when the index generation moves. A width the cache has not seen is a miss that runs `source.resolve` (a `session.read`, i.e. a synchronous file read on the main actor, `TransclusionSource+Live.swift:28`) plus the `fitted` binary-search layout; the comment at `:300-302` reasons about keystrokes only. Entries for every width seen accumulate until the next save.
- Trigger: a note with N `![[…]]` lines; resize the window or the split so the column width passes through K integer widths while a styling pass runs → up to N×K disk reads and fits, and N×K cache entries held until a save. Whether a live resize reaches the transclusion pass was not traced (`observeWidthChanges` → `applyReadableWidth`, `+Coordinator.swift:706-720`), hence suspected.
- Fix: split the cache: resolved excerpt keyed by reference/section/generation (the disk half), fitted rendition keyed by width on top of it; or bound the width entries to the last one per occurrence.
- Tracked: none

### S09-editor-b-03 — Applying a template whose file can no longer be read closes the sheet and does nothing, silently
- Where: `Sources/Features/Editor/TemplateSheet.swift:64-67`
- Category: correctness
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `apply(_:)` sets `defer { vault.isChoosingTemplate = false }` and then `guard let note = vault.openNote, let text = try? vault.session?.read(template.relativePath).text else { return }`. A read failure is swallowed by `try?`: the sheet closes, nothing is inserted, no problem is recorded, so the click looks like it worked on a note that did not change.
- Trigger: open «Applica un template»; rename, delete or make non-UTF-8 the template file from Finder while the sheet is up (the list is `vault.templates`, which lags until a rescan) → click the row → sheet closes, caret position unchanged, no message.
- Fix: `do/catch` around the read and `vault.recordProblem(...)` on failure, as `VaultBrowser.open(_:)` does for the daily note (`VaultBrowser.swift:75-77`); keep the sheet open or say why.
- Tracked: none

### S09-editor-b-04 — Inspector history section lists the history directory on every inspector body pass
- Where: `Sources/Features/Editor/VaultBrowser+History.swift:18`, `Sources/Features/Editor/VaultBrowser.swift:196-201`, `Sources/Vault/NoteHistory.swift:78-84`
- Category: performance
- Severity: P3 · Confidence: suspected
- In flight: no
- What: `history(note)` calls `vault.session?.history.snapshotDates(for:)`, which is `FileManager.contentsOfDirectory` plus a parse of every name, inline in `VaultBrowser.inspector`. The inspector body reads `vault.openNote` (`focusedTab?.note`, whose `OpenNote` carries `text`, `NoteTab.swift:130-135`) and `note.text` (`categoryLink`, `:248`), so it plausibly re-evaluates on every keystroke while the inspector is open; `history` is a function call, not a child view with stable inputs, so diffing cannot skip it. The comment at `:15-16` guards against reading texts but still pays a directory listing per pass.
- Trigger: inspector open, type in a note with many snapshots → one directory listing per body evaluation on the main actor (whether each keystroke re-evaluates the inspector was inferred from the observed properties, not measured).
- Fix: move the section into a child view taking `relativePath` and an index/save generation, and memoise the dates on that key (ADR-0072's pattern); or read them in `.task(id:)`.
- Tracked: none

### S09-editor-b-05 — A view block committed from «Modifica query» into a CRLF note is written with LF fence lines
- Where: `Sources/Features/Editor/NoteTextView+ViewBlockEditing.swift:61`, `Sources/Features/Editor/NoteTextView+ViewBlockEditing.swift:72-76`
- Category: correctness
- Severity: P3 · Confidence: suspected
- In flight: no
- What: `commitViewBlock` builds the replacement as `"```\(ViewBlock.language)\n" + body + "\n```"` and `viewBlockBody` splits and rejoins on `"\n"`, so a note whose lines end in `\r\n` gets a fence whose own lines end in `\n`: mixed line endings in a file the app wrote. `commitTable` was fixed for exactly this through `LineBreak.detected` (PG-316, ADR-0065 §D3 "round-trips faithfully or is refused"); the view-block door was not. CRLF fences are recognised (`CodeFence.swift:91`), so the path is reachable.
- Trigger: a note saved with CRLF endings (Windows editor, some sync tools) containing a `pergamenum-view` fence → «Modifica query» → change a term → save → the fence's opening and closing lines are LF, the rest CRLF.
- Fix: detect the note's (or the fence's) line break with `LineBreak.detected` and use it for the two fence lines and the body join; strip a trailing `\r` per body line when splitting.
- Tracked: none

### S09-editor-b-06 — Transclusion caption font is a hardcoded 10pt system face, never pushed from a token
- Where: `Sources/Features/Editor/TranscludedLineFragment.swift:34`, `Sources/Features/Editor/TranscludedLineFragment.swift:54`, `Sources/Features/Editor/TranscludedLineFragment.swift:196`
- Category: house-rules
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `static var captionFont: NSFont { .systemFont(ofSize: 10, weight: .regular) }` draws the collapsed-row caption and the «… apri la nota» line, and `captionHeight` built from it feeds `reservedHeight`. Its colours come from tokens (`+Transclusion.swift:330-331`) but the font does not; the sibling `FoldedHeadingFragment.badgeFont` has the same default yet is overwritten from the theme each pass (`+Coordinator.swift:510` → `EditorDecorationDelegate.swift:489`). ROADMAP chain 9's font list does not name this file.
- Trigger: n/a
- Fix: carry the font on `TranscludedRendition` (set from `theme.nsFont(.caption)` in `rendition(for:)`, beside the colours) and measure `captionHeight` from that instance.
- Tracked: none

### S10-workspace-02 — Wikilink completion replaces a range counted in Characters against a UTF-16 caret
- Where: `Sources/Features/Workspace/CardWikilinkCompletion.swift:33`, `Sources/Features/Workspace/FormattingTextView.swift:261-272`
- Category: correctness
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `WikilinkTrigger.context` builds `NSRange(location: caret - prefix.count, length: prefix.count)`. `caret` is a UTF-16 offset and `prefix.count` counts Characters. In the same file, `closingInsertion` (`:42-46`) already uses `.utf16.count`. When the typed prefix holds a character outside the BMP or a multi-scalar grapheme, the range is too short, and `applyWikilinkCompletion` replaces the wrong span. That leaves part of the prefix behind, or splits a surrogate pair into U+FFFD. The note editor has the same shape (`CompletingTextView+Context.swift:153`, outside this slice).
- Trigger: in a sticky or text card type `[[😀ab`, pick a candidate → the card keeps a stray piece of the prefix, or a broken surrogate, before the inserted name.
- Fix: count the prefix with `prefix.utf16.count` for both location and length, and fix the editor twin with it.
- Tracked: none

### S10-workspace-03 — Board candidates with the same file name share an id in the completion popup
- Where: `Sources/Features/Workspace/CardWikilinkCompletion.swift:59`, `Sources/Features/Workspace/CardWikilinkCompletion.swift:121-125`, `Sources/Features/Workspace/BoardWikilinkCompletionLayer.swift:168`
- Category: correctness
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `WikilinkCandidate.id` is `"\(kind)-\(insertText)"`, and board candidates use the bare file name as `insertText`. Two boards with the same name in different folders get the same id, and the popup's `ForEach` then renders duplicate identities. SwiftUI can show one row twice, drop one, or move the highlight to the wrong row. Picking also inserts an ambiguous bare name.
- Trigger: boards `A/Piano.canvas` and `B/Piano.canvas`, type `[[Pia` in a card → two rows with one id; arrow-key highlight and pick become unreliable.
- Fix: derive `id` from the vault-relative path (or `displayTitle` plus path), and decide whether `insertText` for a duplicated name should carry the folder.
- Tracked: none

### S10-workspace-04 — CardTextView's coordinator lacks the stale-delegate guard the note editor gained
- Where: `Sources/Features/Workspace/CardTextView.swift:257`, `Sources/Features/Workspace/CardTextView.swift:280`, `Sources/Features/Workspace/CardTextView.swift:317`
- Category: correctness
- Severity: P3 · Confidence: suspected
- In flight: no
- What: `textDidChange`, `textViewDidChangeSelection` and `textDidEndEditing` act on any notification's `textView` without `guard textView.delegate === self`. The note editor added that guard in 4c802094 (`NoteTextView+Coordinator.swift:202`, `:291`) after a stale Coordinator wrote one view's state into another. A card's text view is reused and torn down as cards enter and leave editing (`CardTextView+Teardown.swift`), so the same shape is possible here. The trigger was not traced end to end. The auto-memory note on the editor fix names `CardTextView` as still lacking the guard; no ledger line tracks it.
- Trigger: n/a (suspected: a late end-editing or change notification from a torn-down card's text view committing into the card now being edited).
- Fix: add the same `guard textView.delegate === self` at the top of the three callbacks.
- Tracked: none

### S10-workspace-05 — Sticky colour fallback force-unwraps a hardcoded hex
- Where: `Sources/Features/Workspace/StickyTextCard.swift:138`
- Category: house-rules
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `let rgba = RGBA(hex: value) ?? RGBA(hex: "#E8E5DF")!` breaks two rules: no force unwrap in production, and no colour that bypasses a token. The fallback is also unreachable, because `CanvasColor.init?` only produces `.hex` when `RGBA(hex:)` succeeds (`JSONCanvas.swift:137-140`).
- Trigger: n/a
- Fix: unwrap the value without a fallback, or fall back to `theme.color(.stickyGrey)` the way the `.unrecognised` branch at `:144` does.
- Tracked: none

### S10-workspace-06 — Dropping an .eml decodes the whole message on the main actor
- Where: `Sources/Features/Workspace/WorkspaceController+Import.swift:32-41`, `Sources/Features/Workspace/WorkspaceView+Board.swift:52-54`
- Category: performance
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `propose(import:at:)` reads each dropped `.eml` with `Data(contentsOf:)` and decodes all of it into a `String` just to parse the headers. This runs synchronously on the main actor from the drop handler. A message with large attachments stalls the board for the length of the read and the decode. `+Files.headerBlock(of:)` (`:72-83`) already reads a capped 64 KB header block.
- Trigger: n/a (drop a 30 MB .eml on a board → visible hang before the import sheet appears).
- Fix: reuse `headerBlock(of:)` for the import proposal.
- Tracked: none

### S10-workspace-07 — Wikilink candidate pools refresh only on settings change and walk every board on appear
- Where: `Sources/Features/Workspace/WorkspaceView+Board.swift:157-173`
- Category: performance
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `applyBoardSettings()` sets `wikilinkNoteTitles` from `vault.index.allNotes` and `wikilinkBoardTitles` from a fresh `CanvasStore(root:).allBoards()` directory walk. It runs on appear and on a settings change only, not when the index changes. Notes and boards created or renamed while the pane is open never appear in card completion, and the comment at `:166-170` admits the staleness. Each pane appearance pays a full board walk on the main actor.
- Trigger: with a board open, create a note `Nuova` from the Note pane or the capture panel, then type `[[Nuo` in a card → no candidate until the Workspace pane is left and re-entered.
- Fix: key the refresh on `vault.indexGeneration` (ADR-0072 pattern, `VaultController.swift:24`) through `.task(id:)`, and take board names from the scan rather than a separate walk.
- Tracked: none

### S10-workspace-08 — Committing an unchanged text or title still mutates the board
- Where: `Sources/Features/Workspace/WorkspaceController+Nodes.swift:69-76`, `Sources/Features/Workspace/WorkspaceController+Nodes.swift:81-91`, `Sources/Features/Workspace/WorkspaceController+TextEditing.swift:25-31`
- Category: correctness
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `endTextEdit(commit: true)` always calls `setText`, and `setText`/`setTitle` always go through `mutate` with no equality check. `settleBoardEditing()` commits on every leave, so double-clicking a card and clicking away, or leaving a board with a card in edit, records a no-op undo step, marks the board `.pending`, and rewrites identical bytes. An «Annulla» then "undoes" nothing. The extra write is also one more chance to meet a concurrent writer (see S10-workspace-01).
- Trigger: double-click a sticky, press nothing, click the canvas → «Annulla» becomes enabled and the indicator shows "Salvataggio…".
- Fix: return early from `setText`/`setTitle` when the new value equals the node's current one.
- Tracked: none

### S10-workspace-09 — Re-editing a drawing keeps the card's old origin while its size follows the new bounds
- Where: `Sources/Features/Workspace/WorkspaceController+Drawing.swift:71-77`
- Category: correctness
- Severity: P3 · Confidence: suspected
- In flight: no
- What: when a drawing card is reopened and saved, the existing node gets the new `width`/`height` from `bounds`, but `x`/`y` stay as they were. New-card creation uses `bounds.minX`/`minY`. If the strokes now start left of or above the old origin, the card is offset from the ink it shows. Whether the SVG's viewBox re-bases strokes to the card was not traced.
- Trigger: n/a (suspected: reopen a drawing, add a stroke above-left of the card, «Fatto» → card frame shifted against the ink).
- Fix: also set `x`/`y` from `bounds`, or confirm the encoding re-bases and document it.
- Tracked: none

### S10-workspace-10 — Three types over the SwiftLint size limits
- Where: `Sources/Features/Workspace/WorkspaceBrowser.swift:109-222`, `Sources/Features/Workspace/FormattingTextView.swift:14-363`, `Sources/Features/Workspace/WorkspaceController.swift:1`
- Category: simplification
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `WorkspaceBrowser.body` is 114 lines. The `FormattingTextView` class body runs from `:14` to `:363`, above the 250-line type body limit, and its own comment says so (`FormattingTextView+Accessibility.swift:17-18`). `WorkspaceController.swift` is 632 lines against the 400-line file limit. PG-146 closed the earlier structure items; ADR-0045 §D1 accepts the `WorkspaceController` file length, so that part is noted for completeness only. The September audit marked the browser item SKIPPED.
- Trigger: n/a
- Fix: split `body` into the header, list and sheet modifiers already named in the file, and move `FormattingTextView`'s key handling (`keyDown`, `doCommand`, `performKeyEquivalent`) into a `+Keys` extension.
- Tracked: none

### S10-workspace-11 — Doc comments attached to the wrong declarations
- Where: `Sources/Features/Workspace/NodeCard.swift:228`, `Sources/Features/Workspace/NodeCard.swift:310-311`, `Sources/Features/Workspace/BoardSheets.swift:104-105`, `Sources/Features/Workspace/WorkspaceTree.swift:45-47`
- Category: docs
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `ThumbnailImage` is documented as "Names a new folder, link or note before it is created", which is the creation sheet's comment. `NodeCard.swift:310-311` holds an orphaned "Confirms the names of files being imported" comment. `ImportSheet` is documented as "Renders a file's thumbnail", which is the thumbnail's comment. The three comments were rotated when the types moved between files. `WorkspaceTree.swift:45-47` says "Folders before boards at every depth" while `:127-130` returns `boardNodes + folderNodes`.
- Trigger: n/a
- Fix: put each comment back on its type, delete the orphan, and correct the ordering sentence (or the order, if folders-first is the intent).
- Tracked: none

### S10-workspace-12 — Stale cross-references in comments
- Where: `Sources/Features/Workspace/BoardWikilinkCompletionLayer.swift:110-111`, `Sources/Features/Workspace/BoardFormatBar.swift:69-73`, `Sources/Features/Workspace/WorkspaceController+Conflict.swift:4-5`, `Sources/Features/Workspace/CardCommand.swift:47-48`, `Sources/Features/Workspace/CardCommand.swift:75`, `Sources/Features/Workspace/CardCommand.swift:126`, `Sources/Features/Workspace/WorkspaceBrowser+Tree.swift:37`, `Sources/Features/Workspace/WorkspaceBrowser+Tree.swift:219`, `Sources/Features/Workspace/FormattingTextView.swift:330`
- Category: docs
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: the completion layer says the viewport is something "nothing drawn today reads", but `:164` passes it to the placement clamp. `BoardFormatBar` promises a "future horizontal clamp" that exists at `:57-61`, `:106`, `:113-116`. `+Conflict` cites PG-202 as an open ticket, but PG-202 is closed. `CardCommand` cites `BoardContentLayer.swift:55-89`/`:66-87` for a menu that now lives in `BoardCardMenu.swift`, and `WorkspaceBrowserToolbar.swift:35` for the trash verb, which is at `:50`. `+Tree` cites `:543-550` for `rows(matching:in:)`, which is at `:167-180`. `FormattingTextView` cites `BoardChrome.swift:118-128` for the bare-key suspension, which is at `:134-140`.
- Trigger: n/a
- Fix: update or drop the line numbers. Cite symbols rather than line ranges.
- Tracked: none

### S11-02 — The progress bar appears only after the first message commits, so «Annulla» is unreachable during the folder scan and the first decode, and the post-loop phases run behind «N di N»
- Where: `Sources/Features/Pratiche/PraticaSyncEngine.swift:118,148,151`, `Sources/Features/Pratiche/PraticheController+Ledger.swift:269-272`, `Sources/Features/Pratiche/PraticaTopBar.swift:126,130-133`
- Category: correctness
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `beginSync` sets `syncProgress = nil` and the top bar draws «n di N · Annulla» only while `syncProgress != nil`; the engine's single `emit` is after each item of the main loop (`:148`). Nothing is emitted during `folderContext` (which reads and digests every attachment, S11-05), `repairCorruptAttachments` or the first `decodeAndCommit`, and nothing during `regeneratePending`/`noLongerInMail` after the loop, so the bar is absent for the longest stretch of a first import and reads «N di N» while the pending re-renders still run. The cooperative `cancelled` flag is read only at `:151`, so the hidden «Annulla» is the one window in which a cancel would have mattered.
- Trigger: «Aggiorna ora» on a pratica with 200 messages and no note yet → no bar and no «Annulla» until message 1 lands; every message already imported but 30 bodies `pending` → `regeneratePending` re-renders 30 notes with no bar at all.
- Fix: `emit(Progress(completed: 0, total: items.count + pendingCount))` once the scan is done, and one `emit` per pending re-render; the bar then covers the whole run and «Annulla» is live from the first second.
- Tracked: none

### S11-03 — The inspector walks the whole vault for boards and re-parses `pratica.md` on every `PratichePane` body evaluation
- Where: `Sources/Features/Pratiche/PratichePane+Links.swift:10-16,101,185-188`, `Sources/Features/Pratiche/PratichePane+Inspector.swift:67-68`, `Sources/Features/Pratiche/PratichePane+LinksSummary.swift:31`, `Sources/Features/Pratiche/PratichePane.swift:53,164`, `Sources/Features/Pratiche/PraticheController.swift:393-406`
- Category: performance
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `inspector`, `praticaLinksSection` and `linkedBoardsSection` are computed properties of `PratichePane`, evaluated inside `PratichePane.body` and sharing its observation scope. That body reads `pratiche.problem`, `pratiche.selectedTray` (`trayProposals`), `pratiche.details` and `pratiche.links` (through `aggregatedNoteLinks`), so every `reloadTimeline` (selection change, every sync outcome, every `inspectorKey` change) and every tray update re-runs `CanvasStore(root:).allBoards()`, the uncached recursive walk of the vault `:187` itself names, and `MarkdownBlockParser.blocks(in: inspectorBody)`, on the main actor, while the inspector is open. The header's claim that the section "redraws only when the pratica's selection or its own links change" (`:10-13`) does not hold under Observation tracking. `aggregatedNoteLinks` is also computed twice per body (`+LinksSummary.swift:31`, `+Links.swift:101`), each pass parsing every detail's `linkedNote`.
- Trigger: n/a
- Fix: hold `boards` and the parsed blocks in `@State`, refreshed from `.task(id: vault.scanGeneration)` and the existing `.task(id: pratiche.inspectorKey(for:))`, the shape `TasksView.swift:55`, `TodayView.swift:70`, `DiaryView.swift:51` and `EditorColumnView.swift:111` already use for `allBoards()`; compute `aggregatedNoteLinks` once in `inspector` and pass it down.
- Tracked: none

### S11-04 — `reloadTimeline` still reads and parses every `email/*.md` synchronously on the main actor
- Where: `Sources/Features/Pratiche/PraticheController+Ledger.swift:225-245`, `Sources/Features/Pratiche/PraticheController+TimelineRead.swift:102-104,113-115`
- Category: performance
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `readTimeline` is `nonisolated static` and takes a URL "so it can move off the main actor the day a pratica gets big enough" (`+TimelineRead.swift:102-104`), but its only caller runs it inline on the `@MainActor` controller on every selection change, after every sync outcome and on every `inspectorKey` change (`reloadTimelineIfStale`). PG-137 (closed) listed this item as `perf-PraticheController.swift-c6e`; the audit doc marks it "Deferred — report-only", so it is a carried-over item rather than a re-introduced one, recorded here because its ledger entry is closed.
- Trigger: n/a
- Fix: `let read = await Task.detached { Self.readTimeline(...) }.value`, then assign `timeline`/`details`/`links`/`timelineOrigin` only if `selection` and `timelineOriginPraticaPath` still match after the `await` (ADR-0043 §D7).
- Tracked: regression of PG-137

### S11-05 — Every sync re-reads and SHA-256-digests every file in `allegati/`
- Where: `Sources/Features/Pratiche/PraticaSyncEngine+Folder.swift:77-79,108-111`
- Category: performance
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `folderContext` loads each attachment fully (`Data(contentsOf:)`), runs `AttachmentIntegrity.verdict` and `digest(of:)` on it, on every run: window-key syncs come once a minute per pratica, FSEvents bursts once per 10 s, «Aggiorna tutte le pratiche» runs it for every pratica, and the digest map is consulted only when a newly prepared attachment needs a duplicate check. A pratica with hundreds of MB of attachments pays a full read of the folder per trigger, before the progress bar exists (S11-02).
- Trigger: n/a
- Fix: cache `(name, size, mtime) → digest` in the per-vault state directory (ADR-0017's home for derived state), recomputing the verdict and digest only for files whose size or mtime changed, or build the map lazily on the first duplicate lookup of a run.
- Tracked: none

### S11-06 — `MessageCommand.symbol` and `PraticaEntryCommand.symbol` are drawn by no surface; the first is kept alive only by its test
- Where: `Sources/Features/Pratiche/MessageCommand.swift:53-70`, `Sources/Features/Pratiche/PraticaEntryCommand.swift:23-30`, `Sources/Features/Pratiche/PraticaMenuItems.swift:52,57,99`, `Sources/Features/Pratiche/PraticaMessageRow.swift:77`, `Sources/Features/Pratiche/PraticaEntryRow.swift:70`
- Category: dead-code
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `MessageMenuItems.item` and `EntryMenuItems.menu` build `Menu(command.title)`/`Button(command.title)`, and the footer and the accessibility actions do the same, so neither `symbol` ever reaches a `Label`. `PraticaCommand.symbol` got its readers after the 2026-09-11 audit (`PraticaMenuItems.swift:21`, `PraticaTopBar.swift:68`); its two twins did not. The only reader of `MessageCommand.symbol` is `Tests/MessageCommandSymbolTests.swift:12,30`, which is why Periphery flags `PraticaEntryCommand.symbol` (`periphery-all.txt:106`) and not this one. Both doc comments ("the SF Symbol both surfaces may draw") describe a rendering that does not exist.
- Trigger: n/a
- Fix: draw `Label(command.title, systemImage: command.symbol)` in `MessageMenuItems.item` and `EntryMenuItems.menu` as `PraticaMenuItems.menu` does (one rendering rule for the three catalogues, ADR-0023 §D1), or delete both accessors and `MessageCommandSymbolTests.swift`.
- Tracked: none

### S11-07 — `MailStoreEventStream`'s outer `@unchecked Sendable` has no documented reason and guards nothing; a failed `start()` disarms the FSEvents trigger silently for the session
- Where: `Sources/Features/Pratiche/MailStoreEventStream.swift:12,46,48,85-88,96-101`, `Sources/Features/Pratiche/PraticheController+Triggers.swift:73-85`
- Category: correctness
- Severity: P3 · Confidence: suspected
- In flight: no
- What: the doc at `:17-22` justifies the inner `Sink` (lock-protected, crosses to the FSEvents queue); the outer class carries the same annotation with `stream` and `sinkInfo` as plain `var`s mutated by `start()`, `stop()` and `deinit` under no lock. Today both calls come from the main actor (`+Triggers.swift:74-85`; `stop()` only from `deinit`, and the controller never releases the stream), so no race is reachable; the annotation is what would hide one when a second caller appears. Separately, when `FSEventStreamCreate` returns nil (`:85-88`) `start()` returns without a word, `mailStoreEvents = stream` is still assigned (`:84`), and the `== nil` gate at `:73` never tries again: the FSEvents trigger is lost for the session and nothing says so.
- Trigger: `MailStoreLocation.resolve()` naming a root FSEvents refuses at `startWatching` time → no FSEvents sync for the rest of the session, window-key and manual syncs still work, no sentence anywhere (suspected: not reproduced).
- Fix: drop the outer conformance (the object lives on a `@MainActor` property and needs none) or make `start`/`stop` `@MainActor`; have `start()` return `Bool`, leave `mailStoreEvents` nil on failure so the next `paneAppeared` retries, and report once through `report(_:)`.
- Tracked: none

### S11-08 — Five files over SwiftLint's 400-line warning, one of them 26 lines from the 1000-line error
- Where: `Sources/Features/Pratiche/PraticaSyncEngine+Messages.swift:1` (974 lines), `Sources/Features/Pratiche/PraticheController+Ledger.swift:1` (824), `Sources/Features/Pratiche/PraticheController.swift:1` (676), `Sources/Features/Pratiche/PraticaCommandActions.swift:1` (579), `Sources/Features/Pratiche/PraticaFileOperations.swift:1` (440)
- Category: simplification
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `wc -l` on 2026-10-30. PG-160 (closed) left `+Messages.swift` over the warning line on purpose (ADR-0045 §D4); it has since grown to 974 and the next feature in it trips the hard error. It holds four separable concerns: `prepare` with attachment resolution (`resolveExternalized`, `:108-136`), `commit` (`:770-860`), regeneration (`regenerationPreview`/`commitRegeneration`, `:670-680,850-858`) and `regeneratePending` (`:891`). `PraticheController+Ledger.swift` mixes the ledger writers with `load`/`select`/`reloadTimeline` and the sync-report API (`:225-335`).
- Trigger: n/a
- Fix: `PraticaSyncEngine+Regeneration.swift` (preview, commit, pending) out of `+Messages.swift`; `PraticheController+Load.swift` (`load`, `select`, `reloadTimeline`, `reloadTimelineIfStale`) out of `+Ledger.swift`. Mechanical moves under ADR-0045 §D3's convention.
- Tracked: none

### S12-02 — A theme named «Trascrizione» (or a `## ` line) collides with the transcript section; its tasks are dropped yet marked imported
- Where: `Sources/Features/Recordings/TranscriptNote.swift:82`, `Sources/Features/Recordings/TranscriptNote.swift:276`, `Sources/Features/Recordings/TranscriptNote.swift:290`, `Sources/Features/Recordings/TranscriptNote.swift:306`, `Sources/Features/Recordings/RecordingsController+Import.swift:76`
- Category: correctness
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `render` merges accepted task lines under `headingPrefix + theme.name` via `merge` (first section whose heading matches), then `replaceTranscript` overwrites the `## Trascrizione` section's lines wholesale. A theme whose name equals the transcript heading puts its task lines into that section and they are erased; a theme name containing a newline, or `parseBody` treating any body line starting with `## ` as a section, splits sections the same way on re-import. `importAccepted` records the fingerprints of every accepted task regardless of whether its line was emitted, so the lost tasks are suppressed as «già importato» forever. Rare trigger (theme names come from the local service), permanent effect.
- Trigger: service proposal with a theme named `Trascrizione` and one accepted task → import → note has no task line, ledger holds its fingerprint, re-import offers nothing.
- Fix: sanitize theme names (strip newlines and leading `#`, rename one equal to `transcriptHeading`); record fingerprints only for lines actually present in the rendered text.
- Tracked: none

### S12-03 — Review sheet clears the draft and dismisses even when the import failed
- Where: `Sources/Features/Recordings/ReviewSheet.swift:371`, `Sources/Features/Recordings/RecordingsController+Import.swift:18`
- Category: correctness
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `importAccepted` returns `Void`; on its early returns (no `recordedAt`, `session.write` refused because the note moved on since `expecting:` hash, ledger save throwing) it only sets `rowErrors`. `runImport` then unconditionally calls `clearDraft(for:)` and `dismiss()` (comment l.382-383 says "the decisions have been acted on"), so the person's accept/reject choices and speaker renames are thrown away on a failed import.
- Trigger: edit the recording's note in the editor while the review sheet is open → «Importa» → write refused on hash mismatch → sheet closes, draft deleted, row shows the error, decisions must be redone.
- Fix: make `importAccepted` return a Bool/outcome; clear the draft and dismiss only on success.
- Tracked: none

### S12-04 — A cancelled poll reports a spurious error and can clobber its replacement's state
- Where: `Sources/Features/Recordings/RecordingsController.swift:218`, `Sources/Features/Recordings/RecordingsController.swift:247`, `Sources/Features/Recordings/RecordingsController.swift:295`
- Category: correctness
- Severity: P3 · Confidence: suspected
- In flight: no
- What: `startPolling` cancels any existing poll task for the id and starts a new one. A task cancelled while awaiting `service.job(id:)` lands in `askJob`'s generic `catch`, which writes `rowErrors[recordingID]` (URLSession cancellation → "…Dettaglio: cancelled") and calls `finishPolling`, which sets `pollTasks[recordingID] = nil` and removes the id from `pollingRecordingIDs` — erasing the *replacement* task's bookkeeping, so the row stops showing progress while the new poll still runs.
- Trigger: press «Rielabora» twice quickly (or switch vault → `stop()`) while a `job` request is in flight → error banner on the row and the spinner disappears.
- Fix: in the catch, return quietly on `CancellationError`/`Task.isCancelled`; in `finishPolling`, clear `pollTasks` only when it still holds the current task.
- Tracked: none

### S12-05 — saveDraft reads, decodes and atomically rewrites plaud-drafts.json on every keystroke, on the main actor
- Where: `Sources/Features/Recordings/RecordingsController+Interface.swift:62`, `Sources/Features/Recordings/RecordingsController+Interface.swift:105`, `Sources/Features/Recordings/ReviewSheet.swift:342`
- Category: performance
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `renameBinding`/`decisionBinding` call `persistDraft()` per change; `saveDraft` (on the `@MainActor` `RecordingsController`) does `store.loadDrafts()` (disk read + JSON decode of all drafts) and `saveDrafts` (encode + atomic write) synchronously each time. The comment at l.105-107 says a disk read per keystroke is "a cost with no answer", yet the read is still there; only the store construction was hoisted. The 2026-09-11 audit filed this as `perf-RecordingsController.swift-8f0` and marked it SKIPPED (audit l.463, l.1166); PG-137's closure (ADR-0041 VaultDisk) did not cover this file.
- Trigger: n/a
- Fix: keep drafts in memory after first load and debounce the write (or write on sheet close/import), off the main actor.
- Tracked: none

### S12-06 — Month scale reads and parses up to 42 daily notes from disk on every reload
- Where: `Sources/Features/Today/DayController.swift:131`, `Sources/Vault/VaultSession+TimeBlocks.swift:18`
- Category: performance
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `DayController.span()` calls `vault.timeBlocks(on:)` per day of the visible range; `VaultSession.timeBlocks(on:preferring:)` reads the daily note file (`dailyNoteText(for:)`) and runs `TimeBlockSection.parse` each call. At month scale that is up to 42 synchronous file reads + parses on the main actor per `reload()`, which fires on scale/showsCompleted changes and on every `indexGeneration` change (`TodayView.swift:82`), i.e. after every save anywhere in the vault. Unmeasured.
- Trigger: n/a
- Fix: derive time blocks from the index snapshot, or memo per (day, index generation) as ADR-0072 does.
- Tracked: none

### S12-07 — Chained time-block write reads `day` and `blocks` after awaiting the previous write
- Where: `Sources/Features/Today/DayController.swift:315`
- Category: correctness
- Severity: P3 · Confidence: suspected
- In flight: no
- What: `pendingWrite = Task { @MainActor in await previous?.value; let sorted = change(blocks)...; guard await vault.setTimeBlocks(sorted, on: day) ...; blocks = sorted }` captures neither `day` nor `blocks` at enqueue time. If the person navigates to another day while a previous write is pending, the queued change is applied to the new day's blocks and written into the new day's note (ADR-0043 §D7 / vault-writes.md guard-after-await rule).
- Trigger: drag a block, then press «Giorno successivo» before the first write completes (slow disk / iCloud) → second queued edit lands on tomorrow's note.
- Fix: capture `day` at enqueue; after the await, skip (or re-target explicitly) when `self.day != capturedDay`.
- Tracked: none

### S12-08 — «Crea» in the new-event draft sheet ignores a failed creation
- Where: `Sources/Features/Today/TodayView.swift:294`
- Category: correctness
- Severity: P3 · Confidence: confirmed
- In flight: yes
- What: the button does `_ = confirm(); dismissDraft()`: the Bool reporting whether the EventKit event/reminder was created is discarded and the sheet closes anyway; the failure reaches only `vault.recordProblem`. `dismissDraft` resets only `draftTitle`, so hour/duration of the failed draft are not kept for a retry either.
- Trigger: create an event with calendar access revoked (or no writable calendar) → sheet closes, no event, no inline message.
- Fix: keep the sheet open with an Italian inline error when `confirm()` returns false.
- Tracked: none

### S12-09 — DiaryView rebuilds the note-title pool on every render
- Where: `Sources/Features/Diary/DiaryView.swift:115`
- Category: performance
- Severity: P3 · Confidence: confirmed
- In flight: yes
- What: `noteTitles: vault.index.allNotes.map(\.title)` is evaluated in `body`, while the sibling pools (`boardTitles`, `noteAliases`) are cached per `scanGeneration` (comment l.30-34) and `TodayView` caches its `noteTitles`. Every diary redraw (each keystroke in the preview) maps the whole note list.
- Trigger: n/a
- Fix: cache `noteTitles` alongside the other pools in the same `.task(id: vault.scanGeneration)`.
- Tracked: none

### S12-10 — MiniCalendar rebuilds the daily-note path by hand
- Where: `Sources/Features/Today/MiniCalendar.swift:160`, `Sources/App/VaultController+TimeBlocks.swift:15`
- Category: simplification
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `hasDailyNote` composes the daily folder and `NoteName.dailyFileName(for:)` itself instead of calling `vault.dailyNotePath(for:)`, which `DayController.swift:143` already uses. Two spellings of one path rule drift independently (e.g. folder canonicalisation).
- Trigger: n/a
- Fix: call `vault.dailyNotePath(for:)`.
- Tracked: none

### S12-11 — Six-week Monday-first month grid implemented twice, offset formula in four places
- Where: `Sources/Features/Tasks/MonthCalendar.swift:115`, `Sources/Features/Today/MiniCalendar.swift:191`, `Sources/Features/Today/WeekPlan.swift:236`, `Sources/Core/Query/ViewDateBound.swift:76`
- Category: simplification
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `MonthCalendar.days` re-implements `MonthGrid`'s 42-day grid (`(DateEntry.weekday(of: first) + 5) % 7`, start, `(0..<42).map`), and the Monday-first offset expression is repeated in `WeekPlan` and `ViewDateBound`. ROADMAP chain 10 names only the duplicated weekday initials, not the grid.
- Trigger: n/a
- Fix: one `DateEntry.mondayOffset(of:)`/`weekStart(of:)` helper in Core, and `MonthCalendar` using `MonthGrid`.
- Tracked: none

### S12-12 — Task composer stays open with no message when capture fails
- Where: `Sources/Features/Tasks/TaskComposer.swift:171`, `Sources/App/VaultController+Tasks.swift:69`
- Category: correctness
- Severity: P3 · Confidence: suspected
- In flight: no
- What: `create` does `guard canCreate, let path = await vault.captureTask(draft) else { return }`; `captureTask` returns nil from `session.captureTask` without recording a problem at that level. «Crea» then appears to do nothing.
- Trigger: destination note moved on/refused write during capture → click «Crea» → nothing happens, no feedback.
- Fix: surface an Italian error in the composer (or ensure the session records one) when capture returns nil.
- Tracked: none

### S12-13 — Category sidebar recomputes per-row subtree progress and implicit categories every render
- Where: `Sources/Features/Tasks/CategorySidebarSection.swift:28`, `Sources/Features/Tasks/CategorySidebarSection.swift:100`, `Sources/Index/IndexSnapshot+Categories.swift:63`, `Sources/Features/Tasks/TaskViewSidebar.swift:20`
- Category: performance
- Severity: P3 · Confidence: suspected
- In flight: no
- What: each row calls `progress(ofCategory:registry:)`, which filters the subtree's tasks per call; `implicitCategories` and `taskCounts` are also recomputed in `body`. With no `IndexKeyedMemo`, every sidebar redraw is O(categories × tasks). PG-138 (closed) covered `taskCounts`'s six passes and `LinkedTasksPanel`, not the category rows.
- Trigger: n/a
- Fix: compute a per-category progress map once per index generation (ADR-0072 memo).
- Tracked: none

### S13-02 — A symlink in the drop folder is imported as a link, hashed as its target
- Where: `Sources/Features/Contenitore/DropFolderListing.swift:99`
- Category: security
- Severity: P3 · Confidence: suspected
- In flight: no
- What: `read(_:)` (`:99-120`) requests `.isDirectoryKey, .fileSizeKey, ...` but not `.isSymbolicLinkKey`; the ingest hashes through the link (`ContenitoreIngestEngine.swift:236-246`) and `moveItem` moves the link itself into the vault. The scheda then records the target's SHA-256 for a file that is a pointer outside the vault (principle 1, file over app). Hinge: whether `isDirectory` and the size key follow the link; not settled from source.
- Trigger: `ln -s /some/file ~/Pergamenum\ Drop/x.pdf`.
- Fix: request `.isSymbolicLinkKey` and classify symlinks as refused (like `.md`/`.canvas`, `:50`), with a notice sentence.
- Tracked: none

### S13-03 — `readContainerTree` walks without a symlink check or visited set
- Where: `Sources/Features/Contenitore/ContenitoreController+Caches.swift:167`
- Category: correctness
- Severity: P3 · Confidence: suspected
- In flight: no
- What: the iterative walk (`:167-185`) uses keys `[.isDirectoryKey]` (`:171`) and `.skipsHiddenFiles` only. A symlinked directory under the root, if `isDirectory` resolves through it, lists outside folders as containers or loops on a cycle (`while let next = pending.popLast()`, `:172`). Hinge as in S13-02. Related: PG-261 item 7 (symlinked vault, open).
- Trigger: a symlink to a parent folder inside the Contenitore root.
- Fix: add `.isSymbolicLinkKey` and skip links, or keep a set of resolved paths.
- Tracked: none

### S13-04 — Extraction store write failure is swallowed
- Where: `Sources/Features/Contenitore/ContenitoreExtractionQueue.swift:85`
- Category: correctness
- Severity: P3 · Confidence: suspected
- In flight: no
- What: `guard (try? store.write(text, sha256: sha256)) != nil else { return }` drops the error with no problem recorded; the document stays "in attesa"/"in estrazione" with no reason given, and the next launch retries silently.
- Trigger: Application Support full or unwritable.
- Fix: record a problem via the controller's notices, mark the summary failed.
- Tracked: none

### SEC-08 — The attachment open gate is a denylist that misses several launchable types
- Where: `Sources/Features/Pratiche/AttachmentChipModel.swift:109`, `Sources/Features/Pratiche/AttachmentChipModel.swift:119`
- Category: security
- Severity: P3 · Confidence: suspected
- In flight: no
- What: `refusesToOpen` refuses `.executable`, `.applicationBundle`, `.diskImage`, `.shellScript`, `.script` and installer packages. Types that launch or redirect but conform to none of these (`.fileloc`/`.inetloc`/`.webloc` location files, `.terminal` settings, Automator `.workflow`, `.jar`) are opened. Quarantine (PG-123) makes Gatekeeper prompt for some of them, not for a location file.
- Trigger: an email attachment `fattura.fileloc` pointing at a local file or `.inetloc` pointing at a URL → «Apri» on the chip opens the target.
- Fix: invert to an allowlist of document types (pdf, images, office, text, archives as reveal-only), or add the location-file and Automator/Java types to the refused set.
- Tracked: none

### SEC-09 — `HTMLTextReducer` writes link text, `href` and `alt` into markdown unescaped
- Where: `Sources/Core/Email/HTMLTextReducer.swift:290`, `Sources/Core/Email/HTMLTextReducer.swift:313`
- Category: security
- Severity: P3 · Confidence: suspected
- In flight: no
- What: after `LinkPolicy.isOpenable(href)` the reducer emits `[\(text)](\(href))`, and for `cid:` images `![\(alt)](\(source))`, with no escaping of `]`, `(`, `)` or newlines. The output is re-parsed as markdown, so anchor text or a crafted href can close the link early and open a second one the reducer never vetted. Downstream gates (`MarkdownBlocksView.swift:254`, `MarkdownAttributedText.clickTarget`) still restrict what is clickable to `LinkPolicy`'s schemes or http/https, which is why this is P3.
- Trigger: `<a href="https://ok.example">x](pergamenum://capture?text=y) [z</a>` in an HTML email → the message note carries a clickable `pergamenum://` link the reducer's own gate did not see as such.
- Fix: escape `\`, `[`, `]` in link text and alt, percent-encode `(`, `)` and spaces in the destination (or wrap it in `<…>`), and collapse newlines in both.
- Tracked: none

### SEC-10 — `LinkPolicy` lets an email carry a clickable `pergamenum://` command link into a pratica
- Where: `Sources/Core/Email/LinkPolicy.swift:29`, `Sources/Core/Email/HTMLTextReducer.swift:290`, `Sources/Features/Editor/MarkdownBlocksView.swift:254`, `Sources/Features/Editor/MarkdownReadingView.swift:127`
- Category: security
- Severity: P3 · Confidence: suspected
- In flight: no
- What: the scheme allowlist includes `pergamenum`, and it is the same list `HTMLTextReducer` applies to a sender's HTML. An external email can therefore plant a link that, when clicked in the pratica timeline or reading view (`OpenURLAction` returns `.systemAction` for every non-note scheme), re-enters the app's URL scheme: a capture that writes a note, a `canvas?file=` or `note?path=` navigation. Confirmed by reading both views: `MarkdownBlocksView.inline` sets `piece.link` for any `LinkPolicy.isOpenable` URL (line 254), and `MarkdownReadingView`'s `OpenURLAction` handles only `pergamenum-wikilink` and returns `.systemAction` for the rest (lines 126-127), so Launch Services hands `pergamenum://` back to the app. P3 rather than P2: every route is boundary-checked and the effect is one unwanted capture write or navigation after a click, not an escape or a read.
- Trigger: `<a href="pergamenum://capture?text=…">Scarica la fattura</a>` in an email synced into a pratica → one click writes a capture note.
- Fix: a separate, narrower policy for content of external origin (`http`, `https`, `mailto`), keeping `pergamenum` and `message` for vault-authored notes.
- Tracked: none

### SEC-11 — `regex:` search compiles an arbitrary pattern and runs it over every note with no time bound, also from the MCP server
- Where: `Sources/Core/Search/SearchQuery.swift:160`, `Sources/Core/Search/SearchQuery+Matching.swift:44`, `Sources/Connector/VaultReads.swift:90`
- Category: performance
- Severity: P3 · Confidence: suspected
- In flight: no
- What: `regex:` patterns go straight to `NSRegularExpression` (ICU, backtracking) and are evaluated against each note body; nothing caps pattern length, nesting or evaluation time. The connector's `search` passes the raw query to the same parser, so a model driving `pergamenum-mcp` can hang the server process on one call.
- Trigger: `regex:(a+)+$` against a vault containing a long run of `a` → the search does not return.
- Fix: cap pattern length, run the match with a deadline (check a clock between notes and abort), or reject nested quantifiers; on the MCP side, a per-call timeout.
- Tracked: none

### SEC-12 — The capture log writes the note path and the refusal reason as public
- Where: `Sources/Features/Capture/CaptureController.swift:232`, `Sources/Features/Capture/CaptureController.swift:236`
- Category: security
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `log(_:)` interpolates the written note's vault path and the refusal reason with `privacy: .public`, so note titles (and any capture text a refusal reason echoes) land in the unified log readable by any admin process and in sysdiagnoses. PG-125 closed the same shape for URL routes only. The doc comment above `log(_:)` (lines 217-227) makes the path public on purpose: it is how a person confirms a capture write when the vault sits somewhere unreadable, such as a UI-test runner's container. No script or test reads this log automatically (`scripts/uitests.sh`'s only `log show` reads launchd), so the purpose is manual inspection.
- Trigger: any capture → `log show --predicate 'subsystem == "it.stefer.pergamenum"'` shows the note title in clear.
- Fix: keep the manual check and drop the leak: `privacy: .private(mask: .hash)` on `path` and `reason` in release builds, and `.public` only when the process is a UI-test instance (the same environment flag the test hosts already pass), or under `#if DEBUG`; keep `destination` public.
- Tracked: none

### SEC-13 — A large `.emlx` is held in memory several times over during a sync
- Where: `Sources/Core/Email/EMLXReader.swift:43`, `Sources/Core/Email/EMLXReader.swift:89`, `Sources/Core/Email/MIMEDecoder.swift:128`
- Category: performance
- Severity: P3 · Confidence: suspected
- In flight: no
- What: the `.emlx` is read whole, `headerBodySeparator` copies it into `Array(rfc822)`, each multipart level copies its body into another array, and base64 decoding allocates the decoded payload on top. A message with a multi-hundred-MB attachment costs several times its size in one actor task.
- Trigger: a 300 MB attachment in a tracked thread → sync peaks above 1 GB resident.
- Fix: work on `Data` slices / `withUnsafeBytes` instead of `Array` copies, and decode only parts that pass the size threshold.
- Tracked: none

### SEC-14 — The network-isolation guard test looks for `URLSession` only
- Where: `Tests/PlaudIsolationTests.swift:26`
- Category: house-rules
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: ADR-0032 §D14 says the loopback exception does not travel, and the test enforcing it fails only on a second file mentioning `URLSession`. `NWConnection`, `import Network`, `CFStream`, `CFSocket` or a `Process` running `curl` would pass it; today none exists (grep of `Sources/` on 2026-10-30 found network symbols only in `PlaudHTTPClient.swift` and `import Sparkle` in `SparkleUpdateController.swift`).
- Trigger: n/a (a future `import Network` in any file passes the merge gate).
- Fix: widen the scan to a list of network symbols (`URLSession`, `NWConnection`, `NWListener`, `import Network`, `CFStream`, `CFSocket`, `URLSessionWebSocketTask`, `/usr/bin/curl`) with an allowlist of exactly the two exception files.
- Tracked: none

### SEC-15 — CLAUDE.md says the network has "one named exception, and only one"; the Plaud loopback client is a second
- Where: `CLAUDE.md` (Binding architectural principles, 2), `Sources/Features/Recordings/PlaudHTTPClient.swift:7`
- Category: docs
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: principle 2 names the Sparkle check as the only exception, while ADR-0032 and `PlaudHTTPClient` hold a `URLSession` to `127.0.0.1:3777`. The audit brief itself lists two exceptions, and ADR-0032 (grepped, not read in full) calls itself the second written exception at line 12 and states it formally as §D14 (line 522). A reviewer applying CLAUDE.md literally would reject the Plaud client.
- Trigger: n/a
- Fix: amend principle 2 to name the loopback client (ADR-0032 §D14) as the second, machine-local exception.
- Tracked: none

### T01-tests-02 — a calendar test's whole body sits behind a TCC-state guard, so it asserts nothing on an ordinary machine
- Where: `Tests/CalendarTests.swift:444-450`
- Category: disabled
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `aDeniedStoreIsNeverOfferedTheRequestAgain` wraps its single assertion in
  `if store.eventAccess == .denied, store.reminderAccess == .denied`. On a machine where calendar
  and reminder access is granted or still `.notDetermined` — the dev machine, CI, and any fresh
  host — the condition is false, the body is skipped and the test passes having checked nothing.
  The named behaviour ("macOS asks once; offering it again would be a button that does nothing")
  is therefore unpinned everywhere it matters.
- Trigger: n/a (test-side)
- Fix: drive the state instead of observing it. `EventKitStore`'s access state needs a seam the
  test can set (an injected authorization provider, or the flag the UI suite's `-disableCalendar`
  already implies) so the denied case can be constructed; then assert unconditionally. If no seam
  is wanted, the test is not buying anything and should say so or go.
- Tracked: none

### T01-tests-03 — two files create temporary roots and never remove them
- Where: `Tests/CanvasByteOrderMarkTests.swift:14`, `Tests/CardFoldTests.swift:60` (call sites
  `Tests/CardFoldTests.swift:216`, `:247`, `:261`)
- Category: hygiene
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: both files declare a local `temporaryRoot()` / `makeTempRoot()` that
  `createDirectory`s a `pergamenum-…-<UUID>` folder under `FileManager.default.temporaryDirectory`,
  and neither file contains a single `removeItem` — verified by cross-referencing every
  `temporaryDirectory` site in the slice (15, in 11 files) against every `removeItem` site (15).
  They are the only two of the eleven that leak: the other nine either pair the helper with
  `defer { try? FileManager.default.removeItem(at: root) }` at each call site
  (`CanvasCropTests:156/:176/:215/:247`, `CanvasCropProbeTests:44`, `CardRoundTripTests:143/:161`,
  `AttachmentChipMenuTests:113`, `AttachmentChipTests:23`, `AttachmentIntegrityTests:209`,
  `AttachmentQuarantineTests:14`) or clean up in `deinit` (`CanvasTestSupport.swift:20`,
  `CanvasTemporaryRoot`). Five directories with vault files in them survive every run of the suite.
- Trigger: n/a
- Fix: use the shared fixture that already exists — `CanvasTemporaryRoot` in
  `Tests/CanvasTestSupport.swift:20` is `~Copyable` and removes its directory in `deinit`, which is
  exactly what both local helpers want. `CardFoldTests` needs a vault write, so
  `TemporaryVault` (`Tests/TemporaryVaultSupport.swift`) may fit better; either way, delete the
  local helper rather than adding a `defer` to three call sites.
- Tracked: none

### T01-tests-04 — a hot-key test demands an exclusive machine-wide registration with no tolerance, while its own sibling defends against exactly that
- Where: `Tests/CapturePanelTests.swift:104-126`
- Category: flaky
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `registeringWithTheSystemReportsWhatTheSystemSaid` asserts
  `#expect(hotkey.register(free) == .registered(free))` for `Cmd+Ctrl+Opt+Shift+Z` (then `…+Y`),
  a real `RegisterEventHotKey` call with `kEventHotKeyExclusive`. The very next test
  (`:129-162`) documents the hazard in its own comment — the hot key is machine-wide and "a second
  test host running this suite at the same time (another worktree) can hold
  Cmd+Ctrl+Opt+Shift+X already" — and defends against it with a candidate loop over
  `["x", "q", "j", "k", "b", "n"]` that tolerates `.takenByAnotherApp`. The earlier test has no such
  tolerance, so two test hosts overlapping on `Z` (routine here: the `Stop` hook runs
  `PergamenumTests` at the end of every turn, in every worktree) turn it red for no defect. Both
  tests do call `unregister()` on every path, so no registration is left behind.
- Trigger: two `PergamenumTests` hosts running this suite concurrently from different worktrees →
  the second gets `.takenByAnotherApp(Cmd+Ctrl+Opt+Shift+Z)` → `#expect` fails.
- Fix: give this test the sibling's candidate loop (or factor that loop into one helper both use),
  tolerating `.takenByAnotherApp` for a candidate while keeping every other answer a failure.
- Tracked: none

### T01-tests-05 — two tests assert the implementation back at itself, with the machine's TCC state as the shared input
- Where: `Tests/CommandActionTests.swift:93-99`, `Tests/CalendarTests.swift:434-442`
- Category: flaky
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `CommandActionTests` asserts
  `#expect(actions.canRun(.newEvent) == actions.calendar.eventAccess.isGranted)` and the
  `.newReminder` twin. `Sources/App/CommandActions+CanRun.swift:57-60` is literally
  `case .newEvent: calendar.eventAccess.isGranted`, so the assertion restates the implementation and
  cannot fail while the two lines agree, whatever either one says. Worse, the test's own doc comment
  ("Without a granted EventKit access these two are off") is the opposite of what runs on a machine
  with access granted — the assertion follows the machine rather than pinning a rule.
  `CalendarTests:434-442` has the same shape: `let expected = store.eventAccess == .notDetermined ||
  store.reminderAccess == .notDetermined` reimplements `canStillBeAsked` and compares the two.
- Trigger: n/a — the defect is that neither test can go red for the reason it names; the TCC grant
  decides which branch is exercised, and both branches are tautologies.
- Fix: assert the rule against constructed access states (the same seam `T01-tests-02` needs), e.g.
  a table of `(eventAccess, reminderAccess) -> canRun/canStillBeAsked` rows, instead of reading the
  live store. Fix the doc comment or delete it with the assertion.
- Tracked: none

### T01-tests-06 — five private copies of the same `CardTextView` wiring helper
- Where: `Tests/CardConcealmentTests.swift:51`, `Tests/CardFoldTests.swift:78`,
  `Tests/CardFoldBadgeTests.swift:21`, `Tests/CardFormattingTests.swift:308`,
  `Tests/CardRoundTripTests.swift:69`
- Category: duplicate-support
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: each of the five is a `@MainActor private func` that builds
  `CardTextView(text: .constant(text), theme: .emergency, style: CardTextStyle(color: nil,
  alignment: nil), isEditable: …, hidesMarkup: …)`, calls `makeCoordinator()`, takes
  `FormattingTextView.scrollableTextView()` and `#require`s its `documentView` — identical wiring,
  differing only in which flags are parameters and in the tuple or struct returned. Each copy's own
  doc comment admits the duplication: `CardRoundTripTests.swift:65-67` says it is "the compromise
  `Tests/CardConcealmentTests.swift` and `Tests/CardFoldTests.swift` already make, restated here
  because each of those helpers is `private` to its own file", and `CardFormattingTests.swift:305`
  says the same while citing `Tests/CardConcealmentTests.swift:35` — a line that no longer holds the
  helper (it is at `:51`), so the cross-reference has already drifted. ADR-0051 §D1 names exactly
  this shape (a shared test helper is an internal free function in one file); the two in-flight
  helpers at `Tests/UnderscoreEmphasisConcealmentTests.swift:253`/`:268` look like copies six and
  seven arriving.
- Trigger: n/a
- Fix: one internal `@MainActor func wiredCard(text:isEditable:hidesMarkup:revealsInlineSpans:)
  throws -> (FormattingTextView, CardTextView.Coordinator)` in a shared support file (beside
  `CanvasTestSupport.swift`), returning the pair every copy already derives; each suite keeps its own
  thin wrapper for the extra fields it reads. Fix the stale `:35` citation in the same pass.
- Tracked: none

### T01-tests-07 — fifteen "RED"/`fatalError`-stub headers describe a TDD state the code left long ago
- Where: `Tests/BoardFileOperationsTests.swift:12` and `:22`, `Tests/BoardFormatBarTests.swift:16`,
  `Tests/CalendarDayMenuTests.swift:20`, `Tests/CanvasDuplicateTests.swift:10`,
  `Tests/CanvasStoreTests.swift:225`, `Tests/CardCommandTests.swift:12`, `:203` and `:222`,
  `Tests/CardFoldTests.swift:22`, `Tests/CardFormattingTests.swift:15` and `:257`,
  `Tests/CardTextStyleCommandTests.swift:15`, `Tests/CardTextStyleTests.swift:8`,
  `Tests/CardTextViewTests.swift:16`; same pass, same files: `Tests/CardTextViewTests.swift:122`
- Category: clarity
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: fifteen header comments in eleven files still tell the reader the code under test is a
  placeholder and the tests below are expected to fail or crash — e.g.
  `// RED: both functions are`fatalError`stubs in `BoardFormatBar.swift` until Task 6's coder fills
  them in, so every `@Test` below is expected to crash the run`. Every cited symbol is implemented
  today (spot-checked against the source rather than assumed: `CardTextAttributes`
  exists at `Sources/Features/Workspace/CardTextAttributes.swift:45`, so
  `CardTextViewTests.swift:16`'s claim is stale wording and not a dead-symbol citation). The cost is
  not cosmetic: a reader triaging a red run in one of these files is told by the file itself that a
  crash there is expected, which is the opposite of true, and the project's rule is that a red is
  diagnosed before anything is rerun.
- Trigger: n/a
  `Tests/CardTextViewTests.swift:122` belongs to the same cleanup for a different reason: its
  thirteen-line "PLAN DEVIATION (ADR-0073 §D2 of the retired concept-to-code workflow)" preamble
  cites an ADR number that in this repo now means "Quitting reviews unsaved notes first", so the
  citation points a reader at an unrelated decision.
- Fix: delete the RED paragraph from each block, keeping whatever the comment says about *why* the
  test exists. Mechanical, one commit, no behaviour change. At `CardTextViewTests.swift:122`, drop
  the retired-workflow citation (or mark it explicitly as a retired-chain number) and keep the one
  sentence that says what the test pins.
- Tracked: none

### T01-tests-08 — a named `UserDefaults` suite per call, never removed
- Where: `Tests/BundledThemePageTypographyTests.swift:21`
- Category: hygiene
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `bundled(_:)` does
  `try #require(UserDefaults(suiteName: "pergamenum.tests.\(UUID().uuidString)"))` and hands it to
  `ThemeEngine(defaults:)`, with no `removePersistentDomain(forName:)` anywhere. It is the slice's
  only `UserDefaults` use. Nothing lands on disk **today**, because `ThemeEngine` reads at init
  (`Sources/DesignSystem/ThemeEngine.swift:76`, `restoreSelection(from:)`) and writes only from
  `persistSelection()` (`:357`, `defaults.set(encoded, forKey: ThemeEngine.selectionKey)`), which no
  assertion in this file reaches. So the finding is the shape, not a current leak: one added line
  that changes the engine's selection turns every parameterised run into a fresh
  `~/Library/Preferences/pergamenum.tests.<UUID>.plist` in the person's real preferences, with no
  name to clean up afterwards because the suite name is a UUID.
- Trigger: add any assertion that sets the engine's selection → one orphan plist per theme per run,
  in the user's own preferences domain.
- Fix: one stable suite name plus
  `defer { UserDefaults.standard.removePersistentDomain(forName: name) }`, or a volatile
  `UserDefaults` built from a registered-defaults dictionary, in a shared helper so the next theme
  suite inherits it.
- Tracked: none

### T01-tests-09 — a caret defect is pinned as expected behaviour with no ledger id
- Where: `Tests/CardFormattingTests.swift:507-529`
- Category: pinned-defect
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `renumberListsAfterARunsTrailingItemShrinksLeavesTheCaretOneCharacterAhead` asserts
  `#expect(view.selectedRange() == NSRange(location: caret, length: 0))` and explains in its own
  comment that this is wrong — "Documented, not ideal: the correct position would compensate for the
  one-character shrink and land at 48 … The restore instead reuses the pre-edit caret unshifted,
  landing at 49 - one character further into `prosa` than where the person's caret actually was."
  No `PG-nnn` is cited anywhere in the block, so the suite now *defends* the defect: a later fix
  that compensates the shift correctly turns this test red and reads as a regression. This is the
  exact shape `PG-413` tracks for `Tests/QuitConflictScopeTests.swift`, and the only instance of it
  in the slice — the other pinned limitations do cite their ids (`CardFoldBadgeTests` cites
  PG-357/358/359, `CanvasStoreTests:399` cites PG-360).
- Trigger: in a Workspace card, delete the ninth item of a correctly numbered ten-item list with the
  caret parked in a trailing plain paragraph → the renumber shrinks `10.` to `9.` and the caret ends
  one character further right than where the person left it.
- Fix: open a ledger entry for the caret compensation, cite it from the test's comment and from the
  assertion's message, so the pin is a known deferral rather than a contract. When the fix lands, the
  expectation moves to 48 and the comment goes.
- Tracked: none (the defect itself is unticketed; `PG-413` is the same shape, elsewhere)

### T02-03 — `waitForRendition` returns whatever it has on timeout instead of failing, and eight callers discard the result
- Where: `Tests/EmbedEditorTestSupport.swift:105`, `Tests/EmbedDrawingTests.swift:195`, `Tests/EmbedCaretTests.swift:34, 63, 118, 145, 202, 232, 261, 299`
- Category: flaky
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: the shared wait polls a hundred times at 50 ms and, when the rendition never leaves
  `.pending`, falls through to `return coordinator.embeds.renditions[offset]` — a silent five-second
  timeout with no `Issue.record` and nothing thrown. Seven of the eight `EmbedCaretTests` tests then
  write `_ = await EmbedEditorFixtures.waitForRendition(...)`, discarding the answer, and
  `landedEmbed` (`:204`) does the same. So under load the render has not landed, the wait says
  nothing, and the failure surfaces as the *caret or click assertion* several lines later — a red
  that names the wrong subject. `waitForSubstitution` (`Tests/EmbedDrawingTests.swift:195`) has the
  same shape, returning `nil`. The repo's good shape is one file away:
  `Tests/DiaryControllerTests.swift:8-20` is a file-scope `waitUntil(timeout:sourceLocation:_:)` with
  a `ContinuousClock` deadline that records an `Issue` and throws.
- Trigger: n/a. The mechanism is precise for the one tracked flake in this slice: PG-199 is
  `movingRightFromTheRunsLeftEdgeSkipsItInOneStep` (`Tests/EmbedCaretTests.swift:104`) failing once
  under a `Stop`-hook run and never reproducing — exactly what a swallowed render timeout on a loaded
  machine looks like.
- Fix: make both waits throwing and failing — `Issue.record` plus a thrown error on deadline, as
  `waitUntil` does — and have the callers `try` them, so a slow render reds as a slow render.
- Tracked: PG-199 (open)

### T02-04 — A ten-second unbounded poll with no failure, followed by an unconditional 100 ms sleep
- Where: `Tests/ContenitoreEditorTests.swift:282`
- Category: flaky
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `lettingTheRetireTaskRun(after:)` spins `for _ in 0..<2000 where editor.problem == nil` at 5
  ms — up to ten seconds of wall clock — and on exhaustion simply returns, so a retire task that
  never reports becomes a downstream assertion failure rather than a timeout. It then yields fifty
  times and ends with `try? await Task.sleep(for: .milliseconds(100))` whatever happened, which every
  caller pays unconditionally.
- Trigger: n/a
- Fix: the same deadline-and-fail shape as `waitUntil` in `Tests/DiaryControllerTests.swift:8`; drop
  the trailing unconditional sleep once the predicate is authoritative.
- Tracked: none

### T02-05 — Ten test files still carry a "red on purpose / placeholder" header for behaviour production now has
- Where: `Tests/EmbedContextMenuTests.swift:14`, `Tests/EditorRestyleSwitchTests.swift:12`, `Tests/EmbedResizeGestureTests.swift:137, 259`, `Tests/EmbedDrawingTests.swift:264`, `Tests/DossierWriterTests.swift:43`, `Tests/EmbedResizeCommitTests.swift:13`, `Tests/DiaryWriteGuardTests.swift:51, 74, 116, 161, 226, 276`, `Tests/ConventionsNamingTests.swift:58`, `Tests/ConventionsTests.swift:177`, `Tests/DesignSystemTests.swift:101, 109, 130`
- Category: clarity
- Severity: P3 · Confidence: confirmed for the first six files, suspected for the last four
- In flight: no
- What: each header announces that the test below is expected to fail against a placeholder or stub.
  The structural argument applies to all of them: `.claude/test-cmd` runs
  `-only-testing:PergamenumTests` at the end of every turn and these files are in it, the slice
  contains no `withKnownIssue`, `.disabled(` or `XCTSkip` wrapper anywhere, and the ledger records no
  open red — so a test these headers describe would have blocked every merge since. Six are
  additionally verified against the production source: `EmbedContextMenu.items()` returns `["Elimina"]`
  (`Sources/Features/Editor/EmbedContextMenu.swift:21`), not `[]`; `EditorRestyleSwitch`
  reads both defaults domains; `resizeEmbed(_:in:)` is implemented
  (`Sources/Features/Editor/NoteTextView+EmbedResize.swift:24`) and the constrained value *is* read
  downstream (`:193-194, 235, 261-262`); `EditorDecorationDelegate.swift:736` builds an
  `EmbedAttachment()`, not a plain `NSTextAttachment`; `DossierWriter.update` returns a sentence
  rather than `nil` (`Sources/Features/Pratiche/DossierWriter.swift:35-38`); and
  `VaultSession+Diary.swift:71-95` honours `over:` through `expecting:`/`expectingAbsent:`.
  `Tests/DiaryGeometryTests.swift:21-24` is explicitly written as history and is not part of this.
- Trigger: n/a
- Fix: delete the red-today sentence from each header, or rewrite it in the past tense the way
  `DiaryGeometryTests` does. A header that lies about the gate is worse than no header: the next
  reader discounts a real red.
- Tracked: none

### T02-06 — `EmbedEditorFixtures.landedEmbed` is used twenty-two times, and `EmbedCaretTests` hand-rolls it eight more
- Where: `Tests/EmbedEditorTestSupport.swift:192`, `Tests/EmbedCaretTests.swift:20, 49, 104, 131, 188, 218, 247, 285`, `Tests/EmbedResizeGestureTests.swift:23`
- Category: duplicate-support
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `landedEmbed(root:text:)` performs the seven steps an embed test needs — write the image,
  build the `ThumbnailStore`, build the editor, `applyStyling`, `applyEmbeds`, await the rendition,
  `ensureLayout`, return the picture frame — and twenty-two call sites across five files use it,
  `EditorPointerTests.swift:285` and `EditorControllerReadTimingRemainingTests.swift:224` among them.
  `EmbedCaretTests.swift` calls it zero times and repeats the sequence in eleven tests; eight of
  those could use it (the three `hidesMarkup: false` cases at `:78, 162, 318` genuinely cannot,
  because they must not let the embed draw). The cost is not line count: each copy is a place where
  the render wait can be forgotten or discarded, which is how T02-03 gets eight callers.
- Trigger: n/a
- Fix: convert those eight to `landedEmbed`; if a case needs the intermediate objects, widen the
  helper's return rather than inlining it again.
- Tracked: none — PG-148 (closed) and `structure-EmbedDrawingTests.swift-048` covered the
  `editor(...)`/`makeTempVaultRoot` copies, which ADR-0051 §D4 then named as deliberate
  (`EmbedResolutionTests.swift:18-22`, `EmbedDrawingTests.swift:168-171`). These are different sites
  and carry no such note, so this is not a regression of either.

### T02-07 — Hosted-editor construction is repeated in five `Editor*` files with no recorded reason, while two shared builders exist
- Where: `Tests/EditorHeightTests.swift:37`, `Tests/EditorPointerTests.swift:40, 68`, `Tests/EditorCompletionCrashTests.swift:38`, `Tests/EditorControllerReadTimingTests.swift:112`, `Tests/EditorControllerReadTimingRemainingTests.swift:62, 113, 262`
- Category: duplicate-support
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: each site repeats the same five steps by hand — `CompletingTextView(usingTextLayoutManager:
  true)`, `textContainerInset`, `frame`, `textContainer?.size`, then
  `textContentStorage?.delegate = coordinator.decorations` — while
  `Tests/ScrolledEditorFixture.swift:64` and `Tests/EmbedEditorTestSupport.swift:75` already build
  exactly that. ADR-0051 §D4 allows a deliberate copy when it is named as one; a grep for an
  ADR-0051 citation or a "not `ScrolledEditorFixture`" note across these eight sites returns nothing,
  so unlike the Embed copies these are undocumented drift. The risk is a step silently omitted: the
  `textContentStorage` delegate line is what makes paragraph substitution run at all, and it is the
  easiest of the five to leave out.
- Trigger: n/a
- Fix: route them through `ScrolledEditorFixture` where the test needs a window, or extend
  `EmbedEditorFixtures.editor(...)` with the parameters these sites vary; where a copy must stay,
  state why in one comment, as ADR-0051 §D4 requires.
- Tracked: none

### T02-08 — Four `fatalError` calls in a shared fixture corpus; a failure there takes down the whole test process
- Where: `Tests/EmailFixtureCorpus.swift:563, 567, 571, 620`
- Category: hygiene
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: the PNG/image fixture helpers abort the process rather than throwing, e.g.
  ```swift
  fatalError("EmailFixtureCorpus.solidColorPNG: CGContext/CGImage creation failed")
  ```
  `xctest` hosts the whole suite in one process, so a `CGContext` that fails to be created on a
  loaded or headless machine kills every other test's result with it — the report shows a crashed
  bundle, not one red fixture, and nothing says which test asked. `Tests/DesignSystemTests.swift:444`
  has the same shape in miniature (`UserDefaults(suiteName:)!`).
- Trigger: n/a
- Fix: make the helpers `throws` and throw a named error; Swift Testing reports a thrown error as one
  failed test with its message intact. The repo already prefers `try #require` for exactly this
  (`Tests/EditorRestyleSwitchTests.swift:19`).
- Tracked: none

### T03-01 — Every Mail fixture leaves its temp tree behind: 3264 of them on this machine today
- Where: `Tests/MailStoreFixture.swift:121-126`, `Tests/MailStoreReaderTests+Fixtures.swift:84-89`, `Sources/Core/Email/MailStoreLocation.swift:48-49`
- Category: hygiene
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `freshRoot()` makes `FileManager.default.temporaryDirectory/pergamenum-mailstore-fixture-<UUID>` on every `MailStoreFixture.build()` and nothing ever removes it — `grep -rn removeItem Tests/` finds cleanups for index files, scripts, links, vault roots and `outside` dirs, never for a fixture root. There are 114 `build()` call sites in 29 files, each writing a SQLite `Envelope Index` plus `.emlx` files, and the unit suite runs at the end of every turn through `.claude/test-cmd`. Measured on this machine at 23:06, uptime 7h58m: **3264 leftover `pergamenum-mailstore-fixture-*` trees, 0.7 GB**, oldest stamped 16:03 today; plus 192 `pergamenum-mailstore-state-*` (`freshStateDirectory()`, 9 call sites) and 36 `pergamenum-test-mailstore-*` from the production resolver's own per-process root. Two tests also leave the fixture's `Envelope Index` at `0o000` if their `defer` `try?` fails (`Tests/MailStoreReaderTests.swift:387-394`, `:414-421`), so some of those trees are unreadable.
- Trigger: n/a (hygiene). Reproduce with `ls -d $TMPDIR/pergamenum-mailstore-fixture-* | wc -l` after one suite run.
- Fix: give `MailStoreFixture.Built` a cleanup door the suites can `defer` — the fixture is already the shared support file, so one `remove()` on it plus a `defer` at the 114 call sites, or make `Built` `~Copyable` with a `deinit`-shaped teardown the way `TemporaryVault` is built. `freshStateDirectory()` wants the same. Nothing else in the suite has to change.
- Tracked: none

### T03-02 — Three tests in `GutterRevealGeometryTests` pass green with nothing measured
- Where: `Tests/GutterRevealGeometryTests.swift:610`, `:668-670`, `:710`
- Category: disabled
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: three `guard let container = page.textView.textContainer else { return }` return silently, with no `Issue.record`, so `aRuleIsDrawnAcrossTheColumnAndNotTheContainer`, `aTableWiderThanTheColumnStillStartsAtTheColumn` and every caller of `expectInsideTheColumn` (including `aViewBlocksHostStaysInsideTheColumn`) report success having asserted nothing if the container is ever nil. The same file does it correctly three lines later — `Issue.record("nessun HorizontalRuleFragment per la riga ---")` at `:611-614`, and again at `:240-243` and `:688` — so the omission is inconsistent within one file, not a house convention. A nil `textContainer` on a TextKit 2 `NSTextView` is unlikely, which is exactly why the silent branch would never be noticed.
- Trigger: a future `Page` fixture built without a container (or a TextKit configuration change) makes three geometry tests vacuous with no signal.
- Fix: `Issue.record("nessun text container")` before each `return`, matching the file's own three correct sites.
- Tracked: none

### T03-03 — Three test headers describe production behaviour that no longer exists; eight more still say "RED against the stub"
- Where: `Tests/FoldStateOrdinalIndexStalenessTests.swift:5-18`, `Tests/MailStoreReaderTests.swift:378-381`, `:404-408`, `Tests/ListIndentFontInvariantTests.swift:5-38`
- Category: clarity
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: three headers state the opposite of what the source now says, verified against it. (1) `FoldStateOrdinalIndexStalenessTests` opens "`NoteTab.foldedEntries: Set<Int>` … stores a heading's identity as its ORDINAL INDEX … rather than a stable identifier", citing `Sources/Vault/NoteTab.swift:18`; that very field's doc comment now reads "each keyed by its own heading's UTF-16 character offset - not by ordinal position", and names this test file as the reason. The same header's second citation, `EditorDecorationDelegate.swift:99` for `foldedHeadings: [Int: Int]`, now lands on `let range: NSRange` inside `HiddenMarker`. (2) `MailStoreReaderTests.swift:378-381` says the implementation "treats every copy failure alike", and `:404-408` says `.permissionDenied` returns "the generic 'Mail is writing' wording … (the placeholder Task 3 left in `MailStorePreparation.swift:36`)"; `Sources/Features/Pratiche/MailStorePreparation.swift:36-39` has a dedicated `.permissionDenied` case naming Full Disk Access under ADR-0068 §D11. (3) `ListIndentFontInvariantTests` carries a 34-line "BUG:"/"INVARIANT THE CODER MUST IMPLEMENT" brief, and the note at `:41-50` says the coder already fixed it (PG-164, closed 2026-09-17). Eight more files head shipped features as red-against-a-stub: `ExternalDeletionReconcileTests.swift:35`, `FolderFileOperationTests.swift:13-14`, `GFMTableTests.swift:10-12`, `FrontmatterPrefixTests.swift:14-19`, `InlineSpanRevealTests.swift:14-18`, `LineFormatTests.swift:10-11`, `ListContinuationTests.swift:10-17`, `ListRenumberScopeTests.swift:8-10`, `ListNestingSeedTests.swift:11`.
- Trigger: n/a (docs drift). It misleads on exactly the files where a reviewer looks to learn what the current behaviour is, and it reads as a live bug report for a closed defect.
- Fix: a sweep that rewrites each header in the present tense to state the invariant the test pins. The precedent exists: PG-200 removed three "RED: the seam is a placeholder" paragraphs in 2026-09-22, and ROADMAP.md:972 records the same residue for `Tests/NoteIDRouteTests.swift:10` (outside this slice).
- Tracked: none (PG-164 and PG-420 are closed and their code fixes landed; this is the comment residue they left)

### T03-04 — A wall-clock assertion that a loaded machine will red
- Where: `Tests/MailStoreReaderTests.swift:397-402`
- Category: flaky
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: the test times a real call with `Date()` and asserts `#expect(elapsed < 1.5, "a permission failure must never pay the 2s torn-copy retry delay")`. The intent is to prove a classification (permission failure takes the fast path, not the retry path), but what it measures is the host's throughput: anything between the two paths — a 1.5 s stall on a saturated Mac — is indistinguishable from the defect. Load average on this machine while auditing was 5.42; the known `appcast-selftest-60s-timeout-under-load` case is the same shape.
- Trigger: run the suite while a second `xcodebuild` is building (the normal state with several worktrees) → red with no code change.
- Fix: assert the classification instead of the duration — have the publish path report which branch it took (a returned reason, or an injected clock the test advances), and keep the timing only as a message. If the duration must stay, raise it well above any plausible stall and say in the message that it is a smoke bound.
- Tracked: none (PG-120, the earlier non-reproducible red in this same file, was closed 2026-10-05 as not reproducible; this is a different assertion)

### T03-05 — `fatalError` in four fixtures aborts the whole test process instead of failing one test
- Where: `Tests/FoldedHeadingBadgeVerticalCenterTests.swift:109`, `Tests/GutterColumnSiteTests.swift:150`, `Tests/ListNestingForwardPassTests.swift:21`, `Tests/ListNestingTests.swift:16`
- Category: flaky
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: four test-side helpers end in `fatalError` — two `fatalError("layout never asked the delegate for a fragment")` and two `fatalError("marker not found: \(marker)")`. A `fatalError` in a Swift Testing process kills the whole run: instead of one red test among 7000 the suite dies with a crash report and no verdict for anything that had not finished, which is the worst possible signal from the merge gate. `Tests/ListNestingTests.swift:101` and `:111` force-unwrap `text.range(of: marker)!` in the same class for the same condition.
- Trigger: edit a fixture note so a marker string no longer occurs (an ordinary refactor of the test data) → the whole `PergamenumTests` run crashes rather than reporting one failure.
- Fix: make the helpers throwing and use `try #require(...)`, which Swift Testing already provides for precisely this (the suite uses it widely elsewhere).
- Tracked: none

### T03-06 — `InlineFormatTests` orders a real `.popUpMenu`-level panel onto the screen during the unit suite
- Where: `Tests/InlineFormatTests.swift:139-153`, `:168-175`
- Category: hygiene
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `barIsVisible(selecting:in:)` builds a window, calls `view.refreshFormatBar(theme: .emergency)` and asserts the bar's `isVisible`. That path is the production one: `FormatBarPanel.show` ends in `parent.addChildWindow(panel, ordered: .above)` then `panel.orderFront(nil)` (`Sources/Features/Editor/FormatBarPanel.swift:46-92`) on a `NeverKeyPanel` whose `level` is `.popUpMenu` (`Sources/Features/Editor/NeverKeyPanel.swift:27`), i.e. above ordinary windows. `theBarStillAppearsOverOrdinaryProse` asserts `isVisible == true`, so the panel really is on screen; the helper hides it one line later, so what the user sees is a flash over whatever is in front. The unit suite runs at the end of every turn through `.claude/test-cmd`, so it happens constantly on the dev machine. The same file's note at `:227-228` says the real panel was deliberately *not* driven in the neighbouring tests "because showing the real one would order a window front" — so the project already took the opposite decision three tests away.
- Trigger: n/a (hygiene). Visible as a brief popup during any `PergamenumTests` run.
- Fix: assert through the same seam the neighbouring tests use (placement/visibility decided without `show`), or front the panel inside the hosted-view harness, whose `NeverKeyWindow` refuses `orderFront` and records the refusal (`Tests/HostedViewSupport.swift`). Either keeps the coverage without touching the screen.
- Tracked: none (the production-side orphan panel is PG-258, open, which names `FormatBarPanel.swift:74`)

### T03-07 — `settle()` spends a fixed 200 ms instead of waiting for a condition
- Where: `Tests/HostedViewSupport.swift:205-215`, `Tests/LayoutDebtHostedTests.swift:356`
- Category: flaky
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: the shared hosted-view `settle()` is `for _ in 0..<10 { try? await Task.sleep(for: .milliseconds(20)); hosting.layoutSubtreeIfNeeded() }` — a budget, not a predicate. Its own comment records the budget being raised from 3 to 10 iterations because of a concurrent `xcodebuild` (PG-214/#424), which is the signature of a time-based wait: the next contended run buys another raise. Every hosted-view test also pays the full 200 ms whether the layout settled on the first pass or not. `LayoutDebtHostedTests.swift:356` sleeps a flat 150 ms for a height callback for the same reason; `:497-502` does it correctly, polling with a 100×50 ms bound and breaking on the condition.
- Trigger: heavy load → a layout that needs an eleventh pass → a red hosted-view test with no code change.
- Fix: give `settle()` a predicate plus a generous deadline (the shape already present at `LayoutDebtHostedTests.swift:497-502` and `HostedViewPrototypeTests.swift:368-376`), so a fast machine returns immediately and a slow one still passes.
- Tracked: none (PG-434, open, is a different defect in this same file: see Already tracked)

### T03-08 — The hand-rolled editor fixture is re-implemented across the suite although three shared ones exist
- Where: `Tests/FoldBadgeClickTests.swift:17-45`, `Tests/GutterColumnSiteTests.swift:298-312`, `Tests/HiddenBlockLinesTests.swift:160-175`, `Tests/HiddenFrontmatterTests.swift:41-55`, `Tests/IncrementalRestyleHostedTests.swift:338-367`, `:371-381`, `Tests/InlineFormatTests.swift:141-152`, `:179-183`, `:190-199`, `:232-239`, `Tests/LinkPreviewControllerTests.swift:45-60`, `Tests/LinkPreviewPopoverTests.swift:22-36`
- Category: duplicate-support
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: 43 files under `Tests/` construct a `CompletingTextView` directly and 24 of them also set `textContainerInset`, i.e. re-build the whole page fixture (view, window, inset, container width) by hand with the magic numbers copied — while `Tests/MarkdownStylerFixture.swift`, `Tests/ScrolledEditorFixture.swift` and `Tests/EmbedEditorTestSupport.swift` already exist for exactly this. ADR-0051 named the shared helpers and `EmbedEditorTestSupport`'s own header says a copy in each suite is a copy that drifts; the deep-refactor audit recorded the same family for the Embed copies only (`structure-EmbedDrawingTests.swift-048`). A layout constant changing means finding 24 copies.
- Trigger: n/a.
- Fix: one `EditorPageFixture.page(text:width:)` in a support file, returning view + window + layout, and let the suites call it. The in-slice copies above are mechanical conversions.
- Tracked: none (same family as audit finding `structure-EmbedDrawingTests.swift-048`, which named only the Embed copies; the `TemporaryVault` home is `structure-VaultTests.swift-3ac`)

### T03-09 — The same `sqlite3_trace_v2` statement counter is written twice, differing only in the class name
- Where: `Tests/MailStoreReaderBatchTests.swift:15-33`, `Tests/MailStoreReaderFollowedBatchTests.swift:13-30`
- Category: duplicate-support
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `StatementCounter`/`countingStatements` and `FollowedStatementCounter`/`countingFollowedStatements` are the same ~15 lines of trace-callback plumbing (register `sqlite3_trace_v2`, count `SQLITE_TRACE_STMT`, hand back the count) with two different names in two neighbouring files. Both exist to prove ADR-0036's batching claim, so they will always need to change together.
- Trigger: n/a.
- Fix: one counter in `Tests/MailStoreFixture.swift` (already the shared support file for this area), taking the connection and the closure.
- Tracked: none

### T03-10 — `FragmentDelegate` is declared three times
- Where: `Tests/FoldedHeadingBadgeVerticalCenterTests.swift:60-72`, `Tests/GutterColumnSiteTests.swift:106-118`, `Tests/TranscludedLineFragmentWidthTests.swift` (outside this slice, same body)
- Category: duplicate-support
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: the same `NSObject, NSTextLayoutManagerDelegate, @unchecked Sendable` stub, with the same `nonisolated(unsafe) var made` recording what the layout asked for, is copied verbatim into three files. Each copy carries its own concurrency escape, so a reviewer grading `@unchecked Sendable` has to grade the same twelve lines three times.
- Trigger: n/a.
- Fix: one `FragmentDelegate` in a support file; it is the same move ADR-0051 made for the other shared fixtures.
- Tracked: none

### T03-11 — Two tests pin production source *text* with a grep and a magic count
- Where: `Tests/InlineSpanRevealFenceTests.swift:334-361`, `Tests/ListRenumberWindowTests.swift:298-306`
- Category: clarity
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: the first greps `Sources/Features/Workspace/CardTextView.swift` for the literal opener `let kind: HiddenMarker.Kind? = switch styled.span {` and asserts the switch maps exactly 9 cases — a count that has to be bumped by hand on every legitimate addition, and a test that reds if the declaration is merely reformatted. The second greps `Sources/Features/Workspace/CardTextView+ListEditing.swift` and asserts `!source.contains("window:")`, so any unrelated parameter named `window` in that file fails it. The same file records at `:363-375` that an earlier point-in-time source fence was deleted for being unmaintainable, which is the verdict on this shape.
- Trigger: rename a case, reflow the declaration, or add an unrelated `window:` label → red with no behaviour change.
- Fix: assert the behaviour instead — exhaustiveness through a `CaseIterable` round-trip over `HiddenMarker.Kind`, and for the second, assert the card's renumbering outcome rather than the absence of a string. Keep the source grep only for the one thing it is good at, an import or a symbol that must not appear at all.
- Tracked: none

### T03-12 — A test requires a second GUI application to be running on the machine
- Where: `Tests/HostedViewPrototypeTests.swift:213`
- Category: flaky
- Severity: P3 · Confidence: suspected
- In flight: no
- What: the test reads `NSWorkspace.shared.runningApplications` and `try #require`s that an application other than the test host is present, to give `neverShown` a foreign pid to reason about (PG-331). On a developer Mac that always holds; on a bare CI runner, or a machine where only the test host is up, the `#require` fails and the test reds for an environmental reason. I did not trace a failing environment, hence `suspected`.
- Trigger: run the suite on a host with no second GUI application running.
- Fix: inject the pid the decision is made against rather than discovering one — the surrounding tests already pass inputs in explicitly.
- Tracked: none

### T04-01 — the vault-escape guard test cannot fail
- Where: `Tests/NoteStoreWriteGuardTests.swift:53-64`
- Category: disabled
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: the only test covering path traversal through the one guarded note door swallows every
  error — `} catch { // refusal - either a boundary violation or VaultWriteRefusal is acceptable. }`
  — and asserts nothing about the file system afterwards. `NoteStore.writeGuarded`
  (`Sources/Vault/NoteStore.swift:208-215`) resolves the boundary first and *then* compares hashes,
  so with the `boundary.url(for:)` line deleted the missing-file guard alone throws
  `VaultWriteRefusal.movedOn` and this test still passes. Its two siblings in the same file
  (`:30-33`, `:48-51`) both pin the post-state with `fileExists`/content; this one does not.
- Trigger: remove or weaken the `VaultBoundary` resolution in `writeGuarded`, then run
  `PergamenumTests` → green, while `writeGuarded(VaultFileChange(path: "../../evil.md", …))`
  writes outside the vault.
- Fix: `catch VaultBoundaryError` (or whatever `boundary.url(for:)` throws) specifically rather
  than bare, and add the sibling's post-state assertion — `../../evil.md` does not exist above
  `vault.root` after the call.
- Tracked: none

### T04-02 — stale red-phase narration tells the reader production code is a stub when it is not
- Where: `Tests/NoteIDFollowTests.swift:9-17,54-58,89,103,274`, `Tests/NoteIDRegistryTests.swift:9-13`,
  `Tests/NoteTreeTests.swift:174-175,246-250,270-277`, `Tests/NoteListEditingTests.swift:22-31`,
  `Tests/NoteIDRouteTests.swift:9-16,105`, `Tests/NarrowInputsTests.swift:10-11`,
  `Tests/MembershipRuleTests.swift:102,128,191`, `Tests/MarkupRevealTests.swift:159`,
  `Tests/MarkdownInlineTokenTests.swift:8`, `Tests/MarkdownLineTokenTests.swift:8`,
  `Tests/MarkdownLineSignatureTests.swift:9`, `Tests/NoteExportGoldenCorpus.swift:305`
- Category: clarity
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: twenty-two comment sites across twelve files still describe the tester-first state of a
  shipped chain — which tests are red, which pass "by accident", which production symbol is a stub.
  Four are verified false against the source: `NoteIDRegistry.path(forID:)`/`id(forPath:)` are
  implemented (`Sources/Core/Vault/NoteIDRegistry.swift:39,45`), `NoteTree.build(fromPaths:)` is
  implemented (`Sources/Core/Vault/NoteTree.swift:81`), and `NoteSelectionRule.opening` is a real
  type in its own file (`Sources/Features/Editor/NoteSelectionRule.swift:52`), not "a RED-placeholder
  `nonisolated static` on `NoteListPane`" as `NoteTreeTests.swift:247-250` still says. Two files
  contradict their own bodies: `NoteIDFollowTests.swift:14-17` says tests 15-25 never call
  `lookUpNote` "as a stub", while test 24 calls it at `:322,326`; `NoteIDRegistryTests.swift:9-13`
  says "every assertion below fails", and they all assert through the real accessors.
- Trigger: n/a
- Fix: delete the phase narration, keep the rule each comment states. The useful half of these
  comments (why a helper reads raw storage, why a case is a negative control) survives without the
  RED/GREEN framing.
- Tracked: none

### T04-03 — the note-id follow tests assert through hand-rolled copies of the accessors under test
- Where: `Tests/NoteIDFollowTests.swift:54-65`
- Category: duplicate-support
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: fourteen assertions in the file go through `rawPath(forID:)`/`rawID(forPath:)`, local
  re-implementations introduced because `NoteIDRegistry.path(forID:)`/`id(forPath:)` "are themselves
  stubs at Task 1 (always `nil`)". Both are implemented. Worse, the copy differs from production:
  `rawID` is `registry.notes.first { $0.value == path }?.key`, where production trims the path and
  returns `keys.min()` so repeated calls agree (`NoteIDRegistry.swift:45-49`) — the copy is
  order-dependent on Swift's per-process dictionary seed. The cases here keep one id per path, so it
  does not flake today; the coverage of the real lookups lives only in
  `Tests/NoteIDRegistryTests.swift`.
- Trigger: n/a (a registry file with two ids for one path would make `rawID` nondeterministic)
- Fix: delete both helpers, call `registry.path(forID:)`/`registry.id(forPath:)`.
- Tracked: none

### T04-04 — a fabricated `StorageEdit` stands in for the value under test
- Where: `Tests/OffsetShiftTests.swift:121-129`, `Tests/OffsetShiftTests.swift:180-183`
- Category: disabled
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: after `#expect(editor.coordinator.lastRecordedEdit != nil, …)` the test substitutes a
  hand-built edit — `let recorded = editor.coordinator.lastRecordedEdit ?? StorageEdit(range: …,
  delta: …)` — and the next two assertions check `recorded.delta` and `recorded.range.location`
  against exactly the arithmetic the fallback was constructed from. On the fallback path those two
  cannot fail, and `shiftDerivedState(by: recorded)` then drives the whole rest of the test off a
  value the production storage delegate never produced. The comment states the intent ("stood in for
  when missing, so the rest of the test still runs red against the placeholders"), which was a
  red-phase convenience.
- Trigger: a regression that stops `textStorage(_:willProcessEditing:…)` recording the edit → one
  failure at the `!= nil` line, then a run that reports the delta and location assertions as
  passing although nothing produced them.
- Fix: `let recorded = try #require(editor.coordinator.lastRecordedEdit)`, which stops the test at
  the cause.
- Tracked: none

### T04-05 — a fixture helper reports and then returns a range that points at nothing
- Where: `Tests/MarkdownLineSignatureTests.swift:200-208`
- Category: disabled
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `utf16Range(of:in:)` records an issue for a line absent from the fixture and then returns
  `NSRange(location: 0, length: 0)`. Every caller slices or scans with that range, so a single
  mistyped fixture line produces one honest failure plus a run of assertions comparing empty
  against empty, and the reported failure names the helper rather than the test that needed it.
  The same file demonstrates the alternative three lines below (`:214`, an explicit non-vacuity
  assertion).
- Trigger: edit one character of the `private let` note at the top of the file → failures whose
  messages point away from the cause.
- Fix: `throws` + `try #require(found.location != NSNotFound)`, so the test stops where the fixture
  broke.
- Tracked: none

### T04-06 — two assertions pass on an empty collection
- Where: `Tests/MarkupRevealTests.swift:105-110`, `Tests/MarkdownInlineTokenTests.swift:96-105`
- Category: assertion-free
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `anEmptyDocumentDoesNotCrashAndRevealsNothingBeyondItself` asserts
  `#expect(result.allSatisfy { $0 == 0 })` — true for an empty `result`, so the test pins only "did
  not crash", not what its name claims. `intrawordUnderscoresAndSpacedStarsProduceNoEmphasis` has a
  body consisting of a `for token in tokens(text)` loop whose only statement is an `Issue.record` in
  the bad case: if the tokenizer ever returns nothing at all, the parameterised test passes four
  times with no assertion executed.
- Trigger: a tokenizer regression that emits zero tokens → `MarkdownInlineTokenTests` green.
- Fix: add the non-vacuity assertion each needs — `result == [0]` (or the count the rule promises)
  and `#expect(!tokens(text).isEmpty)` before the loop.
- Tracked: none

### T04-07 — eight bound tests are skipped, silently, in a Release test bundle
- Where: `Tests/OffsetStoreBoundsTests.swift:163,187,215,246`,
  `Tests/OffsetStoreHostedCounterTests.swift:78,106,166,190`
- Category: disabled
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: all eight carry `.enabled(if: StepTally.isCounting)`, and `isCounting` is
  `#if DEBUG true #else false` (`Sources/Features/Editor/StepBuffer.swift:48-54`). This is
  deliberate and documented in both files and in the type's own comment — the counters compile out
  of Release — but the consequence is that ADR-0094 §D4/§D5/§D6's entire cost envelope (the
  constant-touch keystroke, the jump bound, the copy count, the rebuild count) is unverified in any
  Release-configuration run, and the run reports no signal distinguishing "skipped" from "nothing to
  check". Worth recording rather than fixing: the merge gate builds Debug, so the coverage is real
  there.
- Trigger: n/a
- Fix: if a Release run is ever made a gate, give the suite one test that fails when
  `!StepTally.isCounting` *and* the configuration was expected to count; otherwise leave as is and
  keep the limitation written down where the bench script is documented.
- Tracked: none

### T04-08 — support code copied instead of shared, after ADR-0051 named the shared helpers
- Where: `Tests/MarkdownConstructParserTests.swift:86`, `Tests/MarkdownInlineTokenTests.swift:17`,
  `Tests/MarkdownLineSignatureTests.swift:210`, `Tests/MarkdownLineTokenTests.swift:22`;
  `Tests/MarkupCoordinatorTests.swift:15-33,115-128`, `Tests/MessageAnchorEditorTests.swift:101-120`;
  `Tests/NoteFileOperationTests.swift:111-135`, `Tests/NoteRenameCharacterizationTests.swift`;
  `Tests/MarkupHidingListTests.swift:96-112`, `Tests/MarkupHidingListTests.swift:307-308`
- Category: duplicate-support
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: four byte-equivalent `slice(_:_:)` helpers; two hand-rolled offscreen-editor builders that
  duplicate `MarkdownStylerFixture.swift:36-81`'s `N5Editor.build` with no stated reason (the two
  other hand-built editors in the slice, `NoteListEditingTests.swift:52-86` and
  `NoteFindTests.swift:296-323`, each document why they cannot use it, so they are not copies but
  exceptions); two `~Copyable` `TemporaryVault` wrappers with their own `exists(_:in:)` free
  function (`OpsVault`, `CharacterizationVault`) that differ only in which store they expose; one
  test that its own comment admits restates `theDisplayedParagraphKeepsItsStoredLength` under
  another name "so a regression … fails on an assertion that names Task 4" — a task that has since
  shipped; and a hardcoded `45` for the content column where
  `ListMarkerRendering.contentColumn(level:font:gutter:)`
  (`Sources/Features/Editor/ListMarkerRendering.swift:92`) is the value the production code uses.
- Trigger: n/a
- Fix: one `slice` and one `~Copyable` vault wrapper in the existing shared support files; point the
  two undocumented editor builders at `N5Editor.build`; drop the admitted duplicate; derive the
  `45`.
- Tracked: none

### T04-09 — production seams that exist only for these tests
- Where: `Sources/Features/Editor/NoteTextView+Coordinator.swift:35,45,961,970`,
  `Sources/Features/Editor/NoteTextView+StorageEdits.swift:6`,
  `Sources/Features/Editor/StepBuffer.swift:38-54`,
  `Sources/Features/Editor/NoteTextView+DerivedState.swift:64`
- Category: test-only-seam
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: the list the checklist asks for, each verified by grepping `Sources/` for every reader:
  `Coordinator.restyleLog` and the `RestyleLog` type (written at four sites, read nowhere in
  production — its own doc comment says "A test seam and a diagnostic: nothing branches on it");
  `Coordinator.lastRecordedEdit` (assigned at `:917`, read nowhere in production);
  `Coordinator.offsetStoreTallies()` and `resetOffsetStoreTallies()` (declarations only, no
  production caller); `Coordinator.derivedStateSnapshot()` (declaration only); `StepTally` with its
  `touched`/`copies`/`shifts`/`splices`/`rebuilds` fields and `isCounting` (`isCounting` has no
  production reference at all). The fields are compiled into Release; only the counting is
  `#if DEBUG`.
- Trigger: n/a
- Fix: nothing to change — they are the measurement surface ADR-0094 asks for. Recorded so the
  Periphery delta is not re-litigated as dead code.
- Tracked: none

### T04-10 — a weakened assertion deferring to an unresolved SPEC gap, citing no id
- Where: `Tests/MarkdownConstructParserTests.swift:97-98`
- Category: pinned-defect
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: the fence-body assertion is weakened with `.trimmingCharacters(in: .newlines)` and the
  comment "Whether it carries the line break before the closing fence is not stated by the SPEC, so
  the assertion ignores it (reported as a gap)". No `PG-nnn`, no ADR section, no SPEC paragraph is
  named, so nothing says where the gap was reported or how it would be closed; the exact bytes
  `FenceChrome.blocks` hands back for a body are therefore unpinned in either direction.
- Trigger: n/a
- Fix: decide the byte in the SPEC and assert it, or open a ledger entry and cite its id here.
- Tracked: none

### T04-11 — a hand-built frontmatter fixture drifted from what `createNote` writes
- Where: `Tests/NoteTemplateTests.swift:229-230`
- Category: clarity
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `let frontmatter = "---\ndate: 2026-08-18\ntags:\n  - type-note\n---\n"` with the comment
  "What `createNote` writes: the block, one separating line break, then the body". Two tests in the
  same file (`:110`, `:129-135`) pin that `createNote` now writes `type-note` *and* `status-inbox`
  (ADR-0080 §D1, PG-384). The test still passes because it only measures offsets inside its own
  string, but the comment asserts a correspondence that no longer holds, and the next reader who
  trusts it will compute the wrong offset.
- Trigger: n/a
- Fix: build the string from the same source the two pins above use, or drop the claim in the
  comment.
- Tracked: none

### T05-01 — `PraticaSyncFixtures` leaks a vault directory on every call (1,680 left in the temp dir right now)
- Where: `Tests/PraticaSyncFixtures.swift:52-58`, `Tests/PraticaSyncFixtures.swift:74-80`
- Category: hygiene
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `makeVaultRoot` and `makeRegenerationVaultRoot` create `pergamenum-pratica-sync-vault-<UUID>` / `pergamenum-pratica-regen-vault-<UUID>` under `FileManager.default.temporaryDirectory`. Nothing removes them: no caller in the roughly ten Pratica sync suites has a `defer`. The only cleanup in the family is `PraticaLedgerTests.swift:63`. The Stop hook runs `PergamenumTests` at the end of every turn, so they pile up. On 2026-10-31 the user's `$TMPDIR` held 1,488 sync-vault and 192 regen-vault directories, and only this file uses those prefixes. They sit in the per-user temp dir, so no real vault or state is touched; that is why this is P3.
- Trigger: n/a
- Fix: return an owning `~Copyable` value with a `deinit` that removes the directory, as `TemporaryVault` does (`Tests/TemporaryVaultSupport.swift:44-47`), or hold a `TemporaryVault` and seed under its `root`. The prefix comment at `:71-73` can stay.
- Tracked: none (the 2026-09-11 audit, line 945, asked for this file to exist; it did not cover cleanup)

### T05-02 — "Red until Task N" headers describe production code that has since shipped
- Where: `Tests/PraticaSyncIntegrityTests.swift:9-10`, `Tests/PraticaSyncIntegrityTests.swift:20-22`, `Tests/PraticaSyncIntegrityTests.swift:74-75`, `Tests/PraticaSyncIntegrityTests.swift:103-105`, `Tests/PraticaSyncIntegrityTests.swift:151-153`, `Tests/PraticaWizardTests.swift:216-217`, `Tests/PraticaSyncAttachmentTests.swift:233-245`, `Tests/PraticaSyncPendingTests.swift:228-233`, `Tests/PraticaLiveSyncTask3Tests.swift:52-54`, `Tests/PraticaLiveSyncTask3Tests.swift:79-81`, `Tests/PraticaFileOperationsSessionTests.swift:12-35`, `Tests/OutlineMapTests.swift:10`, `Tests/OutlineStoreTests.swift:11`, `Tests/OutlineMapPropertyTests.swift:19-20`, `Tests/OutlinePaneFoldableOffsetTests.swift:14`, `Tests/OutlinePaneInputsTests.swift:11`, `Tests/PlaudQuoteTests.swift:9-11`, `Tests/PraticaCommandTests.swift:13-14`, `Tests/PraticaDeleteKeyTests.swift:13-14`
- Category: clarity
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: these TDD-era comments say the production fix is still missing and cite exact source lines. I checked the source and every named fix has landed. `PraticaSyncIntegrityTests` calls itself a "Tester-declared red suite", but `noLongerInMail` now has the ledger fallback (`PraticaSyncEngine.swift:231-245`; the comment cites `:206`). `seenInMail` is subtracted at `PraticheController+Ledger.swift:349`. `takenNoteNames` is appended at `PraticaSyncEngine+Folder.swift:65,69`. The injected `quarantine` is called at `PraticaSyncEngine+Messages.swift:957` and feeds `attachmentProblems` at `:726`. In `PraticaWizardTests.swift:216-217` the comment says the stub "still writes unconditionally", yet `PraticaCreation.swift:19` passes `expectingAbsent: true`. A reader who trusts these comments will think the merge gate is red or will go looking for a missing fix. Across all of `Tests/`, 22 files contain the phrase.
- Trigger: n/a
- Fix: rewrite each header to describe what the test pins now and drop the cited line numbers. One sweep over the 22 files from `grep -rln "Red until Task\|Tester-declared red" Tests/`.
- Tracked: none (a new instance of the family ROADMAP §Chain 13 item 8 names for `Tests/NoteIDRouteTests.swift:10`, closed under PG-266)

### T05-03 — The randomized oracle tests pass on a degenerate generator
- Where: `Tests/OffsetStoreModelTests.swift:16-25`, `Tests/OffsetStoreModelTests.swift:29-38`
- Category: assertion-free
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: these 40 parameterized cases can fail only through `Issue.record` inside `if let run.firstDisagreement()`. Nothing checks that the run did any work, for example that the stores grew or that edits and splices both happened. If `OffsetStoreRun.step()` became a no-op or produced only empty edits, all 40 would stay green. The later edge-case tests in the same file and `OutlineMapPropertyTests.swift:192-202` show the non-vacuity guard the project already uses.
- Trigger: n/a
- Fix: after each loop, `#expect` a coverage counter on the run (operations by kind, maximum store size above some floor).
- Tracked: none

### T05-04 — Fixed sleeps where a deadline poller already exists
- Where: `Tests/PraticaEntryCarryBackTests.swift:96`, `Tests/PraticaEntryCarryBackTests.swift:230`, `Tests/PraticaEntryCarryBackUndoTests.swift:32`, `Tests/PraticaEntryCarryBackUndoTests.swift:66`, `Tests/PraticaSyncIntegrityTests.swift:45`
- Category: flaky
- Severity: P3 · Confidence: suspected
- In flight: no
- What: `try await Task.sleep(for: .milliseconds(300))` is used to wait for asynchronous carry-back or undo work to settle. Under the full parallel suite, which is the load the PG-213/PG-218 flakes came from, 300 ms is a guess and also a fixed cost on every run. The 50 ms sleep in `PraticaSyncIntegrityTests` only moves an mtime, and setting `.modificationDate` explicitly would make it deterministic. `waitUntil` (`Tests/DiaryControllerTests.swift:8`, already used by `PraticaEntryCarryTests` and eight other files) polls against a deadline.
- Trigger: n/a
- Fix: replace each sleep with `waitUntil { <observable condition> }`, and set the mtime directly with `FileManager.setAttributes`.
- Tracked: none

### T05-05 — Verbatim helper copies across the Pratica live-sync suites
- Where: `Tests/PraticaLedgerFolderTrashEdgeTests.swift:66-74`, `Tests/PraticaLiveSyncTrashedMidRunTests.swift:51-59`, `Tests/PraticaLiveSyncRelocatedMidRunTests.swift:28-47`, `Tests/PraticaLiveSyncUnloadedLedgerReadTests.swift:12-31`, `Tests/PraticaLiveSyncTask3Tests.swift:12-30`, `Tests/PraticaLiveSyncTrashedMidRunTests.swift:25-41`, `Tests/PraticaLinkCommandTests.swift:24-40`, `Tests/PraticaLinksWriterTests.swift:118-134`, `Tests/PraticaLedgerFolderTrashEdgeTests.swift:53-57`, `Tests/PraticaLedgerFolderTrashTests.swift:29-33`, `Tests/PraticaEntryCarryBackTests.swift:11-22`, `Tests/PraticaEntryCarryVaultSwitchTests.swift:15-40`
- Category: duplicate-support
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: under ADR-0051 §D4, a fixture is shared only if it is byte-identical, and a copy that differs stays local with a comment saying how. These are byte-identical copies with no such comment: `stop(continuing:on:)` (twice), the dossier-note builder (four times), `messageWithNoLink` (twice), `stateImporting` / `ledgerState(importing:)` (same body, two names), and `PhaseLog` + `anchoredCount(in:)` (twice).
- Trigger: n/a
- Fix: move them into `PraticaSyncFixtures.swift` (or a `PraticaLiveSyncSupport.swift`) and delete the copies.
- Tracked: none

### T05-06 — Test-only hooks compiled into Release
- Where: `Sources/Features/Pratiche/PraticheController.swift:120`, `Sources/Features/Diary/DiaryController.swift:68`, `Sources/Vault/VaultSession.swift:67`
- Category: test-only-seam
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: checklist item 7 inventory. The tests in this slice drive three seams that exist only for them. `testOnlyCarryHook` is awaited at `PraticaEntryCarry.swift:234`. `testOnlyWriteHook` is awaited at `DiaryController.swift:284,300`. `testOnlyStarredSaveCount` is incremented at `VaultSession+Starred.swift:29,61,100`. None is under `#if DEBUG`, unlike `StepBuffer.swift`'s counters, so Release builds carry an optional closure check on the write and carry paths.
- Trigger: n/a
- Fix: wrap the three in `#if DEBUG`, as `StepBuffer` does, or document in place why they must ship.
- Tracked: none

### T06-03 — `UserDefaults` suites created and never removed
- Where: `Tests/RecordingsControllerTests.swift:32-37`, `Tests/SparkleUpdateControllerTests.swift:33-38`
- Category: hygiene
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `isolatedDefaults` writes `disablePlaud` or `disableUpdater` into a fresh `RecordingsControllerTests.<UUID>` or `SparkleUpdateControllerTests.<UUID>` suite and never calls `removePersistentDomain`. Each test that writes leaves one plist in `~/Library/Preferences`. The inline Sparkle suites at `:51`, `:69` and `:82` set no key, so they probably leave no file. `ShortcutTests.swift:174-182` shows the right shape. This is P3, not P2 like T06-01, because it is a handful of plists per run holding one flag with a throwaway name, not the per-controller leak behind the 1.1M files.
- Trigger: n/a
- Fix: put `defer { defaults.removePersistentDomain(forName:) }` beside each suite, or use the shared helper T05-10 proposes.
- Tracked: none

### T06-04 — Temp files and directories created and never removed
- Where: `Tests/QuickLookFocusTests.swift:228-234`, `Tests/PraticheSettingsTests.swift:138-143` (used at `:148`, `:180`), `Tests/RecentVaultsTests.swift:15-20`
- Category: hygiene
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `tempFile()` writes `pg298-quicklook-<UUID>.txt`, `makeRoot()` creates `settings-root-<UUID>` directories, and `makeVaultDirectory()` creates `pergamenum-recents-<UUID>` directories. All three go under `temporaryDirectory`, and none has a `defer` to remove them. `rememberReportsThePathTheMaximumCapEvicts` alone creates maximum+1 directories per run.
- Trigger: n/a
- Fix: use `TemporaryVault`, or another `~Copyable` owner with a `deinit`, or add a `defer { removeItem }`.
- Tracked: none

### T06-05 — `ReleasePipelineTests` runs outside tools inside the repository tree
- Where: `Tests/ReleasePipelineTests.swift:232-251` (`run(executable:arguments:currentDirectory:)` builds the `Process` at `:238` and launches it at `:251`; callers pass `/usr/bin/env python3 scripts/appcast.py --self-test` and `/bin/bash -n`, cwd from `resolvedRepoRoot()`)
- Category: hygiene
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: the unit suite runs whatever `python3` is first on the PATH, from the checkout. `--self-test` is documented as touching no repository, so this is not a write hazard today. It is still the only unit test that depends on the host's Python, it runs every turn, and the merge gate turns red when the PATH changes.
- Trigger: n/a
- Fix: resolve `python3` once with an absolute path and skip with a clear message when it is missing. Or move the self-test to CI and `release.sh`, which already run it.
- Tracked: none (the pipe drain issue in the same file is under Already tracked)

### T06-06 — `RowCommandTests` builds a real EventKit store
- Where: `Tests/RowCommandTests.swift:25`
- Category: hygiene
- Severity: P3 · Confidence: suspected
- In flight: no
- What: `EventKitStore()` makes a real `EKEventStore` and calls `refreshAccessStatus()` (`Sources/Calendar/CalendarService.swift:61`). The test host carries the app's bundle id, so it inherits any calendar grant, and the store sees the person's calendars. The init requests no access and nothing is written, so the exposure is reads at most. The UI suite isolates the same thing with `-disableCalendar`. The same file also never calls `controller.close()`.
- Trigger: n/a
- Fix: pass a fake `CalendarService` (or an isolated store) the way `LinkFixtures.actions(root:)` does, and close the controller.
- Tracked: none

### T06-07 — Assertion-free test: `pratiche` read only for not crashing
- Where: `Tests/PraticheConnectorTests.swift:150`
- Category: assertion-free
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: the body ends in `_ = VaultAPI.pratiche(session)` with no `#expect`, so it passes on any answer that does not trap.
- Trigger: n/a
- Fix: assert the payload, for example the count or the empty list the name implies.
- Tracked: none

### T06-08 — Assertion-free test: fenced lines are never checked
- Where: `Tests/RelatedSectionLineRolesTests.swift:40-45`
- Category: assertion-free
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `fencedLinesDoNotRaiseTooManyLinks` holds only `_ = try RelatedLink.add(...)`. The name promises that the fence lines stay untouched, but nothing compares them.
- Trigger: n/a
- Fix: `#expect` that the fenced block in the output equals the input's.
- Tracked: none

### T06-09 — A delivery test asserts only its own precondition
- Where: `Tests/ReminderDeliveryTests.swift:65-70`
- Category: assertion-free
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `anOpenedRouteWithNoSinkReturns` checks the precondition and then calls `deliver`. Nothing is asserted after the call, so it is a does-not-crash test.
- Trigger: n/a
- Fix: assert the observable outcome, for example that no route was recorded or that the return value is what the name promises.
- Tracked: none

### T06-10 — A test asserts a constant
- Where: `Tests/QuitReviewTests.swift:187`
- Category: disabled
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `theNoteSaveCapIsTenSeconds` asserts that a `static let` equals 10. It pins a number, not a behaviour, and it changes in lockstep with the constant.
- Trigger: n/a
- Fix: drop it, or test the behaviour the cap bounds through the injected `sleep`.
- Tracked: none

### T06-11 — Sidebar order assertions are skipped when a row is missing
- Where: `Tests/SidebarTests.swift:63-68`, `:80-82`
- Category: disabled
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: the adjacency `#expect` sits inside `if let praticheIndex, let recordingsIndex` (and `tasksIndex`, `unfiledIndex`). The pane under test has its own `contains` check, but if «Registrazioni» or «Attività» left the LAVORO group, the order assertion would silently not run.
- Trigger: n/a
- Fix: `try #require` both indexes.
- Tracked: none

### T06-12 — The appcast self-test still races a 60 s wall-clock watchdog
- Where: `Tests/ReleasePipelineTests.swift:236-258`
- Category: flaky
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: the `Process` is killed by a `Task.sleep(nanoseconds:)` watchdog after 60 s. Project memory records the test going red at about 60 s under load, and it still does. Separately, the pipes are read only after `waitUntilExit`, which deadlocks once the output passes the 64 KB pipe buffer.
- Trigger: a full suite run on a loaded machine (another worktree building, the UI suite running).
- Fix: drain the pipes while the process runs (`readabilityHandler`) and give the watchdog headroom, or take this test off the per-turn gate (see T06-05).
- Tracked: regression of PG-110

### T06-13 — Recording poll tests assert after fixed sleeps
- Where: `Tests/RecordingsControllerTests.swift:326`, `:330`, `:378`, `:382`, `:412`, `:420`
- Category: flaky
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: these tests sleep 20, 30 or 60 ms and then assert on `pollingRecordingIDs` or `recordings`, against a 5 ms poll interval. PG-204 fixed exactly this shape in the sibling `pollingStopsAndMarksExpiredAfterTheInjectedTimeout` by switching to `waitUntil(timeout:)`. The other three tests kept the sleeps.
- Trigger: a loaded machine, where 30 ms is not enough for the first poll.
- Fix: `try await waitUntil(timeout: .seconds(5)) { … }` before each assertion, as at `:351`.
- Tracked: none (same shape as closed PG-204, which fixed one test of the four)

### T06-14 — `drain()` stands in for "nothing else happened"
- Where: `Tests/QuitTestSupport.swift:142-145`
- Category: flaky
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `drain()` does 20 `Task.yield()` calls and then a 50 ms sleep. Quit tests call it and then assert that no further question or reply arrived. On a slow run a late callback lands after the window, so the test is green when it should be red, a false negative.
- Trigger: a loaded machine.
- Fix: gate on the coordinator's own completion (a `Gate` opened by the injected `reply`) instead of a time window.
- Tracked: none

### T06-15 — Fixed waits used to move time or the run loop
- Where: `Tests/PraticheControllerTests+Conversations.swift:150` (`Task.sleep(50ms)` to move a millisecond generation key), `Tests/ReplayAndWindowCoverageTests.swift:16` (`RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))`)
- Category: flaky
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: the first test depends on the wall clock advancing between two writes. The second waits a fixed 150 ms for AppKit work to happen.
- Trigger: clock granularity or load.
- Fix: inject the generation clock, and wait on the condition with a deadline.
- Tracked: none

### T06-16 — Environment-dependent shapes
- Where: `Tests/ProseTypographyTests.swift:74`, `:81`, `:249` (Avenir Next, Papyrus, Georgia), `Tests/PraticheControllerTests.swift:121-129` (0o000 permissions as an EPERM probe; same trick in `QuitGapTests.swift:207`, `QuitVanishedSchedaTests.swift:184`, `RecordingsControllerTests.swift:209`, `QuitSaveTests.swift`), `Tests/ReminderDeliveryTests.swift:86` (reads the host process's global notification delegate), `Tests/ReminderRescheduleKeyTests.swift:93-107` (one `Task.yield()` to catch `isScanning` mid-scan)
- Category: flaky
- Severity: P3 · Confidence: suspected
- In flight: no
- What: these pass on this Mac today but depend on the installed fonts, on not running as root, on the app's launch state inside the test host, and on executor scheduling.
- Trigger: a different machine or CI image, root, or a scheduler change.
- Fix: font tests should `#require` the font or use a bundled one. Hold the scan behind a `Gate` instead of a single yield. Build the delegate test on an injected center.
- Tracked: none

### T06-17 — The rich twin's rendition poll gives up silently
- Where: `Tests/ScrolledEditorFixture.swift:367-370`
- Category: flaky
- Severity: P3 · Confidence: suspected
- In flight: no
- What: `RestyleTwin.rich` polls up to 100×50 ms for both editors' image renditions, then carries on whether they arrived or not. A twin built without renditions makes the differential tests compare a state the fixture's comment says can't happen.
- Trigger: load beyond 5 s.
- Fix: after the loop, `#require` that both renditions are non-empty (the function already `throws`).
- Tracked: none

### T06-18 — Quit tests re-implement `ConflictProbe` and its siblings
- Where: `Tests/QuitConflictCapTests.swift:13-57` (`CapProbe`), `Tests/QuitCoordinatorTests.swift:11-62` (`QuitProbe`), `Tests/QuitGapTests.swift:10-37` (`GapProbe`), `Tests/QuitVanishedSchedaTests.swift:13-38` (`SchedaQuitProbe`), `Tests/QuitVaultSwitchTests.swift:211-223`, against `Tests/QuitTestSupport.swift:156-209`. Also `bytes(_:_:)` at `QuitConflictTests.swift:13`, `QuitConflictLastCheckTests.swift:9` and `QuitConflictOffScreenTests.swift:11`; `diaryPath` at `QuitConflictTests.swift:28` and `QuitConflictLastCheckTests.swift:13`; `holdDiaryWrite` at `QuitConflictLastCheckTests.swift:95-115` against `quitConflictedDiary` (`QuitTestSupport.swift:106-134`); `column(_:)` at `QuitReviewTests.swift:21`, `QuitReviewConflictTests.swift:11` and `QuitReviewCoverageTests.swift:10`; and a private `tab(...)` at `QuitReviewTests.swift:8` that shadows the shared one
- Category: duplicate-support
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `QuitTestSupport` is the shared quit helper, yet five files build their own probe and three files keep private copies of the same small helpers. A change to `QuitCoordinator`'s injected closures has to be made in six places.
- Trigger: n/a
- Fix: extend `ConflictProbe` with the extras the copies add, such as a cap clock or a reveal log, and move `bytes`, `diaryPath` and `column` into `QuitTestSupport`.
- Tracked: none

### T06-19 — Controller and `CommandActions` builders copied beside `LinkFixtures`
- Where: open-controller copies at `Tests/PraticheLedgerDoorTests.swift:116`, `Tests/PraticheLedgerOrderingTests.swift:28`, `Tests/QuickOpenCreationTests.swift:23`, `Tests/RecordingsControllerTests.swift:23`, `Tests/ReminderRescheduleKeyTests.swift:18`; `makeActions` at `Tests/RowCommandTests.swift:22-41`, a near-verbatim copy of `LinkFixtures.actions(root:)` (`Tests/LinkNavigationTestSupport.swift:24-40`)
- Category: duplicate-support
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `LinkFixtures.controller(root:)` and `.actions(root:)` already exist. The copies drift: `RowCommandTests` takes a real `EventKitStore()` (T06-06), while the shared builder does not.
- Trigger: n/a
- Fix: call the `LinkFixtures` helpers and add a parameter where one copy needs it.
- Tracked: none

### T06-20 — Pratica, recordings and related-section fixtures repeated
- Where: pratica notes at `Tests/PraticheConnectorTests.swift:16`, `Tests/PraticheConnectorTimelineDatePinTests.swift:14`, `Tests/PraticheControllerTests+Conversations.swift:84`, `Tests/PraticheLedgerDoorTests.swift:169`; `proposal()` at `PraticheLedgerOrderingTests.swift:34` and `PraticheControllerTests.swift:197`; FDA temp-dir setup three times in `PraticheControllerTests.swift` (`:94`, `:112`, `:122`); `sampleProposal`/`sampleRecording` at `RecordingsControllerTests.swift:39-59` and `RecordingsViewModelTests.swift:13-42`; `doc(_:)` at `RelatedLinkSectionPreservationTests.swift:9` against `RelatedSectionFixture.note`; `VaultSession(root:stateBase:bundledVocabulary: Bundle.pergamenumResources…)` at `RelatedLinkSectionPreservationTests.swift:50`, `RelatedSectionLineRolesTests.swift:72`, `:210`, `:230`, `RelatedSectionTests.swift:37`, `:56`
- Category: duplicate-support
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: the same fixtures are declared privately in several files and their contents are not compared. The ADR-0051 amendment of 2026-09-20 recorded the pratica-note copies as out of scope when it closed PG-190, and the copies are still there.
- Trigger: n/a
- Fix: one `PraticaFixtures`/`RecordingsFixtures` file and a `RelatedSectionFixture.session(vault:)` helper. Alternatively, re-confirm in ADR-0051 that these copies stay.
- Tracked: regression of PG-190

### T06-21 — Production seams that exist only for the unit suite
- Where: `Sources/Features/Diary/DiaryController.swift:68` (`testOnlyWriteHook`, awaited at `:284`, `:300`; used by `QuitTestSupport.swift:112`, `QuitConflictLastCheckTests.swift:100`, `QuitCoordinatorTests.swift:405`); `Sources/Features/Pratiche/PraticaLiveSync.swift:171` (`preparationStep`, used by `PraticheControllerTests+SyncIntegrity.swift:90`); `isTestHost:` on `SparkleUpdateController` and `RecordingsController` (`RecordingsController.swift:123`); `pollInterval:`/`pollTimeout:` (`RecordingsController.swift:124-125`); `ReminderScheduler(becomesDelegate:queue:access:)` (`Sources/Calendar/ReminderScheduler.swift:57-71`, documented as unit-suite only); `NoteTextView.Coordinator.restyleLog` (`NoteTextView+Coordinator.swift:35`, read only by tests and the bench fixtures)
- Category: test-only-seam
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: the list was confirmed by grep in `Sources/`. `windowKeyObserver` and `undoObservers` are production state that tests merely read, so they are not seams. `MailStoreOverride`, `RealEditProbe` and the `RESTYLE_BUDGET_*` gating live in `Tests/` only. `testOnlyWriteHook` is the one seam whose name says what it is; `restyleLog` costs an increment on every restyle in production.
- Trigger: n/a
- Fix: none required. Keep them named and documented as seams, and consider `#if DEBUG` around `restyleLog`.
- Tracked: none

### T06-22 — "Red until / stub" headers describe code that has shipped
- Where: `Tests/PraticheControllerTests+SyncIntegrity.swift:22-24`, `:60-63`, `:113-116`, `:150-151`, `:165-167`, `:184-185`; `Tests/ProseTypographyTests.swift:9-13`; `Tests/QuickLookFocusTests.swift:15-16`; `Tests/RestyleScopeTests.swift:14`; `Tests/RowCommandTests.swift:15-19`, `:98-100`, `:125`, `:207-208`; `Tests/SidebarTests.swift:55-56`, `:72-73`; `Tests/SparkleUpdateControllerTests.swift:26-28`, `:64`, `:76`; `Tests/ReleasePipelineTests.swift:12-14`; `Tests/RecordingsControllerTests.swift:9-11`; `Tests/RestyleBudgetSupport+Update.swift:4` ("ADR-0096 (planned)"); `Tests/StructureMapTests.swift:12`, `:165` ("the stub's map is empty")
- Category: clarity
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: the fixes these headers wait for have landed. For example, `PraticaLiveSync` has `stopRequested` (`PraticaLiveSync.swift:165`) and `PraticheController.inspectorKey(for:)` reads `landedGeneration`. `SparkleUpdateController` ORs in `isTestHost`. ADR-0096 exists. Pratiche and «Da classificare» are in LAVORO. These tests are green on `main`, yet their comments say red.
- Trigger: n/a
- Fix: rewrite each header to say what the test pins now. The same sweep as T05-02 (`grep -rln "Red until\|RED against\|stub" Tests/`).
- Tracked: none

### T06-23 — Smaller clarity items
- Where: `Tests/ProseParagraphSpacingTests.swift:229-240`, `Tests/RealEditPathTests.swift:22`, `Tests/ShortcutTests.swift:69-76` and `:95-101`, `Tests/QuitVaultSwitchTests.swift:222`
- Category: clarity
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `ProseParagraphSpacingTests` hardcodes `paragraphSpacing == 8`, while its header says it checks the `spacing.paragraph` token. The token is 8 in both shipped themes (`Resources/Themes/pergamenum-{light,dark}.json:145`), so a token change would fail with no pointer to why. `RealEditPathTests` `print`s its outcome lines; its header says this is intentional evidence. `everyShippedDefaultIsUsable` and `everyCommandOutsideShipsUnboundShipsAValidUsableKey` assert the same thing twice. The injected sleep in `QuitVaultSwitchTests` is 60 s, so a regression shows up as a hang, not a failure.
- Trigger: n/a
- Fix: read the value from `Theme.emergency`'s token, route `print` through an attachment or an env gate, delete the older of the two shortcut tests, and use a short injected sleep or a `Gate`.
- Tracked: none

### T07-tests-02 — `UserDefaults(suiteName:)` suites left behind in the user's Preferences on every run
- Where: `Tests/ThemeCustomizationTests.swift:123` (and :144, :170, :219, :307, :332, :343, :376, :408, :430, :445, 11 sites), `Tests/TagBrowserTests.swift:121`, `Tests/VaultControllerLandedChangeTests.swift:476`
- Category: hygiene
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: each test builds a fresh UUID-named suite and never calls `removePersistentDomain(forName:)`. None of the three files contains that call. The host is the unsandboxed app, so every suite that gets a write leaves a `pergamenum.tests.<UUID>.plist` (or `VaultControllerLandedChangeTests.<UUID>.plist`) in `~/Library/Preferences`, more than ten per run, repeated by the Stop hook every turn. The siblings in this slice clean up: `UpdatePathFixture.swift:172`, `VaultControllerCacheCleanupTests.swift:64-65`, and OpenTabsStore/Shortcut tests.
- Trigger: any run of `PergamenumTests`.
- Fix: one shared helper (ADR-0051 §D2 style) that returns a `~Copyable` suite owner whose `deinit` removes the persistent domain. Replace the 13 call sites with it.
- Tracked: none

### T07-tests-03 — Fixtures built over the app's real domain and a live EventKit store
- Where: `Tests/UpdatePathFixture.swift:64`, `Tests/UpdatePathFixture.swift:74`, `Tests/UpdatePathFullWindowFixture.swift:57`, `Tests/TaskComposerTests.swift:163`
- Category: hygiene
- Severity: P3 · Confidence: suspected
- In flight: no
- What: `UpdatePathFixture` builds `EventKitStore()` in the unit host. `isIsolated` reads `UserDefaults.standard` `disableCalendar`, which is false there, so the fixture creates an `EKEventStore`, installs observers and reads access status for the person's calendar. `ThemeEngine()` (`UpdatePathFullWindowFixture.swift:57`, and inside the closure at `UpdatePathFixture.swift:74`) defaults to `.standard` and so reads the person's real theme selection, which can make the full-window fixture's typography depend on the machine. `TaskComposerTests.swift:163` builds a bare `VaultController()`, whose `RecentVaults()`/`OpenTabsStore()` defaults sit on the app's real domain. No write path was found for that test, so this is read-only exposure. None of these writes user data today. The risk is a future code path that does.
- Trigger: n/a, unless a change makes these stores write.
- Fix: inject a fake `CalendarStore` (the protocol exists), `ThemeEngine(defaults:)` with a throwaway suite, and `VaultController(recents: .volatile(), openTabs: .volatile())`, which the rest of the suite already uses.
- Tracked: none

### T07-tests-04 — The escape sentinel of a boundary test lands in the shared temp dir under a fixed name
- Where: `Tests/VaultDiskTests.swift:127`
- Category: hygiene
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `aPathEscapingTheVaultThrowsBeforeAnyByteIsWritten` writes `../fuori.md` through a `TemporaryVault` and asserts that `vault.root.deletingLastPathComponent()/fuori.md` is absent. `TemporaryVault.root` sits directly under the system temp dir (`TemporaryVaultSupport.swift:33-34`). A regression would therefore write a fixed-name file into the shared `$TMPDIR` that nothing cleans up, and a leftover from one failing run would make every later run fail. ADR-0051 §D4 kept `BoundaryFixture` local in `VaultBoundaryTests.swift:115-121` for exactly this reason, and `VaultBoundaryCallSiteTests.swift:23-27` mirrors it.
- Trigger: a regression in `VaultDisk.write`'s boundary check.
- Fix: build this test on a nested fixture (`container/level/vault`), as `VaultBoundaryCallSiteTests`'s `CallSiteFixture` does.
- Tracked: none

### T07-tests-05 — A test whose only check is "did not throw"
- Where: `Tests/ThumbnailStoreTests.swift:30`
- Category: assertion-free
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `clearCacheOnDiskIsANoOpWhenNothingWasEverRendered` has no `#expect` and no `#require`. It passes as long as the call returns, so it cannot tell a no-op from a call that deleted something it should not have.
- Trigger: n/a
- Fix: assert the cache directory's state after the call (absent, or present and empty), and that a sibling file in the state base survives.
- Tracked: none

### T07-tests-06 — A tautological assertion pins nothing about the drag payload
- Where: `Tests/VaultItemDragTests.swift:93-106`
- Category: disabled
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `dragNameForANoteBuiltFromANoteRecordEqualsTheRecordsTitle` builds the drag itself with `dragName: record.title` and then asserts `drag.dragName == record.title`. Its doc comment says it guards the SPEC §7.2 contract that a call site builds the payload from the title, but no production builder is exercised, so the test passes whatever the real call sites do.
- Trigger: n/a
- Fix: drive the production code that builds a `VaultItemDrag` for a note row (the sidebar's drag source) and assert on its output, or delete the test and say in the file that the contract is not covered.
- Tracked: none

### T07-tests-07 — Silent early returns and conditional-only assertions
- Where: `Tests/TranscludedLineTests.swift:142`, `Tests/TranscludedLineTests.swift:182`, `Tests/VaultBoundaryCallSiteTests.swift:271-277`
- Category: disabled
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `guard let manager = textView.textLayoutManager else { return }` passes the test without one assertion if TextKit 2 is ever not in use. That fallback is exactly the regression these tests exist to catch. In `readTimelineNeverResolvesAnAttachmentNameEscapingTheVault`, every assertion sits inside `if let entry = read.entries.first`, so a `readTimeline` that returns no rows at all (for example, because the fixture message stopped parsing) passes silently.
- Trigger: a fixture or setup regression that removes the guarded value.
- Fix: `try #require(textView.textLayoutManager)`. For the timeline test, split the two acceptable outcomes and `#expect` one of them explicitly (`read.entries.isEmpty || detail has no ".." name`), plus a positive control that the same fixture with a legal name yields one entry.
- Tracked: none

### T07-tests-08 — Developer tools shaped as tests, with `print` on every run
- Where: `Tests/StylerGoldenTests.swift:85-112`, `Tests/UpdatePathGateTests.swift:110-113`, `Tests/UpdatePathGateTests.swift:122-149`
- Category: disabled
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `stylerGoldenCapture` is gated by `.enabled(if: capturing)` (`TEST_RUNNER_STYLER_GOLDEN_CAPTURE`/`STYLER_GOLDEN_CAPTURE`), asserts nothing, `print`s the whole corpus, and writes with `try?` to `STYLER_GOLDEN_CAPTURE_PATH`, so a failed write is silent. `UpdatePathGateTests` is gated by `.enabled(if: UpdatePathGate.selected)` (`PG401_GATES`), and `guard UpdatePathGate.wanted(c) else { return }` at :124 makes a deselected case a silent pass. Its `print` at :110-113 runs on every suite run, not only in the gated benchmark. These are legitimate tools, but they show up in the test count and the log as tests.
- Trigger: n/a
- Fix: move both into a tagged suite (`.tags(.tool)`) or a script-driven target. Turn the per-case `guard … return` into an argument filter so deselected cases are not reported as passes, drop the ungated `print`, and make the capture write `try`.
- Tracked: none

### T07-tests-09 — Test names that say the opposite of what they assert
- Where: `Tests/TimeBlockGestureTests.swift:44`, `Tests/TranscriptNoteTests.swift:278`, `Tests/TaskComposerTests+SelectedTask.swift:24`, `Tests/TaskComposerTests+SelectedTask.swift:46`, `Tests/VaultControllerWriteCatchUpTests.swift:123`, `Tests/VaultControllerWriteCatchUpTests.swift:140`, `Tests/VaultControllerWriteCatchUpTests.swift:155`, `Tests/VaultControllerWriteCatchUpTests.swift:175`
- Category: clarity
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `aMoveThatWouldRunPastMidnightIsRefused` asserts `!= nil`: the move is clamped, not refused. `aRenderedNoteIsExpectedToFailTheLinterUntilTask9LandsTheFrontmatterAllowance`, whose comment says "INTENTIONALLY RED", asserts `violations.isEmpty`. `selectedTaskStaysStaleAfterASubtaskCaptureAndBreaksASecondOne` asserts that it does not stay stale, and its "The bug:" comment at :46 reads as if the bug were still present. Four `syncOpenNote…` tests are named after `syncOpenNote(with:)`, which ADR-0067 §D5 deleted; they now drive `landed(.written…)`, as the file's own header at :13-16 says. A red run would print a name that misleads whoever triages it.
- Trigger: n/a
- Fix: rename to the asserted behaviour (`…IsClampedToMidnight`, `aRenderedNotePassesTheLinter`, `selectedTaskFollowsASubtaskCapture`, `landedWriteRaisesThePrompt…`), and reword the :46 comment as history.
- Tracked: none (`TaskComposerTests+SelectedTask.swift` was created by PG-389, which split the file and did not touch names)

### T07-tests-10 — "RED / stub / until Task N" headers describe production code that has shipped
- Where: `Tests/TableEditTests.swift:5-14`, `Tests/TableRenderingTests.swift:16-22`, `Tests/TableRenderingTests.swift:188-192`, `Tests/TableRenderingTests.swift:210-227`, `Tests/TableRenderingTests.swift:316-321`, `Tests/TaskArrangementTests.swift:132-139`, `Tests/TaskMarkerLintTests.swift:11-20`, `Tests/TaskMarkerWriteTests.swift:11-19`, `Tests/TranscludedLineFragmentWidthTests.swift:5-18`, `Tests/TransclusionLayoutTests.swift:159-176`, `Tests/TranscriptMergeTests.swift:9-11`, `Tests/TranscriptNoteTests.swift:9-13`, `Tests/TypographyResolutionTests.swift:10-13`, `Tests/TypographyResolutionTests.swift:87-92`, `Tests/URLSchemeTests.swift:91`, `Tests/SurfaceParityUpdateTests.swift:13`, `Tests/UpdatePathCounterTests.swift:9-13`, `Tests/UpdatePathSourceGuardTests.swift:11-12`, `Tests/ThemeCustomizationTests.swift:312`, `Tests/VaultBatchMoveTests.swift:27-39`, `Tests/VaultBatchMoveTests.swift:92-95`, `Tests/VaultBatchMoveTests.swift:137-140`, `Tests/VaultBatchMoveTests.swift:171-172`, `Tests/VaultBatchMoveTests.swift:231-233`, `Tests/VaultBoundaryTests.swift:5-8`, `Tests/VaultControllerExternalDeletionTests.swift:32-34` (and :54, :75, :94, :121, :141, :168, :231), `Tests/VaultControllerLandedChangeTests.swift:11-21`, `Tests/VaultDiskTests.swift:45` (and :67, :102, :154), `Tests/VaultMoveBatchTests.swift:17-21`, `Tests/VaultMoveTests.swift:21-24`
- Category: clarity
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: TDD-era comments still say the code under test is a placeholder. Examples: "`VaultMoveBatch.plan` always returns `.refused([])`", "`VaultSession.moveItems` and `VaultController.moveItems` are placeholders", "`announce(_:)` and `landed(_:)` are both intentional no-op stubs", "Red on today's code", "these tests exercise the existing store until the coder declares VaultBoundary", while the same files call `VaultBoundary.Violation`. The `VaultDiskTests` failure messages blame "stub del Task 8" for any throw. These suites have been green on main for weeks, so a reader trusting the comments thinks the gate is red, and a real failure message points at a stub that no longer exists. The family spans slices: 56 files under `Tests/` match `grep -rln "Red until Task\|Tester-declared red\|RED against\|Red on today\|RED here\|^// RED"`.
- Trigger: n/a
- Fix: one sweep: rewrite each header to state what the test pins now, drop the cited line numbers, and change the `VaultDiskTests` `Issue.record` text to a neutral "VaultDisk.write threw". Same family as T05-02.
- Tracked: none

### T07-tests-11 — `fatalError` in a fixture takes down the whole test host
- Where: `Tests/TranscludedLineFragmentWidthTests.swift:87`
- Category: clarity
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: a fixture precondition fails with `fatalError` instead of `Issue.record`/`#require`. If it fires, the unit host crashes and every test still pending in that process is reported as a crash. One fixture problem becomes a red suite with no pointer to the cause.
- Trigger: the fixture's precondition stops holding (a TextKit layout change).
- Fix: make the fixture `throws` and use `try #require(...)`.
- Tracked: none

### T07-tests-12 — Near-identical file names for different subjects, and a shared poller living in a test file
- Where: `Tests/VaultMoveBatchTests.swift:1`, `Tests/VaultBatchMoveTests.swift:1`, `Tests/VaultMoveTests.swift:1`, `Tests/DiaryControllerTests.swift:8`
- Category: clarity
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `VaultMoveBatchTests` covers the pure `VaultMoveBatch.plan` rules (ADR-0026 Task 1), `VaultBatchMoveTests` covers ADR-0041 §D8's walk and save counts, and `VaultMoveTests` covers the `moveItems` dispatch. The first two differ only in word order. `VaultBatchMoveTests.swift:243` also repeats the mid-batch-failure shape of `VaultMoveTests.swift:132`, as its own comment at :247-250 admits. `waitUntil`, used by `VaultMoveTests` and `VaultControllerMoveNoteTests`, is a module-wide helper declared at the top of `DiaryControllerTests.swift` (outside this slice, cross-slice location for the coordinator to dedupe) and not in a `*Support.swift` file. ADR-0051 §D2 put shared helpers in support files.
- Trigger: n/a
- Fix: rename `VaultBatchMoveTests` to `VaultMoveBatchingCountTests` (or merge its two count suites into `VaultMoveTests`), and move `waitUntil` to `Tests/AsyncWaitSupport.swift`.
- Tracked: none

### T07-tests-13 — Run-loop spins, a real timer and fixed-deadline polling
- Where: `Tests/UpdatePathFixture.swift:154`, `Tests/SurfaceParityUpdateTests.swift:96`, `Tests/UnsavedMarkPauseTests.swift:177-192`, `Tests/VaultMoveTests.swift:195`, `Tests/VaultMoveTests.swift:227`, `Tests/VaultMoveTests.swift:240`, `Tests/VaultMoveTests.swift:268`, `Tests/VaultControllerMoveNoteTests.swift:96`, `Tests/VaultControllerMoveNoteTests.swift:121`
- Category: flaky
- Severity: P3 · Confidence: suspected
- In flight: no
- What: two fixtures pump `RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001))`, one 1 ms turn, assuming deferred layout work completes inside it. `UnsavedMarkPauseTests` uses a real `TaskPauseScheduler` with a 20 ms interval, polls with a 2 s deadline, and then sleeps a fixed 100 ms as a negative proof. Under load, "nothing happened in 100 ms" can be a false green. The move and undo tests wait on fire-and-forget `Task`s through `waitUntil`'s fixed 2 s deadline. That deadline has held so far, but it is the shape of the PG-213/PG-218 cross-suite flakes, and the rest of this slice avoids it by calling the post-`await` half directly (ADR-0058 §D3).
- Trigger: a loaded machine during the full parallel suite (the Stop hook beside another worktree's build).
- Fix: replace the 1 ms spins with an explicit layout call (`ensureLayout`) or a loop bounded on the condition. For the pause test, use `ManualPauseScheduler` (`Tests/ManualPauseScheduler.swift`) as its siblings do, or keep the one real-timer test and drop the fixed-sleep negative. For the moves, have `moveNote`/`moveItems` return or expose the task so the test can `await` it.
- Tracked: none (the `waitUntil` helper is the PG-208-era fix for a fixed sleep, `TODO.md:743`; it does not cover these call sites)

### T07-tests-14 — Hosted editor and table fixtures, task builders and theme loaders copied across files
- Where: `Tests/TableColumnMenuTests.swift:75-134`, `Tests/TableGridCommitTests.swift:20-80`, `Tests/TableGridHostedAttachmentTests.swift:31-69`, `Tests/TableCaretTests.swift:33-65`, `Tests/TagDateClickTargetTests.swift:210-238`, `Tests/TagDateClickTargetTests.swift:203`, `Tests/TagDateClickTargetTests.swift:320`, `Tests/TaskArrangementTests.swift:16`, `Tests/TaskCommandTests.swift:9`, `Tests/TaskMarkerTests.swift:15`, `Tests/TaskMarkerWriteTests.swift:26`, `Tests/TaskArrangementTests.swift:274`, `Tests/TaskMarkerTests.swift:171`, `Tests/TableGridControlLabelTests.swift:14`, `Tests/TableRenderingTests.swift:266`, `Tests/TranscriptNoteTests.swift:15-48`, `Tests/TranscriptMergeTests.swift:13-41`, `Tests/TranscludedLineTests.swift:163-178`, `Tests/VaultControllerMoveNoteTests.swift:25`, `Tests/VaultMoveTests.swift:447`
- Category: duplicate-support
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: four table test files each build their own hosted `CompletingTextView`/table-grid fixture. `TagDateClickTargetTests` re-implements `EmbedEditorFixtures.editor` with a force unwrap at :232 and declares its `Spy` class twice (:203, :320). The `task()` helper wrapping `TaskParser.parse(...)!` appears in four files. Index-snapshot builders appear in two (plus `RolloverTests`). Theme-from-JSON loaders appear in two (plus `ProseTypographyTests`). `TranscriptNoteTests` and `TranscriptMergeTests` carry identical `makeTask`/`makeProposal`. `TranscludedLineTests:163-178` inlines its own `editor()` from :35-53. `exists(_:at:)` is duplicated between `VaultControllerMoveNoteTests` and `VaultMoveTests`. These are ADR-0051's "copies not worth closing" category, but none of them is named in its list.
- Trigger: n/a
- Fix: `Tests/TableHostedFixture.swift` for the four table files; reuse `EmbedEditorFixtures.editor` in `TagDateClickTargetTests`; one `TaskFixtures.task(_:)` using `try #require`; a shared `TranscriptFixtures`. Or record the remaining ones in ADR-0051's list of copies not worth closing.
- Tracked: none (ADR-0051's amendment covers other copies, such as `praticaNote` under PG-190)

### T07-tests-15 — New in-flight tests copy an existing card fixture and a marker table
- Where: `Tests/UnderscoreEmphasisConcealmentTests.swift:253-291`, `Tests/UnderscoreEmphasisConcealmentTests.swift:19`, `Tests/UnderscoreAndTransclusionCoverageTests.swift:15`
- Category: duplicate-support
- Severity: P3 · Confidence: confirmed
- In flight: yes
- What: `makeCard` is a copy of `CardConcealmentTests`'s fixture, and its own comment says so. `markerSpellings` in the coverage file repeats `emphasisMarkerSpellings` from the sibling file added in the same commit, so the two tables can drift apart without anyone noticing.
- Trigger: n/a
- Fix: before merge, lift `makeCard` into a shared card-fixture support file and declare the marker table once (module-internal) for both files.
- Tracked: none

### T07-tests-16 — Production types carry counters and hooks that exist only for tests
- Where: `Sources/App/VaultController.swift:213` (`unsavedMarkChecks`), `Sources/Vault/VaultSession.swift:67` (`testOnlyStarredSaveCount`), `Sources/Vault/FolderFileOperations.swift:22` (`onBoardsWalk`), `Sources/Features/Editor/NoteTextView+Coordinator.swift:35` (`restyleLog`), `Sources/Features/Editor/ModelSync.swift:27-30` (`compares`, `countCompare()`), `Sources/Features/Editor/FindSession.swift:42` (`updates`), `Sources/Features/Diary/DiaryController.swift:41` (`proseCompares`), `Sources/Features/Editor/OutlineStore.swift:47` (`tally`), `Sources/Features/Editor/NoteTextView+Transclusion.swift:106` (`lastScannedRange`), `Sources/Features/Editor/NoteTextView+DerivedState.swift:64` (`derivedStateSnapshot()`), `Sources/Features/Editor/TableGridView.swift:139` (`controlLabels`), `Sources/App/PergamenumApp.swift:46` (`isTestHost`)
- Category: test-only-seam
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: twelve counters, logs and hooks are stored and incremented in shipping code only so tests in this slice can count passes, compares, walks and saves. `unsavedMarkChecks` says so itself ("a counter for the tests; never observed"). `testOnlyStarredSaveCount` and `onBoardsWalk` are documented in `Tests/VaultBatchMoveTests.swift:31-39` as contracts the production code "must keep incrementing" or the tests "cannot ever go green". The cost is small, but several live on keystroke paths (restyle, model sync, find), and a refactor that drops one turns a perf regression test into a false red, or into a silent pass if the test reads a default. Real state that tests also read (`renditionCache`, `lastRenditions`, `hiddenMarkers`, the injected `modifierFlags` clock) is not counted here. ADR-0053 accepts seams for the hosted-view conversion, so this finding asks for an inventory, not removal.
- Trigger: n/a
- Fix: gate the pure counters behind `#if DEBUG`, or group them in one injected `TestProbe`, and list them in ADR-0053's seam table so a refactor knows which ones are load-bearing.
- Tracked: none

### T07-tests-17 — Controllers closed at the end of the body, not in a `defer`
- Where: `Tests/VaultControllerReconcileTests.swift:57` (and every test in the file), `Tests/VaultControllerMoveNoteTests.swift:53` (and :75, :104, :125), `Tests/VaultMoveTests.swift:200` (and :247, :281, :303, :338, :360, :380), `Tests/VaultBreadcrumbTests.swift:39` (and :52, :68)
- Category: hygiene
- Severity: P3 · Confidence: suspected
- In flight: no
- What: these tests call `controller.close()` as their last line. A failing `try #require` or a `waitUntil` timeout throws first, so the controller stays open with its FSEvents watcher running, in the same process as every other suite. Sibling files (`VaultControllerExternalDeletionTests`, `VaultControllerLandedChangeTests`, `VaultControllerWriteCatchUpTests`) use `defer { controller.close() }`. A leaked watcher only matters after a first failure, which is when a clean second signal matters most.
- Trigger: any thrown failure in these tests.
- Fix: `defer { controller.close() }` right after `open`.
- Tracked: none

### T08-tests-01 — `makeTempRoot()` never removes the directories it creates
- Where: `Tests/WorkspaceOpenStateTests.swift:28`
- Category: hygiene
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `makeTempRoot()` creates `$TMPDIR/pergamenum-workspace-open-state-<UUID>` and returns a bare `URL`. Nothing removes it. Twelve tests use it (lines 46, 64, 81, 136, 152, 169, 189, 209, 228, 245, 261, 276), so every run leaves twelve directories, some holding `.canvas` files. None of these tests calls `detach()` either. The helper and `makeDirectory(_:in:)` at :35 also re-implement `CanvasTemporaryRoot` (`Tests/CanvasTestSupport.swift:11`), which deletes its directory in `deinit`.
- Trigger: every unit-suite run.
- Fix: replace both helpers with `CanvasTemporaryRoot` and its `makeDirectory`, and call `controller.detach()` at the end of each test.
- Tracked: none

### T08-tests-02 — the journal helper leaves its temp directory behind
- Where: `Tests/WriteJournalGestureTests.swift:11`
- Category: hygiene
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `journal()` creates `NSTemporaryDirectory()/JournalTest-<UUID>`. Every caller (lines 33, 61, 77, 93, 109) discards the returned URL with `_`, and nothing deletes the directory, so each run leaves five directories with `journal.jsonl` in them.
- Trigger: every unit-suite run.
- Fix: keep the URL and `defer { try? FileManager.default.removeItem(at: root) }`, or build the journal on a `TemporaryVault`/`CanvasTemporaryRoot`, which clean up after themselves.
- Tracked: none

### T08-tests-03 — a regression in the escape tests writes outside the temp root, under a fixed name that is never cleaned up
- Where: `Tests/WorkspaceLifecycleTests.swift:350`
- Category: hygiene
- Severity: P3 · Confidence: suspected
- In flight: no
- What: `commitDrawingRefuses…` (:336) and `commitImportRefuses…` (:357) pass `../../escaped.svg` and `../../escaped.txt`. They check for the file two levels above `CanvasTemporaryRoot`, which is the parent of `$TMPDIR` (`/var/folders/xx/yyy/`). If the boundary check regresses, production writes a file there that is outside any directory the test owns, and the test does not remove it. Because the name is fixed, that stray file then makes the test fail on every later run, even after the regression is fixed.
- Trigger: any regression of the `VaultBoundary` check in `commitDrawing` or `commitImport`.
- Fix: nest the vault two levels inside a per-test sandbox directory, so that `../../` still lands inside a directory the test owns, and remove the sandbox in a `defer`. Alternatively use a UUID-suffixed escape name and delete it in a `defer`.
- Tracked: none

### T08-tests-04 — a fixed 400 ms sleep checks for the absence of a refit with a debounce of about 350 ms
- Where: `Tests/WorkspaceLifecycleTests.swift:397`
- Category: flaky
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `detachCancelsAPendingRefit…` sleeps a fixed 400 ms and then asserts that pan and zoom did not change. The debounce it races is about 350 ms, a 50 ms margin. Under load the refit can fire after the sleep returns, so the test passes without proving anything. This is a false green, not a red.
- Trigger: a loaded CI or Stop-hook run.
- Fix: assert on the controller's state instead (`refitTask == nil` / `pendingRefit == nil` after `detach()`, as :683 and :687 already do), or inject the debounce clock.
- Tracked: none

### T08-tests-05 — FSEvents delivery is awaited with a fixed sleep before a positive assertion
- Where: `Tests/VaultWatcherTests.swift:146`
- Category: flaky
- Severity: P3 · Confidence: suspected
- In flight: no
- What: `reportsMarkdownOnly` writes four files, sleeps a fixed 900 ms and then asserts on the set of paths that were delivered. FSEvents latency under a loaded run can go past 900 ms, and the test then fails red with no defect behind it.
- Trigger: a loaded full-suite run.
- Fix: poll with the shared `waitUntil` (`Tests/DiaryControllerTests.swift:8`) until both notes are reported or a generous deadline passes, then assert.
- Tracked: none

### T08-tests-06 — `silentAfterStop` can pass vacuously
- Where: `Tests/VaultWatcherTests.swift:78`
- Category: flaky
- Severity: P3 · Confidence: suspected
- In flight: no
- What: the test sleeps a fixed 700 ms at :78 and again at :85. Its own comment says the first sleep is there so the watcher has delivered "at least one batch", but nothing asserts that a batch arrived before `stop()`. If the stream never came up, `afterSeal == 0` holds trivially.
- Trigger: a slow FSEvents start-up.
- Fix: `#expect(!deliveries.all.isEmpty)` before `stop()`, after polling for the first batch.
- Tracked: none

### T08-tests-07 — a Bool `canUndo` stands in for the history depth
- Where: `Tests/WorkspaceControllerToolsTests.swift:193`
- Category: disabled
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `let undoDepthBefore = controller.canUndo` is compared after a cancelled crop (:200). The same pattern appears at :286-288 after a no-op `removeCrop`. `placeFile` and the confirmed crop have already made `canUndo` true, so a stray extra history step would leave it true and the assertion still passes. The test does not check what its name and comments promise ("must not touch history").
- Trigger: a regression that records an extra undo step on cancel or on a no-op removal.
- Fix: compare an undo-stack count (a test-visible depth), or undo once and check that the state returned is the one from before the crop.
- Tracked: none

### T08-tests-08 — the round-trip test sets the default value
- Where: `Tests/VaultTests.swift:666`
- Category: disabled
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `revealsInlineSpansSurvivesAnEncodeDecodeRoundTrip` sets `revealsInlineSpans = true`, which is already the value in `VaultSettings.default`. A field dropped from encoding would decode to the default and the test would stay green.
- Trigger: removing `revealsInlineSpans` from `CodingKeys` or `encode(to:)`.
- Fix: round-trip `false`, the non-default value.
- Tracked: none

### T08-tests-09 — a tautological assertion
- Where: `Tests/VaultUnguardedWriteGuardTests.swift:77`
- Category: disabled
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `daily.contains("Sopralluogo".lowercased()) || daily.contains("sopralluogo")` checks the same string twice. If the case the link should carry matters, nothing asserts it. Line 76 force-unwraps `created.dailyNote!` right after an `#expect` that it is non-nil, so a regression crashes the run instead of failing the test.
- Trigger: a regression in the daily-note link text, or a nil `dailyNote`.
- Fix: assert the exact link line (for example `[[Sopralluogo]]`) and use `try #require(created.dailyNote)`.
- Tracked: none

### T08-tests-10 — the `sourcePath` assertion accepts both outcomes
- Where: `Tests/WikilinkClickVariantTests.swift:40`
- Category: disabled
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `sourcePath == nil || sourcePath == "Nota.md"` passes whether or not the click carries its source note, so the field is untested.
- Trigger: a regression that drops or changes `sourcePath`.
- Fix: decide which value the fixture should produce and assert only that one.
- Tracked: none

### T08-tests-11 — the "re-pick" test assigns the value already there
- Where: `Tests/ViewQueryTextTests.swift:379`
- Category: disabled
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `repickingFolderPreservesMatchCountKey` sets `scope[0] = "Clienti"` on a draft whose scope is already `["Clienti"]` and compares it with an identical draft. Unless `body(of:)` is non-deterministic, this cannot fail, and it never exercises the folder picker's path.
- Trigger: none; the test cannot fail.
- Fix: drive the real re-pick entry point (the picker's setter on the draft) or delete the test as redundant.
- Tracked: none

### T08-tests-12 — test methods call other suites' test methods
- Where: `Tests/ViewQueryOutOfScopeTests.swift:148`
- Category: clarity
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `oneAtomicRewrite`, `oneUndoStep` and `refusedCommitLeavesTheBufferUntouched` (:148-161) instantiate `ViewQueryCommitTests()` and call its `@Test` methods. Each body runs twice per suite run, and the copies run outside `ViewQueryCommitTests`' own `.serialized` trait, concurrently with that suite. They share AppKit editor state on the main actor.
- Trigger: every run; a parallel interaction is possible.
- Fix: delete the three forwarders. Their own comment says they exist for "named coverage", and an R-13 tag on the original tests gives the same traceability.
- Tracked: none

### T08-tests-13 — test headers still describe production as a RED stub or placeholder
- Where: `Tests/WorkspaceTreeTests.swift:16`
- Category: clarity
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: header comments say the code under test is a "placeholder", "stub" or "RED" and that the assertions fail. The production code is implemented and the tests pass. For example, `WorkspaceFolderNavigation.folderAfterRename` is real at `WorkspaceFolderActions.swift:92`, and `openAction` is real at `ViewRowRenderers.swift:80`. Locations:
  - `WorkspaceTreeTests.swift:16-33,208-213`
  - `WorkspaceFolderNavigationTests.swift:18-21,135-137`
  - `WorkspaceMultiSelectionTests.swift:13-34`
  - `WorkspaceOpenStateTests.swift:21-26`
  - `WorkspaceReferenceTests.swift:11-14`
  - `WorkspaceBrowserToolbarTests.swift:23-38,70`
  - `WorkspaceCreationTests.swift:14-31,99-104`
  - `WorkspaceControllerTests.swift:397-401`
  - `VaultPlanApplicationTests.swift:7-12`
  - `VaultSessionFolderOperationsTests.swift:19-22`
  - `VaultWriteAbsentPreconditionTests.swift:21-22,49,62,91-92,108`
  - `ViewBlockCaretTests.swift:16-29,218-224,259-260,267,289-294,342-347,383-386`
  - `ViewBlockHostStoreTests.swift:14-22,42,76,104,124`
  - `ViewBlockQuerySourceTests.swift:10-22,81-82,253-256`
  - `ViewBlockRenderingTests.swift:14-22,128-129,144-146,176-199,221-224,314-315,344-347`
  - `ViewBlockSpanTests.swift:13-18` (cites `MarkdownStyler.viewBlockRuns(in:outside:)` as a stub; it is now `private static func viewBlockRuns(outside:)`, `MarkdownStyler.swift:498`)
  - `ViewQueryCommitTests.swift:6-7`
  - `ViewQueryEntryPointTests.swift:6-7,240-241`
  - `ViewQuerySeedTests.swift:177-178`
  - `ViewQueryTextTests.swift:225-228,408-411`
- Trigger: a reader trusts the header and treats the tests as red or the code as unfinished.
- Fix: delete the RED/placeholder paragraphs, keeping the ADR, plan and R-nn references, the same treatment PG-200 gave three other files.
- Tracked: none (the same class as PG-200, closed; the files PG-200 named are clean)

### T08-tests-14 — a comment says a test is "trivially true" when it no longer is
- Where: `Tests/ViewBlockRenderingTests.swift:370`
- Category: clarity
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: lines 370-378 say `withHidesMarkupFalseThePassClearsLinesAPreviousPassHid` passes trivially because `apply(viewBlockLines:)` stores nothing. It now stores (`EditorDecorationDelegate.swift:336-340`), so the test is a real guard, and the comment invites someone to delete it.
- Trigger: reading the comment during a cleanup.
- Fix: rewrite the comment to state what the test now pins.
- Tracked: none

### T08-tests-15 — a comment contradicts the code below it
- Where: `Tests/VaultSessionJournalTests.swift:34`
- Category: clarity
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: the comment at :34-39 says the closure of `transaction` is a synchronous `() throws -> T`, so `await` cannot appear in it and the two writes resolve to the synchronous `write(_:to:)`. Lines 40-43 call `await session.transaction` and `try? await session.write(...)` inside the closure, so the comment is out of date. The `try?` also swallows any write failure, so the journal assertions that follow can fail without saying why.
- Trigger: reading or maintaining the test.
- Fix: delete the stale paragraph and use `try` instead of `try?`, so a failed write fails the test with its own error.
- Tracked: none

### T08-tests-16 — a structural test regex-matches production source text
- Where: `Tests/ViewQueryEntryPointTests.swift:221`
- Category: clarity
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: lines 221-236 read `Sources/Features/Views/RenderedViewBlock.swift` through `#filePath` and regex-match its code. A rename or reformat turns it red with no behaviour change, and a behaviour change written differently keeps it green.
- Trigger: any refactor of `RenderedViewBlock.swift`.
- Fix: assert through the view's seam (the entry-point action), as the rest of the file does.
- Tracked: none

### T08-tests-17 — the frontmatter `note(_:)` builder is copied into ten files
- Where: `Tests/VaultWriteOrderingTests.swift:17`
- Category: duplicate-support
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: there are private copies of the same frontmatter-note builder at:
  - `VaultRescanOrderingTests:12`
  - `VaultSessionFileOperationsTests:12`
  - `VaultSessionFolderOperationsTests:24`
  - `VaultSessionJournalTests:11`
  - `VaultTransactionGestureTests:12`
  - `VaultUnguardedWriteGuardTests:31`
  - `VaultWriteAbsentPreconditionTests:10`
  - `VaultWriteOrderingBatch3Tests:14`
  - `VaultWriteOrderingTests:17`
  - `WhereNoteAppearsScanTests:13`

  `WorkspaceIntegrationWalkTests:53` (`Walk.note(titled:)`) is a near copy. ADR-0051 §D2 asks for one shared helper.
- Trigger: a frontmatter-schema change has to be made in ten places.
- Fix: one `TestNote.frontmatter(...)` in the shared vault test support.
- Tracked: none

### T08-tests-18 — the session opener and `armedSession` are copied file by file
- Where: `Tests/VaultSessionTests.swift:13`
- Category: duplicate-support
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: there are separate copies of "build a `VaultSession` over a `TemporaryVault` with the bundled vocabulary and rescan" at:
  - `VaultSessionTests:13`
  - `VaultUnguardedWriteGuardTests:36`, re-spelled inline at :122-126
  - `VaultWriteOrderingTests:22`
  - `VaultWriteAbsentPreconditionTests:15`
  - `ViewConnectorTests:29`
  - `ViewsScanTests:46`
  - `WorkspaceIntegrationWalkTests:59`

  `armedSession` is copied in four files, and `armedAbsentPreconditionSession` is a fifth variant.
- Trigger: a change to `VaultSession.init` or `VaultAPI.arm` touches every copy.
- Fix: one `TemporaryVault.openSession(armed:)` in shared support.
- Tracked: none

### T08-tests-19 — the editor fixture and its layout helpers are re-copied despite shared fixtures
- Where: `Tests/ViewBlockQuerySourceTests.swift:84`
- Category: duplicate-support
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: the wiring of `NoteTextView` + `CompletingTextView` + Coordinator is duplicated in:
  - `ViewBlockCaretTests:51`
  - `ViewBlockQuerySourceTests:84` (whose comment says "copied rather than imported")
  - `ViewQueryCommitTests:39`
  - `ViewQueryEntryPointTests:67`
  - `ViewQueryOutOfScopeTests:18`
  - `ViewBlockRenderingTests:350,385`

  `laidOutOffsets` and `substitutedParagraph` are copied from `TableRenderingTests` into `ViewBlockRenderingTests:25,37` and `ViewBlockCaretTests:136`. `ScrolledEditorFixture` and `EmbedEditorFixtures` already exist.
- Trigger: a Coordinator wiring change silently diverges between copies.
- Fix: extend the existing shared fixture and delete the copies.
- Tracked: none

### T08-tests-20 — three copies of the Mirror-reflection view finder
- Where: `Tests/ViewQueryEntryPointTests.swift:11`
- Category: duplicate-support
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `entryPointFind` (`ViewQueryEntryPointTests:11-23`), `outOfScopeFind` (`ViewQueryOutOfScopeTests:8-11`) and the finder in `ViewBlockOutOfScopeTests:31-40` walk `Mirror(reflecting:)` the same way.
- Trigger: maintenance drift.
- Fix: one shared `MirrorFinder` in test support.
- Tracked: none

### T08-tests-21 — six private `ViewCorpus` test doubles and `NoteRecord` builders
- Where: `Tests/ViewEvaluatorTests.swift:7`
- Category: duplicate-support
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: there are six private `ViewCorpus` doubles or `NoteRecord` builders:
  - `Corpus`/`record` (`ViewEvaluatorTests:7,15`)
  - `GraphCorpus`/`graphRecord` (`GraphPinTests:13,24`)
  - `CountingCorpus`/`countedRecord` (`WorkCountTests:27,43`)
  - `MatchCountCorpus` (`ViewQueryTextTests:348`)
  - `record` (`ViewBlockQuerySourceTests:47`)
  - `makeRecord` (`VaultTests:172`)

  Each one has to change when `NoteRecord` or `ViewCorpus` changes.
- Trigger: a field added to `NoteRecord`.
- Fix: one `StubCorpus` + `NoteRecord.fixture(...)` in shared support. Only the counting variant needs its own wrapper.
- Tracked: none

### T08-tests-22 — `rescanGate` exists only for a test
- Where: `Sources/Vault/VaultSession.swift:392`
- Category: test-only-seam
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `rescanGate` is awaited inside `rescan()` (:412) on every production rescan. Its only setter is `Tests/VaultRescanOrderingTests.swift:22`; the app never sets it.
- Trigger: n/a (design).
- Fix: document it as an ADR-0053-style seam with its scope, or move it behind an injected scan hook that the app passes as a no-op.
- Tracked: none

### T08-tests-23 — `apply(_:at:)` is kept alive only by tests
- Where: `Sources/Vault/VaultSession+WriteOrdering.swift:22`
- Category: test-only-seam
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: the overload's only callers are `Tests/VaultWriteOrderingTests.swift:69,73`. Production uses the other entry points.
- Trigger: n/a.
- Fix: route those tests through a production entry point and delete the overload, or mark it as a declared seam.
- Tracked: none

### T08-tests-24 — branches the tests say they leave uncovered
- Where: `Tests/WorkspaceAutosaveRaceTests.swift:169`
- Category: clarity
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `WorkspaceAutosaveRaceTests:169-177` says the "retry at most once" branch of `WorkspaceController+Saving.swift` is not exercised. `VaultUnguardedWriteGuardTests:24-27,175-180` names guard branches it does not reach either. These are known gaps recorded only in comments.
- Trigger: a regression in those branches goes unseen.
- Fix: add the two cases (a second conflicting write during the retry; the named guard branches), or record them in the ledger.
- Tracked: none

### X01-01 — `--affected` maps Tasks/Diary/Workspace changes away from the GUI classes that drive them
- Where: `scripts/uitests.sh:170`, `scripts/uitests.sh:175`, `scripts/uitests.sh:177`
- Category: correctness
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `classes_for_path` sends `Sources/Features/Tasks/*` only to `TaskCategoriesUITests`, but `ComposerUITests` drives `tasks-capture` (`TasksView.swift:90`) and `task-composer-*` (`TaskComposer+Footer.swift:99`, `TaskDatePanels.swift:158`). `Sources/Features/Diary/*` goes to Day/Diary/EditorHandCheck, but `QuitReviewUITests` asserts `diary-conflict-banner` (`DiaryView+Conflict.swift:24`). `Sources/Features/Workspace/*` goes to the four Workspace/SidebarMove classes, but `QuitReviewUITests` clicks `board-conflict-keep-local` (`BoardChrome.swift:60`). The script's own comment at :160 names the result: "a green run that says nothing about it".
- Trigger: a PR that only edits `TaskComposer+Footer.swift`, `DiaryView+Conflict.swift` or `BoardChrome.swift` → `--affected` skips `ComposerUITests` / `QuitReviewUITests`, and the merge-time run is green without them.
- Fix: add `ComposerUITests` to the Tasks branch and `QuitReviewUITests` to the Diary and Workspace branches. Better, add a `--self-test` check that resolves each class's identifiers back to their source files and fails when the map does not select that class for those files.
- Tracked: none

### X01-02 — Light `text.tertiary` family is under 3:1 on every ground; dark is under 3:1 on the pratica entry surfaces
- Where: `Resources/Themes/pergamenum-light.json:36`, `Resources/Themes/pergamenum-light.json:51`, `Resources/Themes/pergamenum-light.json:54`, `Resources/Themes/pergamenum-light.json:64`, `Resources/Themes/pergamenum-dark.json:36`, `Resources/Themes/pergamenum-dark.json:51`, `Resources/Themes/pergamenum-dark.json:54`, `Resources/Themes/pergamenum-dark.json:64`
- Category: house-rules
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `text.tertiary`, `task.done`, `task.cancelled` and `code.comment` share one hex per theme (`#9C968B` light, `#77726A` dark), so changing one value fixes four tokens. Light: 2.43–2.94:1 on all 12 grounds, including 2.94 on `background.primary`. That fails even the 3:1 large-text/UI threshold. Dark: 2.38–2.83 on `surface.entryNote/entry/entryCall/sent`, and 3.00 on `background.tertiary`/`surface.raised`. Also under 4.5 in light: `code.string`, `calendar.holiday` and `callout.tip` on the sunken/received/sent/inline-code grounds (4.14–4.48), and `calendar.prefestive` `#C98B84` (2.31–2.80) everywhere. The full matrix is in the Surface inventory, second table.
- Trigger: tertiary text (captions, done tasks, code comments) on the parchment ground in light → 2.47–2.94:1.
- Fix: darken light `#9C968B` to at least 4.5:1 on `background.primary` and 3:1 on every ground. Measured: `#756F65` gives 4.98 on white and 4.19 on `background.tertiary`; `#6F6A61` gives 5.37 and 4.52. Lighten dark `#77726A` until it clears 3:1 on `surface.entryNote` `#453911`. `category.*`, `rail.*` and `calendar.prefestive` may be non-text marks (dots, rails, day tints) where 3:1 or no threshold applies, so the GUI step decides those. Raise this to P2 if the GUI step finds tertiary carrying running text.
- Tracked: none

### X01-03 — `mcp-smoke.py` with no argument runs the newest server of any worktree
- Where: `scripts/mcp-smoke.py:125`
- Category: correctness
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `find_binary` sorts every `DerivedData/Pergamenum-*/…/Debug/pergamenum-mcp` by mtime and takes the last one. With parallel worktrees, that is another branch's server, and the smoke check passes or fails on code it was not asked about. CLAUDE.md requires picking the folder by `WorkspacePath` for exactly this reason. The user's memory notes record that it "silently ran another worktree's server", but the ledger has no entry.
- Trigger: worktree B builds after worktree A, then `scripts/mcp-smoke.py` runs from A → it checks B's binary.
- Fix: resolve the DerivedData folder whose `info.plist` `WorkspacePath` is `$(git rev-parse --show-toplevel)/Pergamenum.xcworkspace` (the CLAUDE.md recipe), or refuse when there is no argument and more than one candidate, as `install-cli.sh:72-76` already does.
- Tracked: none

### X01-04 — Every merge-integrity run walks the whole working tree, gitignored `build/` included
- Where: `scripts/check-merge-integrity.py:195`
- Category: performance
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `config_warnings` runs `os.walk(repo)` looking for `.gitattributes` with `merge=`. It prunes only `.git`, so it also walks `build/`, which holds 35,022 files on this checkout (`pg401-gates-dd`, `restyle-bench-dd`, `release*`). It runs inside the pre-push hook every time. The mechanism is confirmed; the delay was not measured.
- Trigger: a push from a checkout that has run the bench or release scripts → a tens-of-thousands-file walk inside the hook.
- Fix: list only tracked attribute files (`git ls-files -z '*.gitattributes'`), or query `git check-attr` on the changed paths.
- Tracked: none

### X01-05 — The merge-integrity self-test inherits `GIT_*` from its caller; its sibling strips them
- Where: `scripts/check-merge-integrity.py:650`, `scripts/check-merge-integrity.py:1193`
- Category: correctness
- Severity: P3 · Confidence: suspected
- In flight: no
- What: `_sh` passes `{**os.environ, GIT_AUTHOR_*…}` and `_run_cli` passes no env at all, so `GIT_DIR`, `GIT_CONFIG_COUNT/KEY_n`, `GIT_INDEX_FILE` and global config leak into the throwaway repos. `check-adr-references.py:604-614` (`_hermetic_env`) documents why that matters: the harness injects core.hooksPath through `GIT_CONFIG_COUNT`, and `GIT_DIR` would point a `git -C <tmp>` call at the real repository. This session's environment shows only `GIT_EDITOR`, so the trigger was not reproduced.
- Trigger: `--self-test` run from a hook or harness that exports `GIT_DIR`/`GIT_INDEX_FILE` → self-test commands can target the real repository, or fail spuriously.
- Fix: reuse the `_hermetic_env(ceiling)` shape from `check-adr-references.py` in both `_sh` and `_run_cli`.
- Tracked: none

### X01-06 — `.claude/protected-interfaces` claims an enforcer that no longer exists
- Where: `.claude/protected-interfaces:1`
- Category: docs
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: the header says "interface-check.sh blocks a diff that removes or changes" an entry. No `interface-check.sh` exists in the repo, `~/.claude/hooks` or `~/.claude/skills`, and no hook, skill or settings file reads `protected-interfaces`. The 14 entries are a list nothing checks, although ADR-0027/0030/0031/0032/0033/0034/0041, `PROJECT_BRIEF.md:315` and `Sources/Core/Vault/NoteIDRegistry.swift:14` still cite the blocking. All 14 named files and symbols still exist (verified one by one).
- Trigger: n/a
- Fix: either restore a check (for example a unit-suite test that pins each listed signature, which runs in the merge gate) or reword the header and `PROJECT_BRIEF.md` to say the list is advisory.
- Tracked: none

### X01-07 — Retired-chain artifacts under `.claude/` with no consumer
- Where: `.claude/step5-report.json:1`, `.claude/refactor-snapshot-override:1`
- Category: dead-code
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: these belong to the concept-to-code chain retired on 2026-09-14. `step5-report.json` and `refactor-snapshot-override` are tracked in git. Nothing in the repo, hooks, skills or settings reads them: `step5-report` is cited only in `TODO.md:410` history, and the 13 local `.claude/.triage-fix-last-*.json` files from the same chain are gitignored (`.gitignore:85`) local leftovers. `refactor-snapshot-override` carries `EXPIRES: 2027-08-30`, which reads as a live waiver.
- Trigger: n/a
- Fix: remove the two tracked files (behind the human gate), delete the local triage JSONs, then drop `.gitignore:85-86`.
- Tracked: none

### X01-08 — Italian comments and docstrings in tooling code
- Where: `scripts/check-merge-integrity.py:2`, `scripts/appcast.py:2`, `.github/workflows/merge-integrity.yml:3`, `scripts/release.sh:97`, `scripts/install-cli.sh:62`
- Category: house-rules
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: CLAUDE.md requires code and comments in English. The module docstrings of `check-merge-integrity.py` (also its self-test docstrings, e.g. :1200) and `appcast.py`, the header block of `merge-integrity.yml`, and the comment blocks at `release.sh:97-99,108` and `install-cli.sh:62-66` are in Italian. Italian printed messages (`fail "…"`) are user-facing and not part of this finding. `check-adr-references.py`, `adr-index.py`, `mcp-smoke.py` comments, `ci.yml` and `adr-references.yml` are already English.
- Trigger: n/a
- Fix: translate the comments and docstrings; leave the output strings.
- Tracked: none

### X01-09 — Design gallery and mockups compile into Release and ship in Settings
- Where: `Project.swift:266`, `Sources/Features/Settings/DesignSystemSettings.swift:101`, `Sources/Features/Settings/DesignSystemSettings.swift:115`
- Category: dead-code
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: the app target globs `Sources/**`, and `Sources/Features/DesignGallery/` (38 files, 8,534 lines) has no `#if DEBUG`. `DesignGalleryView()` and `MockupGalleryView()` are reachable from Settings in the shipped build, so dev-only mockups ship to the user. S13 reads the views; this finding covers the target configuration.
- Trigger: Release build → Settings → design system section → the gallery and mockups open.
- Fix: keep the gallery out of Release, with `#if DEBUG` around the two entry points and the folder, or a Debug-only source set in `Project.swift`.
- Tracked: none

### X01-10 — Duplicated polling helpers across UITests
- Where: `UITests/PraticheUITests+Support.swift:222`, `UITests/SidebarDeleteUITests.swift:55`, `UITests/SidebarMoveUITests.swift:203`, `UITests/DiaryUITests.swift:72`, `UITests/EditorHandCheckUITests.swift:110`, `UITests/NoteBirthUITests.swift:173`, `UITests/QuitReviewUITests.swift:201`, `UITests/SidebarMoveUITests.swift:170`
- Category: simplification
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: there are three identical `waitForFile(_:toExist:timeout:)` copies, and four `waitFor`/`waitUntil(timeout:_:)` loops that differ only in the default timeout and sleep (0.1–0.2 s). `workspaceRow` re-implements the base class's `element(_:)` (`PergamenumUITestCase.swift:102`). The three `waitForFile` bodies are identical (verified by diff). These copies are not among those ADR-0051 chose to keep. The base class already hosts the shared launch and lookup helpers, and these belong beside them.
- Trigger: n/a
- Fix: move `waitForFile` and one `poll(timeout:interval:_:)` into `PergamenumUITestCase`, and replace `workspaceRow` with `element`.
- Tracked: none

### X01-11 — Stale census string and stale cross-references in test tooling
- Where: `scripts/uitests.sh:395`, `UITests/WorkspaceIntegrationUITests.swift:85`, `UITests/WikilinkNavigationUITests.swift:12`, `UITests/PergamenumUITestCase.swift:8`
- Category: docs
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `--status` prints "censimento 2026-09-21: 17" next to a live count of 36 (CLAUDE.md: 36 on 2026-10-15). `WorkspaceIntegrationUITests:85` cites `NoteTreeAndShortcutsUITests.testTheSettingsPaneListsEveryCommandAndCanPutOneBack`, which was retired (`NoteTreeAndShortcutsUITests.swift:7-10`). `WikilinkNavigationUITests:12` cites `NoteTextView+Coordinator.swift:411`, which is now `applyStyling`'s doc comment. The base class says "twenty-one copies" while `.claude/rules/ui-tests.md:52` says "Seventeen". Separately, the class `NoteTreeAndShortcutsUITests` no longer tests a tree.
- Trigger: n/a
- Fix: drop the census figure or read it from one place. Cite symbols, not line numbers. Align the two counts.
- Tracked: none

### X01-12 — Fixed one-second sleep before a negative assertion
- Where: `UITests/NoteTreeAndShortcutsUITests.swift:50`
- Category: correctness
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: after Cmd+O, `Thread.sleep(forTimeInterval: 1)` is followed by `XCTAssertFalse(…exists)`. On a loaded machine the switcher could open after more than 1 s, and the test passes while the old binding still works. Every other wait in the suite polls.
- Trigger: a slow run where the menu responds late → a false green.
- Fix: `XCTAssertFalse(field.waitForExistence(timeout: 3))`.
- Tracked: none

### X01-13 — Workflow actions pinned by tag, not commit SHA
- Where: `.github/workflows/ci.yml:50`, `.github/workflows/ci.yml:64`, `.github/workflows/adr-references.yml:38`, `.github/workflows/merge-integrity.yml:59`
- Category: security
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `actions/checkout@v4` and `actions/cache@v4` follow a movable tag. Exposure is low: all three workflows set `permissions: contents: read`, use first-party actions, and take no secrets. Release signing happens locally.
- Trigger: n/a
- Fix: pin to full SHAs with a version comment, and let Dependabot bump them.
- Tracked: none

### X01-14 — Small script hygiene leftovers
- Where: `scripts/appcast.py:374`, `scripts/adr-0043-interleaving-check.sh:13`
- Category: dead-code
- Severity: P3 · Confidence: confirmed
- In flight: no
- What: `appcast.py --self-test` writes `appcast-selftest-*.xml` with `mkstemp` and never removes it, so one temp file accumulates per run. `adr-0043-interleaving-check.sh` is the acceptance harness of a shipped ADR. Only ADR-0050/0051, `PROJECT_BRIEF.md` and the 2026-09-13 plan reference it (no test, no workflow), and it runs under `set -u` only.
- Trigger: n/a
- Fix: delete the self-test file, or keep it only behind a flag. Archive or remove the ADR-0043 harness.
- Tracked: none

## P4 (122)

### S01-10 — Impostazioni ▸ Scorciatoie files eight commands under «File» that the menu bar shows under Vista or Modifica
- Where: `Sources/App/MenuCommands.swift:36-40,116-131,309-313`, `Sources/Core/Shortcuts/ShortcutCommand.swift:199-202`
- Category: correctness
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: PG-263 moved «Vai alla nota…», «Cronologia…», the star toggle, «Applica un template…», «Classifica…» and «Anteprima rapida» into Vista and «Copia link Pergamenum», «Ricerca globale…» into Modifica (the comments at `MenuCommands.swift:36` and `:309` say so), but `ShortcutCommand.section` still returns `.file` for `quickLook`, `globalSearch`, `quickSwitcher`, `copyLink`, `noteHistory`, `toggleStar`, `applyTemplate` and `classifyNote`, and `Sources/Features/Settings/ShortcutSettings.swift:21` groups the settings list by that section. The settings list and the menu bar disagree on where eight commands live, the "recognisably the same command" invariant the catalogue states for its titles.
- Trigger: Impostazioni ▸ Scorciatoie lists «Anteprima rapida» under File; the Vista menu holds it.
- Fix: move the eight cases to `.view`/`.edit` in `section`, and build the menu groups from `section` (one `ForEach` per section) so the two cannot drift again.
- Tracked: none

### S01-11 — A note is promoted to RECENTI before the read that can fail
- Where: `Sources/App/VaultController+Tabs.swift:343,353,384-385`
- Category: correctness
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `openNote(at:caret:)` and `openNoteInNewTab` call `rememberRecent(relativePath)` and only then `readForEditing`, which returns nil and records a problem when the file cannot be read. A note that vanished between the index scan and the click is still moved to the top of RECENTI, so the sidebar offers a row that opens nothing until the list evicts it.
- Trigger: delete a note in Finder, click it in the note list before the watcher's rescan → RECENTI gains the row; clicking it records the problem again.
- Fix: call `rememberRecent` after the `guard let note = readForEditing(...)` in both doors.
- Tracked: none

### S01-12 — «Svuota cache e ricostruisci» swallows the thumbnail removal while reporting the extracted-text one
- Where: `Sources/App/VaultController.swift:475-481`
- Category: correctness
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `clearCache()` writes `try? await thumbnails?.clearCacheOnDisk()` and, four lines later, catches the same kind of failure for `extractedTexts.removeAll()` and reports it through `recordProblem`. A thumbnail directory that cannot be removed leaves every PNG on disk (the PG-131 symptom) with nothing said.
- Trigger: an unwritable thumbnail directory, Impostazioni ▸ Avanzate ▸ «Svuota cache e ricostruisci» → no problem recorded.
- Fix: the `do/catch` + `recordProblem("miniature non eliminate: …")` shape the next statement already uses.
- Tracked: none

### S01-13 — Two comments still place «Copia link Pergamenum» in File and call the Finder entry «Rivela»
- Where: `Sources/App/CommandActions+Contenitore.swift:8`, `Sources/App/CommandActions+CanRun.swift:150`
- Category: docs
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: both comments say «Copia link Pergamenum» and «Rivela nel Finder» are "File's two entries". Since PG-263 the copy-link command sits in Modifica (`MenuCommands.swift:309-310`), and the File entry is titled through `ShortcutCommand.revealInFinder.title`, «Mostra nel Finder» (`VaultCommands.swift:103`, `ShortcutCommand.swift:240`).
- Trigger: n/a
- Fix: reword to the two menus and the current title.
- Tracked: none

### S01-14 — The «Cartelle recenti» comment describes an existence filter that does not exist
- Where: `Sources/App/VaultCommands.swift:55-57`, `Sources/Vault/RecentVaults.swift:62-86`
- Category: docs
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: the comment says the menu is built at menu-build time "so a vault deleted since the last launch is simply not offered", but `RecentVaults.urls` is a plain `UserDefaults` read with no `fileExists` check: a deleted vault is offered, and choosing it fails inside `switchVault`/`open(_:)`.
- Trigger: n/a
- Fix: filter with `FileManager.default.fileExists(atPath:)` when building the menu (one stat per recent, the menu is rebuilt on each open), or fix the comment.
- Tracked: none

### S01-15 — The updater self-check treats an absent `SUEnableAutomaticChecks` as satisfied, which is the one case Sparkle prompts in
- Where: `Sources/App/UpdaterConfiguration.swift:31,48`, `Project.swift:213`
- Category: correctness
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `checksAutomatically` is read as `as? Bool ?? false`, so a missing key passes the "must be false" check at 48. Sparkle's own logic (`Tuist/.build/checkouts/Sparkle/Sparkle/SPUUpdater.m:405-417`, read in this audit) prompts the person on the second launch for permission to check automatically exactly when the key is absent from Info.plist and no user default exists, the launch-time network behaviour ADR-0031 §D13 excludes. The guard exists to catch a dropped key in `Project.swift` and would miss that one case. Today the key is set to `false` (`Project.swift:213`), so nothing is wrong at runtime.
- Trigger: n/a (configuration guard only)
- Fix: read the key as `Bool?` and report an absent key as a problem, as the feed URL and public key checks do.
- Tracked: none

### S02-12 — History and the undo door test the `.md`/`.canvas` suffix case-sensitively while the scanner, the watcher and the disk actor do not
- Where: `Sources/Vault/VaultSession.swift:680`, `Sources/Vault/VaultSession+Journal.swift:390`, `Sources/Vault/VaultScanner.swift:63`, `Sources/Vault/VaultScanner.swift:176`, `Sources/Vault/VaultWatcher.swift:72`, `Sources/Vault/VaultDisk.swift:475`
- Category: correctness
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: the scanner (63, 176), the watcher (72) and `derivesNoteRecord` (`VaultDisk.swift:475`) lowercase the extension, so `Nota.MD` is a note everywhere; `write` decides `recordsHistory` with `hasSuffix(".md")` (680), so that note gets no version snapshot, and `performUndo` routes a board by `hasSuffix(".canvas")` (390), so `Board.CANVAS` would be undone through the note door the comment above it says to avoid.
- Trigger: a note or board whose extension is upper-case (a Finder rename, a Windows export) → indexed, watched and reconciled, never snapshotted; its undo takes the wrong door.
- Fix: one shared predicate (`VaultDisk.derivesNoteRecord` already is one for notes) used at 680 and 390; the same for `CanvasStore.fileExtension`.
- Tracked: none

### S02-13 — `TaskDropOutcome.result` is documented as what the caller uses to catch the editor up, and no caller reads it
- Where: `Sources/Vault/VaultSession+TaskDrop.swift:32-34`, `Sources/App/VaultController+TaskDrop.swift:31`, `Sources/App/VaultController+TaskDrop.swift:33-35`
- Category: docs
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: the doc (32-33) says the field exists "so a caller with the editor open on that note can put it back in step without reading the file a second time"; the one caller reads `didWrite` only (31) and says why — the open tabs already heard of the write from the door (ADR-0067 §D1, 33-35). Periphery flags the field as assign-only; what it cannot see is that the comment describes a mechanism ADR-0067 replaced.
- Trigger: n/a
- Fix: delete the field and its sentence, or keep it with a doc that says what it is for now.
- Tracked: none

### S03-11 — `ShortcutCommand.swift` keeps plan-era narration and the ADR-0029 residue `PG-266` listed as dropped
- Where: `Sources/Core/Shortcuts/ShortcutCommand.swift:292-295`, `Sources/Core/Shortcuts/ShortcutCommand.swift:107-108`, `Sources/Core/Shortcuts/ShortcutCommand.swift:118-120`, `Sources/Core/Shortcuts/ShortcutCommand.swift:395-396`
- Category: docs
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `defaultBinding`'s doc still says "reading mode keeps Cmd+Shift+M" (`:294`) though `readingMode` left with ADR-0029 §D13; `paneRecordings`' doc says `Navigation.Pane.recordings` is "not yet a case of that enum" (`:107-108`) while it is (`Sources/App/Navigation.swift:31`); `:118-120` and `:395-396` say Task 8 "still" measures the `panePratiche` binding, contradicted by `:398-403` ("Measured … at wiring time"). The comments are most of why the file is 425 lines (SwiftLint `file_length` 400; the type body has 233 non-comment lines).
- Trigger: n/a
- Fix: delete the three stale sentences and the ADR-0029 clause.
- Tracked: regression of PG-266 (closed 2026-10-02 naming `ShortcutCommand.swift:246-249` among the residues reworded or dropped; the sentence is still there)

### S03-12 — `uniqueFileName`'s doc comment sits above `pastedImageFileName`
- Where: `Sources/Core/Conventions/ImportNaming.swift:97-107`, `Sources/Core/Conventions/ImportNaming.swift:220-228`
- Category: docs
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: "A name that does not collide with an existing file, by appending `-2`, `-3`…" (`:97-101`) is followed by `pastedImageFileName`'s own doc and declaration (`:102-107`); `uniqueFileName` (`:228`) has its current doc at `:220-227`, so the orphan paragraph documents nothing and reads as part of the pasted-image doc.
- Trigger: n/a
- Fix: delete `:97-101`.
- Tracked: none

### S03-13 — `NoteName.category` tests the daily folder as a substring of the path
- Where: `Sources/Core/Conventions/NoteName.swift:102`, `Sources/Vault/VaultSession+Search.swift:174`
- Category: correctness
- Severity: P4 · Confidence: suspected
- In flight: no
- What: `path.contains("\(dailyFolder)/")` classifies `Archivio/Calendar/20260811.md` and `MyCalendar/20260811.md` as daily when the daily folder is `Calendar`, so a date-named note filed elsewhere gets the daily tag rules (`NoteCategory.allowsStatus`, `initialTags`).
- Trigger: daily folder `Calendar`, note `Archivio/Calendar/20260811.md` → `.daily`.
- Fix: compare the note's parent folder path to `dailyFolder` (equal, or `hasPrefix("\(dailyFolder)/")` from the start of the path).
- Tracked: none

### S03-14 — `RelatedLink` refuses a self-link by exact string, while titles resolve case-insensitively elsewhere
- Where: `Sources/Core/Conventions/RelatedLink.swift:42`
- Category: correctness
- Severity: P4 · Confidence: suspected
- In flight: no
- What: `guard target != selfTitle` is case-sensitive; `NoteRename.fold`, `LinkChoice.sharedTitles` and `BacklinkContext` compare lowercased, so a hand-typed `nota` in note `Nota` passes the guard and writes a bullet that resolves to the note itself.
- Trigger: «Collega» from `Nota` with target typed `nota` → a self-pointing structural link.
- Fix: compare through the same fold the rename uses.
- Tracked: none

### S03-15 — Linking from a note with an empty body starts the body with two blank lines
- Where: `Sources/Core/Conventions/RelatedLink.swift:88-89`
- Category: correctness
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: with no section the separator is `newline + newline` unless the body already ends in `\n`; an empty body (frontmatter only) ends in nothing, so the result is `\n\n## Note correlate…`.
- Trigger: new note, no body → «Collega» → body `"\n\n## Note correlate\n\n- [[B]] …"`.
- Fix: no separator when `body.isEmpty`.
- Tracked: none

### S03-16 — `Tag.isWellFormedValue` compares `Character`s, so a decomposed grapheme passes the `[a-z0-9]` grammar
- Where: `Sources/Core/Conventions/Tag.swift:43-50`, `Sources/Core/Conventions/Tag.swift:59-62`, `Sources/Core/Categories/CategoryRegistry.swift:48`
- Category: correctness
- Severity: P4 · Confidence: suspected
- In flight: no
- What: `isLowercaseASCIILetter`/`isASCIIDigit` are `Character` range tests (`:60-61`); a multi-scalar grapheme whose first scalar is in range (`"b\u{0301}"`, `"1\u{0301}"`) orders between `a` and `z` and is accepted, while SPEC §4.4's regex rejects the combining mark per scalar. Shared by `TagEntry.check` and `CategoryRegistry.validating`, so a slug the harness refuses can be written.
- Trigger: tag `topic-b\u{0301}` (pasted from an NFD source) → accepted by the app, refused by the harness linter.
- Fix: test `$0.asciiValue` against the ranges.
- Tracked: none

### S04-10 — `ListContinuation` traps on an ordinal near `Int.max`
- Where: `Sources/Core/Editor/ListContinuation.swift:82,85,126`, `Sources/Core/Editor/ListContinuation+Window.swift:175`
- Category: correctness
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `ordered(on:in:)` accepts any digit run `Int` parses (`:323`), and the continuation and both renumberings add to it with plain `+`, which traps on overflow.
- Trigger: a line `9223372036854775807. a`, Return at its end → `first + position + 1` (`:85`) overflows and the app crashes. Not ordinary input.
- Fix: `addingReportingOverflow`, or `ordered` refuses a run longer than 18 digits (nobody wrote that as a list marker).
- Tracked: none

### S04-11 — Search `path:` is lowercased but not diacritic-folded, unlike words, tags and the views' `path()`
- Where: `Sources/Core/Search/SearchQuery+Matching.swift:73-75`, `Sources/Core/Search/SearchQuery.swift:149,157`
- Category: correctness
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: words, phrases and tags go through `SearchQuery.fold` (`:31-33`, diacritic and case insensitive) and the views' `path()` through `Glob` (folded), but `path:` compares `lowercased()` strings on both sides (`:73`, `SearchQuery.swift:149`).
- Trigger: `path:citta` misses `Città/…`; `path:Città` misses a folder saved as `Citta`.
- Fix: fold both sides with `SearchQuery.fold`.
- Tracked: none

### S04-12 — `Matcher.excerpt` keeps the `\r` of a CRLF hit line
- Where: `Sources/Core/Search/SearchQuery+Matching.swift:110,114`
- Category: correctness
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `excerpt` splits on `"\n"` (`:110`), so a CRLF line keeps its trailing `\r`, and `trimmingCharacters(in: .whitespaces)` (`:114`) does not remove U+000D.
- Trigger: a CRLF note's hit line comes back as `…testo\r` in the search row.
- Fix: trim `.whitespacesAndNewlines`, or walk lines with `LineBreak.isTerminator` as the other readers do.
- Tracked: none (PG-316 covered the `"\n"`-`Character` walks; this split is NSString-level and never had that defect)

### S04-13 — `SearchQuery` drops an unknown `task:` value silently
- Where: `Sources/Core/Search/SearchQuery.swift:189-193`
- Category: correctness
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `task:` with a value other than `open`/`done` reaches `default: break` (`:193`): the term vanishes and the query runs as if it had not been typed, while an invalid `regex:` is surfaced.
- Trigger: `task:aperto forno` returns every note matching `forno`, with no sign the filter was ignored.
- Fix: keep the token as a word, or report it the way `regex:` reports an invalid pattern.
- Tracked: none

### S04-14 — `line(for:settingState:today:)` trims trailing whitespace, dropping a two-space hard break
- Where: `Sources/Core/Tasks/TaskParser+Writes.swift:48,50`
- Category: correctness
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: the rewritten line is `trimmingTrailingWhitespace()` on both paths (`:48`, `:50`), so a task line ending in two spaces (a markdown hard break, the next line is its continuation) loses them on a state toggle: a save that rewrites what it did not read (ADR-0065's R-items).
- Trigger: `- [ ] chiama Rossi  ` followed by an indented continuation line → toggle done, toggle open → `- [ ] chiama Rossi`, the continuation becomes a lazy paragraph.
- Fix: keep the trailing run and insert `@done(…)` before it, or trim only on the path that appends.
- Tracked: none

### S04-15 — `ItalianHolidays` force-unwraps two `CalendarDate` fallbacks
- Where: `Sources/Core/Tasks/ItalianHolidays.swift:58,103`
- Category: house-rules
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: two `CalendarDate(year:month:day:)!` fallbacks (April 1 and January 1 of `year`, always valid, so the `!` cannot fire) in production code, against the global Swift rule that forbids `!` in production.
- Trigger: n/a
- Fix: a non-failable initialiser for a date valid by construction, or a `guard` that returns an empty holiday set.
- Tracked: none

### S04-16 — Periphery confirmed: `DiarySection.prose(of:)` has no caller in Sources or Tests
- Where: `Sources/Core/Diary/DiaryEntry.swift:240`
- Category: dead-code
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: no reference outside its declaration in `Sources` or `Tests`. The symbol is on chain 13's list (ROADMAP `:928`, PG-266's original text); PG-266 closed with fourteen deletions and four named test-only keeps, and this symbol is in neither.
- Trigger: n/a
- Fix: delete it (`VaultSession+Diary.swift:47` reads `split(…).prose` directly).
- Tracked: regression of PG-266

### S04-17 — Periphery confirmed: `DateEntry.parse(_:today:calendar:)` never reads `calendar`
- Where: `Sources/Core/Tasks/DateEntry.swift:54`
- Category: dead-code
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: the body builds its dates through `CalendarDate(year:month:day:)` and the named-day cases and never touches the parameter. Listed among chain 13's "14 unused parameters" (ROADMAP `:936`), PG-266 closed.
- Trigger: n/a
- Fix: drop the parameter and its default.
- Tracked: regression of PG-266

### S04-18 — Periphery confirmed: `ViewEvaluator.Context.today` is stored and never read, and `labels(for:)` carries a fallback that never runs
- Where: `Sources/Core/Query/ViewEvaluator.swift:150,194,238`
- Category: dead-code
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `prepare` is called with the init parameter (`:238`) and the stored `today` (`:194`) is never read afterwards; the ADR-0014 §D3 comment on it describes the parameter's role, which `prepare` already fulfils. Same file, not visible to Periphery: `labels(for:)` falls back to `tagPattern ?? Glob.Pattern(glob)` (`:150`), but `tagPattern` is built for every `.tag` grouping (`:122`), so the right-hand side never runs.
- Trigger: n/a
- Fix: drop the stored property (move its comment to the parameter) and the `??` fallback.
- Tracked: none

### S04-19 — Periphery confirmed: `Callout.fold` on the block value is written in `MarkdownBlocks` and never read
- Where: `Sources/Core/Markdown/Callout.swift:67`, `Sources/Core/Markdown/MarkdownBlocks.swift:250`
- Category: dead-code
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: the block's `fold` is set at `MarkdownBlocks.swift:250` and read nowhere: every `.fold` reader under `Sources/Features` reads `Callout.Header.fold` from the token layer, and `MarkdownHTML.html(for:)` draws a callout open whatever the field says.
- Trigger: n/a
- Fix: drop the field from the block, or make the exporter honour it (`<details>`), which is a decision for ADR-0087's reading surfaces.
- Tracked: none

### S04-20 — `UnlinkedMentions.mentions(_:in:)` and `containsWholeWord` are kept alive only by tests
- Where: `Sources/Core/Search/UnlinkedMentions.swift:156-159,173`
- Category: dead-code
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: documented in place as having "no production caller" (`:156`) since `firstMention` took over (ADR-0084 §D3), kept for the tests. Periphery misses it because the test target references it.
- Trigger: n/a
- Fix: move the oracle into the test file that uses it.
- Tracked: none

### S04-21 — `GFMTable.runs(in:from:outside:)` has no production caller
- Where: `Sources/Core/Markdown/GFMTable.swift:37`
- Category: dead-code
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `MarkdownStyler.tableSpans` reads tables through `MarkdownTokens.tableLines` (`MarkdownTokens.swift:196-206`, written to avoid `runs`'s whole-text `[String]` materialisation), `MarkdownStyler.swift:464` cites it only in a comment, and the callers are `Tests/GFMTableTests.swift:17,75` and `Tests/CRLFLineWalkTests.swift:150-151`. Periphery misses it because the test target references it.
- Trigger: n/a
- Fix: delete it and point the two tests at `MarkdownBlockParser.lineTokens`, or move it next to them as an oracle.
- Tracked: none

### S04-22 — `MarkdownBlocks.table` says "never a lost line" and returns an empty table
- Where: `Sources/Core/Markdown/MarkdownBlocks.swift:159-163`
- Category: docs
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: the comment says the parse "cannot fail; an empty table is the answer if it ever did, never a lost line", and the guard returns `Table(header: [], alignments: [], rows: [])`, which loses every line of the run. The branch is unreachable by construction (the token layer applies `parsed`'s own test first, `MarkdownTokens.swift:196-206`), so only the sentence is wrong.
- Trigger: n/a
- Fix: say "unreachable", or return a paragraph with the raw lines, which is what the sentence promises.
- Tracked: none

### S05-13 — `MailStoreCopy.publish` blocks a cooperative-pool thread for two seconds
- Where: `Sources/Core/Email/MailStoreCopy.swift:105`
- Category: performance
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: the doc (58-60) makes the synchronous `Thread.sleep(forTimeInterval: retryDelay)` deliberate, but the caller `MailStorePreparation.reader` runs inside `Task.detached`, which still occupies a cooperative-pool thread and cannot be cancelled during the sleep (the «Annulla» concern from ROADMAP chain 4 item 9, corrected by ADR-0068 §D14).
- Trigger: a torn copy → 2 s of an unavailable pool thread, «Annulla» waits it out.
- Fix: make the retry `async` with `Task.sleep`, or run publish on a dedicated thread.
- Tracked: none

### S05-14 — MIME depth cap drops content silently
- Where: `Sources/Core/Email/MIMEDecoder.swift:32`
- Category: correctness
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: beyond `maximumDepth = 12` the subtree returns `[]` with no marker, so a deeply nested (forwarded-of-forwarded) message loses its body or attachments with nothing in the note or the problem list, contrary to ADR-0065's refuse-don't-drop direction.
- Trigger: a message with 13 nested `multipart/mixed` levels → note written with an empty body.
- Fix: surface a truncation flag the engine turns into a problem sentence.
- Tracked: none

### S05-15 — Unreadable `.emlx` is reported as `fileNotFound` and the message is skipped silently
- Where: `Sources/Core/Email/EMLXReader.swift:43`, `Sources/Features/Pratiche/PraticaSyncEngine+Context.swift:42`
- Category: correctness
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: any `Data(contentsOf:)` error (permission, I/O) becomes `ReadError.fileNotFound`, and the only caller uses `try?`, so `resolveContext` returns nil and the message disappears from the run with no problem sentence, unlike the `.permissionDenied` path ADR-0068 §D11 added for the index.
- Trigger: Full Disk Access revoked mid-run or an `.emlx` with restrictive permissions → message silently absent from the pratica.
- Fix: propagate the underlying error and report it.
- Tracked: none

### S05-16 — `PraticaManualEntries.heading` doc contradicts its kind detection
- Where: `Sources/Core/Pratiche/PraticaManualEntries.swift:153`
- Category: docs
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: the doc at 127-134 describes the kind as read from the heading's label, but line 153 classifies by `tail.hasPrefix(PraticaEntry.Kind.call.label)` and treats everything else as `.note`, so an unknown label is silently a note.
- Trigger: n/a
- Fix: align the doc with the prefix rule, or match each kind's label explicitly.
- Tracked: none

### S05-17 — Message note `date:` depends on the machine's time zone
- Where: `Sources/Core/Pratiche/MessageDocument.swift:103`
- Category: correctness
- Severity: P4 · Confidence: suspected
- In flight: no
- What: `CalendarDate(document.frontmatter.date)` uses `Calendar.current`, so a message sent near midnight gets a different `date:` (and daily-note mirror day) depending on the zone of the machine that synced it; ADR-0065 §D8.2 asks for a stated zone rule.
- Trigger: message sent 23:30 UTC, synced on a CET machine → dated next day; re-synced elsewhere → frontmatter churn.
- Fix: pass the calendar explicitly from the sync request and document the rule.
- Tracked: none

### S05-18 — Re-rendering drops malformed hand-typed items
- Where: `Sources/Core/Pratiche/PraticaLinks.swift:46`, `Sources/Core/Pratiche/Dossier.swift:58`
- Category: correctness
- Severity: P4 · Confidence: suspected
- In flight: no
- What: `PraticaLinks.parse` and `Dossier.parse` (`inlineIntList`) `compactMap` away entries they cannot parse, and `merging` re-renders from the parsed values, so a hand-edited item with a typo is erased on the next write rather than kept or refused (ADR-0065 direction).
- Trigger: user types `- [[Nota` (unclosed) in a pratica's links block → the next link added by the app removes that line.
- Fix: carry unparsed lines through as opaque items, as `CanvasOpaqueElement` does for canvases.
- Tracked: none

### S05-19 — Negative or non-finite canvas node sizes are accepted
- Where: `Sources/Core/Canvas/JSONCanvas.swift:235`, `Sources/Core/Canvas/CanvasRequiredKey.swift:18`
- Category: correctness
- Severity: P4 · Confidence: suspected
- In flight: no
- What: `width`/`height` are read as any number with no finite or positive check and converted to `CGFloat`; a negative or huge size reaches layout unchanged.
- Trigger: a `.canvas` from another tool with `"width": -300` → card drawn inverted or not hit-testable.
- Fix: treat non-finite or non-positive sizes as the existing `absent` default in `CanvasRequiredKey`, keeping the original value in the opaque payload.
- Tracked: none

### S05-20 — `text/plain` part with a filename but no `attachment` disposition is taken as the body
- Where: `Sources/Core/Email/MIMEDecoder.swift:80`
- Category: correctness
- Severity: P4 · Confidence: suspected
- In flight: no
- What: only `Content-Disposition: attachment` marks a part as attachment; an `inline; filename="log.txt"` text part becomes `.textPlain` and may replace or concatenate into the message body.
- Trigger: a mailer that sends an attached `.txt` as `inline; filename=...` → the log appears as the note body, no attachment placed.
- Fix: treat a named `text/plain` part after the first body part as an attachment.
- Tracked: none

### S05-21 — `TextExtracting.pagesDone` is written and never read
- Where: `Sources/Core/Contenitore/TextExtracting.swift:33`
- Category: dead-code
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: written at `SystemTextExtractor.swift:40,64,82`, read nowhere (Periphery confirms). Either progress was meant to be shown or the field is residue.
- Trigger: n/a
- Fix: show it in the Contenitore progress or delete it.
- Tracked: none

### S06-13 — `trash_note`'s description ties `undo_write` to the Finder Trash, which the restore never reads
- Where: `Sources/MCPServer/ToolCatalogue+Writing.swift:86-88`
- Category: docs
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: «undo_write la rimette al suo posto finché il cestino non è stato svuotato», but the restore rewrites the journal's `textBefore` to the path (`VaultSession+Journal.swift:363-368,396-405`) and refuses only when the path is occupied again; emptying the Trash changes nothing, and the sentence sends a model to check the Trash before undoing.
- Trigger: n/a
- Fix: «undo_write la riscrive dal journal, se nel frattempo nulla ha ripreso quel percorso».
- Tracked: none

### S06-14 — `list_notes`/`note list --folder` is a string prefix, so `01` also lists `010 …` and `01.md`
- Where: `Sources/Connector/VaultReads.swift:14`, `Sources/MCPServer/ToolCatalogue.swift:53`
- Category: correctness
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `relativePath.hasPrefix(folder)` matches across path-component boundaries. The schema calls it «prefisso di percorso», so a prefix is intended, but a person asking for folder `01` in a vault that also has `010-archivio` gets both, and the result silently mixes folders.
- Trigger: `note list --folder 01` with `01-progetti/` and `010-archivio/` present → both.
- Fix: compare against `folder` with a `/` appended when absent, and say «cartella» in the schema.
- Tracked: none

### S06-15 — The CLI flag table lists two flags nothing reads and lacks the one `perg lint` tests
- Where: `Sources/Connector/Arguments.swift:25`, `Sources/CLI/Commands/LintCommands.swift:11-17`
- Category: dead-code
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `version` and `all` are declared as flags and read nowhere: `perg --version` prints the usage and exits 1, `--all` is accepted and ignored. `fix` is not a flag, so `perg lint --fix` dies at the parser with «manca il valore» before the friendly «le correzioni automatiche non ci sono ancora», which only `perg lint --fix x` reaches; and `LintCommands` opens the session, a full vault scan (`:11`), before refusing `--apply`/`--fix` (`:13`).
- Trigger: n/a
- Fix: drop `version` and `all` from `flagNames` (or wire `--version` to `AppInfo`), add `fix` to it, move the refusal above the session open.
- Tracked: none

### S06-16 — «Svuota cache» swallows a failed delete
- Where: `Sources/Index/IndexCache.swift:194-196`
- Category: correctness
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `clear()` is `try? FileManager.default.removeItem(at: url)`: a permission or open-handle failure leaves the file and the caller reports success. Nothing is lost (the cache is derived, principle 3), but the person who clicked to reset a misbehaving index is told it happened.
- Trigger: n/a
- Fix: make `clear()` `throws` and let `VaultController.clearCache()` surface the error like other vault problems.
- Tracked: none

### S06-17 — `prefix(limit)` in the shared query layer still traps on a negative limit
- Where: `Sources/Index/IndexSnapshot+Search.swift:48`, `Sources/Index/IndexSnapshot.swift:142`
- Category: correctness
- Severity: P4 · Confidence: suspected
- In flight: no
- What: ADR-0063 §D1.1 put the negative-limit check in the connector (`checkedLimit`); the trap itself stays in `search(_:limit:)` and `unresolvedLinks(limit:)`, which the app calls with constants today. The next caller that forwards a user number trips it, in all three targets.
- Trigger: n/a (no current caller passes a negative)
- Fix: `prefix(max(0, limit))` in the two queries.
- Tracked: none (PG-256/PG-272, closed, hardened the connector side)

### S06-18 — `TimeBlock.resized`'s first filter is implied by its second
- Where: `Sources/Calendar/TimeBlock.swift:117-121`
- Category: simplification
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `.filter { $0.startMinutes >= block.endMinutes || $0.startMinutes > block.startMinutes }` is followed by `.filter { $0 > block.startMinutes }`; since `endMinutes > startMinutes` (duration is at least 15), the first condition is exactly the second.
- Trigger: n/a
- Fix: keep one filter.
- Tracked: none

### S06-19 — Three files of the slice are over SwiftLint's 400-line limit
- Where: `Sources/Connector/VaultPraticheLinks.swift` (421), `Sources/Index/IndexCache.swift` (408), `Sources/MCPServer/ToolCatalogue+Writing.swift` (402)
- Category: simplification
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: Each has a clean seam: the create-and-link verbs (`VaultPraticheLinks.swift:255-342`) into `VaultPraticheLinks+Create.swift`; the SQLite plumbing (`IndexCache.swift:198` onwards) into `IndexCache+SQLite.swift`; the pratica and message tools of `writing` into `ToolCatalogue+Pratiche.swift`. `CalendarService.swift`, 552 lines in the 2026-09-11 audit, is now 383 and clean.
- Trigger: n/a
- Fix: as above; new files under `Sources/Connector` and `Sources/Index` are picked up by the shared globs, the MCPServer one by its own.
- Tracked: none

### S07-06 — The capture log writes the derived note title into the unified log as `.public`
- Where: `Sources/Features/Capture/CaptureController.swift:228-237`, `Sources/Features/Capture/CaptureController.swift:172-177`, `Sources/Features/Capture/CaptureController.swift:194`
- Category: security
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: The doc at `:218-221` says "The destination and the resulting path only. Never the text", but for a «Nota nuova» the path is `NoteName.fileName(for: derivedTitle(...))` (`:172-173`, `:194`), that is the first typed line of the capture, interpolated with `privacy: .public` at `:232`; the taken-title refusal at `:175-177` and `refusal.description` at `:198` carry the same path into `:236`. The body is not logged; the title line is. PG-125 (closed, PR #846) made the route's capture text `.private` in `VaultController+Routes.swift` and did not reach this file.
- Trigger: Ctrl+Opt+Space, type a line, Return; `log show --predicate 'subsystem == "it.stefer.pergamenum"'` shows the title.
- Fix: `privacy: .private` on `path` and `reason`; the destination `rawValue` can stay public, and the UI-test verifiability the comment wants survives because a test instance reads its own container.
- Tracked: none

### S07-07 — The Help sheet's «Scorciatoie» table is typed by hand and already disagrees with the defaults
- Where: `Sources/Features/Help/HelpSheets.swift:98-102`, `Sources/Core/Shortcuts/ShortcutCommand.swift:373-376`
- Category: docs
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `("Cmd+0 / 1 / 2 / 3", "oggi, domani, +2 giorni, settimana prossima")` names chords whose defaults are Cmd+Opt+0…3 (`.taskToday` … `.taskNextWeek`, `ShortcutCommand.swift:373-376`); the other two rows match (`.taskToggle` `:369`, `.quickTask` `:313`). The rows are string literals, so a binding changed in Impostazioni › Scorciatoie (ADR-0002) leaves the sheet showing the old one.
- Trigger: Aiuto › Guida sintassi task, last section.
- Fix: Render the section from the shortcut store, one row per `.taskToggle`, `.taskToday` … `.taskNextWeek`, `.quickTask`, using the binding-to-text rendering the Scorciatoie tab already has (`ShortcutSettings.swift:112-242`); the sheet is already parametrised (`inboxNotePath`, `:72`).
- Tracked: none

### S07-08 — `ViewsPane` keys its catalogue scan on `scanGeneration`, the key PG-325 and PG-328 moved the editor's siblings off
- Where: `Sources/Features/Views/ViewsPane.swift:56`
- Category: correctness
- Severity: P4 · Confidence: suspected
- In flight: no
- What: The Viste pane rescans on `ScanTrigger(generation: vault.scanGeneration, dayTick:)`; an in-app save goes through `VaultSession.write`, which updates the index and bumps `indexGeneration`, not `scanGeneration` (PG-095's analysis, ADR-0072). Adding or editing a `pergamenum-view` fence and saving does not change the pane's list or counts while it is open until a rescan or a new day. The editor's view block (PG-325) and the transclusion source (PG-328) were moved to `indexGeneration` for the same reason; this pane was named in neither burn-down and ADR-0072 does not mention it. Suspected because the app was not run to see whether something else bumps `scanGeneration` on save.
- Trigger: Viste pane open, add a fence to a note in another window, save.
- Fix: `generation: vault.indexGeneration`.
- Tracked: none (same family as PG-325 and PG-328, both closed)

### S07-09 — `ShadowValue.spread` is parsed and never applied (Periphery confirmed)
- Where: `Sources/DesignSystem/TokenValue.swift:56-62`, `Sources/DesignSystem/ThemeEnvironment.swift:99`
- Category: dead-code
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `ShadowValue` decodes `spread` from the DTCG shadow token but the only consumer draws `content.shadow(color:radius: shadow.blur / 2, x:y:)`; SwiftUI's shadow has no spread, so a theme author setting it changes nothing. Periphery's `assignOnlyProperty` at `TokenValue.swift:61` is right. The other two Periphery lines in this slice, `ViewsPane.swift:36-37` (`ScanTrigger.generation` and `dayTick` assign-only), are refuted: both fields exist for the synthesized `Equatable` that `.task(id:)` compares.
- Trigger: n/a
- Fix: Drop the property and tolerate the key (DTCG allows it), or say on the token that spread is read and ignored.
- Tracked: none

### S07-10 — Write-only `@State hasLooked` in the view thumbnail
- Where: `Sources/Features/Views/ViewGridRenderers.swift:74`, `Sources/Features/Views/ViewGridRenderers.swift:127`, `Sources/Features/Views/ViewGridRenderers.swift:129`, `Sources/Features/Views/ViewGridRenderers.swift:135`
- Category: dead-code
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `hasLooked` is assigned in three places and read nowhere (`grep -n hasLooked` returns the declaration and the three assignments only), so each write schedules a view update for a value no `body` reads.
- Trigger: n/a
- Fix: Delete the property and the three assignments; if it was meant to suppress a second look-up, read it in the guard that starts the look-up.
- Tracked: none

### S07-11 — `.onExitCommand` in `CapturePanelView` is documented dead by the panel that hosts it
- Where: `Sources/Features/Capture/CapturePanelView.swift:52`, `Sources/Features/Capture/CapturePanel.swift:144-172`
- Category: dead-code
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `CapturePanel.swift:146-153` explains that SwiftUI's `.onExitCommand` never fires inside the non-activating panel and that `EscapableCapturePanel.cancelOperation` (`:164-172`) closes it instead; the view still carries `.onExitCommand(perform: onClose)`, a second Esc path that does nothing and that every reader has to disprove.
- Trigger: n/a
- Fix: Remove the modifier and leave a one-line pointer to `EscapableCapturePanel`.
- Tracked: none

### S07-12 — `ProseTypography` still says it is a compile-time stub for a red suite
- Where: `Sources/DesignSystem/ProseTypography.swift:12-14`
- Category: docs
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: The header reads "`Tests/ProseTypographyTests.swift` is the red suite this stub exists to satisfy compile-time; the coder fills in each body next (plan `2026-09-04-editor-page-typography-noteplan.md`, Task 2)"; the type has been the live implementation since that plan shipped (`TODO.md:826` names `ProseTypography.prose(_:)` as the mechanism `ef7c915` relies on).
- Trigger: n/a
- Fix: Replace the three lines with what the type does now.
- Tracked: none

### S07-13 — `EditorSettings` reads the font-family and spell-checker lists "once" into instance storage SwiftUI rebuilds with the parent
- Where: `Sources/Features/Settings/EditorSettings.swift:15`, `Sources/Features/Settings/EditorSettings.swift:21`
- Category: performance
- Severity: P4 · Confidence: suspected
- In flight: yes
- What: `private let availableFamilies = NSFontManager.shared.availableFontFamilies` and `availableLanguages` are instance properties of a `View` struct whose comments say "read once … rebuilding it on every redraw of the picker is work nobody asked for"; a struct initialiser runs every time `SettingsView.body` re-evaluates (`SettingsView.swift:22` constructs `EditorSettings()` inline), so the couple-of-hundred-entry read repeats per parent evaluation, not once per window. Suspected: how often the parent re-evaluates depends on what it observes; the comment's claim is wrong either way.
- Trigger: n/a
- Fix: `static let`, or `@State` filled in `.task`, and the comment corrected.
- Tracked: none

### S07-14 — No test walks `ColorToken.allCases` through the emergency palette the `!` fallbacks depend on
- Where: `Sources/DesignSystem/Theme.swift:38`, `Sources/DesignSystem/Theme.swift:243-247`, `Tests/DesignSystemTests.swift:230`
- Category: correctness
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `color(_:)` and `rawColor(_:)` resolve a token a theme lacks with `Theme.emergency.colors[token]!`, and the emergency palette is a hand-typed literal (58 entries today, equal to the 58 cases). PG-225 (closed, PR #471) was exactly a case added to `ColorToken` and not to the literal, crashing xctest on a partial theme; its test `emergencyThemeDefinesTheCalendarTokens` covers the three tokens of that incident and `grep -rn 'ColorToken.allCases' Tests` finds no exhaustive check, so the next added case repeats PG-225 unnoticed until a partial theme resolves it. `FontToken.allCases` has such a walk (`DesignSystemTests.swift:230`).
- Trigger: Add a `ColorToken` case, forget the literal, resolve it on a user theme that omits it.
- Fix: One test: `for token in ColorToken.allCases { #expect(Theme.emergency.colors[token] != nil) }`, and the same for spacings, radii and shadows.
- Tracked: none (regression class of PG-225, closed)

### S07-15 — `QuickLookPresenter`'s delegate doc promises arrow-key forwarding the method refuses
- Where: `Sources/Features/QuickLook/QuickLookPresenter.swift:136-141`
- Category: docs
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: "Lets the panel forward arrow keys back here so the selection can follow it" sits on `previewPanel(_:handle:)`, whose body returns `false` on every path, so the selection never follows the panel. Either the sentence or the method is unfinished.
- Trigger: n/a
- Fix: Say the method declines every key (and why the delegate still implements it), or forward the arrow keys to the selection as the sentence says.
- Tracked: none

### S08-10 — A standard layout fragment is allocated for every paragraph even when a custom one is returned
- Where: `Sources/Features/Editor/EditorDecorationDelegate.swift:437`
- Category: performance
- Severity: P4 · Confidence: confirmed
- In flight: yes
- What: `let standard = NSTextLayoutFragment(textElement:range:)` is created before any branch, then discarded whenever a fold badge, rule, anchor, callout, fence or chip fragment is returned.
- Trigger: n/a
- Fix: create it in the fall-through only.
- Tracked: none

### S08-11 — `Logger.folding` doc says `notice`; every call is `debug`
- Where: `Sources/Features/Editor/EditorDecorationDelegate.swift:963-966`, `Sources/Features/Editor/EditorDecorationDelegate.swift:284`, `Sources/Features/Editor/EditorDecorationDelegate.swift:361`
- Category: docs
- Severity: P4 · Confidence: confirmed
- In flight: yes
- What: the doc comment claims «One line per fold, at `notice` and not `info`… it has to leave a trace», but all six calls (`:284, :293, :299, :312, :339, :361`) are `.debug`, which is not persisted. The demotion fixed ROADMAP chain 13 item 10 (per-keystroke notice); the comment was left behind.
- Trigger: n/a
- Fix: rewrite the comment to say debug and why.
- Tracked: none

### S08-12 — `MessageAnchorFragment` builds a symbol image on every bounds query and draw
- Where: `Sources/Features/Editor/MessageAnchorFragment.swift:31`, `Sources/Features/Editor/MessageAnchorFragment.swift:54`, `Sources/Features/Editor/MessageAnchorFragment.swift:62`
- Category: performance
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: the marker image (`NSImage(systemSymbolName:)` + configuration) is a computed property read from both `renderingSurfaceBounds` and `draw(at:in:)`, which TextKit calls repeatedly while scrolling.
- Trigger: n/a
- Fix: a `lazy var` or a static cache keyed by point size and colour.
- Tracked: none

### S08-13 — Quote rendering computes `survivors` twice for one paragraph
- Where: `Sources/Features/Editor/EditorDecorationDelegate+QuoteRendering.swift:76-81`
- Category: simplification
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `Self.survivors(among:of:in:)` is called once over the non-blockquote markers and again over all markers for the same range and text.
- Trigger: n/a
- Fix: compute once and filter.
- Tracked: none

### S09-editor-b-07 — Outline drag recomputes a whole-note outline parse per row and per gap on every body evaluation
- Where: `Sources/Features/Editor/OutlinePane.swift:93`, `Sources/Features/Editor/OutlinePane.swift:115`, `Sources/Core/Markdown/OutlineMove.swift:33`, `Sources/Core/Markdown/OutlineMove.swift:65`
- Category: performance
- Severity: P4 · Confidence: suspected
- In flight: no
- What: while a heading is being dragged, `isValidDrag` for each row (`.nestingUnder`) and each gap (`.toPrecede`) calls `moveReplacements`, and both `OutlineMove.replacements` overloads start with `NoteOutline.entries(in: text)`. A body evaluation during a drag therefore parses the note's outline 2N+1 times for N headings.
- Trigger: a long note with ~100 headings; drag a heading over the outline → ~200 outline parses per hover-driven re-render.
- Fix: compute the set of valid targets once when the drag begins (`beginDrag`) and read it per row.
- Tracked: none

### S09-editor-b-08 — Quick switcher `Nota#sezione` reads the target note (disk when not open) per keystroke
- Where: `Sources/Features/Editor/QuickSwitcher.swift:235`, `Sources/Features/Editor/QuickSwitcher.swift:242`, `Sources/App/VaultController+Notes.swift:50-55`
- Category: performance
- Severity: P4 · Confidence: suspected
- In flight: no
- What: `headingGroup` calls `vault.noteText(at:)` (open tab's text, else `session.read`, a synchronous disk read) and `NoteOutline.entries(in:)` on each render while the query contains `#`; the cost is acknowledged at `:33-35` but uncached.
- Trigger: type `Progetto#` then the section name letter by letter → one file read and outline parse per keystroke for a note not open in a tab.
- Fix: memoise text/outline by path and index generation for the switcher's lifetime.
- Tracked: none

### S09-editor-b-09 — Unused `@Environment(\.theme)` in VaultTopBar survives the chain-13 dead-code close
- Where: `Sources/Features/Editor/VaultTopBar.swift:11`
- Category: dead-code
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: the body uses only `.themedText(...)`, which reads the theme itself; `theme` is never read (Periphery agrees). ROADMAP chain 13 listed it (`ROADMAP.md:935`) and PG-266 closed with no in-file note keeping it, unlike `NoteSelectionRule.swift:53 old` and `ViewBlockHostStore.swift:41-44 textView`, which are documented in place.
- Trigger: n/a
- Fix: delete the property.
- Tracked: regression of PG-266

### S09-editor-b-10 — `OutlineMap.Item`/`items` kept alive in production only by a test seam
- Where: `Sources/Features/Editor/OutlineMap.swift:38-43`, `Sources/Features/Editor/OutlineMap.swift:54-67`, `Sources/Features/Editor/NoteTextView+DerivedState.swift:80`
- Category: dead-code
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `items` is read in production only to fill `DerivedStateSnapshot.outline` (`outline: fedOutlineStore?.map.items ?? []`), a snapshot built for tests; `Item.kind` and `Item.level` are assigned and never read (Periphery `:40`, `:42` assignOnly).
- Trigger: n/a
- Fix: compute the snapshot's outline in the test target from `map`, or drop `kind`/`level` from `Item`.
- Tracked: none

### S09-editor-b-11 — `nonisolated(unsafe)` fragment fields carry no stated reason
- Where: `Sources/Features/Editor/QuoteBarFragment.swift:11-16`, `Sources/Features/Editor/TranscludedLineFragment.swift:67-69`
- Category: docs
- Severity: P4 · Confidence: suspected
- In flight: no
- What: both `NSTextLayoutFragment` subclasses mark their mutable fields `nonisolated(unsafe)` with no comment on why it holds (written by the delegate when the fragment is made, read at draw time on the same thread). The brief asks for a documented reason on every such escape; `FoldedHeadingFragment.swift:20-23` gives a partial one. No race was traced.
- Trigger: n/a
- Fix: one comment per class naming the write-at-creation / read-at-draw invariant on the main thread, or `let` fields set through an initialiser.
- Tracked: none

### S10-workspace-13 — Redundant explicit memberwise initializer
- Where: `Sources/Features/Workspace/CanvasCrop.swift:25-30`
- Category: simplification
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: the explicit `init` assigns each stored property from a parameter of the same name and label, which is the synthesized memberwise init.
- Trigger: n/a
- Fix: delete it.
- Tracked: none

### S10-workspace-14 — Force unwrap after a guard that already matched the node
- Where: `Sources/Features/Workspace/WorkspaceController+TextEditing.swift:45`
- Category: house-rules
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `LinkCardTitle.read(from: document.node(id: nodeID)!)` re-looks-up a node that `:37` already matched, then force-unwraps it. The unwrap is safe today but breaks the no-force-unwrap rule.
- Trigger: n/a
- Fix: bind the node in the `guard` at `:37` (`guard let node = ..., case .link = node.kind`) and pass it.
- Tracked: none

### S10-workspace-15 — Folder-creation failure shows a raw error dump in the sheet
- Where: `Sources/Features/Workspace/WorkspaceController+Documents.swift:57`
- Category: correctness
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `let sentence = "\(error)"` renders whatever the error's description is. For a file-system `NSError` that is the full `Error Domain=NSCocoaErrorDomain Code=…` dump in English. The doc above says each error keeps "its own text", but only the app's own error types read as sentences. The note kind uses `ConformanceText.creationFailure(error)` (`:40`).
- Trigger: create a folder from the canvas sheet where the disk refuses (permissions) → the sheet shows a Cocoa debug string.
- Fix: route through `ConformanceText.creationFailure` or use `localizedDescription` for non-app errors.
- Tracked: none

### S10-workspace-16 — New cards from the tray and the empty state always land at (60, 60)
- Where: `Sources/Features/Workspace/BoardTray.swift:249`, `Sources/Features/Workspace/WorkspaceView.swift:219`, `Sources/Features/Workspace/WorkspaceView.swift:251`, `Sources/Features/Workspace/WorkspaceController+Nodes.swift:181-192`
- Category: correctness
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: these entry points pass `CGPoint(x: 60, y: 60)`, and `placeFile` uses it with no offset. Cards stack exactly on top of each other, and on a panned or zoomed board they appear off screen.
- Trigger: add three items from «Nuovi elementi» on a board scrolled away from the origin → nothing visible appears; all three sit stacked at (60, 60).
- Fix: place at the visible viewport's centre (the viewport helpers are in `+Viewport.swift`), cascading like the import path (`+Import.swift:52`).
- Tracked: none

### S10-workspace-17 — Browser width read unclamped; divider cursor can stay pushed
- Where: `Sources/Features/Workspace/WorkspaceView.swift:59`, `Sources/Features/Workspace/WorkspacePaneDivider.swift:45-51`
- Category: correctness
- Severity: P4 · Confidence: suspected
- In flight: no
- What: `@AppStorage("workspaceBrowserWidth")` is used as stored. `WorkspacePaneDivider.clamp` (160...420, `:32-34`) applies only while dragging, so an out-of-range stored value (an older build, `defaults write`) is drawn as is. The divider pushes `NSCursor.resizeLeftRight` on hover and pops it on hover-out. If the divider disappears while hovered (concentrazione or the tree toggled by shortcut), the pop never runs. The same leak was fixed for the crop grip under PG-146.
- Trigger: n/a (suspected: hover the divider, toggle «Albero» by shortcut → resize cursor persists over the board).
- Fix: clamp on read, and pop in `.onDisappear` when a push is outstanding.
- Tracked: none

### S11-09 — An always-true `guard let existingOnDisk` inside the row-4 branch
- Where: `Sources/Features/Pratiche/PraticaSyncEngine+Messages.swift:772-778,794`
- Category: dead-code
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `mustFullyRender` is `true` whenever `existingOnDisk == nil` (`:774`), so inside `guard mustFullyRender else { … }` the value is always non-nil and `guard let existingOnDisk else { return }` (`:794`) can never return. A reader takes it for a reachable "nothing on disk, patch nothing" path.
- Trigger: n/a
- Fix: bind once above, `guard let existingOnDisk, !isRequestedRegeneration, existingOnDisk.document.frontmatter.body != .pending, … else { full render }`, and drop the inner guard.
- Tracked: none

### S11-10 — `PraticaSyncEngine.vaultRoot` is stored but read only in `init`, and its doc describes writes that no longer bypass the boundary
- Where: `Sources/Features/Pratiche/PraticaSyncEngine.swift:24-25,47-48,73`
- Category: dead-code
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `self.vaultRoot = vaultRoot` feeds `VaultBoundary(root: vaultRoot)` on the next line and nothing reads the property afterwards (Periphery `periphery-all.txt:107`, confirmed). The doc above it says "attachments and `.eml` are written directly under it (they are not notes, so they never go through `write`)": they now resolve through `boundary` and `makeDirectory` and get `stampQuarantine` (`+Messages.swift:749,849`), which the sentence hides.
- Trigger: n/a
- Fix: drop the stored property; say that attachments and `.eml` resolve through `boundary` and are written atomically with quarantine, not through `VaultSession.write`.
- Tracked: none

### S11-11 — Three comments describe code that moved on
- Where: `Sources/Features/Pratiche/PraticaSyncEngine.swift:86-90`, `Sources/Features/Pratiche/PraticheController+TimelineRead.swift:109-112`, `Sources/Features/Pratiche/PraticheController+DeleteKey.swift:5-6`
- Category: docs
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: (1) `PraticaSyncEngine.swift:88` cites the three `write` call sites as `:398`, `:878`, `:906`; they are `+Folder.swift:159`, `+Messages.swift:814` and `:855`, so the one note telling a reader where the `expecting:` argument matters points at nothing. (2) `+TimelineRead.swift:110-112` says "`readMessages` below is the RED stub - it still hardcodes `isInMail: true` and ignores it", while `:167` reads `isInMail: !notInStore.contains(…)`. (3) `+DeleteKey.swift:5-6` says `PraticheController.swift` "sits against SwiftLint's 400-line warning at 641 lines"; it is 676.
- Trigger: n/a
- Fix: name the call sites by function (`makeDirectory`, `commit`, `commitRegeneration`) rather than by line; delete the RED-stub paragraph; drop the line count.
- Tracked: none

### S11-12 — Three hand-rolled `.replacingOccurrences(of: ".md", with: "")` where `deletingPathExtension` exists
- Where: `Sources/Features/Pratiche/PraticaFileOperations.swift:175,284,348`
- Category: simplification
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: the three sites strip every `.md` substring from a file name to get its stem; `(name as NSString).deletingPathExtension`, which `PratichePane+Links.swift:201` already uses for boards, is the Foundation call. Not a correctness issue today: `PraticaNaming.messageFileName` kebab-cases the subject (`PraticaNaming.swift:36-39`), so `.md` cannot occur mid-name in a note this app named.
- Trigger: n/a
- Fix: one `stem(of:)` helper on `PraticaFileOperations`, or `deletingPathExtension` at the three sites.
- Tracked: none

### S11-13 — Two UI sentences interpolate a raw Swift error
- Where: `Sources/Features/Pratiche/PraticaCommandActions+Links.swift:147,174`
- Category: house-rules
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `pratiche.report("nota non creata: \(error)")` and `"nuova board: \(error)"` put an English error description in the Italian problem line the pane shows (`PratichePane.swift:53-59`); every other reporter in the slice uses `error.localizedDescription` (`PraticaCreation.swift:24`, `PraticheController.swift:519`).
- Trigger: a note creation refused by the write door → the error's debug description on screen after «nota non creata:».
- Fix: `error.localizedDescription`, in a sentence with a subject («Non è stato possibile creare la nota: …»).
- Tracked: none

### S11-14 — The wizard's eyebrow and footer deviate from DESIGN.md's binding decisions, because DESIGN.md is behind the SPEC
- Where: `Sources/Features/Pratiche/NuovaPraticaWizard.swift:47`, `Sources/Features/Pratiche/NuovaPraticaWizard+Steps.swift:225-247`, `Sources/Features/Pratiche/WizardState.swift:12-13,21`
- Category: house-rules
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: DESIGN.md:32 binds «PASSO n DI 3» and the footers Annulla/Continua, Indietro/Continua, Indietro/Crea. The code shows «PASSO n DI 4» whenever new counterparts are offered (the fourth step the SPEC added, `WizardState.Step.newCounterparts`, `:21`) and keeps «Annulla» leading on every step (`:227`, the Esc target). `WizardState.swift:12-13` still documents three steps. The behaviour is the SPEC's; the design note and the type's doc are what drifted.
- Trigger: n/a
- Fix: amend DESIGN.md's binding decision (eyebrow «PASSO n DI 3», «DI 4» when the detector offers addresses; «Annulla» on every footer as the Esc target) and `WizardState`'s doc; no code change.
- Tracked: none

### S11-15 — `PraticaWatcher.decideImmediateTrigger` takes a `now` it never reads
- Where: `Sources/Features/Pratiche/PraticaWatcher.swift:64-72`
- Category: dead-code
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: the body consults `trigger` and `eligibility` only; `now` is a leftover of the tester's signature (`:64-66`), confirmed by Periphery (`periphery-all.txt:108`). Every caller computes a date for nothing.
- Trigger: n/a
- Fix: drop the parameter and its argument at the call sites and in the tests.
- Tracked: none

### S11-16 — `MailDropReport.at` is written on every drop and read by nothing
- Where: `Sources/Features/Pratiche/MailDropReceiver.swift:25`, `Sources/Features/Pratiche/PratichePane.swift:168-174`
- Category: dead-code
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: the pane shows `dropReport.summary` only; `at` is assigned at construction and never read (Periphery `periphery-all.txt:105`, confirmed). The R-22 tracer bullet records the UTIs, which is the whole probe; the timestamp is noise.
- Trigger: n/a
- Fix: remove the field, or show it in the report line if a date was wanted.
- Tracked: none

### S12-14 — Transcript quote sanitizer omits `!`, the task grammar's due marker
- Where: `Sources/Features/Recordings/TranscriptNote.swift:24`, `Sources/Core/Tasks/TaskParser.swift:65`
- Category: correctness
- Severity: P4 · Confidence: suspected
- In flight: no
- What: `charactersTheTaskGrammarOwns` is `[">", "#", "^", "[", "]"]`; `TaskParser` also reads `!` as the due marker (l.65, l.295). A quoted task text containing `!<date>`-like text could be parsed as a due date.
- Trigger: proposed task text "chiamare !domani" → imported line gains a due date.
- Fix: add `!` to the set (or reuse the parser's own marker list).
- Tracked: none

### S12-15 — DayTimeline projects events four times per body
- Where: `Sources/Features/Today/DayTimeline.swift:23`, `Sources/Features/Today/DayTimeline.swift:234`
- Category: performance
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `projectedEvents` is a computed property read by `hours`, `timedEvents`, `allDayEvents` and `eventLanes`, so the projection runs repeatedly per render.
- Trigger: n/a
- Fix: compute once in `body` and pass down, or store it.
- Tracked: none

### S12-16 — Stale doc comments and citations
- Where: `Sources/Features/Today/DayTimeline.swift:276`, `Sources/Features/Recordings/RecordingsController.swift:307`, `Sources/Features/Recordings/PlaudService.swift:8`, `Sources/Features/Recordings/PlaudVaultStore.swift:52`, `Sources/Features/Recordings/PlaudTimestamp.swift:23`
- Category: docs
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `DayTimeline.time(at:)`'s comment describes behaviour the code no longer has; `RecordingsController.swift:307-308` cites `VaultController+Files.swift:70` for `trashNote`, now at `:96`; `PlaudService.swift:8` cites `CalendarService.swift:69-104` for `CalendarStore`, but that region is `CalendarService.init`/observers and the protocol is `Sources/Calendar/CalendarStore.swift:10`; `PlaudVaultStore.swift:52` cites `VaultSettings.swift:161-211` for `init(from:)`, a region now holding `resolveInboxFolder` and `.default` (decoders at `:32`, `:229`); `PlaudTimestamp.swift:23-27` justifies allocations by "a handful of parses per import", but `RecordingRow.swift:176` and `:262` parse per row per render.
- Trigger: n/a
- Fix: update the citations (prefer symbol names over line numbers) and the cost rationale.
- Tracked: none

### S12-17 — Plaud service address hardcoded twice
- Where: `Sources/Features/Recordings/PlaudError.swift:53`, `Sources/Features/Recordings/PlaudHTTPClient.swift:18`
- Category: simplification
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: the unreachable message spells `127.0.0.1:3777` literally, separate from `PlaudHTTPClient.base`; changing the port would leave the message wrong.
- Trigger: n/a
- Fix: interpolate the host/port from `PlaudHTTPClient.base`.
- Tracked: none

### S12-18 — DayController problem strings interpolate raw English `\(error)`
- Where: `Sources/Features/Today/DayController.swift:165`, `Sources/Features/Today/DayController.swift:281`, `Sources/Features/Today/DayController.swift:374`, `Sources/Features/Today/DayController.swift:387`, `Sources/Features/Today/DayController.swift:402`
- Category: house-rules
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: Italian problem messages append `\(error)` (Swift debug description, English, type names), the shape the Recordings code avoids via `readableMessage` (R-13).
- Trigger: n/a
- Fix: route through a shared readable-message helper (`localizedDescription` at least).
- Tracked: none

### S12-19 — Checkbox images toggled by tap gesture have no accessibility action
- Where: `Sources/Features/Today/DayReferences.swift:77`, `Sources/Features/Today/DayReferences.swift:117`, `Sources/Features/Tasks/TasksView+Row.swift:20`, `Sources/Features/Tasks/LinkedTasksPanel.swift:63`
- Category: house-rules
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: task completion is an `Image(...).onTapGesture`, not a `Button`/`Toggle`: VoiceOver and keyboard users cannot complete a task from these rows, and UI tests cannot address them as buttons.
- Trigger: n/a
- Fix: wrap in a `Button` with a plain style and an Italian accessibility label.
- Tracked: none

### S12-20 — Reminder time built through `EventKitStore.date(.today, …)` shifts on the DST gap
- Where: `Sources/Features/Tasks/TaskTimeRow.swift:55`
- Category: correctness
- Severity: P4 · Confidence: suspected
- In flight: no
- What: `moment(of:)` anchors the picker value on *today* via `Calendar.date(from:)`; on the spring-forward day in Europe/Rome 02:xx does not exist and normalises to 03:xx, so a 02:30 time picked that day shows/stores 03:30.
- Trigger: on the last Sunday of March, set a task time of 02:30 → shown as 03:30.
- Fix: build the picker anchor on a fixed reference day without a DST transition, keep only hour/minute.
- Tracked: none

### S12-21 — Toolbar `selected` scans all tasks six times per render; options binding decodes JSON per read
- Where: `Sources/Features/Tasks/TasksView.swift:153`, `Sources/Features/Tasks/TasksView+List.swift:130`
- Category: performance
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `selected` is `vault.index.allTasks.first { ... }`, read by six `.disabled(selected == nil)` modifiers per toolbar render; `optionsBinding`'s getter decodes the `@AppStorage` JSON map on every read (residual of PG-268's per-row decode fix).
- Trigger: n/a
- Fix: compute `selected` once per body; decode options once per change.
- Tracked: none

### S13-05 — `createContainer` touches the disk directly beside the store call that already does it
- Where: `Sources/Features/Contenitore/ContenitoreCommand.swift:201`
- Category: house-rules
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `rootFolder` comes from `session.store.url(for: parent)` (`:200`, boundary-resolved), then `FileManager.default.createDirectory` (`:201`) runs from a Feature file before `CanvasStore(root:).createFolder` (`:202`). ADR-0041 §D1 keeps disk access in one place; the other three `createFolder` callers do not pre-create the parent.
- Trigger: n/a
- Fix: let `CanvasStore.createFolder` / `FolderFileOperations.createFolder` create intermediates, drop `:201`.
- Tracked: none

### S13-06 — `DropFolderEventStream` start/stop state is unisolated under `@unchecked Sendable`
- Where: `Sources/Features/Contenitore/DropFolderEventStream.swift:43`
- Category: correctness
- Severity: P4 · Confidence: suspected
- In flight: no
- What: the sink lifetime already follows the bd5b571 VaultWatcher fix (`passRetained` at `:59`, `cancel()` then `queue.async { sink.release() }` in `stop()` `:87-101`), so no use-after-free. What remains: `stream`/`sinkInfo` (`:43-45`) are plain vars mutated by `start()`/`stop()` and `deinit` (`:52-54`), with thread confinement asserted by `@unchecked Sendable` (`:15`) but not enforced. Same shape as `MailStoreEventStream.swift:12-26`.
- Trigger: n/a today (callers are main-actor).
- Fix: `@MainActor` on `start()`/`stop()` or a doc comment naming the invariant.
- Tracked: none

### S13-07 — Disk stats in view bodies on the main actor
- Where: `Sources/Features/Contenitore/ContenitoreList.swift:23`
- Category: performance
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `rows(vault:contenitore:)` passes `fileExists: session.exists` (one `fileExists` stat per scheda per body, `VaultSession.swift:291-294`); `ContenitoreInspector.fileLine` calls `attributesOfItem` in body (`:137-145`); sidebar `allRows`/`inboxCount` recompute per body (`ContenitoreSidebar.swift:90-101`); `apply` lists the drop folder on the main actor (`ContenitoreController.swift:283`). ADR-0072: a disk-derived value is cached for one body evaluation, never longer.
- Trigger: a root with hundreds of documents.
- Fix: compute existence and size in the cached row model keyed by index generation.
- Tracked: none

### S13-08 — `move` does not await the rescan that `trash` awaits
- Where: `Sources/Features/Contenitore/ContenitoreCommand.swift:150`
- Category: correctness
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `move` fires `Task { await vault.rescan() }` (`:150`) and returns `true`; `trash` awaits it (`:173`). The caller can read a stale index for the moved row.
- Trigger: n/a
- Fix: `await vault.rescan()` as in `trash`.
- Tracked: none

### S13-09 — `drainTask` is write-only and never cancelled
- Where: `Sources/Features/Contenitore/ContenitoreController.swift:108`
- Category: dead-code
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: assigned at `:325`, never read, never cancelled in `stop()` (`:207`) or `releaseSession()` (`:369`); a drain can outlive a vault switch. Periphery missed it.
- Trigger: closing a vault while extraction runs.
- Fix: cancel it in `stop()`/`releaseSession()`, or drop the property.
- Tracked: none

### S13-10 — Row subtitle drops only the first path component of the container
- Where: `Sources/Features/Contenitore/ContenitoreList.swift:223`
- Category: correctness
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `row.container.split(separator: "/").dropFirst()` assumes a one-component root; `ContenitoreSettings.validateRoot` (`Sources/Core/Contenitore/ContenitoreSettings.swift:121-134`) accepts `Archivio/Contenitore`, so the subtitle shows the root's tail. `ContenitoreListModel.breadcrumb(of:root:)` (`:207`) already strips the full root.
- Trigger: root set to a nested path.
- Fix: use `ContenitoreListModel.breadcrumb`.
- Tracked: none

### S13-11 — Grid badge matches display strings
- Where: `Sources/Features/Contenitore/ContenitoreGrid.swift:98`
- Category: simplification
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `badge(_:)` switches on `"testo"`/`"testo da OCR"` (`:103-104`), the Italian labels from `ExtractionSummary.displayLabel` (`Sources/Core/Contenitore/TextExtracting.swift:72-84`); a label edit silently breaks the badge.
- Trigger: n/a
- Fix: switch on `ExtractionStatus`/`ExtractionMethod`.
- Tracked: none

### S13-12 — The inbox arm of `inspectorActions` is never rendered
- Where: `Sources/Features/Contenitore/ContenitoreInspector.swift:220`
- Category: dead-code
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `inspectorActions(isInbox: true)` returns `[.classify] + rest` (`ContenitoreCommand.swift:71-74`), but the inspector draws `.classify` separately (`:74`) and filters it out at `:220`; the ordering is consumed only by `Tests/ContenitoreCommandTests.swift:105`.
- Trigger: n/a
- Fix: make `inspectorActions` return `rest` for the inbox and let the inspector own the lead button; the assertion at `ContenitoreCommandTests.swift:105` changes accordingly (explain in the PR, do not delete it).
- Tracked: none

### S13-13 — Three hand-kept copies of the move-target list
- Where: `Sources/Features/Contenitore/ContenitoreInspector.swift:147`
- Category: simplification
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `containerMenu` (`:147-161`), `ContenitoreMoveMenu` (`ContenitoreMenuItems.swift:32-50`) and `ContenitoreMoveSheet` (`ContenitoreView.swift:168-213`) each build the container targets.
- Trigger: n/a
- Fix: one target list on the controller, three renderers.
- Tracked: none

### S13-14 — Unused properties in Contenitore views
- Where: `Sources/Features/Contenitore/ContenitoreNoticeStrip.swift:42`
- Category: dead-code
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `actions` (`:42`) is passed from `ContenitoreList.swift:32` and never read; `ContenitoreList.theme` (`:136`) unused (Periphery). The strip also keys `ForEach` by `\.offset` (`:52`), so dismissing a notice re-identifies the rest.
- Trigger: n/a
- Fix: remove both; key notices by a stable id.
- Tracked: none

### S13-15 — Text extraction loads whole files and checks cancellation only in OCR
- Where: `Sources/Features/Contenitore/SystemTextExtractor.swift:130`
- Category: performance
- Severity: P4 · Confidence: suspected
- In flight: no
- What: `readText` (`:130-134`) reads the whole file into a `String` with no size cap; `Task.isCancelled` is checked only in the OCR page loop (`:72`).
- Trigger: a multi-GB `.log`/`.csv` dropped in.
- Fix: cap bytes read, check cancellation between stages.
- Tracked: none

### S13-16 — ADR-0071 names a title and a type the code does not have
- Where: `docs/adr/0071-contenitore-managed-document-archive.md:406`
- Category: docs
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: §D12 says «Rivela nel Finder» (`:393`, `:406`, `:409-410`, claiming the app-wide entry is so titled); code everywhere says "Mostra nel Finder" (`ContenitoreCommand.swift:35`, `ShortcutCommand.swift:240`, and six others) and «Rivela nel Finder» appears nowhere in `Sources`. `ContenitoreContainerCommand` (`:418`, `docs/adr/INDEX.md:106`, `docs/plans/contenitore.md:675,730`) does not exist: the tree verbs are methods `createContainer`/`renameContainer`/`moveContainer`/`trashContainer`. §D11 «Sposta nel Cestino…» (`:394`) vs `:39` without ellipsis. Label unification is ROADMAP chain 10 item 2 (PG-263, no open ledger line found).
- Trigger: n/a
- Fix: amend ADR-0071 §D11-§D12 to the shipped names.
- Tracked: none

### S13-17 — Design gallery ships in Release
- Where: `Sources/Features/DesignGallery/MockupGalleryView.swift:14`
- Category: dead-code
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: 38 files / about 8.5k lines compiled into the app by `Project.swift:266` (`.glob("Sources/**", ...)`), no `#if DEBUG` in the folder, reachable from Impostazioni › Design System (`DesignSystemSettings.swift:101,115`). Deliberate per ADR-0051 §D6 ("The design gallery ships in the app"); listed so the decision is visible, not as a defect.
- Trigger: n/a
- Fix: none unless §D6 is reopened; option: exclude the folder from Release via a `DEBUG` condition.
- Tracked: none

### S13-18 — Gallery labels and header comments describe pre-implementation states
- Where: `Sources/Features/DesignGallery/MockupGalleryView.swift:84`
- Category: docs
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: the milestone label records the mockup's approval, not the feature's shipping, but several drifted: "da approvare" on shipped features (transclusion `:84`, template `:89`, tabs `:90`, tagBrowser `:91`, views `:93`, week `:94`, taskControls `:95`, gutter `:96`) and on N5 (`:104-106`) although PG-421 («approve the three mockups») is recorded "#1023 closed COMPLETED 2026-10-16". Tests pin strings: `Tests/MockupGalleryLayoutTests.swift:40,60,62,67,93,125`. Comments: `OutlineMockup.swift:13` says `NoteOutline` "does not exist yet" (it is `Sources/Core/Markdown/NoteOutline.swift`); `CodeBlockMockup.swift:13-16` and `HistoryMockup.swift:5-6` describe the pre-feature app as current.
- Trigger: n/a
- Fix: update labels and the pinned test strings together; rewrite the three comments in past tense. The N4 label is PG-410.
- Tracked: none

### S13-19 — The four M0 mockups duplicate shipped panes off the shared page
- Where: `Sources/Features/DesignGallery/EditorMockup.swift:1`
- Category: simplification
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `EditorMockup`, `WorkspaceMockup`, `TodayMockup`, `TasksMockup` redraw panes that shipped in M1-M5 and do not use `MockupPage`/`MockupScene` (ADR-0051 §D5).
- Trigger: n/a
- Fix: delete them or move them onto `MockupPage`; decide with ADR-0051 §D6.
- Tracked: none

### S13-20 — Unused gallery properties and a Conformità comment survive the chain-13 cleanup
- Where: `Sources/Features/DesignGallery/LinkPreviewMockupPieces.swift:45`
- Category: dead-code
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: unused `@Environment(\.theme)` at `LinkPreviewMockupPieces.swift:45` (never in chain 13), plus the residues ROADMAP chain 13 items 1 and 5 named and PG-266 closed without removing: unused `theme` at `CaptureMockup.swift:15`, `SlashMenuMockup.swift:19`, `TransclusionMockup.swift:15`, `WeekMockup.swift:25`, `WeekMockupPieces.swift:40`; unused `TagBrowserMockup.paneWidth` `:39`; "Conformità" in the `TagBrowserMockup.swift:14` doc comment. The user-visible «Verifica conformità»/CONFORMITÀ strings are gone. All confirmed by Periphery lines 76-82.
- Trigger: n/a
- Fix: remove the seven properties, drop "Conformità" from the comment.
- Tracked: regression of PG-266

### S13-21 — Two gallery literals outside tokens and outside ADR-0051 §D10
- Where: `Sources/Features/DesignGallery/ViewMockupRenderers.swift:152`
- Category: house-rules
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `.shadow(radius: isLifted ? 6 : 0, y: isLifted ? 3 : 0)` bypasses `themedShadow`; `LinkPreviewMockup.swift:131` uses the `[.black, .black.opacity(0)]` mask ramp that §D10 exempts only for `TransclusionMockup`.
- Trigger: n/a
- Fix: `themedShadow`; extend §D10's sentence to name the second mask.
- Tracked: none

### SEC-16 — TODO.md's Tier 1 security header says every finding is open, and two sub-bullets have lost their parent
- Where: `TODO.md:299`, `TODO.md:307`, `TODO.md:309`
- Category: docs
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: the heading reads "all 27 findings are still open" while `PG-122` (line 301) and `PG-127` (line 311) under it are `[x]`; lines 307 and 309 are rationale bullets for `PG-155` and `PG-125` that now sit under `PG-122`.
- Trigger: n/a
- Fix: drop the count from the heading, move the two bullets under their entries.
- Tracked: none

### SEC-17 — `release.sh` verifies the published feed with the `curl | grep -q` shape it documents as broken a hundred lines earlier
- Where: `scripts/release.sh:311`, `scripts/release.sh:171`
- Category: correctness
- Severity: P4 · Confidence: suspected
- In flight: no
- What: under `set -o pipefail`, `grep -qF` exits at the first match and `curl` can then die of SIGPIPE, turning a found signature into a failed pipeline; the script fixed exactly this for `codesign` at lines 170-178 with a here-string. The appcast is small, so curl usually finishes before grep closes the pipe, hence a rare false "feed not updated".
- Trigger: a feed large enough that curl is still writing when grep matches → the verification loop reports a miss and retries/fails.
- Fix: capture the body first (`feed=$(curl -fsSL "$feed_url")`) and grep the variable, as the `codesign` checks do.
- Tracked: none

### SEC-18 — Workflow actions are pinned by tag, not by commit SHA
- Where: `.github/workflows/ci.yml:50`, `.github/workflows/ci.yml:64`, `.github/workflows/merge-integrity.yml:59`, `.github/workflows/adr-references.yml:38`
- Category: security
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `actions/checkout@v4` and `actions/cache@v4` follow a movable tag. Exposure is small: every workflow declares `permissions: contents: read`, uses no secret, has no `pull_request_target`, and passes event fields through `env:` rather than inline `${{ }}` in scripts.
- Trigger: n/a (a retagged upstream action would run with read access to the repository).
- Fix: pin to the full SHA with the tag in a comment.
- Tracked: none

### T01-tests-10 — a title/filename agreement test reads the real clock
- Where: `Tests/CaptureTests.swift:439-459`
- Category: flaky
- Severity: P4 · Confidence: suspected
- In flight: no
- What: `theCaptionAndTheFileNameOfACaptureAgree` calls `controller.titleCaption()` and compares it
  with a derived file name, with no injected clock or calendar; both sides read `Date()` /
  `Calendar.current` through the controller. The two reads are close enough together that an
  ordinary run agrees, which is why this is P4 and `suspected` rather than confirmed: the failure
  needs the two reads to straddle a date boundary (or a timezone change mid-run).
- Trigger: a run crossing local midnight → caption from day N, file name from day N+1 → red.
- Fix: inject the instant once and pass it to both sides, as the dated tests elsewhere in the slice
  already do.
- Tracked: none

### T02-09 — One `@Test` body with no assertion: an env-gated bench row that only prints
- Where: `Tests/EditorRestyleJumpTests.swift:86`
- Category: assertion-free
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `aKeystrokeAfterACaretJumpIsPrinted` ends in `print(RestyleBudget.jumpLine(...))` and asserts
  nothing. It is a deliberate measurement row, not a weakened test: it is gated
  `.enabled(if: RestyleBudget.includesJumpRows)` (`RESTYLE_BUDGET_JUMP=1`, driven by
  `scripts/editor-restyle-bench.sh`), so it does not run in the merge gate at all. Worth recording
  only because its three sibling bench rows *do* assert while they measure —
  `Tests/EditorRestyleBudgetTests.swift:273` and `:371` call `expectThePath` /
  `expectTheStructuralPath`, and `Tests/EditorUpdatePathBudgetTests.swift:164` asserts
  `fixture.missedUpdates == 0` — so this one row is the odd one out and a regression in the jump path
  would print quietly rather than fail.
- Trigger: n/a
- Fix: add the one invariant the row can state without pinning a number (the path taken, or
  `missedUpdates == 0`), matching its three siblings. The printed line stays.
- Tracked: none

### T02-10 — A negative source-substring guard goes green when the symbol it watches is renamed
- Where: `Tests/DailySurfaceTransclusionsTests.swift:179`
- Category: clarity
- Severity: P4 · Confidence: confirmed
- In flight: yes
- What: `theColumnNoLongerCarriesTheLookupItself` asserts
  `#expect(!source.contains("vault.index.resolve(title:"), ...)`. Any rename of
  `resolve(title:)`, or a change of receiver from `vault.index`, makes the needle unfindable and the
  test passes for the wrong reason — permanently and silently. Its own comment claims the opposite
  protection ("A call-site check, not a symbol check, so a factory nothing calls fails here"), which
  is true of the sibling positive guard at `:168` but not of a negated `contains`. Source-grep tests
  are an established pattern here (`SharedSourcesPurityTests`, `PlaudIsolationTests`,
  `Tests/RepoRootSupport.swift:10`), so the pattern is not the finding — the negation is.
- Trigger: n/a
- Fix: pair the negative with a positive that fails on a rename — assert the factory call
  `.live(for:` is present in `EditorColumn+Text.swift` as well as asserting the lookup is absent — so
  a renamed symbol breaks the positive half.
- Tracked: none

### T02-11 — Twenty dead `let root = vault.root` bindings in two Diary test files
- Where: `Tests/DiaryComposerTests.swift:15, 38, 59, 79, 98, 128, 144`, `Tests/DiaryControllerTests.swift:32, 50, 66, 81, 111, 132, 152, 165, 178, 198, 216, 230, 253`
- Category: clarity
- Severity: P4 · Confidence: suspected
- In flight: no
- What: every test in both files opens with the same binding; in the sites listed the name is never
  read afterwards, the test using `vault.root` or the controller directly instead. Marked `suspected`
  because the judgement is per-test and made by reading, not by a compiler warning — `let` bindings
  do not warn in Swift, which is why twenty copies survived.
- Trigger: n/a
- Fix: delete the unread bindings. No behaviour anywhere depends on them.
- Tracked: none

---

### T03-13 — Four `print(` calls in always-running test bodies
- Where: `Tests/IncrementalStylerPropertyTests.swift:170`, `:193`, `:224`, `:258`
- Category: clarity
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: four property tests print their generated corpus statistics on every run, so the output of the merge gate carries noise that nothing reads, and a real `Issue.record` message competes with it. The information belongs in the failure message of the `#expect` that cares.
- Trigger: n/a.
- Fix: move each line into the `#expect`'s message, or drop it.
- Tracked: none (PG-420, closed 2026-10-15 by PR #1011, shortened these lines for `line_length`; it never proposed removing the output)

### T03-14 — Assertion messages in Italian, against the project's English-code rule
- Where: `Tests/GutterRevealGeometryTests.swift:136`, `:241`, `:612`, `:674-675`, `:703`, `:716-717` (21 in that file), `Tests/GutterColumnSiteTests.swift:220`, `:239-241`, `:260-270`, `:337-342`, `Tests/GutterBlockRevealCoverageTests.swift:133`, `:139`, `:155`, `:161`, `Tests/GFMTableTests.swift:87`, `:91`, `Tests/GuardrailTests.swift:39`, `:46`, `:63`, `Tests/ExternalDeletionReconcileTests.swift:104`, `Tests/IndexUnresolvedTargetsTests.swift:76`, `Tests/InboxFolderReachTests.swift:166`, `Tests/InboxFolderSettingsTests.swift:108`, `Tests/LinkChoiceTests.swift:53`, `Tests/LinkDestinationTests.swift:51`, `:73`, `:83`, `:95`, `Tests/LinkMentionReviewTests.swift:38`
- Category: clarity
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: roughly sixty `#expect` messages are written in Italian ("la tabella comincia a … invece di …"). CLAUDE.md's rule is that the UI is Italian and code, comments and commits are English; a failure message is code output, not interface. Italian *production* strings asserted as values (`InspectorLinkRowsTests`, `LinkFollowCommandTests.swift:183`, `MailStoreReaderTests.swift:430`) are correct and out of scope — this is only about the diagnostic prose.
- Trigger: n/a.
- Fix: translate the messages when the surrounding file is next touched; not worth a dedicated sweep on its own.
- Tracked: none

### T04-12 — a file name that names nothing, and Italian test diagnostics
- Where: `Tests/NarrowInputsTests.swift` (whole file), `Tests/NoteAppearancesTests.swift`,
  `Tests/NoteEditorTeardownTests.swift:102-179`, `Tests/NoteListEditingTests.swift:230,275,306,318,323`,
  `Tests/NoteStoreReadTests.swift:78,193,200`, `Tests/MarkdownReadingTests.swift:179,188,199,208`,
  `Tests/NoteHistoryTests.swift:305`
- Category: clarity
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `NarrowInputsTests.swift` holds `NoteTab.ChipFace` tests and says so only in its header
  comment; nothing in the name points at the chip, the tab bar or ADR-0096. Separately, a minority
  of `#expect` messages and comments across the slice are in Italian ("premessa: la riga da
  cancellare deve esistere", "il buffer non salvato non è finito nella cronologia") against
  `CLAUDE.md`'s "Code, comments and commits stay in English" — the UI strings they quote are
  correctly Italian, the diagnostics around them are not.
- Trigger: n/a
- Fix: rename the file for what it asserts; translate the diagnostics, keeping quoted UI strings as
  they are.
- Tracked: none

---

### T05-07 — Shared test helpers declared inside one suite's file
- Where: `Tests/PraticaEntryCarryTests.swift:15`, `Tests/OutlineMapTests.swift:13`, `Tests/DiaryControllerTests.swift:8`
- Category: duplicate-support
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `CarryHarness` (9 users), `OutlineOracle` (6 users) and `waitUntil` (10 files) are cross-suite helpers, but each lives in a suite file rather than a `*Support.swift`. ADR-0051 §D2 put shared helpers in support files so they can be found. Today nothing makes them visible, and a new suite is likely to copy them.
- Trigger: n/a
- Fix: move each into its own `*Support.swift`. No behaviour change.
- Tracked: none

### T05-08 — Unconditional `print` in the property suite
- Where: `Tests/OutlineMapPropertyTests.swift:213`, `Tests/OutlineMapPropertyTests.swift:227`, `Tests/OutlineMapPropertyTests.swift:240`, `Tests/OutlineMapPropertyTests.swift:262`, `Tests/OutlineMapPropertyTests.swift:276`
- Category: clarity
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: these lines print summary output on every run, including the Stop-hook run at the end of every turn. The text lands in the xcodebuild log, where it adds noise around real failures.
- Trigger: n/a
- Fix: delete the lines, or attach the text to an `#expect` comment or `Issue.record` so it shows only on failure.
- Tracked: none

### T05-09 — Header names an API the file does not use
- Where: `Tests/PlaudHTTPClientTests.swift:10`, `Tests/PlaudHTTPClientTests.swift:141-145`
- Category: clarity
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: the header says the stub is registered with `URLProtocol.registerClass`, but the code installs it through `configuration.protocolClasses`. That difference matters: `registerClass` is process-global and would leak into other suites, while the per-session path does not.
- Trigger: n/a
- Fix: correct the header to say `protocolClasses`.
- Tracked: none

### T05-10 — UserDefaults suite created and never removed
- Where: `Tests/PraticaRailTokenTests.swift:15-17`
- Category: hygiene
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `isolatedDefaults()` creates `pergamenum.tests.<UUID>` and never calls `removePersistentDomain`. Of the 15 `Tests/` files using that prefix, the 8 that clean up do. In practice this suite writes no plist: `ThemeEngine` persists only through `selection`'s `didSet` (`ThemeEngine.swift:30`), which does not fire inside `init` (`:76`), and the suite never changes the selection. So this is a consistency issue now and a leak waiting for the first test that writes. See the note below for the real leak of this shape.
- Trigger: n/a
- Fix: one shared `IsolatedDefaults` helper (create + `deinit` → `removePersistentDomain`) for all 15 sites.
- Tracked: none

### T08-tests-25 — `droppedWhileBusy` has no assertion
- Where: `Tests/VaultWatcherTests.swift:101`
- Category: assertion-free
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: by design the test is a crash probe: it passes as long as the process survives, and it ends with a bare 400 ms sleep (:118). The doc comment says so. It still counts as a zero-assertion test, and it is the test whose one-off red PG-309 investigated (closed, no defect).
- Trigger: none.
- Fix: optionally assert that at least one round delivered, so the churn is shown to have reached a live stream.
- Tracked: none (PG-309, closed, is about the runner exit, not this)

### T08-tests-26 — identical fixtures within one file
- Where: `Tests/WikilinkClickNavigationTests.swift:277`
- Category: duplicate-support
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `linkedFixture()` (:277) duplicates `wikilinkFixture()` (:251). `VaultSwitchTests`' `vaultB`/`vaultC` are near-identical.
- Trigger: n/a.
- Fix: keep one and parameterise it.
- Tracked: none

### T08-tests-27 — the comment cites an agent-memory file that does not exist
- Where: `Tests/ViewBlockCaretTests.swift:169`
- Category: clarity
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: the comment points to `.claude/agent-memory/coder/topics/pg-099-task6-reveal-supersedes-caret-rescue.md`. No such file exists under `.claude/agent-memory/coder/topics/` (checked with `ls`).
- Trigger: following the reference.
- Fix: cite the ADR or plan section instead.
- Tracked: none

### T08-tests-28 — a theme-token test sits in the board-lifecycle file
- Where: `Tests/WorkspaceLifecycleTests.swift:644`
- Category: clarity
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `bothBundledThemesDefineTheTwoNewStickyColorTokens` checks the token JSON and has nothing to do with board lifecycle.
- Trigger: n/a.
- Fix: move it beside the theme tests.
- Tracked: none

### T08-tests-29 — controllers left attached or vaults left open at the end of a test
- Where: `Tests/WorkspaceLifecycleTests.swift:139`
- Category: hygiene
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: some tests never release what they open:
  - the first controller in `leavingForAFolderOrDetachingLeavesNothingToUndo` is never detached.
  - `WorkspaceEnterFolderTests.swift:236` never detaches its `workspace`.
  - `WeekScaleTests.swift:85-118` never calls `vaultController.close()`.
  - many tests put `detach()`/`close()` after early-return guards instead of in a `defer`, for example `WorkspaceLifecycleTests.swift:507,581,634`.

  The leaked watchers and save tasks outlive the test that made them.
- Trigger: every run, and early returns on a failed setup.
- Fix: `defer { controller.detach(); vault.close() }` immediately after creation, as `WorkspaceDocumentCreationTests` does.
- Tracked: none

### T08-tests-30 — wall-clock "today" and `Calendar.current` in date-sensitive tests
- Where: `Tests/WorkspaceIntegrationWalkTests.swift:121`
- Category: flaky
- Severity: P4 · Confidence: suspected
- In flight: no
- What: `CalendarDate.today` is captured once and compared with due dates that the session computes later. A run that crosses midnight can disagree. `ViewEvaluatorTests.swift:46` uses `Calendar.current.date(from:)`, which hour 12 mitigates.
- Trigger: a run that crosses midnight, or an unusual time zone.
- Fix: inject a fixed day, as `ViewDateBoundTests` does.
- Tracked: none

### X01-15 — The move-conflict alert's message identifier never reaches accessibility
- Where: `Sources/Features/Workspace/WorkspaceBrowser.swift:220`, `Sources/Features/Editor/NoteListPane.swift:125`, `UITests/SidebarMoveUITests.swift:110`
- Category: correctness
- Severity: P4 · Confidence: suspected
- In flight: no
- What: `.accessibilityIdentifier("sidebar-move-conflict")` on the `.alert` message is lost when SwiftUI bridges to `NSAlert`, so `SidebarMoveUITests` matches the sheet by its text. Its own comment says the bug was reported rather than fixed. The only evidence is that comment; the AX tree was not inspected. The ledger has no entry.
- Trigger: VoiceOver or a UI test looking up `sidebar-move-conflict` → nothing.
- Fix: keep only the button identifier, or host the message in a custom sheet. File a ledger entry either way.
- Tracked: none

### X01-16 — Three font tokens below 11 pt
- Where: `Resources/Themes/pergamenum-light.json:122`, `Resources/Themes/pergamenum-light.json:125`, `Resources/Themes/pergamenum-light.json:133`
- Category: house-rules
- Severity: P4 · Confidence: confirmed
- In flight: no
- What: `font.icon.small` is 10 pt, `font.icon.badge` 7 pt and `font.control.label` 9 pt/600, the same in dark. 7 pt is legible only as a glyph badge. Avenir Next is installed on this Mac (`/System/Library/Fonts/Avenir Next.ttc`), and `Theme.swift:52-55` falls back to `Font.system` if it is ever missing, so the prose tokens are safe.
- Trigger: n/a
- Fix: the GUI step should confirm that `control.label` never carries words; if it does, raise it to 10–11 pt.
- Tracked: none
