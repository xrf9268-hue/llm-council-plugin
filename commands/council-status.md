# /council-status

Check the status and availability of LLM Council components.

## Implementation

When this command is invoked, run the following diagnostic checks:

### 1. CLI Availability Check

Run the council utilities to check CLI availability:

```bash
source ./skills/council-orchestrator/scripts/council_utils.sh
get_cli_status
```

Display the results in a formatted table:

| Member | CLI | Status | Version |
|--------|-----|--------|---------|
| Claude | `claude` | [check] | [version if available] |
| OpenAI Codex | `codex` | [check] | [version if available] |
| Google Gemini | `gemini` | [check] | [version if available] |

### 2. Version Information

For each available CLI, attempt to get version information:

```bash
# Claude
claude --version 2>/dev/null || echo "Version unknown"

# Codex
codex --version 2>/dev/null || echo "Version unknown"

# Gemini
gemini --version 2>/dev/null || echo "Version unknown"
```

### 3. Configuration Status

Display current configuration using:

```bash
source ./skills/council-orchestrator/scripts/council_utils.sh
config_list
```

### 4. Quorum Assessment

Calculate and display quorum status:
- Total available members: X/3
- Quorum requirement: Y members
- Status: [Met/Not Met]

### 5. Recent Session (if exists)

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
  Claude    : [Available/Missing]
  Codex     : [Available/Missing]
  Gemini    : [Available/Missing]

Council Readiness:
  Members   : X/3 available
  Quorum    : [Ready/Not Ready] (minimum Y required)

Configuration:
  Config    : ~/.council/config
  Members   : claude,codex,gemini
  Timeout   : 120s

Previous Session:
  [Status of .council/ directory if exists]
```

## Installation Guidance

If any CLI is missing, provide installation instructions:

- **Claude**: Visit https://claude.ai/code or run `npm install -g @anthropic-ai/claude-code`
- **Codex**: Run `npm install -g @openai/codex`
- **Gemini**: Run `npm install -g @google/gemini-cli`
