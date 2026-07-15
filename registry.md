---
title: "Registry"
---

> **Retired.** The `iv-registry` VM was destroyed on 2026-07-14 (tailnet node
> deleted too). Nothing pulled from its legacy `registry:2` container under the
> script-based approach, and the hosted doc site it served was dropped — the
> docs are readable in-repo, and any IV VM can serve them again with
> `provision-docsite ~/iv-image` (disaster-recovery steps below double as the
> recreate recipe). This doc is retained for historical reference.

## What `iv-registry` is now

Under the script-based approach nothing is built or pulled, so the Docker
registry service is gone. `iv-registry` survives only as the host for this doc
site, served on `:8000` over the exe.dev HTTPS proxy at
`https://iv-registry.exe.xyz/`. It runs stock `boldsoftware/exeuntu` with Quarto
installed and the site served by a systemd user service — the same `:8000`
doc-site pattern every IV VM uses. (It could equally be retired and the site
moved to any other VM, or dropped entirely.)

If you still run the legacy `registry:2` container here for unrelated reasons,
it is independent of this project and out of scope for these docs.

### Disaster recovery (rebuild the doc-site host)

If `iv-registry` is destroyed, recreate it like any other IV VM (see
`bootstrap.md`) and provision this repo as its doc site:

```bash
ssh exe.dev new --name=iv-registry --tag=iv
ssh exe.dev integrations attach github-kylelundstedt-iv-image vm:iv-registry
ssh iv-registry.exe.xyz "git clone https://github-kylelundstedt-iv-image.int.exe.xyz/kylelundstedt/iv-image.git ~/iv-image \
  && ~/iv-image/provision-iv.sh \
  && provision-docsite ~/iv-image"
```

`provision-iv.sh` installs Quarto; `provision-docsite` renders the site and
serves `_site` on `:8000`. The VM is reached over the exe.dev edge; run the
`join-tailnet` skill only if you want `ssh iv-registry` short-name access.

## Historical: arm64 image-build research (custom-image era, retired)

Moved from TODO.md 2026-07-14 — research notes from the attempt to build
iv-image natively for linux/arm64 on `klundstedt-mini` (Apple Silicon, Apple
`container`) and push to the registry this VM hosted. The custom-image
workflow is retired (stock exeuntu + `provision-iv.sh` replaced it — custom
images lost exe.dev's Shelley integration), and the registry host is gone;
resuming any of this would first mean recreating a registry host AND
revisiting that architectural decision. Preserved so the hard-won findings
aren't re-learned.

**The goal was:** build arm64 natively on the Mini (builder only), push over
the tailnet to `iv-registry:5000`, merge with the amd64 build into one
multi-arch tag so Apple Containers on macOS could pull `iv-image:N`.

**Blocker that stopped it:** Apple `container` 1.0.0 context transfer is
broken — every `COPY` from the build context fails
`failed to calculate checksum … not found`; `--progress plain` shows
`transferring context: 2B` (empty stream). Reproducible interactively (not an
SSH/TCC artifact), on a freshly-recreated builder, with the correct shim
(0.12.0) and `--no-cache`. RUN steps work; only host-context reads fail.
Regressed from 0.10.0. Version catch-22: 0.10.0 = `COPY` works but the
exeuntu Dockerfile crashes the builder (size/complexity); 1.0.0 = size OK
(with slimming) but `COPY` broken. Untested combo that might work: 0.10.0 +
the slimmed Dockerfile (12649 B stays under the crash threshold).

**Workarounds validated:**

- 16 KiB Dockerfile cap (apple/container#735): exeuntu Dockerfile is 16749 B;
  stripping comment + blank lines (semantics-preserving) → 12649 B.
- Builder OOM: default 2 GB builder dies on large base images; use
  `container builder start -m 8G -c <ncpu>` — the memory flag needs a unit
  suffix (bare `6144` parses to 0 bytes).

**Proven working (don't re-test):** native arm64 RUN-step builds on the Mini
(reached 35/37 steps); pushing a proper `linux/arm64` manifest to a
tailnet-reachable registry; distribution generally — any arm64 build landed
in the registry fine. **Remaining plan had been:** `build.sh` `REG=` override
+ arm64 path → push arch-suffixed tag → merge into a multi-arch `:N`
(`docker buildx imagetools create` or `container` equivalent); `Dockerfile.iv`
and the exeuntu base were already arch-aware with no image-side blockers.
