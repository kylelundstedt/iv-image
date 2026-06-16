#!/usr/bin/env bash
# Provision the IV layer onto a STOCK exeuntu VM (replaces the old custom image).
#
# Stock boldsoftware/exeuntu keeps Shelley (binary injected at VM creation), so the
# VMs-list icon, the detail-page Shelley button, and <vm>.shelley.exe.xyz all work.
# This script just layers IV tooling on top — pinned and reproducible from a git
# commit. It needs NO node: skills are vendored in ./skills and copied into place.
#
#   ssh exe.dev new --name=<vm> --tag=iv                 # default image = exeuntu
#   ssh exe.dev integrations attach github-kylelundstedt-iv-image vm:<vm>
#   ssh <vm>.exe.xyz "git clone https://github-kylelundstedt-iv-image.int.exe.xyz/kylelundstedt/iv-image.git ~/iv-image \
#                     && git -C ~/iv-image checkout <tag-or-sha> && ~/iv-image/provision-iv.sh"
#
# To refresh the pinned tool/skill versions, edit the pins below / run vendor-skills.sh,
# commit, and re-provision. The git commit is the reproducible identity (see README).
#
# Arch-aware (amd64 + arm64). Idempotent: every step guards on `command -v`.
set -euo pipefail

DUCKDB_VERSION=1.5.3
QUARTO_VERSION=1.9.38
IV_REPO="$(cd "$(dirname "$0")" && pwd)"
DPKG_ARCH="$(dpkg --print-architecture)"   # amd64 | arm64 — matches duckdb/quarto/rclone assets
UNAME_ARCH="$(uname -m)"                    # x86_64 | aarch64 — matches the awscli asset

echo "== DuckDB $DUCKDB_VERSION ($DPKG_ARCH) =="
if ! command -v duckdb >/dev/null; then
  curl -fsSL "https://github.com/duckdb/duckdb/releases/download/v${DUCKDB_VERSION}/duckdb_cli-linux-${DPKG_ARCH}.zip" -o /tmp/duckdb.zip
  sudo unzip -o /tmp/duckdb.zip -d /usr/local/bin
  rm /tmp/duckdb.zip
fi

echo "== Quarto $QUARTO_VERSION ($DPKG_ARCH) =="
if ! command -v quarto >/dev/null; then
  curl -fsSL "https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/quarto-${QUARTO_VERSION}-linux-${DPKG_ARCH}.tar.gz" -o /tmp/quarto.tar.gz
  sudo mkdir -p /opt/quarto
  sudo tar -xzf /tmp/quarto.tar.gz -C /opt/quarto --strip-components=1
  sudo ln -sf /opt/quarto/bin/quarto /usr/local/bin/quarto
  rm /tmp/quarto.tar.gz
fi

# Cloud / object-storage CLIs (arch-aware). Small + broadly useful → installed here.
# Azure CLI + gcloud SDK are ~2 GB and rarely needed, so they install on demand via
# the install-cloud-cli helper (copied onto PATH below).
echo "== AWS CLI v2 ($UNAME_ARCH) =="
if ! command -v aws >/dev/null; then
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${UNAME_ARCH}.zip" -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp
  sudo /tmp/aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli
  rm -rf /tmp/awscliv2.zip /tmp/aws
fi

echo "== Tigris CLI =="
if ! command -v tigris >/dev/null; then
  curl -fsSL https://github.com/tigrisdata/cli/releases/latest/download/install.sh \
    | sudo env TIGRIS_INSTALL_DIR=/usr/local/bin TIGRIS_SKIP_PATH=1 sh
fi

echo "== rclone ($DPKG_ARCH) =="
if ! command -v rclone >/dev/null; then
  curl -fsSL "https://downloads.rclone.org/rclone-current-linux-${DPKG_ARCH}.zip" -o /tmp/rclone.zip
  unzip -q /tmp/rclone.zip -d /tmp
  sudo mv /tmp/rclone-*-linux-${DPKG_ARCH}/rclone /usr/local/bin/rclone
  sudo chmod +x /usr/local/bin/rclone
  rm -rf /tmp/rclone.zip /tmp/rclone-*-linux-${DPKG_ARCH}
