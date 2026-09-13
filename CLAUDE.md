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
- **A security or invariant check exposed as a separately-callable assertion gets skipped by the
  next call site, not maliciously — just by omission.** `NoteStore`'s vault-boundary check stayed
  `private` and reachable from exactly two of eleven call sites for this reason (ADR-0041). Expose
  it instead as the only way to obtain the value callers need (`VaultBoundary.url(for:) throws ->
  URL`, not `assertInsideVault(url)`) — a resolver a caller cannot route around, rather than a step
  a caller can forget.
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
- **A UI test that launches the app must never let it reach the real Apple Mail store**, the
  third flag of the same family. The suite passes `-mailStoreRoot <fixture>` (ADR-0036), which
  `MailStoreLocation.resolve()` reads before anything else, so a run resolves to a directory the
  test made and threw away rather than to `~/Library/Mail/V10`. Every UI-test file passes it, not
  only the pratiche ones — an empty temporary directory where the test has no Mail fixture of its
  own. Without it, any pratiche sync a run happens to trigger reads the person's actual mail, and
  a Full Disk Access grant is what makes that *succeed* rather than fail visibly. A new UI-test
  file wants the flag too.
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

## Decisions from earlier chains (ADR-0019 – ADR-0026)

Full narrative for these six chains is compacted here to essentials; see the ADR files for detail.
The one-line summary of each already lives in the Chain decision index below.

- **ADR-0019 (embed drag-resize):** size lives only in the note's own text (Obsidian `|W`/`|WxH`
  suffix), no new storage. Resize handle is painted inside the attachment's own picture, not a
  separate `NSView`, so hit-testing geometry never diverges from the no-handle case. Source-text
  rewrite happens once at `mouseUp` (one undo step). CommonMark `![alt](file.png)` embeds get no
  handle — only the wikilink form has verified sizing syntax and the app never writes the other.
- **ADR-0021 (Workspace/Task/Note integration):** no new dependency, schema, or index bump —
  `StoredTask` re-parses `rawLine` via `TaskParser.parse`, so a new `TaskItem` field is free in
  cache. `^[[...]]` is a Workspace marker only when its target ends in `.canvas`. "Progetti" is a
  sixth `TaskGrouping`, never a sixth `TaskView` (the five views are closed by ADR-0013 §D6).
  Protected interfaces: `IndexCache.schemaVersion`, `VaultAPI.LintFinding`.
- **ADR-0022 (Workspace UI creazione/toolbar/rename):** a wikilink names a note by title, never by
  path, so folder rename repoints `.canvas` node paths and the folder's own board file name, not
  ordinary `[[Nota]]` links. An ambiguous board name skips the marker rewrite and reports it rather
  than guessing. Folder rename/delete are not journalled (recovery is Trash or a reverse rename).
  Delete uses `FileManager.trashItem`, never `removeItem`.
- **ADR-0023 (universal command surface parity):** a command is named once (`CardCommand`,
  `CalendarDayCommand`, `CommandActions.run(_:on:)`) and rendered on both the toolbar/menu-bar and
  the context menu, so the two cannot diverge. A folder row's context menu attaches to the row's
  label, never to its `DisclosureGroup` (which would leak onto every descendant row). The editor
  embed's `menu(for:)` always falls through to `super.menu(for:)` outside an embed, or the system
  spelling/paste menu silently disappears for the whole editor.
- **ADR-0024 (Workspace board tree single selection):** the tree is flat recursive rows with
  `.tag`, not `DisclosureGroup` (whose label is not a `List` row, so selection cannot bind to it).
  One `WorkspaceSelection` enum replaces the old two-variable model. The selection tag is always
  the folder path, never the board path.
- **ADR-0025 (Workspace folder/board separation):** a board is addressed by its own file path,
  never derived from a folder name — `load(board:)` throws instead of returning `.empty`, closing
  every silent-blank-board defect this repo had traced to that derivation. Folders and boards are
  distinct tree rows; no synthesized root row. `WorkspaceBoardResolver` is the one place that
  answers both "which board does this marker name" and "which board does this folder mean."
- **ADR-0026 (drag-and-drop board/note files into folders):** the dragged item carries two
  `Transferable` representations so the existing "drop a note title onto a task line" contract
  (`CompletingTextView+Pasteboard.swift`, now protected) keeps working untouched. Multi-selection
  is `List`'s own `Binding<Set<String>>` — no custom gesture recognizer, which would starve
  `List(selection:)`'s own tap (ADR-0025 §D9's fix). A move repoints every `.canvas` node's file
  path but rewrites no wikilink/marker (both are title/bare-name based).

