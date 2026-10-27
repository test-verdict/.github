# Verdict: test output for coding agents

Survey of existing solutions, format design, and implementation plan.

Design record, 2026-10-27. Status: research and design; nothing implemented. Verdict is a new
project family: one specification, one console grammar, and one repository per test framework.

## 0. Summary

**The library you remembered is `pytest-markdown-report`** (David Allouche, PyPI 0.2.0, July 2026): a
pytest plugin that replaces the console reporter with markdown, "token-efficient markdown test reports
for LLM-based TDD agents". It is small and sound but shallow. **A stronger Python sibling exists,
`pytest-receptor`** (1.2.2, October 2026), whose contribution is not the syntax but the *rules*: group
failures by root cause, never report an incomplete run as a success, give a rerun command, keep the
decisive stack frame, treat test output as untrusted, degrade safely. Outside Python the field is
nearly empty: Vitest 4.1 ships an `agent` reporter (failures only, auto-enabled when an agent is
detected), one community Vitest JSON reporter exists, Microsoft has an open RFC for `dotnet test`
with a measured pilot and no shipped format, and Java, Kotlin, Swift, Jest and NUnit have nothing.

**What to build.** Verdict: one console format, the same grammar in every language, with three native slots
(test id, assertion text, rerun command), plus a machine-readable sidecar file in the existing
cross-framework standard (CTRF JSON) at a stable path. The format is markdown-shaped plain text:
a one-line verdict first, failures grouped by root cause with the decisive frame and the native
assertion text, a rerun command per group, a delta against the previous run, and a short
sentinel-delimited index last so it survives head-and-tail truncation by the agent's tool. A
passing run is one line.

**Where the gap and the leverage are.** Java and Kotlin first, because nothing exists, the audience
is large, and the right vehicle (a Gradle plugin plus a JUnit Platform listener, and a Maven
extension) covers JUnit 4, JUnit 5, Kotest, TestNG, Spock and Kotlin Multiplatform at once. .NET
second, through a Microsoft.Testing.Platform extension and a VSTest logger. TypeScript third (Jest
has nothing; Vitest to make the format identical). Python fourth, as a thin plugin that reuses the
receptor's rules but emits the shared format. Swift last, as a CLI wrapper over Swift Testing's
JSON event stream. Section 7 has the phased plan; every phase is gated on a conformance corpus and
on an A/B agent benchmark, because the one rigorous pilot so far (Microsoft, October 2026) found
that a footer index *alone* saves little; the savings come from grouping, the decisive frame and
not re-running.

## 1. Phase 1: what exists today

### 1.1 Python

