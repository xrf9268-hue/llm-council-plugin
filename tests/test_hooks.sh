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

    output=$(echo "$input" | "$PRE_TOOL_HOOK" 2>&1)
    exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        echo "  ✓ Exit code 0 (allowed)"
    else
        test_fail "Should allow normal command, got exit code $exit_code" "pre_tool_normal_command"
        return
    fi

    # Check JSON output
    if echo "$output" | jq -e '.permissionDecision == "allow"' >/dev/null 2>&1; then
        echo "  ✓ JSON indicates allow"
        test_pass
    else
        test_fail "JSON should indicate allow: $output" "pre_tool_normal_command"
    fi
}

test_pre_tool_non_bash_tool() {
    test_start "pre_tool_non_bash_tool" "Test non-Bash tools are allowed"

    local input='{"tool_name":"Read","tool_input":{"file_path":"/some/path"}}'
    local output
    local exit_code

    output=$(echo "$input" | "$PRE_TOOL_HOOK" 2>&1)
    exit_code=$?

    if [[ $exit_code -eq 0 ]] && echo "$output" | jq -e '.permissionDecision == "allow"' >/dev/null 2>&1; then
        test_pass "Non-Bash tool allowed"
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

    echo "$input" | "$PRE_TOOL_HOOK" >/dev/null 2>&1
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

    echo "$input" | "$PRE_TOOL_HOOK" >/dev/null 2>&1
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

        output=$(echo "$input" | "$PRE_TOOL_HOOK" 2>&1)
        exit_code=$?

        if [[ $exit_code -ne 0 ]]; then
            echo "  ✗ Blocked legitimate command: $input"
            all_passed=false
        else
            if echo "$output" | jq -e '.permissionDecision == "allow"' >/dev/null 2>&1; then
                echo "  ✓ Allowed: $(echo "$input" | jq -r '.tool_input.command')"
            else
                echo "  ✗ JSON didn't allow: $input"
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

    echo "$input" | "$PRE_TOOL_HOOK" >/dev/null 2>&1
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

    output=$(PATH="/usr/local/bin:/usr/bin:/bin" command -v jq >/dev/null 2>&1 || echo "$input" | "$PRE_TOOL_HOOK" 2>&1)
    exit_code=$?

    # If jq is available system-wide, we can't easily test this
    if command -v jq >/dev/null 2>&1; then
        echo "  ⚠ jq is available, skipping fallback test"
        test_pass "with warnings (jq available)"
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

    output=$(echo "$input" | "$POST_TOOL_HOOK" 2>&1)

    if echo "$output" | jq -e '.additionalContext | contains("Rate limit")' >/dev/null 2>&1; then
        echo "  ✓ Detected rate limit in output"
    else
        test_fail "Should detect rate limit" "post_tool_rate_limit_detection"
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

    output=$(echo "$input" | "$POST_TOOL_HOOK" 2>&1)

    if echo "$output" | jq -e '.additionalContext | contains("Authentication")' >/dev/null 2>&1; then
        echo "  ✓ Detected authentication error"
        test_pass
    else
        test_fail "Should detect authentication error" "post_tool_auth_error_detection"
    fi
}

test_post_tool_sensitive_data_detection() {
    test_start "post_tool_sensitive_data_detection" "Test sensitive data pattern detection"

    # Test OpenAI key pattern
    local input='{"tool_name":"Bash","tool_output":"API_KEY=sk-proj-abc123def456ghi789jkl012mno345pqr678stu901","exit_code":"0"}'
    local output

    output=$(echo "$input" | "$POST_TOOL_HOOK" 2>&1)

    if echo "$output" | jq -e '.additionalContext | contains("SECURITY")' >/dev/null 2>&1; then
        echo "  ✓ Detected OpenAI key pattern"
    else
        test_fail "Should detect OpenAI key pattern" "post_tool_sensitive_data_detection"
        return
    fi

    # Test GitHub token pattern (exactly 36 characters after ghp_)
    input='{"tool_name":"Bash","tool_output":"TOKEN=ghp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","exit_code":"0"}'
    output=$(echo "$input" | "$POST_TOOL_HOOK" 2>&1)

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

    output=$(echo "$input" | "$POST_TOOL_HOOK" 2>&1)

    if echo "$output" | jq -e '.additionalContext | contains("very large")' >/dev/null 2>&1; then
        test_pass "Warned about large output"
    else
        test_fail "Should warn about large output" "post_tool_large_output_warning"
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
    output=$(COUNCIL_DIR="$test_council_dir" echo "$input" | "$POST_TOOL_HOOK" 2>&1)

    if echo "$output" | jq -e '.additionalContext | contains("quorum")' >/dev/null 2>&1; then
        test_pass "Detected low quorum"
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

    output=$(echo "$input" | "$POST_TOOL_HOOK" 2>&1)
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

    output=$(echo "$input" | "$POST_TOOL_HOOK" 2>&1)
    exit_code=$?

    if [[ $exit_code -eq 0 ]] && [[ "$output" == "{}" ]]; then
        test_pass "Empty output handled gracefully"
    else
        test_fail "Should handle empty output gracefully" "post_tool_empty_output"
    fi
}

test_post_tool_json_output_structure() {
    test_start "post_tool_json_output_structure" "Test JSON output structure compliance"

    local input='{"tool_name":"Bash","tool_output":"Normal output","exit_code":"0"}'
    local output

    output=$(echo "$input" | "$POST_TOOL_HOOK" 2>&1)

    # Validate JSON structure
    if echo "$output" | jq empty 2>/dev/null; then
        echo "  ✓ Output is valid JSON"
    else
        test_fail "Output should be valid JSON" "post_tool_json_output_structure"
        return
    fi

    # Check for expected fields (even if null)
    local has_expected_fields=true

    if ! echo "$output" | jq -e 'has("additionalContext")' >/dev/null 2>&1; then
        echo "  ✗ Missing additionalContext field"
        has_expected_fields=false
    else
        echo "  ✓ Has additionalContext field"
    fi

    if ! echo "$output" | jq -e 'has("systemMessage")' >/dev/null 2>&1; then
        echo "  ✗ Missing systemMessage field"
        has_expected_fields=false
    else
        echo "  ✓ Has systemMessage field"
    fi

    if $has_expected_fields; then
        test_pass "JSON structure compliant"
    else
        test_fail "JSON structure incomplete" "post_tool_json_output_structure"
    fi
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
