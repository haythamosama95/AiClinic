#!/usr/bin/env bash
# Delegates to boundary-test-runner.py (kept for existing docs and wrapper scripts).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec "$ROOT/boundary-test-runner.py" "$@"
