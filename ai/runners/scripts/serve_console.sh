#!/usr/bin/env bash
# Serve the AI Model Runner console (static UI + localhost runtime APIs).
# Usage: ./scripts/serve_console.sh   (from ai/runners, or any cwd)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_verbose_log.sh
. "${SCRIPT_DIR}/_verbose_log.sh"
RUNNER_LOG_NAME="serve_console"

ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONSOLE_DIR="$(cd "${ROOT}/../runner-console" && pwd)"
PORT="${RUNNER_CONSOLE_PORT:-11435}"
HOST="${RUNNER_CONSOLE_HOST:-127.0.0.1}"
SERVER="${ROOT}/scripts/console_server.py"

if [[ ! -d "${CONSOLE_DIR}" ]]; then
  _runner_log_v0 "Runner console directory not found" "path=${CONSOLE_DIR}"
  echo "error: runner console not found at ${CONSOLE_DIR}" >&2
  exit 1
fi

if [[ ! -f "${CONSOLE_DIR}/index.html" ]]; then
  echo "error: ${CONSOLE_DIR}/index.html is missing" >&2
  exit 1
fi

if [[ ! -f "${SERVER}" ]]; then
  echo "error: ${SERVER} is missing" >&2
  exit 1
fi

if command -v ss >/dev/null 2>&1 && ss -tlnH "sport = :${PORT}" 2>/dev/null | grep -q .; then
  echo "error: port ${PORT} is already in use." >&2
  ss -tlnpH "sport = :${PORT}" 2>/dev/null || true
  echo >&2
  echo "Stop the existing console, or use another port:" >&2
  echo "  RUNNER_CONSOLE_PORT=11436 ./scripts/serve_console.sh" >&2
  exit 1
fi

export RUNNER_CONSOLE_HOST="${HOST}"
export RUNNER_CONSOLE_PORT="${PORT}"
export OLLAMA_BASE_URL="${OLLAMA_BASE_URL:-http://127.0.0.1:11434}"

if ! curl -sf "${OLLAMA_BASE_URL}/api/version" >/dev/null 2>&1; then
  _runner_log_v1 "Ollama API unreachable before console start" "url=${OLLAMA_BASE_URL}"
  echo "warning: Ollama is not responding at ${OLLAMA_BASE_URL}" >&2
  echo "Start the runner first: ./start.sh" >&2
  echo "If system ollama.service owns port 11434: sudo systemctl stop ollama" >&2
  echo >&2
fi

_runner_log_v0 "Starting runner console HTTP server" "host=${HOST}" "port=${PORT}" "ollama_url=${OLLAMA_BASE_URL}"
exec python3 "${SERVER}"
