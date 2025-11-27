# LLM Council Plugin Hooks

This directory contains lifecycle hooks that enhance the security and reliability of LLM Council plugin operations.

## Overview

The hooks implement a defense-in-depth security model with three lifecycle hooks:
- **SessionStart** (`session-start.sh`) - Initializes environment for council operations
- **PreToolUse** (`pre-tool.sh`) - Validates commands before execution
- **PostToolUse** (`post-tool.sh`) - Analyzes outputs and provides intelligent context

All hooks follow [Claude Code hooks best practices](https://code.claude.com/docs/en/hooks-guide.md) with structured JSON output and appropriate exit codes.

## Hook Configuration

Hooks are registered via `hooks.json` and target Bash tool executions. They run automatically during agent execution with a 30-second timeout.

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [{
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh",
          "timeout": 30,
          "description": "Initialize LLM Council environment for new sessions"
        }]
      },
      {
        "matcher": "resume",
        "hooks": [{
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh",
          "timeout": 30,
          "description": "Re-initialize LLM Council environment for resumed sessions"
        }]
      }
    ],
    "PreToolUse": [{
      "matcher": "Bash",
      "hooks": [{
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/hooks/pre-tool.sh",
        "timeout": 30,
        "description": "Validate inputs before Bash tool execution"
      }]
    }],
    "PostToolUse": [{
      "matcher": "Bash",
      "hooks": [{
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/hooks/post-tool.sh",
        "timeout": 30,
        "description": "Analyze outputs after Bash tool execution"
      }]
    }]
  }
}
```

## SessionStart Hook (`session-start.sh`)

### Purpose
Initializes the environment for LLM Council operations at the start of each Claude Code session. This hook sets up persistent environment variables that solve the "Shell cwd was reset" issue and configure council operational parameters.

### Initialization Logic

1. **Environment Variable Persistence** (via `CLAUDE_ENV_FILE`)
   - `COUNCIL_DIR` - Council session directory (default: `.council`)
   - `COUNCIL_MAX_COMMAND_LENGTH` - Max command length for validation (default: 50000)
   - `COUNCIL_MAX_OUTPUT_LENGTH` - Output warning threshold (default: 500000)
   - `CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR=1` - **Prevents "Shell cwd was reset" messages**
   - `COUNCIL_PLUGIN_ROOT` - Plugin installation path for scripts

2. **Dependency Validation** (Non-blocking)
   - Checks for required CLI tools (`bash`, `jq`)
   - Reports missing dependencies as warnings
   - Hook continues even if dependencies are missing

3. **Council Script Validation** (Non-blocking)
   - Validates existence of council orchestrator scripts
   - Checks script executability
   - Warns if scripts are missing or not executable

### Exit Codes

- **0** - Success (always succeeds, even with warnings)
- SessionStart hooks **cannot block** session initialization per official Claude Code behavior

### JSON Output Schema (Official Claude Code Format)

```json
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "LLM Council Plugin environment initialized for startup session. Environment variables configured: COUNCIL_DIR, COUNCIL_MAX_COMMAND_LENGTH, COUNCIL_MAX_OUTPUT_LENGTH, CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR."
  }
}
```

### Environment Variables

**Provided by Claude Code:**
- `CLAUDE_PROJECT_DIR` - Project root path (for path resolution)
- `CLAUDE_PLUGIN_ROOT` - Plugin installation path
- `CLAUDE_ENV_FILE` - File path to persist environment variables (**SessionStart exclusive**)

**Set by this hook (persisted across session):**
- `COUNCIL_DIR` - Council working directory
- `COUNCIL_MAX_COMMAND_LENGTH` - PreToolUse validation limit
- `COUNCIL_MAX_OUTPUT_LENGTH` - PostToolUse warning threshold
- `CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR` - Prevents cwd reset messages
- `COUNCIL_PLUGIN_ROOT` - Plugin root for script execution

### How It Solves "Shell cwd was reset"

The **official solution** per Claude Code IAM documentation is to use SessionStart hooks with `CLAUDE_ENV_FILE`:

1. **Problem**: Claude Code resets working directory between bash calls for security
2. **Solution**: Set `CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR=1` in `CLAUDE_ENV_FILE`
3. **Result**: Working directory is maintained, eliminating reset messages

This is **Method 1** from the official documentation and the recommended approach for plugins.

### Matcher Values

SessionStart hooks support four matchers:

| Matcher | When Triggered | Hook Behavior |
|---------|---------------|---------------|
| `startup` | New session created | Full environment initialization |
| `resume` | Session resumed (`/resume`, `--resume`) | Re-initialize environment |
| `clear` | Context cleared (`/clear`) | Re-setup after clear |
| `compact` | Context compacted | Re-setup after compaction |

Currently registered for: `startup`, `resume`

### Example Scenarios

**Scenario 1: New session startup**
```bash
# User starts new Claude Code session
$ claude -p /path/to/project

