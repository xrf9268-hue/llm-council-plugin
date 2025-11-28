# LLM Council Plugin Development Context

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

## Repository Guidelines & Standards

All repository guidelines, project structure, and technical standards are documented in:
- @AGENTS.md – canonical reference for repository structure, naming conventions, testing, and commit guidelines

Follow this file as the single source of truth for:
- Project structure and module organization
- Plugin and marketplace metadata conventions
- Slash command development patterns
- Build, test, and development workflows
- Coding style and naming conventions
- Testing guidelines and requirements
- Commit and PR standards
- Path resolution best practices

## Quick Command Reference

**User-facing commands**:
- `/council <question>` - Start multi-model consensus deliberation
- `/council-status` - Check CLI availability and quorum status
- `/council-config [set <key> <value> | reset]` - Manage configuration
- `/council-cleanup` - Remove `.council/` working directory
- `/council-help` - Display usage documentation

**Development commands**:
- `./tests/test_runner.sh` - Run full test suite (required before commits)
- `./tests/test_hooks.sh` - Validate hook behavior in isolation
- `claude plugin validate .` - Validate manifests before publishing
- `chmod +x hooks/*.sh skills/*/scripts/*.sh` - Fix script permissions

**Key files**:
- `@AGENTS.md` - Comprehensive development guidelines (single source of truth)
- `@hooks/README.md` - Hook security model and configuration
- `@ROOT_CAUSE_ANALYSIS.md` - Path resolution architecture fix (Nov 2025)
- `@REPETITION_ANALYSIS.md` - Code organization justification

## Session Context

When working on this plugin:
1. **Read @AGENTS.md first** - All guidelines, patterns, and conventions
2. **Path resolution** - Always use `COUNCIL_PLUGIN_ROOT` → `CLAUDE_PLUGIN_ROOT` → `CLAUDE_PROJECT_DIR` fallback
3. **Hooks** - Review @hooks/README.md when modifying security logic
4. **Manifests** - Keep `.claude-plugin/` synchronized with `docs/INSTALL.md`
5. **Testing** - Maintain coverage for orchestration, hooks, and commands
6. **Naming** - Command filenames match command names (`council.md` → `/council`)