| Project | Version, date | What it does | Output | Verdict |
|---|---|---|---|---|
| `pytest-markdown-report` (ddaanet) | 0.2.0, 2026-07-15 | Replaces pytest's TerminalReporter with a markdown renderer. Default: summary line plus errors and failures with full traceback and assertion introspection in a fenced block; `-v` adds a passes list; `-q` prints the summary and a rerun command only; `-r` flags select sections; `--markdown-report=FILE` also writes a file. | Markdown: `# Test Report`, `**Summary:** 2/7 passed, 3 failed, 1 error, 1 skipped`, `## Failures`, `### test_validation.py::test_invalid_input[empty] FAILED`, fenced traceback | The one you remembered. Honest and minimal. No grouping, no delta, no truncation awareness, no injection hardening, claims "~40% fewer tokens than verbose markdown" without a published method. Unregisters pytest's reporter, which breaks plugins that look it up (the receptor's author hit exactly this). |
| `pytest-receptor` (uibcdf) | 1.2.2, 2026-10 | Opt-in `--receptor=llm` or `ci`. Verdict line with exit code and completeness; failures grouped by exception type, phase, crash location and cause chain; three occurrences named and the rest counted; rerun command per group; skip, warning and xfail reasons grouped; local frames kept, external frames pruned to entry and breaking frame; ANSI and control characters stripped, credential-shaped values redacted; progress to stderr once per 20%; full report to `.pytest_cache/d/receptor/last-run.txt`; byte-identical under xdist; `RECEPTOR_ERROR` degrade path; optional versioned JSONL event file; `--receptor-stats` measures tokens against your own configuration. | Plain text: `FAIL exit=1 \| 38 errors, 90 passed \| 12.40s \| 1 root cause`, then `[1] TypeError \| 38 tests \| setup`, location, message, test list, `rerun:` | The best-designed reporter in any language. Measured with tiktoken: a 38-failure cascade costs 105 tokens against 3,283 for plain pytest; a green 8,000-test suite 17 tokens against 812 for `pytest -q`. Its format is its own, not a cross-language one. |
| `pytest-md-report`, `pytest-github-report` | older | Markdown *tables* of outcomes for PR comments | Markdown table | Human and CI oriented, not agent oriented. |
| `faultline` | 2026 | Not a reporter: Claude Code hooks and an MCP server that, after a pytest failure, inject the deepest user-code frame, rerun the one failing test under a tracer and report runtime values of the failing versus a passing run. | JSON | One A/B on one real bug, 21 sessions a side: 29% fewer tokens per fixed bug, from fewer turns. The signal that matters is *runtime values along the failing path*, which is exactly what a narrative trace is. |

### 1.2 TypeScript and JavaScript

| Project | What it does | Verdict |
|---|---|---|
| Vitest 4.1 built-in `minimal` reporter, alias `agent` | Prints only failed files and failed tests with their errors; suppresses passing output, console logs of passing tests and the summary. Auto-selected when no `reporters` is configured and `std-env`'s `isAgent` is true. `AI_AGENT=<name>` forces it. | The only framework-shipped agent mode. Two open issues show the cost of silent auto-switching: a user's `--silent` is ignored under the agent reporter (#11266), and projects with a configured reporter get nothing unless they re-implement the detection (#10217). No grouping, no rerun hint, no index, no summary at all. |
| `vitest-llm-reporter` (hansjm10, 1.2.2) | Structured JSON: summary with counts, flaky and retried counts, environment; per failure the test, file, lines, suite path, error type and message, parsed stack frames tagged `inProject`, assertion expected/actual/operator, a numbered source-context window, captured console events, retry history. Token budget with truncation; log deduplication; framework-noise presets. | The richest *content* model in the field. The JSON envelope spends tokens on structure the agent does not need and is the wrong shape for a terminal; the content list is the right checklist. |
| Jest | Nothing agent-specific. Community advice: `summary` reporter with `summaryThreshold: 0`, `--silent`. | Jest is the largest TypeScript framework and has no solution. |
| `tdd-guard` reporters (Vitest, Jest, pytest, PHPUnit, Go, Rust, RSpec, Minitest) | Write `.claude/tdd-guard/data/test.json` for a Claude Code hook that enforces TDD. | A cross-framework *sidecar file* convention with a per-framework reporter. Proves the multi-framework reporter approach is practical. |
| `context-mode`, `RTK`, `agentfixer` | Wrappers that fold a command's output before the model reads it: passing tests collapse to one counted line, the full output is archived under an id. | Measured 17.0 KB to 1.2 KB on a 600-test `npm test`. Works on any runner but parses human output, so it is brittle and loses assertion detail. The source should emit the compact form itself. |

### 1.3 .NET

| Project | What it does | Verdict |
|---|---|---|
| microsoft/testfx RFC #8824, "Agent/LLM-efficient test output for Microsoft.Testing.Platform" (June 2026, open) | Umbrella: honour `NO_COLOR` (done), compress the banner in LLM mode (done), filter MTP/MSTest plumbing frames (closed, not planned), a JSON report extension (#8828, open), a compact end-of-run failure index (#8827, open), stable error codes, `--help --output json`. The .NET CLI already detects agents (`LLMEnvironmentDetectorForTelemetry`: `CLAUDECODE`, `CODEX_*`, `CURSOR_AGENT`, `GEMINI_CLI`, Copilot and others) and `dotnet test` turns ANSI off when it fires. | The one place with a measurement: a single-model pilot on eight synthetic scenarios found a footer index saved about 10% of initial-view tokens, an index-first layout cost 7% more, and on real output the index saved 0.6%. Maintainers kept the defaults and asked for evidence on clipped logs. Nothing has shipped. |
| `Microsoft.Testing.Extensions.CtrfReport` (experimental) | Writes CTRF JSON at session end. | Shows the extension mechanism we would use. |
| xUnit v3 runner reporters | `json` (one message per line), `quiet`, `silent`, `teamCity`, `verbose`; custom reporters via `[assembly: RegisterRunnerReporter(typeof(T))]`. | Mechanism exists, no agent reporter. |
| NUnit, TUnit | Nothing. NUnit reaches MTP through NUnit3TestAdapter 5.0 (`EnableNUnitRunner`). | |

### 1.4 Java, Kotlin, Swift

Nothing agent-specific was found for JUnit 4, JUnit 5, Gradle, Maven Surefire, Kotest, XCTest or Swift
Testing. The building blocks exist and are listed in section 6: JUnit Platform `TestExecutionListener`
(auto-registered through `META-INF/services`), Open Test Reporting XML and the legacy XML, Gradle's
`TestListener`, Surefire's `statelessTestsetInfoReporter` and `consoleOutputReporter` extensions,
Swift Testing's versioned JSON Lines event stream, XCTest's `XCTestObservation`, and
`xcresulttool get test-results tests` on Xcode 16.

### 1.5 Cross-framework interchange

**CTRF, Common Test Report Format** (spec 0.2.0, pre-1.0): a flat JSON report with `tool`, `summary`
(`tests, passed, failed, pending, skipped, other, start, stop`, optional `flaky, duration`) and a
flat `tests` array (`name, status, duration` required; `suite[], message, trace, snippet, line,
filePath, retries, retryAttempts, flaky, stdout[], stderr[], parameters, steps, extra`). Reporters
exist for Jest, Vitest, Mocha, Cypress, Playwright, WebdriverIO, pytest, .NET (MSTest, NUnit, xUnit,
and the MTP extension), Go, Rust, plus `junit-to-ctrf`. It is the right *file* format: it is already
cross-language, it has a `snippet` and an `ai` field, and an agent can query it with `jq`. It is the
wrong *console* format: the Microsoft pilot's CTRF-query arm saved 13.8% of initial-view tokens on
synthetic cases and lost an inner diagnostic that the terminal kept.

### 1.6 Facts about the reader that shape the design

- **The agent pays for output on every later turn.** Claude Code resends the whole conversation
  each request, so a verbose passing run keeps costing until compaction.
- **The agent's tool truncates, head and tail.** Claude Code's Bash tool keeps roughly the first
  and last part of a command's output and drops the middle, with a default cap reported as 30,000
  characters (`BASH_MAX_OUTPUT_LENGTH`; community-documented, with reports that the behaviour
  changed across versions and that a smaller inline preview applies in newer builds). Codex CLI's
  older TypeScript version capped at 10 KB or 256 lines, later raised to 100 KB or 1,024 lines, and
  the Rust CLI has a per-call token budget. Consequence: the verdict must be in the head, the index
  in the tail, and the renderer must clip the body itself rather than let the tool clip it.
- **The agent cannot scroll back but can open files.** Every reporter that works writes the full
  report to a known path and says so.
- **Agents detect themselves through environment variables**, and three independent lists agree
  (`std-env`, the .NET CLI, Aspire): `AI_AGENT` as an override, `CLAUDECODE`/`CLAUDE_CODE`,
  `CODEX_SANDBOX`/`CODEX_THREAD_ID`, `CURSOR_AGENT`, `GEMINI_CLI`, `COPILOT_AGENT`/`COPILOT_CLI`,
  `OPENCODE`, `AUGMENT_AGENT`, `GOOSE_PROVIDER`, `JUNIE_*`, `REPL_ID`.
- **Instructions in CLAUDE.md are not a guarantee.** Buffer's engineers found the agent did not
  always pass the reporter flag they asked for; switching the reporter from the environment in the
  config worked every time.

## 2. First principles: what an agent needs from a test run

This section was written before the survey, then checked against it. The agent's loop is edit, run,
read, decide. The output has one job: let the agent make the right next decision with the fewest
tokens read and the fewest reruns. In priority order it must answer:

1. **Did it pass, and can I trust the answer?** A verdict that distinguishes pass, fail, an error
   outside the tests (compile, collection, session fixture, runner crash), an incomplete run
   (fail-fast, interrupt, timeout, killed worker) and "no tests selected". An incomplete or
   empty run is never a pass. The exit code is printed, never inferred.
2. **What broke, where, and why**, grouped by cause rather than by test, because the costliest
   case in practice is one broken fixture failing forty tests. Per cause: the exception or
   assertion, the decisive user-code frame, the assertion library's own expected/actual text (the
   richest signal a framework produces; stripping it to save tokens makes the agent guess and
   loop), the chain of causes, and the frames that lead there with plumbing removed but external
   frames kept where the failure lives in a dependency.
3. **What to do next.** An exact rerun command for the failing subset, in the framework's own
   selection syntax, and the path of the full report.
4. **What changed since last run.** New failures, still-failing, fixed. A TDD loop lives on this
   and no reporter provides it; it costs one stored file.
5. **Anomalies that change the decision**: flaky (passed on retry), skip reasons (an undocumented
   skip is a finding), timeouts, captured output of failing tests only, capped.
6. **Nothing else by default.** No banner, no plugin list, no progress characters on stdout, no
   passing test names, no timings, no colour.

Properties of the text itself:

- **Verdict first, index last, nothing essential in the middle**, because the middle is what gets
  cut.
- **Line-oriented, labelled, ASCII-structured.** LLMs read `label: value` lines and fenced blocks
  reliably; JSON spends a third of its tokens on punctuation, nests, and needs escaping inside a
  terminal. Markdown headings and fences are nearly free and render for humans in a PR comment.
- **Bounded by variety, not by volume.** Lists are bounded by the number of distinct causes or
  reasons; occurrences are named up to a small N and counted beyond it.
- **Deterministic.** Same failures, same bytes, independent of worker scheduling. The agent and
  tooling can diff runs.
- **Unforgeable.** Test output cannot produce a line that reads as a verdict or a section header;
  ANSI and control characters are stripped; credential-shaped values are redacted.
- **Self-identifying.** The first line names the format and its version so hooks, skills and
  dashboards can detect it.
- **Safe to leave on.** Explicit configuration always wins over auto-detection; a reporter failure
  falls back to the framework's own output plus one line.

The survey confirmed every item and added two: the rerun hint and the "do not let `--tb=line`
destroy what you are summarising" caveat both come from the receptor, and the file sidecar
convention from tdd-guard and the receptor.

## 3. Lessons from the existing solutions

Keep:
- The receptor's grouping key (exception type, phase, crash location, cause chain; message
  excluded so a parametrised test is one bug), its truth rules (incomplete is never a pass; exit
  code from the framework), its frame policy (local frames kept, external pruned to entry and
  breaking frame, elisions marked), its safe-degradation path, its progress-on-stderr, its
  xdist determinism, and its measurement discipline (tokenise against *your* configuration).
