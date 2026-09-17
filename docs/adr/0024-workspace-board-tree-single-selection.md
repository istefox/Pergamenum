# ADR-0024 — One selection, one row, one meaning

**To be moved by the operator to `docs/adr/0024-workspace-board-tree-single-selection.md`.**
This project's ADRs all live under `docs/adr/NNNN-slug.md`; the architect agent's write scope
forbids that directory, so the file is written here and moved by hand, exactly as ADR-0022 and
ADR-0023 were. Every reference to it elsewhere is by **name** (`ADR-0024`), never by path, so the
move breaks nothing.

## Status

Proposed — 2026-08-25. To be accepted at Gate 2 of the `workspace-board-tree-single-selection`
chain.

**Supersedes ADR-0022 §D9** in full. §D9 introduced `@State private var selectedFolder: String?` in
`WorkspaceBrowser` as the toolbar's target, deliberately *separate* from the open board, with the
fallback `selectedFolder ?? openFolder` so the toolbar would never be inert. That decision is
withdrawn: the two variables are replaced by one, the fallback is deleted along with the divergence
it existed to paper over, and the sentence «a board row's click selects its parent folder and opens
it» becomes «a row *is* a folder, and clicking it is the only selection there is».

**Extends ADR-0023 §D2 and §D4**, and reaffirms both. §D2's conclusion — the folder row's context
menu attaches to the row, never to a container that reaches disclosed descendants — survives
verbatim; §D1 below removes the container that made it dangerous, so the conclusion now holds by
construction rather than by care. §D4's rule — the context menu sets the selection before it raises
a sheet — survives, plumbed through the new single setter.

**Base read:** every file:line quoted below was read at `5041d5c`.
**Plan:** `docs/superpowers/plans/2026-08-25-workspace-board-tree-single-selection.md`.

**Scope note (2026-09-16, ADR-0047):** the Obsidian round-trip is no longer a binding
constraint. The decision below stands as taken and the format it chose is unchanged; what no
longer applies is the obligation that a future change keep Obsidian able to read the result.
Body untouched.

---

## Context

The Workspace sidebar lights up to three rows at once and none of them means anything a person can
name. A screenshot and a user report started this; reading the code says why, and the why is
structural rather than cosmetic.

**F1 — There are two selection variables and opening a board writes both.**
`WorkspaceBrowser.selectedFolder` (`WorkspaceBrowser.swift:42`) is the toolbar's target, ADR-0022
§D9. `openBoardPath` (`WorkspaceBrowser.swift:19`, computed in `WorkspaceView.swift:166-169` from
`hasOpenBoard` + `folder`) is the board on screen. `boardRow`'s click sets both
(`WorkspaceBrowser.swift:425-426`): the parent folder becomes the toolbar's target *and* the board
opens. Two rows now claim to be selected, for two different reasons, in the same colour.

**F2 — And there is a third row lit that is not a selection at all.**
The folder icon is `.accentPrimary` **unconditionally** (`WorkspaceBrowser.swift:366-367`), on every
folder row, always. It has never been a selection signal; it reads as one because the two real
signals use the same token (`:369`, `:430`, `:432`).

**F3 — The reference model is in this repository and it is a *row structure* as much as a binding.**
`NoteListPane.folderTree` is `List(selection: selectedPath)` (`NoteListPane.swift:156`) over a
binding derived from the controller (`:221-232`): the getter reads `vault.openNote?.relativePath`,
the setter calls `vault.openNote(at:)`. But the rows it selects among are **not** a
`DisclosureGroup` tree. `NoteTreeRow` is a `@ViewBuilder` that emits the row and, as a *sibling*,
its expanded children (`NoteListPane.swift:290-322`), drawing its own chevron with
`.rotationEffect(.degrees(isOpen ? 90 : 0))` and paying for depth in
`.padding(.leading, CGFloat(depth) * Self.indent)`. Only the note rows carry `.tag` (`:345`); the
folder rows carry none, which is what makes them structurally unselectable rather than merely
un-highlighted. The Workspace tree is the other shape: `DisclosureGroup(isExpanded:)`
(`WorkspaceBrowser.swift:352`), whose label is not a row of the enclosing `List`.

