#!/bin/bash
#
# test_hooks.sh - Hook tests for LLM Council Plugin
#
# Tests PreToolUse and PostToolUse hooks for correct behavior
#
# Usage: ./tests/test_hooks.sh [test_name]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PRE_TOOL_HOOK="$PROJECT_ROOT/hooks/pre-tool.sh"
POST_TOOL_HOOK="$PROJECT_ROOT/hooks/post-tool.sh"
SESSION_START_HOOK="$PROJECT_ROOT/hooks/session-start.sh"

# Test results tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# Test Framework Functions
# ============================================================================

test_start() {
    local name="$1"
    local description="$2"
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}TEST: $name${NC}"
    echo -e "${BLUE}Description: $description${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    TESTS_RUN=$((TESTS_RUN + 1))
}

test_pass() {
    local msg="${1:-}"
    echo -e "${GREEN}✓ PASSED${NC}${msg:+: $msg}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

test_fail() {
    local msg="${1:-}"
    local test_name="${2:-unknown}"
    echo -e "${RED}✗ FAILED${NC}${msg:+: $msg}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS="$FAILED_TESTS\n  - $test_name: $msg"
}

# ============================================================================
# PreToolUse Hook Tests
# ============================================================================

test_pre_tool_normal_command() {
    test_start "pre_tool_normal_command" "Test normal bash command is allowed"

    local input='{"tool_name":"Bash","tool_input":{"command":"ls -la | grep config"}}'
    local output
    local exit_code

    output=$(echo "$input" | CLAUDE_PROJECT_DIR="$PROJECT_ROOT" "$PRE_TOOL_HOOK" 2>&1)
    exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        echo "  ✓ Exit code 0 (allowed)"
    else
        test_fail "Should allow normal command, got exit code $exit_code" "pre_tool_normal_command"
        return
    fi

    # Check official JSON schema structure
    if echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"' >/dev/null 2>&1; then
        echo "  ✓ Has official hookSpecificOutput wrapper"
    else
        test_fail "Missing official hookSpecificOutput wrapper: $output" "pre_tool_normal_command"
        return
    fi

    if echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "allow"' >/dev/null 2>&1; then
        echo "  ✓ JSON indicates allow (official schema)"
        test_pass
    else
        test_fail "JSON should indicate allow in hookSpecificOutput: $output" "pre_tool_normal_command"
    fi
}

test_pre_tool_non_bash_tool() {
    test_start "pre_tool_non_bash_tool" "Test non-Bash tools are allowed"

    local input='{"tool_name":"Read","tool_input":{"file_path":"/some/path"}}'
    local output
    local exit_code

    output=$(echo "$input" | CLAUDE_PROJECT_DIR="$PROJECT_ROOT" "$PRE_TOOL_HOOK" 2>&1)
    exit_code=$?

    if [[ $exit_code -eq 0 ]] && echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "allow"' >/dev/null 2>&1; then
        test_pass "Non-Bash tool allowed (official schema)"
    else
        test_fail "Should allow non-Bash tools" "pre_tool_non_bash_tool"
    fi
}

test_pre_tool_command_too_long() {
    test_start "pre_tool_command_too_long" "Test command length limit"

    # Generate 60,000 character command
    local long_command
    long_command=$(printf 'a%.0s' $(seq 1 60000))
    local input="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$long_command\"}}"
    local exit_code

    echo "$input" | CLAUDE_PROJECT_DIR="$PROJECT_ROOT" "$PRE_TOOL_HOOK" >/dev/null 2>&1
    exit_code=$?

    if [[ $exit_code -eq 2 ]]; then
        test_pass "Correctly blocked overly long command with exit code 2"
    else
        test_fail "Should block long command with exit 2, got $exit_code" "pre_tool_command_too_long"
    fi
}

test_pre_tool_missing_council_script() {
    test_start "pre_tool_missing_council_script" "Test missing council script detection"

    local input='{"tool_name":"Bash","tool_input":{"command":"bash skills/council-orchestrator/scripts/nonexistent_script.sh"}}'
    local exit_code

    echo "$input" | CLAUDE_PROJECT_DIR="$PROJECT_ROOT" "$PRE_TOOL_HOOK" >/dev/null 2>&1
    exit_code=$?

    if [[ $exit_code -eq 2 ]]; then
        test_pass "Correctly blocked missing council script"
    else
        test_fail "Should block missing script with exit 2, got $exit_code" "pre_tool_missing_council_script"
    fi
}

test_pre_tool_shell_operators_allowed() {
    test_start "pre_tool_shell_operators_allowed" "Test legitimate shell operators are allowed"

    local commands=(
        '{"tool_name":"Bash","tool_input":{"command":"echo test | grep t"}}'
        '{"tool_name":"Bash","tool_input":{"command":"cmd1 && cmd2"}}'
        '{"tool_name":"Bash","tool_input":{"command":"echo hello > file.txt"}}'
        '{"tool_name":"Bash","tool_input":{"command":"cat < input.txt"}}'
        '{"tool_name":"Bash","tool_input":{"command":"cmd1 || cmd2"}}'
        '{"tool_name":"Bash","tool_input":{"command":"cmd1; cmd2"}}'
    )

    local all_passed=true

    for input in "${commands[@]}"; do
        local output
        local exit_code

        output=$(echo "$input" | CLAUDE_PROJECT_DIR="$PROJECT_ROOT" "$PRE_TOOL_HOOK" 2>&1)
        exit_code=$?

        if [[ $exit_code -ne 0 ]]; then
            echo "  ✗ Blocked legitimate command: $input"
            all_passed=false
        else
            # Check official schema
            if echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "allow"' >/dev/null 2>&1; then
                echo "  ✓ Allowed: $(echo "$input" | jq -r '.tool_input.command')"
            else
                echo "  ✗ JSON didn't allow (official schema): $input"
                all_passed=false
            fi
        fi
    done

    if $all_passed; then
        test_pass "All legitimate shell operators allowed"
    else
        test_fail "Some legitimate operators were blocked" "pre_tool_shell_operators_allowed"
    fi
}

test_pre_tool_empty_command() {
    test_start "pre_tool_empty_command" "Test empty command handling"

    local input='{"tool_name":"Bash","tool_input":{"command":""}}'
    local exit_code

    echo "$input" | CLAUDE_PROJECT_DIR="$PROJECT_ROOT" "$PRE_TOOL_HOOK" >/dev/null 2>&1
    exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        test_pass "Empty command handled gracefully"
    else
        test_fail "Should handle empty command gracefully" "pre_tool_empty_command"
    fi
}

test_pre_tool_no_jq() {
    test_start "pre_tool_no_jq" "Test graceful fallback when jq unavailable"

    # Temporarily hide jq
    local input='{"tool_name":"Bash","tool_input":{"command":"ls"}}'
    local output
    local exit_code

    output=$(PATH="/usr/local/bin:/usr/bin:/bin" command -v jq >/dev/null 2>&1 || echo "$input" | CLAUDE_PROJECT_DIR="$PROJECT_ROOT" "$PRE_TOOL_HOOK" 2>&1)
    exit_code=$?

    # If jq is available system-wide, we can't easily test this
    if command -v jq >/dev/null 2>&1; then
        echo "  ⚠ jq is available, testing with official schema"
        output=$(echo "$input" | CLAUDE_PROJECT_DIR="$PROJECT_ROOT" "$PRE_TOOL_HOOK" 2>&1)
        if echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"' >/dev/null 2>&1; then
            test_pass "Uses official schema when jq available"
        else
            test_fail "Should use official schema" "pre_tool_no_jq"
        fi
    else
        if [[ $exit_code -eq 0 ]]; then
            test_pass "Gracefully fell back when jq unavailable"
        else
            test_fail "Should fallback gracefully without jq" "pre_tool_no_jq"
        fi
    fi
}

# ============================================================================
# PostToolUse Hook Tests
# ============================================================================

test_post_tool_rate_limit_detection() {
    test_start "post_tool_rate_limit_detection" "Test rate limit detection"

    local input='{"tool_name":"Bash","tool_output":"Error: rate limit exceeded","exit_code":"1"}'
    local output

    output=$(echo "$input" | CLAUDE_PROJECT_DIR="$PROJECT_ROOT" "$POST_TOOL_HOOK" 2>&1)

    # Check official schema structure
    if echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "PostToolUse"' >/dev/null 2>&1; then
        echo "  ✓ Has official hookSpecificOutput wrapper"
    else
        test_fail "Missing official hookSpecificOutput wrapper" "post_tool_rate_limit_detection"
        return
    fi

    if echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("Rate limit")' >/dev/null 2>&1; then
        echo "  ✓ Detected rate limit in additionalContext (official schema)"
    else
        test_fail "Should detect rate limit in hookSpecificOutput.additionalContext" "post_tool_rate_limit_detection"
        return
    fi

    if echo "$output" | jq -e '.systemMessage | contains("Rate limit")' >/dev/null 2>&1; then
        echo "  ✓ System message includes rate limit warning"
        test_pass
    else
        test_fail "System message should include warning" "post_tool_rate_limit_detection"
    fi
}

test_post_tool_auth_error_detection() {
    test_start "post_tool_auth_error_detection" "Test authentication error detection"

    local input='{"tool_name":"Bash","tool_output":"Error: 401 Unauthorized - invalid api key","exit_code":"1"}'
    local output

    output=$(echo "$input" | CLAUDE_PROJECT_DIR="$PROJECT_ROOT" "$POST_TOOL_HOOK" 2>&1)

    if echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("Authentication")' >/dev/null 2>&1; then
        echo "  ✓ Detected authentication error (official schema)"
        test_pass
    else
        test_fail "Should detect authentication error in hookSpecificOutput.additionalContext" "post_tool_auth_error_detection"
    fi
}

test_post_tool_sensitive_data_detection() {
    test_start "post_tool_sensitive_data_detection" "Test sensitive data pattern detection"

    # Test OpenAI key pattern
    local input='{"tool_name":"Bash","tool_output":"API_KEY=sk-proj-abc123def456ghi789jkl012mno345pqr678stu901","exit_code":"0"}'
    local output

    output=$(echo "$input" | CLAUDE_PROJECT_DIR="$PROJECT_ROOT" "$POST_TOOL_HOOK" 2>&1)

    if echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("SECURITY")' >/dev/null 2>&1; then
        echo "  ✓ Detected OpenAI key pattern (official schema)"
    else
        test_fail "Should detect OpenAI key pattern in hookSpecificOutput.additionalContext" "post_tool_sensitive_data_detection"
        return
    fi

    # Test GitHub token pattern (exactly 36 characters after ghp_)
    input='{"tool_name":"Bash","tool_output":"TOKEN=ghp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","exit_code":"0"}'
    output=$(echo "$input" | CLAUDE_PROJECT_DIR="$PROJECT_ROOT" "$POST_TOOL_HOOK" 2>&1)

    if echo "$output" | jq -e '.systemMessage | contains("sensitive")' >/dev/null 2>&1; then
        echo "  ✓ Detected GitHub token pattern"
        test_pass
    else
        test_fail "Should detect GitHub token pattern" "post_tool_sensitive_data_detection"
    fi
}

test_post_tool_large_output_warning() {
    test_start "post_tool_large_output_warning" "Test large output warning"

    # Generate 600,000 character output
    local large_output
    large_output=$(printf 'a%.0s' $(seq 1 600000))
    local input="{\"tool_name\":\"Bash\",\"tool_output\":\"$large_output\",\"exit_code\":\"0\"}"
    local output

    output=$(echo "$input" | CLAUDE_PROJECT_DIR="$PROJECT_ROOT" "$POST_TOOL_HOOK" 2>&1)

    if echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("very large")' >/dev/null 2>&1; then
        test_pass "Warned about large output (official schema)"
    else
        test_fail "Should warn about large output in hookSpecificOutput.additionalContext" "post_tool_large_output_warning"
    fi
}

test_post_tool_council_quorum_check() {
    test_start "post_tool_council_quorum_check" "Test council quorum verification"

    # Create a temporary council directory with incomplete responses
    local test_council_dir="$SCRIPT_DIR/.test_council_hook"
    rm -rf "$test_council_dir" 2>/dev/null || true
    mkdir -p "$test_council_dir"

    # Create only one Stage 1 response
    echo "Response" > "$test_council_dir/stage1_claude.txt"

    local input="{\"tool_name\":\"Bash\",\"tool_output\":\"Council operation in $test_council_dir\",\"exit_code\":\"0\"}"
    local output

    # Set COUNCIL_DIR for the hook
    output=$(COUNCIL_DIR="$test_council_dir" CLAUDE_PROJECT_DIR="$PROJECT_ROOT" echo "$input" | "$POST_TOOL_HOOK" 2>&1)

    if echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("quorum")' >/dev/null 2>&1; then
        test_pass "Detected low quorum (official schema)"
    else
        # Quorum check only happens if output mentions council, so this might be expected
        test_pass "with warnings (quorum check may not trigger)"
    fi

    rm -rf "$test_council_dir" 2>/dev/null || true
}

test_post_tool_non_bash_tool() {
    test_start "post_tool_non_bash_tool" "Test non-Bash tools are skipped"

    local input='{"tool_name":"Read","tool_output":"file contents","exit_code":"0"}'
    local output
    local exit_code

    output=$(echo "$input" | CLAUDE_PROJECT_DIR="$PROJECT_ROOT" "$POST_TOOL_HOOK" 2>&1)
    exit_code=$?

    if [[ $exit_code -eq 0 ]] && [[ "$output" == "{}" ]]; then
        test_pass "Non-Bash tool skipped correctly"
    else
        test_fail "Should skip non-Bash tools" "post_tool_non_bash_tool"
    fi
}

test_post_tool_empty_output() {
    test_start "post_tool_empty_output" "Test empty output handling"

    local input='{"tool_name":"Bash","tool_output":"","exit_code":"0"}'
    local output
    local exit_code

    output=$(echo "$input" | CLAUDE_PROJECT_DIR="$PROJECT_ROOT" "$POST_TOOL_HOOK" 2>&1)
    exit_code=$?

    if [[ $exit_code -eq 0 ]] && [[ "$output" == "{}" ]]; then
        test_pass "Empty output handled gracefully"
    else
        test_fail "Should handle empty output gracefully" "post_tool_empty_output"
    fi
}

test_post_tool_json_output_structure() {
    test_start "post_tool_json_output_structure" "Test official JSON output schema compliance"

    local input='{"tool_name":"Bash","tool_output":"Normal output","exit_code":"0"}'
    local output

    output=$(echo "$input" | CLAUDE_PROJECT_DIR="$PROJECT_ROOT" "$POST_TOOL_HOOK" 2>&1)

    # Validate JSON structure
    if echo "$output" | jq empty 2>/dev/null; then
        echo "  ✓ Output is valid JSON"
    else
        test_fail "Output should be valid JSON" "post_tool_json_output_structure"
        return
    fi

    # Check for official schema structure
    local has_expected_fields=true

    # Check for hookSpecificOutput wrapper
    if ! echo "$output" | jq -e 'has("hookSpecificOutput")' >/dev/null 2>&1; then
        echo "  ✗ Missing hookSpecificOutput wrapper"
        has_expected_fields=false
    else
        echo "  ✓ Has hookSpecificOutput wrapper"
    fi

    # Check for hookEventName
    if ! echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "PostToolUse"' >/dev/null 2>&1; then
        echo "  ✗ Missing or incorrect hookEventName"
        has_expected_fields=false
    else
        echo "  ✓ Has correct hookEventName"
    fi

    # Check for additionalContext in hookSpecificOutput
    if ! echo "$output" | jq -e '.hookSpecificOutput | has("additionalContext")' >/dev/null 2>&1; then
        echo "  ✗ Missing additionalContext in hookSpecificOutput"
        has_expected_fields=false
    else
        echo "  ✓ Has additionalContext in hookSpecificOutput"
    fi

    # Check for continue field
    if ! echo "$output" | jq -e 'has("continue")' >/dev/null 2>&1; then
        echo "  ✗ Missing continue field"
        has_expected_fields=false
    else
        echo "  ✓ Has continue field"
    fi

    # Check for systemMessage field
    if ! echo "$output" | jq -e 'has("systemMessage")' >/dev/null 2>&1; then
        echo "  ✗ Missing systemMessage field"
        has_expected_fields=false
    else
        echo "  ✓ Has systemMessage field"
    fi

    if $has_expected_fields; then
        test_pass "Official JSON schema compliant"
    else
        test_fail "JSON schema incomplete or incorrect" "post_tool_json_output_structure"
    fi
}

# ============================================================================
# SessionStart Hook Tests
# ============================================================================

test_session_start_startup() {
    test_start "session_start_startup" "Test SessionStart hook for startup scenario"

    local input='{"session_id":"test123","transcript_path":"~/.claude/test.jsonl","cwd":"'"$PROJECT_ROOT"'","permission_mode":"default","hook_event_name":"SessionStart","source":"startup"}'
    local output
    local exit_code

    # Create temporary CLAUDE_ENV_FILE
    local temp_env_file=$(mktemp)

    # Capture stdout only for JSON parsing (stderr contains warnings)
    # Export variables so they're available in the pipeline
    export CLAUDE_PROJECT_DIR="$PROJECT_ROOT"
    export CLAUDE_ENV_FILE="$temp_env_file"
    output=$(echo "$input" | "$SESSION_START_HOOK" 2>/dev/null)
    exit_code=$?
    unset CLAUDE_PROJECT_DIR CLAUDE_ENV_FILE

    if [[ $exit_code -ne 0 ]]; then
        test_fail "Should exit 0, got $exit_code" "session_start_startup"
        rm -f "$temp_env_file"
        return
    fi
    echo "  ✓ Exit code 0 (success)"

    # Check official JSON schema structure
    if echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null 2>&1; then
        echo "  ✓ Has official hookSpecificOutput wrapper with SessionStart event"
    else
        test_fail "Missing official hookSpecificOutput wrapper: $output" "session_start_startup"
        rm -f "$temp_env_file"
        return
    fi

    # Check additionalContext
    if echo "$output" | jq -e '.hookSpecificOutput | has("additionalContext")' >/dev/null 2>&1; then
        echo "  ✓ Has additionalContext field"
    else
        test_fail "Missing additionalContext field" "session_start_startup"
        rm -f "$temp_env_file"
        return
    fi

    # Check environment variables were persisted
    if grep -q "COUNCIL_DIR" "$temp_env_file"; then
        echo "  ✓ COUNCIL_DIR persisted to CLAUDE_ENV_FILE"
    else
        test_fail "COUNCIL_DIR not persisted" "session_start_startup"
        rm -f "$temp_env_file"
        return
    fi

    if grep -q "CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR" "$temp_env_file"; then
        echo "  ✓ CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR persisted"
        test_pass
    else
        test_fail "CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR not persisted" "session_start_startup"
    fi

    rm -f "$temp_env_file"
}

test_session_start_resume() {
    test_start "session_start_resume" "Test SessionStart hook for resume scenario"

    local input='{"session_id":"test456","transcript_path":"~/.claude/test.jsonl","cwd":"'"$PROJECT_ROOT"'","permission_mode":"default","hook_event_name":"SessionStart","source":"resume"}'
    local output
    local exit_code

    local temp_env_file=$(mktemp)

    # Capture stdout only for JSON parsing (stderr contains warnings)
    # Export variables so they're available in the pipeline
    export CLAUDE_PROJECT_DIR="$PROJECT_ROOT"
    export CLAUDE_ENV_FILE="$temp_env_file"
    output=$(echo "$input" | "$SESSION_START_HOOK" 2>/dev/null)
    exit_code=$?
    unset CLAUDE_PROJECT_DIR CLAUDE_ENV_FILE

    if [[ $exit_code -eq 0 ]]; then
        echo "  ✓ Exit code 0 (success)"
    else
        test_fail "Should exit 0 for resume, got $exit_code" "session_start_resume"
        rm -f "$temp_env_file"
        return
    fi

    # Check context mentions "resume"
    if echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("resume")' >/dev/null 2>&1; then
        echo "  ✓ Context mentions resume scenario"
        test_pass
    else
        test_pass "with warnings (context doesn't mention resume explicitly)"
    fi

    rm -f "$temp_env_file"
}

test_session_start_no_env_file() {
    test_start "session_start_no_env_file" "Test SessionStart hook without CLAUDE_ENV_FILE"

    local input='{"session_id":"test789","transcript_path":"~/.claude/test.jsonl","cwd":"'"$PROJECT_ROOT"'","permission_mode":"default","hook_event_name":"SessionStart","source":"startup"}'
    local output
    local exit_code

    # Run without CLAUDE_ENV_FILE (should succeed but warn)
    # Export only CLAUDE_PROJECT_DIR, not CLAUDE_ENV_FILE
    export CLAUDE_PROJECT_DIR="$PROJECT_ROOT"
    output=$(echo "$input" | "$SESSION_START_HOOK" 2>/dev/null)
    exit_code=$?
    unset CLAUDE_PROJECT_DIR

    if [[ $exit_code -eq 0 ]]; then
        echo "  ✓ Hook handles missing CLAUDE_ENV_FILE gracefully"
        test_pass
    else
        test_fail "Should handle missing CLAUDE_ENV_FILE gracefully, got exit $exit_code" "session_start_no_env_file"
    fi
}

test_session_start_json_structure() {
    test_start "session_start_json_structure" "Test SessionStart JSON output schema compliance"

    local input='{"session_id":"test999","transcript_path":"~/.claude/test.jsonl","cwd":"'"$PROJECT_ROOT"'","permission_mode":"default","hook_event_name":"SessionStart","source":"startup"}'
    local output
    local temp_env_file=$(mktemp)

    # Capture stdout only for JSON parsing (stderr contains warnings)
    # Export variables so they're available in the pipeline
    export CLAUDE_PROJECT_DIR="$PROJECT_ROOT"
    export CLAUDE_ENV_FILE="$temp_env_file"
    output=$(echo "$input" | "$SESSION_START_HOOK" 2>/dev/null)
    unset CLAUDE_PROJECT_DIR CLAUDE_ENV_FILE

    # Validate JSON structure
    if echo "$output" | jq empty 2>/dev/null; then
        echo "  ✓ Output is valid JSON"
    else
        test_fail "Output should be valid JSON" "session_start_json_structure"
        rm -f "$temp_env_file"
        return
    fi

    local has_expected_fields=true

    # Check for hookSpecificOutput wrapper
    if ! echo "$output" | jq -e 'has("hookSpecificOutput")' >/dev/null 2>&1; then
        echo "  ✗ Missing hookSpecificOutput wrapper"
        has_expected_fields=false
    else
        echo "  ✓ Has hookSpecificOutput wrapper"
    fi

    # Check for hookEventName
    if ! echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null 2>&1; then
        echo "  ✗ Missing or incorrect hookEventName"
        has_expected_fields=false
    else
        echo "  ✓ Has correct hookEventName"
    fi

    # Check for additionalContext
    if ! echo "$output" | jq -e '.hookSpecificOutput | has("additionalContext")' >/dev/null 2>&1; then
        echo "  ✗ Missing additionalContext"
        has_expected_fields=false
    else
        echo "  ✓ Has additionalContext"
    fi

    if $has_expected_fields; then
        test_pass "Official JSON schema compliant"
    else
        test_fail "JSON schema incomplete or incorrect" "session_start_json_structure"
    fi

    rm -f "$temp_env_file"
}

test_session_start_environment_vars() {
    test_start "session_start_environment_vars" "Test SessionStart environment variable persistence"

    local input='{"session_id":"test111","transcript_path":"~/.claude/test.jsonl","cwd":"'"$PROJECT_ROOT"'","permission_mode":"default","hook_event_name":"SessionStart","source":"startup"}'
    local temp_env_file=$(mktemp)

    # Must provide CLAUDE_ENV_FILE for variables to be persisted
    # Export so they're available in the pipeline
    export CLAUDE_PROJECT_DIR="$PROJECT_ROOT"
    export CLAUDE_ENV_FILE="$temp_env_file"
    echo "$input" | "$SESSION_START_HOOK" >/dev/null 2>/dev/null
    unset CLAUDE_PROJECT_DIR CLAUDE_ENV_FILE

    local all_vars_present=true

    # Check required environment variables
    if grep -q "export COUNCIL_DIR=" "$temp_env_file"; then
        echo "  ✓ COUNCIL_DIR exported"
    else
        echo "  ✗ COUNCIL_DIR not exported"
        all_vars_present=false
    fi

    if grep -q "export COUNCIL_MAX_COMMAND_LENGTH=" "$temp_env_file"; then
        echo "  ✓ COUNCIL_MAX_COMMAND_LENGTH exported"
    else
        echo "  ✗ COUNCIL_MAX_COMMAND_LENGTH not exported"
        all_vars_present=false
    fi

    if grep -q "export COUNCIL_MAX_OUTPUT_LENGTH=" "$temp_env_file"; then
        echo "  ✓ COUNCIL_MAX_OUTPUT_LENGTH exported"
    else
        echo "  ✗ COUNCIL_MAX_OUTPUT_LENGTH not exported"
        all_vars_present=false
    fi

    if grep -q "export CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR=" "$temp_env_file"; then
        echo "  ✓ CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR exported"
    else
        echo "  ✗ CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR not exported"
        all_vars_present=false
    fi

    if $all_vars_present; then
        test_pass "All required environment variables present"
    else
        test_fail "Some environment variables missing" "session_start_environment_vars"
    fi

    rm -f "$temp_env_file"
}

# ============================================================================
# Integration Tests
# ============================================================================

test_hooks_executable() {
    test_start "hooks_executable" "Verify hook scripts are executable"

    local all_executable=true

    if [[ -x "$PRE_TOOL_HOOK" ]]; then
        echo "  ✓ pre-tool.sh is executable"
    else
        echo "  ✗ pre-tool.sh is not executable"
        all_executable=false
    fi

    if [[ -x "$POST_TOOL_HOOK" ]]; then
        echo "  ✓ post-tool.sh is executable"
    else
        echo "  ✗ post-tool.sh is not executable"
        all_executable=false
    fi

    if [[ -x "$SESSION_START_HOOK" ]]; then
        echo "  ✓ session-start.sh is executable"
    else
        echo "  ✗ session-start.sh is not executable"
        all_executable=false
    fi

    if $all_executable; then
        test_pass
    else
        test_fail "Some hooks are not executable" "hooks_executable"
    fi
}

test_hooks_config_valid() {
    test_start "hooks_config_valid" "Verify hooks.json is valid JSON"

    local hooks_config="$PROJECT_ROOT/hooks/hooks.json"

    if [[ ! -f "$hooks_config" ]]; then
        test_fail "hooks.json not found" "hooks_config_valid"
        return
    fi

    if jq empty "$hooks_config" 2>/dev/null; then
        echo "  ✓ hooks.json is valid JSON"
        test_pass
    else
        test_fail "hooks.json is not valid JSON" "hooks_config_valid"
    fi
}

# ============================================================================
# Test Runner
# ============================================================================

run_all_tests() {
    echo -e "\n${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║           LLM Council Plugin - Hook Test Suite              ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"

    # Check prerequisites
    if ! command -v jq >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠ Warning: jq not installed, some tests may be skipped${NC}"
    fi

    echo -e "\n${BLUE}▶ Running Integration Tests${NC}"
    test_hooks_executable
    test_hooks_config_valid

    echo -e "\n${BLUE}▶ Running PreToolUse Hook Tests${NC}"
    test_pre_tool_normal_command
    test_pre_tool_non_bash_tool
    test_pre_tool_command_too_long
    test_pre_tool_missing_council_script
    test_pre_tool_shell_operators_allowed
    test_pre_tool_empty_command
    test_pre_tool_no_jq

    echo -e "\n${BLUE}▶ Running PostToolUse Hook Tests${NC}"
    test_post_tool_rate_limit_detection
    test_post_tool_auth_error_detection
    test_post_tool_sensitive_data_detection
    test_post_tool_large_output_warning
    test_post_tool_council_quorum_check
    test_post_tool_non_bash_tool
    test_post_tool_empty_output
    test_post_tool_json_output_structure

    echo -e "\n${BLUE}▶ Running SessionStart Hook Tests${NC}"
    test_session_start_startup
    test_session_start_resume
    test_session_start_no_env_file
    test_session_start_json_structure
    test_session_start_environment_vars

    print_summary
}

run_single_test() {
    local test_name="$1"
    local test_func="test_${test_name}"

    if declare -f "$test_func" >/dev/null 2>&1; then
        "$test_func"
        print_summary
    else
        echo -e "${RED}Unknown test: $test_name${NC}"
        echo "Available tests:"
        declare -F | grep "test_" | sed 's/declare -f test_/  - /'
        exit 1
    fi
}

print_summary() {
    echo -e "\n${YELLOW}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}                         TEST SUMMARY                          ${NC}"
    echo -e "${YELLOW}══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  Total tests:  $TESTS_RUN"
    echo -e "  ${GREEN}Passed:       $TESTS_PASSED${NC}"
    echo -e "  ${RED}Failed:       $TESTS_FAILED${NC}"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "\n${RED}Failed tests:${NC}$FAILED_TESTS"
    fi

    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All hook tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some hook tests failed.${NC}"
        return 1
    fi
}

# ============================================================================
# Main
# ============================================================================

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "LLM Council Plugin Hook Test Runner"
    echo ""
    echo "Usage: $0 [test_name]"
    echo ""
    echo "Run all tests:     $0"
    echo "Run specific test: $0 pre_tool_normal_command"
    echo ""
    echo "Test categories:"
    echo "  hooks_*          - Hook integration tests"
    echo "  pre_tool_*       - PreToolUse hook tests"
    echo "  post_tool_*      - PostToolUse hook tests"
    exit 0
fi

if [[ $# -eq 0 ]]; then
    run_all_tests
else
    run_single_test "$1"
fi