- `vitest-llm-reporter`'s content checklist: assertion expected/actual/operator, source context
  with line numbers, project-versus-dependency frame tagging, retry history, console capture with
  deduplication and caps.
- Vitest's auto-detection with `AI_AGENT` override, and the explicit opt-out that it lacks.
- Microsoft's sentinel-delimited failure index (`##[failures]` … `##[/failures]`, one line per
  failure: name, first error line, `file:line`) as the tail block, and their finding that it is an
  index, not a substitute for the body.
- pytest-markdown-report's headings-and-fences shape, which is both agent-readable and renders.
- CTRF as the sidecar interchange format.

Avoid:
- Replacing the framework's reporter object (breaks other plugins; the receptor documents the
  exact failure with pytest-cov).
- Silent auto-switching that ignores the user's configured reporter or flags (Vitest #10217,
  #11266).
- JSON on stdout.
- An index without a body, or a body without an index.
- Withholding detail that only a rerun can recover ("nothing is reachable solely by running the
  suite again").
- Parsing human output after the fact (wrappers lose the assertion payload).

## 4. The Verdict format, version 1

### 4.1 Shape

Markdown-compatible plain text. Structural characters are ASCII only. Six parts, in this order:

```
<verdict line>          one line, always
<status lines>          run:, delta:, full:   (two to three lines)
<failure groups>        one block per root cause, biggest cascade first
<anomaly blocks>        skipped:, flaky:, warnings:   (only when present, bounded by variety)
<clip notice>           only when the renderer clipped the body
<index>                 ##[failures] ... ##[/failures], only when failures exist
```

Progress, when the run exceeds ten seconds, goes to **stderr** as at most five lines
(`tests: 40% 3733/9332 108s`), never to stdout.

### 4.2 Grammar

**Verdict line** (H1, so it is a heading for humans and a sentinel for tools):

```
# TESTS <VERDICT> | <counts> | <n> run | <duration> | verdict/1
```

`VERDICT` is one of `PASS`, `FAIL`, `ERROR` (failure outside tests), `INCOMPLETE` (stopped early),
`NO_TESTS`, `REPORTER_ERROR`. Counts list only non-zero outcomes from the vocabulary
`failed, error, passed, skipped, xfail, xpass, flaky, timeout`. Duration is wall time rounded to
0.1 s. `verdict/1` is the format marker and version.

**Status lines:**

```
run: <complete|stopped after N of M|interrupted|killed> | exit <code> | <framework> <version> | <k> root causes
delta: <n> new, <n> still failing, <n> fixed | vs <previous run id>
full: <path to .md> | <path to .ctrf.json>
```

`delta:` is omitted on a first run. `full:` is omitted when sidecars are disabled.

**Failure group** (H2; one per root cause; sorted by affected-test count descending, then by
location):

````
## [<i>/<k>] <ExceptionType> in <setup|test|teardown|collection|session> | <n> tests
<test id>                                   (one line per test when n <= 3)
tests: <id1> | <id2> | <id3> | +<n-3> more   (when n > 3)
at <path>:<line> in <symbol>                (the decisive frame: deepest user-code frame)
frames: <path>:<line> <symbol> -> ... -> <path>:<line> <symbol> (ext) -> ...   (elided plumbing shown as "...")
caused by: <ExceptionType>: <message>       (one line per cause in the chain, when any)
```<native assertion / message text, as the framework renders it, ANSI stripped>```
output: <stdout|stderr> last <n> of <m> lines
```<captured output of one representative failing test, capped>```
rerun: <framework-native command selecting exactly these tests>
````

**Anomaly blocks** (H2 each, bounded by number of distinct reasons, at most five lines each,
remainder in the file):

```
## skipped: <n> in <r> reasons
- <count> x <reason>
- <count> x (no reason declared)
## flaky: <n> passed on retry
- <test id> (attempt 2 of 3)
## warnings: <n> in <r> kinds
- <count> x <first line of warning>
```

**Clip notice**, only when the body budget (default 12,000 bytes, configurable) was exceeded:

```
clipped: <shown> of <k> root causes shown | full report: <path>
```

**Index** (last; one line per root cause, so it stays short even for a 200-test cascade):

```
##[failures]
[<i>] <ExceptionType> | <n> tests | <path>:<line> | <first line of message, <= 200 chars> | rerun: <command>
##[/failures]
```

A literal `|` inside a value is written `\|`. Any line of test-produced text that begins with `#`
or `##[` is prefixed with a space inside its fence. Fence length is one longer than the longest
backtick run in the content.

### 4.3 Examples

A green run is one or two lines:

```
# TESTS PASS | 93 passed, 3 skipped | 96 run | 4.2s | verdict/1
delta: 3 fixed | vs 2026-10-27T10:14Z
```

A single assertion failure (pytest):

````
# TESTS FAIL | 1 failed, 95 passed | 96 run | 4.4s | verdict/1
run: complete | exit 1 | pytest 9.1.1 | 1 root cause
delta: 1 new | vs 2026-10-27T10:14Z
full: .verdict/last-run.md | .verdict/last-run.ctrf.json

## [1/1] AssertionError in test | 1 test
tests/test_tax.py::test_rate[eu]
at tests/test_tax.py:42 in test_rate
```
    assert calculate_tax(100, region="eu") == 105.5
E   assert 105.0 == 105.5
E    +  where 105.0 = calculate_tax(100, region='eu')
```
rerun: pytest "tests/test_tax.py::test_rate[eu]"

##[failures]
[1] AssertionError | 1 tests | tests/test_tax.py:42 | assert 105.0 == 105.5 | rerun: pytest "tests/test_tax.py::test_rate[eu]"
##[/failures]
````

The same failure under JUnit 5 through Gradle differs only in the three native slots:

````
# TESTS FAIL | 1 failed, 95 passed | 96 run | 6.1s | verdict/1
run: complete | exit 1 | junit-platform 6.0.1 via gradle 9.2 | 1 root cause
full: build/verdict/last-run.md | build/verdict/last-run.ctrf.json

## [1/1] AssertionFailedError in test | 1 test
com.acme.tax.TaxCalculatorTest#rate(String)[eu]
at src/test/java/com/acme/tax/TaxCalculatorTest.java:42 in rate
```
expected: <105.5> but was: <105.0>
```
rerun: ./gradlew :tax:test --tests "com.acme.tax.TaxCalculatorTest.rate"

##[failures]
[1] AssertionFailedError | 1 tests | src/test/java/com/acme/tax/TaxCalculatorTest.java:42 | expected: <105.5> but was: <105.0> | rerun: ./gradlew :tax:test --tests "com.acme.tax.TaxCalculatorTest.rate"
##[/failures]
````

A cascade (one fixture, 38 tests), where grouping does the work:

````
# TESTS FAIL | 38 error, 90 passed | 128 run | 12.4s | verdict/1
run: complete | exit 1 | pytest 9.1.1 | 1 root cause
delta: 38 new | vs 2026-10-27T10:14Z
full: .verdict/last-run.md | .verdict/last-run.ctrf.json

## [1/1] TypeError in setup | 38 tests
tests: tests/test_merge.py::test_merge[0] | tests/test_merge.py::test_merge[1] | tests/test_merge.py::test_merge[2] | +35 more
at conftest.py:31 in db_connection
frames: tests/test_merge.py:12 test_merge -> conftest.py:31 db_connection
```
TypeError: 'NoneType' object is not subscriptable
```
rerun: pytest tests/test_merge.py

##[failures]
[1] TypeError | 38 tests | conftest.py:31 | 'NoneType' object is not subscriptable | rerun: pytest tests/test_merge.py
##[/failures]
````

An incomplete run is never a pass:

```
# TESTS INCOMPLETE | 12 passed | 12 of 128 run | 1.9s | verdict/1
run: stopped after first failure (-x) | exit 1 | pytest 9.1.1 | 1 root cause
...
```

### 4.4 Sidecar files

- `<dir>/last-run.ctrf.json`: CTRF 0.2 with every test, every attempt, full traces, captured
  output, and the groups under `extra.verdict.groups` (group id, member test ids, decisive frame,
  rerun command). This is what tools, hooks, dashboards and `jq` consume.
- `<dir>/last-run.md`: the unclipped console report with all tests listed (the review-agent view).
- `<dir>/previous-run.ctrf.json`: kept for the delta; rotated on each run.
- `<dir>` defaults per ecosystem (`.verdict/`, `build/verdict/`, `target/verdict/`,
  `TestResults/verdict/`); the reporter prints the path in `full:` and adds nothing to
  version control.

### 4.5 Activation

1. Explicit configuration or flag always wins (`--reporter verdict` / `-Pverdict` /
   `--logger verdict` / `--receptor`-style flag, per ecosystem).
2. Otherwise auto-enable when an agent environment is detected (the `std-env` list, `AI_AGENT`
   override) **and** the framework's reporter is at its default. When the user has configured a
   reporter, do not replace it: add the Verdict reporter after it and print one stderr line saying so.
3. `VERDICT=0` disables everything; `VERDICT=1` forces it for CI or humans.
4. Verbosity: `-v` equivalent adds the passing-test list; `-q` equivalent prints the verdict,
   status lines and index only.

### 4.6 What no existing reporter does

These are in the version 1 grammar because they are cheap and change the agent's next decision.
Each has a line of its own, so a port that cannot compute one simply omits the line.

| Feature | Where it appears | Rule |
|---|---|---|
| Delta against the previous run | `delta: 1 new, 1 still failing, 3 fixed` | Compare test identities (source location plus declared name) with `previous-run.ctrf.json`. Omitted on a first run. |
| Culprit hint from the working tree | `culprit: src/tax.py:40-48 (edited since last run, in the failing path)` on the status lines, and `culprit:` inside a group | Intersect `git diff` since the previous run with the frames of each group. Printed only when the intersection is non-empty; never guessed. |
| Silent shrinkage detection | `# TESTS PASS \| 40 passed \| 40 run (was 128: 88 missing) \| ...` | The run count fell against the previous run by more than a configurable share (default 10%) with no selection flag given. A broken import, a renamed file, a `describe.skip`, a missing test import all make tests vanish without an error. The verdict stays PASS; the warning is on the verdict line so it cannot be missed. |
| Build and compile failures in the same grammar | `# TESTS ERROR \| build failed \| ...` then `## [1/2] compile error \| 3 files` with `path:line: message` lines | Only the build-tool renderers (Gradle, Maven, `dotnet test`, `tsc` before Jest) can do this; a large share of agent test runs in compiled languages never reach the tests. |
| Self-clipping to a byte budget | `clipped: 4 of 9 root causes shown \| full report: <path>` | The renderer clips, so the agent's tool never cuts the middle silently. Default 12,000 bytes. |
| Exact pattern across variants | `pattern: actual = expected - 0.5 in 20 of 20 variants` inside a group | Only when expected and actual are structured values and the relation is exact for every variant. Never printed for a partial match. |
| Next-action hint for certain cases | `hint: setup-phase cascade, fix the fixture before the tests` | A closed list: setup cascade, collection or compile error, incomplete run (rerun without fail-fast before judging), shrinkage. No free-text advice. |
| Short flakiness memory | `flaky: test_x (failed 3 of last 10 runs)` | From the last N sidecars kept in the Verdict directory. |

The pattern and hint lines are the two that must earn their default through the A/B benchmark in
phase 0; the rest are reported facts.

## 5. One format across frameworks: identical, similar, or per-framework?

**Decision: identical grammar, native payload.** Everything structural is byte-identical across
Java, Kotlin, .NET, TypeScript, Python and Swift: the verdict line, status lines, section headers,
labels, ordering rules, caps, the index, the sidecar names, the activation rules, the outcome and
phase vocabularies. Three slots carry framework-native text, because normalising them would
destroy their value:

| Slot | Why native | Examples |
|---|---|---|
| Test id | It must paste into the framework's own selection syntax and match what the IDE shows | `tests/test_tax.py::test_rate[eu]`; `com.acme.TaxTest#rate(String)[eu]`; `Acme.Tax.TaxTests.Rate(region: "eu")`; `tax.test.ts > Tax > rate eu`; `TaxTests/rate(region:)` |
| Assertion or message text | The assertion library's rendering is the richest diagnostic the framework has (pytest introspection, AssertJ and Truth diffs, FluentAssertions, Jest's diff, Swift Testing's expanded `#expect` expression) | kept verbatim inside the fence, ANSI stripped |
| Rerun command | Must be the build tool's real invocation | `pytest "<id>"`; `./gradlew :mod:test --tests "<class>.<method>"`; `dotnet test --filter "FullyQualifiedName~<id>"`; `npx vitest run <file> -t "<name>"`; `swift test --filter "<id>"` |

What is normalised even though it is language-specific: the **frame list** (`path:line symbol`,
relative to the repository root, plumbing elided, dependency frames tagged `(ext)`), the
**phase** (`setup | test | teardown | collection | session`, mapping `@BeforeEach`, fixtures,
`beforeEach`, `[SetUp]`, `init()`), the **outcome vocabulary** (so `xfail` covers pytest's xfail,
JUnit's `@Disabled`-with-reason is `skipped`, Swift's known issue is `xfail`, a retry-then-pass is
`flaky` everywhere), and the **grouping key** (exception type, phase, decisive frame, cause
chain).

Why identical rather than merely similar:

- The agent learns one grammar. An agent moving between languages should not relearn test output.
- One skill, one CLAUDE.md paragraph, one hook, one parser, one dashboard, one GitHub Action
  comment renderer.
- Conformance can be tested mechanically: a polyglot "failure zoo" (section 7, phase 0) produces
  the same expected report in every language with the three native slots masked. Drift between
  ports becomes a failing test, the same way the rendering parity corpus works today.

Why not a single JSON schema on stdout: the Microsoft pilot, the receptor's measurements and the
token arithmetic all point the same way. JSON is the sidecar; text is the console.

Where identity is impossible and the spec says so: Gradle and Maven run tests in a forked JVM
whose stdout the build tool rewrites, so the Java and Kotlin console report is rendered by the build
plugin, not by the listener; `swift test` has no reporter API, so the Swift report is rendered by a
wrapper over the event stream; Bun has no custom reporter API at all and gets only the JUnit-XML
conversion path.

## 6. Per-framework analysis

The decisive engineering fact in every ecosystem is **where the text reaches the agent's stdout**.
A reporter inside the test process is only useful when the build tool relays its output
unchanged. Where it does not (Gradle, Maven, `swift test`, Xcode), the architecture is
*collector in the test process, renderer at the build-tool boundary*: the in-process listener
writes the evidence (full stack traces with assertion payloads, captured output, timings) to the
sidecar, and the build-tool plugin renders the console report from its own test events plus that
evidence.

### 6.1 Java: JUnit 5, JUnit 4, TestNG, Spock

| Layer | Extension point | Role |
|---|---|---|
| JUnit Platform (JUnit 5, Kotest, Spock 2, TestNG via engine, JUnit 4 via vintage) | `org.junit.platform.launcher.TestExecutionListener`, auto-registered through `META-INF/services`, deactivatable with `junit.platform.execution.listeners.deactivate`; `ReportEntry` for metadata; Open Test Reporting XML listener as precedent | **Collector.** Receives `TestIdentifier` with unique id, display name, source (`MethodSource` gives class, method, parameter types), tags, and `TestExecutionResult` with the `Throwable`. Writes the CTRF sidecar with full traces and the grouping key. Captured stdout/stderr through `junit.platform.output.capture.stdout`. |
| JUnit 4 standalone | `RunListener` via `JUnitCore.addListener`; Surefire's `listener` property for the junit4 provider | Only needed when JUnit 4 runs without the platform; otherwise vintage covers it. Lower priority. |
| Gradle `Test` task | `Test.addTestListener(TestListener)` (`beforeSuite/afterSuite/beforeTest/afterTest` with `TestDescriptor` and `TestResult.getExceptions()`), `addTestOutputListener`, `testLogging` to silence the default output, `TestEventReporter` in recent Gradle for custom report formats | **Renderer.** Engine-agnostic: sees JUnit 4, JUnit 5, TestNG, Kotest and Kotlin Multiplatform results through one API. A plugin `verdict` applies to every `Test` task, turns off Gradle's per-test logging, suppresses Gradle's own `FAILED` lines and "See the report at" pointer when active, renders the report at the end of the task, and in a multi-module build merges per-task reports into one at build finish (`--continue` aware). The rerun command is `./gradlew :mod:test --tests "<class>.<method>"`. Exceptions arriving in the build process are deserialised; when the exception class is not on the build classpath Gradle substitutes a placeholder, so the message and stack frames remain but the assertion payload must come from the sidecar written by the listener. |
| Maven Surefire and Failsafe (3.0.0-M4+) | `consoleOutputReporter` and `statelessTestsetInfoReporter` extensions in the plugin configuration (the `maven-surefire-junit5-tree-reporter` project is the template); `surefire.printSummary`, `trimStackTrace` | **Renderer.** Same split as Gradle: Surefire forks and relays test-set events to the Maven process, where the extension renders. Rerun: `mvn -pl mod test -Dtest="Class#method"`. |
| Plain console launcher | `java -jar junit-platform-console-standalone --details=none` plus the listener | The listener alone renders when it owns stdout (no build tool). |

Effort: listener S, Gradle plugin M, Maven extension M. Gradle is the first deliverable because
Gradle is what agents actually run in Java and Kotlin repositories.

### 6.2 Kotlin: JVM, Kotest, Multiplatform, Android

- **Kotlin/JVM with JUnit or Kotest**: fully covered by 6.1; Kotest runs on the JUnit Platform
  (`kotest-runner-junit5`), so the platform listener sees its specs and the Gradle plugin renders.
  Kotest's own `AfterProjectListener` in `ProjectConfig` (`io.kotest.provided.ProjectConfig` or
  `kotest.framework.config.fqn`) is available for Kotest-specific detail (nested test paths,
  `shouldBe` clue text) but is optional.
