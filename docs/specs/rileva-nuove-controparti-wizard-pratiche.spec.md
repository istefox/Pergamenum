
# SPEC — Rilevazione di nuove controparti nella wizard «Nuova pratica»

**Topic slug:** rileva-nuove-controparti-wizard-pratiche

## Objectives

When Mail conversation threads grow, new people are routinely added mid-thread (typically via
Cc) and sometimes go on to write directly to the user without including any of the pratica's
original counterparts. Today the «Nuova pratica…» wizard's step 3 fetches proposals keyed only
on the counterpart address(es) the person explicitly named in step 2, so anyone who joined the
conversation later and is not one of those addresses is invisible: their messages are silently
absent from the pratica the moment it is created, with no signal that anything was missed.

This feature adds a detection pass, scoped to pratica **creation only**, that scans every
message across the conversation(s) chosen in step 3 and surfaces any email address that took
part in the exchange but is not yet one of the pratica's counterparts. The person reviews the
candidates and decides, address by address, whether each becomes an additional counterpart of
the pratica being created.

**Out of scope, tracked separately (`PG-111` in `TODO.md`):** detecting a newly-joined
participant in a pratica that is **already being followed**, during its regular sync. This
feature only ever runs once, during the creation wizard.

## Scope

In scope:
- A new step in the «Nuova pratica…» wizard, reached after step 3 (proposals/conversation
  selection) and before the pratica is actually created.
- Scanning every message of every conversation selected in step 3 for participant addresses
  (as sender or as a recipient) not already in `WizardState.counterparts`, excluding the
  person's own address(es) (`PraticheSettings.ownAddresses`).
- Presenting up to 10 candidate addresses, each individually acceptable or skippable, grouped
  and ranked as described under UI flows.
- Accepting a candidate makes it a real additional counterpart of the pratica: it joins
  `WizardState.counterparts` exactly as a counterpart typed by hand would, and therefore
  benefits from the wizard's existing counterpart-driven conversation search (same mechanism
  `NuovaPraticaWizard.loadProposals()` already runs for step 3) — bringing in any other
  conversation with that address, not only the one(s) already selected.

Out of scope:
- Detection for an already-followed pratica during ongoing sync (`PG-111`).
- Any UI to manage or revisit skipped candidates after the wizard has moved past this step —
  skipping is final for this wizard run; the address can always be added later by hand like any
  other counterpart, through the pratica's own existing settings/tray mechanisms.
- Filtering by anything other than participation in the message exchange itself (no heuristic
  for "looks like a mailing list", no domain allow/deny list).

## Stack / architecture

No new dependency. Swift 6 / SwiftUI, unchanged from the rest of Pratiche (ADR-0036): the
detection itself is pure, synchronous, `Sendable`-safe logic over data already read from the
Mail store copy (`MailStoreReader`/`MailMessageRow`) — no new I/O, no new network, no new file
format.

## Architecture (high level)

