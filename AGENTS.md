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

### Official References

When changing `.claude-plugin/*` manifests or installation flows, validate against these official schemas:

- [Plugin Manifest Reference](https://code.claude.com/docs/en/plugins-reference.md) - Official plugin.json schema
- [Marketplace Schema](https://code.claude.com/docs/en/marketplace.md) - Official marketplace.json schema
- [Plugin Development Guide](https://code.claude.com/docs/en/plugins.md) - Plugin development best practices

## Slash Commands

- Slash command files live in `commands/` and follow the official rule `/<command-name>` where `<command-name>` is derived from the Markdown filename (without `.md`), e.g. `council.md` → `/llm-council-plugin:council`.
- You can still present a shorter user-facing form like `/council` in the command body, but the namespaced form (`/plugin-name:<command-name>`) always comes from the filename, so choose filenames accordingly.
- When a command accepts arguments, add an `argument-hint` in the frontmatter that matches how users invoke it (e.g. `<question>` or `[set <key> <value> | reset]`) and explicitly wire that into the prompt using `$ARGUMENTS` (all args) or `$1`, `$2`, `$3`, etc. for structured subcommands.

### Command Execution Model

Our slash commands use the **instructional approach**:
- Commands provide implementation guidance for Claude through clear "Implementation Instructions" sections
- Claude intelligently uses its tools (Bash, Skill, etc.) to execute the instructions
- This allows for flexible error handling, context-aware execution, and intelligent decision-making

**Do NOT use**:
- Direct bash execution with `!bash` prefix (unless command is trivial and fixed)
- `allowed-tools` frontmatter (only needed for direct `!bash` execution)

**DO use**:
- Clear "Implementation Instructions" sections that explicitly state "Use the **Bash tool**" or "Use the **Skill tool**"
- Appropriate 2025 model selection in frontmatter
- Structured argument handling with `$ARGUMENTS` or positional parameters (`$1`, `$2`, `$3`)

### Model Selection Guidelines (2025)

All commands should specify appropriate models in frontmatter based on complexity:

| Model | Model ID | Use Case | Examples |
|-------|----------|----------|----------|
| **Sonnet 4.5** | `claude-sonnet-4-5-20250929` | Complex orchestration, multi-step workflows, advanced reasoning | `/council` (multi-model coordination) |
| **Haiku 4.5** | `claude-haiku-4-5-20251001` | Simple commands, configuration, status checks, help docs | `/council-config`, `/council-status`, `/council-help` |
| **Omit** | - | Inherit from user settings (good default for flexibility) | Commands that should adapt to user preference |

**Rationale**:
- **Sonnet 4.5** provides the strongest reasoning for complex tasks requiring coordination, synthesis, and multi-step logic
- **Haiku 4.5** offers fast, economical performance for straightforward operations like displaying config, running status checks, or showing help
- Omitting `model` allows commands to inherit from the user's session settings, providing maximum flexibility

### Argument Handling Best Practices

- **Use `$ARGUMENTS`** when the command takes a single conceptual input (e.g., a question, a query string)
  ```markdown
  argument-hint: "<question>"
  # In prompt: "Treat `$ARGUMENTS` as the user's complete question"
  ```

- **Use positional parameters** (`$1`, `$2`, `$3`) when the command has structured subcommands or multiple distinct arguments
  ```markdown
  argument-hint: "[set <key> <value> | reset]"
  # In prompt: "When `$1` is 'set', use `$2` as key and `$3` as value"
  ```

- Always include `argument-hint` in frontmatter to guide auto-completion and user expectations

## Skills Best Practices (2025)

Following the official Claude Code skills documentation, our skills adhere to these best practices:

### Frontmatter Schema Compliance

**Only use official fields** in SKILL.md frontmatter:
- `name`: lowercase-with-hyphens (max 64 characters)
- `description`: what it does + when to use it (max 1024 characters)
- `allowed-tools`: optional tool restrictions (e.g., `[Bash, Read, Write]`)

**Do NOT add** unofficial fields like `license`, `version`, `author` in skill frontmatter. Store metadata in a separate `METADATA.md` file within the skill directory.

### Discovery-Optimized Descriptions

Descriptions should include **trigger terms** to help Claude recognize when to activate the skill:

**Good Example:**
```yaml
description: Orchestrates multi-model LLM consensus through a three-phase deliberation protocol. Use when you need collaborative AI review, multi-model problem-solving, code review from multiple perspectives, or consensus-based decision making.
```

**Key elements:**
- What the skill accomplishes (technical summary)
- **Explicit activation phrase**: "Use when you need..."
- **Trigger terms**: "collaborative AI review", "multi-model problem-solving", "consensus-based decision making"
- Workflow mention: "three-phase deliberation protocol"

### Progressive Disclosure Pattern

For complex skills, split documentation into multiple files to reduce context consumption:

```
skills/skill-name/
├── SKILL.md           # Core workflow (~150 lines, Level 2 - always loaded)
├── REFERENCE.md       # Detailed implementation (Level 3 - on-demand)
├── EXAMPLES.md        # Usage scenarios (Level 3 - on-demand)
├── SECURITY.md        # Security guidelines (Level 3 - on-demand)
├── METADATA.md        # Version/license info (Level 3 - on-demand)
├── scripts/           # Executable utilities (Level 3 - executed, not loaded)
└── templates/         # Reusable templates (Level 3 - loaded when referenced)
```

**Loading Levels:**
- **Level 1**: Metadata from frontmatter (~100 tokens) - always in system prompt
- **Level 2**: SKILL.md content - loaded when skill is activated
- **Level 3**: Additional files - loaded only when explicitly referenced

**Benefits:**
- Reduces Level 2 context by 60-70%
- Faster skill activation
- Better maintainability
- On-demand detailed docs

### Security for External Tool Execution

When skills execute external tools (CLIs, APIs), document security considerations:

1. **Input Validation**: Add `validate_user_input()` functions
2. **SECURITY.md**: Create dedicated security documentation
3. **Reference in SKILL.md**: Link to security docs from main skill file
4. **Sanitization Patterns**: Document safe quoting and escaping

Example pattern:
```bash
# In SKILL.md
validate_user_input "$query" || exit 1
```

### Template Extraction

Extract reusable prompts to `templates/` directory:

```
templates/
├── review_prompt.txt      # Peer review template
└── synthesis_prompt.txt   # Output formatting template
```

Use variable substitution:
```bash
PROMPT=$(cat templates/review_prompt.txt)
PROMPT="${PROMPT//\{\{QUESTION\}\}/$user_question}"
```

### Validation Before Publishing

Before committing skill changes:

```bash
# Validate plugin manifest
claude plugin validate .

# Run test suite
./tests/test_runner.sh

# Verify file structure
ls skills/skill-name/
```

### council-orchestrator Example

Our `council-orchestrator` skill demonstrates all these best practices:
- ✓ Schema-compliant frontmatter (no extra fields)
- ✓ Discovery-optimized description with trigger terms
- ✓ Progressive disclosure (SKILL.md + REFERENCE.md + EXAMPLES.md)
- ✓ Security documentation (SECURITY.md)
- ✓ Template extraction (templates/)
- ✓ Input validation (validate_user_input function)

## Hooks Best Practices (2025)

Following the official Claude Code hooks documentation, our hooks adhere to these best practices:

### Structured JSON Output

All hooks must use structured JSON output per the official Claude Code hooks API:

**PreToolUse hooks** (validation before execution):
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow|deny|ask",
    "permissionDecisionReason": "explanation if denied/ask",
    "updatedInput": null
  },
  "continue": true,
  "systemMessage": "user-facing message"
}
```

**PostToolUse hooks** (analysis after execution):
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "context for Claude to consider"
  },
  "continue": true,
  "systemMessage": "user-facing warning/info"
}
```

**SessionStart hooks** (session initialization):
```json
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "setup context for Claude"
  },
  "continue": true,
  "systemMessage": "user-facing warning/info"
}
```

**IMPORTANT**: The `hookSpecificOutput` wrapper is required by the official Claude Code hooks API. Hooks using the older simplified format (without `hookSpecificOutput`) will not work correctly and may cause "BLOCKED" errors even for legitimate operations.

### Exit Code Conventions

- **SessionStart**: Exit 0 (always succeeds, cannot block session initialization)
- **PreToolUse**: Exit 0 with JSON (allow), Exit 2 (block with error message)
- **PostToolUse**: Exit 0 with JSON (continue with context), non-zero for logging only (non-blocking)

### Security Model

Our hooks implement **defense in depth** with these principles:

1. **Allow by Default** - Focus on actual security threats, not style or legitimate shell operations
2. **Fail Open** - Missing dependencies (like `jq`) don't block operations; hooks gracefully degrade
3. **Structured Communication** - Use official JSON schema for Claude integration, not plain text
4. **Validation Over Blocking** - PreToolUse validates inputs; PostToolUse provides intelligent context

### Hook Types and Responsibilities

**SessionStart (`session-start.sh`)** - Initializes environment at session start:
- Environment variable persistence via `CLAUDE_ENV_FILE` (**exclusive to SessionStart**)
- Sets `CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR=1` to prevent "Shell cwd was reset" messages
- Council configuration defaults (COUNCIL_DIR, max lengths, etc.)
- Dependency validation (bash, jq) - non-blocking warnings
- Council script availability checks - non-blocking warnings
- Runs once per session (on startup, resume, clear, compact)

**PreToolUse (`pre-tool.sh`)** - Validates commands before execution:
- Command length validation (configurable via `COUNCIL_MAX_COMMAND_LENGTH`, default: 50000)
- Injection pattern detection (warnings only, not blocking legitimate shell syntax)
- Council script path validation (blocking if scripts missing)
- System path protection warnings (informational)

**PostToolUse (`post-tool.sh`)** - Analyzes outputs after execution:
- Rate limit detection with retry guidance
- Authentication error detection with credential check guidance
- Output size monitoring and truncation suggestions
- Council quorum verification (minimum 2 models)
- Sensitive data leak detection (API keys, tokens)

All PostToolUse checks are **informational and non-blocking**.

### Environment Variables

Hooks use these environment variables for configuration:

**Provided by Claude Code:**
- `CLAUDE_PROJECT_DIR` - Project root path (always use for resolving relative paths)
- `CLAUDE_PLUGIN_ROOT` - Plugin installation path
- `CLAUDE_ENV_FILE` - File path to persist environment variables (**SessionStart hooks only**)

**Plugin-specific (configurable):**
- `COUNCIL_DIR` - Council session directory (default: `.council`)
- `COUNCIL_MAX_COMMAND_LENGTH` - PreToolUse max command size (default: 50000)
- `COUNCIL_MAX_OUTPUT_LENGTH` - PostToolUse output warning threshold (default: 500000)
- `CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR` - Set to `1` by SessionStart to prevent "Shell cwd was reset" messages

### Hook Development Guidelines

**When to use hooks:**
- **SessionStart**: Environment setup, dependency validation, persistent configuration
- **PreToolUse**: Input validation before potentially dangerous operations, security threat detection
- **PostToolUse**: Post-execution analysis and intelligent context provision, operational monitoring

**What hooks should NOT do:**
- ❌ Block legitimate shell operations (pipes, redirects, command chaining are required)
- ❌ Enforce style guidelines or code formatting
- ❌ Replace proper authentication and secrets management
- ❌ Make network calls or expensive computations (respect timeout limits)

### Testing and Validation

Hooks are tested as part of the plugin test suite:

```bash
# Run all tests including hooks
./tests/test_runner.sh

# Test hooks in isolation
./tests/test_hooks.sh

# Manual testing examples in hooks/README.md
```

**Test coverage requirements:**
- Integration tests (executable, config validation)
- SessionStart tests (environment persistence, JSON schema, dependency handling)
- PreToolUse tests (command length, validation, blocking behavior)
- PostToolUse tests (detection patterns, JSON structure, context provision)
- Edge cases (missing jq, timeouts, malformed input, missing CLAUDE_ENV_FILE)

### Configuration and Troubleshooting

See `hooks/README.md` for comprehensive documentation including:
- Detailed hook behavior and JSON schemas
- Security model and design principles
- Configuration via environment variables
- Manual testing procedures
- Troubleshooting common issues (hook not running, jq unavailable, timeouts, false positives)

### Common Pitfalls and Lessons Learned

**Issue: Hooks block legitimate shell operators (&&, ||, |, etc.)**

**Symptoms:**
- Commands with `&&`, `||`, or `|` are blocked by PreToolUse hook
- Error messages like "BLOCKED: Detected potentially dangerous pattern: &&"
- Council orchestrator commands fail with hook validation errors

**Root Cause:**
Using incorrect JSON schema format. The official Claude Code hooks API requires the `hookSpecificOutput` wrapper. Hooks using the simplified format without this wrapper may be misinterpreted by Claude Code, causing legitimate operations to be blocked.

**Solution:**
1. ✅ **Always use official JSON schema** with `hookSpecificOutput` wrapper
2. ✅ **Never block legitimate shell operators** - `&&`, `||`, `|`, `;`, `>`, `<` are fundamental shell features
3. ✅ **Use `CLAUDE_PROJECT_DIR`** for all path resolution in hooks
4. ✅ **Query official documentation** when implementing hooks - don't rely on examples alone

**Prevention:**
- Validate hooks against official schema: https://code.claude.com/docs/en/hooks-guide.md
- Test hooks with legitimate complex commands (pipes, redirects, chaining)
- Review hook output format matches official examples exactly
- When debugging hook issues, always check official docs first

**Key Takeaway:**
Hook schema compliance is critical. Even minor deviations from the official format can cause unexpected blocking behavior. Always validate against official Claude Code documentation rather than relying on third-party examples or documentation.

### References

- [Claude Code Hooks Guide](https://code.claude.com/docs/en/hooks-guide.md) - Official best practices
- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks.md) - API reference
- [Local hooks documentation](../hooks/README.md) - Plugin-specific implementation details

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
