---
title: "Consuming"
---

## Creating a VM from iv-image

```bash
ssh exe.dev new --image=iv-registry.exe.xyz:5000/iv-image:2 --name=<vm> --tag=iv
```

Pin to an exact build or digest for reproducibility:

```bash
ssh exe.dev new --image=iv-registry.exe.xyz:5000/iv-image:2.0.0 ...
ssh exe.dev new --image=iv-registry.exe.xyz:5000/iv-image@sha256:... ...
```

The image is consumed only at VM creation — there is no default-image setting,
so pass `--image` on every `new`.

## Joining the tailnet (on demand)

The image does **not** auto-join the tailnet. A fresh VM is reachable only over
the exe.dev edge (`ssh <vm>.exe.xyz`). To put it on IV's tailnet, run the
`join-tailnet` agent skill (or the equivalent commands by hand) — it SSHes in
over `*.exe.xyz` and runs `tailscale up` with a one-use key minted through the
`tailscale-api` proxy. After it joins, use `ssh <vm>` (Tailscale) for the rest.

Pass `--tag=iv` at creation so the `tailscale-api` integration is attached;
the join step needs it to mint the key. See `tailnet.md` for the full flow.

## Upgrading to a new image

exe.dev applies an image only at creation, so upgrading a VM to a newer
`iv-image` means destroy + recreate under the same name. The `upgrade-vm` agent
skill does this without a `-1` tailnet name: from a control node it deletes the
stale tailnet node, recreates from the target image, and rejoins. It **wipes the
VM's local disk** — reprovision, not migrate. See `tailnet.md`.

## Agent config (baked in)

Every iv-image VM ships with team agent defaults — no setup required:

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

## Provisioning a doc site

Each repo-VM serves its rendered site on `:8000` (the exe.dev HTTPS proxy port).
After cloning a repo:

```bash
ssh <vm>.exe.xyz "git clone https://<integration>.int.exe.xyz/<org>/<repo>.git ~/<repo>"
ssh <vm>.exe.xyz "provision-docsite ~/<repo>"
```

`provision-docsite` renders the Quarto project and starts a persistent systemd
user service serving `_site` on `:8000`. To re-render after edits, run
`render-site ~/<repo>` — no restart needed.
