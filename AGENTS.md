# Repository Guidelines

## Project Structure & Module Organization

- `commands/` – Slash command definitions (e.g. `/council`, `/council-status`).
- `agents/` – Sub-agent definitions, especially the council chairman.
- `skills/council-orchestrator/` – Core orchestration Skill and Bash scripts.
- `hooks/` – Lifecycle hooks (`hooks.json`, `pre-tool.sh`, `post-tool.sh`).
- `tests/` – Minimal smoke tests and integration checks.
- `.claude-plugin/` – Plugin manifest (`plugin.json`) and marketplace metadata.

Keep new files in these folders unless there is a strong reason to introduce a new top‑level directory.

## Build, Test, and Development Commands

- `./tests/test_runner.sh` – Run the test suite (idempotent; safe to run often).
- `chmod +x hooks/*.sh skills/council-orchestrator/scripts/*.sh` – Ensure new or edited scripts remain executable.

There is no separate build step; this repository is loaded directly by Claude Code as a plugin.

## Coding Style & Naming Conventions

- Shell scripts: `bash`, `set -euo pipefail`, 2‑space indentation, functions in `snake_case`, environment variables in `UPPER_SNAKE_CASE`.
- Markdown: start with a single H1, use `##`/`###` for structure, fenced code blocks with language tags (`bash`, `json`, etc.).
- Paths in manifests: always relative and starting with `./` (e.g. `"./commands/summon-council.md"`).

Prefer small, composable scripts over large monoliths. Avoid one‑letter variable names in new code.

## Testing Guidelines

- Add or update tests in `tests/test_runner.sh` when changing orchestration logic, hooks, or commands.
- Aim to cover:
  - Happy path council runs.
  - Failure/degradation paths (missing CLIs, rate limits).
- Keep tests fast; avoid network calls inside the test harness.

## Commit & Pull Request Guidelines

- Commit messages: short, imperative, and scoped, e.g. `Align hooks with docs`, `Add council-status command`.
- Group related changes into a single commit; avoid mixing refactors with behavior changes without explanation.
- PRs should include:
  - A brief summary of motivation and behavior change.
  - Notes on testing (`./tests/test_runner.sh` results).
  - Any user-facing command or config changes called out explicitly.
