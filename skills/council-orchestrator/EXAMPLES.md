# Council Orchestrator - Usage Examples

## Overview

This document provides comprehensive usage scenarios for the council-orchestrator skill, covering full council mode, degraded mode, error recovery, and troubleshooting.

---

## Scenario 1: Full Council Mode (All 3 CLIs Available)

### User Request
"Review this authentication implementation from a security perspective"

### Prerequisites
```bash
# Verify all CLIs are available
command -v claude && echo "✓ Claude"
command -v codex && echo "✓ Codex"
command -v gemini && echo "✓ Gemini"
```

### Execution
```bash
# Resolve plugin root
PLUGIN_ROOT="${COUNCIL_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CLAUDE_PROJECT_DIR}}}"
source "${PLUGIN_ROOT}/skills/council-orchestrator/scripts/council_utils.sh"

# Phase 0: reset working directory for this run
council_cleanup || true
council_init

# Phase 1: Parallel opinion collection
"${PLUGIN_ROOT}/skills/council-orchestrator/scripts/run_parallel.sh" \
    "Review this authentication implementation from a security perspective" \
    .council

# Phase 2: Peer review
"${PLUGIN_ROOT}/skills/council-orchestrator/scripts/run_peer_review.sh" \
    "Review this authentication implementation from a security perspective" \
    .council

# Phase 3: Chairman synthesis
CHAIRMAN_PROMPT=$("${PLUGIN_ROOT}/skills/council-orchestrator/scripts/run_chairman.sh" \
    "Review this authentication implementation from a security perspective" \
    .council)

# Invoke chairman agent with the generated prompt
# (Use Task tool with council-chairman agent)

# Retrieve and display final report for this run
cat .council/final_report.md
```

### Expected Output
```
┌─────────────────────────────────────────────────────────┐
│  Stage 1: Opinion Collection
└─────────────────────────────────────────────────────────┘

Council Status: Full council (3/3 members)
  ⏳ Claude: consulting...
  ⏳ Codex: consulting...
  ⏳ Gemini: consulting...

  ✓ Claude: responded
  ✓ Codex: responded
  ✓ Gemini: responded

┌─────────────────────────────────────────────────────────┐
│  Stage 2: Peer Review
└─────────────────────────────────────────────────────────┘

  ✓ Claude reviewing Codex + Gemini
  ✓ Codex reviewing Claude + Gemini
  ✓ Gemini reviewing Claude + Codex

┌─────────────────────────────────────────────────────────┐
│  Stage 3: Chairman Synthesis
└─────────────────────────────────────────────────────────┘

Chairman synthesizing council responses...

Final Report Generated: .council/final_report.md
```

---

## Scenario 2: Degraded Council (Only Claude + Gemini)

### User Request
"What's the best approach for implementing rate limiting?"

### Prerequisites
```bash
# Codex CLI not available
command -v claude && echo "✓ Claude"
command -v gemini && echo "✓ Gemini"
! command -v codex && echo "⚠ Codex not available"
```

### Execution
```bash
# Initialize working directory (reset if needed)
council_cleanup || true
council_init

# Phase 1: Only available members participate
"${PLUGIN_ROOT}/skills/council-orchestrator/scripts/run_parallel.sh" \
    "What's the best approach for implementing rate limiting?" \
    .council
```

### Expected Output
```
Council Status: Degraded council (2/3 members)
  ✓ Claude: responded
  ○ Codex: not available (CLI not found)
  ✓ Gemini: responded

⚠ WARNING: Only 2 member(s) available (minimum 2 recommended)
Council will proceed with degraded coverage.

Peer Review: Proceeding with 2 members
Final Synthesis: Chairman will note absent member
```

### Final Report Note
The chairman's report will include:
```markdown
### Council Participation Notes

**Unavailable CLIs:**
- codex (not installed)

_Note: Council consensus was reached with available members._
```

---

## Scenario 3: Single-Model Mode (Testing)

### User Request
"Explain dependency injection patterns"

### Prerequisites
```bash
# Only Claude available (testing environment)
command -v claude && echo "✓ Claude"
! command -v codex && echo "⚠ Codex not available"
! command -v gemini && echo "⚠ Gemini not available"
```

### Execution
```bash
# Initialize working directory (reset if needed)
council_cleanup || true
council_init

# Single-model mode - no peer review
"${PLUGIN_ROOT}/skills/council-orchestrator/scripts/query_claude.sh" \
    "Explain dependency injection patterns" \
    > .council/stage1_claude.txt 2>&1

# Display response directly
cat .council/stage1_claude.txt

# Optional: when you no longer need this session's files, clean up
council_cleanup
```

### Expected Output
```
Council Status: Single-model mode (1/3 members)
  ✓ Claude: response collected
  ○ Codex: not available
  ○ Gemini: not available

Note: Single-model mode - no peer review or synthesis performed
Displaying Claude's response directly:

[Claude's response...]
```

