# ADR-0025 — A folder is a container, a board is a file, and neither is named after the other

**To be moved by the operator to `docs/adr/0025-workspace-folder-board-separation.md`.**
This project's ADRs all live under `docs/adr/NNNN-slug.md`; the architect agent's write scope
forbids that directory, so the file is written here and moved by hand, exactly as ADR-0022,
ADR-0023 and ADR-0024 were. Every reference to it elsewhere is by **name** (`ADR-0025`), never by
path, so the move breaks nothing.

## Status

Proposed — 2026-08-27. To be accepted at Gate 2 of the `workspace-folder-board-separation` chain.

**Supersedes ADR-0024 §D3 in full**, and **§D2 in the two respects that made a board a property of
a folder**. Details in *What is superseded, and why* below, before the Context — because a reader
who knows ADR-0024 needs to know what stopped being true before they read anything else.

**Supersedes ADR-0022 §D5 in full** (the folder's own board file is renamed with the folder) and
**relocates ADR-0022 §D4** (the ambiguous-board-name guard) rather than deleting it, contrary to
this chain's SPEC. See §D6 and the *SPEC claims that are false* table in the plan.

**Base read:** every file:line quoted below was read at `93d3069`.
**Plan:** `docs/superpowers/plans/2026-08-27-workspace-folder-board-separation.md`.
**SPEC:** `/Users/stefer/Developer/Pergamenum/SPEC.md` (R-01 … R-18).

---

## What is superseded, and why

### ADR-0024 §D2 — «A row is a folder; the board that folder owns is drawn *on* it, never beside it»

Superseded in two respects, and reaffirmed in a third.

1. **The fold itself is reversed.** §D2 merged a folder and the `.canvas` named after it into one
   row, because «SPEC §6.2 makes a board a folder. The tree drew them as two rows, so the tree
   contradicted the app's own specification.» That premise is what this chain retires: the app
   specification's own §6.1 (`docs/20260811_Pergamenum_SpecApp.md:189-190`) is amended by R-17, so
   after this chain a board is *not* a folder and one row per folder is no longer the rule to hold
   to. A folder row and a board row are two rows because they are two things on disk.
2. **The root synthesis is deleted.** §D2's transform recognised the root board — «a top-level leaf
   with no folder node above it (F7) — and emit it as the row for folder `""`». There is no row for
   folder `""` any more. The tree's top level *is* the vault root's contents, which is what
   `NoteTree` already does for the note sidebar (F7) and what R-11 asks for by name.
3. **What survives, verbatim:** `id` is the `List`'s selection tag *and* the row's identity, one
   string, with no mapping step where two spellings could disagree; and the fold is a pure function
   in a file of its own rather than a decision taken inside a view body. §D3 below makes the first
   of those *stronger* than §D2 could: under §D2 the tag was a folder path chosen so that every case
   had one, and it collided with nothing by argument. Under this ADR every node's `id` is the node's
   own filesystem path, and a path names a file or a directory but never both — so tag uniqueness is
   a property of the filesystem instead of a property of the transform.

The `boardPath` closure parameter goes with the rule it existed to ask (§D1).

### ADR-0024 §D3 — «A `.canvas` that is not named after the folder holding it is drawn, and cannot be selected»

**Superseded in full.** `.foreignBoard`, its untagged row, its `workspace-foreign-board-<path>`
identifier and its structural non-selectability are all removed.

§D3's premise was: «it stops being clickable because there is nothing this app can do with it.»
That was true, and it stops being true at §D1 below. Nothing this app could do with such a file was
a consequence of `open(folder:)` being the only door into a board — the app could not *name* a
`.canvas` other than the one its folder implied. §D3 fixed the resulting defect (F6: a row whose
click opened a different board than the one it named) by making the row inert. This ADR fixes the
same defect by making the row open the board it names, which is what the row said all along.

§D3 is also where ADR-0024 recorded that hiding such files would be «the app editing the vault's
meaning, against binding principle 1 and principle 4». That reasoning survives and is strengthened:
every `.canvas` in the vault is now a first-class, openable board, whoever wrote it.

**ADR-0024 A3** («make the selection tag the board path rather than the folder path») was rejected
on two grounds, and both are answered rather than ignored. *«A board-less folder has no board path,
so Decision 3 would need a sentinel value»*: it does not, because a board-less folder is a `.folder`
row carrying its own real folder path — the tag namespace is «every path the tree draws», not «every
board path». *«A board opened from the breadcrumb onto a folder with no `.canvas` file yet would
have a tag no row carries»*: that state cannot arise, because nothing in the app opens a board that
does not exist (§D1's throwing load, §D5's resolver).

### ADR-0022 §D5 — «The folder's own board file is renamed with the folder, in the same operation»

**Superseded in full.** A folder rename renames no `.canvas` file. §D5 existed for F1 — «the board
silently reads as blank while its content sits on disk under the old name», ADR-0022's own «single
most damaging failure mode». That failure mode is closed at its root by §D1 rather than by a
compensating rename: a board is addressed by the path it actually has, and a load that cannot find
its file **throws** instead of returning `.empty`.

### ADR-0022 §D4 — «When the old board name is ambiguous, the marker rewrite is skipped and reported»

**Relocated, not removed.** This chain's SPEC states that this case «is removed, since there is no
more one board per folder to disambiguate». That reasoning does not hold, and the conclusion is
wrong in one direction and right in another:

- **Right:** §D4 leaves *folder rename*, because a folder rename no longer renames any board file
  and therefore has no file name to rewrite markers for. ADR-0022 §D2.2's whole name-level pass
  disappears from `FolderFileOperations`. R-09 is satisfied.
- **Wrong:** the ambiguity §D4 guards against is not a property of the folder↔board rule. It is a
  property of the `^[[<name>.canvas]]` marker grammar, which carries a bare **file name**
  (ADR-0021 §D1/§D5) and is matched case-insensitively by file name alone
  (`WorkspaceBoardResolver.matches`, `Sources/Core/Tasks/WorkspaceBoardResolver.swift:29-32`;
  `IndexSnapshot.tasks(assignedToWorkspace:)`, `Sources/Index/IndexSnapshot.swift:186-188`). That
  grammar is untouched by this chain (§D11), and this chain makes duplicate board file names
  **easier** to create, not harder — two folders can now each hold a `prova.canvas` deliberately,
  where before that required two folders sharing a name.

So §D4's guard attaches to the operation that now renames a `.canvas` file: **board rename** (§D6).
It is the same rule, on the same reasoning, in a different place.

### ADR-0022 §D9 — already superseded by ADR-0024 §D7

Its one surviving fragment is the root exemption («Rinomina»/«Elimina» refuse the vault root), which
§D8 keeps inside `canMutate` even though the root is no longer selectable, for the reason stated
there.

---

## Context

Fourteen facts constrain the design. They were read at `93d3069` rather than recalled, because five
of this chain's SPEC statements about the repository are false or under-determined (the plan's own
table lists all eight it found), and because three prior Workspace chains have each left a
documented trap in these files that a fourth would otherwise pay for again.

