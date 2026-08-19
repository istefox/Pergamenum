# ADR-0012: A tab owns the note's state; the tag browser writes one note at a time

- Status: accepted
- Date: 2026-08-19. Six points were put to Stefano before this was written - how much of M10
  ships at once, what a tab is, what closing a tab with unsaved edits does, what the split view
  holds, which keys the tabs take, and how a vault-wide tag rename is written. All six were
  answered as recorded below.
- Supersedes: nothing.
- Depends on: ADR-0002 (the shortcut catalogue, which is what makes D5 a change of defaults
  rather than a change of keys), ADR-0007 §D6 (the write guardrails D7 leans on), ADR-0009 §D2
  (which forbids `created:` and is not reopened here).

## Context

M10 (`PG-011`, `docs/20260816_Pergamenum_Roadmap.md`) is seven features under one heading: tabs,
split view, a tag browser, starred notes, an extended Quick Open, the missing search operators,
and unlinked mentions. They look like a grab bag. Two of them are not.

**`openNote` is singular, and eighty-two places read it.** `VaultController.openNote` is one
optional `OpenNote` (`Sources/Vault/VaultController.swift:100`), referenced 82 times across 24
files - the note list, the task views, the search results, the diary, the Workspace, the menu
bar. Tabs mean N of them. A rename of that property would be a diff nobody could review, and the
milestone would be spent on mechanical churn instead of on the feature.

**The per-note state is not all in the note.** `Navigation` holds `foldedEntries`,
`currentOutlineEntry` and `isReadingMode`, and `FindSession` holds the find bar's. Every one of
those belongs to *a note being looked at*, not to the window, and the existing code already knows
it: `VaultBrowser` clears the folds on `onChange(of: vault.openNote?.relativePath)` with the
comment "Carried over, the third fold of one note would silently become the third fold of the
next one." That guard is the single-note version of what tabs need structurally. With two tabs
open, clearing on change is no longer a fix - it is a data loss, because the other tab's folds
were real and are now gone.

**A vault-wide tag rename is the problem `PG-005` is already open about.** `NoteFileOperations`
rewrites links across many notes without going through `VaultSession.write`, so the journal
covers only part of the operation and neither connector can offer `note rename|move|trash`
(CLAUDE.md says so in as many words). Renaming `topic-x` to `topic-y` across forty notes is the
same shape. Shipping it the same way would double a debt this project has already written down.

**M11 is downstream.** The roadmap's own dependency line says Viste "depends on the index work
and the search operators of M10". Whatever else moves, the operators ship here.

Neither tabs nor the tag browser has a line in `docs/20260811_Pergamenum_SpecApp.md` - §13's
table stops at M6. This ADR follows the M7-M9 precedent: the SPEC amendment is debt filed on
`PG-015`, not a blocker.

## Decision

**D1. Tabs live inside the Note pane. `Navigation.pane` survives untouched.**

The tab bar belongs to `VaultBrowser`, not to the window. Switching to Oggi or Workspace hides
it; coming back restores it. The alternative - tabs as the top-level container, with the
Workspace and Oggi as tab *types* and the sidebar demoted to navigation - is the Craft model and
is a different application: `Navigation.pane` is read across `Sources/App/` and every feature
folder, and it would stop existing. That is a milestone of its own, and not this one.

**D2. A tab owns the buffer and every piece of state that belongs to the note in it.**

`NoteTab` holds the `OpenNote` (text, savedText, `externalChangePending`) plus what is today
scattered: `foldedEntries`, `currentOutlineEntry`, `isReadingMode`, and the find session. Those
three move off `Navigation`; the menu bar reaches them through `VaultController` exactly as it
reaches the buffer now, so SPEC §10's rule that a menu can change what it names still holds.

