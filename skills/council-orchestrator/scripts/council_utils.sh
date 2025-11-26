#!/bin/bash
#
# council_utils.sh - Utility functions for LLM Council orchestration
#
# This script provides shared utility functions for managing the council
# working directory, validating outputs, and checking dependencies.
#
# Source this file in other scripts:
#   source "$(dirname "$0")/council_utils.sh"

set -euo pipefail

# Default working directory (relative to project root)
COUNCIL_DIR="${COUNCIL_DIR:-.council}"

# Colors for output (disabled if not a terminal)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
fi

# Initialize the council working directory
# Usage: council_init
council_init() {
    if [[ ! -d "$COUNCIL_DIR" ]]; then
        mkdir -p "$COUNCIL_DIR"
        echo -e "${GREEN}Created council working directory: $COUNCIL_DIR${NC}" >&2
    fi
}

# Clean up the council working directory
# Usage: council_cleanup
council_cleanup() {
    if [[ -d "$COUNCIL_DIR" ]]; then
        rm -rf "$COUNCIL_DIR"
        echo -e "${GREEN}Cleaned up council working directory${NC}" >&2
    fi
}

# Validate that an output file exists and is non-empty
# Usage: validate_output <file_path> <member_name>
# Returns: 0 if valid, 1 if invalid
validate_output() {
    local file_path="$1"
    local member_name="$2"

    if [[ ! -f "$file_path" ]]; then
        echo -e "${RED}$member_name: No response file${NC}" >&2
        return 1
    fi

    if [[ ! -s "$file_path" ]]; then
        echo -e "${YELLOW}$member_name: Empty response (marked as absent)${NC}" >&2
        return 1
    fi

    echo -e "${GREEN}$member_name: Response captured${NC}" >&2
    return 0
}

# Check if a CLI tool is available
# Usage: check_cli <cli_name>
# Returns: 0 if available, 1 if not
check_cli() {
    local cli_name="$1"
    command -v "$cli_name" &>/dev/null
}

# Get the status of all council member CLIs
# Usage: get_cli_status
# Output: JSON-like status string
get_cli_status() {
    local claude_status="absent"
    local codex_status="absent"
    local gemini_status="absent"

    check_cli claude && claude_status="available"
    check_cli codex && codex_status="available"
    check_cli gemini && gemini_status="available"

    echo "claude:$claude_status codex:$codex_status gemini:$gemini_status"
}

# Count available council members
# Usage: count_available_members
# Returns: Number of available CLIs (0-3)
count_available_members() {
    local count=0
    check_cli claude && ((count++)) || true
    check_cli codex && ((count++)) || true
    check_cli gemini && ((count++)) || true
    echo "$count"
}

# Display progress message
# Usage: progress_msg <message>
progress_msg() {
    echo -e "${YELLOW}>>> $1${NC}" >&2
}

# Display error message
# Usage: error_msg <message>
error_msg() {
    echo -e "${RED}ERROR: $1${NC}" >&2
}

# Display success message
# Usage: success_msg <message>
success_msg() {
    echo -e "${GREEN}$1${NC}" >&2
}

# Check if the final report was generated
# Usage: check_final_report
# Returns: 0 if report exists and is non-empty, 1 otherwise
check_final_report() {
    local report_file="$COUNCIL_DIR/final_report.md"

    if [[ ! -f "$report_file" ]]; then
        error_msg "Final report not found: $report_file"
        return 1
    fi

    if [[ ! -s "$report_file" ]]; then
        error_msg "Final report is empty: $report_file"
        return 1
    fi

    success_msg "Final report generated: $report_file"
    return 0
}

# Get list of available Stage 1 response files
# Usage: get_stage1_files
# Output: Space-separated list of file paths
get_stage1_files() {
    local files=""
    [[ -s "$COUNCIL_DIR/stage1_claude.txt" ]] && files="$files $COUNCIL_DIR/stage1_claude.txt"
    [[ -s "$COUNCIL_DIR/stage1_openai.txt" ]] && files="$files $COUNCIL_DIR/stage1_openai.txt"
    [[ -s "$COUNCIL_DIR/stage1_gemini.txt" ]] && files="$files $COUNCIL_DIR/stage1_gemini.txt"
    echo "$files"
}

