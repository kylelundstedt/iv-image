---
title: "Tailnet Join"
---

## Contract

A newly created VM starts off the tailnet, and joins during provisioning **iff the
`api-tailscale` integration is attached to it**. Nothing is baked in and no
credential ever reaches the VM: exe.dev injects the Tailscale OAuth credential at
the network edge, so the proxy is reachable only from a VM the control plane
deliberately attached it to.

That attachment *is* the consent signal. Least authority means it is normally
attached to nothing — attach it, provision, detach. An unattached VM simply stays
off the tailnet, and `provision-iv.sh` says so and carries on.

> **Corrected 2026-08-19.** This section previously said there was "no automatic
> join" and that a VM stays off the tailnet until someone runs the `join-tailnet`
> workflow by hand. That has never been how fleet VMs actually joined: the personal
> dotfiles `install.sh` has always performed the join automatically, by exactly the
> mechanism now in `provision-iv.sh`. Moving the tailscale *install* into the
> provisioner in 3.0.x without the *join* converted a one-command bring-up into a
> hand-run OAuth dance — a regression that stayed hidden because every existing VM
> had already joined via dotfiles.

> **Resolved 2026-08-18.** `provision-iv.sh` now installs `tailscale` from
> Tailscale's signed apt repository and enables `tailscaled`. Until then the
> client was not provided by this repo *or* the `exeslim-dev` base — it arrived
> via the personal dotfiles `install.sh` — so `join-tailnet` could not succeed on
> a freshly provisioned VM at all. Enabling the daemon does not join the tailnet;
> membership stays the explicit decision described below.

The v2.0.0 objection still holds, and this satisfies it. What was removed then was
**auto-join-on-boot**: it put every VM on the tailnet whether or not it belonged
there, and the logic had to live in a per-account setup hook or baked-in image
code, both of which drifted and coupled unrelated things together.

Joining during provisioning, gated on an integration the control plane attaches,
is not that. A VM is still just a VM until someone decides it should be a tailnet
node — the decision is the attachment, made off-VM, rather than a command typed on
the box. Nothing is baked in, nothing runs on boot, and the credential stays at
the edge.

## Joining a VM by hand (the `join-tailnet` skill)

Provisioning joins automatically. This skill remains for the cases it cannot
cover: a VM that was provisioned before the integration was attached and should
not be re-provisioned right now, or one being re-joined after a node was deleted.

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
> `tailscale-api` and said to attach it via a `tag:iv`. The name was wrong — it is
> `api-tailscale`, matching the `api-<service>` convention used by
> `api-motherduck-mcp` and friends — and it is attached **per VM** today, not by
> tag.
>
> So the `join-tailnet` procedure as documented could never have worked; every node
> on the tailnet joined through the personal dotfiles `install.sh`, which uses the
> correct hostname, and nothing surfaced the discrepancy until a VM was created
> that had no dotfiles overlay to fall back on.
>
> A first correction on the same day also claimed "no fleet VM carries an `iv` tag
> at all." That is false: `iv-provision` carries the exe.dev tag `iv`, set when it
> was created. Checking `tailscale status` — where the tag does not and cannot
> appear — is what made it look absent. See "Two tag systems" below, which is the
> confusion that produced both errors.

## Two tag systems, one word

The fleet is subject to two unrelated tagging systems, and the earlier drafts of
this document silently conflated them. They do not interact at all.

| | **Tailscale tags** | **exe.dev VM tags** |
| --- | --- | --- |
| Written | `tag:dev`, `tag:iv-aperture-pilot` | `iv`, `mcp-agent`, `fannie-sflpd` |
| Set by | the auth key used at `tailscale up`, or the Tailscale admin console | `ssh exe.dev tag <vm> <name>`, or `--tag` at creation |
| Governs | network reachability and the SSH policy | which integrations a VM receives |
| Read with | `tailscale status --json` | `curl reflection.int.exe.xyz/tags` |
| Lives in | the tailnet | the exe.dev control plane |

