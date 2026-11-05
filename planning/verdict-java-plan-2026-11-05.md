# Verdict for Java: the plan

Plan, 2026-11-05. It takes over from section 4 of the design record for the console format and from
phase 1 of its implementation plan for the order of work. Everything else in the design record still
holds: the per-framework analysis (section 6.1), the safety rules, activation, the sidecar.

## Status

| Step | State | Notes |
|---|---|---|
| J0, this plan and the format draft | **done** | Decided 2026-11-05: the library is built first, from the format the Python tuning rounds produced, and benchmarked from its real output. |
| J1, specification and Java zoo | not started | `verdict-spec` |
| J2, core renderer | not started | `verdict-jvm` |
| J3, JUnit Platform listener | not started | `verdict-junit` |
| J4, Gradle plugin | not started | `verdict-gradle` |
| J5, Java benchmark | not started | `verdict-bench`, corpus `java` |
| J6, Maven extension | later | `verdict-maven` |

## 1. Decisions of 2026-11-05

1. **Java is the most important benchmark.** The Python rounds (shakedown, never cited) said which edits to
   a plain report help; the Java result is the one the project is judged by.
2. **Library first, benchmark second.** One pass of format tuning has been done on Python; the format below
   carries its result. The Java benchmark measures the output of the real library under Gradle, not a
   renderer inside the benchmark. Because a feature can still lose, two rules keep iteration cheap:
   - **Every feature is a switch** in the core renderer (`dedupe`, `rerun`, `delta`, `clip`), on or off from
     the plugin's configuration. An ablation is a flag, not a code change.
   - **The listener always writes the full evidence** to a sidecar file, and the core renders from that
     file through a small command-line entry point. The benchmark captures each item once under Gradle and
     renders every arm from the sidecar; a parity test asserts that the command-line render equals the
     plugin's console output on every item.
3. **The format is the tuned plain report, not the grouped design.** In the Python rounds the grouped
   design of the design record (section 4) lost: groups that share a crash site were read as root causes,
   and one bug failing 37 tests read as 37 causes. Every feature that grouped or summarised failures lost
   too (`md-places`, `md-shared`, `md-line`, `md-line-loc`); `pytest-receptor`, which groups, lost the cause
   count by 56 points. Section 2 is the format; grouping, the root-cause count and the index are withdrawn
   until a measurement brings any of them back.
4. **JUnit Platform first, Gradle as the host.** One `TestExecutionListener` covers JUnit Jupiter (JUnit 5
   and 6), JUnit 4 through the vintage engine, TestNG, Spock and Kotest. Agents run tests through
   `./gradlew test`, and Gradle runs the tests in a forked JVM whose output it does not relay, so the
   listener collects and the Gradle plugin renders (design record, section 6). Maven follows.
5. **Core plus adapters**, as in the repository map of the design record (section 7.0): a shared renderer
   with no user-facing surface, and one project per framework or host.

## 2. The format, version 1 (draft for `verdict-spec`)

Markdown-shaped plain text, the shape of the Python baseline that scored best, with the two features the
Python rounds kept and the Java slots filled natively.

````
# Test Report

**Summary:** 1204/1212 passed, 8 failed
**Delta:** 1 new, 7 still failing, 2 fixed (vs previous run)

## Failures

### com.acme.tax.TaxTest.rateForRegion [1] region=eu FAILED

```
org.opentest4j.AssertionFailedError: expected: <0.19> but was: <0.2>
	at com.acme.tax.TaxCalculator.rate(TaxCalculator.java:88)
	at com.acme.tax.TaxTest.rateForRegion(TaxTest.java:42)
```

### com.acme.tax.TaxTest.rateForRegion [2] region=uk FAILED

```
org.opentest4j.AssertionFailedError: expected: <0.19> but was: <0.2>
… same error as `com.acme.tax.TaxTest.rateForRegion [1] region=eu`
```

**Rerun:** all failed `./gradlew :tax:test --tests "com.acme.tax.TaxTest.rateForRegion"` · one test `./gradlew :tax:test --tests "<class>.<method>"`
````

The example is a sketch; the specification and its golden reports fix every byte.

**What each part does.**

- **Summary first.** Passed of run, then the non-zero outcomes (`failed`, `skipped`, `aborted`). A run that
  stopped early or selected no tests says so on this line. A passing run is the heading and this line.
- **Delta** (switch `delta`, on). Compared with the previous run's sidecar by test identity: new, still
  failing, fixed. Omitted on a first run. When the selection differs from the previous run's, it says
  `(1 of 128 selected)` and never counts unselected tests as fixed. A drop in the number of tests run of
  more than 10% without a selection filter is reported on this line (silent shrinkage).
- **One section per failing test**, in the order the framework reports them. The heading is the test's
  filter-ready name (`<class>.<method>`, which `--tests` accepts), then the display name of a parameterised
  invocation, then `FAILED`. A failure outside a test (`@BeforeAll`, a class initialiser, an engine error)
  gets a section headed by its container, so it is never lost.
