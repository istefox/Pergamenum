<!-- step5-brief: plan=/Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md tasks=6,7,8 lines=257-356 -->
# Step 5 Batch Brief -- 2026-09-04-sparkle-auto-update-integration.md -- tasks 6-8

## Task text (verbatim, plan lines 257-356)

### Task 6 — the Sparkle tools arrive pinned and checksum-verified (R-05, R-06)

- Budget: `scripts/fetch-sparkle-tools.sh` (new) (~90 lines)
- Bash 3.2, `#!/usr/bin/env bash`, `set -euo pipefail`, every variable quoted. Header comment
  cites `ADR-0031` and `2026-09-04-sparkle-auto-update-integration`.
- Downloads `https://github.com/sparkle-project/Sparkle/releases/download/2.9.6/Sparkle-for-Swift-Package-Manager.zip`,
  verifies its SHA-256 against the pinned constant
  `8d5fb41d960b43f4a68aa14126bf62b098544ec8d191cdcc73eb14e63a8e7606` **before unpacking anything**,
  and extracts `bin/` into `build/tools/sparkle/bin/`. That checksum is the value in Sparkle's own
  `Package.swift`, so the tools and the framework Task 2 links are provably the same build
  (ADR §D11). `build/` is already gitignored (`.gitignore:66`) — no gitignore edit.
- **Idempotent:** an existing unpack whose `bin/sign_update` is present and whose recorded
  checksum matches is left alone and reported, not re-downloaded.
- **Fails loud on a checksum mismatch and deletes nothing** — it reports both hashes and exits
  non-zero. Never `rm -rf` anything (a chained `rm -rf` gets the whole Bash call denied on this
  machine, and this script must stay runnable).
- Verification for this task: run it twice. First run downloads and unpacks; second run reports
  "already present" and exits 0 in under a second.
  `build/tools/sparkle/bin/sign_update --help` runs.
  Then flip one character of the pinned checksum in a scratch copy and confirm it refuses.
- No unit test: this repo has no shell test harness and inventing one for a 90-line fetcher is
  the wrong trade. The verification above is the coverage, and it is written into the task.

### Task 7 — the release preflight, and the distributable cut from the stapled bundle (R-06)

- Budget: `scripts/release.sh` (~90 lines)
- **Two insertions, both in one task because the first exists to protect the second.**
- **Preflight**, immediately after the branch/clean-tree guards at `:44-46`, before the
  ten-minute archive:
  - resolve `sign_update` via `$SPARKLE_BIN` → `build/tools/sparkle/bin` → `PATH`, in that order,
    in a `sparkle_tool()` function; `fail` naming `scripts/fetch-sparkle-tools.sh` if absent;
  - `gh auth status` exits 0;
  - the EdDSA private key is in the login Keychain — **verify the exact service/account
    `generate_keys` writes before hardcoding them** (`security find-generic-password -s <service>
    -a <account>` with output suppressed; never print the key). If Task 9 has not run yet, this
    check is written but the script is not run end to end, which is fine.
  - `command -v python3`.
  This is the script's own philosophy applied one step earlier — `:92-97` reads *"Check what came
  out, before asking Apple to bless it… Each of these has been wrong at least once."*
- **The distributable**, after the `spctl` verdict at `:133-135`. Move the existing
  `version=` line (`:137`) **up**, above the new stage, since the filename uses it — that is the
  only existing line this task moves. Then:

  ```
  step "Impacchetto la build firmata e ticketata"
  readonly DIST="$OUTPUT/Pergamenum-$version-$BUILD.zip"
  ditto -c -k --sequesterRsrc --keepParent "$BUNDLE" "$DIST"
  ```

  **`$zip` (`:118`) is not reused, not renamed, not overwritten**, and `$log` (`:123`) is left
  pointing at it: `$zip` is the record of what notarytool was handed, and the two files have
  opposite ticket status (ADR §D8). `--sequesterRsrc` is added because Sparkle's publishing
  documentation asks for it.
- Verification without cutting a release: `bash -n scripts/release.sh` passes; then run the
  preflight block alone in a scratch shell with the same resolution order and confirm it passes
  with the tools present and fails with `SPARKLE_BIN=/nonexistent`. Confirm the `$DIST` `ditto`
  line against the **already-installed** `/Applications/Pergamenum.app` in a temp directory, and
  check the ticket survives the round trip:
  `ditto -c -k --sequesterRsrc --keepParent /Applications/Pergamenum.app /tmp/t.zip && ditto -x -k /tmp/t.zip /tmp/x && xcrun stapler validate /tmp/x/Pergamenum.app`.
  That last command passing **is** R-06's proof, and it is the one thing today's `$BUILD.zip`
  would fail.

