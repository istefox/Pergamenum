# ADR-0009: A view is a saved query over the index, written in a file

- Status: proposed
- Date: 2026-08-16
- Supersedes: nothing. Adds the aggregation layer of the roadmap
  (`docs/20260816_Pergamenum_Roadmap.md`, M11), which SPEC v2.2 does not describe.

## Context

Craft's Collections are the one feature of that app with no answer here: a set of typed
fields with table, gallery and kanban views over them. What they buy is aggregation - a
board of open client work, a table of projects with their next deadline, a gallery of
what is being read. Pergamenum can say what one note contains and what links to it, and
nothing at all about a hundred notes at once.

Three things constrain the answer before any design starts.

**The frontmatter schema is closed.** SPEC §4.3 fixes it at `date`, `tags`, `related`,
`aliases`, and §4.4 fixes tags as flat namespaced strings. A typed-field system in the
Craft sense needs somewhere to put `status`, `client`, `amount`, `deadline`; the two
places available are a fifth frontmatter key and a sidecar store, and both were rejected
on 2026-08-16 in favour of computing every field from what the files already say.

**Principle 1 says the file is the product.** A view that exists only in the app's
preferences is a view that disappears with the app, and cannot be committed, moved
between machines, or read by anything else.

**Principle 3 says the index is disposable.** Whatever a view reads, it must be
recomputable from a vault scan alone. That is a promise about the whole design, not about
the cache file: a view that could not be recomputed would make the index load-bearing.

The temptation this ADR exists to refuse is the one every query language meets a year in:
a computed column, then a formula, then a user-defined field, then a second schema nobody
chose and everybody now depends on.

## Decision

**D1. A view is a fenced block in an ordinary note.**

````markdown
```pergamenum-view
from: path("Clienti")
where: tag("client-*") and not tag("status-chiuso")
sort: modified desc
group: tag("status-*")
render: board
columns: [title, tags, modified, tasks.open, deadline.next]
```
````

It lives in the vault, it is a plain file, it is versioned with everything else, and
Obsidian renders it as an inert code block - which is the correct behaviour for a reader
that does not know how to run it. A view is therefore embeddable anywhere a note is: a
project index page carries its own board, and the "Viste" pane is a folder of such notes
rather than a separate kind of object.

The alternatives, both refused: a JSON file under `.pergamenum/` is app state and would
not travel with the notes it describes; a row in `cache.db` would make the disposable
index hold the only copy of something the user wrote.

The body of the block is YAML-shaped rather than YAML: seven keys, all optional but
`render`, parsed by hand. A block that does not parse renders as an error naming the line,
never as an empty result - an empty list is indistinguishable from a vault that lost its
notes, and that confusion has already cost this project an afternoon once.

**D2. Fields are derived from the index, and the list is closed.**

Everything a view can name is already in `StoredRecord` (`Sources/Index/IndexCache.swift`)
or is computed from the whole index in `IndexSnapshot`:

| Field | Source |
|---|---|
| `title` | `NoteRecord.title`, the file stem (naming.md 4.6) |
| `path`, `folder` | `relativePath` and its derived `folder` |
| `tags` | `frontmatter.tags` |
| `date` | `frontmatter.date`, the only date the schema carries |
| `aliases`, `related` | frontmatter |
| `modified`, `size` | `modifiedAt`, `byteSize` |
| `links`, `linkedFrom` | `linkTargets` and the `backlinkIndex` derived from it |
| `tasks.open`, `tasks.done`, `tasks.total` | `record.tasks` re-parsed by `TaskParser` |
| `deadline.next`, `scheduled.next` | the `!` and `>` dates of those tasks |
| `unresolved` | targets no note answers to (`unresolvedLinks()`) |

No user-defined fields. No computed columns. No formulas. A column is one of the names
above or the view does not parse.

Two fields a reasonable person will ask for do **not** exist, and saying so here is the
point of the table:

- **`created`.** The index stores `modifiedAt` and nothing else. Adding a creation date
  means a new field on `StoredRecord` and a bump of `IndexCache.schemaVersion`, which
  discards every cached row on first run. That is a decision, taken deliberately, not an
  implementation detail discovered while wiring a sort menu.
- **`embedTargets`.** `NoteStore.linkTargets` filters embeds out on purpose, so
  `![[file.pdf]]` and `![[foto.png]]` are invisible to the index. The gallery renderer
  needs them, so **M11 bumps the schema to 2 and adds them** - and it is the only schema
  change the milestone is permitted, stated in advance rather than at the end.

**D3. The language is small, declarative, and has no escape hatch.**

