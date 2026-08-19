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
#    Use the immutable build ID for a fleet VM (see "Picking a tag" below).
#    https://github.com/kylelundstedt/exeslim/pkgs/container/exeslim-dev
ssh exe.dev new --name=<vm> \
  --image=ghcr.io/kylelundstedt/exeslim-dev:<date>.<run>.<attempt>
ssh exe.dev integrations attach api-tailscale vm:<vm>   # needed to join the tailnet

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

### Entire (ACR) capture

Provisioning installs the **Entire CLI** (pinned `0.8.42`, checksum-verified) and
IV's **`entire-agent-shelley`** plugin (`0.1.3`), which together implement the
source-native authoring-context capture path adopted by ADR 0010. Neither needs a
login: capture works unauthenticated with the `git-branch` checkpoint backend.

Before 2026-08-18 neither was installed by this script, so the *primary* ACR
capture path was hand-placed and did not survive a VM recreate — unlike a missing
tool, that gap loses provenance and does so silently.

The CLI pin is **not** "latest" on purpose: `entire-agent-shelley` 0.1.3 is
qualified only against Entire CLI 0.8.42, and 0.10.1 is already published.
Re-qualify the plugin before bumping the CLI, and bump both together.

Also installed: the vendored **`entire-agent-agentsview`** adapter
(`vendor/entire-agent-agentsview/`), ADR 0010's attach-only backfill and
reconciliation path, and the only one that can attach Claude Code or Codex
sessions to a checkpoint. It was previously on `PATH` as a symlink into a *spike
worktree*, so it broke if that worktree was pruned.

Provisioning stops at the mechanism. It does **not** run `entire enable`, because
that writes `.entire/settings.json` and git hooks into a repository — a per-repo
decision about which repositories are approved for capture, not a machine
baseline. Enroll a repository explicitly:

```bash
cd ~/<repo>
entire enable --agent shelley --project --telemetry=false --checkpoint-backend branch
```

`.entire/` is tracked in git, so enrolling once covers every worktree and future
clone of that repository.

### AgentsView source activation

AgentsView `0.38.1` is installed on every IV VM. Its source daemon is fail-closed:
it stays disabled until the VM is on the tailnet, since it serves the whole
normalized archive over HTTP and has no business listening anywhere else.

**Nothing to do by hand.** Provisioning generates the per-host token if it is
absent, writes it at mode `0600`, and enables the service once the VM is joined.
The service binds only the VM's Tailscale IPv4 address on port `8080`.

The token used to be a manual step: the docs told you to invent a
`<unique-token>`, paste it into `source.env`, and re-run the provisioner. That was
ceremony. The value is a self-chosen random secret -- nothing issues it and nothing
validates it beyond matching what the collector was told -- so a human typing it
added no security and made the daemon the one part of provisioning that could not
complete unattended (fixed 2026-08-19).

It is generated **once and never rotated**: the collector stores the value in its
own `[[remote_hosts]]` block, so re-minting on every provision would silently break
remote sync. It is **per host** rather than fleet-wide because it guards read
access to that VM's entire agent history -- every prompt, response and tool call --
and a shared secret would turn one compromised VM into a key to the whole fleet's
archive. Uniqueness is free once it is generated rather than typed.

## Relationship to the dotfiles repo

**This repo no longer depends on the dotfiles repo** (changed 2026-08-18). The
team layer's contents — the skill set, MCP server list, and the shared
`AGENTS.md` sections — are declared in `provisioning/`
(`skills.manifest`, `mcp.manifest`, `agents-shared.md`) and vendored into
`skills/` + `agent/` by `vendor-skills.sh`. Edit the manifests here, re-vendor,
and commit the result.

