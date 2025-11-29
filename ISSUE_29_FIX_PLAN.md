# Issue #29 Multi-Step Fix Plan

**Issue**: Missing jq Dependency Causes Hook Validation Bypass (Security Risk)
**Created**: 2025-11-29
**Status**: Planning Complete, Ready for Implementation

---

## 📋 Executive Summary

This plan addresses the silent security degradation when `jq` is unavailable by implementing fixes in 5 phases:

| Phase | Priority | Effort | Impact | Timeline |
|-------|----------|--------|--------|----------|
| **Phase 1** | P0 (Critical) | 15 min | High - Prevents new user issues | Immediate |
| **Phase 2** | P1 (High) | 45 min | High - Alerts existing users | Day 1 |
| **Phase 3** | P2 (Medium) | 1 hour | Medium - Proactive diagnosis | Day 2 |
| **Phase 4** | P2 (Medium) | 1 hour | Medium - Prevents regressions | Day 2-3 |
| **Phase 5** | P3 (Low) | 3-4 hours | Low - Future enhancement | Future |

**Total Estimated Effort**: ~3 hours for P0-P2 (critical fixes)

---

## 🎯 Phase 1: Documentation Updates (P0 - Critical)

**Priority**: CRITICAL
**Effort**: 15 minutes
**Impact**: HIGH - Prevents new users from encountering the issue
**Dependencies**: None

### Objectives
- Add `jq` to prerequisites in all installation documentation
- Clearly mark `jq` as required for security features
- Provide installation instructions for all platforms

### Tasks

#### Task 1.1: Update README.md Prerequisites
**File**: `README.md` (lines 38-47)
**Current State**: Lists Claude/Codex/Gemini CLIs, but NOT jq
**Target State**: jq listed as required dependency with security context

**Implementation**:
```markdown
## Prerequisites

### Required Dependencies

You need these installed before using the plugin:

| Dependency | Purpose | Installation |
|------------|---------|--------------|
| **jq** | JSON parsing for hook security validations | macOS: `brew install jq`<br>Ubuntu/Debian: `sudo apt-get install jq`<br>Alpine: `apk add jq` |
| **Claude CLI** | Required for council deliberations | [code.claude.com/docs/setup](https://code.claude.com/docs/en/setup) |

**⚠️ Important**: Without `jq`, security validations are disabled (command injection detection, sensitive data leak detection, etc.)

### Optional Dependencies (for multi-model council)

| CLI | Installation | Notes |
|-----|--------------|-------|
| Codex | `npm install -g @openai/codex` | Adds OpenAI perspective |
| Gemini | `npm install -g @google/gemini-cli` | Adds Google perspective |
```

**Validation**:
- [ ] jq appears in prerequisites section
- [ ] Security implications clearly stated
- [ ] Installation commands provided for all platforms
- [ ] Distinction between required and optional is clear

---

#### Task 1.2: Update docs/INSTALL.md Prerequisites
**File**: `docs/INSTALL.md` (lines 6-14)
**Current State**: Lists optional CLIs only
**Target State**: jq listed first as critical dependency

**Implementation**:
```markdown
## Prerequisites

### Required Dependencies

- **jq** - JSON parsing utility for hook security validations
  - **Critical**: Without jq, all security validations are disabled
  - Installation:
    - macOS: `brew install jq`
    - Ubuntu/Debian: `sudo apt-get install jq`
    - Alpine: `apk add jq`
    - Verify: `jq --version`

- **Claude Code** installed and signed in (VS Code or JetBrains)
  - See https://code.claude.com/docs/en/setup

### Optional Dependencies (for multi-model council)

- **codex** - OpenAI Codex CLI for additional perspectives
- **gemini** - Google Gemini CLI for additional perspectives
```

**Validation**:
- [ ] jq listed as first required dependency
- [ ] Security warning prominent
- [ ] Verification command provided (`jq --version`)
- [ ] Optional CLIs clearly separated

---

#### Task 1.3: Add jq Check to Installation Instructions
**File**: `docs/INSTALL.md` (after line 58)
**Add Section**: Verify Installation > Check Dependencies

**Implementation**:
```markdown
## Verify Installation

### Check Dependencies

Before using the plugin, verify all required dependencies:

```bash
# Check jq (REQUIRED for security)
if command -v jq &>/dev/null; then
    echo "✅ jq is installed (version: $(jq --version))"