# Get list of available Stage 2 review files
# Usage: get_stage2_files
# Output: Space-separated list of file paths
get_stage2_files() {
    local files=""
    [[ -s "$COUNCIL_DIR/stage2_review_claude.txt" ]] && files="$files $COUNCIL_DIR/stage2_review_claude.txt"
    [[ -s "$COUNCIL_DIR/stage2_review_openai.txt" ]] && files="$files $COUNCIL_DIR/stage2_review_openai.txt"
    [[ -s "$COUNCIL_DIR/stage2_review_gemini.txt" ]] && files="$files $COUNCIL_DIR/stage2_review_gemini.txt"
    echo "$files"
}

# Count Stage 1 responses
# Usage: count_stage1_responses
# Returns: Number of Stage 1 files (0-3)
count_stage1_responses() {
    local count=0
    [[ -s "$COUNCIL_DIR/stage1_claude.txt" ]] && ((count++)) || true
    [[ -s "$COUNCIL_DIR/stage1_openai.txt" ]] && ((count++)) || true
    [[ -s "$COUNCIL_DIR/stage1_gemini.txt" ]] && ((count++)) || true
    echo "$count"
}

# Count Stage 2 reviews
# Usage: count_stage2_reviews
# Returns: Number of Stage 2 files (0-3)
count_stage2_reviews() {
    local count=0
    [[ -s "$COUNCIL_DIR/stage2_review_claude.txt" ]] && ((count++)) || true
    [[ -s "$COUNCIL_DIR/stage2_review_openai.txt" ]] && ((count++)) || true
    [[ -s "$COUNCIL_DIR/stage2_review_gemini.txt" ]] && ((count++)) || true
    echo "$count"
}

# Sanitize a prompt for safe shell execution
# Usage: sanitize_prompt "user input"
# Returns: Sanitized string with dangerous characters escaped/removed
sanitize_prompt() {
    local input="$1"
    local sanitized="$input"

    # Remove null bytes
    sanitized=$(echo "$sanitized" | tr -d '\0')

    # Escape backticks (command substitution)
    sanitized="${sanitized//\`/\\}"

    # Escape $( sequences (command substitution)
    sanitized="${sanitized//\$(/\\$\\(}"

    # The prompt will be passed as a single argument to the CLI
    # Most shell metacharacters are safe in single quotes
    # We just need to escape single quotes themselves
    sanitized="${sanitized//\'/\'\\\'\'}"

    echo "$sanitized"
}

