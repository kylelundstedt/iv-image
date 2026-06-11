---
title: "Tailnet Join"
---

## Contract

Every VM created from `iv-image` should join IV's Tailscale tailnet as soon as
systemd starts. The image owns that behavior directly through
`iv-tailscale-join.service`; it does not depend on `/exe.dev/setup`.

The long-lived Tailscale credential stays outside the VM. The VM talks to
exe.dev's `tailscale-api` HTTP proxy integration at
`https://tailscale-api.int.exe.xyz`. exe.dev integrations inject secrets on the
network side, so the VM can use the integration endpoint without reading the
secret value.

## Required exe.dev integration

Attach the existing `tailscale-api` integration to any VM that should autojoin.
For IV VMs, attach it to the `iv` tag:

```bash
ssh exe.dev integrations attach tailscale-api tag:iv
```

Then create VMs with the `iv` tag:

```bash
ssh exe.dev new --image=iv-registry.exe.xyz:5000/iv-image:1.8 --name=<vm> --tag=iv
```

The integration must proxy to the Tailscale API base URL:

```text
https://api.tailscale.com
```

The VM-side service expects this endpoint:

```text
https://tailscale-api.int.exe.xyz/api/v2/tailnet/-/keys
```

The image only calls the auth-key creation endpoint. A direct HTTP proxy
integration does not by itself enforce that path; code running on an attached VM
can call whatever Tailscale API endpoints the integration's backing credential
permits. Keep the integration attached only to trusted VM tags, and prefer a
small broker service if you need hard server-side enforcement of "create exactly
one auth key for this VM".

## Boot flow

1. `tailscaled.service` starts.
2. `iv-tailscale-join.service` waits for the local `tailscaled` socket.
3. If Tailscale is already running, the service only ensures Tailscale SSH is
   enabled.
4. Otherwise, it asks `tailscale-api.int.exe.xyz` for a one-use, ephemeral,
   preauthorized auth key tagged `tag:dev`.
5. The auth key expires after 10 minutes and is passed to `tailscale up` through
   an inherited file descriptor, not argv, environment, shell history, or disk.
6. The VM joins with `--ssh`, `--accept-dns`, and `--hostname=$(hostname)`.

The service retries internally while the integration is coming up, and systemd
restarts it on failure. A missing or unattached integration is therefore a
recoverable boot problem: attach `tailscale-api` and restart the unit.

```bash
sudo systemctl restart iv-tailscale-join.service
journalctl -u iv-tailscale-join.service -n 100 --no-pager
```

## Security boundary

The VM never receives the long-lived Tailscale API token or OAuth client secret.
It receives only the one-use auth key it must present to `tailscale up`. That key
is short-lived, non-reusable, preauthorized, and tagged.

Do not bake Tailscale credentials into the image, `/exe.dev/setup`, environment
variables, dotfiles, or repo files.

## Why stale-node deletion is not in the VM

The old `ts-bootstrap` deleted existing Tailscale devices with the same hostname
before joining. That avoided MagicDNS `-1` suffixes after quick VM rebuilds, but
it also required every new VM to have device-list and device-delete authority
through the Tailscale API proxy.

The image no longer does that. The VM-side join path should not depend on
device-delete authority. If a hostname is reused before Tailscale removes the old
ephemeral node, clean up the stale node from an admin workstation or a dedicated
broker service, not from the newly created VM.

## Operational notes

- Disable autojoin for an image-derived VM by creating
  `/etc/iv-image/disable-tailscale-join`.
- Override the Tailscale API proxy with `IV_TAILSCALE_API_URL`.
- Override the tag with `IV_TAILSCALE_TAG`.
- Override the hostname with `IV_TAILSCALE_HOSTNAME`.
- If the `tailscale-api` integration is backed by a Tailscale API access token,
  that token still has Tailscale's normal API-token expiry and must be rotated in
  exe.dev before it expires.
