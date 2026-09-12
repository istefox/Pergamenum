# Debugger Report

## Root cause

A **use-after-free of `VaultWatcher`**, caused by handing FSEvents a non-owning pointer
to it.

`VaultWatcher.start()` built its stream context as

```swift
info: Unmanaged.passUnretained(self).toOpaque(),
retain: nil,
release: nil,
```

The SDK header (`FSEvents.h`, `struct FSEventStreamContext`) is explicit that the
framework only retains `info` *if* a retain callback is supplied. With both `nil`,
FSEvents holds a bare pointer whose validity is tied to nothing, while the callback it
feeds is delivered asynchronously on `it.stefer.pergamenum.watcher`.

The callback then did `Unmanaged<VaultWatcher>.fromOpaque(info).takeUnretainedValue()`
and read `self.root`. When the watcher had already been deallocated, `root` was read out
of freed storage, and `URL.standardizedFileURL` died on it.

Neither of the two named suspects was the cause:

- **`VaultScanner.relativePath(of:under:)` is pure and innocent.** It is byte-for-byte
  unchanged since the commit that introduced it (`f555d33`), so Task 4's `VaultWalk`
  unification did not touch it — only the doc comment above it moved. Confirmed by
  `git show f555d33:Sources/Vault/VaultScanner.swift`.
- **`URL.standardizedFileURL` is thread-safe.** 2.4M concurrent calls across 12 threads,
  both on a shared `URL` value and on thread-local ones, ran clean. Hypothesis (a) from
  the brief is rejected.

## Evidence

The decisive evidence is the **crash registers**, not a reproduction.

`URL.standardizedFileURL.getter` disassembles (in the shared cache on this machine, at
`0x18c2d37fc`, which is where all three crashes' `lr = 0x18c2d3824` points) to:

```
<+28>:  ldp  x22, x21, [x20]        ; load the URL struct's two words
<+32>:  mov  x0, x22                ; x0 = the _URLProtocol object reference
<+36>:  bl   swift_getObjectType    ; <- faults here
```

So `x20` is the address of the `URL`, and `x0`/`x22` is the object reference it holds.
Across the three reports:

| crash | `x20` (URL address) | `x22` (word 0) | `x21` (word 1) | `far` |
|---|---|---|---|---|
| 2026-09-11 16:13 | `0x7c5ac8f90` | `0x20` | `0xf00000000000001a` | `0x20` |
| 2026-09-12 14:02 | `0xcbc055490` | `0x0` | `0x0` | `0x0` |
| 2026-09-12 17:19 | `0xab4c71e90` | `0x0` | `0x0` | `0x0` |

`x20` is a live heap address in every case, but the two words read out of it are zeros
twice and, in the first, `0x20` beside **`0xf00000000000001a` — a Swift `_StringObject`
bit pattern**. That block was no longer holding a `URL`; it had been freed and handed to
a `String`. `esr = 0x92000006` is a translation-fault read with `far == x0`, i.e.
`swift_getObjectType` dereferencing a null/garbage object pointer.

Line attribution corroborates rather than contradicts. The three reports name
`VaultScanner.swift` lines 178, 191 and 190, which looks like two different expressions
until each is resolved against the build that was actually live at that timestamp
(`VaultScanner.swift` was edited that day): at `57a3dce` line 178, at `b0d3a65` line 191
and at `abb5325` line 190 are all the same statement —
`let rootPath = root.standardizedFileURL.path(percentEncoded: false)`. **All three
crashes are on `root`**, never on the locally-built `url`.

Supporting measurement: teardown does not wait for the callback. With a callback
deliberately holding the stream's queue for 400 ms, `FSEventStreamStop` +
`Invalidate` + `Release` returned in **0.0 ms**, three runs out of three, with the
callback confirmed not yet returned.

One honest qualification. `takeUnretainedValue()` returns a *managed* reference and so
retains, which means a callback that has already reached that line is safe; the exposure
is a callback delivered or started when the watcher is already gone. Six deliberate
constructions of that interleaving (mid-callback teardown, enqueued-behind-a-blocker
delivery, ASan, per-object liveness ledgers) all came back clean — expected for a window
this narrow, given the bug produced three crashes in five days of heavy UI-test runs. Two
earlier probes did appear to prove it at 39/40, and both were **false positives** from a
global in-callback counter scoring one round's teardown against the next round's
callback; they were discarded rather than reported. The register evidence above stands on
its own and does not depend on any of them.

All three crashes were in XCTest-hosted app instances (thread 0 in `XCTWaiter`), which
fits: UI tests open, replace and close vaults repeatedly over churning temp directories,
which is exactly the teardown-while-events-in-flight shape.

## Fix applied (files modified)

**`Sources/Vault/VaultWatcher.swift`** — the callback's context is no longer the watcher.
A nested `Sink` holds `root` and the `onChange` closure; `start()` takes an explicit `+1`
on it (`passRetained`) and `stop()` gives that `+1` up from `queue` itself:

```swift
Unmanaged<Sink>.fromOpaque(info).takeUnretainedValue().cancel()
queue.async { Unmanaged<Sink>.fromOpaque(info).release() }
```

`queue` is serial and is the queue FSEvents delivers on, so anything the stream already
handed to it has run before the last reference goes. The watcher may now be deallocated
whenever it likes — no callback reads it. `deinit { stop() }` still works, because the
watcher holds the sink only as a raw pointer, so there is no cycle.

`cancel()` additionally closes a real behavioural bug: before, an event still in flight
when a vault closed reached `onChange` carrying paths relative to the *old* root, which
`VaultController.reconcile` would then apply against the newly-opened vault.

**`Sources/Features/Pratiche/PraticheController.swift`** — `MailStoreEventStream` was
written in `VaultWatcher`'s shape and carried the identical defect (`passUnretained`,
`retain: nil`, `release: nil`, callback calling `onChange()` on the unretained `self`).
Same fix, same shape. Not scope creep: it is the same use-after-free, and leaving a known
one in place is not an option.

