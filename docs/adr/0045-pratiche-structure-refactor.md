# ADR-0045: The pratiche layer splits by file, and names which `private` widens

- Status: accepted (see the plan at `docs/plans/pg-143-pratiche-structure-refactor.md`)
- Date: 2026-09-15. Written on the working tree at `75d4db5` (`main`, clean, no open PRs, no
  unmerged pratiche branch). Every line count, every violation and every access modifier quoted
  below was read out of the tree or produced by running `swiftlint 0.65.1` against
  `.swiftlint.yml` on that commit — none is recalled from the issue text, which is already stale
  (it says `PraticheController.swift` is 1575 lines; it is 1649).
- **Numbering note:** `0044` is the highest under `docs/adr/` and no `0045` exists in any commit
  reachable from `--all`. Checked, not assumed.
- **Reopens nothing.** No SPEC §14 decision, no on-disk format, no frontmatter key, no tag
  grammar, no user-visible behaviour, no protected-interface signature. No test is added to make
  a red one green, none is skipped, none is removed.
- **Adds no exception to CLAUDE.md principle 2.** Nothing here gains a network path.
- Depends on, and amends none of: **ADR-0036** (Pratiche — §D5 one editor, §D6 the two rewrite
  exceptions, §D14 sync is one actor, §D19 the connectors cannot open the Mail store, §D21 the
  regeneration plan is opaque), **ADR-0040** (§D6's amendments and `AttachmentIntegrity`),
  **ADR-0042** (inline-image placeholders), **ADR-0001 §D1** (`Sources/Core` imports no
  SwiftUI/AppKit), **ADR-0007** (shared sources), **ADR-0032** (`ImportNaming.recordingNoteTitle`
  is a protected interface).

---

## Context

`PG-143` (GitHub issue #243) asks for a pure structural refactor of the pratiche layer. Nothing
about what the feature does changes. The reason an ADR exists at all is that the mechanics of
splitting Swift types across files force four decisions that a future reader could not recover
from the diff, and one of them would silently undo a decision ADR-0036 already took.

### What was measured, at the line, before deciding

`swiftlint 0.65.1` against this repo's own `.swiftlint.yml`, deduplicated, on `75d4db5`. Only the
**error**-level findings are obligations; the warnings are listed because the same moves reach
them for free.

| File | Violation | Level |
|---|---|---|
| `Sources/Features/Pratiche/PraticheController.swift` | file 1649 lines (limit 1000) | **error** |
| `Sources/Features/Pratiche/PraticheController.swift:1193` `runExclusive` | body 119 (limit 100), complexity 21 (limit 10) | **error** |
| `Sources/Features/Pratiche/PraticaSyncEngine.swift` | file 1144 lines | **error** |
| `Sources/Features/Pratiche/PraticaSyncEngine.swift:20` | actor body 695 (limit 350) | **error** |
| `Sources/Features/Pratiche/PraticaSyncEngine.swift:481` `prepare` | body 169 (limit 100) | **error** |
| `Sources/Features/Pratiche/PraticaCommandActions.swift:21` | struct body 498 | **error** |
| `Sources/Features/Pratiche/NuovaPraticaWizard.swift:16` | struct body 390 | **error** |
| `Tests/PraticaSyncTests.swift` | file 2250, struct body 1665 | **error** (out of scope, §D8) |
| `PraticheController.swift:21` / `:1025` | class bodies 325 / 343 (limit 250) | warning |
| `PraticheController.swift:1468` `prepare` | body 53, complexity 14 | warning |
| `PraticaCommandActions.swift` / `NuovaPraticaWizard.swift` / `MessageDocument.swift` | files 823 / 486 / 526 | warning |
| `PratichePane.swift:14` / `MessageDocument.swift:10` | struct bodies 293 / 327 | warning |
| `MailStoreReader.swift` / `RecordingsController.swift` | files 412 / 624 | warning |

Two facts about the tool that shape every decision below, both confirmed against the real output
rather than read from documentation:

1. **`type_body_length` counts only the type's own declaration, never its extensions.**
   `PraticheController.swift` reports two type-body violations (`:21` and `:1025`, the two class
   declarations) and reports nothing for the two `extension PraticheController` blocks at `:635`
   and `:945`, which together run 335 lines. So moving members into an extension satisfies
   `type_body_length` even in the same file — but `file_length` counts every line including
   comments, so only an extension **in a separate file** satisfies both.
2. **`type_body_length` and `function_body_length` exclude comments and whitespace; `file_length`
   does not.** This codebase is heavily doc-commented, so the two never agree: `PraticheController`
   spans 576 raw lines and counts as 325.

### The constraint that makes this more than a text move

Swift's `private` is scoped to the enclosing declaration **and its extensions in the same file**.
Moving a member into an extension in another file therefore breaks every `private` it touches.
Three clusters in the pratiche layer are affected, and they are not equivalent:

- `PraticaSyncEngine`'s stored properties (`vaultRoot`, `boundary`, `write`, `cancelled`, `reader`,
  `progressChannel`, `mailStoreURL`) and its `private` nested `ExistingMessage`/`FolderContext`:
  ordinary encapsulation, no recorded invariant.
- `PraticaSyncEngine`'s `fileprivate` `PreparedMessage`/`PreparedAttachment` and
  `RegenerationPlan.prepared`: ADR-0036 §D21 made the opacity load-bearing in its own words —
  «Opaque on purpose: the only way to obtain one is `regenerationPreview`, and the only thing that
  can be done with one is `commitRegeneration` — so the bytes shown and the bytes written cannot
  diverge.» The `fileprivate` *is* that guarantee. Widening it to `internal` for a line count
  would repeal an ADR decision in a commit titled `refactor:`.
- `NuovaPraticaWizard`/`PratichePane`'s `@State`/`@Environment`: a SwiftUI `View`'s stored property
  cannot move to an extension at all, so splitting a `View` across files always widens.

The repository has already faced the third case and decided it. `Sources/Features/.../NoteListPane.swift:23-30`
widens nine `@State` properties and says so inline: «Not `private`, on this property and every
other `@State` down to `deletingFolder` below: `NoteListPane+FolderVerbs.swift` is an extension of
this same struct in a separate file, and reads and writes all of them…». Forty `Type+Aspect.swift`
files exist under `Sources/`. The convention is settled; what is not recorded anywhere is **where
it stops**.

### The two verbatim duplicates, read side by side

- `PraticaNaming.truncated(_:toFit:)` (`Sources/Core/Pratiche/PraticaNaming.swift:64-77`) and
  `ImportNaming.truncatedAtWordBoundary(_:toFit:)` (`Sources/Core/Conventions/ImportNaming.swift:162-175`)
  are the same twelve statements with two identifiers renamed. Both are `private static`. The first
  feeds `PraticaNaming.messageFileName`, the second feeds `ImportNaming.recordingNoteTitle` — and
  **both of those are protected interfaces** (`.claude/protected-interfaces`), because re-import
  matches a file already on disk by the name each derives.
- `MessageDocument.splitTopLevel(_:)` (`:293-322`) and `MessageDocument.splitOutsideQuotes(_:on:)`
  (`:361-387`) are one quote-and-escape-aware splitter written twice, the first with `,` hardcoded.
  Both `private static`, same file, identical escape handling.

The publish-and-open-the-Envelope-Index block has **four** copies, not the two the issue names:
`PraticheController.swift:1377` and `:1473`, `MailSeedPicker.swift:150`, `PraticheSettingsTab.swift:187`.
Three of the four carry the same two Italian sentences verbatim.

---

## Decision

### §D1 — The obligation is the error threshold; the warnings are taken where the same move reaches them

`.swiftlint.yml`'s own header says the size rules are kept on deliberately, «they are the ones
pointing at actual structural debt», and its `file_length` comment records seven types as debt
«recorded rather than configured away». So raising a threshold is not on the table. But the
obligation this chain accepts is the **error** line: 1000 lines per file, 350 per type body, 100
per function body. A file that lands at 560 lines clears every error and keeps one warning, and
that is a finished task, not a half-done one. §D4 depends on this being said out loud.

### §D2 — A type splits into `Type+Aspect.swift` extensions of itself, with exactly two new types

Pure move, signatures untouched, which is the issue's own constraint and the reason forty such
files already exist here. Two exceptions, both because the finding names a genuine second
responsibility rather than a length problem:

- **`PraticaFileOperations`** (`Sources/Features/Pratiche/PraticaFileOperations.swift`) —
  `PraticaCommandActions`' filesystem half (trash, restore, move, copy, attachment renaming,
  `TrashedFile`/`MovedFile`/`ContentRewrites`/`AttachmentRename`). It needs exactly two things from
  its host, `vault.root` and `pratiche.report(_:)`, both already `internal let`s, so it takes them
  as two stored properties and nothing widens. The four nested types are used nowhere else in
  `Sources/`, `Tests/` or `UITests/` — checked, not assumed.
