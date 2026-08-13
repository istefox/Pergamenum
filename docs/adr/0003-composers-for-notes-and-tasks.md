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

*Revised 2026-08-13, same day.* The panel first offered three dates: Programma (`>`),
Scadenza (`!`) and Promemoria. Programma and Scadenza are the same decision asked
twice at capture time, so they are now one field called Scadenza, which writes **both**
markers with that date. Writing `!` alone would have been the tidier file and the worse
app: `tasks(for:on:)` puts a task in Oggi when it is scheduled today or already late,
in Prossimi when it is scheduled within the week, and in Inbox when it has neither
marker - so a task with a due date only would sit in no view at all until the day it
became late. `>` is when it shows up, `!` is when it turns red, and one date sets both.
Rescheduling later (Cmd+0/1/2/3) still moves `>` alone, which is right: the plan
changes, the deadline does not. `TaskDraft.deadline` is the computed property that
holds the pair together, and it reads back from whichever marker a hand-written task
happens to carry.

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
