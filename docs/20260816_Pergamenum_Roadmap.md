# PERGAMENUM — Roadmap v2 (Craft parity, on Pergamenum's terms)

> Written 2026-08-16, after a full read of Craft's help centre, marketing site and
> comparison pages. Subordinate to `docs/20260811_Pergamenum_SpecApp.md` (v2.2): where
> this roadmap and the spec disagree, the spec wins until the amendment listed in §6 is
> applied to it.

## 0. The four decisions this roadmap rests on

Taken by Stefano on 2026-08-16, before a line of it was written.

1. **The binding principles win; the feature adapts.** No network call is added to the
   app. Nothing stops being a readable file. Web publishing becomes local static HTML
   export, AI stays outside the app behind `perg` and `pergamenum-mcp`, structured data
   is computed from files rather than stored in a second schema.
2. **Collections are query views over existing files**, not a database. No new
   frontmatter key, no sidecar record store. A view is a saved query rendered as a
   table, a board, a gallery or a calendar.
3. **All four work areas are wanted** — capture, editor, planning, organisation — so
   this document sequences them instead of choosing between them.
4. **Three workflows are optimised for**: work (clients, offers, projects), personal
   knowledge and research, and daily planning in a GTD shape. Personal life admin is
   served incidentally, never designed for.

## 1. What Craft actually is, feature by feature

Compiled from `support.craft.do` (the complete page list came from their `llms.txt`),
`craft.do` and `craft.do/it/compare`. Every row carries a verdict: **adopt** (build it,
adapted where needed), **have** (Pergamenum already does this, sometimes better),
**reject** (with the reason).

### 1.1 Write and edit

| Craft | Pergamenum | Verdict |
|---|---|---|
| Everything is a block; a block with children becomes a page; group/ungroup with Cmd+G | Notes are files, folders are the hierarchy | **adopt, adapted** — the analogue of a subpage is transclusion `![[note]]` and `![[note#section]]`, which keeps every piece addressable on disk |
| Slash menu (`/`) with ~80 commands across 12 categories | Nothing. Every command is a menu item or a shortcut | **adopt** — the single highest-value editor feature; discovery without leaving the keyboard |
| Markdown shortcuts while typing | Styled source: syntax stays visible, styling is applied (SPEC §5) | **have** |
| Toggles (collapsible blocks) | — | **adopt** — as folding of a heading section in the editor, plus `> [!note]-` callout folding in reading view |
| Formatting toolbar on selection | — | **adopt, small** — a floating bar over a selection, tokens only |
| Find and replace, in document | Global search only (Cmd+Shift+F) | **adopt** — Cmd+F / Cmd+Alt+F inside a note, with regex |
| Surround selection (brackets, quotes) | — | **adopt, trivial** — falls out of the editor work |
| Spell check, 34 languages | — | **adopt, trivial** — `NSTextView` gives it for free, it only needs enabling and a setting |
| Emoji insertion via `:` | — | **adopt, small** — but never in the UI chrome, only in note content |
| Date badges (`/today`, `/tomorrow`, date & time) | Date markers exist in task syntax | **adopt** — as slash commands writing `>`/`!` dates and plain dates |
| Subscript and superscript | — | **reject** — not CommonMark, would not survive a round trip through Obsidian |
| Code blocks, 30+ languages highlighted | Fenced blocks, unstyled | **adopt** — syntax highlighting in both the styled source and the reading view |
| Math formulas (LaTeX) | — | **defer** — needs a typesetter; no webview (SPEC §14). Candidate: render to an image via a local engine, or leave the fence unstyled. Not worth a milestone |
| Mermaid diagrams | — | **reject** — Mermaid is JavaScript. A diagram belongs on the Workspace canvas, which is the better tool and already exists |
| Tables with formulas, sorting, cell formatting | GFM tables, read and write | **adopt, partial** — sorting and alignment yes, formulas no: a formula in a markdown table is a value nobody else can read |
| Media with automatic layout, Unsplash, Image Playground | Images embed and render; drag-and-drop copies into the vault | **have** for images; **reject** Unsplash and Image Playground (both are network) |
| Files and links, rich previews fetched from the web | `.eml` cards, URI cards per scheme, embedded files | **have**, and **reject** the fetch: a preview that phones the site out is exactly the call principle 2 forbids. Local enrichment only (file type, size, favicon if already on disk) |
| Whiteboards | The Workspace, JSON Canvas 1.0, round-trips with Obsidian | **have**, better |
| Drawings (Apple Pencil) | SVG drawing tool on the canvas | **have** for the Mac; Pencil is an iPad question |
| Styling: fonts, colours, backgrounds, cover images, cards, saved presets | Full DTCG token theming, light and dark | **adopt, narrowly** — a per-note accent and an optional cover image, both written as frontmatter-free companion state in `.pergamenum/`. **Reject** per-note fonts and backgrounds: they would defeat the design system and the token rule |
| Templates: gallery, custom, `/template`, daily-note template | Daily note template mentioned in SPEC §8.1, never built | **adopt** — templates as real notes in `Templates/`, with `{{date}}`, `{{title}}`, `{{cursor}}` placeholders |
| Version history, hourly snapshots, cloud, 7–180 days by plan | `WriteJournal` covers connector writes only | **adopt, adapted** — local snapshots in `.pergamenum/versions/`, disposable, never the source of truth |

