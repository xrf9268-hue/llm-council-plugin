#!/bin/bash
# LLM Council Plugin - SessionStart Hook
# Initializes environment variables for council operations
# Follows official Claude Code SessionStart hook best practices
set -euo pipefail

# Setup persistent environment variables for the session
setup_environment() {
  if [ -z "${CLAUDE_ENV_FILE:-}" ]; then
    echo "Warning: CLAUDE_ENV_FILE not available" >&2
    return 0
  fi

  # Persist council configuration
  echo "export COUNCIL_DIR=\"\${COUNCIL_DIR:-.council}\"" >> "$CLAUDE_ENV_FILE"
  echo "export COUNCIL_MAX_COMMAND_LENGTH=\"\${COUNCIL_MAX_COMMAND_LENGTH:-50000}\"" >> "$CLAUDE_ENV_FILE"
  echo "export COUNCIL_MAX_OUTPUT_LENGTH=\"\${COUNCIL_MAX_OUTPUT_LENGTH:-500000}\"" >> "$CLAUDE_ENV_FILE"

  # Prevent shell cwd reset messages
  echo "export CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR=1" >> "$CLAUDE_ENV_FILE"

  # Set plugin root for convenience
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    echo "export COUNCIL_PLUGIN_ROOT=\"${CLAUDE_PLUGIN_ROOT}\"" >> "$CLAUDE_ENV_FILE"
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

  # Report missing dependencies (non-blocking)
  if [ ${#missing_deps[@]} -gt 0 ]; then
    echo "Warning: Missing dependencies: ${missing_deps[*]}" >&2
    echo "Some council features may be limited" >&2
  fi
}

# Validate council scripts availability
validate_council_scripts() {
  local project_dir="${CLAUDE_PROJECT_DIR:-.}"
  local plugin_root="${CLAUDE_PLUGIN_ROOT:-}"

  # If running from installed plugin, validate scripts exist
  if [ -n "$plugin_root" ]; then
    local scripts_dir="${plugin_root}/skills/council-orchestrator/scripts"

    if [ ! -d "$scripts_dir" ]; then
      echo "Warning: Council scripts directory not found: $scripts_dir" >&2
      return 1
    fi

    # Check for critical scripts
    for script in council_utils.sh orchestrate.sh; do
      if [ ! -f "${scripts_dir}/${script}" ]; then
        echo "Warning: Missing council script: ${script}" >&2
      elif [ ! -x "${scripts_dir}/${script}" ]; then
        echo "Warning: Council script not executable: ${script}" >&2
      fi
    done
  fi

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
