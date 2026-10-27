**Read the verdict, not the log.** Verdict is a family of test reporters that render a test run for the reader that pays for every token and cannot scroll back: a coding agent. One grammar across Java, Kotlin, .NET, TypeScript, Python and Swift; the same first line, the same failure groups, the same index, with the framework's own test ids, assertion text and rerun commands.

```
# TESTS FAIL | 1 failed, 95 passed | 96 run | 4.4s | verdict/1
run: complete | exit 1 | pytest 9.1.1 | 1 root cause
delta: 1 new | vs 2026-10-27T10:14Z
full: .verdict/last-run.md | .verdict/last-run.ctrf.json

## [1/1] AssertionError in test | 1 test
tests/test_tax.py::test_rate[eu]
at tests/test_tax.py:42 in test_rate
    assert calculate_tax(100, region="eu") == 105.5
E   assert 105.0 == 105.5
rerun: pytest "tests/test_tax.py::test_rate[eu]"

##[failures]
[1] AssertionError | 1 tests | tests/test_tax.py:42 | assert 105.0 == 105.5 | rerun: pytest "tests/test_tax.py::test_rate[eu]"
##[/failures]
```

A green run is one line. Failures are grouped by root cause, so one broken fixture is one entry, not forty. Every group carries the decisive frame, the assertion library's own text, and the exact command to rerun it. The report says what changed since the last run, names the file you edited when it sits in the failing path, warns when tests silently vanished, and never reports an incomplete run as a pass.

### Projects

| Repository | Covers | Status |
|---|---|---|
| verdict-spec | The format specification, the polyglot failure zoo, golden reports, conformance kit, token and agent benchmarks | design |
| verdict-junit, verdict-gradle, verdict-maven | JUnit 5, JUnit 4, Kotest, Spock, TestNG, Kotlin Multiplatform, Android unit tests | planned, phase 1 |
| verdict-mtp, verdict-vstest | xUnit v2 and v3, NUnit, MSTest, TUnit | planned, phase 2 |
| verdict-jest, verdict-vitest, verdict-node-test, verdict-mocha, verdict-playwright | Jest, Vitest, `node:test`, Mocha, Playwright | planned, phase 3 |
| verdict-pytest, verdict-unittest | pytest, unittest | planned, phase 4 |
| verdict-swift | Swift Testing, XCTest, `xcodebuild` | planned, phase 5 |
| verdict-agent | CLAUDE.md and AGENTS.md snippets, skill, hook, GitHub Action, MCP tool | planned, phase 6 |

The design record, with the survey of existing reporters, the full grammar and the per-framework implementation plan, is in [`.github/planning/verdict-design-2026-10-27.md`](https://github.com/test-verdict/.github/blob/main/planning/verdict-design-2026-10-27.md).