- **`MailStorePreparation`** (`Sources/Features/Pratiche/MailStorePreparation.swift`) — §D6.

Everything else is an extension. In particular `PraticaLiveSync` and `SyncRunQueue` leave
`PraticheController.swift` as they are: `PraticaLiveSync` reads only `internal` members of
`PraticheController` (`ledger`, `report`, `beginSync`, `endSync`, `updateProgress`,
`recordSyncOutcome`, `remapLedgerConversations`, `updateTray`, `regeneration`, and the
`static` `dossier`/`stateDirectory`/`eligibility`), so that move widens nothing at all.

### §D3 — `private` widens to `internal` only where the split requires it, and every widening carries the comment naming the file that reads it

`NoteListPane.swift:23-30`'s convention, made general. The comment is the point: a bare `var` where
a `private var` used to be is indistinguishable from carelessness, and the next person to read it
has no way to learn that a named sibling file depends on it. Three rules:

1. Widen the member, never the type, unless the type itself crosses the boundary.
2. One comment per widened member — or one comment covering a contiguous run, as `NoteListPane`
   does — naming the extension file that reads it and why that file exists.
3. A member whose callers all move with it does not widen. `PraticheController.markOpened` and
   `persistTrayCount` are `private` and stay `private`, because `select` and `updateTray` move into
   the same extension file.

