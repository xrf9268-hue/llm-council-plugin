# LLM Council Plugin for Claude Code

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
| Claude | [claude.ai/code](https://claude.ai/code) | Yes |
| Codex | `npm install -g @openai/codex` | No |
| Gemini | `npm install -g @google/gemini-cli` | No |

### Installation

For a full installation and debugging walkthrough, see `docs/INSTALL_DEBUG.md`.

Quick summary:

- Recommended: in Claude Code, add a GitHub marketplace with owner `xrf9268-hue` (or add the Git repo `https://github.com/xrf9268-hue/llm-council-plugin.git`), then install **LLM Council** from the marketplace.
- For local development: clone this repo into `.claude-plugins/llm-council` in your project and ensure the scripts in `hooks/` and `skills/council-orchestrator/scripts/` are executable.

### Usage

#### Using the Slash Command

In Claude Code, use the `/council` command:

```
/council "How should I implement rate limiting in a Node.js API?"
```

#### Using the Skill Directly

Invoke the `council-orchestrator` skill for more control:

```
Use the council-orchestrator skill to answer: "What's the best approach for database connection pooling?"
```

#### Running Scripts Manually

For debugging or customization:

```bash
# Stage 1: Collect opinions
./skills/council-orchestrator/scripts/run_parallel.sh "Your question here"

# Stage 2: Run peer reviews
./skills/council-orchestrator/scripts/run_peer_review.sh "Your question here" .council

# Stage 3: Generate chairman prompt
./skills/council-orchestrator/scripts/run_chairman.sh "Your question here" .council
```

## Commands

| Command | Description |
|---------|-------------|
| `/council <query>` | Summon the council for a technical question |
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
# Enable only Claude and Codex
./skills/council-orchestrator/scripts/council_utils.sh
source ./skills/council-orchestrator/scripts/council_utils.sh
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
# Run all tests
./tests/test_runner.sh

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

### "Claude CLI is required but not available"

Install the Claude Code CLI:

```bash
# Visit https://claude.ai/code for installation instructions
```

### "Quorum not met"

At least 2 responses are needed for peer review. Check:

1. Are the CLIs properly authenticated?
2. Are there rate limit issues?
3. Check `.council/stage1_*.txt` files for error messages

### "Empty response from [CLI]"

The CLI returned nothing. Common causes:

- Authentication expired
- Rate limit exceeded
- Network issues

Check the output file for error details:

```bash
cat .council/stage1_claude.txt
```

### Hooks Not Running

Ensure hooks are configured in `hooks/hooks.json` and scripts are executable:

```bash
chmod +x hooks/pre-tool.sh hooks/post-tool.sh
```

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

```
llm-council-plugin/
├── .claude-plugin/
│   └── plugin.json          # Plugin manifest
├── agents/
│   └── council-chairman.md  # Chairman sub-agent definition
├── commands/
│   ├── summon-council.md    # /council command
│   ├── council-help.md      # /council-help command
│   ├── council-status.md    # /council-status command
│   └── council-config.md    # /council-config command
├── skills/
│   └── council-orchestrator/
│       ├── SKILL.md         # Skill definition
│       └── scripts/
│           ├── council_utils.sh   # Shared utilities
│           ├── query_claude.sh    # Claude CLI wrapper
│           ├── query_codex.sh     # Codex CLI wrapper
│           ├── query_gemini.sh    # Gemini CLI wrapper
│           ├── run_parallel.sh    # Stage 1 orchestration
│           ├── run_peer_review.sh # Stage 2 orchestration
│           └── run_chairman.sh    # Stage 3 preparation
├── hooks/
│   ├── hooks.json           # Hook configuration
│   ├── pre-tool.sh          # Pre-execution validation
│   └── post-tool.sh         # Post-execution verification
├── tests/
│   └── test_runner.sh       # Test suite
└── README.md                # This file
```

## License

MIT License - See LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Run tests: `./tests/test_runner.sh`
4. Submit a pull request

## Acknowledgments

- OpenAI for the Codex CLI
- Google for the Gemini CLI
- Anthropic for Claude Code and the plugin system
