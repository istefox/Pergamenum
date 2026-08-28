# CLAUDE.md

## Project

Pergamenum - a native, fully offline macOS app for personal use that merges three
tools into one: a local markdown note vault with wikilinks and backlinks (Obsidian
model), an infinite spatial canvas called **Workspace** where notes, PDFs, images,
emails and links float as resizable cards (VisualOS / JSON Canvas model), and an
integrated task and calendar system with daily notes, `>date` scheduling,
timeblocking and two-way EventKit integration.

The authoritative source is `docs/20260811_Pergamenum_SpecApp.md` (v2.2). Every
development task must be verified against it. `PROJECT_BRIEF.md` is the condensed
handoff; the spec wins on any conflict.

## Stack

- Language/runtime: Swift 6 with strict concurrency, SwiftUI on the macOS 26 SDK
- Platform: macOS 26 Tahoe or later, Apple Silicon. No compatibility fallbacks for
  earlier releases - current SwiftUI APIs are used directly.
- AppKit via `NSViewRepresentable` where SwiftUI is insufficient: the text editor
  (TextKit 2 in an `NSTextView`) and the canvas.
- Tooling: Tuist 4 for project generation, Swift Testing for tests, Xcode 26 toolchain
- Bundle identifier: `it.stefer.pergamenum` (lowercase, unlike the folder name).
  URL scheme `pergamenum://`. Automatic signing, team `T7H24G7BFW`. Developer ID
  distribution, no App Store, not sandboxed in v1. Apple Developer account:
  `istefoxdev@gmail.com`, name Stefano Ferri - this is the Apple ID notarization
  authenticates with, not the git commit address.
- Frameworks: PDFKit, EventKit, QuickLookThumbnailing, QuickLookUI, UserNotifications,
  GRDB (SQLite cache only)

## Binding architectural principles

1. **File over app.** Every piece of content lives as a readable file on disk (md,
   canvas, pdf, eml, svg). If Pergamenum disappeared, the data stays usable.
2. **Fully offline.** No network call in any feature. No server, no account, no
   telemetry.
3. **Rebuildable index.** The SQLite cache (links, backlinks, tasks, thumbnails)
   regenerates entirely from a vault scan. It is never the source of truth; deleting
   it loses nothing. Since ADR-0017 (`PG-004`) it lives with the rest of a vault's
   derived state in `~/Library/Application Support/it.stefer.pergamenum/vaults/<id>/`,
   not inside `.pergamenum/` - "delete `.pergamenum/` to reset the app" is no longer
   true, and the unit suite must always pass a temporary state base
   (`VaultState.processDefaultBase()` is test-aware; `VaultSession.init` still takes
   `stateBase` with no default) rather than resolving the real directory.
4. **Obsidian compatibility.** The existing "Labs" vault opens without conversion.
   `.canvas` files follow JSON Canvas 1.0 and round-trip with Obsidian. Extra
   properties use prefixed keys and are preserved, not interpreted.
5. **Harness conformance.** The naming, tag, frontmatter and wikilink conventions of
   the `harness-system` repo are the app's native schema, not an option. That repo
   stays the single source of truth: when a convention changes, the app config
   (`.pergamenum/vocabolari.json`) is updated, never the other way round.
6. **Delegated sync.** Future iPad sync happens by putting the vault in iCloud Drive.
   No proprietary transport.

Two schemas are closed and must not be extended: note frontmatter is exactly
`date`, `tags`, `related`, `aliases` (SPEC §4.3 - `title`, `status`, `type`, `draft`,
`version`, `author` are forbidden), and tags are flat namespaced strings matching
`^(client|competitor|project|type|topic|status|area|source)-[a-z0-9]+(-[a-z0-9]+)*$`
with no `/` nesting (SPEC §4.4).

## Design system

The UI is designed with Claude before implementation: every milestone screen gets an
approved mockup first. Aesthetic reference is Craft - minimal, generous whitespace,
hierarchy from weight and space rather than lines and boxes, SF Symbols, short
animations, no emoji in the interface.

