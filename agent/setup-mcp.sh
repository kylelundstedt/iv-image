#!/bin/bash
# Pre-register exe.dev proxy MCP servers in ~/.claude.json so they're available
# on first Claude Code launch. Only adds servers — personal dotfiles can overlay.
set -euo pipefail

CLAUDE_JSON="$HOME/.claude.json"

# Seed the file if it doesn't exist
if [ ! -f "$CLAUDE_JSON" ]; then
    echo '{}' > "$CLAUDE_JSON"
fi

# Merge MCP servers into the existing config (jq is on exeuntu PATH)
jq '.mcpServers = (.mcpServers // {}) + {
  "motherduck": {
    "type": "http",
    "url": "https://motherduck-mcp.int.exe.xyz/mcp"
  },
  "github-work": {
    "type": "http",
    "url": "https://github-mcp-work.int.exe.xyz/mcp/"
  }
}' "$CLAUDE_JSON" > "$CLAUDE_JSON.tmp" && mv "$CLAUDE_JSON.tmp" "$CLAUDE_JSON"
