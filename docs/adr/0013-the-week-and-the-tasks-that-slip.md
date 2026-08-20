# ADR-0013: The week is a scale of the day, and a task that slipped is surfaced rather than moved

- Status: accepted
- Date: 2026-08-20. Three points were put to Stefano before this was written - where M12 starts,
  what tags an event note is born with, and whether the weekly review is a screen or a template.
  All three were answered as recorded below.
- Supersedes: nothing. **Amends SPEC §7.3**, which rejects rollover outright, and that amendment
  is the reason this ADR exists rather than a plan.
- Depends on: ADR-0004 (the hours a task carries and the day view's filters), ADR-0006 (the hours
  a timeline draws are a setting), ADR-0009 §D5 (the guarded, journalled write a gesture makes,
  which D5 here reuses whole), ADR-0011 §D5 (a reserved folder is a location, not a tag).

## Context

M12 (`PG-013`, `docs/20260816_Pergamenum_Roadmap.md`) has one sentence for a brief: *the day is
well served; the week is not.* There is a day view with a timeline, a month grid used as a date
picker, and five task views. There is no way to look at a week, no way to plan one by moving
things onto days, and no way to group or sort the task list in front of you.

Two things in it are decisions rather than work, and this ADR exists for them.

**SPEC §7.3 rejects rollover, by name and with a model behind it.** *«Nessun rollover automatico
(modello NotePlan): i task non completati restano evidenziati.»* That is not an omission to be
filled in; it is a choice, and CLAUDE.md says §14's choices are not reopened without a stated
reason. The reason is in the roadmap and it is narrow: **the rule assumes the day view is opened
every day.** It is a good rule for somebody who opens it every morning. Skip two days and a task
scheduled for Monday is reachable only by navigating back to Monday, while the Attività *Oggi*
view shows it as overdue with no way to move a group of them. The original argument - that a
task must not silently change the day its file says - is untouched by this, and the amendment is
built to keep it.

**An event note has nowhere to live yet.** The roadmap asks for *«Nota per questo evento»* from
the timeline, writing `Calendar/YYYYMMDD-<slug>.md`. Two facts collide there. The first: SPEC
§8.1 already makes `Calendar/` the **daily-note folder**, configurable, so this is not a new
place but a sibling of the note for that day. The second: a generated note is judged by the
linter like every other, and an ordinary note owes `type-note` plus a `topic-*` - which a stub
created by one click does not have and cannot invent.

## Decision

**D1. Rollover is a setting, default off, and it surfaces without moving anything.**

When it is on, the day view shows yesterday's unfinished scheduled tasks - and the day before
that, up to a bound the setting names - under the day's own, with a marker saying which day each
one belongs to. Nothing is rewritten. Moving one is a keystroke that rewrites `>date` in the
source file, exactly as the panels do today.

The three narrowings that make this an amendment rather than a reversal:

- **The file does not change and Obsidian sees nothing new.** A rolled-over task is a task whose
  `>date` still says Monday, drawn on Thursday with Monday written next to it. There is no new
  marker in the markdown, no second date, no state kept beside the file. Deleting `.pergamenum/`
  changes nothing about it, which is principle 3 still holding.
- **The marker says where the task is, not where it is going.** A rolled-over row that looked
  like an ordinary one would be the silent move §7.3 refuses, drawn instead of written.
- **Default off, and the setting says what it does in a sentence.** Somebody who opens the day
  every morning is served by the existing rule and should not have to discover why their list
  grew.

The alternative considered and refused: rollover that rewrites `>date` on launch. It is what
every other app means by the word, and it is the one thing this vault cannot have - a file
changing because a day passed, with no gesture behind it, is a diff nobody made appearing in a
git history somebody reads.

**D2. An event note is a sibling of the daily note, not a new reserved folder.**

`Calendar/YYYYMMDD-<slug>.md` in the folder SPEC §8.1 already configures for daily notes, next to
`YYYYMMDD.md`. Nothing is reserved that was not reserved before, and a vault whose daily folder
is called something else gets its event notes there without a second setting.

