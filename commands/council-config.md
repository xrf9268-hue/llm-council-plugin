# /council-config

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

## Implementation

When this command is invoked:

### Show Configuration (default)

```bash
source ./skills/council-orchestrator/scripts/council_utils.sh
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

When user provides `set <key> <value>`:

```bash
source ./skills/council-orchestrator/scripts/council_utils.sh
config_set "<key>" "<value>"
```

### Reset Configuration

When user provides `reset`:

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
