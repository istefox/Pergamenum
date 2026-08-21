# ADR-0015: Back and forward move between places, and a place is derived rather than stored

- Status: accepted
- Date: 2026-08-21. Two questions were put to Stefano before this was written - what counts as
  a step, and where the arrows go given that one pane already owns a pair of chevrons. Both
  were answered as recorded in §D1 and §D5.
- Supersedes: nothing.
- Depends on: ADR-0012 (tabs, and the rule that what belongs to a note lives on the tab),
  ADR-0013 §D4 (the three scales share one anchor, which is why a scale is not a pane).

## Context

The window has nine panes, three day scales, tabs, a tag browser and a views pane, and nothing
that retraces a step. Following a wikilink, clicking a row in the Viste pane, or picking a day
out of the month grid all move you somewhere, and the only way back is to remember where you
were and go there again by hand.

The state that says where you are is already there and already derived. `RootView.currentItem`
computes the lit sidebar row from `Navigation.pane`, `DayController.scale` and the open note,
rather than storing a copy beside them - the comment on it records why: with two copies, the
toolbar's scale picker moved the week without moving the row. This ADR extends that same idea
one level: if *where you are* is a value computed from the window's state, then *where you were*
is a list of those values, and no new source of truth is introduced.

What makes this worth an ADR rather than a patch is that a history is the first thing in this
app that must distinguish a move the user made from a move the app made. Every other piece of
window state can be derived; this one cannot be, and §D4 is where that is paid for.

## Decision

**D1. A step is a place: a pane, plus that pane's anchor.**

```
enum Destination: Equatable, Sendable {
    case pane(Navigation.Pane)          // tags, starred, views, tasks, conformance, diary, workspace
    case note(String)                   // the Note pane, by relative path
    case day(CalendarDate, DayScale)    // Oggi, at a day and a scale
}
```

Three cases and not nine, because seven of the panes have no anchor here: the Viste pane shows
every view in the vault, «Preferite» shows every starred note, and going there is going to one
place. The two that do carry an anchor carry it because the pane means something different
depending on it - the Note pane on `Note/lavoro.md` is not the Note pane on `Note/settimana.md`.

**The Workspace is one place and not one per canvas, and that is a limit rather than a
judgement.** Its folder lives on a `WorkspaceController` held as `@State` inside
`WorkspaceView`, so it is view state and the window cannot read it without lifting the
controller to the app - a change with its own reasons and its own risks, which this feature
does not need in order to be useful. When that lifting happens for another reason, a
`case canvas(String)` is a small amendment to this section and to one `switch`. Recorded here
so the absence is a decision and not an oversight.

**The Note pane's anchor is the path, not the tab id.** Back means «that note», and a tab
closed and reopened is the same place; a tab id would make it a different one. A Note pane with
nothing open is `.pane(.notes)`, which is a real place - it is what the window shows before the
first note is opened.

**Not a step:** narrowing the tag browser, folding a section, toggling the inspector, changing
the reading mode, choosing a tab with `Cmd+1…9`. These change what a place looks like, not
which place it is. The tabs in particular already have their own way back and would otherwise
have two.

**D2. The history is derived by watching one value, not recorded at each call site.**

`RootView` computes `destination` the same way it computes `currentItem`, and observes it.
A push happens because the derived value changed, not because a method remembered to say so.

The alternative refused: calling `history.record(…)` from `openNote`, `focusTab`,
`choose(_:)`, `DayController.show`, the route handler, and the six other places that move the
window. That is eleven sites to keep correct and one to forget, and the one forgotten is
invisible - a history with a hole in it looks exactly like a history. It is also the shape
ADR-0012 already refused for the tab state, for the same reason.

The cost, stated plainly: an observer sees *that* the window moved, never *how*. §D3 is the one
place where that is not good enough, and it is handled by asking rather than by inferring.

**D3. Scrolling a day at a time is drift, and drift replaces rather than pushes.**

`Cmd+←` pressed five times in the week view must leave one entry, not five, or «back» becomes
«undo my last five keystrokes» and the button that goes back to the Note pane is six presses
away. But an explicit jump - «Vai a data», a click on a day in the month grid, the row in the
sidebar - is a step.

