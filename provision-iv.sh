#!/usr/bin/env bash
# Provision the IV layer onto a stock exeuntu VM.
#
# This script layers IV tooling on top. Tool releases are version-pinned and
# checksum-verified; skills and agent configuration are vendored in this repo.
# It needs no Node runtime. Arch-aware (amd64 + arm64) and safe to re-run.
set -euo pipefail

DUCKDB_VERSION=1.5.3
QUARTO_VERSION=1.9.38
AWS_CLI_VERSION=2.35.7
TIGRIS_VERSION=3.1.0
RCLONE_VERSION=1.74.3

DUCKDB_SHA256_AMD64=35caef1fecbc8d7e2c07de4fd2cdefc5189ec9ba9e1cca228fb1a1c48cc52a8a
DUCKDB_SHA256_ARM64=5e2399428793642e994f1584c47d49f4c58b7b4ec2297ea4a522353a6c553835
QUARTO_SHA256_AMD64=ea8c897368791ad9f200010c087ea3111b2e556b12a960487dd4e216902aa102
QUARTO_SHA256_ARM64=75fbc5c1121ffe65e564e9d24711db2ad8f617f9552f5dc7d8a06307d72dde38
AWS_CLI_SHA256_X86_64=300cd0b8a8dd64f080202e02ef1745bf327b8a2546054a2d036869c0f27f4199
AWS_CLI_SHA256_AARCH64=2d4f222c1e16212c0a6bfea23af2e2e8c13a053600d12f68846d794e8470dd9f
TIGRIS_SHA256_AMD64=bf79f07bddddbca5858b3687a4fd1ba93851a5c8ffea7cfc47a6cfe90b024f4a
TIGRIS_SHA256_ARM64=c6f777cae123ec83138e3b6dd0c637236abb63b3b42e6caccd68599a71a9e471
RCLONE_SHA256_AMD64=dbee7ccd7a5d617e4ed4cd4555c16669b511abfe8d31164f61be35ac9e999bd2
RCLONE_SHA256_ARM64=8f8d47446e061f80c3256659fe8e21f56d72d96aaefe1275d088ea5eb6b42aa7

if [[ $EUID -eq 0 ]]; then
  echo "provision-iv: run as the VM login user, not with sudo" >&2
  exit 1
fi

IV_REPO="$(cd "$(dirname "$0")" && pwd)"
DPKG_ARCH="$(dpkg --print-architecture)"
UNAME_ARCH="$(uname -m)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

case "$DPKG_ARCH" in
  amd64)
    DUCKDB_SHA256=$DUCKDB_SHA256_AMD64
    QUARTO_SHA256=$QUARTO_SHA256_AMD64
    TIGRIS_SHA256=$TIGRIS_SHA256_AMD64
    TIGRIS_ASSET_ARCH=x64
    RCLONE_SHA256=$RCLONE_SHA256_AMD64
    ;;
  arm64)
    DUCKDB_SHA256=$DUCKDB_SHA256_ARM64
    QUARTO_SHA256=$QUARTO_SHA256_ARM64
    TIGRIS_SHA256=$TIGRIS_SHA256_ARM64
    TIGRIS_ASSET_ARCH=arm64
    RCLONE_SHA256=$RCLONE_SHA256_ARM64
    ;;
  *) echo "provision-iv: unsupported dpkg architecture: $DPKG_ARCH" >&2; exit 1 ;;
esac

case "$UNAME_ARCH" in
  x86_64) AWS_CLI_SHA256=$AWS_CLI_SHA256_X86_64 ;;
  aarch64) AWS_CLI_SHA256=$AWS_CLI_SHA256_AARCH64 ;;
  *) echo "provision-iv: unsupported uname architecture: $UNAME_ARCH" >&2; exit 1 ;;
esac

download_verified() {
  local url=$1 sha256=$2 output=$3
  curl -fsSL "$url" -o "$output"
  printf '%s  %s\n' "$sha256" "$output" | sha256sum -c -
}

duckdb_version() { /usr/local/bin/duckdb --version 2>/dev/null | awk '{sub(/^v/, "", $1); print $1}' || true; }
quarto_version() { /usr/local/bin/quarto --version 2>/dev/null | head -1 || true; }
aws_version() { /usr/local/bin/aws --version 2>&1 | sed -nE 's#aws-cli/([^ ]+).*#\1#p' || true; }
tigris_version() { /usr/local/bin/tigris --version 2>/dev/null | head -1 | sed 's/^v//' || true; }
rclone_version() { /usr/local/bin/rclone version 2>/dev/null | sed -nE '1s/^rclone v?//p' || true; }

