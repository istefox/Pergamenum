# Memory index

- [Swift Testing filter gap](swift-testing-only-testing-gap.md) — `-only-testing:PergamenumTests/<File>` silently selects 0 tests for loose top-level `@Test func`s.
- [Fresh worktree needs tuist install first](tuist-worktree-fresh-checkout.md) — `tuist generate` fails "could not find external dependencies" until `tuist install` runs once per worktree.
- [Tester-owns-interface stub pattern](pergamenum-tester-stub-pattern.md) — how to keep exhaustive switches compiling when declaring not-yet-built enum cases/types (ADR-0155 §D1).
- [spec-coverage.sh MALFORMED on this SPEC.md](spec-coverage-malformed-success-criteria.md) — script chokes on the `- [ ] R-NN —` bullet format; read §9 directly instead.
- [Theme.emergency force-unwrap crash](pergamenum-emergency-theme-force-unwrap.md) — a new TokenKey case needs a placeholder in `Theme.emergency` too, or a red test crashes the whole xctest process.