else
    echo "❌ jq is NOT installed - SECURITY VALIDATIONS DISABLED"
    echo "   Install: brew install jq (macOS) or sudo apt-get install jq (Linux)"
    exit 1
fi

# Check Claude CLI (REQUIRED)
if command -v claude &>/dev/null; then
    echo "✅ Claude CLI is installed"
else
    echo "❌ Claude CLI is NOT installed"
    exit 1
fi

# Check optional CLIs
for cli in codex gemini; do
    if command -v "$cli" &>/dev/null; then
        echo "✅ $cli CLI is installed"
    else
        echo "ℹ️  $cli CLI is not installed (optional)"
    fi
done
```

Run this before proceeding with plugin installation.
```

**Validation**:
- [ ] Verification script provided
- [ ] jq check fails with exit 1
- [ ] Clear distinction between required and optional
- [ ] User-friendly output with emojis

---

### Phase 1 Success Criteria
- [x] All documentation mentions jq as required dependency
- [x] Security implications clearly explained
- [x] Installation instructions provided for all platforms
- [x] Verification steps included
- [ ] **Phase 1 Complete** - Ready to commit

### Phase 1 Testing
```bash
# Manual verification
grep -n "jq" README.md
grep -n "jq" docs/INSTALL.md

# Ensure security warnings present
grep -n "security" README.md
grep -n "SECURITY" docs/INSTALL.md
```

### Phase 1 Commit Message
```
docs: add jq as required dependency in all installation docs

Add jq to prerequisites with security context:
- README.md: Add jq to prerequisites table with security warning
- docs/INSTALL.md: Add jq as first required dependency
- docs/INSTALL.md: Add dependency verification script

Without jq, all hook security validations are disabled:
- Command injection detection
- Sensitive data leak detection
- Council quorum verification
- Command length limits

Addresses #29 (Phase 1: Documentation)
```

---

## 🔧 Phase 2: Enhanced Warning Messages (P1 - High)

**Priority**: HIGH
**Effort**: 45 minutes
**Impact**: HIGH - Alerts existing users to security issues
**Dependencies**: None (can run parallel to Phase 1)

### Objectives
- Enhance SessionStart hook warning for missing jq
- Improve PreToolUse hook warning message
- Improve PostToolUse hook warning message
- Make warnings actionable with installation commands

### Tasks

#### Task 2.1: Enhance SessionStart Hook Warning
**File**: `hooks/session-start.sh` (lines 92-106)
**Current Warning**: "Warning: Missing dependencies: jq"
**Target**: Prominent security warning with installation instructions

**Implementation**:
```bash
validate_dependencies() {
  local missing_deps=()

  # Check for required CLI tools
  for cmd in bash jq; do
    if ! command -v "$cmd" &> /dev/null; then
      missing_deps+=("$cmd")
    fi
  done

  # Report missing dependencies with enhanced security context
  if [ ${#missing_deps[@]} -gt 0 ]; then
    # Check if jq specifically is missing (critical security dependency)
    local jq_missing=false
    for dep in "${missing_deps[@]}"; do
      if [[ "$dep" == "jq" ]]; then
        jq_missing=true
        break
      fi
    done

    if [[ "$jq_missing" == true ]]; then
      # Critical security warning for missing jq
      cat >&2 <<'EOF'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️  SECURITY WARNING: Critical Dependency Missing
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Missing: jq (JSON parser)

Without jq, these security features are DISABLED:
  ❌ Command injection detection
  ❌ Sensitive data leak detection (API keys, tokens)
  ❌ Council quorum verification
  ❌ Command length limits (50,000 chars)
  ❌ System path protection warnings

🔧 Install jq to enable full security:
  macOS:          brew install jq
  Ubuntu/Debian:  sudo apt-get install jq
  Alpine:         apk add jq
  Verify:         jq --version

📚 More info: https://github.com/xrf9268-hue/llm-council-plugin#prerequisites

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
    else
      # Standard warning for other dependencies
      echo "Warning: Missing dependencies: ${missing_deps[*]}" >&2
      echo "Some features may be limited" >&2
    fi
  fi
}
```

**Validation**:
- [ ] Prominent visual separator (box drawing)
- [ ] Lists specific disabled security features
- [ ] Provides installation commands
- [ ] Includes verification command
- [ ] Links to documentation

