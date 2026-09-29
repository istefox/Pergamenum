Status: Approved (2026-09-28)

# SPEC — Search and query correctness (Audit Fable chain 7, PG-260 / #574)

## Destination

One PR that closes #574: the five confirmed defects of ROADMAP §Chain 7 fixed, each pinned by a
test, the chain 7 items ticked in the roadmap. No ADR.

## Objectives

Global search and the «Viste» pane give the answer the query asks for, and stay responsive while
they compute it. Today `tag:client-acme` also returns `client-acme-industriale`, a phrase ending in a
colon swallows the rest of the query, the search spinner disappears while a search is still pending
and the window freezes during a search or a views scan, and a project parent living on a board shows
no sub-tasks.

## Scope and non-goals

In: the five items of ROADMAP §Chain 7, plus the search legend line that makes the new tag rule
discoverable.

Out: moving `VaultSession` reads off the main actor (ADR-0041 isolation stays), the §D7 watcher for
the «Viste» pane, a text index for search, changes to the connectors' search behaviour beyond the
tag rule they share.

## Decisions

- **One SPEC, one PR, no ADR** — the five items are independent, small, and touch no on-disk format,
  schema or protected interface. Rejected: one PR per item — five review cycles for a size-S chain.
- **Search `tag:` uses the views' rule** — exact when the term has no wildcard, glob when it has one
  (`tag:client-*`), through the one shared predicate the views already use, and one test ties the two
  matchers together so they cannot drift again. Negated `-tag:` follows the same rule. Search keeps
  matching task tags as well as frontmatter tags: only the comparison changes. Rejected: exact match
  only, no glob — loses the family search the prefix rule accidentally gave, with no way back;
  keeping the prefix rule — it is the defect.
- **Quote state is tracked explicitly** — an operator quote opens only when no quote is open; a quote
  closes whichever quote is open. Rejected: special-casing a trailing colon inside a phrase — patches
  the one symptom and keeps the ambiguous state.
- **Search and the views scan stay on the main actor, cooperative** — both work in chunks, yield the
  run loop between chunks and check cancellation, so the spinner draws, typing is accepted during a
  search, and a superseded search stops early. Rejected: moving the read to a background actor —
  reopens ADR-0041's decision that `VaultSession` reads stay main-actor bound, for a vault size that
  does not need it.
- **Two doors, one loop** — the synchronous search stays for `perg`, `pergamenum-mcp` and the tests;
  the app gets a cooperative async variant built on the same per-candidate loop, so the two cannot
  return different results. Rejected: making the one door async — changes the connectors' signature
  for nothing they gain.
- **Search spinner and validation ordered by generation** — invalid `regex:` patterns and the spinner
  belong to the query being searched, set after the debounce, and a superseded search never clears the
  spinner of the one that replaced it. Rejected: keeping the pre-debounce validation — flashes an
  error for a pattern the user is still typing.
- **Sub-tasks of a board-hosted parent come from that board** — a parent task whose source is a board
  reads its children from the same board's task records, scoped by source path exactly as a note parent
  reads them from its note. Rejected: a vault-wide lookup by local id — local ids are unique per file,
  not per vault.
- **The legend shows `tag:client-*`** — without it the change from prefix to exact is invisible.
  Rejected: unchanged legend.
- **One GUI test for the search spinner** (user choice). Justified here since the chain has no ADR:
  whether the spinner is actually drawn while a search runs, and typing is accepted meanwhile, is
  exactly what the in-process harness cannot observe (no run loop pressure, no real drawing).
  Rejected: unit-only with the spinner's visibility as no-test.

## Constraints

- **`VaultSession` reads stay main-actor bound** — origin: ADR-0041.
- **The connectors' search signature and JSON do not change** — origin: ADR-0007, user decision in
  this interview.
- **Tag schema** (flat namespaced strings) is untouched — origin: SPEC §4.4.
- **GUI tests: at most two or three per feature, run through `scripts/uitests.sh`, not a merge gate** —
  origin: `CLAUDE.md` merge-gate rule.
- **A UI test finds controls by `accessibilityIdentifier`, passes `-disableCalendar`,
  `-disableUpdater` and `-mailStoreRoot`** — origin: `CLAUDE.md`.

