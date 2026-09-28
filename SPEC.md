Status: Approved (2026-09-26)

# SPEC — Pratiche sync integrity and one post-write door

## Destination

A SPEC handed to `/workplan`. Closes issue #571 (Audit Fable chain 4, `PG-257`) in one PR carrying
two new ADRs: one for a post-write notification from `VaultSession` (ROADMAP Chain 16 item 1,
pulled forward into this chain), one for the nineteen Pratiche sync-integrity defects. Every one of
the nineteen was re-verified present on `main` at 3fcde6f0 (after PR #593).

## Objectives

- A write, move or trash that lands through `VaultSession` reaches every open editor tab showing
  that path, without the caller having to remember a catch-up step. Today twelve call sites
  remember it by hand and at least seven writers (ADR-0058 §D7) plus nine Pratiche writers forget.
- Nothing in the Pratiche feature writes, moves, copies, trashes or restores a note (`.md`) behind
  `VaultSession`'s back, so the index, the journal, the self-write bookkeeping and the tabs always
  see the app's own changes as the app's own.
- A sync never silently destroys what the person added (a message↔note link), never tells them a
  message left Mail when the app simply could not find or resolve it, never overwrites a file it
  could not read, and never loses the outcome of a run because one step failed late.
- «Annulla», «Escludi», «Anteprima allegato», «Apri», the inspector and the settings folder picker
  do what they say, or refuse with a sentence.

## Scope and non-goals

In:
- The post-write notification and the removal of the explicit catch-up calls it replaces.
- ROADMAP §Chain 4 items 1–19, with the two corrections found at verification (item 9: the
  engine already has its own cancellation flag; item 18: the correctly-fixed twin lives in the
  Pratiche command actions, not in the add-to-pratica sheet).
- The wider shape behind item 2: every raw move, copy, trash and restore of a message note in the
  Pratiche file operations.

Out (detail below): board catch-up through the hook; binary attachment and `.eml` copies/writes
routed through the session; the note-rename/move performers outside Pratiche beyond what the hook
changes; the §D13 residuals of chain 1.

## Decisions

- **One PR, two ADRs.** The post-write door is cross-cutting (it touches writers far outside
  Pratiche and extends ADR-0058 §D7); the Pratiche integrity work extends ADR-0036/0040/0049/0052.
  Each ADR reads on its own. Rejected: one ADR with two parts — a decision about every writer in
  the app would be buried in a Pratiche document. Rejected: no new ADR — nineteen decisions with no
  single place to read them.
- **All nineteen items are in scope.** They share files and a root cause; chain 1 closed
  seventeen edges in one chain. Rejected: only 1–13 (data/state loss), or only 1–11.
- **The post-write notification is pulled into this chain** instead of fixing item 2 locally and
  leaving Chain 16 item 1 for later. Chosen by the user. Rejected: local fix only — it would close
  item 2 and leave the same "caller forgets the catch-up" shape in sixteen other writers.
- **The hook is the only door.** The explicit `syncOpenNote(with:)` calls (twelve sites) and the
  manual `movedNote`/`trashedNote` calls (six sites) are removed; their behaviour becomes the
  hook's handler. Rejected: keep the explicit calls beside the hook — a step a caller can forget
  is the failure ADR-0041's working agreement names.
- **The hook covers write, move and trash; not the `.canvas` door.** No editor tab shows a
  `.canvas` file, and boards have their own origin/conflict model (ADR-0054). Rejected: text
  writes only — the Pratiche moves routed through `moveFile` would then still need a manual
  follow-up call, the shape this chain removes.
- **The editor's own save keeps ADR-0058 §D3.** The tab that saved adopts only its saved text and
  keeps whatever was typed during the suspension; it never receives a conflict prompt for its own
  write. Every other tab showing the path gets ADR-0058 §D1's rule. Measured: a generic catch-up
  applied to the writer after the save raises a false prompt whenever text was typed during the
  suspension (ADR-0058 acceptance test 12).
- **Nothing is notified for a rehearsal.** A dry-run write lands nothing, so it notifies nothing.
- **The connectors are unaffected.** `perg` and `pergamenum-mcp` construct the session with no
  subscriber; the door exists in the shared session and does nothing there.
- **Item 2 widens to every raw note operation in the Pratiche file operations.** The two raw text
  rewrites go through the session's guarded write; the moves (including the move back on undo)
  through the session's move door; the trash through the session's trash door; a copy of a
  message note through a write that expects the destination absent. Chosen because, since
  ADR-0064, the watcher reads a raw move as an external deletion and closes the tab. Rejected:
  file the raw moves as a separate issue.
- **Restoring a pratica file from the Finder Trash gets a session door.** None exists today; the
  only restore in the codebase is a raw move. The door moves a file from outside the vault to a
  path inside it that must be absent, records it as the session's own, updates the index and
  notifies. It is not journalled, like the trash it undoes.
- **Item 5 (Mail file lookup): three outcomes, and an explicit notice.** Found, absent, or
  indeterminate (search budget exhausted, a folder unreadable). Only absent becomes "not in Mail".
  Indeterminate records no marker, leaves the message pending for the next sync, and shows one
  sentence in the pane. Chosen by the user. Rejected: silent retry.
- **Item 4: "no longer in Mail" is reversible.** A row the index cannot resolve falls back to the
  ledger's recorded row, as the pending retry already does; and the marker clears when the message
  is seen again, whether or not it is re-imported.
- **Item 11: a failed quarantine keeps the file and blocks direct opening.** The failure is a
  recorded problem, the run continues and records its outcome. Opening an attachment that lacks
  the quarantine attribute first tries to apply it (this also covers attachments placed before
  PG-123); if that fails, «Apri» refuses with a sentence and offers «Mostra nel Finder». Chosen by
  the user. Rejected: open normally (drops PG-123's guarantee); refuse every file without the
  attribute (breaks every pre-PG-123 attachment); delete the file and stay pending (the attachment
  never arrives on such a volume).
- **Item 13: «Escludi» records first, trashes second.** If the dossier cannot be read or the write
  is refused, nothing goes to the Trash and the person sees the problem. Rejected: trash anyway
  and report.
- **Item 14: the pane's appearance triggers a throttled sync.** The unthrottled open-vault trigger
  is reserved for actually opening a vault. The activation observer is removed when the vault
  closes and holds the vault weakly. Rejected: no sync on appearance.
- **Item 15: the inspector reloads on any landed write to the selected `pratica.md`,** driven by
  the same post-write door (an observable per-path write generation), not by a Pratiche-specific
  signal.
- **Item 17: the Pratiche folder must be a strict subfolder of the vault.** The relative path is
  computed through the vault boundary; the vault root itself or a folder outside it is refused
  with a sentence and the previous setting is kept. Rejected: allow the root (every top-level
  folder would become a pratica candidate).
- **Item 16: one predicate decides both whether «Anteprima allegato» is offered and what it
  opens,** through the attachment chip's own preview URL (ADR-0023's shape).
- **Items 7, 8, 18: state read before an `await` is re-read or enforced after it** (CLAUDE.md
  working agreement "a precondition evaluated before an `await` is a filter"): the wizard writes
  expecting the file absent; the sync-all loop re-reads each pratica after each suspension; the
  add-to-pratica flow re-reads its target after the write.
- **Item 12: the regeneration engine is released when its sheet closes, and a permission failure
  copying Mail's index is classified apart from "Mail is writing"** and points to Full Disk
  Access, not to quitting Mail.
- **Item 19: consecutive preparation problems are joined, not overwritten.**

## Constraints

- **Principle 1 and 3 (file over app, rebuildable index)** — origin: `CLAUDE.md`. No new on-disk
  format, no new frontmatter key, no index schema bump.
- **Every protected interface untouched** (`Dossier.render`, `VaultAPI.PraticaSummary`,
  `PraticaNaming.messageFileName`, `MessageDocument.isPendingAttachmentEntry`,
  `VaultBoundary.url(for:)`, …) — origin: `.claude/protected-interfaces`, ADR-0036/0040/0063.
- **ADR-0058 §D1 and §D3 hold** (per-buffer catch-up rule; the writer keeps text typed during its
  own save) — origin: ADR-0058.
- **ADR-0052's one ledger write door and ADR-0036 §D21's "the diff shown is the bytes written"
  hold** — origin: ADR-0052, ADR-0036.
- **Sync never deletes a file; a corrupt attachment goes to the Trash** — origin: ADR-0036 §D6,
  ADR-0040.
- **At most two or three GUI tests per feature, each justified in the ADR** — origin: `CLAUDE.md`
  merge-gate rule. This chain adds none.
- **The connectors build and behave unchanged** — origin: ADR-0007.

## Stack

Swift 6 strict concurrency, SwiftUI/AppKit, Swift Testing. No new dependency.

## Data model

No change on disk. In memory:
- The session gains a subscriber for landed changes, carrying one of: text written at a path;
  a path moved from → to; a path trashed. Rehearsals produce none.
- The session exposes an observable per-path write generation (item 15).
- The Mail-file lookup result becomes three cases: found, absent, indeterminate (with the reason).

## API / interfaces

- `VaultSession`: the post-write subscription; a restore-from-outside door (absent-destination
  precondition, not journalled); write/move/trash notify on landing.
- `VaultController`: subscribes on open, unsubscribes on close; `syncOpenNote(with:)` disappears
  as a public step; the save path keeps its writer-by-id rule.
- The Pratiche file operations become asynchronous where they now go through the session.
- Connector JSON shapes unchanged.

## UI flows

- «Annulla» during the Mail-index publication phase stops the run before the engine starts.
- «Apri» on an attachment without quarantine that cannot receive it: a refusal sentence plus
  «Mostra nel Finder».
- Settings, Pratiche folder: choosing the vault root or an outside folder shows a refusal sentence;
  the field keeps the previous value.
- Pratiche pane: one sentence when a message's Mail file could not be located this time
  (indeterminate), distinct from «Non più in Mail».
- Permission failure on Mail's index: the sentence points to Full Disk Access.

## Edge cases

- The writer tab types during its own save: no prompt, typed text stays unsaved (ADR-0058 R-12).
- A write that lands while another tab on the same path is dirty: that tab gets the ADR-0001 §D3.4
  prompt, not a silent overwrite.
- A hook fires and the watcher later reports the same write: dropped as self-written, no double
  report. A trash still reaches the tab through both paths and closes it once.
- Undo of «Sposta in…» with chained attachment renames (`q→q-2`, `q-2→q-3`): all inverted renames
  applied in one pass; every attachment stays reachable.
- A message whose body was pending and has a linked note: the body arrives, the link survives.
- An unreadable or evicted `.md` in a pratica's email folder: its name stays reserved; an import
  with the same stem gets a new name; nothing is overwritten.
- A quarantine failure mid-run: every message decoded before it keeps its imported status.
- The line-4 patch equal to disk (the normal path for an unresolvable pending attachment): the
  ledger's row bridge is still recorded.
- A pratica archived during a sync-all pass: it is not synced and its watcher records nothing.
- A Pratiche restore whose original path is now taken: refused, file stays in the Trash, problem
  shown.

## Test seams

Existing seams, one per layer, zero GUI tests:
- Post-write door and tab behaviour: the controller write catch-up suite (both columns, writer by
  id), extended.
- Sync engine (items 1, 4, 6, 10, 11): the Pratiche sync suites over the synthetic Mail store
  fixture (the fixture can already drop the table that forces "not resolvable from index"); the
  quarantine step made injectable.
- Pratiche file operations (items 2, 3, moves/copy/trash/restore): a new file-operations suite on
  the temporary-vault + real controller harness the note-id follow tests already use.
- Pratiche controller (items 8, 9, 14, 15, 19): the controller suite with its injected sync
  closure; item 15 checked on the observable write generation, not on the view.
- Pure units (items 5, 12, 16, 17): a new Mail-file locator suite with an injectable budget; the
  Mail-store reader suite; the command catalogue suite; the settings suite on an extracted
  relative-path function.
- Item 7: the absent-precondition write suite plus an extracted create helper.

## Success criteria

- [ ] R-01 — A text write through the session reaches every tab showing the path in every column,
  per ADR-0058 §D1, with no explicit catch-up call at the writer.
- [ ] R-02 — The tab that saved never receives a conflict prompt for its own save; text typed
  during the save stays unsaved (ADR-0058 R-12 still green).
- [ ] R-03 — A move through the session re-points every tab showing the old path; a trash closes
  clean tabs and prompts dirty ones — with no manual follow-up call anywhere.
- [ ] R-04 — No `syncOpenNote(with:)` call, and no manual `movedNote`/`trashedNote` call, remains
  outside the hook's handler.
- [ ] R-05 — A rehearsal (dry run) notifies nothing; `perg` and `pergamenum-mcp` build and their
  tests pass unchanged.
- [ ] R-06 — Each of the seven ADR-0058 §D7 writers, and a Pratiche link write, now catches up an
  open tab of the note it wrote (one test per writer family).
- [ ] R-07 — Item 1: a message with a linked note whose pending body arrives (and one whose store
  references change) keeps `pergamenum-mail-note` after the sync.
- [ ] R-08 — Item 2 + widening: after «Sposta in…», copy, «Escludi», and restore, every `.md`
  change was made through the session: index updated, a failure reported (never swallowed), and
  an open tab follows the move. Move, copy and restore are recorded as self-written; «Escludi»'s
  trash still reaches the watcher as `.deleted` (ADR-0064 §D6).
- [ ] R-09 — Item 3: undo of «Sposta in…» with chained attachment renames leaves every attachment
  link pointing at an existing file.
- [ ] R-10 — Item 4: a followed message the index cannot resolve but the ledger can is not marked
  «Non più in Mail»; a marked message seen again loses the marker.
- [ ] R-11 — Item 5: budget exhaustion and an unreadable folder yield "indeterminate", record no
  marker, leave the message pending, and surface one sentence; only a genuine miss yields "not in
  Mail".
- [ ] R-12 — Item 6: an unreadable `.md` reserves its name; a same-stem import takes a new name and
  the unreadable file's bytes are unchanged.
- [ ] R-13 — Item 7: creating a pratica over a path created during the wizard's suspension is
  refused, not overwritten.
- [ ] R-14 — Item 8: a pratica archived mid sync-all is not synced and its watcher records nothing.
- [ ] R-15 — Item 9: «Annulla» during the publication phase stops the run before the engine
  starts.
- [ ] R-16 — Item 10: the row bridge is recorded on every early exit of the line-4 patch.
- [ ] R-17 — Item 11: a quarantine failure is a recorded problem, the run completes and records
  every earlier message as imported; «Apri» applies the attribute when missing and refuses with
  «Mostra nel Finder» when it cannot.
- [ ] R-18 — Item 12: closing the regeneration sheet releases the engine; a permission failure
  copying Mail's index is reported as a Full Disk Access problem, not "Mail is writing".
- [ ] R-19 — Item 13: when the dossier cannot be parsed or written, «Escludi» trashes nothing and
  reports the problem.
- [ ] R-20 — Item 14: two pane appearances within the throttle window trigger one sync; closing the
  vault removes the activation observer and releases the vault.
- [ ] R-21 — Item 15: a landed write to the selected `pratica.md` («Nota», «Chiudi»/«Riapri»)
  advances the write generation the inspector reloads on.
- [ ] R-22 — Item 16: «Anteprima allegato» is offered exactly when it can open something, and
  opens the chip's preview URL.
- [ ] R-23 — Item 17: a strict subfolder is stored relative; the vault root and an outside folder
  are refused and the setting is unchanged.
- [ ] R-24 — Item 18: adding to a pratica re-reads its target after the write.
- [ ] R-25 — Item 19: two consecutive preparation problems are both shown.
- [ ] R-26 — (no-test: documentation obligation) Two ADRs (next free numbers at merge time)
  record the decisions above; the ROADMAP §Chain 4 corrections (items 9 and 18) and Chain 16
  item 1 are marked as absorbed; `CLAUDE.md`'s chain index gains both entries.

## Not yet specified

_none_

## Out of scope

- **Board catch-up through the hook** — boards have their own origin/conflict model (ADR-0054) and
  no editor tab shows a `.canvas`; the quit-flush gap for boards is #506, chain 2's.
- **Binary attachment and `.eml` writes/copies through the session** — the watcher ignores
  non-`.md` files, the index does not hold them, and the session has no byte door; adding one is a
  separate decision.
- **Note rename/move performers outside Pratiche** — they already go through the session; they
  change here only in that their manual follow-up calls become the hook.
- **Chain 1 residuals (§D13) and the three sub-threshold findings of the #593 review** — tracked
  by the chain 1 session.

## Domain terms

- **Landed change** — a write, move, trash or restore that the session actually performed on disk
  (not a rehearsal, not refused).
- **Indeterminate (Mail file lookup)** — the app could not decide whether the message's file is in
  Mail's store (budget exhausted or folder unreadable); distinct from absent.
