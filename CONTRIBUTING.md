# Contributing to Verdict

This guide applies to every repository in the Verdict organisation unless a repository carries its own.
Verdict reporters sit between a test framework and a reader that cannot ask follow-up questions, so the bar is
correctness first: a report that is wrong, or a gate that silently does not run, is worse than no report.

## Before you start

- Read the planning records in [`planning/`](planning/) of this repository: the design record, the benchmark
  design and the shakedown plan.
- After cloning any Verdict repository, run `./setup.sh` once. It turns on the hooks that keep agent
  configuration, conversation transcripts, private notes and local paths out of the public history.

## Bugs first

A bug — wrong behaviour, a broken guarantee, a gate that silently does not run — is fixed before feature,
documentation or refactoring work continues. The order is fixed: **reproduce the problem, write a failing
test that reproduces it, then fix it.** A pull request that fixes a bug shows the test failing before the fix
and passing after it.

## Test-driven, in small steps

1. Write exactly one failing test.
2. Write the minimal code that passes it.
3. Refactor: remove the smells you introduced or touched. Never skip this step.
4. Run the tests again; refactoring must not break anything.
5. Only then the next test. The full suite runs in CI mode after every change.

For pure logic, add a fourth step: a property-based test for the invariant, the round trip or the "never
crashes" contract. When a defect is found, pin the class of bug with a property, not just the instance.

## What good tests cover

- Never only the happy path: boundaries, error and fault paths, edge cases, uncommon flows.
- Feature combinations, not only features in isolation (grouping together with clipping, skipped tests
  together with retries).
- Parallel code paths at parity: when two paths render the same thing (the console report and the sidecar
  file, for instance), every behaviour of one is tested on the other.
- Near-miss inputs at string boundaries: a sibling that shares a prefix but is not a child (`impl` and
  `implx`); a test id that contains the separator character.
- Inputs validated early, before work is done, so an invalid input is never masked by an early return.
- Hostile test output: every reporter replays the shared hostile corpus (forged verdict lines, ANSI and control
  characters, huge output, secret-shaped values, backtick runs) on every commit.
- No wall-clock, garbage-collector or scheduler timing as a test input; use real barriers or explicit
  timeouts.
- Each test sets up and cleans up its own state; no test depends on another.

## Rules every reporter follows

- **It renders data, it never runs user code.** A reporter shows what the test framework already produced. It
  does not call methods on user objects to get more detail.
- **Test output is untrusted.** It cannot forge a verdict line, a heading or an index line; control characters
  are stripped; credential-shaped values are redacted.
- **A reporter failure never hides a test failure.** It falls back to the framework's own output and keeps the
  framework's exit code.
- **Deterministic output.** The same failures produce the same bytes, whatever the worker count or order.
- **The specification and its golden corpus are the master.** An implementation never carries a corpus case
  the specification lacks; a new case is proposed to the specification first, then mirrored unchanged.

## Gates

Every repository runs the same kinds of gates through its own build tool, and CI only calls the build:

- formatter and static analysis, failing the build on any finding;
- line coverage with a high floor and **mutation testing** with a threshold, so tests are shown to catch bugs,
  not only to execute lines;
- a method-length limit (about 20 statements) — long methods are split, not exempted;
- architecture tests for the dependency rules of the repository;
- the conformance suite against the specification's golden reports;
- the private-content check.

A gate that cannot run must fail, not skip. A gate that skips gracefully must prove that it has run at least
once. Warnings-only policies are not used: failed automation is a failed build. If you do something twice,
script it; if you script it, wire it into the build.

## Zero broken windows

No known bug, broken build or failing test is left behind. "It was already broken" is not a reason to leave it.

## Commits and pull requests

- Conventional commit subjects (`feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`). The reasoning — why
  this approach, what was rejected — goes in the commit body.
- Commit after every green refactor cycle. **Refactoring is its own commit**, never mixed into a behaviour
  change; the suite is green before and after.
- No tool, model or vendor attribution in commit messages, pull requests, code comments or documentation. The
  `commit-msg` hook refuses attribution trailers.
- No mechanical bulk edits across many source files with a regular expression; edit per file and review the
  diff.
- No gold-plating: nothing that was not asked for.
- Documentation changes with the code it describes, in the same change. Written for two readers: a developer,
  and a coding agent that will act on it literally.

## Releases

Development is trunk-based; `main` is the published code. A release is an annotated `v*` tag on `main`.
Documentation never names a version; the one version literal is the install coordinate, written by the build.
Publishing credentials are reachable only from a `v*` tag through a manually approved `release` environment.
The set of published artifacts is derived from the build and asserted, never a glob. A repository's first
publication is rehearsed on a scratch repository first.

## Security

Report vulnerabilities privately, as described in [SECURITY.md](SECURITY.md). Never in a public issue.