### 1.2 Organise and find

| Craft | Pergamenum | Verdict |
|---|---|---|
| Collections: 21 typed fields, table / gallery / kanban views, filter, sort, group, relational fields | — | **adopt as query views** (decision 2). Fields are derived, never stored |
| Tags, nested one level with `/` | Flat namespaced tags, `^(client\|competitor\|project\|type\|topic\|status\|area\|source)-…$`, closed (SPEC §4.4) | **have**, and **reject** the `/` nesting — the prefix *is* the hierarchy. What is missing is the browser, below |
| Tag view, pinned tags in the sidebar, multi-tag narrowing, rename across the vault | Tags are indexed and searchable; no browser | **adopt** — a tag pane grouped by namespace, pinnable, with rename-across-vault (a real write, journalled) |
| Search: full text, `"phrase"`, `-exclusion`, `regex:`, ranking by recency and starring | Full text with `tag:`, `path:`, `task:open`, `"phrase"` | **adopt the missing operators** — `-term`, `regex:`, `is:starred`, `linked:`, `orphan:` |
| Quick Open (Cmd+O) with recents, starred, daily note | Quick switcher with fuzzy match on titles and aliases | **adopt the extras** — recents, starred, daily note, and actions ("create note named X") |
| Search inside a document | — | folded into find and replace above |
| Starred documents | — | **adopt, small** — starred state lives in `.pergamenum/`, not in frontmatter (closed schema) |
| Tabs | One note at a time | **adopt** — tabs and a split view; a research session is two notes side by side |
| Table of contents / outline in the sidebar | — | **adopt** — headings and subpages, click to scroll, drag to reorder a section |
| Spaces, Teams, Shared with me | One vault at a time, recents list | **reject** — a space is a vault; multi-vault windows are the answer if it ever hurts |
| Links and backlinks, block links, unlinked mentions | Wikilinks, backlinks, unresolved links, `related` with reason and symmetry | **have**, and better. **Adopt** two gaps: block/heading links `[[note#heading]]` and **unlinked mentions** (a note whose title appears as plain text elsewhere) |
| Deeplinks | `pergamenum://` with eight routes | **have** |

### 1.3 Plan and do

