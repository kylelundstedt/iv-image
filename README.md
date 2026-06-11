# iv-image

The IV custom OCI image for exe.dev VMs, plus the build/push pipeline for IV's
private registry (`iv-registry.exe.xyz`).

**Full documentation:** [https://iv-registry.exe.xyz/](https://iv-registry.exe.xyz/)

## Quick start

```bash
# Create a VM from the latest image (does not auto-join the tailnet; see tailnet.md)
ssh exe.dev new --image=iv-registry.exe.xyz:5000/iv-image:2 --name=<vm> --tag=iv

# Cut a new version (on iv-registry)
cd ~/iv-image && $EDITOR build.sh && ./build.sh
```

## Layout

| File             | Role                                                                                          |
| ---------------- | --------------------------------------------------------------------------------------------- |
| `Dockerfile.iv`  | The IV overlay: pinned exeuntu base + DuckDB + Quarto + doc-site tooling + agent config; `tailscaled` enabled but idle (on-demand join). |
| `build.sh`       | Fetch pinned exeuntu, build base + overlay, tag, push, record digest.                         |
| `bin/`           | `render-site` + `provision-docsite` + `gen-llms-txt` — baked onto PATH.                        |
| `agent/`         | Team agent config: `AGENTS.md`, Claude Code `settings.json`, MCP + skills setup scripts.       |
| `*.qmd` / `*.md` | Quarto doc site served at `https://iv-registry.exe.xyz/`.                                     |
