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

## References

- `SPEC.md` (topic slug `pratiche`, R-01…R-41), `UX-BLUEPRINT.md`, `DESIGN.md` and its export at
  `docs/design/pratiche/Pergamenum Pratiche.dc.html`.
- Plan: `docs/superpowers/plans/2026-09-09-pratiche.md`.
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
