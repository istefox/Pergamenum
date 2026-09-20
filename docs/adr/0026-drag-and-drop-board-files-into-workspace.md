# ADR-0026 — A row is dragged into a folder, and several rows are chosen first

- **Status:** Accepted (2026-08-27). Implementation pending — see
  `docs/superpowers/plans/2026-08-27-drag-and-drop-board-files-into-workspace.md`.
- **Supersedes in part:** **ADR-0024 §D2/§D3**, in the same declared-and-bounded way ADR-0025
  superseded them: this chain adds a *second, additive* concept beside the single derived
  selection — a multi-row set that decides what a drag carries — and does **not** reverse
  ADR-0024's core claim. There is still exactly one open board and one thing that "opens" when a
  row is clicked, and it is still one value, not two booleans. What changes is that "lit" and
  "open" stop being the same set: a row can be lit without being open. §D4 states the new
  invariant in full.
- **Builds on, and does not reopen:** ADR-0021 (`^[[x.canvas]]` marker grammar, board-file-name
  resolution), ADR-0022 §D6 (a directory operation is not journalled) and §D8 (AX-identifier
  propagation on container elements), ADR-0023 §D1/§D4 (a command is named once and rendered
  twice), ADR-0024 §D1 (flat recursive rows, never `DisclosureGroup`, inside `List(selection:)`)
  and §D5 ("the triangle expands, the row selects"), ADR-0025 §D1/§D3 (a board is addressed by
  its own file path), §D5 (`WorkspaceBoardResolver` answers both board questions) and §D9 (the
  chevron owns the double-click, never the row).
- **Relocates nothing.** ADR-0022 §D4's ambiguity guard stays exactly where ADR-0025 §D6 put it,
  on board *rename*. A move never changes a board's file name, so it never reaches that guard —
  §D7 below is the proof, not an assumption.

---

## Context

Neither sidebar tree can be reorganised from inside the app. The Workspace tree (`WorkspaceBrowser
.swift`, folders and `.canvas` rows since ADR-0025 §D2) and the Note tree (`NoteListPane.swift`,
folders and `.md` rows) both draw the vault the way it sits on disk and both offer creation,
rename and delete — but the one verb that changes *where* something sits, for anything other than
a single note, does not exist as a gesture. Today the answer is Finder, or a rename-and-recreate
dance that breaks card references on the way.

The request is a direct one: drag a row onto a folder row and it moves; drag it onto the tree's
empty area and it goes to the vault root; select several rows first and they all move together;
Cmd+Z puts it back. That last clause is the one that costs the most, because nothing in
`Sources/` has ever registered an undo action with `NSUndoManager` — verified, zero occurrences
of `UndoManager`, `NSUndoManager` or `registerUndo` across the whole tree.

Four things were read out of the source before any of this was designed, and each one changed the
design:

1. **The note half is already built.** `NoteFileOperations.movePlan(_:toFolder:)` and
   `.move(_:toFolder:)` exist (`NoteFileOperations.swift:146-158, 274-294`), performed inside a
   journal transaction by `VaultSession.moveNote` (`VaultSession+Files.swift:52-73`), wrapped by
   `VaultController.moveNote` (`VaultController+Files.swift:41-55`), and already reachable from
   every note row through a shipped **«Sposta in»** menu (`NoteRowMenu.swift:30-36`). The SPEC
   asked the architect to find out whether an equivalent existed; it exists all the way up to the
   user interface. R-03 is therefore a wiring job, not a new file operation.
2. **The note rows are already drag sources**, and their payload is load-bearing.
   `NoteListPane.swift:197` and `:346` carry `.draggable(note.title)` / `.draggable(node.name)`,
   and the consumer is `CompletingTextView.performDragOperation`
   (`CompletingTextView+Pasteboard.swift:102-112`), which accepts the drop only when the dragged
   string is a real note title (`noteTitles.contains(title)`) and then appends `[[title]]` to the
   task line under the cursor — SPEC §7.2, "collegamento assistito". A view carries one
   `.draggable`. Replacing that payload with a move payload would break §7.2 silently: the string
   would stop matching a title, `performDragOperation` would fall through to `super`, and
   `NSTextView` would paste the raw payload into the note as text. The SPEC does not mention this
   anywhere.
