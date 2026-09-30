Status: Approved (2026-09-28)

# SPEC — Day-boundary and calendar math: time blocks that survive midnight, events drawn on the day they cover, and five smaller calendar defects

## Destination

A SPEC handed to `/workplan`. Closes issue #573 (Audit Fable chain 6, ledger `PG-259`) in one PR.
The per-finding evidence is `ROADMAP.md` §Chain 6, re-verified against `origin/main` @ `2d1adb40`
on 2026-09-28. One audit claim was refuted there and is excluded (see Out of scope).

## Objectives

- A time block is never lost because of where it ends. Today a block that ends at midnight is
  written as `00:00`, the parser refuses it, and the next rewrite of the day's timeline section
  deletes the line. Resize and move already produce such an end, and creation near midnight
  produces a line that wraps past it.
- A new block never overlaps an existing one and never runs past midnight. Today the free-slot
  search tests only the start point and ignores the duration.
- An EventKit event that crosses midnight or spans several days is drawn, on each day, at the hours
  it actually occupies that day. Today every day after the first draws it at the start hour with
  its full duration.
- Five smaller defects stop misleading the user: diary drags measured in a coordinate space that
  moves with the card, every category and week deadline painted as overdue, duplicate identities
  in the mini calendar, the Today pane embedding any open note whose path merely contains the
  day's date, and a 30-second timer that re-evaluates the diary on days where it draws nothing.

## Scope and non-goals

In: the time-block model (formatting, parsing, placement, creation), the three creation paths that
reach it (app, `perg`, MCP), the conversion of an event into a per-day time range in the Day and
Week views, the diary card's drag and resize gestures, the deadline colour in the category view and
the week plan, the mini calendar's cell identities, the Today pane's daily-note check, the diary's
now-line timer.

Out, one line each: diary resize clamping (refuted, already correct); an upper bound on a block
beyond the existing 5…480 settings range; recurring-event expansion; any GUI test; the diary's own
24:00 handling (already correct, it is the reference).

## Decisions

- **Time blocks follow the diary's midnight rule.** A block never crosses midnight; an end of
  exactly midnight is written as `24:00` and read back as the end of the day, the same convention
  the diary's entries already use. Rejected: capping the end at 23:59 — it avoids `24:00` but stops
  a block one minute short of midnight and makes the two timeline formats diverge.
- **Creation shortens rather than overlaps, refuses, or moves earlier.** A block starts at the
  first free slot at or after the requested start and lasts the requested duration or until the
  next block or midnight, whichever comes first, provided at least the smaller of 15 minutes and
  the requested duration is free. Otherwise creation is refused with a visible sentence, including
  in the app's «Inserisci Blocco Tempo» and hour-drop paths, which are silent today. Rejected:
  refusing whenever the full duration does not fit — a drop at 23:30 with a 60-minute default would
  simply fail; moving the block earlier — it keeps the duration but does not start where the user
  dropped it.
- **Lines already on disk are recovered, not dropped.** An end of `00:00` with a start after
  midnight reads as `24:00`; an end earlier than the start (a line that wrapped past midnight)
  reads as `24:00`, truncating the block at midnight, provided the recovered block lasts at most
  480 minutes, the longest block the app can write; a longer one stays malformed and is skipped,
  as today. The next rewrite stores the corrected form. (Cap added at plan gate G3, 2026-09-28: the
  uncapped reading turned the existing malformed-line fixture `11:00-10:00` into a 13-hour block.)
  Rejected: recovering only `00:00` — the wrapped lines creation has already produced would still
  be deleted on the next write.
- **An event is drawn per day as the part of it that day covers.** The first day shows it until
  midnight, the last day from midnight, a day it covers entirely goes into the all-day row instead
  of filling the grid. One shared pure helper computes this for both the Day and Week views, which
  today duplicate the conversion. Rejected: clipping only (a fully covered day becomes a 00–24
  block and widens the hour window to the whole day); showing the event only on its first day (it
  becomes invisible on the others).
