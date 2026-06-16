# iv-image

The IV provisioning layer for exe.dev VMs: a script (`provision-iv.sh`) plus
vendored skills and doc-site tooling that turn a stock `boldsoftware/exeuntu`
VM into an IV dev box.

**Full documentation:** [https://iv-registry.exe.xyz/](https://iv-registry.exe.xyz/)

## Quick start

VMs are created from stock `boldsoftware/exeuntu` (no `--image` flag), then
provisioned by running `provision-iv.sh` from this repo at a pinned tag/sha.

```bash
# 1. Create a VM from stock exeuntu (default image — NO --image flag)
ssh exe.dev new --name=<vm> --tag=iv

# 2. Attach the repo integration so the VM can clone this repo
ssh exe.dev integrations attach github-kylelundstedt-iv-image vm:<vm>

# 3. Clone at a pinned tag/sha and provision
ssh <vm>.exe.xyz "git clone https://github-kylelundstedt-iv-image.int.exe.xyz/kylelundstedt/iv-image.git ~/iv-image \
  && git -C ~/iv-image checkout <tag-or-sha> && ~/iv-image/provision-iv.sh"
```

The VM does not auto-join the tailnet; join on demand with the `join-tailnet`
skill (see `tailnet.md`). Repo and doc-site provisioning are unchanged (see
`consuming.md`).

## Why a script, not a custom image

A custom Docker image is not recognized by exe.dev as "exeuntu", which silently
disables Shelley (exe.dev's built-in coding agent): no VMs-list icon, no
detail-page Shelley button, and exe.dev never injects the shelley binary at VM
creation. Stock exeuntu keeps Shelley fully working. Provisioning the IV layer
onto stock exeuntu takes ~23 seconds.

## Layout

| File               | Role                                                                                                                                                |
| ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `provision-iv.sh`  | Provisions the IV layer onto stock exeuntu (DuckDB, Quarto, aws/tigris/rclone, doc-site tools, agent config, skills); writes `~/iv-provision.lock`. |
| `vendor-skills.sh` | Refreshes the vendored skills snapshot in `skills/` (needs node/npx).                                                                               |
| `skills/`          | Vendored, pinned team skills — committed to the repo so they are frozen.                                                                            |
| `bin/`             | `render-site` + `provision-docsite` + `gen-llms-txt` + `install-cloud-cli` (on-demand azure/gcloud) — installed onto PATH.                          |
| `agent/`           | Team agent config: `AGENTS.md`, Claude Code `settings.json`, Codex `config.toml`, MCP setup.                                                        |
| `*.qmd` / `*.md`   | Quarto doc site served at `https://iv-registry.exe.xyz/`.                                                                                           |

## Reproducibility

The pinned artifact is the git commit of this repo: check out a specific tag/sha
on the VM, run `provision-iv.sh`, and you get the same result.

- Tool versions are pinned inside `provision-iv.sh` (DuckDB 1.5.3, Quarto 1.9.38).
- Skills are vendored into `skills/` (committed = frozen); `provision-iv.sh`
  copies them in with no node/npx needed on the VM.
- The base exeuntu image cannot be pinned — exe.dev manages it (floating) and
  there is no version/digest selector on `ssh exe.dev new`. Instead,
  `provision-iv.sh` records it in `~/iv-provision.lock` (exeuntu image revision,
  shelley version, DuckDB/Quarto versions, skills count, and the provision repo
  git sha) as the per-VM provenance record.
