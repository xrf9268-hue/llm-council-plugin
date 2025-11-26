#!/bin/bash
#
# run_peer_review.sh - Execute peer review phase (Stage 2) of council deliberation
#
# Usage: ./run_peer_review.sh "Original question" [output_dir]
#
# This script orchestrates the cross-examination phase where each council member
# reviews the responses from other members. Reviews are anonymized (Response A, B).
#
# Prerequisites:
#   - Stage 1 outputs must exist in the output directory (stage1_*.txt files)
#   - At least 2 Stage 1 responses required for meaningful peer review
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source utility functions
source "$SCRIPT_DIR/council_utils.sh"

# Validate input
if [[ $# -lt 1 ]]; then
    error_msg "No original question provided"
    echo "Usage: $0 \"Original question\" [output_dir]" >&2
    exit 1
fi

ORIGINAL_QUESTION="$1"
OUTPUT_DIR="${2:-.council}"

# Validate output directory exists with Stage 1 outputs
if [[ ! -d "$OUTPUT_DIR" ]]; then
    error_msg "Output directory not found: $OUTPUT_DIR"
    echo "Run run_parallel.sh first to generate Stage 1 outputs" >&2
    exit 1
fi

# Display stage header
stage_header "$STAGE_REVIEW" "Peer Review (Cross-Examination)"

# Check CLI availability
CLAUDE_AVAILABLE=$(check_cli claude && echo "yes" || echo "no")
CODEX_AVAILABLE=$(check_cli codex && echo "yes" || echo "no")
GEMINI_AVAILABLE=$(check_cli gemini && echo "yes" || echo "no")

council_progress 2 10
progress_msg "Loading Stage 1 responses for review..."

# Read Stage 1 outputs
CLAUDE_RESPONSE=""
CODEX_RESPONSE=""
GEMINI_RESPONSE=""
RESPONSE_COUNT=0

if [[ -s "$OUTPUT_DIR/stage1_claude.txt" ]]; then
    CLAUDE_RESPONSE=$(cat "$OUTPUT_DIR/stage1_claude.txt")
    ((RESPONSE_COUNT++)) || true
    member_status "Claude" "responded" "Stage 1 response loaded"
fi

if [[ -s "$OUTPUT_DIR/stage1_openai.txt" ]]; then
    CODEX_RESPONSE=$(cat "$OUTPUT_DIR/stage1_openai.txt")
    ((RESPONSE_COUNT++)) || true
    member_status "OpenAI Codex" "responded" "Stage 1 response loaded"
fi

if [[ -s "$OUTPUT_DIR/stage1_gemini.txt" ]]; then
    GEMINI_RESPONSE=$(cat "$OUTPUT_DIR/stage1_gemini.txt")
    ((RESPONSE_COUNT++)) || true
    member_status "Google Gemini" "responded" "Stage 1 response loaded"
fi

# Check quorum for peer review (need at least 2 responses)
if [[ $RESPONSE_COUNT -lt 2 ]]; then
    error_msg "Insufficient responses for peer review (found $RESPONSE_COUNT, need at least 2)"
    echo "Peer review requires at least 2 Stage 1 responses" >&2
    exit 1
fi

council_progress 2 20
progress_msg "Preparing cross-examination with $RESPONSE_COUNT responses"

# Load review template
TEMPLATE_PATH="$SCRIPT_DIR/../templates/review_prompt.txt"
if [[ ! -f "$TEMPLATE_PATH" ]]; then
    error_msg "Review template not found: $TEMPLATE_PATH"
    exit 1
fi

REVIEW_TEMPLATE=$(cat "$TEMPLATE_PATH")
progress_msg "Loaded peer review template"

# Function to construct anonymized review prompt using template
# Arguments: $1 = response_a, $2 = response_b (optional)
construct_review_prompt() {
    local response_a="$1"
    local response_b="${2:-}"

    # Start with template and substitute question
    local prompt="${REVIEW_TEMPLATE//\{\{QUESTION\}\}/$ORIGINAL_QUESTION}"

    # Substitute Response A
    prompt="${prompt//\{\{RESPONSE_A\}\}/$response_a}"

    # Substitute Response B (or handle single response case)
    if [[ -n "$response_b" ]]; then
        # Multiple responses: substitute Response B normally
        prompt="${prompt//\{\{RESPONSE_B\}\}/$response_b}"
    else
        # Single response: remove Response B section from template
        # This handles the edge case where only one peer response exists
        prompt=$(echo "$prompt" | sed '/--- Response B ---/,/^$/d')
    fi

    echo "$prompt"
}

# Track PIDs for parallel execution (bash 3 compatible)
PIDS=""
PID_CLAUDE=""
PID_CODEX=""
PID_GEMINI=""

council_progress 2 30
progress_msg "Launching peer reviews in parallel..."
echo "" >&2

# Claude reviews Codex + Gemini responses
if [[ "$CLAUDE_AVAILABLE" == "yes" ]]; then
    REVIEW_RESPONSES_FOR_CLAUDE=""
    REVIEW_A=""
    REVIEW_B=""

    if [[ -n "$CODEX_RESPONSE" ]]; then
        REVIEW_A="$CODEX_RESPONSE"
    fi
    if [[ -n "$GEMINI_RESPONSE" ]]; then
        if [[ -n "$REVIEW_A" ]]; then
            REVIEW_B="$GEMINI_RESPONSE"
        else
            REVIEW_A="$GEMINI_RESPONSE"
        fi
    fi

    if [[ -n "$REVIEW_A" ]]; then
        member_status "Claude" "reviewing" "evaluating Codex + Gemini"
        REVIEW_PROMPT=$(construct_review_prompt "$REVIEW_A" "$REVIEW_B")
        "$SCRIPT_DIR/query_claude.sh" "$REVIEW_PROMPT" > "$OUTPUT_DIR/stage2_review_claude.txt" 2>&1 &
        PID_CLAUDE=$!
        PIDS="$PIDS $PID_CLAUDE"
    fi
fi

# Codex reviews Claude + Gemini responses
if [[ "$CODEX_AVAILABLE" == "yes" ]]; then
    REVIEW_A=""
    REVIEW_B=""

    if [[ -n "$CLAUDE_RESPONSE" ]]; then
        REVIEW_A="$CLAUDE_RESPONSE"
    fi
    if [[ -n "$GEMINI_RESPONSE" ]]; then
        if [[ -n "$REVIEW_A" ]]; then
            REVIEW_B="$GEMINI_RESPONSE"
        else
            REVIEW_A="$GEMINI_RESPONSE"
        fi
    fi

    if [[ -n "$REVIEW_A" ]]; then
        member_status "OpenAI Codex" "reviewing" "evaluating Claude + Gemini"
        REVIEW_PROMPT=$(construct_review_prompt "$REVIEW_A" "$REVIEW_B")
        "$SCRIPT_DIR/query_codex.sh" "$REVIEW_PROMPT" > "$OUTPUT_DIR/stage2_review_openai.txt" 2>&1 &
        PID_CODEX=$!
        PIDS="$PIDS $PID_CODEX"
    fi
fi

# Gemini reviews Claude + Codex responses
if [[ "$GEMINI_AVAILABLE" == "yes" ]]; then
    REVIEW_A=""
    REVIEW_B=""

    if [[ -n "$CLAUDE_RESPONSE" ]]; then
        REVIEW_A="$CLAUDE_RESPONSE"
    fi
    if [[ -n "$CODEX_RESPONSE" ]]; then
        if [[ -n "$REVIEW_A" ]]; then
            REVIEW_B="$CODEX_RESPONSE"
        else
            REVIEW_A="$CODEX_RESPONSE"
        fi
    fi

    if [[ -n "$REVIEW_A" ]]; then
        member_status "Google Gemini" "reviewing" "evaluating Claude + Codex"
        REVIEW_PROMPT=$(construct_review_prompt "$REVIEW_A" "$REVIEW_B")
        "$SCRIPT_DIR/query_gemini.sh" "$REVIEW_PROMPT" > "$OUTPUT_DIR/stage2_review_gemini.txt" 2>&1 &
        PID_GEMINI=$!
        PIDS="$PIDS $PID_GEMINI"
    fi
fi

# Check if any reviews were launched
if [[ -z "$PIDS" ]]; then
    error_msg "No peer reviews could be launched"
    echo "Ensure at least one CLI is available and has peer responses to review" >&2
    exit 1
fi

# Wait for all background jobs and track results
council_progress 2 50
progress_msg "Waiting for peer reviews to complete..."
FAILED=""
SUCCEEDED=""

# Wait for Claude review
if [[ -n "$PID_CLAUDE" ]]; then
    if wait "$PID_CLAUDE"; then
        SUCCEEDED="$SUCCEEDED Claude"
    else
        FAILED="$FAILED Claude"
    fi
fi

# Wait for Codex review
if [[ -n "$PID_CODEX" ]]; then
    if wait "$PID_CODEX"; then
        SUCCEEDED="$SUCCEEDED Codex"
    else
        FAILED="$FAILED Codex"
    fi
fi

# Wait for Gemini review
if [[ -n "$PID_GEMINI" ]]; then
    if wait "$PID_GEMINI"; then
        SUCCEEDED="$SUCCEEDED Gemini"
    else
        FAILED="$FAILED Gemini"
    fi
fi

# Report results
echo "" >&2
council_progress 2 80
progress_msg "Peer review phase complete"

# Use enhanced display
members_complete "$SUCCEEDED" "$FAILED"

# Validate review outputs
echo "" >&2
progress_msg "Validating review outputs..."
REVIEW_COUNT=0

if validate_output "$OUTPUT_DIR/stage2_review_claude.txt" "Claude Review"; then
    ((REVIEW_COUNT++)) || true
fi

if validate_output "$OUTPUT_DIR/stage2_review_openai.txt" "Codex Review"; then
    ((REVIEW_COUNT++)) || true
fi

if validate_output "$OUTPUT_DIR/stage2_review_gemini.txt" "Gemini Review"; then
    ((REVIEW_COUNT++)) || true
fi

# Summary
echo "" >&2
council_progress 2 100
if [[ $REVIEW_COUNT -gt 0 ]]; then
    success_msg "Stage 2 complete: $REVIEW_COUNT peer review(s) captured"
else
    error_msg "No peer reviews were captured"
    exit 1
fi

# Output file listing
echo "" >&2
progress_msg "Stage 2 review files:"
ls -la "$OUTPUT_DIR"/stage2_review_*.txt 2>/dev/null || echo "No review files found" >&2
echo "" >&2

exit 0
