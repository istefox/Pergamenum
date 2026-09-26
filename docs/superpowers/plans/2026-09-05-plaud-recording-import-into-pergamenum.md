# Plan — Plaud recording import into Pergamenum

- **ADR:** `docs/adr/0032-plaud-recording-import-into-pergamenum.md`
  (the architect wrote it to `docs/architecture/ADR-0032-plaud-recording-import-into-pergamenum.md`
  because `test-write-scope.sh` permits only that root; the orchestrator relocates it and removes
  the filing note at the top, as it did for ADR-0030 and ADR-0031 on 2026-09-04)
- **SPEC:** `SPEC.md` at the repository root (R-01 … R-15)
- **UX blueprint:** `UX-BLUEPRINT.md` at the repository root — honoured throughout; its one
  inaccuracy (the sidebar has eleven rows in three groups, not four rows) is reconciled by
  ADR-0032 §D15 without changing its decision
- **Branch base:** `feat/plaud-recording-import` forked from `main`. **Not** the current
  `feat/editor-page-typography-noteplan` branch — that chain is unrelated and still open.
- **Style:** TDD. Red precondition first on every task, per this repo's last nine chains.
- **Service contract:** `/Users/stefer/Developer/Plaud/docs/PERGAMENUM-API.md` — read-only, outside
  this repository. **Do not copy it in, do not edit anything under `/Users/stefer/Developer/Plaud`.**

---

## Before anything: what the SPEC and the contract say that the world does not

Every row was **measured live on 2026-09-05** against the running service. Do not design or code
against the left column.

| # | SPEC / contract says | The live service says | Where |
|---|---|---|---|
| C1 | `recorded_at` is ISO 8601 UTC, e.g. `2026-09-04T11:44:51Z` | **No zone designator, in all eight rows**: `2026-09-04T11:48:07`. `generated_at` meanwhile is `2026-09-05T07:55:24.906Z` — zone *and* fractional seconds. `ISO8601DateFormatter()` with default options **rejects both**. | ADR §D8 |
| C2 | zone-less means "unknown" | **It means UTC**, measured: the one recording still carrying the old name form has `name` `2026-09-04 13:44:51` and `recorded_at` `2026-09-04T11:44:51` — exactly Europe/Rome's +2 DST offset. Reading it as local is a two-hour error and a whole-day error before 02:00. | ADR §D8 |
| C3 | `"name": "2026-09-04 13:44:51"` | **Seven of eight are human titles**, e.g. `09-04 Riunione: Preparazione revisione trimestrale con cliente - Diagramma di Flusso Componenti` — 79 chars, contains `:`. Both shapes coexist. A note title may not contain `:` and may not exceed 60 chars. | ADR §D5 |
| C4 | tag `type-trascrizione` | **Unwritable.** `type` is a closed family (`Vocabulary.swift:68-73`) and `trascrizione` is not in `Resources/vocabolari.json`. Adding it violates CLAUDE.md principle 5. Also `TagRules.missingRequired` demands `type-note` **and** a `topic-*` on any ordinary note. Use `type-note` + `topic-trascrizione` (+ `source-meeting` when kind is `meeting`). | ADR §D7 |
| C5 | frontmatter sketch with `related: []`, `aliases: []`, `tags: [type-trascrizione]` | **Non-conformant three ways.** F-08 forbids the empty forms and `FrontmatterSerializer.render` omits them anyway; F-04 forbids the inline tag list and the serializer writes the block form. Use the serializer unchanged — do not hand-write YAML. | ADR §D11 |
| C6 | speakers are `Speaker 1`, `Speaker 2` | **The service already resolves most of them**: `["Speaker 1", "Nome Cognome A", "Nome Cognome B", "Nome Cognome C"]`. Pre-fill each rename field with the label as given, not with a synthesised «Speaker N». | ADR §D8/M4 |
| C7 | `due_hint` is an ISO date or null | **Null on 25 of 25 tasks sampled.** The `>date` marker is the exception. A writer that assumes a date emits a bare `>`. | ADR §D11 |
| C8 | failure is an edge case | **Five of eight recordings are `failed`**, with three unrelated raw strings including one that is not a coded error at all (`Plaud MCP tool get_transcript returned non-JSON content: Bl…`). R-07 needs a mapping table **and** a fallback. | ADR §M5 |
| C9 | `http://127.0.0.1:3777`, loopback | **IPv4 only**, measured with `lsof`. `localhost` may resolve to `::1` first and connect to nothing. Use the IP literal, never the hostname. | ADR §D2 |
| C10 | recording ids and task ids are UUIDs | Task ids are UUIDs; **recording ids are 32-char hex** (`a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6`). Both are opaque strings — never type either as `UUID`. | ADR §M3 |

**Four constraints the SPEC could not know:**

