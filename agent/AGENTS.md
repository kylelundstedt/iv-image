# IV Agent Instructions

Team-wide defaults for AI agents on iv-image VMs. Personal dotfiles layer on
top — anything here can be overridden by `~/.agents/AGENTS.md` from your own
dotfiles.

## Code

- Verify before asserting — read the code, don't guess.
- Prefer concrete findings with file and line references.
- Don't add features, abstractions, or cleanup beyond what was asked.
- Formatters: Prettier for Markdown (`npx prettier --write "**/*.md"`), Ruff for Python (`uv run ruff format .`). Run before committing.

## Data Work

- Prefer SQL first, then Python, then bash. Use the simplest language that gets the job done.
- SQL dialect: DuckDB, including DuckDB-specific syntax (EXCLUDE, REPLACE, GROUP BY ALL, list/struct literals, etc.).
- Python package/project management: uv. Never use pip directly.
- Preferred Python libraries: polars (not pandas), dlt for ingestion, sqlmesh for transformations, duckdb for local analytics, marimo for notebooks, altair/seaborn for visualization.
- Use node+npm for JavaScript environment management.

## TODO

- At the start of a session, check for `TODO.md` in the project root. If it exists, read it to understand outstanding work.
- When completing a task from `TODO.md`, mark it done. When new work is identified, add it.
- Keep entries short — one line per item, grouped by topic if needed.

## Skills

- Global: `~/.agents/skills/<name>/SKILL.md`, symlinked into `~/.claude/skills/` and `~/.codex/skills/`.
- Project-level: `.claude/skills/<name>/SKILL.md` in the repo root.
- **Read skills before touching a platform.** Before writing code, running commands, or creating/managing VMs on any platform that has a skill, you MUST read the relevant SKILL.md file first. Do not proceed from memory — skills contain platform-specific gotchas that cause hours of debugging when ignored.

## exe.dev SSH

- **Never launch parallel SSH attempts to `*.exe.xyz`.** One attempt at a time — wait for the result before retrying.
- exe.dev silently drops TCP SYNs per source IP. Multiple concurrent attempts (including background retry loops) trigger a minutes-long lockout.
- After creating a VM, wait ~20s, then try **one** SSH with `ConnectTimeout=30`. If it fails, wait 30-60s before **one** more attempt.
