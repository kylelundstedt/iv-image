#!/usr/bin/env bash
# Validate an installed IV provisioning layer and its provenance lock.
set -euo pipefail

repo=${1:-$(cd "$(dirname "$0")/.." && pwd)}
lock=${2:-$HOME/iv-provision.lock}

expected_value() {
  sed -nE "s/^$1=//p" "$repo/provision-iv.sh" | head -1
}

actual_duckdb=$(/usr/local/bin/duckdb --version | awk '{sub(/^v/, "", $1); print $1}')
actual_quarto=$(/usr/local/bin/quarto --version | head -1)
actual_aws=$(/usr/local/bin/aws --version 2>&1 | sed -nE 's#aws-cli/([^ ]+).*#\1#p')
actual_tigris=$(/usr/local/bin/tigris --version | head -1 | sed 's/^v//')
actual_rclone=$(/usr/local/bin/rclone version | sed -nE '1s/^rclone v?//p')
actual_herdr=$(/usr/local/bin/herdr --version | awk '{print $2}')
actual_agentsview=$(/usr/local/bin/agentsview version --format json | jq -r '.version' | sed 's/^v//')

[[ $actual_duckdb == "$(expected_value DUCKDB_VERSION)" ]]
[[ $actual_quarto == "$(expected_value QUARTO_VERSION)" ]]
[[ $actual_aws == "$(expected_value AWS_CLI_VERSION)" ]]
[[ $actual_tigris == "$(expected_value TIGRIS_VERSION)" ]]
[[ $actual_rclone == "$(expected_value RCLONE_VERSION)" ]]
[[ $actual_herdr == "$(expected_value HERDR_VERSION)" ]]
[[ $actual_agentsview == "$(expected_value AGENTSVIEW_VERSION)" ]]

for tool in render-site provision-docsite gen-llms-txt shot install-cloud-cli agentsview-source-daemon; do
  test -x "/usr/local/bin/$tool"
done

test -x "$HOME/.agents/ssh-guard.sh"
test -f "$HOME/.agents/AGENTS.md"
test -f "$HOME/.claude/settings.json"
test -f "$HOME/.codex/config.toml"
test -f "$HOME/.claude.json"
test -f "$HOME/.agents/iv-team-skills.list"
test -f "$HOME/.config/systemd/user/agentsview-source.service"

while IFS= read -r name; do
  test -f "$HOME/.agents/skills/$name/SKILL.md"
  test -L "$HOME/.claude/skills/$name"
  test -L "$HOME/.codex/skills/$name"
done < "$HOME/.agents/iv-team-skills.list"

test -f "$lock"
grep -qx "duckdb_version=$actual_duckdb" "$lock"
grep -qx "quarto_version=$actual_quarto" "$lock"
grep -qx "aws_cli_version=$actual_aws" "$lock"
grep -qx "tigris_version=$actual_tigris" "$lock"
grep -qx "rclone_version=$actual_rclone" "$lock"
grep -qx "herdr_version=$actual_herdr" "$lock"
grep -qx "agentsview_version=$actual_agentsview" "$lock"

printf 'smoke-provision: IV layer is healthy (%s)\n' "$lock"
