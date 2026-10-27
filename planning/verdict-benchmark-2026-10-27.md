# Verdict benchmark: measuring whether agents understand the report

Design record, 2026-10-27. Status: design; nothing built. Companion to
[the design record](verdict-design-2026-10-27.md), whose phase 0 this document expands.

## 0. Summary

**The question, in priority order.** First: does an agent *understand* a test run better when it reads a
Verdict report, meaning it states the outcome correctly, finds the right place to work, and takes the right
next step. Second: does it get there with fewer tokens, turns and reruns. Economy is measured and reported,
but a format that saves tokens and costs one misread verdict has failed.

**The approach: three layers, cheapest first, each one gating the next.**

| Layer | What it measures | Needs a model? | Cost | Role |
|---|---|---|---|---|
| L0 Static | Tokens, bytes, and whether the facts the agent needs are present and survive the agent tool's truncation | No | Seconds, deterministic | Necessary condition; runs in CI on every format change |
| L1 Comprehension | A model reads one report cold and answers fixed questions about it; answers scored against ground truth, some by executing them | Yes, single call per item | Thousands of cheap calls | **The primary measure.** Decides the format. |
| L2 Agentic | An agent fixes real bugs in a loop with the reporter installed; hidden oracle decides | Yes, full agent sessions | Expensive, slow, noisy | Confirms that L1 gains translate into outcomes; never the only evidence |

**Why not a standard benchmark.** No published benchmark measures how well a model understands test
output; a search found studies of compiler-error explanations for students and of agents improving with
compiler feedback (one finding is directly encouraging: Rust gained the most from feedback, attributed to
its detailed compiler messages), but nothing that isolates the reporter. Standard *bug datasets* are still
the right raw material, because they give real failures with known fixes: Defects4J (Java), BugsInPy,
BugsJS, and the fail-to-pass tests of SWE-bench-style datasets. And a SWE-bench-style resolution run is the
right shape for L2, adapted so the agent's loop is actually driven by test output.

