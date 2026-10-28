# Verdict benchmark: creation and shakedown plan

Plan, 2026-10-27. Status: plan; nothing built. Expands the build order of
[the benchmark design](verdict-benchmark-2026-10-27.md) into steps with exit criteria, under two
decisions taken today:

- **Subscriptions, not API spend.** Every model call goes through a subscription command-line agent:
  Claude Code, Codex CLI, Gemini CLI. Their allowances are the budget.
- **Lesser models first.** The cheaper, smaller and older models are the primary lane.

## Status

| Step | State | Notes |
|---|---|---|
| S0, repository and lanes | **Claude lane done**; Codex and Gemini lanes wait for their logins | Claude: hello and tool bait pass on Haiku 4.5, Haiku 5.5 and Sonnet 5.5 with every tool disabled; a short custom system prompt keeps a call at 525 to 641 input tokens (6,800 with the agent's default prompt). Codex cannot run tool-free: its read-only sandbox still executes shell commands, so tool calls are detected from its event stream and recorded as violations; its fixed overhead is about 15,000 input tokens per call and it does not report the answering model. First signal for the abstention question: asked to list files without tools, Haiku 4.5 answered with an empty list; the newer models said they could not. |
| S1, Python failure zoo and capture | **done** | Twenty pytest scenarios captured under five arms (default, tuned, receptor, markdown, ctrf); every exit check is an automated test, and a recapture is byte-identical to the committed capture. Findings about competitors: the CTRF reporter drops collection errors; receptor lists three tests per group, then `+N more`. Specification and implementation notes in `verdict-bench/docs/s1-python-zoo.md`. Next: S2, reference renderer and the static layer. |
| S2, reference renderer and static layer | **done** | The reference renderer turns the S1 evidence into the Verdict report and equals twenty golden reports written by hand before it existed; six ablation switches and an optional hint line. The static layer measures all six arms: tokens (o200k, cl100k), fact coverage, survival under the five truncation conditions, noise share, injection, determinism; the first table is recorded as shakedown. Every exit check passes: full coverage apart from facts elided by design (test ids behind `+N more`), the verdict line and index intact under every truncation, no forged line from `hostile-output`, byte-identical renders in any record order. Ground truth corrected first: a fixture failing in setup or teardown is a failing run, not an error. Specification and notes in `verdict-bench/docs/s2-renderer.md`. Next: S3, questions, answer schema and scorer. |
| S3, questions, answer schema and scorer | **done** | Question text and answer schema fixed for every arm before any tuning. Ground truth derived from the scenario and the evidence; the next-action question uses a stated rule with accepted sets, because most zoo failures do not show whether the test or the code is wrong. The rerun command is executed without a shell, against a fixed option set, in a copy whose pytest cache holds the last failures. Exit checks pass: the ideal answer scores full marks on all 720 presentations, an empty answer scores zero, sixteen hand-made wrong answers score as expected. Known weakness: short expected and actual values match almost any text. Specification in `verdict-bench/docs/s3-questions.md`. Next: S4, comprehension runner. |
| S4, comprehension runner and harness shakedown | **done** | One tool-free call per presentation, an identical prompt for every arm apart from the report, one row per planned call whatever its outcome, resumable runs, single-row reruns, and rescoring of stored answers after a scoring correction. The first real calls found two faults in the lane (a schema key the CLI refuses; structured-output turns counted as tool calls), fixed before the run. The 132-call shakedown on the smallest Claude model answered and parsed every call, with no rate limits. The direction check was **not evaluable**: the model scores near the ceiling on every arm, so the zoo is too easy to separate formats. Every arm missed the same items, which exposed three question rules, corrected and rescored without new calls. Specification in `verdict-bench/docs/s4-comprehension.md`. Next: harder items before calibration (section 6, question 4). |
| S6, mutation corpus pilot (Python) | **done**, taken before S5 (section 6, question 4) | Subject marshmallow 4.3.1 (MIT), 1,192 tests in about a second; our own one-line mutation operators. 159 items from 800 sampled mutants: 90 single, 60 with two or three causes, 9 cascades from a fixture or helper (50 wanted; the subject has few fixtures that fail five tests or more, shortfall reported, not padded); 48 tuning, 111 sealed. 48 items have more than 20 failing tests. Every item scores only what the output can show; captures stored compressed (23 MB), byte-identical on recapture. First static findings, shakedown: Verdict's index does not survive the tightest cuts on large reports, and Verdict is about three times the size of receptor on this corpus. The hand check of 20 tuning items found every cause location sane. CTRF is left out of model runs on this corpus: listing every passing test, it exceeds a small model's context. Specification and notes in `verdict-bench/docs/s6-mutation.md`. |

## 1. Why lesser models, and the three guards that keep it honest

**Why it is right.** Earlier agent experiments showed tool effects appearing first on weaker models. A strong model reads almost any
output correctly, so its accuracy sits near the ceiling, and a better format has nowhere to show up. A
lesser model makes the format's clarity the deciding variable. They are also the models that run test
loops in practice, as subagents and in high-volume automation, and they spend far less allowance per call.

**Guard 1: calibrate against the floor, not only the ceiling.** A model that fails most questions on every
arm shows no effect either. During shakedown each candidate model answers the tuning set on the default
and hand-tuned arms; a model enters the ladder only if its baseline comprehension score is between 40% and
85%. The ladder is chosen by that measurement, not by name.

**Guard 2: do no harm on a strong model.** A format tuned for weak readers could get worse for strong ones,
for example by over-structuring. One strong model runs a small fixed sample of every versioned run. The
claim is only "not worse", with the margin stated in advance.

**Guard 3: size to the allowance.** A command-line agent sends its own system prompt and tool definitions
with every call, so one comprehension item costs far more allowance than its text suggests. The shakedown
measures that overhead per CLI and model, and the versioned run is sized from the measurement, not
guessed. Planning figures until then:

| Run | Items | Arms | Models | Samples | Calls |
|---|---|---|---|---|---|
| Shakedown, comprehension | 20 | 6 | 1 | 1 | 120 |
| Calibration | 30 | 2 | up to 6 | 1 | 360 |
| First versioned comprehension run | 150 | 6 | 3 | 3 | 8,100 |
| Do-no-harm sample | 40 | 6 | 1 | 1 | 240 |

Several questions are asked per item in one call (the ten question types share one answer object), so calls
equal items, not questions.

**Lanes and candidate models** (decided 2026-10-27: Claude Code and Codex on paid subscriptions, Codex on
Pro; Gemini on the free tier). Exact ids are pinned in every run manifest after S0 confirms what each
subscription exposes.

| Lane | Subscription | Candidate lesser models | Role |
|---|---|---|---|
| Claude Code | paid | Haiku 4.5, Haiku 5.5 | Primary lane for every step; do-no-harm model Sonnet 5.5 |
| Codex CLI | Pro | the smallest and the mid-size model Codex offers | Second vendor for calibration, the versioned comprehension run, and the agentic pilot's repeat |
| Gemini CLI | free tier | the Flash model the free tier serves | Calibration and a small cross-vendor sample only |

**Gemini free tier, constraints to respect.** The free tier has a daily request cap and a per-minute rate
limit (to be measured in S0, not assumed), one CLI turn can consume several requests, and the served model
can change under load. So Gemini never carries a full arm set: it runs calibration (S5) and a fixed sample
of at most 40 items × the arms still in contention per versioned run, spread across days by a quota guard
that stops cleanly at the cap and resumes the next day. Free-tier prompts may be used by the provider; the
corpus is public test output from open-source projects and our own zoo, so nothing private goes there,
and the harness refuses to send any item not marked public.

## 2. Ground rules

- Everything before the maintainers declare the harness correct is **shakedown**: kept under
  `results/shakedown/`, labelled, never cited.
- **One lane per credential**, each lane logged in on its own once (`CLAUDE_CONFIG_DIR=<lane dir>` then
  login; the Codex and Gemini equivalents). Two copies of one credential kill each other on token refresh.
- **No more than two heavy jobs on the host at once**; check memory pressure first.
- **Every trial cleans up**: work directories after their transcripts are copied, Gradle daemons, test
  JVMs (`pgrep` before timing runs), containers. Measure free disk and the work root at the start and the end of each
  benchmark day.
- **Paired** comparisons only; **one format change per tuning round**; **three seeds** before any agentic
  claim.
- The harness is code with tests. A scorer is proven on known answers before it scores a model.

## 3. Steps and exit criteria

Each step ends with a check that can fail. A step that fails its check is fixed before the next starts.

### S0 Repository and lanes
- Create the `verdict-bench` repository, written from scratch. It stays local until the maintainers decide
  to publish it.
- Python harness (`uv`), one command per step (`bench <step>`), results schema with a version field.
- Prepare one lane per CLI (Claude Code, Codex CLI, Gemini CLI). Verify headless invocation, JSON output, a way to run with **no tools**
  (comprehension must measure reading, not exploration), and a way to pin the model.
- - Measure the Gemini free tier's daily and per-minute limits and requests per CLI turn; record them in the
  lane file; build the quota guard (stop at the cap, resume next day, never lose a row).
- **Exit:** a scripted "hello" call per lane returns a parsed JSON answer with the model id recorded; the
  tool-free mode is proven by a prompt that asks the model to list files and gets no tool call.

### S1 Failure zoo and capture, Python then Java
- The twenty zoo scenarios as a pytest project, then as a JUnit 5 project under Gradle.
- `capture` runs each scenario once and stores the raw evidence: the framework's structured results
  (pytest report objects through a small capture plugin; JUnit Platform events through a listener), full
  traces, exit code, the default console output, the hand-tuned console output, CTRF JSON, and every
  competitor's output from its real plugin at its documented best setting (pytest-markdown-report,
  pytest-receptor `--receptor=llm`).