**F4 — This repository has already been bitten by a silently dropped `.tag`.**
`RootView.swift:205-208`, in its own words: *"`.badge` before `.tag`, and the order is the whole
thing: applied after it, `.badge` drops the tag, the `List` falls back to the `ForEach`'s implicit
id — a `String` — and no row can ever equal a `SidebarItem` selection. The sidebar then lights
nothing and swallows every click, which is how it shipped for the twenty minutes the starred count
sat on the wrong side of the tag."* The same file also records that the data-driven `List`
initialiser binds selection to `Identifiable.id` and *"silently ignored the initial value"*
(`:182-184`), which is why it uses an explicit `ForEach` plus `.tag`. Both failures are silent.

**F5 — A row that is a `Button` cannot be selected by the `List` around it.**
`boardRow` is a `Button` with `.buttonStyle(.plain)` (`WorkspaceBrowser.swift:421-438`); the button
consumes the click before the list's selection machinery sees it. Every row that must participate in
`List(selection:)` has to stop being a `Button` — which also changes what XCUITest finds it as
(`app.buttons[…]` no longer resolves; see F11).

**F6 — A board is opened by *folder*, never by file.**
`WorkspaceController.open(folder:)` (`WorkspaceController.swift:167-191`) takes a folder and loads
`CanvasStore.boardPath(forFolder:)` (`CanvasStore.swift:21-28`), which is `<folder>/<last
component>.canvas`, or `<vault name>.canvas` for the root. Nothing in the app can open a `.canvas`
by name. **Consequence, live today:** the tree lists every `.canvas` in the vault
(`CanvasStore.allBoards()`, `:113-136`), so a folder `X` holding an Obsidian canvas `Y.canvas` shows
a row for `Y` whose click runs `open(folder: "X")` and shows `X/X.canvas` — a row that opens
something other than what it names. Binding principle 4 (the Labs vault opens without conversion)
guarantees such files exist.

**F7 — `NoteTree` has no root node, and its leaves are boards.**
`NoteTree.build(fromPaths:)` (`NoteTree.swift`) builds folder nodes from real path components,
`nodes(prefix: "")` downwards. There is no node for the vault root: the root board is a top-level
`.note` leaf named after the vault. A folder's own board is the child leaf whose id equals
`boardPath(forFolder: <that folder>)`. `noteCount` on a folder counts the boards at or below it,
including the folder's own.

**F8 — `hasOpenBoard` and `closeBoard()` are eight days old and were shipped as a stopgap.**
`5041d5c` — *"feat(workspace): no board open until chosen … A follow-up redesign of the tree's
row-highlight model is planned next."* The flag is stored (`WorkspaceController.swift:80`), written
in four places (`:148, :176, :201`, and `markOpen:` at `:167`), and `closeBoard()` (`:197-203`) is
reachable from exactly one call site: the browser's hand-rolled blank-space `onTapGesture`
(`WorkspaceView.swift:69`).

**F9 — There is no open-board persistence anywhere in this app.**
`VaultSettings` (`Sources/Vault/VaultSettings.swift`) has `boardShowsGrid` and `boardSnapsToGrid`
and no board path of any kind. `attach` calls `open(folder: "", markOpen: false)`
(`WorkspaceController.swift:133`) — loaded, not chosen. `5041d5c` shipped the **opposite** of
persistence, and its own UI test says so by name:
`testLeavingAndReturningToTheWorkspacePaneForgetsTheOpenBoard`. The SPEC's Decision 7 and R-10 are
therefore describing a feature this repository does not have; see *Consequences (neutral)*.

**F10 — `open(folder:)` is called from five places that are not the tree**, and every one of them
means «show me that folder's board»: the breadcrumb (`BoardChrome.swift:28`), a folder card's double
click (`BoardCardMenu.swift:118`), a `pergamenum://canvas` route
(`WorkspaceController+Viewport.swift:81`), a note handed over from the editor
(`WorkspaceView.swift:131`), and the three folder verbs (`WorkspaceView.swift:219, 248, 264`). None
of them wants a «selected but not opened» state.

**F11 — Call sites, already grepped at `5041d5c`.** `WorkspaceBrowser(` has exactly one
(`WorkspaceView.swift:63`). `hasOpenBoard` has five outside the controller, all in
`WorkspaceView.swift` (`:77, :131, :167, :235, :258`), plus three assertions in
`Tests/WorkspaceOpenStateTests.swift`. `workspace-folder-<path>` is asserted by **nothing**.
`workspace-board-<path>` is asserted twice: `UITests/WorkspaceIntegrationUITests.swift:155` through
`descendants(matching: .any)`, which survives an element-type change, and
`UITests/WorkspaceOpenStateUITests.swift:39` through `app.buttons[…]`, which does not.

