#!/usr/bin/env bash
# PreToolUse hook: re-render the Apex documentation site before any `git push`,
# so the locally-served _site/ stays in sync. A failed render blocks the push.
set -euo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')

case "$cmd" in
  *"git push"*) ;;
  *) exit 0 ;;
esac

repo="${CLAUDE_PROJECT_DIR:-$PWD}"
renderer=$(command -v render-site || true)
[[ -n "$renderer" ]] || renderer="$repo/bin/render-site"

if "$renderer" "$repo" >&2; then
  exit 0
fi

echo "render-before-push: 'render-site' failed; blocking push" >&2
exit 2
