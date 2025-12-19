# LLM Council Plugin Development Context

> **Purpose**: Core project instructions for AI agents. For comprehensive development guidelines, see @docs/DEVELOPMENT.md.

## What is LLM Council Plugin?

A Claude Code plugin that orchestrates **multi-model LLM consensus** through collaborative deliberation. Coordinates Claude, OpenAI Codex, and Google Gemini for:
- Collaborative AI code review
- Multi-perspective problem-solving
- Consensus-based decision making
- Three-phase deliberation protocol (Opinion → Peer Review → Synthesis)

**Use when**: You need multiple AI perspectives on complex decisions, code reviews, or architectural choices.

## Core Architecture

- **Phase 1**: Parallel opinion collection from available LLMs
- **Phase 2**: Anonymous cross-examination peer review
- **Phase 3**: Chairman agent synthesizes consensus
- **Output**: Comprehensive markdown report in `.council/final_report.md`

## Quick Development Workflow

**Before any commit**:
```bash
# 1. Run test suite (REQUIRED)
./tests/test_runner.sh

# 2. Validate manifests (if changed)
claude plugin validate .

# 3. Set execute permissions on NEW scripts (only if you added scripts)
find hooks/ skills/*/scripts/ tests/ -name "*.sh" -type f ! -perm -u+x -exec chmod +x {} \;
```

**Path resolution** (for plugin files):
```bash
PLUGIN_ROOT="${COUNCIL_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CLAUDE_PROJECT_DIR}}}"
source "${PLUGIN_ROOT}/skills/council-orchestrator/scripts/council_utils.sh"
```

## Project Structure

- `commands/` – Slash command definitions (e.g. `/council`, `/council-status`)
- `agents/` – Sub-agent definitions, especially the council chairman
- `skills/council-orchestrator/` – Core orchestration Skill and Bash scripts
- `hooks/` – Lifecycle hooks (`hooks.json`, `pre-tool.sh`, `post-tool.sh`)
- `tests/` – Minimal smoke tests and integration checks
- `.claude-plugin/` – Plugin manifest (`plugin.json`) and marketplace metadata (`marketplace.json`)
- `docs/` – User-facing docs; `INSTALL.md` is the canonical installation & debugging guide

## User-Facing Commands

- `/council <question>` - Start multi-model consensus deliberation
- `/council-status` - Check CLI availability and quorum status
- `/council-config [set <key> <value> | reset]` - Manage configuration
- `/council-cleanup` - Remove `.council/` working directory
- `/council-help` - Display usage documentation

## Key Development Patterns

### Slash Commands
- Use **instructional approach** (not `!bash` prefix)
- Models: Opus 4.5 (complex), Sonnet 4.5 (orchestration), Haiku 4.5 (simple)
- Arguments: `$ARGUMENTS` for single input, `$1 $2 $3` for subcommands
- Details: @docs/COMMANDS_GUIDE.md

### Skills
- Progressive disclosure: SKILL.md (~150 lines) + REFERENCE.md
- Include "Use when you need..." trigger terms in descriptions
- Details: @docs/SKILLS_GUIDE.md

### Hooks
- Use `hookSpecificOutput` wrapper in JSON output (required by API)
- Security model: allow by default, fail open
- Details: @hooks/README.md

### Path Resolution (Critical)
- Plugin files: `${COUNCIL_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CLAUDE_PROJECT_DIR}}}`
- User files (`.council/`): `${CLAUDE_PROJECT_DIR}` directly
- ❌ Never use relative paths like `./skills/...`
- Details: @docs/PATH_RESOLUTION.md

### Council Working Directory
- `.council/` = most recent `/council` run only
- Reset at session start, cleanup via `/council-cleanup`

## Plugin & Marketplace Metadata

- `plugin.json` describes the plugin (paths relative, starting with `./`)
- `marketplace.json` follows official marketplace schema
- When changing manifests, also update `docs/INSTALL.md` and `README.md`
- Validate before publishing: `claude plugin validate .`

**Note**: Standard component directories are auto-discovered. Claude Code v2.0.73+ auto-loads `hooks/hooks.json`; `plugin.json` `hooks` should only reference additional hook files (e.g. `./hooks/extra-hooks.json`) or inline config. Do NOT point `hooks` to `./hooks/hooks.json` or you'll get duplicate loading errors.

**Official References**:
- [Plugin Manifest Reference](https://code.claude.com/docs/en/plugins-reference.md)
- [Marketplace Schema](https://code.claude.com/docs/en/marketplace.md)
- [Plugin Development Guide](https://code.claude.com/docs/en/plugins.md)

## Testing

```bash
./tests/test_runner.sh     # Required before commits
claude plugin validate .   # Manifest validation
```

## Style

- Shell: `bash`, `set -euo pipefail`, 2-space indent, `snake_case` functions
- Paths in manifests: relative, starting with `./`
- Commits: `scope: short imperative description`

## Subagent Configuration

@AGENTS.md

## Detailed Guidelines

@docs/DEVELOPMENT.md
