#!/bin/bash
#
# diagnose-cwd-reset.sh - Comprehensive diagnostic for "Shell cwd was reset" issue
#
# This script helps diagnose whether the SessionStart hook is working correctly
# and whether the CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR environment variable
# is being set properly.
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "================================================================"
echo "  LLM Council Plugin - 'Shell cwd was reset' Diagnostic Tool"
echo "================================================================"
echo ""

# Step 1: Locate cached plugin
echo -e "${BLUE}Step 1: Locating cached plugin installation...${NC}"
echo ""

CACHE_DIRS=(
    "$HOME/.claude/plugins/cache/llm-council-plugin"
    "$HOME/.config/claude/plugins/cache/llm-council-plugin"
    "/Users/$USER/.claude/plugins/cache/llm-council-plugin"
)

CACHED_PLUGIN=""
for dir in "${CACHE_DIRS[@]}"; do
    if [[ -d "$dir" ]]; then
        CACHED_PLUGIN="$dir"
        echo -e "${GREEN}✓ Found cached plugin at: $CACHED_PLUGIN${NC}"
        break
    fi
done

if [[ -z "$CACHED_PLUGIN" ]]; then
    echo -e "${RED}✗ No cached plugin found. Plugin may not be installed.${NC}"
    echo ""
    echo "Install the plugin with:"
    echo "  claude plugin install $(pwd)"
    exit 1
fi

echo ""

# Step 2: Check if SessionStart hook exists in cached plugin
echo -e "${BLUE}Step 2: Checking SessionStart hook installation...${NC}"
echo ""

SESSION_START_HOOK="$CACHED_PLUGIN/hooks/session-start.sh"
HOOKS_JSON="$CACHED_PLUGIN/hooks/hooks.json"

if [[ ! -f "$SESSION_START_HOOK" ]]; then
    echo -e "${RED}✗ SessionStart hook NOT FOUND at: $SESSION_START_HOOK${NC}"
    echo ""
    echo -e "${YELLOW}ROOT CAUSE IDENTIFIED: Your cached plugin does not have the SessionStart hook.${NC}"
    echo ""
    echo "This means you're running an OLD VERSION of the plugin from before PR #16."
    echo ""
    echo "SOLUTION: Reinstall the plugin from the latest version:"
    echo "  1. Remove cached plugin:   rm -rf '$CACHED_PLUGIN'"
    echo "  2. Reinstall from latest:  claude plugin install $(pwd)"
    echo ""
    exit 1
else
    echo -e "${GREEN}✓ SessionStart hook exists: $SESSION_START_HOOK${NC}"

    if [[ -x "$SESSION_START_HOOK" ]]; then
        echo -e "${GREEN}✓ SessionStart hook is executable${NC}"
    else
        echo -e "${RED}✗ SessionStart hook is NOT executable${NC}"
        echo "  Fix with: chmod +x '$SESSION_START_HOOK'"
    fi
fi

echo ""

# Step 3: Check hooks.json registration
echo -e "${BLUE}Step 3: Verifying SessionStart hook registration...${NC}"
echo ""

if [[ ! -f "$HOOKS_JSON" ]]; then
    echo -e "${RED}✗ hooks.json not found at: $HOOKS_JSON${NC}"
    exit 1
fi

if grep -q '"SessionStart"' "$HOOKS_JSON"; then
    echo -e "${GREEN}✓ SessionStart hook is registered in hooks.json${NC}"

    # Check for required matchers
    if grep -q '"matcher".*:.*"startup"' "$HOOKS_JSON"; then
        echo -e "${GREEN}  ✓ Registered for 'startup' matcher${NC}"
    else
        echo -e "${YELLOW}  ⚠ NOT registered for 'startup' matcher${NC}"
    fi

    if grep -q '"matcher".*:.*"resume"' "$HOOKS_JSON"; then
        echo -e "${GREEN}  ✓ Registered for 'resume' matcher${NC}"
    else
        echo -e "${YELLOW}  ⚠ NOT registered for 'resume' matcher${NC}"
    fi
else
    echo -e "${RED}✗ SessionStart hook is NOT registered in hooks.json${NC}"
    echo ""
    echo -e "${YELLOW}ROOT CAUSE: hooks.json is outdated.${NC}"
    echo "Reinstall the plugin to fix this."
fi

echo ""