## Stack

Swift 6, SwiftUI, Swift Testing, XCUITest for the one GUI test.

## Data model

No change. `IndexCache.schemaVersion` stays 5.

## API / interfaces

- Search gains an async cooperative variant beside the synchronous one; both share the matching loop.
- The views scan becomes async and cooperative.
- The sub-task lookup accepts a board-hosted parent.
- The search progress indicator and results list gain accessibility identifiers for the GUI test.

## UI flows

Global search (Cmd+Shift+F): the spinner appears once the debounce has elapsed and stays until the
current query's results are in; typing during a search is accepted and restarts the search. The
«Viste» pane shows its progress indicator while a scan runs.

## Edge cases

- `tag:` with a wildcard (`*`, `?`) matches as a glob; without one, exactly, case-folded as today.
- `-tag:status-a` excludes only notes tagged exactly `status-a`.
- `"nota:" progetto forno` is one phrase plus two words.
- `path:"01 Progetti"` still works (operator quote).
- An unbalanced quote at the end of the query behaves as today.
- A search cancelled mid-loop publishes nothing and leaves the newer search's spinner alone.
- A views scan cancelled by a new scan generation or a day change publishes nothing stale.
- A board parent with no children, or whose board is not indexed, returns no sub-tasks.

## Test seams

Unit (`PergamenumTests`, the merge gate): `SearchQuery` tokenising and `Matcher` tag rule; one test
feeding the same tag/term pairs to the search matcher and the views predicate; `IndexSnapshot`
sub-tasks and project progress for a board parent; the async search variant (same results as the
synchronous one, stops on cancellation); the cooperative views scan (same entries as before, stops on
cancellation); the search state's ordering (validation and spinner after the debounce, a superseded
generation never clears the current spinner), through a small state type extracted from the view.
GUI: one test in a new class on a generated vault large enough for a search to take visible time.

## Success criteria

- [ ] R-01 — `tag:client-acme` matches a note tagged `client-acme` and not one tagged only `client-acme-industriale`.
- [ ] R-02 — `-tag:status-a` excludes only notes tagged exactly `status-a`; notes tagged `status-attivo` stay.
- [ ] R-03 — `tag:client-*` matches every `client-` tag; `?` matches one character.
- [ ] R-04 — for a shared table of tag/term pairs, the search matcher and the views' tag predicate give the same answer.
- [ ] R-05 — search tag matching still covers task tags as well as frontmatter tags.
- [ ] R-06 — `"nota:" progetto forno` tokenises as the phrase `nota:` plus the words `progetto` and `forno`.
- [ ] R-07 — `path:"01 Progetti"` still parses as one operator value.
- [ ] R-08 — invalid `regex:` patterns and the spinner are set only after the debounce, for the query being searched.
- [ ] R-09 — a superseded search never clears the spinner or overwrites the results of the search that replaced it.
- [ ] R-10 — the async search variant returns exactly the synchronous search's results for the same query and limit.
- [ ] R-11 — the async search variant yields between chunks and stops, publishing nothing, when cancelled.
- [ ] R-12 — `perg` and `pergamenum-mcp` build and their search output is unchanged apart from the tag rule.
- [ ] R-13 — the views scan is cooperative: same entries as before, yields between chunks, publishes nothing when cancelled.
- [ ] R-14 — the «Viste» progress indicator is shown while a scan runs (no-test: visible drawing of the indicator is not observable in-process; R-13 pins the yield that makes it drawable).
- [ ] R-15 — a project parent task living on a board lists its sub-tasks from that board, and its project progress counts them.
- [ ] R-16 — the search legend shows a `tag:client-*` example.
- [ ] R-17 — GUI: on a large generated vault, the search progress indicator appears while a search runs, and text typed during the search reaches the field before results arrive.
- [ ] R-18 — ROADMAP §Chain 7 items 1-5 are marked done and the PR closes #574 (no-test: a process obligation on the roadmap file and the PR body).

## Not yet specified

_none_

## Out of scope

- Moving reads off the main actor: ADR-0041 decided it; the cooperative loop gives responsiveness without reopening it.
- The «Viste» §D7 watcher: a larger feature, not a correctness fix.
- Chunk size tuning beyond a sensible constant: no measured need.
