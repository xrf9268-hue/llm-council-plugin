#!/bin/bash
#
# source_utils.sh - Bootstrap helper to source council_utils.sh
#
# This script solves the path resolution chicken-and-egg problem:
# We need council_utils.sh to resolve paths, but we need to resolve
# the path to council_utils.sh first!
#
# Usage in commands/skills:
#   source "$(resolve_council_utils)"
#
# Or as inline function:
#   resolve_council_utils() {
#       if [[ -n "${COUNCIL_PLUGIN_ROOT:-}" ]]; then
#           echo "${COUNCIL_PLUGIN_ROOT}/skills/council-orchestrator/scripts/council_utils.sh"
#       elif [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
#           echo "${CLAUDE_PLUGIN_ROOT}/skills/council-orchestrator/scripts/council_utils.sh"
#       elif [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
#           echo "${CLAUDE_PROJECT_DIR}/skills/council-orchestrator/scripts/council_utils.sh"
#       else
#           echo "./skills/council-orchestrator/scripts/council_utils.sh"
#       fi
#   }
#   source "$(resolve_council_utils)"

# Resolve the path to council_utils.sh
resolve_council_utils() {
    local utils_path="skills/council-orchestrator/scripts/council_utils.sh"

    # Try COUNCIL_PLUGIN_ROOT first (set by SessionStart hook)
    if [[ -n "${COUNCIL_PLUGIN_ROOT:-}" ]]; then
        echo "${COUNCIL_PLUGIN_ROOT}/${utils_path}"
        return 0
    fi

    # Try CLAUDE_PLUGIN_ROOT (marketplace installation)
    if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
        echo "${CLAUDE_PLUGIN_ROOT}/${utils_path}"
        return 0
    fi

    # Try CLAUDE_PROJECT_DIR (local development)
    if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
        echo "${CLAUDE_PROJECT_DIR}/${utils_path}"
        return 0
    fi

    # Fallback: relative path (testing mode only)
    echo "./${utils_path}"
}

# Export the function so it can be used in subshells
export -f resolve_council_utils

# If this script is being sourced, do nothing else
# If it's being executed, print the path
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    resolve_council_utils
fi
