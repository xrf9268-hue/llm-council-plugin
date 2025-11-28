# LLM Council Plugin for Claude Code

![LLM Council Header](header.png)

A multi-model consensus engine that integrates OpenAI Codex CLI, Google Gemini CLI, and Claude CLI for collaborative code review and problem-solving.

## Overview

The LLM Council summons multiple AI models to deliberate on your technical questions. Each model provides its perspective, reviews its peers' answers, and a chairman synthesizes everything into a final verdict.

### How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                    LLM COUNCIL WORKFLOW                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Stage 1: Opinion Collection (Parallel)                     │
│  ┌─────────┐   ┌─────────┐   ┌─────────┐                   │
│  │ Claude  │   │  Codex  │   │ Gemini  │                   │
│  └────┬────┘   └────┬────┘   └────┬────┘                   │
│       │             │             │                         │
│       v             v             v                         │
│  Stage 2: Peer Review (Cross-examination)                   │
│  ┌─────────────────────────────────────┐                   │
│  │ Each model reviews others' answers  │                   │
│  └─────────────────────────────────────┘                   │
│                      │                                      │
│                      v                                      │
│  Stage 3: Chairman Synthesis                                │
│  ┌─────────────────────────────────────┐                   │
│  │ Claude Opus synthesizes the verdict │                   │
│  └─────────────────────────────────────┘                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Quick Start

### Prerequisites

You need at least one CLI installed. For full council functionality, install all three:

