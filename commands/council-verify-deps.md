---
name: council-verify-deps
description: Verify all dependencies for LLM Council plugin (jq, Claude CLI, optional CLIs)
model: claude-haiku-4-5-20251001
---

# Verify LLM Council Plugin Dependencies

This command checks all required and optional dependencies for the LLM Council plugin.

## Implementation Instructions

Use the **Bash tool** to run the dependency verification:

```bash
#!/bin/bash

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  LLM Council Plugin - Dependency Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Track overall status
ALL_REQUIRED_PRESENT=true
WARNINGS=()

# Check jq (CRITICAL for security)
echo "🔍 Checking Required Dependencies..."
echo ""
if command -v jq &>/dev/null; then
    JQ_VERSION=$(jq --version 2>&1)
    echo "✅ jq is installed: $JQ_VERSION"
    echo "   → Security validations: ENABLED"
else
    echo "❌ jq is NOT installed"
    echo "   → Security validations: DISABLED"
    echo "   → Command injection detection: OFF"
    echo "   → Sensitive data leak detection: OFF"
    echo "   → Council quorum verification: OFF"
    echo ""
    echo "   Install jq:"
    echo "     macOS:          brew install jq"
    echo "     Ubuntu/Debian:  sudo apt-get install jq"
    echo "     Alpine:         apk add jq"
    ALL_REQUIRED_PRESENT=false
    WARNINGS+=("jq missing - SECURITY VALIDATIONS DISABLED")
fi

echo ""

# Check Claude CLI (REQUIRED)
if command -v claude &>/dev/null; then
    CLAUDE_VERSION=$(claude --version 2>&1 | head -n1)
    echo "✅ Claude CLI is installed: $CLAUDE_VERSION"
else
    echo "❌ Claude CLI is NOT installed"
    echo "   See: https://code.claude.com/docs/en/setup"
    ALL_REQUIRED_PRESENT=false
    WARNINGS+=("Claude CLI missing - plugin will not work")
fi

echo ""
echo "🔍 Checking Optional Dependencies (for multi-model council)..."
echo ""

# Check optional CLIs
OPTIONAL_PRESENT=0
OPTIONAL_TOTAL=2

if command -v codex &>/dev/null; then
    echo "✅ Codex CLI is installed"
    OPTIONAL_PRESENT=$((OPTIONAL_PRESENT + 1))
else
    echo "ℹ️  Codex CLI is not installed (optional)"
    echo "   Install: npm install -g @openai/codex"
fi

echo ""

if command -v gemini &>/dev/null; then
    echo "✅ Gemini CLI is installed"
    OPTIONAL_PRESENT=$((OPTIONAL_PRESENT + 1))
else
    echo "ℹ️  Gemini CLI is not installed (optional)"
    echo "   Install: npm install -g @google/gemini-cli"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ "$ALL_REQUIRED_PRESENT" == true ]]; then
    echo "✅ All required dependencies are installed"
else
    echo "❌ Missing required dependencies:"
    for warning in "${WARNINGS[@]}"; do
        echo "   • $warning"
    done
fi

echo ""
echo "📊 Council Capability: $((OPTIONAL_PRESENT + 1)) models available"
if [[ $OPTIONAL_PRESENT -eq 0 ]]; then
    echo "   → Single-model mode (Claude only)"
elif [[ $OPTIONAL_PRESENT -eq 1 ]]; then
    echo "   → Two-model deliberation"
else
    echo "   → Full three-model council"
fi

echo ""

if [[ "$ALL_REQUIRED_PRESENT" == false ]]; then
    echo "⚠️  Fix required dependencies before using the plugin"
    exit 1
fi
```

Run this command anytime to verify your installation.
