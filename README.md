# iv-image

The IV custom OCI image for exe.dev VMs, plus the build/push pipeline for IV's
private registry (`iv-registry.exe.xyz`).

## Why this exists

- **Escape Bold's default.** exe.dev's stock image is `boldsoftware/exeuntu`,
  which can change under us. We pin our own base commit.
- **Preinstall + region.** Bake DuckDB in and control the base so VMs come up
  identical and in the right region (LAX).
- **Reproducible compute for GitLake.** Recorded executions pin the image by
  digest — see the image-identity section of `iv/iv_platform.md` in the gitlake
  repo (`kylelundstedt/gitlake`).

## Layout

| File            | Role                                                                   |
| --------------- | ---------------------------------------------------------------------- |
| `Dockerfile.iv` | The IV overlay: pinned exeuntu base + DuckDB + Quarto + doc-site tooling + tailscaled fix. |
| `build.sh`      | Fetch pinned exeuntu, build base + overlay, tag, push, record digest.  |
| `bin/`          | `render-site` + `provision-docsite` — render a repo to `_site` and serve it on `:8000` (baked onto PATH). |

The base layer is built from upstream `boldsoftware/exeuntu` at a pinned commit
(`build.sh` clones it into `exeuntu/`). We don't vendor exeuntu's Dockerfile.

## Versioning (SemVer)

The overlay is versioned `iv-image:MAJOR.MINOR.PATCH`. `build.sh` pushes the
exact build plus floating `MAJOR.MINOR` and `MAJOR` aliases:

| Tag                 | Meaning                                 | Mutable?           |
| ------------------- | --------------------------------------- | ------------------ |
| `iv-image:1.1.0`    | the exact build — pin this for a recipe | no (by convention) |
| `iv-image:1.1`      | latest `1.1.x`                          | yes                |
| `iv-image:1`        | latest `1.x`                            | yes                |
| `iv-image@sha256:…` | true immutable pin (worker VMs / ER)    | never              |

Bump rules:

- **MAJOR** — re-pin the exeuntu base to a new commit, Ubuntu bump, or remove
  tooling (breaking).
- **MINOR** — additive overlay change: bump DuckDB, bake in a tool or
  `install.sh`, enable a service.
- **PATCH** — rebuild with no recipe change (e.g. security-only refresh). Rare,
  since the base is commit-pinned.

Note: an upstream component's own patch (DuckDB 1.5.3 → 1.5.4) is an image
**MINOR** — from the image's contract it's an additive content change, not a fix
to our layer. Don't mirror the upstream number into the image number.

### History

| Version | Change                                          | exeuntu commit |
| ------- | ----------------------------------------------- | -------------- |
| `1.0.0` | exeuntu base + DuckDB 1.5.3                      | `d20aa680543e` |
| `1.1.0` | + `systemctl enable tailscaled` (BYO-image fix) | `d20aa680543e` |
| `1.2.0` | + Quarto 1.9.38 (doc-site rendering)            | `d20aa680543e` |
| `1.3.0` | + doc-site tooling (`render-site`, `provision-docsite`) | `d20aa680543e` |

Pushed digests are recorded in `digests.log` on the registry host
(`1.1.0` = `sha256:eed9f18a63c717867107d1301554bee2d76b04403a74a553cd69989fd5e54b46`;
`1.2.0` = `sha256:9838519534ab7ed474932c47772d9b4333ca4d7d411371caac38852087005642`;
`1.3.0` = `sha256:699d49a3c4c37b15e17c0365cc2c836d2b28acbb0c417bac07b0abaedbf95d4c`).

## Cutting a new version

```bash
git clone https://github.com/kylelundstedt/iv-image.git && cd iv-image
$EDITOR build.sh        # bump IV_VERSION; edit Dockerfile.iv as needed
./build.sh              # builds + pushes to localhost:8000 (run on iv-registry)
# or build elsewhere and push to the registry over TLS:
REG=iv-registry.exe.xyz ./build.sh
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

## Registry / builder topology

- `iv-registry` (VM, LAX) runs `docker run -d --restart=always -p 8000:5000
  registry:2`; exe.dev's HTTPS proxy maps `iv-registry.exe.xyz:443` → VM `:8000`,
  so our VMs pull over TLS with no `--registry-auth`.
- **The registry host runs stock `boldsoftware/exeuntu`, not `iv-image`** — on
  purpose. A registry host must not depend on the artifact it serves (bootstrap
  cycle). It's near-disposable: rebuild it, `./build.sh` to repopulate, repoint
  the proxy.
- **Build anywhere, push to the registry.** `docker build` is local; only `push`
  needs the registry reachable. Updating `iv-image` never recreates the registry.

## Consuming the image

```bash
ssh exe.dev new --image=iv-registry.exe.xyz/iv-image:1 --name=<vm> --tag=iv
# reproducible: pin a build or a digest
ssh exe.dev new --image=iv-registry.exe.xyz/iv-image:1.1.0 ...
ssh exe.dev new --image=iv-registry.exe.xyz/iv-image@sha256:eed9f18a… ...
```

The image is consumed only at VM creation; there's no default-image key, so pass
`--image` on every `new`.
