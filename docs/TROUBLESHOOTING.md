# Troubleshooting Guide

## Quick Diagnosis

If you're experiencing issues with hooks blocking commands, run the diagnostic script first:

```bash
./scripts/verify-plugin-version.sh
```

This will automatically detect version mismatches and provide specific fix instructions.

---

## Common Issues and Solutions

### Issue: "BLOCKED: Detected potentially dangerous pattern: &&"

**Symptom:**
```
⏺ Bash(cd ... && source ... && ...)
  ⎿ PreToolUse:Bash says: Plugin hook error: BLOCKED: Detected potentially
     dangerous pattern: &&
     Pre-tool validation failed. Tool execution blocked.
```

**Root Cause:**
This error occurs when using an **outdated cached version** of the plugin that contains the old hook implementation. The old `pre-tool.sh` incorrectly blocked all shell operators including `&&`, `||`, `|`, `;`, etc.

**Status:** ✅ **FIXED** in commit `78ac404` (PR #13)

**Quick Fix:**
```bash
# Run diagnostic script to identify the issue
./scripts/verify-plugin-version.sh

# Follow the script's recommendations
```

**Manual Solution:**
Update your locally cached plugin to get the latest version:

```bash
# Method 1: Reinstall the plugin (recommended - safest)
claude plugin uninstall llm-council-plugin
claude plugin install <your-plugin-source>

# Method 2: Clear cache and restart Claude Code
rm -rf ~/.claude/plugins/cache/llm-council-plugin
# Then restart Claude Code - it will re-cache the latest version

# Method 3: Manual hook file replacement (fastest)
# Find your cache directory (usually one of these):
#   macOS: /Users/$USER/.claude/plugins/cache/llm-council-plugin
#   Linux: ~/.claude/plugins/cache/llm-council-plugin
#   Linux (alt): ~/.config/claude/plugins/cache/llm-council-plugin

# Copy updated hooks from repository
cp ./hooks/pre-tool.sh ~/.claude/plugins/cache/llm-council-plugin/hooks/
cp ./hooks/post-tool.sh ~/.claude/plugins/cache/llm-council-plugin/hooks/
chmod +x ~/.claude/plugins/cache/llm-council-plugin/hooks/*.sh

# Restart Claude Code or start a new session
```

**Verify Fix:**
Use the diagnostic script or test manually:

```bash
# Option 1: Use diagnostic script (recommended)
./scripts/verify-plugin-version.sh

# Option 2: Manual test - should return "allow" with no blocking
echo '{"tool_name":"Bash","tool_input":{"command":"cd /tmp && echo test"}}' | \
  ~/.claude/plugins/cache/llm-council-plugin/hooks/pre-tool.sh

# Expected output (indicates fix is working):
# {
#   "hookSpecificOutput": {
#     "hookEventName": "PreToolUse",
#     "permissionDecision": "allow",
#     ...
#   }
# }
```

**What Changed:**
- ❌ **Old behavior**: Blocked ALL shell operators (`&&`, `||`, `|`, `;`, etc.)
- ✅ **New behavior**: Only blocks actual security threats (command too long, missing council scripts)
- ✅ Warnings only for obfuscation attempts (hex encoding, IFS manipulation)
- ✅ Uses official Claude Code JSON schema with `hookSpecificOutput` wrapper
- ✅ Follows [Claude Code hooks best practices](https://code.claude.com/docs/en/hooks-guide.md)

**Why This Happened:**
The old hooks incorrectly used regex patterns that matched legitimate shell operators. The fix:
1. Removed all checks for standard shell operators (`&&`, `||`, `|`, `;`)
2. Updated to official Claude Code hooks JSON schema
3. Focused on actual security threats (injection, obfuscation) not syntax

---

### Issue: Hook validation warnings

**Symptom:**
```
INFO: Multiple command separators detected
WARNING: Destructive operation on critical path: /etc/passwd
```

**Root Cause:**
These are **informational warnings** from the PreToolUse hook. They do not block execution.

**Solution:**
- Review the warning to ensure the command is intentional
- These warnings help detect potential security issues but won't prevent legitimate operations
- To suppress warnings, adjust detection thresholds via environment variables (see Configuration)

---

### Issue: jq not available

**Symptom:**
```
{"permissionDecision":"allow","systemMessage":"Warning: jq not available, hook validation skipped"}
```

**Root Cause:**
Hooks require `jq` for JSON parsing. Without it, hooks gracefully degrade (allow all operations).

**Solution:**
Install `jq` for full hook validation:

```bash
# Ubuntu/Debian
sudo apt-get install jq

# macOS
brew install jq

# Alpine
apk add jq
```

**Security Note:**
Without `jq`, hooks cannot validate commands. This is a **fail-open** design to prevent blocking legitimate work.

---

### Issue: Hook timeout

**Symptom:**
Hook execution times out after 30 seconds.

**Root Cause:**
- Hook scripts contain expensive operations (network calls, large file processing)
- System is under heavy load

**Solution:**
1. **Optimize hook logic** - Remove expensive operations from hook scripts
2. **Increase timeout** (if necessary):
   ```json
   // In hooks/hooks.json
   {
     "hooks": {
       "PreToolUse": [{
         "hooks": [{
           "timeout": 60  // Increase to 60 seconds (max recommended)
         }]
       }]
     }
   }
   ```
3. **Check for blocking operations** - Ensure hooks don't make network calls or wait for user input

---

### Issue: Council quorum not met

**Symptom:**
```
⚠️ Council quorum low: 1/2 models responded
```

**Root Cause:**
- One or more council members (OpenAI, Anthropic, Google) failed to respond
- Possible causes: API rate limits, authentication errors, network issues

**Solution:**
1. **Check API credentials** - Ensure all API keys are valid:
   ```bash
   # Check environment variables
   echo $OPENAI_API_KEY
   echo $ANTHROPIC_API_KEY
   echo $GOOGLE_API_KEY
   ```

2. **Check for rate limits** - Look for rate limit messages in output
3. **Verify network connectivity** - Test API endpoints directly
4. **Review PostToolUse context** - The hook provides detailed guidance on retry strategies

---

## Configuration

### Environment Variables

Configure hooks and council behavior via environment variables:

```bash
# PreToolUse configuration
export COUNCIL_MAX_COMMAND_LENGTH=50000  # Max command size (default: 50000)

# PostToolUse configuration
export COUNCIL_MAX_OUTPUT_LENGTH=500000  # Output warning threshold (default: 500000)

# Council session directory
export COUNCIL_DIR=.council  # Session working directory (default: .council)

# Claude Code environment (provided automatically)
# CLAUDE_PROJECT_DIR  - Project root path
# CLAUDE_PLUGIN_ROOT  - Plugin installation path
```

### Disabling Hooks Temporarily

If hooks are causing issues during development:

1. **Project-level**: Rename `hooks/hooks.json` to `hooks/hooks.json.disabled`
2. **User-level**: Remove hooks from `~/.claude/settings.json`
3. **Per-session**: Set environment variable `SKIP_HOOKS=1` (if supported)

⚠️ **Warning**: Disabling hooks removes security validations. Re-enable after debugging.

---

## Testing and Validation

### Run Test Suites

Verify hooks and council orchestrator are working correctly:

```bash
# Run all tests (includes hooks + orchestrator)
./tests/test_runner.sh

# Run hooks tests only
./tests/test_hooks.sh

# Expected results:
# - test_runner.sh: 18/18 tests passing
# - test_hooks.sh: 17/17 tests passing
```

### Manual Hook Testing

Test hooks in isolation:

```bash
# Test PreToolUse with normal command
echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' | ./hooks/pre-tool.sh

# Test PreToolUse with command chaining (should allow)
echo '{"tool_name":"Bash","tool_input":{"command":"cd /tmp && echo test"}}' | ./hooks/pre-tool.sh

# Test PostToolUse with rate limit detection
echo '{"tool_name":"Bash","tool_output":"Error: rate limit exceeded","exit_code":"1"}' | ./hooks/post-tool.sh

# Test PostToolUse with auth error detection
echo '{"tool_name":"Bash","tool_output":"401 Unauthorized","exit_code":"1"}' | ./hooks/post-tool.sh
```

---

## Getting Help

If you encounter issues not covered here:

1. **Check documentation**:
   - `README.md` - Plugin overview and installation
   - `docs/INSTALL.md` - Detailed installation and setup
   - `hooks/README.md` - Hook behavior and security model
   - `AGENTS.md` - Repository structure and guidelines

2. **Run tests**: `./tests/test_runner.sh` to identify failures

3. **Enable debug logging**:
   ```bash
   export DEBUG=1
   # Then re-run the command to see detailed hook output
   ```

4. **Report issues**: https://github.com/xrf9268-hue/llm-council-plugin/issues
   - Include: error message, command being run, hook output
   - Specify: plugin version (git commit hash)

---

## Version Information

**Current Version:** Based on commit `ce48fbb` or later

**Key Fixes:**
- ✅ Shell operators (`&&`, `||`, `|`, `;`) no longer blocked (ce48fbb)
- ✅ Structured JSON output per Claude Code API (ce48fbb)
- ✅ Non-blocking informational warnings (ce48fbb)
- ✅ Comprehensive test coverage (17 hook tests, 18 orchestrator tests)

**References:**
- [Claude Code Hooks Guide](https://code.claude.com/docs/en/hooks-guide.md)
- [Plugin Development Best Practices](https://code.claude.com/docs/en/plugins.md)
- [Hooks Reference](https://code.claude.com/docs/en/hooks.md)