1. **The frontmatter parser already round-trips unknown keys** (`Frontmatter.swift:206-208`,
   `:299-301`). The *only* code change the schema reopening needs is one condition in
   `FrontmatterRules.validate` (`:335`) — not a parser change, not a serializer change.
2. **`.claude/test-cmd` is `-only-testing:PergamenumTests`** and runs at the end of every turn
   through the `Stop` hook. It does **not** build `perg` or `pergamenum-mcp`, so R-15's real
   enforcement is a unit test plus two deliberate builds in Task 9.
3. **The service is running on this Mac right now** and answers `/health` with 200. Nineteen files
   under `UITests/` call `launch()`. Without `-disablePlaud YES` a UI test can list somebody's real
   meetings and enqueue real transcription work.
4. **`Sources/Features/**` is not in `sharedSources`** and the app target globs `Sources/**`
   (`Project.swift:190-192`), so every new file in this chain needs **no `Project.swift` edit**.

---

## Contract changes and their already-grepped call sites

Every row was grepped **before** this plan was written. The coder does not go looking for these;
they are listed and updated in the same task that changes the contract. **Run the full unit suite
after each task, not just the touched file's tests.**

| Contract | Change | Call sites that break or go stale |
|---|---|---|
| `FrontmatterRules.validate` (`Sources/Core/Conventions/Frontmatter.swift:335`) | stops emitting `.foreignKey` for a key matching `^pergamenum-[a-z0-9]+(-[a-z0-9]+)*$` | Grepped for `foreignKey`, all 8 hits: `Frontmatter.swift:7` (doc comment — **update it**), `:21`, `:35`, `:207`, `:299`, `:314`, `:335` (the change), `Sources/Features/Editor/VaultBrowser.swift:317` (renders «Chiave fuori schema» — no edit needed, it renders fewer findings). **No signature changes.** `FrontmatterViolation` gains no case. `Tests/ConventionsTests.swift` asserts on foreign keys — read it and add the prefixed-key case beside the existing ones, do not replace them. |
| `Navigation.Pane` (`Sources/App/Navigation.swift:13-84`) | `+ case recordings` | Two exhaustive switches in the same file (`title`, `symbol`, `shortcut`) — all three must gain a case or it does not compile. `RootView.swift:238-248` `detail` switch. `MenuCommands.swift:25` iterates `allCases` and needs no edit. `Sources/Features/DesignGallery/*` — grepped, no `Pane` switch. |
| `ShortcutCommand` (`Sources/Core/Shortcuts/ShortcutCommand.swift`) | `+ case paneRecordings`, `+ case refreshRecordings`, **appended at the end of the enum, never inserted** | Three exhaustive switches in the same file (`section`, `title`, `defaultBinding`). `Tests/ShortcutTests.swift` — `noTwoCommandsShipOnTheSameKeys` will fail if either binding collides; both were measured free (Cmd+R plain, Ctrl+Cmd+0). `Sources/App/CommandActions.swift` and `CommandActions+CanRun.swift` — `run(_:)`/`canRun(_:)` switches. **The raw values are the keys of the overrides file (ADR-0005 §D8): append only.** |
| `SidebarItem.Group.items` (`Sources/App/SidebarItem.swift:74-83`) | `.work` gains `.pane(.recordings)` **last** | No other call site: `RootView.sidebar` iterates `Group.allCases` then `group.items`. |
| `PergamenumApp` (`Sources/App/PergamenumApp.swift`) | `+ @State private var recordings: RecordingsController`, built in `init()` beside `day`/`diary`; `+ .environment(recordings)` on `RootView` | `init()` `:76-124` (the `_x = State(initialValue:)` pattern — copy it, `RecordingsController(service:vault:)` needs `vault`, which exists as a local there). `.environment` chain `:149-158`. The Settings scene's chain `:232-240` also needs it if the Impostazioni field reads the controller — **it does**. |
| `UITests/**` (19 files) | every `XCUIApplication()` gains `-disablePlaud`, `YES` beside `-disableCalendar`, `YES` | Grepped: `-disableCalendar` appears in all 19. Same edit, same place, one task. **Do not add a twentieth UI-test file in this chain without it.** |
| `ImportNaming` (`Sources/Core/Conventions/ImportNaming.swift`) | `+ static func recordingNoteTitle(recordedAt:name:)` | **Additive only.** `kebabCase` and `uniqueFileName` are called but not modified. This file is inside `Sources/Core/**` → compiled into `perg` and `pergamenum-mcp`; it is Foundation-only and must stay so. |
| `.claude/protected-interfaces` | **nothing added, nothing touched** | Checked one by one: `IndexCache.schemaVersion` (stays 3, no index change); `VaultAPI.LintFinding` (`Sources/Connector/VaultPayloads.swift` is **not edited** — its `frontmatter: [String]` field simply carries fewer interpolated violations); `CompletingTextView+Pasteboard.swift` (no editor file is touched). `interface-check.sh` must stay silent for the whole chain. **If a task looks like it needs to edit a connector or editor file, stop and report.** |
| `Project.swift` | **not edited**, unless Task 2's ATS probe fails | The app target already globs `Sources/**`. The only possible edit is the named fallback `NSAppTransportSecurity: { NSAllowsLocalNetworking: true }`, and only if the probe proves it necessary. **Never `NSAllowsArbitraryLoads`.** |

