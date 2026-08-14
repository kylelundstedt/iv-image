---
title: "Bootstrap"
---

The canonical end-to-end bring-up for an IV VM. Each step is a distinct layer with
its own ownership — they are orchestrated in order, not merged into one script:

| Step | What                                          | Owned by                                   |
| ---- | --------------------------------------------- | ------------------------------------------ |
| 1    | Create a **stock exeuntu** VM (keeps Shelley) | exe.dev                                    |
| 2    | Join the tailnet                              | `join-tailnet` skill                       |
| 3    | Install the **team software layer**           | `provision-iv.sh` (this repo, public)      |
| 4    | Clone the work repo + serve its doc site      | repo integration + `provision-docsite`     |
| 5    | _(optional)_ Personal overlay                 | your dotfiles `install.sh` (separate repo) |

Stock exeuntu is deliberate — but **not** because a custom image must lose
Shelley. It loses Shelley only by default; `LABEL exe.dev/install-shelley=true`
opts back in (`ssh exe.dev doc customization`). The durable reason is that
exe.dev fixes the image at creation with no way to move a live VM onto a newer
one, so baking the version-pinned tools would turn every bump into a fleet
recreate. See "Why a script, not a custom image" in `README.md`.

## 1. Create the VM (stock exeuntu)

```bash
ssh exe.dev new --name=<vm> --tag=iv          # no --image ⇒ stock exeuntu
```

## 2. Join the tailnet (on demand)

Run the `join-tailnet` skill (or its commands by hand). The image does not
auto-join; a fresh VM is reachable only over the exe.dev edge until it joins.
See `tailnet.md`.

## 3. Provision the team software layer

Pin by checking out a tag/sha of this repo before running the script.

```bash
ssh <vm>.exe.xyz "git clone https://github.com/kylelundstedt/iv-image.git ~/iv-image \
  && git -C ~/iv-image checkout <tag-or-sha> \
  && ~/iv-image/provision-iv.sh"
```

`provision-iv.sh` installs DuckDB, Apex (the Markdown and documentation-site
renderer), the cloud CLIs (tigris/rclone; aws/azure/gcloud on demand,
via the `install-cloud-cli` helper), herdr, the
doc-site tools, the team agent config (AGENTS.md, Claude settings, Codex config, MCP
servers), and the vendored skills — no node required — and writes
`~/iv-provision.lock` recording exactly what landed.

## 4. Clone a repo + serve its doc site

```bash
ssh exe.dev integrations attach github-<owner>-<repo> vm:<vm>
ssh <vm>.exe.xyz "git clone https://github-<owner>-<repo>.int.exe.xyz/<org>/<repo>.git ~/<repo> \
  && provision-docsite ~/<repo>"
```

See `consuming.md` for repo-integration and doc-site details.

## 5. Personal overlay (optional)

```bash
ssh <vm>.exe.xyz "curl -fsSL https://raw.githubusercontent.com/kylelundstedt/dotfiles/master/install.sh | bash"
```

Personal dotfiles layer on top of the team defaults — they overlay `AGENTS.md`,
add personal MCP servers, and install additional skills. This stays in the
personal dotfiles repo, not here, so the team layer remains user-neutral.

## Upgrading later

To update an existing VM's software layer, re-provision in place — no recreate
needed. See the `upgrade-vm` skill.
