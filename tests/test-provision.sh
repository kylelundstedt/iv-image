#!/usr/bin/env bash
# Validate provision-iv.sh version/checksum selection and command parsing without
# installing packages or modifying the host.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
script="$repo/provision-iv.sh"

bash -n "$script"

# The AWS CLI pins are deliberately absent: 307069f moved the AWS CLI out of the
# default provision path and into the on-demand `bin/install-cloud-cli`, where
# AWS_CLI_VERSION now lives. Everything below is still installed by
# provision-iv.sh itself.
required=(
  DUCKDB_VERSION TIGRIS_VERSION RCLONE_VERSION
  HERDR_VERSION AGENTSVIEW_VERSION SHELLEY_VERSION SHELLEY_TAG SHELLEY_COMMIT APEX_VERSION
  DUCKDB_SHA256_AMD64 DUCKDB_SHA256_ARM64
  TIGRIS_SHA256_AMD64 TIGRIS_SHA256_ARM64
  RCLONE_SHA256_AMD64 RCLONE_SHA256_ARM64
  HERDR_SHA256_X86_64 HERDR_SHA256_AARCH64
  AGENTSVIEW_SHA256_AMD64 AGENTSVIEW_SHA256_ARM64
  SHELLEY_SHA256_AMD64 SHELLEY_SHA256_ARM64
  APEX_SHA256_AMD64 APEX_SHA256_ARM64
  ENTIRE_VERSION ENTIRE_PLUGIN_VERSION
  ENTIRE_SHA256_AMD64 ENTIRE_SHA256_ARM64
  CLAUDE_CODE_VERSION CODEX_VERSION UV_VERSION
  CLAUDE_CODE_SHA256_AMD64 CLAUDE_CODE_SHA256_ARM64
  CODEX_SHA256_AMD64 CODEX_SHA256_ARM64
  UV_SHA256_AMD64 UV_SHA256_ARM64
)

# Not in the loop above: these are single-value pins with no _AMD64/_ARM64 pair,
# so they need the 64-hex check applied by name rather than by suffix.
# entire-agent-shelley is a shell/Python polyglot and the AgentsView adapter is
# Python, so both are arch-independent.
for name in ENTIRE_PLUGIN_SHA256 ENTIRE_AGENTSVIEW_SHA256; do
  value=$(sed -nE "s/^${name}=//p" "$script")
  [[ $value =~ ^[0-9a-f]{64}$ ]] || {
    echo "invalid SHA-256 pin: $name=$value" >&2
    exit 1
  }
done

# The vendored adapter must match the pin the provisioner verifies, or every
# provision fails at the checksum instead of at review time.
vendored="$repo/vendor/entire-agent-agentsview/entire-agent-agentsview"
if [[ -f $vendored ]]; then
  want=$(sed -nE 's/^ENTIRE_AGENTSVIEW_SHA256=//p' "$script")
  got=$(sha256sum "$vendored" | awk '{print $1}')
  [[ $want == "$got" ]] || {
    echo "vendored entire-agent-agentsview does not match its pin" >&2
    echo "  pin:  $want" >&2
    echo "  file: $got" >&2
    exit 1
  }
fi

# Entire's CLI pin must stay at the version entire-agent-shelley was qualified
# against. Bumping one without the other is the failure this guards.
grep -q 'qualified only against 0.8.42' "$script" || {
  echo "provisioner no longer records why the Entire CLI pin is held back" >&2
  exit 1
}

for name in "${required[@]}"; do
  value=$(sed -nE "s/^${name}=//p" "$script")
  [[ -n $value ]] || { echo "missing provision pin: $name" >&2; exit 1; }
  if [[ $name == *_SHA256_* ]]; then
    [[ $value =~ ^[0-9a-f]{64}$ ]] || {
      echo "invalid SHA-256 pin: $name=$value" >&2
      exit 1
    }
  fi
done

if grep -Eq 'releases/latest|rclone-current|curl[^|]*\|[^|]*(sh|bash)' "$script"; then
  echo "mutable release URL or curl-pipe-shell found in provisioner" >&2
  exit 1
fi

for managed in duckdb aws tigris rclone herdr agentsview shelley apex; do
  grep -q "/usr/local/bin/${managed}" "$script" || {
    echo "managed tool is not probed by absolute path: $managed" >&2
    exit 1
  }
done

grep -q 'run as the VM login user, not with sudo' "$script"

# Claude settings must be MERGED, not overwritten: overwriting silently deleted the
# personal overlay's SessionStart refresh-env hook, and the mitigation (re-run the
# overlay afterwards) both failed in practice and cannot self-heal, since the hook
# that would restore it lives in the clobbered file.
grep -q 'MERGE the team Claude settings' "$script" || {
  echo "provisioner must merge ~/.claude/settings.json, not overwrite it" >&2
  exit 1
}
grep -q 'SHELLEY_SKIP_VERSION_CHECK=true' "$script"

# The restart decision must read systemd's MainPID, not `pgrep`. shelley.service
# uses KillMode=process, so terminal helpers -- also named "shelley" -- survive a
# restart, predate the drop-in and sort first by PID, which made the check report
# "not in effect" on every run and restart Shelley forever.
grep -q "systemctl show shelley.service -p MainPID" "$script" || {
  echo "restart check must use systemd MainPID, not pgrep" >&2
  exit 1
}
# Nothing may wait on or inspect "a process named shelley": KillMode=process means
# terminal helpers outlive the service and share the name.
if grep -vE '^\s*#' "$script" | grep -q 'pgrep -x shelley'; then
  echo "provisioner still matches processes by name; use systemd MainPID/is-active" >&2
  exit 1
fi

# The socket must be stopped BEFORE the service. shelley.service is BindsTo= the
# socket, so stopping only the service leaves the socket able to activate the old
# binary, which then self-upgrades over the pinned install (observed on kgl-songs
# 2026-08-17, where a clean provision silently reverted a minute later).
socket_stop=$(grep -n 'systemctl stop shelley.socket' "$script" | head -1 | cut -d: -f1)
service_stop=$(grep -n 'systemctl stop shelley.service' "$script" | head -1 | cut -d: -f1)
[[ -n $socket_stop && -n $service_stop && $socket_stop -lt $service_stop ]] || {
  echo "shelley.socket must be stopped before shelley.service (socket=$socket_stop service=$service_stop)" >&2
  exit 1
}
grep -q 'Shelley health check failed; restoring prior binary' "$script"
grep -q 'sqlite3.connect(src)' "$script"
grep -q 'unsafe prior skill name' "$script"
grep -q 'ln -sT' "$script"

source_wrapper="$repo/bin/agentsview-source-daemon"
unit="$repo/systemd/agentsview-source.service"
bash -n "$source_wrapper"
grep -q ': "${AGENTSVIEW_AUTH_TOKEN:?' "$source_wrapper"
grep -q -- '--host "$TS_IP"' "$source_wrapper"
grep -q -- '--public-url "$PUBLIC_URL"' "$source_wrapper"
! grep -q '0\.0\.0\.0' "$source_wrapper"
grep -q '^EnvironmentFile=%h/.config/agentsview/source.env$' "$unit"
grep -q '^UMask=0077$' "$unit"
grep -q '^NoNewPrivileges=true$' "$unit"

printf '%s\n' 'provision script tests passed'
