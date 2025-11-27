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
source ./skills/council-orchestrator/scripts/council_utils.sh
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

Execute using Bash tool:
```bash
source ./skills/council-orchestrator/scripts/council_utils.sh
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
