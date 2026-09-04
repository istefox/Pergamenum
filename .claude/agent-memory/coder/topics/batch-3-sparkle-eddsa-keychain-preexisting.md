---
name: batch-3-sparkle-eddsa-keychain-preexisting
description: The Sparkle EdDSA signing key already exists in this Mac's login Keychain — Task 9 of the Sparkle chain must not regenerate it.
metadata:
  type: project
---

On 2026-09-04, while rehearsing the ADR-0031 release preflight (Sparkle chain, step 5 batch 3),
`security find-generic-password -s "https://sparkle-project.org" -a "ed25519"` already returned an
item on this machine: `svce=https://sparkle-project.org`, `acct=ed25519`, `desc=private key`. The
plan assumed the key would not exist until Task 9 ran `generate_keys`.

**Why:** the EdDSA private key is the one artifact of this chain that cannot be recovered if it is
overwritten — every already-published appcast signature was made with it, and Sparkle refuses an
update signed by a different key. `generate_keys` run blind against an existing account is the one
way to lose it.

**How to apply:** before Task 9 (or any later re-run of key generation), check for the existing
item first and read out its public key (`generate_keys -p`) rather than generating a new pair. The
value that goes into `SUPublicEDKey` must be the public half of the key already in the Keychain.

Related: [[batch-3-sparkle-tools-fetch]] (does not exist yet — the fetch script's own facts live in
`scripts/fetch-sparkle-tools.sh` comments and need no memory).
