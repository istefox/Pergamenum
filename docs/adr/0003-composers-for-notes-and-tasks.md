# ADR-0003: A new note is composed in the editor, a task in a Craft-shaped panel

- Status: accepted
- Date: 2026-08-13
- Supersedes: nothing. Refines SPEC §7.4 (cattura rapida) and §10 (File > Nuova nota).

## Context

Two creation flows both opened a sheet floating over the window.

For a note the sheet asked for a title, a folder and a topic, then dismissed itself and
left the editor showing the new file. The title has to be settled before the file
exists, because the title *is* the file name (SPEC §4.2) - but settling it in a modal
meant the next thing you wanted to do, write, happened somewhere you could not see
while deciding.

For a task the sheet was a single text field appending to `00 Inbox/Capture.md`. Every
task therefore arrived with no date and in one place, and anything else - a due date, a
reminder, a task belonging to a particular note - had to be typed as markers by hand,
or edited afterwards in the note. Craft's capture panel does all of it in one panel and
was named as the model to follow.

The quick-capture sheet was also presented by the Attività pane, so the File menu's
"Nuovo task rapido" did nothing at all from the other four panes: the same class of
defect as the Conformità one fixed the day before.

## Decision

**D1. The new-note composer lives in the editor column.** `VaultController.newNote`
holds a draft (folder, title, topic); while it is non-nil the Note pane's middle column
shows `NewNoteComposer` instead of the editor. Enter creates the note, the column
becomes the editor showing it, and the cursor is put in the text. Escape or Annulla
drops the draft. The File-menu command switches to the Note pane first, since the
composer is now part of that pane rather than a window of its own.

**D2. The task composer is a panel with a destination, one date and a reminder.** It
carries, top to bottom: the destination note (Inbox by default, any note through a
searchable picker), the text, a Scadenza chip and a Promemoria chip, then a Crea button
whose menu offers "Crea e apri la nota" and "Crea e continua". What it writes is the
ordinary markdown line of SPEC §7.1 - there is no second representation of a task
anywhere, which is what keeps the vault the source of truth.

*Revised twice on 2026-08-13.* First the three date fields (Programma, Scadenza,
Promemoria) became one called Scadenza that wrote both markers, because Programma and
Scadenza read as the same decision asked twice. Then they became two again, with the
names the right way round and a panel each:

- **Programma** (`>`) opens the list: Oggi, Domani, La prossima settimana, Fra 2
  settimane, Fra 3 settimane, Fra un mese, Seleziona data…, and below a divider
  Ricordami… and Ripeti…, which is where the reminder and the finite `@repeat(n/N)`
  now live. A list, because the day wanted at capture time is nearly always one of a
  handful and paging a calendar to find it is work.
- **Scadenza** (`!`) opens a calendar and nothing else, because a deadline is a
  particular day someone already has in mind.

Both fields take a date typed into them (`20/08`, `2026-09-01`, `domani`); anything
that does not read as a date is refused rather than guessed.

The consequence to know: a task given a Scadenza and no Programma is in no task view
until the day it becomes late, because SPEC §7.4 defines Oggi as `>oggi` plus overdue
and Prossimi as the next seven days of `>`. That is the specified behaviour and this
ADR does not change it; the Programma field is what puts a task in front of you.

**D3. Only the inbox note is created on demand.** A destination that is a note has to
exist; the composer refuses and says so otherwise. Inventing a note from a task
composer is how a vault fills with files nobody meant to create.

**D4. The composer is presented by the window, not by a pane.** `RootView` shows it, so
the command works from wherever the user is.

**D5. Both composers type into an AppKit field.** SwiftUI restores focus to a
`TextField` by selecting the whole of it, so returning from a date popover left the
task text selected and the next keystroke replaced it - observed on the running app,
and a silent loss of what the user had written. `ComposerTextField` wraps an
`NSTextField` and puts the caret at the end instead. The font and colour still come
from the theme, through a new `Theme.nsFont(_:)`: the token rule is about where a value
comes from, not about which framework draws it.

**D6. A task write bumps its own generation counter.** `taskGeneration` is incremented
by every completed scan *and* by every task line the app writes, and the reminder
scheduler watches that instead of `scanGeneration`. A `@remind` composed in the app
used to schedule nothing until the next full rescan.

## Consequences

- `NewNoteSheet` is gone; the naming rules and their error messages moved to
  `NewNoteComposer` unchanged.
- `captureTask(_ text:)` stays as the one-line form and now delegates to the draft one,
  so the existing tests and the URL scheme keep working.
- The Attività pane follows a capture into the view it landed in (Inbox, Oggi or
  Prossimi), because a captured task that appears nowhere reads as a capture that
  failed.
- The composer panel is still a sheet, which is what Craft's is: the objection was to
  naming a *note* in a floating window, not to a capture panel being one.
