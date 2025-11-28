# Council Orchestrator - Technical Reference

This document provides detailed bash implementation guidance for the LLM Council orchestration protocol. For quick-start instructions, see [SKILL.md](./SKILL.md).

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Phase 1: Opinion Collection](#phase-1-opinion-collection)
- [Phase 2: Peer Review](#phase-2-peer-review)
- [Phase 3: Chairman Synthesis](#phase-3-chairman-synthesis)
- [Error Handling](#error-handling)
- [Advanced Configuration](#advanced-configuration)

---

## Prerequisites

### CLI Installation

#### Claude CLI
```bash
# Installation varies by platform
# See: https://code.claude.com/docs/en/setup
command -v claude || echo "Install required"
```

#### OpenAI Codex CLI (Optional)
```bash
npm install -g @openai/codex
export OPENAI_API_KEY="your-key-here"
```

#### Google Gemini CLI (Optional)
```bash
npm install -g @google/gemini-cli
export GEMINI_API_KEY="your-key-here"
```

### Quorum Requirements

| Scenario | Available CLIs | Council Mode | Recommendation |
|----------|----------------|--------------|----------------|
| Minimum | Claude only | Single-model | Testing only |
| Reduced | 2 of 3 | Degraded council | Acceptable for production |
| Optimal | All 3 | Full council | Recommended |

**Minimum Quorum Check:**
```bash
# Resolve plugin root
PLUGIN_ROOT="${COUNCIL_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CLAUDE_PROJECT_DIR}}}"
source "${PLUGIN_ROOT}/skills/council-orchestrator/scripts/council_utils.sh"
can_council_proceed || {
    error_msg "Cannot proceed - no CLIs available"
    exit 1
}
```

---

## Phase 1: Opinion Collection

### Overview
Phase 1 consults all available LLM CLIs in parallel, capturing their independent opinions.

### Manual Implementation

#### Step 1.1: Initialize Working Directory
```bash
# Resolve plugin root
PLUGIN_ROOT="${COUNCIL_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CLAUDE_PROJECT_DIR}}}"
source "${PLUGIN_ROOT}/skills/council-orchestrator/scripts/council_utils.sh"
council_init  # Creates .council/ directory with 700 permissions
```

#### Step 1.2: Check Available CLIs
```bash
CLAUDE_AVAILABLE=$(command -v claude &>/dev/null && echo "yes" || echo "no")
CODEX_AVAILABLE=$(command -v codex &>/dev/null && echo "yes" || echo "no")
GEMINI_AVAILABLE=$(command -v gemini &>/dev/null && echo "yes" || echo "no")
MEMBER_COUNT=$(count_available_members)

progress_msg "Available council members: $MEMBER_COUNT"
```

#### Step 1.3: Validate User Input
```bash
# Security check before processing
validate_user_input "$user_query" || {
    error_msg "Invalid input detected"
    exit 1
}
```

#### Step 1.4: Invoke Available Members (Parallel)

**Single-Model Mode (Claude only):**
```bash
# Get plugin root for script paths
PLUGIN_ROOT="${COUNCIL_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CLAUDE_PROJECT_DIR}}}"

if [[ "$MEMBER_COUNT" -eq 1 && "$CLAUDE_AVAILABLE" == "yes" ]]; then
    progress_msg "Single-model mode: Consulting Claude..."
    "${PLUGIN_ROOT}/skills/council-orchestrator/scripts/query_claude.sh" "$query" \
        > .council/stage1_claude.txt 2>&1
fi
```

**Full Council Mode (2+ members):**
```bash
# Get plugin root for script paths
PLUGIN_ROOT="${COUNCIL_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CLAUDE_PROJECT_DIR}}}"

progress_msg "Full council mode: Consulting all available members in parallel..."

# Track PIDs for background job management
PIDS=()

# Launch Claude (required)
if [[ "$CLAUDE_AVAILABLE" == "yes" ]]; then
    progress_msg "Consulting Claude..."
    "${PLUGIN_ROOT}/skills/council-orchestrator/scripts/query_claude.sh" "$query" \
        > .council/stage1_claude.txt 2>&1 &
    PIDS+=($!)
fi

# Launch Codex (optional)
if [[ "$CODEX_AVAILABLE" == "yes" ]]; then
    progress_msg "Consulting OpenAI Codex..."
    "${PLUGIN_ROOT}/skills/council-orchestrator/scripts/query_codex.sh" "$query" \
        > .council/stage1_openai.txt 2>&1 &
    PIDS+=($!)
fi

# Launch Gemini (optional)
if [[ "$GEMINI_AVAILABLE" == "yes" ]]; then
    progress_msg "Consulting Google Gemini..."
    "${PLUGIN_ROOT}/skills/council-orchestrator/scripts/query_gemini.sh" "$query" \
        > .council/stage1_gemini.txt 2>&1 &
    PIDS+=($!)
fi

# Wait for all background jobs to complete
for pid in "${PIDS[@]}"; do
    wait "$pid" || true  # Continue even if one fails
done

progress_msg "All council members have responded."
```

#### Step 1.5: Validate Outputs
```bash
ABSENT_MEMBERS=()

validate_output ".council/stage1_claude.txt" "Claude" || \
    ABSENT_MEMBERS+=("Claude")

[[ "$CODEX_AVAILABLE" == "yes" ]] && \
    validate_output ".council/stage1_openai.txt" "Codex" || \
    ABSENT_MEMBERS+=("Codex")

[[ "$GEMINI_AVAILABLE" == "yes" ]] && \
    validate_output ".council/stage1_gemini.txt" "Gemini" || \
    ABSENT_MEMBERS+=("Gemini")

if [[ ${#ABSENT_MEMBERS[@]} -gt 0 ]]; then
    echo "Absent members: ${ABSENT_MEMBERS[*]}" >&2
fi
```

#### Step 1.6: Check Quorum
```bash
check_stage1_quorum || {
    error_msg "Insufficient responses for council deliberation"
    council_cleanup
    exit 1
}
```

### Automated Script

**Using run_parallel.sh:**
```bash
# Get plugin root for script paths
PLUGIN_ROOT="${COUNCIL_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CLAUDE_PROJECT_DIR}}}"
"${PLUGIN_ROOT}/skills/council-orchestrator/scripts/run_parallel.sh" "$query" .council
```

This script handles all of Phase 1 automatically.

---

## Phase 2: Peer Review

### Overview
Each LLM reviews the responses from other members, providing critique and validation.

### Manual Implementation

#### Step 2.1: Read Stage 1 Outputs
```bash
CLAUDE_RESPONSE=""
CODEX_RESPONSE=""
GEMINI_RESPONSE=""

[[ -s ".council/stage1_claude.txt" ]] && \
    CLAUDE_RESPONSE=$(cat .council/stage1_claude.txt)

[[ -s ".council/stage1_openai.txt" ]] && \
    CODEX_RESPONSE=$(cat .council/stage1_openai.txt)

[[ -s ".council/stage1_gemini.txt" ]] && \
    GEMINI_RESPONSE=$(cat .council/stage1_gemini.txt)
```

#### Step 2.2: Construct Anonymized Review Prompts

**Load Review Template:**
```bash
REVIEW_TEMPLATE=$(cat ./skills/council-orchestrator/templates/review_prompt.txt)
```

**Cross-Review Matrix:**

| Reviewer | Reviews |
|----------|---------|
| Claude   | Codex (A) + Gemini (B) |
| Codex    | Claude (A) + Gemini (B) |
| Gemini   | Claude (A) + Codex (B) |

**Generate Claude's Review Prompt:**
```bash
CLAUDE_REVIEW_PROMPT="${REVIEW_TEMPLATE//\{\{QUESTION\}\}/$original_question}"
CLAUDE_REVIEW_PROMPT="${CLAUDE_REVIEW_PROMPT//\{\{RESPONSE_A\}\}/$CODEX_RESPONSE}"
CLAUDE_REVIEW_PROMPT="${CLAUDE_REVIEW_PROMPT//\{\{RESPONSE_B\}\}/$GEMINI_RESPONSE}"
```

**Generate Similar Prompts for Codex and Gemini:**
```bash
# Codex reviews Claude (A) + Gemini (B)
CODEX_REVIEW_PROMPT="${REVIEW_TEMPLATE//\{\{QUESTION\}\}/$original_question}"
CODEX_REVIEW_PROMPT="${CODEX_REVIEW_PROMPT//\{\{RESPONSE_A\}\}/$CLAUDE_RESPONSE}"
CODEX_REVIEW_PROMPT="${CODEX_REVIEW_PROMPT//\{\{RESPONSE_B\}\}/$GEMINI_RESPONSE}"

# Gemini reviews Claude (A) + Codex (B)
GEMINI_REVIEW_PROMPT="${REVIEW_TEMPLATE//\{\{QUESTION\}\}/$original_question}"
GEMINI_REVIEW_PROMPT="${GEMINI_REVIEW_PROMPT//\{\{RESPONSE_A\}\}/$CLAUDE_RESPONSE}"
GEMINI_REVIEW_PROMPT="${GEMINI_REVIEW_PROMPT//\{\{RESPONSE_B\}\}/$CODEX_RESPONSE}"
```

#### Step 2.3: Execute Reviews in Parallel
```bash
# Get plugin root for script paths
PLUGIN_ROOT="${COUNCIL_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CLAUDE_PROJECT_DIR}}}"

progress_msg "Starting peer review phase..."
PIDS=()

# Claude reviews Codex + Gemini responses
if [[ "$CLAUDE_AVAILABLE" == "yes" && ( -n "$CODEX_RESPONSE" || -n "$GEMINI_RESPONSE" ) ]]; then
    progress_msg "Claude reviewing peer responses..."
    "${PLUGIN_ROOT}/skills/council-orchestrator/scripts/query_claude.sh" "$CLAUDE_REVIEW_PROMPT" \
        > .council/stage2_review_claude.txt 2>&1 &
    PIDS+=($!)
fi

# Codex reviews Claude + Gemini responses
if [[ "$CODEX_AVAILABLE" == "yes" && ( -n "$CLAUDE_RESPONSE" || -n "$GEMINI_RESPONSE" ) ]]; then
    progress_msg "Codex reviewing peer responses..."
    "${PLUGIN_ROOT}/skills/council-orchestrator/scripts/query_codex.sh" "$CODEX_REVIEW_PROMPT" \
        > .council/stage2_review_openai.txt 2>&1 &
    PIDS+=($!)
fi

# Gemini reviews Claude + Codex responses
if [[ "$GEMINI_AVAILABLE" == "yes" && ( -n "$CLAUDE_RESPONSE" || -n "$CODEX_RESPONSE" ) ]]; then
    progress_msg "Gemini reviewing peer responses..."
    "${PLUGIN_ROOT}/skills/council-orchestrator/scripts/query_gemini.sh" "$GEMINI_REVIEW_PROMPT" \
        > .council/stage2_review_gemini.txt 2>&1 &
    PIDS+=($!)
fi

# Wait for all reviews to complete
for pid in "${PIDS[@]}"; do
    wait "$pid" || true
done

progress_msg "Peer review phase complete."
```

#### Step 2.4: Validate Review Outputs
```bash
validate_output ".council/stage2_review_claude.txt" "Claude Review" || true
validate_output ".council/stage2_review_openai.txt" "Codex Review" || true
validate_output ".council/stage2_review_gemini.txt" "Gemini Review" || true
```

**Output Files:**
- `.council/stage2_review_claude.txt` - Claude's review of Codex + Gemini
- `.council/stage2_review_openai.txt` - Codex's review of Claude + Gemini
- `.council/stage2_review_gemini.txt` - Gemini's review of Claude + Codex

### Automated Script

**Using run_peer_review.sh:**
```bash
# Get plugin root for script paths
PLUGIN_ROOT="${COUNCIL_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CLAUDE_PROJECT_DIR}}}"
"${PLUGIN_ROOT}/skills/council-orchestrator/scripts/run_peer_review.sh" "$original_question" .council
```

This script handles all of Phase 2 automatically.

---

## Phase 3: Chairman Synthesis

### Overview
The chairman sub-agent analyzes all Stage 1 responses and Stage 2 peer reviews to generate a final consensus report.

### Manual Implementation

#### Step 3.1: Generate Chairman Prompt
```bash
# Get plugin root for script paths
PLUGIN_ROOT="${COUNCIL_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CLAUDE_PROJECT_DIR}}}"

# Use the chairman script to generate the invocation prompt
CHAIRMAN_PROMPT=$("${PLUGIN_ROOT}/skills/council-orchestrator/scripts/run_chairman.sh" \
    "$original_question" \
    .council)
```

**The script validates:**
- Stage 1 response files exist
- At least 1 Stage 1 response is available
- Stage 2 peer review files (if available)

**The prompt includes:**
- Original user question
- Paths to all Stage 1/2 files
- Instructions from templates/chairman_prompt.txt
- Report structure guidelines

#### Step 3.2: Invoke Chairman Sub-agent

**Using Task Tool:**
```
Use the council-chairman agent to synthesize the council's responses.

$CHAIRMAN_PROMPT
```

The chairman sub-agent will:
1. Read all Stage 1 response files from `.council/`
2. Read all Stage 2 peer review files from `.council/`
3. Analyze for consensus points and disagreements
4. Generate a comprehensive verdict report
5. Write the final report to `.council/final_report.md`

#### Step 3.3: Context Isolation

**Important**: The chairman sub-agent operates in an isolated context:
- It has access ONLY to Read and Write tools (no Bash, no external CLIs)
- It cannot invoke claude/codex/gemini CLIs
- It processes data independently from the main session
- The main session only receives the final report

This isolation ensures:
- No contamination between main session and synthesis
- Chairman cannot be influenced by ongoing conversation
- Reproducible results based solely on Stage 1/2 files

#### Step 3.4: Retrieve Final Report
```bash
if [[ -s ".council/final_report.md" ]]; then
    cat .council/final_report.md
else
    error_msg "Chairman failed to generate report"
    exit 1
fi
```

#### Step 3.5: Cleanup (Optional)
```bash
# Optional: when you no longer need this session's files,
# remove the council working directory and all generated artifacts.
council_cleanup

# Or manually:
# rm -rf .council
```

**Note**: The cleanup step removes all intermediate files, including `final_report.md`. Ensure you've captured or presented the final report to the user and do not intend to reuse the `.council/` directory before running cleanup. The `/council` command is responsible for resetting `.council/` at the start of each new council session, so end-of-session cleanup is not required for correctness.

### Automated Script

**Using run_chairman.sh:**
```bash
# Get plugin root for script paths
PLUGIN_ROOT="${COUNCIL_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CLAUDE_PROJECT_DIR}}}"

# Generate chairman prompt
CHAIRMAN_PROMPT=$("${PLUGIN_ROOT}/skills/council-orchestrator/scripts/run_chairman.sh" \
    "$original_question" \
    .council)

# Then invoke chairman agent with the prompt
```

---

## Error Handling

### Rate Limiting (HTTP 429)

**Detection:**
```bash
check_rate_limit_output "$cli_output" || {
    progress_msg "Rate limit detected"
}
```

**Mitigation: Exponential Backoff**
```bash
retry_with_backoff 2 "./scripts/query_codex.sh \"$query\"" || {
    mark_member_absent "Codex" "Rate limit exceeded"
}
```

**Backoff Schedule:**
- Attempt 1: Immediate
- Attempt 2: Wait 5 seconds
- Attempt 3: Wait 10 seconds

### CLI Execution Error (Non-Zero Exit)

**Detection:**
```bash
if ! ./scripts/query_claude.sh "$query" > .council/stage1_claude.txt 2>&1; then
    error_msg "Claude CLI failed with exit code $?"
    mark_member_absent "Claude" "CLI execution error"
fi
```

**Handling:**
- Mark member as absent in final report
- Continue with available members
- Log error details to stderr

### Empty Output

**Detection:**
```bash
validate_output ".council/stage1_claude.txt" "Claude" || {
    mark_member_absent "Claude" "Empty response"
}
```

**Common Causes:**
- Authentication failure (missing API key)
- Network timeout
- Rate limiting (check stderr for 429)
- CLI bug or crash

### Timeout (>60 seconds)

**Implementation:**
```bash
timeout 60s ./scripts/query_claude.sh "$query" \
    > .council/stage1_claude.txt 2>&1 || {
    exit_code=$?
    if [[ $exit_code -eq 124 ]]; then
        error_msg "Claude timed out after 60 seconds"
        mark_member_absent "Claude" "Timeout"
    fi
}
```

**Configurable Timeout:**
```bash
TIMEOUT_SECONDS="${COUNCIL_CLI_TIMEOUT:-60}"
timeout "${TIMEOUT_SECONDS}s" ./scripts/query_claude.sh "$query"
```

### Quorum Failure

**Detection:**
```bash
check_stage1_quorum || {
    error_msg "Quorum not met: $(count_stage1_responses) responses"
    council_cleanup
    exit 1
}
```

**Quorum Requirements:**
- Default: MIN_QUORUM=2
- Override: `export COUNCIL_MIN_QUORUM=1`

---

## Advanced Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `COUNCIL_DIR` | `.council` | Working directory for council files |
| `COUNCIL_MIN_QUORUM` | `2` | Minimum responses required |
| `COUNCIL_MAX_PROMPT_LENGTH` | `10000` | Maximum query length (chars) |
| `COUNCIL_CLI_TIMEOUT` | `60` | CLI timeout (seconds) |
| `COUNCIL_CONFIG_FILE` | `~/.council/config` | Config file location |

### Configuration File

**Location:** `~/.council/config`

**Format:**
```
enabled_members=claude,codex,gemini
min_quorum=2
max_prompt_length=10000
timeout=120
```

**Usage:**
```bash
# Get config value
timeout=$(config_get "timeout" "60")

# Set config value
config_set "enabled_members" "claude,gemini"

# List all config
config_list
```

### Selective Member Enabling

**Disable Specific Members:**
```bash
# Only use Claude and Gemini (skip Codex)
config_set "enabled_members" "claude,gemini"

# Check if member is enabled
is_member_enabled "codex" || echo "Codex disabled"
```

### Custom Prompt Templates

**Override Review Template:**
```bash
# Use custom review template
export REVIEW_TEMPLATE_PATH="./my-custom-review.txt"

# In scripts, check for custom template
if [[ -f "$REVIEW_TEMPLATE_PATH" ]]; then
    REVIEW_TEMPLATE=$(cat "$REVIEW_TEMPLATE_PATH")
else
    REVIEW_TEMPLATE=$(cat ./skills/council-orchestrator/templates/review_prompt.txt)
fi
```

### Debugging Mode

**Enable Verbose Output:**
```bash
set -x  # Enable bash debug trace

# Or use council utilities
export COUNCIL_DEBUG=1

# In scripts:
[[ -n "$COUNCIL_DEBUG" ]] && set -x
```

**Capture Full CLI Output:**
```bash
# Redirect both stdout and stderr to separate files
./scripts/query_claude.sh "$query" \
    > .council/stage1_claude.stdout \
    2> .council/stage1_claude.stderr
```

---

## File Structure Reference

### After Phase 1 (Opinion Collection)
```
.council/
├── stage1_claude.txt   # Claude's response
├── stage1_openai.txt   # Codex's response (if available)
└── stage1_gemini.txt   # Gemini's response (if available)
```

### After Phase 2 (Peer Review)
```
.council/
├── stage1_claude.txt
├── stage1_openai.txt
├── stage1_gemini.txt
├── stage2_review_claude.txt   # Claude's review
├── stage2_review_openai.txt   # Codex's review
└── stage2_review_gemini.txt   # Gemini's review
```

### After Phase 3 (Chairman Synthesis)
```
.council/
├── stage1_*.txt
├── stage2_review_*.txt
└── final_report.md      # Chairman's consensus report
```

---

## See Also

- [SKILL.md](./SKILL.md) - Core workflow and quick start
- [EXAMPLES.md](./EXAMPLES.md) - Usage scenarios and troubleshooting
- [SECURITY.md](./SECURITY.md) - Security best practices
- [METADATA.md](./METADATA.md) - Version and compatibility info
- [templates/review_prompt.txt](./templates/review_prompt.txt) - Peer review template
- [templates/chairman_prompt.txt](./templates/chairman_prompt.txt) - Chairman invocation template