**The decisive trick: benchmark the format before building any reporter.** Every run in the corpus is
captured once as raw evidence (structured events, full stack traces, the framework's own console output, the
competitors' output from their real plugins). A reference renderer turns that evidence into the Verdict
text. So the format can be measured, ablated and redesigned in Python on day one, and the per-framework
implementations later only have to match the golden reports.

**My take on your framing.** Comprehension first is right, and it is more measurable than it sounds: most
of "did the agent understand" reduces to questions with one correct answer that a script can check, and the
most important single number is the **false-success rate**, how often the agent believes or says the run is
fine when it is not. Economy then comes almost free, because L0 counts tokens deterministically and L2
records them from transcripts. The risk is the opposite one: we design the format *and* the benchmark, so
the benchmark must be built to be able to say no (held-out items, honest competitor arms, pre-registration,
publication regardless of direction).

## 1. Lessons from earlier agent benchmarks

Earlier agent experiments by the authors on a different developer tool taught the rules below. Each rule
exists because its absence produced a misleading result at least once.

| Rule | Why |
|---|---|
| Every comparison is **paired** on the same item, model and seed, and effects are reported per model tier. | The model effect can dwarf the tool effect, and one run per cell cannot separate effect from variance. |
| **Self-reports are data, never the score.** Agentic runs use a hidden oracle, and the agent's final claim is itself scored. | Weaker agents routinely claimed success they had not achieved; only an oracle the agent could not see told the difference. |
| **Pre-register** questions, scoring, arms and analysis, and hash them before the first counted run. | Measures chosen after looking at results invite reading in what one hopes to see. |
| **Shakedown runs are labelled and never cited**; counted runs publish whatever they say. | Setting up a harness produces many runs that are wrong for setup reasons. |
| Every arm passes a **validity check** before it counts. | An arm that silently under-represents the tool, or starts from a broken baseline, corrupts a whole batch. |
| The prompt is **identical across arms**; only the reporter differs. | Prompt order alone changed outcomes in earlier work. |
| The control is the **honest competitor**: the framework tuned by an expert and every existing agent reporter at its best. | Beating untuned default output is not a result. |
| Weak models first; **one change per tuning round**; three seeds before an agentic claim. | Effects show first where the reader struggles; several changes at once cannot be attributed. |
| Agentic trials use **small, fast subjects** and clean up after themselves. | Long trials on large repositories limit repetitions, and leftover processes and files degrade the host and later measurements. |
| Inputs, prompts, answers and transcripts are **published** so anyone can rerun and disagree. | The authors design and grade their own product. |

## 2. What "understands the report" means, operationally

Comprehension is split into the decisions an agent makes after a test run. Each becomes a question type with
a ground-truth answer derived mechanically from the captured run, never written by hand.

| Code | Question the agent must answer | Ground truth from | Scoring |
|---|---|---|---|
| Q1 Outcome | Did the run pass, fail, error outside the tests, stop early, or select no tests? | Exit code plus run completeness | Exact. **A wrong "pass" is counted separately as a false success.** |
| Q2 Trust | Can this result be trusted as complete? If not, why? | Fail-fast, interrupt, timeout, shrinkage against the previous run | Exact category |
| Q3 Cause count | How many distinct problems are there? | Distinct seeded faults (mutants, fixture breaks) | Exact, and absolute error |
| Q4 Localisation | Which file and line should be changed first? | The seeded fault's location | Top-1 file, line within ±3; partial credit for the right file |
| Q5 Membership | Which tests fail because of problem X? | Seeded fault to failing-test mapping | F1 over test ids |
| Q6 Evidence | What was expected and what was actually produced? | Assertion payload | Exact after normalising whitespace |
| Q7 Rerun | Give the command that reruns exactly the failing tests | Failing set | **Executed**: precision and recall of the selected tests, plus "command runs at all" |
| Q8 Delta | Which failures are new since the last run, and which were fixed? | Two captured runs | F1 |
| Q9 Next action | What do you do next? Choose from a fixed list (fix production code at X, fix the fixture, fix the test, rerun without fail-fast, open the full report, investigate missing tests) | Scenario design | Exact |
| Q10 Abstention | When the report does not contain the answer (clipped body, missing detail), say so and say where to look | Clipping applied by the harness | Rewarded for "need more: open path P"; penalised for an invented answer |

Two answer formats per item, both scored: a **structured answer** (a small JSON object the harness checks)
and a **free explanation** of the failure, kept for qualitative reading and, later, a rubric checked by two
model judges with agreement reported. The headline numbers never depend on a judge.

The **comprehension score** of a format is the pre-registered weighted mean, with outcome and false success
weighted highest:

```
Q1 outcome ........ 25%     Q4 localisation ... 15%     Q7 rerun (executed) ... 10%
Q2 trust .......... 10%     Q5 membership ..... 10%     Q9 next action ........ 10%
Q3 cause count .... 5%      Q6 evidence ....... 5%      Q8 delta 5%, Q10 abstention 5%
```

Reported alongside, never folded in: **false-success rate** (gate: must not be worse than any competitor),
tokens read, output tokens, and latency.

## 3. Arms

Every arm renders **the same captured run**.

| Arm | What the model sees |
|---|---|
| D Default | The framework's own console output, untouched |
| H Hand-tuned | The best flags an expert would put in CLAUDE.md (per framework, written down and reviewed) |
| C Competitors | Each existing agent reporter at its documented best setting: pytest-markdown-report, pytest-receptor `--receptor=llm`, Vitest `agent`, vitest-llm-reporter JSON, a wrapper's folded output (context-mode style) |
| J JSON | CTRF JSON of the same run |
| V Verdict cold | The Verdict report, no explanation of the format anywhere in the prompt. **This is the "obvious to an agent" measure.** |
| V+ Verdict taught | The Verdict report plus the one-paragraph skill text an adopter would install |
| V−x Ablations | Verdict with one part removed: grouping, index, verdict-line wording, delta, culprit, decisive frame, rerun, clip notice |
| V′ Variants | Alternative spellings of the same content, for tuning: labels, ordering, heading levels, JSON-lines body, YAML body |

The gap between V and V+ is itself a finding: a large gap means the format is not self-explanatory yet.

## 4. Corpus

### 4.1 Sources of failures

1. **The failure zoo** from the design record: twenty scenarios per language, hand-built, covering every
   outcome and edge case. Small, fully understood, used for L0 and for golden reports.
2. **Mutation-generated failures in real projects.** Run a mutation tool (PIT for Java, Stryker for
   TypeScript and .NET, mutmut for Python) over mid-sized open-source projects; every killed mutant is a
   real failing run whose cause location is known exactly. Combine two or three mutants for multi-cause
   runs; mutate a shared fixture or helper for cascades. This produces thousands of realistic items with
   machine ground truth and no hand labelling.
3. **Real bug datasets.** Defects4J for Java, BugsInPy for Python, BugsJS for JavaScript: the
   bug-triggering tests run against the buggy version; ground truth is the developer's fix location.
   These guard against mutants being too easy or too uniform.
4. **Run pairs for the delta questions**: the same project before and after an edit, including an edit
   that silently drops tests (a broken import, a renamed file, a skip marker).
5. **Adversarial items**: tests whose output forges a verdict line, contains ANSI and control characters,
   floods 50,000 lines, or prints secret-shaped values.

### 4.2 Stratification

Every item is labelled before scoring with: language and framework, number of failing tests, number of
distinct causes, phase (test, setup, teardown, collection, compile), whether the cause is in project code
or a dependency, report size, and whether the harness clipped it. Results are always shown per stratum;
the pooled number is secondary. The hypothesis to test is that Verdict's advantage grows with failing tests
and causes and is near zero for a single assertion, so a pooled average would hide the shape.

### 4.3 Truncation conditions

Agents do not see the whole output when it is long. Each item is also presented as the agent's tool
would cut it: head-and-tail clipping at 2,000, 10,000 and 30,000 characters (Claude Code's reported
behaviours) and head-only at 10,000 bytes or 256 lines (older Codex behaviour). This tests the design
claim that the verdict line and the index survive the cut.

### 4.4 Split

- **Tuning set**, about 30%: used freely while iterating the format; results are shakedown.
- **Evaluation set**, about 70%, hashed and sealed: opened only for a pre-registered, versioned run.
  A format change made after looking at evaluation results makes the next run a new version on a freshly
  generated evaluation set (mutation generation makes this cheap).

## 5. Layer L0: static measures

Deterministic, no model, runs in every repository's CI against the golden reports.

| Measure | Definition |
|---|---|
| Tokens | Per item and arm, with several tokenisers: OpenAI `o200k_base` and `cl100k_base` locally, and Anthropic's token-counting endpoint (counted, not sampled) |
| Fact coverage | Fraction of the ground-truth facts present verbatim: outcome, each cause location, each failing test id, expected and actual, rerun selection |
| Survival under clipping | Fact coverage after each truncation condition in 4.3. The verdict line and index must survive every condition. |
| Noise share | Tokens not attributable to any ground-truth fact (banners, progress, passing test names, plumbing frames) |
| Injection resistance | Whether any test-produced text renders as a verdict line, heading or index line |
| Determinism | Same input, same bytes, across worker counts and runs |

L0 is a necessary condition only. A format can score perfectly here and still confuse a model, which is
what L1 is for.

## 6. Layer L1: comprehension

**Procedure per item.** One stateless call. System prompt: a neutral coding-agent persona, identical across
arms. User message: the project's file tree (names only), the command that was run, the arm's output under
the item's truncation condition, and the question set with the answer schema. No tools, so the score
measures reading, not exploration. Temperature as the product uses it, three samples per item.

**Variant L1b, with drill-down.** The model may call one tool, `read_file`, to open the sidecar or the full
report the output points to. Measures whether pointers are followed correctly and what drilling down costs.
This is where the Microsoft pilot's finding is retested: an index is cheap only if the follow-up read is.

**Models.** A ladder from weak to strong, because the effect shows first on weaker models: a small current
model, a mid model, a frontier model, from at least two vendors, plus one older small model. Exact model ids
are pinned in the run manifest.

**Size and power.** Paired binary outcomes per item: with 400 evaluation items, a two-sided paired test
detects roughly a 6 to 8 percentage-point difference in outcome accuracy at conventional power when
discordance is moderate; the pre-registration states the minimum effect we care about and the test
(McNemar for single binary measures, a mixed-effects logistic model with item and model as random effects
for the full set, bootstrap intervals for the weighted score). No p-values at L2 sizes.

**Volume.** 400 items × 8 to 12 arms × 4 truncation conditions × 5 models × 3 samples is on the order of
200,000 calls. That is too many to run blindly, so the plan staggers it: the full arm set on the
no-truncation condition and two models first; truncation and the full ladder only for the arms still in
contention.

## 7. Layer L2: agentic outcome

**Task shape: test-driven repair.** The agent receives a short ticket and a repository whose visible suite
is red because of a seeded fault (mutant, real bug, or fixture break). The reporter under test is installed
and active; the prompt is identical across arms and does not mention it, except in the taught arm. The agent
works until it says it is done. A hidden oracle suite, kept outside the sandbox, decides. This keeps the
agent's loop driven by test output, which a plain SWE-bench issue does not guarantee.

**Arms.** D, H, the strongest competitor from L1, and Verdict in the variant L1 selected. Fewer arms than L1,
because each trial is expensive.

**Measures, all from the harness and the transcript, never from the agent's report:**

| Measure | Why |
|---|---|
| Resolved: oracle green, visible suite green, diff within a size cap | The outcome |
| Wrong fix: visible green, oracle red | Comprehension failure that looked like success |
| **False success claim**: agent says done or all green while the oracle, or its own last run, says otherwise | The single most important failure |
| Test runs, and full-suite runs where a subset would do | Did it use the rerun command |
| Tokens of test-output in context, summed over all test commands | The economy the format controls directly |
| Total input and output tokens, turns, wall-clock, cost | Overall economy |
| Time and tokens to the first edit in the right file | Localisation in practice |
| Pointer use: did it open the full report, and was it needed | Drill-down behaviour |

**Subjects.** Small, fast projects per language, suites under a minute, in containers. A small slice of
real-world repositories (for example Defects4J projects, a few SWE-bench-style instances adapted to the
test-driven shape) for external validity, run with fewer seeds.

**Agents.** The command-line agents a developer actually uses (Claude Code, Codex, Gemini CLI), each in an
isolated configuration, plus one plain tool-calling loop over an API model so the result is not tied to one
agent product's own output handling.

**Analysis.** Paired by (ticket, model, agent, seed); three seeds minimum before any claim; effects reported
per model tier and per stratum with bootstrap intervals; counts shown alongside rates.

## 8. Using the benchmark to improve the format

The loop the design is built for:

1. Change one thing in the format (a label, an order, a section).
2. L0 in CI: no fact coverage or clipping-survival regression; token delta recorded.
3. L1 on the tuning set, two models, no truncation: comprehension score and false-success rate against the
   current version.
4. If it wins, L1 on the tuning set across the ladder and truncation conditions.
5. At a milestone, a versioned L1 evaluation run on a sealed set, then L2.

Every feature listed in the design record's section on new capabilities (delta, culprit hint, shrinkage
warning, pattern line, next-action hint) enters as an ablation pair and stays in the default only if L1
shows it helps or at least does not hurt, with the cost in tokens stated.

