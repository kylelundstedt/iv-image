---
title: "Tailnet Join"
---

## Contract

A newly created VM starts off the tailnet. There is no baked bootstrap script
and no automatic join. A VM stays off the tailnet until the `join-tailnet`
workflow explicitly enables the daemon and runs `tailscale up`.

> **Resolved 2026-08-18.** `provision-iv.sh` now installs `tailscale` from
> Tailscale's signed apt repository and enables `tailscaled`. Until then the
> client was not provided by this repo *or* the `exeslim-dev` base — it arrived
> via the personal dotfiles `install.sh` — so `join-tailnet` could not succeed on
> a freshly provisioned VM at all. Enabling the daemon does not join the tailnet;
> membership stays the explicit decision described below.

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
   `api-tailscale` HTTP proxy (`https://api-tailscale.int.exe.xyz`). exe.dev
   injects the real API credential at the proxy layer, so the VM never sees the
   secret.
3. Run `tailscale up --ssh --accept-dns --hostname=$(hostname)` with that key.

By hand it is two commands on the VM:

```bash
ssh -o ConnectTimeout=30 <vm>.exe.xyz 'bash -s' <<'REMOTE'
set -euo pipefail
# Two-step (OAuth client behind the proxy, 2026-07): exchange for a 1h token
# via the proxy, then mint against the public API (the proxy injects
# Authorization on every request, so only the exchange goes through it).
TOKEN=$(curl -fsSL -X POST -d "grant_type=client_credentials" \
  https://api-tailscale.int.exe.xyz/api/v2/oauth/token | jq -er .access_token)
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

After it joins, use `ssh <vm>` (Tailscale SSH) for everything else.

## Required exe.dev integration

The join step needs the `api-tailscale` integration attached to the VM so it can
mint the key. **Attach it explicitly, per VM:**

```bash
ssh exe.dev new --name=<vm>
ssh exe.dev integrations attach api-tailscale vm:<vm>
```

> **Corrected 2026-08-19.** This section previously named the integration
> `tailscale-api` and said to attach it via a `tag:iv`. Both were wrong, and had
> been since they were written: the integration is `api-tailscale` (matching the
> `api-<service>` convention used by `api-motherduck-mcp` and friends), and it is
> attached **per VM** — nine of them as of today, none by tag. No fleet VM carries
> an `iv` tag at all.
>
> So the `join-tailnet` procedure as documented could never have worked; every node
> on the tailnet joined through the personal dotfiles `install.sh`, which uses the
> correct hostname, and nothing surfaced the discrepancy until a VM was created
> that had no dotfiles overlay to fall back on.
>
> Attaching to `tag:iv` and tagging the fleet would be a genuine improvement — it
> is what lets a recreated VM rejoin without a manual step — but that is a change
> to make deliberately, not a state to document as though it exists.

The integration must proxy to the Tailscale API base URL `https://api.tailscale.com`;
the VM-side endpoint that matters is `https://api-tailscale.int.exe.xyz/api/v2/oauth/token`
(the only call that needs the injected credentials — everything after uses the
returned 1h Bearer token against the public API).

A direct HTTP proxy integration does not restrict which Tailscale API paths an
attached VM can call — code on the VM can hit any endpoint the backing
credential permits. The skill only mints an auth key, but if you need hard
server-side enforcement of "create exactly one key for this VM," put a small
broker in front instead of attaching the raw proxy.

## Upgrading a VM to a new revision

The normal upgrade is an in-place re-provision: check out a newer `iv-provision`
tag/sha in `~/iv-provision` and run `provision-iv.sh` again. This updates the team
software/configuration layer and rewrites `~/iv-provision.lock` without wiping
the VM or changing its tailnet identity. The `upgrade-vm` skill documents this
as Path A.

A full destroy/recreate is only needed for a fresh disk or an exe.dev-managed
base change that re-provisioning cannot address. In that exceptional path,
destroy the VM, delete the stale tailnet node from a trusted workstation,
recreate from the pinned base image, rejoin, and re-provision. It **wipes the VM's local
disk**.

## Security boundary

The VM never receives the long-lived Tailscale API token or OAuth client secret.
It receives only the one-use auth key it presents to `tailscale up` — short-lived,
non-reusable, preauthorized, and tagged. Do not bake Tailscale credentials into
the image, a setup script, environment variables, dotfiles, or repo files.

## Alternatives considered

Two simpler-looking paths exist. Both were evaluated 2026-07-28 and rejected;
the two-step mint above is the minimum shape that keeps the long-lived
credential off the VM while still producing a **tag-owned** node.

**OAuth client secret used directly as the auth key.** Tailscale accepts an
OAuth client secret in place of an auth key
(`tailscale up --auth-key='$SECRET?ephemeral=true&preauthorized=true'
--advertise-tags=tag:dev`), and such devices stay tag-owned. This would collapse
the mint to zero API calls — but it puts the raw client secret in the VM's
process arguments, which is exactly what the exe.dev proxy exists to prevent.
Two `curl` calls is the price of the security boundary above.

**OAuth device provisioning**
(<https://tailscale.com/docs/features/oauth-apps/device-provisioning>, alpha as
of 2026-06). An authorization-code flow where the access token _is_ the auth
key — no separate key-creation call. It does not fit:

- It requires a **human consent click per device**, with no refresh tokens. The
  join path is unattended by design; an agent runs it and the VM comes up.
- Devices are **user-owned, not tag-owned**. The dotfiles ssh_config dispatches
  on `tag:dev` via `Match host *.ts.net exec "ssh-tailnet-tagged %h tag:dev"`,
  which is what lets a new VM work without re-running `install.sh`. Untagged
  user devices would need a hand-written stanza each, and any ACL keyed on
  `tag:dev` would miss them.
- "Only users in the same tailnet as the OAuth app can authorize devices
  through it" — at odds with the per-client-tailnet multi-tenant direction.

It is aimed at internal tools provisioning devices on behalf of named users (an
IT self-service portal), not at machine-to-machine fleet enrollment. Revisit
only if the shape of the fleet changes to want user-attributed nodes.

## Stale-node `-1` suffix

Tailscale MagicDNS names are sticky per node. If you rebuild a VM with a hostname
that an old, not-yet-reaped ephemeral node still holds, the **new** VM registers
as `<name>-1`. Because the join path holds no device-delete authority, it does
not clean up the old node.

For the common case, re-provisioning in place keeps the existing node and name.
If a full rebuild with a reused hostname collides, delete the stale node from a
trusted admin context (the Tailscale admin console, or the API from a workstation
holding the real credential) — not from the freshly created VM. Or wait for the
ephemeral node to be reaped. The `upgrade-vm` skill documents both paths.

## Operational notes

- A VM that is never joined simply stays reachable over `ssh <vm>.exe.xyz`.
- Override the proxy URL, tag, or hostname by editing the join command
  (`api-tailscale.int.exe.xyz`, `tag:dev`, `$(hostname)`).
- If the `api-tailscale` integration is backed by a Tailscale API access token,
  that token has the normal API-token expiry and must be rotated in exe.dev
  before it expires.