| Craft | Pergamenum | Verdict |
|---|---|---|
| Task Inbox: tasks attached to no document | "Inbox" view = tasks with no date and no project, still living in a note | **adopt, adapted** — a real capture target `00 Inbox/Inbox.md`, so a captured task has a home on disk from the first second |
| Three dates per task: schedule, deadline, reminder | `>date`, `!date`, `@remind(...)`, all with optional time (ADR-0004) | **have** |
| Repetition rules | `@repeat(n/N)` finite; infinite delegated to Apple Reminders | **have** |
| Four tabs: Inbox, Today, Upcoming, All, with grouping and sorting | Five views: Inbox, Oggi, Prossimi, Per progetto, Tutti | **have**, plus **adopt** the sort and group controls (by note, by schedule, by deadline, by project; compact and expanded density) |
| Pinned documents in the All tab, up to 20 | — | **adopt, small** — pinned notes at the top of Tutti |
| Rollover: unfinished tasks appear on today automatically | Explicitly rejected in SPEC §7.3 ("nessun rollover automatico", NotePlan model) | **spec change requested** — as an *option*, default off. Reason in §6 |
| Calendar view unifying daily notes, tasks and events | Today view with a timeline, mini month calendar, Diary pane | **adopt** — a week and a month view, one surface, drag a task onto a day to schedule it |
| Event notes become subpages of the daily note | — | **adopt** — "Note for this event" creates `Calendar/YYYYMMDD-<event>.md` and links it from the day |
| Reminders and notifications | UserNotifications + two-way Apple Reminders | **have** |

### 1.4 Capture and integrate

| Craft | Pergamenum | Verdict |
|---|---|---|
| Quick Entry, Ctrl+Space **from any app**, four destinations, markdown in → blocks out, Schedule and Deadline buttons | Quick capture exists but only when Pergamenum is frontmost | **adopt** — the largest single gap in daily use |
| Web Clipper browser extension | — | **adopt, adapted** — a bookmarklet and a Shortcut that build a `pergamenum://capture` URL with the selection, title, URL and date. No extension, no native messaging host, no server |
| Email to Craft (a unique address per space) | `.eml` drag-and-drop, `message://` links | **adopt, adapted** — a Mail rule plus a Shortcut that writes into the inbox note; the address version is a server |
| Readwise sync | — | **adopt, adapted** — import a Readwise/Kindle **export file**, one note per book, highlights as blocks |
| Apple Shortcuts, Siri, Back Tap | URL scheme only | **adopt** — an `AppIntents` provider: create note, append to today, add task, open route, run a saved view |
| Widgets | — | **defer** — a widget for today's tasks is nice and cheap once AppIntents exists |
| Craft REST API | `perg` CLI and `pergamenum-mcp` over stdio | **have**, and **reject** the REST server: it opens a socket |
| MCP for Claude and ChatGPT, paid plans | `pergamenum-mcp`, twelve read tools and eight write tools, dry-run by default | **have**, and it is the feature Craft charges for |

### 1.5 Share, publish, AI

| Craft | Pergamenum | Verdict |
|---|---|---|
| Export to PDF, Word, Markdown; folder and space export | Export a note as Markdown, HTML or PDF | **adopt the scope** — export a folder or the whole vault, with links rewritten |
| Publish to the web, custom domain, analytics, branding, password | — | **adopt, adapted** — export a folder as a **static HTML site** into a chosen directory, wikilinks resolved, tokens as CSS. What happens to that directory is not the app's business |
| Real-time collaboration, comments, teams, permissions | — | **reject** — out of scope v1 and against principle 2 |
| AI Assistant, smart search, document review, custom prompts, OCR on images and PDFs, bring your own key | The vault is reachable by any assistant through MCP and the CLI | **have, differently.** The gap worth closing is not an in-app chat: it is that a model cannot yet rename, move or trash a note, and that prompts live nowhere. Both are addressed in M13 |

## 2. The shape of the gap

Craft is a **document** app that grew tasks and a calendar. Pergamenum is a **vault** app
that already has tasks, a calendar, a canvas and a machine interface. Sorted by what it
costs Stefano every day, the real gaps are:

1. **Capture is not global.** Everything Craft does well starts with Ctrl+Space from
   inside another app. Pergamenum's capture requires Pergamenum to be in front, which is
   exactly when capture is not needed.
2. **The editor has no command surface.** Every capability is behind a menu, so
   capabilities that exist go unused.
3. **Nothing aggregates.** A project is a tag and a note; there is no board of open
   client work, no gallery of PDFs, no table of notes by status.
4. **Navigation is single-file.** One note at a time, no tabs, no outline, no tag
   browser, no starred.
5. **A day is well served; a week is not.** The Today and Diary panes are strong, the
   month calendar is a date picker, and there is no week.

## 3. Milestones

