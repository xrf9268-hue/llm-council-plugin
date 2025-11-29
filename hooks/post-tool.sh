#!/bin/bash
#
# post-tool.sh - PostToolUse hook for LLM Council plugin
#
# This hook validates outputs after tool execution to provide:
# - Rate limit detection and guidance
# - Error pattern detection
# - Quorum verification for council operations
# - Sensitive data leak detection
#
# Called by Claude Code after Bash tool execution.
# Receives tool context via stdin as JSON.
#
# Exit codes:
#   0 - Continue with structured JSON response
#   non-zero - Signal issue (logged only, non-blocking)
#
# Output: Official Claude Code PostToolUse JSON schema (exit 0):
#   {
#     "hookSpecificOutput": {
#       "hookEventName": "PostToolUse",
#       "additionalContext": "context for Claude to consider"
#     },
#     "continue": true,
#     "systemMessage": "message for the user"
#   }

set -euo pipefail

# Configuration
MAX_OUTPUT_LENGTH="${COUNCIL_MAX_OUTPUT_LENGTH:-500000}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
COUNCIL_DIR="${COUNCIL_DIR:-.council}"
MIN_QUORUM=2

# Read input from stdin (JSON format from Claude Code)
INPUT=$(cat)

# Extract tool info from JSON (requires jq)
TOOL_NAME=""
TOOL_OUTPUT=""
EXIT_CODE="0"

if command -v jq &>/dev/null; then
    TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
    TOOL_OUTPUT=$(echo "$INPUT" | jq -r '.tool_output // empty' 2>/dev/null || echo "")
    EXIT_CODE=$(echo "$INPUT" | jq -r '.exit_code // "0"' 2>/dev/null || echo "")
else
    # If jq unavailable, exit gracefully without validation (fail open)
    cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "Post-tool security analysis disabled (jq not available). The following checks are skipped: rate limit detection, auth error detection, sensitive data leak detection, council quorum verification."
  },
  "continue": true,
  "systemMessage": "⚠️  SECURITY: jq missing - output analysis DISABLED. Install: brew install jq (macOS) | apt-get install jq (Linux) | apk add jq (Alpine)"
}
EOF
    exit 0
fi

# Array to collect context messages
declare -a CONTEXT_MESSAGES=()
declare -a SYSTEM_MESSAGES=()

# Function to check for rate limit errors
check_rate_limit() {
    local output="$1"

    local rate_limit_patterns=(
        'rate limit'
        'Rate limit'
        'RATE_LIMIT'
        '429'
        'Too many requests'
        'too many requests'
        'quota exceeded'
        'Quota exceeded'
    )

    for pattern in "${rate_limit_patterns[@]}"; do
        if [[ "$output" == *"$pattern"* ]]; then
            CONTEXT_MESSAGES+=("Rate limit detected. Consider implementing exponential backoff or waiting before retry.")
            SYSTEM_MESSAGES+=("⚠️  Rate limit detected - consider waiting before retrying")
            return 1
        fi
    done

    return 0
}

# Function to check for authentication errors
check_auth_errors() {
    local output="$1"

    local auth_patterns=(
        'unauthorized'
        'Unauthorized'
        'UNAUTHORIZED'
        '401'
        '403'
        'authentication failed'
        'Authentication failed'
        'invalid api key'
        'Invalid API key'
        'access denied'
        'Access denied'
    )

    for pattern in "${auth_patterns[@]}"; do
        if [[ "$output" == *"$pattern"* ]]; then
            CONTEXT_MESSAGES+=("Authentication error detected. Check API credentials in environment variables.")
            SYSTEM_MESSAGES+=("🔐 Authentication error - check API credentials")
            return 1
        fi
    done

    return 0
}

