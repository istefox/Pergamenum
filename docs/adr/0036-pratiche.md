# ADR-0036: A pratica is a folder that fills itself from a copy of Mail's index, and never from Mail

- Status: proposed
- Date: 2026-09-09. Written after reading every file it names, at the line, on the working tree at
  `76ac529` (`main`, ADR-0035 merged through PR #181/#183). Every claim below about this repo's
  code was read out of `Sources/`, not out of the SPEC; every claim about SQLite was measured with
  a compiled probe on this Mac on this date. Facts about Apple Mail's store come from the SPEC's
  own verified-facts block of the same date, and the two that the SPEC leaves ambiguous are
  designed around rather than assumed (§D3, §D4).
- **Relocation note:** this file is written at `docs/architecture/ADR-0036-pratiche.md` because
  that is the architect's enforced write scope (`test-write-scope.sh`); the orchestrator relocates
  it to `docs/adr/0036-pratiche.md`, which is where this repo's ADRs live (`0001`…`0035`) and which
  is the path every reference below and in the plan assumes. Same convention ADR-0029, ADR-0030,
  ADR-0031, ADR-0032, ADR-0033 and ADR-0034 carry in their own headers.
- **Amends SPEC §14** in one row: «Rendering corpo email — Escluso» becomes «Rendering *HTML* del
  corpo email — Escluso; estrazione del testo del corpo in markdown leggero — Inclusa dal
  2026-09-09 (pratiche)» (§D16). The Workspace `.eml` card keeps headers only.
- **Amends the SPEC's own data model in two measured places** (§D11): both frontmatter examples in
  the SPEC fail this repo's linter as written, because `Tag.missingRequired` demands `type-note`
  **and** a `topic-*` on every note that is not a daily note. The tag sets are corrected here.
- **Does not reopen the closed frontmatter schema.** ADR-0032 §D6 already opened
  `^pergamenum-[a-z0-9]+(-[a-z0-9]+)*$` in `FrontmatterRules.validate` (`Frontmatter.swift:359-367`,
  read at the line). The `pergamenum-dossier-*` and `pergamenum-mail-*` keys are lint-clean the day
  they are written, with **no edit to `Frontmatter.swift`** — this chain spends that precedent, it
  does not extend it.
- **Adds no exception to CLAUDE.md principle 2.** No network call, no socket, no loopback. This
  feature reads local files. ADR-0031's Sparkle exception and ADR-0032's loopback exception are
  untouched and are not widened.
- **Supersedes nothing.** No mechanism of ADR-0018, ADR-0023, ADR-0024, ADR-0026, ADR-0029,
  ADR-0030, ADR-0032, ADR-0033, ADR-0034 or ADR-0035 is reopened. No editor delegate, text
  container, attachment, canvas property or index field is touched. `IndexCache.schemaVersion`
  stays 3.
- Depends on: **ADR-0007 §D2/§D3/§D4** (`sharedSources`, the connector boundary, why EventKit is
  absent from both tools — the reason the Mail store is absent too), **ADR-0017 §D1/§D2** (derived
  per-vault state lives beside the vault, keyed by the vault's UUID), **ADR-0020** (a prefixed key
  is how this repo extends a closed schema), **ADR-0023 §D1/§D5** (a command is declared once and
  rendered on every surface; the shortcut catalogue is the set of *rebindable* shortcuts, not of
  all commands), **ADR-0024 §D1** (flat recursive rows, never a `DisclosureGroup`, inside
  `List(selection:)`), **ADR-0026 §D5** (undo registers on the window's `@Environment(\.undoManager)`),
  **ADR-0031 §D4** (a launch argument, not a compile-time flag, keeps a system out of the UI suite),
  **ADR-0032 §D6/§D10/§D15** (the frontmatter namespace, per-vault non-vault state, the pane row
  and its shortcut measurement), **ADR-0034 §D11** (`FolderPickerMenu`, which already exists and is
  reused rather than rebuilt).

---

## Context

A **pratica** is one matter with one counterpart: an offer, a claim, a negotiation. It exists in no
tool. Mail knows threads that split on every subject change; the Finder knows attachments; the
phone calls are in somebody's head. The SPEC's objective is to make the pratica a folder in the
vault that fills itself from Apple Mail's *local store* and shows one chronological, two-lane
timeline.

Everything this feature needs is already on this Mac and already local: `~/Library/Mail/V10/` holds
128,877 `.emlx` files and a 127,818-row SQLite `Envelope Index`. Nothing has to be fetched. What
has to be decided is how a program reads a database another program is writing to, without
corrupting either, without a dependency, and without ever putting a permission prompt or somebody
else's correspondence in front of a test run.

### What was read in this repository, at the line, before deciding

Eleven findings. The first four would each produce a shipped defect if the SPEC were implemented
literally; the rest close design questions the SPEC left open.

1. **Both of the SPEC's frontmatter examples fail this repo's linter.**
   `Tag.missingRequired` (`Sources/Core/Conventions/Tag.swift:133-152`) demands `type-note`, and a
   `topic-*` unless the note wears `status-inbox`; `NoteName.category`
   (`Sources/Core/Conventions/NoteName.swift:89-98`) returns `.note` for every file whose stem is
   not a compact date, so there is no category a pratica or a message file could fall into that
   escapes the rule. The SPEC's `pratica.md` (`[type-note, client-rossi, status-active,
   source-email]`) is missing `topic-*`; the SPEC's message file (`[type-email, client-rossi,
   source-email]`) is missing both. R-37 requires both to pass. §D11.
2. **`status-final` may not be written on a pratica.** `NoteCategory.allowsStatus`
   (`Tag.swift:207-215`) reserves `status-final` for a Deliverable. The SPEC's sidebar groups
   «Chiuse» as `archived`/`final`. Writing `final` on `pratica.md` would be a lint violation
   authored by the app — the same defect class as issue #30, which this repo already paid for.
   §D11.
3. **A `pergamenum-*` key is stored as raw YAML lines, not as a typed value.**
   `Frontmatter.ForeignKey` is `{ name, lines: [String] }` (`Frontmatter.swift:33-36`), preserved
   in source order, and the serializer writes the four closed keys and then those lines verbatim
   (`:171`). A dossier carrying five list-valued keys therefore needs a **line codec** of its own,
   not a `Codable` conformance. §D12.
4. **`EmailHeaders.mailURL` and `MailLink.url(forMessageID:)` percent-encode the same message id
   two different ways**, and the SPEC names the first one. `mailURL` allows only
   `alphanumerics + -._~`, so `@` becomes `%40`; `MailLink.url` allows `urlPathAllowed` minus `%`,
   so `@` stays literal, and wraps the brackets by hand as `%3C…%3E`
   (`EmailHeaders.swift:35-42`, `MailLink.swift:26-36`). `mailURL` has **no production call site**
   — grepped: `Tests/EmailTests.swift:149` and `:159` are its only two callers. `MailLink.url` is
   the one that ships, through `MenuCommands.swift:226`. §D9.
5. **`import SQLite3` needs no dependency and no manifest change.** Measured on this Mac on
   2026-09-09: a plain `xcrun swiftc` build of a file importing `SQLite3` and calling
   `sqlite3_open_v2` compiles, links and runs, reporting `sqlite3_libversion()` = **3.51.0**. GRDB
   is not in this repo and does not need to be. §D1.
6. **The unit suite already has the mechanism that keeps a real system out of it.**
   `VaultState.processDefaultBase()` is test-aware (`VaultState.swift:97-120`), and
   `Tests/SharedSourcesPurityTests.swift` walks the repository from `#filePath` to turn a manifest
   fact into a test that runs every turn. Both are reused rather than reinvented. §D7, §D14.
7. **`Sources/Features/**` is not in `sharedSources` and the app target globs `Sources/**`**
   (`Project.swift:70-113`, `:190-192`), so no new file under `Sources/Features/Pratiche/` needs a
   manifest edit. A new file under `Sources/Core/**` is picked up by the glob automatically and
   **must stay Foundation-level**, or both connector builds break (ADR-0001 §D1 enforcing itself).
8. **The pane shortcut digits are exhausted.** `paneRecordings` took Ctrl+Cmd+0 in ADR-0032 §D15,
   which was the last one (`ShortcutCommand.swift:283-286`). The eleventh pane cannot follow the
   convention, and `everyShippedDefaultIsUsable` (`Tests/ShortcutTests.swift:66-71`) forbids a case
   with no valid binding, so "no shortcut" is not available either. §D8.
9. **Cmd+Opt+I is already taken** by `toggleInspector` (`ShortcutCommand.swift:294`), which the UX
   blueprint proposes for the pratica inspector. One command that means "the inspector of the pane
   in front" is the ADR-0023-shaped answer; a second case on the same keys would fail
   `noTwoCommandsShipOnTheSameKeys`. §D8.
10. **`FolderPickerMenu` exists** (`Sources/Features/Views/ViewQueryTermRow.swift:173`), extracted
    by ADR-0034 §D11 for exactly this kind of reuse. The wizard's client picker is that menu, not a
    tree. Similarly `QuickLookPresenter` (`Sources/Features/QuickLook/`) and `MarkdownBlocksView`
    (`Sources/Features/Editor/MarkdownBlocksView.swift:13-28`) already exist with the shapes the
    timeline needs.
11. **`VaultSettings` has exactly one construction site**, its own `static let default`
    (`VaultSettings.swift:133`), and a hand-written tolerant `init(from:)` that defaults every key
    (`:167-210`). Growing it is additive and cheap, provided the new value is decoded the same
    tolerant way. §D10.

### The two things about Mail's store that are not known and are designed around

The SPEC verified the store's shape on 2026-09-09 and is trusted on it. Two details it does not
pin down would each be a silent, invisible failure if guessed:

- **What `messages.message_id` actually holds.** The SPEC writes «index lookup by `message_id`
  hash → row → `conversation_id`», which reads as an integer hash of the RFC 5322 Message-ID by an
  algorithm Apple does not document. If it is a hash, no query can find a row from a `Message-ID`
  string. §D3 removes the dependency entirely instead of betting on it.
- **How a ROWID becomes an `.emlx` path.** Mail fans messages across nested numeric directories
  under `<mailbox>.mbox/<uuid>/Data/…/Messages/`. A wrong rule finds no file, and "no file" is a
  *legitimate* state of this feature (R-16, a message deleted in Mail), so a wrong rule would be
  indistinguishable from correct behaviour. §D4 makes the two distinguishable and probes the rule
  before relying on it.

Nothing in this ADR reads the real store. The probe that answers both questions is a named,
human-present task in the plan (Task 1), it prints schema and paths only, never message content,
and its two possible outcomes both have a designed implementation.

---

## Decision

### §D1 — SQLite is read through the system `SQLite3` module, from one file family, with prepared statements

`import SQLite3` in `Sources/Core/Email/MailStore*.swift`. No package, no module map, no
`Tuist/Package.swift` edit, no `Project.swift` edit. Measured working on this Mac (finding 5).

Three rules bind:

- **`sqlite3_` appears in `MailStoreConnection.swift` and nowhere else.** Every query is a method on
  it returning value types. A second file reaching for the C API is a stop-and-report.
- **Every value is bound, never interpolated.** `sqlite3_bind_text` with the transient destructor,
  which Swift does not import: it is spelled
  `unsafeBitCast(-1, to: sqlite3_destructor_type.self)`, because the `SQLITE_TRANSIENT` macro is
  invisible to the Swift importer. Binding a `String` without it hands SQLite a pointer that is
  dead before `sqlite3_step` runs, and the symptom is intermittently wrong rows, not a crash.
- **`SQLITE_OPEN_CREATE` is never passed.** A missing copy must fail loudly; with `CREATE` it would
  produce an empty database and a sync that reports «nessun messaggio» forever.

### §D2 — The store is read from a published generation copy, never from Mail's live file

`MailStoreCopy` writes into `…/vaults/<id>/pratiche/index/.staging-<uuid>/`, then publishes with a
single directory rename to `…/index/<sourceModificationStamp>/`, then deletes older generations.
One rename is one atomic syscall; three separate file renames are three chances to be interrupted
between them.

Inside the staging directory, before publication:

1. Copy `Envelope Index` and `Envelope Index-wal`. **The `-shm` is never copied**: it is shared
   memory belonging to Mail's own processes, and a stale one beside a fresh database is worse than
   none — SQLite rebuilds it.
2. Open the copy **read-write** (`SQLITE_OPEN_READWRITE`, no `CREATE`) so SQLite recovers the WAL
   into it. Writing to our own copy cannot touch Mail; opening Mail's file at all is what R-02
   forbids, and this never does.
3. `PRAGMA quick_check` plus one `SELECT count(*) FROM messages`. A torn copy — Mail wrote between
   the two `copyItem` calls — surfaces here as `SQLITE_CORRUPT`/`SQLITE_NOTADB` rather than as
   missing messages later. On failure: discard the staging directory, retry once after 2 s, then
   report «Mail sta scrivendo, riprovo più tardi» and leave the previous generation published.
4. `CREATE INDEX IF NOT EXISTS` on the copy for `conversation_id` and `sender`. This is the answer
   to «127,818 rows»: one index build per generation, off the main actor, in exchange for
   millisecond per-pratica queries. It is possible only because the copy is ours.
5. `PRAGMA query_only = 1` for the query session, after recovery has happened.

The copy is skipped entirely when the source's modification date is unchanged since the published
generation's stamp (R-02).

### §D3 — The ledger is the `Message-ID` ↔ index-row bridge; the index is never asked to resolve a `Message-ID` string

At import time the ledger records, per message, the triple **(RFC `Message-ID`, index ROWID,
`conversation_id`)**. Re-deriving a renumbered `conversation_id` (R-14) is then a lookup in our own
file, not a query against a column whose contents are a guess.

`MailStoreReader.row(forMessageID:)` (R-03) exists and is implemented **only if Task 1's probe
proves the index stores the RFC id in a queryable form**. If it does not, the method resolves
through the ledger and returns `.notResolvableFromIndex` for anything never imported, which is a
state the tray already has to render («non più ricostruibile», SPEC Edge cases). Either outcome
satisfies R-03 and R-14; neither is discovered at 3am.

### §D4 — `.emlx` location is a probed rule with an enumerated fallback, and «not found» is never silent

`EMLXLocator.url(forRowID:inMailbox:)` returns
`.found(URL)` / `.notInStore` / `.ruleFailed(candidatesTried: [String])`.

- The digit-fan rule is written from **Task 1's probe on three real rows**, not from memory, and
  pinned by fixture tests.
- `.ruleFailed` triggers one bounded directory enumeration of that mailbox's `Messages/`
  directories, cached per mailbox for the sync's lifetime; a hit repairs the answer and **records a
  diagnostic**, so a rule that has drifted is visible instead of degrading into R-16's legitimate
  «non più in Mail».
- `.notInStore` is the only state that becomes «non più in Mail». R-16's caption is never shown for
  a locator bug.

### §D5 — `pratica.md` has exactly one editor, and it is the inspector

The UX blueprint asks the architect to name the single owner of a manual entry's text and
recommends binding timeline rows to heading ranges of the open editor buffer. **The single-owner
requirement is adopted; the range-binding implementation is rejected.**

- The timeline draws every manual entry **read-only**, with `MarkdownBlocksView` — the same
  renderer an expanded message body uses.
- Editing an entry means putting the caret in `pratica.md`, which is open in the inspector column
  beside the timeline. Creating an entry (R-28), clicking one, or pressing Return on one, opens the
  inspector if closed and sends `Navigation.jumpToLine(range:ordinal:)` — the mechanism that
  already exists for the outline and for a task row in the week (`Navigation.swift:180-210`).
- Nothing in the timeline ever writes a text range. The timeline's only writes are: insert one
  heading (one atomic `VaultSession.write`), and the daily-note line (R-29).

Reason: *n* live `NSTextView`s bound to *n* ranges of one file, inside a `List` that culls rows,
while a background sync may rewrite that same file, is the shape of every text-loss defect this
repo has documented — the culling deallocation named in ADR-0029, the zero-rect layout trap in
CLAUDE.md, and the `growToFitTheText` regression that once cost the Diario its typed text. R-28's
«editable inline con il motore dell'editor» is satisfied literally: the editor engine, on the
pratica note, on screen, with the caret placed for you.

### §D6 — A sync never rewrites a message file, with exactly two exceptions

Exceptions: a `pergamenum-mail-body: pending` file whose body has since arrived (R-15), and an
explicit «Rigenera», which shows a `UnifiedDiff` first (the type already exists,
`Sources/Core/UnifiedDiff.swift`). A sync **never deletes a file** (R-16): a message gone from Mail
loses its link, not its file.

### §D7 — `MailStoreLocation` is test-aware, and fixtures are built by code

`MailStoreLocation.resolve()` returns, in order: the `-mailStoreRoot` launch argument when present
(R-19), a per-process temporary fixture root when `VaultState.isRunningUnderTest`, and only then
`~/Library/Mail/V10`. This mirrors `VaultState.processDefaultBase()` exactly, and it means the unit
suite cannot reach the real store **even on a machine whose test host has been granted Full Disk
Access** — which this Mac's terminal demonstrably has (a `test -e` on the index succeeded here on
2026-09-09).