## 9. Threats to validity, and the mitigation for each

| Threat | Mitigation |
|---|---|
| We built the format and the benchmark | Pre-registration, sealed evaluation set, competitor authors invited to check their arms, full publication including losses |
| Overfitting the format to the question set | Questions are derived from the agent's decisions, written before the format is tuned; sealed set regenerated per version |
| Mutants are unlike real bugs | Real-bug datasets as a separate stratum; results reported per source |
| Training contamination: models have seen Defects4J and pytest output | Mutation-generated and freshly generated items dominate; contamination-prone sources reported separately |
| One agent product handles output specially (truncation, folding) | Truncation simulated explicitly in L1; L2 runs several agents and one plain loop |
| Single-call comprehension differs from in-loop reading | L2 exists for exactly this; disagreement between L1 and L2 is reported, not hidden |
| Answer format leaks hints (field names imply where to look) | The answer schema is identical for all arms and was written before the Verdict labels were chosen |
| Run-to-run variance in agents | Paired design, three samples or seeds, intervals |
| Vendor drift: models change under the same name | Exact model ids pinned; every result carries its model id and date |

## 10. Repository and build order

A new repository in the family, `verdict-bench`, with the harness, the captured corpus, the reference
renderer and the results. It is written from scratch; the lessons in section 1 carry over as rules, not as code.