Same contract as SPEC §13: binding order, each milestone yields a usable app, none
starts before the previous acceptance criterion is verified by hand.

### M7 — Cattura globale

*The panel that works when Pergamenum is not the app in front.*

- A global hotkey (default Ctrl+Space, remappable through the existing `ShortcutStore`)
  registered with `RegisterEventHotKey`, which needs no Accessibility permission, unlike
  a global `NSEvent` monitor.
- A borderless `NSPanel` at `.floating`, non-activating, that appears over the frontmost
  app and returns focus on dismiss. `ComposerTextField` (ADR-0003 D5), not `TextField`.
- Four destinations in one control: **new note** (folder chosen, conformant frontmatter
  generated), **task to the inbox**, **append to today's daily note**, **append to a
  chosen note**. The destination is remembered per launch.
- Markdown in the panel arrives as markdown: headings, lists, tasks and quotes are
  written verbatim, one line per line. No block conversion, because there are no blocks.
- Schedule and Deadline buttons on the task destination, reusing `TaskDatePanels`.
- Unsent text survives a dismiss for sixty seconds.
- `pergamenum://capture?dest=…&text=…&schedule=…&deadline=…` as the same code path, so a
  Shortcut, a bookmarklet and a Mail rule all reach it.
- A menu-bar item (`NSStatusItem`, hideable) with: capture, today, inbox, last note.

**Acceptance:** with Pergamenum in the background and Safari in front, Ctrl+Space
captures a task with a deadline into `00 Inbox/Inbox.md`, and the task appears in
Attività without touching the app window.

**Touches:** new `Sources/Features/Capture/`, `Core/URLScheme/PergamenumURL.swift`,
`App/PergamenumApp.swift`, `Connector/VaultWrites.swift` (the capture write belongs in
the connector, so `perg capture` gets it for free).

### M8 — Il menu comandi e l'editor

*Everything the app can do, reachable from the caret.*

- **Slash menu** on `/` at the start of an empty line or after a space, filtered as you
  type, driven by the existing `ShortcutCommand` catalogue plus editor-only entries:
  headings, lists, task, quote, callout, code fence with language, table (2×2…9×9),
  separator, date, `[[wikilink]]`, `![[embed]]`, template, "open in canvas", "related
  note".
- **Find and replace** inside the note: Cmd+F, Cmd+Alt+F, regex, in-selection, count.
- **Outline pane**: headings and embedded notes, click to scroll, drag to move a whole
  section (a real text rewrite, journalled).
- **Heading folding** in the editor and callout folding in the reading view.
- **Code fence syntax highlighting**, in both the styled source and the reading view,
  from a small local grammar set (swift, python, js, json, yaml, sh, sql, md).
- **Transclusion**: `![[note]]` and `![[note#heading]]` render inline in the reading view
  and are navigable in the editor. This is Craft's subpage, done in a way Obsidian reads.
- **Block links**: `[[note#heading]]` completes on `#` after a note name.
- Floating format bar on selection; surround selection; emoji on `:`; spell check with a
  language setting.

**Acceptance:** a note is written end to end — heading, callout, task with a date, code
block, table, embedded note — using only `/` and the keyboard, and Obsidian opens the
same file unchanged.

**Touches:** `Features/Editor/*`, `Core/Markdown/*`, `Core/Shortcuts/*`.

### M9 — Template e cronologia

*A structure worth repeating, and a way back.*

- Templates are notes in `Templates/` (folder configurable). Placeholders `{{date}}`,
  `{{date:FORMAT}}`, `{{title}}`, `{{time}}`, `{{cursor}}`, `{{selection}}`.
- New note from template, `/template` to insert into the current note, and a **daily
  note template** setting, which SPEC §8.1 already promises and nothing implements.
- Templates ship for the three optimised workflows: meeting note, client note, project
  index, reading note, weekly review, daily note.
- **Local version history**: before every write through `VaultSession.write`, the prior
  content is snapshotted into `.pergamenum/versions/<hash>/<timestamp>.md`. Retention by
  count and age, both settings, default 50 versions and 90 days. A pane lists versions
  with a `UnifiedDiff` and restores one. Snapshots are disposable: deleting the folder
  loses history and nothing else.