fi

echo "== doc-site tools + install-cloud-cli helper =="
sudo cp "$IV_REPO"/bin/render-site "$IV_REPO"/bin/provision-docsite "$IV_REPO"/bin/gen-llms-txt "$IV_REPO"/bin/install-cloud-cli /usr/local/bin/
sudo chmod +x /usr/local/bin/render-site /usr/local/bin/provision-docsite /usr/local/bin/gen-llms-txt /usr/local/bin/install-cloud-cli

echo "== agent config =="
mkdir -p "$HOME/.agents" "$HOME/.claude" "$HOME/.codex"
cp "$IV_REPO"/agent/AGENTS.md "$HOME/.agents/AGENTS.md"
cp "$IV_REPO"/agent/settings.json "$HOME/.claude/settings.json"
cp "$IV_REPO"/agent/codex-config.toml "$HOME/.codex/config.toml"
ln -sf ../.agents/AGENTS.md "$HOME/.claude/CLAUDE.md"
ln -sf ../.agents/AGENTS.md "$HOME/.codex/AGENTS.md"

echo "== MCP servers =="
bash "$IV_REPO"/agent/setup-mcp.sh

echo "== skills (vendored — no node needed) =="
mkdir -p "$HOME/.agents/skills" "$HOME/.claude/skills" "$HOME/.codex/skills"
cp -a "$IV_REPO"/skills/. "$HOME/.agents/skills/"
for d in "$IV_REPO"/skills/*/; do
  name="$(basename "$d")"
  ln -sf "../../.agents/skills/$name" "$HOME/.claude/skills/$name"
  ln -sf "../../.agents/skills/$name" "$HOME/.codex/skills/$name"
done

echo "== ssh config (VM-to-VM short names) =="
# Stock exeuntu ships no ~/.ssh/config, so the first VM-to-VM SSH by short name
# (e.g. `ssh iv-docs`) fails host-key verification: the default
# StrictHostKeyChecking can't accept the new key in a non-interactive/BatchMode
# session. This stanza makes `ssh iv-gitlake` Just Work across the tailnet —
# accept host keys on first contact, default the login user to exedev. Idempotent
# (guarded by the marker), so re-provisioning won't duplicate it.
mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
SSH_CFG="$HOME/.ssh/config"; touch "$SSH_CFG"; chmod 600 "$SSH_CFG"
if ! grep -q "# >>> iv-provision ssh >>>" "$SSH_CFG"; then
  cat >> "$SSH_CFG" <<'EOF'

# >>> iv-provision ssh >>>
# VM-to-VM tailnet SSH: accept new host keys, default user exedev.
Host iv-* *.ts.net
  StrictHostKeyChecking accept-new
  User exedev
# <<< iv-provision ssh <<<
EOF
fi

echo "== provenance lockfile =="
# Records exactly what landed. The base exeuntu is exe.dev-managed (floats); we can't
# pin it, but we record its image revision + the Shelley version exe.dev injected.
LOCK="$HOME/iv-provision.lock"
{
  echo "provisioned_utc=$(date -u +%FT%TZ)"
  echo "provision_repo_sha=$(git -C "$IV_REPO" rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "arch=$DPKG_ARCH"
  echo "exeuntu_image_revision=$(jq -r '.Labels["org.opencontainers.image.revision"] // "unknown"' /exe.dev/etc/image.conf 2>/dev/null || echo unknown)"
  echo "exeuntu_image_created=$(jq -r '.Labels["org.opencontainers.image.created"] // "unknown"' /exe.dev/etc/image.conf 2>/dev/null || echo unknown)"
  echo "shelley_version=$(cat /exe.dev/etc/shelley-version 2>/dev/null || echo unknown)"
  echo "duckdb_version=$DUCKDB_VERSION"
  echo "quarto_version=$QUARTO_VERSION"
  echo "skills_count=$(find "$IV_REPO"/skills -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ')"
} | tee "$LOCK"

echo "== IV layer provisioned on stock exeuntu (see $LOCK) =="