# Validate that a prompt is safe to execute
# Usage: validate_prompt "user input"
# Returns: 0 if safe, 1 if potentially dangerous
validate_prompt() {
    local input="$1"
    local max_length="${COUNCIL_MAX_PROMPT_LENGTH:-10000}"

    # Check length
    if [[ ${#input} -gt $max_length ]]; then
        error_msg "Prompt exceeds maximum length ($max_length characters)"
        return 1
    fi

    # Check for null bytes
    if [[ "$input" == *$'\0'* ]]; then
        error_msg "Prompt contains null bytes"
        return 1
    fi

    return 0
}

# Validate user input for security (wrapper around validate_prompt)
# Usage: validate_user_input "user input"
# Returns: 0 if valid, 1 if invalid
validate_user_input() {
    local input="$1"
    validate_prompt "$input"
}

# Check for rate limit indicators in output
# Usage: check_rate_limit "output text"
# Returns: 0 if no rate limit, 1 if rate limited
check_rate_limit_output() {
    local output="$1"

    if [[ "$output" == *"rate limit"* ]] || \
       [[ "$output" == *"Rate limit"* ]] || \
       [[ "$output" == *"429"* ]] || \
       [[ "$output" == *"Too many requests"* ]] || \
       [[ "$output" == *"quota exceeded"* ]]; then
        return 1
    fi

    return 0
}

# Retry a command with exponential backoff
# Usage: retry_with_backoff <max_retries> <command> [args...]
# Returns: Exit code of the last command attempt
retry_with_backoff() {
    local max_retries="$1"
    shift
    local cmd="$@"

    local attempt=0
    local exit_code=0

    while [[ $attempt -le $max_retries ]]; do
        if [[ $attempt -gt 0 ]]; then
            local wait_time=$((5 * attempt))
            progress_msg "Retry attempt $attempt (waiting ${wait_time}s)..."
            sleep "$wait_time"
        fi

        if eval "$cmd"; then
            return 0
        else
            exit_code=$?
        fi

        ((attempt++))
    done

    return $exit_code
}

# ============================================================================
# Graceful Degradation & Quorum Functions
# ============================================================================

# Minimum quorum for council operations
MIN_QUORUM="${COUNCIL_MIN_QUORUM:-2}"

# Check if quorum is met for Stage 1 responses
# Usage: check_stage1_quorum
# Returns: 0 if quorum met, 1 if not
check_stage1_quorum() {
    local count
    count=$(count_stage1_responses)

    if [[ $count -lt $MIN_QUORUM ]]; then
        error_msg "Quorum not met: Only $count of $MIN_QUORUM required responses"
        return 1
    fi

    success_msg "Quorum met: $count responses available"
    return 0
}

# Check if quorum is met for Stage 2 reviews
# Usage: check_stage2_quorum
# Returns: 0 if quorum met, 1 if not
check_stage2_quorum() {
    local count
    count=$(count_stage2_reviews)

    if [[ $count -lt $MIN_QUORUM ]]; then
        error_msg "Review quorum not met: Only $count of $MIN_QUORUM required reviews"
        return 1
    fi

    success_msg "Review quorum met: $count reviews available"
    return 0
}

# Get list of absent council members (CLI not available)
# Usage: get_absent_clis
# Output: Space-separated list of absent CLI names
get_absent_clis() {
    local absent=""
    check_cli claude || absent="$absent claude"
    check_cli codex || absent="$absent codex"
    check_cli gemini || absent="$absent gemini"
    echo "$absent"
}

# Get list of absent members (no Stage 1 response)
# Usage: get_absent_members
# Output: Space-separated list of absent member names
get_absent_members() {
    local absent=""
    [[ ! -s "$COUNCIL_DIR/stage1_claude.txt" ]] && absent="$absent Claude"
    [[ ! -s "$COUNCIL_DIR/stage1_openai.txt" ]] && absent="$absent Codex"
    [[ ! -s "$COUNCIL_DIR/stage1_gemini.txt" ]] && absent="$absent Gemini"
    echo "$absent"
}

# Mark a member as absent and create placeholder file
# Usage: mark_member_absent <member_name> <reason>
mark_member_absent() {
    local member="$1"
    local reason="$2"
    local file=""

    case "$member" in
        claude|Claude)
            file="$COUNCIL_DIR/stage1_claude.txt"
            ;;
        codex|Codex|openai|OpenAI)
            file="$COUNCIL_DIR/stage1_openai.txt"
            ;;
        gemini|Gemini)
            file="$COUNCIL_DIR/stage1_gemini.txt"
            ;;
        *)
            error_msg "Unknown member: $member"
            return 1
            ;;
    esac

    echo "[ABSENT] $member did not respond: $reason" > "$file"
    echo -e "${YELLOW}Marked $member as absent: $reason${NC}" >&2
}

# Determine if council can proceed based on quorum
# Usage: can_council_proceed
# Returns: 0 if can proceed, 1 if should abort
can_council_proceed() {
    local available
    available=$(count_available_members)

    if [[ $available -lt 1 ]]; then
        error_msg "No council members available. Cannot proceed."
        return 1
    fi

    if [[ $available -lt $MIN_QUORUM ]]; then
        echo -e "${YELLOW}WARNING: Only $available member(s) available (minimum $MIN_QUORUM recommended)${NC}" >&2
        echo -e "${YELLOW}Council will proceed with degraded coverage.${NC}" >&2
    fi

    return 0
}

# Generate degradation report section for final report
# Usage: generate_degradation_report
# Output: Markdown section describing absent members
generate_degradation_report() {
    local absent_clis
    local absent_members

    absent_clis=$(get_absent_clis)
    absent_members=$(get_absent_members)

    if [[ -z "$absent_clis" && -z "$absent_members" ]]; then
        echo "All council members participated fully."
        return 0
    fi

    echo "### Council Participation Notes"
    echo ""

    if [[ -n "$absent_clis" ]]; then
        echo "**Unavailable CLIs:**"
        for cli in $absent_clis; do
            echo "- $cli (not installed)"
        done
        echo ""
    fi

    if [[ -n "$absent_members" ]]; then
        echo "**Members who did not respond:**"
        for member in $absent_members; do
            echo "- $member"
        done
        echo ""
    fi

    echo "_Note: Council consensus was reached with available members._"
}