- Craft's hourly snapshot is the wrong granularity for a file-backed app; per-write is
  cheaper and truer.

**Acceptance:** today's daily note is created from a template with the date resolved; a
paragraph deleted an hour ago is found in the version list and restored.

**Touches:** `Vault/VaultSession.swift`, `Vault/WriteJournal.swift` (the two stores share
a mechanism and must not diverge), `Features/Editor/`, new `Features/History/`.

### M10 — Navigazione e organizzazione

*Two notes at once, and a way through the tags.*

- **Tabs** in the note pane, with Cmd+T…Cmd+9, reopen-closed-tab, and drag to reorder;
  and a **split view**, two notes side by side, or a note beside its canvas.
- **Tag browser**: a pane grouped by namespace (`client-`, `project-`, `topic-`…), counts,
  pinnable to the sidebar, multi-tag narrowing, and rename-across-vault as a journalled
  write with a diff shown first.
- **Starred notes**, state in `.pergamenum/starred.json` — the frontmatter schema is
  closed and this is app state, not content.
- **Quick Open**, extended: recents, starred, daily note, "create note named X", and
  jumping to a heading inside the chosen note.
- **Search operators** completed: `-term`, `regex:`, `is:starred`, `linked:<note>`,
  `orphan:`, `modified:` ranges. Not `created:` — the index has no creation date and
  inventing one is a schema decision, not an operator (ADR-0009 §D2). Saved searches feed
  M11.
- **Unlinked mentions** in the backlinks pane: notes where this note's title or an alias
  appears as plain text, with one-click linking.

**Acceptance:** a client note and its project index open side by side in two tabs; the
tag pane narrows `client-*` plus `status-aperto` to a working list; an unlinked mention
is turned into a wikilink from the panel.

**Touches:** `Features/Editor/VaultBrowser*`, `Features/Search/`, `Index/`, `App/`.

### M11 — Viste (le Collections, fatte sui file)

*The aggregation layer. This is the milestone that changes what the app is for.*

A **view** is a saved query with a renderer. It is stored as a real note containing a
fenced block, so it lives in the vault, is readable in Obsidian as a code block, and
travels with the files:

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

- **Query language**, deliberately small: `path()`, `tag()`, `linksTo()`, `linkedFrom()`,
  `task()`, `has()`, `created`/`modified`, `frontmatter.date`, boolean operators. Every
  term resolves against `.pergamenum/cache.db`, so a view is index-speed and rebuildable.
- **Fields are derived, never stored**: title, path, folder, tags, the four frontmatter
  keys, `modified`, size, links, backlinks, open/done task counts, next deadline and next
  scheduled date, unresolved links. The closed list is in ADR-0009 §D2, and it matches
  `StoredRecord` field for field. No new frontmatter key anywhere — decision 2.
- Two fields do **not** exist today and are named rather than discovered: `created` (the
  index stores `modifiedAt` only) and `embedTargets` (`NoteStore.linkTargets` filters
  `![[...]]` out on purpose). The gallery needs the second, so M11 bumps
  `IndexCache.schemaVersion` to 2 exactly once, and that is the only schema change the
  milestone may make.
- **Renderers**: table (sortable columns), board (grouped by a tag namespace), gallery
  (thumbnails from `ThumbnailStore`, which already exists for PDFs), calendar (by
  frontmatter date or by task dates), list.
- **The board writes back.** Dragging a card between columns rewrites the `status-*` tag
  in that note, through `VaultSession.write`, journalled, undoable. This is the one place
  a view is not read-only, and it is what makes a project board usable.
- Views are embeddable in any note, so a project index page shows its own open tasks and
  its own documents.
- Ships with views for the three workflows: **Clienti attivi** (board by status),
  **Progetti** (table with open-task counts and next deadline), **Letture** (gallery),
  **Note orfane**, **Scadenze** (calendar).

**Acceptance:** a project index note embeds a board of its client notes; dragging one
card from "in corso" to "consegnato" rewrites the tag in the underlying file, and
Obsidian shows the change.