Those manifests previously lived in
[kylelundstedt/dotfiles](https://github.com/kylelundstedt/dotfiles) and were
fetched at the commit recorded in `dotfiles-manifest.pin`, with dotfiles'
`diff-provisioning.sh` policing drift. That arrangement made a fleet VM's
provisioning depend on a personal repository — and the pin was silently wrong
when it was removed: `agent/mcp-servers.json` was committed with
`api-motherduck-mcp` (matching the real exe.dev integration) while the pinned
manifest still read `motherduck-mcp`, so the content had been re-vendored from a
newer dotfiles commit without bumping the pin. A pin that can disagree with the
artifact it pins buys nothing.

The division of labor is unchanged: this repo provisions the _team_ baseline onto
a VM; dotfiles' `install.sh` then (optionally) layers _personal_ config on top as
a thin overlay that never touches the team layer. Personal rows in
`skills.manifest` are ignored by provisioning and exist for that overlay.

## Authoring boundary

GitHub is the canonical source of truth, and changes land on `main` by pull
request with CI green. **Provisioning changes originate on the `iv-provision`
VM**, which is the only host carrying the `repo-iv-provision-rw` and
`repo-exeslim-rw` integrations.

The write integrations *are* the boundary. This is not a convention asking to be
remembered: a fleet VM without a writable integration cannot push, so "where did
this change come from" has a mechanical answer rather than an honour-system one.

### Why a single writer, when PR + CI already gates merges

Between 2026-08-18 and 2026-08-19 this section said the opposite — *any host may
author* — on the reasoning that single-workstation authoring had never been
enforced by permissions and PR + CI was the guardrail that actually held. Two
things from the 2026-08-19 fleet refresh argue the other way, and the rule was
restored the same day.

**PR + CI gates what merges, not what gets tried.** `iv-docs` was found carrying
two unpushed commits, one of them a fix for the Shelley socket-activation race
that `main` had *already* fixed differently and better (`bd5c11f`, shipped as
`3.0.1`). Two hosts independently solved one bug; the fleet VM's version was
never wrong enough to notice and never right enough to merge. It also documented
itself as "fixed in 2.9.1" — a tag that was never cut. That is the specific
failure mode of distributed authoring on a repo whose entire job is to be the one
agreed description of a machine.

**A VM fixing its own provisioner cannot cleanly test the fix.** The provisioner
is the thing under change *and* the thing running; a defect that only manifests
on older bases (as the 3.0.9 PATH-probe bug did) is invisible from a VM that has
already been re-provisioned. The authoring host is deliberately not a workload
VM, so it can hold a checkout at an arbitrary revision without disrupting work.

The honest counter is that a rule enforced only by attachment gets broken the
moment it is inconvenient — which is exactly what happened on 2026-08-19, when
`repo-iv-provision-rw` was attached to `iv-foundry-stage2` as an expedient and a
dozen commits were pushed from there. The answer is to make compliance cheap
rather than to abandon the rule: the authoring VM exists, `ssh iv-provision`
reaches it from anywhere on the tailnet, and a re-provision there costs ~23
seconds. If an exception is genuinely needed, attach the writer deliberately,
land the change by PR, and **detach it again** — the exception should be an
event, not a new steady state.

### What else holds

No VM worktree is authoritative, and a checkout on a fleet VM is expected to sit
detached at a release tag (see `consuming.md`). Linux compatibility canaries are
created on demand and stay read-only unless a writer is deliberately attached;
delete the canary after validation.

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
| `provision-iv.sh`       | Provisions the IV layer onto the IV base image (tailscale, uv, claude, codex, Entire + plugins, DuckDB, Apex, tigris/rclone, herdr, AgentsView, doc-site tools, agent config, skills); writes `~/iv-provision.lock`. |
| `vendor-skills.sh`      | Refreshes the vendored skills snapshot in `skills/` (needs node/npx).                                                                                      |
| `skills/`               | Vendored, pinned team skills — committed to the repo so they are frozen.                                                                                   |
| `bin/`                  | `render-site` + `provision-docsite` + `gen-llms-txt` + `install-cloud-cli` (on-demand aws/azure/gcloud) — installed onto PATH.                                 |
| `agent/`                | Team agent config: `AGENTS.md`, Claude Code `settings.json`, Codex `config.toml`, MCP setup.                                                               |
| `vendor/`               | Third-party/IV code vendored with a SHA pin verified at install (`entire-agent-agentsview`).                                                               |
| `provisioning/`         | Declarative source for the team layer: `skills.manifest`, `mcp.manifest`, `agents-shared.md`. `vendor-skills.sh` reads these; nothing is fetched from another repository. |
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
