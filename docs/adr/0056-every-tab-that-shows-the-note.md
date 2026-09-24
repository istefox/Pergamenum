# ADR-0056: An external change, a rename and a trash reach every tab that shows the note

- Status: proposed, on the branch `kepler/fix/415-vaultcontroller-reconcile-drops-edits`.
  Accepted when that branch merges to `main`.
- Date: 2026-09-23. Written **after** the implementation, against `1a56ed99` plus its
  uncommitted diff (`Sources/App/VaultController+Tabs.swift`,
  `Sources/App/VaultController+Watching.swift`, new `Tests/VaultControllerReconcileTests.swift`).
  "Before" line numbers are read from `git show HEAD:`, "after" ones from the working tree; none
  is recalled from the ticket.
- **Numbering note:** `0055` is the highest file under `docs/adr/`, and
  `git log --all -- 'docs/adr/0056*'` returns nothing. The only `ADR-0056` string in the tree
  before this file is the new test file's header, which anticipates it.
- Source: `TODO.md` **`PG-211`** (P3, fix) → issue **#415** (#417 was a duplicate promotion of
  the same ticket, closed). Named and deliberately left open by ADR-0055 §D5 and by its Context
  paragraph «The real gap is narrower and different».
- **Extends ADR-0012 §D2/§D4 and closes ADR-0055 §D5; amends neither.** §D2's facade (`openNote`
  is the focused tab) and §D4's two columns stand as written. What changes is which question four
  verbs ask of them.
- **Reopens nothing else.** No on-disk format, no frontmatter key, no `IndexCache.schemaVersion`
  bump (stays 4), no protected interface, no connector surface: `Sources/App` is not in
  `sharedSources`, so `perg` and `pergamenum-mcp` compile none of it.
- **GUI-test budget: zero.** Everything below is observable on `VaultController` in-process.

---

## Context

### Three verbs asked the focused column a question about a path

ADR-0012 §D2 kept `openNote` as a facade over the focused tab, and `tabs` is «the tabs of the
focused column». Both are right for the readers that mean «what the person is looking at». They
are wrong for a verb whose trigger is a *path*: a file changing on disk, a rename, a trash.
ADR-0012 §D4 lets one path be open in both columns, and nothing stops it sitting in a background
tab of either. Three verbs had drifted into asking the focused column only:

| Verb | Before (`HEAD`) | Read | Consequence |
|---|---|---|---|
| `reconcile(_:)` | `VaultController+Watching.swift:28` | `guard var note = openNote, note.relativePath == change.path` | an external change to a background tab or to the other column dropped: no reload when clean, no ADR-0001 §D3.4 banner when dirty, and the next save overwrote it (#415) |
| `movedNote(from:to:)` | `VaultController+Tabs.swift:299-310` | `tabs` | a tab in the other column kept a path with no file behind it |
| `trashedNote(at:)` | `VaultController+Tabs.swift:313-315` | `tabs`, then `closeTab`, itself focused-column only (`:222-224`) | a tab in the other column kept showing a trashed note |

### The precedent was already in the layer

`canOperate(on:)` (`VaultController+Files.swift:18-29`) asks `columns.contains { column in
column.tabs.contains { … } }`: every column, every tab. It is also what makes widening `movedNote`
safe at note level. `NoteTab.showing(_:)` replaces the buffer wholesale, which is harmless only
because `canOperate(on:)` has already refused a rename or move while any tab on that path is
dirty. The guard asked every column; its follow-up asked one.

---

## Decision

### §D1 - One door, `updateTabs(showing:_:)`

```swift
func updateTabs(showing relativePath: String, _ change: (inout NoteTab) -> Void)
```

`VaultController+Tabs.swift:260`. `updateTab(_:_:)`'s shape without the `focusedColumnIndex`
constraint: `change` is applied to every tab whose note is at `relativePath`, in every column. It
lives in that file because `columns` is written only from there (`VaultController.swift:35-41`,
`VaultController+Tabs.swift:95-100`). `updateFocusedTab` and `updateTab` are unchanged.

### §D2 - `reconcile` goes through it

The per-tab logic is the one it already had: dirty sets `externalChangePending` (never merge,
never discard: ask), clean adopts `text` and `savedText`. It now runs on every tab showing
`change.path` instead of on `openNote`, and `replaceOpenNote` is no longer called here. No
`rememberTabs()`: the stored session is paths, preview flags and the active path
(`VaultController+Session.swift:12-28`, ADR-0012 §D10), never the buffer.

### §D3 - `movedNote` and `trashedNote` read every column

`movedNote` guards on `columns.contains(…)`, reads `newPath` once, and applies `$0.showing(note)`
through §D1. `trashedNote` collects the matching ids from every column first and only then calls
`closeTab` on each, because closing shifts the indices a loop over the columns would still be
walking. The `recentNotePaths` and `closedTabPaths` steps are unchanged.

### §D4 - `closeTab` finds the tab in whichever column holds it

Needed by §D3's `trashedNote`. The column is found by id, the «front goes to the tab before it»
rule applies to that column, and `focusedColumnIndex` is never touched. The three UI call sites
(`EditorColumn+Closing.swift:29,46,54`) already wrap the call in `focused { }`, and a tab id is a
`UUID` (`NoteTab.swift:14`), so they resolve to the same tab as before.

### §D5 - Every close is remembered, after the new front is picked

Before, `guard wasFocused else { return }` (`:229`) returned ahead of `rememberTabs()`, so closing
a background tab (its close button on the tab bar, or `trashedNote`) was not persisted until some
other door ran, and a relaunch in between reopened it. The plan proposed moving `rememberTabs()`
above that guard. **Not done, on purpose:** `rememberTabs()` records
`column.active?.note.relativePath` (`VaultController+Session.swift:21`), and when the closed tab
was the active one, `activeID` still names the removed tab at that point, so `active` is nil and
the column would be saved with no active path. The guard became `if wasActive { pick the
neighbour }`, and `rememberTabs()` runs after it on every close.

### §D6 - Left as they are, deliberately

- `openNote(at:)`'s dedupe reads `tabs` (`VaultController+Tabs.swift:290`). It answers «where does
  this click land», and the answer is the focused column; a note already open in the other column
  is opened here too, which is what a split is for.
- `tabs` (`:355`) stays «the focused column's tabs»: the tab bar, `selectTab` and `restoreTabs`
  ask for exactly that.
- `updateTab(_:_:)` stays focused-column scoped. Its remaining callers are `updateFocusedTab` and
  `restoreTabs` (`VaultController+Session.swift:45`), both focused by construction. Its doc
  comment's reason («a rename reaches a tab nobody is looking at») now describes §D1's job rather
  than its own.

### §D7 - Two more places with the same shape, found and fixed in this same chain; a third filed separately

Found while checking this record against the shipped diff, after §D1-§D6 had already landed.

1. **`canOperateOnFolder(_:)` asked only `openNote`** (`VaultController+Folders.swift:21-28`), yet
   it is the only guard in front of `renameFolder` (`:42`), `trashFolder` (`:73`) and a batch
   folder move (`VaultController+Move.swift:173`), and all three now reach every column through
   §D3. A dirty tab under the folder that is not the focused one passed the guard; a rename then
   replaced its buffer with the disk text through `showing(_:)`, and a trash closed it without
   ADR-0012 §D3's dialog. A background tab in the focused column already lost its edits that way
   before this chain; a tab in the *other* column was left on a dead path instead, still holding
   its text. This chain would have turned that second case from «stranded» into «discarded» had it
   shipped unfixed. **Fixed**: `canOperateOnFolder` now asks `columns.contains { column in
   column.tabs.contains { … } }`, `canOperate(on:)`'s own shape, guarded by
   `Tests/VaultControllerReconcileTests.swift`'s
   `trashFolderRefusesWhileANoteUnderItIsDirtyInTheOtherColumn`.
2. **The conflict banner's buttons acted on the focused column.**
   `EditorColumn+Conflict.swift:17-18` called `acceptExternalChange` and `keepLocalVersion`
   directly; both read `openNote` or go through `updateFocusedTab`
   (`VaultController+Editing.swift:93-104`), and neither went through the column's `focused { }`
   (`EditorColumnView.swift:173-176`), the door the file's own doc comment says every write in it
   goes through. Before this chain a banner showed in a non-focused column only after the person
   moved focus away from it; now that is the ordinary way one appears. **Fixed**: both buttons now
   call `focused(vault.acceptExternalChange)` / `focused(vault.keepLocalVersion)`, so a click first
   focuses the column the banner is in. Not covered by an automated test - the GUI-test budget for
   this chain is zero (front matter) and an in-process `VaultController` test cannot drive a
   SwiftUI `Button`; the fix is the file's own established pattern, not a new one.
3. **`syncOpenNote(with:)` keeps `reconcile`'s old guard verbatim**
   (`VaultController+Editing.swift:79-80`). It is how ten in-process writes (a task toggle, a
   drop, time blocks, the diary, categories, a URL route, the pratiche composer) catch the editor
   up, and since the session records their hashes, `VaultSession.reconcile` skips them and §D2
   never sees them (the method's own doc comment, `:64-78`, says so). A note open in a background
   tab or in the other column keeps the old text, and a later save from it reverts the write.
   `saveOpenNote()` (`:22-32`) has the sibling shape: saving one copy of a path leaves another copy
   stale and clean. Pre-existing and not widened by this chain; left as its own ticket rather than
   folded in here, the same reasoning ADR-0055 §D5 used to file this whole chain.

---

## Alternatives considered

1. **Fix `reconcile` alone, the ticket's literal scope.** Rejected: `movedNote` and `trashedNote`
   carried the same drift in the same file, and fixing one of three leaves two templates for the
   next verb to copy (ADR-0041's rule).
2. **Make `tabs` return every column's tabs.** Rejected: its readers mean the focused column
   (§D6), and `openNote(at:)` would start jumping to the other column on a click.
3. **Make `openNote` search every tab.** Rejected: ADR-0012 §D2's readers mean «the note the
   person is looking at», and that is what it has to keep returning.
4. **Spell the loop over `columns` inline in each verb.** Rejected: three hand-written nested
   loops are three templates, and `columns` is written only through the doors in
   `VaultController+Tabs.swift`.
5. **Move `rememberTabs()` above the guard in `closeTab`**, as the plan had it. Rejected at §D5:
   it saves the column with a nil active path.

---

## Consequences

### Positive

- An external change is no longer dropped by a tab the person is not looking at: a clean one
  reloads, a dirty one gets ADR-0001 §D3.4's banner (#415).
- A rename follows, and a trash closes, the note in the other column too.
- A folder rename, trash or batch move no longer reaches a dirty tab in the other column without
  asking (§D7.1).
- The conflict banner's own buttons resolve the tab it is actually showing, in whichever column
  that is (§D7.2).
- One door answers «every tab showing this path», and the next verb that needs it calls it.
- Closing a background tab survives a relaunch.

### Negative

- A clean tab in the other column now changes under the person when its file changes on disk.
  The focused tab always did; only the place is new.
- §D7.3 (`syncOpenNote`/`saveOpenNote` and ten in-process writers) is pre-existing, unfixed and
  filed separately - the fixes above narrow it (it no longer competes with a wider folder-level
  data-loss case) but do not close it.

### Neutral

- No on-disk format, schema, protected interface or connector change. One new test file, so
  `tuist generate --no-open` and nothing more.

---

## Acceptance

`Tests/VaultControllerReconcileTests.swift`, nine tests. Every write that must read as external
goes through `TemporaryVault.write`, outside the session, so it never lands in
`selfWrittenHashes` and reaches `reconcile` as a real `ExternalChange`:

- a dirty tab in the other column gets `externalChangePending` and keeps its text;
- a clean tab in the other column adopts `text` and `savedText`;
- a dirty background tab in the focused column gets `externalChangePending`;
- the focused tab, dirty and clean, behaves as before (two regression guards);
- `movedNote` follows, and `trashedNote` closes, a tab in the second column;
- closing a non-active tab persists the session;
- `trashFolder` refuses while a note under it is dirty in the other column, and leaves the file
  and the buffer untouched (§D7.1).

§D7.2's fix (the conflict banner's buttons) is not exercised by an automated test - see the
front matter's zero GUI-test budget and §D7.2 itself for why. §D7.3 is filed separately and
exercised by neither.

---

## References

- `TODO.md` `PG-211` → issue #415; branch `kepler/fix/415-vaultcontroller-reconcile-drops-edits`.
  The plan was a session plan and is not committed under `docs/plans/`; this record replaces it.
- ADR-0055 §D5 and Context («The real gap is narrower and different») -
  `docs/adr/0055-note-write-guard-and-the-dead-rename-performer.md`.
- ADR-0012 §D2 (a tab owns its buffer; `openNote` is the focused tab), §D3 (the close dialog), §D4
  (two columns), §D10 (the remembered session) - `docs/adr/0012-tabs-split-view-and-the-tag-browser.md`.
- ADR-0001 §D3.4 (never merge, never discard: ask); ADR-0043 §D7 (`syncOpenNote`'s conflict
  prompt); ADR-0026 §D10 (the batch move reuses both guards); ADR-0041 (one door rather than a
  step a caller can forget).
- `Sources/App/VaultController+Tabs.swift:217-237`, `:256-267`, `:309-339`;
  `Sources/App/VaultController+Watching.swift:19-43`; `Sources/App/VaultController+Files.swift:18-29`;
  `Sources/App/VaultController+Folders.swift:21-28`; `Sources/App/VaultController+Editing.swift:22-32`,
  `:64-104`; `Sources/Features/Editor/EditorColumn+Conflict.swift`;
  `Sources/Features/Editor/EditorColumnView.swift:96-99`, `:173-176`.
