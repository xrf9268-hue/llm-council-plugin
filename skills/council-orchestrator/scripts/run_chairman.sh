#!/bin/bash
#
# run_chairman.sh - Phase 3: Chairman Synthesis
#
# This script prepares the context for the council-chairman sub-agent
# and generates the invocation prompt.
#
# Usage: ./run_chairman.sh "<original_question>" [council_dir]
#
# Arguments:
#   original_question  - The original user question posed to the council
#   council_dir        - Working directory (default: .council)
#
# Output:
#   - Validates Stage 1 and Stage 2 files exist
#   - Generates chairman invocation prompt to stdout
#   - The prompt should be passed to the council-chairman sub-agent
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/council_utils.sh"

# Parse arguments
ORIGINAL_QUESTION="${1:-}"
COUNCIL_DIR="${2:-.council}"

# Validate arguments
if [[ -z "$ORIGINAL_QUESTION" ]]; then
    error_msg "Usage: $0 \"<original_question>\" [council_dir]"
    exit 1
fi

if [[ ! -d "$COUNCIL_DIR" ]]; then
    error_msg "Council directory not found: $COUNCIL_DIR"
    error_msg "Run Phase 1 (run_parallel.sh) and Phase 2 (run_peer_review.sh) first."
    exit 1
fi

# Display stage header
stage_header "$STAGE_SYNTHESIS" "Chairman Synthesis"

council_progress 3 10
progress_msg "Preparing context for Chairman deliberation..."

# Check for Stage 1 files
STAGE1_FILES=()
STAGE1_MEMBERS=()

if [[ -s "$COUNCIL_DIR/stage1_claude.txt" ]]; then
    STAGE1_FILES+=("$COUNCIL_DIR/stage1_claude.txt")
    STAGE1_MEMBERS+=("Claude")
fi

if [[ -s "$COUNCIL_DIR/stage1_openai.txt" ]]; then
    STAGE1_FILES+=("$COUNCIL_DIR/stage1_openai.txt")
    STAGE1_MEMBERS+=("OpenAI Codex")
fi

if [[ -s "$COUNCIL_DIR/stage1_gemini.txt" ]]; then
    STAGE1_FILES+=("$COUNCIL_DIR/stage1_gemini.txt")
    STAGE1_MEMBERS+=("Google Gemini")
fi

# Check for Stage 2 files
STAGE2_FILES=()
STAGE2_MEMBERS=()

if [[ -s "$COUNCIL_DIR/stage2_review_claude.txt" ]]; then
    STAGE2_FILES+=("$COUNCIL_DIR/stage2_review_claude.txt")
    STAGE2_MEMBERS+=("Claude")
fi

if [[ -s "$COUNCIL_DIR/stage2_review_openai.txt" ]]; then
    STAGE2_FILES+=("$COUNCIL_DIR/stage2_review_openai.txt")
    STAGE2_MEMBERS+=("OpenAI Codex")
fi

if [[ -s "$COUNCIL_DIR/stage2_review_gemini.txt" ]]; then
    STAGE2_FILES+=("$COUNCIL_DIR/stage2_review_gemini.txt")
    STAGE2_MEMBERS+=("Google Gemini")
fi

