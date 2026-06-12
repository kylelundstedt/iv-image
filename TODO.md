# TODO

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
- Cleanup: delete leftover `smoke:armtest` test image from `iv-registry`.

## Pending (amd64, unrelated to arm64)

- IV 2.3.0 is uncommitted: arch-aware DuckDB/Quarto edits in `Dockerfile.iv`, `IV_VERSION`
  bump, new `agent/codex-config.toml`. Commit + `build.sh` + push when ready.