---

#### Task 2.2: Enhance PreToolUse Hook Warning
**File**: `hooks/pre-tool.sh` (lines 48-60)
**Current**: "Warning: jq not available, hook validation skipped"
**Target**: Security-focused warning with actionable guidance

**Implementation**:
```bash
else
    # Fallback: allow by default if jq unavailable (fail open)
    cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "jq not available - command validation disabled for security",
    "updatedInput": null
  },
  "continue": true,
  "systemMessage": "⚠️  SECURITY: jq missing - command validation DISABLED. Install: brew install jq (macOS) | apt-get install jq (Linux) | apk add jq (Alpine)"
}
EOF
    exit 0
fi
```

**Changes**:
- Reason field explains security context
- System message includes installation commands for multiple platforms
- Uses warning emoji for visibility
- Emphasizes DISABLED state

**Validation**:
- [ ] systemMessage includes installation commands
- [ ] Reason field mentions security
- [ ] JSON schema remains valid

---

#### Task 2.3: Enhance PostToolUse Hook Warning
**File**: `hooks/post-tool.sh` (lines 48-60)
**Current**: "Warning: jq not available, post-tool validation skipped"
**Target**: Security-focused warning matching PreToolUse style

**Implementation**:
```bash
else
    # If jq unavailable, exit gracefully without validation (fail open)
    cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "Post-tool security analysis disabled (jq not available). The following checks are skipped: rate limit detection, auth error detection, sensitive data leak detection, council quorum verification."
  },
  "continue": true,
  "systemMessage": "⚠️  SECURITY: jq missing - output analysis DISABLED. Install: brew install jq (macOS) | apt-get install jq (Linux) | apk add jq (Alpine)"
}
EOF
    exit 0
fi
```

**Changes**:
- additionalContext lists disabled checks
- systemMessage provides installation commands
- Consistent style with PreToolUse hook

**Validation**:
- [ ] additionalContext lists all disabled checks
- [ ] systemMessage matches PreToolUse format
- [ ] JSON schema valid

---

### Phase 2 Success Criteria
- [ ] SessionStart displays prominent security warning
- [ ] PreToolUse systemMessage includes installation commands
- [ ] PostToolUse systemMessage includes installation commands
- [ ] All warnings mention specific disabled features
- [ ] Installation commands provided for macOS/Linux/Alpine
- [ ] **Phase 2 Complete** - Ready to commit

### Phase 2 Testing
```bash
# Test SessionStart hook without jq
PATH="/usr/bin:/bin" ./hooks/session-start.sh <<< '{"source":"startup"}'

# Test PreToolUse hook without jq
PATH="/usr/bin:/bin" ./hooks/pre-tool.sh <<< '{"tool_name":"Bash","tool_input":{"command":"ls"}}'

# Test PostToolUse hook without jq
PATH="/usr/bin:/bin" ./hooks/post-tool.sh <<< '{"tool_name":"Bash","tool_output":"test"}'

# Verify warnings are prominent and actionable
```

### Phase 2 Commit Message
```
feat(hooks): enhance security warnings for missing jq dependency

Improve warning messages across all hooks:
- SessionStart: Add prominent boxed warning listing disabled features
- PreToolUse: Include installation commands in systemMessage
- PostToolUse: Include installation commands in systemMessage

All warnings now:
- List specific disabled security features
- Provide installation commands for macOS/Linux/Alpine
- Use warning emoji for visibility
- Maintain fail-open behavior while informing users

Addresses #29 (Phase 2: Enhanced Warnings)
```

---

## 🛠️ Phase 3: Verification Tools (P2 - Medium)

**Priority**: MEDIUM
**Effort**: 1 hour
**Impact**: MEDIUM - Enables proactive diagnosis
**Dependencies**: Phase 1 (documentation)

### Objectives
- Create `/council-verify-deps` slash command
- Add dependency check to `/council-status` command
- Create standalone verification script

### Tasks

#### Task 3.1: Create `/council-verify-deps` Slash Command
**File**: `commands/council-verify-deps.md` (new file)
**Purpose**: Standalone dependency verification command

**Implementation**:
```markdown
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
```

