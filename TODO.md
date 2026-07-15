# TODO

Open work only. Release history → the table in `index.qmd`. Historical
research (custom-image / arm64 era) → `registry.md`.

- [ ] `provision-docsite`: separate the rendered build directory from the
      nginx docroot so a preview render cannot modify the live site.
- [ ] `provision-iv.sh` (~line 175): merge `~/.claude/settings.json` instead
      of overwriting — reprovisioning wipes hooks a personal dotfiles overlay
      spliced in. The upgrade-vm skill's re-run-the-overlay step (2026-07-14)
      covers it procedurally; do this if that step proves error-prone.