### Task 8 — `scripts/appcast.py`, with its own self-test (R-07)

- Budget: `scripts/appcast.py` (new) (~230 lines)
- `python3`, stdlib only (`xml.etree.ElementTree`, `urllib.request`, `argparse`, `email.utils`).
  Header cites `ADR-0031` and this plan's basename.
- **Why not `generate_appcast`:** one `--download-url-prefix` for all items where each release has
  its own tag, a local archive folder standing in as the feed's history, and delta generation
  which is a non-goal (ADR §D10). The SPEC permits the hand-built branch explicitly.
- Interface: `appcast.py --feed-url <url> --version <build> --short-version <v>
  --min-system <x.y> --download-url <url> --signature <sparkle:edSignature value>
  --length <bytes> --notes-link <url> --output <path>`.
- Behaviour: fetch the currently published feed from `--feed-url`; **a 404 yields a fresh
  skeleton, not an error** (that is the state before the first release, and it must be the happy
  path once). Register the `sparkle` namespace
  (`http://www.andymatuschak.org/xml-namespaces/sparkle`) so the output uses the `sparkle:` prefix
  rather than `ns0:`. Insert the `<item>` at the top of `<channel>`; if an item with the same
  `sparkle:version` exists, **replace it in place** rather than duplicating. Write to `--output`.
  A feed that exists but does not parse is a **loud failure**, never a silent skeleton.
- **On parsing XML fetched over the network:** stay on stdlib `xml.etree.ElementTree`. Do **not**
  add `defusedxml` — it is a third-party package and this repo has no Python dependency file to
  put it in. `ElementTree` on Python 3 does not resolve external entities and refuses undefined
  ones outright, so neither XXE nor billion-laughs applies; the input is additionally a document
  fetched over HTTPS from a repository this account owns. Reject any feed carrying a `<!DOCTYPE`
  before parsing it — one `if b"<!DOCTYPE" in raw: fail(...)` line, so the reasoning is enforced
  rather than remembered.
- The item carries exactly: `<title>`, `<pubDate>` (RFC 2822 via `email.utils.formatdate`),
  `<sparkle:version>`, `<sparkle:shortVersionString>`, `<sparkle:minimumSystemVersion>`,
  `<sparkle:releaseNotesLink>`, and one `<enclosure url= sparkle:edSignature= length=
  type="application/octet-stream"/>`.
- **`--self-test`** mode with in-process assertions — no new test framework, no second runner,
  `scripts/mcp-smoke.py` is the precedent. Cases: (1) empty/absent feed → one item, well-formed,
  `sparkle:` prefix present; (2) existing feed with one item → two items, the old one intact and
  the new one first; (3) same `sparkle:version` twice → still one item, updated; (4) malformed
  existing feed → non-zero exit and a message naming the parse error.
- Verification for this task: `python3 scripts/appcast.py --self-test` exits 0 and prints what it
  checked. Then feed the output through `python3 -c "import xml.dom.minidom,sys; xml.dom.minidom.parse(sys.argv[1])"`.
- **Nothing is published by this task.** It writes a local file.

## File map (from Budget: declarations, tasks 6-8)

- scripts/release.sh

No parseable Budget: for task(s): 6 8 (absent is not zero -- consult the task text above)

## Excluded tasks (not in this batch)

- Task 1 -- see /Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md
- Task 2 -- see /Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md
- Task 3 -- see /Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md
- Task 4 -- see /Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md
- Task 5 -- see /Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md
- Task 9 -- see /Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md
- Task 10 -- see /Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md

Full plan: /Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md

## Context documents (open only for the reason stated -- not read unconditionally)

- ADR: /Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/docs/adr/0031-sparkle-auto-update-integration.md -- D8 (DIST cut from the stapled bundle, zip untouched), D10 (hand-built appcast.py, sign_update only), D11 (pinned checksum-verified tools fetch), D12 (release preflight)
- SPEC: /Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/SPEC.md -- requirement IDs R-05, R-06, R-07 for this batch
- CLAUDE.md: /Users/stefer/Developer/Pergamenum_worktrees/feat-add-sparkle/CLAUDE.md -- Commands and Versioning sections (release.sh contract, never install over /Applications without asking)
