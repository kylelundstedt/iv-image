#!/bin/bash
# Install team agent skills into ~/.agents/skills/ with symlinks for Claude and
# Codex. Runs at image build time so VMs start ready — no npm install on boot.
set -euo pipefail

# fnm (exeuntu's node manager) needs eval to put node/npx on PATH.
# In Docker RUN, .bashrc isn't sourced, so we do it explicitly.
export PATH="$HOME/.local/bin:$PATH"
eval "$(fnm env)"

# Ensure target directories exist
mkdir -p "$HOME/.agents/skills" "$HOME/.claude/skills" "$HOME/.codex/skills"

# Team skills — general-purpose, useful to everyone on the team.
# Each `npx -y skills add -g -y` fetches from GitHub and installs to ~/.agents/skills/.
npx -y skills add -g -y matsonj/mviz
npx -y skills add -g -y vercel-labs/skills -s find-skills
npx -y skills add -g -y duckdb/duckdb-skills
npx -y skills add -g -y motherduckdb/agent-skills
npx -y skills add -g -y posit-dev/skills -s quarto-authoring brand-yml
npx -y skills add -g -y marimo-team/skills -s marimo-notebook marimo-batch
# archil-guide — no GitHub repo, download skill file directly
mkdir -p "$HOME/.agents/skills/archil-guide"
curl -fsSL https://archil.com/skill.md -o "$HOME/.agents/skills/archil-guide/SKILL.md"
for agent_dir in "$HOME/.claude/skills" "$HOME/.codex/skills"; do
    ln -sf "../../.agents/skills/archil-guide" "$agent_dir/archil-guide"
done

echo "Skills installed."