- The hand-tuned flags per framework are written down in `arms/` with the reason for each flag.
- **Exit:** each capture is reproducible byte for byte on a second run, except timestamps and durations,
  which are normalised. Each competitor's output passes an arm-validity check: it contains the failures it
  should and nothing indicates a misconfiguration.

### S2 Reference renderer and the static layer
- The Verdict renderer from the captured evidence, plus the ablation and variant switches.
- Golden reports for the zoo, written by hand first, then compared with the renderer.
- Static measures: tokens (local tokenisers; Anthropic counting only if a key is available, otherwise
  local counts only), fact coverage, survival under the five truncation conditions, noise share,
  injection resistance, determinism.
- **Exit:** renderer equals the golden reports; Verdict has full fact coverage on the zoo; the verdict line
  and index survive every truncation condition; the injection scenario cannot forge a line. First token
  table across all arms recorded as shakedown.

### S3 Questions, answer schema and scorer
- Question generators derive the ground truth for the ten question types from the captured evidence.
- The answer schema is written once for all arms, before any Verdict label is tuned.
- The rerun-command scorer actually executes the command in a copy of the project and compares the
  selected tests.
- **Exit:** the scorer gives full marks to the ground truth, zero to an empty answer, and the expected
  partial marks to a hand-made set of wrong answers. A model is never the first thing to run through it.