Two consequences accepted knowingly. An `internal` member is visible to the whole app module, and
`@testable import` raises `internal` — so widening also exposes these to `PergamenumTests`. Neither
is a reason to stop: actor isolation still guards `PraticaSyncEngine`'s state (nothing outside can
touch it without `await`), and a test that reaches for `PraticaSyncEngine.cancelled` would be
caught in review the same way any other test reaching into internals is.

### §D4 — `PreparedMessage`, `PreparedAttachment` and `RegenerationPlan.prepared` keep `fileprivate`, and `PraticaSyncEngine+Messages.swift` stays one file over the warning line

They move together, into one file, and the `fileprivate` is unchanged. That file lands around 560
lines: past the 400-line warning, comfortably inside the 1000-line error, which §D1 is what makes
acceptable.

This is the decision most likely to be «fixed» by somebody later, so it is stated as a refusal: the
opacity of the regeneration plan is ADR-0036 §D21's guarantee that the bytes shown in the diff are
the bytes written, and it is implemented by nothing except that keyword. A future split of
`PraticaSyncEngine+Messages.swift` must either keep the cluster whole or supersede §D21 — not widen
the modifier and leave the ADR standing.

`ExistingMessage` and `FolderContext` are the opposite case and do widen to `internal`: they are
descriptions of what is already in the folder, they carry no invariant any ADR records, and keeping
them `fileprivate` would force a 706-line file for no guarantee at all.

### §D5 — One word-boundary truncator, held by `ImportNaming`, pinned by the two protected names' existing tests

`ImportNaming.truncatedAtWordBoundary(_:toFit:)` drops `private`. `PraticaNaming.truncated(_:toFit:)`
is deleted and its one call site calls the survivor. No new file, no new type: `PraticaNaming`'s own
header already records that it «Reuses `ImportNaming.kebabCase`/`canonicalCounterparty`/`uniqueFileName`»,
so this is the fourth member of a relationship that exists, not a new dependency. Exposing an
existing member is also not what that header's «adds nothing to `ImportNaming` itself» forbade,
which was new API for pratiche's benefit.

The coupling is real and is the reason this clause exists: one helper now feeds two protected
file-naming paths, so an edit meant for recording-note titles would silently rename every future
message file. What makes it safe is that the pins already exist and were read before deciding —
`Tests/PraticaNamingTests.swift` asserts `messageFileName` byte-for-byte and asserts the 40-character
slug budget, `Tests/ConventionsTests.swift:464-545` asserts `recordingNoteTitle` across five cases
including the long-token and short-token boundaries. An edit to the shared helper turns both suites
red. The helper carries a doc comment naming both protected callers, so the coupling is visible at
the place somebody would edit it and not only in this ADR.

The same reasoning, one notch smaller, applies to `MessageDocument`: `splitTopLevel(_:)` is deleted
and its call sites call `splitOutsideQuotes(_:on: ",")`. The two implementations' escape handling was
compared statement by statement before deciding; they are equivalent.

### §D6 — The Envelope-Index publish-and-open block gets one home, and all four call sites use it

