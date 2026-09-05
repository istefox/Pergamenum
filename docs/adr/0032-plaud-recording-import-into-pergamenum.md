# ADR-0032: A recording reaches the vault over a socket that never leaves the machine

- Status: proposed
- Date: 2026-09-05. Every external fact below was **measured live on this machine on this date**,
  against the running `plaud-service`, not recalled and not read off the contract document:
  `/health`, `/recordings?days=14` (eight recordings), `/proposals/{id}` for three of them,
  `lsof -nP -iTCP:3777`, `~/Library/LaunchAgents/`, `Resources/vocabolari.json`,
  `com.apple.symbolichotkeys`, and the source of `Frontmatter.swift`, `Tag.swift`,
  `NoteName.swift`, `VaultState.swift` and `Project.swift`. **Where a measurement contradicts the
  SPEC or the contract document, the measurement wins and the contradiction is named.**
- **Narrowly and formally excepts CLAUDE.md principle 2 ("Fully offline. No network call in any
  feature.")** — D14. This is the *second* written exception, after ADR-0031 §D13, and a narrower
  one: a loopback request cannot leave the machine even in principle.
- **Deliberately reopens the closed four-key note frontmatter of SPEC §4.3/§14** — D6, with three
  `pergamenum-`-prefixed keys, following the precedent ADR-0020 set for `.canvas` node properties.
- **Amends the SPEC's Data model in four measured places**: the tag value (D7 — `type-trascrizione`
  is unwritable), the timestamp format (D8 — `recorded_at` carries no zone designator), the note
  name (D5 — a recording's `name` is a human title with a colon in it), and the body order (D11).
- **Supersedes nothing.** No mechanism of ADR-0018, ADR-0021, ADR-0028, ADR-0029, ADR-0030 or
  ADR-0031 is reopened. No view, text container, delegate, token or index field is touched.
- **Does not reopen ADR-0007 §D3/§D4.** `perg` and `pergamenum-mcp` gain no capability, no flag and
  no tool; the reason this feature is absent from both is the reason EventKit and Sparkle are.
- Depends on: **ADR-0017 §D1/§D2** (derived per-vault state lives beside the vault, keyed by the
  vault's UUID), **ADR-0020** (a prefixed key is how this repo extends a closed schema),
  **ADR-0021 §D1** (the task line is the storage; no table, no schema bump), **ADR-0031 §D4**
  (a launch argument, not a compile-time flag, keeps a system out of the UI suite) and
  **ADR-0031 §D13** (the shape an exception to principle 2 has to take).

## Context

**The recordings already exist and the app cannot see them.** `plaud-service` — a separate repo,
`Plaud`, already shipped — transcribes a Plaud voice recorder's files and extracts themed action
items. Its whole output is reachable at `http://127.0.0.1:3777` and nothing in this app knows the
port exists. The contract is `/Users/stefer/Developer/Plaud/docs/PERGAMENUM-API.md`, cited from
here and deliberately not copied into this repo.

### What was measured, on 2026-09-05, rather than assumed

```
$ curl -s -m 3 http://127.0.0.1:3777/health
{"status":"ok","plaud":"connected","version":"0.2.0"}          http=200

$ lsof -nP -iTCP:3777 -sTCP:LISTEN
node  63900 stefer  23u  IPv4 0x2f39...  TCP 127.0.0.1:3777 (LISTEN)

$ ls ~/Library/LaunchAgents/ | grep -i plaud
it.stefer.plaud-service.plist                       (Sep 5 10:36)
```

Eight recordings came back from `/recordings?days=14`. Reading them changes five things about the
design:

| # | The SPEC and the contract say | The live service says | Consequence |
|---|---|---|---|
| M1 | `"name": "2026-09-04 13:44:51"` — a timestamp | **Seven of eight are human titles**: `09-04 Riunione: Preparazione revisione trimestrale con cliente - Diagramma di Flusso Componenti` (79 characters, contains `:`). One row still carries the old timestamp form. **Both shapes are in the wild at once.** | The recording's name **cannot** be a note title: `:` is in `NoteName.forbiddenCharacters` and 79 > `NoteName.maximumLength` (60). D5 derives one. |
| M2 | "All timestamps are ISO 8601 UTC", example `2026-09-04T11:44:51Z` | `recorded_at` is `2026-09-04T11:48:07` — **no `Z`, no offset, in all eight rows.** `generated_at` in a proposal is `2026-09-05T07:55:24.906Z` — zone **and** fractional seconds. | `ISO8601DateFormatter` with default options rejects *both*. D8 is a tolerant parser, and the zone-less form is UTC, measured. |
| M3 | task `id` is a UUID; recording `id` likewise | Task ids **are** UUIDs (`11223344-5566-7788-99aa-bbccddeeff00`). Recording ids are 32-character hex (`a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6`). | Both are opaque strings and neither is parsed. Worth recording so nobody types `UUID` into a payload struct. |
| M4 | speakers are `["Speaker 1", "Speaker 2"]`, renamed by the person at review | Measured: `["Speaker 1", "Nome Cognome A", "Nome Cognome B", "Nome Cognome C"]`. **The service already resolves most speakers to real names.** | The rename field is pre-filled with the label *as given*; only an unresolved `Speaker N` is actually worth typing over. The UX blueprint's "pre-filled with Speaker N" is right for one label out of four. |
| M5 | failure is an edge case | **Five of the eight recordings are `failed`**, with three distinct raw strings: `extraction_invalid: themes is not an array` (×3), `cleanup returned no text for chunk 2`, `Plaud MCP tool get_transcript returned non-JSON content: Bl…` | R-07's readable-error mapping is the common path, not a corner. It needs a table *and* a fallback, because the third string is not a coded error at all. |

Two further measurements from `/proposals/{id}`, on three recordings:

- **`due_hint` was `null` on every task sampled** (25 of 25). The `>date` marker is the exception,
  not the rule; a writer that assumes a date is present writes `>` and nothing after it.
- **A live proposal has `themes: []` with `warnings: ["no_action_items"]` right now.** The
  zero-theme case the SPEC lists under Edge cases is not hypothetical; it is on this machine today.
- Themes carry 6–10 tasks each, four themes to a proposal. A review sheet holds 25+ checkboxes,
  and quotes run to ~140 characters.

### What this repository already does, measured by reading it

**The frontmatter parser already preserves unknown keys, and the linter already condemns them.**
`FrontmatterParser.parse` puts any key outside the closed four into `foreignKeys` with its raw
lines (`Frontmatter.swift:206-208`), and `FrontmatterSerializer.render` writes them all back after
`aliases` (`:299-301`). So a `pergamenum-plaud-id` round-trips today with **no parser change at
all**, and Obsidian — which preserves unknown YAML keys — is unaffected (principle 4).

But `FrontmatterRules.validate` maps every one of them to `.foreignKey(name)`
(`Frontmatter.swift:335`), which `VaultBrowser.swift:317` renders as «Chiave fuori schema». Without
a change, **every transcript note this feature writes is permanently non-conformant** in the
Conformità pane, in `perg lint` and in the MCP `lint` tool. That is the real cost of the schema
reopening, and D6 is where it is paid.

**`type-trascrizione` cannot be written.** `TagNamespace.isClosed` (`Vocabulary.swift:68-73`) makes
`type` a closed family, and `Resources/vocabolari.json`'s `type` array is
`[offer, report, datasheet, minutes, presentation, manual, certificate, pricelist, standard, paper,
catalog, invoice, receipt, contract, statement, email, photo, audio, note, code]` — no
`trascrizione`. Adding one would mean editing the declared replica of `harness-system`'s closed
table, which CLAUDE.md principle 5 forbids in exactly those words: *"that repo stays the single
source of truth: when a convention changes, the app config is updated, never the other way round."*
Separately, `TagRules.missingRequired` requires an ordinary note to carry `type-note` **and** at
least one `topic-*`, so the SPEC's single-tag frontmatter would produce two more findings on top.
D7 resolves all of it inside the vocabulary that exists.

**There is no `URLSession` in this repository.** `grep -rln "URLSession" Sources/ Tests/` returns
nothing. This feature introduces the first one, which means the exception of D14 is enforceable by
a grep rather than by a promise — the ADR-0031 §D2 shape.

**Nothing about this feature may enter `sharedSources`.** `Project.swift:72-112` lists
`Sources/Core/**`, `Sources/Connector/**` and 30 named files. `Sources/Features/**` is not among
them, and the app target's own glob is `Sources/**` minus the two `main.swift` directories
(`:190-192`), so a new file under `Sources/Features/Recordings/` is compiled by the app and by
nothing else, with no manifest edit. The one shared file this chain touches is
`Sources/Core/Conventions/Frontmatter.swift`, and D6 explains why that is unavoidable and why it
adds no API.

### Two runtime facts that had to be checked rather than remembered

macOS 26 gates local-network access behind a privacy prompt, and App Transport Security blocks
cleartext HTTP. Both would sink a loopback client silently. Checked against Apple's forums and
documentation on 2026-09-05: **loopback addresses (`127.0.0.1`, `::1`) are an explicit exception to
the local-network restrictions**, because the traffic cannot leave the device, and ATS does not
apply to a request made to an IP literal in the loopback range — no `NSAllowsLocalNetworking`, no
`NSLocalNetworkUsageDescription`, no entitlement (the app is not sandboxed in v1, CLAUDE.md
§Stack). That is a claim from documentation, not a measurement of this app, so the plan's Task 2
**verifies it with one real request from the app process** and D2 names the fallback:
`NSAppTransportSecurity: { NSAllowsLocalNetworking: true }` in `Project.swift`'s `infoPlist`,
scoped, never `NSAllowsArbitraryLoads`.

## Decision

**D1. The whole feature lives under `Sources/Features/Recordings/`, and `sharedSources` gains
nothing. Exactly one file in the repository says `URLSession`, and a test enforces it.**

Ten new files, all under one directory: the payload types, the timestamp parser, the error mapping,
the `PlaudService` protocol, the `PlaudHTTPClient`, the local store, the note builder, the dedup
rule, the controller, and the views. Nothing goes in `Sources/Core` (compiled into both
connectors), nothing in `Sources/Connector` (that *is* the connector surface), nothing in
`Sources/App` (which holds app-lifetime infrastructure with no pane of its own — this feature has a
pane).

`Tests/PlaudIsolationTests.swift` walks the repository from `#filePath` and asserts that
`URLSession` appears in exactly one file, `Sources/Features/Recordings/PlaudHTTPClient.swift`. That
turns D14's "the exception does not travel" from a sentence into a test that goes red in the same
turn — the difference matters because the connector builds are not in `.claude/test-cmd`.

Rejected: **a `Sources/Network/` directory.** A directory named after a technology invites a second
client for a second purpose, which is precisely what the exception forbids. The client belongs to
the feature that is excepted.

**D2. `PlaudService` is a protocol, `PlaudHTTPClient` its only implementation, and the base URL is
the IPv4 literal `http://127.0.0.1:3777` — hard-coded, not settable, and never `localhost`.**

```swift
protocol PlaudService: Sendable {
    func health() async throws -> PlaudHealth
    func recordings(days: Int) async throws -> [PlaudRecording]
    func process(id: String, force: Bool) async throws -> PlaudJobHandle
    func job(id: String) async throws -> PlaudJob
    func proposal(recordingID: String) async throws -> PlaudProposal
    func confirmImported(recordingID: String, taskIDs: [String]) async throws
}
```

Protocol first, because `CalendarStore` (`CalendarService.swift:69-104`) is this repo's precedent
for exactly this problem and states it: *"EventKit cannot run in tests… everything above this line
is therefore written against the protocol and tested with a stub."* A network service is the same
shape of untestable dependency, for the same reason: a suite that hits a real socket passes or
fails on whether a LaunchAgent happened to be loaded.

**`127.0.0.1` and never `localhost`, and this is measured rather than stylistic.** `lsof` shows the
service listening on **IPv4 only**. `localhost` resolves to `::1` first on this machine's resolver
order, so a client written the obvious way would attempt an IPv6 connection to a socket nothing is
holding and report a connection failure indistinguishable from "the service is down" — the exact
failure the health banner exists to explain, arriving when the service is running perfectly.

**Not settable, and that is the load-bearing half.** A host or port field in Impostazioni would
turn a bounded exception into an unbounded one: D14's promise is auditable precisely because the
only address this app can reach is a literal in one file that a grep finds. If the service's port
ever moves, that is a one-line code change and an amendment to this ADR, which is the correct
amount of friction for widening a network exception.

The session is `URLSessionConfiguration.ephemeral` with `timeoutIntervalForRequest = 10`,
`waitsForConnectivity = false`, `httpCookieStorage = nil`, `urlCache = nil`,
`httpShouldSetCookies = false`. Each of those is a way of not accumulating state about a machine
talking to itself.

Rejected: **`URLSession.shared`.** It carries a shared cache and cookie storage that this app has
no other user for, and a cached `/recordings` response would make «Aggiorna» a lie.

Rejected: **a settable host/port.** Above.

**D3. `-disablePlaud YES` keeps the client out of a launch entirely, and every file under
`UITests/` passes it — not only the ones that would otherwise notice.**

```swift
private let isIsolated = UserDefaults.standard.bool(forKey: "disablePlaud")
```

the exact shape of `EventKitStore.isIsolated` (`CalendarService.swift:151`) and
`SparkleUpdateController`'s (ADR-0031 §D4). When set, the controller makes no request of any kind
and the pane draws the service-unavailable banner.

**The hazard here is sharper than either predecessor's, and it is measured.** The service is
running on this Mac *right now* and answers `/health` with 200. Nineteen files under `UITests/`
call `XCUIApplication().launch()`, and this ADR adds a sidebar row that a stray selection or a
future test can land on. Without the flag, a UI test would list somebody's real meetings, and
`process` would enqueue real transcription work against a real recorder. All nineteen files get the
flag, for the reason CLAUDE.md gives about `-disableCalendar`: *"Every one of the thirteen files
passes it, not only the one that needed it."*

Rejected: **pointing the UI suite at a stub server on another port.** A second implementation of a
contract this repo does not own, kept in step by hand, to test a pane whose logic is already unit
tested against the protocol.

**D4. Polling is one structured `Task` owned by the controller — 3 seconds, bounded at 30 minutes,
cancelled when the job ends, the vault changes, or the pane's owner goes away. There is no `Timer`
anywhere.**

`Task { while !Task.isCancelled { try await Task.sleep(for: .seconds(3)); … } }`, stored on the
controller and cancelled explicitly. The 30-minute cap is not a guess at how long transcription
takes: it is the point past which a silent repeating request stops being something the person
asked for. On expiry the row says so and offers «Aggiorna», which is one deliberate request.

The controller lives at scene level (`@State private var recordings` in `PergamenumApp`, beside
`day` and `diary`), **not** as `@State` inside the pane — a poll that dies because the person went
to look at a note would leave a job running with nothing watching it, and coming back would show a
stale row.

Rejected: **a repeating `Timer` or a background refresh.** D14's narrowness is a claim about *time*
as much as about content, and ADR-0031 §D13 already identified that as the thing that makes an
exception real: with no timer, an offline Pergamenum makes zero requests for its entire life.

**D5. The note's name is derived from the recording, never taken from it.**

```
20260904_Registrazione_riunione-preparazione-audit-cgm
```

`<compact local date>_Registrazione_<slug>`, built by a new `ImportNaming.recordingNoteTitle` that
reuses `kebabCase` and follows the `YYYYMMDD_Controparte_Tipo_slug` shape `emailFileName` already
writes (naming.md 4.3/7.3). Four rules, each forced by a measurement:

1. **A leading date-like token in `name` is dropped before slugging** — six of eight names begin
   `09-04 ` or `2026-09-04 `, and leaving it in produces `20260904_Registrazione_09-04-riunione…`,
   the date twice.
2. **The slug is truncated at a word boundary so the whole title is ≤ 60 characters**, and never
   ends in a hyphen. `NoteName.maximumLength` is 60 and the measured names reach 79.
3. **Collisions take `ImportNaming.uniqueFileName`'s `-2`, `-3` suffix**, the convention already
   used for imported mail and pasted images. `NoteName.versionSuffix` does not fire on a single
   digit, so `…-2` stays conformant.
4. **The date is the recording's own local date, not today's** — a recording imported a week later
   is filed under the day it happened.

The note is written into `Registrazioni/` at the vault root, created on demand:
`NoteStore.write` already calls `createDirectory(withIntermediateDirectories: true)`
(`NoteStore.swift:112-113`), so no folder-creation code is needed.

Rejected: **`NoteName.sanitized(recording.name)`.** It exists and it would compile. On the measured
name it yields `09-04 Riunione Preparazione revisione trimestrale con cliente - Diagra` — the colon
silently swallowed, the sentence truncated mid-word, and no date prefix to sort by.

**D6. Three `pergamenum-`-prefixed frontmatter keys, and the linter stops calling a prefixed key
foreign. This is a deliberate, scoped reopening of SPEC §4.3/§14, and it is the right one.**

```yaml
pergamenum-plaud-id: "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6"
pergamenum-plaud-recorded-at: "2026-09-04T11:48:07"
pergamenum-plaud-duration-ms: 1236000
```

`FrontmatterRules.validate` no longer emits `.foreignKey` for a key matching
`^pergamenum-[a-z0-9]+(-[a-z0-9]+)*$`. **Every other foreign key is still a finding**, and
`Frontmatter.foreignKeys` still keeps all of them verbatim — the parser and the serializer are not
touched at all. The change is four lines in one function.

**Why a tag is not sufficient, which is the question the SPEC asks to have answered.** A tag is a
taxonomy value: it says what kind of thing a note is, it is shared by many notes, and it is
constrained to `[a-z0-9-]` segments by T-01. What R-08 needs is different in kind — an *exact,
unique, machine-readable anchor* that answers "which note, if any, already holds recording
`2dade977…`" without a full-text search and without ambiguity. Three concrete things a tag cannot
do:

- **It cannot be unique.** `topic-*` values are a shared vocabulary by construction; a tag whose
  value is a 32-hex id would be one tag per recording forever, and `TagRules.maximumTagsPerNote` is
  7 with a linter that reports date-like and unfamiliar values.
- **It cannot carry `recorded_at` or `duration_ms` at all.** T-07 explicitly forbids a tag that
  encodes a date (`TagRules.isDateLike`), which is the second key exactly.
- **It cannot survive the round-trip guarantee that makes idempotency possible.** The frontmatter
  keys are preserved byte-for-byte by a parser that was written to preserve them; a tag is parsed,
  ordered, and re-serialized.

The two are not alternatives and the SPEC is right that they serve different purposes: the tag is
how a person finds transcripts in the Tag pane, the keys are how the app finds *this* transcript.

**Why prefixed keys rather than a sidecar file.** Principle 1, file over app: if Pergamenum
disappeared, or the vault were handed to somebody else, or `~/Library/Application Support/` were
deleted, the note must still say what it is. A sidecar mapping note path → recording id breaks on
a rename, on a move, and on exactly the reset that ADR-0017 §Consequences already warns is now
somebody's mental model of "reset the app".

**Why this reopening is valid and worth making, stated as an assessment rather than assumed.** The
closed schema exists so that note frontmatter does not silently become a database of app-specific
fields — a real risk, and the reason `title`, `status`, `type`, `draft`, `version` and `author` are
forbidden by name. A *prefixed namespace* preserves that purpose rather than eroding it: the prefix
is self-identifying, greppable, impossible to confuse with a harness convention, and already the
mechanism this repo chose the last time it faced the same question (ADR-0020, `pergamenum-crop` on
a `.canvas` node, which likewise extends a schema owned by somebody else — JSON Canvas 1.0 — by
prefixing rather than by inventing a bare key). Without it, R-08 is not merely harder; it is
unimplementable, because there is nothing in the file that says which recording it came from.

The scope is stated and narrow: **three keys, one prefix, this feature only.** A future feature
wanting a fourth prefixed key gets it for free from the linter rule, which is a real widening, and
the compensation is that the prefix makes every such key visible to a one-line grep.

Rejected: **leaving the linter alone and accepting the findings.** Every imported note would carry
three permanent «Chiave fuori schema» findings, the Conformità pane would show a growing count that
means nothing, and the person would learn to ignore it — which costs the linter its whole value.

Rejected: **adding the three names to `Frontmatter.allowedKeys`.** That set is SPEC §4.3's closed
four and is used as the definition of the schema. Widening it by name would say the schema is now
seven keys; the prefix rule says the schema is still four, plus a namespace this app owns.

**D7. The tags are `type-note` + `topic-trascrizione`, plus `source-meeting` when
`recording_kind == "meeting"`. `type-trascrizione` is not written, and `vocabolari.json` is not
edited.**

Forced by three measurements: `type` is a closed family, `trascrizione` is not in its table, and
`TagRules.missingRequired` requires `type-note` and a `topic-*` on any ordinary note. `topic` is an
open family (`Vocabulary.swift:71`), so `topic-trascrizione` carries the SPEC's intent — a
vault-wide way to find transcripts — in the namespace that is actually open for it.
`source-meeting` is in the closed `source` table and is added only for the kind where it is exactly
true; `lecture`, `update` and `personal` get no `source-*` rather than a convenient lie.

The result is a note its own linter passes, which is the standard this repo already set: `#30` is
recorded in `TagRules.initialTags`' own header as *"how the app came to generate a file its own
linter flagged without anybody noticing."*

Rejected: **adding `trascrizione` to `Resources/vocabolari.json`.** Principle 5, in its own words.
If the harness genuinely needs a transcript type, that change starts in `harness-system` and
arrives here through «Importa convenzioni…», not the other way round.

**D8. Timestamps go through one tolerant parser, and a zone-less `recorded_at` is read as UTC. The
frontmatter stores the service's own string, byte for byte.**

`PlaudTimestamp.parse` tries three shapes in order:

1. `[.withInternetDateTime, .withFractionalSeconds]` — `2026-09-05T07:55:24.906Z` (`generated_at`).
2. `[.withInternetDateTime]` — `2026-09-04T11:44:51Z`, the form the contract documents.
3. `yyyy-MM-dd'T'HH:mm:ss` in **UTC** — `2026-09-04T11:48:07`, the form every measured
   `recorded_at` actually has.

**That the third is UTC and not local is measured, not assumed**, and getting it wrong is a
two-hour error that becomes a whole-day error for anything recorded before 02:00 local. The one
recording still carrying the old timestamp-style `name` gives both readings of the same instant:
`name` = `2026-09-04 13:44:51`, `recorded_at` = `2026-09-04T11:44:51`. Two hours apart, which is
Europe/Rome's DST offset — so the name is local and the zone-less `recorded_at` is UTC with the
designator dropped.

Everything shown to a person, and the `date:` in the frontmatter, is the **local** calendar date of
that instant. `pergamenum-plaud-recorded-at` holds the service's original string unmodified: the
app never re-serializes a value it did not author, so a re-import compares strings and nothing this
app does can drift the service's own record.

Rejected: **`ISO8601DateFormatter()` with default options.** It rejects both forms actually on the
wire. This is the failure that would have shipped.

**D9. Dedup across a re-run is a quote fingerprint, and the suppression set is the union of the
note's own task lines and a local ledger. This resolves the SPEC's open question.**

The contract guarantees a task's UUID is stable *"across reads of the same proposal"* and says
nothing about two `process` runs, so an id-based rule is unsound by construction. The rule:

```
PlaudQuote.fingerprint(_ raw: String) -> String
  1. precomposedStringWithCanonicalMapping           (NFC)
  2. folding(.diacriticInsensitive, .caseInsensitive, .widthInsensitive), en_US_POSIX
  3. every character that is not a letter or a digit becomes a space
  4. split on whitespace, join with a single space
  5. an empty result is never a fingerprint: it matches nothing, including another empty one
```

Step 5 is the guard that matters: a quote of pure punctuation would otherwise fingerprint to `""`
and suppress every other such quote. Empty means "unique", never "equal".

The **suppression set** for a recording is the union of two sources, and the asymmetry is
deliberate:

- **The note itself**, read back by matching the written `(urgenza N/5, importanza N/5 — "…")`
  suffix on every task line under a theme heading. The note is the source of truth (principle 1),
  and it works even if Application Support was deleted.
- **The ledger** in `plaud.json`, which records every fingerprint ever accepted for this recording
  and never removes one.

The ledger only ever *adds* to the set. That is what makes a task the person deliberately deleted
from the note stay deleted instead of returning on the next forced re-run — the failure mode a
note-only rule has, and the reason the local file is not merely a cache here.

A proposed task whose fingerprint is in the set is shown in the review with a «già importato» mark
and its checkbox **unchecked by default**. It is not hidden and not forbidden: if the person checks
it, it is written again, because a person re-adding a task on purpose is not an error to prevent.

Known limit, named rather than solved: **a person who edits a quote inside the note changes its
fingerprint**, and the ledger is what stops that from producing a duplicate. If both the note and
the ledger have lost it, it comes back. That is the correct behaviour for a rule whose inputs are
both gone.

Rejected: **matching on task id.** Unsound per the contract, and testing it would require forcing a
real re-run of a real meeting through a real transcription pipeline.

Rejected: **asking the service.** There is no endpoint, by design: the contract states the service
does not need to know what was rejected.

Rejected: **matching on the task title.** Titles are model-generated prose and vary between runs
far more than a `quote`, which the contract pins as *"non-empty and taken verbatim from the raw
transcript"* — that verbatimness is exactly what makes it the stable key.

**D10. The quote is written inline and verbatim, minus the five characters the task grammar owns
and minus newlines — and that sanitation is provably invisible to the fingerprint.**

`TaskParser` reads `>date`, `#tag`, `^marker` and `[[wikilink]]` out of a task line's body. A quote
is transcript prose and will almost never contain any of them, but "almost never" applied to
somebody's meeting notes for the next five years is a phantom due date waiting to happen. So `>`,
`#`, `^`, `[`, `]` and any newline become a space, then whitespace is collapsed.

The property that makes this free: **fingerprint step 3 already replaces every non-alphanumeric
character with a space**, so `fingerprint(sanitized(q)) == fingerprint(q)` for every `q`. Dedup
compares the sanitized form in the note against the raw form from the service and they agree by
construction. That equality is a unit test, not a comment.

The quote is **not truncated**. It is the dedup key and the evidence for the task; the measured
maximum is ~140 characters, the editor soft-wraps, and a truncated key is a key that stops matching
the day somebody widens the truncation.

**D11. The body is themes first, transcript last, each under a heading.**

```markdown
---
date: 2026-09-04
tags:
  - type-note
  - topic-trascrizione
  - source-meeting
pergamenum-plaud-id: "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6"
pergamenum-plaud-recorded-at: "2026-09-04T11:48:07"
pergamenum-plaud-duration-ms: 1236000
---

## Tema di esempio

- [ ] Titolo task di esempio (urgenza 5/5, importanza 5/5 — "quote verbatim di esempio dal parlato.")

## Trascrizione

Speaker 1: …
```

(Struttura mostrata su un esempio sintetico — id, tema, quote e speaker fittizi. La forma dei campi
è quella misurata sul servizio reale il 2026-09-05; il contenuto no.)

Three departures from the SPEC's sketch, each with a reason:

- **The transcript moves to the end, under `## Trascrizione`.** A 58-minute meeting is tens of
  kilobytes of speech; put first, the note opens on a wall of text and the tasks are below the
  fold. Under a heading it gains an `OutlinePane` entry and the heading fold of ADR-0029 for free.
  The SPEC's sketch gives it no heading at all, so it would have had neither.
- **`related: []` and `aliases: []` are not written.** `FrontmatterSerializer.render` omits an empty
  optional key and F-08 forbids the empty form outright. The sketch is non-conformant here; the
  serializer is right and is used unchanged.
- **`tags:` is written in block form, never `[a, b]`.** F-04 forbids the inline list and
  `Frontmatter.usedInlineTagList` is a linter finding. Same conclusion: the serializer already does
  the right thing and is not bypassed.

The note is rendered in memory and written through `VaultSession.write` — one write, one history
snapshot, one index update, exactly like every other note this app creates.

**D12. Local state is two JSON files in the ADR-0017 directory. `VaultSettings` is not touched, and
neither is `IndexCache`.**

`~/Library/Application Support/it.stefer.pergamenum/vaults/<vaultID>/`:

- **`plaud.json`** — the `days` window, the notes folder, and one entry per recording: local status,
  note path once written, the accepted-quote fingerprints, and whether the confirm call is still
  owed (D13).
- **`plaud-drafts.json`** — the pending reviews: per recording, the proposal's `generated_at`, the
  per-task accept/reject decisions by task id, and the speaker renames.

Confirming the SPEC's suggestion, with the reasons stated rather than inherited:

- **Not `IndexCache`.** `clearCache()` is an ordinary button (SPEC §12, "svuota cache") and the
  index is defined as rebuildable from a vault scan (principle 3). Which recordings this vault has
  imported is *not* derivable from the vault — the fingerprints could be re-derived from the notes,
  but the deliberate deletions and the owed confirmations could not.
- **Not `.pergamenum/`.** ADR-0012's question — a fact about the vault, or a fact about this desk?
  — answers cleanly: `plaud-service` runs on this Mac and nowhere else, and principle 6 puts the
  vault on an iPad that has no Plaud at all.
- **Not `UserDefaults`.** It is per-vault and it is a growing list, not a preference. `RecentVaults`
  and `PinnedTagsStore` key on the resolved root path, which ADR-0017 §D2 already rejected as an
  identity because it does not survive a folder rename.
- **`days` and the notes folder live here too, not in `VaultSettings`.** Two reasons: a Plaud key in
  a file that syncs to a device with no Plaud is dead weight, and — the load-bearing one — keeping
  them here means this chain edits **no** file that `perg` and `pergamenum-mcp` compile except the
  linter rule of D6. The cost is named: the Impostazioni field writes through the recordings
  controller rather than through `updateSettings`, which is a second write path in that pane
  (it already has two: `settings.json` and `UserDefaults`).

The draft is keyed by `(recording id, generated_at)`. A proposal whose `generated_at` differs from
the stored one **discards the draft** and starts fresh with everything checked: task ids are stable
only within one proposal, so carrying decisions across a re-run would silently apply somebody's
choices to different tasks.

Rejected: **`VaultSettings.plaudDays`.** Genuinely defensible — `harnessRepositoryPath` is already a
machine-specific absolute path living in `settings.json` — and rejected for the two reasons above.

**D13. The import is two phases, and the ledger records the gap. A retried confirmation re-issues
only the POST.**

1. The note is written (or updated in place). The ledger records `notePath`, the new fingerprints
   and `pendingConfirmation: [task ids]`.
2. `POST /proposals/{id}/imported` is called with exactly those ids. On 204, `pendingConfirmation`
   is cleared and the row becomes `imported`.

If step 2 fails, the note stays — the local write already succeeded and file-over-app means the
file is the point — and the row reads «importata, conferma al servizio non riuscita» with a
«Riprova conferma» action that re-runs **only step 2**. The note is never re-written and no
fingerprint is added twice, which is the SPEC's edge case answered by construction rather than by a
guard.

Rejected: **confirming first, writing second.** A confirmation the vault cannot honour marks the
recording `imported` server-side with nothing to show for it, and there is no un-import endpoint.

**D14. The exception to CLAUDE.md principle 2, recorded formally. This section is R-14's first
half.**

Principle 2 says: *"Fully offline. No network call in any feature. No server, no account, no
telemetry."* This feature makes HTTP requests, so the principle must either forbid it or admit a
second named exception. It admits one, on these terms:

- **Nothing crosses a wire.** Every request goes to `127.0.0.1`, the loopback interface, which the
  kernel does not put on any network adapter. This is materially narrower than ADR-0031 §D13's
  exception, which does reach the internet: **no packet produced by this feature can leave the
  machine, in any network condition, including a misconfigured one.**
- **What is sent.** A `days` integer, a recording id, a job id, and — on confirmation — the list of
  task ids the person accepted. **No vault content, no note text, no path, no file name, no tag, no
  task text, no calendar data, ever.** Symmetrically, rejected tasks are never sent: the contract
  says the service does not need to know, and this app does not tell it.
- **No authentication, no credential, no account.** There is nothing to store and nothing to leak;
  the socket is reachable only from this machine.
- **The exception is scoped to the Registrazioni pane and does not travel.** No feature of the
  vault, Workspace, tasks, calendar, editor or index gains network access. `perg` and
  `pergamenum-mcp` remain unaware the port exists, for the reason ADR-0007 §D4 gives about EventKit.
  Enforced by D1's one-file `URLSession` test, not by memory.
- **The timing is bounded.** No launch check, no timer, no background task. Requests happen when
  the person opens or refreshes the pane, starts or retries a job, or confirms an import — plus the
  3-second poll of a job they themselves started, which stops when the job stops (D4). With the
  pane unopened, this feature makes zero requests for the app's entire life.
- **`SUSendsSystemProfile` stays `false` and this changes nothing about it.** Principle 2's
  telemetry clause is untouched: there is no telemetry here in either direction.

**Assessment, stated rather than implied.** This exception is smaller than the one already
accepted, and the feature it buys is larger. The honest cost is not privacy — it is that "no
network call in any feature" now has two written exceptions instead of one, and a rule with
exceptions is weaker than a rule without. The compensation is that both are written, argued,
scoped, and mechanically enforced, which an unwritten assumption never was.

**D15. One new pane, one new rebindable command, and the sidebar row goes last.**

- **`Navigation.Pane.recordings`**, titled «Registrazioni», symbol `waveform`. A tenth pane forces a
  tenth `ShortcutCommand` case, because `Pane.shortcut` is an exhaustive switch returning a
  catalogue entry: `paneRecordings`, default `Ctrl+Cmd+0` — the digit after the nine already bound,
  **measured free** against `com.apple.symbolichotkeys` (58 entries parsed; no match for keycode 29
  with Cmd+Ctrl). Adding a case rather than making `shortcut` optional: the raw values are the keys
  of the overrides file, so a case may be appended but never moved (ADR-0005 §D8), and appending is
  the cheaper of the two.
- **`ShortcutCommand.refreshRecordings`**, «Aggiorna registrazioni», default **`Cmd+R`** — measured
  free both in this app (`revealInFinder` holds `Cmd+Shift+R`; nothing holds the unshifted form)
  and in the system map. It is enabled only while the Registrazioni pane is showing, through
  `CommandActions+CanRun`, and it is the same action as the toolbar's `arrow.clockwise` button, per
  the UX blueprint's menu-bar map.
- **The sidebar row is appended to the `LAVORO` group, last.** The blueprint asks for it *"placed
  last, after Calendario"* and describes a four-row sidebar; the sidebar that exists has eleven rows
  in three groups (`SidebarItem.Group`). Appending to `.work` satisfies both readings — it is the
  last row of the last group, and therefore after every calendar row — and puts recordings beside
  «Attività» and «Conformità», the two other rows that are about processing rather than browsing.

Row-level actions (Elabora / Rivedi / Riprova / Elimina / Rielabora / Apri nota) get no shortcut and
no menu-bar entry, per the blueprint and per ADR-0023's precedent for row-scoped commands.

**D16. Nothing is persisted in the index, no schema moves, no protected interface is touched.**

`IndexCache.schemaVersion` stays 3. No index field, no `.canvas` property, no migration. Checked
one by one against `.claude/protected-interfaces`: `IndexCache.schemaVersion` (no index change);
`VaultAPI.LintFinding` (its JSON shape is `[String]` of interpolated violations — D6 removes some
findings from the array and changes no field, no type and no name, and `VaultPayloads.swift` is not
edited); `CompletingTextView+Pasteboard.swift` (no editor file is touched). `interface-check.sh`
must stay silent for the whole chain.

The transcript note is an ordinary note in every other respect: indexed, searchable, linkable,
renamable, and deletable by the same trash path as any other (`VaultController.trashNote`, which
already reports dangling links, closes the tab and rescans).

## Alternatives considered

**A1. Do nothing — read the transcripts in the Plaud service's own output and copy what matters
into a note by hand.** Zero code, zero network, principle 2 intact. Rejected on the measured shape
of the material: a single meeting produced four themes and 25 tasks with verbatim quotes, urgencies
and importances. Transcribing that by hand is the work the service exists to remove, and doing it
by hand is also where the anchoring disappears — a hand-made note has no `pergamenum-plaud-id`, so
a re-run cannot find it and R-08 is unreachable in principle.

**A2. Read the service's data files directly off disk instead of speaking HTTP.** This is the
strongest alternative and the only one that would keep principle 2 literally intact — no socket, no
exception, no D14. Rejected on three counts, the third fatal: the service's storage is a private
implementation detail of a different repository, and reading it couples this app to internals the
contract exists precisely to hide; a file format has no version negotiation, so an upgrade over
there silently corrupts this side; and **there is nothing to read until a job has run.** A proposal
is produced on demand by `POST /recordings/{id}/process`, and no amount of file reading can start
one. The feature is not "read some files", it is "drive a pipeline".

**A3. A sidecar file mapping note path → recording id, leaving the frontmatter closed.** Rejected
under D6: the anchor would not survive a note rename, a move, a vault handed to somebody else, or
the deletion of Application Support — and principle 1 says the file must carry its own meaning.

**A4. Write `type-trascrizione` as the SPEC asks, adding `trascrizione` to `vocabolari.json`.**
Rejected under D7 and principle 5: that file is a declared replica of `harness-system`'s closed
table, and editing it to suit the app inverts the direction conventions are allowed to travel. The
note would also still be missing `type-note` and a `topic-*`.

**A5. Dedup on task id.** The obvious rule, and unsound: the contract pins id stability to reads of
one proposal, not across `process` runs. Rejected under D9. It is also the rule that fails
*silently* — a duplicate arrives looking like a new task.

**A6. Ask the service what was already imported.** No endpoint exists, and the contract is explicit
that rejected tasks are deliberately not reported, so the service could not answer even in
principle. Rejected.

**A7. A settable host and port in Impostazioni.** Rejected under D2. It costs the exception its
boundary: D14's promise is checkable only because the sole reachable address is a literal in one
file.

**A8. Put `days` and the notes folder in `VaultSettings`.** Genuinely defensible —
`harnessRepositoryPath` is already a machine-specific path in `settings.json`, and the Impostazioni
pane's plumbing is built for exactly this. Rejected under D12 because it would grow a struct both
connectors compile, for a key that is dead weight on any device without a Plaud service, when the
ledger it belongs beside already lives in a per-vault local file.

**A9. Refresh the list on a background timer, or check `/health` at launch.** Rejected under D4 and
D14: an app that reaches a socket on a schedule is a different thing from one that answers when
asked, and the timing bound is half of what makes the exception narrow.

**A10. Write the transcript as its own note, linked from a tasks note.** Two files per recording,
two things to rename, two to delete, and the tasks lose the evidence they were extracted from.
Rejected; the SPEC asks for one note and one note is right.

**A11. Truncate the quote in the note and keep the full text only in the ledger.** Shorter task
lines, and it breaks D9's guarantee: the note stops being a sufficient source for the suppression
set, so deleting Application Support would start producing duplicates. Rejected — the quote in the
file *is* the mechanism.

**A12. Keep the review as a third column instead of a sheet.** Rejected by the UX blueprint, and
correctly: the review is a bounded flow that ends in import or cancel, not a browsing surface, and
a third column would need persistent state for something that must not persist past the decision.

## Consequences

**Positive.**

- A recording becomes a real note with real task lines in the vault, with no retyping, and the
  tasks land in every surface the app already has — Attività, the week, the day, search, the index
  — because they are ordinary task lines and nothing else (ADR-0021's premise paying off again).
- **A re-run is safe.** `pergamenum-plaud-id` makes the note findable and the fingerprint rule makes
  the merge idempotent, so «Rielabora» is a button somebody can press twice.
- **Principle 2 comes out of this better specified, not weaker.** It now distinguishes a request
  that leaves the machine (ADR-0031, one host, manual) from one that cannot (this ADR, loopback,
  manual), and both are enforced by tests rather than by anybody's memory.
- The linter stops being wrong about this app's own notes, in the one narrow way D6 opens, while
  still condemning every genuinely foreign key.
- Five measured contract deviations — the timestamp with no zone, the fractional-second one, the
  human-title name, the already-named speakers and the always-null `due_hint` — are handled by
  design instead of being discovered at 3am by a decode failure.

**Negative.**

- **This app now opens a socket, and the sentence in CLAUDE.md that says it does not needs its
  second qualifier.** Two written exceptions is a real erosion of a very clean property, and no
  amount of scoping makes "fully offline" as true as it was yesterday.
- **The feature depends on a program in another repository.** If `plaud-service` changes a field
  name, this app fails to decode and the pane shows an error; there is no shared type, no versioned
  schema, and no test on this side that can see the change coming. The mitigation is a fixture
  suite captured verbatim from live responses, which detects nothing until somebody re-runs the
  capture.
- **Five of eight recordings are currently `failed`**, so the first impression of the pane is a
  list of errors. That is the service's problem and not this app's, but it is this app's screen.
- **The transcript note is large** — tens of kilobytes for a long meeting — and every save writes a
  full `NoteHistory` snapshot (ADR-0011 §D4, thinned but unbounded in age). A vault with many
  recordings grows its history directory noticeably faster than one without.
- **A twentieth UI-test file will need `-disablePlaud YES`**, a third standing tax beside
  `-disableCalendar` and `-disableUpdater`. Nothing enforces it but this sentence and the three
  places it is already written down.
- **The Impostazioni pane gains a third write path.** Its two existing ones (`settings.json` and
  `UserDefaults`) are documented in its own header; the recordings controller is a third, and the
  header needs to say so or the next person will assume the field is a `VaultSettings` key.

**Neutral.**

- The pane's visual language is the existing sidebar-section/list one and adds no design token; the
  status badges reuse the app's existing badge treatment. Nothing here reaches the theme.
- Sparkle and Plaud both make requests and are entirely unrelated: neither knows the other exists,
  and the two exceptions share no code, no session and no configuration.
- `recording_kind` is shown in the review header and used for exactly one decision (the
  `source-meeting` tag). The other three kinds are display-only, which is all the SPEC asks.
- The service's `device_serial` is decoded and ignored. It is in the payload, it is not in the
  note, and nothing this app does depends on which recorder produced the file.
- Speaker renaming applies only at review time and only to lines beginning `<label>:`, anchored on
  the colon so `Speaker 1` cannot match inside `Speaker 10`. Renaming after import is a SPEC
  non-goal and stays one.

## Non-goals

Restated from the SPEC so the boundary is in one place: nothing on the `Plaud` side is touched; no
`perg` or `pergamenum-mcp` exposure and no new `Sources/Connector` surface; no EventKit or Reminders
object for an imported task (the `>date` on the line is the whole of it); no Workspace card for a
recording; no retroactive speaker rename; no delete endpoint call; no automatic or scheduled check
of any kind; no second network destination; no index field, no schema bump, no migration.

## References

- SPEC: `SPEC.md` (this chain, R-01 … R-15). Its Data model is amended by D5, D7, D8 and D11; its
  open question about task dedup is resolved by D9; its suggestion about local state is confirmed
  by D12.
- UX blueprint: `UX-BLUEPRINT.md` — window inventory (review as a `.sheet`), the `Cmd+R` map, the
  «placed last» sidebar decision reconciled in D15, and the accessibility checklist.
- Plan: `docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md`.
- Service contract: `/Users/stefer/Developer/Plaud/docs/PERGAMENUM-API.md` (v0.2, read-only, out of
  this repository and deliberately not copied into it). Live responses measured 2026-09-05.
- `CLAUDE.md` — principle 1 (file over app, D6/A3), principle 2 (excepted by D14), principle 3
  (untouched, D12/D16), principle 4 (Obsidian preserves unknown keys, D6), principle 5 (forbids
  A4), §Stack (not sandboxed), §AI connector (`sharedSources`, D1), §Working agreements (the
  UI-suite launch-argument precedent behind D3).
- ADR-0007 §D2/§D4 — the connectors compile the same files and deliberately lack interactive-app
  capabilities; this feature is absent from both for the same reason.
- ADR-0011 §D4 — `NoteHistory` writes a snapshot per save (the size consequence above).
- ADR-0012 §D6/§D10 — the question that sorts vault state from desk state, applied in D12.
- ADR-0017 §D1/§D2 — the per-vault Application Support directory D12 writes into.
- ADR-0020 — `pergamenum-crop`, the precedent for extending somebody else's closed schema by
  prefixing (D6).
- ADR-0021 §D1 — the task line is the storage; no new table, `schemaVersion` stays 3.
- ADR-0031 §D2/§D4/§D13 — the one-file import test, the launch-argument isolation, and the shape an
  exception to principle 2 has to take.
- `Sources/Core/Conventions/Frontmatter.swift` — `:206-208` (foreign keys preserved), `:299-301`
  (written back), `:335` (the one line D6 changes).
- `Sources/Core/Conventions/Tag.swift` — `:133-152` (`missingRequired`, forcing D7),
  `Vocabulary.swift:68-73` (which families are closed).
- `Sources/Core/Conventions/NoteName.swift` — `:13` (forbidden characters), `:14` (60), and
  `ImportNaming.swift:81-129` (`kebabCase`, `uniqueFileName`) reused by D5.
- `Sources/Calendar/CalendarService.swift:69-104,151` — the `CalendarStore` protocol and
  `isIsolated`, copied by D2 and D3.
- `Sources/Vault/VaultState.swift:31-46` — the per-vault state directory D12 extends.
- `Sources/App/SidebarItem.swift`, `Sources/App/Navigation.swift`,
  `Sources/Core/Shortcuts/ShortcutCommand.swift` — the three files D15 touches.
- `Project.swift:72-112` (`sharedSources`), `:190-192` (the app target's glob, which picks up
  `Sources/Features/Recordings/**` with no manifest edit).
- Apple documentation and developer-forum guidance on loopback, checked 2026-09-05: loopback
  addresses are an explicit exception to macOS local-network privacy, and ATS does not apply to an
  IP-literal loopback request. Verified from the app process by the plan's Task 2 rather than
  trusted.