- **The trace, in Java's own shape.** The exception line exactly as the framework produced it (the native
  assertion text: JUnit, AssertJ, Hamcrest, Truth messages and diffs verbatim, ANSI stripped). Then the
  frames, pruned:
  - keep the throw site (the first frame), every project frame, and the first frame of each
    `Caused by:` link with its project frames;
  - replace each run of other frames with `... <n> frames`;
  - drop everything below the test method (runner plumbing) with no marker;
  - a frame is a project frame when its class was loaded from the build's own output directories, not
    from a jar; a fixed list of plumbing packages (`org.junit`, `org.opentest4j`, `org.gradle`,
    `java.lang.reflect`, `jdk.internal`, `sun.reflect`) is never project code.
- **Repeats shown once** (switch `dedupe`, on). A failure whose exception line and first project frame equal
  an earlier one keeps its heading and exception line, then points to the first. This cut about 21% of the
  tokens in Python at an understanding cost inside noise.
- **Rerun line last** (switch `rerun`, on). Gradle has no "rerun last failed", so the line names the failing
  methods (`--tests` once per method, per class when more than ten methods fail) and gives the one-test
  form. In Python this line raised the right rerun command by about 30 points.
- **Clip** (switch `clip`, off until measured). Over a byte budget the renderer keeps whole sections and
  ends with `**Clipped:** <shown> of <n> failures shown | full report: <path>`. The Python clip condition
  hinted that a shorter report loses more to the agent's own cut; whether self-clipping helps is a
  Java benchmark question.
- **Sidecar files** under `build/verdict/` (design record, section 4.4): `last-run.ctrf.json` (CTRF with full
  traces and every test), `last-run.md` (the unclipped report), `previous-run.ctrf.json` for the delta.
  The full path is printed only when the report was clipped.

**What it never does**: name a root cause, count causes, group failures, collapse a failure to one line,
print one shared location for several failures, call `toString`, `equals` or accessors on user objects, or
change the exit code.

**Untested ideas kept for the benchmark**: captured standard output of a failing test (last lines),
compile errors in the same format, the culprit hint from the working tree, a next-action hint.

## 3. How it behaves

**Activation.** In order: an explicit setting wins (`-Pverdict=true|false`, or `VERDICT=1|0` in the
environment); otherwise the plugin switches on when an agent is detected from the environment variables
that agents set (`AI_AGENT`, `CLAUDECODE`, `CLAUDE_CODE`, `CODEX_*`, `CURSOR_AGENT`, `GEMINI_CLI` and the
rest of the `std-env` list); otherwise it stays off and Gradle's output is untouched. It never replaces a
test logging configuration the user wrote: it adds its report after it and prints one line saying so. That
the variable reaches the Gradle daemon and the forked test JVM is verified by a functional test, not
assumed.

**IDEs.** A human's run sees nothing new, because nothing switches on without an agent or an explicit
setting. IntelliJ builds its test tree from Gradle's structured test events, which the plugin does not
touch; the HTML and XML reports stay as they are.

**Gradle.** The listener is added to the test runtime classpath by the plugin and writes the sidecar from
inside the test JVM; the plugin renders when the `Test` task ends and quiets Gradle's per-test lines only
while active. The build fails exactly as before: the task's result and the exit code are Gradle's. A task
skipped as up to date prints one line (`tests up to date, nothing ran; last run passed`) so the agent never
sees silence. Several test tasks in one build (modules, `--continue`) are merged into one report at build
end. The plugin is compatible with the configuration cache.

**Direct runs.** Under the JUnit console launcher, where the listener owns standard output, it renders the
report itself.

**Failure of the reporter.** Any exception inside the listener or the plugin falls back to Gradle's own
output plus one line `verdict: reporter error, see build/verdict/reporter-error.txt`; the exit code is
untouched.

## 4. Repositories and build

| Repository | Contents | Depends on |
|---|---|---|
| `verdict-spec` | The normative format specification, the Java zoo (twenty scenarios as one Gradle project), the golden reports written by hand, the hostile corpus | nothing |
| `verdict-jvm` | Core: the model, the CTRF reader and writer, frame pruning, sanitising, dedupe, rerun and delta, the renderer with its switches, the command-line render entry point | nothing at run time |
| `verdict-junit` | JUnit Platform listener: collector, sidecar writer, console mode | `verdict-jvm`, `junit-platform-launcher` (provided) |
| `verdict-gradle` | Gradle plugin: activation, classpath wiring, rendering, merge, up-to-date line | `verdict-jvm` |

- Java 17 bytecode (`--release 17`) for everything that runs in the test JVM, so a project on Java 17 or
  later can load it; JUnit 6 and Gradle 9 have the same floor. Whether Java 11 projects must be served is
  an open question (section 7).
- No runtime dependency in `verdict-jvm` and `verdict-junit` beyond the JUnit Platform they plug into: the
  listener runs on the user's test classpath, where any library can conflict. JSON is read and written by a
  small internal codec, tested against the CTRF schema.
