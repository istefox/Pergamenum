# ADR-0004: A task date can carry an hour, and the day view filters rather than duplicates

- Status: accepted
- Date: 2026-08-14
- Supersedes: nothing. Extends SPEC §7.1 (task syntax) and refines §8.1/§8.3 (day view
  and timeblocking) and §12 (settings).

## Context

Seven things were asked for in the Oggi pane, and they turn out to be three subjects.

The first is the toolbar. It had a bell that created an Apple reminder, which the
Calendario menu already does with a shortcut - a second door to the same room, in the
one place where a filter was missing. It had no way to capture a task, so a task
thought of while looking at the day had to be captured from the Attività pane or from
the menu. And it could not show a finished task at all: a task ticked off leaves every
view immediately, which is right until one wants to see what got done.

The second is the hour. SPEC §7.1 spells both date markers as a bare day:
`>YYYY-MM-DD` for the day a task surfaces on and `!YYYY-MM-DD` for the day past which
it is late. A deadline at 15:00 could therefore only be written as prose inside the
task text, where nothing reads it, or as a `@remind(...)`, which is a different thing:
a notification, not a due time.

The third is the time block. The button that made one said "Blocca", which reads as
blocking the *task*; blocks always lasted 30 minutes with no way to change that; and
once made, the only way to remove one was a context menu on the timeline that nobody
would guess was there, or editing the markdown by hand.

## Decision

**D1. A date marker may carry an hour, written after the date.** `>2026-08-15 09:00`
and `!2026-08-20 18:00`. The hour is optional everywhere, is exactly `HH:MM`, and is
refused rather than guessed at when it is anything else - `>2026-08-15 25:99` parses as
a day with `25:99` left in the task text.

It goes *after* the date rather than inside it because that keeps every existing reader
correct: a parser that stops at the ten characters of the date - Obsidian, or a
Pergamenum older than this - still gets the day right and treats the hour as ordinary
text. Nothing that was written before this change reads differently after it.

This is a divergence from SPEC §7.1, recorded here rather than by editing the
specification, as ADR-0002 did for the Note pane's name. `TaskTime` is the type;
`TaskParser` reads and writes it; the whole marker, hour included, comes out of the
display text.

**D2. Rescheduling drops the hour.** Cmd+0/1/2/3 and the "Domani" context menu say a
day and nothing about a time, so `line(for:scheduledOn:)` writes the day alone. An hour
carried onto a day nobody mentioned is an appointment the user never made.

**D3. A task with an hour can also become a block, and is asked about.** When the
composer holds a date *and* an hour, a checkbox appears: "Mettilo anche nell'orario del
giorno". Ticking it writes a block into the daily note of that day, at that hour,
creating the note from the template when it does not exist. Unticked - the default -
nothing but the task line is written.

The planned hour wins over the deadline when a draft has both: `>` is when the work is
meant to happen, `!` is when it stops being on time. Without an hour there is no
question to ask, because a block is a span of a day and a date alone says nothing about
where on the day it goes.

The block is written to the file directly rather than by opening the note: a task due
next Tuesday would otherwise take the editor away from whatever was on screen.

**D4. The bell filters instead of creating.** It toggles a "SCADENZE IN ARRIVO" card
listing the open tasks due in the next thirty days, soonest first, each with its date
and hour and a way to jump to that day. "Nuovo promemoria" keeps its place in the
Calendario menu, keys and all.

**D5. Days with a deadline are marked on the month, always.** A second dot beside the
daily-note one, in the colour deadlines are drawn in everywhere else. Not behind the
filter: a deadline exists to be seen before it arrives, and the filter is for reading
the list, not for knowing there is one.

**D6. Completed tasks come back on request.** A second toggle widens the day's list to
tasks already done, through `NoteIndex.tasks(for:on:includingCompleted:)`. Off by
default, because a day list that keeps everything ever finished stops being a day list.

**D7. "Blocca" is now "Inserisci Blocco Tempo", its length is a setting, and it can be
undone from either side.** The duration lives in `VaultSettings.blockMinutes` - per
vault rather than per user, since a block is a line in a daily note - and defaults to
the 30 minutes of SPEC §8.3. Blocks are listed in the note column with a delete button
each, and each block on the timeline shows one on hover as well as keeping its context
menu. A block made from a task starts at the task's own hour when it has one.

## Consequences

- A vault written by this version and read by an older one loses nothing: the hour is
  extra text on a line that still parses. Read by Obsidian it is plain text, as the
  markers already were.
- `TaskItem` gained `scheduledTime` and `dueTime`; anything matching on `scheduled` or
  `due` alone is unaffected.
- `TodayView` was split into `DayReferences` and `DayTimeline`. It was the largest view
  in the app and two of the seven changes landed in it; the split removed two SwiftLint
  warnings rather than adding any.
- The day view's filters live on `DayController`, not in `@AppStorage`: they are how
  one is reading today, not a preference, and they start off on every launch.
- The settings window gained an "Attività" tab, which SPEC §12 asks for anyway.