**F1 — A board's path is derived from its folder's last component, and the derivation is the
feature.** `CanvasStore.boardPath(forFolder:)` (`Sources/Vault/CanvasStore.swift:21-28`) maps
`01 Progetti/vibrofer-emea` → `01 Progetti/vibrofer-emea/vibrofer-emea.canvas`, and `""` → the
vault's own name. `url(forFolder:)`, `load(folder:)`, `save(_:folder:)` and
`contents(ofFolder:board:)` all go through it. Nothing in the app can name a `.canvas` any other
way.

**F2 — `load(folder:)` returns `.empty` for a file that is not there, and does not fail**
(`CanvasStore.swift:37-43`). ADR-0022 F1 named this «the single most damaging failure mode of the
feature». It is still there. Every silent-blank-board defect this codebase has had came through
this one `guard … else { return .empty }`, and any redesign that keeps an analogous path reintroduces
the whole class.

**F3 — `NoteTree.build(fromPaths:)` cannot represent an empty folder, and `NoteTree.swift` is a
shared file.** Its private `Builder` creates a folder node only from the path components of a leaf
(`Sources/Vault/NoteTree.swift:99-105, 110-132`), so a folder holding no `.canvas` produces no node
at all. There is no node for the vault root either: a root-level leaf is a top-level `.note`
(ADR-0024 F7). And `Sources/Vault/NoteTree.swift` is named in `sharedSources`
(`Project.swift:84`), so it compiles into `perg` and `pergamenum-mcp` — extending it for the
Workspace's benefit changes a type the note sidebar and both connectors read.

**F4 — Nothing else enumerates the vault's directories.** `VaultSession.folders`
(`Sources/Vault/VaultSession+Files.swift:93-106`) derives folders from **note** paths, which is
exactly why ADR-0022 §D11 refused it for the parent picker: «it would omit a folder that holds only
boards or only subfolders — precisely the folders a Workspace user creates». `CanvasStore.allBoards()`
(`CanvasStore.swift:113-136`) already walks the vault with the right exclusions
(`VaultLayout.isExcludedDirectory`, `VaultSettings.swift:257-259`) and discards every directory it
passes.

**F5 — A `.canvas` sibling already appears in the «Nuovi elementi» tray today.**
`contents(ofFolder:board:)` excludes exactly one path — `boardPath(forFolder: folder)`
(`CanvasStore.swift:92`) — and filters nothing by extension. A second `.canvas` in the folder is an
unplaced item and can be dropped onto the board as a file card. R-07's two clauses cannot both be
satisfied by keeping this.

**F6 — `openRoute` throws away the board path the route carried.**
`WorkspaceController+Viewport.swift:150-156` takes `route.path` — a real `.canvas` path from
`pergamenum://canvas?file=…` — reduces it to its folder, and opens *that folder's* board. A link to
`A/altro.canvas` opens `A/A.canvas`. This is ADR-0024 F6's defect surviving in the one place ADR-0024
did not look, because ADR-0024's §D3 made the tree row inert without making the route correct.

**F7 — `attach` loads the root board, and nothing needs it to.**
`WorkspaceController.attach` calls `load(folder: "")` then sets `current = nil`
(`WorkspaceController.swift:165-174`). `WorkspaceView` draws the board only `if
workspace.isShowingBoard` (`WorkspaceView.swift:136`), which is `current?.hasBoard ?? false`. The
loaded document is therefore never on screen. `Tests/CanvasTests.swift:357` asserts the breadcrumb
after `attach` is `["Workspace"]`, which is a statement about `current`, not about the document.

**F8 — Two callers turn a folder into a board and one of them re-opens the door ADR-0024 A5
closed.** `BoardCardMenu.open(_:)` (`:115-118`) enters a folder card's board;
`WorkspaceView.placePendingNote` (`:177-189`) sends a note from the editor to «the board of its own
folder» and, when that folder has no `.canvas` yet, `placeFile` writes one — which is precisely
«the first card dropped writes `<folder>/<folder>.canvas` and turns a grouping folder into a
workspace nobody asked to create», the outcome ADR-0024 A5 rejected. A5's rejection covered the
tree; this door was left open.

**F9 — The `^[[<name>.canvas]]` marker is a bare file name, by decision, and is written into every
task line that uses it.** ADR-0021 §D1/§D5; `WorkspacePicker`'s own doc comment («what is written is
the board's file name, not its vault-relative path»); `TaskParser+Writes.swift:94` for the plain
`[[name.canvas]]` form. `WorkspaceBoardResolver` already models the consequence as a first-class
outcome: `.unique(String)` / `.ambiguous` / `.notFound`
(`Sources/Core/Tasks/WorkspaceBoardResolver.swift:11-19`). Changing the grammar would rewrite task
lines in every note of the vault, which this chain's Non-goals forbid.