The trap is that exe.dev's *attachment syntax* borrows Tailscale's `tag:` prefix
— `integrations attach api-tailscale tag:iv` refers to the **exe.dev** tag `iv`,
not to anything Tailscale knows about. A reader who has just been thinking about
`tag:dev` will read that as a Tailscale tag every time.

Both documented errors came from this. "Attach it via a `tag:iv`" was written as
though exe.dev tags were Tailscale tags; "no fleet VM carries an `iv` tag" was
written after checking the Tailscale side, where an exe.dev tag can never appear.

### Where each stands today (2026-08-19)

**Tailscale `tag:dev` — uniform, and already automatic.** `provision-iv.sh` mints
every join key with `"tags":["tag:dev"]` hardcoded, so any VM this repo joins is
tagged correctly by construction. The SSH policy keys on `tag:dev`, which is what
makes `ssh <vm>` work fleet-wide.

The one gap is a node that joined by some *other* path. `iv-entire-agent-shelley`
joined via the old dotfiles `install.sh` carrying only `tag:iv-aperture-pilot`,
so SSH to it timed out — not refused, *timed out*, which is indistinguishable at
a glance from a dead host. It went unnoticed for weeks and was fixed by adding
`tag:dev` in the console (2026-08-19). Purpose tags and `tag:dev` coexist fine:
`iv-docs` carries `tag:dev` **and** `tag:iv-aperture-admin`.

**exe.dev `iv` — exists on one VM, unused for attachment.** `api-tailscale` is
attached per VM. Tagging the fleet `iv` and attaching to `tag:iv` is the
improvement described below.

### Proposal: attach `api-tailscale` to the exe.dev tag `iv`

```bash
ssh exe.dev tag <vm> iv                              # per existing fleet VM
ssh exe.dev integrations attach api-tailscale tag:iv # once
ssh exe.dev new --name=<vm> --tag=iv ...             # new VMs inherit it
```

What this buys: a **recreated VM rejoins on its own**. Today a fresh VM is inert
until someone attaches the integration by hand — and it cannot be reached from
another VM to fix, because it is not on the tailnet yet and `*.exe.xyz` needs an
exe.dev SSH key that no VM holds. The bootstrap is only breakable from a
workstation.

It also keeps the consent property this document argues for. The decision moves
from "attach an integration after creation" to "create it with `--tag=iv`" —
still deliberate, still made off-VM, but now durable across a recreate instead of
being lost with the disk.

The cost is honest: every `iv`-tagged VM can mint `tag:dev` auth keys, and the
proxy does not restrict which Tailscale API paths an attached VM may call. That
is a real widening. It should be weighed against the actual alternative, which is
not "nobody holds it" but "somebody attaches it under time pressure and forgets
to detach" — which is what happened to `repo-iv-provision-rw` on 2026-08-19. If
hard enforcement is wanted, the broker described at the end of this section is
the answer, and it is orthogonal to how the integration is attached.

### Why not `auto:all`

exe.dev also offers `integrations attach <name> auto:all`, which attaches to
every VM in the account **including every VM created in the future**. For
`api-tailscale` that is the wrong shape, and specifically it discards the
property the top of this document is built on: the attachment *is* the consent
signal.

Under `auto:all` there is no signal left — a throwaway sandbox, a client canary,
or a VM running untrusted generated code would all be able to mint preauthorized
`tag:dev` keys against the tailnet, and to call any other Tailscale API endpoint
the backing credential permits, up to and including deleting other nodes. "Least
authority means it is normally attached to nothing" and `auto:all` cannot both be
true.

The two integrations exe.dev ships with `auto:all` by default — `reflection` and
`llm` — are the contrast that makes the rule legible: both are read-mostly and
scoped to the VM asking, so a new VM having them harms nothing. Tailnet
membership is not in that class. `tag:iv` is the smallest change that fixes the
recreate problem without giving that up.

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