# Display council session summary
# Usage: council_summary
council_summary() {
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "                   COUNCIL SESSION SUMMARY                  "
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "Stage 1 Responses: $(count_stage1_responses)/3"
    echo "Stage 2 Reviews:   $(count_stage2_reviews)/3"
    echo ""

    if check_final_report 2>/dev/null; then
        echo "Final Report:      ✓ Generated"
        echo ""
        echo "Report Location:   $COUNCIL_DIR/final_report.md"
    else
        echo "Final Report:      ✗ Not generated"
    fi
    echo ""
    echo "═══════════════════════════════════════════════════════════"
}

# ============================================================================
# Phase 7: Enhanced Progress Display Functions
# ============================================================================

# Stage indicator constants
STAGE_OPINION="1"
STAGE_REVIEW="2"
STAGE_SYNTHESIS="3"

# Display stage header with visual separator
# Usage: stage_header <stage_number> <stage_name>
stage_header() {
    local stage_num="$1"
    local stage_name="$2"
    echo "" >&2
    echo -e "${YELLOW}┌─────────────────────────────────────────────────────────┐${NC}" >&2
    echo -e "${YELLOW}│  Stage $stage_num: $stage_name${NC}" >&2
    echo -e "${YELLOW}└─────────────────────────────────────────────────────────┘${NC}" >&2
    echo "" >&2
}

# Display member status with icon
# Usage: member_status <member_name> <status> [details]
# Status: consulting, responded, failed, absent, reviewing
member_status() {
    local member="$1"
    local status="$2"
    local details="${3:-}"
    local icon=""
    local color=""

    case "$status" in
        consulting)
            icon="⏳"
            color="$YELLOW"
            ;;
        responded)
            icon="✓"
            color="$GREEN"
            ;;
        failed)
            icon="✗"
            color="$RED"
            ;;
        absent)
            icon="○"
            color="$YELLOW"
            ;;
        reviewing)
            icon="🔍"
            color="$YELLOW"
            ;;
    esac

    if [[ -n "$details" ]]; then
        echo -e "  ${color}$icon $member: $status - $details${NC}" >&2
    else
        echo -e "  ${color}$icon $member: $status${NC}" >&2
    fi
}

# Display progress bar (visual only, not functional progress)
# Usage: progress_bar <current> <total> <label>
progress_bar() {
    local current="$1"
    local total="$2"
    local label="${3:-Progress}"
    local width=30
    local filled=$((current * width / total))
    local empty=$((width - filled))

    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done

    echo -e "  ${YELLOW}$label: [$bar] $current/$total${NC}" >&2
}

# Display estimated progress through council session
# Usage: council_progress <stage> <substep>
# stage: 1=opinion, 2=review, 3=synthesis
# substep: 0-100 within stage
council_progress() {
    local stage="$1"
    local substep="${2:-0}"
    local total_stages=3
    local progress=0

    case "$stage" in
        1) progress=$((substep / 3)) ;;          # 0-33%
        2) progress=$((33 + substep / 3)) ;;     # 33-66%
        3) progress=$((66 + substep / 3)) ;;     # 66-100%
    esac

    local width=40
    local filled=$((progress * width / 100))
    local empty=$((width - filled))

    local bar=""
    for ((i=0; i<filled; i++)); do bar+="▓"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done

    echo -e "\n${YELLOW}Council Progress: [$bar] ${progress}%${NC}\n" >&2
}

# Display spinner during long operations (call in subshell)
# Usage: spinner <pid> <message>
spinner() {
    local pid="$1"
    local msg="${2:-Working...}"
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0

    while kill -0 "$pid" 2>/dev/null; do
        local char="${spin:i++%${#spin}:1}"
        echo -ne "\r  ${YELLOW}$char $msg${NC}" >&2
        sleep 0.1
    done
    echo -e "\r  ${GREEN}✓ $msg - done${NC}" >&2
}