**`VaultController.openNote` stays, as a computed facade over the focused tab.** The 82 call
sites keep compiling and keep meaning what they meant: "the note the person is looking at".
`openNote(at:)` keeps its name and opens into the focused tab. This is deliberate and is the
reason this milestone is tractable - the type changes shape underneath while its one published
surface does not.

**D3. Closing a tab with unsaved edits asks: Salva / Non salvare / Annulla.**

The app saves explicitly, on Cmd+S (`VaultController.saveOpenNote`, guarded by
`hasUnsavedChanges`), and that is not being reopened. With one note open, explicit save is safe
because the buffer is in front of you. With six tabs it is not: closing the third one would
discard work silently. Autosaving on close would remove the risk and quietly end explicit
saving, which is a bigger decision than a tab close should make.

**D4. The split view is two columns, each with its own tab strip and its own focused tab.**

Only notes. A column is `[NoteTab]` plus a selection; the window holds one or two, and
`VaultController` knows which is focused - that is what D2's facade resolves against. "A note
beside its canvas", which the roadmap mentions, would mean the Workspace and Oggi learning to
draw in half a window, and it is not in this milestone. Two columns of notes is the Obsidian and
Xcode model and covers the acceptance case the roadmap actually states: a client note and its
project index side by side.

**D5. Tabs take Cmd+T and Cmd+1…Cmd+9. Two existing defaults move.**

`Cmd+T` is «Nota di oggi» (`ShortcutCommand.dailyNote`) and `Cmd+1` is «Task a domani»
(`.taskTomorrow`) today. In an application with tabs, Cmd+T that does not open a tab is a
surprise every time. «Nota di oggi» moves to `Cmd+Shift+T`, «Task a domani» to a free key. Both
are entries in ADR-0002's remappable catalogue, so this changes *defaults*: a binding the user
has already overridden is untouched, because the overrides file is keyed by
`ShortcutCommand`'s raw value. The panes are on `Ctrl+Cmd+1`… and are unaffected.

Every key introduced here is checked against the system's own before it is bound. M9 bound a
shortcut an approved mockup had drawn, and `Opt+Cmd+H` turned out to be «Nascondi altre».

**D6. Starred notes are `.pergamenum/starred.json`, a set of relative paths.**

Frontmatter is closed by SPEC §4.3 and starring is app state, not content: a note is not
different because this machine finds it useful. Losing the file loses the stars and nothing
else. Paths, not hashes, and a rename moves the star as part of the rename - the same class of
follow-up `PG-005` already carries.

**D7. Renaming a tag across the vault is N single-note writes through `VaultSession.write`,
journalled, presented as one operation.**

The diff is shown before anything is written (`UnifiedDiff` already exists, ADR-0007 §D6), the
writes go one note at a time through the one path every change goes through, and the journal
therefore records each of them. Undo puts them all back, refusing any note that has moved on
since - the guarantee `WriteJournal` already gives per file, applied to a group.

This is the more expensive answer and it is chosen on purpose: it is the first multi-note write
in this app that is *not* outside the journal, and it is the shape `note rename|move|trash` will
need in M13. Doing it any other way would mean writing the same feature twice and leaving
`PG-005` twice as large.

**It also narrows ADR-0007 §D6 rather than contradicting it.** `VaultSession.journal` is nil for
the app today, deliberately - "a person editing their own note in their own editor does not need
an undo log beside the file". That reasoning is about *one note the person is looking at*, and it
still holds. It does not extend to rewriting forty notes at once, thirty-nine of which are not on
screen and none of which the person will proof-read. So the journal is armed for the duration of
this one operation and disarmed after: the app gains a group undo for bulk writes and gains
nothing for ordinary editing, which is exactly the line §D6 drew, read at the right granularity.
Arming it wholesale for the app is a separate decision and is not taken here.

**D8. The operators complete the set, and each is computed where its data already is.**