**Touches:** new `Core/Query/` (pure, so both connectors compile it), new
`Features/Views/`, `Index/IndexCache.swift`, `Connector/VaultReads.swift` (a view must be
runnable from `perg view run` and from MCP — that is the point of `Sources/Connector/`).

### M12 — La settimana

*The day is well served; the week is not.*

- **Week view** and **month view** beside the existing Today: events from EventKit,
  scheduled tasks, deadlines, daily notes, time blocks, on one grid.
- Drag a task onto a day to set `>date`; onto an hour to set the time and create a block.
- **Task view controls**: group by note / project / schedule / deadline, sort, compact and
  expanded density, pinned notes at the top of Tutti.
- **Optional rollover** (see §6): a setting, default off, that surfaces yesterday's
  unfinished scheduled tasks in Today with a distinct marker and a one-key "move to
  today" that rewrites `>date` in the source file. Nothing moves without a keystroke.
- **Event notes**: from an event in the timeline, "Nota per questo evento" creates
  `Calendar/YYYYMMDD-<slug>.md`, links it from the daily note, and stamps the attendees
  and time in the body.
- **Weekly review**: a template plus a view — what was done, what slipped, what is
  unscheduled, which projects moved.

**Acceptance:** a week is planned by dragging six tasks onto days; the event note for
Thursday's meeting is created from the timeline and is reachable from both the day and
the event.

**Touches:** `Features/Today/`, `Features/Tasks/`, `Calendar/`, `Features/Views/`.

### M13 — Il vault e il modello, per intero

*Close the connector's remaining gaps rather than build a chat panel.*

- `NoteFileOperations` (rename, move, trash) brought under `VaultSession.write` so the
  journal covers a link rewrite across many notes, then exposed as `note rename|move|
  trash` in both connectors. This is the open item from the last handoff and the reason a
  model cannot yet reorganise a vault safely.
- `view run`, `template apply`, `capture` and `version list|restore` in both connectors.
- **Prompts live in the vault**: `.pergamenum/prompts/*.md`, exposed as MCP prompts, so
  "write the weekly review", "extract the actions from this meeting note" are versioned
  files rather than habits.
- **Static site export**: a folder or the whole vault to HTML in a chosen directory,
  wikilinks resolved to relative paths, tokens emitted as CSS, an index page, no network
  and no analytics. Craft's publishing, minus the server.
- **Import**: Readwise and Kindle export files, Apple Notes export, Bear, and a plain
  markdown folder, all through `Core/Conventions/ImportNaming.swift`.
- **AppIntents**: create note, append to today, add task, open route, run a view — which
  gives Shortcuts, Siri and Spotlight actions in one implementation, and a widget later.

**Acceptance:** `perg note rename` rewrites every wikilink in the vault and `perg journal
undo` puts all of them back; a folder exports to a browsable local site.

**Touches:** `Vault/NoteFileOperations.swift`, `Sources/Connector/`, both front ends,
`App/NoteExporter.swift`, new `Sources/Features/Import/`.

## 4. Sequence and rationale

| # | Milestone | Size | Why here |
|---|---|---|---|
| M7 | Cattura globale | M | Feeds everything downstream; useless later, valuable immediately |
| M8 | Menu comandi ed editor | L | Makes existing capabilities discoverable; every later milestone adds commands to it |
| M9 | Template e cronologia | M | Templates are what make capture produce structure instead of debris |
| M10 | Navigazione e organizzazione | M | Tabs and the tag browser are prerequisites for using views seriously |
| M11 | Viste | L | The centre of gravity; depends on the index work and the search operators of M10 |
| M12 | La settimana | M | Planning depth reads better once views exist, because a week view is a view |
| M13 | Vault completo e connettori | M | Cleanup, import, export and the model's missing verbs |

Roughly two to three sessions each at the pace of the last week, M8 and M11 longer.

## 5. What is deliberately not built

Each with the reason, so it is not re-proposed in six months.

- **Real-time collaboration, comments, teams, shared spaces.** Principle 2, and out of
  scope in SPEC.
