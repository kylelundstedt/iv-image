#!/usr/bin/env bash
# Refresh the vendored ./skills snapshot from upstream. Run occasionally on any
# machine with node; commit the result to re-pin. provision-iv.sh installs from
# ./skills with no network, so this is the ONLY step that touches upstream/node.
#
# Installs into a throwaway HOME so your real ~/.agents/skills is left untouched.
set -euo pipefail
cd "$(dirname "$0")"

command -v npx >/dev/null || { echo "vendor-skills: need node/npx on PATH" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"
mkdir -p "$HOME/.agents/skills"

# Team skills — keep this list in sync with what the team wants pinned.
npx -y skills add -g -y matsonj/mviz
npx -y skills add -g -y vercel-labs/skills -s find-skills
npx -y skills add -g -y duckdb/duckdb-skills
npx -y skills add -g -y motherduckdb/agent-skills
npx -y skills add -g -y posit-dev/skills -s quarto-authoring brand-yml
npx -y skills add -g -y marimo-team/skills -s marimo-notebook marimo-batch
# archil-guide has no GitHub repo — fetch the skill file directly
mkdir -p "$HOME/.agents/skills/archil-guide"
curl -fsSL https://archil.com/skill.md -o "$HOME/.agents/skills/archil-guide/SKILL.md"

# Replace the vendored snapshot with the freshly resolved trees.
OUT="$(cd "$(dirname "$0")" && pwd)/skills"
rm -rf "$OUT"
mkdir -p "$OUT"
cp -a "$HOME/.agents/skills/." "$OUT/"

echo "vendored $(find "$OUT" -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ') skills into ./skills — commit to pin"