**F12 — Target membership needs no edit.** The app target is `Sources/**` minus `Sources/CLI/**`
and `Sources/MCPServer/**` (`Project.swift:139-141`), so every new file under
`Sources/Features/Workspace/` enters it automatically. Nothing here goes into `sharedSources`: the
Workspace sidebar is not a connector capability, and ADR-0022 §D6 keeps that boundary deliberate.

---

## Decision

### D1 — The tree stops being a `DisclosureGroup` and becomes the reference model's flat recursive rows

`WorkspaceTreeRow`'s `DisclosureGroup` (`WorkspaceBrowser.swift:352-417`) is replaced by
`NoteTreeRow`'s shape (F3): a `@ViewBuilder` emitting the row, then — as a sibling, not as content —
`if isExpanded { ForEach(children) { … } }`, with the chevron drawn by hand and depth paid for in
`.padding(.leading, CGFloat(depth) * indent)`.

This is not a stylistic alignment. **The label of a `DisclosureGroup` is not a row of the enclosing
`List`**, and `List(selection:)` selects rows. Copying the reference model's binding (F3) without
copying its row structure would produce a binding nothing can satisfy, and F4 is this repository's
own evidence that such a failure is silent: the list lights nothing and swallows every click.

Three things fall out of it, and the third is why this decision is worth its diff:

- Depth becomes a number instead of a nesting, so every row of the tree is a sibling in one `List`.
- The chevron becomes a hit target of its own, which is what keeps «the triangle expands, the row
  selects» (§D5) implementable at all.
- **The accessibility-propagation trap of ADR-0022 §F9 and ADR-0023 §D2 disappears with the
  container that caused it.** A modifier on a flat row reaches that row. There is no longer a
  `DisclosureGroup` under which a `.contextMenu` could hang the parent folder's «Elimina» off every
  board nested inside it. ADR-0023 §D2's conclusion is unchanged and is now structural.

### D2 — A row is a folder; the board that folder owns is drawn *on* it, never beside it

SPEC §6.2 makes a board a folder. The tree drew them as two rows, so the tree contradicted the app's
own specification before it confused anybody. One row per folder (SPEC Decision 1), and that row
carries the board when the folder has one.

The fold is a **pure function in a file of its own**, `Sources/Features/Workspace/WorkspaceTree.swift`,
over `NoteTree.build(fromPaths:)`'s output — not a decision taken inside a view body:

```
WorkspaceTree.build(boards: [String], boardPath: (String) -> String) -> [Node]
```

`Node` is `(id, name, kind, children, boardCount)` with
`kind = .workspace(board: String?) | .foreignBoard(path: String)`. For a `.workspace` node
**`id` is the folder path**, `""` for the vault root.

Two properties are the whole of the design:

- **The folder↔board naming rule is asked, never restated.** `boardPath` is passed in as
  `CanvasStore.boardPath(forFolder:)` itself (F6), so the transform cannot drift from the rule the
  controller loads by. It is also what lets the transform recognise the root board — a top-level
  leaf with no folder node above it (F7) — and emit it as the row for folder `""`.
- **`id` is the `List`'s selection tag and the toolbar's target and the row's identity, one string.**
  There is no mapping step where two spellings of «which row» could disagree, because there is one
  spelling.

`boardCount` is `NoteTree`'s `noteCount` carried through unchanged, and is drawn only on a row that
has children — which is exactly the set of rows that showed a count before this change, so nothing
moves on screen that was not asked to.

### D3 — A `.canvas` that is not named after the folder holding it is drawn, and cannot be selected

It gets a `.foreignBoard` row and **no `.tag`** — structurally excluded from the selection, the same
mechanism `NoteListPane` uses for its folder rows (F3), not a disabled state anybody has to
remember to apply.

This corrects a defect rather than introducing a limit (F6): the row exists today and its click
opens a different board than the one it names. It stays visible because Binding principle 4 makes
those files somebody's real data and hiding them would be this app editing what Obsidian wrote; it
stops being clickable because there is nothing this app can do with it. The folder that holds it is
a row of its own, selectable, and opens the board that folder actually owns.

### D4 — The controller holds **one** optional, and it is both «the lit row» and «is a board drawn»

