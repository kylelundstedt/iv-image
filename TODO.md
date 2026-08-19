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

- [x] ~~Enroll `ave-adapters` in Entire ACR capture.~~ Done: `ff5cc95 chore:
      enable Entire Shelley capture` (2026-08-18) is on `origin/main`, settings
      byte-identical to `fannie-sflpd`/`iv-docs` (git-branch backend, telemetry
      off, external agents on), tracking only `.entire/settings.json` and
      `.entire/.gitignore` so all nine worktrees and future clones inherit it.
      Confirmed 2026-08-19 from `iv-ave-adapters`: `entire status` reports
      **Enabled** on `main` with the Shelley lifecycle hooks registered and
      checkpoints syncing to origin.
- [x] ~~Re-qualify `entire-agent-shelley` against a current Entire CLI.~~ Done
      (release 3.0.15). CLI bumped 0.8.42 → 0.10.1 after re-qualifying plugin
      0.1.3 against it on `iv-entire-agent-shelley` — full live suite incl. real
      checkpoint condensation passed; 0.10.0 passed identically, 0.10.1 pinned
      as the newer stable. Evidence in the plugin repo
      (`QUALIFICATION-v0.1.3-cli0.10.1.md`). Fleet re-provisioned to 3.0.15;
      every VM now runs Entire CLI 0.10.1 with plugin 0.1.3.
- [ ] Evaluate the `refs` checkpoint backend (do **not** flip yet). CLI 0.10.1's
      `entire enable` recommends `--checkpoint-backend refs` (one git ref per
      checkpoint) over the `branch` backend the fleet uses (a shared
      `entire/checkpoints/v1` orphan branch). Bench-measured on
      `iv-entire-agent-shelley` 2026-08-19 against plugin 0.1.3: `refs` produces
      `"type":"git-refs"`, seeds no orphan branch at enable, and the plugin
      captures correctly under it — commit trailer added, transcript captured,
      metadata byte-identical (`full.jsonl`/`metadata.json`/`prompt.txt`/
      `transcript.jsonl`). Storage moves to `refs/entire/checkpoints/<shard>/<id>`,
      **outside** `refs/heads/*`; propagation is the backend-aware `entire hooks
      git pre-push` hook, not a push refspec. So the plugin side is cheap. The
      cost is elsewhere, and is why this is not a flag flip:
      1. **Qualify `refs` against 0.1.3** — the live suite
         (`test-shelley-live.sh`) hard-codes `refs/heads/entire/checkpoints/v1`
         in four places (settings, the `--checkpoint-backend` flag, and the
         verification block L204-208), so it currently *cannot* qualify `refs`;
         it needs a `refs`-aware variant. ~an afternoon.
      2. **Confirm AgentsView reads `refs/entire/*`** — the real gate, and the
         one thing the bench cannot answer. ADR 0010 makes AgentsView the
         backfill/reconciliation path and it is built against the `v1` branch
         layout; if it does not read the new refs, switching **silently breaks
         reconciliation** (the exact quiet-provenance-loss failure this section
         exists to prevent). Verify against the running AgentsView. If no, stop.
      3. **Decide existing history** — a switch does not migrate it. `iv-docs`
         already has 16 checkpoint commits on `origin/entire/checkpoints/v1`;
         new checkpoints would go to `refs/entire/*`, stranding the old ones
         unless a dual-read or a one-time migration copies them. Per enrolled
         repo (`iv-docs`, `fannie-sflpd*`, `ave-adapters`, ...).
      4. **Flip fleet-wide as one coordinated change** — `settings.json` is
         committed and inherited by all worktrees/clones, so mixing backends
         across enrolled repos fragments how checkpoints are read. All-or-nothing.
      Trigger to actually do it: upstream deprecating `branch`, or hitting the
      push-contention `refs` was built for (we are not — low concurrency per
      repo). Until then `branch` is qualified, fleet-consistent, and carrying
      real history.

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

- [x] ~~Merge upstream `ryanlewis/exeslim`.~~ Nothing to merge — re-verified
      2026-08-19 against a real `git fetch upstream`, not the stale SHAs the
      prior note carried. `git merge-base --is-ancestor upstream/main main`
      returns true: upstream's head `9e681cc` ("adopt the shared Renovate
      config") is **fully contained** in our `main`, brought in by our merge
      commit `a22636d`. `git log main..upstream/main` is empty. The earlier
      "one housekeeping commit behind" was written before that merge landed.
      Our fork adds eight commits upstream lacks (own GHCR namespace, the
      `exeslim-dev` image, `openssh-client`/`nginx-light`/`libyaml-0-2`, Shelley
      units, `FORK.md`) — all legitimate fork content, none of it upstream-bound.
      The structural point still holds as an *ongoing* task, not a backlog item:
      the weekly rebuild runs against **our** Dockerfile, so re-fetch upstream
      periodically and merge if it moves — there is simply nothing outstanding
      right now.
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
- [x] ~~Narrow the tailnet credential.~~ Done 2026-08-19: `auth_keys` on
      `tag:dev` only, `devices:core` dropped, old client revoked. Verified after
      the swap — join path mints preauthorized `tag:dev` keys (200), everything
      else 403. A broker proved unnecessary; Tailscale's scopes covered it. What
      a broker would still add is a *per-VM* bound, which the scope model cannot
      express since every tagged VM shares one credential — revisit only if that
      specific property is wanted.
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

      **It is one command, run from a workstation** (`--cmds` is the allow-list,
      `--label` creates a separately revocable SSH key behind the token):

      ```bash
      ssh exe.dev ssh-key generate-api-key \
        --label=iv-provision-ro --cmds=integrations,ls,tags --exp=30d
      ```

      Then, on this VM, with the token in a `0600` file outside the repo:

      ```bash
      curl -X POST https://exe.dev/exec \
        -H "Authorization: Bearer $(cat ~/.config/exe/api-token)" -d 'integrations'
      ```

      Three properties make this a bounded grant rather than an open one.
      `cmds` is an allow-list of *command names*, and subcommands must be listed
      explicitly — granting `integrations` does not grant `integrations attach`,
      so the token literally cannot attach, detach, create or delete. `exp`
      bounds replay. And `--label` mints a dedicated SSH key, so revoking is
      removing that one key, with normal SSH access unaffected.

      Still a real credential on a VM, which is exactly what the integration
      model exists to avoid — so it is the owner's call, not an assumption. The
      argument for it is that three documentation errors in one evening all came
      from *inferring* control-plane state that a one-line query would have
      settled.

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
