# Security Considerations for Council Orchestrator

## Overview

This skill executes external CLI tools (claude, codex, gemini) with user-provided input. Follow these security guidelines to prevent command injection and ensure safe operation.

## Input Validation

### User Query Sanitization

All user queries are passed to external CLIs. The wrapper scripts implement validation before execution.

#### ✅ Safe Patterns

```bash
# Always use proper quoting
./scripts/query_claude.sh "$query"

# Validate input length (prevent resource exhaustion)
if [[ ${#query} -gt 10000 ]]; then
    echo "Error: Query too long (max 10000 chars)" >&2
    exit 1
fi

# Check for null bytes (shell injection vector)
if [[ "$query" == *$'\0'* ]]; then
    echo "Error: Null bytes not allowed" >&2
    exit 1
fi

# Use utility function
source ./skills/council-orchestrator/scripts/council_utils.sh
validate_user_input "$query" || exit 1
```

#### ❌ Unsafe Patterns

```bash
# NEVER use eval with user input
eval "query_claude.sh $query"  # VULNERABLE TO INJECTION!

# NEVER use unquoted variables
./scripts/query_claude.sh $query  # WORD SPLITTING VULNERABILITY!

# NEVER construct commands dynamically from user input
cmd="./scripts/query_claude.sh $query"
$cmd  # VULNERABLE!
```

### Input Validation Function

The `council_utils.sh` provides a centralized validation function:

```bash
validate_user_input() {
    local input="$1"
    local max_length=10000

    # Check length
    if [[ ${#input} -gt $max_length ]]; then
        error_msg "Input too long (max $max_length characters)"
        return 1
    fi

    # Check for null bytes
    if [[ "$input" == *$'\0'* ]]; then
        error_msg "Input contains null bytes"
        return 1
    fi

    return 0
}
```

## CLI Validation

### Verify CLI Authenticity

Before executing external CLIs, verify they are in expected locations:

```bash
# Check CLI is in standard location
CLAUDE_PATH=$(command -v claude)
case "$CLAUDE_PATH" in
    /usr/bin/claude|/usr/local/bin/claude|"$HOME"/.local/bin/claude)
        # Expected locations - proceed
        ;;
    *)
        echo "⚠ Warning: claude CLI in unexpected location: $CLAUDE_PATH" >&2
        echo "Verify installation before proceeding" >&2
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
        ;;
esac
```

### Check Script Permissions

Ensure wrapper scripts have correct permissions:

```bash
# Verify scripts are executable but not writable by others
for script in ./skills/council-orchestrator/scripts/*.sh; do
    if [[ ! -x "$script" ]]; then
        echo "Error: $script is not executable" >&2
        echo "Fix with: chmod +x $script" >&2
        exit 1
    fi

    # Check for world-writable (security risk)
    if [[ $(stat -c '%a' "$script") =~ [0-9][0-9]7 ]]; then
        echo "Error: $script is world-writable (security risk)" >&2
        echo "Fix with: chmod 755 $script" >&2
        exit 1
    fi
done
```

## Data Security

### Temporary File Handling

Council data is stored in `.council/` directory during execution:

```bash
# Ensure .council/ has restrictive permissions
mkdir -p .council
chmod 700 .council  # Only owner can read/write/execute

# Write responses with restrictive permissions
response_file=".council/stage1_claude.txt"
umask 077  # New files are owner-only
./scripts/query_claude.sh "$query" > "$response_file" 2>&1
```

**Best Practices**:
- All council data is automatically cleaned up after synthesis
- Temporary files are never persisted beyond the session
- Ensure `.council/` is in `.gitignore` to prevent accidental commits

### API Key Protection

External CLIs manage their own credentials:

**Do**:
- Use environment variables for API keys (`OPENAI_API_KEY`, `GEMINI_API_KEY`)
- Store credentials in `~/.config/` or CLI-specific secure storage
- Never log or echo API responses that may contain sensitive data

**Don't**:
- Hardcode API keys in scripts
- Pass API keys as command-line arguments (visible in `ps`)
- Store API keys in `.council/` or version control

### Log Sanitization

Prevent sensitive data leakage in logs:

```bash
# Sanitize error output
query_result=$(./scripts/query_claude.sh "$query" 2>&1)
if [[ $? -ne 0 ]]; then
    # Log failure without exposing query content
    error_msg "Claude CLI failed (query length: ${#query} chars)"
    # Don't log: error_msg "Query failed: $query"
fi
```

## Threat Model

| Threat | Attack Vector | Mitigation | Status |
|--------|---------------|------------|--------|
| **Shell Injection** | Malicious input in user query | Proper quoting, input validation | ✅ Implemented |
| **Command Injection** | Crafted query with shell metacharacters | validate_user_input(), null byte check | ✅ Implemented |
| **Path Traversal** | Query with `../` to access files | Input confined to CLI stdin, not file paths | ✅ N/A |
| **Malicious CLI** | Trojan CLI in PATH | CLI path verification, user confirmation | ⚠️ Recommended |
| **Resource Exhaustion** | Extremely long queries | 10000 character limit | ✅ Implemented |
| **Temp File Leakage** | `.council/` files committed to git | Automatic cleanup, .gitignore | ✅ Implemented |
| **Log Poisoning** | ANSI escape codes in output | Sanitized output paths, no user input in logs | ✅ Implemented |
| **Privilege Escalation** | World-writable scripts | Permission checks, 755 for scripts | ⚠️ Recommended |

## Security Audit Checklist

Before deploying this skill in production environments:

- [ ] Review all bash scripts for proper variable quoting
- [ ] Verify external CLIs (claude, codex, gemini) are from trusted sources
- [ ] Confirm `.council/` directory is in `.gitignore`
- [ ] Test with malformed inputs (null bytes, extreme lengths, shell metacharacters)
- [ ] Verify cleanup runs even on errors (trap EXIT in scripts)
- [ ] Check script permissions are not world-writable (755 or stricter)
- [ ] Ensure API keys are stored securely (not in scripts or git)
- [ ] Test CLI path validation with non-standard installations
- [ ] Review logs for accidental exposure of sensitive data
- [ ] Confirm umask is set to 077 before writing temporary files

## Responsible Disclosure

If you discover a security vulnerability in this skill:

1. **Do not** open a public GitHub issue
2. Email security details to: [repository maintainers]
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested mitigation (if available)

## References

- [OWASP Command Injection](https://owasp.org/www-community/attacks/Command_Injection)
- [Bash Security Best Practices](https://mywiki.wooledge.org/BashPitfalls)
- [Claude Code Security Guidelines](https://code.claude.com/docs/en/security)
