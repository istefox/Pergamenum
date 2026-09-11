<!-- step5-brief: plan=/Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md tasks=9,10 lines=386-527 -->
# Step 5 Batch Brief -- 2026-09-09-pratiche.md -- tasks 9-10

## Task text (verbatim, plan lines 386-527)

### Task 9 — Settings tab and the two read-only connector reads (R-35, R-36; screen 1f)

- Budget: `Sources/Features/Settings/PraticheSettingsTab.swift`,
  `Sources/Features/Settings/SettingsView.swift` (one `tabItem`),
  `Sources/Connector/VaultPratiche.swift`, `Sources/Connector/VaultPayloads.swift` (additive),
  `Sources/CLI/**`, `Sources/MCPServer/**`, `scripts/mcp-smoke.py`,
  `Tests/PraticheConnectorTests.swift`, `Tests/PraticheSettingsTests.swift` (~700 lines)
- **Measure the toolbar collapse before believing it fits.** `SettingsView.swift:29-38` records
  that at 620 pt the toolbar collapsed two `tabItem`s into an unlabeled overflow popup once the
  count crossed eight, found by dumping the toolbar's accessibility tree. Repeat that dump with
  **eleven** tabs at 700×560. If it collapses, widen the window — never nest the tab, never add a
  `ScrollView`.
- Tester writes: `PraticheSettings`'s eight rows bound to `VaultSettings.pratiche`;
  `VaultAPI.pratiche(_:)` and `VaultAPI.pratica(_:_:)` signatures plus `PraticaSummary` and
  `PraticaTimelinePayload`.
- Tests (red): every setting round-trips through `.pergamenum/settings.json` and a hand-edited `0`
  is clamped, and own addresses pre-fill from the index and stay editable (R-35); `pratiche` returns
  path, title, client, status, counterparts, last activity, message count and tray count, `pratica`
  returns ordered timeline entries and resolves its argument through `VaultLookup`'s existing
  title/path rules, and **neither opens the Mail store** (R-36, and the Task 5 purity case covers
  the structural half).
- Coder: bodies; both front ends translate only — the capability lives in `Sources/Connector/`
  (CLAUDE.md «AI connector»). `scripts/mcp-smoke.py` gains one call per new tool. **Do not touch
  `VaultAPI.LintFinding`.**
- Screen: 1f.
- `tuist generate --no-open`; full unit suite; both connector builds; `scripts/mcp-smoke.py`.

### Task 10 — accessibility identifiers, the documentation obligations, regeneration and the end-to-end run (R-18, R-33, R-39, R-40, R-41)

- Budget: `UITests/PraticheUITests.swift`, `Sources/Features/Pratiche/**` (identifiers only),
  `docs/20260811_Pergamenum_SpecApp.md` (one row), `TODO.md`, `CLAUDE.md`, `PROJECT_BRIEF.md`
  (~500 lines)
- **Accessibility identifiers**: every identifier listed in UX-BLUEPRINT.md's checklist is applied
  and asserted — `pratiche-pane`, `-list`, `-row-<slug>`, `-new`, `-refresh`, `-filter`,
  `-sender-menu`, `-attachments-only`, `-inspector-toggle`, `-fda-banner`, `-fda-open-settings`,
  `-sync-progress`, `-sync-cancel`, `-tray`, `-tray-row-<conversationID>`, `-tray-add-<id>`,
  `-tray-ignore-<id>`, `-timeline`, `-message-<messageIDHash>`, `-message-chevron-<hash>`,
  `-message-subject-<hash>`, `-attachment-<hash>-<n>`, `-entry-<timestamp>`, `-add-note`,
  `-add-call`, `-insert-here-<index>`, `-wizard`, `-wizard-title`, `-wizard-client`,
  `-wizard-seed-mail`, `-wizard-seed-search`, `-wizard-seed-later`, `-wizard-proposal-<id>`,
  `-wizard-keywords`, `-wizard-create`, `-picker`, `-picker-row-<slug>`, `-delete-alert`, and
  `settings-pratiche-*` per row. **A UI test finds a control by identifier, never by the words on
  it** (CLAUDE.md, paid for twice). The new UI-test file carries `-mailStoreRoot <fixture>
  -disableCalendar YES -disableUpdater YES`; it asserts the banner, the lanes, expansion, the tray
  and the wizard against a **fixture** store (R-18, R-33, R-39).