`-term` and `regex:` extend `SearchQuery`, which already reads file text (search reads files,
not the index - the index holds structure only, `VaultSession+Search.swift:4-8`). `linked:<note>`
and `orphan:` read `IndexSnapshot`'s link graph, which has them today. `modified:` ranges read
`NoteRecord.modifiedAt`. `is:starred` reads D6's store, which is the one operator whose data
lives outside both the index and the files, and the reason the store is on `VaultSession` rather
than in a view. **No `created:`**: the index has no creation date and inventing one is a schema
decision, not an operator (ADR-0009 §D2, not reopened).

**D9. Unlinked mentions are computed on request, never on every note open.**

Finding notes whose text contains this note's title or an alias is a full-vault text scan - the
same cost as a search, because it is the same read loop. It runs when the backlinks pane asks
for it, not as part of opening a note, and the result is not cached in the index: `IndexCache`'s
schema version is spent by M11 (ADR-0009 §D2, `PG-012`) and this milestone must not touch it.

**D10. Open tabs are restored at launch, from `UserDefaults` keyed by the vault's path.**

Not `.pergamenum/`. The vault is meant to travel through iCloud Drive (principle 6) and which
notes are open on *this* machine is not something the other one should inherit. Starred notes
are the opposite case and go in the vault, which is what makes D6 and D10 different decisions
rather than an inconsistency.

## Slices

Four, each usable on its own, each verified on screen before the next starts.

1. **Tabs**: `NoteTab`, the facade of D2, the tab bar, D3's dialog, D5's keys, D10's restore.
2. **Split view**: the second column on top of slice 1, and the focus rule the facade resolves.
3. **Tag browser and starred**: the pane, counts, multi-tag narrowing, pinning, D6's store, and
   D7's journalled rename.
4. **Search and mentions**: D8's operators, Quick Open extended (recents, starred, daily note,
   "create note named X", jump to a heading), D9's unlinked mentions.

Slices 3 and 4 depend on nothing in 1 and 2 and can be reordered if the tab work proves larger
than it looks.

## Consequences

- **The riskiest change is invisible from the outside.** D2 rewrites what `VaultController`
  holds while leaving `openNote` reading the same at all 82 call sites. That is the point, and
  it is also the thing to be suspicious of in review: a facade that silently resolves against
  the wrong column is a bug no compiler will catch and no unit test will notice unless the test
  opens two tabs. Every test in slice 1 opens at least two.
- **The M9 lesson applies to the whole of slice 1.** A unit test reaches what the controller
  does; it does not reach what SwiftUI decides not to call. Tabs are made of selection bindings,
  drag reordering and keyboard focus - three mechanisms that failed exactly that way in
  `PG-027`, where six green tests said a fix was complete and the first click on screen said it
  was not.
- **Three new visual elements need a mockup first** (SPEC §11.1): the tab bar, the tag browser
  pane, and the unlinked-mentions section of the inspector. None is designed here - this ADR
  settles the state model and the write path, not the screen.
- **`Navigation` gets smaller, which is a migration, not a cleanup.** `foldedEntries`,
  `currentOutlineEntry` and `isReadingMode` move to `NoteTab`; the `onChange` that clears folds
  when the path changes is deleted rather than adapted, because per-tab state makes it wrong.
- **The connectors gain nothing here and must keep building.** Tabs, split view and starring are
  window state, and `Sources/Features/**` is not in `sharedSources`. D6's store and D7's rename
  belong on `VaultSession`, so `perg` and `pergamenum-mcp` *could* reach them later; whether
  they do is a separate decision, and CLAUDE.md's rule that a capability lives in
  `Sources/Connector/` once is unaffected by deferring it.
- **The SPEC amendment is debt, filed on `PG-015`**, as §18 (Tabs e split view) and §19 (Tag
  browser e preferiti), alongside the sections already waiting there.
- **`.pergamenum/starred.json` is a new file in the vault**, the fourth thing under that folder
  after `cache.db`, `history/` and `ai-journal/`. Deleting it loses the stars and nothing else.
