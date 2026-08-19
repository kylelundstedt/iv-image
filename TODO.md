# TODO

Open work only. Release history → the table in `index.qmd`. Historical
research (custom-image / arm64 era) → `registry.md`.

## Decouple from the personal dotfiles repo

The team layer must stand alone: a fleet VM should provision fully without
`kylelundstedt/dotfiles`. Ordered by severity.

Done so far (all 2026-08-18): `tailscale`, `uv`, `claude`, and `codex` are
installed here, and the `provisioning/` manifests moved in-tree, retiring
`dotfiles-manifest.pin`. `provision-iv.sh` now has no functional dotfiles
dependency.

`node`/fnm was considered and deliberately left to dotfiles: the only thing that
needs it is `vendor-skills.sh`, which runs at authoring time and never on a VM.

Still to do on the **dotfiles** side. Its integration is read-only from every
host that has it, including the authoring VM, so these edits must happen on a
workstation with dotfiles write access:

- [ ] Retire `diff-provisioning.sh`, which policed a pin that no longer exists.
- [ ] Move `claude`/`codex`/`uv` from `personal` to `team` in `tools.manifest`.
      This repo installs all three, and the manifest asserts
      `personal ∩ provision-iv.sh = ∅`, so the assertion is currently false.
- [ ] Drop the copy of `entire-push-exclude.txt` that moved to `provisioning/`
      here.

- [ ] **Copy over the load-bearing rationale** now cross-linked into
      `dotfiles/agent_docs/` (`vm-disk-weight.md`, `exe-dev-remediation.md`
      Track 2) so `exeslim/FORK.md` and this repo stop dangling.

## Own the Entire ACR capture path

Done 2026-08-18: the CLI (pinned 0.8.42, checksummed), the
`entire-agent-shelley` plugin (0.1.3), and the vendored
`entire-agent-agentsview` adapter are installed by `provision-iv.sh` and recorded
in the lock file; `entire enable` is deliberately left out as a per-repo
governance action; and `entire-push-exclude.txt`
moved into `provisioning/`. `entire-push-check` itself stays in dotfiles, being
macOS-only and part of the auditing control plane rather than the audited VMs.
What remains:

- [ ] Decide whether `ave-adapters` should be enrolled. Entire is enabled in
      `fannie-sflpd*` and `iv-docs*` but in **none** of the nine `ave-adapters`
      worktrees, so agent-authored commits there carry no ACR — which
      `iv-acr-required-v0` may reject at promotion. Because `.entire/` is tracked
      in git, enrolling is one `entire enable` plus one commit, inherited by all
      worktrees and future clones. Re-verified 2026-08-19: `~/iv-docs/.entire`
      exists on `iv-docs`, and no `.entire` exists anywhere under
      `~/ave-adapters` on `iv-ave-adapters`. (The summary above previously
      claimed `ave-adapters` was already enrolled; it is not, and that claim has
      been removed.)
- [ ] Re-qualify `entire-agent-shelley` against a current Entire CLI. The pin is
      0.8.42 because 0.1.3 was qualified only against it; upstream is at 0.10.1.
      Until then the CLI cannot be bumped without risking the capture path.

## AgentsView

- [ ] Upstream request: throttle re-sync. Every Shelley write to
      `shelley.db-wal` retriggers a full reprojection of all conversations
      (~every 15s while active; 7.1% of one core sustained, 344 MB RSS).
      `serve` exposes no knob — only `--events-coalesce-interval` (SSE) and
      `--no-sync` (all-or-nothing).