- **Connectors refuse an out-of-range block duration.** `perg` and the MCP server refuse a
  duration outside 5…480 minutes, the settings range, or one that is not a number, with one
  sentence, following chain 3's rule for malformed input; a valid value follows the same shortening
  rule as the app. (Non-numeric case added at plan gate G2, 2026-09-28: today it silently falls
  back to the vault default.) Rejected:
  silently clamping into range — the connector would write something other than what was asked.
- **A deadline is painted overdue only when it has passed.** The category view and the week plan
  use the rule task rows already use (a date before today is overdue), and the secondary text
  colour otherwise, the colour the upcoming-deadlines list already uses (plan gate G1, 2026-09-28).
  No new rule is invented.
- **The Today pane recognises the daily note by exact path**, the same path every other daily-note
  lookup already builds, instead of a substring match on the date.
- **The diary's now-line timer runs only while the shown day is today.**
- **Tests are unit tests on pure seams, zero GUI tests.** The diary gesture coordinate space and the
  timer cannot be asserted by a unit test and are verified by hand. Rejected: a GUI drag test for
  the diary — the GUI suite is deliberately small and synthetic drags on macOS 27 are fragile
  (PG-162).

## Constraints

- **Timeline section format stays plain `HH:MM-HH:MM` lines** readable by any editor — origin:
  CLAUDE.md principle 1 (file over app). `24:00` is already a value the diary writes, so no new
  syntax enters the vault.
- **No on-disk format, schema or protected interface changes** — origin: user mandate for this
  chain, consistent with every Audit Fable fix chain so far.
- **The existing unit test that asserts `24:00` is rejected by the time-block parser changes
  meaning, it is not deleted** — origin: CLAUDE.md working agreement (never disable or delete a
  test to make a suite pass). Its expectation flips because the behaviour it pins is the defect.
- **Colours and fonts go through tokens** — origin: CLAUDE.md design-system binding rule.

## Data model

A time block is a start minute and an end minute within one day, `0 ≤ start < end ≤ 1440`. The
value 1440 is legal as an end and is written `24:00`. No other entity changes.

An event's per-day projection, computed from its start, end and the shown day:

```
enum DayProjection { case none, allDay, timed(startMinute: Int, endMinute: Int) }
```

`allDay` when the event covers the whole day (starts at or before its midnight, ends at or after the
next); `timed` with the clipped range otherwise; an event ending exactly at midnight belongs to the
previous day only, as the existing week bucketing already asserts.

## API / interfaces

- The time-block free-slot search returns a start and a (possibly shortened) duration, or nothing.
  Its three callers (app creation, hour drop, session creation used by capture and both connectors)
  report the refusal as a sentence.
- The connectors' block-duration argument is validated to 5…480 before reaching the session.
- `perg` and MCP output shapes are unchanged.

## UI flows

- Dropping a task on an hour, or «Inserisci Blocco Tempo», near midnight or next to another block
  creates a shorter block rather than an overlapping or wrapping one; when no slot of at least 15
  minutes remains, the day shows a one-line refusal instead of doing nothing.
- A multi-day event appears on each of its days at the right hours, or in the all-day row on the
  days it covers entirely.

## Edge cases

- A resize or move that ends exactly at midnight is written `24:00` and survives a reload.
- A block at 23:45 with a 60-minute default becomes 23:45–24:00.
- A requested start that snaps to 24:00 has no room and is refused.
- A requested duration of 10 minutes (connector) in a 12-minute gap is created at 10 minutes; the
  15-minute floor applies only as `min(15, requested)`.
- An event ending exactly at 00:00 appears only on the day it started.
- An event starting at 00:00 and ending at 24:00 of the same day is all-day for that day.
- A note at `20260925-riunione.md` open while the Today pane shows 2026-09-25 is not embedded as
  the daily note.
- The mini calendar's leading and trailing blank cells, and the two «M» weekday initials, each have
  a distinct identity.