# Step 4: Test SessionStart hook execution
echo -e "${BLUE}Step 4: Testing SessionStart hook execution...${NC}"
echo ""

# Create a temporary file to simulate CLAUDE_ENV_FILE
TEMP_ENV=$(mktemp)
trap "rm -f $TEMP_ENV" EXIT

# Simulate SessionStart hook input
TEST_INPUT='{"session_id":"test","transcript_path":"~/.claude/test.jsonl","cwd":"'$(pwd)'","permission_mode":"default","hook_event_name":"SessionStart","source":"startup"}'

echo "Running SessionStart hook with test input..."
TEST_OUTPUT=$(echo "$TEST_INPUT" | CLAUDE_PROJECT_DIR="$(pwd)" CLAUDE_ENV_FILE="$TEMP_ENV" CLAUDE_PLUGIN_ROOT="$CACHED_PLUGIN" "$SESSION_START_HOOK" 2>&1 || true)

echo ""
echo "Hook Output:"
echo "$TEST_OUTPUT"
echo ""

# Check if hook produced valid JSON
if echo "$TEST_OUTPUT" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Hook executed successfully and returned valid JSON${NC}"
else
    echo -e "${RED}✗ Hook did not return valid JSON output${NC}"
    echo ""
    echo "This might indicate:"
    echo "  - Hook execution error"
    echo "  - Missing jq dependency"
fi

echo ""

# Step 5: Check if environment variables were written to CLAUDE_ENV_FILE
echo -e "${BLUE}Step 5: Verifying environment variable persistence...${NC}"
echo ""

if [[ -s "$TEMP_ENV" ]]; then
    echo -e "${GREEN}✓ Environment variables were written to CLAUDE_ENV_FILE:${NC}"
    echo ""
    cat "$TEMP_ENV"
    echo ""

    # Check for critical variable
    if grep -q "CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR=1" "$TEMP_ENV"; then
        echo -e "${GREEN}✓ CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR=1 is set${NC}"
    else
        echo -e "${RED}✗ CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR=1 is NOT set${NC}"
        echo ""
        echo -e "${YELLOW}ROOT CAUSE: Hook is not setting the required environment variable.${NC}"
    fi
else
    echo -e "${RED}✗ No environment variables were written${NC}"
    echo ""
    echo -e "${YELLOW}This could mean:${NC}"
    echo "  - Hook failed to execute the setup_environment function"
    echo "  - CLAUDE_ENV_FILE was not provided"
fi

echo ""

# Step 6: Compare cached vs repository versions
echo -e "${BLUE}Step 6: Comparing cached plugin vs repository versions...${NC}"
echo ""

REPO_SESSION_START="./hooks/session-start.sh"
if [[ -f "$REPO_SESSION_START" ]]; then
    CACHED_HASH=$(md5sum "$SESSION_START_HOOK" 2>/dev/null || md5 -q "$SESSION_START_HOOK" 2>/dev/null || echo "unknown")
    REPO_HASH=$(md5sum "$REPO_SESSION_START" 2>/dev/null || md5 -q "$REPO_SESSION_START" 2>/dev/null || echo "unknown")

    echo "Cached SessionStart hook hash: $CACHED_HASH"
    echo "Repo SessionStart hook hash:   $REPO_HASH"
    echo ""

    if [[ "$CACHED_HASH" == "$REPO_HASH" ]]; then
        echo -e "${GREEN}✓ Versions match - SessionStart hook is up to date${NC}"
    else
        echo -e "${YELLOW}⚠ Versions differ - cached plugin is OUTDATED${NC}"
        echo ""
        echo -e "${YELLOW}ROOT CAUSE: Your cached plugin is from an older commit.${NC}"
        echo ""
        echo "SOLUTION: Update the cached plugin:"
        echo "  Option 1 (Clean reinstall - recommended):"
        echo "    rm -rf '$CACHED_PLUGIN'"
        echo "    claude plugin install $(pwd)"
        echo ""
        echo "  Option 2 (Manual update):"
        echo "    cp ./hooks/session-start.sh '$SESSION_START_HOOK'"
        echo "    chmod +x '$SESSION_START_HOOK'"
    fi
else
    echo -e "${YELLOW}⚠ Not running from repository directory${NC}"
    echo "  Please run this script from the llm-council-plugin repository root"
fi

echo ""

# Step 7: Check current environment in Claude Code session
echo -e "${BLUE}Step 7: Checking current session environment...${NC}"
echo ""

