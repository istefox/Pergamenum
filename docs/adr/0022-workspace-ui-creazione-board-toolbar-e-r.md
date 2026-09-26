# ADR-0022: Creating, renaming and deleting a workspace is a folder operation, performed outside the journal

- **Status:** Accepted. Landed on `main` via PR #104 (merge `cc4c372`,
  2026-08-25).
- **Date:** 2026-08-25
- **Supersedes / extends:** nothing. Delivers the follow-up ADR-0021 §D3 named and declined to build
  ("a canvas-rename UI is named here as a follow-up somebody may or may not want").
- **Plan:** `docs/superpowers/plans/2026-08-25-workspace-ui-creazione-board-toolbar-e-r.md`
- **Base read:** every file:line below was read at `7ffd5fd`.

**Scope note (2026-09-16, ADR-0047):** the Obsidian round-trip is no longer a binding
constraint. The decision below stands as taken and the format it chose is unchanged; what no
longer applies is the obligation that a future change keep Obsidian able to read the result.
Body untouched.

---

## Context

The Workspace sidebar can open a board and nothing else. There is no way to create one from the
Workspace UI (only File → «Nuova board», `PergamenumApp.swift` → `vault.beginNewBoard()` →
`WorkspaceView.checkPendingNewBoard()`), no way to name a board explicitly under a chosen parent,
and no way to rename or delete one at all. This ADR decides how those three verbs work.

Twelve facts constrain the design. They were read from the code, not recalled, because three of
the SPEC's own statements about this repository turn out to be false (F3, F7 below) and designing
on top of them would have produced a feature that rewrites nothing and journals a directory.

**F1 — A workspace is a folder, and its board is named after that folder.**
`CanvasStore.boardPath(forFolder:)` (`Sources/Vault/CanvasStore.swift:21-28`) derives the board's
file name from the folder's last path component (`01 Progetti/vibrofer-emea` →
`01 Progetti/vibrofer-emea/vibrofer-emea.canvas`); the root folder's board is named after the
vault. Renaming the folder without renaming the `.canvas` inside it leaves
`boardPath(forFolder:)` pointing at a file that is no longer there, and `load(folder:)`
(`CanvasStore.swift:37-43`) returns `.empty` rather than failing: **the board silently reads as
blank while its content sits on disk under the old name.** This is the single most damaging
failure mode of the feature and the reason D5 exists.

**F2 — There is no folder rename or folder delete anywhere in the vault layer.**
`CanvasStore.createFolder(named:in:)` (`CanvasStore.swift:139-147`) is the only folder-shaped write
in the app; it refuses an existing path with `StoreError.alreadyExists` and deliberately does not
create intermediate directories. `NoteFileOperations` is note-only. This feature introduces the
vault's first folder rename and first folder delete.

**F3 — A wikilink names a note by *title*, not by path.**
`IndexSnapshot.resolve(title:)` (`Sources/Index/IndexSnapshot.swift:99-102`) resolves through a
lowercased title index; `NoteFileOperations.move` says it in the code itself
(`Sources/Vault/NoteFileOperations.swift:270-273`): *"No link rewriting: a wikilink names a note by
title, not by path (wikilink.md W-01)"*. Moving a folder changes no note's title. **No `[[Nota]]`
link in the vault needs rewriting after a folder rename.** SPEC R-06 — "every wikilink … that
pointed to a note under the renamed folder is rewritten to the new path" — describes a rewrite this
codebase's link model has no target for. The requirement is not dropped; it is satisfied against
the reference classes that really do break (F4, F5) plus a regression test that pins the invariant
(D2).

**F4 — What *is* path-shaped: `.canvas` node file paths.**
A `CanvasNode.kind == .file(path:subpath:)` holds a vault-relative path, built as
`folder.isEmpty ? name : "\(folder)/\(name)"` (`CanvasStore.swift:83`).
`NoteFileOperations.repointBoards` (`NoteFileOperations.swift:300-324`) already repoints those for
a single note, and its doc comment records why it exists: *"renaming a note left its card on the
root board pointing at a file that no longer existed"*. A folder rename moves N files at once, so
every board in the vault holding a card for any of them is stale.