### S4 Comprehension runner and harness shakedown
- One call per item, tool-free, identical prompt across arms apart from the report text, answer parsed
  against the schema; failures to parse recorded as a separate outcome, never dropped.
- Measure per lane: allowance cost per call as far as the CLI reports it, system-prompt overhead, latency,
  parse rate, rate-limit behaviour, and run-to-run variance on repeated identical calls.
- Run the 120-call shakedown: the twenty zoo items, all six arms (default, hand-tuned, pytest-receptor,
  pytest-markdown-report, CTRF JSON, Verdict cold), one model. This is also the first direction check of
  section 4: the redesign trigger is evaluated on it and the result recorded.
- **Exit:** parse rate at least 98%; no item lost silently; every row has model id, CLI version, arm,
  item hash and truncation condition; a reviewer can rerun any single row with one command.

### S5 Model calibration
- Up to six candidate lesser models across the three lanes on 30 tuning items, default and hand-tuned arms only.
- Keep the models whose baseline score falls between 40% and 85%; keep at most three, spanning the band.
- **Exit:** the ladder is chosen and recorded with each model's baseline; the do-no-harm model is
  confirmed working on the same setup.

### S6 Mutation corpus pilot
- One small Python project and one small Java project with fast suites; mutation tools (mutmut, PIT)
  produce killed mutants; single-cause, multi-cause (two or three mutants) and cascade (mutated fixture or
  helper) items are composed and captured like the zoo.