**Validation**:
- [ ] Command registered in `plugin.json`
- [ ] Uses Haiku model for efficiency
- [ ] Clear output with emojis and formatting
- [ ] Actionable installation instructions
- [ ] Exit code 1 if required deps missing

---

#### Task 3.2: Add Dependency Check to `/council-status`
**File**: `commands/council-status.md` (modify existing)
**Current**: Shows CLI availability only
**Target**: Add jq security status section

**Implementation** (add after CLI status):
```bash
# Security Status
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Security Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if command -v jq &>/dev/null; then
    echo "✅ Hook Security: ENABLED (jq installed)"
else
    echo "⚠️  Hook Security: DISABLED (jq not installed)"
    echo "   Install jq to enable:"
    echo "     macOS:          brew install jq"
    echo "     Ubuntu/Debian:  sudo apt-get install jq"
fi
```

**Validation**:
- [ ] Security section added to status output
- [ ] Clear indication of security state
- [ ] Installation commands provided

---

#### Task 3.3: Create Standalone Verification Script
**File**: `scripts/verify-dependencies.sh` (new file)
**Purpose**: Standalone script users can run before installation

**Implementation**:
```bash
#!/bin/bash
# verify-dependencies.sh - Verify LLM Council Plugin dependencies
# Usage: ./scripts/verify-dependencies.sh

set -euo pipefail

# Same implementation as Task 3.1 but as standalone script
# Can be run before plugin installation

# [Content same as /council-verify-deps command]
```

**Make executable**:
```bash
chmod +x scripts/verify-dependencies.sh
```

**Validation**:
- [ ] Script is executable
- [ ] Can run before plugin installation
- [ ] Same output as `/council-verify-deps`

---

### Phase 3 Success Criteria
- [ ] `/council-verify-deps` command created and working
- [ ] `/council-status` includes security status
- [ ] Standalone script created and executable
- [ ] All tools provide actionable guidance
- [ ] **Phase 3 Complete** - Ready to commit

### Phase 3 Testing
```bash
# Test new command
/council-verify-deps

# Test updated status command
/council-status

# Test standalone script
./scripts/verify-dependencies.sh

# Test without jq
PATH="/usr/bin:/bin" ./scripts/verify-dependencies.sh
```

### Phase 3 Commit Message
```
feat: add dependency verification tools

Add comprehensive dependency checking:
- /council-verify-deps: New slash command for verification
- /council-status: Add security status section
- scripts/verify-dependencies.sh: Standalone verification script

All tools:
- Check jq (required for security)
- Check Claude CLI (required)
- Check Codex/Gemini (optional)
- Provide installation instructions
- Exit with error if required deps missing

Addresses #29 (Phase 3: Verification Tools)
```

---

## 🧪 Phase 4: Test Coverage (P2 - Medium)

**Priority**: MEDIUM
**Effort**: 1 hour
**Impact**: MEDIUM - Prevents regressions
**Dependencies**: Phase 2 (warnings)

### Objectives
- Add tests for missing jq security degradation
- Test warning message visibility and content
- Test SessionStart hook with/without jq
- Update test documentation

### Tasks

#### Task 4.1: Add PreToolUse Security Degradation Tests
**File**: `tests/test_hooks.sh` (add new tests)
**Purpose**: Verify what validations are skipped without jq