**F5 — What is also name-shaped: the folder's own board file name.**
A task assigned to a workspace carries `^[[<name>.canvas]]` and
`IndexSnapshot.tasks(assignedToWorkspace:)` (`IndexSnapshot.swift:188`) matches the **file name**,
lowercased — not the path. `WorkspacePicker`'s own doc comment states it: *"What is written is the
board's file name, not its vault-relative path"*. The same is true of an ordinary
`[[<name>.canvas]]` wikilink written by «Collega nota o board…» (`TaskParser+Writes.swift:94`).
Renaming a folder renames exactly one board file (F1), so exactly those references change.

**F6 — The marker rewrite is already implemented and costs one function call.**
ADR-0021 §D3: `NoteRename.rewritingLinks` replaces `link.range`, which for a non-embed link starts
at `[[`; the caret sits outside the replaced range. `TaskParser.annotatedLinks`
(`Sources/Core/Tasks/TaskParser.swift:174-183`) confirms the geometry from the other side — it
reads the caret at `body[body.index(before: link.range.lowerBound)]`. Rewriting `Vecchio.canvas` to
`Nuovo.canvas` turns `^[[Vecchio.canvas]]` into `^[[Nuovo.canvas]]` **with no new code**.

**F7 — The journal cannot describe a directory, and the SPEC is wrong about the note delete.**
`WriteJournal.Entry` has three kinds. `.move` is preflighted by comparing `currentHash(at:)` to
`hashAfter` (`VaultSession+Journal.swift:236-245`), and `Data(contentsOf:)` on a directory URL
fails, so a directory-move entry can never pass preflight — it would block the undo of every other
entry in the same gesture. `.removal` restores from `textBefore`, one file's text
(`VaultSession+Journal.swift:106-140`); a tree has none. Separately, the SPEC's claim that the
existing single-note delete "is not journaled either" is false: `trashNote` runs inside
`transaction("note trash")` and records a `.removal` carrying the whole text (ADR-0016 §D3).

**F8 — Writing directly, without the journal, is an established half of this layer.**
`NoteFileOperations.swift:67-75`: *"`rename`, `move` and `trash` above write directly and stay
exactly as they were, for the callers — this file's own tests included — that have no journal to go
through."* A folder operation that writes directly is not a new pattern in this file.

**F9 — An accessibility identifier on a macOS container propagates onto its descendants.**
Recorded at `WorkspaceBrowser.swift:195-203` for `DisclosureGroup` (found by exporting a UI
hierarchy, the same way the `task-project-group` fix was), and the browser's `header` already
carries `.accessibilityElement(children: .contain)` plus
`.accessibilityIdentifier("workspace-browser-header")` (`WorkspaceBrowser.swift:62-64`). A button
placed inside that container risks answering to the header's identifier instead of its own — and
CLAUDE.md makes finding a control by its words a rule violation, so the identifier is the only
handle a UI test has.

**F10 — The board autosaves about a second after a change.**
`WorkspaceController.autosaveDelay` (`WorkspaceController.swift:113`), with `flushPendingSave()`
already called on `.onDisappear` and inside `open(folder:)`. A rename or a delete performed under a
board with a pending save lets that save land on the old path afterwards — recreating the directory
that was just renamed away, or resurrecting a `.canvas` inside a folder that was just trashed.

**F11 — Call sites, already grepped.** `WorkspaceBrowser(` has exactly one
(`WorkspaceView.swift:43`). The identifiers UI tests depend on are `workspace-filter` and
`workspace-board-<path>` (`UITests/WorkspaceIntegrationUITests.swift:150,155`).