Theming uses W3C DTCG design tokens in JSON under `.pergamenum/themes/`, loaded at
runtime by a `ThemeEngine` and exposed to views through the Environment. Light and
dark themes are both first class from day one.

**Binding rule: a view that uses a color or a font without going through a token
does not pass review.** No hardcoded colors in views, ever.

## Layout

```
Project.swift              Tuist manifest - single source of truth for targets
Tuist.swift                Tuist configuration
Tuist/Package.swift        SPM dependencies (GRDB to be added at indexing milestone)
Sources/                   App code, compiled into the Pergamenum target
Resources/                 Assets.xcassets and other bundled resources
Tests/                     Swift Testing suite, compiled into PergamenumTests
docs/                      Specification, ADRs and design notes
```

## Milestones

Order M0 to M6 is binding. Every milestone yields a usable app, and a milestone does
not start until Stefano has manually verified the previous acceptance criterion. See
SPEC §13 for the full table.

M0 design system, M1 vault + editor, M2 Workspace base, M3 PDF and email cards,
M4 tasks, M5 calendar, M6 URL scheme + conformance linter.

## Git conventions

- Workflow: GitHub Flow. `main` stays deployable, work happens on feature branches
  merged through pull requests.
- Commits: Conventional Commits v1.0.0 - `feat:`, `fix:`, `refactor:`, `docs:`,
  `test:`, `chore:`, `perf:`. English, imperative mood.
- Branches: Conventional Branch - `feature/`, `fix/`, `chore/`, `docs/`, `refactor/`
  followed by a short kebab-case description.
- Default branch: `main`. Never commit directly to it, never force-push.
- No branch protection is configured: the discipline above is the only guard.

## Commands

```bash
tuist generate --no-open                                                                        # regenerate after editing Project.swift
xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' build
xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' test
xcodebuild -workspace Pergamenum.xcworkspace -scheme perg -destination 'platform=macOS' build    # the CLI
xcodebuild -workspace Pergamenum.xcworkspace -scheme pergamenum-mcp -destination 'platform=macOS' build
scripts/release.sh                                                                              # signed, notarized, numbered build
scripts/install-cli.sh [dir]                                                                    # build both connectors Release and put them on the PATH
scripts/mcp-smoke.py [binary]                                                                   # drive the MCP server over stdio and check it
scripts/uitests.sh                                                                              # the UI suite, run the way it has to be - before every merge to main
```

## AI connector

ADR-0007. The vault is reachable without the app, so an assistant works on the files
through the app's own conventions and Pergamenum never opens a socket.

`VaultSession` owns an open vault with no user interface under it - settings,
vocabulary, index, and the single `write` every change goes through.
`VaultController` is the observable facade over it and keeps only what the views watch:
the editor buffer, the selection, the drafts, the route state. Anything that belongs to
the vault rather than to the window goes on the session, or the CLI cannot reach it.

`perg` and `pergamenum-mcp` are `.commandLineTool` targets compiling **the same files on
disk** as the app - `Sources/Core/**`, `Sources/Connector/**` and the pure files under
`Vault` and `Index`, named explicitly in `sharedSources` in `Project.swift`. Not a
framework, not a module: nothing is `public` and there is no second implementation of the
conventions to drift. Three consequences worth remembering:

- a new file under `Sources/Core` that imports SwiftUI **breaks both tool builds**, which
  is ADR-0001 §D1 enforcing itself. It found three inverted dependencies the first time
  it ran.
- a new file outside those globs that a tool needs must be added to `sharedSources` by
  hand.
- `Sources/CLI/**` and `Sources/MCPServer/**` are excluded from the app target, because
  each holds a `main.swift` of top-level code and a module may contain only one.