- **Exit:** at least 200 items per language with ground truth; a stratification label on every item; a
  sample of 20 checked by hand for a sane cause location.

### S7 First format-tuning rounds, shakedown
- Two or three rounds on the tuning set with the ladder, run by the protocol in section 4: ablations first,
  then one addition or change per round.
- **Exit:** a format candidate frozen for the first versioned run, with the change log of the rounds.

### S8 Agentic harness pilot
- Small subject per language, suite under a minute, three seeded tickets, arms default and Verdict, one
  lesser model through Claude Code, one seed; hidden oracle outside the sandbox; transcripts kept; work
  directories removed after copying.
- **Exit:** six trials end to end; every measure in the design's agentic table is present in the ledger
  from the transcript and the oracle, not from the agent's report; cleanup leaves no daemons or work dirs.

### S9 Review and pre-registration
- The maintainers review the harness, the shakedown results and the arm configurations; competitor authors are
  invited to review their arms.
- `PREREGISTRATION.md` frozen and hashed: the format version, questions, weights, arms, models with ids,
  sizes from the S4 measurements, the analysis, the minimum effects, the do-no-harm margin; the evaluation
  set generated after the freeze and sealed.
- **Exit:** the maintainers declare the harness correct. From here every run publishes whatever it says.

## 4. Format refinement protocol

Decided 2026-10-28, replacing the protocol of 2026-10-27 (refine one Verdict design from the top down).

**Why it changed.** On the tuning items of the mutation corpus the Verdict design as a whole did not beat
the free hand-tuned output, and on the hard strata it lost (Haiku 4.5, shakedown): its groups share a crash
site, the report calls each group a root cause, and one bug failing 37 tests at 37 assertions read as 37
causes (cause count 4% against 70% to 89% for the plain arms). The design is therefore not refined as a whole.
The format is **built up feature by feature** from the best plain baseline, and every feature earns its place
in an isolated A/B test.

**Baseline.** The markdown reporter's output (pytest-markdown-report): best on the tuning items (87.8%
against 87.4% for tuned), smaller than tuned, summary first, one section per failing test with short
tracebacks, no claims about causes. Features are edits to that output built from data the run already
recorded; nobody's plugin is rewritten. The hand-tuned arm stays the bar of the go or stop decision (section
6, question 6): whatever is built must beat what any pytest user gets for free.

**Two measures per A/B test, both primary.**
- **A/B score**: the comprehension score over the questions that discriminate (Q3 cause count, Q4
  localisation, Q5 membership, Q6 evidence, Q7 rerun). Q1, Q2 and Q9 are at or near 100% on every arm, carry
  45% of the full score's weight and would hide differences; they become a **guard**: a feature must not
  lower them.