```swift
enum WorkspaceSelection: Equatable, Sendable {
    case board(folder: String)   // this folder's board is loaded and on screen
    case folder(String)          // selected for the toolbar's verbs; opens nothing
}

// on WorkspaceController
private(set) var current: WorkspaceSelection?
func select(_ new: WorkspaceSelection?)
var isShowingBoard: Bool { if case .board = current { true } else { false } }
```

`hasOpenBoard` and `closeBoard()` are **removed** (SPEC Decision 4, R-11). `isShowingBoard` is
derived, not stored; `select(nil)` is what `closeBoard()` was. `open(folder:)` keeps its name and its
one-argument signature — it always means `.board`, which is what all five non-tree callers mean
(F10) — and loses `markOpen:`, whose only `false` caller was `attach` (F8). `attach` now loads the
root board's document without selecting anything, through the private `load(folder:)` the two paths
share.

`select(_:)` carries the guard `open(folder:)` never had: **`guard new != current else { return }`**.
Without it, ADR-0023 §D4's context menu — which sets the selection before raising a sheet — would
re-`open` the board already on screen and reset its `zoom` and `pan` (`WorkspaceController.swift:
178-179`) because somebody right-clicked it and chose «Rinomina…».

Why the discriminator is stored rather than computed: «does this folder have a board» is a
filesystem question, and answering it in a view body on every layout pass is a `stat` per row per
frame. The tree already knows the answer for free (§D2), so the answer travels with the selection
instead of being re-asked.

### D5 — The triangle expands, the row selects, and clicking a board-less folder opens nothing

ADR-0022 §D9's split survives its own supersession: the chevron toggles `expanded`, the rest of the
row selects. SPEC flow 3 requires the triangle not to change the selection; SPEC Decision 3 and flow
2 require the row of a board-less folder to be selectable without opening anything. R-05's «only
expands or collapses it» cannot be read literally against those two — see *Consequences (neutral)* —
and its operative content is the clause that follows it: no board is opened and no creation prompt
appears.

A board-less folder therefore selects as `.folder(F)`: the row lights, any open board closes, the
toolbar targets `F`, and the board area shows the empty state. **Nothing is created**, which is the
point — `open(folder:)` on a pure grouping folder would draw an inviting empty board, and dropping
one card on it writes `Progetti/Progetti.canvas` and silently turns a grouping folder into a
workspace.

The tree is the only surface that can produce `.folder`. The breadcrumb, the route, the folder card
and the three verbs keep `open(folder:)` and keep meaning `.board` (F10). **That asymmetry is
invisible in the tree**, and this is the property that makes it acceptable rather than a second
model: the selection tag is the folder path in *both* cases, so a board opened from anywhere lights
exactly the row for its folder whether or not a `.canvas` file exists there. What differs is only
whether a board is drawn.

### D6 — The browser is handed the selection as a value and a closure, never the controller

ADR-0022 §D10 stands: the browser decides, `WorkspaceView` performs. Its parameters change shape:

| Before | After |
|---|---|
| `openBoardPath: String?` | `selectedFolder: String?` |
| `onOpen: (String) -> Void` | `onSelect: (WorkspaceSelection?) -> Void` |
| `onDeselect: () -> Void` | — (folded into `onSelect(nil)`) |

Three parameters become two, and `WorkspaceView.openBoardPath` (`:166-169`) — a whole computed
property whose only job was to spell «the open board» a second way — is deleted.

The browser builds the `Binding<String?>` locally because only it holds the tree, and therefore only
it can decide whether a newly selected folder means `.board` or `.folder`. The getter is
`selectedFolder`; the setter looks the folder up in its own tree and calls `onSelect` with the case
it found.

`NoteListPane.swift:213-232` records the trap that comes with a derived selection binding and it is
recorded here so nobody rediscovers it: **the setter runs on a change**, so clicking the row that is
already selected calls nothing. Here that is correct and wanted — re-clicking the open board must
not reload it — which is why this ADR does not need `NoteListPane`'s «read nil while the composer is
up» counter-measure.

### D7 — `targetFolder` reads the selection and nothing else

`WorkspaceBrowser.targetFolder` (`:131-135`) loses its fallback branch:
`selection ?? ""`, with `WorkspaceBrowserToolbar.canMutate(folder:)` unchanged as the one enablement
rule (ADR-0022 §D9's root exemption, ADR-0023 §D1's one-rule-two-surfaces). ADR-0022 §D9's
`selectedFolder ?? openFolder` existed because a board could be open with nothing selected; under
§D4 that state does not exist, so the fallback has nothing to fall back from and R-06's «no fallback
branch that can diverge from what is shown on screen» is satisfied by deletion rather than by care.

