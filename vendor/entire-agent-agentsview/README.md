# Vendored: `entire-agent-agentsview`

Entire external-agent adapter backed by AgentsView's normalized archive. It
attaches sessions produced by **Shelley, Claude Code, Codex, or any other
AgentsView provider** to an Entire checkpoint. Attach-only: it installs no live
lifecycle hooks and never writes restored sessions back into AgentsView or a
native agent store.

In ADR 0010's routing this is the **fallback, backfill, and reconciliation**
path across agents. Live source-native capture for Shelley is
`entire-agent-shelley`; native Entire integrations cover Claude Code and Codex.

## Provenance

| | |
| --- | --- |
| Canonical source | `kylelundstedt/iv-docs`, `spikes/23-harness/entire-agent-agentsview` |
| Vendored from | iv-docs commit `b016b7c8dde15562f4fb28ec1bf23f82b6325750` |
| SHA-256 | `801065264f065068f5e8da8e58af61669c24ee10a6b4dff2a2e411660f4de84e` |
| Entire external-agent protocol | `v1` |
| Vendored on | 2026-08-18 |

`provision-iv.sh` verifies that SHA-256 before installing, so a silent edit
to the vendored copy fails provisioning rather than shipping.

## Why vendored rather than symlinked

It was on `iv-foundry-stage2`'s `PATH` as
`~/.local/bin/entire-agent-agentsview` -> a **spike worktree**
(`~/worktrees/iv-docs-fannie-memory/spikes/23-harness/`). A fleet capability must
not depend on a branch-specific worktree that can be pruned at any time, and it
was not provisioned at all, so it did not survive a VM recreate.

## Keeping it current

iv-docs remains canonical: edit it there, then re-copy here and bump the pin in
`provision-iv.sh` (`ENTIRE_AGENTSVIEW_SHA256`) in the same commit. If this
adapter accumulates its own qualification record it should graduate to a
standalone repository, as `entire-agent-shelley` did.

Tests (`test.sh`, `test-real.sh`) stay with the canonical copy in iv-docs; only
the executable is vendored.
