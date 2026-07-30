#!/usr/bin/env bash

# Resolve Spec Kit feature paths for an AI platform delivery slice.
#
# This is a thin wrapper around check-prerequisites.sh. It exists because the AI
# platform phases branch as `ai/<NNN>-<name>` off `ai/master`, while `.specify/feature.json`
# pins whichever feature the last non-AI Spec Kit run was working on. That pin takes
# priority over branch lookup inside common.sh, so calling check-prerequisites.sh
# directly on an `ai/` branch resolves the wrong feature directory.
#
# This script derives the numeric prefix from the current `ai/` branch, finds the single
# matching directory under specs/, and passes it to check-prerequisites.sh via
# SPECIFY_FEATURE_DIRECTORY, which outranks feature.json.
#
# Usage: ./ai-platform-paths.sh [check-prerequisites.sh options...]
#
#   ./ai-platform-paths.sh --json --paths-only                      # specify / clarify
#   ./ai-platform-paths.sh --json                                   # plan / tasks (plan.md required)
#   ./ai-platform-paths.sh --json --require-tasks --include-tasks   # implement
#
# All options are forwarded verbatim. Output is check-prerequisites.sh's own.

set -e

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

REPO_ROOT=$(get_repo_root)
BRANCH=$(get_current_branch)

# Strip the `ai/` (or any single) prefix segment, matching Spec Kit's own gitflow handling.
EFFECTIVE=$(spec_kit_effective_branch_name "$BRANCH")

PREFIX=$(printf '%s' "$EFFECTIVE" | grep -Eo '^[0-9]{3,}' || true)
if [[ -z "$PREFIX" ]]; then
    echo "ERROR: Not on an AI platform slice branch. Current branch: $BRANCH" >&2
    echo "Expected a branch like: ai/017-a3-canonical-inference-representation" >&2
    exit 1
fi

matches=()
for dir in "$REPO_ROOT/specs/$PREFIX"-*; do
    [[ -d "$dir" ]] && matches+=("$dir")
done

if [[ ${#matches[@]} -eq 0 ]]; then
    echo "ERROR: No spec directory found with prefix '$PREFIX' under $REPO_ROOT/specs" >&2
    echo "Run /ai-platform-specify first to create the slice." >&2
    exit 1
elif [[ ${#matches[@]} -gt 1 ]]; then
    echo "ERROR: Multiple spec directories found with prefix '$PREFIX':" >&2
    printf '  %s\n' "${matches[@]}" >&2
    exit 1
fi

export SPECIFY_FEATURE_DIRECTORY="${matches[0]}"

exec "$SCRIPT_DIR/check-prerequisites.sh" "$@"
