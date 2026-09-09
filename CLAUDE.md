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
   telemetry. **One named exception, and only one** (ADR-0031 §D13): the update check,
   which happens when the person chooses «Cerca Aggiornamenti…» and at no other moment -
   no timer, no launch check, no background task. It carries the app's own version
   identifiers and nothing else: no vault content, no note text, no path, no file name,
   no tag, no task, no calendar data, ever. `SUSendsSystemProfile` stays `false`, so
   Sparkle's optional hardware profile is off and the telemetry sentence above is
   untouched. The exception is scoped to the updater and does not travel: no feature of
   the vault, Workspace, tasks, calendar, editor or index gains network access from it,
   and neither `perg` nor `pergamenum-mcp` knows Sparkle exists.
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
scripts/release.sh                                                                              # signed, notarized, numbered build, published with its appcast
scripts/fetch-sparkle-tools.sh                                                                  # Sparkle's sign_update/generate_keys into build/, checksum-pinned
scripts/appcast.py --self-test                                                                  # the appcast generator's own assertions, offline, writes no feed
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
- **A UI test that launches the app risks a Sparkle update-check alert on screen**, the same
  shape of trap as `-disableCalendar` above. The suite passes `-disableUpdater YES` (ADR-0031),
  which keeps `SparkleUpdateController` from starting the updater at all. Every UI-test file
  passes it, not only the one that would need it — a stray modal alert during `launch()` reads
  as the app hanging, not as an update being offered. A new UI-test file wants the flag too.
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
- **A stale instance left alive from a previous run poisons the next full UI run wholesale,
  not just the test that left it.** A run started with stale instances still holding the
  app's global hot key exclusively has produced 18 failures that were not real defects, every
  one timing out at exactly 60.2 s — the launch timeout, not a broken feature. Kill every
  instance before trusting a red run, and read the per-test timings `scripts/uitests.sh`
  prints beside each failure before believing it: 60.2 s names the launch timeout, not the
  app.
- **`firstRect(forCharacterRange:)` returns a zero rectangle for a text range TextKit 2 has
  not laid out yet** — reliably true at the end of a long note, since TextKit 2 lays out
  lazily. A zero rectangle handed to a popover or panel's placement clamps it to the screen's
  bottom-left corner instead of failing loudly, so a UI test asserting on a popup's position
  can pass by accident there. Anything anchoring UI to a character range must confirm layout
  has reached that range first, not assume `firstRect` always returns something meaningful.