install_duckdb() {
  local actual
  actual=$(duckdb_version)
  echo "== DuckDB $DUCKDB_VERSION ($DPKG_ARCH; installed: ${actual:-missing}) =="
  [[ $actual == "$DUCKDB_VERSION" ]] && return
  download_verified \
    "https://github.com/duckdb/duckdb/releases/download/v${DUCKDB_VERSION}/duckdb_cli-linux-${DPKG_ARCH}.zip" \
    "$DUCKDB_SHA256" "$TMP/duckdb.zip"
  unzip -q -o "$TMP/duckdb.zip" -d "$TMP/duckdb"
  sudo install -m 0755 "$TMP/duckdb/duckdb" /usr/local/bin/duckdb
  [[ $(duckdb_version) == "$DUCKDB_VERSION" ]]
}

install_quarto() {
  local actual
  actual=$(quarto_version)
  echo "== Quarto $QUARTO_VERSION ($DPKG_ARCH; installed: ${actual:-missing}) =="
  [[ $actual == "$QUARTO_VERSION" ]] && return
  download_verified \
    "https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/quarto-${QUARTO_VERSION}-linux-${DPKG_ARCH}.tar.gz" \
    "$QUARTO_SHA256" "$TMP/quarto.tar.gz"
  mkdir -p "$TMP/quarto"
  tar -xzf "$TMP/quarto.tar.gz" -C "$TMP/quarto" --strip-components=1
  [[ $("$TMP/quarto/bin/quarto" --version | head -1) == "$QUARTO_VERSION" ]]
  local target="/opt/quarto-${QUARTO_VERSION}"
  local backup=/opt/quarto.pre-iv
  sudo rm -rf "$target.new"
  sudo mkdir -p "$target.new"
  sudo cp -a "$TMP/quarto/." "$target.new/"
  sudo rm -rf "$target"
  sudo mv "$target.new" "$target"
  sudo rm -rf "$backup"
  if [[ -e /opt/quarto && ! -L /opt/quarto ]]; then
    sudo mv /opt/quarto "$backup"
  fi
  if ! sudo ln -sfn "$target" /opt/quarto; then
    [[ ! -e $backup ]] || sudo mv "$backup" /opt/quarto
    return 1
  fi
  sudo ln -sfn /opt/quarto/bin/quarto /usr/local/bin/quarto
  [[ $(quarto_version) == "$QUARTO_VERSION" ]]
  sudo rm -rf "$backup"
}

install_aws() {
  local actual
  actual=$(aws_version)
  echo "== AWS CLI $AWS_CLI_VERSION ($UNAME_ARCH; installed: ${actual:-missing}) =="
  [[ $actual == "$AWS_CLI_VERSION" ]] && return
  download_verified \
    "https://awscli.amazonaws.com/awscli-exe-linux-${UNAME_ARCH}-${AWS_CLI_VERSION}.zip" \
    "$AWS_CLI_SHA256" "$TMP/aws.zip"
  unzip -q "$TMP/aws.zip" -d "$TMP"
  if [[ -d /usr/local/aws-cli ]]; then
    sudo "$TMP/aws/install" --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update
  else
    sudo "$TMP/aws/install" --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli
  fi
  [[ $(aws_version) == "$AWS_CLI_VERSION" ]]
}

install_tigris() {
  local actual
  actual=$(tigris_version)
  echo "== Tigris CLI $TIGRIS_VERSION ($DPKG_ARCH; installed: ${actual:-missing}) =="
  [[ $actual == "$TIGRIS_VERSION" ]] && return
  download_verified \
    "https://github.com/tigrisdata/cli/releases/download/v${TIGRIS_VERSION}/tigris-linux-${TIGRIS_ASSET_ARCH}.tar.gz" \
    "$TIGRIS_SHA256" "$TMP/tigris.tar.gz"
  tar -xzf "$TMP/tigris.tar.gz" -C "$TMP"
  sudo install -m 0755 "$TMP/tigris-linux-${TIGRIS_ASSET_ARCH}" /usr/local/bin/tigris
  [[ $(tigris_version) == "$TIGRIS_VERSION" ]]
}

install_rclone() {
  local actual
  actual=$(rclone_version)
  echo "== rclone $RCLONE_VERSION ($DPKG_ARCH; installed: ${actual:-missing}) =="
  [[ $actual == "$RCLONE_VERSION" ]] && return
  download_verified \
    "https://downloads.rclone.org/v${RCLONE_VERSION}/rclone-v${RCLONE_VERSION}-linux-${DPKG_ARCH}.zip" \
    "$RCLONE_SHA256" "$TMP/rclone.zip"
  unzip -q "$TMP/rclone.zip" -d "$TMP"
  sudo install -m 0755 "$TMP/rclone-v${RCLONE_VERSION}-linux-${DPKG_ARCH}/rclone" /usr/local/bin/rclone
  [[ $(rclone_version) == "$RCLONE_VERSION" ]]
}

