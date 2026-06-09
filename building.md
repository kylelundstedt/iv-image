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
  1). We add an explicit `RUN systemctl enable tailscaled` (verified `is-enabled`
  = enabled). Without it the node drops off the tailnet when first-boot
  `install.sh` exits and short-form `ssh <vm>` times out.