The consequence is stated rather than hidden: **with nothing selected, «Rinomina» and «Elimina» are
disabled**, where ADR-0022 §D9 deliberately kept them live by aiming at the open board's folder.
That is the price of R-06 and it is the right side of the trade — a destructive verb aimed at a row
the user cannot see is worse than a destructive verb that asks for a click first.

`rebuild()`'s stale-selection drop (`:261-263`) survives, retargeted: a selection naming a folder the
rebuilt tree no longer has becomes `onSelect(nil)` rather than falling back to the open board.

### D8 — The breadcrumb derives from the selection, its last segment stops being a link, and `.accentPrimary` stops meaning «selected» in this pane

Three changes in `BoardChrome.swift`, closing SPEC Decision 5 / R-12:

1. **`WorkspaceController.breadcrumb` (`:153-161`) derives from `current?.folder`, not from
   `folder`.** `folder` names the *loaded* document, and under §D4 a `.folder(F)` selection loads
   nothing — so the breadcrumb would keep showing the previous board's trail while the tree showed
   `F`. That is the diagnosis's defect 5 arriving through a new door, which the SPEC's edge cases
   forbid by name. With nothing selected the trail is `["Workspace"]`, which is what
   `Tests/CanvasTests.swift:357` already asserts after `attach`.
2. **The current segment is a `Text`, not a `Button`.** It is not somewhere you can go; you are
   there. Today clicking it runs `open(folder:)` on the folder already open and resets the board's
   zoom and pan (`WorkspaceController.swift:178-179`).
3. **Nothing in the breadcrumb uses a colour to mean «this is the open board».** The tree's new
   answer to that question is the system's row fill and no token at all (R-02), and a breadcrumb has
   no row to fill — so it says it the only other way the design system has: emphasis
   (`.textPrimary` current, `.textSecondary` ancestors) plus not being a link. After this change
   `.accentPrimary` has exactly one meaning left in the Workspace pane's chrome: the save indicator's
   «Salvato» (`BoardChrome.swift:21`).

### D9 — VoiceOver is told by label and trait, not by colour

R-02 removes the manual colouring that was the only signal a screen reader could not use anyway, so
the state has to be said out loud: the selected row's accessibility label gains a suffix and the row
gains `.accessibilityAddTraits(.isSelected)`.

The row computes this from `selectedFolder == node.id` — a **one-way read of the same single
selection**, not a second variable. It is written down here because «you reintroduced the state you
just removed» is the first thing a reviewer will think, and the answer is that a derived read cannot
diverge from what it reads.

### D10 — What deliberately does not change

- **The identifiers.** `workspace-board-<boardPath>` stays on every row that owns a board and
  `workspace-folder-<folderPath>` stays on every row that does not, exactly as spelled today. Both
  existing UI call sites keep resolving by identifier (F11); the one that also asserts the element
  *type* is rewritten by R-14 anyway. A `.foreignBoard` row gets a third,
  `workspace-foreign-board-<path>`, so a test can tell «unopenable by design» from «missing».
- **No persistence is added** (F9). See *Consequences (neutral)*.
- **`CanvasStore`, `CanvasDocument` and the `.canvas` format are untouched.** This is a selection and
  rendering redesign; SPEC Scope says so and there is no reason to disagree with it.
- **`IndexCache.schemaVersion` is not touched**, which matters because it is a declared protected
  interface (`.claude/protected-interfaces`). Boards are still not indexed (ADR-0021 §D10).
- **No new dependency, no `Project.swift` edit, no `sharedSources` entry** (F12).

---

## Alternatives considered

**A1 — Keep the `DisclosureGroup` and put the `.tag` on it.**
Rejected. The label of a `DisclosureGroup` is not a row of the enclosing `List`, so the tag has no
row to attach to and the binding is satisfied by nothing; F4 is this repository's own record of how
that failure presents — a list that lights nothing and swallows every click, shipped for twenty
minutes before anyone worked out why. Even if a tag could be made to stick, ADR-0022 §F9 and
ADR-0023 §D2 both document that a modifier on a `DisclosureGroup` reaches every disclosed descendant
on macOS, so the row's own selection affordance would risk reaching the rows nested under it. The
reference model does not use one (F3), and the reference model is the thing that is known to work
here.

