---
title: "Tailnet Join"
---

## Contract

`iv-image` VMs do **not** join the Tailscale tailnet automatically. The image
ships `tailscaled` enabled but idle — no baked bootstrap script, no
`/exe.dev/setup` hook, no Tailscale API access on the VM. A VM stays off the
tailnet until something explicitly runs `tailscale up` on it.

This is deliberate. Auto-join-on-boot put every VM on the tailnet whether or not
it belonged there, and the logic to do it had to live somewhere — a per-account
setup hook or baked-in image code — both of which drifted and coupled unrelated
things together. On-demand join keeps the default clean: a VM is just a VM until
you decide it should be a tailnet node.

## Joining a VM (the `join-tailnet` skill)

A fresh VM is reachable over the exe.dev edge (`ssh <vm>.exe.xyz`) before it is
on the tailnet. The `join-tailnet` agent skill uses that edge path to bootstrap
the tailnet:

1. SSH into the VM over `*.exe.xyz` (no tailnet required).
2. Mint a one-use, ephemeral, preauthorized `tag:dev` auth key by POSTing to the
   `tailscale-api` HTTP proxy (`https://tailscale-api.int.exe.xyz`). exe.dev
   injects the real API credential at the proxy layer, so the VM never sees the
   secret.
3. Run `tailscale up --ssh --accept-dns --hostname=$(hostname)` with that key.

By hand it is two commands on the VM:

```bash
ssh -o ConnectTimeout=30 <vm>.exe.xyz 'bash -s' <<'REMOTE'
set -euo pipefail
KEY=$(curl -fsSL -X POST https://tailscale-api.int.exe.xyz/api/v2/tailnet/-/keys \
  -H "Content-Type: application/json" \
  -d '{"capabilities":{"devices":{"create":{"reusable":false,"ephemeral":true,"preauthorized":true,"tags":["tag:dev"]}}}}' \
  | jq -r .key)
sudo tailscale up --ssh --accept-dns --hostname="$(hostname)" --authkey="$KEY"
tailscale status
REMOTE
```

After it joins, use `ssh <vm>` (Tailscale SSH) for everything else.

## Required exe.dev integration

The join step needs the `tailscale-api` integration attached to the VM so it can
mint the key. Attach it via the `iv` tag and create VMs with that tag:

```bash
ssh exe.dev integrations attach tailscale-api tag:iv
ssh exe.dev new --image=iv-registry.exe.xyz:5000/iv-image:2 --name=<vm> --tag=iv
```

The integration must proxy to the Tailscale API base URL `https://api.tailscale.com`;
the VM-side endpoint is `https://tailscale-api.int.exe.xyz/api/v2/tailnet/-/keys`.

A direct HTTP proxy integration does not restrict which Tailscale API paths an
attached VM can call — code on the VM can hit any endpoint the backing
credential permits. The skill only mints an auth key, but if you need hard
server-side enforcement of "create exactly one key for this VM," put a small
broker in front instead of attaching the raw proxy.

## Security boundary

The VM never receives the long-lived Tailscale API token or OAuth client secret.
It receives only the one-use auth key it presents to `tailscale up` — short-lived,
non-reusable, preauthorized, and tagged. Do not bake Tailscale credentials into
the image, a setup script, environment variables, dotfiles, or repo files.

## Stale-node `-1` suffix

Tailscale MagicDNS names are sticky per node. If you rebuild a VM with a hostname
that an old, not-yet-reaped ephemeral node still holds, the **new** VM registers
as `<name>-1`. Because the join path holds no device-delete authority, it does
not clean up the old node.

If a reused hostname collides, delete the stale node from a trusted admin context
(the Tailscale admin console, or the API from a workstation holding the real
credential) — not from the freshly created VM. Or just wait: ephemeral nodes are
reaped after they disconnect, and the next rebuild gets the clean name.

## Operational notes

- A VM that is never joined simply stays reachable over `ssh <vm>.exe.xyz`.
- Override the proxy URL, tag, or hostname by editing the join command
  (`tailscale-api.int.exe.xyz`, `tag:dev`, `$(hostname)`).
- If the `tailscale-api` integration is backed by a Tailscale API access token,
  that token has the normal API-token expiry and must be rotated in exe.dev
  before it expires.