**Implementation**:
```bash
test_pre_tool_no_jq_command_length() {
    test_start "pre_tool_no_jq_command_length" "Verify command length limit not enforced without jq"

    # Create command exceeding MAX_COMMAND_LENGTH (50000 chars)
    local long_command=$(printf 'a%.0s' $(seq 1 60000))
    local input="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$long_command\"}}"

    # Test WITH jq - should block
    if command -v jq &>/dev/null; then
        local output
        output=$(echo "$input" | CLAUDE_PROJECT_DIR="$PROJECT_ROOT" "$PRE_TOOL_HOOK" 2>&1)
        local exit_code=$?

        if [[ $exit_code -eq 2 ]]; then
            echo "  ✓ WITH jq: Blocks long command (exit 2)"
        else
            test_fail "Should block commands exceeding length limit" "pre_tool_no_jq_command_length"
            return
        fi
    fi

    # Test WITHOUT jq - should allow (fail open)
    local output
    output=$(PATH="/usr/bin:/bin" echo "$input" | CLAUDE_PROJECT_DIR="$PROJECT_ROOT" "$PRE_TOOL_HOOK" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        echo "  ✓ WITHOUT jq: Allows long command (fail open)"

        # Verify warning message present
        if echo "$output" | grep -q "jq missing"; then
            echo "  ✓ Warning message present"
            test_pass
        else
            test_fail "Should include warning about jq" "pre_tool_no_jq_command_length"
        fi
    else
        test_fail "Should allow (fail open) without jq" "pre_tool_no_jq_command_length"
    fi
}

test_pre_tool_no_jq_obfuscation() {
    test_start "pre_tool_no_jq_obfuscation" "Verify obfuscation detection skipped without jq"

    # Command with obfuscation patterns
    local obfuscated_cmd='echo${IFS}test'
    local input="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$obfuscated_cmd\"}}"

    # Test WITHOUT jq - should allow without detection
    local output
    output=$(PATH="/usr/bin:/bin" echo "$input" | CLAUDE_PROJECT_DIR="$PROJECT_ROOT" "$PRE_TOOL_HOOK" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        echo "  ✓ WITHOUT jq: Obfuscation not detected (validation skipped)"
        test_pass
    else
        test_fail "Should allow without validation" "pre_tool_no_jq_obfuscation"
    fi
}

test_pre_tool_warning_content() {
    test_start "pre_tool_warning_content" "Verify warning message includes installation instructions"

    local input='{"tool_name":"Bash","tool_input":{"command":"ls"}}'

    # Only test if jq is NOT available (otherwise can't test fallback)
    if ! command -v jq &>/dev/null; then
        local output
        output=$(echo "$input" | CLAUDE_PROJECT_DIR="$PROJECT_ROOT" "$PRE_TOOL_HOOK" 2>&1)

        # Check for installation instructions
        if echo "$output" | grep -q "brew install jq"; then
            echo "  ✓ Contains macOS installation command"
        else
            test_fail "Missing macOS install command" "pre_tool_warning_content"
            return
        fi

        if echo "$output" | grep -q "apt-get install jq"; then
            echo "  ✓ Contains Linux installation command"
            test_pass
        else
            test_fail "Missing Linux install command" "pre_tool_warning_content"
        fi
    else
        echo "  ⚠ jq available, cannot test fallback warning"
        test_pass "skipped (jq available)"
    fi
}
```

**Validation**:
- [ ] Tests run successfully
- [ ] Command length bypass detected
- [ ] Obfuscation bypass detected
- [ ] Warning message content verified

---

#### Task 4.2: Add PostToolUse Security Degradation Tests
**File**: `tests/test_hooks.sh` (add new tests)
**Purpose**: Verify output analysis is skipped without jq

**Implementation**:
```bash
test_post_tool_no_jq_sensitive_data() {
    test_start "post_tool_no_jq_sensitive_data" "Verify sensitive data detection skipped without jq"

    # Output containing API key
    local output_with_key='{"tool_name":"Bash","tool_output":"OPENAI_API_KEY=sk-proj-abc123def456ghi789","exit_code":"0"}'

    # Test WITHOUT jq - should not detect
    local hook_output
    hook_output=$(PATH="/usr/bin:/bin" echo "$output_with_key" | CLAUDE_PROJECT_DIR="$PROJECT_ROOT" "$POST_TOOL_HOOK" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        echo "  ✓ WITHOUT jq: Sensitive data not detected (validation skipped)"

        # Verify fallback message
        if echo "$hook_output" | grep -q "jq"; then
            echo "  ✓ Warning about jq present"
            test_pass
        else
            test_fail "Should warn about jq" "post_tool_no_jq_sensitive_data"
        fi
    else
        test_fail "Should succeed with warning" "post_tool_no_jq_sensitive_data"
    fi
}

test_post_tool_no_jq_quorum() {
    test_start "post_tool_no_jq_quorum" "Verify quorum check skipped without jq"

    # Setup council directory with low quorum
    setup_test_env
    echo "Response" > "$TEST_COUNCIL_DIR/stage1_claude.txt"

    local input='{"tool_name":"Bash","tool_output":"council operation completed","exit_code":"0"}'

    # Test WITHOUT jq - should not detect quorum issue
    local output
    output=$(PATH="/usr/bin:/bin" COUNCIL_DIR="$TEST_COUNCIL_DIR" echo "$input" | \
             CLAUDE_PROJECT_DIR="$PROJECT_ROOT" "$POST_TOOL_HOOK" 2>&1)

    if ! echo "$output" | grep -q "quorum"; then
        echo "  ✓ WITHOUT jq: Quorum not checked (validation skipped)"
        test_pass
    else
        test_fail "Should skip quorum check without jq" "post_tool_no_jq_quorum"
    fi

    cleanup_test_env
}
```

