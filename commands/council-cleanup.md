---
description: Clean up the LLM Council working directory and temporary files created in .council/.
model: claude-haiku-4-5-20251001
---

# Council Cleanup

Remove the `.council/` working directory and all temporary files created by the LLM Council for the most recent sessions.

## Usage

```
/council-cleanup
```

This command takes no arguments and is safe to run multiple times.

## Implementation Instructions

When this command is invoked:

1. **Check for existing working directory**: Use the **Bash tool** to determine whether `.council/` exists in the current project root.

2. **If `.council/` exists**:
   - Inform the user that this operation will delete:
     - `.council/final_report.md`
     - All Stage 1/2 files (`stage1_*.txt`, `stage2_review_*.txt`)
     - Any other temporary artifacts under `.council/`
   - Use the **Bash tool** to execute:
     ```bash
     source ./skills/council-orchestrator/scripts/council_utils.sh
     council_cleanup
     ```
   - Confirm back to the user that the council working directory has been cleaned, e.g.:
     - `✅ Council working directory cleaned (removed .council/)`

3. **If `.council/` does not exist**:
   - Inform the user that there is nothing to clean, for example:
     - `ℹ️ No .council/ working directory found (already clean).`

4. **Idempotency**:
   - Make it clear in the response that `/council-cleanup` is idempotent and can be run safely at any time when the user wants to remove prior council session files.