- During development the repositories are siblings joined by Gradle composite builds (`includeBuild`); each
  builds and tests on its own in CI.
- Tests first, as in the contributing guide: JUnit Jupiter for unit tests, jqwik for properties (sanitising
  never lets a forged heading through, rendering is deterministic under any order), Gradle TestKit for the
  plugin's functional tests, and the conformance test that renders the zoo and compares with the goldens.
- Every repository gets the organisation's guard hooks and the `private-check` CI job in its first commit,
  and `SECURITY.md` before its first publication.

## 5. Steps and exit criteria

### J1 Specification and Java zoo (`verdict-spec`)
- The format of section 2 as a normative document: grammar, frame-pruning rule, dedupe key, rerun
  forms, delta rules, escaping and redaction, switches.
- The Java zoo: one Gradle project with JUnit Jupiter, twenty scenarios mirroring the Python zoo (single
  assertion with diff, exception with cause chain, setup cascade, parameterised partial failure, teardown
  failure, skipped with and without reason, aborted assumption, disabled, `@BeforeAll` failure, timeout,
  fail-fast, interrupted, no tests selected, a test printing 500 lines, hostile output forging a heading
  with ANSI and backticks, a secret-shaped value, nested classes, a failure inside a dependency, an
  all-green run, a delta pair: the same project before and after a fix).
- Golden reports written by hand from the specification and the scenarios' real stack traces, before any
  renderer exists.
- **Exit:** every scenario runs under Gradle with the expected outcome; every golden reviewed against the
  specification; the hostile corpus listed.

### J2 Core renderer (`verdict-jvm`)
- The model and the CTRF codec; frame pruning; sanitising; dedupe; rerun; delta; the renderer with its
  switches; the command-line render entry point.
- **Exit:** the zoo's goldens reproduced byte for byte from hand-built evidence; every switch has tests on
  and off; properties for determinism and forgery; no runtime dependency.

### J3 JUnit Platform listener (`verdict-junit`)
- Auto-registered through `META-INF/services`; records every test, every container failure, the
  exception chain with frames and the code source of each frame's class; writes the sidecar; renders alone
  under the console launcher.
- **Exit:** the zoo run with the listener produces sidecars from which the core reproduces the goldens;
  listener failure leaves the test run and its exit code intact.

### J4 Gradle plugin (`verdict-gradle`)
- Activation, classpath wiring, rendering at task end, quiet Gradle lines while active, up-to-date line,
  multi-task merge, configuration-cache compatibility, the reporter-error fallback.
- **Exit:** `./gradlew test` on the zoo prints the goldens under an agent environment and Gradle's own output
  without one; exit codes equal with and without the plugin on every scenario; functional tests for every
  activation path.

### J5 Java benchmark (`verdict-bench`, corpus `java`)
- Capture the zoo and a mutation corpus from a real Java project under Gradle, three arms per item from
  one capture: `default` (Gradle's console as configured out of the box), `tuned` (the best `testLogging`
  settings: full exception format, failed events only), and `verdict` with each switch as an ablation arm.
- **Two-run items** (before and after an edit) so the delta line can be scored; the scorer's question on
  new and fixed tests applies to them.
- Subject: a permissive project with fast tests that builds under Gradle or can be wrapped in a Gradle
  build; candidates to verify, not chosen: Apache Commons Lang, Commons Text, jsoup, Joda-Money.
- The bar is written before the first run: `verdict` against `tuned`, understanding up by at least 3
  points, or tokens down by at least half with understanding not lower (the Python rule 2 bounds).
- Tuning split for the rounds, sealed evaluation split for the versioned run, as in the benchmark design.
- **Exit:** the first Java A/B report, shakedown; every arm captured from the real plugin.

### J6 Maven extension (`verdict-maven`), later
Surefire and Failsafe console reporter extension on the same core.

## 6. Order of work

J1 and J2 start together: the core's unit tests come from the specification draft in section 2, and its
conformance test switches on when the goldens land. J3 follows J2's model; J4 follows J3. J5 begins its
subject selection and harness changes while J3 and J4 are built, and captures as soon as J4 passes its exit.

## 7. Open questions

1. **Maven Central coordinates.** The design record proposes `io.verdict`; publishing under it requires
   control of the domain `verdict.io`, which has not been verified. The fallback is a namespace verified
   through the GitHub organisation. Decide before the first publication; until then the group id is one
   Gradle property.
2. **Java 11 floor.** Some projects still test on Java 11; serving them means `--release 11` for the
   listener and the core. Decide from the benchmark subjects and early users.
3. **Kotlin and Kotest test names.** Display names with spaces and nested specs do not paste into
   `--tests`; the rerun form for them is decided when Kotest is verified.
4. **Captured output.** Whether the last lines of a failing test's standard output earn their tokens is a
   benchmark question; off in version 1.
