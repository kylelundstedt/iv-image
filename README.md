# iv-image

The IV custom OCI image for exe.dev VMs, plus the build/push pipeline for IV's
private registry (`iv-registry.exe.xyz`).

**Full documentation:** [https://iv-registry.exe.xyz/](https://iv-registry.exe.xyz/)

## Quick start

```bash
# Create a VM from the latest 1.x image
ssh exe.dev new --image=iv-registry.exe.xyz:5000/iv-image:1.3 --name=<vm> --tag=iv

# Cut a new version (on iv-registry)
cd ~/iv-image && $EDITOR build.sh && ./build.sh
```

## Layout

| File            | Role                                                                   |
| --------------- | ---------------------------------------------------------------------- |
| `Dockerfile.iv` | The IV overlay: pinned exeuntu base + DuckDB + Quarto + doc-site tooling + tailscaled fix. |
| `build.sh`      | Fetch pinned exeuntu, build base + overlay, tag, push, record digest.  |
| `bin/`          | `render-site` + `provision-docsite` — baked onto PATH in the image.    |
| `*.qmd` / `*.md` | Quarto doc site served at `https://iv-registry.exe.xyz/`.            |