# Display member waiting status for parallel execution
# Usage: waiting_for_members <member1> [member2] [member3]
waiting_for_members() {
    local members=("$@")
    echo -e "\n${YELLOW}  Waiting for responses from:${NC}" >&2
    for m in "${members[@]}"; do
        echo -e "    ${YELLOW}⏳ $m${NC}" >&2
    done
}

# Display completion status for all members
# Usage: members_complete <responded_list> <failed_list>
members_complete() {
    local responded="$1"
    local failed="$2"

    echo "" >&2
    if [[ -n "$responded" ]]; then
        echo -e "  ${GREEN}Responded:${NC}" >&2
        for m in $responded; do
            echo -e "    ${GREEN}✓ $m${NC}" >&2
        done
    fi

    if [[ -n "$failed" ]]; then
        echo -e "  ${RED}Failed/Absent:${NC}" >&2
        for m in $failed; do
            echo -e "    ${RED}✗ $m${NC}" >&2
        done
    fi
}

# Display final report preview
# Usage: preview_report <report_file> [num_lines]
preview_report() {
    local report_file="$1"
    local num_lines="${2:-10}"

    if [[ ! -s "$report_file" ]]; then
        error_msg "Report file not found or empty: $report_file"
        return 1
    fi

    echo "" >&2
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
    echo -e "${GREEN}                     COUNCIL VERDICT                       ${NC}" >&2
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
    echo "" >&2
    head -n "$num_lines" "$report_file" >&2
    echo "" >&2
    echo -e "${YELLOW}... (see full report in $report_file)${NC}" >&2
    echo "" >&2
}

# ============================================================================
# Configuration Management Functions
# ============================================================================

# Default configuration file location
COUNCIL_CONFIG_FILE="${COUNCIL_CONFIG_FILE:-$HOME/.council/config}"

# Get a configuration value
# Usage: config_get <key> [default_value]
config_get() {
    local key="$1"
    local default="${2:-}"

    if [[ -f "$COUNCIL_CONFIG_FILE" ]]; then
        local value
        value=$(grep "^${key}=" "$COUNCIL_CONFIG_FILE" 2>/dev/null | cut -d'=' -f2-)
        if [[ -n "$value" ]]; then
            echo "$value"
            return 0
        fi
    fi

    echo "$default"
}

# Set a configuration value
# Usage: config_set <key> <value>
config_set() {
    local key="$1"
    local value="$2"

    # Ensure config directory exists
    local config_dir
    config_dir=$(dirname "$COUNCIL_CONFIG_FILE")
    mkdir -p "$config_dir"

    # Create file if doesn't exist
    touch "$COUNCIL_CONFIG_FILE"

    # Remove existing key if present
    if grep -q "^${key}=" "$COUNCIL_CONFIG_FILE" 2>/dev/null; then
        # macOS/BSD sed compatibility
        if [[ "$(uname)" == "Darwin" ]]; then
            sed -i '' "/^${key}=/d" "$COUNCIL_CONFIG_FILE"
        else
            sed -i "/^${key}=/d" "$COUNCIL_CONFIG_FILE"
        fi
    fi

    # Append new value
    echo "${key}=${value}" >> "$COUNCIL_CONFIG_FILE"
    success_msg "Set $key=$value"
}

# List all configuration values
# Usage: config_list
config_list() {
    echo ""
    echo "Council Configuration"
    echo "─────────────────────────────────────────────"

    if [[ -f "$COUNCIL_CONFIG_FILE" ]]; then
        echo "Config file: $COUNCIL_CONFIG_FILE"
        echo ""
        cat "$COUNCIL_CONFIG_FILE"
    else
        echo "No configuration file found."
        echo ""
        echo "Default values:"
        echo "  enabled_members=claude,codex,gemini"
        echo "  min_quorum=2"
        echo "  max_prompt_length=10000"
        echo "  timeout=120"
    fi
    echo ""
    echo "─────────────────────────────────────────────"
}

# Check if a specific member is enabled
# Usage: is_member_enabled <member_name>
is_member_enabled() {
    local member="$1"
    local enabled
    enabled=$(config_get "enabled_members" "claude,codex,gemini")

    if [[ "$enabled" == *"$member"* ]]; then
        return 0
    fi
    return 1
}

# Get list of enabled members
# Usage: get_enabled_members
get_enabled_members() {
    config_get "enabled_members" "claude,codex,gemini"
}