`MailStorePreparation` (`Sources/Features/Pratiche/`) holds the `Prepared`/`Preparation` pair,
`PraticaLiveSync.prepare`'s whole `nonisolated static` body, and one `reader(mailRoot:stateDirectory:)`
that publishes a generation, appends `Envelope Index` and opens a `MailStoreReader` — returning the
three Italian sentences the four copies already say. `PraticheController.swift:1377`, `:1473`,
`MailSeedPicker.swift:150` and `PraticheSettingsTab.swift:187` all route through it.
`PraticheSettingsTab`'s copy currently swallows both failure cases into `[]`; it keeps doing exactly
that at its own call site, because changing what Settings shows would be a behaviour change and this
chain has none.

`Sources/Features/`, not `Sources/Core/`: this is app-side orchestration over `MailStoreCopy` and
`MailStoreReader`, and ADR-0036 §D19 is explicit that the connectors are structurally unable to open
the Mail store. Putting it under `Sources/Core/**` would compile it into `perg` and `pergamenum-mcp`,
which is not forbidden by itself — `MailStore*.swift` already compiles there — but it would move a
publishing orchestrator one step closer to two binaries that must never call it, for no gain.

### §D7 — Nothing this refactor puts under `Sources/Core` imports SwiftUI or AppKit, and the guard already exists

`sharedSources` globs `Sources/Core/**`, so a file added there is compiled into both connectors
without anybody editing `Project.swift`. The only `Sources/Core` edits in this chain are to existing
pure-Foundation files (`PraticaNaming.swift`, `ImportNaming.swift`, `MessageDocument.swift`,
`MailStoreReader.swift`), and `Tests/SharedSourcesPurityTests.noCoreOrConnectorFileImportsAppKitOrSwiftUI`
already fails any regression. No new assertion is needed; the plan only requires that this test is in
the suite that runs at every gate, which it is.

`PraticaCommandActions.praticaNotePath(of:)` moving to `PraticaNaming` (finding `-697`) is therefore
also a move into shared-source territory. It is pure string manipulation, it is where the connector's
own duplicate spelling of `pratica.md` (`VaultPratiche.praticaFileName`) can eventually collapse, and
`PraticaNaming` is already the file that answers «what is this pratica's file called». Adding a
function to a file that holds a protected entry does not change that entry's signature.

### §D8 — `Tests/PraticaSyncTests.swift` is out of scope, and that is recorded rather than left silent

It is an error-level violation of the same two rules (file 2250, struct body 1665) in the same
feature, and `.swiftlint.yml`'s `included:` covers `Tests`. It is excluded here because splitting a
1665-line Swift Testing suite is a different kind of risk from moving production types — suite names,
`@Suite` grouping and fixture sharing all move with it — and because this chain's acceptance criterion
is «`PraticaSyncTests` green before and after each step», which reads badly if the same chain is also
rewriting it. The plan's risk section carries a concrete recommendation to file it as its own `PG-`
entry. Silence here would have read as «nobody noticed», which is worse than «deferred, and here is
why».

---

## Alternatives considered

**Extract collaborator types everywhere instead of extensions** — a `PraticaMessageDecoder`, a
`PraticaFolderScanner`, a `PraticaWriter`, each owning its own state and taking what it needs as
parameters. This would preserve every `private` and would arguably be the better end state.
Rejected for this chain, not forever: it is not a pure move. Every extracted type changes the shape
of its call sites, and the issue's own constraint is «pure moves first (types/functions into new
files), signatures untouched where possible». A refactor that both relocates and re-plumbs cannot be
verified by «the suite was green before and is green after» — a behaviour change would hide inside
the re-plumbing. §D2 takes it in the two places a finding names a real second responsibility and
nowhere else. If §D3's widening ever proves to cost something, this is the follow-up.

**Keep both word-boundary truncators and document the duplication in each** — defensible on its own
terms: two protected interfaces matched against files already on disk arguably should not share a
mutable dependency, and the comment would make the duplication deliberate rather than accidental.
Rejected because the premise turned out to be false when checked: both protected names already carry
exact-string regression tests (`PraticaNamingTests`, `ConventionsTests:464-545`), so the shared helper
is pinned from both sides and an edit cannot pass silently. A documented duplicate would also have to
be kept in sync by hand forever, and the reason this finding exists is that a structure scan found the
drift-in-waiting; leaving it would guarantee the same finding is raised again.

**Raise the SwiftLint thresholds, or add `// swiftlint:disable` to the offending files** — the
cheapest possible resolution, and the one the config explicitly pre-empts: «Kept at their defaults on
purpose, and currently failing on seven types … That is real debt, recorded rather than configured
away.» Rejected because `PG-143` is a P1 precisely because the app's own linter says these files are
past the point where a person can hold one in their head, and silencing the instrument does not move
the file.

