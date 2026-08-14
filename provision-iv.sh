#!/usr/bin/env bash
# Provision the IV layer onto a stock exeuntu VM.
#
# This script layers IV tooling on top. Tool releases are version-pinned and
# checksum-verified; skills and agent configuration are vendored in this repo.
# It needs no Node runtime. Arch-aware (amd64 + arm64) and safe to re-run.
set -euo pipefail

DUCKDB_VERSION=1.5.3
TIGRIS_VERSION=3.6.1
RCLONE_VERSION=1.74.3
HERDR_VERSION=0.7.4
AGENTSVIEW_VERSION=0.38.1
SHELLEY_VERSION=0.959.914757635
SHELLEY_TAG=v0.959.914757635
SHELLEY_COMMIT=33df9d893b0de54d32942c7541841cb0e626baa2
APEX_VERSION=1.1.16

DUCKDB_SHA256_AMD64=35caef1fecbc8d7e2c07de4fd2cdefc5189ec9ba9e1cca228fb1a1c48cc52a8a
DUCKDB_SHA256_ARM64=5e2399428793642e994f1584c47d49f4c58b7b4ec2297ea4a522353a6c553835
TIGRIS_SHA256_AMD64=3038796d9a6ef9f9c0fdfdc7846d516d88b8775a2b34110d9d5813a4b7da57dd
TIGRIS_SHA256_ARM64=38a4ca3e94e09c22fca08896f12ec8abf5ead731dd7fc07d56e9d3c98b5be4ba
RCLONE_SHA256_AMD64=dbee7ccd7a5d617e4ed4cd4555c16669b511abfe8d31164f61be35ac9e999bd2
RCLONE_SHA256_ARM64=8f8d47446e061f80c3256659fe8e21f56d72d96aaefe1275d088ea5eb6b42aa7
# herdr publishes no checksum files — these are sha256sums of the release
# assets, computed locally at pin time. Version bumps must recompute them.
HERDR_SHA256_X86_64=bc0fc02d4ba500f9cac2353a43e67fe036785ecca6eb55378e050fac3c103059
HERDR_SHA256_AARCH64=544e0002de42806d1ab64ccdef3a7e7414f24717b0b6b022bc9e57d2eefd26a2
AGENTSVIEW_SHA256_AMD64=3b3f7098ab855571df8e6d6c99efdf307be3407d32197816f0c4c698fac4f997
AGENTSVIEW_SHA256_ARM64=aace4bea2f6b8626fb9aaecf28b4ffaf93d510550e3468231de81f741266d037
SHELLEY_SHA256_AMD64=6f1aff50a7890d397c3da32aa4d6fddf06ed6aa8aebaa987adbb527bb3db1dff
SHELLEY_SHA256_ARM64=e89091075ae2732b6e073bdb75896be9ce8ef524d23b8c916b036c4c73dd53d3
APEX_SHA256_AMD64=d19c99148cf1d3cd3302c1ff13b893c09f5b3575b00c67f183b0b9ddb7000ac1
APEX_SHA256_ARM64=dbf306f515301b6c2b91988d142da2e95b89c3efbcc359c03975fb12a811a2d9

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
    TIGRIS_SHA256=$TIGRIS_SHA256_AMD64
    TIGRIS_ASSET_ARCH=x64
    RCLONE_SHA256=$RCLONE_SHA256_AMD64
    AGENTSVIEW_SHA256=$AGENTSVIEW_SHA256_AMD64
    SHELLEY_SHA256=$SHELLEY_SHA256_AMD64
    APEX_SHA256=$APEX_SHA256_AMD64
    APEX_ASSET_ARCH=x86_64
    ;;
  arm64)
    DUCKDB_SHA256=$DUCKDB_SHA256_ARM64
    TIGRIS_SHA256=$TIGRIS_SHA256_ARM64
    TIGRIS_ASSET_ARCH=arm64
    RCLONE_SHA256=$RCLONE_SHA256_ARM64
    AGENTSVIEW_SHA256=$AGENTSVIEW_SHA256_ARM64
    SHELLEY_SHA256=$SHELLEY_SHA256_ARM64
    APEX_SHA256=$APEX_SHA256_ARM64
    APEX_ASSET_ARCH=aarch64
    ;;
  *) echo "provision-iv: unsupported dpkg architecture: $DPKG_ARCH" >&2; exit 1 ;;