install_duckdb
install_quarto
install_aws
install_tigris
install_rclone

echo "== doc-site and cloud helpers =="
for tool in render-site provision-docsite gen-llms-txt shot install-cloud-cli; do
  sudo install -m 0755 "$IV_REPO/bin/$tool" "/usr/local/bin/$tool"
done

echo "== agent config =="
mkdir -p "$HOME/.agents" "$HOME/.claude" "$HOME/.codex"
install -m 0644 "$IV_REPO/agent/AGENTS.md" "$HOME/.agents/AGENTS.md"
install -m 0755 "$IV_REPO/agent/ssh-guard.sh" "$HOME/.agents/ssh-guard.sh"
install -m 0644 "$IV_REPO/agent/settings.json" "$HOME/.claude/settings.json"
install -m 0644 "$IV_REPO/agent/codex-config.toml" "$HOME/.codex/config.toml"
ln -sfn ../.agents/AGENTS.md "$HOME/.claude/CLAUDE.md"
ln -sfn ../.agents/AGENTS.md "$HOME/.codex/AGENTS.md"

echo "== MCP servers =="
bash "$IV_REPO/agent/setup-mcp.sh"

echo "== skills (vendored; no node needed) =="
mkdir -p "$HOME/.agents/skills" "$HOME/.claude/skills" "$HOME/.codex/skills"
TEAM_SKILLS="$HOME/.agents/iv-team-skills.list"
NEW_SKILLS="$TMP/team-skills"
mkdir -p "$NEW_SKILLS"
cp -a "$IV_REPO/skills/." "$NEW_SKILLS/"
find "$NEW_SKILLS" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort > "$TMP/team-skills.list"

if [[ -f $TEAM_SKILLS ]]; then
  while IFS= read -r name; do
    [[ -n $name ]] || continue
    [[ $name =~ ^[A-Za-z0-9._-]+$ && $name != . && $name != .. ]] || {
      echo "provision-iv: unsafe prior skill name: $name" >&2
      exit 1
    }
    rm -rf "$HOME/.agents/skills/$name"
    rm -rf "$HOME/.claude/skills/$name" "$HOME/.codex/skills/$name"
  done < "$TEAM_SKILLS"
fi

while IFS= read -r name; do
  [[ $name =~ ^[A-Za-z0-9._-]+$ && $name != . && $name != .. ]] || {
    echo "provision-iv: unsafe vendored skill name: $name" >&2
    exit 1
  }
  rm -rf "$HOME/.agents/skills/$name"
  cp -a "$NEW_SKILLS/$name" "$HOME/.agents/skills/$name"
  rm -rf "$HOME/.claude/skills/$name" "$HOME/.codex/skills/$name"
  ln -sT "../../.agents/skills/$name" "$HOME/.claude/skills/$name"
  ln -sT "../../.agents/skills/$name" "$HOME/.codex/skills/$name"
done < "$TMP/team-skills.list"
install -m 0644 "$TMP/team-skills.list" "$TEAM_SKILLS"

echo "== ssh config (VM-to-VM short names) =="
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
SSH_CFG="$HOME/.ssh/config"
touch "$SSH_CFG"
chmod 600 "$SSH_CFG"
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
LOCK="$HOME/iv-provision.lock"
{
  echo "provisioned_utc=$(date -u +%FT%TZ)"
  echo "provision_repo_sha=$(git -C "$IV_REPO" rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "arch=$DPKG_ARCH"
  echo "exeuntu_image_revision=$(jq -r '.Labels["org.opencontainers.image.revision"] // "unknown"' /exe.dev/etc/image.conf 2>/dev/null || echo unknown)"
  echo "exeuntu_image_created=$(jq -r '.Labels["org.opencontainers.image.created"] // "unknown"' /exe.dev/etc/image.conf 2>/dev/null || echo unknown)"
  echo "shelley_version=$(cat /exe.dev/etc/shelley-version 2>/dev/null || echo unknown)"
  echo "duckdb_version=$(duckdb_version)"
  echo "quarto_version=$(quarto_version)"
  echo "aws_cli_version=$(aws_version)"
  echo "tigris_version=$(tigris_version)"
  echo "rclone_version=$(rclone_version)"
  echo "dotfiles_manifest_pin=$(tr -d '[:space:]' < "$IV_REPO/dotfiles-manifest.pin" 2>/dev/null || echo unknown)"
  echo "skills_count=$(wc -l < "$TEAM_SKILLS" | tr -d ' ')"
} | tee "$LOCK"

echo "== IV layer provisioned on stock exeuntu (see $LOCK) =="
