---
name: upgrade-vm
description: Upgrade an IV exe.dev VM's software layer by re-provisioning it in place at a newer iv-provision commit (no recreate, no disk wipe). Falls back to a full destroy/recreate only when a fresh disk or a base change is actually required.
---

# Upgrade VM

IV VMs run the **`ghcr.io/kylelundstedt/exeslim-dev`** base (which keeps Shelley
via `LABEL exe.dev/install-shelley=true` plus its own units) and get their
tooling from `provision-iv.sh` in the `iv-provision` repo. So "upgrading" a VM is
normally just **re-running the provisioner at a newer commit** — in place, no
recreate, no disk wipe, no tailnet churn.

Full destroy/recreate is now the exception, needed only when you genuinely want a
fresh disk or the exe.dev-managed base has changed in a way re-provisioning can't
pick up.

## Path A — Re-provision in place (default)

The user provides the **VM name** and optionally a **target tag/sha** of the
`iv-provision` repo (defaults to the latest on the default branch).

**One SSH command at a time** — never parallel SSH to `*.exe.xyz` or `exe.dev`.

```bash
ssh -o ConnectTimeout=30 <vm>.exe.xyz "cd ~/iv-provision \
  && git fetch --tags --quiet \
  && git checkout --detach <tag-or-sha> \
  && ~/iv-provision/provision-iv.sh \
  && ~/iv-provision/tests/smoke-provision.sh ~/iv-provision"
```

This re-pins tools and re-installs the vendored skills + agent config, and
rewrites `~/iv-provision.lock`. Verify:

```bash
ssh -o ConnectTimeout=30 <vm>.exe.xyz "cat ~/iv-provision.lock"
```

If `~/iv-provision` doesn't exist yet (older VM), clone it first — see `bootstrap.md`.

**Then, if the VM has a personal dotfiles overlay (`~/dotfiles` exists),
re-run it.** `provision-iv.sh` overwrites `~/.claude/settings.json` with the
team default, which wipes any hooks the overlay spliced in (e.g. a SessionStart
auto-refresh) — and a refresh hook that lives in the clobbered file cannot heal
itself:

```bash
ssh -o ConnectTimeout=30 <vm>.exe.xyz "cd ~/dotfiles && git pull --ff-only && ./install.sh"
```

## Path B — Full destroy + recreate (only when required)

This **wipes the VM's local disk** — it reprovisions, it does not migrate state.
Use only when Path A can't deliver the change.

Run sequentially. **One SSH command at a time.**

### 1. Confirm with the user

This is destructive. Confirm the VM name and that wiping its disk is acceptable.

### 2. Destroy the old VM

Destroy the old VM before creating the replacement. The stale Tailscale node can
still be located by hostname afterward, and must be deleted before the new VM
joins.

```bash
ssh -o ConnectTimeout=30 exe.dev rm <vm>
```

### 3. Delete the stale Tailscale node

Delete the old node before the replacement joins, otherwise the new VM gets a
`-1` suffix. This workstation-specific path expects the 1Password CLI and the
Industry Vault account. Mint a short-lived (1h) access token from the Tailscale
OAuth client — the old static API key is revoked (2026-07); see `tailnet.md`
for the OAuth setup. Credentials are passed through curl config on stdin
rather than exposed in curl's process arguments:

```bash
TS_TOKEN=$(printf 'user = "%s:%s"\n' \
    "$(op read 'op://Employee/Tailscale OAuth Dev/Client ID' --account industryvault.1password.com)" \
    "$(op read 'op://Employee/Tailscale OAuth Dev/Client secret' --account industryvault.1password.com)" \
  | curl --config - -fsS -d grant_type=client_credentials \
      https://api.tailscale.com/api/v2/oauth/token \
  | jq -er .access_token)

curl_with_tailscale_auth() {
  printf 'header = "Authorization: Bearer %s"\n' "$TS_TOKEN" \
    | curl --config - "$@"
}

NODE_ID=$(curl_with_tailscale_auth -fsSL \
  https://api.tailscale.com/api/v2/tailnet/-/devices \
  | jq -er --arg hostname "<vm>" \
      '[.devices[] | select(.hostname == $hostname) | .id] | unique | if length == 1 then .[0] else error("expected exactly one matching node") end')

curl_with_tailscale_auth -fsSL -X DELETE \
  "https://api.tailscale.com/api/v2/device/$NODE_ID"
unset TS_TOKEN
```

### 4. Remove stale SSH state

```bash
ssh-keygen -R <vm> 2>/dev/null || true
ssh -O exit <vm> 2>/dev/null || true
ssh -O exit <vm>.exe.xyz 2>/dev/null || true
```

### 5. Create the new VM (IV dev base)

Use the exe.dev VM tag `iv` so the required integrations are attached. This is
not the provisioning repository release tag.

Recreate is also the **only** way to pick up a newer base image — exe.dev fixes
a VM's image at creation. Take the current immutable build ID from the
[package page](https://github.com/kylelundstedt/exeslim/pkgs/container/exeslim-dev).
Use the build ID rather than a mutable tag here specifically: the whole point of
this path is to land on a *known* base, and exe.dev caches mutable tags for up to
24 h (`:<date>` and `:<sha>` included — only `latest`/`main`/`master` are 1 h).

```bash
ssh -o ConnectTimeout=30 exe.dev new --name=<vm> --tag=iv \
  --image=ghcr.io/kylelundstedt/exeslim-dev:<date>.<run>.<attempt>
```

If the user specified integrations, attach them:

```bash
ssh -o ConnectTimeout=30 exe.dev integrations attach <integration> vm:<vm>
```

### 6. Wait for the VM to boot

Wait ~20s, then try one SSH with `ConnectTimeout=30`:

```bash
sleep 20
ssh -o ConnectTimeout=30 <vm>.exe.xyz echo "VM is up"
```

If it fails, wait 30-60s and try once more.

### 7. Rejoin the tailnet + provision

Use the `join-tailnet` skill, then run the full bring-up from `bootstrap.md`
(attach `github-kylelundstedt-iv-provision`, clone, `provision-iv.sh`, then clone the
work repo + `provision-docsite`).

### 8. Verify

```bash
tailscale status | grep <vm>
ssh -o ConnectTimeout=30 <vm>.exe.xyz "cat ~/iv-provision.lock"
```

## SSH discipline

- **One SSH attempt at a time.** Never launch parallel SSH to `*.exe.xyz` or `exe.dev`.
- Wait for each command to complete before starting the next.
- If SSH fails, wait 30-60s before one more attempt.