---

## Scenario 4: Error Recovery - CLI Timeout

### Situation
Claude and Codex respond normally, but Gemini times out after 120 seconds.

### Output
```
┌─────────────────────────────────────────────────────────┐
│  Stage 1: Opinion Collection
└─────────────────────────────────────────────────────────┘

  ⏳ Claude: consulting...
  ⏳ Codex: consulting...
  ⏳ Gemini: consulting...

  ✓ Claude: responded (42.3s)
  ✓ Codex: responded (48.7s)
  ⏳ Gemini: still waiting... (90s)
  ⏳ Gemini: still waiting... (120s)
  ✗ Gemini: timeout after 120 seconds

Council Status: Partial failure (2/3 members responded)

Proceeding with 2 available responses...
```

### Handling
The orchestrator automatically:
1. Marks Gemini as absent
2. Proceeds with Claude + Codex
3. Includes timeout note in final report

---

## Scenario 5: Rate Limit Handling

### Situation
OpenAI Codex hits rate limit (HTTP 429)

### Output
```
Consulting OpenAI Codex...
⚠ Rate limited (429), waiting 5s...
Retry attempt 1...
⚠ Rate limited (429), waiting 10s...
✗ Codex: Rate limit exceeded after retries

Marking Codex as absent
Proceeding with Claude + Gemini...
```

### Script Behavior
```bash
# Automatic retry with exponential backoff
retry_with_backoff 2 "./scripts/query_codex.sh \"$query\"" || {
    mark_member_absent "Codex" "Rate limit exceeded"
}
```

---

## Scenario 6: Empty Response Handling

### Situation
CLI executes successfully (exit code 0) but produces no output

### Detection
```bash
validate_output ".council/stage1_codex.txt" "Codex" || {
    mark_member_absent "Codex" "Empty response"
}
```

### Output
```
  ✓ Claude: Response captured
  ⚠ Codex: Empty response (marked as absent)
  ✓ Gemini: Response captured
```

---

## Scenario 7: Input Validation Failure

### Situation
User provides input with null bytes or excessive length

### Input
```bash
# Malicious input with null byte
query=$(printf 'SELECT * FROM users\0; DROP TABLE users;')

validate_user_input "$query"
```

### Output
```
ERROR: Input contains null bytes
Aborting council session for security
```

### Prevention
```bash
# Always validate before processing
# Resolve plugin root
PLUGIN_ROOT="${COUNCIL_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CLAUDE_PROJECT_DIR}}}"
source "${PLUGIN_ROOT}/skills/council-orchestrator/scripts/council_utils.sh"
validate_user_input "$user_query" || {
    error_msg "Invalid input - council aborted"
    exit 1
}
```

---

## Scenario 8: Manual Fallback (Script Failure)

### Situation
Wrapper scripts fail; need to manually invoke CLIs

### Manual Phase 1
```bash
mkdir -p .council

# Query each CLI manually
echo "Your question" | claude chat > .council/stage1_claude.txt 2>&1
echo "Your question" | codex exec --skip-git-repo-check > .council/stage1_openai.txt 2>&1
echo "Your question" | gemini ask > .council/stage1_gemini.txt 2>&1
```

### Manual Phase 2
```bash
# Construct review prompt manually (see templates/review_prompt.txt)
cat > review_prompt.txt <<'EOF'
Review these responses:

Response A:
$(cat .council/stage1_claude.txt)

Response B:
$(cat .council/stage1_gemini.txt)

[... review instructions ...]
EOF

# Query each CLI with review prompt
cat review_prompt.txt | codex exec --skip-git-repo-check > .council/stage2_review_openai.txt
```

---

## Troubleshooting Guide

### Problem: "No council members available"

**Symptoms:**
```
ERROR: No council members available. Cannot proceed.
Required: At least Claude CLI
```

**Solution:**
```bash
# Install Claude CLI
# See: https://code.claude.com/docs/en/setup

# Verify installation
command -v claude || echo "Still not available"
```

---

### Problem: "Quorum not met"

**Symptoms:**
```
ERROR: Quorum not met: Only 1 of 2 required responses
```

**Cause:** Only 1 CLI responded, but minimum quorum is 2

**Solution:**
```bash
# Option 1: Install additional CLIs
npm install -g @openai/codex
npm install -g @google/gemini-cli

# Option 2: Lower quorum requirement (not recommended)
export COUNCIL_MIN_QUORUM=1
```

---

### Problem: "Peer review skipped"

**Symptoms:**
```
Warning: Only 1 response collected, skipping peer review
```

**Cause:** Peer review requires at least 2 responses

**Solution:**
- Ensure at least 2 CLIs are installed and working
- Check CLI authentication (API keys)
- Verify network connectivity

