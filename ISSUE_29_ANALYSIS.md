# Issue #29 Analysis: Missing jq Dependency Causes Hook Validation Bypass

**Issue**: [#29 - Missing Dependency jq Causes Hook Validation to Bypass (Potential Security Risk)](https://github.com/xrf9268-hue/llm-council-plugin/issues/29)

**Analysis Date**: 2025-11-29
**Status**: Investigation Complete

---

## Executive Summary

The LLM Council plugin's hooks silently degrade security when `jq` is unavailable, creating a potential security risk. While this "fail-open" design is **intentional** per the documented security model, the implementation has several critical problems:

1. ❌ **jq is not documented as a required dependency** in installation guides
2. ❌ **Warning messages are insufficient** and don't explain security implications
3. ❌ **No installation-time detection** to alert users before they encounter issues
4. ❌ **Silent degradation** means users may not realize critical security validations are disabled

---

## Current Behavior Analysis

### Hook Fallback Mechanism

All three hooks (`pre-tool.sh`, `post-tool.sh`, `session-start.sh`) check for jq availability:

**pre-tool.sh (lines 43-61)**:
```bash
if command -v jq &>/dev/null; then
    # Parse JSON and perform validation
    TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
    TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input.command // .tool_input // empty' 2>/dev/null || echo "")
    COMMAND="$TOOL_INPUT"
else
    # Fallback: allow by default if jq unavailable (fail open)
    cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "jq not available, validation skipped",
    "updatedInput": null
  },
  "continue": true,
  "systemMessage": "Warning: jq not available, hook validation skipped"
}
EOF
    exit 0
fi
```

**post-tool.sh (lines 44-60)**: Similar pattern - skips all post-execution analysis

**session-start.sh (lines 92-106)**: Validates jq availability but continues with warnings

### Documented Design Intent

From `AGENTS.md` (line 331):
> **Fail Open** - Missing dependencies (like `jq`) don't block operations; hooks gracefully degrade

From `hooks/README.md` (line 369):
> **Fail Open** - If jq is unavailable, hooks gracefully skip validation

**Design Rationale**: Prevent blocking legitimate work when dependencies are unavailable.

---

## Problems Identified

### Problem 1: Silent Security Degradation ⚠️ **CRITICAL**

When `jq` is missing, these security validations are **completely bypassed**:

| Hook | Bypassed Validation | Security Impact |
|------|---------------------|-----------------|
| **PreToolUse** | Command length limit (50,000 chars) | Allows arbitrarily long commands |
| **PreToolUse** | Obfuscation detection (`${IFS}`, `\x`, octal) | Cannot detect command injection attempts |
| **PreToolUse** | Council script path validation | Cannot verify scripts exist/are executable |
| **PostToolUse** | Rate limit detection | No retry guidance for API limits |
| **PostToolUse** | Authentication error detection | No credential check guidance |
| **PostToolUse** | Sensitive data leak detection | Cannot detect API keys/tokens in output |
| **PostToolUse** | Council quorum verification | Cannot ensure minimum 2-model responses |

**Risk Level**: HIGH - Users may unknowingly operate without security guardrails.

### Problem 2: Inadequate Documentation 📚

**Missing from Prerequisites**:
- `README.md` (lines 38-47): Lists Claude/Codex/Gemini CLIs, but NOT jq
- `docs/INSTALL.md` (lines 6-14): Lists optional CLIs, but NOT jq

**Found in Documentation**:
- `hooks/README.md` (lines 494-500): Mentions jq troubleshooting **after installation**
- `docs/TROUBLESHOOTING.md` (lines 120-145): Explains jq installation **after problems occur**

**Gap**: Users discover jq is needed only **after** installation, not during prerequisites check.

### Problem 3: Insufficient Warning Messages 💬

Current warning message:
```json
"systemMessage": "Warning: jq not available, hook validation skipped"
```

**Problems**:
- ❌ Doesn't explain WHAT validations are skipped
- ❌ Doesn't explain WHY this matters (security implications)
- ❌ Doesn't explain HOW to fix it (installation instructions)
- ❌ Appears only during hook execution, not during setup

**Better Message Would Include**:
```
⚠️  SECURITY WARNING: jq not available
   → Hook security validations are DISABLED
   → Command injection detection: OFF
   → Sensitive data leak detection: OFF
   → Council quorum verification: OFF

   Install jq to enable security features:
     macOS: brew install jq
     Ubuntu/Debian: sudo apt-get install jq
     Alpine: apk add jq
```

### Problem 4: No Installation-Time Detection 🔍

**SessionStart hook** (lines 92-106) checks for jq:
```bash
validate_dependencies() {
  local missing_deps=()

  for cmd in bash jq; do
    if ! command -v "$cmd" &> /dev/null; then
      missing_deps+=("$cmd")
    fi
  done

  # Report missing dependencies (non-blocking)
  if [ ${#missing_deps[@]} -gt 0 ]; then
    echo "Warning: Missing dependencies: ${missing_deps[*]}" >&2
    echo "Some council features may be limited" >&2
  fi
}
```

**Problems**:
- Check happens **after** session already started
- Warning says "features may be limited" - understates security implications
- Output goes to stderr - may be missed in logs
- No persistent warning or status indicator

### Problem 5: Dependency Classification Inconsistency 🏷️

The plugin treats all missing CLIs the same way:

| Dependency | Purpose | Missing Impact | Current Treatment |
|------------|---------|----------------|-------------------|
| `jq` | JSON parsing in hooks | **Security validations disabled** | Optional, warn |
| `claude` | Council member | One less perspective | Optional, warn |
| `codex` | Council member | One less perspective | Optional, warn |
| `gemini` | Council member | One less perspective | Optional, warn |

**Problem**: `jq` is a **security dependency**, not a feature dependency. It should be treated differently:
- Missing Claude/Codex/Gemini → Degraded functionality (acceptable)
- Missing jq → **Degraded security** (unacceptable for security-conscious users)

---

## Test Coverage Analysis

### Existing Tests

**tests/test_hooks.sh** (lines 205-230):
```bash
test_pre_tool_no_jq() {
    test_start "pre_tool_no_jq" "Test graceful fallback when jq unavailable"

    # Test acknowledges degraded state
    if command -v jq >/dev/null 2>&1; then
        echo "  ⚠ jq is available, testing with official schema"
        # Tests that it works WITH jq
    else
        # Tests that it doesn't crash WITHOUT jq
        test_pass "Gracefully fell back when jq unavailable"
    fi
}
```

**Coverage Gaps**:
- ✅ Tests that hooks don't crash without jq
- ❌ Doesn't test WHAT validations are skipped
- ❌ Doesn't test security implications
- ❌ Doesn't test warning message visibility
- ❌ Doesn't test installation-time detection

---

## Security Risk Assessment

### Threat Scenarios

**Scenario 1: Command Injection Without Detection**
```bash
# User's system lacks jq
# Malicious AI-generated command contains obfuscation:
bash -c "echo${IFS}secretdata${IFS}>${IFS}/tmp/exfil"

# PreToolUse hook:
# - WITH jq: Detects ${IFS} obfuscation, warns user
# - WITHOUT jq: Allows silently, no warning
```

**Scenario 2: API Key Leak Without Detection**
```bash
# Command outputs API credentials
echo "OPENAI_API_KEY=sk-proj-abc123def456..." > .env

# PostToolUse hook:
# - WITH jq: Detects OpenAI key pattern, warns user
# - WITHOUT jq: No detection, credentials leaked to context
```

**Scenario 3: Failed Council Quorum Without Detection**
```bash
# Only 1 of 3 models responded (below MIN_QUORUM=2)

# PostToolUse hook:
# - WITH jq: Detects low quorum, warns degraded consensus
# - WITHOUT jq: Proceeds with single opinion, no warning
```

### Attack Surface

**Without jq, attacker could**:
1. Submit arbitrarily long commands exceeding MAX_COMMAND_LENGTH (50,000 chars)
2. Use command obfuscation techniques without detection
3. Cause council to make decisions without minimum quorum
4. Leak sensitive data in tool outputs without warnings

**Likelihood**: MEDIUM (requires jq to be missing AND malicious input)
**Impact**: HIGH (complete bypass of security validations)
**Overall Risk**: MEDIUM-HIGH

---

## Recommendations

### 1. Update Documentation (HIGH PRIORITY) 📝

**README.md Changes**:
```markdown
## Prerequisites

### Required Dependencies
- **jq** - JSON parsing for hook security validations
  - macOS: `brew install jq`
  - Ubuntu/Debian: `sudo apt-get install jq`
  - Alpine: `apk add jq`

### Required CLI Tools
- **Claude CLI** - See [code.claude.com](https://code.claude.com/docs/en/setup)

### Optional CLI Tools (for multi-model council)
- Codex: `npm install -g @openai/codex`
- Gemini: `npm install -g @google/gemini-cli`
```

**docs/INSTALL.md Changes**: Add jq to Prerequisites section (line 8)

### 2. Enhance SessionStart Hook (MEDIUM PRIORITY) 🔧

**Improve Warning Output**:
```bash
validate_dependencies() {
  local missing_deps=()

  for cmd in bash jq; do
    if ! command -v "$cmd" &> /dev/null; then
      missing_deps+=("$cmd")
    fi
  done

  if [ ${#missing_deps[@]} -gt 0 ]; then
    # Enhanced warning with security context
    cat >&2 <<EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️  SECURITY WARNING: Missing Critical Dependency
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Missing: ${missing_deps[*]}

Without jq, these security features are DISABLED:
  • Command injection detection
  • Sensitive data leak detection
  • Council quorum verification
  • Command length limits

Install jq to enable full security:
  macOS:          brew install jq
  Ubuntu/Debian:  sudo apt-get install jq
  Alpine:         apk add jq

For more info: https://github.com/xrf9268-hue/llm-council-plugin#prerequisites

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
  fi
}
```

### 3. Improve Hook Warning Messages (MEDIUM PRIORITY) 💬

**Update pre-tool.sh and post-tool.sh**:

Current:
```json
"systemMessage": "Warning: jq not available, hook validation skipped"
```

Proposed:
```json
"systemMessage": "⚠️  SECURITY: jq missing - validations DISABLED. Install: brew install jq (macOS) or apt-get install jq (Linux)"
```

### 4. Add Installation Verification Command (LOW PRIORITY) 🔍

**New slash command**: `/council-verify-deps`

```markdown
---
name: council-verify-deps
description: Verify all dependencies for LLM Council plugin
---

# Dependency Verification

This command checks if all required dependencies for the LLM Council plugin are installed.

## Implementation Instructions

Use the **Bash tool** to run the verification script:

```bash
# Check jq
if command -v jq &>/dev/null; then
    echo "✅ jq is installed (version: $(jq --version))"
    JQ_STATUS="OK"
else
    echo "❌ jq is NOT installed - SECURITY VALIDATIONS DISABLED"
    echo "   Install: brew install jq (macOS) or sudo apt-get install jq (Linux)"
    JQ_STATUS="MISSING"
fi

# Check CLIs
for cli in claude codex gemini; do
    if command -v "$cli" &>/dev/null; then
        echo "✅ $cli CLI is installed"
    else
        echo "⚠️  $cli CLI is not installed (optional for multi-model council)"
    fi
done

# Summary
if [[ "$JQ_STATUS" == "MISSING" ]]; then
    echo ""
    echo "⚠️  CRITICAL: Install jq to enable hook security validations"
fi
```
```

### 5. Consider Bash-Native JSON Fallback (FUTURE) 🔮

For critical validations, implement bash-native JSON parsing as fallback:

**Pros**:
- No external dependencies for basic security
- Always-on command length limits
- Basic pattern detection

**Cons**:
- More complex code
- Less robust than jq
- Maintenance burden

**Example**:
```bash
# Bash-native JSON parsing for critical fields
extract_json_field() {
    local json="$1"
    local field="$2"

    # Use grep/sed for basic extraction (not perfect, but better than nothing)
    echo "$json" | grep -o "\"$field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed 's/.*: *"\(.*\)".*/\1/'
}
```

### 6. Update Test Suite (MEDIUM PRIORITY) 🧪

**Add comprehensive tests for missing jq**:

```bash
test_pre_tool_no_jq_security_degradation() {
    test_start "pre_tool_no_jq_security_degradation" "Verify what validations are skipped without jq"

    # Test 1: Command length not enforced
    # Test 2: Obfuscation not detected
    # Test 3: Council script validation skipped
    # Test 4: Warning message includes security context
}

test_session_start_jq_warning_visibility() {
    test_start "session_start_jq_warning_visibility" "Verify jq warning is prominent"

    # Test that warning goes to stderr
    # Test that warning includes installation instructions
    # Test that warning mentions security implications
}
```

---

## Implementation Priority

| Priority | Task | Effort | Impact |
|----------|------|--------|--------|
| **P0 (Critical)** | Update README.md prerequisites | 10 min | High - Prevents new users from missing jq |
| **P0 (Critical)** | Update docs/INSTALL.md prerequisites | 5 min | High - Clear installation guidance |
| **P1 (High)** | Enhance SessionStart warning messages | 30 min | High - Alerts existing users |
| **P1 (High)** | Enhance pre/post-tool warning messages | 15 min | Medium - Ongoing reminders |
| **P2 (Medium)** | Add `/council-verify-deps` command | 45 min | Medium - Proactive diagnosis |
| **P2 (Medium)** | Add test coverage for security degradation | 1 hour | Medium - Prevents regressions |
| **P3 (Low)** | Investigate bash-native JSON fallback | 3-4 hours | Low - Complex, future enhancement |

---

## Conclusion

**The "fail-open" design is intentional and documented**, but the **implementation has critical gaps**:

1. ✅ **Design Philosophy is Sound**: Don't block users when dependencies are missing
2. ❌ **Documentation is Incomplete**: jq not listed as required dependency
3. ❌ **Warnings are Insufficient**: Don't convey security implications
4. ❌ **User Experience is Poor**: Discovery happens after installation

**Recommended Action**: Implement P0 and P1 fixes (documentation + warnings) immediately. These are low-effort, high-impact changes that address the core issue without requiring architectural changes.

**Security Posture After Fixes**:
- Users will know jq is required BEFORE installation
- Missing jq will trigger prominent, actionable warnings
- Security implications will be clearly communicated
- Fail-open behavior remains for flexibility, but informed

---

## Related Files

- `hooks/pre-tool.sh` (lines 43-61) - jq fallback logic
- `hooks/post-tool.sh` (lines 44-60) - jq fallback logic
- `hooks/session-start.sh` (lines 92-106) - dependency validation
- `AGENTS.md` (line 331) - "Fail Open" design principle
- `hooks/README.md` (lines 369-370, 494-500) - jq troubleshooting
- `docs/INSTALL.md` (lines 6-14) - Prerequisites (missing jq)
- `README.md` (lines 38-47) - Prerequisites (missing jq)
- `tests/test_hooks.sh` (lines 205-230) - jq fallback tests

---

**Analyst**: Claude Code (Sonnet 4.5)
**Review Status**: Ready for maintainer review