- **Documentation obligations, each one a separate small commit:**
  - `docs/20260811_Pergamenum_SpecApp.md:500` — amend the «Rendering corpo email» row to
    ADR §D16's wording, and confirm by reading it back that CLAUDE.md principle 2 gains no new
    exception, because no network is used (R-40, `no-test:` documentation amendment — cited here
    exactly like any other id, per ADR-0138).
  - `TODO.md` — record the four deferred items as new `PG-` entries: ChatGPT inside Pergamenum,
    «Apri come board», the `pergamenum://pratica/add` URL-scheme entry point, and connector write
    access to pratiche (R-41, `no-test:` ledger entry).
  - `CLAUDE.md` — one «Decisions from the pratiche chain (ADR-0036)» section and one line in the
    chain decision index, matching the shape of the ten sections already there.
  - `PROJECT_BRIEF.md` — Status section.
- **`tuist generate --no-open`** one final time, then the whole gate: unit suite,
  `scripts/uitests.sh` **with no argument** (kill stale instances first; 60.2 s beside a failure
  names the launch timeout, not a defect), and both connector builds.
- **Manual acceptance on the Labs vault, with Stefano, against the real store** — the SPEC's
  Definition of Done, in order: create a pratica from a message selected in Mail; the conversation
  arrives in order with sent on the right; attachments land in `allegati/` and open with Space; the
  subject opens Mail; a reply sent from Mail appears within 30 s; a new conversation from the same
  counterpart lands in «Da smistare»; a phone-call entry appears in today's daily note; Obsidian
  opens the folder without a frontmatter complaint; `perg pratica <title>` prints the timeline;
  `pergamenum-mcp` lists it.
- **HITL gates in this task:** the first run against the real store; the commit; the PR; the merge.

---

## Risks, dependencies and HITL gates

**Risks.**

- **Reading Mail's store while Mail is writing.** The index ships a `-wal` and is open at all times.
  A file-level copy can be torn between the two `copyItem` calls, and a torn SQLite file does not
  report itself as torn on every query — it reports missing rows. `quick_check` plus one retry
  (ADR §D2) is the whole mitigation, and a sync that reports «Mail sta scrivendo» is the correct
  outcome, not a failure to hide.
- **`.partial.emlx` bodies pending.** 84,194 of the 128,877 files are partial. A first import of a
  long Exchange conversation can be mostly `pending` rows, which will read as "the feature does not
  work" unless the dimmed row and «Apri in Mail» are convincing. R-15 is a UI risk as much as a
  parsing one.
- **The `message://` encoding.** Two encodings exist in this repo today and neither is measured
  against Mail. The wrong one is a subject line that opens nothing, and it will look like a Mail
  problem. Task 2 measures it before anything depends on it.
- **Probing Full Disk Access without a prompt at launch.** macOS does not prompt for FDA, it denies
  silently — so the risk is not a dialog, it is a per-launch touch of somebody's mail store and a
  probe that mistakes "Mail not installed" for "not granted". The probe runs on triggers only, and
  distinguishes `EPERM` from `ENOENT` (R-18 vs «Nessun archivio di Mail trovato»).
- **Performance on 127,818 rows.** An unindexed `sender` or `conversation_id` scan per pratica per
  trigger is a full table scan on every window activation. The indexes created on our own copy
  (ADR §D2) are what make this milliseconds; if that step is skipped the feature will feel broken
  on this Mac specifically, because this Mac is the large case.
- **The same `Message-ID` in Sent and Archive.** All accounts are Exchange, so duplicates across
  mailboxes are the norm, not an edge case. Deduplication happens **before** the first write
  (ADR §D15); after it, the vault has two files and no way to tell which is canonical.
- **A private, undocumented Apple format.** A macOS update can change the schema or the `.emlx`
  layout, and the fixture suite will stay green while acquisition has stopped. There is no early
  warning available; the mitigation is that failures are reported per message rather than swallowed.