**`Sources/Vault/VaultScanner.swift`** — one stale doc reference (`VaultWatcher.swift:82`
→ `VaultWatcher.Sink.handle`). No code change.

`git add` result: **staged**, four paths (`VaultWatcher.swift`, `VaultScanner.swift`,
`PraticheController.swift`, `Tests/VaultWatcherTests.swift`). Not committed, per the brief.

## Regression test

`Tests/VaultWatcherTests.swift`, suite `VaultWatcher lifetime`, three tests — all
passing. The race itself is deliberately **not** what they try to reproduce, and the
file says so; forcing a flaky timing test into a suite that runs on every turn would
cost more than it catches.

- *no event is delivered after stop()* — pins the `cancel()` contract. Asserts that
  something does **not** happen, so a quiet file system passes rather than flakes.
- *a watcher dropped without stop() while the vault churns does not fault* — runs the
  `deinit`-only teardown path against a busy stream twelve times, ~1 s. Cannot prove the
  race is gone and does not claim to; it gives a reintroduced use-after-free somewhere to
  show up.
- *only markdown outside excluded directories is reported, deduped and sorted* — the
  filtering in `handle` had **zero** coverage before, and the fix moved it into `Sink`. A
  move is exactly when behaviour changes silently.

## Verification

```
xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum \
  -destination 'platform=macOS' -derivedDataPath ".build/DerivedData" \
  -only-testing:PergamenumTests test
```

**`** TEST SUCCEEDED **` — 2895 tests in 137 suites, 0 failures.** Run twice, green both
times; `Suite "VaultWatcher lifetime" passed after 3.336 seconds`. App target builds
clean. `tuist install && tuist generate --no-open` run first, and again after adding the
test file (`Tests/**` is a glob).

TSan was not used in the end: the defect is a lifetime bug, not a data race on a shared
location, and TSan does not flag use-after-free. ASan was tried — it faulted twice out of
two early on, but its own symbolizer crashed on the nested fault and the result did not
reproduce later, so it is reported as suggestive only and carries no weight in the
conclusion above.

**Not run: the UI suite.** `scripts/uitests.sh` is the pre-merge gate per CLAUDE.md, and
since all three crashes came from UI-test instances it is the most likely place to see
the fix hold. I did not run it deliberately: it launches `XCUIApplication()`, which
terminates the copy of Pergamenum the person at the keyboard is using. Worth running
before the merge.

## Confidence

**High** on the root cause. The register evidence is direct and unambiguous — a `URL`
read out of a heap block that had been freed and reused for a `String` — and the
ownership defect that permits it is plainly visible against the SDK header's own
contract.

**Medium-high** on the fix eliminating the crash. It removes the non-owning pointer
entirely, which is the documented-correct discipline for an FSEvents context, and the
suite is green. But since the race does not reproduce on demand, I cannot demonstrate the
crash is gone — only that the unsafe ownership it evidences is. Absence of the crash over
the next several UI-test runs is the confirmation to look for.