---

### Problem: "Empty response files"

**Symptoms:**
```
ERROR: Claude response file is empty
File: .council/stage1_claude.txt
```

**Debugging:**
```bash
# Check CLI manually
claude chat "test query"

# Check wrapper script permissions
ls -la skills/council-orchestrator/scripts/query_claude.sh

# Check wrapper script output
bash -x "${PLUGIN_ROOT}/skills/council-orchestrator/scripts/query_claude.sh" "test" 2>&1 | head -20
```

**Common Causes:**
- CLI not authenticated (missing API key)
- Network connectivity issues
- Wrapper script permissions (not executable)
- Rate limiting (check stderr output)

---

### Problem: "Chairman failed to generate report"

**Symptoms:**
```
ERROR: Chairman failed to generate report
File .council/final_report.md not found
```

**Debugging:**
```bash
# Check if chairman agent exists
ls -la agents/council-chairman.md

# Manually invoke chairman for debugging
# Review Stage 1/2 files first
ls -la .council/

# Ensure chairman has Read/Write tools available
```

**Common Causes:**
- Chairman agent not found
- Stage 1/2 files missing or corrupted
- Chairman agent has insufficient tool access
- Errors during synthesis (check logs)

---

## Performance Benchmarks

### Full Council (3 members)

| Phase | Duration | Notes |
|-------|----------|-------|
| Phase 1 (Opinion) | 15-30s | Parallel execution |
| Phase 2 (Review) | 20-40s | 3 reviews in parallel |
| Phase 3 (Synthesis) | 10-20s | Chairman processing |
| **Total** | **45-90s** | End-to-end |

### Degraded Council (2 members)

| Phase | Duration | Notes |
|-------|----------|-------|
| Phase 1 (Opinion) | 15-25s | 2 CLIs in parallel |
| Phase 2 (Review) | 15-30s | 2 reviews in parallel |
| Phase 3 (Synthesis) | 10-15s | Faster with less data |
| **Total** | **40-70s** | End-to-end |

---

## Best Practices

### ✅ Do

- Always validate user input before processing
- Check CLI status before starting council session
- Use parallel execution for Phase 1 and Phase 2
- Reset the `.council/` directory before starting a new council session (e.g., via `/council` or `council_cleanup` + `council_init`)
- Clean up the `.council/` directory when you no longer need the current session's files (e.g., via `/council-cleanup` or `council_cleanup`)
- Monitor for rate limits and implement backoff
- Include absent member notes in final report

### ❌ Don't

- Skip input validation for "trusted" sources
- Run CLIs sequentially (use parallel execution)
- Assume `.council/` contains data from multiple sessions (it should always represent the most recent run)
- Ignore rate limit errors (implement retry logic)
- Modify Stage 1/2 files during processing
- Run council without at least 1 working CLI

---

## Configuration Examples

### Custom Quorum
```bash
# Require all 3 members (strict mode)
export COUNCIL_MIN_QUORUM=3

# Accept single member (testing only)
export COUNCIL_MIN_QUORUM=1
```

### Custom Timeout
```bash
# Increase timeout for slow networks
export COUNCIL_CLI_TIMEOUT=120  # 120 seconds
```

### Custom Max Length
```bash
# Allow longer prompts
export COUNCIL_MAX_PROMPT_LENGTH=20000  # 20k characters
```

### Disable Specific Members
```bash
# Only use Claude and Gemini
config_set "enabled_members" "claude,gemini"
```

---

## Integration Examples

### Use in CI/CD Pipeline
```bash
#!/bin/bash
# .github/workflows/council-review.sh

set -euo pipefail

# Review PR changes
PR_DIFF=$(git diff origin/main...HEAD)

council_init
"${PLUGIN_ROOT}/skills/council-orchestrator/scripts/run_parallel.sh" \
    "Review this PR diff for issues: $PR_DIFF" \
    .council

# Generate report
"${PLUGIN_ROOT}/skills/council-orchestrator/scripts/run_chairman.sh" \
    "Review this PR diff" \
    .council > pr_review.md

# Post as PR comment
gh pr comment --body-file pr_review.md
```

### Automated Code Review
```bash
#!/bin/bash
# Review all changed Python files

for file in $(git diff --name-only '*.py'); do
    code=$(cat "$file")
    "${PLUGIN_ROOT}/skills/council-orchestrator/scripts/run_parallel.sh" \
        "Review this Python code for bugs and best practices: $code" \
        ".council-$file"
done
```

---

## See Also

- [SKILL.md](./SKILL.md) - Core workflow and quick start
- [REFERENCE.md](./REFERENCE.md) - Detailed implementation guide
- [SECURITY.md](./SECURITY.md) - Security best practices
- [METADATA.md](./METADATA.md) - Version and compatibility info