**Validation**:
- [ ] Sensitive data detection bypass verified
- [ ] Quorum check bypass verified
- [ ] Warning messages verified

---

#### Task 4.3: Add SessionStart Dependency Tests
**File**: `tests/test_hooks.sh` (add new tests)
**Purpose**: Verify SessionStart warning behavior

**Implementation**:
```bash
test_session_start_jq_warning() {
    test_start "session_start_jq_warning" "Verify SessionStart warns about missing jq"

    # Only test if jq is NOT available
    if ! command -v jq &>/dev/null; then
        local input='{"source":"startup","session_id":"test123"}'
        local output
        output=$(echo "$input" | CLAUDE_PROJECT_DIR="$PROJECT_ROOT" "$SESSION_START_HOOK" 2>&1)

        # Check for security warning
        if echo "$output" | grep -i "security" | grep -q "warning"; then
            echo "  ✓ Contains security warning"
        else
            test_fail "Missing security warning" "session_start_jq_warning"
            return
        fi

        # Check for installation instructions
        if echo "$output" | grep -q "brew install jq" && \
           echo "$output" | grep -q "apt-get install jq"; then
            echo "  ✓ Contains installation instructions"
            test_pass
        else
            test_fail "Missing installation instructions" "session_start_jq_warning"
        fi
    else
        echo "  ⚠ jq available, cannot test warning"
        test_pass "skipped (jq available)"
    fi
}

test_session_start_jq_success() {
    test_start "session_start_jq_success" "Verify SessionStart succeeds with jq"

    # Only test if jq IS available
    if command -v jq &>/dev/null; then
        local input='{"source":"startup","session_id":"test456"}'
        local output
        output=$(echo "$input" | CLAUDE_PROJECT_DIR="$PROJECT_ROOT" "$SESSION_START_HOOK" 2>&1)
        local exit_code=$?

        if [[ $exit_code -eq 0 ]]; then
            echo "  ✓ SessionStart succeeds"
        else
            test_fail "SessionStart should succeed with jq" "session_start_jq_success"
            return
        fi

        # Should not contain security warnings about jq
        if ! echo "$output" | grep -i "missing.*jq"; then
            echo "  ✓ No warnings about missing jq"
            test_pass
        else
            test_fail "Should not warn when jq is available" "session_start_jq_success"
        fi
    else
        echo "  ⚠ jq not available, cannot test success case"
        test_pass "skipped (jq not available)"
    fi
}
```

**Validation**:
- [ ] SessionStart warning verified
- [ ] Success case (with jq) verified
- [ ] Installation instructions in warning

---

#### Task 4.4: Update Test Runner
**File**: `tests/test_runner.sh` (add new test category)
**Purpose**: Add security degradation test category

**Implementation**:
```bash
# Add after line 761 (before print_summary)

echo -e "\n${BLUE}▶ Running Security Degradation Tests${NC}"
test_pre_tool_no_jq_command_length
test_pre_tool_no_jq_obfuscation
test_pre_tool_warning_content
test_post_tool_no_jq_sensitive_data
test_post_tool_no_jq_quorum
test_session_start_jq_warning
test_session_start_jq_success
```

**Validation**:
- [ ] New test category runs
- [ ] All 7 new tests execute
- [ ] Tests pass regardless of jq availability

---

### Phase 4 Success Criteria
- [ ] 7 new security degradation tests added
- [ ] Tests verify bypassed validations
- [ ] Tests verify warning message content
- [ ] Tests work with and without jq installed
- [ ] Test runner updated
- [ ] All tests pass
- [ ] **Phase 4 Complete** - Ready to commit

### Phase 4 Testing
```bash
# Run new tests
./tests/test_runner.sh

# Run security tests only (once integrated)
./tests/test_runner.sh test_pre_tool_no_jq_command_length
./tests/test_runner.sh test_post_tool_no_jq_sensitive_data

# Verify coverage
grep -c "test_.*_no_jq" tests/test_hooks.sh
```