`Sources/Connector/` is where anything a connector does actually lives: `VaultAPI` holds
the payload shapes both encode, the reads, the writes, and the lookups that turn a string
into a date, a view or a task. **A new capability goes there, not into one of the two
front ends** - a read implemented in `Sources/CLI` is a read the MCP server does not have.
The front ends only translate: `Sources/CLI` reads flags and prints for a person,
`Sources/MCPServer` declares JSON schemas and answers over stdio.

Writes carry three guardrails (§D6) that live on `VaultSession` and are armed in one
place, `VaultAPI.arm`: `isDryRun` computes a write without performing it, `UnifiedDiff`
shows what would change, and `WriteJournal` records what was replaced so `undo` can put
it back - refusing when the file has moved on since. The app arms none of them: a person
editing their own note does not need an undo log. On the MCP side there is a second lock:
write tools are absent from `tools/list` without `--allow-write`, and each one's `dryRun`
defaults to **true**, so a model that omits it gets a diff instead of a change.

Registering the server, read-only first:

```bash
claude mcp add pergamenum -- /usr/local/bin/pergamenum-mcp --vault ~/Labs
```

The protocol layer has no unit tests and cannot have them without linking the MCP SDK
into the app; `scripts/mcp-smoke.py` drives a real server over stdio instead, and is the
thing to run after touching `Sources/MCPServer`.

Not in either connector, on purpose: EventKit, because TCC would attribute a command-line
tool's calendar access to the terminal that launched it.

## Versioning

`CFBundleShortVersionString` is `marketingVersion` in `Project.swift`, raised by hand.
`CFBundleVersion` is the number of commits behind HEAD, handed to the manifest as
`TUIST_BUILD_NUMBER` by `scripts/release.sh` - so Informazioni shows `1.0 (56)` and
`git rev-list --count HEAD` says which commit that was. An ordinary `tuist generate`
passes no number and the build is stamped `0`, which is what marks it a development
build; the release script refuses to ship one, refuses to run off `main` and refuses a
dirty tree, because a release you cannot come back to is not a release.

Never install a release build over `/Applications/Pergamenum.app` without asking, and
move the previous copy aside rather than deleting it.

## Working agreements

- **A `SwiftUI` tree that must participate in `List(selection:)` cannot use `DisclosureGroup`.** A
  `DisclosureGroup`'s label is not a row of the enclosing `List`, so a `.tag` on it satisfies no
  binding — the list lights nothing and swallows every click, and it fails silently (`RootView.swift`
  §D-noted trap: a `.badge` applied after `.tag` drops the tag the same way). Use flat recursive rows
  instead (`NoteListPane.swift`'s shape: a `@ViewBuilder` row plus, as a sibling, `if isExpanded {
  ForEach(children) {...} }`, chevron and depth drawn by hand) — see ADR-0024.
- Verify every change against `docs/20260811_Pergamenum_SpecApp.md`. If the spec and
  an instruction disagree, say so before writing code.
- SPEC §14 lists decisions already taken with their rationale. Do not reopen them
  without a stated reason.
- Never edit the `.xcodeproj` or `.xcworkspace` - they are generated. Change
  `Project.swift` and run `tuist generate`. The same applies to *git* operations that add
  or remove a file: `git stash`, `git checkout <branch>`, dropping a file - the generated
  project still lists what is no longer there and the build fails naming the compiler
  rather than the cause. Run `tuist generate` straight after.
- The pre-commit `weakening-scan.sh` reports every Swift Testing test as
  `zero-assertion-test`. Its body scanner skips lines starting with `#`, treating them
  as comments, and a Swift Testing assertion is `#expect(...)`. The findings are
  advisory and this one is systematically wrong for this stack; a genuinely
  assertion-free test still has to be caught by reading the diff.
- The pre-commit secret scanner's `assigned-secret` heuristic fires on this codebase's
  design-token code: it matches the keyword `token` followed by `:` or `=` and 16 or
  more identifier characters, which describes ordinary lines like `tokens =
  collector.tokens`. These are expected false positives, not credentials. Read each
  one before dismissing it - the rule still catches a real key assigned to a variable
  named `token`.
