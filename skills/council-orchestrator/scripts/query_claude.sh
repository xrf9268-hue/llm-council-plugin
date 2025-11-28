#!/bin/bash
#
# query_claude.sh - Query Claude CLI in non-interactive mode
#
# Usage: ./query_claude.sh "Your prompt here"
#
# This script wraps the Claude CLI to provide non-interactive querying
# for the LLM Council orchestration system.

set -euo pipefail

# Configuration
TIMEOUT_SECONDS="${CLAUDE_TIMEOUT:-120}"
MAX_RETRIES="${CLAUDE_MAX_RETRIES:-1}"

# Find timeout command (macOS uses gtimeout from coreutils, Linux uses timeout)
TIMEOUT_CMD=""
if command -v timeout &>/dev/null; then
    TIMEOUT_CMD="timeout"
elif command -v gtimeout &>/dev/null; then
    TIMEOUT_CMD="gtimeout"
fi

# Validate input
if [[ $# -lt 1 ]]; then
    echo "Error: No prompt provided" >&2
    echo "Usage: $0 \"Your prompt here\"" >&2
    exit 1
fi

PROMPT="$1"

# Check if Claude CLI is available
if ! command -v claude &> /dev/null; then
    echo "Error: claude CLI not found" >&2
    echo "Install from: https://code.claude.com/docs/en/setup" >&2
    exit 1
fi

# Function to execute query with retry logic
query_claude() {
    local attempt=0
    local exit_code=0

    while [[ $attempt -le $MAX_RETRIES ]]; do
        if [[ $attempt -gt 0 ]]; then
            echo "Retry attempt $attempt..." >&2
            sleep $((5 * attempt))  # Exponential backoff: 5s, 10s
        fi

        # Execute Claude in non-interactive print mode
        # -p: print mode (non-interactive, outputs response to stdout)
        # --output-format text: plain text output (no JSON/markdown wrappers)
        local cmd_result=0
        if [[ -n "$TIMEOUT_CMD" ]]; then
            # Use < /dev/null to prevent stdin blocking when output is redirected
            if $TIMEOUT_CMD "$TIMEOUT_SECONDS" claude -p --output-format text "$PROMPT" < /dev/null 2>/dev/null; then
                return 0
            else
                cmd_result=$?
            fi
        else
            # No timeout command available, run without timeout
            # Use < /dev/null to prevent stdin blocking when output is redirected
            if claude -p --output-format text "$PROMPT" < /dev/null 2>/dev/null; then
                return 0
            else
                cmd_result=$?
            fi
        fi

        exit_code=$cmd_result

        # Check for timeout and other errors (exit code may vary, but we handle retryable errors)
        if [[ $exit_code -eq 124 ]]; then
            echo "Warning: Claude CLI timed out after ${TIMEOUT_SECONDS}s" >&2
        elif [[ $exit_code -eq 1 ]]; then
            echo "Warning: Claude CLI returned error" >&2
        fi

        ((attempt++))
    done

    echo "Error: Failed to query Claude after $((MAX_RETRIES + 1)) attempts" >&2
    return $exit_code
}

# Execute the query
query_claude
