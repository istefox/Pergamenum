---
name: swift-testing-comment-concat
description: A multi-line `+`-concatenated String literal as the comment argument to #expect/#require fails to build in this codebase's Swift Testing setup ("Cannot convert value of type 'String' to expected argument type 'Comment?'").
metadata:
  type: project
---

`#expect(condition, "part one " + "part two")` and `#require(value, "part one " + "part two")`
fail to compile here with `Cannot convert value of type 'String' to expected argument type
'Comment?'`, even though a single string-literal argument (including one with `\(interpolation)`)
works fine. `Comment` is `ExpressibleByStringLiteral`/`ExpressibleByStringInterpolation`, and the
compiler resolves that conversion for a literal at the call site, but not for a `String` value
produced by evaluating a `+` expression first - by the time `+` runs, the operands are plain
`String`, and `String` does not implicitly convert to `Comment`.

**How to apply:** never wrap a `#expect`/`#require` message across lines with `+`. Either keep it
one line (this codebase's SwiftLint line-length tolerance for a test message is generous, verified
against `CardTextViewTests.swift`) or interpolate everything into one string literal
(`"prefix \(computed) suffix"`) rather than concatenating literals. Caught during Task 5 of the
`editor-page-typography-noteplan` chain (ADR-0030) - the failure surfaces as **two** build errors
per bad call site and takes down the whole compile unit those tests live in, producing zero red
for every test in that file, not just the one with the bad message - worth checking early rather
than debugging why an entire suite reports zero tests ran.