**A2 — Keep both variables and make them mutually exclusive by writing both from one function.**
The minimal diff: leave `selectedFolder` and `openBoardPath` in place, funnel every write through a
single `select(…)` helper that always sets both consistently. Rejected: it fixes today's three lit
rows and leaves the shape that produced them. Two variables that must agree are two variables that
will disagree at the next feature — this is the third chain in a row to touch these files
(ADR-0021, ADR-0022, ADR-0023) and the second to add state to them. The SPEC's own framing is that
the defect is the two-variable model, not its current values.

**A3 — Make the selection tag the board path rather than the folder path.**
Rejected on two counts. A board-less folder has no board path, so Decision 3 would need a sentinel
value — the «sentinel hack» the chain brief asked to be checked for and which `List(selection:)`
does not require. And a board opened from the breadcrumb onto a folder with no `.canvas` file yet
would have a tag no row carries, so the tree would light nothing while a board was on screen: the
diagnosis's defect 5 reproduced exactly. The folder path is the one string that names every case
(§D2, §D5).

**A4 — Follow `NoteListPane` literally: folder rows carry no `.tag`, and Rinomina/Elimina target the
nearest board-owning ancestor.**
Rejected: it is unimplementable against SPEC Decision 3 and R-05, which require a board-less folder
to be selectable for exactly those two verbs, and it would make «Elimina» aim at a row other than the
one the user right-clicked — R-06's divergence in a new costume. The reference model is followed
where it is a model (its row structure, its derived binding, its structural exclusion by absent tag)
and departed from where the Workspace has a requirement the Note pane does not have. §D3 is where
the absent-tag mechanism is actually reused, on the rows that genuinely have nothing to select for.

**A5 — Let a board-less folder open its (empty, uncreated) board, since `open(folder:)` writes no
file.**
Tempting, because it makes every row do one thing and deletes the `.folder` case entirely. Rejected:
`open` creates nothing, but it draws an empty board that invites a drop, and the first card dropped
writes `<folder>/<folder>.canvas` and turns a grouping folder into a workspace nobody asked to
create. SPEC Decision 3 is locked against exactly this and the reason is better than the SPEC's own
wording of it.

**A6 — Keep the selection in `WorkspaceBrowser`'s `@State` and give the controller only «open this».**
Rejected: the browser is destroyed and rebuilt every time the pane is left and returned to
(`UITests/WorkspaceIntegrationUITests.swift:146-149` records this about `RootView`), so a selection
living there is lost on every pane switch while the board it named stays open — a fourth way for the
tree and the chrome to disagree. It would also leave the breadcrumb (§D8) with nothing to derive
from.

**A7 — Implement SPEC Decision 7 / R-10 as written: persist the open board and restore it at
launch.**
Rejected: it is not in the SPEC's own Scope list, no such persistence exists to preserve (F9), and
`5041d5c` shipped the opposite eight days ago with a green UI test asserting the open board is
*forgotten* (`testLeavingAndReturningToTheWorkspacePaneForgetsTheOpenBoard`). Building it here would
mean deleting a passing test to satisfy a requirement that describes the behaviour that test was
written to prevent. R-10 is satisfied against what it can actually be satisfied against: no
regression from `5041d5c`, and a board opened from outside the tree lighting its own row.

**A8 — Drop foreign `.canvas` rows from the tree entirely.**
Rejected: they are files in the user's vault and the Workspace browser is the only place in this app
that lists boards. Hiding somebody's Obsidian canvas because this app's folder↔board rule cannot name
it is the app editing the vault's meaning, against binding principle 1 and principle 4. Drawn and
unselectable says the true thing (§D3).

**A9 — Keep the hand-rolled blank-space `onTapGesture` alongside `List(selection:)`.**
Rejected as the *default*, kept as the named fallback. R-07 requires the hand-rolled gesture to be
gone, and a tap gesture on a `List` that also has a selection binding is a second deselection path
that can fire on a row hit the list already handled. But whether an `NSTableView`-backed SwiftUI
`List` clears an optional selection on a background click is **not verified in this repository** —
`NoteListPane` never deselects, and the gesture being removed was written when the list had no
selection binding at all. So: implement without it, verify by hand before merge, and if the native
behaviour does not fire, restore the gesture as a single `onTapGesture { onSelect(nil) }` with a
comment recording the finding. That is a fallback with a trigger, not a hedge.