**F12 — Target membership is decided by globs, except for `Sources/Vault`.**
`Project.swift:139-141`: the app is `Sources/**` minus `Sources/CLI/**` and `Sources/MCPServer/**`.
`Project.swift:72-106`: `sharedSources` names each `Sources/Vault` file individually. A new file
under `Sources/Vault/` is therefore in the app automatically and **out of both connectors unless
somebody names it**. The unit target is the `Tests/**` glob (`Project.swift:155`).

---

## Decision

### D1. One new rules type, `FolderFileOperations`, modelled on `NoteFileOperations`'s direct-write half

`Sources/Vault/FolderFileOperations.swift` holds everything a folder verb needs to *decide*:
validation, collision, content counts, and a `FolderRenamePlan` computed without touching disk, in
the shape `NoteFileOperations.renamePlan` already has (`FileChange(path:before:after:)` triples).
It also performs, directly through `FileManager` and `NoteStore`, exactly as
`NoteFileOperations.rename/move/trash` still do (F8).

`Sources/Vault/VaultSession+Folders.swift` is the thin session wrapper: it calls the operations,
remaps the stars of every moved note (`moveStar`, `VaultSession+Starred.swift:37`), forgets the
stars of every trashed one, and returns the moved/trashed note lists the facade needs.
`Sources/Vault/VaultController+Folders.swift` is the facade: it refuses while a note under the
target folder has unsaved edits (the folder-scoped twin of `canOperate(on:)`,
`VaultController+Files.swift:14-19`), reports failures through `recordProblem`, calls
`movedNote(from:to:)` / `trashedNote(at:)` per note so tabs and RECENTI follow
(`VaultController+Tabs.swift:310-332`), and rescans.

**None of the three files is added to `sharedSources`** (F12), so `perg` and `pergamenum-mcp` are
byte-identical after this change. That is not an oversight; see D6.

### D2. R-06 is satisfied against the reference classes that actually break, and pinned by a test

A folder rename rewrites:

1. every `.canvas` node whose `file` path starts with `<old>/`, in **every** board of the vault,
   by prefix substitution (F4) — decoded and re-encoded through `CanvasDocument`, never patched as
   text, so a board written by Obsidian keeps the keys this app does not know
   (`NoteFileOperations.swift:296-299`);
2. every link whose target is the old **board file name**, in every note of the vault — which is
   the same pass for the plain `[[old.canvas]]` form and the `^[[old.canvas]]` marker form (D3).

It rewrites **no ordinary wikilink**, because there is nothing to rewrite (F3). A regression test
asserts precisely that: a note linking `[[Nota interna]]` to a note inside the renamed folder is
byte-identical after the rename, and the link still resolves. That test is how R-06 stops being a
sentence somebody has to re-derive from the SPEC's wrong wording.

### D3. The task marker rewrite reuses `NoteRename` unchanged — no extension

`NoteRename.rewritingLinks(in: text, from: "\(old).canvas", to: "\(new).canvas")` already rewrites
`^[[old.canvas]]` because the caret is outside `link.range` (F6, ADR-0021 §D3). **`NoteRename` gains
no code, no parameter and no path-awareness in this change.** The chain brief anticipated extending
it; the code says extension is unnecessary, and an unnecessary extension of the rename machinery is
a second thing that can go wrong on every note rename in the app, forever, for a feature that does
not need it.

### D4. When the old board name is ambiguous, the marker rewrite is skipped and reported

`tasks(assignedToWorkspace:)` matches on file name alone (F5), so `x.canvas` is ambiguous the
moment two folders in the vault are both called `x`. After renaming `A/x` to `A/y`, `B/x/x.canvas`
still exists and every `^[[x.canvas]]` marker that meant *it* is still correct — rewriting them
would break references the rename never touched.