## Chain decision index

- **ADR-0019** — drag-to-resize handle for drawn embeds, size persisted as Obsidian `|W`/`|WxH` → `docs/adr/0019-embed-drag-resize.md`
- **ADR-0020** — non-destructive image card crop, persisted as one prefixed scalar key `pergamenum-crop` on the canvas node, never touching the file on disk → `docs/adr/0020-image-card-crop.md`
- **ADR-0021** — Workspace browser + Task↔Workspace/Note relations + project sub-tasks, entirely as new task-line caret markers, no new storage → `docs/adr/0021-workspace-tasks-notes-integration.md`
- **ADR-0022** — Workspace sidebar toolbar, folder-backed board creation/rename/delete, no journal, no connector exposure → `docs/adr/0022-workspace-ui-creazione-board-toolbar-e-r.md`
- **ADR-0023** — Toolbar/context-menu command parity across six clusters + Duplica card, one catalogue per cluster shared by both surfaces → `docs/adr/0023-universal-command-surface-parity.md`
- **ADR-0024** — One derived `WorkspaceSelection` for the sidebar tree, flat rows replacing `DisclosureGroup`, supersedes ADR-0022 §D9 → `docs/adr/0024-workspace-board-tree-single-selection.md`
- **ADR-0025** — Board addressed by own file path, not folder-derived; folders and boards are distinct tree rows; supersedes ADR-0024 §D2/§D3, relocates ADR-0022 §D4 → `docs/adr/0025-workspace-folder-board-separation.md`
- **ADR-0026** — Drag-and-drop for both sidebar trees, `List`'s own multi-selection, moves reuse the existing "Sposta in ▸" file operations → `docs/adr/0026-drag-and-drop-board-files-into-workspace.md`
- **ADR-0037** — Reveal-on-caret narrows from paragraph to span for emphasis/strikethrough/link, behind a new off-by-default setting, reusing `MarkdownStyler`'s existing recursive parse → `docs/adr/0037-word-grained-markdown-reveal-on-caret-in.md`
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
- **ADR-0038** — Removes both Conformità UI surfaces (the dedicated pane and the note inspector's CONFORMITÀ block); keeps `perg lint`, the MCP `lint` tool, `VaultAPI.LintFinding` (protected interface) and the rule engine untouched, since Principle 5 and tag-entry blocking depend on the engine, not the review UI → `docs/adr/0038-remove-conformance-ui-section.md`
- **ADR-0039** — Task ↔ note/board link and navigation: `TaskCommand` catalogue replaces the never-working "Collega nota o board…" with a single "Collega una board…" (the note is already fixed at capture time), `CommandActions.run(_:on:)` closes the breadcrumb's missing pane-switch, `navigation.taskPickingBoard` hosts the picker at `RootView` for every surface, reopens SPEC §7.2's note-linking requirement → `docs/adr/0039-task-note-board-link-and-navigation.md`
- **ADR-0040** — Fixes Pratiche attachment reliability: an unvalidated `part.decodedData ?? Data()` wrote empty/corrupt bytes straight to `allegati/`; a magic-byte `AttachmentIntegrity` check now gates every write, a pending entry patches the message's attachment line in place rather than re-rendering, and a `.complete` message with a pending entry is now automatically retried every sync; a corrupt file already on disk is moved to the Trash. Amends ADR-0036 §D6 → `docs/adr/0040-pratiche-attachment-reliability-bugs.md`
- **ADR-0041** — Vault layer consistency and security: the vault-boundary check becomes a resolver (`VaultBoundary.url(for:) throws -> URL`, not a skippable assert) used by all 11 call sites that touch the disk with a caller-supplied path; three drifted vault-walk copies and six drifted apply-plan copies become one shared helper in `Sources/Core`; `VaultController*` (18 files) moves out of `Sources/Vault` into `Sources/App`; the write path's disk work moves to a background actor with the hash computed before the hop and a per-path sequence number guarding update order, preserving ADR-0001's index-immediately-after-write invariant. Extends ADR-0001 and ADR-0007, amends neither → `docs/adr/0041-vault-layer-consistency-and-security-cha.md`
- **ADR-0043** — Follow-up to ADR-0041, found by an independent post-implementation review: the per-path write-ordering guard (§D11) covers one of the vault's six index writers, two overlapping async writes can capture the same journal "before", and a `canOperate` check does not survive the `await` it guards. Decides one clock stamped inside `VaultDisk` with `apply` as the only index door, the journal's "before" read inside the actor, and a dirty-buffer prompt instead of an unconditional reload. Extends ADR-0041 §D9/§D10/§D11, amends none. **Decision only, not yet implemented** → `docs/adr/0043-vault-write-ordering-concurrency-races.md`

## Decisions from later chains (ADR-0027 – ADR-0041)

Full narrative for these chains is compacted here to essentials; the one-line summary of each
already lives in the Chain decision index above.

- **ADR-0027 (Nota/Testo unification + rich text):** the Workspace card gets its own lightweight
  `NSTextView`, sharing no class with the note editor — only `InlineFormat.swift` (pure
  markdown wrap/unwrap) is reused. The floating format bar positions itself in board-space
  coordinates (`p * zoom + pan`), never screen coordinates, or it drifts at any zoom other than 1.
  Text color/alignment are whole-card `CardCommand`s, not selection-bar controls.
- **ADR-0028 (WYSIWYG markdown rendering in Workspace):** the card's text view reuses
  `EditorDecorationDelegate` directly rather than forking it, so the two surfaces cannot silently
  diverge. A list marker is substituted character-for-character, never inserted/collapsed —
  TextKit 2 forbids changing a paragraph's length mid-layout. Feature lives behind the existing
  `VaultSettings.hidesMarkup` toggle, no new switch.
- **ADR-0029 (editor WYSIWYG unification):** removes the Modifica/Lettura toggle everywhere (it
  lived in six places, not two) — the editor is now always editable and always styled. A GFM
  table becomes a real `NSTextAttachmentViewProvider`-hosted `NSView` grid, not a fourth
  length-preserving substitution; cell edits commit on Tab/blur/Enter, never per keystroke.
  Workspace `.text` cards are explicitly excluded (a live `NSView` grid must never land in a
  culling-deallocated card).
- **ADR-0030 (editor page typography):** one helper, `ProseTypography` (`Sources/DesignSystem/`),
  is the only place outside `Sources/Core` allowed to construct an `NSFont` in editor/Workspace
  scope. Two new tokens, `font.prose`/`font.proseTitle` (Avenir Next), sit beside the untouched
  interface faces. Bold/italic on a named font family goes through `withSymbolicTraits`, never a
  weight trait — measured: a `.weight: .bold` trait on Avenir Next silently returns the regular
  face.
- **ADR-0031 (Sparkle auto-update):** first explicit, narrow exception to Principle 2 (fully
  offline) — manual-only update check (`SUEnableAutomaticChecks: false`), no telemetry
  (`SUSendsSystemProfile` false), Sparkle enters through exactly one file under `Sources/App/`,
  invisible to `Sources/Core`/`Sources/Connector`/both CLI targets. Appcast/binaries are hosted on
  a dedicated public repo (`istefox/pergamenum-updates`), not the main repo — the SPEC's original
  private-repo hosting plan was verified broken. EdDSA private key lives only in this Mac's login
  Keychain.
- **ADR-0032 (Plaud recording import):** second, narrower exception to Principle 2 — traffic never
  leaves 127.0.0.1:3777 (loopback only). Closed note-frontmatter schema is reopened only via
  `pergamenum-*` prefixed keys. Dedup across re-imports matches on quote-text fingerprint, never
  task id (the service never guarantees a stable id across separate `process` runs). Two-phase
  import: write the note locally first, `POST` accepted task ids only after. Protected interface:
  `ImportNaming.recordingNoteTitle`.
- **ADR-0033 (Views render live in the editor):** `pergamenum-view` fences become an
  `NSHostingView`-hosted attachment reusing the existing `RenderedViewBlock` renderers (query
  layer untouched). Host store is keyed by the fence's ordinal in the note, never by paragraph
  offset, or every keystroke above the fence would re-run its query. Reveal-on-caret is keyed on
  the fence's whole source range, not ADR-0018's per-paragraph set.
- **ADR-0034 (pergamenum-view query builder):** one "Modifica query" affordance shared by both
  fence states. Validity round-trips through the real `ViewBlock.parse` — no second, lenient
  grammar exists. `where` is a flat AND-of-terms model with a raw-text fallback for anything
  non-flat (or/not/nesting), so a non-flat filter is never dropped or altered.
- **ADR-0035 (view-block adaptive height):** measurement crosses from SwiftUI's `@MainActor`
  layout into TextKit's `nonisolated attachmentBounds` through a lock-guarded box on a new host
  subclass, never a shared `@MainActor` property. A height-change callback never invalidates
  TextKit synchronously — it defers one `Task { @MainActor }` hop. `storableHeight` clamps before
  it compares, which is what makes the measure→relayout→remeasure cycle actually terminate.
- **ADR-0036 (Pratiche):** a vault folder synced from a published copy of Apple Mail's Envelope
  Index (system `SQLite3`, in exactly one file, `MailStoreConnection.swift`) plus `.emlx` files —
  one markdown note per message, `allegati/` for attachments, no network. `pratica.md` has exactly
  one editor, the inspector — timeline rows are read-only, because *n* live text views bound to
  ranges of one file is the shape of every text-loss defect this repo has documented. A sync never
  deletes a file and rewrites a message file only for a `pending` body that arrived or an explicit
  «Rigenera» (amended by ADR-0040, see below). `MailStoreLocation.resolve()` is test-aware; all
  UI-test files pass `-mailStoreRoot <fixture>`. Protected interfaces: `PraticaNaming.messageFileName`,
  `Dossier.render`, `VaultAPI.PraticaSummary`.
- **ADR-0037 (word-grained markdown reveal-on-caret):** narrows reveal-on-caret from paragraph to
  span for emphasis/strikethrough/link only, behind an off-by-default setting. Construct extents
  come from `MarkdownStyler`'s existing recursive walk, never a second parser. A caret reveals only
  the innermost containing span; a non-empty selection reveals every span it intersects.
- **ADR-0039 (task-note-board link and navigation):** `TaskCommand` (mirrors `CardCommand`) is the
  one catalogue for `.linkBoard`/`.goToNote`/`.goToBoard`, replacing four hand-kept lists that had
  drifted. "Collega nota o board…" loses its note half (a task's note is already fixed at capture
  time) and becomes "Collega una board…". The board picker's `.sheet(item:)` moves to `RootView`
  so it works from every surface, not just `TasksView`.
- **ADR-0040 (Pratiche attachment reliability fix, amends ADR-0036 §D6):** root cause was one
  line — `PraticaSyncEngine`'s `let bytes = part.decodedData ?? Data()` fed empty/truncated bytes
  straight into hashing and writing; the existing SHA-256 dedup was already correct and needed no
  change. A new `AttachmentIntegrity` type (`Sources/Core/Email/AttachmentIntegrity.swift`,
  Foundation-only) checks magic bytes/terminators before every write and before the store-reference
  threshold check; an unknown format is judged on emptiness alone, never rejected for want of a
  signature. A pending attachment reuses the existing `pergamenum-mail-attachments` list (bare name
  = pending, `[[name]]` = placed) — no new frontmatter key. §D6 amended twice: a `.complete`
  message with a pending entry is now retried every sync via a one-line patch
  (`MessageAttachmentPatch`), never a full re-render, no attempt cap; and a corrupt file already in
  `allegati/` is moved to the Trash (never deleted outright) and re-enqueued as pending. Attachment
  chip UI moves from a `Bool` gate to a three-state `FileState { usable, missing, unusable }` plus a
  `.pending` chip content case. Protected interface: `MessageDocument.isPendingAttachmentEntry`.
- **ADR-0041 (vault layer consistency and security):** the boundary guard that used to be a private,
  skippable `assertInsideVault` inside `NoteStore` becomes `VaultBoundary.url(for:) throws -> URL` in
  `Sources/Core/Vault/` — a resolver is the only way to get a usable `URL`, so a new call site
  inherits the check instead of needing to remember it. The same file holds one shared vault-walk
  helper and one shared apply-plan helper, replacing three and six drifted copies respectively.
  `VaultController*` (18 files) relocates from `Sources/Vault` to `Sources/App`, wider than the SPEC's
  single-file scope because moving only the declaration would have left 17 app-shell files stranded
  in the vault layer. The write path's disk I/O moves to a background actor; the hash is computed on
  the main actor *before* the hop (not after) so `selfWrittenHashes` cannot observe an FSEvents batch
  ahead of its own bookkeeping, and a per-path sequence number — not await-ordering alone — guards
  against two rapid writes to the same file landing out of order. `VaultSession.read` deliberately
  stays synchronous: it has 25 call sites that are synchronous `@Observable` computed properties
  SwiftUI evaluates from `body`, which cannot `await`. Extends ADR-0001 (index-immediately-after-write
  invariant, made mechanical rather than convention) and ADR-0007 (VaultSession/VaultController split,
  shared-sources architecture) without amending either.

Detail: see each ADR under `docs/adr/`.
