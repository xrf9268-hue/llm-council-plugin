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
#   0 - Allow tool execution (may return JSON to modify behavior)
#   2 - Block tool execution with error message
#
# Output: JSON object with optional fields (exit 0 only):
#   - permissionDecision: "allow" | "deny" | "ask"
#   - permissionDecisionReason: explanation text
#   - systemMessage: warning/info message for user
#   - suppressOutput: true to hide hook output

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
    # Fallback: exit without validation if jq unavailable
    echo '{"permissionDecision":"allow","systemMessage":"Warning: jq not available, hook validation skipped"}'
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

# Function to detect potential command injection in user-provided data
# Note: This is NOT about blocking shell operators in commands themselves,
# but about detecting suspicious patterns that might indicate injection attempts
detect_injection_attempts() {
    local command="$1"
    local warnings=()

    # Check for suspicious patterns that might indicate injection
    # These are heuristics, not hard blocks

    # Detect multiple command separators in quick succession (unusual)
    if echo "$command" | grep -qE '(;{2,}|&&{2,}|\|\|{2,})'; then
        warnings+=("Multiple command separators detected")
    fi

    # Detect obvious obfuscation attempts
    if echo "$command" | grep -qE '(\$\{IFS\}|\\x[0-9a-f]{2}|\\\[0-7]{3})'; then
        warnings+=("Potential obfuscation detected")
    fi

    # Output warnings if any found (informational only)
    if [[ ${#warnings[@]} -gt 0 ]]; then
        for warning in "${warnings[@]}"; do
            echo "INFO: $warning" >&2
        done
    fi

    return 0
}

# Function to check for operations on sensitive system paths
check_system_path_operations() {
    local command="$1"
    local warnings=()

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
            if echo "$command" | grep -qE "(rm|mv|>|>>|tee)" && echo "$command" | grep -qF "$path"; then
                warnings+=("Destructive operation on critical path: $path")
            fi
        fi
    done

    # Output warnings if any (not blocking, just informational)
    if [[ ${#warnings[@]} -gt 0 ]]; then
        for warning in "${warnings[@]}"; do
            echo "WARNING: $warning" >&2
        done
    fi

    return 0
}

# Function to validate council-specific operations
validate_council_operation() {
    local command="$1"

    # Check if this is a council script execution
    if [[ "$command" == *"council-orchestrator/scripts"* ]]; then
        # Extract script path using PROJECT_DIR
        local script_pattern='(skills/council-orchestrator/scripts/[a-z_]+\.sh)'

        if echo "$command" | grep -qE "$script_pattern"; then
            local script_path
            script_path=$(echo "$command" | grep -oE "$script_pattern" | head -n1)

            # Check if script exists (relative to project root)
            if [[ -n "$script_path" ]]; then
                local full_path="$PROJECT_DIR/$script_path"
                if [[ ! -f "$full_path" && ! -f "$script_path" ]]; then
                    echo "Council script not found: $script_path" >&2
                    return 1
                fi
            fi
        fi
    fi

    return 0
}

# Function to build JSON response
build_json_response() {
    local decision="$1"
    local reason="$2"
    local system_message="$3"

    jq -n \
        --arg decision "$decision" \
        --arg reason "$reason" \
        --arg message "$system_message" \
        '{
            permissionDecision: $decision,
            permissionDecisionReason: $reason,
            systemMessage: (if $message != "" then $message else null end),
            suppressOutput: false
        }'
}

# Main validation logic
main() {
    # Only validate Bash tool calls
    if [[ "$TOOL_NAME" != "Bash" && "$TOOL_NAME" != "bash" ]]; then
        echo '{"permissionDecision":"allow"}'
        exit 0
    fi

    # Skip if no command to validate
    if [[ -z "$COMMAND" ]]; then
        echo '{"permissionDecision":"allow"}'
        exit 0
    fi

    # Check command length (hard limit)
    if ! check_command_length "$COMMAND"; then
        local length=${#COMMAND}
        echo "Command too long ($length chars, max: $MAX_COMMAND_LENGTH)" >&2
        exit 2  # Block with error
    fi

    # Run informational checks (non-blocking)
    detect_injection_attempts "$COMMAND"
    check_system_path_operations "$COMMAND"

    # Validate council-specific operations (can block)
    if ! validate_council_operation "$COMMAND"; then
        echo "Invalid council operation" >&2
        exit 2  # Block with error
    fi

    # All checks passed - allow execution
    build_json_response "allow" "" ""
    exit 0
}

main