Fixture stores are **generated by a helper that creates a small SQLite file and writes `.emlx`
bytes**. No file is ever copied out of `~/Library/Mail` into `Tests/`. A fixture built from real
mail is somebody's correspondence in version control, which is the same rule
`-disableCalendar` exists for.

All 19 existing `UITests/` files gain `-mailStoreRoot <fixture>` beside `-disableCalendar YES` and
`-disableUpdater YES`, and so does every new one.

### §D8 — Three new shortcut commands, one of which breaks the pane-digit convention, and no fourth

| Command | Binding | Why |
|---|---|---|
| `panePratiche` | Ctrl+Cmd+P | The digits ran out at ADR-0032 §D15 (finding 8). The pane family moves to a mnemonic letter here; the next pane after this one does the same. |
| `newPratica` | Cmd+Opt+P | File menu, UX blueprint. |
| `addToPraticaFromMail` | Cmd+Shift+P | Inserisci menu, UX blueprint. |

Checked against the whole catalogue by hand before proposing: nothing holds Ctrl+Cmd+P, Cmd+Opt+P
or Cmd+Shift+P today. All three are appended at the end of the enum, never inserted — the raw
values are the keys of the overrides file (ADR-0005 §D8). All three must additionally be **measured
against `com.apple.symbolichotkeys` at wiring time**, as ADR-0032 §D15 did for Cmd+R.

**No case for the pratica inspector**: `toggleInspector` becomes pane-aware, toggling
`Navigation.isShowingInspector` in the Note pane and `Navigation.isShowingPraticaInspector` in this
one. **No case for «Aggiorna ora»**, which the blueprint deliberately leaves toolbar- and
menu-only; ADR-0023 §D5 already says the catalogue is the set of rebindable shortcuts, not the set
of commands.

### §D9 — One `message://` builder, and its encoding is measured once

`EmailHeaders.mailURL` keeps its name and its call shape (the SPEC names it, R-26) and is
re-pointed at a single Core function implementing **the encoding that ships today**, i.e.
`MailLink.url(forMessageID:)`'s. `MailLink.url` then delegates to the same function, so the two
cannot drift again.

This changes `EmailHeaders.mailURL`'s output for any id containing `@`, which is all of them. Its
only two callers are `Tests/EmailTests.swift:149` and `:159` (grepped, finding 4) and they are
updated in the same task. Before the change lands, one measurement: build both forms for one real
message id and `NSWorkspace.open` each. If the `%40` form wins, the shared function takes that
encoding instead and `MenuCommands`'s «Copia link» changes with it — either way there is one
implementation and one measurement behind it, not two encodings and a coin toss.

### §D10 — The pratiche settings are one nested value inside `VaultSettings`

`VaultSettings` gains a single field, `pratiche: PraticheSettings`, decoded
`decodeIfPresent(...) ?? .default` in the existing tolerant `init(from:)`, with a defaulted
parameter in the memberwise initialiser. One construction site exists (finding 11), so the change
is additive. `PraticheSettings` carries: root folder (default `01 Progetti`), own addresses,
`.eml` retention (on), attachment threshold MB (100), proposal window days (90), daily-note
mirroring (on). Values are clamped on the way in like `blockMinutes` and `rolloverDays` already
are: a hand-edited `0` for the proposal window must not silently mean "propose nothing".

Own addresses are per-vault, per the SPEC's own reasoning: the vault is personal.

### §D11 — The tag sets that actually pass the linter, and `status-final` is never written

- `pratica.md`: `type-note`, `topic-pratica`, `client-<slug>`, `status-<active|waiting|archived>`,
  `source-email`. Five tags, under the limit of seven (`Tag.maximumTagsPerNote = 7`).
- message `.md`: `type-note`, `type-email`, `topic-pratica`, `client-<slug>`, `source-email`. Two
  `type-*` tags is legal — only `status` is limited to one (`Tag.swift:106-109`) — and `type-note`
  is what `missingRequired` demands of every non-daily note.
- **«Chiuse» means `status-archived`.** `status-final` is read and grouped if a person writes it by
  hand, and never written by the app (finding 2). Chiudi/Riapri swaps `active` ↔ `archived` (R-34).

A unit test asserts zero violations from the real `Tag.violations` for both generated files, the
same guard ADR-0032 shipped.

### §D12 — The dossier is a line codec over `Frontmatter.ForeignKey`, not a `Codable` model

