# Pergamenum roadmap

Source: full read-only audit of `main` @ `0d6f34a`, 2026-09-25 (616 Swift files, 102k lines).
Method: four parallel code-reading passes (removed-feature residues; Core/Vault/Connector bugs;
Features/App bugs; GUI, menus and formatting), Periphery 3.8 on the `Pergamenum` scheme, SwiftLint,
and a hand re-check of the highest-severity findings in the source. Nothing was modified.

Every finding already tracked in `TODO.md` at audit time was excluded, so this file adds to the
ledger rather than repeating it. Items are grouped into **chains**: sets of findings that share a
root cause, a subsystem or a pattern, and can be fixed under one SPEC/ADR and one PR. Chains are
listed in priority order. Inside a chain, items are ordered by severity.

How to read an item:

- **Where**: `file:line` at `0d6f34a`.
- **What / Why**: the defect, and the scenario that triggers it (concrete input → wrong result).
- **Fix**: the shape of the fix as far as the audit could see it. Not a plan; the chain's own
  `/workplan` decides.
- **Confidence**: `confirmed` (the path was traced in the source, and for items marked `*` also
  re-checked by hand), `suspected` (the shape is present, the trigger was not reproduced).

Part 2 at the end is the short schedule.

---

## Part 1 — Chains in priority order

### Chain 1 — Format-edge hardening (P1, data loss on ordinary input)

**Shipped** as ADR-0064 (`docs/adr/0064-format-round-trip-faithful-or-refused.md`), branch
`fix/chain-1-format-edge-hardening`, PR #TBD. It closes all 17 items below. Item 17 needed no code
change: Swift's `String` comparison already equates NFD and NFC, and regression tests now pin that
(ADR-0064 §D10). The residuals the chain found and did not fix are in ADR-0064 §D13 and are filed
separately.

Root cause: the parsers for the on-disk formats were written for the happy path and lose or
corrupt data on inputs that are legitimate in this vault's own life (a note synced from Windows,
a `.canvas` written by another tool, an Exchange mail). Every item is silent: no error, no report.
One ADR ("the round-trip of every on-disk format is faithful or refused"), fixtures per case,
table-driven tests. This chain is first because principle 1 (file over app) is exactly what it
protects.

1. **CRLF or BOM note gets a second frontmatter block prepended.** `confirmed*`
   Where: `Sources/Core/Conventions/Frontmatter.swift:148-151`.
   What: `parse` splits on `"\n"` and trims `.whitespaces`, which does not contain `\r`. A CRLF
   file's first line is `"---\r"`, the guard fails, the document reads as `hasFrontmatterBlock:
   false` with the whole file as body. The next `serialized()` (`:171`) prepends an empty
   `---\n---\n` block in front of everything, original frontmatter included. A BOM does the same.
   Why it matters: a note synced from Obsidian on Windows gets two frontmatter blocks the first
   time «Collega» or a category change runs on it.
   Fix: split on newlines with `\r\n` handling (or `.newlines`), strip a BOM, and add a fixture.

2. **Unparsable tags are read, held in memory and dropped on write.** `confirmed`
   Where: `Frontmatter.swift:203-206` (populates `unparsableTags`) vs `:290-292` (`render` writes
   `frontmatter.tags` only).
   What: `cliente-acme` is not a `TagNamespace` (`Vocabulary.swift:56-64`), lands in
   `unparsableTags`, and never comes back out. One in-app write and the tag no longer exists on
   disk. The file's own header says a foreign key is preserved "or the next save would destroy
   data the user put there"; the same rule was not applied to tags.
   Fix: `render` re-emits `unparsableTags` verbatim after the valid ones.

3. **Any frontmatter line without a colon is deleted on rewrite; duplicate keys lose the first.**
   `confirmed`
   Where: `Frontmatter.swift:183-186`, `:220-224` (`isContinuation`).
   What: a YAML comment at column 0 (`# importato da Plaud`) is neither a key nor a continuation,
   so it is skipped and cannot be re-rendered. `switch key` assigns rather than merges, so a
   duplicated `tags:` keeps the last block only, while a duplicated foreign key is written twice.
   Fix: keep an ordered list of raw lines the parser does not understand and re-emit them in place.

4. **JSON Canvas drops payload keys of unknown node types, unknown colours, and nodes without
   `id`/`type`.** `confirmed`
   Where: `Sources/Core/Canvas/JSONCanvas.swift:52` (`compactMap`), `:83-92` (`CanvasColor.init?`),
   `:192-193` (`consumed` set), `:215-217` (`case .unknown: break`).
   What: `{"type":"embed","url":"…"}` reads as `.unknown(type: "embed")` with `url` filtered out,
   so the first save rewrites the node without its `url`. A colour the enum rejects is omitted. A
   node missing `id` is dropped from the file. The header promises "carries everything else
   through untouched".
   Fix: for `.unknown`, keep the whole raw object; keep an unrecognised colour as a raw string;
   refuse to save a document whose parse dropped nodes (or keep them as opaque).

5. **`CanvasDocument.reconcile` traps on duplicate node or edge ids.** `confirmed*`
   Where: `Sources/Core/Canvas/CanvasReconciliation.swift:38-39`, `:62-63`.
   What: `Dictionary(uniqueKeysWithValues:)` over `base.nodes`/`theirs.nodes`; `CanvasDocument.
   init(data:)` never checks id uniqueness. A `.canvas` with two nodes sharing an id opens fine,
   then the first ADR-0054 write refusal — the path that exists to protect data — reaches
   `reconcile` and the app dies with "Duplicate values for key", losing the pending autosave.
   Fix: `Dictionary(_:uniquingKeysWith:)` plus a `reasons` entry; ideally reject duplicates at
   parse time with a visible problem.

6. **`HTMLTextReducer.finished()` discards everything after an unclosed `<a>` or `<td>`.**
   `confirmed`
   Where: `Sources/Core/Email/HTMLTextReducer.swift:207-219`.
   What: `open("a")`/`open("td")` push a buffer, only `close` pops, `finished()` reads
   `buffers[0]` alone. An HTML mail with `<a href="…">Preventivo` and no `</a>` (routine in
   malformed signatures and truncated bodies) writes a message file in `pratiche/` truncated at
   that point.
   Fix: drain the stack (`while buffers.count > 1`) before reading `buffers[0]`.

7. **ISO-8859-15 decoded as ISO-8859-2.** `confirmed*`
   Where: `Sources/Core/Email/MIMEDecoder.swift:290`, `EmailHeaders.swift:218`.
   What: `.isoLatin2` is Central European, not Latin-9; the tables differ in eight positions, all
   Western. `1.250,00 €` (byte `0xA4`) imports as `1.250,00 ¤`. The string decodes cleanly, just
   wrongly, so no fallback fires.
   Fix: `String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(
   CFStringEncodings.isoLatin9.rawValue)))`.

8. **RFC 2047: whitespace between adjacent encoded-words is copied into the subject and hence the
   file name.** `confirmed`
   Where: `EmailHeaders.swift:154-166`; `EmailHeaderParser.parse:76` unfolds continuation lines
   with `" " + trimmed`, making the adjacent pair the common case.
   What: a folded subject decodes as `Preventivo fornitura artic oli tecnici in gomma` and reaches
   `pergamenum-mail-subject` and, through `PraticaNaming.messageFileName`, the file name on disk.
   Related: `Data(base64Encoded:)` at `:182` without `.ignoreUnknownCharacters` shows a
   non-canonically padded B-word raw.
   Fix: drop linear whitespace between two consecutive encoded-words per §6.2.

9. **RFC 2231 attachment file names not handled; `;` split ignores quotes.** `confirmed`
   Where: `MIMEDecoder.swift:191-203`.
   What: `filename*=UTF-8''…` yields `filename == nil`, so `AttachmentIntegrity.format(declaredAs:
   named:)` has no extension and skips the signature check. `filename="Report; finale.pdf"` is
   truncated at the semicolon.
   Fix: a small parameter parser honouring quotes and `*=` continuations.