| CLI | Installation | Required |
|-----|--------------|----------|
| Claude | [code.claude.com](https://code.claude.com/docs/en/setup) | Yes |
| Codex | `npm install -g @openai/codex` | No |
| Gemini | `npm install -g @google/gemini-cli` | No |

### Installation

For a full installation and debugging walkthrough, see `docs/INSTALL.md`.

#### Option A: Install via Marketplace (Recommended)

In Claude Code, run these commands:

```bash
# Add the marketplace
/plugin marketplace add xrf9268-hue/llm-council-plugin

# Install the plugin
/plugin install llm-council-plugin@llm-council
```

Alternatively, you can add via Git URL:
```bash
/plugin marketplace add https://github.com/xrf9268-hue/llm-council-plugin.git
```

#### Option B: Local Development

Clone this repo and make scripts executable:

```bash
git clone https://github.com/xrf9268-hue/llm-council-plugin.git .claude-plugins/llm-council
chmod +x .claude-plugins/llm-council/hooks/*.sh .claude-plugins/llm-council/skills/council-orchestrator/scripts/*.sh
```

#### ⚠️ Troubleshooting Hook Issues

If you see errors like **"BLOCKED: Detected potentially dangerous pattern: &&"**, your cached plugin is outdated.

**Quick fix:**
```bash
# Run diagnostic script
./scripts/verify-plugin-version.sh

# Or manually update cache
rm -rf ~/.claude/plugins/cache/llm-council-plugin
# Then reinstall the plugin
```

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for comprehensive troubleshooting guidance.

### Usage

#### Using the Slash Command

In Claude Code, use the `/council` command:

```
/council "How should I implement rate limiting in a Node.js API?"
```

Each `/council` run:

- Resets the `.council/` working directory for this session.
- Runs opinion collection, peer review, and chairman synthesis.
- Displays the final report in chat and saves it to `.council/final_report.md`.

When you no longer need files from previous sessions, you can clean up with:

```
/council-cleanup
```

#### Using the Skill Directly

Invoke the `council-orchestrator` skill for more control:

```
Use the council-orchestrator skill to answer: "What's the best approach for database connection pooling?"
```

#### Running Scripts Manually

For debugging or customization:

```bash
# Resolve plugin root (works for both local dev and marketplace installations)
PLUGIN_ROOT="${COUNCIL_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CLAUDE_PROJECT_DIR}}}"

# Stage 1: Collect opinions
"${PLUGIN_ROOT}/skills/council-orchestrator/scripts/run_parallel.sh" "Your question here"

# Stage 2: Run peer reviews
"${PLUGIN_ROOT}/skills/council-orchestrator/scripts/run_peer_review.sh" "Your question here" .council

# Stage 3: Generate chairman prompt
"${PLUGIN_ROOT}/skills/council-orchestrator/scripts/run_chairman.sh" "Your question here" .council
```

## Commands

| Command | Description |
|---------|-------------|
| `/council <query>` | Summon the council for a technical question |
| `/council-cleanup` | Delete the `.council/` working directory and all session files |
| `/council-help` | Display usage information and examples |
| `/council-status` | Check CLI availability and configuration |
| `/council-config` | Manage council settings |

## Configuration

Configuration is stored in `~/.council/config`. Available settings:

| Setting | Default | Description |
|---------|---------|-------------|
| `enabled_members` | `claude,codex,gemini` | Which CLIs to use |
| `min_quorum` | `2` | Minimum responses required |
| `timeout` | `120` | CLI timeout in seconds |
| `max_prompt_length` | `10000` | Maximum prompt length |

### Example Configuration

```bash
# Resolve path to council_utils.sh
PLUGIN_ROOT="${COUNCIL_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CLAUDE_PROJECT_DIR}}}"
source "${PLUGIN_ROOT}/skills/council-orchestrator/scripts/council_utils.sh"

# Enable only Claude and Codex
config_set enabled_members "claude,codex"

# Adjust timeout
config_set timeout 180
```

## Output Files

During execution, the council creates files in the `.council/` directory:

```
.council/
├── stage1_claude.txt      # Claude's initial response
├── stage1_openai.txt      # Codex's initial response
├── stage1_gemini.txt      # Gemini's initial response
├── stage2_review_claude.txt   # Claude's peer review
├── stage2_review_openai.txt   # Codex's peer review
├── stage2_review_gemini.txt   # Gemini's peer review
└── final_report.md        # Chairman's synthesized verdict
```

The `.council/` directory always represents the **most recent** `/council` run. A new `/council` invocation will reset this directory before starting a fresh session, so previous session files are never mixed into a new deliberation. Use `/council-cleanup` if you want to remove the directory entirely when you no longer need the latest session's files.

## Final Report Format

The chairman produces a structured Markdown report:

```markdown
# LLM Council Verdict

## Executive Summary
[One-paragraph overview of the consensus]

## Council Participation
| Member | Status | Key Position |
|--------|--------|--------------|
| Claude | Present | ... |
| Codex  | Present | ... |
| Gemini | Absent  | N/A |

## Consensus Points
- Point 1
- Point 2

## Areas of Disagreement
### Topic 1
- Claude: [position]
- Codex: [position]

## Final Recommendation
[Synthesized answer incorporating all perspectives]
```

## Graceful Degradation

The council handles failures gracefully:

- **One CLI unavailable**: Council proceeds with remaining members
- **Empty response**: Member marked as "absent" in report
- **Timeout**: Member terminated and marked absent
- **Rate limits**: Automatic retry with exponential backoff

### Quorum Requirements

- Minimum 2 responses required for peer review stage
- Council can produce a verdict with just 1 response (degraded mode)
- Missing members are clearly noted in the final report

## Testing

Run the test suite:

```bash
# Run all tests (council + hooks)
./tests/test_runner.sh

# Run hook tests separately
./tests/test_hooks.sh

# Run specific test category
./tests/test_runner.sh unit_council_init
./tests/test_runner.sh partial_failure_simulation
```

### Test Categories

- `unit_*` - Unit tests for utility functions
- `integration_*` - Script existence and permissions
- `happy_path_*` - Full flow with real CLIs
- `edge_*` - Edge cases (empty prompts, special characters)
- `partial_failure_*` - Simulated CLI failures
- `total_failure_*` - Complete failure scenarios

## Troubleshooting

**For comprehensive troubleshooting guidance, see [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).**

### Common Issues

#### "Claude CLI is required but not available"

Install the Claude Code CLI:

```bash
# Visit https://code.claude.com/docs/en/setup for installation instructions
```

#### "Quorum not met"

At least 2 responses are needed for peer review. Check:

1. Are the CLIs properly authenticated?
2. Are there rate limit issues?
3. Check `.council/stage1_*.txt` files for error messages

#### "Empty response from [CLI]"

The CLI returned nothing. Common causes:

- Authentication expired
- Rate limit exceeded
- Network issues

Check the output file for error details:

```bash
cat .council/stage1_claude.txt
```

#### Hooks Not Running

Ensure hooks are configured in `hooks/hooks.json` and scripts are executable:

```bash
chmod +x hooks/session-start.sh hooks/pre-tool.sh hooks/post-tool.sh
```

See [hooks/README.md](hooks/README.md) for detailed hook troubleshooting.

## Security

### Input Validation

Prompts are validated for:
- Shell injection patterns (backticks, `$()`, pipes)
- Maximum length (10,000 characters default)
- Null bytes

### Output Sanitization

Post-execution hooks check for:
- API key leakage
- Rate limit indicators
- Error patterns

## Architecture

### Project Structure

```
llm-council-plugin/
├── .claude-plugin/
│   ├── plugin.json              # Plugin manifest
│   └── marketplace.json         # Marketplace metadata
├── agents/                      # Sub-agent definitions (chairman, etc.)
├── commands/                    # Slash commands (/council, /council-cleanup, ...)
├── skills/
│   └── council-orchestrator/
│       ├── SKILL.md             # Core workflow (Level 2)
│       ├── REFERENCE.md         # Detailed implementation (Level 3)
│       ├── EXAMPLES.md          # Usage scenarios (Level 3)
│       ├── SECURITY.md          # Security best practices (Level 3)
│       ├── METADATA.md          # Version and licensing (Level 3)
│       ├── scripts/             # Orchestration and CLI wrapper scripts
│       └── templates/           # Peer review + chairman prompt templates
├── hooks/
│   ├── hooks.json               # Hook configuration
│   ├── session-start.sh         # SessionStart hook (environment setup)
│   ├── pre-tool.sh              # Pre-execution validation
│   ├── post-tool.sh             # Post-execution verification
│   └── README.md                # Hook documentation and troubleshooting
├── scripts/                     # Development and diagnostic scripts
├── docs/
│   ├── INSTALL.md               # Installation and setup guide
│   └── TROUBLESHOOTING.md       # Comprehensive troubleshooting guide
├── tests/
│   ├── test_runner.sh           # Main test suite
│   ├── test_hooks.sh            # Hook-specific tests
│   └── test_codex_integration.sh# Codex integration tests
├── CLAUDE.md                    # Project context for Claude Code
├── AGENTS.md                    # Repository guidelines and standards
├── header.png                   # Header image
└── README.md                    # This file
```

### Skill Architecture - Progressive Disclosure Pattern

The council-orchestrator skill follows the official progressive disclosure pattern (2025):

- **SKILL.md** (Level 2) - Core workflow and quick-start guide (~8.5KB)
  - Loaded when skill is activated
  - Contains essential execution flow
  - Links to detailed documentation

- **REFERENCE.md** (Level 3) - Detailed bash implementation (~16KB)
  - Loaded only when referenced
  - Manual execution procedures
  - Advanced configuration options

- **EXAMPLES.md** (Level 3) - Usage scenarios and troubleshooting (~14KB)
  - Loaded only when referenced
  - Real-world usage patterns
  - Error recovery procedures

- **SECURITY.md** (Level 3) - Security best practices (~6.7KB)
  - Loaded only when referenced
  - Input validation patterns
  - Threat model and mitigations

- **METADATA.md** (Level 3) - Version history and licensing (~1KB)
  - Loaded only when referenced
  - Changelog and compatibility info

**Benefits:**
- Reduces Level 2 context consumption by ~65%
- Faster skill loading
- On-demand access to detailed docs
- Better maintainability

## License

MIT License - See LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Run tests: `./tests/test_runner.sh`
4. Submit a pull request

## Acknowledgments

- Inspired by [karpathy/llm-council](https://github.com/karpathy/llm-council): LLM Council works together to answer your hardest questions - GitHub, accessed November 25, 2025
- OpenAI for the Codex CLI
- Google for the Gemini CLI
- Anthropic for Claude Code and the plugin system