# SessionStart hook runs automatically
# Output: Initializes COUNCIL_DIR, sets CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR=1
# Result: Environment ready, no "Shell cwd was reset" messages during session
```

**Scenario 2: Resume existing session**
```bash
# User resumes previous session
$ claude --resume last

# SessionStart hook runs with matcher="resume"
# Output: Re-initializes environment variables
# Result: Environment restored to working state
```

**Scenario 3: Missing dependencies**
```bash
# jq is not installed
# Hook Output: Warning about jq, but continues
# Exit: 0 (non-blocking)
# Session starts normally with reduced validation capabilities
```

## PreToolUse Hook (`pre-tool.sh`)

### Purpose
Validates commands before execution to detect security issues and enforce council operational requirements.

### Validation Logic

1. **Command Length Check** (Blocking)
   - Enforces max command length (default: 50,000 chars)
   - Configurable via `COUNCIL_MAX_COMMAND_LENGTH`

2. **Obfuscation Detection** (Warning)
   - Detects suspicious patterns: hex encoding, octal encoding, IFS manipulation
   - Informational only - does NOT block legitimate shell operators (&&, ||, |, ;, etc.)

3. **System Path Protection** (Warning)
   - Warns about destructive operations on critical paths (`/etc/passwd`, `~/.ssh/`, etc.)
   - Informational only - allows legitimate operations

4. **Council Script Validation** (Blocking)
   - Validates existence and executability of council orchestrator scripts
   - Uses `CLAUDE_PROJECT_DIR` to resolve absolute paths correctly

### Exit Codes

- **0 with JSON** - Allow execution (may include warnings)
- **2** - Block execution with error message

### JSON Output Schema (Official Claude Code Format)

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow|deny|ask",
    "permissionDecisionReason": "explanation if denied/ask",
    "updatedInput": null
  },
  "continue": true,
  "systemMessage": "user-facing message"
}
```

### Environment Variables

- `CLAUDE_PROJECT_DIR` - Project root path (provided by Claude Code)
- `COUNCIL_MAX_COMMAND_LENGTH` - Max command length (default: 50000)
- `COUNCIL_DIR` - Council session directory (default: .council)

### Example Scenarios

**Scenario 1: Normal command with && operator**
```bash
# Input: legitimate bash command with && operator
$ bash -c "ls -la && echo done"

# Output: {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow",...},"continue":true}
# Exit: 0
```

**Scenario 2: Command too long**
```bash
# Input: 60,000 character command
# Output: "Command exceeds maximum length: 60000 chars (max: 50000)"
# Exit: 2 (blocked)
```

**Scenario 3: Missing council script**
```bash
# Input: skills/council-orchestrator/scripts/nonexistent.sh
# Output: "Council script not found at: /home/user/llm-council-plugin/skills/..."
# Exit: 2 (blocked)
```

## PostToolUse Hook (`post-tool.sh`)

### Purpose
Analyzes command outputs to provide intelligent context and warnings to Claude.

### Analysis Features

1. **Rate Limit Detection**
   - Patterns: "rate limit", "429", "quota exceeded", etc.
   - Provides context: retry guidance with exponential backoff

2. **Authentication Error Detection**
   - Patterns: "unauthorized", "401", "403", "invalid api key", etc.
   - Provides context: credential check guidance