- **Hosted publishing, custom domains, analytics.** Replaced by a local static export.
- **A REST API.** `perg` and MCP cover it without opening a socket (ADR-0007).
- **Rich link previews fetched from the web, Unsplash, Image Playground.** Network.
- **An in-app AI chat panel.** The vault already speaks MCP; a second surface would
  duplicate `Sources/Connector/` and put a network call inside the app.
- **Mermaid.** JavaScript, and the Workspace is the better answer.
- **Nested `/` tags.** Forbidden by SPEC §4.4; the namespace prefix is the hierarchy.
- **Typed collection fields stored anywhere.** Decision 2; derived fields only.
- **Per-note fonts and page backgrounds.** They would defeat the token rule, which is a
  review gate in CLAUDE.md.
- **Multiple spaces in one window.** A space is a vault; open a second window.
- **Subscript and superscript.** Not portable markdown.

## 6. Amendments the SPEC needs

None of these are silent. Each must be applied to
`docs/20260811_Pergamenum_SpecApp.md` before the milestone that depends on it.

- **§5 Editor**: add the slash menu, transclusion `![[note]]` and `![[note#heading]]`,
  find and replace, the outline, heading folding, code highlighting.
- **§7.3 Behaviours — a reopened decision.** The spec rejects rollover on the NotePlan
  model: a task stays where it was scheduled and is highlighted. The stated reason to
  reopen: that rule assumes the day view is opened every day. When two days are skipped,
  a task scheduled for Monday is visible only by navigating back to Monday, and the
  Attività "Oggi" view shows overdue items without a way to move them in bulk. The
  amendment is narrow — **an off-by-default setting** that surfaces, never moves;
  rescheduling stays an explicit keystroke that rewrites the source file. The file
  format does not change and Obsidian sees nothing new.
- **§7.4 Task views**: grouping, sorting, density, pinned notes; and the Inbox becomes a
  real note (`00 Inbox/Inbox.md`) rather than a filter.
- **§8 Calendar**: week and month views, event notes as day subpages.
- **§12 Search and settings**: the new operators, saved views, tabs, starred, templates,
  version retention, capture settings.
- **New §16 Cattura**: the global panel, the URL route, the menu-bar item, AppIntents.
- **New §17 Viste**: the query language, the derived field list, the renderers, and the
  one write path (board drag → `status-*`).

## 7. ADRs to write

- **ADR-0008 — Global capture panel.** `RegisterEventHotKey` over a global `NSEvent`
  monitor (no Accessibility grant), a non-activating `NSPanel`, and why the capture write
  lives in `Sources/Connector/` rather than in the app.
- **ADR-0009 — Views are queries in files.** *Written 2026-08-16, status proposed:*
  `docs/adr/0009-views-are-queries-over-the-index.md`. Why a fenced block in a note beats
  a sidecar and beats extending the frontmatter; the closed field list; why the board's
  drag is the only write.
- **ADR-0010 — Local version snapshots.** Per-write rather than hourly; the relationship
  with `WriteJournal`; why the store is disposable and how that stays true.
- **ADR-0011 — Static export instead of publishing.** What is emitted, what is not, and
  why the app never uploads.
- **ADR-0012 — Rollover as a setting.** The reopening of SPEC §7.3, with the argument
  above recorded rather than assumed.

## 8. Risks

- **M11 is the one that can sprawl.** A query language grows without a stated boundary.
  The boundary here is: no user-defined fields, no computed columns, no formulas, and
  every term must be answerable from the existing index schema. If a view needs a new
  column in `cache.db`, that is a decision, not an implementation detail.
- **The slash menu and the completion code share a code path** that has already taken the
  app down once (a lone `#` on a line, `completionContext()`). M8 starts by putting that
  function under test with hostile input.
- **Tabs plus split view plus the existing `HSplitView` panes** is where UI tests get
  fragile, and the saved window state is the thing that breaks them (the sidebar-drag
  gotcha in PROJECT_BRIEF). Any new splitter needs a frame-based selector from day one.
- **A rename across the vault under the journal (M13)** is the highest-risk write in the
  project: many files, one atomic intent. It gets a dry-run diff over every affected file
  before it is offered.
- **Craft is a moving target and this analysis is a snapshot** of 2026-08-16. Nothing in
  the roadmap depends on Craft continuing to work the way it does today.