# Validate minimum requirements
if [[ ${#STAGE1_FILES[@]} -eq 0 ]]; then
    error_msg "No Stage 1 responses found. Cannot proceed with synthesis."
    exit 1
fi

council_progress 3 30
progress_msg "Gathering evidence from council deliberation..."
echo "" >&2

# Display what we found
for member in "${STAGE1_MEMBERS[@]}"; do
    member_status "$member" "responded" "Stage 1 opinion available"
done

for member in "${STAGE2_MEMBERS[@]:-}"; do
    if [[ -n "$member" ]]; then
        member_status "$member" "responded" "Stage 2 review available"
    fi
done

echo "" >&2
progress_msg "Evidence summary: ${#STAGE1_FILES[@]} opinions, ${#STAGE2_FILES[@]} reviews"

# Determine absent members
ALL_MEMBERS=("Claude" "OpenAI Codex" "Google Gemini")
ABSENT_STAGE1=()
ABSENT_STAGE2=()

for member in "${ALL_MEMBERS[@]}"; do
    found=0
    for present in "${STAGE1_MEMBERS[@]}"; do
        if [[ "$member" == "$present" ]]; then
            found=1
            break
        fi
    done
    if [[ $found -eq 0 ]]; then
        ABSENT_STAGE1+=("$member")
    fi
done

for member in "${ALL_MEMBERS[@]}"; do
    found=0
    for present in "${STAGE2_MEMBERS[@]:-}"; do
        if [[ "$member" == "$present" ]]; then
            found=1
            break
        fi
    done
    if [[ $found -eq 0 ]]; then
        ABSENT_STAGE2+=("$member")
    fi
done

# Build the context summary
CONTEXT_SUMMARY=""

# Stage 1 summaries
CONTEXT_SUMMARY+="## Stage 1: Initial Responses\n\n"
for file in "${STAGE1_FILES[@]}"; do
    member_name=$(basename "$file" .txt | sed 's/stage1_//')
    case "$member_name" in
        claude) member_name="Claude" ;;
        openai) member_name="OpenAI Codex" ;;
        gemini) member_name="Google Gemini" ;;
    esac
    CONTEXT_SUMMARY+="### $member_name\n"
    CONTEXT_SUMMARY+="File: $file\n\n"
done

if [[ ${#ABSENT_STAGE1[@]} -gt 0 ]]; then
    CONTEXT_SUMMARY+="### Absent Members (Stage 1)\n"
    for absent in "${ABSENT_STAGE1[@]}"; do
        CONTEXT_SUMMARY+="- $absent (no response)\n"
    done
    CONTEXT_SUMMARY+="\n"
fi

# Stage 2 summaries
CONTEXT_SUMMARY+="\n## Stage 2: Peer Reviews\n\n"
if [[ ${#STAGE2_FILES[@]} -gt 0 ]]; then
    for file in "${STAGE2_FILES[@]}"; do
        member_name=$(basename "$file" .txt | sed 's/stage2_review_//')
        case "$member_name" in
            claude) member_name="Claude" ;;
            openai) member_name="OpenAI Codex" ;;
            gemini) member_name="Google Gemini" ;;
        esac
        CONTEXT_SUMMARY+="### $member_name's Review\n"
        CONTEXT_SUMMARY+="File: $file\n\n"
    done
else
    CONTEXT_SUMMARY+="No peer reviews available.\n\n"
fi

if [[ ${#ABSENT_STAGE2[@]} -gt 0 ]]; then
    CONTEXT_SUMMARY+="### Absent Members (Stage 2)\n"
    for absent in "${ABSENT_STAGE2[@]}"; do
        CONTEXT_SUMMARY+="- $absent (no review)\n"
    done
    CONTEXT_SUMMARY+="\n"
fi

council_progress 3 50
progress_msg "Generating Chairman invocation prompt..."

# Generate the chairman invocation prompt
cat << EOF
# Council Chairman: Synthesis Request

## Original User Question

$ORIGINAL_QUESTION

## Council Working Directory

$COUNCIL_DIR

## Available Files

$(echo -e "$CONTEXT_SUMMARY")

## Instructions

You are the Council Chairman. Please:

1. Read all available Stage 1 response files from the council directory
2. Read all available Stage 2 peer review files from the council directory
3. Analyze the responses for consensus and disagreements
4. Generate a comprehensive verdict report following the format in your system prompt
5. Write the final report to: $COUNCIL_DIR/final_report.md

Remember to:
- Remain neutral and objective
- Base judgments on technical merit
- Note any absent members in your report
- Identify and refute any incorrect or dangerous advice
EOF

council_progress 3 70
progress_msg "Chairman invocation prompt generated."
progress_msg "Ready to invoke council-chairman sub-agent for final synthesis."
echo "" >&2
success_msg "The Chairman will now deliberate and produce the final verdict."
