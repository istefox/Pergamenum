# ADR-0006: The hours a timeline draws are a setting, one window per section

- Status: accepted
- Date: 2026-08-15
- Supersedes: nothing. Refines ADR-0005 §D5 and SPEC §8.3, both of which spell the
  hours as literals.

## Context

Two panes draw a day on a grid, and each had its hours written into the view: SPEC §8.3
puts the Oggi pane at 06:00 to 22:00, and ADR-0005 put the Diario at 06:00 to midnight
after the first window (06:00 to 20:00) turned out to end the day too early.

That second change is the argument for this one. The right window is not a fact about
the app, it is a fact about the person using it: someone who starts at five and stops at
six wants a grid that says so, and every hour drawn outside their day is a stretch of
empty pixels between the hours that matter.

## Decision

**D1. Each timeline reads its own window from `settings.json`.** `dayHours` and
`diaryHours`, both `{first, last}` in whole hours, defaulting to what each pane already
drew - 06:00 to 22:00 for Oggi, 06:00 to 24:00 for the Diario. In the vault rather than
in `UserDefaults`, like every other setting that describes how a notes folder is worked
with (SPEC §12).

**D2. Two settings, not one shared.** The two panes answer different questions: a plan
for a working day, and a record of a day that includes the evening it is written in. One
number would make one of them wrong, and the pane that lost the argument would be the
one nobody thought about.

**D3. A window never hides anything.** Both grids widen themselves to reach a block or
an event outside the hours set: `HourWindow.covering(startMinutes:endMinutes:)` extends
the window up to the earliest start and down to the hour above the latest end. The
setting says which hours are *always* drawn, not which hours may exist. Without this a
block at 21:00 under a window ending at 18:00 would be drawn below the grid, invisible
and impossible to move back - the setting would eat the data it displays.

**D4. A window is repaired rather than obeyed.** `settings.json` is meant to be
editable by hand, so `{first: 22, last: 3}` is clamped on decode instead of producing a
grid of negative height that draws nothing and cannot be fixed from inside the app. The
pickers cannot express one: the "alle" list only offers hours after the "dalle".

## Consequences

- `DayTimeline` takes its window as a parameter rather than holding two constants, so
  the Oggi pane's grid also grows to reach a late event - which it never did, and which
  is why an event at 23:00 used to be drawn above the top of the day.
- One more settings tab, "Giornata". The two windows are the only thing in it.
- SPEC §8.3's "06:00 to 22:00" is now the default rather than the rule, and ADR-0005 §D5
  reads the same way for the diary.