- `.claude/test-cmd` runs at the end of **every** turn, through the `Stop` hook in
  `~/.claude/settings.json`. It is therefore restricted to `-only-testing:PergamenumTests`,
  and that restriction is load-bearing rather than tidiness: with the whole suite in there,
  each turn ended by launching the UI tests, every `XCUIApplication().launch()` terminated
  the app the person at the keyboard was using, and each round left an instance alive
  holding the global hot key exclusively - so the next launch was refused. Two hours went
  into hunting an external culprit for something the assistant was doing itself. The UI
  tests still exist and are run deliberately, by hand.
- **The UI suite runs before every merge to `main`, through `scripts/uitests.sh`.** That
  rule is the price of the one above, and it was bought on 2026-08-21: three of the
  sixty-seven UI tests had been red since before the milestone about to be merged, and
  nothing had said so, because a suite outside `test-cmd` is a suite whose state is
  unknown between deliberate runs (`PG-033`). A merge is the one moment that is rare
  enough to afford twelve minutes and important enough to deserve them.
  The script is not a convenience wrapper: it kills stale instances first, refuses to run
  while a copy out of `/Applications` is open, prints the seconds beside each failure so a
  launch timeout is not mistaken for a defect, and cleans up after itself. Run it with no
  arguments for the whole bundle; an argument **replaces** the selection rather than
  adding to it, because two `-only-testing` flags are a union and would silently run
  everything.
- **A UI test that reads the machine's calendar is a test about somebody's diary.** The
  suite passes `-disableCalendar YES`, which keeps `EventKitStore` out of EventKit
  entirely. Every one of the thirteen files passes it, not only the one that needed it:
  `TimelineHoursUITests` checked that nothing was drawn past a 14:00 window, and the grid
  widens itself to reach an event outside that window by design, so the assertion failed
  on the afternoon there was a real meeting at 16:30. A new UI-test file wants the flag
  too.
- **A UI test must not find a control by the words on it.** Prose grows: the quick
  switcher's placeholder gained «, o a una sezione con #…» when Quick Open learned to jump
  to headings, and two tests spent days looking for a field that no longer answered to
  that name while the feature worked perfectly. Use `accessibilityIdentifier`, which is
  the part of a view that is a contract.
- **A UI-test instance outlives its run.** After `xcodebuild test`, one or more copies of
  the app are usually still running on a vault inside
  `~/Library/Containers/it.stefer.pergamenum.uitests.xctrunner/Data/tmp/`, which is not
  readable even with the sandbox disabled. Any manual check reaching a window that shows
  notes nobody created is reaching one of those. `ps -Ao pid,command | grep
  Pergamenum.app/Contents/MacOS` shows the vault each instance opened; start by reading it,
  not by trusting the window.
- **`-recentVaults` needs the plist array form.** The key holds `[String]`, so
  `-recentVaults /path` leaves `stringArray(forKey:)` nil and no vault is reopened at
  launch; `-recentVaults '("/path")'` works. The launch argument outranks the persistent
  domain, so a throwaway vault reaches a Debug build without touching what the installed
  app opens.
- **Finding the latest Debug build under DerivedData needs `-t`, not plain `ls -d`.** `tuist
  generate` stamps a fresh `Pergamenum-<hash>` DerivedData folder on each regeneration, and
  stale ones accumulate. `ls -d .../Pergamenum-*/Build/Products/Debug/Pergamenum.app | head -1`
  sorts alphabetically by hash, not by build time, and can silently hand you a stale build that
  still shows an already-fixed regression. Use `ls -dt .../Pergamenum-*/Build/Products/Debug/Pergamenum.app | head -1`
  (or `APP=$(ls -dt ... | head -1)`) to get the most recently built bundle before an `open -n`
  hand-check launch.
- Build and tests must pass before committing. A change that does not build is not done.
- Keep commits small and atomic, one logical change each.
- Never disable or delete a test to make a suite pass.
- UI language is Italian, with the architecture ready for English localization. Code,
  comments and commits stay in English.
