# Verdict

Organisation-wide files for the Verdict project family: the profile shown on the organisation page, the security policy that applies to every repository, and the planning records that precede code.

- [Profile](profile/README.md)
- [Design record, 2026-10-27](planning/verdict-design-2026-10-27.md): survey of existing agent-oriented test reporters, the Verdict format, and the implementation plan, one repository per framework.
- [Benchmark design, 2026-10-27](planning/verdict-benchmark-2026-10-27.md): how we measure whether agents understand the report (first) and what it saves (second).
- [Benchmark creation and shakedown plan, 2026-10-27](planning/verdict-bench-shakedown-plan-2026-10-27.md): steps S0 to S9 with exit criteria; subscriptions only; lesser models first.
- [Security policy](SECURITY.md)

Nothing is released yet. The format marker `verdict/1` and the package coordinates named in the design record are reserved by convention until the specification repository publishes them.

## What is never published

Agent instructions and configuration (`CLAUDE.md`, `.claude/`, `.codex/`, `.gemini/`), conversation
transcripts, and anything under `private/` are git-ignored, and the hooks in `.githooks/` refuse them and
any local home path on commit and on push. After cloning, enable the hooks once:

```
git config core.hooksPath .githooks
```

Before any publication, run `.githooks/check-private.sh --all`.