esac

case "$UNAME_ARCH" in
  x86_64) HERDR_SHA256=$HERDR_SHA256_X86_64 ;;
  aarch64) HERDR_SHA256=$HERDR_SHA256_AARCH64 ;;
  *) echo "provision-iv: unsupported uname architecture: $UNAME_ARCH" >&2; exit 1 ;;
esac

download_verified() {
  local url=$1 sha256=$2 output=$3
  curl -fsSL "$url" -o "$output"
  printf '%s  %s\n' "$sha256" "$output" | sha256sum -c -
}

remove_legacy_quarto() {
  # Reclaim installations created by older iv-image releases. Do not touch a
  # user-managed quarto binary unless it resolves into the old /opt/quarto tree.
  local target dir
  if [[ -L /usr/local/bin/quarto ]]; then
    target=$(readlink -f /usr/local/bin/quarto || true)
    [[ $target == /opt/quarto/* ]] && sudo rm -f /usr/local/bin/quarto
  fi
  [[ ! -L /opt/quarto ]] || sudo rm -f /opt/quarto
  while IFS= read -r dir; do
    sudo rm -rf -- "$dir"
  done < <(find /opt -maxdepth 1 -type d -name 'quarto-*' -print)
}

duckdb_version() { /usr/local/bin/duckdb --version 2>/dev/null | awk '{sub(/^v/, "", $1); print $1}' || true; }
# aws is on-demand (install-cloud-cli aws); empty in the lock file when absent.
aws_version() { /usr/local/bin/aws --version 2>&1 | sed -nE 's#aws-cli/([^ ]+).*#\1#p' || true; }
tigris_version() { /usr/local/bin/tigris --version 2>/dev/null | head -1 | sed 's/^v//' || true; }
rclone_version() { /usr/local/bin/rclone version 2>/dev/null | sed -nE '1s/^rclone v?//p' || true; }
herdr_version() { /usr/local/bin/herdr --version 2>/dev/null | awk '{print $2}' || true; }
agentsview_version() { /usr/local/bin/agentsview version --format json 2>/dev/null | jq -r '.version' | sed 's/^v//' || true; }
shelley_info() { /usr/local/bin/shelley version 2>/dev/null || true; }
shelley_version() { shelley_info | jq -r '.version // empty' 2>/dev/null || true; }
shelley_commit() { shelley_info | jq -r '.commit // empty' 2>/dev/null || true; }
apex_version() { /usr/local/bin/apex --version 2>/dev/null | awk 'NR == 1 {print $2}' || true; }

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

# AWS CLI moved to on-demand 2026-07-28: `install-cloud-cli aws`.
#
# It was a default install costing 267-533 MB per VM (~2.9 GB fleet-wide) while
# NOT ONE VM had ~/.aws/config or ~/.aws/credentials — installed everywhere,
# configured nowhere. S3 work here targets Tigris over S3-compatible endpoints
# via the tigris CLI, boto3 and duckdb httpfs, none of which use this CLI.
#
# The pins and the installer live in bin/install-cloud-cli alongside azure and
# gcloud, which were already on-demand for exactly this reason. tigris and
# rclone stay default: used, and far smaller.

install_tigris() {
  local actual
  actual=$(tigris_version)
  echo "== Tigris CLI $TIGRIS_VERSION ($DPKG_ARCH; installed: ${actual:-missing}) =="
  [[ $actual == "$TIGRIS_VERSION" ]] && return
  # tigrisdata/cli is deprecated and its releases froze without
  # TIGRIS_FORCE_PATH_STYLE (required by exe.dev Object Storage integrations).
  # The live repo is tigrisdata/storage, which tags releases @tigrisdata/cli@X.Y.Z
  # (not vX.Y.Z) — hence the @-prefixed path segment below.
  download_verified \
    "https://github.com/tigrisdata/storage/releases/download/@tigrisdata/cli@${TIGRIS_VERSION}/tigris-linux-${TIGRIS_ASSET_ARCH}.tar.gz" \
    "$TIGRIS_SHA256" "$TMP/tigris.tar.gz"
  tar -xzf "$TMP/tigris.tar.gz" -C "$TMP"
  sudo install -m 0755 "$TMP/tigris-linux-${TIGRIS_ASSET_ARCH}" /usr/local/bin/tigris
  [[ $(tigris_version) == "$TIGRIS_VERSION" ]]
}

# rclone moved to on-demand 2026-07-29 (`install-cloud-cli rclone`): 75 MB per
# VM, used only by the Tigris backup, which runs on klundstedt-mini. No dev VM
# had ~/.config/rclone/rclone.conf. tigris stays a default install — 18 vendored
# agent skills depend on it.

# herdr releases bare binaries named with uname-style arch (x86_64/aarch64)
install_herdr() {
  local actual
  actual=$(herdr_version)
  echo "== herdr $HERDR_VERSION ($UNAME_ARCH; installed: ${actual:-missing}) =="
  [[ $actual == "$HERDR_VERSION" ]] && return
  download_verified \
    "https://github.com/ogulcancelik/herdr/releases/download/v${HERDR_VERSION}/herdr-linux-${UNAME_ARCH}" \
    "$HERDR_SHA256" "$TMP/herdr"
  sudo install -m 0755 "$TMP/herdr" /usr/local/bin/herdr
  [[ $(herdr_version) == "$HERDR_VERSION" ]]
}

install_agentsview() {
  local actual
  actual=$(agentsview_version)
  echo "== AgentsView $AGENTSVIEW_VERSION ($DPKG_ARCH; installed: ${actual:-missing}) =="
  [[ $actual == "$AGENTSVIEW_VERSION" ]] && return
  download_verified \
    "https://github.com/kenn-io/agentsview/releases/download/v${AGENTSVIEW_VERSION}/agentsview_${AGENTSVIEW_VERSION}_linux_${DPKG_ARCH}.tar.gz" \
    "$AGENTSVIEW_SHA256" "$TMP/agentsview.tar.gz"
  mkdir -p "$TMP/agentsview"
  tar -xzf "$TMP/agentsview.tar.gz" -C "$TMP/agentsview"
  sudo install -m 0755 "$TMP/agentsview/agentsview" /usr/local/bin/agentsview
  [[ $(agentsview_version) == "$AGENTSVIEW_VERSION" ]]
}

install_shelley() {
  local actual_version actual_commit backup_dir backup_bin db_backup
  actual_version=$(shelley_version)
  actual_commit=$(shelley_commit)
  echo "== Shelley $SHELLEY_VERSION ($DPKG_ARCH; installed: ${actual_version:-missing} ${actual_commit:+@$actual_commit}) =="

  # The pin is both release and source identity. A matching version built from a
  # different commit is not accepted.
  if [[ $actual_version == "$SHELLEY_VERSION" && $actual_commit == "$SHELLEY_COMMIT" ]]; then
    sudo mkdir -p /etc/systemd/system/shelley.service.d
    printf '%s\n' '[Service]' 'Environment=SHELLEY_SKIP_VERSION_CHECK=true' \
      | sudo tee /etc/systemd/system/shelley.service.d/10-iv-managed.conf >/dev/null
    sudo systemctl daemon-reload
    # A newly written drop-in does not affect the running process until restart.
    # Restart even for matching bytes so unmanaged self-upgrade is actually off.
    sudo systemctl restart shelley.service
    return
  fi

  download_verified \
    "https://github.com/aifoundry-org/shelley/releases/download/${SHELLEY_TAG}/shelley_linux_${DPKG_ARCH}" \
    "$SHELLEY_SHA256" "$TMP/shelley"
  chmod 0755 "$TMP/shelley"
  [[ $("$TMP/shelley" version | jq -r '.version') == "$SHELLEY_VERSION" ]]
  [[ $("$TMP/shelley" version | jq -r '.commit') == "$SHELLEY_COMMIT" ]]

  backup_dir="$HOME/.local/state/iv-provision/shelley/$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p "$backup_dir"
  chmod 700 "$HOME/.local/state/iv-provision" "$HOME/.local/state/iv-provision/shelley" "$backup_dir"
  if [[ -x /usr/local/bin/shelley ]]; then
    sudo cp -a /usr/local/bin/shelley "$backup_dir/shelley.prior"
    sudo chown "$USER:$(id -gn)" "$backup_dir/shelley.prior"
    sha256sum "$backup_dir/shelley.prior" > "$backup_dir/shelley.prior.sha256"
    /usr/local/bin/shelley version > "$backup_dir/shelley.prior.version.json" 2>/dev/null || true
  fi
  [[ ! -f /etc/systemd/system/shelley.service ]] || sudo cp -a /etc/systemd/system/shelley.service "$backup_dir/shelley.service.prior"
  [[ ! -f /etc/systemd/system/shelley.socket ]] || sudo cp -a /etc/systemd/system/shelley.socket "$backup_dir/shelley.socket.prior"

  # Stop only the service; keep the socket active. Use SQLite's backup API when
  # Python is available, otherwise copy the stopped/checkpointed database.
  sudo systemctl stop shelley.service 2>/dev/null || true
  if [[ -f $HOME/.config/shelley/shelley.db ]]; then
    db_backup="$backup_dir/shelley.db.prior"
    if command -v python3 >/dev/null 2>&1; then
      python3 - "$HOME/.config/shelley/shelley.db" "$db_backup" <<'PY'
import sqlite3, sys
src, dst = sys.argv[1:]
a = sqlite3.connect(src)
b = sqlite3.connect(dst)
a.backup(b)
assert b.execute("pragma integrity_check").fetchone()[0] == "ok"
b.close(); a.close()
PY
    else
      cp -a "$HOME/.config/shelley/shelley.db" "$db_backup"
    fi
    chmod 600 "$db_backup"
  fi

  rollback_shelley() {
    echo "provision-iv: Shelley health check failed; restoring prior binary" >&2
    if [[ -x $backup_dir/shelley.prior ]]; then
      sudo install -o root -g root -m 0755 "$backup_dir/shelley.prior" /usr/local/bin/shelley.rollback-new
      sudo mv /usr/local/bin/shelley.rollback-new /usr/local/bin/shelley
      sudo systemctl restart shelley.service || true
    fi
  }
  trap rollback_shelley ERR

  sudo install -o root -g root -m 0755 "$TMP/shelley" /usr/local/bin/shelley.new
  sudo mv /usr/local/bin/shelley.new /usr/local/bin/shelley
  sudo mkdir -p /etc/systemd/system/shelley.service.d
  printf '%s\n' '[Service]' 'Environment=SHELLEY_SKIP_VERSION_CHECK=true' \
    | sudo tee /etc/systemd/system/shelley.service.d/10-iv-managed.conf >/dev/null
  sudo systemctl daemon-reload
  sudo systemctl start shelley.service

  local healthy=false
  for _ in $(seq 1 20); do
    if sudo systemctl is-active --quiet shelley.service \
        && [[ $(shelley_version) == "$SHELLEY_VERSION" ]] \
        && [[ $(shelley_commit) == "$SHELLEY_COMMIT" ]]; then
      healthy=true
      break
    fi
    sleep 1
  done
  [[ $healthy == true ]]
  if [[ -S $HOME/.config/shelley/shelley.sock ]]; then
    curl -fsS -H 'X-Exedev-Userid: iv-provision-health' \
      --unix-socket "$HOME/.config/shelley/shelley.sock" \
      http://localhost/api/conversations >/dev/null
  fi
  trap - ERR
  printf '%s\n' "$backup_dir" > "$HOME/.local/state/iv-provision/shelley/current"
}

install_apex() {
  local actual
  actual=$(apex_version)
  echo "== Apex $APEX_VERSION ($APEX_ASSET_ARCH; installed: ${actual:-missing}) =="
  [[ $actual == "$APEX_VERSION" ]] && return
  download_verified \
    "https://github.com/ApexMarkdown/apex/releases/download/v${APEX_VERSION}/apex-${APEX_VERSION}-linux-${APEX_ASSET_ARCH}.tar.gz" \
    "$APEX_SHA256" "$TMP/apex.tar.gz"
  mkdir -p "$TMP/apex"
  tar -xzf "$TMP/apex.tar.gz" -C "$TMP/apex"
  sudo install -m 0755 \
    "$TMP/apex/apex-${APEX_VERSION}-linux-${APEX_ASSET_ARCH}/apex" \
    /usr/local/bin/apex
  [[ $(apex_version) == "$APEX_VERSION" ]]
}

remove_legacy_quarto
install_duckdb
install_tigris
install_herdr
install_agentsview
install_shelley
install_apex

echo "== doc-site and cloud helpers =="
for tool in render-site render-md-site provision-docsite gen-llms-txt shot install-cloud-cli; do
  sudo install -m 0755 "$IV_REPO/bin/$tool" "/usr/local/bin/$tool"
done
sudo install -m 0755 "$IV_REPO/bin/agentsview-source-daemon" /usr/local/bin/agentsview-source-daemon

# Install the source-daemon template unconditionally, but activate only after
# the separate network-identity and local-secret prerequisites are explicit.
# `systemctl --user` over a non-interactive SSH needs to be told where the user
# bus is. exeuntu sets DBUS_SESSION_BUS_ADDRESS as an image ENV so it is
# inherited and this Just Works; a minimal base need not, and then EVERY
# `systemctl --user` call fails with "Failed to connect to bus: No medium
# found". Because the disable branch below had a guarded `disable` followed by
# an UNGUARDED `daemon-reload`, `set -e` aborted the whole provision there —
# after the binaries were installed but before the agent config, MCP servers,
# skills and the lock file. A partial provision that reported success only in
# the exit code, which nothing was reading. Found 2026-07-29 on an exeslim-dev
# canary; latent on any first provision where the user manager has no bus in
# the environment.
#
# uctl: supply the address if it is missing, and never let a user-bus problem
# take down a provision run — this whole section is fail-closed by design, so
# failing to disable an already-absent unit must not be fatal.
uctl() {
  local rc=0
  XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" \
  DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}" \
    systemctl --user "$@" || rc=$?
  if (( rc != 0 )); then
    echo "  note: systemctl --user $1 failed (rc=$rc); user bus unavailable" >&2
  fi
  return 0
}

echo "== AgentsView source service =="
mkdir -p "$HOME/.config/systemd/user"
install -m 0644 "$IV_REPO/systemd/agentsview-source.service" \
  "$HOME/.config/systemd/user/agentsview-source.service"
SOURCE_ENV="$HOME/.config/agentsview/source.env"
if [[ -s $SOURCE_ENV ]] \
    && grep -qE '^AGENTSVIEW_AUTH_TOKEN=.+$' "$SOURCE_ENV" \
    && tailscale ip -4 >/dev/null 2>&1; then
  chmod 600 "$SOURCE_ENV"
  sudo loginctl enable-linger "$USER"
  uctl daemon-reload
  uctl enable --now agentsview-source.service
  echo "AgentsView source enabled (tailnet + per-host token present)"
else
  uctl disable --now agentsview-source.service >/dev/null 2>&1 || true
  uctl daemon-reload
  echo "AgentsView source disabled; requires tailnet reachability and $SOURCE_ENV"
fi

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

echo "== OS security patching (in-place) =="
# WHY IN-PLACE, not recreate. Recreating a VM was the original patching plan,
# and it is a poor one: a VM built from the current image already carried 3
# pending security updates the next day, because the image is rebuilt weekly
# and a VM freezes whatever build existed the day it was created. Recreate buys
# point-in-time freshness that decays immediately — and pays for it by
# destroying whatever working state the box holds. Patching in place is
# continuous and risks nothing.
#
# OUR OWN TIMER, not apt-daily. Both exeuntu and exeslim mask apt-daily.timer
# and apt-daily-upgrade.timer on purpose: those units hang or fight the
# platform in a container-as-VM. Unmasking them would undo a deliberate
# platform decision, so this ships a separate unit instead.
#
# NOT unattended-upgrades: it is python-based and there is no system python3
# here (uv's lives in ~/.local/bin, not on root's PATH), so installing it would
# pull ~30-50 MB of interpreter into every VM to run three apt commands.
#
# No automatic reboot. The kernel belongs to the host on a container-as-VM, so
# kernel packages are not the point; userspace CVEs are, and those take effect
# on the next process start.
sudo tee /etc/systemd/system/iv-apt-upgrade.service >/dev/null <<'UNIT'
[Unit]
Description=IV: apt update + upgrade (in-place OS patching)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
Environment=DEBIAN_FRONTEND=noninteractive
# --force-confold/confdef: never prompt, and never silently replace a config we
# manage. An interactive prompt in a timer unit hangs forever.
ExecStart=/usr/bin/apt-get update -qq
ExecStart=/usr/bin/apt-get -y -o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef upgrade
ExecStart=/usr/bin/apt-get -y autoremove
UNIT

sudo tee /etc/systemd/system/iv-apt-upgrade.timer >/dev/null <<'UNIT'
[Unit]
Description=IV: daily in-place OS patching

[Timer]
OnCalendar=daily
# Persistent so a VM that was stopped catches up on next boot rather than
# silently skipping its window; randomised so the fleet does not hit the
# mirrors in lockstep.
Persistent=true
RandomizedDelaySec=2h

[Install]
WantedBy=timers.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable --now iv-apt-upgrade.timer >/dev/null 2>&1 \
  && echo "  iv-apt-upgrade.timer enabled (daily, persistent)" \
  || echo "  [!] could not enable iv-apt-upgrade.timer"

echo "== provenance lockfile =="
LOCK="$HOME/iv-provision.lock"
{
  echo "provisioned_utc=$(date -u +%FT%TZ)"
  echo "provision_repo_sha=$(git -C "$IV_REPO" rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "arch=$DPKG_ARCH"
  echo "exeuntu_image_revision=$(jq -r '.Labels["org.opencontainers.image.revision"] // "unknown"' /exe.dev/etc/image.conf 2>/dev/null || echo unknown)"
  echo "exeuntu_image_created=$(jq -r '.Labels["org.opencontainers.image.created"] // "unknown"' /exe.dev/etc/image.conf 2>/dev/null || echo unknown)"
  echo "shelley_version=$(shelley_version)"
  echo "shelley_tag=$SHELLEY_TAG"
  echo "shelley_commit=$(shelley_commit)"
  echo "shelley_sha256=$(sha256sum /usr/local/bin/shelley 2>/dev/null | awk '{print $1}')"
  echo "duckdb_version=$(duckdb_version)"
  echo "aws_cli_version=$(aws_version)"
  echo "tigris_version=$(tigris_version)"
  echo "rclone_version=$(rclone_version)"
  echo "herdr_version=$(herdr_version)"
  echo "agentsview_version=$(agentsview_version)"
  echo "apex_version=$(apex_version)"
  echo "dotfiles_manifest_pin=$(tr -d '[:space:]' < "$IV_REPO/dotfiles-manifest.pin" 2>/dev/null || echo unknown)"
  echo "skills_count=$(wc -l < "$TEAM_SKILLS" | tr -d ' ')"
} | tee "$LOCK"

echo "== IV layer provisioned on stock exeuntu (see $LOCK) =="
