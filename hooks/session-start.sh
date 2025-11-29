#!/bin/bash
# LLM Council Plugin - SessionStart Hook
# Initializes environment variables for council operations
# Follows official Claude Code SessionStart hook best practices
set -euo pipefail

# Discover plugin installation path dynamically
# This is critical for environments where CLAUDE_PLUGIN_ROOT is not set
discover_plugin_root() {
  local plugin_root=""

  # Method 1: Use CLAUDE_PLUGIN_ROOT if available (standard case)
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    plugin_root="$CLAUDE_PLUGIN_ROOT"
    echo "Debug: Using CLAUDE_PLUGIN_ROOT=$plugin_root" >&2
    echo "$plugin_root"
    return 0
  fi

  # Method 2: Derive from this script's location
  # This hook is at: <plugin_root>/hooks/session-start.sh
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local candidate="${script_dir%/hooks}"

  # Verify this is the plugin root by checking for signature files
  if [ -f "${candidate}/.claude-plugin/plugin.json" ] && \
     [ -d "${candidate}/skills/council-orchestrator" ]; then
    plugin_root="$candidate"
    echo "Debug: Discovered plugin root from script location: $plugin_root" >&2
    echo "$plugin_root"
    return 0
  fi

  # Method 3: Check standard Claude Code plugin cache locations
  local home="${HOME:-}"
  if [ -n "$home" ]; then
    for candidate_dir in \
      "$home/.claude/plugins/cache/llm-council-plugin" \
      "$home/.claude/plugins/llm-council-plugin" \
      "$home/.config/claude/plugins/llm-council-plugin"; do
      if [ -f "${candidate_dir}/.claude-plugin/plugin.json" ] && \
         [ -d "${candidate_dir}/skills/council-orchestrator" ]; then
        plugin_root="$candidate_dir"
        echo "Debug: Found plugin in standard location: $plugin_root" >&2
        echo "$plugin_root"
        return 0
      fi
    done
  fi

  # Method 4: Fall back to CLAUDE_PROJECT_DIR for local development
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && \
     [ -f "${CLAUDE_PROJECT_DIR}/.claude-plugin/plugin.json" ]; then
    plugin_root="$CLAUDE_PROJECT_DIR"
    echo "Debug: Using CLAUDE_PROJECT_DIR for local dev: $plugin_root" >&2
    echo "$plugin_root"
    return 0
  fi

  echo "Error: Could not discover plugin installation path" >&2
  return 1
}

# Setup persistent environment variables for the session
setup_environment() {
  if [ -z "${CLAUDE_ENV_FILE:-}" ]; then
    echo "Warning: CLAUDE_ENV_FILE not available - environment variables will not persist" >&2
    return 0
  fi

  # Persist council configuration
  echo "export COUNCIL_DIR=\"\${COUNCIL_DIR:-.council}\"" >> "$CLAUDE_ENV_FILE"
  echo "export COUNCIL_MAX_COMMAND_LENGTH=\"\${COUNCIL_MAX_COMMAND_LENGTH:-50000}\"" >> "$CLAUDE_ENV_FILE"
  echo "export COUNCIL_MAX_OUTPUT_LENGTH=\"\${COUNCIL_MAX_OUTPUT_LENGTH:-500000}\"" >> "$CLAUDE_ENV_FILE"

  # Prevent shell cwd reset messages
  echo "export CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR=1" >> "$CLAUDE_ENV_FILE"

  # Discover and set plugin root (critical for path resolution)
  local discovered_root
  if discovered_root=$(discover_plugin_root); then
    echo "export COUNCIL_PLUGIN_ROOT=\"${discovered_root}\"" >> "$CLAUDE_ENV_FILE"
    echo "Debug: COUNCIL_PLUGIN_ROOT set to: $discovered_root" >&2
  else
    echo "Warning: Could not set COUNCIL_PLUGIN_ROOT - path resolution may fail" >&2
    echo "Warning: You may need to manually set: export COUNCIL_PLUGIN_ROOT=/path/to/plugin" >&2
  fi
}

# Validate council dependencies
validate_dependencies() {
  local missing_deps=()

  # Check for required CLI tools
  for cmd in bash jq; do
    if ! command -v "$cmd" &> /dev/null; then
      missing_deps+=("$cmd")
    fi
  done

  # Report missing dependencies with enhanced security context
  if [ ${#missing_deps[@]} -gt 0 ]; then
    # Check if jq specifically is missing (critical security dependency)
    local jq_missing=false
    for dep in "${missing_deps[@]}"; do
      if [[ "$dep" == "jq" ]]; then
        jq_missing=true
        break
      fi
    done

    if [[ "$jq_missing" == true ]]; then
      # Critical security warning for missing jq
      cat >&2 <<'EOF'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️  SECURITY WARNING: Critical Dependency Missing
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Missing: jq (JSON parser)

Without jq, these security features are DISABLED:
  ❌ Command injection detection
  ❌ Sensitive data leak detection (API keys, tokens)
  ❌ Council quorum verification
  ❌ Command length limits (50,000 chars)
  ❌ System path protection warnings

🔧 Install jq to enable full security:
  macOS:          brew install jq
  Ubuntu/Debian:  sudo apt-get install jq
  Alpine:         apk add jq
  Verify:         jq --version

📚 More info: https://github.com/xrf9268-hue/llm-council-plugin#prerequisites

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
    else
      # Standard warning for other dependencies
      echo "Warning: Missing dependencies: ${missing_deps[*]}" >&2
      echo "Some features may be limited" >&2
    fi
  fi
}

# Validate council scripts availability
validate_council_scripts() {
  local project_dir="${CLAUDE_PROJECT_DIR:-.}"
  local plugin_root="${CLAUDE_PLUGIN_ROOT:-}"

  # Enhanced diagnostic output
  if [ -z "$plugin_root" ]; then
    echo "Debug: CLAUDE_PLUGIN_ROOT not set (local development mode?)" >&2
    echo "Debug: CLAUDE_PROJECT_DIR=${project_dir}" >&2
    return 0  # Non-blocking in local dev
  fi

  # If running from installed plugin, validate scripts exist
  local scripts_dir="${plugin_root}/skills/council-orchestrator/scripts"

  if [ ! -d "$scripts_dir" ]; then
    echo "Warning: Council scripts directory not found: $scripts_dir" >&2
    echo "Debug: CLAUDE_PLUGIN_ROOT=$plugin_root" >&2
    return 1
  fi

  # Check for critical scripts
  for script in council_utils.sh run_parallel.sh; do
    if [ ! -f "${scripts_dir}/${script}" ]; then
      echo "Warning: Missing council script: ${script}" >&2
    elif [ ! -x "${scripts_dir}/${script}" ]; then
      echo "Warning: Council script not executable: ${script}" >&2
    fi
  done

  return 0
}

# Main hook execution
main() {
  local hook_input
  local session_source

  # Read hook input from stdin (optional for SessionStart)
  if [ -t 0 ]; then
    # Running interactively (testing mode)
    session_source="test"
  else
    # Parse session start source if available
    hook_input=$(cat)
    session_source=$(echo "$hook_input" | jq -r '.source // "unknown"' 2>/dev/null || echo "unknown")
  fi

  # Perform validation
  validate_dependencies
  validate_council_scripts

  # Setup environment variables
  setup_environment

  # Output structured JSON response per official schema
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "LLM Council Plugin environment initialized for $session_source session. Environment variables configured: COUNCIL_DIR, COUNCIL_MAX_COMMAND_LENGTH, COUNCIL_MAX_OUTPUT_LENGTH, CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR."
  }
}
EOF

  exit 0
}

main
