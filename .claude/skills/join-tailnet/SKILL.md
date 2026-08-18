---
name: join-tailnet
description: Join an exe.dev VM to the Tailscale tailnet on demand. SSHes in over *.exe.xyz, ensures tailscaled is running, and runs tailscale up with a one-use key minted via the tailscale-api proxy.
---

# Join Tailnet

Joins an exe.dev VM to the IV Tailscale tailnet. The VM must have
the `tailscale-api` integration attached (use `--tag=iv` at creation).

## Usage

The user provides a VM name (e.g. `iv-gitlake`). The skill SSHes in over
the exe.dev edge and runs two commands on the VM.

## Steps

1. **SSH into the VM over `*.exe.xyz`** (one attempt, `ConnectTimeout=30`).
2. **Run the join commands** on the VM:

```bash
ssh -o ConnectTimeout=30 <vm>.exe.xyz 'bash -s' <<'REMOTE'
set -euo pipefail
# Stock exeuntu may ship tailscaled disabled; enable and start it before joining.
sudo systemctl enable --now tailscaled
# Two-step (OAuth client behind the proxy, 2026-07): exchange for a 1h token
# via the proxy, then mint against the public API (the proxy injects
# Authorization on every request, so only the exchange goes through it).
TOKEN=$(curl -fsSL -X POST -d "grant_type=client_credentials" \
  https://tailscale-api.int.exe.xyz/api/v2/oauth/token | jq -er .access_token)
trap 'rm -f "${auth_config:-}"; unset TOKEN KEY' EXIT
auth_config=$(mktemp)
chmod 600 "$auth_config"
printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" > "$auth_config"
KEY=$(curl --config "$auth_config" -fsSL -X POST \
  https://api.tailscale.com/api/v2/tailnet/-/keys \
  -H "Content-Type: application/json" \
  -d '{"capabilities":{"devices":{"create":{"reusable":false,"ephemeral":true,"preauthorized":true,"tags":["tag:dev"]}}}}' \
  | jq -er .key)
rm -f "$auth_config"
sudo tailscale up --ssh --accept-dns --hostname="$(hostname)" --authkey="$KEY"
tailscale status
REMOTE
```

3. **Verify** the VM appears in `tailscale status` output.

After it joins, use `ssh <vm>` (Tailscale SSH) for everything else.

## Preflight: confirm the integration is actually attached

Do this **first**. The mint fails at the OAuth exchange with an opaque proxy
error when `tailscale-api` is missing, and nothing connects that to a tag that
was never set at creation time.

```bash
ssh -o ConnectTimeout=30 <vm>.exe.xyz \
  "curl -s https://reflection.int.exe.xyz/integrations | jq -r '.integrations[].name' | grep -qx tailscale-api \
     && echo 'tailscale-api: attached' \
     || echo 'tailscale-api: MISSING -- VM was not created with --tag=iv'"
```

If it is missing, attach it before going further (`ssh exe.dev tag <vm> iv`, or
`ssh exe.dev integrations attach tailscale-api vm:<vm>`).

This is not hypothetical: `iv-foundry-stage2` sits on the tailnet with **no** `iv`
tag and **no** `tailscale-api` integration, so it joined by a path it can no
longer reproduce and cannot rejoin if it ever drops off. Worth auditing the rest
of the fleet the same way.

## Prerequisites

- The VM must be created with `--tag=iv` so the `tailscale-api` integration is attached.
- `tailscale` itself is installed by `provision-iv.sh` (since 2026-08-18), which
  also enables `tailscaled`. On a VM that has not been provisioned yet, install
  it first — the `exeslim-dev` base does not carry it, and neither did stock
  exeuntu in a started state.

## SSH discipline

- **One SSH attempt at a time.** Never launch parallel SSH to `*.exe.xyz`.
- If SSH fails, wait 30-60s before one more attempt.
