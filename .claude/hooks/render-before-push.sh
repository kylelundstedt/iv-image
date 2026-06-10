#!/usr/bin/env bash
# PreToolUse hook: re-render the Quarto site before any `git push`, so the
# locally-served _site/ stays in sync with what we're about to push. A failed
# render exits 2 to block the push.
set -euo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')

case "$cmd" in
  *"git push"*) ;;
  *) exit 0 ;;
esac

repo="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$repo"

if ! command -v quarto >/dev/null; then
  echo "render-before-push: quarto not on PATH; skipping render" >&2
  exit 0
fi

if quarto render >&2; then
  exit 0
fi

echo "render-before-push: 'quarto render' failed; blocking push" >&2
exit 2