- **A copy of the Envelope Index in Application Support** — a few hundred megabytes of mail
  metadata outside `~/Library/Mail`. Regenerable and deletable, and still a widening of where that
  data sits.
- **`.dropDestination` against Mail's file promise is unproven** (R-22) and is a tracer bullet with
  a named fallback, not a commitment.
- **The eleventh Settings tab may collapse the toolbar.** Undocumented threshold, measured once at
  eight tabs / 620 pt. Widen the window; never nest.
- **Eleven panes exhaust the shortcut digits.** Ctrl+Cmd+P is the first pane key that is not a
  digit; the seam is documented in ADR §D8 and nowhere else.

**Dependencies.**

- Full Disk Access granted to the Pergamenum build being run (and never to the UI-test runner).
- Apple Mail installed with a populated `~/Library/Mail/V10/` — present on this Mac.
- Automation (AppleScript) consent for Mail, for the seed path only.
- Tuist 4 + Xcode 26 toolchain, as for every chain here. **No new package.**
  `Tuist/Package.swift` and `Project.swift` are **not** edited.

**HITL gates.**

- **Gate 2 (before Task 1):** approve the ADR — in particular §D5 (the timeline is not edited in
  place), §D8 (the pane-shortcut convention breaks), §D9 (`EmailHeaders.mailURL` changes output),
  §D11 (the SPEC's two tag sets are corrected) and §D16 (the SPEC §14 amendment) — plus the audit
  profile and the protected-interface proposals below.
- **The two probes in Task 1** and the `message://` measurement in Task 2: they read the real store
  and the real Mail. Stefano present, output limited to schema and paths.
- **The first sync against the real store** (Task 10).
- **Commit, push, PR, merge to `main`** — all four, as always.
- **Any edit to `Resources/vocabolari.json`, `Frontmatter.swift`, `Tag.swift`, `IndexCache.swift`,
  `Project.swift` or `Tuist/Package.swift`** is a stop-and-report, not a gate.
- **Nothing under `~/Library/Mail` is ever written.**

---

EXTERNAL DEPENDENCY: /Users/stefer/Library/Mail/V10/MailData/Envelope Index | file | provisioned: true
EXTERNAL DEPENDENCY: Full Disk Access for the Pergamenum build | tcc-consent | provisioned: unknown
EXTERNAL DEPENDENCY: Automation consent for Apple Mail (AppleScript) | tcc-consent | provisioned: unknown

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -derivedDataPath "/Users/stefer/Developer/Pergamenum/.build/DerivedData" -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield

CODER-MODEL CANDIDATE: opus

## File map (from Budget: declarations, tasks 9-10)

- (none declared -- no task in this range carries a parseable Budget:)

No parseable Budget: for task(s): 9 10 (absent is not zero -- consult the task text above)

## Excluded tasks (not in this batch)

- Task 1 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 2 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 3 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 4 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 5 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 6 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 7 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md
- Task 8 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md

Full plan: /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-09-pratiche.md

## Context documents (open only for the reason stated -- not read unconditionally)

- ADR: docs/adr/0036-pratiche.md -- D11/D12 (connectors read-only, VaultAPI.PraticaSummary protected interface, isolation test), D19 (settings values and clamps), D8 (all 19 UITests files carry -mailStoreRoot, done in batch 4), and every Follow-up section (identifier scheme pratiche-*, deferred R-22 tracer bullet, notInStore, tray model) bind Task 9's settings tab and connector reads and Task 10's UI tests, docs and end-to-end run
- SPEC: SPEC.md -- requirement IDs R-35, R-36 (Task 9) and R-18, R-33, R-39, R-40, R-41 (Task 10), plus screen 1f and the SPEC §14 row this chain amends
- CLAUDE.md: CLAUDE.md -- AI connector section (a capability goes in Sources/Connector/VaultAPI, both front ends translate; scripts/mcp-smoke.py after touching Sources/MCPServer), UI-test rules (identifiers only, -disableCalendar/-disableUpdater/-mailStoreRoot, scripts/uitests.sh with no argument, stale instances), Chain decision index and the ADR-0036 decisions block to update, PROJECT_BRIEF Status