- **Kotlin Multiplatform (JS, Native, Wasm)**: the Gradle plugin receives those targets' results
  through Gradle's test-event protocol (TeamCity service messages from the JS and Native runners),
  so the console report covers every target. Assertion detail is limited to what those runners
  forward (message plus stack string); the grouping key degrades to type plus location.
- **Android unit tests**: `AndroidUnitTest` tasks are Gradle `Test` tasks; covered. Instrumented
  tests run on a device through a different task type and are out of scope for version 1.

Rerun commands are native: `./gradlew :mod:jvmTest --tests "..."`, `:mod:iosSimulatorArm64Test
--tests "..."`.

### 6.3 .NET: xUnit v2 and v3, NUnit, MSTest, TUnit

Two hosting models coexist and both must be served:

| Host | Extension point | Role |
|---|---|---|
| Microsoft.Testing.Platform (MTP: xUnit v3, MSTest 3.x+, TUnit, NUnit through NUnit3TestAdapter 5.0 with `EnableNUnitRunner`) | Extension package registering through the generated entry point's `TestingPlatformBuilderHook`; `IDataConsumer` for `TestNodeUpdateMessage` (node uid, display name, outcome properties with exception type, message, stack trace, `TestMethodIdentifierProperty`, `TestFileLocationProperty` for file and line), `ITestSessionLifetimeHandler` for session end, `IOutputDevice` for console. `Microsoft.Testing.Extensions.CtrfReport` is the template. The platform already detects agents through the .NET CLI's `LLMEnvironmentDetectorForTelemetry` and honours `NO_COLOR`, `--no-ansi`, `--no-progress`. | **Collector and renderer** in one, because the MTP executable owns stdout and `dotnet test` relays it. Rerun: `dotnet test --filter "FullyQualifiedName~<id>"` or MTP's `--filter-method`. Coordinate with testfx RFC #8824: our index block uses their proposed sentinel and line layout so a future first-party footer and ours are parse-compatible. |
| VSTest (`Microsoft.NET.Test.Sdk`: xUnit v2, NUnit with adapter 4.x, MSTest 2.x) | A test logger: a class with `[FriendlyName("verdict")]` and `[ExtensionUri(...)]` implementing `ITestLoggerWithParameters`, discovered from the test output directory the way `JunitXml.TestLogger` is, invoked as `dotnet test --logger verdict`; events `TestResult` (outcome, `ErrorMessage`, `ErrorStackTrace`, messages), `TestRunComplete`. | **Collector and renderer.** `dotnet test` prints its own summary and `Failed <name>` lines in this mode; the logger cannot remove them, so the report follows them and the documentation tells agents to prefer `--logger verdict -v q` (`--verbosity quiet` trims the host noise). |
| xUnit v3 runner reporter | `[assembly: RegisterRunnerReporter(typeof(AgentReporter))]`, `IRunnerReporter` | Alternative to the MTP extension for xUnit-only users; not needed for version 1 if the MTP extension exists. |