**F10 — There is no double-click handler on any Workspace tree row.** The row selects on a single
click through `List(selection:)` and the chevron toggles expansion through its own
`.onTapGesture` (`WorkspaceBrowser.swift:692-701`). R-05's «double-clicking a folder row expands or
collapses that row» is a behaviour to be **added**, and adding a tap gesture to a row inside a
`List(selection:)` is exactly the class of change ADR-0024 already paid for once: its
`.accessibilityElement(children: .combine)` incident swallowed the chevron's gesture into a merged
element and made a click on a row *with children* land on the triangle
(`WorkspaceBrowser.swift:626-648`, measured from a failing run's synthesized event coordinates).

**F11 — A `.contextMenu`'s entries are not in the accessibility hierarchy of the view that carries
it.** They are `NSMenuItem`s, found by a UI test through `app.menuItems["…"]` and never through the
row's `accessibilityIdentifier`. R-08 puts Rinomina/Elimina on a board row's context menu, so the
test for it cannot be written the way a test for a toolbar button is.

**F12 — `WorkspaceBrowser`'s header carries `.accessibilityElement(children: .contain)` and its own
identifier** (`WorkspaceBrowser.swift:247-249`), and on macOS an identifier on a container reaches
its descendants (ADR-0022 §F9). The toolbar is already a **sibling row** below it
(`WorkspaceBrowser.swift:85-90`, `WorkspaceBrowserToolbar.swift`), which is where R-07 of ADR-0022
put it and why. The «Nuova cartella» button of this chain goes into that existing sibling row and
inherits the property; it must not go into the header.

**F13 — `ShortcutCommand` is the catalogue of *remappable* shortcuts, not of all commands**
(ADR-0023 §D5). The board verbs of R-08 are toolbar and context-menu only and carry no key, so they
add no case.

**F14 — Target membership and the connector boundary need no edit, and one of the changed files is
already shared.** `Project.swift:139-141`: the app is `Sources/**` minus `Sources/CLI/**` and
`Sources/MCPServer/**`, so a new file under `Sources/Features/Workspace/` or `Sources/Vault/` enters
it automatically. `Project.swift:80` names **`Sources/Vault/CanvasStore.swift` in `sharedSources`
already**, and `Sources/Core/**` is a glob there (`Project.swift:73`) — so §D1's and §D5's changes
compile into `perg` and `pergamenum-mcp` whether anybody wants them to or not. Grepped at
`93d3069`: `Sources/Connector/**`, `Sources/CLI/**` and `Sources/MCPServer/**` contain **zero**
call sites for `boardPath(forFolder:)`, `url(forFolder:)`, `load(folder:)`, `save(_:folder:)` or
`contents(ofFolder:board:)`. R-15 is therefore a build check, not a rewrite.

---

## Decision

### D1 — A board is addressed by its own file path, and a load that cannot find its file fails

`CanvasStore` stops deriving and starts being told:

| Before | After |
|---|---|
| `boardPath(forFolder: String) -> String` | **removed** |
| `url(forFolder: String) -> URL` | `url(forBoard: String) -> URL` |
| `load(folder: String) throws -> CanvasDocument` | `load(board: String) throws -> CanvasDocument` |
| `save(_: CanvasDocument, folder: String) throws -> String` | `save(_: CanvasDocument, board: String) throws -> String` |
| `contents(ofFolder: String, board: CanvasDocument) -> FolderContents` | `contents(ofBoard: String, document: CanvasDocument) -> FolderContents` |
| — | `createBoard(named: String, in: String) throws -> String` |
| — | `boardNameIsAvailable(_: String, in: String) -> Bool` |
| — | `allFolders() -> [String]` |
| `createFolder(named:in:)` | unchanged |

Two of those rows are the decision and the rest are consequence.

**`boardPath(forFolder:)` is deleted, not deprecated.** A rule that still exists is a rule a caller
can still ask, and the failure it produces is a board that opens the wrong file — silently. There is
no fallback «the folder's default board»; §D5 is the one place that answers «which board does this
folder mean», it answers with a resolution rather than a name, and it can answer «none».

**`load(board:)` throws `StoreError.missing(path)` where `load(folder:)` returned `.empty`.** This
is the point of the whole chain expressed in one signature. F2's silent fallback existed because
`boardPath(forFolder:)` could name a file that had never been created — under F1 that was the
normal case, since a board file «appears when something is placed on it». Under path addressing it
is not the normal case: every path the tree offers is a file the walk found, `createBoard` writes
the file before anything opens it, and `attach` opens nothing (§D4). A missing file now means the
disk moved under us, which is a thing to report, not a thing to render as a blank board.

`contents(ofBoard:document:)` derives the containing folder with `deletingLastPathComponent`, so
file-drop placement is unchanged: a dropped file lands beside the open board, in its containing
folder. It also **excludes every `.canvas` in that folder from `unplaced`**, not just the open one —
see §D10.

`allFolders()` reuses `allBoards()`'s enumerator, its `skipsPackageDescendants` option and its
`VaultLayout.isExcludedDirectory` skip, collecting the directories that walk already visits and
discards (F4). Not `VaultSession.folders`, for ADR-0022 §D11's reason exactly.

### D2 — The tree is built from folders **and** boards, they are different rows, and the vault root is the list

```swift
enum WorkspaceTree {
    struct Node {
        enum Kind: Equatable { case folder, board(path: String) }
        let id: String          // the node's own vault-relative path
        let name: String        // folder name, or the board file name without ".canvas"
        let kind: Kind
        let children: [Node]
        let boardCount: Int     // boards at or below this node
    }
    static func build(folders: [String], boards: [String]) -> [Node]
    static func flattened(_ nodes: [Node]) -> [(node: Node, depth: Int)]
    static func folders(in nodes: [Node]) -> [String]
    static func node(withID id: String, in nodes: [Node]) -> Node?
}
```

Four properties, and the fourth is the one worth the diff:

- **`id` is always the node's own path**: a directory path for `.folder`, a file path for `.board`.
  A `.board` node's `id` and its `kind`'s payload are the same string, and the payload is kept
  because a `switch` that has to reach for `id` to get the board path is a `switch` a later reader
  will get wrong.
- **Tag uniqueness is a filesystem property.** ADR-0024 §D2 argued for one spelling of «which row»;
  here a path names a file or a directory but never both, so two rows cannot carry the same tag no
  matter what the transform does.
- **No root row.** `NoteTree` emits none for the note sidebar (F3) and the two sidebars must indent
  alike or they read as two designs. R-11's «at the top of the tree» means «among the top-level
  rows», beside the root's folders. With nothing selected, `.folder("")` is never constructed — see
  §D3.
- **`build` does not go through `NoteTree.build(fromPaths:)`.** It cannot: that builder makes a
  folder node only out of a leaf's path components, so every empty folder R-10 requires would
  vanish (F3). Extending `NoteTree` was rejected (A4) because it is a shared file the note sidebar
  and both connectors read. `WorkspaceTree.build` therefore does its own two-list walk and
  **replicates `NoteTree`'s ordering rule exactly** — folders first, then leaves, each group by
  `localizedStandardCompare` — because that ordering is what makes `9 Note` sort before `10 Note` in
  both sidebars.

`folders(in:)` narrows to `.folder` ids and feeds «Espandi tutto». The stale-selection drop stops
asking it and asks `node(withID:in:) == nil` instead, which is one question over both kinds rather
than a second list to keep in step.

### D3 — One selection, still one string, and it names a board file or a folder

```swift
enum WorkspaceSelection: Equatable, Sendable {
    case board(path: String)   // this .canvas is loaded and on screen
    case folder(String)        // selected for the toolbar's verbs; opens nothing

    var path: String           // the id either case names — the List's tag
    var folder: String         // the containing folder: deletingLastPathComponent for .board, self for .folder
}
```

`path` replaces ADR-0024's `folder` property as «the id either case names», and a **new** `folder`
means «the folder this selection sits in». That second accessor is not a convenience: it is what
keeps «create the new board where the selected row is» (§D7) and «where does a dropped file go»
(§D1) answerable without a branch at every call site, and it is why this stays one value rather than
becoming two again (A5).

**`.folder("")` is never produced.** There is no root row to click (§D2), the breadcrumb's root
segment calls `select(nil)` (§D4), and nothing selected is `nil`. The type can spell it; the app
does not.

### D4 — The controller opens a board, and `folder` becomes derived

- `open(folder:)` → **`open(board path: String)`**.
- `private(set) var folder` stops being stored and becomes
  `var folder: String { (board as NSString).deletingLastPathComponent }` over a new stored
  `private(set) var board = ""`. Its ten readers compile unchanged, which is the point: `folder`
  still answers «which directory is the open board in», it just stops being the identity.
- **`attach` loads nothing.** `board = ""`, `document = .empty`, `current = nil`. F7 says nothing
  needed the load; §D1 says there is no root board to load; `Tests/CanvasTests.swift:357`'s
  breadcrumb assertion is about `current` and survives.
- `load(board:)` returns `false` and records the problem when `CanvasStore.load(board:)` throws, so
  `open(board:)` does not select a board that is not there. The `.empty` fallback has no successor.
- `select(_:)` keeps its shape and its `guard new != current else { return }` — ADR-0024 §D4's
  no-op guard is load-bearing for ADR-0023 §D4's «set the selection, then raise the sheet» and this
  chain adds two more context-menu verbs that do it (§D8).
- `breadcrumb` derives from `current` (ADR-0024 §D8.1, reaffirmed). For `.board(p)` the trail is
  `Workspace › <folder components of p> › <board name>`; for `.folder(F)` it is
  `Workspace › <components of F>`. The last segment stays a `Text` and not a `Button`
  (ADR-0024 §D8.2) — an ancestor segment is a place you can go, and now it goes there by
  **selecting the folder**, not by opening a board that folder may not have. The root segment
  («Workspace») calls `select(nil)`, which is the only spelling of «nothing selected» (§D3).
- `openRoute` calls `open(board: route.path)` directly, deleting the
  `deletingLastPathComponent` that discarded the link's own answer (F6).

### D5 — Exactly one thing resolves «a folder» to «a board», and it is the resolution enum that already exists

`WorkspaceBoardResolver` (`Sources/Core/Tasks/`, pure, already shared by glob) gains one function
beside the marker lookup it already has:

```swift
static func board(inFolder folder: String, among boards: [String]) -> WorkspaceBoardResolution
```

matching on `deletingLastPathComponent == folder`, and returning the **same three-case enum**
(`.unique(path)` / `.ambiguous` / `.notFound`) the `^[[x.canvas]]` lookup returns. One enum for
«which board did this marker mean» and «which board does this folder mean» is not tidiness: both
questions are «I have a name for a board and the vault may disagree about which one», and a second
enum would be a second place to get the ambiguous case wrong.

Three callers, one rule: **`.unique` opens that board; `.ambiguous` and `.notFound` select the
folder and open nothing.**

- the breadcrumb's folder segments (§D4);
- a folder card's double click on the board (`BoardCardMenu.open(_:)`);
- the editor's hand-off (`WorkspaceView.placePendingNote`), which **also** records a problem,
  because the other two are navigation and this one is a gesture that would otherwise land nowhere.

This is what closes F8's door, and with it the last path by which the app creates a `.canvas` file
nobody asked for. On the existing vault, where every folder holds at most one board, all three
behave exactly as they do today (R-13).

The tree is deliberately **not** a caller. A folder row selects the folder, full stop (§D9) — a
resolver on the tree would be «one board per folder» returning as a special case, which R-05
forbids by name.

### D6 — Board rename and board delete are file operations in the folder-verb layer, and ADR-0022 §D4's guard moves here

New `Sources/Vault/BoardFileOperations.swift`, `FolderFileOperations`'s shape: validation and a
plan computed without touching disk, then a performer that writes directly through `FileManager`
and `NoteStore` (ADR-0022 §D1/§F8). `Sources/Vault/VaultSession+Folders.swift` and
`Sources/Vault/VaultController+Folders.swift` gain the session and facade halves beside the folder
verbs they already hold — no star remap and no tab follow-up, because a board is not a note.

**Rename** (`<folder>/<old>.canvas` → `<folder>/<new>.canvas`, same folder, never a move):

1. refuses a name already taken by another `.canvas` in that folder (the same predicate the sheet
   blocks on, `CanvasStore.boardNameIsAvailable`);
2. repoints every `.canvas` **node** whose `file` path is the old board path, in every board of the
   vault — reusing the vault-wide repoint pass that `FolderFileOperations.swift:223-260` and
   `NoteFileOperations.swift:300-324` each already run, never a third implementation of it;
3. rewrites `[[old.canvas]]` and `^[[old.canvas]]` in every note through
   `NoteRename.rewritingLinks(in:from:to:)` **unchanged** — ADR-0021 §D3's caret geometry means the
   marker form costs no new code, exactly as ADR-0022 §D3 found;
4. **skips step 3 whole and reports it** when the old file name names more than one board in the
   vault. This is ADR-0022 §D4 verbatim, relocated: after renaming `A/x.canvas`, a `B/x.canvas` still
   exists and every `^[[x.canvas]]` that meant *it* is still correct.

**Delete** moves the `.canvas` to the Trash with `FileManager.trashItem(at:resultingItemURL:)` and
returns the resulting URL, which is what lets a unit test prove it went to the Trash rather than
being unlinked (ADR-0022 §D7). **No marker rewrite on delete:** an orphaned marker is already a
first-class outcome (`WorkspaceBoardResolution.notFound`, F9) and a note delete leaves dangling
wikilinks for the same reason.

**Neither verb is journalled and neither is exposed to `VaultAPI`**, extending ADR-0022 §D6 to
boards on its own terms rather than by analogy. `WriteJournal.Entry.removal` restores from
`textBefore` and a `.canvas` *is* text, so a board delete is technically journallable — but a rename
that also rewrites N notes and repoints M boards is a gesture whose reversal the journal's three
entry kinds cannot express as a unit, and ADR-0016 §D1 («all of a gesture or none of it») makes a
half-journalled pair worse than an unjournalled one. Recovery is the Trash and a reverse rename, the
same story the folder verbs already tell. This is what keeps `BoardFileOperations.swift` out of
`sharedSources` (A10).

### D7 — Two creation verbs, and creating a folder creates nothing else

`WorkspaceBrowserToolbar` gains a second button in the row it already is (F12):
«Nuova board» keeps `plus` and the identifier **`workspace-new`**; «Nuova cartella» gets
`folder.badge.plus` and **`workspace-new-folder`**. Both sit in
`WorkspaceBrowserToolbar`, never in the header.

`WorkspaceView+FolderVerbs.createWorkspace(named:in:)` splits:

- `createBoard(named:in:)` → `CanvasStore.createBoard`, then `open(board:)` on what it wrote;
- `createFolder(named:in:)` → `CanvasStore.createFolder` alone, then `select(.folder(created))`.
  **The `try store.save(.empty, folder: created)` at `WorkspaceView+FolderVerbs.swift:32` is
  deleted**, and that one deleted line is R-01.

Both reuse `NewWorkspaceSheet` with a `kind` parameter switching its title and its collision
predicate (`CanvasStore.boardNameIsAvailable` vs `FolderFileOperations.nameIsAvailable`) — one
sheet, so there is one creation dialect and not two (ADR-0022 §D11). The identifiers
`workspace-new-sheet`, `workspace-new-name` and `workspace-new-parent` are preserved for both, so no
existing UI assertion moves.

The target folder is `current?.folder ?? ""` — §D3's second accessor, which is why a **board** row
being selected creates the new board beside it rather than nowhere.

### D8 — The toolbar's two verbs dispatch on the selection's case, through one rule in one place

`WorkspaceBrowserToolbar.canMutate(folder: String) -> Bool` becomes
`canMutate(_ selection: WorkspaceSelection?) -> Bool`:

- `nil` → `false` (nothing selected: the verbs are disabled, ADR-0024 §D7);
- `.board` → `true` (a `.canvas` file is never the vault root);
- `.folder(f)` → `!f.trimmingCharacters(in: .init(charactersIn: "/")).isEmpty`.

That last branch is ADR-0022 §D9's root exemption, kept even though §D2 makes the root
**unselectable by construction**. A guard whose precondition is «this state is unreachable» is a
guard that stops being true the first time somebody makes it reachable, and this pane has had three
chains in a row add rows to it.

Both surfaces read the one rule (ADR-0023 §D1): the toolbar's `.disabled`, and the row's context
menu. The identifiers `workspace-rename` and `workspace-delete` are **preserved unchanged** for both
kinds; only the `.help` and the accessibility label adapt («Rinomina board» / «Rinomina cartella»),
because a UI test reads the identifier and never the words (CLAUDE.md) and 200 points of pane will
not hold four buttons where two will do.

The board row's Rinomina/Elimina are context-menu and toolbar entries only and add **no
`ShortcutCommand` case** (F13).

### D9 — Double-click on a folder row toggles it, as a simultaneous gesture, and opens nothing

`.simultaneousGesture(TapGesture(count: 2).onEnded { toggle() })` on the folder row's content,
**before** the `.tag`, which stays the last modifier in the chain and the one nothing may follow
(ADR-0024 §D1/F4 — a modifier applied after `.tag` drops it and the list then lights nothing and
swallows every click, silently).

`simultaneousGesture` rather than `onTapGesture(count: 2)` because the latter consumes the click
and `List(selection:)` would never see it. The double click therefore both selects the folder and
toggles it, which satisfies R-05 as written: selecting a folder is not opening a board.

**This behaviour is unverified in this repository** (F10) and it is the one part of this design that
rests on a SwiftUI behaviour rather than on something the code already does. It is a
manual-verification item before merge, with a stated fallback: if the simultaneous gesture does not
fire, or fires at the cost of single-click selection, move the double-click onto the chevron's
existing hit target and record the finding in a comment. A fallback with a trigger, not a hedge.

### D10 — The tray shows no `.canvas` at all

`contents(ofBoard:document:)` excludes every entry whose extension is `canvas` from `unplaced`, not
only the open board's own file.

R-07's two clauses («excludes only the file of the currently-open board» and «sibling `.canvas` files
in the same folder do not appear as tray cards») cannot both hold, because nothing filters by
extension today and a sibling already reaches the tray (F5). The second clause is the one with a
reason attached — «the tray shows unplaced items, not a board switcher» — and one predicate is
easier to test and to read than an exception list. A `.canvas` that was already placed as a card on
some board keeps rendering; this changes what the tray *offers*, not what a board *draws*.