3. **`.dropDestination` has no payload-aware validation.** Its two closures are `action: ([T],
   CGPoint) -> Bool`, called *after* the drop, and `isTargeted: (Bool) -> Void`, which is handed a
   `Bool` and never the payload. Neither the SwiftUI API nor the older `DropDelegate.validateDrop`
   (whose `DropInfo` yields `NSItemProvider`s that can only be read asynchronously) can tell a
   folder row what is hovering over it. The SPEC left the collision-affordance choice to the
   architect "depending on what the chosen drag API makes straightforward"; what it makes
   straightforward is nothing, unless the source side remembers what it started dragging.
4. **The editor's undo is the window's undo.** `NoteTextView.swift:114` sets `textView.allowsUndo
   = true`, and an `NSTextView` registers on `NSResponder.undoManager`, which walks up to the
   window. There are not two undo domains to keep apart. There is one, and the question is
   whether to register in it or to build a second one beside it.

---

## Decision

### §D1 — A move is a file operation of the same two-phase shape the folder and board verbs
### already have, and it lives in the two files that are deliberately outside `sharedSources`

`BoardFileOperations` gains `movePlan(_:toFolder:)` / `moveBoard(at:toFolder:)`.
`FolderFileOperations` gains `movePlan(_:toParent:)` / `moveFolder(at:toParent:)`. Both follow
`renamePlan`/`renameBoard` and `renamePlan`/`renameFolder` exactly: a plan computed with nothing
written, then a performance that moves the one file or directory first and writes the many
repoints second — "the move is one operation that either happens or does not, while the rewrites
are many and each can fail on its own" (`FolderFileOperations.swift:242-250`, the argument
`NoteFileOperations.rename` makes first).

`FolderFileOperations.OperationError` gains one case, `wouldNest(String)`, for the destination
that is the folder itself or one of its descendants. `alreadyExists` already says what a
collision is and needs no sibling.

Neither file is named in `sharedSources` (`Project.swift:72-107` lists `Sources/Vault/*.swift` one
at a time and lists neither), so the new writes cannot reach `perg` or `pergamenum-mcp`. That is
not a promise this ADR makes — it is a compile-time fact ADR-0022 §D6 and ADR-0025 §D6 already
arranged, and this chain simply does not disturb it. `VaultAPI` gains nothing.

### §D2 — The note move is not reimplemented. It is called.

Nothing is added to `NoteFileOperations`, and nothing is added to `VaultSession+Files`. A note
dragged in the Note sidebar goes through `VaultController.moveNote(at:toFolder:)`, the same entry
point the shipped «Sposta in» menu has been calling since ADR-0016 — journalled, star-carrying,
board-repointing, tab-following. A second spelling of that verb, on a value type of this chain's
own, is exactly the kind of drift `CLAUDE.md`'s connector section is about.

One consequence is worth naming: **the three kinds of move are not journalled alike.** A note move
is a `transaction("note move")` in `WriteJournal`; a board or folder move is not, because
`WriteJournal`'s vocabulary is one file's text and a directory has none (ADR-0022 §D6, ADR-0016
§D1). This chain does not fix that and does not pretend to. The undo of §D8 is a session-scoped,
in-memory inverse that covers all three; the journal remains the durable record that covers one.

### §D3 — The dragged item carries two representations: the structured move payload under an
### exported type, and the plain name the editor has always read

A new `Transferable` value, `VaultItemDrag` (`Sources/App/VaultItemDrag.swift`), carries the
item's vault-relative path, its kind (`note` / `board` / `folder`), its display name, and the
whole effective drag set. It declares two representations:

```
CodableRepresentation(contentType: .pergamenumVaultItem)   // it.stefer.pergamenum.vault-item
ProxyRepresentation(exporting: \.dragName)                 // String — the note title / the row's name
```

The first is what a folder row's `.dropDestination(for: VaultItemDrag.self)` reads. The second is
what `CompletingTextView.performDragOperation` reads, byte-identical to what
`.draggable(note.title)` puts on the pasteboard today, so SPEC §7.2 keeps working with **no edit
to `CompletingTextView+Pasteboard.swift` at all** (R-09). A file this chain does not touch is a
regression this chain cannot cause.

The UTType is declared for real, in `Project.swift`'s `infoPlist` under
`UTExportedTypeDeclarations`, and reached through `UTType(exportedAs:conformingTo:)`. This is a
deliberate departure from `TaskDragPayload` and `BoardDragPayload`, which each wrote down the
opposite reasoning — "a drag inside one window needs no declared uniform type, and one would have
to be registered in the app's Info.plist to be worth anything outside it"
(`TaskDrag.swift:6-9`, `ViewBoardRenderer.swift:180-182`). They were right for their case and
wrong for this one: their rows had no competing payload, and these rows do. Registering the type
is what buys the *second* representation, and the second representation is the whole of §7.2's
survival.