# Function to check output length
check_output_length() {
    local output="$1"
    local length=${#output}

    if [[ $length -gt $MAX_OUTPUT_LENGTH ]]; then
        CONTEXT_MESSAGES+=("Output is very large ($length chars). Consider truncating or summarizing if it impacts context window.")
        SYSTEM_MESSAGES+=("⚠️  Large output detected ($length chars)")
    fi

    return 0
}

# Function to verify council quorum after parallel execution
verify_council_quorum() {
    local output="$1"

    # Only check if this looks like a council operation
    if [[ "$output" != *"council"* && "$output" != *".council"* ]]; then
        return 0
    fi

    # Check if we're in a council session (use PROJECT_DIR)
    local council_path="$PROJECT_DIR/$COUNCIL_DIR"
    [[ -d "$COUNCIL_DIR" ]] && council_path="$COUNCIL_DIR"

    if [[ ! -d "$council_path" ]]; then
        return 0
    fi

    # Count Stage 1 responses
    local stage1_count=0
    [[ -s "$council_path/stage1_claude.txt" ]] && ((stage1_count++)) || true
    [[ -s "$council_path/stage1_openai.txt" ]] && ((stage1_count++)) || true
    [[ -s "$council_path/stage1_gemini.txt" ]] && ((stage1_count++)) || true

    if [[ $stage1_count -gt 0 && $stage1_count -lt $MIN_QUORUM ]]; then
        CONTEXT_MESSAGES+=("Council quorum not met: only $stage1_count of $MIN_QUORUM required responses available. Consider degraded mode or retry.")
        SYSTEM_MESSAGES+=("⚠️  Council quorum low: $stage1_count/$MIN_QUORUM models responded")
    fi

    return 0
}

# Function to sanitize output for sensitive data
check_sensitive_data_leak() {
    local output="$1"

    # Patterns that might indicate sensitive data exposure
    local sensitive_patterns=(
        'sk-(proj-)?[a-zA-Z0-9]{20,}'   # OpenAI API key pattern (old and new formats)
        'AIza[a-zA-Z0-9_-]{35}'         # Google API key pattern
        'AKIA[A-Z0-9]{16}'              # AWS access key pattern
        'ghp_[a-zA-Z0-9]{36}'           # GitHub personal access token
        'gho_[a-zA-Z0-9]{36}'           # GitHub OAuth token
    )

    for pattern in "${sensitive_patterns[@]}"; do
        if echo "$output" | grep -qE "$pattern" 2>/dev/null; then
            CONTEXT_MESSAGES+=("SECURITY: Potential API key or token detected in output. Review and sanitize before sharing.")
            SYSTEM_MESSAGES+=("🔒 Potential sensitive data detected in output")
            return 1
        fi
    done

    return 0
}

# Function to build JSON response using official Claude Code PostToolUse schema
build_json_response() {
    local additional_context=""
    local system_message=""

    # Join context messages with newlines
    if [[ ${#CONTEXT_MESSAGES[@]} -gt 0 ]]; then
        additional_context=$(printf '%s\n' "${CONTEXT_MESSAGES[@]}")
    fi

    # Join system messages with newlines
    if [[ ${#SYSTEM_MESSAGES[@]} -gt 0 ]]; then
        system_message=$(printf '%s\n' "${SYSTEM_MESSAGES[@]}")
    fi

    # Build JSON response using official schema
    jq -n \
        --arg context "$additional_context" \
        --arg message "$system_message" \
        '{
            hookSpecificOutput: {
                hookEventName: "PostToolUse",
                additionalContext: (if $context != "" then $context else null end)
            },
            continue: true,
            systemMessage: (if $message != "" then $message else null end)
        }'
}

# Main validation logic
main() {
    # Only validate Bash tool outputs
    if [[ "$TOOL_NAME" != "Bash" && "$TOOL_NAME" != "bash" ]]; then
        echo '{}'
        exit 0
    fi

    # Skip if no output to validate
    if [[ -z "$TOOL_OUTPUT" ]]; then
        echo '{}'
        exit 0
    fi

    # Run all checks (collect warnings/context)
    check_rate_limit "$TOOL_OUTPUT" || true
    check_auth_errors "$TOOL_OUTPUT" || true
    check_output_length "$TOOL_OUTPUT" || true
    verify_council_quorum "$TOOL_OUTPUT" || true
    check_sensitive_data_leak "$TOOL_OUTPUT" || true

    # Build and output JSON response
    build_json_response
    exit 0
}

main