So: `renamePlan` counts the vault's boards whose file name equals the old board's file name. If
more than one, the name-level rewrite (D2.2) is **omitted entirely** and the plan carries a failure
line the facade surfaces through `recordProblem` («N task puntano a `x.canvas`, che nomina più di
una board: marker lasciati invariati»). The path-level repoint (D2.1) always runs; it is
unambiguous by construction.

### D5. The folder's own board file is renamed with the folder, in the same operation

`<new>/<old>.canvas` → `<new>/<new>.canvas`, when it exists. Without this the board reads empty
(F1). When the folder has no board file yet, nothing is renamed and no name-level rewrite is
performed — a board file that never existed cannot have been assigned to a task, because
`WorkspacePicker` lists `CanvasStore.allBoards()`, which enumerates real files.

Nested boards inside the renamed folder keep their own names and therefore their own markers: only
one folder was renamed, so only one board file name changed.

### D6. A folder operation is not a journalled gesture, and is not exposed to the connectors

No `transaction`, no `WriteJournal` entry, for either verb. The journal's vocabulary is per-file
text (F7): a directory move cannot be recorded in a way that could ever be undone, and journalling
only the *text* halves of a rename would produce exactly the half-reversed state ADR-0016 §D1
exists to prevent — links put back pointing at `old.canvas` while the folder is still called `new`.

Recovery is what the filesystem gives: the Trash for a delete, renaming back for a rename (which
re-runs the same symmetric rewrite). The SPEC puts both out of scope and this ADR agrees, for a
sharper reason than the SPEC's.

**Consequence, stated so nobody has to discover it:** `renameFolder`/`trashFolder` must not be
added to `VaultAPI` (and therefore to `perg` or the MCP server) until `WriteJournal` gains an entry
kind that can describe a directory. A connector write that `--dry-run` cannot rehearse and `undo`
cannot reverse would break ADR-0007 §D6's guarantee for every caller, not just this one. D1's
`sharedSources` decision is what makes that a compile-time fact rather than a promise.

### D7. Delete moves the whole folder to the Trash in one `trashItem`, never `removeItem`

`FileManager.trashItem(at:resultingItemURL:)` moves a file *or a directory* — verified against
Apple's current Foundation documentation on 2026-08-25, not from memory:
*"Use this method to move a file or directory at a specified URL to the trash."* One call on the
directory, matching `NoteFileOperations.swift:336`, the only convention this repo has for deletion.

`trashFolder` returns the `resultingItemURL` the call produces. That return value is not decoration:
it is what lets a unit test prove the folder went to the Trash rather than being unlinked — a URL
`removeItem` could not have produced.

### D8. The toolbar is a sibling of the header row, never a child of it

`WorkspaceBrowser`'s header keeps its identifier, its `children: .contain` grouping and its filter
field exactly as they are. The new toolbar is a **second row** below it, in its own file
`Sources/Features/Workspace/WorkspaceBrowserToolbar.swift`, with its own container identifier and
one identifier per button (`workspace-new`, `workspace-rename`, `workspace-delete`,
`workspace-expand-all`, `workspace-collapse-all`). Putting the buttons inside the identified header
container is what F9 says would make each of them answer to `workspace-browser-header`.

«Espandi tutto» / «Comprimi tutto» stay in the tree's context menu **and** appear in the toolbar,
both driving the same `expanded` binding — the SPEC asks for the toolbar, and removing the context
menu would be a regression nobody asked for.

### D9. Selection is a folder path, defaulting to the open board's folder; the root disables both verbs

**Superseded by ADR-0024** (`docs/adr/0024-workspace-board-tree-single-selection.md`): the
`selectedFolder ?? openFolder` fallback this section describes is deliberately removed — with
nothing selected, the toolbar now targets nothing and «Rinomina»/«Elimina» are disabled, rather
than aiming at whatever board happens to be open.