---

## Conventions binding on every task

- **The tester owns the interface, the coder owns the body** (ADR-0155 of the
  retired concept-to-code workflow, not a Pergamenum ADR). Swift is compiled: a batch
  that leaves the target unable to build produces no red tests at all, only a build error. Every
  new type's *declaration* — stored properties, function signatures returning a stub — is written in
  the **tester's** task together with the tests that call it. The coder fills bodies.
- **Every new source and test file's header cites both `ADR-0032` and this plan's basename**
  (`2026-09-05-plaud-recording-import-into-pergamenum`) — ADR-0154: a harness naming neither is
  descoped.
- **Swift Testing (`@Test`/`#expect`) for all new tests.** Never XCTest, except inside `UITests/`,
  which is an XCTest bundle and stays one.
- **One principal type per file** (`~/.claude/rules/swift.md`). `@Observable`, never
  `ObservableObject`. No force-unwrap, no `try!`.
- **Nothing goes under `Sources/Core`, `Sources/Connector`, `Sources/Index`, `Sources/Calendar` or
  `Sources/Vault`** except the two named additive edits (`Frontmatter.swift`, `ImportNaming.swift`),
  both Foundation-only. An AppKit/SwiftUI import in either breaks both connector builds
  (ADR-0001 §D1).
- **`URLSession` appears in exactly one file**, `Sources/Features/Recordings/PlaudHTTPClient.swift`.
  Task 2's test enforces it. If a task looks like it needs a second, **stop and report**.
- **No test makes a real network request** except the one explicitly named probe in Task 2. Every
  other test drives `FakePlaudService`.
- **`tuist generate --no-open` after every task that adds a file under `Sources/` or `Tests/`.**
- **The unit test command is `.claude/test-cmd` exactly as it stands** — do not widen it: the UI
  tests in there terminate the app the person at the keyboard is using, and it runs at the end of
  every turn through the `Stop` hook.
- **`scripts/uitests.sh` runs once, in Task 10, before merge** — never per task, and with **no
  argument** (an argument *replaces* the selection rather than adding to it).
- **Any shell helper is Bash 3.2-clean.** macOS ships bash 3.2: no `mapfile`, no associative arrays,
  no `${x^^}`/`${x,,}`. `#!/usr/bin/env bash` + `set -euo pipefail`, every variable quoted.
  **`python3`, never `python`.**
- **Nothing under `/Users/stefer/Developer/Plaud` is read except `docs/PERGAMENUM-API.md`, and
  nothing there is ever written.**
- **No `POST` is issued against the live service by any task before Task 10.** `GET` probes are
  fine; `POST /recordings/{id}/process` starts real transcription work and
  `POST /proposals/{id}/imported` permanently marks a recording imported server-side with no
  un-import endpoint. Task 10 is the HITL gate for both.
- **`weakening-scan.sh` reports every Swift Testing test as `zero-assertion-test`** because it treats
  `#expect` as a comment. Expected, systematically wrong for this stack, advisory.
- **The secret scanner's `assigned-secret` heuristic will fire** on this chain's `token`-adjacent
  lines and on anything shaped `id = "<32 hex>"`. Read every hit; these are recording ids, not keys.

---

## Phase 1 — the wire and the store (no UI, no vault write)

### Task 1 — the payloads, the tolerant timestamp, and the readable error (R-03, R-07, R-13)

- Budget: `Sources/Features/Recordings/PlaudPayloads.swift`,
  `Sources/Features/Recordings/PlaudTimestamp.swift`,
  `Sources/Features/Recordings/PlaudError.swift`, `Tests/PlaudPayloadTests.swift`,
  `Tests/PlaudTimestampTests.swift` (~420 lines)
- **Tester first.** Write the three tests plus the *declarations* of the three types. The suite must
  **build** and go **red**.
- **Fixtures are captured verbatim from the live service**, as string literals in the test file —
  not fetched at test time. Capture with `curl -s http://127.0.0.1:3777/recordings?days=14` and
  `curl -s http://127.0.0.1:3777/proposals/<id>`; the values already measured are in the ADR's
  Context table and in C1–C10 above. **A fixture that was edited to be tidy is a fixture that tests
  nothing** — keep the 79-character name with its colon, keep the null `due_hint`s, keep the empty
  `themes` array, keep all three raw error strings.
