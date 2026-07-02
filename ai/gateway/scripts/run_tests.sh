#!/usr/bin/env bash
# Run the AI Gateway developer/CI gate: lint, isolation scan, pytest.
# Usage: ./scripts/run_tests.sh   (from ai/gateway, or any cwd)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -x "$ROOT/.venv/bin/python" ]]; then
  PYTHON="$ROOT/.venv/bin/python"
  RUFF="$ROOT/.venv/bin/ruff"
  PYTEST="$ROOT/.venv/bin/pytest"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON="python3"
  RUFF="ruff"
  PYTEST="pytest"
else
  echo "error: no python found; create a venv first:" >&2
  echo "  python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.lock.txt && .venv/bin/pip install -e . --no-deps" >&2
  exit 1
fi

echo "==> ruff check"
"$RUFF" check src tests

echo "==> isolation scan"
if [[ -f "$ROOT/scripts/isolation_scan.py" ]]; then
  "$PYTHON" "$ROOT/scripts/isolation_scan.py"
else
  echo "    skip: scripts/isolation_scan.py not found (Phase 3)"
fi

echo "==> pytest"
set +e
"$PYTEST" -q
pytest_status=$?
set -e
if [[ $pytest_status -eq 0 ]]; then
  :
elif [[ $pytest_status -eq 5 ]]; then
  echo "    skip: no tests collected yet (Phase 3+)"
else
  exit $pytest_status
fi

echo "==> all checks passed"
