<!-- step5-brief: plan=/Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md tasks=4 lines=238-260 -->
# Step 5 Batch Brief -- 2026-09-08-word-grained-markdown-reveal-on-caret-in.md -- tasks 4-4

## Task text (verbatim, plan lines 238-260)

### Task 4 — the setting, stored and offered (R-07, R-08)

- `Sources/Vault/VaultSettings.swift`: `revealsInlineSpans: Bool` with a doc comment naming
  ADR-0037 and saying why it is off by default; `false` in `.default`; `revealsInlineSpans: Bool = false`
  in the memberwise initialiser; `decodeIfPresent(…) ?? fallback.revealsInlineSpans` in
  `init(from:)`. Nothing else in that file changes.
- `Sources/Features/Settings/EditorSettings.swift`: a `Toggle` immediately after the
  `hidesMarkup` toggle and its caption, reading and writing through
  `vault.updateSettings { $0.revealsInlineSpans = … }`, `.accessibilityIdentifier("settings-reveals-inline-spans")`,
  `.disabled(!vault.settings.hidesMarkup)` (ADR §D7 — with markup shown the hook is a no-op), and
  an explanatory `Text(...).themedText(.caption, color: .textTertiary)` in Italian saying that
  grassetto, corsivo, barrato and collegamenti show their syntax only where the cursor is, and
  that titoli, elenchi, citazioni e tabelle are unchanged.

**Tester** extends `Tests/VaultTests.swift` copying `readableWidthDefaultsToTrueAndAnOlderSettingsFileStillReadsTrue`
(`:680-692`) exactly: default is `false`; a `settings.json` written before the key exists still
decodes `false`; `{"dailyFolder":"Calendar","revealsInlineSpans":true}` decodes `true`; and a
round trip through `JSONEncoder`/`JSONDecoder` preserves it. Red first.

**Coder** adds the property and the toggle.

- Budget: `Sources/Vault/VaultSettings.swift`, `Sources/Features/Settings/EditorSettings.swift`, `Tests/VaultTests.swift` (~90 lines)

## File map (from Budget: declarations, tasks 4-4)

- Sources/Features/Settings/EditorSettings.swift
- Sources/Vault/VaultSettings.swift
- Tests/VaultTests.swift

## Excluded tasks (not in this batch)

- Task 1 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 2 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 3 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 5 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 6 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 7 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 8 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md

Full plan: /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md

## Context documents (open only for the reason stated -- not read unconditionally)

- ADR: /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/adr/0037-word-grained-markdown-reveal-on-caret-in.md -- the one setting (ADR §D7)
- SPEC: /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/SPEC.md -- requirement IDs for this task's tests