### D11 — What deliberately does not change

- **The `^[[<name>.canvas]]` marker grammar** stays a bare file name (F9, ADR-0021 §D1/§D5), and
  `IndexSnapshot.tasks(assignedToWorkspace:)` / `WorkspaceBoardResolver.matches` keep comparing
  lowercased file names. Changing it to a path would rewrite task lines in every note of the vault,
  which this chain's Non-goals forbid (A8). **Consequence, stated rather than discovered:** this
  chain makes duplicate board file names easier to produce, so `.ambiguous` becomes more reachable —
  in `WorkspacePicker`, in the tray's assigned-task count, and in §D6's rename guard. Every one of
  those already degrades correctly; none of them guesses.
- **`IndexCache.schemaVersion` stays 3** and `.canvas` files stay out of the index (ADR-0021 §D10).
  It is a declared protected interface (`.claude/protected-interfaces`); a diff touching it in this
  chain is a design error.
- **`VaultAPI.LintFinding`** — the other protected interface — is untouched, and no connector
  capability is added (ADR-0022 §D6, extended by §D6 above).
- **No `Project.swift` edit and no `sharedSources` entry** (F14). `CanvasStore.swift` and
  `Sources/Core/**` are already there; new files under `Sources/Vault/` and
  `Sources/Features/Workspace/` enter the app target through `Sources/**`. `tuist generate --no-open`
  is still required after any task that adds a file — the generated project lists files and does not
  regenerate itself.
