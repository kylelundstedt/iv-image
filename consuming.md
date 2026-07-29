---
title: "Consuming"
---

## Creating a VM

VMs are created from stock `boldsoftware/exeuntu` (the default — no `--image`
flag), then provisioned by running `provision-iv.sh` from this repo at a pinned
tag/sha:

```bash
# 1. Create a VM from stock exeuntu (default image — NO --image flag)
ssh exe.dev new --name=<vm> --tag=iv

# 2. Clone at a pinned tag/sha and provision. This repo is public: no
#    integration, no credential, no proxy host.
ssh <vm>.exe.xyz "git clone https://github.com/kylelundstedt/iv-image.git ~/iv-image \
  && git -C ~/iv-image checkout <tag-or-sha> && ~/iv-image/provision-iv.sh"
```

For reproducibility, pin by checking out a Git tag/sha of this repo before
running `provision-iv.sh`. Tool releases and checksums are pinned in the script,
and team skills are vendored in the repo. `~/iv-provision.lock` records the
exeuntu image revision, Shelley version, installed
DuckDB/Quarto/AWS/Tigris/rclone/herdr versions, skills count, manifest pin, and
provisioning repository SHA.

## Joining the tailnet (on demand)

The image does **not** auto-join the tailnet. A fresh VM is reachable only over
the exe.dev edge (`ssh <vm>.exe.xyz`). To put it on IV's tailnet, run the
`join-tailnet` agent skill (or the equivalent commands by hand) — it SSHes in
over `*.exe.xyz` and runs `tailscale up` with a one-use key minted through the
`tailscale-api` proxy. After it joins, use `ssh <vm>` (Tailscale) for the rest.

Pass `--tag=iv` at creation so the `tailscale-api` integration is attached;
the join step needs it to mint the key. See `tailnet.md` for the full flow.

## Upgrading to a new revision

To move a VM to a newer provisioning recipe, update `~/iv-image` to the target
tag/sha and re-run `provision-iv.sh`. This is normally an in-place operation: it
preserves the disk and tailnet identity while refreshing pinned tools, vendored
skills, agent configuration, and `~/iv-provision.lock`.

The `upgrade-vm` skill also documents the exceptional destroy/recreate path for
cases that genuinely require a fresh disk or newer exe.dev-managed base. That
path wipes the VM; see `tailnet.md`.

## Agent config (installed by provision-iv.sh)

Every provisioned VM gets team agent defaults — no manual setup required:

- **AGENTS.md** — team-wide instructions for Claude Code and Codex (data work
  conventions, exe.dev SSH discipline, skill usage rules)
- **Claude Code settings** — SSH guard hook (blocks parallel SSH to exe.dev) and
  `DISABLE_NON_ESSENTIAL_MODEL_CALLS`
- **MCP servers** — MotherDuck and GitHub (work) pre-registered via exe.dev proxy
  (no secrets on the VM)
- **Skills** — mviz, duckdb-skills, motherduck agent-skills,
  quarto-authoring, brand-yml, marimo-notebook, marimo-batch, find-skills,
  archil-guide

Personal dotfiles layer on top. Running your own `install.sh` will overlay
`AGENTS.md`, add personal MCP servers (github-home, tigris, readwise), and
install additional skills.

## Cloning a repo (integration)

The image bakes in no repo credentials. To pull a private repo onto a VM, attach
a GitHub integration and clone over the exe.dev proxy — the credential stays in
exe.dev's proxy layer and never lands on the VM.

```bash
# Attach the integration to the VM (or to the `iv` tag, once, for all iv VMs)
ssh exe.dev integrations attach github-<owner>-<repo> <vm>

# Clone over the proxy host: https://<integration>.int.exe.xyz/<org>/<repo>.git
ssh <vm>.exe.xyz "git clone https://github-<owner>-<repo>.int.exe.xyz/<org>/<repo>.git ~/<repo>"
```

The `.int.exe.xyz` host is the VM-side proxy endpoint; exe.dev injects the real
GitHub token at the proxy, so no PAT or SSH key is stored on the VM. The
integration name and the `int.exe.xyz` subdomain match (e.g. integration
`github-kylelundstedt-gitlake` → `github-kylelundstedt-gitlake.int.exe.xyz`).

This applies to **private** repos only. The two repos a VM needs to provision
itself — this one and `dotfiles` — are public and clone straight from
github.com, so a fresh dev VM needs no repo integration at creation.

## Provisioning a doc site

Each repo-VM serves its rendered site on `:8000` (the exe.dev HTTPS proxy port).
After cloning a repo (see above):

```bash
ssh <vm>.exe.xyz "provision-docsite ~/<repo>"
```

`provision-docsite` renders the Quarto project and serves `_site` on `:8000` with
**nginx** (gzip + immutable cache headers on the hashed `site_libs/` assets — a
typical Quarto page's payload drops ~80%+). To re-render after edits, run
`render-site ~/<repo>` — no restart needed (nginx serves whatever is in `_site`).