```
verdict-bench/
  corpus/<lang>/zoo/            the failure zoo projects
  corpus/<lang>/mutants/        generation scripts and pinned project revisions
  corpus/<lang>/bugs/           adapters for Defects4J, BugsInPy, BugsJS
  capture/                      runs each item once, keeps raw evidence and every competitor's output
  render/                       the reference Verdict renderer and the ablation variants
  questions/                    question generators and the answer schema
  l0/  l1/  l2/                 one runner per layer
  results/shakedown/  results/<version>/
  PREREGISTRATION.md            frozen per version, hashed
```

**Build order**

1. Zoo for Python and Java, capture, reference renderer, L0 in CI. Python first because the competitors
   exist there, so the first comparison is against the best work in the field, not a strawman.
2. Question generators and L1 runner; shakedown on the tuning set with two models.
3. Mutation corpus for one Python and one Java project; first format-tuning rounds.
4. Pre-registration and the first versioned L1 run.
5. L2 harness on small subjects, then the first L2 pilot: a few tickets, four arms, two models, three seeds.
6. Extend to TypeScript and .NET as their zoos land; Swift last.

## 11. Decisions to take

1. **Spend.** L1 is many cheap single calls. Subscriptions suit long agent sessions but not 200,000 short calls. Options: a capped API budget for L1 only,
   or a much smaller L1 run through subscription CLIs. Recommendation: a capped API budget for L1, and
   subscriptions for L2.