### Phase 4 Commit Message
```
test: add comprehensive tests for jq dependency degradation

Add 7 new tests covering security validation bypass:
- PreToolUse: command length limit bypass
- PreToolUse: obfuscation detection bypass
- PreToolUse: warning message content
- PostToolUse: sensitive data detection bypass
- PostToolUse: quorum verification bypass
- SessionStart: warning for missing jq
- SessionStart: success with jq

Tests verify:
- What validations are skipped without jq
- Warning messages include installation instructions
- Hooks fail open gracefully
- Security context is communicated to users

Addresses #29 (Phase 4: Test Coverage)
```

---

## 🔮 Phase 5: Future Enhancements (P3 - Low)

**Priority**: LOW
**Effort**: 3-4 hours
**Impact**: LOW - Future improvement, not critical
**Dependencies**: Phases 1-4 complete

### Objectives
- Investigate bash-native JSON fallback for critical validations
- Consider bundling lightweight JSON parser
- Explore alternative dependency management

### Tasks

#### Task 5.1: Research Bash-Native JSON Parsing
**Purpose**: Enable basic validations without jq
**Effort**: 1-2 hours research

**Options to investigate**:

1. **Pure bash JSON extraction** (limited but functional):
```bash
extract_json_field() {
    local json="$1"
    local field="$2"

    # Use grep/sed for basic extraction
    echo "$json" | grep -o "\"$field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | \
        sed 's/.*: *"\(.*\)".*/\1/'
}

# Example usage
COMMAND=$(extract_json_field "$INPUT" "command")
```

2. **Python fallback** (if available):
```bash
if command -v python3 &>/dev/null; then
    COMMAND=$(python3 -c "import json,sys; print(json.load(sys.stdin)['tool_input']['command'])" <<< "$INPUT")
fi
```

3. **Node.js fallback** (if available):
```bash
if command -v node &>/dev/null; then
    COMMAND=$(node -e "console.log(JSON.parse(require('fs').readFileSync(0).toString()).tool_input.command)")
fi
```

**Pros/Cons Analysis**:
| Approach | Pros | Cons |
|----------|------|------|
| Pure bash | No dependencies | Fragile, limited features |
| Python fallback | Robust parsing | Requires Python |
| Node.js fallback | Robust parsing | Requires Node.js |
| Bundle jq | Always available | Increases plugin size |

**Recommendation**: Document findings, implement if clear win identified.

---

#### Task 5.2: Investigate Bundling Lightweight JSON Parser
**Purpose**: Eliminate external jq dependency
**Effort**: 1 hour research

**Options**:
1. **jq-static binary** - Include compiled jq in plugin
   - Pros: No installation needed
   - Cons: Platform-specific binaries, size (~2MB), licensing

2. **jshon** - Lighter alternative (~50KB)
   - Pros: Smaller size
   - Cons: Still requires bundling, less feature-complete

3. **gron** - JSON to greppable format
   - Pros: Simple, bash-friendly
   - Cons: Different paradigm, learning curve

**Recommendation**: Research licensing and feasibility, document in issue.

---

#### Task 5.3: Create Plugin Dependency Specification
**Purpose**: Formal dependency declaration for future Claude Code support
**Effort**: 30 min

**Implementation**:
Create `dependencies.json` (if Claude Code supports in future):
```json
{
  "dependencies": {
    "required": {
      "jq": {
        "version": ">=1.5",
        "purpose": "JSON parsing for hook security validations",
        "install": {
          "macos": "brew install jq",
          "debian": "sudo apt-get install jq",
          "alpine": "apk add jq"
        },
        "verify": "jq --version",
        "security_critical": true
      }
    },
    "optional": {
      "codex": {
        "purpose": "Multi-model council (OpenAI perspective)",
        "install": "npm install -g @openai/codex"
      },
      "gemini": {
        "purpose": "Multi-model council (Google perspective)",
        "install": "npm install -g @google/gemini-cli"
      }
    }
  }
}
```

**Validation**:
- [ ] JSON schema valid
- [ ] All dependencies documented
- [ ] Security flags set appropriately

---

### Phase 5 Success Criteria
- [ ] Research documented in issue/wiki
- [ ] Bash-native parsing POC created (if feasible)
- [ ] Bundling options evaluated
- [ ] Dependency specification created
- [ ] **Phase 5 Complete** - Future roadmap clear

