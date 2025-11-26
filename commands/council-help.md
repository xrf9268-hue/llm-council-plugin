# /council-help

Display comprehensive help information for the LLM Council plugin.

## Overview

The LLM Council is a multi-model deliberation system that consults three AI assistants (Claude, OpenAI Codex, and Google Gemini) to provide consensus-driven technical recommendations.

## Available Commands

| Command | Description |
|---------|-------------|
| `/council "<question>"` | Summon the full council for deliberation |
| `/council-help` | Display this help information |
| `/council-status` | Check CLI availability and configuration |
| `/council-config` | View and modify council settings |

## How the Council Works

The council operates in three phases:

### Phase 1: Opinion Collection
Each available council member independently analyzes your question and provides their response. Queries are sent in parallel for efficiency.

### Phase 2: Peer Review (Cross-Examination)
Each member reviews the responses from other members anonymously (labeled as "Response A" and "Response B"). This helps identify:
- Points of agreement (consensus)
- Points of disagreement (divergence)
- Potential errors or security issues

### Phase 3: Chairman Synthesis
The Council Chairman (Claude Opus) synthesizes all opinions and reviews into a final verdict, including:
- Executive Summary
- Debate Summary with divergence analysis
- Final Synthesized Recommendation

## Council Members

| Member | CLI | Role |
|--------|-----|------|
| Claude | `claude` | Required - Primary council member |
| OpenAI Codex | `codex` | Optional - Additional perspective |
| Google Gemini | `gemini` | Optional - Additional perspective |

## Requirements

- **Minimum**: Claude CLI must be installed
- **Recommended**: All three CLIs for full consensus

## Examples

```bash
# Technical architecture question
/council "What's the best approach for implementing real-time updates in a React application?"

# Code review
/council "Review this authentication implementation for security issues"

# Best practices
/council "How should I structure a microservices application for scalability?"
```

## Quorum Rules

- At least 1 member (Claude) required to proceed
- At least 2 members required for meaningful peer review
- Full council (3 members) provides optimal consensus

## Configuration

Use `/council-config` to:
- Enable/disable specific council members
- Set minimum quorum requirements
- Configure timeout values

## Troubleshooting

Run `/council-status` to:
- Check which CLIs are installed
- Verify configuration settings
- Test connectivity to each service

## More Information

For installation instructions and detailed documentation, see the project repository.