- **No data migration, no vault rewrite.** `prova/prova.canvas` needs no change on disk; it is read
  as «the board named `prova`, inside the folder `prova`», and after this chain the tree draws both,
  which is the Finder model arriving where the vault already was.
- **`pergamenum://canvas?file=…` semantics** are unchanged. The scheme already carried a board file
  path; §D4 makes the app honour it (F6).
- **The JSON Canvas format**, `CanvasDocument`, `CanvasID`, and Obsidian round-tripping. No new
  prefixed key, no new node kind.
- **`NoteTree`** gains nothing (F3, A4).

---

## Alternatives considered

**A1 — Keep `boardPath(forFolder:)` as «the folder's default board» and address only additional
boards by their own path.**
The smallest diff that satisfies R-03, and it was the first shape considered. Rejected: two
addressing rules is one more than the number of rules that can be right, and the silent-empty read
of F2 has to survive for the derived one — a folder with no `.canvas` still resolves to a name, and
opening it still has to render *something*. Every defect this chain exists to close (F2's blank
board, F6's route, F8's accidental creation, ADR-0024 F6's mis-opening row) is an instance of «a
name derived from somewhere else», and keeping the derivation for the common case keeps the class.

**A2 — Migrate the vault: rename every `prova/prova.canvas` to a name that cannot be confused with
its folder.**
Rejected on three counts. The SPEC's Non-goals forbid it; binding principles 1 and 4 make the vault
a directory a person also uses from Finder and Obsidian; and there is nothing wrong with
`prova/prova.canvas` — it is a valid path under the new model and reads perfectly well. A migration
that changes files to satisfy a model is the model failing to describe what is there.

**A3 — Keep one row per folder and disclose its boards only when there is more than one.**
Rejected: it is the current model with a special case bolted on, and it makes «how many `.canvas`
files does this folder contain» something the user must know before they can predict what a click
does. R-05's «including one containing exactly one board» exists to forbid exactly this, and the
reason is better than the requirement's wording: the whole point of the Finder model is that a
folder behaves the same way whatever is inside it.

**A4 — Extend `NoteTree.build(fromPaths:)` with an `emptyFolders:` parameter so the Workspace can
keep folding it.**
Tempting, because ADR-0024 §D2 and ADR-0021 §D10 both made a deliberate point of reusing `NoteTree`
rather than writing a parallel tree. Rejected: `Sources/Vault/NoteTree.swift` is named in
`sharedSources` (F14), so the parameter would compile into `perg` and `pergamenum-mcp` and would sit
in the note sidebar's hot path forever, for a caller neither of them has. `WorkspaceTree`'s own
builder is roughly thirty lines over two flat lists, and §D2 requires it to replicate `NoteTree`'s
ordering rule exactly — which is the real cost of this alternative, paid once and pinned by a test,
rather than a shared type gaining an argument only one caller passes.

**A5 — Go back to two variables: a board path for what is drawn and a folder path for what the
toolbar targets.**
Rejected without much thought, and recorded so nobody proposes it as «obviously simpler now that
they are different things». ADR-0024 F1 is this pane's own history: two variables that must agree
are two variables that will disagree at the next feature, and this is the fifth chain to touch these
files. §D3's second accessor gives the toolbar its folder from the one value, derived, which cannot
diverge from what it derives from.

**A6 — Give a board a stable identity inside the `.canvas` file — a generated id under a prefixed
key — so renaming and moving it break nothing.**
Rejected. JSON Canvas 1.0 has no such field, so it would be a Pergamenum-only key (ADR-0020's
mechanism), and every board this app did not write would lack one — which means a fallback to the
path anyway, for the majority of a vault opened from Obsidian. Binding principle 4 makes «works
without conversion» the test, and an identity scheme that only works on files we wrote fails it.
The path is the identity the filesystem already maintains.

**A7 — Let a folder row open its board when the folder contains exactly one.**
Rejected **as a tree behaviour**, and this is the one alternative that is half-accepted rather than
refused. In the tree it is the «one board per folder» model returning as a special case, and R-05
forbids it by name. It is accepted for §D5's three *navigation-from-elsewhere* callers, where the
alternative is a gesture that lands nowhere — and there it degrades to selecting the folder rather
than to guessing, which is the property that makes the two treatments consistent rather than
contradictory: **nothing ever opens a board the user did not name, and nothing ever opens a board
that does not exist.**

**A8 — Rewrite every `^[[x.canvas]]` marker in the vault to carry a vault-relative path, so board
ambiguity disappears for good.**
The honest long-term fix, and rejected here on scope rather than on merit. It rewrites task lines in
every note of the vault, which this chain's Non-goals forbid; it changes a grammar ADR-0021 §D1/§D5
fixed deliberately; and it would need the marker's reader, its writer, `WorkspacePicker`, the tray's
assigned-task query and `IndexSnapshot` to change together, in a chain about the Workspace tree.
§D11 states the increased ambiguity plainly instead of hiding it, and §D6 reports rather than
guesses when it bites. Named here as a follow-up somebody may want.

**A9 — Exclude only the currently-open board from the tray, as this chain's SPEC Architecture
section says.**
Rejected: it contradicts the SPEC's own R-07 second clause and the rationale attached to it, and it
is not even the status quo — a sibling `.canvas` already appears in the tray today (F5), so
«continues to exclude only the open board» describes a behaviour that would newly surface board
files as droppable cards the moment a folder is allowed two of them. One predicate over an
extension, stated in §D10, is the reading that makes both of R-07's clauses true.

**A10 — Put board rename and delete on `CanvasStore`, which already exists and is already shared,
instead of a new `BoardFileOperations`.**
Rejected: `CanvasStore.swift` is named in `sharedSources` (F14), so the two verbs would compile into
`perg` and `pergamenum-mcp` and be available to a connector capability ADR-0022 §D6 deliberately
withholds until `WriteJournal` can describe the gesture. A new file under `Sources/Vault/` is
app-only automatically, which makes the exclusion a compile-time fact rather than a promise — the
same argument ADR-0022 §D1 made for `FolderFileOperations`, and the reason the two files are
siblings rather than one.

**A11 — Keep `.foreignBoard` for a `.canvas` this app did not write, so «boards Pergamenum made» stay
visually distinct.**
Rejected: the distinction has no consequence left. Under §D1 the app can open, rename and delete any
`.canvas` by path, so «foreign» would be a label with no behaviour behind it — and the one behaviour
it used to carry (unselectable) was a workaround for the addressing defect this chain removes.
Binding principle 4 wants the Labs vault's canvases to be ordinary; drawing them as ordinary is the
literal version of that.

---

## Consequences

### Positive

- **The silent blank board is structurally impossible.** F2's `return .empty` is gone, `attach`
  loads nothing, and the only paths that reach `load(board:)` carry a path the walk found or
  `createBoard` just wrote. ADR-0022 called this the feature's single most damaging failure mode and
  spent §D5 compensating for it; this removes it instead.
- **Three latent defects close on the way past.** A `pergamenum://canvas` link to a board other than
  its folder's own now opens the board it names (F6). A `.canvas` not named after its folder is
  openable rather than inert (ADR-0024 §D3). And the editor hand-off can no longer conjure a
  `.canvas` into a grouping folder (F8) — the last door ADR-0024 A5 left open.
- **A folder becomes a folder.** An empty folder is visible (R-10), a folder with three boards shows
  three rows, and creating a folder creates a folder. One deleted line
  (`WorkspaceView+FolderVerbs.swift:32`) is most of that.
- **The «new folder» toolbar button stops being blocked.** It was deferred through ADR-0022 and
  ADR-0024 because a folder with no board did not appear in a tree built from `allBoards()`. §D2
  unblocks it and §D7 ships it.
- **Tag uniqueness stops being an argument.** Under ADR-0024 §D2 it was a property of the transform;
  under §D2 here it is a property of the filesystem.
- **One resolution enum answers both «which board» questions** (§D5), where the codebase previously
  had an enum for the marker case and an implicit derivation for the folder case.
- **`WorkspaceController` loses a stored property** (`folder` becomes derived) and `attach` loses a
  load. This chain removes state in the controller even while adding rows to the tree.

### Negative

- **This is a wide change to a pane four chains have already touched.** `CanvasStore`'s five-member
  signature change reaches `WorkspaceController`, `BoardTray`, `BoardCardMenu`,
  `FolderFileOperations`, `WorkspaceBrowser` and seven test files, and the tree's `Kind` change
  reaches most of `WorkspaceBrowser.swift`. There is no incremental path: A1 was the attempt to find
  one and it keeps the defect class.
- **Duplicate board file names get easier to create, and the `^[[x.canvas]]` marker still matches by
  file name** (§D11, F9). Two folders can now each hold a `prova.canvas` on purpose. Every consumer
  degrades correctly — `.ambiguous` is reported, never guessed — but «assign this task to a board»
  gets less precise in a vault that uses the new freedom, and A8 is the fix this chain does not do.
- **The tree gets taller.** Every folder that owns a board is now two rows where ADR-0024 §D2 made
  it one, and that was §D2's stated goal. On the existing vault, where nearly every folder holds
  exactly one board, the row count roughly doubles. That is the price of the model and the
  disclosure state is the only mitigation.
- **A folder rename and a board rename can both leave a `^[[x.canvas]]` marker stale**, in different
  ways: the folder rename no longer touches markers at all (correct, since it renames no board), and
  the board rename skips them when the name is ambiguous (§D6). Neither is undoable in the app
  (§D6). This is a real reduction in guarantees relative to a note rename, accepted rather than
  hidden, and it is the same trade ADR-0022 §D6 made.
- **R-05's double click rests on an unverified SwiftUI behaviour** (§D9, F10), in a row structure
  whose gesture handling this repository has already been bitten by once. It is a manual check
  before merge with a named fallback, and it cannot be unit-tested.
- **`UITests/WorkspaceOpenStateUITests.swift:146-147` inverts.** It currently asserts that a folder
  owning a board must *not* also have a `workspace-folder-` row — the literal statement of ADR-0024
  §D2, and exactly what this chain reverses. Inverting a green assertion is the correct action here
  and it is also the shape of a mistake, so it is named in the plan's contract table rather than
  left to be discovered in a diff.
- **`WorkspaceBrowserToolbar.canMutate` changes its parameter type**, so the pure rule ADR-0022 §D8
  made testable-without-a-view is a contract change with a rewritten test file. Small, but it is the
  second chain in a row to move it.

### Neutral

- **No new dependency, no schema change, no index change, no `Project.swift` edit** (F14, §D11).
  GRDB still does not exist in this repository; `IndexCache.schemaVersion` stays 3; both declared
  protected interfaces are untouched.
- **No data migration and no file on disk changes shape.** The `.canvas` format, `CanvasDocument`
  and Obsidian round-tripping are untouched; what changes is which paths the app is willing to name.
- **`perg` and `pergamenum-mcp` are byte-identical in behaviour**, but they are **not** untouched by
  the compiler: `CanvasStore.swift` is in `sharedSources` (F14), so both tool builds must succeed on
  the new signatures. Zero call sites exist in either front end, so R-15 is a build check.
- **No new `ShortcutCommand` case and no new key binding** (F13, ADR-0023 §D5).
- **The identifiers `workspace-board-<boardPath>`, `workspace-folder-<folderPath>`,
  `workspace-filter`, `workspace-tree`, `workspace-flat-list`, `workspace-browser-header`,
  `workspace-browser-toolbar`, `workspace-new`, `workspace-rename`, `workspace-delete`,
  `workspace-expand-all`, `workspace-collapse-all`, `workspace-delete-confirm`,
  `workspace-new-sheet`, `workspace-new-name`, `workspace-new-parent` are preserved byte-identical.**
  Exactly one is removed (`workspace-foreign-board-<path>`, asserted by one unit test and no UI
  test) and exactly one is added (`workspace-new-folder`).
- **ADR-0023 §D2's «attach the context menu to the row, never to a container that reaches disclosed
  descendants» is still structural**, because ADR-0024 §D1 removed the `DisclosureGroup` and this
  chain does not bring it back. §D9's double-click gesture is the first new gesture on a row since
  then and is the reason F10 is written down.
- **The UI language stays Italian** and every new string («Nuova cartella», «Rinomina board»,
  «Elimina board») follows the existing surface. No hardcoded colour is added: §D2's icon change is
  a symbol change, and the selected row keeps the system's own fill (ADR-0024 R-02).
- **`.claude/test-cmd` is unchanged.** This chain adds unit tests to the bundle it already runs and
  UI tests to the suite run by hand before a merge, which is the split `CLAUDE.md` requires.

---

## References

- SPEC of this chain: `/Users/stefer/Developer/Pergamenum/SPEC.md` (R-01 … R-18).
- App specification: `docs/20260811_Pergamenum_SpecApp.md` — §6.1 lines **189** («Gerarchia»),
  **190** («Mappatura su disco») and **194** («Rinomina ed eliminazione cartella», which also
  describes the board-file rename and the ambiguity skip §D6 relocates), and §6.4 tool 4 line
  **227** («Cartella»). All four are amended by R-17; the SPEC of this chain names only two of them.
- **ADR-0024**, `docs/adr/0024-workspace-board-tree-single-selection.md` — §D3 **superseded in
  full**; §D2 **superseded** in its fold and its root synthesis, reaffirmed in its one-string tag and
  its pure-transform placement; A3's two rejection grounds answered; §D1 (flat recursive rows, `.tag`
  last) unchanged and depended on; §D4 (`select`'s no-op guard) unchanged; §D5 (the triangle expands,
  the row selects) unchanged and extended by §D9; §D6 (the browser is handed a value and a closure)
  unchanged; §D7 (no fallback target) unchanged, its root exemption living on in §D8; §D8 (the
  breadcrumb derives from the selection) unchanged and re-derived over the new cases; §D9 (VoiceOver
  by label and trait) unchanged; A5 (a grouping folder must not silently become a workspace) —
  §D5 closes the door A5's reasoning missed.
