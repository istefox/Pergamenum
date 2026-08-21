# ADR-0014: A view can say today, it says it in days, and the day is told to it

- Status: accepted
- Date: 2026-08-21. Three points were put to Stefano before this was written - how many words
  the vocabulary grows by, whether a bound may point at the future, and what happens to a view
  left open across midnight. All three were answered as recorded below, and the third was
  answered against the recommendation, which is why §D4 decides more than it was going to.
- Supersedes: nothing. **Amends ADR-0009 §D3**, whose grammar admits an ISO date and nothing
  else after a comparison.
- Depends on: ADR-0009 (a view is a fenced block, the closed grammar, and §D7's rule about when
  a view runs), ADR-0013 (the weekly review that made the gap visible).

## Context

M12 shipped a weekly review as a template with four view blocks, and **none of them says «this
week»** (`PG-032`). It could not: `ViewFilter.comparison` accepts `date` and `modified` against a
`CalendarDate` parsed from a written-out ISO string, so a week has to be typed as
`modified >= 2026-08-17`. That block is correct for six days and wrong for ever after, and it is
wrong in the worst available way - it narrows, quietly, to a list that shrinks each week until it
is empty. An empty view is indistinguishable from a vault that lost its notes, which is the exact
confusion ADR-0009 §D1 wrote the *error naming the line* rule to prevent. The workaround shipped
in the template is to order by `modified` and explain in prose why the question is not being
asked; a template that has to apologise for its own query is a template teaching the wrong thing.

The grammar is closed on purpose, and §D3 says what to do about it: *«if a question cannot be
asked with these terms, the answer is a new term in a later version with an argument for it, not
a general mechanism that makes every future question the user's problem.»* This ADR is that later
version. Its whole job is to add the smallest thing that answers the question and to say where
the line is, because `text()` is already in the grammar as the standing reminder of what an
escape hatch costs.

One fact about the parser shapes half of what follows, and it was read rather than assumed. The
lexer's word set is `alphanumerics` plus `-_./*?#` and the accented vowels, so **`today-7` already
lexes as a single word** - it is the same token shape `2026-08-01` has today. A relative bound is
therefore a second *reading* of a token that already exists, not a new token. `+` is not in that
set, and that asymmetry is not arbitrary: it is the reason §D2 refuses a forward bound rather
than merely declining to build one.

## Decision

**D1. A date bound may be relative, and only where an absolute one is already allowed.**

`modified >= today-7`, `date = today`, `modified >= week-start`. The relative form is accepted
exactly where `CalendarDate(iso:)` is tried now: after a comparison operator, on `date` or on
`modified`, and nowhere else. No other key of the block gains a notion of now - not `from`, not
`sort`, not `group`. A view still describes a set of notes; what changes is that one of the ways
of describing it can be anchored to the day it is read on.

A bound that parses as neither an ISO date nor one of the three words in §D2 is **an error naming
the line**, as every other malformed block already is. It is never silently treated as absent:
a `where` that quietly lost half its expression is the empty-result failure this ADR exists to
stop repeating.

**D2. The vocabulary is three words, and the third one is the reason this ADR exists.**

- **`today`** - the day the view is evaluated on.
- **`today-N`** - `N` whole days before it. Days, because every field that can be compared is a
  `CalendarDate` with no time in it: `7d`, `2w`, `1m` would be three spellings of a unit the data
  does not carry, and a month has no fixed length to spell.
- **`week-start`** - the Monday of the week the view is evaluated in.

`week-start` earns its place because `today-7` is not «this week» and the difference is not
pedantic: read on a Friday, `today-7` reaches back into the previous Friday and puts last week's
finished work into a review of this one. The app already computes the Monday - `WeekPlan` does it
as `(DateEntry.weekday(of: day) + 5) % 7` - so this is a **name for arithmetic that exists**, not
new arithmetic. Monday and not Sunday, because that is the week the rest of this app draws
(ADR-0013 §D4, and the weekday row of `MonthView`).

Refused, and each with its reason rather than a shrug:

- **`today+N`, a bound in the future.** `+` is not in the lexer's word set, so admitting it
  widens the token grammar - the one part of this parser that is currently unambiguous about what
  a word is. And the natural forward-looking question is not about `date` or `modified` at all,
  it is *«what falls due in the next thirty days»*, which needs `deadline.next` to be comparable
  and it is not. When that restriction is lifted, `+` arrives with it and with a question to
  justify it. Building it now would be widening the alphabet for a case nobody has.
- **`month-start`.** Symmetry with a monthly review nobody has asked for. It costs one line the
  day somebody does.