- [ ] Reconcile ADR 0010's "AgentsView is the fallback/backfill/reconciliation
      path" language with the single-producer topology. Both AgentsView and
      `entire-agent-shelley` read the *same* Shelley SQLite, so AgentsView cannot
      be a fallback *for capture loss*: if that database is corrupt, truncated, or
      a conversation never landed in it, both readers fail identically. It is a
      second reader of one source, not a second source, and calling it a fallback
      invites exactly the wrong conclusion — that the capture path is redundant
      when it has a single point of failure.

      Proposed reframing, to replace the fallback language rather than merely
      soften it. AgentsView is:

      1. the **read plane** — FTS, model attribution, health grading, MCP; and
      2. the **cross-agent** capture path — it is the only thing that can attach
         Claude Code or Codex sessions to a checkpoint, which
         `entire-agent-shelley` cannot do at all. That is a real capture
         capability, but for *different agents*, not a backup for the same one.

      The single point of failure is the Shelley SQLite itself. If that risk is
      worth mitigating, the mitigation is backing up that database — which
      `install_shelley` already does per provision, via the SQLite backup API —
      not a second reader of it. Verified 2026-08-18: 134/134 sessions match and
      nothing is lost; tool traffic is relocated into `tool_calls` (16,417 rows),
      not dropped.
- [ ] `usage_events` is empty, so `cost_usd` is null and `agentsview usage` /
      `token-use` report nothing. Determine whether Shelley's usage data can be
      projected, or drop the cost-analytics claim.

## Base image (`kylelundstedt/exeslim`)

- [ ] Merge upstream `ryanlewis/exeslim`. Re-checked 2026-08-19: our `main` is at
      `2d1a663` (2026-08-18) and upstream's last commit is `9e681cc`
      (2026-08-05, "adopt the shared Renovate config"), so the gap is one
      housekeeping commit rather than the security backlog the earlier note
      implied — the dates in that note were wrong in both directions. The
      structural point stands and is the reason to keep this open: the weekly
      rebuild runs against *our* Dockerfile, so any future upstream security work
      reaches the fleet only after a merge.
- [ ] **Decide a base-image recreate cadence, or accept the drift explicitly.**
      A VM cannot be migrated to a newer image — exe.dev fixes the image at
      creation and offers no swap — so this is a recreate decision, not an
      upgrade one.

      What a stale base actually costs is narrow, and worth stating plainly so
      the decision is not made out of vague unease: CVEs land via
      `iv-apt-upgrade.timer` on every VM daily, so a stale base does **not** mean
      unpatched packages. What it misses is *newly added* packages (e.g.
      `nginx-light`, `openssh-client`) and image-level changes to the boot path.

      Fleet state 2026-08-19 (from `~/iv-provision.lock`):

      | Base | VMs |
      | ---- | --- |
      | `exeslim-dev` `2026-08-18.11.1` | `iv-provision` |
      | `exeslim-dev` `2026-07-29.6.1` | `iv-docs`, `iv-ave-adapters`, `iv-gitlake`, `iv-gitlake-examples`, `iv-home`, `iv-foundry-stage2` |
      | pre-exeslim `exe` | `kgl-songs` (`main`, 2026-08-05), `kgl-thoughts` (`nightly`, 2026-06-16), `telnyx-vm` (`nightly`, 2026-07-21) |

      The three `exe`-base VMs are the interesting ones: that base ships
      `claude`/`codex`/`uv` in `/usr/local/bin`, which is what surfaced the 3.0.9
      PATH-probe defect. They are the most likely to surface the next
      base-dependent bug too.

## Other

- [ ] `provision-docsite`: separate the rendered build directory from the
      nginx docroot so a preview render cannot modify the live site.
- [ ] The three pre-exeslim `exe`-base VMs still carry duplicate agent binaries
      in `/usr/local/bin` (`claude`, `codex`, `uv`), shadowed by the copies in
      `~/.local/bin` that win PATH. Since 3.0.9 the provisioner *reads* those
      copies correctly, so they are no longer harmful — on `kgl-songs` they are
      in fact the live ones — but a shadowed 260 MB `claude` is wasted disk
      wherever the `~/.local/bin` copy wins. Decide whether to prune, or fold
      into the recreate cadence above.
- [x] ~~`iv-entire-agent-shelley` unreachable over the tailnet.~~ Resolved
      2026-08-19: `tag:dev` added to the node in the Tailscale console, alongside
      its existing `tag:iv-aperture-pilot`. The VM was never off the tailnet —
      `tailscale ping` answered in 3 ms throughout — it was the SSH policy
      dropping TCP/22, since that rule is keyed on `tag:dev`. Upgraded to 3.0.9
      the same day; it was the last VM on 2.9.0. Whole fleet is now on one tag.

