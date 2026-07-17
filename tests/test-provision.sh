#!/usr/bin/env bash
# Validate provision-iv.sh version/checksum selection and command parsing without
# installing packages or modifying the host.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
script="$repo/provision-iv.sh"

bash -n "$script"

required=(
  DUCKDB_VERSION QUARTO_VERSION AWS_CLI_VERSION TIGRIS_VERSION RCLONE_VERSION
  HERDR_VERSION
  DUCKDB_SHA256_AMD64 DUCKDB_SHA256_ARM64
  QUARTO_SHA256_AMD64 QUARTO_SHA256_ARM64
  AWS_CLI_SHA256_X86_64 AWS_CLI_SHA256_AARCH64
  TIGRIS_SHA256_AMD64 TIGRIS_SHA256_ARM64
  RCLONE_SHA256_AMD64 RCLONE_SHA256_ARM64
  HERDR_SHA256_X86_64 HERDR_SHA256_AARCH64
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

for managed in duckdb quarto aws tigris rclone herdr; do
  grep -q "/usr/local/bin/${managed}" "$script" || {
    echo "managed tool is not probed by absolute path: $managed" >&2
    exit 1
  }
done

grep -q 'run as the VM login user, not with sudo' "$script"
grep -q 'unsafe prior skill name' "$script"
grep -q 'ln -sT' "$script"

printf '%s\n' 'provision script tests passed'
