# Coder memory index

- [Connector build red at base](topics/batch-1-connector-build-red-at-base.md) — perg/pergamenum-mcp fail to build for a pre-existing sharedSources gap, not because of current work.
- [Standard menu items render English](topics/batch-2-macos-standard-menu-items-english.md) — About/Settings… are English in this en-only bundle; use accessibilityIdentifier, never the Italian title.
- [Sparkle EdDSA key pre-exists in the Keychain](topics/batch-3-sparkle-eddsa-keychain-preexisting.md) — read the public key with `generate_keys -p`; never regenerate the pair.
- [Waiting on long xcodebuild runs](topics/batch-3-waiting-on-long-xcodebuild-runs.md) — a `pgrep -f` wait-loop self-matches and never exits; poll the log file instead.
- [sign_update raises a Keychain prompt](topics/batch-4-sign-update-keychain-prompt.md) — not rehearsable headlessly; verify its output format from the pinned source and try the binary once at most.