10. **`MessageDocument` escape/unescape order is inverted.** `confirmed`
    Where: `Sources/Core/Pratiche/MessageDocument.swift:216-223` (write: `\`→`\\` then
    newline→`\n`) vs `MessageDocument+Reading.swift:141-147` (read: `\n`→newline before `\\`→`\`).
    What: a subject containing `C:\nuovo` does not round-trip, producing a phantom diff for the
    R-08 dedup comparison.
    Fix: unescape in the reverse order of escaping.

11. **`pergamenum-mail-date` uses `.current` timezone.** `confirmed`
    Where: `MessageDocument.swift:231-236`.
    What: the comment says "the zone the message was sent in"; the code uses the machine's. A
    «Rigenera» across a DST change rewrites every message file of a pratica with a different
    offset, against ADR-0036 §D21's diff-stability guarantee.
    Fix: format with the message's own offset, or pin UTC.

12. **`displayText` corrupts a task line when one tag is a prefix of another.** `confirmed`
    Where: `Sources/Core/Tasks/TaskParser.swift:259-263`.
    What: `replacingOccurrences` removes every occurrence in first-seen order. `- [ ] Rivedere
    offerta #topic-forni e #topic-forni-tunnel` renders as "Rivedere offerta e -tunnel" in every
    task view and in connector output. Disk is untouched.
    Fix: remove by ranges from the parse, or sort longest-first with word-boundary matching.

13. **`![[foto.png]]` leaves an orphan `!` in inline rendering.** `confirmed`
    Where: `Sources/Core/Markdown/MarkdownInline.swift:69`, `:78-79`.
    What: `wikilink(at:)` requires a leading `[[`, `link(at:)` drops the `!` and fails on the
    missing `(`, so `!` is emitted as text and the embed parsed as a wikilink. A heading
    `## ![[schema.png]]` shows as `!schema.png` in the outline.
    Fix: recognise `![[` as an embed token before the two fallbacks.

14. **Related-section detection is not anchored to a line start.** `confirmed`
    Where: `Sources/Core/Conventions/NoteExport.swift:19`, `Wikilink.swift:212`.
    What: `body.range(of: RelatedSection.heading)` finds `## Note correlate` inside `### Note
    correlate operative` and inside a mid-sentence mention. Export then deletes from there to the
    next `#` line; the linter counts a sub-heading's bullets as the structural section and invents
    W-06 discrepancies.
    Fix: match `^## Note correlate$` per line.

15. **A bold wikilink resolves for navigation but is not rewritten by rename.** `confirmed`
    Where: `Sources/Core/Conventions/NoteRename.swift:30` vs `Wikilink.swift:29-38`
    (`resolvedTitle`).
    What: rename filters on `target` (literal bracket contents) while everything else uses
    `resolvedTitle`, which strips emphasis. `[[**Forno tunnel**]]` backlinks fine and becomes a
    dead link after a rename, with "0 link riscritti" reported.
    Fix: rename matches on `resolvedTitle` and rewrites inside the emphasis markers.

16. **`NoteStore+ReadSurface.swift:30-33` admits `[[Q4.canvas]]` from an ADR-0021 `^[[…]]` marker
    into `linkTargets`**, so a board appears as a backlink target; `Transclusion.isNoteReference`
    also returns `true` for any extension longer than five characters (`else { return true }`).
    `confirmed`. Fix: exclude `.canvas` targets from note link targets; make the extension test
    explicit.

17. **Unicode normalisation in board/note resolvers.** `suspected`
    Where: `WorkspaceBoardResolver.swift:36-38, 46-48`, `NoteRename.fold:72-74`,
    `Transclusion.normalised:177-179`.
    What: comparisons use `lowercased()` only. A `.canvas` stored NFD (HFS+ backup, foreign zip)
    never matches an NFC-typed `^[[Città.canvas]]`, and «Vai alla board» silently does nothing.
    Fix: `precomposedStringWithCanonicalMapping` in every fold.

Acceptance for the chain: a fixture corpus (CRLF note, BOM note, note with YAML comment and
duplicate key, canvas with `embed`/duplicate id/unknown colour, ISO-8859-15 mail, RFC 2047
folded subject, RFC 2231 filename, unclosed `<a>`) round-trips byte-identical or is refused with a
recorded problem. Never a silent drop.

---

### Chain 2 — Workspace board lifecycle (P1, data loss)

Root cause: `WorkspaceController` resets some state on `attach`/`detach`/`load(board:)` and not
the rest; the editing ids, the deferred save and the deferred refit outlive the board they belong
to. The `foldedHeadings` comment already states the rule ("a table keyed by node id would
otherwise outlive the board"). One ADR extending ADR-0054/0060: "every per-board state has one
reset door, and every leave path flushes".

1. **`detach()` discards a just-confirmed crop.** `confirmed*`
   Where: `Sources/Features/Workspace/WorkspaceController.swift:230-257`.
   What: `detach` calls `endCrop(confirm: true)` (which only schedules a ~1 s deferred save), then
   `saveTask?.cancel()` at `:244` and replaces the document at `:252`, never calling
   `flushPendingSave()` — the first line of `flushBoard()` (`:320`, `:378`) and of every folder
   verb. Crop, press Return, close or switch vault within a second: `pergamenum-crop` never lands.
   Fix: `flushPendingSave()` before cancelling in `detach`.

2. **Inline editing state survives a board switch.** `confirmed`
   Where: `WorkspaceController.swift:171-172, 637, 647, 669`.
   What: `attach`, `detach`, `load(board:)` reset `document`, `origin`, `selection`, `history`,
   `foldedHeadings`, `pan`, `zoom`, but none of `editingTextNodeID`, `editingTextDraft`,
   `editingTitleNodeID`, `editingTitleDraft`, `editingDrawingNodeID`, `activeDrawing`. Draw on
   board A, switch to B without «Fatto»: `commitDrawing` writes the SVG into B's folder. A live
   `editingTextNodeID` also permanently disables every single-letter tool key with no card in edit.
   Fix: one `resetTransientEditing()` called from all three doors.

3. **`beginTextEdit` does not close an open title edit; `delete(nodeIDs:)` leaves editing ids
   pointing at deleted nodes.** `confirmed`
   Where: `WorkspaceController+TextEditing.swift:11-18` vs `:32-43`; `WorkspaceController+Nodes.
   swift:133`.
   What: rename a link card, then click into a sticky: the title draft is never committed and the
   rename is lost. Deleting a node in edit leaves `editingTitleNodeID`/`croppingNodeID`/
   `editingDrawingNodeID` set.
   Fix: same `resetTransientEditing()`; `beginTextEdit` commits a title edit first, mirroring
   `beginTitleEdit`.

4. **Single-letter tool keys eat typing in a link card's title field.** `confirmed`
   Where: `BoardChrome.swift:131-136` with `NodeCard.swift:173-191`.
   What: bare-key suspension checks `editingTextNodeID == nil` only. Rename a link card and type
   "video": `v` switches to the selection tool, `d` opens drawing.
   Fix: suspend on any of the editing ids (`isEditingAnything` computed property).

5. **`subfolder(for:)` bypasses `VaultBoundary`.** `confirmed`
   Where: `WorkspaceController+Files.swift:94-102`, used by `+Drawing.swift:50, 92`.
   What: `store.root.appending(path:)` two lines below a correct `store.boundary.url(for:)`. A
   `.canvas` node with `file: ../../altro` (hand-written, synced, merged) resolves outside the
   vault and the drawing SVG is read and written there. PG-122 fixed line 12 of the same file.
   Fix: route through the resolver.

6. **`zoomToFit` does not fire for a second board in the same folder.** `confirmed`
   Where: `WorkspaceView.swift:334-337`.
   What: the refit hangs off `.onChange(of: workspace.folder)`; since ADR-0025 a board is addressed
   by its own path, so two boards in one folder produce no change. `load(board:)` has already
   reset `pan`/`zoom`, so a board with cards at x 3000 opens on an empty viewport.
   Fix: key the refit on the board path (or on `origin`).

7. **`detach()` cancels `saveTask` but not `refitTask`.** `confirmed`
   Where: `WorkspaceController+Viewport.swift:111-126`.
   What: a deferred refit can run after `replaceDocument(.empty, …)` and set `pan`/`zoom` from
   an empty document.
   Fix: cancel both.

8. **Import of two same-named files in one drop can overwrite.** `suspected`
   Where: `WorkspaceController+Import.swift:14-48`.
   What: `ImportNaming.uniqueFileName` is asked per file against disk state without accumulating
   the names minted earlier in the same loop.
   Fix: pass the reserved set through the loop.

9. **Two pre-`await` reads in folder verbs and creation.** `suspected`
   Where: `WorkspaceView+FolderVerbs.swift:39-62`, `WorkspaceView+Creation.swift:60-87`.
   What: `flushBoard()`/`canLeaveOpenBoardForVerb()` run before `await vault.moveItems`, then
   `workspace.board` is read after; a note created while another board is opened lands on the
   wrong board (`workspace.folder` read before `await vault.createNote`).
   Fix: re-read after the suspension (ADR-0043 §D7 shape).

10. **Sticky colour menu offers six colours over five tokens.** `confirmed`
    Where: `StickyTextCard.swift:127-142`, `BoardContentLayer.swift:277`, `TokenKeys.swift:69-73`.
    What: `stickyColor` maps 1 and 2 both to `.stickyPink`, 6 to the grey default. Red and orange
    are indistinguishable, purple draws grey.
    Fix: one token per menu entry (add `sticky.orange`/`sticky.purple`) or five menu entries.

11. **`ViewBoardRenderer` accepts any dropped plain text as a payload.** `suspected`
    Where: `ViewBoardRenderer.swift:239-241`, `BoardDragPayload.init?(text:)` `:209-215`.
    What: without the `\u{1}` separator the whole string becomes `path`; a word dragged from
    Safari reaches `queries.move(<text>, nil, tag)`.
    Fix: require the separator; use a custom UTType.

Also in scope, already tracked: `#506` (no terminate hook for the autosave debounce) is the same
family and should ship in this chain.

---

### Chain 3 — Connector input hardening (P1, small, one afternoon)

Root cause: `perg` and `pergamenum-mcp` trust the shape of what they receive. Every item is a
few lines; the chain exists so they ship together with tests in `scripts/mcp-smoke.py`.

1. **Negative `limit`/`cursor` trap the process.** `confirmed*`
   Where: `Sources/Connector/VaultWrites.swift:340` (`.suffix(limit ?? 20)`), `Sources/MCPServer/
   VaultHost.swift:276-283` (`notes[start..<end]`).
   What: `perg journal list --limit -1` kills the CLI; `{"cursor": "-1"}` kills the MCP server
   mid-session.
   Fix: clamp to `0...`, reject with a `ConnectorError` sentence.

2. **A value-taking flag eats the next flag.** `confirmed*`
   Where: `Sources/Connector/Arguments.swift:65-67`.
   What: `options[body] = raw[index]` consumes the following token unconditionally. `perg note
   new Titolo --folder --dry-run` performs a real write into a folder named `--dry-run`. The
   safety flag is the one most likely to be mistyped.
   Fix: a token starting with `--` is never a value; throw `missingValue`.

3. **`createAndLinkPraticaBoard` bypasses the dry-run lock and the journal.** `confirmed*`
   Where: `Sources/Connector/VaultPraticheLinks.swift:290`.
   What: calls `CanvasStore(root:).createBoard` directly, so `isDryRun` never sees it and `undo`
   cannot remove it. With MCP's `dryRun` at its default `true` the board is still created.
   Fix: route board creation through a `VaultSession` door that honours `isDryRun` and journals.

4. **`FileManager` calls that bypass `VaultBoundary`** (defence in depth, all currently gated
   upstream). `suspected`
   Where: `VaultSession+Notes.swift:99-110` (`importFile`), `CanvasStore.swift:293-301`
   (`createFolder`), `FolderFileOperations.swift:387/392/440`, `Connector/VaultPratiche.swift:187`,
   `Core/Conventions/Attachment.swift:99`.
   Fix: resolve through `VaultBoundary.url(for:)`; add the `.claude/protected-interfaces` entry
   PG-151 asks for.

---

### Chain 4 — Pratiche sync integrity (P1/P2)

Root cause: three writers in the Pratiche feature go around `VaultSession` or around the
carry-over that keeps ADR-0049 links alive, and several ledger/outcome paths throw away state on
their early exits. Extends ADR-0036/0040/0049/0052.

1. **An automatic re-render destroys `pergamenum-mail-note`.** `confirmed`
   Where: `PraticaSyncEngine+Messages.swift:822-826`, `:884`; `carryingOverLinkedNote` (`:670`) is
   called only from `regenerationPreview` (`:737`).
   What: the other two full-render conditions (a `.pending` body resolving, a `storeReferences`
   change) rewrite `prepared.noteText` from Mail alone. Link a note to an Exchange message whose
   body is pending; the next sync downloads the body and the link vanishes from timeline,
   inspector and `VaultPraticheLinks`.
   Fix: apply `carryingOverLinkedNote` on every full render.

2. **Post-move content rewrites bypass `VaultSession`.** `confirmed`
   Where: `PraticaFileOperations.swift:270-277`, `+Attachments.swift:95-112`.
   What: both end in `try? text.write(to:atomically:encoding:)`, which `DossierWriter.swift:10-13`
   declares must never happen. No `expecting:`, no index update, no `selfWrittenHashes` entry (so
   the watcher reports the app's own write as external and raises the ADR-0001 §D3.4 prompt on a
   dirty tab), and `try?` swallows failure so `moveFiles` reports success while
   `pergamenum-mail-original` names a missing `.eml`.
   Fix: `VaultSession.write(..., expecting:)`.

3. **Undo of «Sposta in…» rewrites attachment links one rename at a time.** `confirmed`
   Where: `PraticaFileOperations.swift:205-207` → `renameAttachmentReference` → `applyAttachment
   Renames([one])`; the function's own comment (`:88-94`) forbids exactly this.
   What: with `q.pdf→q-2.pdf` and `q-2.pdf→q-3.pdf` applied in the wrong order the second pass
   rewrites both tokens to `[[q.pdf]]`; one attachment becomes unreachable.
   Fix: one call with all inverted renames.

4. **`noLongerInMail` permanently marks rows the index cannot resolve.** `confirmed`
   Where: `PraticaSyncEngine.swift:206-212`; `MailStoreReader.swift:26-28` measures
   `.notResolvableFromIndex` at 3.1%; `+Ledger.swift:320-323` removes the marker only for ids in
   `importedMessageIDs`, which for a message already on disk never happens.
   What: 3% of followed messages are eventually told "Non più in Mail", irreversibly. Twenty lines
   away `regeneratePending` (`+Messages.swift:938-947`) falls back to `request.ledgerEntries`.
   Fix: same fallback; make the marker clearable when the message is seen again.

5. **`EMLXLocator` collapses budget-exhausted and unreadable into "not in store".** `confirmed`
   Where: `Sources/Core/Email/EMLXLocator.swift:60-72`, `:100-117`.
   What: `enumerate` returns `nil` for three causes; the caller maps all to `.notInStore` when
   `Data/` exists. The header says these "must never be confused". On a large mailbox the user is
   told a message that is in Mail is gone, and the ledger records it.
   Fix: a three-case result; only `absent` becomes `.notInStore`.

6. **An unreadable `.md` in `email/` does not reserve its own name.** `confirmed`
   Where: `PraticaSyncEngine+Folder.swift:59-68`; `PraticheController+TimelineRead.swift:129, 135`.
   What: the `continue` on a failed read precedes `takenNoteNames.append`; `uniqueMessageFileName`
   consults only that array. On an iCloud vault with an evicted file, an import with the same stem
   overwrites it. The timeline also skips the file with two `try?`, and being in
   `importedMessageIDs` it is never re-imported.
   Fix: reserve the name from the directory listing, not from successful reads.

7. **The «Crea» wizard evaluates `exists` before the `await` and writes with no
   `expectingAbsent:`.** `confirmed`
   Where: `NuovaPraticaWizard+Actions.swift:164`, `:176`. The correct door exists at
   `VaultSession+Diary.swift:81` and `VaultSession+Tasks.swift:263`.
   Fix: `expectingAbsent: true`.

8. **`syncAll` iterates a pre-`await` snapshot.** `confirmed`
   Where: `PraticheController+Triggers.swift:117-122`; its twin `fireDueFSEventsPulses`
   (`:90-98`) re-reads after the suspension and says why.
   What: a pratica archived mid-pass is synced anyway and its watcher records `.automatic`.
   Fix: re-read `pratiche.first(where:)` after each `await`.

9. **«Annulla» does nothing during the whole publication phase.** `confirmed`
   Where: `PraticaLiveSync.swift:148-153`, `+Run.swift:91, 294`.
   What: `running` is assigned only inside `runEngine`, after the `Task.detached` that copies the
   Envelope Index (plus a `Thread.sleep(2)` on a torn copy). `cancel()` finds `nil`.
   `PraticaSyncEngine.sync` never consults `Task.isCancelled`.
   Fix: register the task before the detached hop; check cancellation in the engine loop.

10. **Line-4 patch discards the §D23.1 bridge triple on its empty exits.** `confirmed`
    Where: `PraticaSyncEngine+Messages.swift:837, 846, 850` vs `:863-867`.
    What: case `:850` ("patch equals disk") is the normal path for an unresolvable pending
    attachment and fires every sync, so the ledger's ROWID goes stale after a Mail index rebuild.
    Fix: append the bridge before the early returns.

11. **`AttachmentQuarantine.apply` failure aborts the run after the bytes landed.** `confirmed`
    mechanism, `suspected` frequency.
    Where: `+Messages.swift:791-798`, `:871-879`.
    What: `setResourceValues` throws on volumes without extended attributes; the `inout outcome`
    is lost, every earlier message misses `importedMessageIDs` and is re-decoded forever.
    Fix: quarantine failure is a recorded problem, not an abort.

12. **`regenerationEngine` is never released; `MailStoreCopy` funnels every error into
    `.mailIsWriting`.** `confirmed`
    Where: `PraticaLiveSync.swift:336`, `:321-329`; `MailStoreCopy.swift:90-99, 143-145`.
    What: ~355 MB unreclaimed after the first «Rigenera»; a missing Full Disk Access (`EPERM`) sends
    the user to quit Mail instead of to Privacy settings.
    Fix: nil the engine when the sheet closes; classify `EPERM` separately.

13. **`DossierWriter.swift:33` returns `nil` (success) when `Dossier.parse` fails**, so «Escludi»
    trashes the files and silently fails to record the exclusion. `confirmed`. Fix: return a
    problem.

14. **`PratichePane.swift:83` calls `syncAll(kind: .vaultOpen)` on every pane appearance**, and
    `.vaultOpen` skips the 60 s throttle; `PraticheController+Triggers.swift:47` registers a
    `NotificationCenter` observer never removed and capturing `vault` strongly. `confirmed`.

15. **Inspector body never reloads after a write to `pratica.md`.** `confirmed`
    Where: `PratichePane.swift:85` (`.task(id: pratiche.selection)` is the only writer of
    `inspectorBody`).
    What: «Nota», «Chiudi»/«Riapri» update the timeline but not the inspector body.
    Fix: key the task on a write generation too.

16. **«Anteprima allegato» offered on messages it cannot show.** `confirmed`
    Where: `PraticaCommandActions.swift:50-54` vs `:148-150`; `PraticaMessageRow.swift:223`.
    What: `hasAttachments` counts `storeReferences`, the action needs `detail?.attachments.first`.
    A message with only over-threshold attachments shows the command and clicking does nothing.
    The URL also skips `AttachmentChipModel.previewURL`.
    Fix: one predicate for both (ADR-0023 shape).

17. **`chooseRootFolder` stores an absolute path when the choice is not strictly below the vault
    root.** `confirmed`
    Where: `PraticheSettingsTab.swift:95-106`.
    What: `directoryURL` only sets the starting directory; choosing the vault root itself stores an
    absolute path (trailing `/` never matches) and every later pratica write is refused.
    Fix: compute the relative path with `VaultBoundary`, refuse anything outside.

18. **`AddToPraticaSheet.swift:184-202` uses `praticaPath` captured before the `await`**; `follow`/
    `ignore` already had to fix this shape (`:319-327`). `suspected`.

19. **Two consecutive `controller.report()` calls overwrite each other.** `confirmed`
    Where: `PraticaLiveSync+Run.swift:229-240`. Fix: join the sentences.

---

### Chain 5 — App and editor state wiring (P2, wrong behaviour the user meets daily)

Root cause: flags set on `VaultController`/`Navigation` are consumed by a pane-scoped view that
may not exist, `.onChange` without `initial:` misses values set in the same block as a pane
switch, and a few AppKit-hosted panels are never torn down. One ADR: "a cross-pane request is a
queue consumed on appear, never a flag read on change".

1. **Bare Space latches `isShowingQuickLook`.** `confirmed*`
   Where: `CommandActions.swift:353-360`; consumer `WorkspaceView.swift:207-210` (`.onChange`
   only); `RootView.swift:253-267` rebuilds each pane on switch.
   What: press Space outside Workspace: the flag latches `true`, later presses are no-ops, the next
   switch to Workspace opens Quick Look unbidden. The four sheets hosted by `VaultBrowser.swift:
   37-57` share the hazard and survive only because `canRun` gates them on the Notes pane.
   Fix: consume on `.onAppear` as well (`WorkspaceView.swift:89-91` already does this for
   `checkPendingNewBoard`), or gate `.quickLook` by pane in `canRun`.

2. **Three `.onChange` without `initial: true` swallow requests emitted with the pane switch.**
   `confirmed`
   Where: `EditorColumnView.swift:121-136`; emitters `DayEntryReveal.swift:44-53`,
   `ViewsPane.swift:140`, `PraticaEntryComposer.swift:131`, `MenuCommands.swift:178-231`.
   What: click a task row in Oggi living in another note: the note opens, caret and scroll never
   reach the line. The first «Inserisci» from the menu bar is swallowed, the second works.
   Fix: `.onChange(..., initial: true)`.

3. **Second `KeyRecorder` leaves two live event monitors.** `confirmed*`
   Where: `ShortcutSettings.swift:107-158` (`addLocalMonitorForEvents` at `:144`, removed only on
   key event or `.onDisappear`).
   What: one press assigns the same binding to two commands, both monitors swallow the key;
   closing Settings with a recording armed can leave a monitor eating keystrokes app-wide.
   Fix: a single shared recorder state; stop on focus loss.

4. **Folder selection pruned on every rescan.** `confirmed*`
   Where: `NoteListPane.swift:557-558`; folder rows carry a `.tag` since the 2026-08-28 parity
   chain (`NoteTreeRow.swift:132`).
   What: `existing` is the set of note paths only, so every folder id fails, the set empties and
   `syncSelectedRows()` lights the open note. «Rinomina» then targets the open note and «Nuova
   nota» lands in the wrong folder.
   Fix: include folder ids in `existing`.

5. **Format bar never hidden outside `refreshFormatBar`; survives as an orphan child window.**
   `confirmed`
   Where: `CompletingTextView+FormatBar.swift:18, 29`; `NoteTextView.dismantleNSView:459-465`;
   `FormatBarPanel.swift:74` (`addChildWindow`).
   What: select text, switch to Workspace: the bar floats over the board and its buttons write
   into a deallocated text view.
   Fix: hide in `resignFirstResponder` and in `dismantleNSView`.

6. **`rangeForUserCompletion` mixes `Character` counts with UTF-16 offsets.** `confirmed*`
   Where: `CompletingTextView.swift:349-365` (same file fixes the identical hazard at `:332`).
   What: `[[📌Riun` then pick a note: the replacement range starts inside the surrogate pair,
   leaving an unpaired surrogate in the file. Feeds `apply(_:)`, `completions(forPartialWordRange:)`
   and `triggerLocation()`.
   Fix: `prefix.utf16.count`.

7. **`onEditQuery` retains the Coordinator.** `confirmed`
   Where: `NoteTextView+ViewBlocks.swift:200-209` (capture list `[weak textView]`, body calls
   `self.commitViewBlock`); cycle through `viewBlockHosts` (`+Coordinator.swift:128`).
   What: one leaked Coordinator per closed column that ever drew a `pergamenum-view`, each holding
   a live query and a stale `text` binding.
   Fix: `[weak self]`.

8. **Caret entering a fence throws away its host.** `confirmed`
   Where: `NoteTextView+ViewBlocks.swift:82-83, 125`; `ViewBlockHostStore.hosts(for:in:)`.
   What: the revealed fence is absent from `found`, the store keeps only `kept`, the host is
   discarded and rebuilt on exit with an `EmptyView`, re-running the query and losing the measured
   height (120 pt, then relayout). ADR-0033 §D3's cost.
   Fix: keep revealed ordinals in the retained set.

9. **`QuickSwitcher` row `.onTapGesture` starves `List(selection:)`.** `confirmed`
   Where: `QuickSwitcher.swift:108`, `:30`, `:118-122`.
   What: ADR-0025 §D9's trap; `choose(selection)` always falls back to `rows.first`, so there is
   no keyboard path to the third row.
   Fix: drop the tap gesture, drive `selection` from the list and arrow keys.

10. **«Nuova nota qui» ignored when the composer is already open.** `confirmed`
    Where: `NewNoteComposer.swift:48-54`; `VaultController.beginNewNote(in:)`.
    What: `isComposingNote` does not change, the view keeps identity, `@State folder` keeps the old
    value; the note is born at the root while the picker says «(radice)».
    Fix: `.onChange(of: vault.noteDraft.folder)` or make the composer read the draft directly.

11. **`renameNote`/`moveNote` defer the tab follow-up behind a full rescan.** `confirmed`
    Where: `Sources/App/VaultController+Files.swift` (`Task { await rescan(); movedNote(...) }`);
    `trashNote` and `renameFolder` do the opposite; `movedNote` reads from disk and never needed
    the rescan.
    What: during the rescan every open tab holds the old path; a save in that window (also from an
    outline move, `EditorColumn+Text.swift:135-143`) recreates the note under its former name.
    Fix: `movedNote` first, then rescan.

12. **`insertion` branch lacks the `alreadyApplied` guard its twin has.** `suspected`
    Where: `NoteTextView.swift:375-411` vs `:425` (PG-093's guard).
    Fix: same guard.

13. **`RelatedLinkSheet`: `selectedTitle` not cleared on query change; list keyed on
    `relativePath` while rows are tagged with `title`.** `confirmed`
    Where: `RelatedLinkSheet.swift:30-38, 42, 84-86`.
    Fix: clear on change; tag with the path.

14. **`NoteListPane+FolderVerbs.swift:146-151` reads `deletingFolder` inside the confirm action
    while the `isPresented` setter nils it**; survives only because `trashFolder` is still
    synchronous. `suspected`. Fix: `.confirmationDialog(…, presenting:)` like its note twin.

15. **`NoteTab.showing(_:)` drops folds on rename.** `confirmed`
    Where: `NoteTab.swift`, used by `movedNote`. Fix: carry `foldedEntries`/`currentOutlineEntry`.

16. **`restoreTabs` documents "skipped rather than reported" but `readForEditing` calls
    `recordProblem`.** `confirmed`. Fix: align one with the other.

17. **`EmbedNavigation.swift:94` deletion range starts at `run.location` while `embedRun(inLine:)`
    drops leading whitespace**, leaving indentation glued to the next line on Backspace. `confirmed`.

18. **`NoteTextView+Tables.swift:116-118` creates grids before `endEditing()` and never asks for a
    remeasure** (48 pt first layout). `suspected`. Distinct from PG-102.

19. **`QuickLookPresenter.swift:98-113`: `isPresented` reset via `DispatchQueue.main.async`, so a
    second update can toggle the panel closed; steals first responder on every update.**
    `suspected`.

20. **`CaptureController.swift:136` returns `false` before `outcome` is set on an empty field**, so
    `CapturePanelView.swift:254-261` shows neither a close nor an explanation. `confirmed`.

21. **`CapturePanelView.swift:81`: `Character("\(index + 1)")` traps at the tenth destination;
    Cmd+digit unremappable and shadowing tab selection; `⌘` glyph in `.help`.** `confirmed*`
    Fix: `KeyEquivalent` from a digit only for `index < 9`, none beyond; use `ShortcutStore`.

22. **`TagBrowserView.swift:335-338, 352-355`: `if vault.isPinned(old) { togglePin(old);
    togglePin(new) }` unpins the target when already pinned**, mirrored on undo. `confirmed`.

23. **`CategorySidebarSection.swift:173`: deleting a category with children is a silent no-op**
    (`mutateCategories` never calls `recordProblem`; `applyCategoryDrop` `:149-160` same).
    `confirmed`. Fix: one `recordProblem` in `mutateCategories`, plus a confirmation dialog.

24. **`ViewQuerySections.swift:152-170`: the Raggruppa control converts a field grouping into a
    tag grouping on any edit; placeholder shows `tag("…")` while the value is the bare glob.**
    `confirmed`. Fix: keep the kind; show the bare glob.

25. **`ViewQueryTermRow.swift:112` clears `argument` on kind change leaving three kinds with a
    disabled «Aggiungi» and no reason; `ViewQueryBuilderSheet.swift:28, 66-70, 152` never clears
    `refusedReason`.** `confirmed`.

26. **`ReviewSheet.swift:342-358`: speaker rename field refills when emptied and persists per
    keystroke; `:311` `.defaultAction` on «Importa» commits on Return inside a text field.**
    `confirmed`.

27. **`HelpSheets.swift:56`, `NoteHistorySheet.swift:143`: `.defaultAction` without
    `.cancelAction`, so Esc does not close.** `confirmed`. Fix: `.onExitCommand` as in
    `GlobalSearchView.swift:38`.

---

### Chain 6 — Day-boundary and calendar math (P2)

Root cause: `TimeBlock` and the timelines treat the day as unbounded. `DiaryEntry.swift:83-88`
solved the identical case on the diary side and documents why; the fix is to share it.

1. **`freeStart` tests only the start point.** `confirmed*`
   Where: `Sources/Calendar/TimeBlock.swift:45-52`; callers `DayController.swift:182`,
   `VaultSession+TimeBlocks.swift:74`.
   What: with a block at 10:00-10:30, dropping a 60-minute task at 09:45 returns 585 and creates an
   overlapping 09:45-10:45 block, against the function's own "Placed rather than overlapped". The
   `start < 24*60` guard ignores duration, so the end can pass midnight.
   Fix: test `[start, start+duration)` against every block and against 1440.

2. **A block ending at 24:00 renders `00:00`, is not re-read, and is erased.** `confirmed*`
   Where: `TimeBlock.swift:27-29` (`(minutes / 60) % 24`), `:122-124` (`end > start`);
   `DayController.swift:177-195`.
   What: a 23:30 block with the default 60 minutes gets end 1470 → `00:30`; `parse` skips it; the
   next section rewrite deletes the line.
   Fix: `DiaryGrid.timeText`'s rule; clamp duration at creation.

3. **Multi-day or midnight-crossing events drawn at the start day's hour.** `confirmed`
   Where: `DayTimeline.swift:240-242, 54-55`; `WeekPlan.swift:135, 227-230`;
   `CalendarService.bucketed:210-224` repeats an event per touched day.
   What: a Monday-to-Wednesday event is drawn at Monday 09:00 on Tuesday; a 22:00-01:00 dinner
   appears the next day at 22:00.
   Fix: clamp start/end to the shown day before converting.

4. **`DiaryEntryCard` drag and resize measure in local space.** `confirmed`
   Where: `DiaryEntryCard.swift:172, 183, 97-99`; `TimelineBlockBox.swift:107-115` carries the
   measured warning and uses `.global`.
   What: the moved view is the coordinate space, so the drag feeds back into itself.
   `DiaryController.resize` also clamps the start instead of the duration (`DiaryGrid.clampStart`),
   dragging a 23:00 entry's bottom handle up to 22:00.
   Fix: `coordinateSpace: .global`; clamp duration.

5. **`CategoryView.swift:115-118`: deadline label always `.taskOverdue`.** `confirmed`.

6. **`MiniCalendar.swift:78-84`: `ForEach(week, id: \.self)` over `[CalendarDate?]` padded with
   `nil` gives cells the same identity.** `confirmed`. Fix: enumerate.

7. **`TodayView.swift`: the daily note is resolved by title containment, so `2026-09-25
   riunione` satisfies the lookup for `2026-09-25`.** `suspected`. Fix: exact match on the daily
   note name.

8. **`DiaryTimeline.swift:52-57`: `now = Date()` assigned every 30 s unconditionally**,
   invalidating the whole timeline on days where `nowLine` is not drawn. `confirmed`.

9. **`MessageDocument` date zone** (Chain 1 item 11) is the same family if that chain does not
   take it.

---

### Chain 7 — Search and query correctness (P2)

Root cause: two tag matchers with opposite rules, a quote parser with no open/close distinction,
and a UI whose debounce sits in the wrong place.

1. **Global search matches tags by prefix.** `confirmed*`
   Where: `Sources/Core/Search/SearchQuery+Matching.swift:78-79`; `Glob.swift:61-63` documents
   why prefix matching is wrong.
   What: `tag:client-acme` also returns `client-acme-industriale`; `-tag:status-a` excludes every
   `status-attivo` and `status-archiviato` note.
   Fix: exact match, one shared predicate, one test tying the two matchers together.

2. **A phrase ending in a colon swallows the rest of the query.** `confirmed`
   Where: `SearchQuery.swift:238-246`.
   What: the "this quote belongs to an operator" test is `current.hasSuffix(":")` with no
   open/close distinction; `"nota:" progetto forno` becomes one phrase and returns nothing.
   Fix: track quote state explicitly.

3. **`GlobalSearchView.swift:100-117`: spinner leaks across generations, `invalidPatterns` set
   before the debounce, and `vault.search` is synchronous on the main actor.** `confirmed`
   Fix: set `isSearching` after the sleep; validate after; move the read off the main actor with
   a cancellation check.

4. **`ViewsPane.swift:166-186`: `scan()` is synchronous, so the `ProgressView` never shows and the
   window freezes.** `confirmed`.

5. **`IndexSnapshot.subtasks(of:)` never reaches `boardTasks`**, so a project parent living on a
   board has no sub-tasks (`IndexSnapshot.swift:204-208`). `confirmed`.

---

### Chain 8 — Vault-side stores without an origin marker (P2, ADR-0052 pattern, third and
fourth instance)

1. **`CategoryRegistryStore.load()` reports an unreadable file as absent, then overwrites it.**
   `confirmed`
   Where: `Sources/Vault/CategoryRegistryStore.swift:31-41`; `VaultSession+Categories.swift:
   176-178` refuses only `.malformed`. `NoteIDStore.swift:46-58` does the `fileExists` check first
   and documents why.
   What: permissions, iCloud eviction or a transient I/O error on `categories.json` → the whole
   registry is replaced by one category. `VaultSession.categories` is also loaded once at `init`
   and written back wholesale with no re-read.
   Fix: `NoteIDStore`'s shape (exists-but-unreadable is `.malformed`; never written over) plus a
   `LedgerOrigin`-style marker on the session copy.

2. **`StarredStore.load()` returns empty on an unreadable file and is saved back
   unconditionally.** `confirmed`
   Where: `Sources/Vault/StarredStore.swift`, `VaultSession.setStar`.
   What: the file's accepted trade ("losing a star is nothing") reasons about a malformed file; it
   also fires on an evicted read, which principle 6 makes routine.
   Fix: same shape.

3. **`IndexCache.save()` stamps `user_version = 4` before the transaction opens.** `confirmed`
   Where: `Sources/Index/IndexCache.swift:119-121`.
   What: `PRAGMA user_version` is not transactional; an interrupted save over a v3 cache leaves v3
   rows stamped v4, so the next launch reuses rows ADR-0047's bump exists to discard.
   Fix: set the pragma inside the transaction, after the rows.

4. **`VaultScanner.isUnchanged` validates on size plus `abs(Δmtime) < 1`.** `confirmed`
   Where: `VaultScanner.swift:208-214`.
   What: a length-preserving edit within one second (`- [ ]` → `- [x]`) never invalidates the row.
   Fix: compare mtime exactly, or hash on equal size.

5. **`CanvasStore.save` creates the parent with `withIntermediateDirectories: true`**, the board
   twin of the PG-168 vacated-folder resurrection `requiringExistingFolder` fixed for notes.
   `confirmed`.

6. **Case-only rename refused.** `confirmed`
   Where: `VaultSession+Journal.swift:71-76`, `NoteFileOperations.swift:103`,
   `FolderFileOperations.swift:191`.
   What: on case-insensitive APFS `exists("Nota.md")` is true while renaming `nota.md` → `Nota.md`;
   the user is told "esiste già" about the file they are holding.
   Fix: compare canonical paths; allow when the only difference is case.

7. **`VaultWatcher` sees nothing for a symlinked vault.** `confirmed`
   Where: `VaultWatcher.swift` (`Sink.handle`) → `VaultScanner.swift:203-206` (`standardizedFileURL`
   does not resolve symlinks; FSEvents delivers canonical paths). `VaultWalk` already uses
   `.canonicalPathKey` for the measured `/var` vs `/private/var` case.
   What: external edits never reach the open tab; spurious `.deleted` events close tabs
   post-ADR-0061.
   Fix: canonicalise the root once and compare against canonical event paths.

---

### Chain 9 — Design system: component layer, missing tokens, lint (P2, the single fix behind
most of the visual drift)

State: colour discipline is at one violation, shadows and radii are token-driven, dark mode is
clean, Settings are complete. What is missing is one level up: no shared components, and a token
scale with no values below 4pt and no font below `.caption`. One ADR amending ADR-0002 (design
system) and ADR-0030.

1. **Create the component layer in `Sources/DesignSystem/`**: `PaneHeader(title:count:trailing:)`,
   `EmptyState(icon:title:subtitle:)`, `SectionHeader(style:)`, `SelectableRowBackground
   (isSelected:)`, `DisclosureChevron(isOpen:)`. Adopt at:
   - empty states (4 shapes today): `EditorColumn+Closing.swift:13-20`, `WorkspaceView.swift:
     244-253`, `RootView.swift:351-363` and `:370-382` (the second is an inline duplicate of
     `needsVault(_:)` ten lines above), `StarredPane.swift:53-54`, `ViewsPane.swift:65-66`,
     `TasksView+List.swift:66-69`, `CategoryView.swift:64-68`, `GlobalSearchView.swift:94-98`,
     `TagBrowserView.swift:245-250`. Copy rule: no trailing period on a fragment.
   - pane titles (three weights): `RecordingsPane.swift:96-105`, `ViewsPane.swift:50-53`,
     `StarredPane.swift:44-49` (`.title`), `PraticheListColumn.swift:52-58` (`.heading`),
     `TaskListControls.swift:21` (uppercase caption).
   - selection (three idioms): move `TasksView+Row.swift:61-65` (stroke ring, `radius.card`) and
     `TagBrowserView.swift:178-183` (filled chip, `radius.control`) to `List(selection:)`, or to
     one shared background. The two radii disagree on purpose today; decide once.
   - disclosure chevrons: 12 symbol-swap sites (`PraticaMessageRow.swift:73`, `PraticaEntryRow.
     swift:55`, `PraticheListColumn.swift:141,153`, `CategorySidebarSection.swift:189,233`,
     `TagBrowserView.swift:149`, `DayMonthSection.swift:55`, `NoteListPane.swift:293`, `OutlinePane.
     swift:155`, `PraticaTrayStrip.swift:84`, `FullDiskAccessBanner.swift:33`) vs 2 rotations
     (`NoteTreeRow.swift:89`, `WorkspaceRow.swift:275`). Rotation wins (it can animate).
   - navigation chevrons: `chevron.backward`/`forward` everywhere (`DayToolbar.swift:33,44`,
     `DiaryToolbar.swift:39`, `MiniCalendar.swift:60`, `MonthCalendar.swift:46` use `left`/`right`;
     `HistoryToolbar.swift:22,27` is right).
   - section-header casing: 5 manual `.uppercased()` sites vs 5 sentence-case `.heading` sites,
     `.textCase(` used zero times. Rule: uppercase caption for grouping labels inside a list,
     sentence `.heading` for pane/section titles.

2. **Add the four tokens the views keep working around**: `spacing.xxs` (2), `spacing.hairline`
   (1), `font.micro` (the `.caption2` role), `radius.hairline`. Then:
   - replace the 12 font violations: `RootView.swift:354,371`, `EditorColumn+Closing.swift:15`,
     `WorkspaceView.swift:248`, `ViewGridRenderers.swift:112`, `WeekEntryRows.swift:33`,
     `BoardChrome.swift:115`, `TableGridView+CellCommit.swift:180` (`NSFont` outside
     `ProseTypography`, ADR-0030 §D1), `.caption2` at `CapturePanelView.swift:103,185`,
     `TaskDatePanels.swift:170`, `TaskComposer.swift:80`, `TaskComposer+Footer.swift:105`,
     `TaskTimeRow.swift:31`, `DayMonthSection.swift:56`, `NoteTreeRow.swift:91`; gallery files
     `TransclusionMockup.swift:114,201`, `EmbedMockup.swift:105`, `ViewMockupRenderers.swift:186`,
     `WeekMockupPieces.swift:23`.
   - snap the ~80 `1/2/3` literals to the two new spacing tokens.
   - sweep the ~26 literal duplicates of `xs/s/m`: `ViewGridRenderers.swift:22,160,217`,
     `ViewRowRenderers.swift:101,210`, `ViewBoardRenderer.swift:44,90,94`, `ViewQueryTermRow.swift:
     138,247,323`, `MonthCalendar.swift:21,60,70`, `MonthView.swift:23,46`, `WeekView.swift:27`,
     `BoardChrome.swift:53`, `FormatBar.swift:66`, `CardFormatBar.swift:95`.
   - radius literals: `TimelineBlockBox.swift:92` (2), `NodeCard.swift:80,258` (3),
     `ViewGridRenderers.swift:240` (4, straight `.sticky` duplicate), `TranscludedNoteView.swift:
     98` (1.5).
   - the last hardcoded colour: `EditorDecorationDelegate.swift:750` `NSColor.secondaryLabelColor`
     → `theme.color(.textSecondary)` pushed in (the delegate is `nonisolated`).

3. **Three named sheet widths** (`sheet.small 460`, `sheet.medium 560`, `sheet.large 720`) as
   dimension tokens; fix the four rename sheets split 460/560 (`BoardSheets.swift:43` vs `:85`,
   `WorkspaceFolderSheets.swift:209,292` vs `TagRenameSheet.swift:57`); 41 hardcoded widths in
   total.

4. **`custom_rules` in `.swiftlint.yml`** forbidding `Color\.(red|blue|…)`, `NSColor\.`,
   `\.font\(\.system`, `\.font\(\.caption2`, `NSFont\.(systemFont|monospacedSystemFont)` under
   `Sources/Features` and `Sources/App`, excluding `ProseTypography.swift` and
   `Sources/DesignSystem`. The binding rule is enforced by a human reading a diff today.

5. **Button style**: `.borderless` for the inline-icon role at `ShortcutSettings.swift:81`,
   `PraticaTopBar.swift:111,192`, `PraticheListColumn.swift:73,87`, `RecordingRow.swift:288,306`,
   `RecordingsPane.swift:179` where ~90% of sites use `.plain`. Pick one.

6. **Toolbar coverage**: `PratichePane.swift` and `GlobalSearchView.swift` declare no `.toolbar {}`
   and miss `themeToggleToolbarItem`.

7. **Dividers**: 119 sites; `TagBrowserView.swift:100,196,213,414` and `BoardChrome.swift:161,198,
   205,209` draw hairlines where sibling panes use whitespace for the same seam. A design decision
   (SPEC §11.2), not a find-replace.

---

### Chain 10 — Menu, label and formatting consistency (P3, a day of edits)

1. **Duplicate menu items without rationale**: «Anteprima rapida» (`MenuCommands.swift:107-109` and
   `VaultCommands.swift:65-67`) and «Rigenera indice» (`MenuCommands.swift:110-111` and
   `VaultCommands.swift:124-125`). Keep the File copies.
2. **Same action, different label**: "Rivela nel Finder" (`VaultCommands.swift:130`,
   `NoteRowMenu.swift:57`, `NoteTreeRow.swift:155`, `ShortcutCommand.swift:202`) vs "Mostra nel
   Finder" (`PraticaCommand.swift:53`, `AttachmentChipModel.swift:105`); "Collega una nota…"
   (`PraticaCommand.swift:54`) vs "Collega nota…" (`MessageCommand.swift:42`); "Assegna
   categoria…" (`TaskCommand.swift:36`) vs "Assegna una categoria…" (`AssignCategoryMenu.swift:
   27`); star toggle static "Preferita" (`MenuCommands.swift:100`) vs dynamic (`NoteRowMenu.swift:
   30`) vs fixed (`StarredPane.swift:87`).
3. **Nine `ShortcutCommand.title` strings differ from their menu button** (breaks the invariant
   stated at `ShortcutCommand.swift:184-186`): `dailyNote` ("Nota di oggi" / "Oggi"),
   `globalCapture`, `insertWikilink`, `insertRelated`, `taskToggle`, `taskToday`, `taskTomorrow`,
   `taskPlusTwo`, `taskNextWeek`. Shorten the titles to the menu wording.
4. **Ellipsis**: missing on `openVault`, `globalSearch`, `quickSwitcher` in `ShortcutCommand.swift:
   197-200`, on «Nuovo evento»/«Nuovo promemoria» (`:234-235`), on «Elimina»/«Rivedi» in
   `RecordingRow.swift:28-37`; wrongly present on the submenus «Sposta in…» and «Aggiungi anche
   a…» (`MessageCommand.swift:39-40`).
5. **Capitalisation** (Italian sentence case): "Cerca Aggiornamenti…" (`MenuCommands.swift:267`,
   also in CLAUDE.md and ADR-0031), "Inserisci Blocco Tempo" (`DayReferences.swift:144`),
   "Consenti Calendario" (`DayTimeline.swift:207`), "Apri Impostazioni di Sistema: Calendario"
   (`SettingsView.swift:224,229`, `PraticheSettingsTab.swift:205`, `FullDiskAccessBanner.swift:40`).
6. **Hand-kept context menu**: `AttachmentChip.swift:60-68` builds from
   `AttachmentChipModel.contextMenuTitles` instead of `MessageCommand`; already drifted
   («Anteprima» vs «Anteprima allegato»). `CardCommand.swift:1-9` states why this is forbidden.
7. **SF Symbols**: `MessageCommand.exclude` uses `xmark.circle` for a trash operation; two glyphs
   for "board" in `PratichePane+Links.swift:214` vs `PraticaLinkPicker.swift:209`; «attività» vs
   «task» oscillates across picker, inspector and errors.
8. **`CommandGroup(replacing: .help)` (`MenuCommands.swift:243`)** removes the built-in Help search
   field, the only `replacing:` in the file without a comment.
9. **File menu**: 25 items in one group, and holds commands SPEC §10 puts in Modifica/Vista (Vai
   alla nota…, Ricerca globale…, Anteprima rapida, Cronologia…). Regroup with dividers or move.
10. **Formatting**: `HH:mm` via `String(format:)` in 13 places (`TaskDatePanels.swift:93`,
    `TaskComposer+Footer.swift:25`, `TodayView.swift:254`, `DayTimeline.swift:146`, `WeekPlan.swift:
    233`, `RecordingRow.swift:198`, `DiaryTimeline.swift:115`, `DiaryEntrySheet.swift:100,109`,
    `TaskItem.swift:139,150`, `RolloverMarker.swift:19`, `PraticaNaming.swift:34`) → one
    `TimeOfDay.formatted` in Core; two weekday-initial conventions (`MonthCalendar.swift:20`
    "lu ma" vs `MiniCalendar.swift:176` "L M M"); `MiniCalendar.swift:227-234` duplicates
    `DateEntry.weekday(of:)`; `NoteHistorySheet.swift:69-77` duplicates relative-day logic;
    Pratiche uses the system locale (`PraticaMessageRow.swift:299-313`, `PraticaTrayStrip.swift:153`)
    while the rest pins `it_IT`.
11. **`ViewBlockAttachment.swift:28`**: `fatalError("init(coder:) non supportato")`, Italian in
    code.

---

### Chain 11 — Motion (P3, SPEC §11.2 asks for it)

The app has two `withAnimation` calls (`PratichePane+Inspector.swift:59`,
`MarkdownReadingView.swift:98`) and zero `.transition`/`.contentTransition`/
`matchedGeometryEffect`. `NoteTreeRow.swift:89`'s `rotationEffect` rotates with nothing
animating it. Add `motion.quick` (0.15 s) and `motion.standard` (0.2 s) tokens and a
`.themedAnimation(_:)` modifier; apply to the 12 disclosure sites, the tray and inspector toggles,
the tab bar and the sidebar focus modes. Ships naturally with Chain 9's `DisclosureChevron`.

---

### Chain 12 — Accessibility (P3)

1. Pen-tool controls in `BoardChrome.swift:176-206` are `Circle()`/`Image` with `.onTapGesture`:
   no trait, no label, not focusable. Convert to `Button` with `.accessibilityLabel`.
2. Zoom-in and zoom-to-fit in `BoardChrome.swift:153-163` have neither identifier nor label.
3. Icon-only deletes relying on `.help()` alone: `TimelineBlockBox.swift:70-81`,
   `DiaryEntryCard.swift:142-152` (compare `NoteTabBar.swift:209-216`).
4. ~53 `Image(systemName:)` inside `Button` with no label nearby (lead, not confirmed); start with
   `PraticaLinkPicker.swift:143`, `WorkspaceBrowserToolbar.swift:85`, `NoteListToolbar.swift:75`,
   `OutlinePane.swift:155`, `VaultBrowser.swift:227`.
5. `CategorySidebarSection.swift:90` sets an identifier on the whole row without
   `.accessibilityElement(children: .contain)`, likely hiding `category-disclosure-`/
   `category-promote-` (`suspected`).
6. 14 UI-test lookups by prose text against the repo's own rule: `PraticheUITests.swift:53,65`,
   `DayViewUITests.swift:64,65,101`, `WorkspaceIntegrationUITests.swift:118,131,218`,
   `SidebarDeleteUITests.swift:41`, `HistoryNavigationUITests.swift:70`.

---

### Chain 13 — Dead code and removed-feature residues (P3, one PR, no behaviour change)

Periphery on the `Pergamenum` scheme; connector symbols used only by `perg`/`pergamenum-mcp` were
verified as live and excluded.

1. **Genuinely dead**: `VaultController.selfWrittenHashes` forwarder (`VaultController.swift:115`),
   `VaultController+Categories.linkCategory(_:toNoteAt:)` (`:61`), `MenuBarItem.isShown` (`:30`),
   `PergamenumApp.capture` `@State` (`:122`, only the initial value is used),
   `JSONValue.stringValue/doubleValue` (`:46,51`), `CategoryColor.label` (`:28`),
   `DiaryEntry.prose(of:)/overlaps(_:)/lastHour` (`:216,38,72`), `EmailHeaders.value(for:)`
   (`:27`), `MailStoreReader.init(connection:)` (`:45`), `MembershipRule.empty` (`:29`),
   `RankableEntry.aWord(of:startsWith:)` (`:148`), `PraticheController+TimelineRead.
   attachmentFileName(fromWikilink:)` (`:261`), `VaultScanner.isEmpty` (`:24`),
   `MailDropReceiver.isTargeted` (`:52`), `TagBrowserMockup.paneWidth` (`:39`); unused
   `@Environment(\.theme)` in `CaptureMockup.swift:15`, `SlashMenuMockup.swift:19`,
   `TransclusionMockup.swift:15`, `WeekMockup.swift:25`, `WeekMockupPieces.swift:40`,
   `AssignCategoryMenu.swift:11`, `VaultTopBar.swift:11`; unused parameters
   `PraticaSyncPlan.swift:47 settings`, `DateEntry.swift:54 calendar`, `VaultPlanApplication.swift:
   73 isolation`, `NoteSelectionRule.swift:53 old`, `ViewBlockHostStore.swift:44 textView`,
   `PraticaWatcher.swift:66 now`, `BoardFormatBar.swift:81 viewport` and
   `BoardWikilinkCompletionLayer.swift:42 viewport` (these two are PG-135), `WorkspaceBrowser+Tree.
   swift:223 old`, `WorkspaceView+Drawing.swift:28 size`, `WorkspaceView.swift:463 size`,
   `FolderFileOperations.swift:177 knownPaths`, `VaultSession+WriteOrdering.swift:22 relativePath`.
2. **Dead settings key**: `VaultSettings.harnessRepositoryPath` (`:68,149,191,240,259`) is
   encoded and decoded, never written by «Importa convenzioni…» (`VaultOpenPanel.swift:21-27`
   opens a fresh panel every time) and never read. Either persist and reuse the path, or remove.
3. **Assign-only properties worth a decision**: `CalendarEvent.isEditable` (never read: read-only
   calendars are not distinguished in the UI), `TokenValue.spread`, `PlaudVaultStore.
   lastImportedAt`, `BoardTray.generation/board`, `FolderFileOperations.rewrittenPaths`,
   `MailMessageRow.indexMessageIDHash/globalMessageID`, `MailAttachmentRef.messageRowID/
   attachmentID`, `TaskPraticaLookup.sourcePath/localID`, `CompletingTextView+Pasteboard.
   characterIndex`, `PraticaSyncEngine.vaultRoot`, `PlaudHTTPClient.taskIDs`,
   `VaultSession+BoardDrop/TaskDrop.path`, `VaultSession+TagRename.title`,
   `Navigation.ordinal`, `VaultCommands.capturePanel/navigation`, `MenuCommands.navigation`.
   `TimeBlock.sourceTaskID` is assign-only on purpose (documented at `DayController.swift:197-203`).
4. **Retired UI tests' leftovers**: `UITests/WorkspaceIntegrationUITests.swift` keeps 15 unused
   helpers (`openBoard`, `captureParentTask`, `assignWorkspace`, `selectGrouping`, …) and 3 unused
   properties; `Tests/TaskViewTests.swift:10 today`, `Tests/FakePlaudService.setProposalResult`,
   `Tests/DayTestSupport` stub members are protocol-required and fine.
5. **ADR-0038 residues (Conformità UI)**: user-visible tooltip «Backlink, conformità, link non
   risolti» at `VaultBrowser.swift:147`; orphan comment above a bare `Divider()` at
   `MenuCommands.swift:76-81`; comparison to «Verifica conformità» at `CommandActions.swift:289`;
   `VaultController+Conformance.swift` kept alive by `Tests/VaultTests.swift:399,492` only; the
   Design Gallery (reachable from Impostazioni › Design System, `DesignSystemSettings.swift:99,113`)
   still shows «Verifica conformità ⌃⌘L» (`SlashMenuMockup.swift:185`) and CONFORMITÀ sections
   (`OutlineMockup.swift:62`, `UnlinkedMentionsMockup.swift:51`, `TagBrowserMockup.swift:14`);
   comments at `OutlinePane.swift:6`, `RelatedLinkSheet.swift:7`.
6. **ADR-0029 residues**: `ShortcutCommand.swift:246-249` still says "reading mode keeps
   Cmd+Shift+M"; `MarkdownReadingView.swift:9` cites a `DiaryView.preview` call site that no longer
   exists (the file is at zero references, retained on purpose per ADR-0029 §D14).
7. **ADR-0047 residues**: `JSONCanvas.swift:6` ("The acceptance criterion for M2 is that a canvas
   written here opens in Obsidian"), `Theme.swift:211` ("the file has to render in Obsidian"),
   `Tests/CardRoundTripTests.swift:20` (points at the retired probe).
8. **ADR-0059 residue**: `Tests/NoteIDRouteTests.swift:10` header still describes the RED-at-Task-1
   state (`RouteState.noteIDs`, deleted).
9. **Contradictory comment**: `VaultSettings.swift:100` says `revealsInlineSpans` is "Off by
   default"; `:161-164` says "On by default" and the code agrees with the latter.
10. **Per-keystroke `Logger.notice`** at `EditorDecorationDelegate.swift:240,249,254,268` and
    `NoteTextView+Transclusion.swift:41-43`, unguarded while `:294`/`:314` in the same file are
    guarded with a comment saying why.

---

### Chain 14 — Documentation consistency (P3, docs only)

1. **SPEC contradicts ADR-0059**: `docs/20260811_Pergamenum_SpecApp.md:396` (§9) and `:512` (§14)
   still say the note id lives in the index. ADR-0059 §D10 declares it amends both; ids live in
   `.pergamenum/note-ids.json`. §14 is the "do not reopen" table, so this one matters.
2. **Two ADRs numbered 0061** (`0061-external-deletion-reaches-the-tabs-and-the-diary.md`,
   `0061-merge-integrity-guard.md`), both listed in CLAUDE.md's index. Renumber one (0063) and
   fix every cross-reference.
3. **18 source files cite "ADR-0155 §D1"**, which does not exist in `docs/adr/`.
4. **16 implemented and merged ADRs still read `Status: proposed`**: 0017, 0029, 0030, 0031,
   0032, 0033, 0034, 0036, 0040, 0042, 0044 ("decided, not implemented" — CI exists), 0050, 0056,
   0057, 0058, 0059.
5. **`TODO.md` `PG-156` is stale**: ADR-0033 put `pergamenum-view` fences back in the editor. Close
   it, or narrow it to "a board surface outside the text flow" (see Chain 16 item 2).
6. `PROJECT_BRIEF.md:1193,1196` mention the Conformità pane inside a dated changelog; add an
   ADR-0038 note beside them rather than editing history.

---

### Chain 15 — Performance nits (P3, measure before touching)

- `OutlinePane.swift:185-189` (reached from `:46` and `NoteListPane+Footer.swift:22`): `foldable`
  re-runs `NoteFolding.hiddenParagraphs` per entry, a full parse each; a 40-heading note re-parses
  ~40 times per keystroke on the main actor.
- `TasksView+List.swift:137-140, 146`: `options(for:)` decodes the `@AppStorage` JSON map per row
  inside `body` (distinct from PG-138).
- `TagRenameSheet.swift:108-111`: `changes` is a computed whole-vault preview consulted three
  times per body evaluation, per character typed.
- `DiaryTimeline.swift:52-57` (see Chain 6 item 8).
- `GlobalSearchView` and `ViewsPane` synchronous reads (Chain 7 items 3 and 4).

---

### Chain 16 — New features (what would make the app more complete), in recommended order

1. **Post-write notification from `VaultSession.write`** (extends PG-232/#512). Seven writers never
   catch the editor up (note-rename link rewrite, `renameTag`, `undoJournalledWrites`,
   `moveOnBoard`, Pratiche `ensuringLocalID`, the composer's diary mirror, Plaud re-import).
   `syncOpenNote` is a step each caller can forget, which is the failure ADR-0041's working
   agreement predicts. One hook, every writer covered, Chain 4 item 2 becomes free. Own ADR.
2. **A live board surface for `pergamenum-view`** beyond the inline attachment. ADR-0033 renders
   the fence in the editor, but a Kanban inside a text flow stays cramped: a panel opened from the
   «Viste» row (or a detachable window) hosting `RenderedViewBlock` with drag-to-write, the
   `ViewBoardRenderer` already exists. Reopens ADR-0009/0033 territory; `/spec` first.
3. **Pratiche completion**: detect new counterparts joining an already-followed conversation
   during sync (`PG-111`) and connector write access `perg pratica add-note` plus an MCP write tool
   (`PG-115`). Both are composition over existing pure pieces (`PraticaEntry.insert`,
   `VaultAPI.arm`). The in-app assistant over a pratica (`PG-112`) is the larger step and its own
   chain.
4. **AppIntents and Spotlight** (the open half of M13, `PG-014`): with `NoteIDRegistry` shipped,
   exposing notes as `CSSearchableItem`s and «Apri nota»/«Cattura» intents is composition, not new
   machinery. Keep it fully offline; `pergamenum://note?id=` is the hand-off.
5. **Static export of the whole vault** (HTML with resolved wikilinks, `PG-014`'s "static
   export"): `NoteExporter` exists; add the vault loop and an index page.
6. **`pergamenum://pratica/add?message=…`** (`PG-114`) once the Automation consent story is decided.
7. **«Apri come board»** for a pratica timeline (`PG-113`): one card per message, pure composition
   over `CanvasStore`/`CanvasID`.
8. **Swift-native template engine** (`PG-121`): only if a real need to customise `Dossier.render`
   or `ImportNaming` emerges. Not recommended now.

Not recommended, unchanged from SPEC §14: HTML rendering of email bodies, any proprietary sync,
branch protection on `main`.

---

## Part 2 — Schedule

Sizes are the audit's estimate of a `/spec → /workplan → /build → /ship` cycle for one person
with the current tooling; "S" is a day or less, "M" two to four days, "L" a week or more. Order
is the recommended order; chains marked ∥ can run in parallel worktrees with the one above them
because they touch disjoint files.

| # | Chain | Priority | Size | ADR | Depends on |
|---|---|---|---|---|---|
| 1 | Format-edge hardening (frontmatter, JSON Canvas, MIME, task text) | P1 | L | new | — |
| 2 | Workspace board lifecycle (flush, editing ids, boundary) | P1 | M | extends 0054/0060 | — ∥ |
| 3 | Connector input hardening (negative ints, flag parser, dry-run bypass) | P1 | S | none | — ∥ |
| 4 | Pratiche sync integrity (carry-over, VaultSession writes, ledger exits) | P1/P2 | L | extends 0036/0049 | 16.1 helps |
| 5 | App and editor state wiring (latched flags, `initial:`, monitors, panels) | P2 | M | new | — ∥ |
| 6 | Day-boundary and calendar math (TimeBlock, timelines, diary drag) | P2 | S/M | extends 0013 | — ∥ |
| 7 | Search and query correctness (tag matcher, quotes, debounce) | P2 | S | none | — ∥ |
| 8 | Vault stores without origin marker (categories, starred, cache pragma, case rename, symlink) | P2 | M | extends 0052 | — |
| 9 | Design system component layer, tokens, lint | P2 | L | amends 0002/0030 | — |
| 10 | Menu, label and formatting consistency | P3 | S | none | 9 for shared helpers |
| 11 | Motion tokens | P3 | S | with 9 | 9 |
| 12 | Accessibility | P3 | S | none | 9 |
| 13 | Dead code and residues | P3 | S | none | — ∥ any |
| 14 | Documentation consistency (SPEC §9/§14, ADR numbering, statuses) | P3 | S | docs | — ∥ any |
| 15 | Performance nits | P3 | S | none | measure first |
| 16.1 | Post-write notification hook | feature | M | new | — |
| 16.2 | Live board surface for views | feature | L | new | 9 |
| 16.3 | Pratiche completion (counterparts, connector write) | feature | M+M | extends 0036 | 4 |
| 16.4 | AppIntents and Spotlight | feature | M | new | — |
| 16.5 | Static vault export | feature | S/M | none | — |
| 16.6–16.8 | Pratica URL route, «Apri come board», template engine | feature | S, S, L | — | on demand |

Suggested sequence for the next weeks:

1. Chains 3, 13, 14 first (small, no design decisions, clear the ground).
2. Chain 1, with chain 2 in a parallel worktree.
3. Chain 4, with chains 5, 6, 7 in parallel worktrees.
4. Chain 8, then 16.1 (the two are neighbours in `Sources/Vault`).
5. Chain 9, then 10, 11, 12 in one sweep behind it.
6. Features 16.2 → 16.4 → 16.3 → 16.5, revisiting order after 9 ships.

Every chain closes by promoting its items into `TODO.md` through `/project-tasks` and by marking
the corresponding entries here as shipped, with the PR number.