- **ADR-0022**, `docs/adr/0022-workspace-ui-creazione-board-toolbar-e-r.md` — §D5 **superseded in
  full**; §D4 **relocated** to §D6 here; §D2.2's name-level rewrite pass removed from folder rename;
  §D1 (a rules type with a plan/perform split) followed by `BoardFileOperations`; §D6 (no journal, no
  connector exposure) extended to boards on its own reasoning; §D7 (`trashItem`, never `removeItem`)
  followed; §D8/§F9 (the toolbar is a sibling of the header) unchanged and depended on by §D7;
  §D9 superseded already by ADR-0024 §D7, its root exemption kept in §D8; §D10 (the browser decides,
  `WorkspaceView` performs) unchanged; §D11 (one sheet dialect; not `vault.folders`) followed by §D7
  and §D1.
- **ADR-0023**, `docs/adr/0023-universal-command-surface-parity.md` — §D1 (one rule, two surfaces)
  followed by §D8; §D2 (context menu on the row) still structural; §D4 (the menu sets the selection
  before raising a sheet) preserved through `select(_:)`'s no-op guard; §D5 (`ShortcutCommand` is the
  remappable catalogue) — why the board verbs add no case.
- **ADR-0021**, `docs/adr/0021-workspace-tasks-notes-integration.md` — §D1/§D3 (the
  `^[[<name>.canvas]]` marker, its bare-file-name grammar and its caret safety) untouched and
  depended on by §D6; §D10 (`.canvas` files are not indexed) unchanged.