- Update the "Status" section of PROJECT_BRIEF.md when a milestone is reached.
- New dependencies go through `Tuist/Package.swift` followed by `tuist install`, not
  through the Xcode UI.

## Decisions from the embed drag-resize chain (ADR-0019)

Drag-to-resize handle on the editor's drawn image/PDF embeds: `docs/adr/0019-embed-drag-resize.md`.

Key architectural decisions:
- **Size lives only in the note's own text**, read as Obsidian's native `|W` / `|WxH` suffix on
  the wikilink embed syntax. No new storage anywhere (no index field, no frontmatter, no table).
- **`EmbedAttachment: NSTextAttachment`** resolves the drawn size through
  `attachmentBounds(for:location:textContainer:...)`, which receives the live `textContainer` at
  layout time — never a value pushed in from outside, which would go stale on window resize.
- **The resize handle is painted inside the picture the attachment returns**, not a separate
  `NSView` — this keeps `frameForTextAttachment(at:)` (and therefore click hit-testing and the
  embed's accessibility frame from ADR-0018/PR #96) identical to the geometry without a handle.
- **The source-text rewrite happens once, at `mouseUp`**, through the same atomic
  `shouldChangeText`/`beginEditing`/`replaceCharacters`/`endEditing` mechanism the embed's
  Backspace deletion already uses — one undo step regardless of drag length.
- **A CommonMark `![alt](file.png)` embed gets no resize handle.** Obsidian's verified sizing
  syntax only exists for the wikilink form; this app's own writers only ever emit wikilinks, so
  no note this app created is affected.

Detail: `docs/adr/0019-embed-drag-resize.md`.

## Decisions from the Workspace/Task/Note integration chain (ADR-0021)

Workspace browser, Task↔Workspace/Note relations, and project sub-tasks: `docs/adr/0021-workspace-tasks-notes-integration.md`.

Key architectural decisions:
- **No new dependency, no schema, no index bump.** GRDB does not exist in this repo (MCP is the
  only third-party dependency) and there is no "task table" — `StoredTask` re-parses `rawLine`
  through `TaskParser.parse` instead of serializing fields, so a field added to `TaskItem` and read
  by the parser is free in the cache with no migration. `schemaVersion` stays 3.
- **`^[[...]]` is a Workspace marker only when its target ends in `.canvas`**, and stays an
  ordinary wikilink at the rename-rewrite level — the caret sits outside the `[[` range the
  rewriter already rewrites, so rename-updates-references comes for free with no new code.
- **"Progetti" is a sixth `TaskGrouping`, never a sixth `TaskView`** — the five task views are
  closed by ADR-0013 §D6; the grouping axis is the one left open for exactly this kind of addition.
- **Two protected interfaces declared** (`.claude/protected-interfaces`, ADR-0053): `IndexCache`'s
  `schemaVersion` and `VaultPayloads`' `VaultAPI.LintFinding` JSON shape (consumed by `perg lint`
  and the MCP `lint` tool) — both now block a signature change without a deliberate edit to that
  file.

Detail: `docs/adr/0021-workspace-tasks-notes-integration.md`.

## Decisions from the Workspace UI creazione/toolbar/rename chain (ADR-0022)

Workspace sidebar toolbar, folder-backed board creation with an explicit parent picker, folder
rename and folder delete: `docs/adr/0022-workspace-ui-creazione-board-toolbar-e-r.md`.

Key architectural decisions:
- **A wikilink names a note by title, never by path** — a folder rename rewrites no ordinary
  `[[Nota]]` link. What actually breaks and gets repointed: `.canvas` node file paths vault-wide,
  and the renamed folder's own board file name (`^[[old.canvas]]` / `[[old.canvas]]`).
- **The `^[[...]].canvas` marker rewrite reuses `NoteRename.rewritingLinks` unchanged** — no
  extension, since the caret already sits outside the rewritten `link.range` (ADR-0021 §D3).