Effort: MTP extension M, VSTest logger M (shared renderer library S).

### 6.4 TypeScript and JavaScript: Jest, Vitest, Mocha, node:test, Playwright, Bun

| Framework | Extension point | Notes |
|---|---|---|
| Jest | `reporters: ['default', ['verdict-jest', opts]]`; class with `onRunStart`, `onTestResult(test, testResult, aggregated)`, `onRunComplete(contexts, results)`. `AssertionResult.failureMessages` are pre-rendered strings with ANSI; `failureDetails` carries `matcherResult` with `expected`, `actual`, `name` (not always present). | Nothing exists; largest user base. Strip ANSI, parse the stack from the message, prefer `failureDetails` for expected/actual. Replace the default reporter when active (`reporters` without `'default'`), otherwise Jest prints its own failures again. Rerun: `npx jest <file> -t "<name>"`. Snapshot failures get their own group kind. |
| Vitest (3 and 4) | `Reporter` interface: `onTestRunEnd(modules, unhandledErrors, reason)`, `TestCase.result().errors[]` with `message`, `stack`, `diff`, `expected`, `actual`, `stacks[]`; `TestCase.location`; retry history through `TestCase.result()` and `annotations`. Vitest 4.1 selects `minimal` when an agent is detected and no reporter is configured. | Ship as a reporter package and request upstream that `agent` alias accept a package name, so the format is identical with the built-in one over time. Rerun: `npx vitest run <file> -t "<name>"`. Coordinate with the `--silent` and configured-reporter issues. |
| Mocha | `--reporter verdict-mocha`; constructor `(runner, options)`, events `EVENT_TEST_FAIL(test, err)` with `err.expected`, `err.actual`, `err.showDiff`, `EVENT_RUN_END`. | Straightforward. Rerun: `npx mocha <file> -g "<name>"`. |
| node:test (Node 20+) | `--test-reporter=verdict-node-test --test-reporter-destination=stdout`; reporter is an async generator or stream over `test:fail`, `test:pass`, `test:diagnostic`, `test:summary` events; `event.data.details.error` carries the `AssertionError` with `expected`, `actual`, `operator`. | Cheap. Rerun: `node --test --test-name-pattern "<name>" <file>`. |
| Playwright | `Reporter` with `onTestEnd(test, result)`; `result.errors[]` have `message`, `stack`, `snippet`, `location`; retries and `status: 'flaky'` native. | Later phase; e2e output has attachments and traces to point at. |
| Bun test | No custom reporter API (only `--reporter=junit --reporter-outfile`; the Inspector protocol `TestReporter` domain is the only hook). | Convert the JUnit XML with the shared converter; coarse. Document the limitation. |

