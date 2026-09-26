# ADR-0023 — A command is named once and rendered twice

**To be moved by the operator to `docs/adr/0023-universal-command-surface-parity.md`.**
This project's ADRs all live under `docs/adr/NNNN-slug.md`; the architect agent's write
scope forbids that directory, so the file is written here and moved by hand, exactly as
ADR-0022 was. Every reference to it elsewhere is by **name** (`ADR-0023`), never by path,
so the move breaks nothing.

## Status

Accepted — dated 2026-08-25; landed on `main` via PR #105 (merge `71e45ad`,
2026-08-25). Supersedes **ADR-0022 §D8** on one point only: the entry point for
the Workspace folder verbs. §D8's accessibility reasoning is untouched and is reaffirmed
below (§D2).

**Scope note (2026-09-16, ADR-0047):** the Obsidian round-trip is no longer a binding
constraint. The decision below stands as taken and the format it chose is unchanged; what no
longer applies is the obligation that a future change keep Obsidian able to read the result.
Body untouched.

## Context

A read-only survey of every command surface in Pergamenum found six clusters where a
command exists on one surface and not on the other it should reasonably appear on, plus
one command with no discoverable UI at all beyond its keyboard shortcut. `SPEC.md`
(PG-042) scopes those six clusters plus one net-new command, `Duplica card`.

The underlying condition is not "some menus are short". It is that **each command's title,
icon and applicability rule is written wherever the command happens to be rendered**. Where
a command is rendered twice, those three facts are written twice, and they drift: the
Calendario menu says «Nuovo evento» while a day cell says nothing; `BoardContentLayer`'s
context menu knows that «Ritaglia» only belongs on a raster image above the placeholder
zoom, and the board's toolbar does not know it at all because the board's toolbar has no
card commands. Adding a second rendering site per cluster without fixing that would double
the drift rather than close it.

Three properties of the codebase shape every decision below, and all three were read at
`b477209` rather than assumed:

- **`CommandActions` already is the app-level catalogue** for commands whose subject is
  "the window" (`Sources/App/CommandActions.swift`). Its own header states the rule this
  ADR extends: the menu bar and the slash menu both call it, *"and neither owns the
  behaviour"*. What it cannot express is a command whose subject is a **row**: a folder
  path, a note path, a task, a canvas node, a date.
- **`ShortcutCommand` is the remappable-keyboard catalogue, not the command catalogue.**
  Its raw values are the keys of the shortcut-overrides file
  (`ShortcutCommand.swift:9-11`), so a case added for a command that has no key costs a
  persisted identifier for nothing. «Cattura rapida» and «Dividi l'editor» are the existing
  precedents for a command deliberately outside it.