- **An ambiguous board file name (two folders sharing a name) skips the marker rewrite and
  reports it**, rather than guessing — only the unambiguous `.canvas`-path repoint always runs.
- **Folder rename and folder delete are not journalled and not exposed to `VaultAPI`/the
  connectors** — `WriteJournal` has no entry kind that can describe a directory; recovery is the
  Trash (delete) or a reverse rename, same as before this feature.
- **Delete moves the whole folder via `FileManager.trashItem`, never `removeItem`** — the only
  deletion convention this repo has, matching the existing single-note trash.
- **The new toolbar is a sibling row of `WorkspaceBrowser`'s header, never a child of it** — the
  header's own `accessibilityElement(children: .contain)` would otherwise propagate its
  identifier onto any button placed inside it.

Detail: `docs/adr/0022-workspace-ui-creazione-board-toolbar-e-r.md`.

## Decisions from the universal command surface parity chain (ADR-0023)

Toolbar/context-menu parity for six command clusters (Workspace folder row, note row, task row,
canvas card, editor embed, calendar day cell) plus a net-new Duplica card command:
`docs/adr/0023-universal-command-surface-parity.md`.

Key architectural decisions:
- **A command is named once and rendered twice** — per cluster, title/SF Symbol/applicability
  live in one declaration (`CardCommand`, `CalendarDayCommand`, `CommandActions.run(_:on:)`) read
  by both the toolbar/menu-bar surface and the context menu, so the two cannot diverge.
- **The Workspace folder row's context menu attaches to the row's label, never to its
  `DisclosureGroup`** — a modifier on the `DisclosureGroup` reaches every descendant row exposed
  under it, so a menu placed there would append the parent folder's "Elimina" to every board row
  nested inside it. This is a different trap from ADR-0022 §D8's own AX-identifier propagation
  (that one is about the header's `.accessibilityElement(children: .contain)`, not applicable to
  an `NSMenu`-backed context menu).
- **Duplica card writes only a new node to the `.canvas` file** — new `id` via
  `CanvasID.generate(avoiding:)`, position offset by one grid step (24pt), every other field
  copied verbatim (crop state included). No file on disk is created, moved, or duplicated (CLAUDE.md
  principle 1, "file over app").
- **The editor embed's context menu is `menu(for:)` returning a custom `NSMenu`, always falling
  through to `super.menu(for:)` when outside an embed** — a `menu(for:)` override that returns
  `nil` on a miss silently drops the system's spelling/substitutions/paste menu for the whole
  editor, not just the embed.
- **No new `ShortcutCommand` case and no new key binding** — every new command already has a
  shortcut where one existed before (menu-bar cases) or never had one (card/cell context-menu-only
  actions); the catalogue stays the set of rebindable shortcuts, not all commands.

Detail: `docs/adr/0023-universal-command-surface-parity.md`.

## Decisions from the Workspace board tree single selection chain (ADR-0024)

One derived selection for the Workspace sidebar tree, replacing the two-variable
`selectedFolder`/`openBoardPath` model: `docs/adr/0024-workspace-board-tree-single-selection.md`.

Key architectural decisions:
- **The tree stops being a `DisclosureGroup` and becomes flat recursive rows with `.tag`**, matching
  `NoteListPane`'s reference shape — a `DisclosureGroup`'s label is not a row of the enclosing
  `List`, so `List(selection:)` cannot select it; copying the reference model's binding without its
  row structure produces a binding nothing can satisfy.
- **One `WorkspaceSelection` enum (`.board(folder:)` / `.folder(_)`) replaces `hasOpenBoard`,
  `closeBoard()` and `selectedFolder`** — the lit row and whether a board is drawn are the same
  value, never two variables that must be kept in sync.
- **The selection tag is always the folder path, never the board path** — a board opened from
  outside the tree (breadcrumb, route, card, editor) lights exactly that folder's row whether or
  not a `.canvas` file exists there yet, closing the tree/toolbar divergence ADR-0022 §D9's
  fallback used to paper over.
