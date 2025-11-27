#!/bin/bash
#
# pre-tool.sh - PreToolUse hook for LLM Council plugin
#
# This hook validates inputs before tool execution to ensure security.
# It focuses on detecting actual security threats rather than blocking
# legitimate shell operations.
#
# Called by Claude Code before Bash tool execution.
# Receives tool context via stdin as JSON.
#
# Exit codes:
#   0 - Allow tool execution with structured JSON response
#   2 - Block tool execution (stderr shown to Claude)
#
# Output: Official Claude Code PreToolUse JSON schema (exit 0):
#   {
#     "hookSpecificOutput": {
#       "hookEventName": "PreToolUse",
#       "permissionDecision": "allow" | "deny" | "ask",
#       "permissionDecisionReason": "explanation text",
#       "updatedInput": null
#     },
#     "continue": true,
#     "systemMessage": "warning/info message for user"
#   }

set -euo pipefail

# Configuration
MAX_COMMAND_LENGTH="${COUNCIL_MAX_COMMAND_LENGTH:-50000}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
COUNCIL_DIR="${COUNCIL_DIR:-.council}"

# Read input from stdin (JSON format from Claude Code)
INPUT=$(cat)

# Extract tool info from JSON (requires jq)
TOOL_NAME=""
TOOL_INPUT=""
COMMAND=""

if command -v jq &>/dev/null; then
    TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
    TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input.command // .tool_input // empty' 2>/dev/null || echo "")
    COMMAND="$TOOL_INPUT"
else
    # Fallback: allow by default if jq unavailable (fail open)
    cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "jq not available, validation skipped",
    "updatedInput": null
  },
  "continue": true,
  "systemMessage": "Warning: jq not available, hook validation skipped"
}
EOF
    exit 0
fi

# Function to check command length
check_command_length() {
    local text="$1"
    local length=${#text}

    if [[ $length -gt $MAX_COMMAND_LENGTH ]]; then
        return 1
    fi

    return 0
}

# Function to detect obvious obfuscation attempts (informational only)
# Note: Does NOT check for legitimate shell operators (&&, ||, |, ;, etc.)
detect_obfuscation() {
    local command="$1"

    # Only detect clear obfuscation patterns, not legitimate shell syntax
    if echo "$command" | grep -qE '(\$\{IFS\}|\\x[0-9a-f]{2}|\\\[0-7]{3})'; then
        return 1  # Obfuscation detected
    fi

    return 0  # No obfuscation
}

# Function to check for operations on sensitive system paths (informational only)
check_system_path_operations() {
    local command="$1"

    # Critical system paths that should trigger warnings
    local critical_paths=(
        '/etc/passwd'
        '/etc/shadow'
        '/etc/sudoers'
        '~/.ssh/id_rsa'
        '~/.ssh/id_ed25519'
    )

    for path in "${critical_paths[@]}"; do
        if [[ "$command" == *"$path"* ]]; then
            # Check if it's a destructive operation
            if echo "$command" | grep -qE "(rm|mv|>|>>|dd|truncate)" && echo "$command" | grep -qF "$path"; then
                return 1  # Warning condition detected
            fi
        fi
    done

    return 0  # No warnings
}

# Function to validate council-specific operations (blocking if scripts missing)
validate_council_operation() {
    local command="$1"

    # Only validate if this command references council orchestrator scripts
    if [[ "$command" != *"council-orchestrator/scripts"* ]]; then
        return 0  # Not a council operation, skip validation
    fi

    # Extract script path - match both absolute and relative forms
    local script_pattern='(/?skills/council-orchestrator/scripts/[a-z_]+\.sh)'

    if ! echo "$command" | grep -qE "$script_pattern"; then
        return 0  # No script path found, allow
    fi

    local script_path
    script_path=$(echo "$command" | grep -oE "$script_pattern" | head -n1)

    # Remove leading slash if present
    script_path="${script_path#/}"

    # Build absolute path using CLAUDE_PROJECT_DIR
    local abs_path="${PROJECT_DIR}/${script_path}"

    # Check if script exists at absolute path
    if [[ ! -f "$abs_path" ]]; then
        echo "Council script not found at: $abs_path" >&2
        echo "Ensure council-orchestrator skill is properly installed." >&2
        return 1  # Blocking error
    fi

    # Check if script is executable
    if [[ ! -x "$abs_path" ]]; then
        echo "Council script not executable: $abs_path" >&2
        echo "Run: chmod +x $abs_path" >&2
        return 1  # Blocking error
    fi

    return 0  # Validation passed
}

# Function to build JSON response using official Claude Code PreToolUse schema
build_json_response() {
    local decision="$1"
    local reason="$2"
    local system_message="$3"

    jq -n \
        --arg decision "$decision" \
        --arg reason "$reason" \
        --arg message "$system_message" \
        '{
            hookSpecificOutput: {
                hookEventName: "PreToolUse",
                permissionDecision: $decision,
                permissionDecisionReason: $reason,
                updatedInput: null
            },
            continue: true,
            systemMessage: (if $message != "" then $message else null end)
        }'
}

# Main validation logic
main() {
    # Only validate Bash tool calls
    if [[ "$TOOL_NAME" != "Bash" && "$TOOL_NAME" != "bash" ]]; then
        build_json_response "allow" "" ""
        exit 0
    fi

    # Skip if no command to validate
    if [[ -z "$COMMAND" ]]; then
        build_json_response "allow" "" ""
        exit 0
    fi

    # BLOCKING CHECK 1: Command length (hard limit)
    if ! check_command_length "$COMMAND"; then
        local length=${#COMMAND}
        echo "Command exceeds maximum length: $length chars (max: $MAX_COMMAND_LENGTH)" >&2
        exit 2  # Block with error
    fi

    # BLOCKING CHECK 2: Validate council-specific operations
    if ! validate_council_operation "$COMMAND"; then
        # Error messages already sent to stderr by validate_council_operation
        exit 2  # Block with error
    fi

    # NON-BLOCKING CHECK 3: Obfuscation detection (warning only)
    local warning_message=""
    if ! detect_obfuscation "$COMMAND"; then
        warning_message="⚠️  Potential command obfuscation detected"
    fi

    # NON-BLOCKING CHECK 4: System path operations (warning only)
    if ! check_system_path_operations "$COMMAND"; then
        if [[ -n "$warning_message" ]]; then
            warning_message="$warning_message; Destructive operation on sensitive system path detected"
        else
            warning_message="⚠️  Destructive operation on sensitive system path detected"
        fi
    fi

    # All checks passed - allow execution with optional warning
    build_json_response "allow" "" "$warning_message"
    exit 0
}

main
