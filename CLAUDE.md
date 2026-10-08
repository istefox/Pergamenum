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

- Language/runtime: Swift 6 with strict concurrency, SwiftUI on the macOS 27 SDK
- Platform: macOS 27 or later, Apple Silicon. No compatibility fallbacks for
  earlier releases - current SwiftUI APIs are used directly. (Raised from macOS 26
  Tahoe/Xcode 26 on 2026-09-18: the dev machine moved to macOS 27.0/Xcode 27.0 and the
  build already targets the macOS27.0 SDK - confirmed live via `sw_vers`/`xcodebuild
  -version`, not assumed.)
- AppKit via `NSViewRepresentable` where SwiftUI is insufficient: the text editor
  (TextKit 2 in an `NSTextView`) and the canvas.
- Tooling: Tuist 4 for project generation, Swift Testing for tests, Xcode 27 toolchain
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
   which happens when the person chooses «Cerca aggiornamenti…» and at no other moment -
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
4. **Obsidian compatibility.** *Amended 2026-09-16 (ADR-0047 §D11).* The existing "Labs" vault
   opens without conversion, and it does so because the formats underneath are ordinary ones -
   markdown, frontmatter YAML, wikilinks, `.canvas` as plain JSON Canvas 1.0, the `|W`/`|WxH`
   embed-size suffix, 16-hex node ids, `pergamenum-` prefixed extra keys preserved and not
   interpreted - not because keeping Obsidian able to read the result is a constraint this project
   still holds. What ends is the round-trip *obligation*: a future design is no longer rejected on
   the ground that it would stop Obsidian from opening a Pergamenum-written file, and the manual
   round-trip probe (ADR-0020's Probe 2) is retired as an acceptance gate, never re-added as one.
   Nothing on disk changes shape because of this amendment. Principle 5 below is untouched by it.
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
- **CI (ADR-0044, `.github/workflows/ci.yml`) builds `Pergamenum`, `perg` and `pergamenum-mcp` from a
  clean checkout and runs `PergamenumTests`, on every PR and on push to `main`.** It is advisory, not
  a required check, and it verifies nothing else: the UI suite (`scripts/uitests.sh`, run through
  `--affected` at merge per the rule below), SwiftLint and the release pipeline are not on it. A green
  CI badge means those three targets build and the unit suite passes — nothing about the UI suite.

## Commands

```bash
tuist install                                                                                   # once per fresh worktree, before the first generate (else the Stop hook reports exit 66, not a red test)
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
scripts/uitests.sh                                                                              # the GUI suite: --affected at merge, a full run before a release
scripts/check-merge-integrity.py --self-test                                                    # ADR-0061's and ADR-0062's own assertions, offline, touches no repository
scripts/check-merge-integrity.py --landings "$(git rev-list --max-parents=0 origin/main)..origin/main"  # ADR-0062's landing audit over main's history (exits 1 on the six known historical landings)
scripts/install-git-hooks.sh                                                                    # once per machine: installs the pre-push guard from ADR-0061/0062; rerun with --force after a hook change
scripts/check-adr-references.py                                                                 # docs/adr/README.md's three rules on the working tree, against origin/main (git fetch first)
scripts/check-adr-references.py --self-test                                                     # its own scenarios, offline, in throwaway repositories, touches no repository
scripts/adr-index.py                                                                            # prints the `## ADR index` lines below from the headings of docs/adr/0*.md
scripts/adr-index.py --check                                                                    # names each stale, missing or out-of-order line of that index (exit 1), offline
scripts/adr-index.py --self-test                                                                # its own scenarios, offline, in throwaway repositories, touches no repository
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

Rules keyed to a file type live in `.claude/rules/` and load only when a matching file is read:

- `.claude/rules/ui-tests.md` (`Tests/**`, `UITests/**`, `scripts/uitests.sh`, `.claude/test-cmd`): the UI-test isolation flags, `PergamenumUITestCase`, `scripts/uitests.sh --status`/`--affected`, stale instances, drags and identifiers.
- `.claude/rules/swiftui-views.md` (`Sources/**`): `List`/`DisclosureGroup`/`.contextMenu`/Quick Look/pointer traps, confirmation-dialog state, `firstRect`.
- `.claude/rules/vault-writes.md` (`Sources/**`): `VaultBoundary`, the guard-after-`await` rule, ledger/board/diary origin markers, `QuitCoordinator`.

- **A merge commit that silently discards a parent's content is refused, not merely logged.**
  PG-240: a branch cut before PR #515 landed merged `main` in, claimed to resolve one `TODO.md`
  conflict, and its tree quietly kept the branch's stale version of fifteen other files nothing
  had flagged as conflicted — a wholesale "ours" resolution, not a per-file one. The next merge
  carried that loss into `main` with nothing left to disagree about. `scripts/git-hooks/pre-push`
  (installed once per machine via `scripts/install-git-hooks.sh`) and the advisory
  `merge-integrity.yml` workflow both run `scripts/check-merge-integrity.py`, which recomputes
  the real merge via `git merge-tree` and fails on any non-conflicted path a committed merge
  disagrees with. A deliberate wholesale override needs `Merge-override: <path>` plus
  `Merge-override-reason: <text>` on the merge commit itself, naming every path — see ADR-0061.
  The same hook and workflow also run the landing check (`--landing BASE HEAD`, ADR-0062), which
  catches the squash/rebase shape a merge-commit check cannot see: a push or PR that would put a
  path back to a blob `main`'s own first-parent history already moved past is refused; a deliberate
  restore needs `Restore-override: <path>` plus `Restore-override-reason: <text>` on any commit in
  the PR's own range — a separate key from `Merge-override`, which does not excuse it.
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
- **The merge gate is the unit suite (`PergamenumTests`) plus the in-process tests
  (`Tests/HostedViewPrototypeTests.swift` and siblings), not the GUI suite.** This
  supersedes the rule bought on 2026-08-21 after three of the sixty-seven UI tests had
  been red since before a milestone merge and nothing had said so (`PG-033`) — the fix for
  that gap is now the hosted-view conversions themselves (`docs/plans/ui-suite-replacement.md`),
  not a mandatory full GUI run on every merge. The seventeen GUI tests that remain run
  through `scripts/uitests.sh --affected` at merge time and do not block it; a full run of
  all seventeen is required only before a release (`scripts/release.sh`), not before every
  merge. `--status`'s `contaminated` verdict counts as neither green nor red — the run is
  disturbed, not conclusive, and is rerun rather than acted on either way. A new feature
  carries at most two or three GUI tests, and each one is justified in the feature's own
  ADR: the GUI suite is a bounded, deliberately small backstop, not the default place a new
  test lands.
  The script is not a convenience wrapper: it kills stale instances first, refuses to run
  while a copy out of `/Applications` is open, prints the seconds beside each failure so a
  launch timeout is not mistaken for a defect, and cleans up after itself. Run it with no
  arguments for the whole bundle; an argument **replaces** the selection rather than
  adding to it, because two `-only-testing` flags are a union and would silently run
  everything.
- **Finding this checkout's latest Debug build: pick the DerivedData folder by `WorkspacePath`,
  the build by `Pergamenum.debug.dylib`.** Every worktree gets its own `Pergamenum-<hash>` folder
  under `~/Library/Developer/Xcode/DerivedData` (274 of them on 2026-10-01), so neither sort order
  over `Pergamenum-*` is safe: `ls -d` goes alphabetically by hash, and `ls -dt` returns the
  newest build of *any* worktree - on 2026-09-30 it opened another branch's app, with no
  Contenitore pane, for a hand check. `-t` on the `.app` is wrong on its own terms too: an
  incremental rebuild does not touch the bundle directory's mtime, so it returned a 09:10 build
  twice while the current one was 11:04 (PG-189). The folder's `info.plist` names the workspace it
  builds, and `Contents/MacOS/Pergamenum.debug.dylib` is rewritten by every build:
  ```bash
  WS="$(git rev-parse --show-toplevel)/Pergamenum.xcworkspace"
  DYLIB=$(for dd in ~/Library/Developer/Xcode/DerivedData/Pergamenum-*; do
      [ "$(plutil -extract WorkspacePath raw "$dd/info.plist" 2>/dev/null)" = "$WS" ] &&
          ls "$dd"/Build/Products/Debug/Pergamenum.app/Contents/MacOS/Pergamenum.debug.dylib 2>/dev/null
  done | xargs ls -t | head -1)
  APP="${DYLIB%/Contents/MacOS/*}"    # empty: this checkout has no Debug build yet - build it
  ```
  then `open -n "$APP" --args …` for the hand check.
- **A crash at launch in `initializeWithCopy for <SwiftUI type>` on a Debug build is a stale
  incremental build until proven otherwise.** Swift's incremental compiler does not record the
  underlying type of a `some View` property as a dependency of the files that use it: when a
  commit changes that type in one file (PR #662 added `.accessibilityIdentifier` inside
  `statusBar`, which `NoteListPane+Footer.swift`'s `footer` composes), the file whose view body
  embeds it (`NoteListPane.swift`'s `pane`) is not recompiled, keeps the old layout, and SwiftUI
  copies the value at the wrong size - `EXC_BAD_ACCESS` in `swift_retain` at `0x8`, every launch,
  test host and UI-test app alike (2026-09-29, three DerivedData folders). Confirm by comparing the
  two `.o` timestamps under `Objects-normal/arm64/` (for the UI suite, read the signature from the
  run's `.xcresult` first, as for any red), then move that DerivedData (or `build/uitests-dd`) to
  the Trash and rebuild clean. Move only this worktree's own `Pergamenum-*` folder (the one whose
  `info.plist` names this checkout's `WorkspacePath`, as above), never the newest one by date:
  with several worktrees building, it may be another session's, mid-build.
  A clean build never showed it.
- Build and tests must pass before committing. A change that does not build is not done.
- Keep commits small and atomic, one logical change each.
- Never disable or delete a test to make a suite pass.
- UI language is Italian, with the architecture ready for English localization. Code,
  comments and commits stay in English.
- Update the "Status" section of PROJECT_BRIEF.md when a milestone is reached.
- New dependencies go through `Tuist/Package.swift` followed by `tuist install`, not
  through the Xcode UI.

## ADR index

Every ADR is `docs/adr/NNNN-<slug>.md`; the title below is that file's own heading, so a new ADR needs no line written by hand here: paste what `scripts/adr-index.py` prints, and `scripts/adr-index.py --check` says when the list is behind. Long-form summaries of ADR-0019 to ADR-0090 are in `docs/adr/INDEX.md` (an older instruction to add a line to the "Chain decision index" means that file). ADR conventions (one number per file, the status line, citing an ADR from outside this repo) and the renumbering register: `docs/adr/README.md`.

- ADR-0001 — Initial architecture
- ADR-0002 — "Note" in the interface, and shortcuts the user can move
- ADR-0003 — A new note is composed in the editor, a task in a Craft-shaped panel
- ADR-0004 — A task date can carry an hour, and the day view filters rather than duplicates
- ADR-0005 — The diary is a pane of its own, with a live preview and a ten-minute grid
- ADR-0006 — The hours a timeline draws are a setting, one window per section
- ADR-0007 — The AI connector is a local process over the vault, not a feature of the app
- ADR-0008 — Capture is a global panel, and the write behind it is not the panel's
- ADR-0009 — A view is a saved query over the index, written in a file
- ADR-0010 — Transclusion is a live view of another note, drawn by both surfaces
- ADR-0011 — Templates are notes in a folder; version history is a new store, not WriteJournal
- ADR-0012 — A tab owns the note's state; the tag browser writes one note at a time
- ADR-0013 — The week is a scale of the day, and a task that slipped is surfaced rather than moved
- ADR-0014 — A view can say today, it says it in days, and the day is told to it
- ADR-0015 — Back and forward move between places, and a place is derived rather than stored
- ADR-0016 — The journal records a gesture, and a gesture may move a file
- ADR-0017 — The derived stores leave the vault; what a person chose stays in it
- ADR-0018 — The editor hides the syntax it can draw
- ADR-0019 — A drawn embed is resized by dragging it, and the size is written into the note
- ADR-0020 — An image card is cropped by a rectangle written into the canvas, and the file on disk is never touched
- ADR-0021 — A task carries its Workspace and its place in a project as caret markers in its own line, and nothing new is stored anywhere else
- ADR-0022 — Creating, renaming and deleting a workspace is a folder operation, performed outside the journal
- ADR-0023 — A command is named once and rendered twice
- ADR-0024 — One selection, one row, one meaning
- ADR-0025 — A folder is a container, a board is a file, and neither is named after the other
- ADR-0026 — A row is dragged into a folder, and several rows are chosen first
- ADR-0027 — Unificare Nota e Testo in un solo strumento del Workspace, con formattazione ricca del testo
- ADR-0028 — WYSIWYG markdown rendering (lists + concealment) unified across Nota and Workspace
- ADR-0029 — One editor, always editable, and a table is a grid
- ADR-0030 — The note is a page, and its faces come from the token file
- ADR-0031 — The app can fetch its own next build, and nothing else on it goes near a network
- ADR-0032 — A recording reaches the vault over a socket that never leaves the machine
- ADR-0033 — A view renders in the editor, in an attachment that hosts the renderer it already had
- ADR-0034 — A view is composed through controls, and the controls write the fence the parser already reads
- ADR-0035 — A view block's attachment measures its own content, capped at 320pt
- ADR-0036 — A pratica is a folder that fills itself from a copy of Mail's index, and never from Mail
- ADR-0037 — The reveal unit shrinks from the paragraph to the span
- ADR-0038 — The Conformità UI surfaces are removed; the linter stays CLI/MCP-only
- ADR-0039 — Task ↔ note/board link and navigation
- ADR-0040 — An attachment Mail has not finished writing is a state, not a file
- ADR-0041 — The vault layer gets one boundary, one walk, and one place where the disk is touched
- ADR-0042 — An inline image Mail has not sent yet is a hole in the prose, not an attachment
- ADR-0043 — The ordering guard has to cover every writer, not the one that asked for it
- ADR-0044 — CI checks that the three targets compile from a clean checkout, and nothing else
- ADR-0045 — The pratiche layer splits by file, and names which `private` widens
- ADR-0046 — A batch rename refuses the file that moved on, one file at a time, and says which
- ADR-0047 — Categories are a registry in the vault, the tag stays the pointer, and the Obsidian round-trip stops being a constraint
- ADR-0048 — An attachment part decoding to zero inline bytes is not always "not yet downloaded"
- ADR-0049 — A pratica links to notes, tasks and boards by writing the shape the rename passes already rewrite
- ADR-0050 — The journal gesture travels with the task that writes, not with the session
- ADR-0051 — Tests, the design gallery and the scripts each get one shared helper, and the copies not worth closing are named
- ADR-0052 — The Pratiche ledger is written only over the ledger it was loaded from
- ADR-0053 — The seams that let the unit suite replace the UI suite as the merge gate
- ADR-0054 — The open board proves what it is writing over
- ADR-0055 — The note half of a rename proves what it is writing over, and the performer nothing calls leaves
- ADR-0056 — An external change, a rename and a trash reach every tab that shows the note
- ADR-0057 — The diary proves what it writes over, one write at a time
- ADR-0058 — An in-process write, a save and a restore reach every tab that shows the note
- ADR-0059 — Stable note ids live in a registry file in the vault, not in the index
- ADR-0060 — ADR-0057's remaining follow-ups — five write sites, quit flush, board navigation
- ADR-0061 — A merge that silently discards an ancestor's content is refused, not just noticed
- ADR-0062 — A landing that restores a version `main` already moved past is refused, whatever the merge method
- ADR-0063 — The connectors refuse malformed input, board creation goes through the session's guarded door, and five more sites resolve through the vault boundary
- ADR-0064 — An external deletion reaches the editor tabs and the Diario pane, not just the index
- ADR-0065 — Every on-disk format round-trips faithfully or is refused
- ADR-0066 — Workspace board lifecycle — one reset door, every leave path settles then flushes
- ADR-0067 — One door onto the editor after a landed change
- ADR-0068 — Pratiche sync integrity — every note operation through the session, nineteen edges closed
- ADR-0069 — The attachment chip's context menu is an AppKit menu, because the `List` row's own `.contextMenu` takes every right-click inside the row
- ADR-0070 — Backspace in the pratica timeline runs the row's own «Escludi», on a route chosen by measuring who holds the key
- ADR-0071 — Contenitore, a managed document archive fed from a drop folder
- ADR-0072 — One index generation keys every index-derived cache; a disk-derived value is cached for one body evaluation, never longer
- ADR-0073 — Quitting reviews unsaved notes first: one question, one save door, one reply
- ADR-0074 — The editor's Coordinator keeps the order of the passes; each feature's state moves into a controller that owns it
- ADR-0075 — Day-boundary and calendar math — a time block ends at 24:00 and is placed in free time, an event is drawn on each day as the part of it that day covers
- ADR-0076 — A manual entry anchors to one message by its Message-ID, through one shared parser, one ordering rule and guarded body writes
- ADR-0077 — The HTML exporter renders from the shared markdown parsers, and escapes once, at emission
- ADR-0078 — A note's frontmatter can be hidden through the fold pass, never through the file
- ADR-0079 — An excluded message takes its anchored entries out of the app's timeline, and an anchored entry hangs off its message by a rail
- ADR-0080 — A note born without a topic is a capture, a capture's title is derived rather than refused, and the inbox folder is a setting
- ADR-0081 — Block markers reveal in the gutter
- ADR-0082 — The styler classifies through the shared parsers
- ADR-0083 — Links answer to the pointer and the keyboard
- ADR-0084 — Backlinks with context, unresolved per note, mentions that link
- ADR-0085 — A «Da classificare» pane for notes, one «Classifica» verb, and one composer
- ADR-0086 — Templates where notes are born
- ADR-0087 — The editor draws the remaining constructs
- ADR-0088 — One word-boundary truncator, and a capture title the panel always shows
- ADR-0089 — A conflicted board or diary is asked about at quit
- ADR-0090 — The editor's pointer is decided and drawn by AppKit, from two overrides