`Dossier` renders and parses a deliberately tiny YAML subset — scalar `Int`, scalar `String`,
`- ` string list, inline `[1, 2]` int list — directly over `ForeignKey.lines` (finding 3), and
round-trips byte-for-byte on anything it did not write. It never touches `date`, `tags`, `related`
or `aliases`, and it never reorders foreign keys it does not own.

The keys are exactly the SPEC's: `pergamenum-dossier`, `-counterparts`, `-conversations`,
`-keywords`, `-included`, `-excluded`, `-ignored`.

### §D13 — The pane is composed like `VaultBrowser`, and the tree is flat rows

Top bar above an `HSplitView` of list column (190–320, ideal 260) · timeline (min 360) ·
inspector (190–320, ideal 280) — the composition `VaultBrowser.swift:17-33` uses, not
`RecordingsPane`'s single column. The app sidebar stays flat: one row, «Pratiche», in the LAVORO
group immediately before «Registrazioni».

The pane's own tree is flat recursive rows with `.tag` on the pratica's folder path, per ADR-0024
§D1. A client folder row is a group row and carries **no `.tag`**, which is what makes it
structurally unselectable rather than disabled-by-remembering. `.badge` is applied **before**
`.tag`, or the tag is dropped and the list lights nothing (CLAUDE.md's own working agreement, paid
for once already).

### §D14 — Sync is one actor, the connection never leaves it, writes hop to the main actor per message

`PraticaSyncEngine` is an `actor` owning the `MailStoreConnection` (an `OpaquePointer` is not
`Sendable`; it must not cross an isolation boundary). Queries and decoding — MIME walk, HTML
reduction, quote splitting, SHA-256 — happen inside it and produce `Sendable` value types. Each
finished message hops once to `@MainActor` to be written through `VaultSession`, which is where
every write in this app already happens. Cancellation is checked at that boundary, which is
exactly what makes «everything written is complete, resume from the ledger» true (R-11).

### §D15 — A `Message-ID` seen in two mailboxes is resolved once, before any write

Sent, Archive and a shared mailbox routinely hold the same message. The candidate set is
deduplicated by RFC `Message-ID` before the first file is written; the surviving row is the one
whose mailbox is neither Trash nor Junk, and among the rest the lowest ROWID. Direction is decided
by `From` against own addresses and **never** by mailbox (R-12), so which duplicate wins cannot
change which lane the row lands in.

### §D16 — SPEC §14's email row is amended, narrowly

Row 500 of `docs/20260811_Pergamenum_SpecApp.md` («Rendering corpo email | Escluso | Nessuna
libreria Swift mantenuta; il doppio click su Mail è sufficiente») becomes «Rendering **HTML** del
corpo email | Escluso | …; estrazione del testo del corpo in markdown leggero inclusa dal
2026-09-09 (pratiche): il costo escluso era quello di mantenere un renderer HTML, che un riduttore
a testo non ha». No WebView, no `.html` sidecar, no styled rendering. The Workspace `.eml` card is
unchanged.

### §D17 — Full Disk Access is probed per trigger, never at launch

`FullDiskAccessProbe` calls `open(2)` for reading on the index path and reads `EPERM` as "not
granted". macOS does not prompt for Full Disk Access — it denies silently — so the probe cannot
raise a dialog; the reason it still never runs at launch is that a per-launch touch of somebody's
mail store is not something an offline notes app should do. It runs on the pane's triggers only,
which is also what makes "granted later, no restart" true (R-18).

One supporting fact already in this repo: `Project.swift:14-19` sets `CODE_SIGN_IDENTITY` to
`Apple Development` precisely because TCC keys a grant to the signing identity, and an ad-hoc
signature re-keys on the binary hash and loses the grant on every rebuild. The FDA grant therefore
survives development rebuilds for the same reason the Calendar grant now does.

### §D18 — A `pending` message gets no `.eml`

