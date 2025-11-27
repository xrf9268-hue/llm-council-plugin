#!/bin/bash
#
# run_parallel.sh - Execute parallel queries to all available council members
#
# Usage: ./run_parallel.sh "Your prompt here"
#
# This script orchestrates parallel execution of Claude, Codex, and Gemini CLIs,
# collecting responses for the LLM Council deliberation process.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source utility functions
source "$SCRIPT_DIR/council_utils.sh"

# Validate input
if [[ $# -lt 1 ]]; then
    error_msg "No prompt provided"
    echo "Usage: $0 \"Your prompt here\"" >&2
    exit 1
fi

PROMPT="$1"
OUTPUT_DIR="${2:-.council}"

# Initialize working directory
COUNCIL_DIR="$OUTPUT_DIR" council_init

# Display stage header
stage_header "$STAGE_OPINION" "Opinion Collection"

# Check CLI availability
CLAUDE_AVAILABLE=$(check_cli claude && echo "yes" || echo "no")
CODEX_AVAILABLE=$(check_cli codex && echo "yes" || echo "no")
GEMINI_AVAILABLE=$(check_cli gemini && echo "yes" || echo "no")

MEMBER_COUNT=$(count_available_members)
progress_msg "Available council members: $MEMBER_COUNT/3"
council_progress 1 10

# Ensure at least Claude is available
if [[ "$CLAUDE_AVAILABLE" != "yes" ]]; then
    error_msg "Claude CLI is required but not available"
    echo "Install from: https://code.claude.com/docs/en/setup" >&2
    exit 1
fi

# Track PIDs and names for parallel execution (bash 3 compatible - no associative arrays)
PIDS=""
PID_CLAUDE=""
PID_CODEX=""
PID_GEMINI=""

# Launch queries in parallel
progress_msg "Launching parallel queries to council members..."
council_progress 1 20

# Build list of members being consulted
CONSULTING_MEMBERS=""

# Claude (required)
member_status "Claude" "consulting"
"$SCRIPT_DIR/query_claude.sh" "$PROMPT" > "$OUTPUT_DIR/stage1_claude.txt" 2>&1 &
PID_CLAUDE=$!
PIDS="$PIDS $PID_CLAUDE"
CONSULTING_MEMBERS="$CONSULTING_MEMBERS Claude"

# Codex (optional)
if [[ "$CODEX_AVAILABLE" == "yes" ]]; then
    member_status "OpenAI Codex" "consulting"
    "$SCRIPT_DIR/query_codex.sh" "$PROMPT" > "$OUTPUT_DIR/stage1_openai.txt" 2>&1 &
    PID_CODEX=$!
    PIDS="$PIDS $PID_CODEX"
    CONSULTING_MEMBERS="$CONSULTING_MEMBERS Codex"
else
    member_status "OpenAI Codex" "absent" "CLI not installed"
fi

# Gemini (optional)
if [[ "$GEMINI_AVAILABLE" == "yes" ]]; then
    member_status "Google Gemini" "consulting"
    "$SCRIPT_DIR/query_gemini.sh" "$PROMPT" > "$OUTPUT_DIR/stage1_gemini.txt" 2>&1 &
    PID_GEMINI=$!
    PIDS="$PIDS $PID_GEMINI"
    CONSULTING_MEMBERS="$CONSULTING_MEMBERS Gemini"
else
    member_status "Google Gemini" "absent" "CLI not installed"
fi

# Wait for all background jobs and track results
council_progress 1 50
progress_msg "Waiting for council members to respond..."
FAILED=""
SUCCEEDED=""

# Wait for Claude
if [[ -n "$PID_CLAUDE" ]]; then
    if wait "$PID_CLAUDE"; then
        SUCCEEDED="$SUCCEEDED Claude"
    else
        FAILED="$FAILED Claude"
    fi
fi

# Wait for Codex
if [[ -n "$PID_CODEX" ]]; then
    if wait "$PID_CODEX"; then
        SUCCEEDED="$SUCCEEDED Codex"
    else
        FAILED="$FAILED Codex"
    fi
fi

# Wait for Gemini
if [[ -n "$PID_GEMINI" ]]; then
    if wait "$PID_GEMINI"; then
        SUCCEEDED="$SUCCEEDED Gemini"
    else
        FAILED="$FAILED Gemini"
    fi
fi

# Report results
echo "" >&2
council_progress 1 80
progress_msg "Opinion collection complete"

# Use enhanced display
members_complete "$SUCCEEDED" "$FAILED"

# Validate outputs
echo "" >&2
progress_msg "Validating responses..."
ABSENT_MEMBERS=""

validate_output "$OUTPUT_DIR/stage1_claude.txt" "Claude" || ABSENT_MEMBERS="$ABSENT_MEMBERS Claude"

if [[ "$CODEX_AVAILABLE" == "yes" ]]; then
    validate_output "$OUTPUT_DIR/stage1_openai.txt" "Codex" || ABSENT_MEMBERS="$ABSENT_MEMBERS Codex"
fi

if [[ "$GEMINI_AVAILABLE" == "yes" ]]; then
    validate_output "$OUTPUT_DIR/stage1_gemini.txt" "Gemini" || ABSENT_MEMBERS="$ABSENT_MEMBERS Gemini"
fi

# Summary
echo "" >&2
council_progress 1 100
if [[ -z "$ABSENT_MEMBERS" ]]; then
    success_msg "Stage 1 complete: All available council members responded"
else
    progress_msg "Stage 1 complete with absent members:$ABSENT_MEMBERS"
fi

# Output file listing
echo "" >&2
progress_msg "Stage 1 output files:"
ls -la "$OUTPUT_DIR"/stage1_*.txt 2>/dev/null || echo "No output files found" >&2
echo "" >&2

exit 0