**Split `PraticaSyncEngine`'s `fileprivate` cluster too, widening it to `internal`** — would bring
every pratiche file under the 400-line warning, which is a tidier final table. Rejected by §D4: it
repeals ADR-0036 §D21's opacity guarantee, which exists so a «Rigenera» diff cannot show one thing
and write another, and it would do so inside a commit whose message says no behaviour changed.

**Do the whole refactor as one commit** — it is one mechanical idea, and eight commits of moves make
a noisy history. Rejected because the acceptance criterion is per-step greenness: a single commit
that turns the suite red gives no information about which of eleven files did it, and the one class
of failure this refactor can produce (a `private` that should have widened, a `fileprivate` cluster
split) is exactly the class that bisects trivially when the steps are separate.

---

## Consequences

### Positive

- Every error-level SwiftLint finding in `Sources/Features/Pratiche/` and its `Sources/Core`
  neighbours is cleared, and most warnings with them. The instrument the project chose to keep on
  goes quiet for this layer, so the next real finding in it is visible.
- The largest file in the feature drops from 1649 to roughly 330 lines, and the largest type body
  from 695 to under 60. `runExclusive`'s complexity of 21 becomes five named steps.
- Four copies of the Envelope-Index publish block become one, so the next change to how a generation
  is published (ADR-0036 §D2's territory) is one edit rather than four and a miss.
- Two verbatim duplicates that a structure scan would keep re-finding are gone, and the one that
  touches two protected interfaces is documented at the helper rather than only in an ADR.
- `praticaNotePath` leaves a command-dispatch struct for the naming enum, which is where
  `Sources/Connector` can see it — the direction CLAUDE.md's «AI connector» section asks for.

### Negative

- Roughly a dozen members widen from `private` to `internal`, and `@testable import` makes them
  visible to the unit suite. §D3's comment rule mitigates the first and nothing mitigates the second
  except review.
- `PraticaSyncEngine+Messages.swift` keeps a `file_length` warning by design (§D4). Somebody will
  want to fix it; §D4 exists to tell them not to, and a warning that is deliberately left is a
  warning people learn to skip past.
- Eleven files become roughly twenty-five. Finding a given function means knowing which `+Aspect`
  file owns it — mitigated by the MARK names being carried into the file names, and by the
  convention already existing forty times over.
- Every step needs `tuist generate` before it builds, because the generated project lists files
  explicitly. A step verified without it produces a compiler error that names the compiler and not
  the cause (CLAUDE.md's own warning).
- `git blame` on the moved code now stops at the refactor commit. `--follow` and `-C` recover it;
  a casual blame does not.

### Neutral

- No behaviour changes, so no UI-test expectation changes and no fixture changes. `scripts/uitests.sh`
  is still the merge gate and still runs by hand.
- `Project.swift` is not edited: the app target globs `Sources/**` and `sharedSources` globs
  `Sources/Core/**`, so every file this chain adds is picked up automatically.
- No protected-interface signature changes, so `.claude/protected-interfaces` needs no new entry and
  no existing one is touched. (Noted for accuracy: `interface-check.sh` is not present in the current
  lean hook set, so that registry is convention here, not an enforced gate.)
- The `weakening-scan.sh` `zero-assertion-test` noise and the secret scanner's `token` false
  positives behave exactly as CLAUDE.md already documents; this chain adds no new category.

---

## References

- GitHub issue #243 / `TODO.md` `PG-143`, and the thirteen `structure-*` findings it lists.
- `docs/adr/0036-pratiche.md` — §D5, §D6, §D14, §D19, §D21.
- `docs/adr/0040-pratiche-attachment-reliability-bugs.md`, `docs/adr/0042-pratiche-inline-image-placeholders.md`.
- `docs/adr/0001` §D1 and `docs/adr/0007` — shared sources and connector purity.
- `.swiftlint.yml` (thresholds and their recorded rationale), `swiftlint 0.65.1` output at `75d4db5`.
- `Sources/Features/.../NoteListPane.swift:23-30` — the widening convention this ADR generalises.
- `Tests/SharedSourcesPurityTests.swift`, `Tests/PraticaNamingTests.swift`,
  `Tests/ConventionsTests.swift:464-545` — the guards and pins relied on above.
- Implementation plan: `docs/plans/pg-143-pratiche-structure-refactor.md`.