- **Explicit `CodingKeys`, never `.convertFromSnakeCase`.** The contract lives in another repo and
  the mapping should be readable beside it.
- `state` and `recording_kind` decode through a wrapper with an `.unknown(String)` case, never a
  bare `RawRepresentable` enum that throws — a service upgrade adding a state must not break the
  whole list decode.
- `PlaudTimestamp.parse` tries the three shapes of ADR §D8 in order. Tests must include: the
  fractional-second `Z` form, the plain `Z` form, the zone-less form **asserted to be UTC**, and a
  garbage string returning `nil`.
- `PlaudError` maps HTTP status + body to a readable Italian message: 400 `invalid_days`, 404
  (`unknown recording` / `job` / `proposal_not_found`), 413, 503 (Plaud disconnected), transport
  failure (service down), decode failure. **Plus a mapping for the three measured `last_error`
  strings and a verbatim fallback** for anything unrecognised — R-07 says "readable, not raw", and
  an unrecognised string shown raw with a prefix is more honest than a generic sentence.
- Verify: `.claude/test-cmd` green.

### Task 2 — `PlaudService`, `PlaudHTTPClient`, and the loopback question answered by measurement (R-01, R-02, R-13, R-15)

- Budget: `Sources/Features/Recordings/PlaudService.swift`,
  `Sources/Features/Recordings/PlaudHTTPClient.swift`, `Tests/PlaudIsolationTests.swift`,
  `Tests/FakePlaudService.swift` (~300 lines)
- **Tester first.** `FakePlaudService` (a `PlaudService` whose responses are set per test, including
  thrown errors) plus `PlaudIsolationTests`. Red first.
- The protocol is exactly the six methods in ADR §D2. `PlaudHTTPClient` is a `struct: Sendable`
  holding one `URLSession` built from `.ephemeral` with the five settings named there.
- **`PlaudEndpoint.base` is the literal `URL(string: "http://127.0.0.1:3777")!`** — one named
  constant, one file. Never `localhost` (C9). This is the one permitted force-unwrap-shaped
  construct; prefer a `static let base: URL` built with `URL(string:)!` guarded by a test that it is
  non-nil, or use the non-failable `URL(string:encodingInvalidCharacters:)` if it types cleanly.
- `PlaudIsolationTests` walks the repo from `#filePath` and asserts `URLSession` appears in exactly
  one file under `Sources/`. This is R-15's mechanical half and D14's enforcement.
- **The loopback probe, run once and reported, not automated into the suite.** From a scratch
  target or a `swift` snippet run inside the app process context, issue one `GET /health` through
  `URLSession` and record the outcome:
  - **Success** → ATS does not apply and no `Project.swift` edit is needed. Say so in the task
    report.
  - **Failure with an ATS error (`NSURLErrorAppTransportSecurityRequiresSecureConnection`, -1022)**
    → add **only** `NSAppTransportSecurity: { NSAllowsLocalNetworking: true }` to
    `Project.swift`'s `infoPlist`, `tuist generate`, re-probe. **Never `NSAllowsArbitraryLoads`.**
  - **A local-network privacy prompt appears** → contradicts the documented loopback exemption;
    **stop and report** rather than adding `NSLocalNetworkUsageDescription` on a hunch.
- Verify: `.claude/test-cmd` green; probe outcome written into the task report.

### Task 3 — the local store: ledger, days window, and the pending-review drafts (R-10, R-11, R-12)

- Budget: `Sources/Features/Recordings/PlaudVaultStore.swift`, `Tests/PlaudVaultStoreTests.swift`
  (~330 lines)
- **Tester first.** Red before any body.
- Two files under `<state base>/vaults/<vaultID>/`: `plaud.json` and `plaud-drafts.json`, per
  ADR §D12. **The store takes its directory as an injected `URL`** — never resolves Application
  Support itself. `VaultState.applicationSupportBase()` has a `precondition` that fires under test
  (`VaultState.swift:67-71`), and the suite must write into a temporary directory or it fills the
  real one (ADR-0017 §Consequences: 860 stray directories from one afternoon).
- `plaud.json` shape: `days` (Int, default 14, **clamped 1…3650 on the way in** — the service
  returns 400 `invalid_days` outside that, SPEC Edge cases), `notesFolder` (String, default
  `"Registrazioni"`), and `recordings: [id: Entry]` where `Entry` carries local status, `notePath?`,
  `quoteFingerprints: [String]`, `pendingConfirmation: [String]`, `lastImportedAt?`.
- `plaud-drafts.json` shape: `[recordingID: Draft]`, `Draft` = `generatedAt` (the proposal's own
  string, verbatim), `decisions: [taskID: Bool]`, `speakerRenames: [String: String]`.