- **ADR-0020** §D5 — the crop is modal state ended on the way out of a board; `open(board:)` and
  `select(_:)` inherit that obligation unchanged.
- **ADR-0016** §D1/§D2/§D3 — all of a gesture or none of it; the journal's three entry kinds. Why
  §D6 journals neither board verb.
- **ADR-0017** — derived state lives outside the vault; nothing here is persisted.
- **ADR-0007** §D3/§D6 — the connector contract §D6 deliberately does not extend.
- **ADR-0001** §D1 — `Sources/Core/**` must not import SwiftUI; §D5's addition to
  `WorkspaceBoardResolver` is Foundation-only and both tool builds enforce it.
- `CLAUDE.md` — binding principle 1 (file over app: §D1, §D7, §D11), principle 4 (Obsidian
  compatibility: §D2, A6, A11); «a UI test must not find a control by the words on it» (§D8's
  identifier preservation); the design-token rule; the `List(selection:)`/`DisclosureGroup` trap
  (§D2, §D9); `scripts/uitests.sh` before every merge to `main`.
- `FileManager.trashItem(at:resultingItemURL:)` — moves a file or directory to the trash and
  reports its resulting location; the convention ADR-0022 §D7 fixed and §D6 reuses.
- Code read at `93d3069`: `Sources/Vault/CanvasStore.swift`, `Sources/Vault/NoteTree.swift`,
  `Sources/Vault/FolderFileOperations.swift`, `Sources/Vault/NoteFileOperations.swift`,
  `Sources/Vault/VaultController+Folders.swift`, `Sources/Vault/VaultSession+Files.swift`,
  `Sources/Vault/VaultSettings.swift`, `Sources/Core/Tasks/WorkspaceBoardResolver.swift`,
  `Sources/Index/IndexSnapshot.swift`, `Sources/Features/Workspace/WorkspaceTree.swift`,
  `WorkspaceSelection.swift`, `WorkspaceBrowser.swift`, `WorkspaceBrowserToolbar.swift`,
  `WorkspaceFolderActions.swift`, `WorkspaceView.swift`, `WorkspaceView+FolderVerbs.swift`,
  `WorkspaceController.swift`, `WorkspaceController+Viewport.swift`, `BoardChrome.swift`,
  `BoardCardMenu.swift`, `BoardTray.swift`, `Project.swift`, `.claude/protected-interfaces`,
  `.claude/test-cmd`, and the seven Workspace test files under `Tests/` and `UITests/`.
