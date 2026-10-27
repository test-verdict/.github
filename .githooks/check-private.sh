#!/bin/sh
# Refuses private files and private markers. Used by the pre-commit and pre-push hooks, and run by
# hand before any publication:  .githooks/check-private.sh --all
# Exit 0 = clean, 1 = something private found (listed on stderr).
set -u
mode="${1:---staged}"
case "$mode" in
  --staged) files=$(git diff --cached --name-only --diff-filter=ACMR) ;;
  --all)    files=$(git ls-files) ;;
  --range)  files=$(git diff --name-only --diff-filter=ACMR "$2") ;;
  *) echo "usage: $0 [--staged|--all|--range <a>..<b>]" >&2; exit 2 ;;
esac
bad=0
# 1. Forbidden paths: agent configuration, instructions, conversations, private notes
for f in $files; do
  case "$f" in
    CLAUDE.md|*/CLAUDE.md|CLAUDE.local.md|*/CLAUDE.local.md|.claude/*|*/.claude/*|.codex/*|.gemini/*|\
    private/*|*/private/*|transcripts/*|*/transcripts/*|conversations/*|*.transcript.*)
      echo "private path: $f" >&2; bad=1 ;;
  esac
done
# 2. Forbidden content: local home paths and session provenance lines
pattern='(/Users/[A-Za-z]|/home/[a-z]|~/Code/|C:\\Users\\|^session: |CLAUDE_CODE_OAUTH_TOKEN=.)'
for f in $files; do
  [ -f "$f" ] || continue
  case "$f" in .githooks/*) continue ;; esac
  if [ "$mode" = "--staged" ]; then
    hits=$(git show ":$f" 2>/dev/null | grep -n -E "$pattern" || true)
  else
    hits=$(grep -n -E "$pattern" "$f" || true)
  fi
  [ -n "$hits" ] && { echo "private marker in $f:" >&2; echo "$hits" | head -5 >&2; bad=1; }
done
[ "$bad" -eq 0 ] || echo "refused: remove the private content above, or move it under private/ (git-ignored)" >&2
exit $bad
