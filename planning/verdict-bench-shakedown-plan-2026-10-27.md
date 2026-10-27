# Verdict benchmark: creation and shakedown plan

Plan, 2026-10-27. Status: plan; nothing built. Expands the build order of
[the benchmark design](verdict-benchmark-2026-10-27.md) into steps with exit criteria, under two
decisions taken today:

- **Subscriptions, not API spend.** Every model call goes through a subscription command-line agent:
  Claude Code, Codex CLI, Gemini CLI. Their allowances are the budget.
- **Lesser models first.** The cheaper, smaller and older models are the primary lane.

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
| Shakedown, comprehension | 30 | 4 | 1 | 1 | 120 |
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
- Run the 120-call shakedown: 30 tuning items, four arms (default, hand-tuned, pytest-receptor, Verdict
  cold), one model.
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
- Two or three rounds on the tuning set with the ladder: one format change per round, static layer then
  comprehension, the change kept only if comprehension improves or holds and the false-success rate does
  not rise.
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

## 4. Who does the work

Steps with a written specification can be delegated; calibration, sizing and tuning need judgement on
what the measurements mean and stay with the maintainers. Gates and long runs run in the foreground.

## 5. Open questions

1. Answered 2026-10-27: Codex on Pro, Gemini on the free tier; lanes in section 1.
2. Answered 2026-10-27: `verdict-bench` is written from scratch.
3. The comprehension-score weights from the benchmark design, before S9 freezes them.