The browser gains `@State private var selectedFolder: String?`. A board row's click selects its
parent folder and opens it, as it does today; a folder row's label click selects that folder
without toggling its disclosure. The verbs act on `selectedFolder ?? openFolder`, so the toolbar is
never inert for lack of a click, and «Rinomina»/«Elimina» are `.disabled` exactly when that target
is `""` — the vault root, whose board is named after the vault (F1) and whose rename would be a
rename of the vault itself (R-09).

### D10. The browser decides, `WorkspaceView` performs

`WorkspaceBrowser` gains one parameter, a `WorkspaceFolderActions` value carrying three closures
(`create(name:parent:)`, `rename(folder:to:)`, `delete(folder:)`). `WorkspaceView` implements them,
because all three need `WorkspaceController`, which the browser has no business holding:

- **before** any of them: `workspace.flushPendingSave()`, or the autosave lands on the old path
  afterwards (F10);
- after a rename: if `workspace.folder` is the renamed folder or sits under it,
  `workspace.open(folder:)` at the prefix-substituted path — which is all R-08 needs, since
  `BoardTopBar`'s breadcrumb is derived from `workspace.folder`
  (`WorkspaceController.breadcrumb`, `BoardChrome.swift:24-34`);
- after a delete: if the open board was the deleted folder or under it,
  `workspace.open(folder:)` at the deleted folder's parent, which always survives (R-12).

The one existing call site (F11) is the one that changes.

### D11. The sheets copy `RenameNoteSheet`'s shape; the parent picker does not read `vault.folders`

`Sources/Features/Workspace/WorkspaceFolderSheets.swift` holds `NewWorkspaceSheet` and
`RenameWorkspaceSheet`: `@State` name, live `NoteName.validate`, violations rendered through
`ConformanceText.lines(NoteViolations(...))`, confirm disabled until clean — the same five elements
`RenameNoteSheet` has (`NoteRowMenu.swift:46-93`), not a new dialect. Two additions:

- a **collision predicate**, checked live, so R-03 blocks inline before anything is created rather
  than reporting `StoreError.alreadyExists` afterwards. The predicate is
  `FolderFileOperations.nameIsAvailable(_:in:)` — on the rules type, so it is unit-testable without
  a view, and the same function the performing code guards with;
- the create sheet's **parent picker**, whose options come from the browser's own board list
  (`CanvasStore.allBoards()`, already loaded for the tree) reduced to folders plus «(radice)».
  Not `vault.folders` (`VaultSession+Files.swift:93-106`), which is derived from note paths and
  would omit a folder that holds only boards or only subfolders — precisely the folders a Workspace
  user creates.

File → «Nuova board» keeps `NewCanvasItemSheet` and its current behaviour, unchanged.

---

## Alternatives considered

**A1 — Extend `NoteRename` with a path-aware rewrite pass, as the chain brief assumed.**
Rejected: there is nothing for it to rewrite. Wikilinks carry titles, not paths (F3), and the one
link form a folder rename does change — the board's file name — is already handled by the existing
title-shaped pass (F6). The extension would be dead machinery sitting in the hot path of every note
rename in the app, and would need its own tests to prove it does nothing.

**A2 — Perform the rename as N single-note `moveFile` calls inside a journalled transaction.**
Rejected on three counts: it leaves the emptied directory tree behind and needs a second pass to
remove it; it is O(notes) filesystem calls for something `moveItem` does in one; and it does not
even buy the journal integrity it costs, because the `.canvas` files and the folders themselves
still have no journal representation (F7). A gesture that is 90% undoable is the failure mode
ADR-0016 §D1 names by hand.

**A3 — Journal the folder move as a `.move` entry with an empty hash.**
Rejected: `preflightMove` compares `currentHash(at:)` — nil for a directory — against `hashAfter`,
so the entry can never be reversed, *and*, being a member of the gesture, its failed preflight
blocks the undo of every sibling entry (`VaultSession+Journal.swift:200-201`). The result is a
journal that records the operation, refuses to undo it, and explains itself with a message about a
hash. Worse than recording nothing.

