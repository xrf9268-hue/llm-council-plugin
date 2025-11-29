---
description: Check the availability and readiness of all LLM Council components.
model: claude-haiku-4-5-20251001
---

# Council Status

Check the status and availability of LLM Council components.

## Implementation Instructions

When this command is invoked, use the **Bash tool** to run diagnostic checks and format the results for the user.

### Step 1: CLI Availability Check

Execute using Bash tool:
```bash
# Resolve path to council_utils.sh
if [[ -n "${COUNCIL_PLUGIN_ROOT:-}" ]]; then
    UTILS_PATH="${COUNCIL_PLUGIN_ROOT}/skills/council-orchestrator/scripts/council_utils.sh"
elif [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
    UTILS_PATH="${CLAUDE_PLUGIN_ROOT}/skills/council-orchestrator/scripts/council_utils.sh"
elif [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    UTILS_PATH="${CLAUDE_PROJECT_DIR}/skills/council-orchestrator/scripts/council_utils.sh"
else
    # Try standard installation locations
    for candidate in \
        "$HOME/.claude/plugins/cache/llm-council-plugin/skills/council-orchestrator/scripts/council_utils.sh" \
        "$HOME/.claude/plugins/llm-council-plugin/skills/council-orchestrator/scripts/council_utils.sh"; do
        if [[ -f "$candidate" ]]; then
            UTILS_PATH="$candidate"
            break
        fi
    done
fi

# Verify path exists
if [[ -z "${UTILS_PATH:-}" ]] || [[ ! -f "$UTILS_PATH" ]]; then
    echo "❌ Error: Cannot locate council utilities"
    echo "Please set COUNCIL_PLUGIN_ROOT to your plugin installation path."
    exit 1
fi

source "$UTILS_PATH"
get_cli_status
```

Parse the output to determine which council member CLIs are available.

Display the results in a formatted table:

| Member | CLI | Status | Version |
|--------|-----|--------|---------|
| Claude | `claude` | [✅ Available / ❌ Missing] | [version if available] |
| OpenAI Codex | `codex` | [✅ Available / ❌ Missing] | [version if available] |
| Google Gemini | `gemini` | [✅ Available / ❌ Missing] | [version if available] |

### Step 2: Version Information

For each available CLI, execute using Bash tool:
```bash
# Claude
claude --version 2>/dev/null || echo "Version unknown"

# Codex
codex --version 2>/dev/null || echo "Version unknown"

# Gemini
gemini --version 2>/dev/null || echo "Version unknown"
```

### Step 3: Configuration Status

Execute using Bash tool (reuse the same UTILS_PATH from Step 1):
```bash
source "$UTILS_PATH"
config_list
```

Display current configuration settings.

### Step 4: Quorum Assessment

Calculate and display quorum status based on:
- Available members count
- Minimum quorum setting from config
- Status: ✅ Ready / ⚠️ Not Ready

Present as:
- Total available members: X/3
- Quorum requirement: Y members
- Status: [✅ Met / ⚠️ Not Met]

### Step 4.5: Security Status

Execute using Bash tool:
```bash
# Check jq availability
if command -v jq &>/dev/null; then
    echo "✅ Hook Security: ENABLED (jq installed)"
    echo "   Version: $(jq --version 2>&1)"
else
    echo "⚠️  Hook Security: DISABLED (jq not installed)"
    echo "   Without jq, the following protections are disabled:"
    echo "     • Command injection detection"
    echo "     • Sensitive data leak detection"
    echo "     • Council quorum verification"
    echo "     • Command length limits"
    echo ""
    echo "   Install jq to enable security features:"
    echo "     macOS:          brew install jq"
    echo "     Ubuntu/Debian:  sudo apt-get install jq"
    echo "     Alpine:         apk add jq"
fi
```

Display jq status:
- ✅ ENABLED if jq is available
- ⚠️ DISABLED if jq is missing (with installation instructions)

### Step 5: Recent Session (if exists)

If `.council/` directory exists from a previous session:
- Show Stage 1 responses count
- Show Stage 2 reviews count
- Show if final report exists

## Output Format

Display results like this:

```
LLM Council Status
==================

CLI Availability:
  Claude    : [✅ Available / ❌ Missing]
  Codex     : [✅ Available / ❌ Missing]
  Gemini    : [✅ Available / ❌ Missing]

Council Readiness:
  Members   : X/3 available
  Quorum    : [✅ Ready / ⚠️ Not Ready] (minimum Y required)

Security Status:
  Hook Security: [✅ ENABLED / ⚠️ DISABLED]
  jq Version   : [version if available]
  [If disabled: Installation instructions]

Configuration:
  Config    : ~/.council/config
  Members   : claude,codex,gemini
  Timeout   : 120s

Previous Session:
  [Status of .council/ directory if exists]
```

## Installation Guidance

If any CLI is missing, provide installation instructions:

- **Claude**: Visit https://code.claude.com/docs/en/setup or run `npm install -g @anthropic-ai/claude-code`
- **Codex**: Run `npm install -g @openai/codex`
- **Gemini**: Run `npm install -g @google/gemini-cli`
