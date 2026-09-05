# Memory index

- [Swift Testing filter gap](swift-testing-only-testing-gap.md) — `-only-testing:PergamenumTests/<File>` silently selects 0 tests for loose top-level `@Test func`s.
- [Fresh worktree needs tuist install first](tuist-worktree-fresh-checkout.md) — `tuist generate` fails "could not find external dependencies" until `tuist install` runs once per worktree.
- [Tester-owns-interface stub pattern](pergamenum-tester-stub-pattern.md) — how to keep exhaustive switches compiling when declaring not-yet-built enum cases/types (ADR-0155 §D1).
- [spec-coverage.sh MALFORMED on this SPEC.md](spec-coverage-malformed-success-criteria.md) — script chokes on the `- [ ] R-NN —` bullet format; read §9 directly instead.
- [Theme.emergency force-unwrap crash](pergamenum-emergency-theme-force-unwrap.md) — a new TokenKey case needs a placeholder in `Theme.emergency` too, or a red test crashes the whole xctest process.
- [ADR-0030 plan "SPEC §N" refs](adr-0030-plan-section-refs-not-spec.md) — those section numbers are the plan's own, not the real SPEC; the roadmap doc it also cites doesn't exist in-tree.
- [Swift Testing comment concat fails](swift-testing-comment-concat.md) — `"a " + "b"` as a `#expect`/`#require` message errors "Cannot convert String to Comment?"; keep the message on one line.
- [TextKit 2 custom fragment injection](textkit2-custom-fragment-injection.md) — only way to get a custom NSTextLayoutFragment subclass into a real layout pass in a test is a throwaway NSTextLayoutManagerDelegate; return storage+layout+delegate too or weak refs deallocate.
- [System menu items render English](system-menu-items-render-english.md) — About/Settings/etc. are English in this en-only bundle; use accessibilityIdentifier, never the Italian title, for those items only.