**A4 — Put the four commands in `BoardTopBar` / `BoardToolbar` instead of the sidebar.**
Rejected: those two hold board tools and view state (undo/redo, anteprima, tray) and act on the
*open* board; these four act on the sidebar's **selected row**, which may be a board nobody has
opened. The SPEC puts them in the browser header and the SPEC is right — a delete that requires
opening the thing first is a delete that renders the board you are about to destroy.

**A5 — Reuse `NewCanvasItemSheet` for the create flow by adding a parent picker to it.**
Rejected: that sheet is shared by three creation kinds (`folder`, `link`, `note`) invoked at a
point on the open board, where the parent is by definition the open folder. Adding a picker changes
the flow for the other two kinds and for File → «Nuova board», which the SPEC explicitly keeps
unchanged. A second, purpose-built sheet costs ~60 lines and touches nothing that already works.

**A6 — Rewrite every `^[[x.canvas]]` marker unconditionally, ambiguity or not.**
Rejected: after renaming `A/x`, a `B/x/x.canvas` still exists and the markers meaning *it* are
still correct; rewriting them would break references this operation never touched, silently, in
notes the user was not looking at. Reporting an ambiguity the user can resolve by hand is the
honest option (D4). The opposite default — rewrite nothing, ever, and always report — was also
considered and rejected as making R-07 false in the common case for the sake of the rare one.

**A7 — Give the toolbar its own selection model with no fallback, so the buttons are disabled until
a row is clicked.** Rejected: the browser has no selection today, so every user's first encounter
with the toolbar would be three disabled buttons with no visible reason. Defaulting the target to
the open board's folder (D9) makes the toolbar always meaningful, and the root exemption still
disables the two destructive verbs exactly when R-09 requires.

**A8 — Make the delete a `.trash/` move inside the vault, Obsidian-style, instead of the system
Trash.** Rejected: `NoteFileOperations.swift:336` fixed this convention for notes and CLAUDE.md
principle 1 makes the vault a plain directory a person also uses from Finder. Two deletion
destinations in one app is a question the user should never have to answer.

---

## Consequences

### Positive

- The vault gains its first folder rename and folder delete, in a rules type shaped like the one
  that already exists for notes, with the same plan/perform split and the same
  `FileChange(path:before:after:)` vocabulary — so a reader who knows `NoteFileOperations` knows
  this file.
- ADR-0021 §D3's caret-safety argument stops being a claim about a mechanism and becomes a claim
  about a screen: the marker rewrite it predicted is now exercised end to end, at the cost of one
  function call (D3).
- The board-goes-blank failure (F1) is closed before it can be shipped, because D5 makes the board
  file rename part of the same operation rather than a follow-up somebody remembers.
- `.canvas` cards stop being the reference class nobody thinks about: D2.1 repoints them vault-wide,
  the same fix `NoteFileOperations` needed after a real vault broke.
- `perg` and `pergamenum-mcp` are unaffected — not by luck, but because `sharedSources` names files
  one at a time and D1 names none of the new ones (F12).
- The sheets, the validation text and the violation rendering are the ones already on screen
  elsewhere in the app, so there is one rename dialect, not two (D11).

### Negative

- **A folder rename and a folder delete cannot be undone inside the app** (D6). The Trash and a
  reverse rename are the whole recovery story. This is a real reduction relative to the note verbs,
  which are journalled, and it is accepted rather than hidden.
- **A folder operation is not available to an assistant.** ADR-0007's premise is that a connector
  can do what the app can do; after this change there are two verbs it cannot. D6 names the
  condition for lifting that (a directory-capable journal entry kind) and D1 makes the exclusion
  mechanical, but the asymmetry is new.
