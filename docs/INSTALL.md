# LLM Council Plugin - Installation & Debugging Guide

## Overview

This guide explains how to install the LLM Council plugin for Claude Code and how to debug it using Claude Code's marketplace and developer tools.

## Prerequisites

### Required Dependencies

Before installing or using the plugin, ensure these critical dependencies are available:

#### 1. jq - JSON Parser (CRITICAL for Security)

**⚠️ Without jq, all security validations are DISABLED**

The plugin's security hooks require `jq` for JSON parsing. Without it, the following protections are bypassed:
- Command injection detection
- Sensitive data leak detection (API keys, tokens)
- Council quorum verification
- Command length limits (50,000 chars)

**Installation**:
```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq

# Alpine
apk add jq

# Verify installation
jq --version
```

Expected output: `jq-1.5` or higher

#### 2. Claude Code

Claude Code must be installed and signed in (VS Code or JetBrains).

#### 3. Claude CLI

The Claude CLI is required for council deliberations.

**Installation**: See https://code.claude.com/docs/en/setup

**Verify**: `claude --version`

### Optional Dependencies (for Multi-Model Council)

For full three-model council functionality, install these optional CLIs:

- **codex** - OpenAI Codex CLI for additional perspective
  - Install: `npm install -g @openai/codex`

- **gemini** - Google Gemini CLI for additional perspective
  - Install: `npm install -g @google/gemini-cli`

**Note**: The plugin works with Claude CLI alone, but multi-model deliberation provides richer perspectives.

### Repository Access

- Public GitHub repository: `https://github.com/xrf9268-hue/llm-council-plugin.git`

## Installation

### Option A: Install via a marketplace (recommended)

Follow the official Claude Code docs for plugin marketplaces.