- **A `.canvas` not named after its folder gets a row with no `.tag`** — structurally unselectable,
  the same mechanism the Note sidebar uses for folder rows, rather than a disabled state anyone has
  to remember to apply.
- **`targetFolder`'s fallback is deleted, not preserved** — with nothing selected, Rinomina/Elimina
  are now disabled rather than aiming at the open board's folder (reverses ADR-0022 A7 deliberately:
  a destructive verb with no visible target is worse than one that asks for a click first).
- **No open-board persistence exists or is added** — corrects the interview's mistaken premise;
  `5041d5c` already shipped "no board open until chosen" and this chain does not reopen it.

Detail: `docs/adr/0024-workspace-board-tree-single-selection.md`.

## Decisions from the Workspace folder/board separation chain (ADR-0025)

Separates the folder-container concept from the board-file concept in the Workspace, moving from
"one board per folder, named after it" to a Finder/Obsidian model: `docs/adr/0025-workspace-folder-board-separation.md`.
Supersedes ADR-0024 §D2/§D3 and relocates ADR-0022 §D4's ambiguity guard from folder rename to
board rename.

Key architectural decisions:
- **A board is addressed by its own file path, never derived from a folder name** —
  `CanvasStore.boardPath(forFolder:)` is deleted outright, not kept as a fallback. `load(board:)`
  throws where `load(folder:)` used to return `.empty`: every silent-blank-board defect this repo
  has had (ADR-0022 F1, ADR-0024 F6) traced back to that folder→board derivation, and a throwing
  read on a path that a walk found or `createBoard` just wrote turns a missed file into a reported
  error instead of a quiet empty board.
- **The tree is built from folders *and* boards as distinct rows, and the vault root is the list
  itself** — no synthesized root row (matching `NoteTree`, which makes none either), so an empty
  folder is visible for the first time and a `.canvas` can live anywhere, any name, any count.
- **One resolution enum answers both "which board does this marker name" and "which board does
  this folder mean"** — `WorkspaceBoardResolver` gains `board(inFolder:among:)` returning the same
  `.unique`/`.ambiguous`/`.notFound` it already used for `^[[x.canvas]]` markers, so every new
  folder→board navigation path (breadcrumb, double-click, editor hand-off) shares one rule instead
  of each guessing separately.
- **ADR-0022 §D4's ambiguity guard is relocated, not deleted** — the SPEC's premise that it
  disappears was wrong: the ambiguity belongs to the marker's bare-file-name grammar, which this
  chain makes *more* reachable (duplicate board names across folders are now legal), so the guard
  moves from folder rename (which no longer touches any `.canvas`) to board rename.
- **Double-click on a folder row always toggles it, never opens a board** — even a folder holding
  exactly one board. Implemented as `.simultaneousGesture(TapGesture(count: 2))` ahead of `.tag`,
  never `.onTapGesture`, which starves the `List(selection:)` binding — untested territory for
  this repo's SwiftUI patterns, verified manually rather than by unit test.
- **`IndexSnapshot.tasks(assignedToWorkspace:)`'s file-name-only comparison is explicitly left
  unchanged** — fixing it would rewrite task-line markers in every note, which Non-goals forbids;
  the resulting ambiguity is reported (`.ambiguous`), never guessed.

Detail: `docs/adr/0025-workspace-folder-board-separation.md`.

## Decisions from the drag-and-drop board/note files into folders chain (ADR-0026)