- **The rename is O(notes in the vault) in reads**, because the name-level rewrite must inspect
  every note for `[[old.canvas]]`, exactly as a note rename does. On a vault of a few thousand notes
  that is a fraction of a second; it is still a full pass triggered by a sidebar button.
- **Ambiguous board names degrade to a warning** (D4). A user with two folders called `Ricerca` gets
  markers left untouched and a message, not a rewrite. Correct, and still a case where the feature
  does less than the SPEC's sentence promises.
- `WorkspaceBrowser` gains a parameter and roughly a hundred lines of state and chrome across three
  new files; the pane that was a read-only tree is now a place where things are destroyed.

### Neutral

- No new dependency, no schema change, no index change. `.canvas` files are still not indexed
  (ADR-0021 §D10), `IndexCache.schemaVersion` stays **3**, and nothing new is persisted: a workspace
  is still identified by its folder's path and nothing else.
- The `.canvas` file format is untouched — no new prefixed key, no new node type. Obsidian
  round-tripping is unaffected.
- The existing File → «Nuova board» path keeps its sheet and its default (the open board's folder).
  Two doors to creation, one of which now asks where.
- Expand/collapse exist in two places after this change (context menu and toolbar), driving one
  binding.
- The UI-visible identifiers `workspace-filter`, `workspace-board-<path>`, `workspace-folder-<id>`,
  `workspace-tree`, `workspace-flat-list` and `workspace-browser-header` are all preserved
  unchanged; the two UI tests that depend on them (F11) keep passing without edits.

---

## References

- SPEC of this chain: `/Users/stefer/Developer/Pergamenum/SPEC.md` (R-01 … R-15).
- App specification: `docs/20260811_Pergamenum_SpecApp.md` §6.1 (board ↔ folder mapping,
  breadcrumb) — updated by this chain's R-15.
- ADR-0021, `docs/adr/0021-workspace-tasks-notes-integration.md` — §D1/§D3 (the `^[[…]].canvas`
  marker and its caret-safety), §D10 (`.canvas` files are not indexed), and the "Nothing in the app
  renames a `.canvas` file" fact this ADR closes.
- ADR-0016, `docs/adr/0016-the-journal-records-a-gesture.md` — §D1 (all of a gesture or none of it),
  §D2/§D3 (the three entry kinds), §D6 (the plan/perform split and `isDryRun`).
- ADR-0017, `docs/adr/0017-the-derived-stores-leave-the-vault.md` — derived state is outside the
  vault; a folder operation touches none of it, the rescan rebuilds it.
- ADR-0012 §D6 — the star is a path, so it has to be carried across a rename (`moveStar`).
- ADR-0007 §D3/§D6 — the connector contract this ADR deliberately does not extend (D6).
- ADR-0001 §D1 — `Sources/Core/**` must not import SwiftUI; enforced by the two tool builds.
- `FileManager.trashItem(at:resultingItemURL:)`, Apple Foundation documentation, read 2026-08-25:
  moves a file **or directory** to the trash and reports its resulting location.
- Code read at `7ffd5fd`: `Sources/Vault/CanvasStore.swift`, `Sources/Vault/NoteFileOperations.swift`,
  `Sources/Vault/VaultSession+Journal.swift`, `Sources/Vault/VaultSession+Files.swift`,
  `Sources/Vault/VaultController+Files.swift`, `Sources/Vault/VaultController+Tabs.swift`,
  `Sources/Core/Conventions/NoteRename.swift`, `Sources/Core/Conventions/NoteName.swift`,
  `Sources/Core/Tasks/TaskParser.swift`, `Sources/Index/IndexSnapshot.swift`,
  `Sources/Features/Workspace/WorkspaceBrowser.swift`, `Sources/Features/Workspace/WorkspaceView.swift`,
  `Sources/Features/Workspace/BoardChrome.swift`, `Sources/Features/Editor/NoteRowMenu.swift`,
  `Sources/Features/Tasks/WorkspacePicker.swift`, `Project.swift`.