3. **Output Size Monitoring**
   - Warns if output exceeds threshold (default: 500,000 chars)
   - Suggests truncation/summarization

4. **Council Quorum Verification**
   - Checks Stage 1 responses from council models
   - Warns if quorum not met (minimum 2 models)

5. **Sensitive Data Detection**
   - Scans for API key patterns: OpenAI, Google, AWS, GitHub
   - Warns about potential credential leaks

### Exit Codes

- **0 with JSON** - Continue (may provide context/warnings)
- **non-zero** - Log issue (non-blocking)

### JSON Output Schema (Official Claude Code Format)

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "context for Claude to consider"
  },
  "continue": true,
  "systemMessage": "user-facing warning/info"
}
```

### Environment Variables

- `CLAUDE_PROJECT_DIR` - Project root path (provided by Claude Code)
- `COUNCIL_MAX_OUTPUT_LENGTH` - Max output warning threshold (default: 500000)
- `COUNCIL_DIR` - Council session directory (default: .council)

### Example Scenarios

**Scenario 1: Rate limit detected**
```bash
# Output contains: "Error: rate limit exceeded"

# JSON Response:
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "Rate limit detected. Consider implementing exponential backoff..."
  },
  "continue": true,
  "systemMessage": "⚠️  Rate limit detected - consider waiting before retrying"
}
```

**Scenario 2: Low quorum**
```bash
# Council session with only 1 Stage 1 response

# JSON Response:
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "Council quorum not met: only 1 of 2 required responses available..."
  },
  "continue": true,
  "systemMessage": "⚠️  Council quorum low: 1/2 models responded"
}
```

**Scenario 3: Sensitive data leak**
```bash
# Output contains: "sk-proj-abc123..." (OpenAI key pattern with 20+ chars)

# JSON Response:
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "SECURITY: Potential API key or token detected..."
  },
  "continue": true,
  "systemMessage": "🔒 Potential sensitive data detected in output"
}
```

## Security Model

### Design Principles

1. **Defense in Depth**
   - Pre-execution validation catches issues before commands run
   - Post-execution analysis provides intelligent feedback

2. **Allow by Default**
   - Hooks focus on actual security threats
   - Legitimate shell operations are not blocked
   - Warnings are informational, not restrictive

3. **Fail Open**
   - If jq is unavailable, hooks gracefully skip validation
   - Network/dependency failures don't block operations

4. **Structured Communication**
   - Hooks use official JSON schema for Claude Code integration
   - Context messages guide Claude's decision-making
   - System messages keep users informed

### What Hooks DON'T Do

**❌ Do NOT block legitimate shell operations**
- Pipes (`|`), redirects (`>`, `<`), command chaining (`&&`, `||`) are allowed
- These are fundamental shell features required for complex operations

**❌ Do NOT enforce style guidelines**
- Hooks focus on security and correctness, not code style
- Formatting and conventions are left to linters and code review

**❌ Do NOT replace proper authentication**
- Hooks detect exposed credentials but don't secure them
- Use environment variables and secrets management properly

### Security Considerations

⚠️ **IMPORTANT**: Hooks run automatically with your environment's credentials. Review and understand all hook code before enabling.

Recommended practices:
1. **Review hook source** - Understand what each hook does
2. **Validate inputs** - Don't trust external data in hook logic
3. **Use absolute paths** - Avoid path traversal vulnerabilities
4. **Quote variables** - Prevent injection in hook scripts themselves
5. **Limit permissions** - Run with minimum required privileges

## Testing

Hooks are tested as part of the plugin test suite:

```bash
# Run all tests including hook tests
./tests/test_runner.sh

# Test hooks in isolation
./tests/test_hooks.sh
```

### Manual Testing

Test pre-tool hook:
```bash
# Test normal command
echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' | ./hooks/pre-tool.sh

# Test command too long
echo '{"tool_name":"Bash","tool_input":{"command":"'$(printf 'a%.0s' {1..60000})''"}}' | ./hooks/pre-tool.sh

