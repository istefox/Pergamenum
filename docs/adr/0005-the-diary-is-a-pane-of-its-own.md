# ADR-0005: The diary is a pane of its own, with a live preview and a ten-minute grid

- Status: accepted
- Date: 2026-08-14
- Supersedes: nothing. Adds a seventh pane to SPEC §10's six, refines §11 (design
  system) for that pane, and takes a bounded exception to §14's ruling on live preview.

## Context

The app had two places that are about a single day and neither of them was a diary.
The Oggi pane is a plan: the daily note, the tasks due, and a `## Timeline` of blocks
that exist to be published to the Apple calendar. The Attività pane is a list of what
has to happen. Nothing recorded what actually did happen, hour by hour, in the words of
the person it happened to.

What was asked for is a journal: free markdown for the day, a rendered view of it that
does not require switching modes, and a column of hours from 06:00 to 20:00 where a
stretch of time can be blocked out, named, and annotated. Ten minutes is the unit -
10, 20, 30, and up through two or three hours. It answers to nothing outside the vault:
no EventKit, no publication, no sync.

Three things about the existing app made this a decision rather than a feature:

1. SPEC §14 rules out a live preview. The ruling is about the *editor*: hiding markdown
   syntax while it is being typed, which §5 and §7.1 both turn down in favour of
   "source visible with style applied". Reading mode (§6.5) is the other half, and it
   is a mode you leave the editor to enter.
2. The Oggi pane's time blocks may not overlap, on purpose: two blocks at one hour say
   nothing about what a *plan* looks like.
3. `ShortcutCommand`'s raw values are the keys of the overrides file, so the pane
   shortcuts are identity, not decoration.

## Decision

**D1. Diario is its own pane, not a section of Oggi.** A plan and a record answer
different questions and want different files. The Oggi pane keeps `## Timeline` in the
daily note and keeps its publish-to-calendar button; the Diario pane writes
`Diario/YYYYMMDD.md` and has no calendar in it at all. The folder is settable
(`diaryFolder`, default `Diario`) beside the daily one.

**D2. The editor and the rendering sit side by side, live, in one page.** This is not
the live preview §14 rules out: the source keeps every character of its syntax and its
styling, exactly as the Note pane's editor does, and the rendering is a second view of
the same text rather than a substitution inside the first. A toolbar picker collapses
either side for a person who wants only one. The rendering is
`MarkdownReadingView(takesFocus: false)` - the same renderer reading mode uses, told
not to take the keyboard, because a preview that takes focus takes the caret out of the
note the moment it is drawn.

**D3. Ten minutes is the grid, everywhere.** Starts and durations are snapped to it on
every path: the composer's pickers, a drag over empty time, a block dragged to a new
hour, a bottom edge pulled. The shortest block is ten minutes and the longest the
composer offers is eight hours. A time written by hand in the file is read as it
stands, whatever it says - the grid governs what the app produces, not what it accepts.

**D4. Blocks may overlap, and are drawn side by side.** The opposite of the Oggi pane's
rule, for the opposite reason: a day written down as it was lived has a call inside a
meeting in it. `DiaryLayout` groups blocks that touch into clusters and gives each the
leftmost free lane, which is what a calendar does.

**D5. 06:00 to 20:00, and further when the day asks.** The window is what was asked
for, but a block outside it must not be invisible, so the grid grows down to the
earliest start and up to the latest end. A day that only holds ordinary hours draws
exactly the fourteen that were asked for.

**D6. The section is markdown, and the prose and the section never touch.** The file
holds the day's text and then:

```
## Diario

- 07:00-08:30 Rassegna e posta [colore:giallo]
  Due articoli sul distretto.
- 09:00-11:30 Sopralluogo pressa 4
```

The editor edits everything *except* that section; the timeline owns the section and
nothing else. Neither can overwrite the other's work, which is the failure mode a
single buffer would have had. A line inside the section that is neither a block nor a
block's note is moved into the prose rather than dropped: it comes back above the
section instead of inside it, which is worse than where the user put it and much better
than gone.

**D7. It saves itself.** There is no Salva in the Diario pane. A block is written the
moment it changes; typing is written 600 ms after it stops, and flushed when the day
changes, when the pane goes away, when the app stops being frontmost, and when it
quits. A day nobody wrote anything on is never given a file: walking through a week
must not leave a week of empty notes behind.

**D8. The pane sits fourth and takes the sixth key.** `Ctrl+Cmd+6`, while Attività and
Conformità keep 4 and 5 with their positions moved down by one. Renumbering to close
the gap would rewrite the meaning of a binding the user may have changed, because the
overrides file is keyed by command name and the defaults are what an unchanged command
falls back to.

## Consequences

- A seventh pane is in the sidebar and in the Vista menu, and `Navigation.Pane` is no
  longer the five of SPEC §10. The spec is the older document here.
- Two files a day exist for a person who uses both panes: `Calendar/20260814.md` and
  `Diario/20260814.md`, same name, different folders. Setting `diaryFolder` equal to
  `dailyFolder` merges them and still works - the diary owns its section, the day view
  owns `## Timeline` - but neither section is readable beside the other for long.
- `MarkdownReadingView` grew a `takesFocus` flag. Reading mode passes nothing and keeps
  taking focus, which is right where it is the only thing on screen.
- `VaultBrowser`'s tag suggestions and its pasted-image import moved onto
  `VaultController`, since two editors now need both.
- A pre-existing crash came out on the way: offering the completion list from
  `textDidChange` re-entered itself, because the list inserts its first candidate as it
  opens and that insertion is another change. Typing `#` at the start of any line in
  any editor took the app down. Guarded, with a UI test that reproduces it.