1. In Claude Code, open the **Marketplaces** section.
2. Add this repository as a marketplace:
   - **GitHub repository**: enter `xrf9268-hue/llm-council-plugin` (equivalent CLI command:  
     ```shell
     /plugin marketplace add xrf9268-hue/llm-council-plugin
     ```
   - **Git repository URL**: enter `https://github.com/xrf9268-hue/llm-council-plugin.git` (equivalent CLI command:  
     ```shell
     /plugin marketplace add https://github.com/xrf9268-hue/llm-council-plugin.git
     ```  
   ).
3. After the marketplace syncs, you should see a marketplace named `llm-council` containing a plugin `llm-council-plugin`. Install it from the UI or via:

```shell
/plugin install llm-council-plugin@llm-council
```

### Option B: Install from a local checkout

1. Clone this repository into your project or a standalone directory:

```bash
# Clone as a standalone plugin
git clone https://github.com/xrf9268-hue/llm-council-plugin.git

# Or add to your project's .claude-plugins directory
cd your-project
git clone https://github.com/xrf9268-hue/llm-council-plugin.git .claude-plugins/llm-council
```

2. Verify scripts are executable (they should already have permissions after cloning):

```bash
# Check permissions
ls -l hooks/*.sh skills/council-orchestrator/scripts/*.sh | head -5

# Only if scripts lack execute permissions (rare on Linux/Mac):
# chmod +x hooks/*.sh skills/council-orchestrator/scripts/*.sh
```

**Note**: Git preserves execute permissions on Linux/Mac by default. You only need to run `chmod +x` if:
- Developing on Windows with `core.fileMode=false`
- Downloaded as ZIP instead of using `git clone`
- Permissions were somehow lost

3. Reload Claude Code so it picks up the plugin.

## Verify Installation

### Check Dependencies (RECOMMENDED - Run First)

Before proceeding with plugin installation, verify all required dependencies are installed:

```bash
#!/bin/bash
# Dependency verification script

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  LLM Council Plugin - Dependency Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Track overall status
ALL_REQUIRED_PRESENT=true

# Check jq (CRITICAL for security)
echo "🔍 Checking Required Dependencies..."
echo ""
if command -v jq &>/dev/null; then
    JQ_VERSION=$(jq --version 2>&1)
    echo "✅ jq is installed: $JQ_VERSION"
    echo "   → Security validations: ENABLED"
else
    echo "❌ jq is NOT installed"
    echo "   → Security validations: DISABLED"
    echo "   → Command injection detection: OFF"
    echo "   → Sensitive data leak detection: OFF"
    echo "   → Council quorum verification: OFF"
    echo ""
    echo "   Install jq:"
    echo "     macOS:          brew install jq"
    echo "     Ubuntu/Debian:  sudo apt-get install jq"
    echo "     Alpine:         apk add jq"
    ALL_REQUIRED_PRESENT=false
fi

echo ""

# Check Claude CLI (REQUIRED)
if command -v claude &>/dev/null; then
    CLAUDE_VERSION=$(claude --version 2>&1 | head -n1)
    echo "✅ Claude CLI is installed: $CLAUDE_VERSION"
else
    echo "❌ Claude CLI is NOT installed"
    echo "   See: https://code.claude.com/docs/en/setup"
    ALL_REQUIRED_PRESENT=false
fi

echo ""
echo "🔍 Checking Optional Dependencies (for multi-model council)..."
echo ""

# Check optional CLIs
OPTIONAL_PRESENT=0

if command -v codex &>/dev/null; then
    echo "✅ Codex CLI is installed"
    OPTIONAL_PRESENT=$((OPTIONAL_PRESENT + 1))
else
    echo "ℹ️  Codex CLI is not installed (optional)"
    echo "   Install: npm install -g @openai/codex"
fi

echo ""

if command -v gemini &>/dev/null; then
    echo "✅ Gemini CLI is installed"
    OPTIONAL_PRESENT=$((OPTIONAL_PRESENT + 1))
else
    echo "ℹ️  Gemini CLI is not installed (optional)"
    echo "   Install: npm install -g @google/gemini-cli"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ "$ALL_REQUIRED_PRESENT" == true ]]; then
    echo "✅ All required dependencies are installed"
    echo "📊 Council Capability: $((OPTIONAL_PRESENT + 1)) models available"
    if [[ $OPTIONAL_PRESENT -eq 0 ]]; then
        echo "   → Single-model mode (Claude only)"
    elif [[ $OPTIONAL_PRESENT -eq 1 ]]; then
        echo "   → Two-model deliberation"
    else
        echo "   → Full three-model council"
    fi
else
    echo "❌ Missing required dependencies - install them before proceeding"
    exit 1
fi
```

**Run this script before installation to ensure all required dependencies are available.**

### Check CLI dependencies (Legacy Method)

From the repository root:

```bash
# Resolve path to council_utils.sh
PLUGIN_ROOT="${COUNCIL_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CLAUDE_PROJECT_DIR}}}"
source "${PLUGIN_ROOT}/skills/council-orchestrator/scripts/council_utils.sh" && get_cli_status
```

Confirm at least `claude` is reported as available.

### Check plugin commands

In Claude Code:

- Open the plugin list and verify **LLM Council** is installed and enabled.
- Start typing `/council` in the chat input. You should see both:
  - Unprefixed commands, e.g. `/council`, `/council-help`, `/council-status`, `/council-config`
  - Namespaced plugin commands, e.g. `/llm-council-plugin:council`, `/llm-council-plugin:council-help`, etc.

Per the official slash command docs, the namespaced form (`/plugin-name:command-name`) is optional unless there are name collisions. For normal use you can just type the unprefixed versions.

### Run the `/council` command

In a Claude Code chat, run either of the following (they are equivalent):

```text
/council "test query from Claude Code"
```

or

```text
/llm-council-plugin:council "test query from Claude Code"
```

Expect:

- No "Unknown command" errors.
- A response generated by the LLM Council flow.

### Check skill and output files

After running a test `/council` invocation, check from the repo root:

```bash
ls .council
cat .council/stage1_claude.txt
```

You should see:

- `.council/` directory present.
- `stage1_claude.txt` non-empty, containing the answer to your test query.

Each new `/council` run will reset the `.council/` directory for the new session, so files from previous sessions will not contaminate the current run. When you no longer need any session files, you can delete the working directory with the `/council-cleanup` command.

## Debugging & Logs

### Use Claude Code debugging tools

1. Open the **plugin developer tools** / debugging view in Claude Code (see the official docs on "Debugging and development tools").
2. Select the **LLM Council** plugin.
3. Enable verbose or trace logging if available.

Then:

- Run `/council "debug test"` in a chat.
- In the debug view, confirm the call chain:
  - `/council` command is parsed.
  - `council-orchestrator` skill is invoked.
  - Skill scripts (`council_utils.sh`, `query_claude.sh`, `run_parallel.sh`, etc.) are executed without fatal errors.

### Debug scripts directly in the terminal

If you suspect CLI or bash issues, run scripts from the repo root:

```bash
# Resolve plugin root
PLUGIN_ROOT="${COUNCIL_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CLAUDE_PROJECT_DIR}}}"

# Single-model: Claude only
"${PLUGIN_ROOT}/skills/council-orchestrator/scripts/query_claude.sh" "terminal test"

# Stage 1: parallel opinion collection
"${PLUGIN_ROOT}/skills/council-orchestrator/scripts/run_parallel.sh" "terminal test"

# Stage 2: peer review
"${PLUGIN_ROOT}/skills/council-orchestrator/scripts/run_peer_review.sh" "terminal test" .council

# Stage 3: chairman synthesis prompt
"${PLUGIN_ROOT}/skills/council-orchestrator/scripts/run_chairman.sh" "terminal test" .council
```

Once these work reliably in the terminal, they should also work when invoked through `/council` inside Claude Code.

## Common Issues & Tips

### ⚠️ Hooks Blocking Shell Operators (FIXED)

**If you see errors like:** `"BLOCKED: Detected potentially dangerous pattern: &&"`

This indicates your **cached plugin is outdated**. The hook validation logic was fixed in commit `78ac404`.

**Quick fix:**
```bash
# Run the diagnostic script
./scripts/verify-plugin-version.sh

# Or manually clear cache and reinstall
rm -rf ~/.claude/plugins/cache/llm-council-plugin
claude plugin install llm-council-plugin@llm-council
```

**For comprehensive troubleshooting guidance, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).**

