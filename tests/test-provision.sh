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
)

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
grep -q 'SHELLEY_SKIP_VERSION_CHECK=true' "$script"
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