- **The UI-test runner's own temporary directory is unreadable from outside the sandbox, on
  or off.** A screenshot or file written to it during a test cannot be inspected afterward by
  reading the path directly. Attach it instead with `XCTAttachment`, run with
  `-resultBundlePath`, and pull it back out with `xcrun xcresulttool export attachments`.
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
- **ADR-0027** — Unify Nota/Testo into one Workspace tool, selection-based rich text (bold/italic/strikethrough/lists/headings as plain markdown) plus whole-card color/alignment as `pergamenum-*` properties → `docs/adr/0027-unificare-nota-e-testo-in-un-solo-strume.md`
- **ADR-0028** — WYSIWYG markdown rendering (concealment + list glyphs) brought from Note into Workspace cards, reopening ADR-0027 §D10 → `docs/adr/0028-wysiwyg-markdown-in-workspace.md`
- **ADR-0029** — One editor, always editable, no Modifica/Lettura toggle; a GFM table becomes a real `NSTextAttachmentViewProvider`-hosted grid; supersedes ADR-0005 §D2 and ADR-0018's "three named constructs" scope boundary → `docs/adr/0029-editor-wysiwyg-unification.md`
- **ADR-0030** — Editor page typography: prose faces (`font.prose`/`font.proseTitle`, Avenir Next) and `spacing.readable` read through tokens by one `ProseTypography` helper, readable-width inset, prose font picker persisted in `personalizzato.json`; amends ADR-0027 §D1 and ADR-0028 §D3, reopens nothing of ADR-0018/0029 → `docs/adr/0030-editor-page-typography-noteplan.md`
- **ADR-0031** — Sparkle auto-update integration: explicit narrow exception to Principle 2 (network) for the updater only, manual-only checks, EdDSA key in Keychain, appcast/binaries hosted on a dedicated public repo `istefox/pergamenum-updates` (amends the SPEC's original private-repo hosting, which live verification found broken), `scripts/release.sh` extended end-to-end → `docs/adr/0031-sparkle-auto-update-integration.md`
- **ADR-0032** — Plaud recording import: loopback-only second exception to Principle 2, `pergamenum-*` frontmatter reopening for transcript notes, quote-fingerprint dedup over note+ledger, two-phase import with retry-only-step-2, app-only scope → `docs/adr/0032-plaud-recording-import-into-pergamenum.md`
- **ADR-0033** — Views render live in the editor again: `pergamenum-view` fences become an `NSHostingView`-hosted attachment reusing the existing `RenderedViewBlock` renderers, host keyed by fence ordinal (not paragraph offset), reveal-on-caret keyed on the fence's whole source range; does not reopen ADR-0009 or ADR-0029 → `docs/adr/0033-views-render-live-in-the-editor.md`
- **ADR-0034** — Visual query builder for `pergamenum-view` fences: one shared "Modifica query" affordance in `RenderedViewBlock`'s header (both live-render and error-card states), validity round-trips through `ViewBlock.parse` itself, flat AND-of-terms `where` with raw-text fallback for or/not/parens, commit reuses `commitTable`'s anchor-and-reload-guard shape; does not reopen ADR-0009 or ADR-0033 → `docs/adr/0034-pergamenum-view-query-builder.md`
- **ADR-0035** — View-block attachment height becomes content-adaptive, capped at the original 320pt (amends ADR-0033 §D8/R-06): measurement crosses the SwiftUI/TextKit isolation boundary via a lock-guarded box on the host, deferred `Task { @MainActor }` relayout to avoid re-entering TextKit, clamp-before-compare for convergence → `docs/adr/0035-view-block-adaptive-height.md`
- **ADR-0036** — Pratiche: a vault folder that fills itself from a published copy of Apple Mail's Envelope Index (system `SQLite3`, db+wal copied, WAL recovered, `quick_check`, own indexes, atomic rename), one markdown file per message plus `allegati/`, membership via `pergamenum-dossier-*` keys, two-lane timeline, `pratica.md` edited only in the inspector, no network, connectors read-only → `docs/adr/0036-pratiche.md`

## Decisions from the Nota/Testo unification + rich text chain (ADR-0027)

Unifies the Workspace's "Nota" and "Testo" toolbar tools into one, and adds selection-based rich
text formatting to `.text` canvas cards: `docs/adr/0027-unificare-nota-e-testo-in-un-solo-strume.md`.

Key architectural decisions:
- **The card gets its own lightweight `NSTextView`, sharing no class with the note editor** — only
  `Sources/Core/Editor/InlineFormat.swift` (Foundation-only markdown wrap/unwrap, already tested,
  with its `isLongerMarker` guard against `****text**`) is reused. `MarkdownAttributedText`'s bold
  rendering (`monospacedSystemFont`) is the note editor's source-mode look and is deliberately not
  reused here.
- **The app already ships a floating format bar (M8: `FormatBar`/`FormatBarPanel`/
  `CompletingTextView+FormatBar`) that deliberately excludes lists and headings** — this chain's
  card-scoped bar is a new, separate component for the same reason; `FormatBar.swift`'s own
  exclusion is not reopened to serve a second surface.
- **The floating bar positions itself in board-space coordinates, never screen coordinates** —
  following the existing `BoardMarquee`/`BoardGuides` precedent (`p * zoom + pan`), since the board
  wraps its content in `.scaleEffect(zoom, anchor: .topLeading)` + `pan` and anything derived from
  `firstRect(forCharacterRange:)` or an `NSPanel` would drift at any zoom other than 1.
- **Text color and alignment are whole-card `CardCommand`s, not selection-bar controls** — they are
  properties of the entire card, reachable without an active text selection, unlike
  bold/italic/strikethrough/lists/headings which are per-selection markdown.
- **`addStickyNote` is not removed** — `Tool.todo` calls it too (`.createSticky("- [ ] ")`); only
  the `.note` case and its toolbar entry point are removed, `.text`/Testo survives as the sole
  card-creating tool for this family.
- **`CanvasColor`'s existing preset/hex parsing is reused for the new text-color property** rather
  than inventing a second color encoding on the same node.

Detail: `docs/adr/0027-unificare-nota-e-testo-in-un-solo-strume.md`.

## Decisions from the WYSIWYG markdown rendering chain (ADR-0028)

Brings Note's WYSIWYG markdown rendering (marker concealment + heading fold) into Workspace's
`.text` cards, and adds list rendering (bullets/ordinals with nesting) to both surfaces for the
first time: `docs/adr/0028-wysiwyg-markdown-in-workspace.md`. Reopens ADR-0027 §D10 (concealment
was an explicit non-goal for cards) and narrowly reopens ADR-0027 §D1 for one class only.

Key architectural decisions:
- **The Workspace card's text view reuses `EditorDecorationDelegate` directly, it is not forked**
  — a deliberate, narrow reopening of ADR-0027 §D1's "share pure logic, never AppKit classes" for
  exactly this one class: the delegate *is* the rendering rule, so forking it would let the two
  surfaces silently diverge. The two attribute tables (`MarkdownAttributedText` vs
  `CardTextAttributes`) stay separate — ADR-0027 §D1's actual prize, the card's real non-monospaced
  bold/italic, is untouched.
- **A list marker is substituted character-for-character, never inserted or collapsed** — TextKit 2
  forbids changing the displayed paragraph's length in
  `textContentStorage(_:textParagraphWith:)` (`NSTextContentManager.h:120`). An ordered marker's
  digits are left verbatim in the source, since the file's own digits are the rendered ordinal;
  this couples correct rendering to keeping the list run's text contiguous.
- **The whole feature lives behind the existing `VaultSettings.hidesMarkup` toggle on both
  surfaces** (already `true` by default) — no new card-only switch, reached through
  `WorkspaceView.applyBoardSettings()` the same way `boardShowsGrid` already is. Never
  `@Environment(VaultController.self)` inside the card view — a preview or test built without that
  environment crashes.
- **Auto-continuation/renumbering of ordered lists needs a new pure type, `ListContinuation`** —
  `LineFormat.toggled(.numbered)` only renumbers the selection from 1 and has no concept of a run's
  extent or starting ordinal, so it is not reusable for this.
- **The Workspace card's heading fold is a new `CardCommand` submenu, not a ported disclosure
  control** — Note has no in-text fold trigger at all; fold there comes from `OutlinePane`'s
  chevron, outside the editor.
- **Checkbox lines (`- [ ]`) never get a list span or bullet** — checkboxes stay their own separate
  rendering in both surfaces, unrelated to the new list-glyph mechanism.

Detail: `docs/adr/0028-wysiwyg-markdown-in-workspace.md`.

## Decisions from the editor WYSIWYG unification chain (ADR-0029)

Collapses the note editor's Modifica/Lettura toggle into one always-editable, always-styled
view and makes a GFM table a real editable grid: `docs/adr/0029-editor-wysiwyg-unification.md`.
Supersedes ADR-0005 §D2 (Diario's "reading sits beside an unchanged source editor" premise) and
ADR-0018's "three named constructs, not the rule" scope boundary — ADR-0018's mechanism itself
(§D1 length-preserving substitution, §D2 reveal-on-caret, §D3 display-only, §D5 caret rules,
§D7 the one setting) is untouched, this chain is that mechanism applied further.

Key architectural decisions:
- **Four more constructs join ADR-0018's substitution mechanism unchanged** — blockquote `>`
  (substituted `▏` per level, character-for-character, so nesting is unbounded for free — the
  file's own character count is the depth), strikethrough `~~` (exact twin of `.emphasisMarker`),
  link/wikilink brackets (hidden marker + hover tooltip via `NSToolTipAttributeName`, a hook this
  repo had never called), horizontal rule (the one case needing the heading-fold hook instead,
  since three characters cannot length-preserve into a full-width line).
- **A GFM table is one attachment anchored to its header paragraph, with the delegate's
  enumeration hook refusing to lay out the body rows** — not a fourth length-preserving delimiter
  substitution. This is why ADR-0018 §D4's "tables are out of reach at sane cost" verdict no
  longer holds: that verdict assumed the grid had to fit inside one length-preserved paragraph.
- **The grid is a real `NSView` via `NSTextAttachmentViewProvider`** (`NSTextAttachment.h`'s own
  "this is where subclasses create their custom view hierarchy" hook, `YES` by default,
  previously unused in this repo) — a genuine subview in the key-view loop, not a rectangle kept
  aligned by hand. Created and owned by the Coordinator, handed to `EditorDecorationDelegate` as
  a finished value — the delegate cannot be `@MainActor` (Swift 6 refuses both conformances) and
  must own no view itself, the same crossing `embedRenditions` already makes.
- **Cell edits commit on Tab/blur/Enter, never per keystroke** — each cell is its own scoped
  text-editing session; the source markdown rewrite happens once per commit through the existing
  `shouldChangeText`/`beginEditing`/`replaceCharacters`/`endEditing` atomic path (ADR-0019
  precedent), giving one `Cmd+Z` per structural edit.
- **`MarkdownReadingView` is retained as dead code, not removed** — only the toggle goes.
  `MarkdownBlocksView` is not dead code either way: `TranscludedNoteView.swift` still draws every
  `![[nota]]` rendition with it, and `NoteExporter.swift` already uses it for HTML export.
  `MarkdownReadingView` has no remaining call site after the toggle's removal, but stays in the
  tree, commented per ADR-0029 §D14, as the seam for a future preview/print surface nobody has
  designed yet — deleting it was explicitly out of scope for this chain.
- **The toggle lived in six places, not the two the SPEC named** — `NoteTabBar.swift`,
  `VaultBrowser.swift`, `MenuCommands.swift`, `CommandActions.swift` (×2),
  `EditorColumnView.swift`, `VaultController+Tabs.swift`, `NoteTab.swift`, and
  `ShortcutCommand.readingMode` (`Cmd+Shift+M`) — all removed together, not just the two
  originally cited.
- **Workspace `.text` cards are explicitly out of scope and structurally protected** — they share
  `EditorDecorationDelegate` with the note editor (ADR-0028 §D1), so this chain's card exclusion
  is not free: the card's own span switch (`CardTextView.swift`) is the seam that keeps a live
  `NSView` grid from ever landing in a card, whose text view is deallocated on culling-rect
  crossings.
- **Blockquote nesting diverges between the editor and `MarkdownBlocksView`** — the editor draws
  one bar per level (unbounded), `MarkdownBlocksView` still strips exactly one `>`. Named as
  known debt, not fixed by this chain.

Detail: `docs/adr/0029-editor-wysiwyg-unification.md`.

## Decisions from the editor page typography chain (ADR-0030)

Makes the note editor read as a page instead of a code buffer, Phase A of
`docs/20260904_Editor_Page_Roadmap.md`: `docs/adr/0030-editor-page-typography-noteplan.md`.
Amends ADR-0027 §D1 (card body font moves to `font.prose`) and ADR-0028 §D3 (list paragraph
style gains a base style); reopens no mechanism of ADR-0018/0028/0029.

Key architectural decisions:
- **One helper, `ProseTypography`, under `Sources/DesignSystem/`, is the only file in
  `Sources/Features/Editor` + `Sources/Features/Workspace` scope allowed to construct an
  `NSFont`** — the allow-list of what may still say `NSFont.` there is ADR-0030 §D8
  (`collapsedFont`, ADR-0018's concealment non-font; the `NSFont.Weight` type name;
  `NSFont.systemFontSize` as last resort; type annotations). Never `Sources/Core`: AppKit there
  breaks the `perg`/`pergamenum-mcp` builds.
- **Two new tokens, `font.prose` (Avenir Next 16, lineHeight 1.4) and `font.proseTitle` (Avenir
  Next Bold 24), beside an untouched `font.body`/`font.title`** — eleven chrome call sites depend
  on the interface faces; the page and the interface are different things.
- **A named font family is a fourth `TypographyValue.Family` case resolved with
  `NSFont(name: family, size:)`, bold/italic through `withSymbolicTraits`, never a weight trait**
  — measured: a `.weight: .bold` trait on Avenir Next silently returns `AvenirNext-Regular`.
  Missing family degrades to the system face. SwiftUI's `Theme.font(_:)` probes with `NSFont`
  first and passes the resolved `fontName`, or `Font.custom` substitutes a different face
  silently.
- **`EditorDecorationDelegate`, `FoldedHeadingFragment` and `TableGridView` receive fonts as
  pushed values** (`decorations.proseFont`/`badgeFont` assigned in `applyStyling` beside the
  colours already pushed there) — the delegate is not `@MainActor` and cannot read `Theme`.
- **Heading scale is `max(prose + 1, proseTitle − (level − 1) × 2)`**, the rule
  `CardTextAttributes.headingSize` already shipped, moved into the helper; no per-level tokens.
- **Line height is one `lineHeightMultiple` composed onto existing paragraph styles, never
  overwriting them, and no `paragraphSpacing`** — three sites build their own style wholesale
  (list markers, transclusion `reservedHeight`, card alignment) and each would silently drop it.
  Workspace `.text` cards take the prose faces but deliberately **not** the line height.
- **Readable width is the horizontal `textContainerInset`, `max(24, (viewWidth − 720) / 2)`**,
  with `widthTracksTextView` left `true` and no frame ever set — `growToFitTheText`'s header
  records why `setFrameSize` on this text view once cost the Diario its typed text.
  `spacing.readable` is a `SpacingToken`; `DesignGalleryView` stops iterating `allCases` for its
  swatch ramp, or it draws a 720×720 square.
- **The prose font picker writes `font.prose`/`font.proseTitle` overrides into
  `.pergamenum/themes/personalizzato.json` through `ThemeCustomization.Draft.fonts`**, the same
  file and path the colour overrides use; only those two tokens are writable from Impostazioni.
- **No index field, no frontmatter key, no `.canvas` property, no migration, no protected
  interface touched.** `IndexCache.schemaVersion` stays 3.

Detail: `docs/adr/0030-editor-page-typography-noteplan.md`.

## Decisions from the Sparkle auto-update integration chain (ADR-0031)

Adds Sparkle-based auto-update: manual-only check, EdDSA-signed releases, and an extended
`scripts/release.sh` publishing pipeline: `docs/adr/0031-sparkle-auto-update-integration.md`.

Key architectural decisions:
- **Explicit, narrow exception to Principle 2 ("Fully offline")** — the update check is a network
  call by nature, scoped exclusively to the updater: no vault content, no note text, no telemetry
  (`SUSendsSystemProfile` stays `false`). No other feature gains network access as a result of
  this chain.
- **Checks are manual-only, triggered from "Cerca Aggiornamenti…" in the app menu** —
  `SUEnableAutomaticChecks: false`, no timer, no background task, no Settings surface. Sparkle's
  own stock update UI (`SPUStandardUserDriver`) is used as-is and is explicitly out of scope for
  the design-token binding rule — it is a system framework window, not a view this app authors.
- **Sparkle enters through exactly one file under `Sources/App/`**, an ordinary SPM dependency in
  `Tuist/Package.swift`, never touching `Sources/Core`/`Sources/Connector` or any `sharedSources`
  glob — `perg` and `pergamenum-mcp` stay unaware Sparkle exists, the same boundary EventKit
  already respects.
- **The distributable zip is built from the already-stapled bundle, in a new variable, never by
  reusing `scripts/release.sh`'s pre-existing `$zip`** — that zip is notarized *before* stapling and
  was never the distributable; Sparkle's archive must be built after `xcrun stapler staple`, which
  is a correctness fix to a pre-existing gap in the script, not new behavior grafted on.
- **Appcast/binaries are hosted on a dedicated public repository, `istefox/pergamenum-updates`, not
  on `istefox/Pergamenum`** — live verification during this chain found the SPEC's original
  private-repo hosting plan broken two independent ways (release assets on a private repo need
  authentication Sparkle never sends; Pages on a private repo is either unreachable to Sparkle or
  makes this repo's `docs/` world-readable). The dedicated repo holds only the appcast and signed
  release archives, nothing else.
- **The appcast item is hand-built by a new `scripts/appcast.py`, not Sparkle's own
  `generate_appcast`** — that tool assumes one download-URL prefix and a local folder as the feed's
  full history, neither of which fits a per-tag GitHub Release; it also generates binary deltas,
  an explicit non-goal for this app.
- **The EdDSA private key lives only in this Mac's login Keychain**, generated once via Sparkle's
  own `generate_keys` tool; never written to disk in cleartext, never committed.

Detail: `docs/adr/0031-sparkle-auto-update-integration.md`.

## Decisions from the Plaud recording import chain (ADR-0032)

Consumes the local `plaud-service` HTTP contract (loopback-only, 127.0.0.1:3777) to turn Plaud
voice recordings into a transcript note plus reviewed tasks: `docs/adr/0032-plaud-recording-import-into-pergamenum.md`.
App-only — `Sources/Connector`/`Sources/Core` and both command-line targets are untouched.

Key architectural decisions:
- **Second, narrower named exception to Principle 2 ("Fully offline")** — traffic never leaves
  127.0.0.1:3777, provably distinct from ADR-0031's Sparkle exception, which reaches the real
  internet. No feature outside this one gains network access, and neither `perg` nor
  `pergamenum-mcp` knows the Plaud service exists.
- **The closed note-frontmatter schema is reopened via `pergamenum-*` prefixed keys**
  (`pergamenum-plaud-id`, `pergamenum-plaud-recorded-at`, `pergamenum-plaud-duration-ms`),
  mirroring ADR-0020's `pergamenum-crop` precedent — a tag alone (`type-trascrizione`, itself
  unwritable in `Resources/vocabolari.json`) could not carry structured recording metadata, so
  the note settles on `type-note` + `topic-trascrizione` + `source-meeting`.
- **Dedup across re-imports matches on quote-text fingerprint, never on task id** — the service
  contract only guarantees a task's id stable within one proposal read, not across separate
  `process` runs, so fingerprint matching runs over the union of the note's own task lines and a
  local, append-only ledger (`plaud.json`), which lets a person's deliberate deletion of a task
  from the note stay deleted rather than resurrecting on the next import.
- **Two-phase import**: (1) write/update the note locally and record `pendingConfirmation` in the
  ledger, (2) `POST` the accepted task ids to `/imported`. A failed step 2 leaves the note intact
  (file over app) with a retry-only-step-2 recovery path — it never re-writes the note or
  duplicates fingerprints.
- **Local, per-vault, non-vault state lives under**
  `~/Library/Application Support/it.stefer.pergamenum/vaults/<vaultID>/` (ADR-0017 precedent) as
  two JSON files, `plaud.json` (ledger/settings) and `plaud-drafts.json` (pending review state) —
  not in `IndexCache` (not vault-derivable), not in `.pergamenum/` (machine-specific, not
  vault-portable), not in `UserDefaults` (a per-vault growing list, not a preference).
- **Sidebar gains one row, "Registrazioni" (`waveform`), last in the existing `.work`/LAVORO
  group**, reachable review flow is a `.sheet`, and a new `ShortcutCommand.refreshRecordings` is
  bound to Cmd+R (verified free against `com.apple.symbolichotkeys` before wiring).
- **One protected interface declared** (`.claude/protected-interfaces`, ADR-0053):
  `Sources/Core/Conventions/ImportNaming.swift:recordingNoteTitle` — re-import matches an
  existing transcript note by the name this function derives, so a silent signature/behavior
  change orphans every note already imported.

Detail: `docs/adr/0032-plaud-recording-import-into-pergamenum.md`.

## Decisions from the Views-render-live-in-the-editor chain (ADR-0033)

Restores a live, interactive surface for `pergamenum-view` fences (table/gallery/calendar/board,
ADR-0009) inside the main editor — orphaned when ADR-0029 removed the Lettura mode that used to
host them: `docs/adr/0033-views-render-live-in-the-editor.md`. Does not reopen ADR-0009 (query
grammar, closed field list, board write/undo semantics) or ADR-0029 (attachment mechanism,
delegate ownership split); applies that mechanism to a sixth construct with three named
divergences.

Key architectural decisions:
- **The attachment hosts the SwiftUI `RenderedViewBlock` that already exists, via `NSHostingView`**
  — not a second AppKit reimplementation of the four renderers. The evaluator, the renderers, the
  board's guarded write and the query source (`viewQuerySource`, left unreferenced by ADR-0029
  §D13 for exactly this) were already written, tested and merged; nothing in the query layer is
  built here.
- **The host store is keyed by the fence's ordinal within the note, not by paragraph offset** —
  diverges from `TableGridStore`'s shape on purpose: an offset key would rebuild the SwiftUI host
  on every keystroke typed above the fence, re-running its `.task` and re-evaluating the query,
  which ADR-0009 §D7 forbids.
- **Reveal-on-caret is keyed on the fence's whole source range, not on ADR-0018's per-paragraph
  `revealedParagraphs` set** — structurally required, not a style choice: the fence's body lines
  are out of the layout, so the caret can only ever occupy the opening-fence paragraph; keying
  reveal per-paragraph there creates a reveal/re-hide loop the instant the caret moves into the
  now-revealed body.
- **The closing fence line is added to the delegate's hidden-paragraph set alongside the body
  lines** — a fence has no equivalent of the table's "ends at its last body row": a fence ends at a
  line of backticks that would otherwise sit under the drawn attachment as stray text.
- **R-09 (click a row to open its note) is net-new, not a restoration** — grepped zero hits for
  `Link`/`Button`/`onTapGesture`/`openURL` in `ViewRowRenderers.swift`/`ViewGridRenderers.swift`;
  Lettura never opened a note from a view row either. Costs a new optional input threaded through
  the renderers rather than reusing existing behavior.
- **R-08 (fail to plain fenced text on a malformed query) is resolved in the editor's favor over
  ADR-0009 §D1's existing rule** ("a block that does not parse renders as an error naming the
  line, never as an empty result") — the error reason text is a recorded, deliberate cost in the
  editor surface only; the error card is kept unchanged on the transclusion, export and Viste-pane
  surfaces.
- **A closed-fence precondition gates attachment creation** — `CodeFence.regions(in:)` runs an
  unclosed fence to end-of-text by design; without this guard, typing an opening
  ` ```pergamenum-view ` fence would take the rest of the note out of the layout mid-keystroke.
- **`TranscludedNoteView` and `NoteExporter` are untouched** — both already render a
  `pergamenum-view` fence correctly via `MarkdownBlocksView` today; this chain adds a second,
  independent live rendering path for the main editor only.
- **Open risk, not yet resolved by this ADR alone:** whether SwiftUI drag-and-drop
  (`@State`/`.task`/`.draggable`/`.dropDestination`) behaves correctly inside an
  `NSTextAttachmentViewProvider`-hosted `NSHostingView` is unproven — ADR-0029 §D16 probe 2 only
  answered this for a plain `NSView`. A tracer-bullet task in the plan gates this before the board
  renderer's drag interaction is built out, with a named fallback (a per-card context menu writing
  through the same `ViewQuerySource.move` closure) if the probe is negative.

Detail: `docs/adr/0033-views-render-live-in-the-editor.md`.

## Decisions from the pergamenum-view-query-builder chain (ADR-0034)

Visual builder for `pergamenum-view` fences, reachable from the fence itself in the main
note editor: `docs/adr/0034-pergamenum-view-query-builder.md`. Does not reopen ADR-0009
(grammar, closed field list, no-materialisation rule) or ADR-0033 (attachment mechanism,
ordinal host key, closed-fence precondition) — it composes text those two already accept.

Key architectural decisions:
- **One affordance in the header both fence states already share** — `RenderedViewBlock`
  gains a third optional `onEditQuery` input (ADR-0033 §D9's `nil`-default pattern), drawn
  once in `header(renderer:count:)`, which both the `.failure` (error card) and `.success`
  (live render) branches call — "present on both states" costs one `Button`, not two
  implementations kept in step.
- **Validity round-trips through the real `ViewBlock.parse` — no second, lenient grammar.**
  The draft serialises to a fence body, that body is parsed, and the resulting
  `Result<ViewBlock, ViewBlockError>` is the only thing "Fatto"'s enabled state, its inline
  error text, and the live match count consult. The sheet cannot disagree with the note.
- **`where` is a flat AND-of-terms model with a raw-text fallback**, decided by one pure
  function (`ViewQueryFlattening.terms(of:)`) that returns `nil` for `or`/`not`/nesting —
  the fallback is a validated text field for `where` alone; every other section still
  loads structured, so a non-flat filter is never dropped or altered.
- **The commit is `commitTable`'s anchor-and-reload-guard shape, not a new channel.** The
  fence is re-read from the live characters at commit time via
  `EditorDecorationDelegate.viewBlockRun` (both model and buffer, ranges and text
  compared); a fence that moved on refuses the write rather than merging or guessing.
  `replaceAtomically` is reached exactly once per commit — one `Cmd+Z` for the whole edit.
- **The insert-view command writes a stub first, so "Fatto" has exactly one
  implementation** — the sheet always edits a fence that already exists, removing the
  create/rewrite fork before it exists. `Navigation`'s tuple becomes a struct
  (`Navigation.Insertion`) to carry the new flag, with a defaulted parameter keeping all
  prior call sites untouched.
- **The SPEC's Italian date keywords (`oggi`, `inizio-settimana`) do not parse** —
  `ViewDateBound` only accepts `today`/`today-N`/`week-start`. The date-bound control's
  labels stay Italian; the text it writes is the parser's own spelling.
- **No folder-tree component exists to reuse for Ambito** — the app's real folder picker
  is a flat `Menu` over `vault.folders` (`NewNoteComposer`/`NoteRowMenu`'s "Sposta in"
  shape), extracted once as `FolderPickerMenu`. Building a tree would be a third one,
  meeting ADR-0024's `DisclosureGroup`/`List(selection:)` trap for no gain.
- **`CompletingTextView`'s wikilink completion cannot be reused in a sheet row** (it is an
  `NSPanel` positioned from `rangeForUserCompletion` inside an `NSTextView`) — the
  `linksTo`/`linkedFrom` term gets a new, small searchable list copying
  `RelatedLinkSheet`'s shape (`TextField` + `vault.index.search`), not extracted from it.
- **`columns` is an ordered `[ViewField]`, and is omitted from the written fence only when
  the selection exactly equals the renderer's `effectiveColumns`** — column order is what
  a table draws, so a `Set` would risk silently reordering a hand-written block.
- **No new capability in `Sources/Core`, `Sources/Connector`, `perg`, or
  `pergamenum-mcp`** — the whole feature lives in `Sources/Features/Views/` (pure builder
  logic) and `Sources/Features/Editor/` (anchor/commit wiring), neither in any
  `sharedSources` glob, so the CLI/MCP boundary is structural rather than a rule to keep.

Detail: `docs/adr/0034-pergamenum-view-query-builder.md`.

## Decisions from the view-block adaptive-height chain (ADR-0035)

Replaces `ViewBlockAttachment`'s fixed 320pt height with one adaptive to content, capped at the
same 320pt: `docs/adr/0035-view-block-adaptive-height.md`. Amends ADR-0033 §D8/R-06 — a small
result set no longer reserves a mostly-empty box; a large one still scrolls internally past the
cap exactly as before.

Key architectural decisions:
- **The measurement crosses from SwiftUI's `@MainActor` layout into TextKit's `nonisolated`
  `attachmentBounds` through a lock-guarded box (`ViewBlockHeightBox`) on a new host subclass
  (`ViewBlockHostView`)**, not a shared `@MainActor` property — `attachmentBounds` cannot read one.
  The box lives on the host, which survives across styling passes (ADR-0033 §D3's ordinal key),
  not on the attachment, which is rebuilt fresh every pass.
- **The measurement point is inside the existing `ScrollView`, never inside `RenderedViewBlock`
  itself** — a vertical `ScrollView` proposes `nil` height to its content, so the attachment's
  capped reserved height can never feed back into what gets measured. Moving either one relative
  to the other breaks the whole design.
- **A height-change callback never invalidates TextKit synchronously** — it runs on SwiftUI's own
  layout stack, and doing so would re-enter `NSTextLayoutManager`. It defers one `Task { @MainActor
  }` hop, coalesced per Coordinator turn, then calls the same `invalidateLayout` +
  `growToFitTheText` path `applyFolding`/`applyTransclusion` already use in production —
  `growToFitTheText` never sets a frame directly, which is the one operation this codebase has a
  documented regression from.
- **Before any measurement, the attachment reserves 120pt, not the 320pt cap** — TextKit 2 lays out
  lazily, so a 320pt default would make every fence visibly collapse to its real height the first
  time it scrolls into view. 120pt approximates the "header, no result yet" placeholder height, so
  the visible motion is normally just results filling in.
- **`storableHeight(measured:current:)` clamps before it compares** — the only thing that makes a
  measure → relayout → remeasure cycle terminate for content taller than the cap: two
  above-the-cap measurements (5000pt, then 5003pt) both clamp to 320pt, so the second stores
  nothing and schedules no further relayout.

Detail: `docs/adr/0035-view-block-adaptive-height.md`.

## Decisions from the Pratiche chain (ADR-0036)

A «pratica» is one matter with one counterpart, kept as a vault folder that fills itself from
Apple Mail's local store and shows received/sent messages, attachments, notes and phone calls as
one two-lane chronological timeline: `docs/adr/0036-pratiche.md`. Amends SPEC §14 in one row
(HTML rendering of email bodies stays excluded; text extraction to light markdown is included).
Adds no exception to principle 2: no network, no socket, no loopback.

Key architectural decisions:
- **The Envelope Index is read from a published generation copy, never from Mail's live file** —
  `Envelope Index` + `-wal` (never `-shm`) are copied into a staging dir under the vault's state
  base, opened read-write so SQLite recovers the WAL, `quick_check`ed, given our own indexes on
  `conversation_id`/`sender`, then published with one directory rename. A torn copy is retried once
  and then reported as «Mail sta scrivendo», never papered over. `immutable=1`, the backup API and
  any handle on Mail's own file are rejected outright.
- **SQLite goes through the system `SQLite3` module, in exactly one file** —
  `MailStoreConnection.swift` is the only place `sqlite3_` may appear (a test enforces it); every
  value is bound with the transient destructor spelled `unsafeBitCast(-1, to:
  sqlite3_destructor_type.self)`, and `SQLITE_OPEN_CREATE` is never passed, or a missing store
  becomes an empty database that reports «nessun messaggio» forever. No GRDB, no manifest edit.
- **The ledger bridges RFC `Message-ID` ↔ index ROWID ↔ `conversation_id`** — the index's
  `message_id` column is a hash, so Task 1's human-present probe decides whether the RFC id is
  queryable, and both outcomes have a designed implementation. `.emlx` location is a probed digit-fan
  rule with an enumerated fallback; «non più in Mail» is shown only for `.notInStore`, never for a
  locator miss.
- **`pratica.md` has exactly one editor, the inspector** — timeline rows draw manual entries
  read-only with `MarkdownBlocksView`; editing places the caret via the existing
  `Navigation.jumpToLine`. The blueprint's *n* live text views bound to *n* ranges of one file,
  inside a culling `List`, beside a background writer, is the shape of every text-loss defect this
  repo has documented and was rejected on that evidence.
- **A sync never deletes a file and rewrites a message file only for a `pending` body that
  arrived or an explicit «Rigenera» with a `UnifiedDiff` preview.** Duplicate `Message-ID`s across
  Sent/Archive are resolved once before any write; direction is decided by `From` against own
  addresses, never by mailbox.
- **`MailStoreLocation.resolve()` is test-aware like `VaultState.processDefaultBase()`** —
  `-mailStoreRoot` launch argument first, a per-process fixture root under xctest, and only then
  `~/Library/Mail/V10`. Fixtures are built by code, never copied from a real store. All 19 UI-test
  files gain `-mailStoreRoot <fixture>` beside `-disableCalendar` and `-disableUpdater`.
- **Full Disk Access is probed per trigger with `open(2)`, never at launch**; macOS denies silently
  and never prompts, and the Apple Development signing identity is what keeps the grant across
  rebuilds. The connectors compile the Mail-store files (they live under `Sources/Core/**`) but
  are structurally forbidden to call them: `SharedSourcesPurityTests` asserts no file under
  `Sources/Connector`, `Sources/CLI` or `Sources/MCPServer` names `MailStore`, `EMLXReader` or
  `SQLite3`.
- **Tag sets corrected against the real linter** — `pratica.md` carries `type-note`,
  `topic-pratica`, `client-<slug>`, `status-*`, `source-email`; message files add `type-email`.
  «Chiuse» means `status-archived`; `status-final` is read but never written. The dossier is a
  line codec over `Frontmatter.ForeignKey`, byte-preserving on keys it does not own.
- **Three new `ShortcutCommand` cases appended, never inserted** — `panePratiche` Ctrl+Cmd+P (the
  pane digits ran out at ADR-0032), `newPratica` Cmd+Opt+P, `addToPraticaFromMail` Cmd+Shift+P;
  `toggleInspector` becomes pane-aware instead of gaining a twin. One shared `message://` builder
  replaces the two encodings in `EmailHeaders.mailURL` and `MailLink.url`, chosen by one measurement.
- **Three protected interfaces declared** (`.claude/protected-interfaces`): `PraticaNaming.messageFileName`,
  `Dossier.render`, `VaultAPI.PraticaSummary`.

Detail: `docs/adr/0036-pratiche.md`.
