# ADR-0058: An in-process write, a save and a restore reach every tab that shows the note

- Status: proposed, on the branch `kepler/461-pg-223-syncopennote-focused-tab`. Accepted when that
  branch merges to `main`.
- Date: 2026-09-24. Written **before** the implementation, against `2e529c14` (clean tree). Every
  line number below was read from that tree. None is recalled from the ticket.
- **Numbering note:** `0056` is the highest file under `docs/adr/` on this branch, but
  `origin/main` already has `0057-diary-origin-marker-and-one-write-door.md` (`adc7297a`, PR #488),
  which merged after this branch was cut. `git log --all -- 'docs/adr/0058*'` returns nothing.
  Bring the branch up to `origin/main` before it merges, or the sequence shows a gap.
- Source: `TODO.md` **`PG-223`** → issue **#461**. ADR-0056 §D7.3 named this gap and left it open
  on purpose.
- **Closes ADR-0056 §D7.3. Extends ADR-0056 §D1/§D2 and ADR-0043 §D7. Amends neither.** ADR-0012
  §D2's facade (`openNote` is the focused tab) and ADR-0011's save-first restore stay as written.
  What changes is how far the catch-up after a write reaches.
- **Reopens nothing else.** There is no on-disk format change and no frontmatter key.
  `IndexCache.schemaVersion` stays 4. No protected interface changes, and no connector sees
  different behaviour. One signature in a shared file changes: the return type of
  `VaultSession.addStructuralLink` (§D5). No connector calls it, but `perg` and `pergamenum-mcp`
  compile the file, so both are built as part of acceptance.
- **GUI-test budget: zero.** Everything below can be observed on `VaultController` in-process.

---

## Context

### What ADR-0056 left open

ADR-0056 gave `reconcile`, `movedNote`, `trashedNote` and `canOperateOnFolder` one door that
reaches every tab showing a path, in every column: `updateTabs(showing:_:)`
(`Sources/App/VaultController+Tabs.swift:257-268`). Its §D7.3 found one more method with the old
guard and filed it on its own:

```swift
func syncOpenNote(with result: VaultSession.WriteResult) {
    guard var note = openNote, note.relativePath == result.path else { return }
```

(`Sources/App/VaultController+Editing.swift:79-80`.) This is the only way an in-process write
catches the editor up. The session records the hash of every write it makes, and
`VaultSession.reconcile` drops those writes when FSEvents reports them back (ADR-0001 §D3.3, the
method's own doc comment at `:64-78`). The watcher therefore never tells a tab about a write made
by this app, and after such a write the caller's catch-up is the tab's only chance to learn of it.
`syncOpenNote` gave that chance to the focused tab only.

It has ten callers, all of them app writes to a `.md` file:

| Caller | Line | Write |
|---|---|---|
| `VaultController+Tasks.swift` | `:20` | a task toggle, reschedule or cancel (`apply(_:to:)`) |
| `VaultController+Tasks.swift` | `:66` | quick capture (`captureTask(_:)`) |
| `VaultController+TaskDrop.swift` | `:33` | a task dropped on a day |
| `VaultController+TimeBlocks.swift` | `:40` | `setTimeBlocks` |
| `VaultController+TimeBlocks.swift` | `:61` | `addTimeBlock` |
| `VaultController+TimeBlocks.swift` | `:97` | the daily note gaining an event-note link |
| `VaultController+Diary.swift` | `:29` | the diary |
| `VaultController+Categories.swift` | `:86` | category link and unlink |
| `VaultController+Routes.swift` | `:133` | the `pergamenum://` capture route |
| `Sources/Features/Pratiche/PraticaEntryComposer.swift` | `:130` | a pratica entry (`handOff`) |

A note can be open in both columns (ADR-0012 §D4). It can also be open twice in one column,
because `openNoteInNewTab` and `reopenClosedTab` do not deduplicate (`VaultController+Tabs.swift:362-367`,
`:65-68`). A copy of the note that is not the focused tab keeps the old text. If that copy is
clean, the next edit and save from it writes the old text back and silently reverts the app's
write. If it is dirty, nobody asks the person, which is exactly what ADR-0001 §D3.4 forbids.

### The sibling shapes: checked, not assumed

The issue says `saveOpenNote()` "has the sibling shape". Fixing it could mean two different
things, so both were checked.

**Which buffer a save writes is correct and stays as it is.** `saveOpenNote` has five callers,
and each is a save gesture on the focused buffer:

- Cmd+S (`CommandActions.swift:180`). Its `canRun` is `openNote?.hasUnsavedChanges`
  (`CommandActions+CanRun.swift:34-35`).
- The tab bar's save chip (`NoteTabBar.swift:77`), behind `focus { }`.
- The outline move's follow-up save (`EditorColumn+Text.swift:142`), in the column that did the
  move.
- «Salva» in the close dialog (`EditorColumn+Closing.swift:39-49`), which calls `focusTab(tab.id)`
  before it awaits the save.
- `restoreVersion` (`VaultController+Editing.swift:50`).

`Tests/NoteTabTests.swift:193` (`savingWritesTheFocusedTabAndNotTheOther`) pins this down. No
caller wants a background buffer saved.

**What happens after the write is wrong, in two ways:**

1. *Other copies of the path.* The write is self-hashed, so the watcher never reports it. A
   second copy of the note stays clean and stale, and saving from it later reverts this save. A
   dirty second copy is never asked. ADR-0056 §D7.3 described this: "saving one copy of a path
   leaves another copy stale and clean".
2. *The tab written back to after the `await`.* `saveOpenNote` takes a copy of `openNote`,
   awaits `session.write`, and then calls `replaceOpenNote(note)` (`:28`), which means
   `updateFocusedTab { $0.note = note }`. The focused tab is looked up when the method resumes,
   not when the save started, and it receives the whole snapshot from before the `await`,
   including `relativePath`. If the focus moved during the suspension, the other tab's note is
   replaced by this one, and that tab's unsaved edits are lost. If the person kept typing, the
   new keystrokes are reverted. This is the shape named in CLAUDE.md's working agreement "A
   precondition evaluated before an `await` is a filter, not a guard". *This has not been seen
   happen. It follows from reading the code.* The window is one actor hop plus a disk write.

`restoreVersion(_:)` (`:48-62`) has both problems. Other copies stay stale. It also re-reads
`openNote` after `await saveOpenNote()` (`:51-52`) and writes the past version to that tab's
path. If the focus moved in between, one note's past version would be written over a different
note.

The same layer has a fourth writer that no ticket names: **`addStructuralLink`**
(`VaultController+Notes.swift:67-85`). It catches up with `reloadFocusedNote()`
(`VaultController+Tabs.swift:305-308`), and only when the focused note is the source. That method
replaces the whole buffer with the text on disk. The command is enabled on a dirty note
(`canRunOnOpenNote`, `CommandActions+CanRun.swift:136-139`, checks only that a note is open). The
sheet takes the focused note as the source (`RelatedLinkSheet.swift:84-99`). The session builds
the link from the disk text (`VaultSession+Notes.swift:183`). So «Collega» on a note with unsaved
edits **discards those edits**, which is a direct breach of ADR-0001 §D3.4, not just a stale copy.
The target note, written at `:197`, is not caught up anywhere, in any tab.

### A wider gap: measured, and left for its own record

The shapes above all make the same mistake: they catch up, but only the focused tab. A second
group of writers has a different shape: **they never catch the editor up at all**, not even the
focused tab. They write through the same self-hashed door, so the watcher is silent about them
too. The cases checked:

| Writer | Where | What stays stale |
|---|---|---|
| A note rename rewriting `[[Old]]` in every note that links to it | `VaultController+Files.swift:36-61` | A tab showing a linking note keeps `[[Old]]`. `movedNote` (`:52-55`) follows only the renamed note. |
| `renameTag` | `VaultController+Files.swift:164-168` | Every tab showing a retagged note |
| `undoJournalledWrites` | `VaultController+Files.swift:170-174` | Every tab showing a note the undo restored |
| `moveOnBoard` | `VaultController+Files.swift:185-189` | A tab showing the dropped note keeps its old `status-*` tag |
| Pratiche `^id` allocation (`ensuringLocalID`) | `Sources/Features/Pratiche/PraticaCommandActions+Links.swift:195` | The task's source note. A save removes the `^id`, and the pratica link loses its target. |
| The pratica composer's diary mirror | `Sources/Features/Pratiche/PraticaEntryComposer.swift:103` | The daily note |
| Plaud re-import | `Sources/Features/Recordings/RecordingsController+Import.swift:65` | The recording note |

§D7 records why these are not fixed here.

---

## Decision

### §D1: One per-buffer rule, `OpenNote.catchUp(to:)`

```swift
extension VaultController.OpenNote {
    mutating func catchUp(to incoming: String)
}
```

The method goes in `Sources/Vault/NoteTab.swift`, next to `OpenNote`. That file is app-only and
not in `sharedSources`. The rule is ADR-0001 §D3.4 applied to one buffer:

- **dirty** (`hasUnsavedChanges`): `externalChangePending = incoming`. `text` and `savedText` are
  left alone. The app never merges and never discards: it asks.
- **clean**: `text = incoming`, `savedText = incoming`, `externalChangePending = nil`.

Two places currently spell this rule out word for word: `reconcile`'s closure
(`VaultController+Watching.swift:33-41`) and `syncOpenNote`'s body (`:81-88`). Both switch to
`catchUp(to:)`, so the rule is written once.

The clean branch also clears a stale `externalChangePending`. Neither current copy does that. A
buffer can be clean while a prompt is still pending if the person undoes their edits back to
`savedText` after the banner appears. Once that buffer has adopted the newest text on disk, an
older incoming text has nothing left to ask about. `restoreVersion` already clears the prompt this
way (`:57`). For `reconcile` this is a deliberate, small widening.

### §D2: `syncOpenNote(with:)` catches up every tab that shows the path

```swift
func syncOpenNote(with result: VaultSession.WriteResult) {
    updateTabs(showing: result.path) { $0.note.catchUp(to: result.text) }
}
```

ADR-0056 §D1's door, with §D1's rule applied to each tab. Each tab decides dirty or clean for
itself; no tab's state decides for another. The method keeps its name and signature, so none of
the ten call sites or the two direct test callers changes
(`Tests/VaultWriteOrderingBatch3Tests.swift:129,146`). It stops calling `replaceOpenNote`. As in
ADR-0056 §D2, there is no `rememberTabs()` call: the session that gets remembered holds paths,
never buffers.

### §D3: `saveOpenNote()` finds the tab that saved by identity after the `await`

The save still writes the focused buffer (see Context). The change is to what happens after the
write:

```swift
func syncOpenNote(with result: VaultSession.WriteResult, savedBy writer: NoteTab.ID)
```

`saveOpenNote` records `focusedTab`'s `id` and note before the `await` and passes the id here
after it. The method goes through `updateTabs(showing: result.path)`:

- **The tab whose `id == writer`:** `savedText = result.text` and `externalChangePending = nil`.
  **`text` is not touched.** If nothing was typed during the suspension, `text == result.text` and
  the tab is clean. If something was typed, the tab stays dirty with the newer text, which is what
  it really is.
- **Every other tab showing the path:** §D1's rule.

The writer is found by `id` in every column, and is not assumed to be the focused tab when the
method resumes. Because the path is part of the filter, a writer tab that was closed or started
showing another note during the suspension is skipped rather than overwritten.
`closeAfterSaving`'s "focus, await the save, then close by id" sequence is unaffected.

This overload is `internal` on purpose. It is the half of the save that runs after the `await`,
exposed so a test can move the focus first and then call it, with no timer and no gate. This is
the approach of ADR-0046 §D11 and of `PraticaEntryComposer.handOff`, which ADR-0043 §D7 made
non-private for the same reason. `Sources/Vault/VaultDisk.swift` has no seam that could suspend a
write in the middle, and adding one would put test machinery on the write door.

### §D4: `restoreVersion(_:)` records its path first, then uses §D2

`restoreVersion` reads the focused note's `relativePath` **before** `await saveOpenNote()`. It
writes the past version to that path and then calls `syncOpenNote(with: result)` (§D2). That call
reaches every tab showing the path, **the writer's own tab included**. The re-read at `:51-52` is
removed.

After a successful save the writer's tab is clean, so §D1 adopts the restored text. That is
today's behaviour, and `Tests/NoteHistoryTests.swift`'s two restore tests stay green. If the save
failed, or the person typed during either `await`, the tab is dirty and gets the §D3.4 prompt
instead of losing the edits. This is the promise the method's own doc comment makes (`:36-43`),
now kept on the one path that used to break it.

### §D5: `addStructuralLink` reports what it wrote, and `reloadFocusedNote()` is removed

`VaultSession.addStructuralLink` (`Sources/Vault/VaultSession+Notes.swift:161-203`) changes its
return type from `Bool` to:

```swift
(created: Bool, written: [VaultSession.WriteResult])
```

- `created` means what the old `Bool` meant: both writes landed.
- `written` holds every write that reached disk, in order. If the target write fails after the
  source write succeeded, it holds the source's result, so the editor catches up with the half
  that landed. Otherwise a later save from a stale buffer would silently undo it.

`VaultController.addStructuralLink` passes each result to `syncOpenNote(with:)` (§D2) and returns
`created`. The controller's `Bool` signature stays the same, so `RelatedLinkSheet` and
`Tests/RelatedLinkTests.swift` do not change.

A focused dirty source now gets the §D3.4 prompt instead of losing its edits. A target open in any
tab is now caught up.

`reloadFocusedNote()` has no caller left and is **deleted**. It was a focused-only door that
replaced the whole buffer, and leaving it would give the next writer the wrong door to copy
(ADR-0055 §D6 deleted a dead door for the same reason).

This does not change whether the pair of writes is atomic. The session's "atomic by construction"
comment is about rendering both texts before writing either. A target write that fails after the
source write succeeded is a separate, existing issue.

### §D6: Left as they are, deliberately

- **`bufferText(for:)`** (`VaultController+TimeBlocks.swift:19-24`) stays focused-only. It picks
  the buffer a composed write (`preferring:`) starts from. When two copies of a path hold
  different unsaved text there is no single right answer, and the focused copy is the one the
  person is looking at: the same category of reader as ADR-0056 §D6. After this chain, the copy
  the write did not start from gets the §D3.4 prompt from §D2 instead of going stale without a
  word.
- **`noteText(at:)`** (`VaultController+Notes.swift:45-50`), used for the quick switcher's
  headings, is a reader of the focused column and stays that way.
- **`acceptExternalChange` / `keepLocalVersion`** (`VaultController+Editing.swift:93-104`) settle
  the banner the person clicked. Since ADR-0056 §D7.2 they are reached through the column's own
  `focused { }`, so "focused" already means "the tab whose banner was clicked".
- **`replaceOpenNote`** stays, and `acceptExternalChange` is now its only caller. `openNote`,
  `tabs`, `updateTab` and `updateFocusedTab` are unchanged (ADR-0056 §D6).
- **The name `syncOpenNote`** stays. It now catches up every tab, and its doc comment says so.
  Renaming it would touch ten call sites, two tests and every record that uses the name, and would
  change no behaviour.

### §D7: Named here and not fixed: writers that never catch the editor up

The writers in Context's last table are not changed by this chain. The fix for them is probably
structural rather than a per-call-site one: `VaultSession.write` (the single door every write goes
through, ADR-0043 §D1) would tell the controller about each `.md` write, and the controller would
apply §D2. `syncOpenNote` is a separate step that each caller has to remember, and seven callers
forgot it. That is exactly the failure CLAUDE.md's ADR-0041 working agreement predicts. It is not
done here for three reasons:

- `VaultSession.swift` is in `sharedSources`, so the hook must stay inert under `perg` and
  `pergamenum-mcp`.
- The table covers writers governed by five other records: ADR-0012 §D7, ADR-0009 §D5, ADR-0036,
  ADR-0049 and ADR-0032.
- A batch writer such as a tag rename across forty notes raises a product question for Stefano:
  whether forty dirty tabs should get forty banners or a single summary.

Nothing in this chain becomes throwaway if that change happens later: §D1 and §D2 are exactly what
such a hook would call. This should be filed as its own ticket, and the orchestrating session
files it.

---

## Alternatives considered

1. **Fix `syncOpenNote` alone, which is the literal first sentence of the ticket.** Rejected.
   `saveOpenNote` and `restoreVersion` in the same file miss the same tabs, and `addStructuralLink`
   is a worse copy of the same mistake. Fixing one of four leaves three examples for the next
   writer to copy. This is ADR-0056's Alternative 1, for the same reason.
2. **Treat `saveOpenNote` as not a bug, on the grounds that a save only ever concerns the focused
   buffer.** Checked against all five callers (Context) and partly accepted: the focused tab is
   the right *target*, and §D3 keeps it. Rejected as a reason to leave the method alone, because
   the *effects* of the save reach every copy of the path, and because of the lookup after the
   `await`.
3. **Apply §D1's rule to every copy after a save, the writer included.** This would be one uniform
   rule with no special case. Rejected: when the method resumes, the writer's `savedText` is still
   the old text, so the tab is dirty and would show a conflict banner against its own save.
4. **Add the `VaultSession.write` notification now (§D7) and remove the ten explicit calls.**
   Rejected for this chain, for §D7's three reasons. It stays the recommended follow-up.
5. **`addStructuralLink` saves the buffer first, as `restoreVersion` does, instead of raising the
   prompt.** This is a real UX option: the link would be built on top of the person's edits, with
   no banner. Rejected as the default, because it is an implicit save under an explicit-save model
   (ADR-0012 D3). `restoreVersion` justified its own implicit save by the history it protects, and
   the link has no such reason. The choice is Stefano's to make and is reported to him. §D5 is the
   conservative option until he decides.
6. **The controller finds the target path itself (`index.resolve(title:)`) instead of the session
   returning its writes.** Rejected. It would duplicate the session's own resolution at `:173` in a
   second place that could drift from it. ADR-0043's composer rule is to use the write's own result
   and never read the file again.
7. **Rename `syncOpenNote`.** Rejected in §D6.

---

## Consequences

### Positive

- A task toggle, drop, time block, diary entry, category link, URL capture or pratica entry now
  reaches the note in a background tab or in the other column. A clean copy updates to the new
  text. A dirty copy gets ADR-0001 §D3.4's banner.
- A save or a restore from one copy reaches the other copies. The last save no longer silently
  overwrites them.
- The save no longer updates whichever tab has the focus when it resumes, and keystrokes typed
  while a save is suspended are kept.
- The «Collega» sheet no longer discards unsaved edits, and the target note is caught up.
- The per-buffer rule is written in one place, `catchUp(to:)`, instead of two.

### Negative

- More banners. Each one is a real conflict that used to be settled silently by whichever save
  came last.
- A clean tab in the other column now changes under the person after an in-process write. For
  external changes this already happens (ADR-0056's first negative). Only the kind of trigger is
  new.
- A person who links a note with unsaved edits now sees a banner straight away (§D5). This is
  arguably clumsier than saving first. Alternative 5 remains open for Stefano to decide.
- §D7's writers are still unfixed. This chain makes the problem narrower but does not close it.

### Neutral

- No format, schema, protected-interface or connector change. There is one new test file, so run
  `tuist generate --no-open`.
- `VaultSession+Notes.swift` is a shared file, so `perg` and `pergamenum-mcp` are built even
  though neither calls the method whose return type changes.
- ADR-0057's line "`syncOpenNote`'s editor prompt is unchanged and still fires when the diary file
  is the focused note" becomes: it fires for every tab that shows the diary file.

---

## Acceptance

`Tests/VaultControllerWriteCatchUpTests.swift`, fifteen tests, all in-process. Once the plan's
Task 1 has declared the new signatures with empty bodies, every test except 7 is red. Test 7
guards behaviour that must not change.

1. **`catchUp` on a dirty buffer** sets `externalChangePending`. `text` and `savedText` do not
   change.
2. **`catchUp` on a clean buffer** adopts `text` and `savedText` and clears the prompt.
3. **`catchUp` on a clean buffer with a stale prompt** clears it.
4. **`syncOpenNote`, dirty tab in the other column:** the tab gets the prompt and keeps its text.
5. **`syncOpenNote`, clean tab in the other column:** the tab adopts the new text.
6. **`syncOpenNote`, dirty background tab in the same column:** the tab gets the prompt.
7. **`syncOpenNote`, tab showing a different path:** not touched. This is a guard.
8. **End to end through a real writer:** `toggle(_:)` on a task whose note is open only in the
   column without focus. That column's tab shows the rewritten line.
9. **`saveOpenNote`, clean copy in the other column:** the copy adopts the saved text.
10. **`saveOpenNote`, dirty copy in the other column:** the copy gets the prompt with the saved
    text and keeps its own text.
11. **`syncOpenNote(with:savedBy:)` after the focus has moved to another note's tab:** the writer
    tab is clean, and the tab that now has the focus keeps its path and its text.
12. **`syncOpenNote(with:savedBy:)` after text was typed into the writer tab after the write:** the
    tab stays dirty with the newer text, `savedText == result.text`, and there is no prompt.
13. **`restoreVersion`, clean copy in the other column:** the copy shows the restored text.
14. **`addStructuralLink` with a dirty focused source:** the buffer text is kept and
    `externalChangePending` equals the linked text on disk.
15. **`addStructuralLink` with the target open, clean, in the other column:** the target's tab
    shows the return link.

These existing tests must stay green without being edited, as regression guards:

- `Tests/VaultControllerReconcileTests.swift` (9 tests: §D1 reaches `reconcile`)
- `Tests/VaultWriteOrderingBatch3Tests.swift`'s `syncOpenNote` and composer `handOff` tests
- `Tests/NoteTabTests.swift`'s `savingWritesTheFocusedTabAndNotTheOther`
- `Tests/NoteHistoryTests.swift`'s two restore tests
- `Tests/VaultTests.swift`'s `editsAndSavesANoteWithoutCorruptingIt`
- `Tests/RelatedLinkTests.swift` (3 tests)

---

## References

- `TODO.md` `PG-223` → issue #461. ADR-0056 §D7.3 and its second Negative consequence:
  `docs/adr/0056-every-tab-that-shows-the-note.md`.
- ADR-0001 §D3.3 and §D3.4. ADR-0011 (save-first restore). ADR-0012 §D2, §D3 and §D4. ADR-0041
  (one door rather than a step a caller can forget). ADR-0043 §D1 and §D7 (the prompt in
  `syncOpenNote`). ADR-0046 §D11 (named seams for tests). ADR-0055 §D6 (a dead door is deleted).
  ADR-0057 (Neutral, on `origin/main`).
- `Sources/App/VaultController+Editing.swift:22-32`, `:48-62`, `:79-90`, `:93-104`.
- `Sources/App/VaultController+Watching.swift:29-43`.
- `Sources/App/VaultController+Tabs.swift:257-276`, `:300-308`, `:362-367`.
- `Sources/App/VaultController+Notes.swift:45-50`, `:67-85`.
- `Sources/Vault/VaultSession+Notes.swift:161-203`. `Sources/Vault/NoteTab.swift:78-90`.
- `Sources/App/VaultController+TimeBlocks.swift:19-24`.
- `Sources/Features/Editor/RelatedLinkSheet.swift:84-99`.
- `Sources/App/CommandActions+CanRun.swift:34-35`, `:136-139`.
