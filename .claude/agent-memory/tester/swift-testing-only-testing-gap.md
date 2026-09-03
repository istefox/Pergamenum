---
name: swift-testing-only-testing-gap
description: xcodebuild -only-testing:PergamenumTests/<FileName> silently runs 0 tests for Swift Testing files whose @Test funcs are top-level (no enclosing @Suite struct) — Pergamenum's own convention for most test files.
metadata:
  type: project
---

Most Pergamenum test files (`MarkdownStylerTests.swift`, `GFMTableTests.swift`'s sibling
files, etc.) mix loose top-level `@Test func ...` with occasional `@Suite struct ...`
blocks. `xcodebuild ... -only-testing:PergamenumTests/MarkdownStylerTests` (naming the file
as if it were an XCTest class) matches nothing and reports "Executed 0 tests, with 0
failures" — no error, no warning, just silently empty. This cost a full build+test round
trip to notice on 2026-09-02/03 (PG-018 / editor-wysiwyg-unification chain).

**Why:** xcodebuild's `-only-testing` selector needs a real Swift Testing suite (a type)
or a fully-qualified test ID; a bare top-level `@Test func` has no such type to match by
file name.

**How to apply:** to run a specific subset while iterating, either (a) run the whole
`PergamenumTests` target (`-only-testing:PergamenumTests`, no suffix) and `grep` the
resulting log for the specific test/file names (`recorded an issue at <File>.swift`,
`✔ Test <name>() passed`), or (b) if the file already has an enclosing `@Suite struct`,
filter by that struct's name (`-only-testing:PergamenumTests/SuiteName`) — this does work.
Do not conclude "0 executed" means the filter syntax is broken globally; it means this
particular file has no addressable suite type.

See also [[pergamenum-tester-stub-pattern]].