2. **Publication.** Recommendation: publish every versioned run whatever
   it says.
3. **Competitor outreach.** Recommendation: before the first versioned run, invite the pytest-receptor,
   pytest-markdown-report and vitest-llm-reporter authors to review their arm's configuration.
4. **Weights** in the comprehension score: the proposal in section 2 is a starting point to confirm before
   pre-registration.

## 12. Sources

- Earlier agent benchmark work by the authors, summarised as rules in section 1.
- Microsoft testfx RFC #8824 and #8827: the measured pilot on failure indexes and CTRF queries.
- pytest-receptor benchmark tables and its `--receptor-stats` method.
- Santos and Becker, "Not the Silver Bullet: LLM-enhanced Programming Error Messages are Ineffective in
  Practice": https://dl.acm.org/doi/fullHtml/10.1145/3689535.3689554
- Code-generation study finding that detailed compiler messages (Rust) gave the largest gain from
  feedback: https://www.sciencedirect.com/science/article/pii/S0925231225021332
- ComBench, repository-level compilation-error repair, via the review at https://arxiv.org/pdf/2605.05267
- Defects4J, BugsInPy, BugsJS, SWE-bench and Multi-SWE-bench, as failure sources and the L2 task shape.
- Earlier agent benchmark work by the authors, summarised as rules in section 1.
