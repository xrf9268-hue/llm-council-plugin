# Repository Guidelines

## Project Structure & Module Organization

- `commands/` – Slash command definitions (e.g. `/council`, `/council-status`).
- `agents/` – Sub-agent definitions, especially the council chairman.
- `skills/council-orchestrator/` – Core orchestration Skill and Bash scripts.
- `hooks/` – Lifecycle hooks (`hooks.json`, `pre-tool.sh`, `post-tool.sh`).
- `tests/` – Minimal smoke tests and integration checks.
- `.claude-plugin/` – Plugin manifest (`plugin.json`) and marketplace metadata (`marketplace.json`).
- `docs/` – User-facing docs; `INSTALL.md` is the canonical installation & debugging guide.

Keep new files in these folders unless there is a strong reason to introduce a new top‑level directory.

## Plugin & Marketplace Metadata

- `plugin.json` describes the plugin itself; keep `commands`, `agents`, `skills`, and `hooks` paths relative and starting with `./`.
- `marketplace.json` must follow the official marketplace schema (`name`/`owner`/`plugins`) and expose the `llm-council` marketplace with the `llm-council-plugin` entry.
- When changing `.claude-plugin/*` manifests or installation flows, also update `docs/INSTALL.md` and the Installation section in `README.md` to stay in sync.
- `plugin.json` must use an `author` **object** (not a string), and should not introduce extra top-level keys beyond the official plugin manifest schema (for example, do not add `strict` here).
- `marketplace.json` plugin entries must only use fields allowed by the marketplace schema; if you need rich marketing content (screenshots, long descriptions, pricing, changelog, etc.), keep it in `README.md` / `docs/INSTALL.md`, not in the marketplace entry.
- Paths in manifests should use the current filenames (e.g. `"./commands/council.md"` for the main `/council` command).
- Before publishing changes to manifests, run `claude plugin validate .` locally to catch schema errors early.

## Slash Commands

- Slash command files live in `commands/` and follow the official rule `/<command-name>` where `<command-name>` is derived from the Markdown filename (without `.md`), e.g. `council.md` → `/llm-council-plugin:council`.
- You can still present a shorter user-facing form like `/council` in the command body, but the namespaced form (`/plugin-name:<command-name>`) always comes from the filename, so choose filenames accordingly.
- When a command accepts arguments, add an `argument-hint` in the frontmatter that matches how users invoke it (e.g. `<question>` or `[set <key> <value> | reset]`) and explicitly wire that into the prompt using `$ARGUMENTS` (all args) or `$1`, `$2`, `$3`, etc. for structured subcommands.

## Build, Test, and Development Commands

- `./tests/test_runner.sh` – Run the test suite (idempotent; safe to run often).
- `chmod +x hooks/*.sh skills/council-orchestrator/scripts/*.sh` – Ensure new or edited scripts remain executable.

There is no separate build step; this repository is loaded directly by Claude Code as a plugin.

## Coding Style & Naming Conventions

- Shell scripts: `bash`, `set -euo pipefail`, 2‑space indentation, functions in `snake_case`, environment variables in `UPPER_SNAKE_CASE`.
- Markdown: start with a single H1, use `##`/`###` for structure, fenced code blocks with language tags (`bash`, `json`, etc.).
- Paths in manifests: always relative and starting with `./` (e.g. `"./commands/council.md"`).

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