- **An identifier on a SwiftUI container reaches its descendants on macOS.** This is
  documented twice in this repository, at `WorkspaceBrowser.swift:195-203` (the browser
  header) and at `WorkspaceBrowser.swift:359-367` (the folder row's `DisclosureGroup`), and
  it is the whole reason ADR-0022 §D8 put the Workspace toolbar in a **sibling** row.

The SPEC asserts two things about the code that are false. Both are corrected in the plan's
own table and neither changes what the feature does; they change what the code may cite as
its reason. They are listed in *Consequences (neutral)* below.

## Decision

### D1 — Per cluster, one catalogue: the title, the SF Symbol and the applicability rule are written once and read by both surfaces

For every cluster this feature touches, the three facts that make a command *the same
command* on two surfaces live in exactly one declaration, and both surfaces read it:

| Cluster | The single naming site |
|---|---|
| 4, 7 — canvas card | `CardCommand` (new): `title`, `symbol`, `available(for:isCroppable:hasCrop:)` |
| 6 — calendar day cell | `CalendarDayCommand` (new): titles taken from `ShortcutCommand.newEvent.title` / `.newReminder.title` |
| 1 — Workspace folder row | `WorkspaceBrowserToolbar.canMutate(folder:)` (existing, unchanged) |
| 2 — note row | `CommandActions.run(_:on:)` / `canRun(_:on:)` (new, over the existing `run`/`canRun`) |
| 3 — task row | `VaultSession.TaskDraft.subtask(of:)` (new, extracted from `CommandActions`) |

**This is what makes R-13 a property of the code rather than a convention someone has to
keep.** A symbol asserted in a review is a symbol that diverges at the next edit; a symbol
that exists in one `switch` cannot diverge at all. Where the existing surface uses **no**
symbol — the menu bar draws plain `Button` titles, `NoteRowMenu` draws plain titles — the
new entry uses none either. R-13 is "the same symbol", including the same absence of one.

### D2 — Cluster 1: the folder row's context menu attaches to the row's **label**, never to its `DisclosureGroup`

ADR-0022 §D8 chose toolbar-only Rinomina/Elimina and gave a reason: the browser's header
carries `.accessibilityElement(children: .contain)` plus its own identifier, and on macOS
that identifier reaches the buttons placed inside it, so a UI test asking for
`workspace-rename` would be handed `workspace-browser-header`. The toolbar was therefore
built as a **sibling row** of the header, never a child of it. That decision stands
verbatim; the toolbar does not move.

**The trap does not reach a context menu, and it is worth being exact about why.** A
SwiftUI `.contextMenu`'s items are presented as `NSMenuItem`s in a menu window of their own.
They are not accessibility descendants of the view the modifier is attached to, and XCUITest
reaches them as `app.menuItems["Rinomina…"]` — by title, through a separate element tree —
which is how `TimeBlockUITests.swift:62-64` already drives a context menu in this suite. No
identifier can propagate onto an element that is not in the hierarchy the identifier is in.
So cluster 1's new entries cannot inherit `workspace-browser-header` or
`workspace-folder-<path>`, and the reason §D8 refused this surface does not apply to it.

**A neighbouring trap does apply, and it is the one to design against.**
`WorkspaceBrowser.swift:359-367` records that a modifier on the `DisclosureGroup` itself
reaches *every disclosed descendant*, including the child rows below it. A `.contextMenu`
placed there would therefore hang the parent folder's Rinomina/Elimina off every board row
and every nested folder row inside it — right-clicking `01 Progetti/a/a.canvas` would offer
to delete `01 Progetti`. The menu goes on the label's own `HStack`: the view that already
carries `.contentShape(Rectangle())`, `.onTapGesture`, the combined accessibility element
and the row's own identifier. Same view, same row, same scope.

### D3 — Cluster 1: R-02 holds by construction, and the toolbar's own rule is still asked

`NoteTree.build(fromPaths:)` (`NoteTree.swift:56-66`) creates a folder node only for a real
path component, from `nodes(prefix: "")` downwards. **There is no vault-root row in the
Workspace tree**: the root board is a top-level leaf (`Labs.canvas`), not a folder, and no
folder node can have an empty id. The SPEC's edge case ("the vault root row does not gain
Rinomina/Elimina") describes a row that does not exist.

The menu is still gated on `WorkspaceBrowserToolbar.canMutate(folder:)` rather than on
nothing. One rule, two surfaces, per §D1 — and if a future tree ever does synthesise a root
row, the guard is already in front of it instead of being remembered.

### D4 — Cluster 1: the context menu selects the row, then triggers the toolbar's own closures

`RenameWorkspaceSheet` is seeded from `WorkspaceBrowser.targetFolder`
(`WorkspaceBrowser.swift:74-84`), which reads `selectedFolder`. A context-menu action that
opened that sheet without setting the selection would rename whatever was selected *before*
the right-click. SwiftUI does not fire `onTapGesture` on a secondary click, so the row sets
`selected = node.id` itself and then calls the same two closures the toolbar buttons call.
No second code path, and the sidebar visibly agrees with what the sheet is about.

### D5 — Cluster 2: "open, then run" is one function on `CommandActions`

`CommandActions.run(_ command: ShortcutCommand, on notePath: String)` opens the note and
then runs the command; `canRun(_:on:)` answers whether to grey the entry. `NoteRowMenu`
gains three entries that call it and no logic of its own.

Two facts make this safe rather than a race, and both were read rather than assumed:

- `VaultController.openNote(at:)` is **synchronous** (`VaultController+Tabs.swift:280-293`):
  `readForEditing` then `show`. The open and the action therefore land in the same turn,
  which is the whole of R-04.
- It **short-circuits** when the note is already open, focusing the existing tab rather than
  re-reading the file — the comment there says why (a tab may hold unsaved edits). So the
  SPEC's "no implicit re-open on the already-open note" edge case is the existing behaviour
  of the function, not a condition the menu has to test.

The three sheets these commands raise (`isShowingHistory`, `isChoosingTemplate`) are
attached in `VaultBrowser` and `VaultBrowser+History`, the Note pane's own container, and
`NoteListPane` is inside it (`VaultBrowser.swift:17,44-47`). No pane switch is needed.

### D6 — Cluster 3: the sub-task draft becomes a value

`CommandActions.addSubtaskToSelectedTask()` builds a `TaskDraft` with
`destination = .note(parent.sourcePath)` and `parent = parent`. That construction moves to
`TaskDraft.subtask(of:)`, a static factory on the existing struct
(`VaultSession+Tasks.swift:41-66`), and both entry points assign its result: the menu bar
through `CommandActions`, the task row directly. The row also sets `selectedTaskID` and
`vault.selectedTask`, so the Task menu's four rescheduling keys act on the row that was just
right-clicked instead of on whatever was clicked before it.

A pure factory rather than a method on the controller because it is the one shape a unit
test can assert without a vault: R-05's real content is *"the same draft, from two places"*,
and a value is the only way to say that as an equality.

### D7 — Cluster 4: the card commands are a floating contextual bar over the board, not window-toolbar items

`BoardCardControls`, a capsule in the same trailing `VStack` as `BoardPenControls` and
`BoardZoomControls` (`WorkspaceView.swift:334-345`). **This is not a new pattern**:
`BoardPenControls` already appears and disappears with `workspace.tool == .drawing`, in that
exact slot, with `.themedShadow(.card)` and the same capsule face. A contextual cluster that
comes and goes with what is selected is the same object as a contextual cluster that comes
and goes with which tool is held.

The window toolbar was the SPEC's literal reading and is rejected in *Alternatives*.

### D8 — Cluster 4: the bar exists only for a selection of exactly one card, and reads the same catalogue the context menu reads

`BoardCardControls.isShown(selection:)` is true for `selection.count == 1`. R-07's
"hidden, not disabled" is then not a rule anybody has to apply — there is no bar to disable.

The bar's buttons and `BoardContentLayer`'s context-menu entries are both built by iterating
`CardCommand.available(for:isCroppable:hasCrop:)`. Multi-selection keeps the context menu,
whose `targets(_:)` rule (`BoardContentLayer.swift:225-227`) already decides correctly
between "the whole selection" and "just this card" — a rule the bar would have to
reimplement and could only get wrong.

### D9 — Cluster 5: the embed context menu is an `NSMenu` from `menu(for:)`, and its delete **is** the Backspace path

The editor is an `NSTextView`. A SwiftUI `.contextMenu` cannot reach a drawn embed: the
text view consumes the mouse before SwiftUI sees it (the same reason `onTakeFocus` exists,
`CompletingTextView.swift:60-71`), and there is no SwiftUI view over the picture to attach
one to. So `CompletingTextView` overrides `menu(for event: NSEvent) -> NSMenu?` and forwards
through `onEmbedMenu: ((CGPoint) -> NSMenu?)?` — **the fourth closure of a shape this file
already has three of** (`onClickInMargin`, `claimsCommand`, `onEmbedResize`), wired in
`NoteTextView.wire(_:to:)` beside them. Not on a drawn embed, the override returns
`super.menu(for:)` and the standard editor menu is untouched.

The delete does not reimplement anything. It places a zero-length selection at the run's end
and asks `EmbedNavigation.deletionRange(selection:direction:.backward,drawnRuns:textLength:)`
— literally the function Backspace asks (`NoteTextView+EmbedCaret.swift:59-64`) — then writes
through `replaceAtomically(_:with:in:)`, whose own header calls itself *"the only mechanism
either of this feature's two writes may use"*. R-08's "the same atomic delete" is therefore a
fact about there being one edit path, not a claim about two that agree.

### D10 — Cluster 6: one shared catalogue for the two entries, disabled rather than hidden without EventKit access

`MonthView.menu(for:)` and `WeekView.menu(for:)` are today **byte-identical** three-entry
blocks (`MonthView.swift:124-135`, `WeekView.swift:135-146`); `MiniCalendar`'s is a
two-entry variant. R-09 requires the new pair to be identical across all three, so the pair
is one shared view over one pure catalogue, `CalendarDayCommand.entries(eventAccess:reminderAccess:)`,
whose titles are read from `ShortcutCommand.newEvent.title` and `.newReminder.title` — the
menu bar's own strings, so the two surfaces cannot be reworded apart.

**Disabled, not hidden, when access has not been granted.** The Calendario menu greys both
(`MenuCommands.swift:123-129`), and `CommandActions` states the reason for greying rather
than hiding in its note on «Applica un template…»: *"the command is how somebody finds out
the folder is a thing"*. A day cell that silently omits «Nuovo evento» teaches nobody that
Pergamenum can make one.

`MiniCalendar` gains two closures (`onNewEvent`, `onNewReminder`) rather than a
`DayController`. It takes `onSelect`/`onOpenDailyNote` today and holds no controller on
purpose; handing it one to satisfy a menu entry would spend that decoupling on a menu entry.
One call site, `DayMonthSection.swift:31`.

### D11 — Duplica: a new node, a new id, a grid-step offset, and not one byte written outside the `.canvas`

`WorkspaceController.duplicate(nodeIDs:)` appends, for each target, a node that copies the
original's `kind`, `width`, `height`, `color` and `unknown` verbatim and differs in exactly
two things:

- **`id`** — `CanvasID.generate(avoiding:)`: the ordinary 16-hex-character generator, retried
  against every id already in the document (**nodes and edges both**, since a strict reader
  is entitled to treat them as one namespace) and against the ids minted earlier in the same
  call, with a bounded retry and then a deterministic suffix walk that cannot fail to
  terminate. `CanvasID.generate()` itself is unchanged and keeps the shape its own comment
  defends: Obsidian writes 16 hex characters, and a Pergamenum canvas stays
  indistinguishable from one Obsidian produced.
- **`x`/`y`** — offset by `WorkspaceController.gridStep` (24) on both axes: the grid the
  board draws *and* the grid it snaps to are the same constant by an existing decision
  (`WorkspaceController.swift:262-268`), so a duplicate lands one cell down-right, aligned
  whether or not snapping is on.

Everything else follows from copying `unknown` wholesale: ADR-0020's `pergamenum-crop`
travels with the copy for free, so a cropped card duplicates as a cropped card, and R-11's
missing-file case needs no special path at all — the node is a pointer, the pointer is
copied, and the existing broken-file placeholder renders the duplicate exactly as it renders
the original.

Three exclusions, stated so they are not rediscovered as bugs:

- **Edges are not duplicated.** An edge joins two nodes; duplicating one endpoint says
  nothing about whether the connection was meant to be doubled.
- **A group duplicates as a group node only**, never the cards it spatially contains. A
  group is hollow (`BoardContentLayer.swift:178-187`); containment is geometry, not
  ownership.
- **`creatingOnDisk: nil`.** The one write is `mutate { nodes.append… }`, so this is one
  undo step and `BoardHistory`'s created-file block (`WorkspaceController.swift:231-233`)
  never fires — which it would, wrongly, if a duplicate claimed to have created a file.

This is CLAUDE.md principle 1 (*file over app*) applied to the canvas: the board is a view
over files, a card is a pointer into it, and duplicating a view of something must not
duplicate the something.

### D12 — No new `ShortcutCommand` case and no new key binding

`Duplica` is the only net-new command and it gets no keyboard shortcut. Adding one would
cost a persisted override key (§Context) and would need the full collision check ADR-0002
demands against the system's `com.apple.symbolichotkeys` and the app's own map — for a
command whose entire purpose in this feature is to be *visible*. It is reachable from the
card bar and the card context menu, which is what R-06 and R-10 ask for. Nothing else in
this feature adds a case either: every other new entry renders a command the catalogue
already holds.

## Alternatives considered

**A1 — One generic command-surface abstraction that renders any command into any surface.**
The tempting shape: a `CommandSurface` protocol, a `Command` value with a subject, and one
renderer per surface. Rejected because the six clusters have **five different subjects** (a
folder path, a note path, a `TaskItem`, a `CanvasNode`, a `CalendarDate`) and **three
different menu technologies** (SwiftUI `.contextMenu`, a SwiftUI view hierarchy, an AppKit
`NSMenu` returned from `menu(for:)`). An abstraction generic over all of those is larger
than the five small catalogues it would replace, and it would have to be built before a
single gap closed. `CommandActions` is the precedent for how far this codebase takes the
idea and where it stops: one catalogue for commands whose subject is the window, and nothing
above it.

**A2 — Put the card commands in the window toolbar (`ToolbarItemGroup`), the SPEC's literal
reading.** Rejected on three counts. (i) The Workspace already contributes four items there
(`WorkspaceView.swift:243-276`) and the window shows a 200-point sidebar and a 200-point
tray beside the board; five more items that appear and vanish on selection re-lay-out the
whole toolbar on every click, moving Annulla, Ripeti and Anteprima horizontally under the
pointer. (ii) macOS collapses an overflowing toolbar into a `>>` overflow menu, and an item
inside it is not reachable by `accessibilityIdentifier` the way a visible one is — which
would make the UI suite's verdict depend on the window's width. (iii) It puts board
**selection** state into window chrome, which is the level at which Annulla/Ripeti and the
tray toggle live; the SPEC itself calls the destination "the board's own toolbar".

**A3 — Add a `ShortcutCommand` case per new entry (`duplicateCard`, `copyLinkAtPath`, …) and
route everything through `CommandActions.run`.** Rejected: that enum's raw values are the
persisted keys of the shortcut-overrides file, so each case is a permanent identifier bought
for a command that has no key; and `run(_:)`'s own header records that the exhaustive switch
was already given up once because SwiftLint scores a thirty-three-way switch as an error in
a codebase that contains no `swiftlint:disable` anywhere. Six more cases pushes the same
switches further in the direction that already had to be undone.

**A4 — Keep ADR-0022 §D8's toolbar-only folder verbs.** Rejected by the user with informed
consent during the interview, and rejected on the merits here too: §D8's stated reason is an
accessibility-identifier propagation that a context menu is structurally outside of (§D2). A
decision should be revisited when the fact under it turns out not to reach the new case,
which is exactly what happened.

**A5 — Make «Duplica card» duplicate the referenced file as well, the Finder sense of the
word.** Rejected: it breaks CLAUDE.md principle 1 at the point that matters most. A second
copy of a note on disk is a second title in the index, a second wikilink target with the
same name, and a conformance-linter finding — produced by a command a person invoked meaning
"put another card here". The card is a pointer; duplicating the pointer is the whole
feature.

**A6 — Put `duplicate` on `CanvasDocument` in `Sources/Core` and expose it to `perg` and the
MCP server.** Rejected: neither connector has any board-editing surface at all, so this
would be the first, arriving as a side effect of a UI feature rather than as a decision —
the same reasoning ADR-0022 §D6 used to keep the folder verbs out of `VaultAPI`. It would
also mean a new `Sources/Core` file compiled into both command-line tools for a command
neither can invoke.

**A7 — Sequential or positional node ids (`node-1`, `node-2`) for the duplicate.** Rejected:
`CanvasID.generate()`'s own comment states that the 16-hex shape is what keeps a Pergamenum
canvas visually indistinguishable from one Obsidian wrote (Binding principle 4), and a
positional id collides the moment a node is deleted and another added.

**A8 — Extract the three shared calendar day-cell entries (`Vai a questo giorno`, `Apri
nella scala Giorno`, the daily note) while adding the two new ones, since `MonthView` and
`WeekView` hold byte-identical copies.** Rejected as scope: the SPEC scopes two new entries,
not a refactor of three existing ones, and touching them puts three currently-green surfaces
at risk for no requirement. The duplication is recorded here so the next person does not
have to rediscover it.

## Consequences

### Positive

- **R-13 stops being a review item.** One naming site per command means the toolbar icon and
  the context-menu icon cannot disagree, because there is only one of them.
- **The Backspace-delete of a drawn embed gains its first discoverable UI** without gaining
  a second edit path: the menu item calls the function the key calls.
- **Duplica costs no storage decision.** No index field, no frontmatter key, no schema bump,
  no `IndexCache.schemaVersion` change — which matters because that constant is a declared
  protected interface (`.claude/protected-interfaces`) and this feature must not touch it.
- **No `Project.swift` edit and no `tuist install`.** Every new file is under `Sources/**`
  minus the two excluded roots, so it enters the app target automatically; the one shared
  file that gains a function (`Sources/Vault/CanvasStore.swift`) is already in
  `sharedSources`.
- **No new dependency.** The only third-party package in this repository is the MCP SDK, and
  nothing here approaches it.
- The three calendar surfaces get their new entries from one place, so R-09's "identici tra
  loro" is enforced by construction rather than by three careful copies.

### Negative

- **`CommandActions` grows a second dispatch axis** (`run(_:on:)` beside `run(_:)`). Two
  functions named `run` differing by a subject is a mild readability cost, and `canRun(_:on:)`
  must be kept honest against `canRun(_:)` — the same negative-control risk
  `CommandActionTests.swift`'s own header describes, now with one more surface to keep in
  step.
- **`MiniCalendar`'s initializer grows by two parameters.** One call site today, but the
  view's argument list is now six, and the next entry will make it eight. If it grows again,
  it wants a small `MiniCalendarActions` struct — the shape `WorkspaceFolderActions` already
  has in the Workspace browser.
- **A right-click in the editor now goes through an override.** `menu(for:)` returning the
  wrong thing on a point that is *not* an embed would replace the standard editor context
  menu (spelling, substitutions, cut/copy/paste) with nothing. The `super.menu(for:)`
  fallback is load-bearing and belongs in the manual QA pass, not only in a unit test.
- **The card bar is a fourth floating control cluster over the board**, alongside the pen
  controls, the zoom controls and the crop editor's grips. On a short window with the pen
  controls open they stack; the bar is placed above the pen row so the zoom controls stay
  where a person has learned to find them.
- **`Duplica` has no keyboard shortcut** (§D12), so a person who duplicates cards often must
  reach for the mouse each time. Deliberate, and cheap to revisit: adding the key later is
  one enum case and one collision check.

### Neutral

- **Two SPEC statements are false and are corrected in the plan rather than obeyed.** (i)
  R-07's stated precedent — *"matching how Anteprima rapida already behaves in that
  toolbar"* — does not exist: Anteprima is `.disabled(workspace.selectedFileURLs.isEmpty)`
  (`WorkspaceView.swift:264`), shown-and-greyed rather than hidden, and its condition is
  *file* cards rather than any card. R-07's rule (hidden, not disabled) is implemented as
  written; the precedent is simply not cited in the code. (ii) The edge case "the vault root
  row does not gain Rinomina/Elimina" describes a row that does not exist (§D3).
- **ADR-0022 §D8 is superseded on its conclusion and reaffirmed on its reasoning.** The
  Workspace toolbar stays exactly where §D8 put it, a sibling row of the header; what
  changes is that the folder verbs now have a second entry point as well.
- The duplicated `menu(for:)` block between `MonthView` and `WeekView` is left as it is
  (A8), now documented.
- `WriteJournal` is not involved anywhere in this feature: every write is either a canvas
  mutation (already outside the journal) or a note edit through a path that is already
  journalled by whoever owns it.

## References

- `SPEC.md` — Universal command surface parity (PG-042), R-01 … R-14
- ADR-0022 — Workspace UI: create, rename and delete a workspace from the sidebar (§D6, §D8, §D9, §D10)
- ADR-0021 — Workspace browser, task↔workspace relations (§D10: boards are not in the index)
- ADR-0020 — Image card crop (`pergamenum-crop`, a prefixed key on the node's `unknown`)
- ADR-0019 — Drag-to-resize for drawn embeds (§D6, §D7: the editor's one edit path)
- ADR-0018 — The editor hides the syntax it can draw (§D5: the caret never enters a drawn embed)
- ADR-0013 — The week and the tasks that slip (§D4: the three calendar scales)
- ADR-0011 — Templates and local version history (§D5: applying a template to the open note)
- ADR-0008 — Global capture panel (§D1: the one command that is deliberately shortcut-only)
- ADR-0002 — Note naming and remappable shortcuts (the collision-check discipline)
- ADR-0001 — Initial architecture (§D1: `Sources/Core` must not import SwiftUI)
- `CLAUDE.md` — binding principles 1 (file over app), 3 (rebuildable index), 4 (Obsidian compatibility); design system (tokens, SF Symbols, no emoji)
- JSON Canvas 1.0 — node `id` uniqueness within a file
