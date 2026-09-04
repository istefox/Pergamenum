---
name: batch-4-sign-update-keychain-prompt
description: Sparkle's sign_update cannot be run by an agent on this Mac — it raises a Keychain authorization prompt only Stefano can answer; generate_keys -p does not.
metadata:
  type: project
---

`build/tools/sparkle/bin/sign_update <file>` hangs on this Mac when an agent runs it: it needs to
read the EdDSA private key out of the login Keychain, and macOS puts up a SecurityAgent
authorization dialog for it. Measured 2026-09-04 (Sparkle chain, step 5 batch 4): the run was
killed by `timeout 60` with empty stdout and empty stderr, and `ps` showed a `SecurityAgent`
process started at the same second as the invocation. `generate_keys -p` on the same keychain item
returned immediately with no prompt, so the difference is reading the private half, not touching
the item at all.

**Why:** it means the signing step of `scripts/release.sh` is not rehearsable headlessly, and a
timeout there is not evidence of a broken command. Retrying only stacks more unanswerable dialogs
on Stefano's screen.

**How to apply:** verify anything that depends on `sign_update`'s behaviour from the pinned source
instead — `~/.cache/swifterpm/sources/sparkle/<version>-*/sign_update/main.swift` is present after
`tuist install` and is the authoritative statement of its output format (`:287` prints
`sparkle:edSignature="…" length="…"` for an archive; `:285`'s `sparkle:length` spelling is the
release-notes branch). Exercise the parser against a literal line of that shape. One attempt at
the real binary is enough; then report it and move on.

Related: [[batch-3-sparkle-eddsa-keychain-preexisting]]