The name is safe against the rules that already exist, and this was checked rather than assumed:
`NoteName.category` calls a note *daily* only when its stem parses as a compact date, so
`20260820-riunione-tecnica` is an ordinary note and is judged by `NoteName.validate`, which it
passes - no forbidden character, no version suffix, inside the length.

**D3. An event note is born in the capture shape: `type-note` + `status-inbox`.**

The exemption already exists and is already argued: a note created by a gesture is a stub, and
`status-inbox` is what tells the linter to stop asking it for a `topic-*` until somebody has
decided what it is about (tag.md 5.1, `NoteCategory` and `missingRequired`). Using it here adds
no rule and asks the harness for nothing.

The alternative considered and refused: a sheet asking for the `topic-*` before creating the
note. It makes the note conformant at birth and makes the feature unused - a dialog in the middle
of a one-click gesture is the reason people stop using the one click.

The body carries the hour and the attendees stamped from the event, and the daily note gets a
wikilink to it. Both are ordinary markdown: the link is a `[[…]]` like any other, so the backlink
panel already answers "which day was this meeting on" without anything new being indexed.

**D4. The week is a scale of the day view, not a new pane.**

Giorno, Settimana, Mese are three scales of one thing, switched in the day view's toolbar, all
anchored on `DayController.day`. Moving in the week and switching back to the day lands on the
day the week had highlighted, because there is one anchor and not three.

Refused: a fourth item in the sidebar. The sidebar names *places in the vault* - notes, tasks,
the workspace - and a second calendar entry beside Oggi would make the day and the week look
like different sources of truth about the same four things.

The grid draws four sources and no fifth: EventKit events, scheduled tasks, deadlines, and time
blocks. The daily note is the column's header rather than a source, because a day is not a note
that has a week - it is a day that has a note, and the note is one click away.

**D5. A drag writes one thing, and it writes it the way the board does.**

Dropping a task on a day rewrites `>date` in its source file. Dropping it on an hour writes the
time as well and creates the block, which is what the timeline already does on the day view
(SPEC §8.3). One task, one file, one write, through `VaultSession.write`, journalled for the
length of the gesture and undoable from the line the gesture leaves behind - the shape ADR-0009
§D5 established for the board's drop, including its **differential conformance guard**: what the
note already fails is not the gesture's fault, what the gesture would introduce is refused with
the reason.

No dry-run diff, for the reason §D5 gives: a drag that asked for confirmation would not be a
drag.

**D6. The task views get controls, and the controls are per view.**

Grouping (by note, project, schedule, deadline), sorting, and a compact/expanded density, each
remembered for the view it was set on: *Oggi* wants a flat list by hour and *Tutti* wants
grouping by note, and one shared setting would make every switch between them a re-setting. This
is SPEC §7.4 growing, not changing: the five views stay the five views.

## Consequences

- **SPEC §7.3 changes, and this ADR is the record.** The sentence rejecting rollover gains the
  option and the three narrowings of D1. The NotePlan model stays the default, which is what
  keeps the amendment narrow enough to make.
- **The daily folder now holds two kinds of note.** `YYYYMMDD.md` and `YYYYMMDD-<slug>.md` sit
  side by side, and every place that lists the folder sees both. That is correct - an event note
  *is* part of that day - and it is worth saying because a folder that held exactly one shape of
  file for five milestones now holds two.
- **A stub with `status-inbox` will show up in the Inbox view.** That is the exemption working as
  designed and not a leak: an event note nobody has tagged is precisely something waiting to be
  dealt with.
- **The week is the first surface that reads more than one day of EventKit at a time.**
  `CalendarService.events(on:)` answers per day; seven calls or one range is an implementation
  question, but the permission story does not change and neither does the on-device constraint.
- **A drag is the second gesture in this app that writes**, after the board's drop. Both go
  through the same guard for the same reason, and the second one is where that guard stops being
  a one-off and starts being the pattern a third gesture will be measured against.
- **Rollover has a bound and the bound is a number somebody has to choose.** How many days back
  it looks is a setting with a default, and a default of "all of them" would turn a quiet week
  into a list nobody reads. It ships at a small number and moves if it is wrong.
