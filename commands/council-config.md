---
description: View and manage LLM Council configuration settings.
argument-hint: "[set <key> <value> | reset]"
model: claude-haiku-4-5-20251001
---

# Council Config

View and manage LLM Council configuration settings.

## Usage

```
/council-config                     # Show current configuration
/council-config set <key> <value>   # Set a configuration value
/council-config reset               # Reset to default configuration
```

## Configuration Keys

| Key | Default | Description |
|-----|---------|-------------|
| `enabled_members` | `claude,codex,gemini` | Comma-separated list of enabled council members |
| `min_quorum` | `2` | Minimum members required for peer review |
| `max_prompt_length` | `10000` | Maximum characters allowed in prompts |
| `timeout` | `120` | Timeout in seconds for CLI operations |

## Implementation Instructions

When this command is invoked, use the **Bash tool** to execute the appropriate commands based on arguments:

### Show Configuration (no arguments)

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
config_list
```

Display the configuration in a readable format:

```
Council Configuration
=====================

Configuration file: ~/.council/config

Current Settings:
  enabled_members   : claude,codex,gemini
  min_quorum        : 2
  max_prompt_length : 10000
  timeout           : 120

To modify settings, use:
  /council-config set <key> <value>
```

### Set Configuration Value

When user provides `set <key> <value>`, interpret the arguments as:
- `$1` – subcommand (`set`)
- `$2` – configuration key
- `$3` – configuration value

Execute using Bash tool (reuse the same UTILS_PATH resolution from "Show Configuration"):
```bash
source "$UTILS_PATH"
config_set "$2" "$3"
```

Confirm the change to the user with a success message.

### Reset Configuration

When user provides `reset`:

Execute using Bash tool:
```bash
rm -f ~/.council/config
echo "Configuration reset to defaults."
```

## Examples

### Enable Only Claude and Gemini

```
/council-config set enabled_members claude,gemini
```

### Increase Timeout for Slow Networks

```
/council-config set timeout 180
```

### Require Full Quorum

```
/council-config set min_quorum 3
```

### View Current Settings

```
/council-config
```

## Configuration File Location

Configuration is stored in: `~/.council/config`

The file uses simple key=value format:
```
enabled_members=claude,codex,gemini
min_quorum=2
timeout=120
```

## Notes

- Changes take effect immediately for new council sessions
- Running sessions are not affected by configuration changes
- Use `/council-status` to verify configuration after changes
