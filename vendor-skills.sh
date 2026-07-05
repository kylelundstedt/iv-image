#!/usr/bin/env bash
# Refresh the vendored ./skills snapshot AND the generated agent/mcp-servers.json
# from the dotfiles provisioning manifests (kylelundstedt/dotfiles
# provisioning/{skills,mcp}.manifest) at the commit pinned in
# ./dotfiles-manifest.pin. dotfiles owns the list; this repo pins WHICH revision
# of the list it baked, so the team image stays reproducible from a git commit.
#
# Run occasionally on any machine with node + jq; commit the result to re-pin.
# provision-iv.sh installs from the committed snapshot with NO network — this
# is the ONLY step that touches upstream/node.
#
# Bump the pin: DOTFILES_SHA=<sha> ./vendor-skills.sh   (rewrites the pin file)
#
# Installs into a throwaway HOME so your real ~/.agents/skills is left untouched.
set -euo pipefail
cd "$(dirname "$0")"

command -v npx >/dev/null || { echo "vendor-skills: need node/npx on PATH" >&2; exit 1; }
command -v jq  >/dev/null || { echo "vendor-skills: need jq on PATH" >&2; exit 1; }

PIN_FILE="dotfiles-manifest.pin"
if [ -n "${DOTFILES_SHA:-}" ]; then
  printf '%s\n' "$DOTFILES_SHA" > "$PIN_FILE"
fi
PIN="$(tr -d '[:space:]' < "$PIN_FILE")"
[ -n "$PIN" ] || { echo "vendor-skills: empty $PIN_FILE" >&2; exit 1; }
RAW="https://raw.githubusercontent.com/kylelundstedt/dotfiles/$PIN/provisioning"

SKILLS_MANIFEST="$(curl -fsSL "$RAW/skills.manifest")"
MCP_MANIFEST="$(curl -fsSL "$RAW/mcp.manifest")"
manifest_rows() { grep -vE '^[[:space:]]*#|^[[:space:]]*$' <<< "$1"; }

OUT="$(pwd)/skills"
SERVERS_OUT="$(pwd)/agent/mcp-servers.json"

# --- skills: install the manifest's team rows into a throwaway HOME ---------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"
mkdir -p "$HOME/.agents/skills"

# The loop feeds on fd 9, NOT stdin: npx (and other children) read stdin and
# would silently eat the remaining manifest rows — first observed as
# "vendored 1 skills" when this loop used stdin.
while read -u 9 -r layer method args; do
  [ "$layer" = "team" ] || continue
  case "$method" in
    npx)
      # word-splitting of $args is intentional (repo + optional -s flags)
      # shellcheck disable=SC2086
      npx -y skills add -g -y $args
      ;;
    curl)
      # args = "<name> <url>" — no GitHub repo, fetch the skill file directly
      name="${args%% *}"; url="${args#* }"
      mkdir -p "$HOME/.agents/skills/$name"
      curl -fsSL "$url" -o "$HOME/.agents/skills/$name/SKILL.md"
      ;;
    *) echo "vendor-skills: unknown method '$method' ($args)" >&2; exit 1 ;;
  esac
done 9< <(manifest_rows "$SKILLS_MANIFEST")

# Replace the vendored snapshot with the freshly resolved trees.
rm -rf "$OUT"
mkdir -p "$OUT"
cp -a "$HOME/.agents/skills/." "$OUT/"

# --- mcp: generate agent/mcp-servers.json from the team rows' vm-urls -------
manifest_rows "$MCP_MANIFEST" \
  | awk -F'|' '$2 ~ /team/ {gsub(/^ +| +$/,"",$1); gsub(/^ +| +$/,"",$3); print $1"\t"$3}' \
  | jq -Rn 'reduce (inputs | split("\t")) as $r ({}; . + {($r[0]): {type: "http", url: $r[1]}})' \
  > "$SERVERS_OUT"

echo "vendored $(find "$OUT" -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ') skills + $(jq 'length' "$SERVERS_OUT") MCP servers from dotfiles@${PIN:0:12} — commit to pin"