**A10 — Rename `WorkspaceController.selection` (the card selection) so the new value could take the
name.**
Rejected as scope: `selection: Set<String>` is read by `BoardContentLayer`, `BoardCardControls`, the
gesture files, `openRoute` and several test files, and renaming it would put a dozen green files at
risk to improve one word. The new value is `current` instead, which is a different word rather than
a near-miss of an existing one.

---

## Consequences

### Positive

- **Three lit rows become one, by construction.** There is one selection variable, one tag spelling,
  and one rule that decides what a row means. The defect cannot recur by two values drifting,
  because there is one value.
- **The tree stops contradicting SPEC §6.2.** A board is a folder in the specification and is now a
  folder in the sidebar. The «two rows for one thing» was a defect against the app's own spec before
  it was a colour problem.
- **A latent defect is closed on the way past** (§D3, F6): a `.canvas` not named after its folder
  currently opens a *different* board when clicked, silently. After this it is drawn and inert, and
  the folder that holds it is the row that opens the board it really owns.
- **Two more latent defects go with it**: clicking the current breadcrumb segment no longer resets
  the board's zoom and pan (§D8.2), and a `pergamenum://canvas` route arriving while a board-less
  folder is selected now opens the board instead of doing nothing
  (`WorkspaceController+Viewport.swift:81`'s guard becomes a comparison against `current`).
- **Keyboard navigation and blank-space deselection arrive for free** (R-07, R-08) rather than as two
  more hand-rolled gestures — subject to A9's verification.
- **The ADR-0022 §F9 / ADR-0023 §D2 propagation trap stops needing to be remembered.** It was
  documented three times across two ADRs and a fifteen-line code comment; §D1 removes the container
  it is about.
- **`WorkspaceView` loses a computed property, `WorkspaceBrowser` loses a parameter and a `@State`,
  and `WorkspaceController` loses a stored flag and a method.** This chain removes more state than
  it adds.

### Negative

- **«Rinomina» and «Elimina» are now disabled until a row is clicked** (§D7), where ADR-0022 §D9
  deliberately kept them live. A user's first encounter with the toolbar is two dimmed buttons —
  precisely the objection ADR-0022 A7 raised against this and accepted the other way. It is
  reversed here because R-06 asks for the opposite and because a destructive verb pointed at an
  invisible target is the worse of the two failures.
- **The Workspace tree and the Note tree now share a row structure but not a row type.** Two
  near-identical recursive `@ViewBuilder` rows sit in two files, and the next person to fix an indent
  bug will fix it once. Extracting a shared row was considered and rejected as scope: the two rows
  differ in their icons, their counts, their identifiers, their context menus and which of them may
  carry a tag, which is most of what a row is.
- **`WorkspaceSelection` is a fourth Workspace-shaped noun** beside `WorkspaceController.selection`
  (cards), `WorkspaceFolderActions` and `WorkspaceBoardResolver`. `current` is short and its meaning
  lives in a doc comment rather than in its name.
- **The `.folder` case exists for one surface.** Only the tree can produce it (§D5); every other
  caller means `.board`. That asymmetry is defensible and invisible in the tree, and it is still an
  enum case a reader has to be told the reason for.
- **Two SwiftUI behaviours this change rests on are unverified in this repository**: native
  blank-space deselection (A9) and whether an `.accessibilityAddTraits(.isSelected)` on custom row
  content reaches XCUITest. Both are manual-QA items before merge, not unit-testable, and R-07 and
  R-13 depend on them.
- **Every row in the tree changes its element type** from `Button` to a list row (F5). One existing
  UI assertion breaks by type rather than by identifier, in the file R-14 rewrites anyway — but the
  class of breakage is real and any future test written against `app.buttons` in this pane will fail
  the same way.

### Neutral

- **The SPEC's Decision 7 and R-10 describe a feature this app does not have** (F9). No board
  persistence exists, and `5041d5c` — the commit R-10 cites as the thing not to regress — shipped
  the opposite, with a green UI test asserting the open board is forgotten. R-10 is implemented as
  «no regression from `5041d5c`» plus the edge case it actually shares a purpose with: a board
  opened from outside the tree lights its own row.
- **R-05 cannot be read literally against Decision 3 and flow 2.** «Clicking a board-less folder's
  name/row only expands or collapses it» and «Its row can still be selected … The clicked folder's
  row lights up» are not both true. Resolved as §D5: the triangle expands, the row selects, no board
  is opened, no prompt appears — which is ADR-0022 §D9's existing split, kept.
- **The SPEC's Architecture section cites `WorkspaceBrowser.swift:191` for the hand-rolled `List`; it
  is `:195` at `5041d5c`.** Every other line reference in the SPEC checks out.
- **`open(folder:)` keeps its name, its meaning and its five non-tree call sites** (F10). Only
  `markOpen:` goes, and only `attach` passed it.
- **`WriteJournal` is not involved.** Nothing here writes to disk at all: a selection is view state
  over a controller, and the only disk access added is the document load `open(folder:)` already did.
- **`Tests/CanvasTests.swift`'s breadcrumb assertions (`:357-361`) pass unchanged** under §D8.1,
  because `current` is nil after `attach` and `.board(F)` after `open(folder: F)`, which is what
  `folder` said in both cases.
- **`.claude/test-cmd` is unchanged.** This feature adds unit tests to the existing bundle and UI
  tests to the suite that is run by hand before a merge, which is the split `CLAUDE.md` already
  requires.

---

## References

- SPEC of this chain: `/Users/stefer/Developer/Pergamenum/SPEC.md` (R-01 … R-16).
- App specification: `docs/20260811_Pergamenum_SpecApp.md` §6.1 (board ↔ folder mapping, breadcrumb),
  §6.2 (a board *is* a folder — the sentence §D2 makes true in the tree).
- **ADR-0022**, `docs/adr/0022-workspace-ui-creazione-board-toolbar-e-r.md` — §D9 **superseded in
  full** by §D4/§D5/§D7 here; §D8 (the toolbar is a sibling row of the header) unchanged; §D10 (the
  browser decides, `WorkspaceView` performs) unchanged and reaffirmed by §D6; §F9 (identifier
  propagation on a macOS container) — the trap §D1 removes the container for.
- **ADR-0023**, `docs/adr/0023-universal-command-surface-parity.md` — §D1 (one rule, two surfaces:
  `canMutate(folder:)` stays the single enablement rule, §D7 here); §D2 (the folder row's context
  menu attaches to the row) reaffirmed and made structural by §D1; §D4 (the context menu sets the
  selection before raising a sheet) preserved, plumbed through `select(_:)`, which is why that setter
  needs its no-op guard (§D4).
- **ADR-0021**, `docs/adr/0021-workspace-tasks-notes-integration.md` — §D10: `.canvas` files are not
  in the index, so the tree is built from `CanvasStore.allBoards()` and `NoteTree.Node.Kind` is not
  extended for boards. §D2 here folds that tree rather than replacing it.
- **ADR-0020** §D5 — the crop is modal state that must be ended on the way out of a board; `select(_:)`
  inherits that obligation from `open(folder:)` on both of its paths.
- **ADR-0017** — derived state lives outside the vault; nothing here is persisted, which is why F9's
  absence of a saved board is a fact about the app rather than a bug in this pane.
- **ADR-0012** §D10 — machine-local view state belongs in `@AppStorage`, not `VaultSettings`; the
  selection is neither, it is per-session controller state.
- **ADR-0001** §D1 — `Sources/Core/**` must not import SwiftUI. The two new files live under
  `Sources/Features/Workspace/` and are Foundation-only, which is a choice about testability rather
  than a requirement of that rule.
- `CLAUDE.md` — binding principle 1 (file over app: §D3, §D5), principle 4 (Obsidian compatibility:
  §D3); the design-token rule (§D8); «a UI test must not find a control by the words on it» (§D10's
  identifier preservation).
- Code read at `5041d5c`: `Sources/Features/Workspace/WorkspaceBrowser.swift`,
  `WorkspaceController.swift`, `WorkspaceController+Viewport.swift`, `WorkspaceView.swift`,
  `WorkspaceBrowserToolbar.swift`, `WorkspaceFolderActions.swift`, `BoardChrome.swift`,
  `BoardCardMenu.swift`, `Sources/Features/Editor/NoteListPane.swift`, `Sources/App/RootView.swift`,
  `Sources/Vault/CanvasStore.swift`, `Sources/Vault/VaultSettings.swift`,
  `Sources/Core/Conventions/NoteTree.swift`, `Tests/WorkspaceOpenStateTests.swift`,
  `Tests/CanvasTests.swift`, `UITests/WorkspaceOpenStateUITests.swift`,
  `UITests/WorkspaceIntegrationUITests.swift`, `Project.swift`.