Seven keys: `from`, `where`, `sort`, `group`, `render`, `columns`, `limit`. The `where`
grammar is boolean combination of a closed set of terms - `path()`, `tag()`, `linksTo()`,
`linkedFrom()`, `task()`, `has()`, `date` and `modified` comparisons, `text()` - with
`and`, `or`, `not` and parentheses. Globs in `tag()` and `path()`; no regular expressions,
because a regex over a hundred notes is the global search's job and it already has them.

There is no way to write an expression that is not one of those terms. If a question
cannot be asked in this grammar, the answer is a new term in a later version with an
argument for it, not a general mechanism that makes every future question the user's
problem.

`text()` is the one term that reads the files: the index holds structure, not content
(`VaultSession+Search` says so in its own doc comment, and searches the files for exactly
this reason). It is allowed, because "notes that mention X" is a real question, and its
cost is stated in D7.

**D4. The query engine is pure, and lives in `Core/Query/`.**

Parsing and evaluation depend on Foundation alone, so the CLI and the MCP server compile
them - ADR-0007 §D2. Running a view is then a capability of `Sources/Connector/`
(`view list`, `view run`), never of `Sources/CLI` alone, which is the rule that keeps the
two front ends from diverging. A model can ask for the open-client board and get the same
rows the app draws, from the same code.

Renderers stay in `Features/Views/` and see only the evaluated result.

**D5. One renderer writes, and it writes one thing.**

Table, gallery, calendar and list are read-only. The **board** is not: dragging a card
from one column to another rewrites the `status-*` tag in that note's frontmatter, through
`VaultSession.write`, journalled like every other write, undoable, and visible to the
watcher as an ordinary external-looking change.

This is deliberate and bounded. A board that cannot be dragged is a report, and the
workflows this roadmap optimises for - client work, projects - are exactly where moving a
card is the natural gesture. The bound is that grouping by anything other than a tag
namespace produces a read-only board: dragging a card into a different `modified` value is
meaningless, and a renderer that silently did nothing on drop would be worse than one that
does not offer the gesture.

The write goes through the vocabulary check of §4.4 like any other tag write. Dropping a
card into a column whose tag is not in the vocabulary is refused with the reason, not
written and then flagged by the linter afterwards.

**D6. A view is recomputed, never stored.**

No materialised result, no cached row set, no "last known" list. The index is rebuilt from
the vault; a view is evaluated from the index. Deleting `.pergamenum/` costs a rescan and
loses nothing, which is principle 3 still holding after this feature exists.

**D7. Cost is bounded by when a view runs, not by what it may ask.**

A view evaluates on open, on an explicit refresh, and on a watcher change that touches a
note in its result set or its `from` scope - debounced, never per keystroke. A view using
`text()` reads every candidate file, which is the same work the global search already does
across the whole vault; measured on the real vault that scan is 150 ms for 77 notes with a
warm cache. If a vault ever grows to where that is felt, the answer is a content index and
a schema bump, decided then, with a number in front of it.

## Consequences

- **No new schema anywhere.** The frontmatter stays the closed four keys of §4.3, the tag
  grammar of §4.4 is untouched, and a vault with views in it opens in Obsidian exactly as
  it does today. This is the whole reason the design is shaped this way.
- **The index becomes an interface.** Until now `StoredRecord` was an internal
  optimisation and could change freely with a version bump. From M11 its fields are named
  in files the user wrote, so removing one breaks their views. Adding is cheap, removing
  is not, and `IndexCache.schemaVersion` no longer describes the only compatibility that
  matters.
- **M11 includes one schema bump**, to 2, adding `embedTargets` for the gallery. Every
  cached row is discarded on first launch after it and rebuilt - 150 ms, already measured.
- **The board is a new class of write**: a bulk-ish frontmatter edit driven by a gesture
  rather than by typing. It gets the same three guardrails as the connector's writes
  (§D6 of ADR-0007) in the one place it can: journalled, undoable, refused when the tag is
  not in the vocabulary. It does **not** get a dry-run diff, because a drag that asked for
  confirmation would not be a drag.
- **Views are notes, so they are indexed as notes.** A view note's own wikilinks are
  ordinary links and its own tags are ordinary tags; a view that filters on `tag("project-x")`
  and is itself tagged `project-x` will appear in its own results. That is correct - it is
  a note in the project - and it will look like a bug the first time it happens.
- **The query grammar will be asked to grow.** The refusal in D3 is worth only as much as
  the next three arguments it survives. Recording the reason here is the mechanism: a new
  term needs a question it answers that the existing terms cannot, written down, not a
  general-purpose escape hatch.
- **`perg view run` gives a model the aggregation layer too**, which is the first thing in
  this project that lets an assistant ask a question about the vault rather than about a
  note.