- The detection is a new pure function alongside the existing tray/proposal reduction logic in
  `Sources/Core/Pratiche/` (its natural neighbor is `PraticaTrayModel.proposals(from:
  ownAddresses:)`, which already does the analogous "reduce raw messages to something the UI
  shows" work for a single counterpart per conversation — this feature needs the same kind of
  reduction but keyed on **participant address**, across **all** messages of the selected
  conversations, not on the newest message's sender/recipient alone).
- Input: the full `[MailMessageRow]` for every conversation ticked in step 3 (already fetched by
  `MailSeedLoader`/`MembershipRule` during that step — no second Mail-store read), the addresses
  already in `WizardState.counterparts`, and `PraticheSettings.ownAddresses`.
- Output: a ranked, capped list of candidate addresses, each carrying at least: the address,
  whether it ever appeared as a message sender ("ha scritto") or only ever as a Cc/To recipient
  alongside a known counterpart or another sender candidate ("solo in copia, mai scritto"), and
  a message count for ranking/display.
- `WizardState` gains a new `Step` case for this screen, positioned after `.proposals` and
  before what `canCreate`/`Crea` currently gates on — `.proposals` no longer being the last step.
  The new step's own gate: reachable regardless of how many candidates were found or accepted
  (finding zero candidates is not an error, exactly as an empty proposal selection today is not
  an error).
- Accepting a candidate is modeled as appending its address to `WizardState.counterparts` (the
  same field step 2's chips already populate) and re-running the wizard's existing
  counterpart-driven conversation search (`NuovaPraticaWizard.loadProposals()`'s existing
  mechanism), so newly accepted counterparts pull in whatever else in Mail already involves them
  through the same code path a manually-typed counterpart already uses — no new search logic.
- Connector boundary unaffected: everything above lives in `Sources/Core/Pratiche/` and
  `Sources/Features/Pratiche/`, reading types (`MailMessageRow`) already compiled into `perg`/
  `pergamenum-mcp` today; no new type or file needs to cross into `Sources/Connector`, and
  nothing here calls into Mail-store-only code from a connector-visible file
  (`SharedSourcesPurityTests` stays green).

## Data model

No persisted schema changes. `Dossier.counterparts` (already `[String]`) is the eventual home of
every accepted address — nothing new to store on disk. The only new in-memory shape is the
candidate list itself, scoped to the wizard's own session state (`WizardState` or a sibling
transient type), never written to disk, discarded once the wizard closes.

Each candidate carries, at minimum:
- the email address (lowercase, matching the convention every other address in this feature
  area already follows)
- whether it was ever a message sender in the scanned conversations ("wrote") or only ever
  appeared as a recipient ("Cc-only")
- a message count, used for ranking and shown to the person so they can judge relevance

## UI flows

1. Step 3 (proposals) is unchanged in its own right: the person still ticks which
   conversation(s) become part of the pratica.
2. On leaving step 3 forward («Continua»/whatever the existing control is), the detection pass
   runs once over the union of every message in every ticked conversation.
3. If candidates are found, a new wizard step is shown before the final «Crea»: a list, one row
   per candidate, each with an individual checkbox/accept-skip control (defaulting to unchecked
   — nothing is added unless the person explicitly opts in). Rows are grouped and ordered:
   - First group: addresses that wrote at least one message, ordered by message count
     (descending).
   - Second group: addresses that only ever appeared as a Cc/To recipient, never as a sender,
     ordered by message count (descending).
   - The two groups' combined length is capped at 10; anything beyond the 10th is summarized as
     "e altri N indirizzi ignorati" with no further detail, never silently dropped without a
     trace.
   - Each row is visually labeled with which group it belongs to (e.g. "ha scritto 4 messaggi"
     vs. "solo in copia, mai scritto direttamente").
4. If no candidates are found, this step is skipped entirely — the wizard proceeds straight from
   step 3 to the existing final step/«Crea» exactly as it does today, with zero behavior change
   for a conversation with no new participants.
5. Confirming this step (however many boxes were checked, including zero) appends every checked
   address to `WizardState.counterparts`, triggers the existing counterpart-driven proposal
   search for the newly added addresses, folds any newly found conversations into the
   already-ticked selection (pre-selected, consistent with how step 3 already pre-selects
   conversations found from an accepted seed), and only then proceeds to «Crea».
6. All new UI text is in Italian, consistent with the rest of the app.

## Edge cases

- **Zero candidates.** The new step does not appear; no change to the existing flow.
- **More than 10 candidates.** Only the top 10 (by the ranking above) are shown individually;
  the rest are named only by count, never silently absorbed into the top 10 or dropped without
  any trace.
- **An address already in `WizardState.counterparts`.** Never listed as a candidate — the whole
  point is "not yet a counterpart".
- **The person's own address(es) (`PraticheSettings.ownAddresses`).** Never listed as a
  candidate, exactly as they are already excluded from counterpart detection elsewhere in
  Pratiche (today's counterpart-address fix).
- **An address that is both a sender in one message and Cc-only in another.** Counts as "wrote"
  (first group), since it did write at least once; its message count is the total across both
  roles.
- **Multiple conversations selected in step 3.** The same address appearing across more than one
  selected conversation is one single candidate row (deduplicated), with its message count
  summed across all of them.
- **Case and whitespace.** Addresses are compared lower-cased and trimmed, matching the
  convention every other address comparison in this feature area already follows
  (`PraticaTrayModel`, `MessageDocument`, `WizardState.makeDossier()`).
- **Accepting a candidate whose broader search (re-run of `loadProposals()`) finds nothing new.**
  Not an error — the address still becomes a counterpart of the pratica; the timeline for the
  already-scanned conversation(s) already includes their messages regardless of what the broader
  search returns.
- **The connectors (`perg`, `pergamenum-mcp`).** No behavior change: this feature is exclusively
  reachable through the app's wizard UI; both connector builds must stay green after the change
  (existing `SharedSourcesPurityTests` boundary, `Sources/Core/**` touched only with types
  already shared).

## Success criteria

- [ ] R-01 — After ticking one or more conversations in step 3 and advancing, if any message in
      those conversations was sent by an address not already in the pratica's counterparts (and
      not the person's own address), a new wizard step appears listing it as a candidate before
      «Crea» is reachable.
- [ ] R-02 — If no such address exists, the new step does not appear and the wizard behaves
      exactly as it does today (step 3 leads straight to the existing final step).
- [ ] R-03 — Each candidate is shown with an individual, independently toggle-able
      accept/skip control, defaulting to not-selected.
- [ ] R-04 — Candidates that sent at least one message are grouped and ranked above candidates
      that only ever appeared as a Cc/To recipient; within each group, ranking is by message
      count, descending.
- [ ] R-05 — At most 10 individual candidates are shown; if more exist, the excess is
      summarized by count only ("e altri N indirizzi ignorati"), never silently omitted without
      any indication and never silently folded into the top 10.
- [ ] R-06 — An address already present in the pratica's counterparts, or matching one of
      `PraticheSettings.ownAddresses`, is never offered as a candidate.
- [ ] R-07 — The same address appearing in more than one of the selected conversations is
      offered exactly once, with its message count summed across all of them.
- [ ] R-08 — Checking a candidate and confirming the step adds its address to the pratica's
      counterparts and re-runs the existing counterpart-driven conversation search for it,
      exactly as a manually-typed counterpart in step 2 would, folding any newly found
      conversations into the pratica's proposal selection before creation.
- [ ] R-09 — Leaving every candidate unchecked and confirming the step creates the pratica
      exactly as if the step had not existed (no counterpart added, no behavior change).
- [ ] R-10 — Address comparisons throughout this feature (against existing counterparts, against
      own addresses, for deduplication) are case-insensitive and whitespace-trimmed.
- [ ] R-11 — `Sources/Core/**` files touched by this feature keep the `perg` and
      `pergamenum-mcp` connector targets building successfully, and
      `SharedSourcesPurityTests` (or its equivalent boundary check) stays green
      (no-test: this is a build/CI verification step run at Step 5/6, not a runtime-testable
      user-facing behavior).
- [ ] R-12 — UI strings introduced by this feature are in Italian, consistent with the rest of
      the app (no-test: a copy/localization convention, verified by review rather than by an
      automated assertion).