## Test seams

All in existing test files, no new test target:

- Time-block formatting, parsing, recovery of `00:00` and wrapped ends, free-slot search with
  shortening and refusal — the calendar test file that already covers the parser and round trip.
- Move and resize ending at midnight surviving a write-and-read — the time-block gesture test file.
- Creation shortening and refusal reporting through the controller and the session — the day
  controller and session test files.
- The event per-day projection helper — the week plan test file, beside the existing bucketing
  tests.
- Mini calendar cell identities — the month grid test file.
- The daily-note predicate and the overdue-deadline rule — the nearest existing test file for each;
  `/workplan` picks it.
- Connector duration validation — the connector test file and `scripts/mcp-smoke.py`.

## Success criteria

- [ ] R-01 — A block ending at 1440 is formatted `24:00`; `24:00` is parsed as 1440 when it is an
  end; the full section round-trips unchanged.
- [ ] R-02 — A move or resize that ends exactly at midnight, written and read back, yields the same
  block; nothing is dropped from the section.
- [ ] R-03 — A line with end `00:00` and a later start is read with end 1440; a line whose end is
  earlier than its start is read with end 1440 when the recovered block lasts at most 480 minutes,
  and is skipped otherwise; the next rewrite writes the recovered lines in the corrected form.
- [ ] R-04 — The free-slot search never returns a range overlapping an existing block.
- [ ] R-05 — The free-slot search never returns a range ending after 1440.
- [ ] R-06 — When the requested duration does not fit before the next block or midnight, the
  returned duration is shortened to the free space, provided at least `min(15, requested)` minutes
  are free; otherwise nothing is returned.
- [ ] R-07 — A refused creation from «Inserisci Blocco Tempo» or an hour drop reports a sentence the
  day view shows; creation through the session still records its problem.
- [ ] R-08 — `perg` and the MCP server refuse a block duration outside 5…480, or one that is not a
  number, with one sentence and write nothing.
- [ ] R-09 — The per-day projection returns `timed` with the clipped range on the first and last
  day of a multi-day event, `allDay` on a day it covers entirely, `none` on a day it does not touch,
  and treats an event ending exactly at midnight as belonging to the previous day only.
- [ ] R-10 — The Day and Week views place events through that projection; neither keeps its own
  date-to-minute conversion for events.
- [ ] R-11 — The Day view's hour window is widened by the projected range, never by the event's
  unclipped start and duration.
- [ ] R-12 — The diary card's move and resize gestures measure translation in a coordinate space
  that does not move with the card. (no-test: gesture coordinate space is not observable from a
  unit test; verified by hand dragging and resizing a diary entry)
- [ ] R-13 — A category or week-plan deadline before today uses the overdue colour; today or later
  uses the secondary text colour, by the same rule task rows use.
- [ ] R-14 — Every mini calendar cell, blank padding included, and every weekday initial has a
  distinct identity.
- [ ] R-15 — The Today pane embeds the open note as the day's note only when its path equals the
  day's daily-note path.
- [ ] R-16 — The diary's now-line timer runs only while the shown day is today. (no-test: the timer
  lives in a view's task; verified by hand opening a past day and today)
- [ ] R-17 — The existing parser test that rejected `24:00` asserts the new behaviour instead of
  being removed; every other existing calendar, diary and week test stays green unchanged.

## Not yet specified

_none_

## Out of scope

- **Diary resize clamping.** The audit said resizing a late entry's bottom edge moves its start;
  the code clamps the duration first and the start stays put. Refuted, nothing to do.
- **Diary 24:00 handling.** Already correct and already tested; it is the model this chain copies.
- **Recurring events and time zones.** The projection works on the event's own start and end dates
  as EventKit returns them; nothing about recurrence expansion or zone conversion changes.
- **A GUI test for the diary drag.** See Decisions.
- **The other Audit Fable chains**, including chain 15's performance work beyond the one timer.
