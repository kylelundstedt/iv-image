# iv-provision

The IV provisioning layer for exe.dev VMs: a script (`provision-iv.sh`) plus
vendored skills and doc-site tooling that turn a stock exe.dev VM into an IV
dev box.

> **Renamed from `iv-image` (2026-08-18).** The old name described something
> this repository has never contained: there is no image here, and VMs are not
> created from one built by this repo. It cost real confusion — "why doesn't a
> new VM use our iv-image?" has a different answer depending on whether you
> think `iv-image` is an image (it isn't) or a script (it is). The actual base
> images live in [`kylelundstedt/exeslim`](https://github.com/kylelundstedt/exeslim)
> and are published to GHCR. GitHub redirects clones and pushes from the old
> name, so existing VM checkouts keep working; update their `origin` at the
> next re-provision.

**Full documentation:** the `*.qmd` / `*.md` files in this repo (`consuming.md`,
`building.md`, `bootstrap.md`, `tailnet.md`, …). The hosted doc site was retired
with the `iv-registry` VM (2026-07-14); any IV VM can serve it again with
`provision-docsite ~/iv-provision` (see `registry.md`).

## Quick start

VMs are created from the IV base image, then provisioned by running
`provision-iv.sh` from this repo at a pinned tag/sha.

```bash
# 1. Create a VM from the IV dev base (exeslim-dev: slim, keeps Shelley).
#    Pin the immutable build ID from the package page; never :latest.
#    https://github.com/kylelundstedt/exeslim/pkgs/container/exeslim-dev
ssh exe.dev new --name=<vm> --tag=iv \
  --image=ghcr.io/kylelundstedt/exeslim-dev:<date>.<run>.<attempt>

# 2. Clone at a pinned tag/sha and provision. This repo is public: no
#    integration, no credential, no proxy host.
ssh <vm>.exe.xyz "git clone https://github.com/kylelundstedt/iv-provision.git ~/iv-provision \
  && git -C ~/iv-provision checkout <tag-or-sha> && ~/iv-provision/provision-iv.sh"
```

The VM does not auto-join the tailnet; join on demand with the `join-tailnet`
skill (see `tailnet.md`). Repo and doc-site provisioning are unchanged (see
`consuming.md`).

The provisioner also replaces exe.dev's creation-time Shelley with IV's pinned,
checksum-verified `aifoundry-org/shelley` release. It preserves the prior binary,
service metadata, and a database backup; installs atomically; rolls back on a
failed version/service/API health check; disables Shelley's unmanaged
self-update path; and records the actual installed version, commit, and hash in
`~/iv-provision.lock`. OAuth credentials and conversation databases are never
baked into this repository or copied between VMs.

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
~/iv-provision/provision-iv.sh
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

GitHub is the canonical source of truth. Changes land on `main` by pull request
with CI green; **any host may author**, including a fleet VM with a writable repo
integration attached.

This replaces the previous rule that only `klundstedt-mini` could author
(changed 2026-08-18). Single-workstation authoring was never enforced by
permissions — fleet VMs with the `repo-iv-provision` integration have always had
push access — so it was a convention that mostly served to keep the fleet from
fixing its own provisioner, and to serialise cross-repo pin bumps through one
laptop. PR + CI is the guardrail that actually holds.

What does still hold: no VM worktree is authoritative, and a checkout on a fleet
VM is expected to sit detached at a release tag (see `consuming.md`). Linux
compatibility canaries are created on demand and stay read-only unless a writer
is deliberately attached; delete the canary after validation.

## General-purpose Markdown with Apex

[Apex](https://github.com/ApexMarkdown/apex) is the Markdown engine for
previews, generated reports, terminal reading, format conversion, and the
multi-page documentation sites produced by `render-site`.

```bash
# Read Markdown in the terminal.
apex -t terminal README.md

# Produce a standalone HTML preview or report.
apex README.md --standalone --pretty -o /tmp/README.html

# Normalize a document to GitHub Flavored Markdown.
apex notes.md -t gfm > /tmp/notes.gfm.md

# Emit an HTML fragment for another program or template to consume.
apex notes.md > /tmp/notes.fragment.html
```

Apex is version-pinned and checksum-verified by `provision-iv.sh`, like the
other provisioned binaries. `render-site` wraps Apex output with navigation,
per-page TOCs, stable links, and the site template.

## Why a script, not a custom image

**Correction, 2026-07-28; resolved 2026-08-18.** This section used to say a
custom image "silently disables Shelley" and that stock exeuntu was therefore
required. That is wrong, and it blocked the slim-base work for months. The
slim-base work has since shipped: IV VMs now run
`ghcr.io/kylelundstedt/exeslim-dev`, so the question is settled by running code
rather than argument. exe.dev supports an opt-in label —
`ssh exe.dev doc customization`:

> `LABEL exe.dev/install-shelley=true` makes exe.dev automatically install a
> recent Shelley in `/usr/local/bin` on creation and makes the UI assume that
> Shelley is installed.

So a custom image loses Shelley only **by default**, not necessarily. What
remains true is that a custom image is not recognised as "exeuntu", so anything
keying off that (`EXEUNTU=1`) is absent — note `/exe.dev/etc/image.conf` *is*
present on a custom-image VM and carries the image's own OCI labels, which is
how `~/iv-provision.lock` records base provenance.

The real reason the *tooling* stays a script is different, and it survives the
correction: **exe.dev fixes a VM's image at creation and offers no way to move a
live VM onto a newer one** (`new`, `rm`, `restart`, `cp`, `resize` — `cp` clones
the disk you already have). Every version bump in the pinned tool list at the
top of `provision-iv.sh` would therefore become a fleet **recreate**, whereas
today it is a re-run in place (`upgrade-vm` Path A, ~23 seconds).

And baking buys nothing on disk: exe.dev bills each VM's own ext4 usage with no
cross-VM dedup (`ssh exe.dev doc faq/disk-usage`), so moving a binary from
`~/.local` into an image layer relocates the bytes rather than removing them.

The disk win comes from the **base**, not from baking: exeuntu is ~4 GB, and a
slim base drops most of it. That argues for a slim base carrying the OS packages
and this script continuing to carry the volatile, version-pinned tools. See
`dotfiles/agent_docs/exe-dev-remediation.md` (Track 2).

## Layout

| File                    | Role                                                                                                                                                       |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `provision-iv.sh`       | Provisions the IV layer onto the IV base image (DuckDB, Apex, tigris/rclone, herdr, AgentsView, doc-site tools, agent config, skills); writes `~/iv-provision.lock`. |
| `vendor-skills.sh`      | Refreshes the vendored skills snapshot in `skills/` (needs node/npx).                                                                                      |
| `skills/`               | Vendored, pinned team skills — committed to the repo so they are frozen.                                                                                   |
| `bin/`                  | `render-site` + `provision-docsite` + `gen-llms-txt` + `install-cloud-cli` (on-demand aws/azure/gcloud) — installed onto PATH.                                 |
| `agent/`                | Team agent config: `AGENTS.md`, Claude Code `settings.json`, Codex `config.toml`, MCP setup.                                                               |
| `dotfiles-manifest.pin` | The dotfiles commit whose `provisioning/` manifests the vendored content comes from (see "Relationship to the dotfiles repo").                             |
| `tests/`                | Validation suite: `smoke-provision.sh` (run on a VM after provisioning), `test-provision.sh`, `test-ssh-guard.sh`, Python unit tests — run by CI.          |
| `.claude/skills/`       | Project-level skills for agents working in this repo (`join-tailnet`, `upgrade-vm`) — not vendored onto VMs.                                               |
| `*.qmd` / `*.md`        | Markdown documentation sources, readable in-repo and served by `provision-docsite` on any IV VM.                                                               |

## Reproducibility

The pinned artifact is the git commit or release tag of this repo: check out a
specific revision on the VM, run `provision-iv.sh`, and get the same IV layer on
that architecture.

- DuckDB, Apex, AWS CLI, Tigris CLI, rclone, herdr, AgentsView, and Shelley
  versions plus per-architecture SHA-256 checksums are pinned inside
  `provision-iv.sh` (herdr publishes no checksums upstream — its pins are
  computed locally at pin time).
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

## License

The IV provisioning layer — `provision-iv.sh`, `bin/`, `tests/`, `systemd/`,
`agent/`, `.claude/skills/`, and the documentation — is MIT licensed; see
`LICENSE`.

`skills/` vendors third-party agent skills that are **not** covered by that
grant. Each retains its upstream license, declared in the `license:` field of
its `SKILL.md` frontmatter where upstream sets one. Redistribution of any
vendored skill is governed by its own terms, not by this repo's.