### Phase 5 Deliverables
- Research document: `docs/DEPENDENCY_ALTERNATIVES.md`
- POC code (if developed): `hooks/json_parser_fallback.sh`
- Dependency spec: `dependencies.json`

---

## 📊 Implementation Timeline

### Week 1 (Critical Fixes)
- **Day 1 Morning**: Phase 1 (Documentation) - 15 min
- **Day 1 Afternoon**: Phase 2 (Warnings) - 45 min
- **Day 2**: Phase 3 (Verification Tools) - 1 hour
- **Day 3**: Phase 4 (Test Coverage) - 1 hour

**Total Week 1 Effort**: ~3 hours

### Week 2+ (Future Enhancements)
- **When time permits**: Phase 5 (Research) - 3-4 hours

---

## ✅ Success Metrics

### Quantitative Metrics
- [ ] 100% of installation docs mention jq as required
- [ ] 3 new verification tools created
- [ ] 7 new tests added (security degradation coverage)
- [ ] 0 new users encountering issue after Phase 1

### Qualitative Metrics
- [ ] Users understand jq is required BEFORE installation
- [ ] Existing users alerted to security implications
- [ ] Warning messages are actionable and clear
- [ ] Test suite prevents future regressions

---

## 🔄 Rollback Plan

Each phase can be rolled back independently:

### Phase 1 Rollback
```bash
git revert <commit-hash>  # Revert documentation changes
```
**Risk**: LOW - Only documentation changed

### Phase 2 Rollback
```bash
git revert <commit-hash>  # Revert hook changes
```
**Risk**: LOW - Hooks still work, just less informative

### Phase 3 Rollback
```bash
git revert <commit-hash>  # Remove verification tools
git rm commands/council-verify-deps.md
```
**Risk**: NONE - New features only

### Phase 4 Rollback
```bash
git revert <commit-hash>  # Remove test additions
```
**Risk**: NONE - Tests only

---

## 📝 Commit Strategy

### Branch Strategy
- Main branch: `main`
- Fix branch: `fix/issue-29-jq-dependency`
- Each phase: Separate commit on fix branch

### Commit Structure
```
Phase 1: docs: add jq as required dependency
Phase 2: feat(hooks): enhance security warnings for missing jq
Phase 3: feat: add dependency verification tools
Phase 4: test: add comprehensive jq degradation tests
Phase 5: docs: research dependency alternatives
```

### Pull Request
- Title: "Fix #29: Address missing jq dependency security risk"
- Description: Link to this plan and ISSUE_29_ANALYSIS.md
- Reviewers: Assign maintainers
- Labels: `security`, `documentation`, `enhancement`

---

## 🎓 Lessons Learned

### What Worked Well
- "Fail-open" design philosophy (don't block users)
- Graceful degradation when dependencies missing
- Comprehensive documentation in @AGENTS.md and @hooks/README.md

### What Needs Improvement
- Required dependencies not prominent in installation docs
- Warning messages lack actionable guidance
- No proactive verification tools
- Security implications not clearly communicated

### Future Recommendations
1. **For New Plugins**: List ALL dependencies (required + optional) upfront
2. **For Security Features**: Never silently degrade without prominent warnings
3. **For User Experience**: Provide verification tools before and after installation
4. **For Documentation**: Security context should be explicit, not implied

---

## 📚 References

- **Original Issue**: #29 - Missing jq Dependency Security Risk
- **Analysis Document**: `ISSUE_29_ANALYSIS.md`
- **Related Files**:
  - `hooks/pre-tool.sh` (lines 43-61)
  - `hooks/post-tool.sh` (lines 44-60)
  - `hooks/session-start.sh` (lines 92-106)
  - `README.md` (lines 38-47)
  - `docs/INSTALL.md` (lines 6-14)
  - `AGENTS.md` (line 331 - Fail Open principle)
  - `hooks/README.md` (lines 369-370, 494-500)

---

**Plan Author**: Claude Code (Sonnet 4.5)
**Plan Status**: ✅ Ready for Implementation
**Estimated Total Effort**: ~3 hours (P0-P2) + 3-4 hours (P3, optional)
**Next Action**: Begin Phase 1 (Documentation Updates)
