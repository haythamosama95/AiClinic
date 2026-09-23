#!/usr/bin/env bash

# Resolve Spec Kit feature paths for an ABO delivery slice.
#
# ABO slices use the same branch convention as the AI platform: `ai/<NNN>-<name>`
# off `ai/master`, while `.specify/feature.json` pins whichever feature the last
# non-AI Spec Kit run was working on. This wrapper derives the numeric prefix from
# the current `ai/` branch and sets SPECIFY_FEATURE_DIRECTORY before delegating
# to check-prerequisites.sh.
#
# Usage: ./abo-paths.sh [check-prerequisites.sh options...]
#
#   ./abo-paths.sh --json --paths-only                      # specify / clarify
#   ./abo-paths.sh --json                                   # plan / tasks (plan.md required)
#   ./abo-paths.sh --json --require-tasks --include-tasks   # implement
#
# All options are forwarded verbatim. Output is check-prerequisites.sh's own.

set -e

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

REPO_ROOT=$(get_repo_root)
BRANCH=$(get_current_branch)

EFFECTIVE=$(spec_kit_effective_branch_name "$BRANCH")

PREFIX=$(printf '%s' "$EFFECTIVE" | grep -Eo '^[0-9]{3,}' || true)
if [[ -z "$PREFIX" ]]; then
    echo "ERROR: Not on an ABO slice branch. Current branch: $BRANCH" >&2
    echo "Expected a branch like: ai/061-m1-catalogue-grace-days" >&2
    exit 1
fi

matches=()
for dir in "$REPO_ROOT/specs/$PREFIX"-*; do
    [[ -d "$dir" ]] && matches+=("$dir")
done

if [[ ${#matches[@]} -eq 0 ]]; then
    echo "ERROR: No spec directory found with prefix '$PREFIX' under $REPO_ROOT/specs" >&2
    echo "Run /abo-specify first to create the slice." >&2
    exit 1
elif [[ ${#matches[@]} -gt 1 ]]; then
    echo "ERROR: Multiple spec directories found with prefix '$PREFIX':" >&2
    printf '  %s\n' "${matches[@]}" >&2
    exit 1
fi

export SPECIFY_FEATURE_DIRECTORY="${matches[0]}"

exec "$SCRIPT_DIR/check-prerequisites.sh" "$@"
