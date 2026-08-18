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

Still to do on the **dotfiles** side (its integration here is read-only, so these
edits must happen elsewhere): retire `diff-provisioning.sh`, which policed a pin
that no longer exists; move `claude`/`codex`/`uv` from `personal` to `team` in
`tools.manifest`, since this repo now installs them and the manifest asserts
`personal ∩ provision-iv.sh = ∅`; and drop the copy of
`entire-push-exclude.txt` that moved to `provisioning/` here.

- [ ] **Copy over the load-bearing rationale** now cross-linked into
      `dotfiles/agent_docs/` (`vm-disk-weight.md`, `exe-dev-remediation.md`
      Track 2) so `exeslim/FORK.md` and this repo stop dangling.

## Own the Entire ACR capture path

Done 2026-08-18: the CLI (pinned 0.8.42, checksummed), the
`entire-agent-shelley` plugin (0.1.3), and the vendored
`entire-agent-agentsview` adapter are installed by `provision-iv.sh` and recorded
in the lock file; `entire enable` is deliberately left out as a per-repo
governance action; `ave-adapters` is enrolled; and `entire-push-exclude.txt`
moved into `provisioning/`. `entire-push-check` itself stays in dotfiles, being
macOS-only and part of the auditing control plane rather than the audited VMs.
What remains:

- [ ] Decide whether `ave-adapters` should be enrolled. Entire is enabled in
      `fannie-sflpd*` and `iv-docs*` but in **none** of the nine `ave-adapters`
      worktrees, so agent-authored commits there carry no ACR — which
      `iv-acr-required-v0` may reject at promotion. Because `.entire/` is tracked
      in git, enrolling is one `entire enable` plus one commit, inherited by all
      worktrees and future clones.
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
      `entire-agent-shelley` read the *same* Shelley SQLite, so it is not a
      fallback for capture loss; its real value is the read plane (FTS, model
      attribution, health grading, MCP). Verified 2026-08-18: 134/134 sessions
      match and nothing is lost — tool traffic is relocated into `tool_calls`
      (16,417 rows), not dropped.
- [ ] `usage_events` is empty, so `cost_usd` is null and `agentsview usage` /
      `token-use` report nothing. Determine whether Shelley's usage data can be
      projected, or drop the cost-analytics claim.

## Base image (`kylelundstedt/exeslim`)

- [ ] Merge upstream `ryanlewis/exeslim` — the fork is behind (ours pushed
      2026-08-01, upstream 2026-08-09), and the weekly rebuild runs against
      *our* Dockerfile, so upstream security work only lands after a merge.
- [ ] Fleet VMs are pinned to whatever base they were created from and cannot be
      migrated (`iv-foundry-stage2` runs `2026-07-29.6.1`; `2026-08-17.10.1`
      exists). CVEs still land via `iv-apt-upgrade.timer`; what a stale base
      misses is *newly added packages* (e.g. `nginx-light`, `openssh-client`).
      Decide a recreate cadence, or accept drift explicitly.

## Other

- [ ] `provision-docsite`: separate the rendered build directory from the
      nginx docroot so a preview render cannot modify the live site.
- [ ] `provision-iv.sh` (~line 175): merge `~/.claude/settings.json` instead
      of overwriting — reprovisioning wipes hooks a personal dotfiles overlay
      spliced in. The upgrade-vm skill's re-run-the-overlay step (2026-07-14)
      covers it procedurally; do this if that step proves error-prone.
