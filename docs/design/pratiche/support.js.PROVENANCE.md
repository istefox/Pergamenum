# support.js provenance

`support.js` (1911 lines) is the runtime that `Pergamenum Pratiche.dc.html` loads with
`<script src="./support.js">` (line 6). It is not Pergamenum code and nothing in the app, the
tests or the build reads it. This note records what can be established about it from this
repository, and marks what cannot. The bundle itself is left byte-faithful to what produced it,
which is why this is a sibling file and not an edit to its header.

Written for PG-148 (ADR-0051 §D9), 2026-09-19.

## What is known

- **How it arrived.** Commit `8fb5c6b` (2026-09-09), "docs(pratiche): add SPEC, ADR-0036, plan,
  UX blueprint and design for Pratiche", in the same batch as the design document it belongs to.
  It has not changed since.
- **Where it came from.** `DESIGN.md:8` records the export: Claude Design, fetched through the
  DesignSync tool from the project "UI mockups for instruction prompt", together with
  `Pergamenum Pratiche.dc.html`. It is the export's own runtime, not something written here.
- **What uses it.** Exactly one file references it, `Pergamenum Pratiche.dc.html:6`. That file is
  the source cited for screens 1a-1g in `docs/superpowers/plans/2026-09-09-pratiche.md:14`, so
  this is live reference material and not dead weight.
- **What its header says.** Line 1: `GENERATED from dc-runtime/src/*.ts — do not edit. Rebuild with
  cd dc-runtime && bun run build`.
- **Third-party code it loads at runtime,** from `unpkg.com`, with no integrity hash and no
  local copy (versions read from the URLs at lines 1143-1147): React 18.3.1, ReactDOM 18.3.1,
  `@babel/standalone` 7.29.0.

## What is not known

- **The source of the runtime.** `dc-runtime/` exists nowhere in this repository or in its
  history, and the bundle carries no version, licence or upstream URL. The header names a build
  command for a directory this project does not have. Nothing here can rebuild the file, and no
  claim is made about who maintains it.
- **Whether a newer export would differ.** Not checked: it would need a fresh DesignSync fetch,
  which is a network call outside this chain's scope.

## Findings already filed against it

Both are in `docs/deep-refactor/2026-09-11-pergamenum-audit.md`, deferred as report-only, and
carried in `TODO.md`.

- `security-support.js-9c6`: the runtime compiles code with `new Function` (lines 844 and 1218)
  and posts to the parent window with a `"*"` target origin (lines 1387 and 1865).
- `perf-support.js-1e7`: `encodeCase` builds nine `RegExp` objects per call (line 380).
- `structure-support.js-0ab`: the size of a committed generated bundle. This note is the
  response to it: the file is kept, and its origin is written down.

## Why it stays as it is

It is design-time material that opens in a browser from disk. It ships in no target, so the
security and performance findings above describe a page a person opens on purpose, not the
app. Editing it would also diverge it from whatever produced it, with nothing to rebuild it
from. If it is ever regenerated, the export replaces it whole.