if [[ -n "${CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR:-}" ]]; then
    echo -e "${GREEN}✓ CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR is set in current session${NC}"
    echo "  Value: $CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR"
else
    echo -e "${YELLOW}⚠ CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR is NOT set in current session${NC}"
    echo ""
    echo "This indicates one of the following:"
    echo "  1. SessionStart hook did not run (session started before plugin was installed)"
    echo "  2. SessionStart hook ran but failed to set the variable"
    echo "  3. You're running this script outside of a Claude Code session"
    echo ""
    echo "SOLUTIONS:"
    echo "  - Restart Claude Code to trigger SessionStart hook"
    echo "  - Run /clear to trigger SessionStart hook with 'clear' matcher"
    echo "  - Verify SessionStart hook has 'startup' and 'resume' matchers"
fi

echo ""

# Step 8: Explain what the fix actually does
echo "================================================================"
echo -e "${BLUE}Understanding 'Shell cwd was reset' Messages${NC}"
echo "================================================================"
echo ""
echo "IMPORTANT: There are TWO different scenarios where you might see this message:"
echo ""
echo "1️⃣  SCENARIO 1: CWD reset BETWEEN separate bash calls (FIXED by SessionStart hook)"
echo ""
echo "   WITHOUT SessionStart hook:"
echo "     Bash call 1: cd /tmp"
echo "     Bash call 2: pwd          → outputs /original/path (cwd was reset)"
echo ""
echo "   WITH SessionStart hook (CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR=1):"
echo "     Bash call 1: cd /tmp"
echo "     Bash call 2: pwd          → outputs /tmp (cwd maintained)"
echo ""
echo "2️⃣  SCENARIO 2: CWD reset AFTER a bash call using 'cd' (EXPECTED BEHAVIOR)"
echo ""
echo "   Single bash call: cd /somewhere && command"
echo "   After completion: Claude Code resets cwd to project directory"
echo "   Message shown:    'Shell cwd was reset to /project/path'"
echo ""
echo "   ℹ️  This message is INFORMATIONAL, not an error."
echo "   ℹ️  This happens even WITH CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR=1"
echo "   ℹ️  The command still executes successfully."
echo ""
echo "If you're seeing the message in SCENARIO 2, this is EXPECTED BEHAVIOR."
echo "The SessionStart hook prevents SCENARIO 1, not SCENARIO 2."
echo ""

# Step 9: Final recommendations
echo "================================================================"
echo -e "${BLUE}Recommendations${NC}"
echo "================================================================"
echo ""

# Determine if there's a problem
PROBLEM_FOUND=false

if [[ ! -f "$SESSION_START_HOOK" ]]; then
    PROBLEM_FOUND=true
    echo -e "${RED}🔧 ACTION REQUIRED: Install SessionStart hook${NC}"
    echo "   rm -rf '$CACHED_PLUGIN'"
    echo "   claude plugin install $(pwd)"
    echo ""
fi

if [[ -f "$REPO_SESSION_START" ]] && [[ "$CACHED_HASH" != "$REPO_HASH" ]]; then
    PROBLEM_FOUND=true
    echo -e "${YELLOW}🔧 ACTION RECOMMENDED: Update cached plugin${NC}"
    echo "   rm -rf '$CACHED_PLUGIN'"
    echo "   claude plugin install $(pwd)"
    echo ""
fi

if [[ -z "${CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR:-}" ]]; then
    echo -e "${YELLOW}🔧 ACTION RECOMMENDED: Restart Claude Code${NC}"
    echo "   Restart Claude Code to trigger SessionStart hook"
    echo "   Or run /clear to re-trigger SessionStart hook"
    echo ""
fi

if [[ "$PROBLEM_FOUND" == "false" ]]; then
    echo -e "${GREEN}✅ No problems detected!${NC}"
    echo ""
    echo "If you're still seeing 'Shell cwd was reset' messages:"
    echo "  1. Verify this is SCENARIO 2 (expected behavior) not SCENARIO 1"
    echo "  2. Check that the message appears AFTER commands using 'cd'"
    echo "  3. Confirm the actual command output is correct (message is just informational)"
    echo "  4. Consider whether the message is actually causing problems"
    echo ""
fi

echo "================================================================"
echo -e "${GREEN}Diagnostic Complete${NC}"
echo "================================================================"