There are no complete RFC 822 bytes to keep. `pergamenum-mail-original` is absent until the body
arrives and the file is regenerated (§D6's first exception).

### §D19 — The connectors are structurally unable to open the Mail store

`Sources/Core/Email/MailStore*.swift` compiles into `perg` and `pergamenum-mcp` because
`sharedSources` globs `Sources/Core/**`. Compiling is not calling. The guarantee is enforced, not
asked for: `SharedSourcesPurityTests` gains a case asserting that **no file under
`Sources/Connector`, `Sources/CLI` or `Sources/MCPServer` names `MailStore`, `EMLXReader` or
`SQLite3`**. `VaultAPI.pratiche` and `VaultAPI.pratica` read what is on disk, in the vault, and
nothing else (R-36) — for the same reason EventKit is absent from both tools (ADR-0007 §D4): TCC
would attribute a command-line tool's access to the terminal that launched it.

### §D20 — Deferred, and recorded as deferred

Out of this chain, into TODO.md at Step 7b (R-41): ChatGPT inside Pergamenum, «Apri come board»,
the `pergamenum://pratica/add?message=…` URL-scheme entry point, and connector **write** access to
pratiche. Also out, permanently unless a new ADR reopens them: HTML rendering, any network path,
IMAP, a Pergamenum CC address, a MailKit extension, Contacts and calendar integration, composing
mail.

---

## Alternatives considered

**A1 — Add GRDB and read the index through it.** Rejected. It is a third-party dependency added to
a repo with exactly two (MCP SDK, Sparkle), and `Sources/Core/**` compiles into both command-line
tools, so the dependency would land in all three targets to serve five read-only queries. The
system module measured working (finding 5) costs one `import` and no manifest edit. GRDB would also
tempt the codebase toward using it for the index cache, which ADR-0001 §D2.3 deliberately keeps
hand-written.

**A2 — Shell out to `/usr/bin/sqlite3`.** Rejected. It puts a text format and a process boundary
between two programs that can pass values, gives no typed errors, and makes quoting a correctness
problem. It would also mean `Foundation.Process` inside `Sources/Core`, which every connector
inherits.

**A3 — Open Mail's live `Envelope Index` read-only with `immutable=1` instead of copying.**
Rejected, and it is the most tempting alternative because it looks cheaper. `immutable=1` tells
SQLite the file cannot change and to ignore the WAL — so every message Mail has written since the
last checkpoint is invisible, which is precisely the recent mail a pratica is about. Without
`immutable=1`, a read-only open of a WAL database needs to write the `-shm`, in Mail's own
directory, under Mail's own lock. R-02 forbids the whole class.

**A4 — `sqlite3_backup_init` (the online backup API) against the live file.** Rejected. It is the
correct way to copy a database you may open, and opening Mail's is exactly what R-02 forbids. The
file-level copy plus `quick_check` plus one retry (§D2) reaches the same place without ever holding
a handle on Mail's file.

**A5 — AppleScript as the acquisition engine, not the fallback.** Rejected, and the SPEC already
rejected it: seconds per hundred messages, an Automation dialog, no way to enumerate conversations,
and it only works while Mail is running. Kept as the manual seed path (R-21), where its cost is one
dialog and its benefit is that it needs no Full Disk Access at all — which is what keeps the
feature usable in the not-granted state (R-18).

**A6 — Bind timeline rows to text ranges of the open `pratica.md` buffer** (the UX blueprint's own
recommendation). Rejected on evidence, see §D5: many live text views over one file, inside a
culling `List`, with a background writer. The blueprint's actual requirement — one owner, the two
never diverge — is met by having one editor rather than by keeping *n* of them in step.

**A7 — Store messages as `.eml` only, and render them.** Rejected by the SPEC and confirmed here:
an `.eml` is opaque in Obsidian, invisible to this app's index and unreadable by the connectors.
The markdown file is the artefact; the `.eml` is the fidelity copy beside it, and is optional.

**A8 — A `.canvas` board as the primary view of a pratica.** Rejected for now, deferred as a
future chain (§D20). Eighty messages make a wall, and there is nowhere on a board for a phone call
that belongs between two of them.

**A9 — A twelfth `Navigation.Pane` shortcut on a digit, by renumbering the panes.** Rejected.
`ShortcutCommand`'s raw values are the keys of the overrides file (ADR-0005 §D8); renumbering
silently moves a binding somebody changed. The convention breaks instead (§D8), visibly, in one
place, with the reason written down.

**A10 — A second inspector-toggle command for this pane.** Rejected: it would collide with
`toggleInspector` on Cmd+Opt+I and fail `noTwoCommandsShipOnTheSameKeys`, and it would mean two
commands whose titles a person cannot tell apart in Impostazioni › Scorciatoie. One pane-aware
command is the ADR-0023 shape.

**A11 — Keep both `message://` encodings and use whichever is nearer.** Rejected. Two encodings for
one URL scheme is a defect waiting for the first id that behaves differently under them, and it is
already unclear which of the two Mail actually accepts. One function, one measurement (§D9).

**A12 — Copy a real `Envelope Index` into `Tests/` as the fixture.** Rejected outright. It is
somebody's correspondence in version control, and it makes the fixture unshareable and
unregenerable. Fixtures are built by code (§D7).

---

## Consequences

### Positive

- The pratica exists as **files**: a folder, markdown per message, real attachments. Principle 1
  holds without qualification — delete the app and the matter is still readable, in Obsidian, in
  the Finder, by `grep`.
- **No new dependency, no schema bump, no migration.** `IndexCache.schemaVersion` stays 3, no
  `.canvas` property is added, no protected interface is broken, `Tuist/Package.swift` and
  `Project.swift` are untouched.
- **The app stays offline.** This is the first large feature since M0 that adds no exception to
  principle 2 at all.
- The messages become ordinary vault content: indexed, searchable, wikilinkable, visible to
  `perg search`, and to the `pergamenum-mcp` tools, without any of them knowing Mail exists.
- The `Envelope Index` copy is **ours to index**, which turns "127,818 rows" from a performance
  risk into a one-second cost per generation (§D2).
- The two genuinely unknown facts about Mail's store are isolated behind two seams (§D3, §D4) with
  both outcomes designed, instead of being discovered by a user whose pratica silently stopped
  filling.
- Full Disk Access being absent degrades the feature to "manual seeding still works" rather than to
  "the pane is broken" (R-18).

### Negative

- **Full Disk Access is a real barrier.** It cannot be prompted for, only explained, and a person
  who does not grant it gets a materially smaller feature. The banner is the whole mitigation.
- **The feature reads a private, undocumented, unversioned Apple format.** A macOS update that
  changes the Envelope Index schema or the `.emlx` layout breaks acquisition with no warning. The
  fixture suite pins our understanding, not Apple's behaviour: it will stay green while the real
  store has moved on.
- **A copy of the Envelope Index lives in Application Support.** It is a few hundred megabytes of
  mail *metadata* — subjects, addresses, dates — outside `~/Library/Mail`, in a directory nothing
  else guards. It is regenerable and deletable, and it is still a real widening of where that data
  sits.
- **`EmailHeaders.mailURL` changes output** (§D9). Two test call sites, both already listed, and a
  behaviour change in a function whose name is unchanged.
- **The pane-shortcut convention breaks** (§D8). Ctrl+Cmd+P beside ten Ctrl+Cmd+digits is a seam a
  future reader will trip over, and the ADR is the only place that explains it.
- **The eleventh Settings tab may collapse the toolbar** into an unlabeled overflow popup. The
  threshold is undocumented and was found empirically at eight tabs / 620 pt
  (`SettingsView.swift:29-38`); eleven tabs at 700 pt is unmeasured. The named fallback is to widen
  the window, never to nest the tab.
- **`.dropDestination` against Mail's file promise is unproven** (R-22). If it fails the feature
  ships with one acquisition path fewer, and the ADR records the probe rather than the wish.
- **The timeline cannot be edited in place** (§D5). Clicking an entry moves the caret to the
  inspector instead of typing where you clicked, which is one step more than the mockup implies.

### Neutral

- Manual entries are level-2 headings in an ordinary note. Anything that already understands this
  vault's markdown — the outline, the task parser, the linter, Obsidian — sees them without being
  told.
- The daily-note mirror (R-29) writes through `VaultSession.write` like everything else, so it is
  journalled, undoable through the ordinary path, and visible to the watcher.
- Three new colour tokens is the eleventh group in the theme files; both themes are edited
  together, as they always are, and the token-completeness check enforces it.
- Nothing in this chain touches the editor, the canvas, the tasks module or the index.
- The `pergamenum-` frontmatter namespace gains eleven more keys. That widening happened at
  ADR-0032; this chain is the first to lean on it at scale, which makes the greppability of the
  prefix load-bearing rather than incidental.

---

## Follow-up — Task 1 probe results (2026-09-09)

Both probes ran on a copy published by `MailStoreCopy.publish` (355 MB index + 1.2 MB `-wal`,
under `$TMPDIR`, deleted afterwards). Mail's live file was never opened; only schema, counts and
paths were read. Four measured facts amend the decisions above; none reverses one.

- **C9 (§D3), answered:** `messages.message_id` is `INTEGER NOT NULL`, an opaque hash in all
  127,677 rows — it can never match an RFC `Message-ID`. The RFC id is nevertheless queryable
  elsewhere: `message_global_data.message_id_header TEXT` holds the header verbatim for 123,693 of
  123,695 rows (96.9% of all messages, shaped `<…@…>`), joined on
  `message_global_data.message_id = messages.message_id` (never on `messages.ROWID`). §D3's
  conditional therefore resolves to "implemented": `MailStoreReader.row(forMessageID:)` queries
  that table and answers `.notResolvableFromIndex` when the table is absent or the id is not there.
  The ledger stays load-bearing for the remaining 3.1%, for R-14's renumbered `conversation_id`,
  and for any store whose schema lacks that Mail-internal table.
- **C10 (§D4), answered:** the rule is
  `<V10>/<account-uuid = mailbox url host>/<Folder>.mbox[/<Sub>.mbox…]/<store-uuid>/Data/<fan>/Messages/<ROWID>.emlx`,
  folders being the url's percent-decoded path components, `<fan>` = `ROWID / 1000` written one
  digit per directory **in reverse order**, empty below 1000. Confirmed on 6 rows across 5
  mailboxes of 3 accounts (directory 6 of 6). The `<store-uuid>` level is identical for every
  mailbox of every account and appears in no table: it is read from the directory, never derived.
  Three of the six rows exist only as `<ROWID>.partial.emlx` (Mail's headers-only form; 723 of them
  in one mailbox). `EMLXLocator` must try `.partial.emlx` before returning `.notInStore`, and a
  `.partial` hit is R-15's «corpo non ancora scaricato», never R-16's «non più in Mail».
- **Not asked, found:** `date_sent` / `date_received` are **Unix epoch seconds**, not Mac absolute
  time (measured range 2007-11-21 … 2026-09-09). Read through `timeIntervalSinceReferenceDate`
  every message lands in 2038–2057. The reader uses `Date(timeIntervalSince1970:)`; the fixture
  writes the same epoch.
- **§D2, refined:** the generation stamp is `max(mtime(Envelope Index), mtime(-wal))`. Measured,
  the live `-wal` was fifteen minutes newer than the database, because Mail appends there and
  writes the database only at a checkpoint; an index-only stamp answers `.unchanged` for hours
  while new mail sits in the log the copy also takes.
- Also observed, no design consequence: a `subjects` table (`ROWID`, `subject TEXT`) backs
  `messages.subject INTEGER`; `Attachments/` sits beside `Messages/` at the same fan-out level.

## Follow-up — Task 2/3 measurement and deviations (2026-09-09)

- **§D9, measured:** both `message://` encodings open the message in Mail. One real
  `Message-ID` was read from a temporary copy of the index (schema only, no body), both forms were
  built and handed to `NSWorkspace.open` once each, and Mail opened the same message window for
  both (verified through Mail's own window list before and after each open). The default §D9
  names therefore stands: `MailURL.forMessageID` keeps `MailLink.url`'s form (`<`/`>` percent-
  escaped, `@` literal), and `EmailHeaders.mailURL` and `MailLink.url(forMessageID:)` both
  delegate to it. No output shape changed, so no note already carrying a `message://` link and no
  existing assertion is affected.
- **§D4, refined at implementation:** `EMLXLocator.locate` returns `.notInStore` only when the
  enumeration ran over an existing `Data/` tree and found nothing; an unrecognisable path shape, a
  missing `Data/` ancestor or an exhausted enumeration budget is `.ruleFailed`. The per-mailbox
  cache §D4 mentions is not inside the locator, which is a static function over one URL; it belongs
  to the sync that calls it (Task 4 onwards).
- **§D7 / SPEC message frontmatter, open point:** the `MessageDocument` declaration carries no
  `subject` field, so `pergamenum-mail-subject` is not written yet; the subject survives only in the
  file name's slug. Task 4's sync needs it, and the tester of that batch adds the field to the
  declaration (tester owns the signature, ADR-0155).
- **Deliberate divergences from the SPEC's worked examples:** an empty `pergamenum-mail-*` list is
  omitted rather than written as `[]`, matching what `FrontmatterSerializer` already does for
  `related`/`aliases`; the dossier codec reads both the block and the inline `[a, b]` list forms
  and writes only the block form, so a `pratica.md` typed by hand from the SPEC parses.
- **`QuoteSplitter`:** only the `-- ` signature marker is implemented; the "sender's display name
  followed by a few short lines" variant has no sender available at `split(_:)` and is deferred.
- **R-10 over-threshold record, named (batch 3):** the SPEC says the frontmatter records
  `{ name, size, storePath }` for an attachment above the threshold but names no key. The key is
  `pergamenum-mail-store-references`, a block list of flow maps in exactly the SPEC's brace shape
  (`- { name: "…", size: 157286400, storePath: "…" }`), omitted when empty like the other lists,
  read into `MessageDocument.StoreReference`.

## Follow-up — Task 4 implementation notes (2026-09-09)

- **R-16 needs two inputs, not one.** `MembershipRule.candidates` already subtracts what is on
  disk, so «absent from this run's candidates» alone would flag every imported message. A message
  loses its link only when it is absent from the candidates **and** `MailStoreReader.row(forMessageID:)`
  does not answer `.found`; the residual is §D3's known 3.1% of rows without a `Message-ID` header.
- **R-15 is a second pass.** `PraticaSyncPlan.workItems` refuses anything already on disk (its own
  test demands it), so a `pending` file from an earlier run is regenerated by a post-loop pass over
  the candidates whose file says `body: pending`, **in place**, matched by the recorded `Message-ID`
  and never by a derived name: the subject can change when the body arrives, and a fresh name would
  leave two files.
- **`SyncOutcome.writtenFiles` counts message notes, one entry per message**, not sidecars or
  attachments; `progressStream()` stays open until the running sync ends, so a consumer subscribing
  right after `sync` starts misses nothing.
- **Smaller choices:** `workItems` also honours `dossier.excluded`; the `-N` collision rule for
  attachments is engine state, `PraticaNaming.attachmentFileName` is reused unchanged;
  `pergamenum-mail-subject` is written even when empty; an over-threshold `storePath` is Mail's
  `Attachments/<ROWID>/<part>/<name>` when that file exists, else the `.emlx` container path; no
  per-mailbox `.emlx` cache was added (the predicted path hits in the normal case and the fallback
  enumeration is already bounded).

## Follow-up — Task 5/6 implementation notes (2026-09-10)

- **Accessibility identifiers are the hyphenated `pratiche-*` names** the plan's Task 10 and the
  UX blueprint enumerate. Two «Aggiorna ora» buttons exist, so the timeline's keeps
  `pratiche-refresh` and the list column's is `pratiche-refresh-all`; a pratica row is
  `pratiche-row-<folder path>`, not a title slug, because two clients can hold a pratica of the
  same name; message rows use an FNV-1a hex of the `Message-ID`, never `hashValue`, which is
  process-seeded.
- **R-26's «non più in Mail» half is deferred to the ledger.** `PraticaLedger.PraticaState`
  carries `pending` but no not-in-store list, so the timeline currently treats every message as
  still in Mail; `PraticaTimelineModel.subjectLink` already implements both branches and needs
  only that field, which Task 7's tester adds beside the R-16 sync outcome.
- **The pane arms the FSEvents watcher, not the app scene**: nothing reads a Mail store until the
  person opens Pratiche once in the session. Full Disk Access is answered from `open(2)`'s errno,
  where only `EPERM`/`EACCES` mean not granted and `ENOENT` means readable-but-absent.
- **The inspector is read-only for now** (`MarkdownBlocksView` plus «Apri nell'editor»); Task 7's
  `Navigation.jumpToLine` hand-off lands in the note editor unchanged (§D13). Task 7 and 8 verbs
  («Nuova pratica», «Aggiungi nota/telefonata», the tray strip, «Inserisci qui», Chiudi/Riapri)
  are drawn disabled with their identifiers in place, so the catalogue is written once in Task 7.

## Follow-up — Task 7/8 measurements and declarations (2026-09-10)

- **§D20, measured:** `com.apple.symbolichotkeys` exported read-only and parsed: 58 entries, 52
  carrying a `parameters` triple; none maps key code 35 (`p`) to Ctrl+Cmd, Cmd+Opt or Cmd+Shift.
  The three bindings ship as designed: `panePratiche` Ctrl+Cmd+P, `newPratica` Cmd+Opt+P
  (section File), `addToPraticaFromMail` Cmd+Shift+P (section Inserisci), all appended after
  `refreshRecordings`, never inserted.
- **§D3/R-16/R-26 closed:** `PraticaLedger.PraticaState` gains `notInStore: [String]`
  (Message-IDs), decoded with `decodeIfPresent` so an older ledger still loads. The sync writes
  it on the R-16 outcome and the timeline reads it for «non più in Mail».
- **R-30 has a pure model:** `PraticaTrayModel` reduces `MembershipRule.TrayEntry` rows into
  proposals (subject, counterpart, date range, count), decides when the strip is hidden, and
  applies «Ignora» (into `pergamenum-dossier-ignored` of this pratica only) and «Aggiungi» (into
  `conversations`) as pure dossier transforms the strip view calls.
- **§D17 tracer bullet (R-22) not run:** it needs a person dragging a message from Mail. Deferred
  to the review gate; `MailDropReceiver` ships as a thin shell that reports what it receives and
  shows the Mail-selection path as the documented way, which is R-22's own escape clause.

- **§D20, the domain that answered:** `defaults -currentHost export com.apple.symbolichotkeys -`
  reports «Domain does not exist» on this Mac; the live domain is the plain one
  (`defaults export com.apple.symbolichotkeys -`). A script reading only `-currentHost` sees an
  empty plist and reports no collision, which is a false all-clear. Any later measurement for a
  new `ShortcutCommand` reads the plain domain and prints the entry count.
- **Task 7/8 implementation deviations (coder):** «Rigenera» is a confirmation sheet that trashes
  the message file and re-syncs it, not a `UnifiedDiff` preview — §D6's diff is recorded as an
  open point, not implemented — closed by §D21 below; «Inserisci qui» is a submenu of the row's context menu, not a hover
  gap between rows; the wizard has no «@dominio» counterpart chip because `MembershipRule` has no
  domain arm; the «Aggiungi anche a…» sheet counts messages from the ledger; manual-entry
  headings are written in UTC (`Z`) as the test pins them; `PraticaTopBar` and the columns gained
  required parameters for the new verbs. `MailDropReceiver` is the §D17 probe shell only.

## Follow-up — Task 9/10 implementation notes (2026-09-10)

- **A dossier is read from `pratica.md` itself, never from an index record.**
  `IndexCache.StoredFrontmatter` persists only `date`, `tags`, `aliases` and `related`, so a
  record a scan reuses from the cache carries no `pergamenum-*` foreign key; the pane and the
  connector both listed nothing from the second scan of a vault onward. Both now let the index
  name the candidate `*/pratica.md` paths and parse the file through one Foundation-only
  `Dossier.parse(praticaFileAt:)`. No `IndexCache.schemaVersion` bump: persisting foreign keys
  in the cache is a separate decision on a protected interface.
- **§D19 connector reads:** `VaultAPI.pratiche(_:)` and `VaultAPI.pratica(_:_:)` answer from
  `pratica.md`, the message files and the per-vault ledger only; the tray count is persisted into
  `PraticaLedger.PraticaState.trayCount` by the app so a re-launched connector can report it.
  `perg pratiche`/`perg pratica`, MCP tools `pratiche`/`pratica` with `readOnlyHint`, and
  `scripts/mcp-smoke.py` gained a `pratiche` stage.
- **§D10 Settings tab, measured:** eleven `tabItem`s collapse into a «more toolbar items» popup
  at 700 pt; the window is 760×560 (item widths sum to 698 pt plus a 17 pt inset). Own addresses
  pre-fill from the Sent/«Posta inviata» mailboxes through `MailStoreReader.sentSenderAddresses()`.
- **Identifiers:** `pratiche-picker`/`pratiche-picker-row-<path>` replace the add-sheet's earlier
  names; `pratiche-delete-alert` added; `pratiche-insert-here-<kind>` and `pratiche-row-<id>`
  stay as batch 5 spelled them.
- **R-27 closed after the coverage gate:** the chip's decisions (symbol, preview/open/reveal
  targets, what «Copia» copies, the two menu titles) live in a pure `AttachmentChipModel`; a store
  reference now opens and reveals from its `storePath` when it still resolves, and «Copia» puts the
  file URL on the pasteboard, the bare name only when no file is on disk.
- **Deferred to the review gate:** the R-22 tracer bullet, the first sync against the real store
  and the manual acceptance on the Labs vault; the UI suite (`scripts/uitests.sh`) is run by the
  orchestrator, never by an agent.

## Follow-up — §D21…§D24, the four RTF findings left after commit `9cd6595` (2026-09-10)

Five review findings from the RTF cycles on `feat/pratiche` were fixed in commit `9cd6595`. Four
were deferred every cycle as architectural and tracked as `PG-105`…`PG-108` in `TODO.md`. They are
decided here. Each was re-verified at the line before anything was designed; two of the four turned
out to be smaller than their TODO entry says and one turned out to be a different bug than the one
reported.

### What was found at the line, before deciding

- **F1 (PG-105).** `PraticaCommandActions.confirmRegeneration` (`PraticaCommandActions.swift:260`)
  calls `trash(filesOf:)` on line `:262`, `forgetImportedMessage` on `:263`, then
  `refreshNow` on `:264`. There is no diff anywhere in the path, and the replacement content does
  not exist at the moment the file is destroyed: it is fetched by a *later* sync that may fail,
  may find the `.emlx` gone, or may be cancelled. §D6 promised the opposite. `UnifiedDiff` has
  existed since ADR-0007 and is already shown to a person once, by `TagRenameSheet.swift:84`
  through a `private struct DiffView` in that file.
- **F2 (PG-106).** `PraticheController.Prepared` (`PraticheController.swift:1082`) carries two
  disjoint maps, and `:1085-1089` states in a comment that `trayConversations` is "**never** folded
  into `snapshot`". `MembershipRule.candidates`'s keyword arm (`MembershipRule.swift:65`) scans
  `everyMessage(in: store)`, which is `snapshot.conversations ∪ snapshot.messagesByID`
  (`:92`) — followed conversations and hand-included ids, and nothing else. A keyword can therefore
  only match inside a conversation the pratica already follows, where rule 1 has already imported
  every message anyway. The arm is a no-op in every case it was written for.
  `Candidates.autoFollowedConversations` is read in exactly one place in the repository,
  `Tests/MembershipRuleTests.swift:89`. No production code reads it; nothing writes it to a
  dossier.
- **F3 (PG-107).** `PraticaLedger.PraticaState.entries` is written in exactly one place,
  `PraticheController.swift:522`, and that place is a `removeAll`. Nothing appends. It is read at
  `:1129` (`ledgerEntries: state.entries`) and by
  `PraticaLedger.memberMessageIDs(forConversation:praticaPath:)`, which is called nowhere.
  `MembershipRule.recoverConversationID` is called nowhere outside
  `Tests/MembershipRuleTests.swift:134`. The whole R-14 machine is built, tested and inert: the
  ledger's `entries` array is empty on every machine, so the bridge §D3 describes does not exist on
  disk.
- **F4 (PG-108), and it is not the reported bug.** The TODO entry says Cc/To matching is
  "impossible with current data". The store-side query is not the problem:
  `MailStoreReader.conversations(counterpart:within:)` (`MailStoreReader.swift:115`) already
  matches recipients, with an `EXISTS (SELECT 1 FROM recipients …)` clause at `:124`, and the tray's
  candidate conversations are exactly what it returns. What discards them is the *in-memory*
  re-check: `MembershipRule.trayCandidates` at `:141-144` reads `row.sender` and nothing else, and
  `MailStoreReader.rowSelect` (`:213`) selects no recipient column, so every row of an
  outgoing-only conversation fails the predicate and the whole entry is dropped. The conversation is
  fetched from SQLite at cost and thrown away one function later. The keyword arm at `:66` has the
  same defect against its own doc comment, which says "from/to a `dossier.counterparts` address".
- **F5, found while reading F4, not reported by anyone.** `conversations(counterpart:within:)`
  wraps its whole query in `do { … } catch { return [] }`. If the real store's `recipients` table
  is not named `recipients`, or its columns are not `message`/`address`, the statement fails to
  prepare and the function answers "no conversations" — an empty tray, forever, with no error and
  no log. The `recipients` schema in `Tests/MailStoreFixture.swift:256-262` was written by the
  tester of Task 1; the plan asked for `PRAGMA table_info(recipients)` on the real store
  (`docs/superpowers/plans/2026-09-09-pratiche.md:133`) but the recorded probe results say nothing
  about it. That table's shape is, in writing, a guess that shipped.

### §D21 — «Rigenera» acquires the replacement before it destroys anything, and the diff it shows is the bytes it writes

Amends §D6, whose diff was recorded as an open point in the Task 7/8 follow-up. Closes `PG-105`.

The order is inverted end to end. Nothing on disk is touched until a person has read a diff of the
exact replacement text, and the text they approved is the text written — not a second acquisition
that could differ.

1. **Acquisition, before anything.** `PraticaSyncEngine` gains a preview entry point that reuses
   its own `prepare(_:request:reader:folder:)` unchanged. That function already does the right
   thing for a regeneration: when the message file exists it reuses `existing.fileName`
   (`PraticaSyncEngine.swift:425-429`), so the replacement lands on the same path and every
   `[[link]]` to it in the vault survives. The only thing standing in the way is §D6's own guard at
   `:329`, which returns `nil` for an existing file that is not a `pending` awaiting its body. The
   guard is not removed: it is given one caller-declared exception.

   ```swift
   /// The one message an explicit «Rigenera» (§D6's second exception) may rewrite.
   /// `nil` for every ordinary sync, which is what keeps §D6's guard absolute
   /// everywhere else.
   var regenerating: String?          // new field on PraticaSyncEngine.SyncRequest
   ```

   and at `:329`

   ```swift
   if let existing {
       let isRequestedRegeneration = request.regenerating == messageID
       guard isRequestedRegeneration || (existing.document.frontmatter.body == .pending && !isPending)
       else { return nil }
   }
   ```

2. **The plan is a value, carried from the preview to the write.** The engine answers

   ```swift
   /// Everything an approved «Rigenera» needs to perform itself, acquired before any
   /// file was touched. Opaque on purpose: the only way to obtain one is
   /// `regenerationPreview`, and the only thing that can be done with one is
   /// `commitRegeneration` — so the bytes shown and the bytes written cannot diverge.
   struct RegenerationPlan: Sendable, Identifiable {
       var id: String { notePath }
       let praticaFolder: String
       let messageID: String
       let notePath: String            // "<folder>/email/<name>.md"
       let currentText: String         // what is on disk now
       let replacementText: String     // what an import would write now
       /// `UnifiedDiff.between(currentText, replacementText, path: notePath, context: 3)`
       /// — `nil` when the file is already identical to what Mail holds.
       let diff: String?
       /// Names that would land in `allegati/`, for the sheet's second line.
       let attachmentFileNames: [String]
       let rewritesOriginalEML: Bool
       fileprivate let prepared: PreparedMessage
       fileprivate let request: SyncRequest
   }

   enum RegenerationFailure: Error, Equatable, Sendable {
       case rowNotFound          // neither the index nor the ledger resolves the Message-ID
       case notInStore           // §D4: the `.emlx` is genuinely gone — R-16, not a bug
       case notDecodable         // the `.emlx` is there and `prepare` still answered nil
       case fileMissing          // the message note is not on disk at all
   }

   func regenerationPreview(
       _ request: SyncRequest, messageID: String, rowID: Int?
   ) async throws -> RegenerationPlan

   func commitRegeneration(_ plan: RegenerationPlan) async throws -> SyncOutcome
   ```

   `PreparedMessage` becomes `Sendable` (it already holds only value types) and stays `private`;
   `RegenerationPlan` is declared in the same file, so `fileprivate` reaches it. Outside that file
   a plan can be held, shown and handed back, and nothing else.

   `commitRegeneration` calls the existing private `commit(_:request:folder:outcome:)` with a fresh
   throwaway `FolderContext` and returns the resulting `SyncOutcome`. Because `prepare` set
   `isRegeneration = true` (the file existed), `commit` records the path in
   `regeneratedPendingFiles` and does **not** append to `importedMessageIDs` — the message stays
   imported, which is correct, and `forgetImportedMessage` is no longer called at all.

3. **Finding the row.** `regenerationPreview` resolves the `MailMessageRow` in two steps:
   `MailStoreReader.row(forMessageID:)` first (which answers for 96.9% of real rows through
   `message_global_data`, Task 1's C9), and on `.notResolvableFromIndex` a new sixth query,
   `MailStoreReader.row(rowID:)`, against the ROWID the **ledger** holds for that `Message-ID`.
   That second path is §D3's bridge doing the job it was designed for, and it only works once §D23
   below is implemented — which is why §D23 ships first (see the plan's task order). Until it does,
   `regenerationPreview` throws `.rowNotFound` for the 3.1%, which is reported and changes no file:
   strictly better than today, where the file is already in the Trash by the time anything fails.

4. **The sheet shows the diff, and the trash step moves after the approval.**
   `PraticaRegenerationRequest` is replaced by `RegenerationPlan` as the sheet's item; a
   `preparing` state is carried by the same value rather than a second variable (ADR-0024 §D2's
   rule):

   ```swift
   // PraticheController
   enum RegenerationState: Identifiable, Sendable {
       case preparing(notePath: String, subject: String)
       case ready(PraticaSyncEngine.RegenerationPlan)
       var id: String { … }
   }
   var regeneration: RegenerationState?
   ```

   `requestRegeneration` sets `.preparing` synchronously (so the sheet opens at once, with a
   `ProgressView` and «Annulla»), runs the acquisition off the main actor, then either replaces the
   value with `.ready(plan)` or clears it and calls `pratiche.report(_:)` with the Italian sentence
   for the failure. **The sheet body must read `pratiche.regeneration`, not the item the
   `.sheet(item:)` closure was handed**: SwiftUI passes the item once at presentation and does not
   re-invoke the closure when a same-`id` value changes, so a sheet built from the closure's
   parameter would show the spinner forever. Spelled as
   `.sheet(item: regenerationBinding) { _ in regenerationSheet() }`.

   On «Rigenera», in this order: (a) `trash(filesOf: plan.notePath)` — the existing private helper,
   unchanged, so the previous `.md` and `.eml` are recoverable in the Trash exactly as they are
   today; (b) `commitRegeneration(plan)`; (c) on a throw from (b), `restore(_:)` the trashed files
   and report. The Trash step is kept rather than replaced by a plain overwrite because it is the
   only deletion convention this repo has and `trash`/`restore` are already written and paired; the
   diff is the guardrail, the Trash copy is the parachute, and neither is expensive.

   When `plan.diff == nil` the sheet says «Il file è già identico al messaggio in Mail: non c'è
   nulla da rigenerare» and offers only «Chiudi». Nothing is trashed, nothing is written.

5. **The diff view stops being private to the tag sheet.** `DiffView` moves out of
   `TagRenameSheet.swift` into `Sources/DesignSystem/DiffView.swift` as an internal view, with its
   "it is the only place in the app that shows one to a person" comment corrected. `TagRenameSheet`
   keeps calling it with the same two arguments. Two copies of a diff renderer is precisely the
   "named once, rendered twice" failure ADR-0023 §D1 exists to prevent.

6. **Not changed.** `forgetImportedMessage` is left in place (the tray and the «Escludi»/«Sposta»
   paths still use the ledger surgery around it) but loses its «Rigenera» caller, and its doc
   comment is corrected to say so. No `refreshNow` is triggered by a regeneration any more: the
   write is complete when the sheet closes, so the timeline is refreshed by the existing `reload()`
   and nothing else runs.

### §D22 — Keyword auto-follow evaluates over the counterpart pool the tray already loads, and what it follows is written to the dossier

Amends §D3's membership half and the `Prepared` comment at `PraticheController.swift:1085-1089`,
which is reversed. Closes `PG-106`.

1. **`MembershipStoreSnapshot` gains a third, explicitly-named pool**, declared last so every
   existing construction site and both test fixtures keep compiling:

   ```swift
   /// Every message of every conversation the counterpart search found inside the
   /// proposal window, followed or not — the pool rule 3's keyword arm scans and the
   /// tray proposes from. Separate from `conversations` on purpose: rule 1 imports
   /// what `dossier.conversations` names, and nothing here is followed yet.
   var unfollowed: [Int: [MailMessageRow]] = [:]
   ```

   `MembershipRule.everyMessage(in:)` (`:92`) folds `unfollowed.values.flatMap { $0 }` in. It is
   used by rule 3 and by nothing else, verified at the line, so this widens the keyword arm and
   only the keyword arm.

   The `Prepared` comment's fear — "an unfollowed conversation added there would start importing
   itself" — is wrong on the code as written: rule 1 iterates `dossier.conversations`, rule 2
   iterates `dossier.included`, and neither consults the pool. Only rule 3 does, and only for a
   message that is both from/to a counterpart **and** carries a keyword in its subject, which is
   the feature. The comment is deleted with the field it described.

2. **`trayCandidates` iterates both maps**, `store.conversations.merging(store.unfollowed) { existing, _ in existing }`,
   so one snapshot can serve both calls and the two evaluations stop being fed different worlds.
   Its own `!followed.contains(conversationID)` filter already excludes anything in
   `dossier.conversations`, so folding the followed map in changes no tray output.

3. **Two evaluations, and the second is proved to be the last.** `runExclusive`
   (`PraticheController.swift:1141`) becomes:

   ```swift
   var effective = dossier
   var candidates = MembershipRule.candidates(dossier: effective, store: prepared.snapshot, onDisk: onDisk)
   if !candidates.autoFollowedConversations.isEmpty {
       for id in candidates.autoFollowedConversations {
           effective = PraticaTrayModel.following(conversationID: id, in: effective)
       }
       DossierWriter.update(at: praticaPath, session: session) { $0 = effective }
       // Rule 3 skips an id already in `dossier.conversations`, so this evaluation
       // auto-follows nothing new: two passes are a fixed point, never a loop.
       candidates = MembershipRule.candidates(dossier: effective, store: prepared.snapshot, onDisk: onDisk)
   }
   ```

   The second pass exists so a keyword match imports the **whole** thread in the run that found it,
   rather than the one matching message now and the rest at some later trigger. For rule 1 to reach
   the freshly-followed conversation, its lookup must consult both pools; `MembershipStoreSnapshot`
   gains one accessor and rule 1 calls it:

   ```swift
   func messages(inConversation id: Int) -> [MailMessageRow] { conversations[id] ?? unfollowed[id] ?? [] }
   ```

   «Aggiungi» from the tray is spelled through the same `PraticaTrayModel.following(conversationID:in:)`
   the strip already uses, so "follow a conversation" has one implementation.

4. **`DossierWriter` is extracted, not duplicated.** The read-modify-write of `pratica.md`'s
   `pergamenum-dossier-*` keys currently lives only on `PraticaCommandActions.updateDossier`
   (`PraticaCommandActions.swift:296`), a `@MainActor` struct built from a view's environment and
   unreachable from the sync. A new `Sources/Features/Pratiche/DossierWriter.swift` holds the body:

   ```swift
   @MainActor
   enum DossierWriter {
       /// Read-modify-write of one pratica's dossier keys through `VaultSession.write`,
       /// byte-preserving on every key it does not own (`Dossier.merging`, §D12).
       /// Returns the Italian sentence when it failed, `nil` on success — including
       /// "nothing changed", which is a success with no write.
       @discardableResult
       static func update(
           at praticaPath: String, session: VaultSession, _ change: (inout Dossier) -> Void
       ) -> String?
   }
   ```

   `PraticaCommandActions.updateDossier` becomes a three-line wrapper that reports the sentence
   through `pratiche.report`. There is one writer of the dossier after this, not two.

5. **The keyword arm's reach is the proposal window, deliberately.** `unfollowed` is built from
   `MailStoreReader.conversations(counterpart:within:)`, whose window is
   `settings.proposalWindowDays` (default 90). A keyword therefore auto-follows inside the last
   *N* days and no further back. The alternative — scanning the whole store per sync for a subject
   substring — is an unindexed full scan of 127,677 rows on this Mac's own store, per pratica, per
   trigger, and there is no counterpart-scoped query that avoids it. The bound is named in the
   Settings help text beside «Finestra proposte», so widening the reach is a number a person can
   change rather than a behaviour they have to discover.

6. **Consequence a person can feel, recorded on purpose:** a broad keyword on a counterpart with a
   large archive inside the window now imports a lot of mail on the first sync after it is typed.
   That is what the feature does; the guardrails are that keywords are opt-in, per pratica, and
   that `dossier.excluded` (which rule 4 subtracts, and `PraticaSyncPlan.workItems` subtracts
   again) survives a re-sync.

### §D23 — The sync records the bridge triple, and recovery runs where the conversation goes missing

Implements the second half of §D3, which was designed and never wired. Closes `PG-107`.

1. **Recording, at the write boundary.** `PraticaSyncEngine.PreparedMessage` gains
   `rowID: Int` and `conversationID: Int?`, copied from the `MailMessageRow` in `prepare`.
   `SyncOutcome` gains

   ```swift
   /// §D3's bridge triples for every message this run wrote — a fresh import and a
   /// regeneration alike, since a regeneration is exactly when a stale ROWID gets
   /// corrected. A row Mail did not thread (`conversationID == nil`) produces no
   /// triple: there is no conversation for R-14 to re-derive.
   var bridge: [PraticaLedger.Entry]
   ```

   appended in `commit` (`PraticaSyncEngine.swift:494-533`) beside the existing
   `outcome.importedMessageIDs.append` at `:525`, but **outside** the `isRegeneration` branch so
   both paths record it.

   `PraticaLedger.Entry.conversationID` stays a non-optional `Int`. Making it optional to carry
   unthreaded messages would widen a persisted `Codable` shape to store a value
   `memberMessageIDs(forConversation:praticaPath:)` filters out anyway.

2. **Persisting, in `recordSyncOutcome`** (`PraticheController.swift:456`), one merge beside the
   two already there, keyed by `Message-ID` with the newest triple winning:

   ```swift
   var entriesByID = Dictionary(state.entries.map { ($0.messageID, $0) }, uniquingKeysWith: { _, new in new })
   for entry in outcome.bridge { entriesByID[entry.messageID] = entry }
   state.entries = entriesByID.values.sorted { $0.messageID < $1.messageID }
   ```

   Newest wins because Mail renumbers ROWIDs on an index rebuild and a stale ROWID is worse than
   none (the same sentence `forgetImportedMessage`'s doc already uses). Sorted because
   `PraticaLedger.save` pretty-prints with `.sortedKeys` so the file stays diffable by hand.

3. **Detecting, in `prepare`** (`PraticheController.swift:1217`). The two loops swap order —
   `messagesByID` is built first, because recovery resolves against it — and the conversation loop
   becomes:

   ```swift
   var conversations: [Int: [MailMessageRow]] = [:]
   var remap: [Int: Int] = [:]
   var unrecoverable: [Int] = []
   let resolved = MembershipStoreSnapshot(conversations: [:], messagesByID: messagesByID)
   for conversation in dossier.conversations {
       let rows = reader.messages(inConversation: conversation)
       guard rows.isEmpty else { conversations[conversation] = rows; continue }
       // An empty conversation is only evidence of renumbering when this pratica has
       // actually imported from it. Nothing imported means nothing to re-derive, and a
       // conversation whose every message a person deleted is not a bug to report.
       let members = ledgerEntries.filter { $0.conversationID == conversation }.map(\.messageID)
       guard !members.isEmpty else { conversations[conversation] = []; continue }
       switch MembershipRule.recoverConversationID(knownMemberMessageIDs: members, store: resolved) {
       case .recovered(let recovered) where recovered != conversation:
           remap[conversation] = recovered
           conversations[recovered] = reader.messages(inConversation: recovered)
       case .recovered:
           conversations[conversation] = []
       case .unrecoverable:
           unrecoverable.append(conversation)
       }
   }
   ```

   `MembershipRule.recoverConversationID`'s signature does not change: it takes a
   `MembershipStoreSnapshot`, and a snapshot carrying only `messagesByID` is a legal one.
   "The conversation returned no rows" is the trigger, and it is the only trigger — there is no
   separate detection pass and no extra query.

4. **Repointing.** `Prepared` gains `conversationRemap: [Int: Int]` and
   `unrecoverableConversations: [Int]`. Back on the main actor, before candidates are evaluated:

   - for each `old → new`, `DossierWriter.update` replaces `old` with `new` in
     `dossier.conversations` **in place** (position preserved, duplicates collapsed) — the list is
     something a person reads in their own `pratica.md`, and the order it grew in is the order they
     followed things in (`PraticaTrayModel.following`'s own reason);
   - the ledger's own triples are repointed too, through a new
     `PraticheController.remapLedgerConversations(_ remap: [Int: Int], of praticaPath: String, in vault:)`,
     or the next sync's `memberMessageIDs(forConversation:)` answers nothing for the new id and the
     pratica silently loses its recovery data one renumbering later;
   - the in-memory `dossier` used for this run's evaluation is updated from the same value, so the
     run that discovered the renumbering already imports through the new id.

5. **Reporting, and what is deliberately not built.** `unrecoverableConversations` is reported
   through the pane's existing banner, `controller.report(_:)`, as
   «Una conversazione seguita non è più ricostruibile in Mail: <n>.» — R-14's "reported, never
   silently dropped" is met, and the conversation stays in the dossier rather than being removed.
   **The tray strip's own «non più ricostruibile» row (SPEC "Edge cases") is not built here**, and
   this is the one place where these four fixes leave the SPEC short of its own words. Building it
   means persisting the state (a fifth `PraticaState` field), inventing its invalidation rule (when
   does a conversation stop being unrecoverable?) and a non-actionable row in
   `PraticaTrayStrip.swift`. That is a separate, small piece of work; it is recorded as such rather
   than half-done here, because a banner that says the true thing beats a tray row that needs a
   staleness rule nobody has designed.

6. **The test that would have caught this.** `Tests/MailStoreFixture.swift` builds a store from
   code, which makes the renumbering case cheap: build a fixture, sync, rebuild the same messages
   under different `conversation_id` values, sync again, assert the dossier's
   `pergamenum-dossier-conversations` now names the new id and the ledger's `entries` came with it.
   R-14 has never had an end-to-end test; the pure function had two.

### §D24 — A message row carries its recipients, and one predicate decides "touches this counterpart"

Amends §D3's `MailMessageRow` shape (Task 1's R-03 row). Closes `PG-108`.

1. **One new field on the row, sourced by its own query.**

   ```swift
   /// Every recipient address of this message — To, Cc and Bcc alike, lower-cased,
   /// joined from `recipients` through `addresses`. Empty for a store whose schema has
   /// no `recipients` table and for a message that has none.
   ///
   /// Flat, with no To/Cc/Bcc distinction: every consumer asks "does this message touch
   /// this address", and nothing in this feature renders or filters by recipient kind.
   /// Not modelling `recipients.type` also means its integer encoding never has to be
   /// probed.
   var recipients: [String] = []
   ```

   Declared **last** in `MailMessageRow`, so the memberwise initialiser stays source-compatible
   with all four existing construction sites (`Tests/PraticaSyncTests.swift:33`,
   `Tests/MembershipRuleTests.swift:18`, `Tests/MailStoreReaderTests.swift:237`,
   `Tests/PraticaTrayTests.swift:20`).

2. **A separate query, never a widened `rowSelect`.** Joining `recipients` into
   `MailStoreReader.rowSelect` (`:213`) multiplies every message row by its recipient count and
   would silently change what every one of the five queries returns. Instead
   `MailStoreReader` gains one private helper with two `WHERE` clauses:

   ```sql
   SELECT r.message, a.address
   FROM recipients AS r
   JOIN addresses AS a ON a.ROWID = r.address
   JOIN messages AS m ON m.ROWID = r.message
   WHERE m.conversation_id = ?1        -- messages(inConversation:)
   ```
   ```sql
   SELECT r.message, a.address
   FROM recipients AS r
   JOIN addresses AS a ON a.ROWID = r.address
   WHERE r.message = ?1                -- row(forMessageID:), row(rowID:)
   ```

   One extra statement per conversation, none per message: no dynamic `IN (?,?,…)` list, so no
   `SQLITE_MAX_VARIABLE_NUMBER` chunking rule to get wrong. `messages(inConversation:)` folds the
   `[Int: [String]]` it gets back onto the rows it already built. Both forms fail closed the way
   every other query in that file does — an unpreparable statement answers "no recipients", never a
   throw. No new file says `sqlite3_`: this is all in `MailStoreReader`, which talks to
   `MailStoreConnection` (§D1 intact, and `Tests/MailStoreReaderTests.swift`'s own assertion
   unaffected).

3. **One predicate, used by both arms.** `MembershipRule` gains

   ```swift
   /// SPEC "Membership rule": a message *from or to* a counterpart. The tray
   /// (`trayCandidates`) and the keyword arm (`candidates`, rule 3) ask this same
   /// question and must never answer it differently — the sender-only version of this
   /// check is what made an outgoing-only conversation invisible to both.
   private static func touches(_ row: MailMessageRow, counterparts: Set<String>) -> Bool {
       if let sender = row.sender?.lowercased(), counterparts.contains(sender) { return true }
       return row.recipients.contains { counterparts.contains($0.lowercased()) }
   }
   ```

   called at `:66` (replacing the `guard let sender …` line) and at `:141-144` (replacing the
   `live.contains { … }` body, keeping the `window.contains(date(of: row))` clause it is `&&`-ed
   with). Both sides are lower-cased at the point of comparison, matching
   `MessageDocument.direction`'s own case-insensitive address rule and
   `sentSenderAddresses()`'s lower-casing.

4. **F5's silent failure gets a voice.** `MailStoreReader` gains

   ```swift
   /// Whether this store exposes a queryable `recipients` table. Asked once per sync,
   /// because a store without one silently reduces the tray and the keyword arm to
   /// sender-only matching — the exact defect §D24 fixes, reintroduced by a schema
   /// rather than by code.
   func supportsRecipients() -> Bool
   ```

   (`SELECT 1 FROM recipients LIMIT 1`, prepared and finalized). `PraticheController.prepare` calls
   it once and, when it answers `false`, reports
   «L'indice di Mail non espone i destinatari: la vaschetta vede solo i messaggi ricevuti.»
   through the banner. This also covers the pre-existing exposure: today a mis-named table makes
   `conversations(counterpart:within:)` return `[]` and the tray is simply empty, with nothing said.

5. **A live probe is still required, and it is narrower than Task 1's.** The `recipients` schema
   this design (and the already-shipped tray query) rests on is written down only in a fixture the
   tester authored; the Task 1 follow-up records no `table_info(recipients)` result. Before the
   coder starts, with Stefano present, on a copy published by `MailStoreCopy.publish` and never on
   Mail's live file:

   ```
   PRAGMA table_info(recipients);
   SELECT count(*) FROM recipients;
   SELECT r.message, a.address FROM recipients AS r
     JOIN addresses AS a ON a.ROWID = r.address
     WHERE r.message = <a ROWID whose message is known to have several recipients>;
   ```

   Both outcomes have a design. Names match → the SQL above ships as written. Names differ → the
   two new statements *and* the shipped `EXISTS` clause at `MailStoreReader.swift:124` are
   corrected together, `Tests/MailStoreFixture.swift`'s `CREATE TABLE recipients` is corrected to
   the measured shape, and the result is recorded as a further follow-up note in this ADR —
   the same contract Task 1's probes ran under. The probe reads schema and addresses only; no
   message body, no subject, and nothing is copied into `Tests/`.

### Alternatives considered

- **§D21: keep the trash-then-resync flow and merely show a diff of the file about to be
  destroyed.** Rejected: a diff of "the current file versus nothing" tells a person only what they
  are losing, not what they are getting, and §D6's promise is a diff of the *replacement*. It also
  leaves the acquisition after the destruction, which is the actual defect — a failed or cancelled
  re-sync still ends with the message gone.
- **§D21: acquire twice — compute the text for the preview, throw it away, recompute at commit.**
  Rejected: the guarantee a diff gate exists to give is "what you approved is what happened", and
  recomputation cannot give it. Holding one message's decoded bytes for the life of a modal sheet
  is bounded by the attachment threshold (default 100 MB, in practice a few MB) and is the cheaper
  side of the trade.
- **§D21: overwrite in place with no Trash copy, since the diff was approved.** Rejected as a
  net loss of recoverability for no gain: `trash(filesOf:)`/`restore(_:)` are already written,
  already paired, and already the only deletion convention this repo has. Moving the call after the
  approval is the whole change.
- **§D21: an `AskUserQuestion`-style alert rather than a sheet.** Rejected: R-34's «Elimina
  pratica» is the only alert in the feature (UX blueprint), and an alert cannot show a scrolling
  diff.
- **§D22: merge `trayConversations` straight into `snapshot.conversations`.** Rejected on
  readability rather than behaviour — with rule 1 iterating `dossier.conversations`, merging is
  behaviourally identical, but it makes `snapshot.conversations` mean two different things
  depending on who built it, and `trayCandidates` *does* iterate that map's keys. A named third
  field costs one line and cannot be misread.
- **§D22: scan the whole store for keyword matches, ignoring the proposal window.** Rejected:
  no counterpart-scoped index exists for a subject substring, so this is a full scan of the
  `messages`/`subjects` join per pratica per trigger (127,677 rows measured on this Mac). The
  window is a number in Settings; an unbounded scan is a design nobody can turn off.
- **§D22: keep one evaluation and let the auto-followed thread arrive on the next sync** (what
  `MembershipRule`'s own comment promises today). Rejected: "next sync" is a trigger that may be
  hours away, and the second evaluation is a pure function over data already in memory that is
  provably a fixed point. Recorded because the comment at `MembershipRule.swift:62-64` must be
  corrected when this lands, not left contradicting the code.
- **§D23: trigger recovery from a separate, explicit "verify followed conversations" pass.**
  Rejected: it is a second query per followed conversation for information the existing
  `messages(inConversation:)` call already returns. An empty result is the signal; nothing else is
  needed.
- **§D23: drop an unrecoverable conversation from the dossier automatically.** Rejected outright
  by R-14 — a pratica that quietly stops receiving mail is the worst failure this feature has.
- **§D23: persist `unrecoverableConversations` in the ledger and draw a tray row now.** Rejected
  *for this batch* (see §D23.5): it needs an invalidation rule that has not been designed. Named as
  known, bounded, remaining work rather than silently skipped.
- **§D24: model `recipients.type` as a To/Cc/Bcc enum.** Rejected: nothing in this feature asks the
  question, and modelling it would require probing an integer encoding that no recorded measurement
  covers. `MessageDocument`'s own `to`/`cc` frontmatter comes from the RFC headers in the `.emlx`,
  not from the index, and is unaffected.
- **§D24: widen `rowSelect` with a `LEFT JOIN recipients` and `group_concat`.** Rejected:
  `group_concat` on a five-way join changes the row cardinality and the `NULL` handling of every
  one of the five R-03 queries at once, to save one statement per conversation.
- **§D24: match the counterpart by domain rather than by address**, which would sidestep the
  recipient problem for the common "anyone at rossi-spa.it" case. Rejected as out of scope and
  already recorded as absent: the Task 7/8 follow-up notes the wizard has no «@dominio» chip
  because `MembershipRule` has no domain arm. Adding one is a separate decision about what a
  counterpart *is*, not a fix to a predicate that reads the wrong field.

### Consequences

**Positive.**

- §D6 stops being a promise the code contradicts: «Rigenera» now cannot destroy a file it has no
  replacement for, and the person sees the replacement's own text before agreeing to it.
- The keyword arm and `autoFollowedConversations` become live for the first time; a pratica can
  discover a conversation nobody has followed, which is the whole of SPEC's membership rule item 3.
- §D3's bridge exists on disk. R-14's recovery — designed, implemented, unit-tested and never
  called — is reachable, and gets its first end-to-end test.
- An outgoing-only thread ("I wrote to them, they have not replied yet") appears in the tray. The
  SQL that finds it has been shipping since Task 1; only the predicate that threw it away changes.
- A `recipients` table Mail does not have, or has under another name, now says so once per sync
  instead of producing a permanently empty tray in silence.
- The dossier has exactly one writer (`DossierWriter`) and the diff has exactly one renderer
  (`DiffView`) after this, where each had one plus a place that could not reach it.

**Negative.**

- `MailMessageRow` grows a field and `MailStoreReader` runs one extra statement per conversation
  per sync. Measured cost is not known and is not measured here; the row count per conversation is
  small and the statement is indexed on `recipients.message` in Mail's own schema — if a real store
  disagrees, it will show in the sync progress and the fix is the same chunked `IN` list this
  design rejected for simplicity.
- A broad keyword can now import a large volume of mail on its first sync (§D22.6). This is the
  feature working; it is nonetheless a surprise available to a person who types «Re».
- The second membership evaluation runs `MembershipRule.candidates` twice per sync whenever a
  keyword matched. It is pure and over in-memory values, but it is not free on a pratica following
  hundreds of conversations.
- Holding a `RegenerationPlan` keeps one message's decoded attachments in memory for as long as the
  sheet is open. Bounded by the attachment threshold, unbounded in count.
- R-14's tray-side «non più ricostruibile» rendering is still not built (§D23.5). The state is
  reported in a banner that clears on the next successful load, so a person who looks away misses
  it until the next sync says it again.
- `PraticaRegenerationRequest` is replaced rather than extended, so `PratichePane`'s sheet, its
  binding and the `pratiche-regenerate*` accessibility identifiers all move together. The
  identifiers are kept byte-identical so the UI suite's selectors do not churn.

**Neutral.**

- No `IndexCache.schemaVersion` bump: nothing here is cached in the app's own index.
- No new protected interface. `Dossier.render` and `PraticaNaming.messageFileName` are read by this
  work and neither changes shape. `PraticaLedger.PraticaState` gains no field at all — `entries`
  already exists and is already `decodeIfPresent`-decoded, so a ledger written by a build before
  this work loads unchanged and simply fills its bridge on the next sync.
- No connector change. `Sources/Features/Pratiche/**` is outside `sharedSources`, and the two files
  under `Sources/Core/**` that do change (`MailMessageRow`, `MembershipRule`) are compiled by
  `perg`/`pergamenum-mcp` but called by neither — `SharedSourcesPurityTests`' ban on `MailStore`,
  `EMLXReader` and `SQLite3` under `Sources/Connector`, `Sources/CLI` and `Sources/MCPServer` is
  untouched (§D19).
- No new dependency, no new `ShortcutCommand`, no new frontmatter key, no new `pergamenum-*`
  property, no migration.
- Both exceptions to CLAUDE.md principle 2 stay where they are: nothing here opens a socket.

## Follow-up — Task 2 probe results, PG-108 (2026-09-10)

Ran on a copy published the same way Task 1's own two probes were (`Envelope Index` + `-wal`
copied to a `/tmp` staging directory, `PRAGMA quick_check`ed, deleted immediately after). Mail's
live file was never opened; schema, a row count and addresses only — no subject, no body.

- **`PRAGMA table_info(recipients)`:** `ROWID INTEGER PRIMARY KEY`, `message INTEGER NOT NULL`,
  `address INTEGER NOT NULL`, `type INTEGER`, `position INTEGER` — column-for-column identical to
  `Tests/MailStoreFixture.swift`'s existing `recipients` table. **No fixture correction needed.**
- **`SELECT count(*) FROM recipients`:** 176,840 rows on this Mac's store.
  `SELECT type, count(*) FROM recipients GROUP BY type`: `0` → 159,259 rows, `1` → 17,581 rows —
  two recipient kinds (To/Cc-shaped vs. a smaller second class), neither queried by column name
  anywhere in this codebase, so the split has no design consequence: every read here joins on
  `message`/`address` only, matching §D24.5's own precedent.
  `SELECT r.message, a.address FROM recipients AS r JOIN addresses AS a ON a.ROWID = r.address
  WHERE r.message = <a ROWID with 631 recipients>` returned real `address` strings for every row —
  the join columns are exactly `recipients.message`/`recipients.address` →
  `addresses.ROWID`/`addresses.address`, which is what the already-shipped `EXISTS` clause at
  `MailStoreReader.swift:124` (`conversations(counterpart:within:)`) already uses. **§D24.5's
  condition resolves to "measured, matches" — the shipped clause is correct today; finding F5 does
  not apply.** Task 3 proceeds with `MailMessageRow.recipients`/`supportsRecipients()`/`row(rowID:)`
  as designed, no schema-driven change to either the fixture or the existing join.

## References

- `SPEC.md` (topic slug `pratiche`, R-01…R-41), `UX-BLUEPRINT.md`, `DESIGN.md` and its export at
  `docs/design/pratiche/Pergamenum Pratiche.dc.html`.
- Plan: `docs/superpowers/plans/2026-09-09-pratiche.md`,
  `docs/superpowers/plans/2026-09-10-pratiche-pg105-pg108.md` (§D21…§D24).
- `docs/adr/0007-…` (connector boundary), `docs/adr/0017-…` (per-vault state),
  `docs/adr/0020-…` (prefixed keys), `docs/adr/0023-universal-command-surface-parity.md`,
  `docs/adr/0024-workspace-board-tree-single-selection.md`,
  `docs/adr/0026-drag-and-drop-board-files-into-workspace.md`,
  `docs/adr/0031-sparkle-auto-update-integration.md`,
  `docs/adr/0032-plaud-recording-import-into-pergamenum.md`,
  `docs/adr/0034-pergamenum-view-query-builder.md`.
- Read at the line for this ADR: `Sources/Core/Email/EmailHeaders.swift`,
  `Sources/Core/Email/MailLink.swift`, `Sources/Core/Conventions/ImportNaming.swift`,
  `Sources/Core/Conventions/Frontmatter.swift`, `Sources/Core/Conventions/Tag.swift`,
  `Sources/Core/Conventions/NoteName.swift`, `Sources/Core/Shortcuts/ShortcutCommand.swift`,
  `Sources/Core/Shortcuts/KeyBinding.swift`, `Sources/App/Navigation.swift`,
  `Sources/App/SidebarItem.swift`, `Sources/App/RootView.swift`,
  `Sources/Features/Editor/VaultBrowser.swift`, `Sources/Features/Settings/SettingsView.swift`,
  `Sources/Features/Recordings/*`, `Sources/Connector/VaultReads.swift`,
  `Sources/Connector/VaultViews.swift`, `Sources/Vault/VaultSettings.swift`,
  `Sources/Vault/VaultState.swift`, `Sources/DesignSystem/TokenKeys.swift`,
  `Resources/vocabolari.json`, `Resources/Themes/*.json`, `Project.swift`,
  `Tests/ShortcutTests.swift`, `Tests/SharedSourcesPurityTests.swift`, `.claude/test-cmd`,
  `.claude/protected-interfaces`.
- Measured on 2026-09-09: `xcrun swiftc` probe of `import SQLite3` →
  `sqlite3_open_v2` rc=0, `sqlite3_libversion()` = 3.51.0.
