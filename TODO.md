# TODO

## Provisioning releases

- Before publishing `2.5.0`, run the provisioner and `tests/smoke-provision.sh` on a newly-created disposable stock exeuntu VM; local control-plane SSH is currently blocked by a missing private key.
- Consider separating the rendered build directory from the nginx docroot so preview cannot modify the live site.

## Retired custom-image notes

The items below are retained only as historical research. Stock exeuntu plus
`provision-iv.sh` replaced the custom-image workflow because custom images lost
exe.dev's Shelley integration. Do not resume image publication without revisiting
that architectural decision.

## arm64 iv-image via Apple `container` 1.0 on klundstedt-mini

Goal: build iv-image **natively for linux/arm64** on `klundstedt-mini` (Apple Silicon, Apple
`container`), push to `iv-registry` over the tailnet, and merge with the amd64 build into a
single multi-arch tag so Apple Containers on macOS can pull `iv-image:N`. The Mini is the
arm64 **builder only** — the registry stays on the exe.dev `iv-registry` VM (exe.dev's
provisioner pulls `--image` only from a `*.exe.xyz`-proxied registry).

### Blocker — must be fixed before this works

- **Apple `container` 1.0.0 context transfer is broken.** Every `COPY` from the build
  context fails `failed to calculate checksum … not found`; `--progress plain` shows
  `transferring context: 2B` (empty stream). Reproducible **interactively** (not an
  SSH/TCC artifact), on a freshly-recreated builder, with the correct shim (0.12.0) and
  `--no-cache`. RUN steps work; only host-context reads fail. Regressed from 0.10.0.
  → File/track upstream; needs a `container` 1.0.x fix (or a documented workaround).
- Version catch-22 today: 0.10.0 = `COPY` works but the exeuntu Dockerfile crashes the
  builder (size/complexity); 1.0.0 = size OK (with slimming) but `COPY` broken. Neither
  builds exeuntu as-is. Untested combo that _might_ work now: **downgrade to 0.10.0 + the
  slimmed Dockerfile** (COPY works there; 12649 B stays under the crash threshold).

### Workarounds already validated

- **16 KiB Dockerfile cap** (apple/container#735): exeuntu Dockerfile is 16749 B. Strip
  comment + blank lines (semantics-preserving) → 12649 B. `build.sh` arm64 path should
  generate a slimmed Dockerfile.
- **Builder OOM**: default 2 GB builder dies on large base images. Use
  `container builder start -m 8G -c <ncpu>` — memory flag **needs a unit suffix** (bare
  `6144` parses to 0 bytes).

### Proven working — do not re-test

- Native arm64 RUN-step builds run fine on the Mini (apt / `unminimize` / tool downloads,
  reached 35/37 steps).
- Push to registry over tailnet: `container image push --scheme http iv-registry:5000/…`;
  registry stores a proper `linux/arm64` manifest. Mini reaches `iv-registry:5000` (HTTP 200).
- Distribution half is solved: any arm64 build, by any builder, lands in `iv-registry` fine.

### Once the builder works

- `build.sh` already supports `REG=` override; add arm64 path: build exeuntu-base + iv-image
  arm64 on the Mini → push arch-suffixed tag → merge into multi-arch `:N`
  (`docker buildx imagetools create` or `container` equivalent).
- `Dockerfile.iv` is arch-aware (DuckDB/Quarto/aws/rclone derive arch); exeuntu base is
  arch-aware; `chromedp/headless-shell:stable` is a multi-arch index. No image-side blockers.
- ~~Cleanup: delete leftover `smoke:armtest` test image from `iv-registry`.~~ Moot — the
  `iv-registry` VM (and its registry container) was retired 2026-07-14; see `registry.md`.
  Resuming any of this arm64 work would first mean recreating a registry host.

## Pending (amd64, unrelated to arm64)

- Historical only: the custom-image 2.3/2.4 work was superseded by stock exeuntu
  plus versioned provisioning releases.

## Doc-site tooling

- **Done:** `provision-docsite` serves `_site` with **nginx** (gzip + immutable
  cache headers on `site_libs/`) instead of `python3 -m http.server`.
