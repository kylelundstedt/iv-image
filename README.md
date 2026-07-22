# iv-image

The IV provisioning layer for exe.dev VMs: a script (`provision-iv.sh`) plus
vendored skills and doc-site tooling that turn a stock `boldsoftware/exeuntu`
VM into an IV dev box.

**Full documentation:** the `*.qmd` / `*.md` files in this repo (`consuming.md`,
`building.md`, `bootstrap.md`, `tailnet.md`, …). The hosted doc site was retired
with the `iv-registry` VM (2026-07-14); any IV VM can serve it again with
`provision-docsite ~/iv-image` (see `registry.md`).

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

### AgentsView source activation

AgentsView `0.38.1` is installed on every IV VM, but its source daemon is
fail-closed and disabled until both prerequisites exist:

1. the VM is joined to Tailscale; and
2. `~/.config/agentsview/source.env` exists with mode `0600` and contains a
   unique per-host token:

```bash
mkdir -p ~/.config/agentsview
printf 'AGENTSVIEW_AUTH_TOKEN=%s\n' '<unique-token>' \
  > ~/.config/agentsview/source.env
chmod 600 ~/.config/agentsview/source.env
~/iv-image/provision-iv.sh
```

The user service binds only the VM's Tailscale IPv4 address on port `8080` and
serves the authenticated HTTP remote-sync endpoints. Provisioning never joins
the tailnet or creates a fleet-wide token as a side effect.

## Relationship to the dotfiles repo

The team layer's _contents_ — the skill set, MCP server list, and the shared
`AGENTS.md` sections — are declared in
[kylelundstedt/dotfiles](https://github.com/kylelundstedt/dotfiles)'
`provisioning/` manifests and vendored into this repo by `vendor-skills.sh` at
the dotfiles commit recorded in `dotfiles-manifest.pin`. **Edit shared material
in dotfiles, then re-vendor and bump the pin here** — dotfiles'
`diff-provisioning.sh` flags any drift between the two repos. The division of
labor: this repo provisions the _team_ baseline onto a VM; dotfiles'
`install.sh` then (optionally) layers _personal_ config on top as a thin
overlay that never touches the team layer.

## Authoring boundary

GitHub is the canonical source of truth. Author, review, merge, and push this
repository from `klundstedt-mini` using the checkout at
`~/github/kylelundstedt/iv-image`. The same host owns dotfiles authoring so
cross-repo pin bumps and vendoring changes stay in one workflow.

`kgl-dotfiles` and ordinary project VMs consume iv-image read-only. A dedicated
writer integration may be attached to the canary only for an explicit
temporary-branch push test and must be detached immediately afterward; no VM
worktree is authoritative.

## Why a script, not a custom image

A custom Docker image is not recognized by exe.dev as "exeuntu", which silently
disables Shelley (exe.dev's built-in coding agent): no VMs-list icon, no
detail-page Shelley button, and exe.dev never injects the shelley binary at VM
creation. Stock exeuntu keeps Shelley fully working. Provisioning the IV layer
onto stock exeuntu takes ~23 seconds.

## Layout

| File                    | Role                                                                                                                                                       |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `provision-iv.sh`       | Provisions the IV layer onto stock exeuntu (DuckDB, Quarto, aws/tigris/rclone, herdr, AgentsView, doc-site tools, agent config, skills); writes `~/iv-provision.lock`. |
| `vendor-skills.sh`      | Refreshes the vendored skills snapshot in `skills/` (needs node/npx).                                                                                      |
| `skills/`               | Vendored, pinned team skills — committed to the repo so they are frozen.                                                                                   |
| `bin/`                  | `render-site` + `provision-docsite` + `gen-llms-txt` + `install-cloud-cli` (on-demand azure/gcloud) — installed onto PATH.                                 |
| `agent/`                | Team agent config: `AGENTS.md`, Claude Code `settings.json`, Codex `config.toml`, MCP setup.                                                               |
| `dotfiles-manifest.pin` | The dotfiles commit whose `provisioning/` manifests the vendored content comes from (see "Relationship to the dotfiles repo").                             |
| `tests/`                | Validation suite: `smoke-provision.sh` (run on a VM after provisioning), `test-provision.sh`, `test-ssh-guard.sh`, Python unit tests — run by CI.          |
| `.claude/skills/`       | Project-level skills for agents working in this repo (`join-tailnet`, `upgrade-vm`) — not vendored onto VMs.                                               |
| `*.qmd` / `*.md`        | Documentation (Quarto sources, readable in-repo; optionally served by `provision-docsite` on any IV VM).                                                   |

## Reproducibility

The pinned artifact is the git commit or release tag of this repo: check out a
specific revision on the VM, run `provision-iv.sh`, and get the same IV layer on
that architecture.

- DuckDB, Quarto, AWS CLI, Tigris CLI, rclone, herdr, and AgentsView versions
  plus per-architecture SHA-256 checksums are pinned inside `provision-iv.sh`
  (herdr publishes no checksums upstream — its pins are computed locally at
  pin time).
- The provisioner compares installed versions to the recipe and upgrades or
  repairs mismatches; it does not treat any command on `PATH` as sufficient.
- Skills are vendored into `skills/` (committed = frozen); `provision-iv.sh`
  copies them in with no node/npx needed on the VM.
- Azure CLI and gcloud remain on demand through `install-cloud-cli`, with pinned
  package/archive versions.
- The base exeuntu image cannot be pinned — exe.dev manages it (floating) and
  there is no version/digest selector on `ssh exe.dev new`. Instead,
  `provision-iv.sh` records it in `~/iv-provision.lock` along with the installed
  tool versions, Shelley version, skills count, and provisioning Git SHA.