- **Named periods - `this-week`, `last-month`.** They read well and they are ambiguous exactly
  where it matters: does «this week» include today, does it start on Monday or on Sunday, is
  «last month» the previous calendar month or the last thirty days. The ambiguity would live in
  code, invisible from the block. `week-start` says the one thing it means, and `today-7` says
  the other one.
- **A general expression language.** `text()` is the precedent: an escape hatch moves every
  future question from this document into the user's block, where it cannot be reasoned about.

**D3. `today` is a parameter, never a clock read at the bottom of the call stack.**

`ViewEvaluator.evaluate` takes the day - defaulted to `.today`, so the three existing call sites
are unchanged - and threads it to the comparison. `ViewFilter` never calls `Date()`.

This is the shape the rest of the codebase already uses and for the same reason:
`IndexSnapshot.tasks(for:on:)` takes its day, `DateEntry` takes its calendar. A test that cannot
fix the day is a test that fails on one day of the year and passes on the other three hundred and
sixty-four, which is precisely the class of defect the UI suite handed over on 2026-08-21 - an
assertion that turned out to be measuring somebody's afternoon appointment. A grammar feature
about *now* is the last place to acquire another one.

Which today: the machine's, in its own time zone, which is the decision `CalendarDate(_:in:)`
already made for the whole app.

**D4. An open view re-evaluates when the day changes, and the mechanism is an observation rather
than a timer.**

`NSCalendarDayChangedNotification` - verified in the macOS 26.5 SDK header rather than recalled -
is posted when the system day changes, and posted on wake when the Mac was asleep for it, once
however many days were skipped. The pane that hosts views observes it and re-evaluates, in the
same shape `EventKitStore` already observes `EKEventStoreChanged` and
`NSApplication.didBecomeActiveNotification`.

**No periodic work is introduced**, and the distinction is the whole reason this is affordable:
nothing wakes up to check the time, something is told when the time changed.

Two limits stated rather than discovered later. The header says there is **no guarantee the
notification is timely** - «same as with distributed notifications» - so this is *at the day
change*, not *at 00:00:00*. And the definition of a day follows `Calendar.current`, so a machine
whose time zone moves gets the notification for that too, which is correct and worth knowing.

The alternative considered and refused: leaving it, with a refresh as the remedy. Rejected
because a view is read to answer a question about now, and one that answers about yesterday
without saying so is the same silent staleness §D1 refuses in a block - drawn instead of typed.
The cost of the fix is one observer, and §D7's existing rule already re-evaluates on open and on
explicit refresh, so this only closes the window where neither happens.

**D5. Nothing is written into the file, and the connectors resolve it where they run.**

The block's text does not change and nothing is stamped into it. `perg` and `pergamenum-mcp`
evaluate the same blocks with the same code, so `today` there is the day of the call - for a
model asking over MCP, the day the request was made. A saved query asked twice on two days giving
two answers is not a defect; it is what a saved query is.

The alternative refused, and it is the trap worth naming: substituting the date at note creation,
the way `NoteTemplate` substitutes `{{date}}`. That is right for a note *generated* from a
template and wrong for a query, and afterwards **the two are indistinguishable in the file** -
`modified >= 2026-08-17` looks the same whether a person typed it meaning that Monday or a
template froze it there. A frozen bound that looks like a chosen one is worse than no feature.

## Consequences

- **The grammar grows for the second time and the rule governing it is unchanged.** One term, an
  argument, a reason, a version. This ADR is the record of the second; a third should read like
  this one or not happen.
- **The weekly review loses its workaround.** The four blocks in `SampleViews` stop ordering by
  `modified` as a substitute for asking about a week, and the paragraph in the template that
  explains why the question could not be asked comes out. `PG-032` closes with that edit, not
  with the parser.
- **A view's result is no longer a function of its text alone.** Nothing caches view results
  today. If anything ever does, the day is part of the key, and this sentence is why.
- **The app acquires its first observer that is about the clock rather than about the vault.**
  Two already exist for EventKit, so the shape is not new; what is new is that a note nobody
  touched can change what a view says. That is correct - the question moved, not the answer -
  and it is the one thing about this feature that will look like a bug the first time it is seen.
- **Obsidian is unaffected.** The block is still an inert fenced block in an ordinary note, and
  the file is still a file. Principles 1 and 4 are untouched, as they were by ADR-0009.
- **The tests can fix the day**, so this ADR does not add a test that fails on Mondays. `D3` is
  what buys that, and it is the reason `D3` is a decision instead of an implementation note.
