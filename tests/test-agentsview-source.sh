#!/usr/bin/env bash
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
WRAPPER="$REPO/bin/agentsview-source-daemon"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home"

cat > "$TMP/bin/tailscale" <<'EOF'
#!/bin/sh
case "$1" in
  ip) echo 100.64.0.10 ;;
  status) echo '{"MagicDNSSuffix":"example.ts.net"}' ;;
  *) exit 1 ;;
esac
EOF
cat > "$TMP/bin/hostname" <<'EOF'
#!/bin/sh
echo source-canary
EOF
cat > "$TMP/bin/ss" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$TMP/bin/agentsview" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$AGENTSVIEW_TEST_ARGS"
EOF
chmod +x "$TMP/bin/"*

# Missing token fails closed.
if HOME="$TMP/home" PATH="$TMP/bin:$PATH" AGENTSVIEW_BIN="$TMP/bin/agentsview" \
    "$WRAPPER" >/dev/null 2>&1; then
  echo "source wrapper accepted a missing token" >&2
  exit 1
fi

ARGS="$TMP/args"
HOME="$TMP/home" PATH="$TMP/bin:$PATH" \
  AGENTSVIEW_AUTH_TOKEN=test-token \
  AGENTSVIEW_BIN="$TMP/bin/agentsview" \
  AGENTSVIEW_TEST_ARGS="$ARGS" \
  "$WRAPPER"

grep -qx 'serve' "$ARGS"
grep -qx '100.64.0.10' "$ARGS"
grep -qx 'http://source-canary.example.ts.net:8080' "$ARGS"
grep -qx -- '--require-auth' "$ARGS"
! grep -qx '0.0.0.0' "$ARGS"
[[ $(stat -c '%a' "$TMP/home/.agentsview") == 700 ]]

echo "agentsview source wrapper tests passed"