- **Decoded key by key with `decodeIfPresent` and a fallback**, the `VaultSettings.init(from:)`
  pattern (`VaultSettings.swift:161-211`) — a file written before a field existed must not be
  discarded whole.
- Tests must cover: round-trip; a missing file yielding defaults; a corrupt file yielding defaults
  **without throwing** and without deleting the corrupt file; `days` clamping; **draft invalidation
  when `generatedAt` differs** (R-10's boundary); and two different vault ids not seeing each
  other's state (R-12).
- Verify: `.claude/test-cmd` green.

## Phase 2 — the vault write

### Task 4 — the note builder: title, frontmatter, tags, body, quote sanitation (R-05)

- Budget: `Sources/Features/Recordings/TranscriptNote.swift`,
  `Sources/Core/Conventions/ImportNaming.swift` (additive), `Tests/TranscriptNoteTests.swift`,
  `Tests/ConventionsTests.swift` (additive) (~450 lines)
- **Tester first.** Red before any body.
- `ImportNaming.recordingNoteTitle(recordedAt:name:)` per ADR §D5, with tests for **both measured
  name shapes** (the 79-char title with the colon, and the old `2026-09-04 13:44:51` form), the
  leading-date-token strip, the ≤60 truncation at a word boundary, and the no-trailing-hyphen rule.
  Foundation-only — this file compiles into both connectors.
- `TranscriptNote.render(...)` is a **pure function**: proposal + accepted task ids + speaker
  renames + existing note text (optional) → the full file text. No `VaultSession`, no disk. That is
  what makes R-05 and R-08 unit-testable at all.
- It builds the frontmatter through `Frontmatter` + `FrontmatterSerializer.render` — **never by
  hand-writing YAML** (C5). The three `pergamenum-plaud-*` keys go in as `foreignKeys` entries with
  their raw lines. Tags per ADR §D7: `type-note`, `topic-trascrizione`, and `source-meeting` only
  when `recording_kind == "meeting"`.
- Body per ADR §D11: `## <Theme>` sections in proposal order, then `## Trascrizione` last.
- Task line: `- [ ] <title>` + ` >YYYY-MM-DD` **only when `due_hint` is non-null** (C7) +
  ` (urgenza N/5, importanza N/5 — "<quote>")`.
- **Quote sanitation per ADR §D10**: `>`, `#`, `^`, `[`, `]` and newlines become spaces, whitespace
  collapsed. A test asserts the invariant `fingerprint(sanitized(q)) == fingerprint(q)` — this is
  the property the dedup rule of Task 5 rests on, so it is a test and not a comment.
- **Speaker rename applies only to a line whose trimmed prefix is exactly `<label>:`** — a test must
  cover `Speaker 1` vs `Speaker 10` not cross-matching, and must cover a label the service already
  resolved to a real name being left alone by default (C6).
- **A test writes the rendered note through a `TemporaryVault` and runs the vault's own linter over
  it, asserting zero findings.** That is the `#30` standard: the app must not generate a file its
  own linter flags. It will be red until Task 9 lands the frontmatter allowance — **that is
  expected and correct**; mark it and keep it red rather than weakening it.
- Verify: `.claude/test-cmd` — all green except the named linter assertion.

### Task 5 — the dedup rule and the in-place merge (R-08)

- Budget: `Sources/Features/Recordings/PlaudQuote.swift`,
  `Sources/Features/Recordings/TranscriptNote.swift` (merge path), `Tests/PlaudQuoteTests.swift`,
  `Tests/TranscriptMergeTests.swift` (~380 lines)
- **Tester first.** Red before any body.
- `PlaudQuote.fingerprint` exactly as ADR §D9, five steps. Tests: accents fold
  (`però`/`PERO`), case folds, punctuation and whitespace collapse, NFC vs NFD equality, **the
  empty-fingerprint guard (two punctuation-only quotes must NOT match)**, and the
  `fingerprint(sanitized(q)) == fingerprint(q)` invariant re-asserted from the other side.
- `TranscriptNote.suppressionSet(existingNoteText:ledgerFingerprints:)` — the union of ADR §D9.
  Reading the note back means matching the `(urgenza N/5, importanza N/5 — "…")` suffix on task
  lines; a task line that does not match the shape (the person rewrote it) contributes nothing and
  is not an error.
- The merge path: given an existing note text and a new proposal, produce a new text that keeps the
  person's own edits outside the theme sections, adds only non-suppressed accepted tasks, and does
  not duplicate a theme heading that already exists. **Tests must cover:** re-import with an
  identical proposal producing a byte-identical note; re-import with one new task appending exactly
  one line; a task the person deleted from the note but present in the ledger **not** returning; a
  task whose quote the person edited returning as a duplicate **only when the ledger has also lost
  it**; and a new theme creating a new `## ` section without disturbing the transcript section.
- **`## Trascrizione` is replaced wholesale on a re-run**, since a forced re-run may produce a
  better transcript; the theme sections are merged, never replaced. A test pins that asymmetry.
- Verify: `.claude/test-cmd` — same one expected-red linter assertion from Task 4.

## Phase 3 — the controller and the interface

### Task 6 — `RecordingsController`: list, health, process/poll, two-phase import, delete (R-01, R-02, R-03, R-06, R-07, R-09, R-12, R-13)

- Budget: `Sources/Features/Recordings/RecordingsController.swift`,
  `Tests/RecordingsControllerTests.swift` (~520 lines)
- **Tester first.** Every test drives `FakePlaudService`; **no test touches the network.** Red first.
- `@MainActor @Observable final class RecordingsController`, built with
  `(service: any PlaudService, vault: VaultController)`, following `DayController(store:vault:)`
  (`PergamenumApp.swift:83`).
- `isIsolated = UserDefaults.standard.bool(forKey: "disablePlaud")` — the exact shape of
  `EventKitStore.isIsolated` (`CalendarService.swift:151`). When set, **every method returns without
  making a request** and `health` reports unavailable. A test asserts the fake receives zero calls.
- **Polling per ADR §D4**: one stored `Task`, `try await Task.sleep(for: .seconds(3))`, cancelled on
  job end, on vault change, and in a `stop()` the scene calls. **Bounded at 30 minutes**, after
  which it stops and the row says so. Tests use an injected clock or a shortened interval — do not
  make the suite sleep for real.
- **Vault scoping (R-12):** the controller reloads its store when `vault.session` changes identity.
  A test opens two `TemporaryVault`s and asserts the second sees none of the first's entries.
- **Two-phase import per ADR §D13:** write note → record ledger + `pendingConfirmation` → POST. A
  test makes the fake throw on `confirmImported` and asserts the note still exists, the row reports
  the failed confirmation, and `retryConfirmation` re-issues **only** the POST — asserted by call
  count on the fake, and by the note's bytes being unchanged.
- **R-06 exactly:** the POST body carries the accepted task ids and nothing else. A test with a
  mixed accept/reject set asserts the rejected ids are absent.
- **Delete (R-09):** confirmation is the *caller's* job; the controller calls
  `vault.trashNote(at:)` (`VaultController+Files.swift:70`) and marks the ledger entry deleted.
  A test asserts **no service method is called at all** during a delete.
- **R-13:** each error from the fake surfaces as a readable message on the right part of the state
  (banner vs row), never a crash and never a raw `Error` interpolation.
- Verify: `.claude/test-cmd` green (except the known Task 4 linter assertion).

### Task 7 — the pane and the review sheet (R-01, R-02, R-04, R-07, R-09, R-10)

- Budget: `Sources/Features/Recordings/RecordingsPane.swift`,
  `Sources/Features/Recordings/RecordingRow.swift`,
  `Sources/Features/Recordings/ReviewSheet.swift`, `Tests/RecordingsViewModelTests.swift`
  (~600 lines)
- **Tester first** on everything that is a value rather than a view: row status → badge text +
  symbol + available actions, the health banner's copyable command string, the review sheet's
  initial checkbox state (all checked, except suppressed ones unchecked per ADR §D9). Red first.
- Follows the existing sidebar-section/list visual language (blueprint) — **no new design token**,
  and **every colour and font through the theme** (CLAUDE.md binding rule).
- Row per status, per the blueprint: `new`→Elabora, `processing`→progress + step name,
  `ready`→Rivedi, `failed`→readable error + Riprova (`force=1`), `imported`→Apri nota / Elimina /
  Rielabora.
- **Health banner (R-02)** replaces the list and shows
  `launchctl load ~/Library/LaunchAgents/it.stefer.plaud-service.plist` as **selectable text plus a
  copy button. The app never executes it** — no `Process`, no `NSTask`, anywhere in this chain.
- **Review sheet (R-04)** is a `.sheet` (blueprint), Form-based, scrollable: header (name, local
  date, duration, `recording_kind`), per-speaker rename fields pre-filled with the label as given
  (C6), per-theme sections with per-task checkboxes, quote, urgency/importance as plain text,
  `due_hint` as a date when present. `no_action_items` shows a banner and **the Importa button stays
  enabled** — a transcript-only import is valid (SPEC). `warnings` shows a dismissible informational
  notice.
- **R-10:** every change to a checkbox or a rename field writes the draft through the store
  immediately. A test asserts a reconstructed sheet state from a persisted draft, including the
  `generatedAt` mismatch discarding it.
- **Accessibility checklist from the blueprint is a task deliverable, not an afterthought**:
  `accessibilityLabel` on every icon-only row button; every task checkbox's label includes the task
  title; status badges exposed as text, never colour alone; semantic fonts only; the sheet keyboard-
  navigable. `accessibilityIdentifier` on the pane, the Aggiorna button, each row and the sheet's
  Importa button — **UI tests must not find controls by prose** (CLAUDE.md).
- Verify: `.claude/test-cmd` green.

### Task 8 — wiring: sidebar row, pane, shortcuts, menu, Impostazioni, and the 19 UI-test files (R-01, R-11, R-15)

- Budget: `Sources/App/Navigation.swift`, `Sources/App/SidebarItem.swift`,
  `Sources/App/RootView.swift`, `Sources/App/PergamenumApp.swift`, `Sources/App/CommandActions.swift`,
  `Sources/App/CommandActions+CanRun.swift`, `Sources/Core/Shortcuts/ShortcutCommand.swift`,
  `Sources/Features/Settings/SettingsView.swift`, `UITests/**` (19 files), `Tests/ShortcutTests.swift`
  (~350 lines)
- **Tester first** where a test exists to write: `ShortcutTests` gains assertions that both new
  bindings are free and that the catalogue has no duplicate keys (the existing
  `noTwoCommandsShipOnTheSameKeys` covers it — make sure it runs and passes, do not weaken it).
- `Navigation.Pane.recordings` + all three switches; `SidebarItem.Group.work` gains
  `.pane(.recordings)` **last** (ADR §D15); `RootView.detail` gains the case with the `needsVault`
  fallback the other panes use.
- `ShortcutCommand.paneRecordings` (Ctrl+Cmd+0) and `.refreshRecordings` (Cmd+R), **appended at the
  end of the enum**, `section` `.view` for both. `CommandActions.run` and `canRun` gain their cases;
  `refreshRecordings` is enabled **only** while `navigation.pane == .recordings` (blueprint).
- **Impostazioni (R-11):** a numeric field «Giorni registrazioni Plaud», default 14, in the
  **Generali** tab — it is a vault-scoped operational setting and Generali already holds the
  vault-identity rows; no new tab (blueprint). It writes through `RecordingsController`, **not**
  through `updateSettings` (ADR §D12) — add a comment saying so, or the next reader will look for a
  `VaultSettings` key that does not exist. Validate on entry: positive integer ≤ 3650.
- **All 19 UI-test files gain `-disablePlaud`, `YES`** beside `-disableCalendar`. Grep afterwards to
  confirm 19 hits, not 18.
- `PergamenumApp` builds and injects the controller into **both** environment chains (`:149-158`
  and `:232-240`).
- Verify: `tuist generate --no-open`, then `.claude/test-cmd` green. Launch the app by hand once and
  confirm the sidebar row appears last and Cmd+R is live only on that pane.

## Phase 4 — the schema reopening and the real service

### Task 9 — the frontmatter allowance, and the connectors proven unaffected (R-05, R-14, R-15)

- Budget: `Sources/Core/Conventions/Frontmatter.swift`, `Tests/ConventionsTests.swift`,
  `Tests/FrontmatterPrefixTests.swift` (~180 lines)
- **Tester first.** Red before the change.
- `FrontmatterRules.validate` stops emitting `.foreignKey` for a key matching
  `^pergamenum-[a-z0-9]+(-[a-z0-9]+)*$`. **Four lines.** The parser and the serializer are not
  touched; `Frontmatter.foreignKeys` still keeps every foreign key verbatim.
- **Update the file's own doc comment at `:5-9`**, which currently states flatly that an extra key
  is a non-conformity. A rule that changed with a comment that did not is the next reader's bug.
- Tests: `pergamenum-plaud-id` produces no finding; `pergamenum-anything-else` produces none;
  `Pergamenum-Plaud-Id` (wrong case) **does**; `pergamenum` alone (no hyphen) **does**;
  `obsidian-foo` **does**; a prefixed key still round-trips byte-for-byte through
  parse→serialize. **The Task 4 linter assertion turns green here** — confirm it, do not delete it.
- **R-15's deliberate half:** build both connector schemes and report the result —
  `xcodebuild -workspace Pergamenum.xcworkspace -scheme perg -destination 'platform=macOS' build`
  and the same for `pergamenum-mcp`. Then run `scripts/mcp-smoke.py` and `perg lint` against a
  throwaway vault containing one rendered transcript note, and confirm the JSON `LintFinding` shape
  is unchanged and the note is clean. **These are not in `.claude/test-cmd`; they only run because
  this task runs them.**
- Verify: `.claude/test-cmd` green, both connector builds green, smoke script green.

### Task 10 — end to end against the real service, the UI suite, and the documentation obligations (R-08, R-14, R-15)

- **HITL gate. Stefano runs this, or explicitly approves each step.** Everything before this task is
  read-only against the service; this task issues real `POST`s.
- No budget: this is verification and prose, not a diff of predictable size.
- **Documentation obligations (R-14 is `no-test:` and lands here):**
  - Relocate the ADR from `docs/architecture/` to `docs/adr/0032-…` and remove the filing note.
  - `CLAUDE.md` principle 2 gains its **second** named exception, written the way the first is: the
    loopback client, manual only, no data leaving the machine, scoped to the Registrazioni pane, and
    unknown to `perg`/`pergamenum-mcp`.
  - `CLAUDE.md` §Working agreements gains the `-disablePlaud YES` line beside `-disableCalendar` and
    `-disableUpdater`.
  - `CLAUDE.md` gains an ADR-0032 entry in the chain decision index and a decisions section, in the
    shape the other ten chains use.
  - `PROJECT_BRIEF.md` Status updated if a milestone moved.
- **Live end-to-end, in this order, each step confirmed before the next:**
  1. `GET /health`, `GET /recordings` through the app. List renders, statuses match `curl`.
  2. A `failed` recording shows a readable message and a working «Riprova» — **this is the common
     case, five of eight** (C8).
  3. `POST process` on one recording, poll to completion, review, **import with a deliberate mix of
     accepted and rejected tasks**. Read the written note by hand: frontmatter keys present, tags
     conformant, transcript under its heading, `>date` only where `due_hint` existed.
  4. **R-08 for real:** «Rielabora» the same recording with `force=1`, import again, and confirm the
     note is updated in place with no duplicated task. This is the one requirement no unit test can
     fully prove, because it depends on the service genuinely reissuing different task ids.
  5. Reject-then-reopen: confirm rejected tasks were never sent (the service still offers them).
  6. Delete a managed recording: note in the Trash, confirmation dialog shown, **no service call**.
  7. Quit and relaunch mid-review: the draft is restored (R-10).
- **`scripts/uitests.sh` with no argument**, once, before merge. Kill stale instances first; read the
  per-test timings — 60.2 s names the launch timeout, not a defect (CLAUDE.md).
- **HITL gates in this task:** every `POST`; the commit; the PR; the merge to `main`.

---

## Risks, dependencies and HITL gates

**Risks.**

- **The service is another repo's program and this side has no early warning of a contract change.**
  A renamed field surfaces as a decode error in front of the person, not in CI. The fixture suite
  only detects what somebody re-captures.
- **Five of eight recordings are `failed` right now.** The pane's first impression is a list of
  errors, and one of the three error strings is not a coded error at all. If the readable-error
  mapping is thin, R-07 is satisfied on paper and useless in practice.
- **ATS/local-network on macOS 26 is documented, not measured on this app.** Task 2 measures it and
  names the fallback; if a local-network prompt appears, the task **stops and reports** rather than
  guessing at plist keys.
- **The zone-less timestamp is the highest-value bug in the chain.** Read as local instead of UTC it
  is a two-hour error that becomes a whole-day error before 02:00, and it would look right in every
  afternoon test.
- **`POST /proposals/{id}/imported` is irreversible** — there is no un-import endpoint. A stray call
  during development permanently marks a real recording imported.
- **`POST /recordings/{id}/process?force=1` starts real transcription work** against a real device
  and costs real time and real model calls.
- **The frontmatter reopening widens by precedent.** Any future `pergamenum-*` key is now
  lint-clean without a decision. The compensation is that the prefix is greppable; the risk is that
  nobody greps.
- **19 UI-test files must all carry `-disablePlaud`.** A file that misses it will one day list
  somebody's real meetings inside a test run.
- **A twentieth pane shortcut has nowhere to go.** Ctrl+Cmd+0 exhausts the digits.

**Dependencies.**

- `plaud-service` v0.2 running as `it.stefer.plaud-service` (measured present and healthy).
- A Plaud device connected for anything beyond reading existing proposals (`/health` reports
  `"plaud":"connected"` today).
- Tuist 4 + Xcode 26 toolchain, as for every chain here.
- No new package. `Tuist/Package.swift` is **not** edited.

**HITL gates.**

- **Gate 2 (before Task 1):** approve the ADR's two reopenings — the network exception and the
  frontmatter schema — and the audit profile below. These are the two decisions that are expensive
  to reverse after notes have been written.
- **Every `POST` against the live service** (Task 10 only).
- **Commit, push, PR, merge to `main`** — all four, as always.
- **Any edit to `Resources/vocabolari.json`** would violate principle 5; if a task believes it needs
  one, that is a stop-and-report, not a gate.
- **No file under `/Users/stefer/Developer/Plaud` is written, ever.**

---

EXTERNAL DEPENDENCY: 3777 | port | provisioned: true
EXTERNAL DEPENDENCY: /Users/stefer/Library/LaunchAgents/it.stefer.plaud-service.plist | file | provisioned: true

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -derivedDataPath "/Users/stefer/Developer/Pergamenum/.build/DerivedData" -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield

CODER-MODEL CANDIDATE: opus
