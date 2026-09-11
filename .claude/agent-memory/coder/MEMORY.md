# Coder memory index

- [Connector build red at base](topics/batch-1-connector-build-red-at-base.md) — perg/pergamenum-mcp fail to build for a pre-existing sharedSources gap, not because of current work.
- [Standard menu items render English](topics/batch-2-macos-standard-menu-items-english.md) — About/Settings… are English in this en-only bundle; use accessibilityIdentifier, never the Italian title.
- [Sparkle EdDSA key pre-exists in the Keychain](topics/batch-3-sparkle-eddsa-keychain-preexisting.md) — read the public key with `generate_keys -p`; never regenerate the pair.
- [Waiting on long xcodebuild runs](topics/batch-3-waiting-on-long-xcodebuild-runs.md) — a `pgrep -f` wait-loop self-matches and never exits; poll the log file instead.
- [sign_update raises a Keychain prompt](topics/batch-4-sign-update-keychain-prompt.md) — not rehearsable headlessly; verify its output format from the pinned source and try the binary once at most.
- [mail-envelope-index-measured-facts](topics/batch-1-mail-store.md) — Four measured facts about Apple Mail's Envelope Index and .emlx layout (epoch, Message-ID location, fan-out rule, WAL skew) that the SPEC and ADR-0036 got wrong or did not know
- [batch-2-emlx-mime-dossier](topics/batch-2-emlx-mime-dossier.md) — Pratiche batch 2 — both message:// encodings open Mail, the Envelope Index is readable from the shell, and a nested MIME boundary is the outer one plus a suffix
- [pratica-sync-two-traps](topics/batch-3-pratica-sync.md) — Two non-obvious facts hit while implementing the Pratiche sync (ADR-0036 Task 4) - EmailHeaderParser needs CRLF-normalised input, and index rows never carry an RFC Message-ID.
- [batch-4-pratiche-pane](topics/batch-4-pratiche-pane.md) — Pratiche pane batch (tasks 5-6) - accessibility-identifier scheme actually used, the identifiers left disabled for later tasks, and the corrected connector-build state
- [batch-5-pratiche-commands-wizard](topics/batch-5-pratiche-commands-wizard.md) — Three measured facts from Pratiche batch 5 — symbolichotkeys lives in the plain domain not -currentHost, the two ReleasePipelineTests flakes pass alone, and both connectors now build on feat/pratiche.
- [batch-6-pratiche-settings-connector](topics/batch-6-pratiche-settings-connector.md) — Three traps met while wiring the Pratiche Settings tab and the read-only connector - the index cache silently drops pergamenum-* foreign keys, System Events accessibility worked (contradicting the global -1728 rule), and opening the app on a throwaway vault reads the real Mail store.