The observer cannot tell those apart, so `DayController` says which it is: `move(by:)` and
`moveSpan(by:)` mark their change as drift, `show(_:)` does not. This is deliberately a
property of the *gesture* and not a rule about the value: two ways of arriving at the same day
are two different intentions, and only the caller knows which one happened.

Drift replaces the top entry rather than being ignored, so going back from a day you scrolled
to returns to where you were before you entered the pane, with the pane's own day left where
you scrolled it. Ignoring it instead would put back one day and leave the other, which is a
history that lies about where it is taking you.

**D4. The history holds the destination it expects back, and that is what tells its own moves
from the user's.**

`goBack()` applies a destination to `Navigation`, `VaultController`, `DayController` and
`WorkspaceController`; those changes move `destination`; the observer sees it move and would
push it as a step. The history therefore remembers what it asked for, and the one change
matching it is absorbed rather than recorded.

**A value and not a boolean, and the difference is not stylistic.** The observer runs on the
next view update, not inside `goBack`, so a flag set and cleared around the apply would already
be false by the time the change arrived - the replay would be recorded as a step and back would
walk in place. Holding the expected destination makes the suppression self-clearing and
independent of when the observer runs, which is the only version of this that does not depend
on SwiftUI's update timing to be correct.

This is still a second copy of something, and this project's rule is that a second copy is a
bug waiting to happen. It is accepted here because what it represents is not window state at
all - it is *who is speaking* - and there is no property of the window from which that can be
read. If a replay lands somewhere other than what was asked for, the expectation is dropped and
the arriving destination is recorded as the truth: an entry whose place could not be applied is
not a place to sit and wait for.

**A destination that is no longer there is dropped and the step continues.** A note that was
renamed or trashed since it was visited is skipped, and back goes to the one before it.
`VaultController+Routes` already fixed this rule for a `pergamenum://` link that names a
missing note: a link that silently does nothing is worse than one that says the note has moved.
A history entry is the same kind of promise, and the same rule applies.

**D5. The arrows are one global pair at the leading edge, and the Oggi pane moves to make room.**

The pair sits where Finder and Safari put it - leading edge of the toolbar, present in every
pane, disabled when its stack is empty. `Cmd+[` and `Cmd+]`, which are the system-wide keys for
this and are both free here: `Cmd+Shift+[` is «Inserisci wikilink» and nothing binds the
unshifted brackets. Both commands go in the catalogue like every other, so they are remappable
in the same pane as the rest (ADR-0002).

**The Oggi pane's day navigators move from the leading edge to the centre, beside the scale
picker.** They are `chevron.left` and `chevron.right`, and the history arrows are
`chevron.backward` and `chevron.forward`, which in a left-to-right interface are the same two
glyphs: four identical chevrons in one strip, two of them meaning «a week» and two meaning
«a place». Moving the day pair next to the scale that gives it its meaning is the smaller
change - the picker is already the control that says whether a chevron is worth a day, a week
or a month.

**D6. The history is the window's, and it does not outlive it.**

Not written to disk, not restored at launch. The app opens a `Window` and not a
`WindowGroup`, so there is one, and one history. A restored history would promise a way back
to a place the vault may no longer contain, on a vault that may not even be the same one; the
recent-notes list already covers «what was I looking at yesterday», and it is a different
question.

Capped at 50 entries, oldest dropped. A number rather than unbounded growth, and large enough
that nobody reaches it deliberately.

## Consequences

- **`RootView` gains a second derived value beside `currentItem`, and they must not diverge.**
  Both read the same state; if a future pane grows an anchor, it grows one in both.
- **`DayController` learns about navigation.** It gains one property that exists for the
  history's benefit, which is a dependency pointing the way this codebase usually refuses.
  The alternative was routing the two gestures through a wrapper in the view, which puts the
  same knowledge in a worse place - a view that has to remember to say «this was drift» is
  §D2's rejected shape with a different name.
- **The Oggi toolbar changes shape**, and it is the visible part of this work. The chevrons and
  «Vai a data» keep their commands, their tooltips and their keys; only their placement moves.
- **Nothing is written to the vault.** Principle 1 is untouched: the history is window state,
  the same class of thing as which pane is showing.
- **A test can drive the whole model without a window.** `NavigationHistory` holds values and
  two stacks and nothing else; the applying is in the view. That split is what keeps the rules
  in §D1 and §D3 testable rather than only observable.