## Authoring and access

- [ ] **Create the `tailnet` exe.dev tag and attach `api-tailscale` to it.**
      Owner action, off-VM; documented in `tailnet.md` → "The `tailnet` tag".

      ```bash
      ssh exe.dev integrations attach api-tailscale tag:tailnet
      ssh exe.dev tag <vm> tailnet          # per VM that should stay a member
      ```

      Decided 2026-08-19: a **dedicated** tag rather than reusing `tag:iv`.
      `iv` already means "gets the MCP integrations"; adding key-minting to it
      would make one tag mean two unrelated things, the second far stronger —
      the same widening `auto:all` was rejected for, but disguised as reuse.
      `auto:all` stays rejected outright: it would cover every future VM,
      including sandboxes running untrusted code.

      Why it is worth doing: a recreated VM currently cannot rejoin unattended,
      and cannot be fixed from another VM — it is not on the tailnet yet, and
      `*.exe.xyz` needs an exe.dev SSH key no VM holds, so the bootstrap is
      breakable only from a workstation.

      Note `tailnet` is an **exe.dev** tag, unrelated to Tailscale's `tag:dev`.
      Tailscale's side needs no fleet decision — `provision-iv.sh` hardcodes
      `"tags":["tag:dev"]` into every join key, so any VM this repo joins is
      tagged by construction; only a node joined by some other path can miss it,
      as `iv-entire-agent-shelley` did.
- [ ] Consolidate `tag:iv` and `mcp-agent`, which overlap — both effectively
      mean "an IV fleet VM that gets the MCP integrations", and the fleet is
      split across them (`iv-provision` has `iv`; most others have `mcp-agent`).
      Deliberately *not* bundled with the `tailnet` tag work above: pairing a
      rename-and-retag with a security-relevant grant is how one of the two ends
      up unreviewed.
- [ ] Establish that control-plane facts are checked **off-VM**. Three
      consecutive corrections to `tailnet.md`'s tag section were the same
      mistake: reasoning about exe.dev attachment from inside a VM.
      `reflection.int.exe.xyz` reports a VM's own tags and its own integrations,
      never the attachment *rules*, so from a VM there is no way to tell whether
      an integration arrived by `vm:`, `tag:`, or `auto:all` — effects are
      visible, rules are not. `ssh exe.dev integrations` is the authority.

      **The gap is closable, and "a VM cannot reach the control plane" was too
      strong a claim.** What a VM lacks is an *SSH key* in the exe.dev account —
      but exe.dev also exposes the same CLI over HTTPS at `POST https://exe.dev/exec`,
      authenticated by a bearer token, and that endpoint is reachable from here
      (it answers 401, not a connection failure). A scoped, expiring token would
      let the authoring host verify attachment rules for itself instead of
      routing every such question through the owner.

      Worth doing deliberately, because the token is a real credential on a VM —
      exactly what the integration model exists to avoid. Mitigations the API
      already supports: `cmds` restricts a token to named commands, so a
      read-only token (`["integrations","ls","tags"]`, no `new`/`rm`/`attach`)
      cannot change anything; `exp` bounds replay. Generated with
      `ssh exe.dev ssh-key generate-api-key --exp=30d` plus a `cmds` restriction,
      stored `0600` outside the repo.

      Until then, any claim in these docs about *how* something is attached needs
      an owner-side check before it is written down.
- [ ] Re-attaching `repo-iv-provision-rw` to a second VM should be an event, not
      a state. On 2026-08-19 it was attached to `iv-foundry-stage2` as an
      expedient, a dozen commits were pushed from there, and it was detached the
      same day. The README's "Authoring boundary" section now documents the
      single-writer rule and what to do when an exception is genuinely needed;
      there is no mechanical enforcement beyond the attachment itself, so this
      stays a thing to notice rather than a thing that is guaranteed.
- [ ] `api-tailscale` is currently attached to nothing, which is the intended
      steady state (attach → join → detach). Note that a *joined* VM stays joined
      after detachment — verified on `iv-provision` 2026-08-19, which has been
      routing all fleet SSH with the integration detached. Nothing to do; recorded
      so the next person does not "fix" the absence.
