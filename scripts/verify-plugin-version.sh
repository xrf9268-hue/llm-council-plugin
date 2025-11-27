#!/bin/bash
#
# verify-plugin-version.sh - Verify and diagnose plugin version issues
#
# This script helps diagnose why hooks might be blocking legitimate shell operators.
#

set -euo pipefail

echo "=== LLM Council Plugin Version Verification ==="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Step 1: Check if we can find the cached plugin
echo "Step 1: Locating cached plugin..."
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
    echo -e "${YELLOW}⚠ No cached plugin found. Plugin may not be installed.${NC}"
    echo ""
    echo "To install the plugin:"
    echo "  claude plugin install <path-to-this-repo>"
    exit 1
fi

echo ""

# Step 2: Test the cached hook
echo "Step 2: Testing cached hook with && operator..."
CACHED_HOOK="$CACHED_PLUGIN/hooks/pre-tool.sh"

if [[ ! -f "$CACHED_HOOK" ]]; then
    echo -e "${RED}✗ Hook file not found at: $CACHED_HOOK${NC}"
    exit 1
fi

if [[ ! -x "$CACHED_HOOK" ]]; then
    echo -e "${YELLOW}⚠ Hook is not executable. Fixing...${NC}"
    chmod +x "$CACHED_HOOK"
fi

# Test with a command containing &&
TEST_INPUT='{"tool_name":"Bash","tool_input":{"command":"cd /tmp && echo test"}}'
TEST_OUTPUT=$(echo "$TEST_INPUT" | "$CACHED_HOOK" 2>&1 || true)

echo "Test input: cd /tmp && echo test"
echo "Hook output:"
echo "$TEST_OUTPUT"
echo ""

# Check if hook is blocking
if echo "$TEST_OUTPUT" | grep -qi "BLOCKED.*&&"; then
    echo -e "${RED}✗ PROBLEM DETECTED: Hook is blocking && operator (OLD VERSION)${NC}"
    echo ""
    echo "This means your cached plugin is outdated."
    echo ""
    echo "Solutions:"
    echo ""
    echo "Option 1 (Recommended): Clear cache and reinstall"
    echo "  rm -rf '$CACHED_PLUGIN'"
    echo "  claude plugin install <path-to-this-repo>"
    echo ""
    echo "Option 2: Manual hook replacement"
    echo "  cp ./hooks/pre-tool.sh '$CACHED_HOOK'"
    echo "  cp ./hooks/post-tool.sh '$CACHED_PLUGIN/hooks/post-tool.sh'"
    echo "  chmod +x '$CACHED_PLUGIN/hooks/'*.sh"
    echo ""
    exit 1
elif echo "$TEST_OUTPUT" | grep -qi '"permissionDecision":"allow"'; then
    echo -e "${GREEN}✓ Hook is working correctly (NEW VERSION)${NC}"
    echo ""
    echo "The hook allows && operators as expected."
    echo "If you're still seeing blocking errors, try:"
    echo "  1. Restart Claude Code"
    echo "  2. Clear any user-level hook overrides in ~/.claude/settings.json"
else
    echo -e "${YELLOW}⚠ Unexpected hook output${NC}"
    echo ""
    echo "The hook output doesn't match expected format."
    echo "This might indicate:"
    echo "  - Missing jq dependency"
    echo "  - Hook execution error"
    echo ""
    echo "Please install jq:"
    echo "  macOS: brew install jq"
    echo "  Ubuntu/Debian: sudo apt-get install jq"
fi

echo ""

# Step 3: Compare versions
echo "Step 3: Comparing cached vs repository versions..."
echo ""

REPO_HOOK="./hooks/pre-tool.sh"
if [[ -f "$REPO_HOOK" ]]; then
    CACHED_HASH=$(md5sum "$CACHED_HOOK" 2>/dev/null || md5 -q "$CACHED_HOOK" 2>/dev/null || echo "unknown")
    REPO_HASH=$(md5sum "$REPO_HOOK" 2>/dev/null || md5 -q "$REPO_HOOK" 2>/dev/null || echo "unknown")

    echo "Cached hook hash: $CACHED_HASH"
    echo "Repo hook hash:   $REPO_HASH"
    echo ""

    if [[ "$CACHED_HASH" == "$REPO_HASH" ]]; then
        echo -e "${GREEN}✓ Versions match - hooks are up to date${NC}"
    else
        echo -e "${YELLOW}⚠ Versions differ - cached plugin is outdated${NC}"
        echo ""
        echo "Update with:"
        echo "  cp ./hooks/*.sh '$CACHED_PLUGIN/hooks/'"
        echo "  chmod +x '$CACHED_PLUGIN/hooks/'*.sh"
    fi
else
    echo -e "${YELLOW}⚠ Not running from repository directory${NC}"
fi

echo ""
echo "=== Verification Complete ==="