# Test missing council script
echo '{"tool_name":"Bash","tool_input":{"command":"skills/council-orchestrator/scripts/nonexistent.sh"}}' | ./hooks/pre-tool.sh
```

Test post-tool hook:
```bash
# Test rate limit detection
echo '{"tool_name":"Bash","tool_output":"Error: rate limit exceeded","exit_code":"1"}' | ./hooks/post-tool.sh

# Test auth error detection
echo '{"tool_name":"Bash","tool_output":"Error: 401 Unauthorized","exit_code":"1"}' | ./hooks/post-tool.sh

# Test sensitive data detection
echo '{"tool_name":"Bash","tool_output":"API_KEY=sk-proj-abc123def456","exit_code":"0"}' | ./hooks/post-tool.sh
```

Test session-start hook:
```bash
# Test startup scenario with environment persistence
TEMP_ENV=$(mktemp)
echo '{"session_id":"test123","transcript_path":"~/.claude/test.jsonl","cwd":"'$(pwd)'","permission_mode":"default","hook_event_name":"SessionStart","source":"startup"}' | \
  CLAUDE_PROJECT_DIR=$(pwd) CLAUDE_ENV_FILE=$TEMP_ENV ./hooks/session-start.sh
cat $TEMP_ENV
rm $TEMP_ENV

# Test resume scenario
echo '{"session_id":"test456","transcript_path":"~/.claude/test.jsonl","cwd":"'$(pwd)'","permission_mode":"default","hook_event_name":"SessionStart","source":"resume"}' | \
  CLAUDE_PROJECT_DIR=$(pwd) ./hooks/session-start.sh

# Test without CLAUDE_ENV_FILE (graceful degradation)
echo '{"session_id":"test789","transcript_path":"~/.claude/test.jsonl","cwd":"'$(pwd)'","permission_mode":"default","hook_event_name":"SessionStart","source":"startup"}' | \
  CLAUDE_PROJECT_DIR=$(pwd) ./hooks/session-start.sh
```

## Configuration

### Environment Variables

Configure hooks via environment variables in your shell or `.env`:

```bash
# Pre-tool configuration
export COUNCIL_MAX_COMMAND_LENGTH=50000

# Post-tool configuration
export COUNCIL_MAX_OUTPUT_LENGTH=500000

# Council session directory
export COUNCIL_DIR=.council
```

### Disabling Hooks

To temporarily disable hooks:

1. **User-level**: Remove hooks from `~/.claude/settings.json`
2. **Project-level**: Remove or rename `hooks/hooks.json`
3. **Per-command**: Use permission bypass mode (advanced)

## Troubleshooting

### Hook Not Running

**Symptom**: Hooks don't execute during agent operations

**Solutions**:
1. Verify hook scripts are executable: `chmod +x hooks/*.sh`
2. Check hooks are registered in `hooks.json`
3. Ensure plugin is properly installed: `claude plugin validate .`

### jq Not Available

**Symptom**: Warning about jq not available

**Solutions**:
1. Install jq: `apt-get install jq` or `brew install jq`
2. Hooks will fall back to allowing all operations without validation

### Hook Timeout

**Symptom**: Hooks timeout after 30 seconds

**Solutions**:
1. Optimize hook logic (remove expensive operations)
2. Increase timeout in `hooks.json` (max recommended: 60s)
3. Check for network calls or blocking operations

### False Positives

**Symptom**: Hooks warn about legitimate operations

**Solutions**:
1. Review warning messages - they're usually informational
2. Adjust thresholds via environment variables
3. Report issues to help improve detection patterns

## References

- [Claude Code Hooks Guide](https://code.claude.com/docs/en/hooks-guide.md)
- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks.md)
- [Plugin Development](../.claude-plugin/plugin.json)
- [Council Orchestrator](../skills/council-orchestrator/SKILL.md)

## Contributing

When modifying hooks:

1. **Test thoroughly** - Run `./tests/test_runner.sh`
2. **Follow best practices** - Use structured JSON output
3. **Document changes** - Update this README
4. **Security review** - Consider security implications
5. **Keep focused** - Hooks should be fast and targeted

## License

Same as parent project - see LICENSE file.