Effort: Jest M, Vitest S, Mocha S, node:test S, Playwright M, Bun S (converter only). One TypeScript
renderer package, framework adapters on top.

### 6.5 Python: pytest, unittest

| Framework | Extension point | Notes |
|---|---|---|
| pytest | `pytest11` entry point; hooks `pytest_addoption`, `pytest_configure`, `pytest_runtest_logreport`, `pytest_collectreport`, `pytest_warning_recorded`, `pytest_report_teststatus` (to swallow progress characters), `pytest_sessionfinish` (render; `pytest_terminal_summary` is not called on internal errors). Quieten the stock reporter through its options (`verbose = -2`, `no_header`, empty `reportchars`), never unregister it, and do not set `no_summary` (it swallows other plugins' summaries; pytest issue #14724). Keep `longrepr` intact (never force `--tb=line` or `--tb=no`). `report.longrepr.reprtraceback.reprentries` gives frames and the `E` lines; `report.when` gives the phase; `xdist` needs a total order before rendering. | Two plugins already exist. Decision in section 7: build the thin shared-format plugin, reusing the receptor's rules, and propose an `verdict` renderer upstream to pytest-receptor as the long-term home if its author is willing. Rerun: `pytest "<nodeid>"` or `--lf`. |
| unittest | No plugin mechanism in `python -m unittest`. `TestResult` subclass (`addFailure`, `addError`, `addSubTest`, `addSkip`, `addExpectedFailure`) passed through `TextTestRunner(resultclass=...)`, or a drop-in runner module `python -m agent_tests.unittest <args>` that wraps `unittest.main`. | Small; mostly for Django-style suites (Django's test runner accepts a custom `--testrunner`). |

Effort: pytest M (or S if contributed upstream), unittest S.

### 6.6 Swift: Swift Testing, XCTest, Xcode

| Runner | Extension point | Notes |
|---|---|---|
| Swift Testing (SwiftPM) | No reporter API. A versioned JSON Lines **event stream** written by the test executable: records `kind: test` (name, display name, `sourceLocation`, id, parameterised flag, tags, bugs) and `kind: event` (`runStarted`, `testStarted`, `issueRecorded` with `issue.expression.sourceCode` and expanded runtime `value`s, `severity`, `isKnown`, `testCaseEnded`, `testSkipped`, `runEnded`). Enabled by the experimental flags `--experimental-event-stream-output <path>` and `--experimental-event-stream-version <ver>`, which `swift test` passes through to the executable. Console output is explicitly declared not machine-readable. | **Wrapper CLI** (`verdict-swift`, the xcbeautify shape): runs `swift test` with the event stream pointed at a FIFO, renders the report, writes the sidecar. The expanded `#expect` expression is the native assertion slot and is richer than any other framework's. Rerun: `swift test --filter "<suite>/<test>"`. |
| XCTest (SwiftPM) | `XCTestObservation` registered with `XCTestObservationCenter.shared.addTestObserver` from a principal class or at first load; or `swift test --xunit-output file.xml` (coarse: message only). | Observer in-process for detail, XML for fallback. The wrapper handles both. |
| Xcode (`xcodebuild test`) | `-resultBundlePath x.xcresult` then `xcrun xcresulttool get test-results tests --path x.xcresult` (JSON, Xcode 16+; the legacy format needs `--legacy`). | The wrapper renders from the result bundle after the run. Rerun: `xcodebuild test -only-testing:<target>/<class>/<method>`. |

Effort: wrapper M (event stream), XCTest observer S, xcresult adapter S.

### 6.7 Go and Rust (out of the asked scope, recorded for later)

Go: `go test -json` is a complete event stream; `gotestsum` is the wrapper precedent; a `go test
-json | verdict-go` filter is S. Rust: libtest's `--format json` is unstable; `cargo nextest`
has a machine-readable output and a reporter hook; tdd-guard's Rust reporter is a pass-through
filter over libtest JSON. Both fit the wrapper shape.

## 7. Implementation plan

Sequencing by gap times audience, with these rules applied: a specification before
code, a corpus that every port replays, the JVM implementation as the reference, measurement before claims.

### 7.0 Repository map: one project per framework

Verdict is a family of small repositories under one GitHub organisation, the way its runtime
cousins are organised. Each framework integration is its own project with its own release cadence,
because framework reporter APIs change on their own schedules and a user installs exactly one.
Where the integration point is the host rather than the framework (Gradle and Maven run every JVM
framework; Microsoft.Testing.Platform and VSTest run every .NET framework; `swift test` and
`xcodebuild` run both Swift frameworks), the repository is named after the host.

| Repository | Contents | Phase |
|---|---|---|
| `.github` | Organisation profile, this report, security policy | 0 |
| `verdict-spec` | The normative format specification, the polyglot failure zoo, the golden reports, the conformance kit, the token benchmark and the A/B protocol | 0 |
| `verdict-jvm` | Shared JVM renderer and CTRF writer (library, no user-facing surface) | 1 |
| `verdict-junit` | JUnit Platform listener: collector for JUnit 5, JUnit 4 via vintage, Kotest, Spock, TestNG engine; renders alone under the console launcher | 1 |
| `verdict-gradle` | Gradle plugin: renderer for every `Test` task, multi-module merge, Kotlin Multiplatform and Android unit tests, compile-failure rendering | 1 |
| `verdict-maven` | Surefire and Failsafe extension: renderer | 1 |
| `verdict-kotest` | Optional Kotest project extension for nested paths and clue text | 1, later |
| `verdict-dotnet` | Shared .NET renderer and CTRF writer | 2 |
| `verdict-mtp` | Microsoft.Testing.Platform extension: xUnit v3, MSTest, TUnit, NUnit through adapter 5 | 2 |
| `verdict-vstest` | VSTest logger: xUnit v2, NUnit, MSTest under `Microsoft.NET.Test.Sdk` | 2 |
| `verdict-js` | Shared JavaScript and TypeScript renderer and CTRF writer | 3 |
| `verdict-jest` | Jest reporter | 3 |
| `verdict-vitest` | Vitest reporter | 3 |
| `verdict-node-test` | `node:test` reporter | 3 |
| `verdict-mocha` | Mocha reporter | 3 |
| `verdict-playwright` | Playwright reporter | 3, later |
| `verdict-python` | Shared Python renderer and CTRF writer | 4 |
| `verdict-pytest` | pytest plugin (or an upstream renderer contribution, see phase 4) | 4 |
| `verdict-unittest` | unittest runner module | 4 |
| `verdict-swift` | Wrapper CLI over the Swift Testing event stream, XCTest observer, xcresult adapter | 5 |
| `verdict-agent` | CLAUDE.md and AGENTS.md snippets, the skill, the PreToolUse hook, the GitHub Action comment step, the optional MCP tool | 6 |
| `verdict-go`, `verdict-rust` | Wrappers over `go test -json` and nextest output | later |

Package coordinates follow the repository names: `pytest-verdict` on PyPI, `verdict-jest` and
friends on npm, `io.verdict` on Maven Central and the Gradle Plugin Portal, `Verdict.*` on NuGet.
Licensing is an open question in section 8; the proposal is a permissive licence for the
specification and the corpus so framework maintainers can adopt the format freely.

### Phase 0: specification and conformance corpus

- Write the format specification as a normative document with the grammar in section 4, the
  vocabularies, the ordering and cap rules, the escaping rules, and the activation rules.
- Build the **failure zoo**: one small project per ecosystem with the same twenty scenarios
  (single assertion with diff, exception with cause chain, setup cascade over many tests,
  parametrised test failing on some inputs, teardown failure, skipped with and without reason,
  expected failure, unexpected pass, flaky on retry, timeout, collection or compile error,
  fail-fast stop, interrupted run, no tests selected, failing test printing 500 lines, output that
  tries to forge a verdict line and contains ANSI and backticks, a secret-shaped value in an
  assertion, nested suites, a failure inside a dependency, an all-green run).
- Write the **golden reports** once, by hand, with the three native slots as placeholders; the
  conformance test for every port renders the zoo and compares with the slots masked.
- Write the **token benchmark**: tokenise (cl100k and Claude's tokenizer) the framework's default
  output, its best hand-tuned flags, and Verdict, for every scenario; publish the table the way
  the receptor does.
- Write the **A/B agent benchmark protocol** on the existing benchmark harness: tasks that start
  from a failing suite, baseline reporter versus Verdict, measuring tokens, turns,
  reruns and fix rate. This is the gate every later phase must pass, because the only rigorous
  pilot to date found the footer alone is not worth much; the hypothesis to test is grouping plus
  decisive frame plus rerun plus delta.
- Publish the specification under the name Verdict; `verdict/1` is the format marker.

### Phase 1: Java and Kotlin (reference implementation)

1. JUnit Platform listener (collector, CTRF sidecar with groups).
2. Gradle plugin (renderer, multi-module merge, activation from environment, `--tests` rerun).
3. Maven Surefire and Failsafe extension (renderer).
4. Console-launcher mode (listener renders alone).
5. Verify on Kotest, TestNG, Spock, a Kotlin Multiplatform project and an Android unit-test module.
6. Gate: conformance corpus green, token table, A/B benchmark delta reported honestly.

### Phase 2: .NET

1. Shared renderer library.
2. MTP extension (xUnit v3, MSTest, TUnit, NUnit via adapter 5.0).
3. VSTest logger (xUnit v2, NUnit 4.x adapter, MSTest 2.x).
4. Align the index block with testfx #8827 and comment on the RFC with the measurements.
5. Gate as above.

### Phase 3: TypeScript and JavaScript

1. Shared renderer package.
2. Jest reporter, Vitest reporter, node:test reporter, Mocha reporter.
3. Propose to Vitest that the built-in `agent` reporter adopt the format or accept a package name.
4. Playwright reporter; Bun through JUnit XML conversion.
5. Gate as above.

### Phase 4: Python

1. Thin pytest plugin emitting the shared format, with the receptor's rules (grouping key,
   completeness, frame policy, untrusted output, stderr progress, xdist order) reimplemented or,
   preferably, contributed upstream as a renderer so one plugin serves both formats. Open the
   conversation with the receptor's author before writing code.
2. unittest runner module.
3. Gate as above.

### Phase 5: Swift

1. Wrapper CLI over the Swift Testing event stream.
2. XCTest observer and `--xunit-output` fallback.
3. xcresult adapter for `xcodebuild`.
4. Gate as above.

### Phase 6: agent-side integration

- A one-paragraph CLAUDE.md and AGENTS.md snippet per ecosystem, and a skill that teaches the
  grammar once ("read the first line; if FAIL, read groups in order; use `rerun:`; open `full:`
  only when a group is clipped").
- A PreToolUse hook that rewrites bare `pytest`, `./gradlew test`, `dotnet test`, `npm test` to
  the Verdict form when the project has the reporter installed and the environment is an agent.
- A GitHub Action step that posts `last-run.md` as a PR comment (the markdown shape is why).
- Optionally an MCP `run_tests` tool that returns the report and exposes `full:` for drill-down.

### Optional `trace:` block

The failure group has room for one more optional block, `trace:`, the execution path of the
failing test with the values that flowed through it, supplied by whatever tracer the project uses
(a narrative tracer, a coverage-guided rerun, a debugger script). That is the "why" layer no
reporter supplies and the one faultline's measurement says pays off (fewer turns, not fewer bytes
per turn). The slot is defined by the specification; no tracer is required, and the format's value
stands without it.

## 8. Risks and open questions

- **The savings claim must be earned.** The receptor's numbers are per-run tokens; faultline's are
  per-fixed-bug tokens; Microsoft's pilot is initial-view tokens and found little from an index
  alone. The A/B benchmark in phase 0 is the only answer that matters, and it may show that
  grouping and delta matter and the index does not. The format is designed so each part can be
  dropped by the measurement.
- **Build-tool rendering is the hard part in Java and Kotlin.** Gradle's deserialised exceptions
  lose the assertion payload when the class is not on the build classpath; the sidecar written by
  the in-JVM listener closes that gap but requires both halves to be installed. The plugin should
  add the listener to the test runtime classpath itself.
- **Auto-activation is a trust question.** Vitest's experience says: never override a configured
  reporter silently, and always provide an off switch. The spec does both.
- **Test ids are not stable across frameworks or even versions** (display names, parameter
  rendering). The sidecar keeps a `testId` derived from source location plus declared name for
  the delta; the console uses the native id for the rerun.
- **Secret redaction is a net, not a boundary.** Say so in the documentation, as the receptor does.
- **Naming and licensing**: pick a product name; keep the specification and the corpus under a
  permissive licence so framework maintainers can adopt the format, whatever the implementation
  licence is.
- **Upstream conversations to open before code**: pytest-receptor (renderer contribution), Vitest
  (`agent` reporter alias), microsoft/testfx (index block compatibility), JUnit (a mention in the
  reporting docs once it exists).

## 9. Sources

- pytest-markdown-report: https://github.com/ddaanet/pytest-markdown-report and https://pypi.org/project/pytest-markdown-report/
- pytest-receptor: https://github.com/uibcdf/pytest-receptor and https://pypi.org/project/pytest-receptor/
- faultline: https://github.com/dingdongkkk/faultline
- vitest-llm-reporter: https://github.com/hansjm10/vitest-llm-reporter
- Vitest 4.1 release notes (agent reporter): https://vitest.dev/blog/vitest-4-1.html ; reporters guide: https://vitest.dev/guide/reporters ; issues #10217, #11266
- std-env agent detection list: https://github.com/unjs/std-env (src/agents.ts)
- Microsoft testfx RFC #8824: https://github.com/microsoft/testfx/issues/8824 ; failure index #8827: https://github.com/microsoft/testfx/issues/8827 ; JSON report #8828
- Microsoft.Testing.Extensions.CtrfReport: https://nuget.org/packages/Microsoft.Testing.Extensions.CtrfReport
- .NET CLI LLM environment detector: https://source.dot.net/dotnet/Telemetry/ILLMEnvironmentDetector.cs.html ; dotnet/sdk PR #54659
- NUnit and Microsoft.Testing.Platform: https://docs.nunit.org/articles/vs-test-adapter/NUnit-And-Microsoft-Test-Platform.html
- xUnit v3 custom runner reporters: https://xunit.net/docs/getting-started/v3/custom-runner-reporter
- CTRF specification: https://github.com/ctrf-io/ctrf/blob/main/spec/ctrf.md and https://ctrf.io/docs/specification/overview
- JUnit Platform reporting: https://docs.junit.org/6.2.0/advanced-topics/junit-platform-reporting.html
- Maven Surefire extensions API: https://maven.apache.org/surefire/surefire-extensions-api/ ; template: https://github.com/fabriciorby/maven-surefire-junit5-tree-reporter
- Kotest project config and extensions: https://kotest.io/docs/6.1/framework/project-config.html
- Swift Testing JSON event stream: https://github.com/swiftlang/swift-testing/blob/main/Documentation/ABI/JSON.md ; SwiftPM pass-through of experimental event-stream flags (swift-package-manager #7564)
- xcresulttool on Xcode 16: https://developer.apple.com/forums/thread/763050
- Bun test reporters: https://bun.sh/docs/test/reporters
- tdd-guard: https://github.com/nizos/tdd-guard
- context-mode failing-test use case: https://context-mode.com/use-cases/failing-test-output
- "Your Test Output Is Burning Tokens" (Buffer, Jest and Vitest reporter switching): https://magarcia.io/your-test-output-is-burning-tokens/
- "9 Flags That Cut the Output It Reads": https://dev.to/gabrielanhaia/your-test-run-floods-the-agents-context-9-flags-that-cut-the-output-it-reads-1f59
- Claude Code Bash output limits (community-documented): https://github.com/anthropics/claude-code/issues/19901
