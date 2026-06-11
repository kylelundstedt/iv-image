---
title: "Building"
---

## Cutting a new version

```bash
# On iv-registry (or any amd64 builder with Docker):
cd ~/iv-image
$EDITOR build.sh        # bump IV_VERSION; edit Dockerfile.iv as needed
./build.sh              # builds + pushes to localhost:5000
```

To build elsewhere and push to the registry over TLS:

```bash
REG=iv-registry.exe.xyz:5000 ./build.sh
```

## Gotchas

- **`docker build --network=host` is mandatory.** Docker's embedded DNS fails to
  resolve `pkgs.tailscale.com` on exe.dev VMs (curl exit 6) even though the host
  resolves fine. `build.sh` already passes it.
- **Build on amd64**, not an arm Mac — exe.dev VMs are amd64.
- **tailscaled ships disabled on BYO images.** exe.dev only enables it on its own
  default image; apt's postinst `systemctl enable` no-ops at build time (no PID
  1). We explicitly `systemctl enable tailscaled` in `Dockerfile.iv` so the
  daemon is up and idle — but the image does **not** join the tailnet at boot.
- **No baked auto-join.** As of 2.0.0 the image carries no `ts-bootstrap`,
  `iv-tailscale-join`, setup-script hook, or Tailscale API access. A VM joins on
  demand via the `join-tailnet` agent skill (`tailnet.md`), which SSHes in over
  `*.exe.xyz` and runs `tailscale up`, minting a one-use key through the
  `tailscale-api` proxy. The skill still needs that integration attached to the
  VM (via `--tag=iv`); the Tailscale API secret stays in exe.dev's proxy layer.