Drag-and-drop reorganization for both sidebar trees (Workspace boards/folders, Note notes/folders):
`docs/adr/0026-drag-and-drop-board-files-into-workspace.md`. Supersedes ADR-0024 §D2/§D3 in part
(adds a second, additive multi-selection concept beside the single derived `WorkspaceSelection` —
does not reverse ADR-0024's "one open value, never two" claim).

Key architectural decisions:
- **The dragged item carries two `Transferable` representations, not one** — a `CodableRepresentation`
  for the structured move payload plus a `ProxyRepresentation(exporting: \.dragName)` byte-identical
  to today's `.draggable(note.title)`, so `CompletingTextView+Pasteboard.swift`'s existing
  "drop a note title onto a task line" contract (SPEC §7.2 of the workspace-tasks-notes-integration
  chain) keeps working with zero edits to that file — now a protected interface.
- **Multi-selection is `List`'s own `Binding<Set<String>>`, no new gesture recognizer anywhere** —
  Cmd/Shift-click come from AppKit for free; a modifier-flag-reading tap recognizer on the row body
  was rejected because that is exactly what starved `List(selection:)`'s own tap once already
  (ADR-0025 §D9's fix). "Open" is derived from the set by a collapse rule: one id opens/closes as
  today, two-or-more ids opens nothing — the set answers only "what does a drag carry".
- **A cycle gives no drop-target affordance (string arithmetic, free per hover); a collision is
  accepted visually and then named in an error dialog** — asymmetric on purpose, because
  `.dropDestination` has no payload-aware validation closure and R-07 requires the conflicting name
  to be shown, which a row that stays dark cannot do.
- **A move rewrites no wikilink and no `^[[board.canvas]]` marker (both are title/bare-name based),
  but does repoint every `.canvas` node's file path** via `FolderFileOperations.repointBoardsPlan`,
  made non-private by ADR-0025 §D6 precisely for this reuse — the SPEC's "no new rewriting" premise
  was incomplete on this one point.
- **Undo registers on the window's `@Environment(\.undoManager)`, the same stack `NSTextView`
  already uses (`allowsUndo = true`)** — there are not two undo domains in this app to keep apart,
  there is one; a private sidebar-owned `NSUndoManager` was rejected because it would make Cmd+Z's
  meaning depend on which pane holds first responder.
- **The drag is a second rendering of a "Sposta in ▸" menu command already reachable from every
  note row** — the note-move file operations (`NoteFileOperations.movePlan`/`.move`) already existed
  end-to-end before this chain; only the board/folder equivalents and the menu wiring are new. The
  menu path also gives R-01…R-07 deterministic XCUITest coverage no drag gesture in this repo has
  ever had (`.draggable`→`.dropDestination` is an untested machine here).

Detail: `docs/adr/0026-drag-and-drop-board-files-into-workspace.md`.

## Chain decision index

- **ADR-0019** — drag-to-resize handle for drawn embeds, size persisted as Obsidian `|W`/`|WxH` → `docs/adr/0019-embed-drag-resize.md`
- **ADR-0020** — non-destructive image card crop, persisted as one prefixed scalar key `pergamenum-crop` on the canvas node, never touching the file on disk → `docs/adr/0020-image-card-crop.md`
- **ADR-0021** — Workspace browser + Task↔Workspace/Note relations + project sub-tasks, entirely as new task-line caret markers, no new storage → `docs/adr/0021-workspace-tasks-notes-integration.md`
- **ADR-0022** — Workspace sidebar toolbar, folder-backed board creation/rename/delete, no journal, no connector exposure → `docs/adr/0022-workspace-ui-creazione-board-toolbar-e-r.md`
- **ADR-0023** — Toolbar/context-menu command parity across six clusters + Duplica card, one catalogue per cluster shared by both surfaces → `docs/adr/0023-universal-command-surface-parity.md`
- **ADR-0024** — One derived `WorkspaceSelection` for the sidebar tree, flat rows replacing `DisclosureGroup`, supersedes ADR-0022 §D9 → `docs/adr/0024-workspace-board-tree-single-selection.md`
- **ADR-0025** — Board addressed by own file path, not folder-derived; folders and boards are distinct tree rows; supersedes ADR-0024 §D2/§D3, relocates ADR-0022 §D4 → `docs/adr/0025-workspace-folder-board-separation.md`
- **ADR-0026** — Drag-and-drop for both sidebar trees, `List`'s own multi-selection, moves reuse the existing "Sposta in ▸" file operations → `docs/adr/0026-drag-and-drop-board-files-into-workspace.md`