---

### Duplicate hooks file detected

If `/doctor` shows `"Duplicate hooks file detected: ./hooks/hooks.json ..."`, your manifest is pointing to the standard hooks file. Claude Code v2.0.73+ auto-loads `hooks/hooks.json`.

**Fix:**
- Remove `"hooks": "./hooks/hooks.json"` from `.claude-plugin/plugin.json`, or
- Point `hooks` at a separate file (e.g. `./hooks/extra-hooks.json`) if you need additional hooks.

Restart Claude Code after changing the manifest.

### Other Common Issues

- **`/council` missing from autocomplete**:
  - Check that the plugin is installed and enabled in Claude Code.
  - Use the plugin debug tools to confirm `plugin.json` loaded without errors.

- **`/council` errors or no response**:
  - First, test `query_claude.sh` and `run_parallel.sh` directly in the terminal.
  - Confirm `.council/` and `stage1_claude.txt` are created after a run.

- **Marketplace cannot find LLM Council**:
  - Ensure you added the GitHub repository `xrf9268-hue/llm-council-plugin` as a marketplace (for example:
    ```shell
    /plugin marketplace add xrf9268-hue/llm-council-plugin
    ```).
  - Confirm the repo is public and contains `.claude-plugin/marketplace.json`.
  - Trigger a marketplace refresh in Claude Code and search again; you should see a marketplace `llm-council` with a plugin `llm-council-plugin`.