- **Token cost**: tokens of the report per item (o200k; Anthropic's count where available), as presented,
  per stratum.

**A feature is kept** when, paired by item and sample against the current baseline, either
1. the A/B score rises by at least **3 points** and the token cost rises by at most 10%, or
2. the token cost falls by at least **10%** and the A/B score falls by at most 1 point,

with the guard intact and no rise in false successes. Whether 3 points is above noise is established by the
A/A run of round 0; if it is not, items or samples are added until it is, never the bar lowered. A kept feature
is confirmed on fresh tuning items before it is combined.

**Combination.** Kept features are combined; the hypothesis is that the combination beats each feature
alone, on the A/B score at no more tokens than the sum of their costs. It is tested like a feature, against
the best single feature.

**Rounds.**
- **Round 0, the bench itself.** Fix the Q6 scorer (every arm scores 0, so a fault is likely); harder items
  (three to five mutants per run with overlapping failing tests allowed, runs mixing failures with skips,
  expected failures and a collection error, and about 150 tuning items in all); the A/B score and token cost
  in the report; truncation at the agent's real limit (head and tail, 30,000 characters) as a standing
  condition beside the full output; an A/A run of the baseline to measure noise.
- **Features, one A/B test each** (target question in brackets, reported to explain a result, not to decide it):
  F1 a rerun line with the failing test ids (Q7); F2 the shared code location, the deepest project-code line
  that the failing tests' tracebacks pass through, named once with its test count (Q4, Q3); F3 a neutral
  grouping summary above the sections, tests that fail at the same place, never called a root cause (Q5,
  Q3); F5 identical tracebacks shown once with their test count (tokens); F6 the same content without Markdown
  syntax (whether the headings and fences help, or only the content).
- Decided 2026-10-28: the membership question (which tests belong to which bug) is scored only on items with
  at most 20 failing tests. On larger items models listed a sample of the right group, so the question
  measured how much they were willing to write, not whether they understood. Giving the model a compact
  name for a group (a file, class or selector standing for all its tests) is tested as a feature of its own.
- Decided 2026-10-28, a principle rather than a test: passing tests get no detail, only their count in one
  summary line with the failing count. The markdown baseline already does this. On a failing pytest run the
  passing tests' progress output is about 3% of the plain output (436 of 13,880 tokens on average), so the
  large savings on failing runs lie in the failure details; on a green run the progress output is nearly all
  of it, so green and near-green runs (the unmutated suite, one failure among 1,192) are added to the token
  measure. Activation without configuration when an agent runs the tests (as Vitest's `minimal` reporter
  does) is recorded as a product requirement; agents do not reliably follow an instruction to pick a reporter.
- Further features come from where models answer wrongly, one at a time.

Every test is recorded in a change log: the feature, the reason, the A/B score and token deltas per stratum,
the guard, and the decision. All of this is shakedown until the evaluation split is opened in a
pre-registered, versioned run (S9).

## 5. Who does the work

Steps with a written specification can be delegated; calibration, sizing and tuning need judgement on
what the measurements mean and stay with the maintainers. Gates and long runs run in the foreground.

## 6. Open questions

1. Answered 2026-10-27: Codex on Pro, Gemini on the free tier; lanes in section 1.
2. Answered 2026-10-27: `verdict-bench` is written from scratch.
3. The comprehension-score weights from the benchmark design, before S9 freezes them.
4. Decided 2026-10-27: the zoo is too easy for calibration (the smallest available model scores above the
   calibration band on every arm), so S6 comes before S5, and S5 calibrates on the S6 tuning items. The Python
   subject is marshmallow 4.3.1; each item is built as a comprehension item and as an agentic task at once.
5. Decided 2026-10-27: the benchmark measures whether the output is understood, not whether the agent can fix
   the bug; fixing depends mostly on the model's coding skill and would bury the format's effect in noise.
   Mutation items therefore score only what the output can show; the mutant's location stays the ground truth
   for grouping failures by root cause. The agentic layer (S8) is deferred, not cancelled: it returns only
   if the comprehension results are borderline and the downstream effect must be seen.
6. Decided 2026-10-27: an early decision on whether the project is worth continuing, taken after S6 and
   a small agentic pilot, before any format tuning. The zoo results do not answer it: the benchmark design
   predicted no advantage on a single failure, and the zoo is mostly single failures. The hypothesis worth
   testing is narrower: the format helps when failures are many, causes are several, or the agent's tool cut
   the output. The bar is the hand-tuned arm, a one-line configuration anyone can adopt for free, and the
   most compact competitors (receptor and markdown already use about 40% fewer tokens than Verdict on the
   zoo).
   - **Continue** when, on the S6 tuning items with a calibrated model, Verdict leads the best of tuned,
     receptor and markdown by at least 5 points in the hard strata (more than 20 failing tests, several
     causes, or a clipped presentation) with no more false successes.
   - **Stop building the library** when it does not: publish the benchmark and its findings (which output
     settings help agents, which reporters do not) as the result.
   - Anything between is a redesign trigger under section 4, not a reason to continue unchanged.
7. Open 2026-10-28, a note for later: if the feature rounds keep a Markdown-shaped report on top, the product
   may become that format, carried to frameworks whose agents have no such reporter today (JUnit and the
   other JVM runners first, as the design record already plans). Whether those frameworks lack one is to be
   verified against their ecosystems before it shapes any plan; nothing changes in the rounds meanwhile.