### §D4 — The multi-selection set is `List`'s own selection, and "open" is derived from it by a
### collapse rule. No gesture is added anywhere.

Both trees change their binding from `Binding<String?>` to `Binding<Set<String>>`. Cmd-click and
Shift-click then work because AppKit's list already does them — nothing in this repository has to
read `NSEvent.modifierFlags`, and no tap recognizer is added to any row.

That last clause is the reason for the whole decision. `WorkspaceBrowser.swift:713-732` records,
in the code, what happened the one time a recognizer spanned a whole row inside
`List(selection:)`: ADR-0025 §D9's row-wide `.simultaneousGesture(TapGesture(count: 2))`
intermittently starved the list's own tap recognizer and a folder-row click stopped registering as
a selection change at all — caught by
`WorkspaceOpenStateUITests.testClickingABoardLessFolderRowClosesTheOpenBoardAndSelectsOnlyItsRow_R04`,
and fixed by moving the gesture onto the chevron, which carries no `.tag`. A modifier-flag
multi-selection would put a recognizer back on the row body. It is refused on those grounds
(A4 below).

The **collapse rule** is how the additive concept stays additive:

| the set the binding's setter receives | what happens to "open" |
|---|---|
| exactly one id, different from what is open | that row is opened — today's behaviour, unchanged |
| exactly one id, the same one | nothing (the Note pane's existing `leaveComposer()` case is preserved verbatim) |
| two or more ids | **nothing**. The open board stays open, the open note stays open (R-10) |
| empty | deselect / close, which is what clicking the blank area below the rows already means (ADR-0024 §D7) |

So `WorkspaceSelection?` on `WorkspaceController` remains the single answer to "what is open", and
`vault.openNote` remains the Note pane's. Neither becomes a set. The set answers one question and
only one: **what does a drag carry.** A drag started on a row inside a non-empty set carries the
set; a drag started on a row outside it carries that row alone and replaces the set with it, which
is the SPEC's own rule and also AppKit's.

ADR-0024's invariant survives in the form that mattered: the thing that is open and the row that
is lit for being open are one value, never two. What is new is that *other* rows may also be lit,
for a different reason, and that reason opens nothing.

### §D5 — A cycle gives no affordance; a collision is accepted and then named

The two refusals are not implemented the same way, and the asymmetry is the decision.

- **Cycle (R-06).** The drop target's own view knows, from the drag set the source stored at drag
  start, whether it is the dragged folder or sits under it. That is pure string arithmetic —
  `dest == folder || dest.hasPrefix("\(folder)/")`, the prefix rule
  `FolderFileOperations.repointing` already follows and for the same reason (a sibling called
  `a-altro` is not inside `a`). It costs nothing per hover, so the row simply does not highlight
  and its `action` returns `false`. Nothing happens, and nothing needed to be said.
- **Collision (R-07).** The drop is accepted visually and an error dialog names every conflicting
  entry. Three reasons, in order of weight: R-07 requires the conflicting name to be **shown**,
  and a row that declines to highlight shows nothing; the check is one `fileExists` per dragged
  item per hovered folder, which during a live drag is a burst of main-actor syscalls on every
  hover transition, where the cycle check is arithmetic; and an all-or-nothing batch (§D6) can
  collide on one item out of six, so a target that silently stays dark leaves the user guessing
  which one.

Neither is a rename and neither is an overwrite. "Reject" means reject.

### §D6 — A multi-row move commits entirely or not at all, and the batch is pruned before it is
### validated

One pure value type, `VaultMoveBatch` (`Sources/Vault/VaultMoveBatch.swift`, Foundation only,
outside `sharedSources` like the two operation files it serves), answers "what would this drop
do" in one function, with no filesystem writes and one filesystem read per candidate:

1. **Prune redundancies.** An item whose ancestor is also in the set is dropped: it moves with its
   ancestor, so moving it separately is not a second move, it is a contradiction. The SPEC left
   this open; silent exclusion is chosen over an error because the user selected a folder and its
   child and asked for one thing, not two.
2. **Drop no-ops.** An item already directly inside the destination is removed from the batch and
   is not an error, and — this is the part that matters for §D8 — it is **not** in the inverse
   either, so an undo cannot try to "restore" a move that never happened.
3. **Refuse cycles**, per §D5.
4. **Refuse collisions**, including two items in the same batch that would land on the same name.
5. **Answer once:** `.moves([VaultMove])` or `.refused([reason])`. Nothing is written unless every
   item passed.

All-or-nothing is the SPEC's own preference and it is kept, for the reason the SPEC gives and one
more: a partial commit has a partial inverse, and a partial inverse is an undo step that puts back
some of what the user sees and not the rest.

### §D7 — A move rewrites no marker and no wikilink, and it *does* repoint `.canvas` node paths

The SPEC's "no new rewriting" section is right twice and incomplete once.

- **Right:** an ordinary `[[Nota]]` names a note by title, so a note move rewrites nothing
  (R-09) — the rule ADR-0022 §F3 and ADR-0025 key decision 1 already state.
- **Right:** a `^[[board.canvas]]` task marker carries a bare **file name** (ADR-0021 §D1/§D5),
  matched by `WorkspaceBoardResolver.matches` and `IndexSnapshot.tasks(assignedToWorkspace:)`
  case-insensitively on the last path component. A move never changes that component, so the
  marker text is never rewritten and its resolution — `.unique` / `.ambiguous` / `.notFound` — is
  computed after the move exactly as before (R-08). ADR-0022 §D4's guard, which ADR-0025 §D6
  relocated onto board *rename*, is never reached by a move and is not touched by this chain.
- **Incomplete:** a `.canvas` **node** addresses its file by **path**
  (`CanvasDocument.Node.kind == .file(path:subpath:)`). A moved note, board or folder that is
  referenced as a card on any board leaves that card pointing at nothing unless the path is
  repointed — the exact break `NoteFileOperations` documents having found on a real vault
  (`NoteFileOperations.swift:11-19`) and already fixes for a note move (`:292`). So both new
  operations run `FolderFileOperations.repointBoardsPlan(from:to:)`, which was made non-private by
  ADR-0025 §D6 precisely so a *file* path and a *folder* path could share one loop: its exact-path
  arm covers a moved board that is itself a card, its `<old>/` prefix arm covers everything inside
  a moved folder, and its `writePath` substitution covers a board that moved as part of the folder
  being repointed. There is no third copy of that loop and this chain does not add one.
- **Amended 2026-09-17** (pratica ledger orphaned by folder move/rename): a folder relocation also
  publishes `MoveBatchOutcome.movedFolders` and triggers `VaultController.didRelocateFolders`, for a
  move and for a rename alike, forward and through undo/redo — and path-keyed feature state
  (Pratiche's ledger today) must subscribe to it rather than assume its own path is stable, the same
  way `.canvas` node paths above must be repointed rather than left stale.
- **Amended 2026-09-19** (pratica ledger forgotten on folder trash, PG-169): the same rule with the
  opposite verb and no destination. `VaultController.trashFolder(at:)` — the one door every folder
  delete goes through, whether from a pratica's own «Elimina», the note list or the Workspace
  browser — publishes the trimmed path it just sent to the Trash through
  `VaultController.didTrashFolder`, fired only after the trash succeeded. Path-keyed feature state must
  therefore *forget* as well as follow: Pratiche removes every ledger key, tray proposal, tray count
  and watcher equal to or under that path (the same trailing-slash subtree rule as a move), clears a
  selection inside it, and stops an in-flight sync or regeneration and discards its outcome, so a
  finishing run cannot put back the key the trash just removed. One deliberate **no**: nothing prunes
  a ledger key merely because its folder is missing from the disk, at load or anywhere else. A Finder
  move, an unmounted volume and a not-yet-scanned index look exactly like a deleted pratica, and
  pruning on that evidence would turn the relocation bug above into unrecoverable history loss; only
  a trash this app performed itself is proof. A folder trashed outside the app still leaves its key.
  What a stale key actually costs, measured when it was fixed: a pratica recreated under the same name
  inherits the old one's history (`importedMessageIDs`, the «non più in Mail» list, bridge `entries`,
  `lastOpenedAt`, tray count). It does not silently skip messages: `MailStoreReader.rows` builds every
  row with `messageID: nil`, so the engine's own on-disk `Message-ID` scan decides what is imported.
- **Amended 2026-09-20** (ledger marker and one write door, PG-172, ADR-0052 §D6): the tombstone the
  trash leaves on a path an in-flight sync or regeneration still claims is no longer kept until the
  whole controller is idle. It is dropped, per path, by whichever of `endSync`/`endRegeneration`
  releases that path, as soon as no sync and no regeneration claims it - a claim on some other path
  no longer keeps it alive. A tombstone on a path that is still claimed stays, and that claim's
  outcome is still discarded exactly as above.

### §D8 — Undo is registered on the window's `UndoManager`, obtained from the SwiftUI
### environment and passed in as a parameter

`@Environment(\.undoManager)` is read in the view that handles the drop and handed to
`VaultController.moveItems(_:into:undo:)` as an argument. The controller never reaches for
`NSApp.keyWindow?.undoManager` and never imports AppKit for this; `UndoManager` is Foundation, so
the facade stays as free of the window as it is today.

It is the **window's** manager, which is the same one `NSTextView` registers text edits on
(`allowsUndo = true`, `NoteTextView.swift:114`, resolved through `NSResponder.undoManager`). That
is a deliberate choice, not an accident of the API: one window means one undo history, Cmd+Z means
"undo the last thing I did in this window" whatever had focus, and the Edit menu's Undo item —
which `MenuCommands.swift` leaves in place, replacing only `.textEditing`, `.help`, `.pasteboard`,
`.sidebar` and `.toolbar` — lights up with the action name for free. A private manager beside it
would make Cmd+Z's meaning depend on which pane holds first responder, which nothing else in this
app does (A6 below).

The registration is **one block per batch**, not one per item, so a six-row move is one undo step
(R-12). The handler performs the inverse batch and re-registers itself with the arguments swapped,
which is how `NSUndoManager` produces redo — there is no custom redo code. If any inverse move
fails validation at the moment it is asked for (the SPEC's "a later rename moved it" race), the
handler performs nothing, reports through `VaultController.recordProblem` and does **not**
re-register: a redo of an undo that did not happen is worse than no redo.

If `@Environment(\.undoManager)` is `nil`, the move still happens and one problem line says it is
not undoable. Degrading silently is the failure mode this repository keeps writing ADR sections
about.

### §D9 — The drag is a second rendering of a command the menu also offers

`Sposta in ▸` is added to the Workspace row context menu (board rows and folder rows) and to the
Note sidebar's **folder** rows; the note rows already have it (`NoteRowMenu.swift:30-36`) and are
left alone. Both surfaces call the same `VaultController.moveItems`, which is ADR-0023 §D1/§D4's
rule — a command is named once and rendered twice, never implemented twice.

This is not decoration. It is the reason R-01 … R-07 have a reliable end-to-end UI test at all:
**no test in this repository has ever driven a `.draggable` → `.dropDestination` pasteboard drag.**
Every existing drag test (`DayViewUITests:166`, `WorkspaceBoardUITests:65-167`, `DiaryUITests:174`)
drives a `DragGesture`, which XCUITest synthesizes reliably; an `NSDraggingSession` initiated by
`.draggable` is a different machine and `press(forDuration:thenDragTo:)` may or may not start one.
The menu path is deterministic, keyboard-reachable and accessible; the drag path is the gesture the
feature is *about*, and gets its own coverage attempt with an explicitly recorded fallback (§D12).

The Workspace menu reads its folder list from `CanvasStore.allFolders()`, which the browser
already holds, and **not** from `VaultController.folders` — the latter derives folders from note
paths (`VaultSession.folders`) and therefore omits a folder holding only boards, which is
precisely the folder a Workspace user makes (ADR-0022 §D11).

### §D10 — Where the open board lands after a move is a pure function, and the flush comes first

`WorkspaceFolderActions` gains `boardAfterMove(open:moves:)`, a static pure function beside
`folderAfterRename` / `folderAfterDelete` / `boardAfterRename` / `boardAfterDelete`, tested in
`Tests/WorkspaceFolderNavigationTests.swift` where the other four already are. Its rule is the
exact-then-prefix substitution the folder rename rule uses: the open board's path is substituted
when it *is* a moved item, prefix-substituted when it sits inside a moved folder, unchanged
otherwise. `open(board:)` on the result re-reads the document and redraws the breadcrumb, so the
board never flickers closed (R-13).

The move runs through the same bracketing `performFolderVerb` / `performBoardVerb` impose, and the
first line of it is not optional: **`flushBoard()` before anything touches disk.** The board
autosaves about a second after a change; without the flush that write lands on the pre-move path
and recreates the file the move just relocated — ADR-0022 §F10, paid for once already by rename
and delete. The SPEC says nothing about the autosave. It would have found out.

The Note pane's equivalent already exists: `VaultController.moveNote` calls
`movedNote(from:to:)`, which carries tabs and RECENTI, and `canOperate(on:)` refuses while the
note has unsaved edits. A folder move reuses `canOperateOnFolder`, whose guard is already written
for exactly this ("moving a file out from under the editor would either lose the buffer or raise
the external-change prompt for a change the app itself made").

### §D11 — The drop targets are the folder rows and the `List` itself, and every new modifier
### goes **before** the `.tag`

`.draggable` and `.dropDestination` are applied inside `WorkspaceRow.content` and inside
`NoteTreeRow`'s two row builders, ahead of `taggedRow`'s `.tag`, which stays the last modifier in
the chain without exception (`WorkspaceBrowser.swift:713-721`, and `RootView.swift:205-208`'s
record of what a modifier applied after a `.tag` does: nothing lights and every click is
swallowed, silently). `NoteListPane` today applies `.tag` before `.draggable` (`:345-346`); that
order is normalised to the Workspace pane's, not copied.

"The root area" (R-05) is the `List`'s own `.dropDestination`, which the rows sit inside: SwiftUI
hit-tests the innermost destination first, so a drop on a row reaches the row's and only a drop on
the background reaches the list's. That is the mechanism, and it is the one part of this design
that is asserted by hand rather than by construction — which is also why the «Sposta in ▸
(radice)» menu entry exists (§D9) and gives R-05 a second, certain surface.

One accessibility rule, learned twice in this repository and applying to a file that has not paid
for it yet: the Note rows gain `accessibilityIdentifier("note-row-<path>")` and **must not** gain
`.accessibilityElement(children: .contain)`. `NoteTreeAndShortcutsUITests` finds every folder and
note by the words on it (`app.staticTexts["01 Progetti"]`, `:54-90`) — a practice `CLAUDE.md`
forbids for new tests and which those existing green tests depend on. Regrouping the row's
children would move those words out of `staticTexts` and break eight assertions that have nothing
to do with this feature. The Workspace rows already carry `.contain` and are unaffected.

### §D12 — Nothing is persisted, and no schema moves

`IndexCache.schemaVersion` stays 3. A move is a filesystem rename that the existing vault scan
already tolerates, because the index is rebuilt from the files on disk wherever they are found
(`CLAUDE.md` principle 3). The multi-selection set is view state and is not remembered across
launches — it answers a question that only exists during a drag.

---

## Alternatives considered

**A1 — Give the note rows a second `.draggable` carrying the move payload, and leave the title
payload alone.** Rejected: a view has one `.draggable`; two applications of the modifier do not
compose into a pasteboard with two payloads, the outer simply wins. The multi-representation
`Transferable` of §D3 is the supported way to put two things on one pasteboard, and it is the only
one that leaves `CompletingTextView+Pasteboard.swift` untouched.

**A2 — Keep the repo's established plain-`String` payload (the `TaskDragPayload` /
`BoardDragPayload` shape) with a discriminating prefix, and teach the editor to ignore it.**
Rejected: it changes the note-row payload, so §7.2's drop stops matching a note title and falls
through to `NSTextView`'s default, which pastes the payload string into the user's note as text.
The fix would be an edit to `performDragOperation` plus a new negative test to stop it regressing —
work spent restoring a behaviour that §D3 never breaks. The prefix scheme is also strictly weaker:
any plain-text drag from any app would still enter our folder rows' drop handlers and have to be
parsed and refused.

**A3 — `CodableRepresentation(contentType: .json)` instead of an exported UTType, to avoid the
`Project.swift` / Info.plist edit.** Rejected: `public.json` is a system type that Finder,
Safari and every text editor also produce, so every folder row would light up for a JSON file
dragged in from anywhere and then refuse it after the fact — the exact "accept then reject"
behaviour §D5 confines to the one case that has something to say. The Info.plist edit is six lines
in a manifest this project regenerates on every file addition anyway.

**A4 — Keep `List(selection: Binding<String?>)` and implement Cmd/Shift-click by reading
`NSEvent.modifierFlags` inside a tap gesture on the row.** Rejected, and this is the strongest
rejection in the ADR: it requires a recognizer on the row body, which is what
`WorkspaceBrowser.swift:713-732` documents as having starved `List(selection:)`'s own tap and made
a folder-row click stop registering — intermittently, which is the worst way for it to fail. It
also reimplements Shift-range selection (which needs the flattened visible row order, i.e. a
second model of what the list is drawing) against an AppKit control that already does it
correctly.

**A5 — `onDrag` / `onDrop` with `NSItemProvider` and a `DropDelegate`, as the SPEC allowed if
`.draggable` proved unable to distinguish an internal drag from an external file drop.** Rejected
on both halves. The discrimination the SPEC worried about is solved by the payload type, not by
the API: `.dropDestination(for: VaultItemDrag.self)` never sees a Finder URL drop, and the canvas
keeps its own `.dropDestination(for: URL.self)` (`WorkspaceView.swift:350`) untouched. And the one
thing `DropDelegate` appears to offer over `.dropDestination` — a `validateDrop(info:)` hook — cannot
read an `NSItemProvider` synchronously, so it cannot inspect the payload either, and buys exactly
nothing for §D5's problem. Against it: no precedent anywhere in this repository, where four
existing drag surfaces all use `.draggable`/`.dropDestination`.

**A6 — A private `NSUndoManager` owned by the sidebar, so a move-undo can never be confused with
a text-undo.** Rejected: reaching it from Cmd+Z means the sidebar must be first responder and must
vend the manager through an `NSViewRepresentable` that overrides `undoManager` — a responder-chain
mechanism this app has nowhere else — and the result is that Cmd+Z would mean different things
depending on which pane has focus, with no visible cue as to which. The single window-scoped stack
of §D8 is both simpler and the platform's own answer. It is *also* the one this rejection is least
sure about, and it is named in the manual verification list (§D9's fallback discipline) rather than
declared safe.

**A7 — Journal the board and folder moves through `WriteJournal`, so «Annulla» and the connector's
`undo` cover them too.** Rejected as out of scope and, more importantly, as a decision that is not
this chain's to take: `WriteJournal` has three entry kinds and all three are about one file's text
(ADR-0016 §D1), which is exactly why ADR-0022 §D6 left folder verbs out of it. Giving the journal
a directory vocabulary is a chain of its own, and doing it badly here would put a half-expressible
operation into the durable record that `perg undo` reads.

**A8 — Let a multi-row move commit what it can and report the rest.** Rejected: the SPEC prefers
all-or-nothing and gives the reason (simpler to reason about, atomic to undo), and a second reason
was found while designing §D8 — a partial commit produces a partial inverse, so the single undo
step would put back some of what the user is looking at and leave the rest, which is a worse
outcome than the refusal it was trying to avoid.

**A9 — Drop the context-menu surface and rely on drag alone, since drag is what the SPEC asks
for.** Rejected: R-15 asks for UI coverage of four drag scenarios and no test in this repository
has ever driven a pasteboard drag, so a drag-only design would ship a feature whose end-to-end
behaviour is asserted nowhere. The menu also happens to be the keyboard-and-VoiceOver route to a
verb that would otherwise require a mouse, and it costs one `Menu` per row kind over a controller
entry point that has to exist regardless.

---

## Consequences

### Positive

- The vault can be reorganised without leaving the app, in both trees, for all four kinds of thing
  that live in them, with the file layout on disk staying the source of truth (`CLAUDE.md`
  principle 1) — nothing new is persisted anywhere to describe where something is.
- SPEC §7.2's note-title drop keeps working with no edit to the file that implements it, because
  the payload gained a representation instead of changing one.
- Cmd/Shift multi-selection arrives with no new gesture recognizer in either tree, so the
  `List(selection:)` arrangement ADR-0024 and ADR-0025 spent two chains stabilising is untouched.
- The app gets an undo history for the first time, wired to the platform's own Edit menu, and the
  one place it registers is a single grouped block per batch — so the shape is right if a later
  chain wants to register renames or deletions there too.
- Four call sites that could have drifted (`WorkspaceBoardResolver`, `repointBoardsPlan`,
  `moveNote`, `boardAfter*`) are reused rather than re-derived; the chain adds two file operations
  and one pure batch planner, and nothing else that computes a path.
- Every rule that decides anything — pruning, cycles, collisions, the collapse rule, the landing
  rule, the inverse batch — is a pure function over values and is unit-tested. Only the gesture
  itself needs a person.

### Negative

- **The undo stack is shared with the text editor.** Cmd+Z after typing undoes the typing; Cmd+Z
  again undoes a file move made ten minutes earlier. That is coherent macOS behaviour and it is
  still surprising the first time. It is on the manual-verification list, and A6 remains the
  documented way out if it proves wrong in use.
- **A board/folder move is undoable only for the life of the session**, through a manager nothing
  persists, while a note move is also in the durable journal. Two recovery stories for one gesture,
  and the difference is invisible in the interface.
- **R-15's UI coverage is the least certain thing in this chain.** XCUITest driving a real
  `NSDraggingSession` is untested territory here; the plan spikes it before the design leans on it
  and records a fallback rather than discovering the problem at the gate.
- One more exported uniform type identifier now belongs to this app's Info.plist, which is a small
  permanent commitment for an intra-app drag, and it contradicts the reasoning two existing payload
  types wrote down for themselves. §D3 states why; a reader who finds those comments first will
  briefly think this chain got it wrong.
- Two files gain a second responsibility: `BoardFileOperations` and `FolderFileOperations` were
  "rename and trash" and are now "rename, move and trash". Both are already near the size SwiftLint
  warns at.
- The Workspace and Note trees now share a payload type and a controller verb but still have two
  separate row implementations. This chain narrows the duplication without removing it, and a
  future reader may reasonably ask why there are still two.

### Neutral

- `IndexCache.schemaVersion` stays 3; no migration, no new index field, no new dependency
  (`Tuist/Package.swift` is untouched).
- `VaultAPI`, `perg` and `pergamenum-mcp` gain nothing and lose nothing — mechanically, because
  the two files that grew are not in `sharedSources`.
- `WorkspaceBoardResolver`, the `^[[x.canvas]]` marker grammar and
  `IndexSnapshot.tasks(assignedToWorkspace:)`'s file-name-only comparison are all left exactly as
  ADR-0025 left them. A move can change whether a bare board name is `.unique` or `.ambiguous` in
  the vault as a whole, and that is reported the way it already is, never guessed.
- The multi-selection set is not remembered across launches, and no preference is added.
- Reordering rows within a folder remains impossible, because neither tree has manual ordering to
  reorder — the SPEC puts it out of scope and nothing here moves toward it.

---

## References

- SPEC: `/Users/stefer/Developer/Pergamenum/SPEC.md` (R-01 … R-15).
- Plan: `docs/superpowers/plans/2026-08-27-drag-and-drop-board-files-into-workspace.md`.
- ADR-0016 §D1/§D6 — the journal's three entry kinds, and the plan/perform split.
- ADR-0021 §D1/§D3/§D5 — the `^[[<board>.canvas]]` marker carries a bare file name.
- ADR-0022 §D4 (relocated by ADR-0025 §D6), §D6 (no journal for a directory), §D8 (AX propagation),
  §D11 (the live collision predicate), §F10 (the autosave that lands on the old path).
- ADR-0023 §D1/§D4 — one command, two renderings.
- ADR-0024 §D1 (flat recursive rows), §D2/§D3 (**superseded in part here**), §D5, §D7, §D9.
- ADR-0025 §D1/§D2/§D3 (a board is its own path), §D5 (`board(inFolder:among:)`), §D6, §D9.
- Source read at `b429ee6`: `Sources/Vault/BoardFileOperations.swift`,
  `Sources/Vault/FolderFileOperations.swift`, `Sources/Vault/NoteFileOperations.swift`,
  `Sources/Vault/NoteTree.swift`, `Sources/Vault/VaultSession+Files.swift`,
  `Sources/Vault/VaultSession+Folders.swift`, `Sources/Vault/VaultController+Files.swift`,
  `Sources/Vault/VaultController+Folders.swift`, `Sources/Vault/CanvasStore.swift`,
  `Sources/Core/Tasks/WorkspaceBoardResolver.swift`,
  `Sources/Features/Workspace/WorkspaceBrowser.swift`,
  `Sources/Features/Workspace/WorkspaceTree.swift`,
  `Sources/Features/Workspace/WorkspaceSelection.swift`,
  `Sources/Features/Workspace/WorkspaceFolderActions.swift`,
  `Sources/Features/Workspace/WorkspaceView+FolderVerbs.swift`,
  `Sources/Features/Editor/NoteListPane.swift`, `Sources/Features/Editor/NoteRowMenu.swift`,
  `Sources/Features/Editor/CompletingTextView+Pasteboard.swift`,
  `Sources/Features/Editor/NoteTextView.swift`, `Sources/Features/Today/TaskDrag.swift`,
  `Sources/Features/Views/ViewBoardRenderer.swift`, `Sources/App/MenuCommands.swift`,
  `Sources/App/SidebarItem.swift`, `Project.swift`.
