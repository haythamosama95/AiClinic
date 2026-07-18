#!/usr/bin/env bash
# Start the full AI layer: Ollama runner, AI Gateway, and runner console.
# Usage: ./start.sh [--no-setup] [--pull-model]
#
# First run bootstraps the gateway Python venv. Ollama starts via Docker Compose.
# Press Ctrl+C to stop the gateway and console (Ollama keeps running in Docker).
#
# Production: use ai/gateway/docker-compose.yaml (restart: always, scoped config/log volumes)
# and ai/runners/ollama/docker-compose.yaml (127.0.0.1 bind, restart: always).

set -euo pipefail

AI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATEWAY_DIR="${AI_ROOT}/gateway"
RUNNERS_DIR="${AI_ROOT}/runners"
GATEWAY_PORT="${GATEWAY_PORT:-8090}"
CONSOLE_PORT="${RUNNER_CONSOLE_PORT:-11435}"
OLLAMA_URL="${OLLAMA_BASE_URL:-http://127.0.0.1:11434}"

SETUP=1
PULL_MODEL=0
PIDS=()

usage() {
  cat <<'EOF'
Usage: ./start.sh [options]

Start the Ollama model runner, AI Gateway, and runner console from one command.

Options:
  --no-setup     Skip first-time gateway venv bootstrap
  --pull-model   Pull the default model (qwen3:4b) after Ollama is up
  -h, --help     Show this help

Environment:
  GATEWAY_PORT          Gateway listen port (default: 8090)
  RUNNER_CONSOLE_PORT   Runner console port (default: 11435)
  OLLAMA_BASE_URL       Ollama API base (default: http://127.0.0.1:11434)

Stop Ollama separately:
  cd ai/runners && bash scripts/ollama_compose.sh down
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-setup) SETUP=0; shift ;;
    --pull-model) PULL_MODEL=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

log() {
  echo "==> $*"
}

wait_for_url() {
  local url="$1"
  local label="$2"
  local attempts="${3:-60}"
  local i
  for ((i = 1; i <= attempts; i++)); do
    if curl -sf "${url}" >/dev/null 2>&1; then
      echo "    ${label} ready (${url})"
      return 0
    fi
    sleep 0.5
  done
  echo "error: ${label} did not become ready at ${url}" >&2
  return 1
}

port_in_use() {
  local port="$1"
  command -v ss >/dev/null 2>&1 && ss -tlnH "sport = :${port}" 2>/dev/null | grep -q .
}

pids_on_port() {
  local port="$1"
  ss -tlnpH "sport = :${port}" 2>/dev/null | grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -u
}

process_cmdline() {
  ps -p "$1" -o args= 2>/dev/null || true
}

is_ai_gateway_process() {
  local cmdline="$1"
  [[ "${cmdline}" == *"uvicorn"* && "${cmdline}" == *"gateway.main"* ]]
}

is_runner_console_process() {
  local cmdline="$1"
  [[ "${cmdline}" == *"console_server.py"* ]]
}

is_known_ai_process() {
  local kind="$1"
  local cmdline="$2"
  case "${kind}" in
    gateway) is_ai_gateway_process "${cmdline}" ;;
    console) is_runner_console_process "${cmdline}" ;;
    *) return 1 ;;
  esac
}

port_held_by_kind() {
  local port="$1"
  local kind="$2"
  local pid cmdline
  for pid in $(pids_on_port "${port}"); do
    cmdline="$(process_cmdline "${pid}")"
    if is_known_ai_process "${kind}" "${cmdline}"; then
      return 0
    fi
  done
  return 1
}

wait_for_port_free() {
  local port="$1"
  local label="$2"
  local i
  for ((i = 1; i <= 20; i++)); do
    if ! port_in_use "${port}"; then
      return 0
    fi
    sleep 0.25
  done
  echo "error: port ${port} is still in use after stopping ${label}" >&2
  ss -tlnpH "sport = :${port}" 2>/dev/null || true
  return 1
}

reclaim_port() {
  local port="$1"
  local kind="$2"
  local label="$3"

  if ! port_in_use "${port}"; then
    return 0
  fi

  local pid cmdline stopped=0 foreign=0
  for pid in $(pids_on_port "${port}"); do
    cmdline="$(process_cmdline "${pid}")"
    if is_known_ai_process "${kind}" "${cmdline}"; then
      log "Stopping stale ${label} (pid ${pid})"
      kill "${pid}" 2>/dev/null || true
      stopped=1
    else
      foreign=1
      echo "error: port ${port} is in use by another process (pid ${pid})" >&2
      echo "       ${cmdline}" >&2
    fi
  done

  if [[ "${foreign}" -eq 1 ]]; then
    echo "Free the port or choose another:" >&2
    case "${kind}" in
      gateway) echo "  GATEWAY_PORT=8091 ./ai/start.sh" >&2 ;;
      console) echo "  RUNNER_CONSOLE_PORT=11436 ./ai/start.sh" >&2 ;;
    esac
    exit 1
  fi

  if [[ "${stopped}" -eq 1 ]]; then
    wait_for_port_free "${port}" "${label}"
  fi
}

ensure_service() {
  local kind="$1"
  local port="$2"
  local health_url="$3"
  local label="$4"
  shift 4

  if curl -sf "${health_url}" >/dev/null 2>&1 && port_held_by_kind "${port}" "${kind}"; then
    echo "    ${label} already running (${health_url})"
    return 0
  fi

  reclaim_port "${port}" "${kind}" "${label}"
  start_background "${label}" "$@"
  wait_for_url "${health_url}" "${label^}"
}

find_python() {
  local candidate
  for candidate in python3.13 python3.12 python3; do
    if command -v "${candidate}" >/dev/null 2>&1; then
      local version
      version="$("${candidate}" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
      if "${candidate}" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 12) else 1)' 2>/dev/null; then
        echo "${candidate}"
        return 0
      fi
      echo "warning: ${candidate} is ${version}; gateway needs Python >= 3.12" >&2
    fi
  done
  return 1
}

ensure_gateway_venv() {
  if [[ -x "${GATEWAY_DIR}/.venv/bin/uvicorn" ]]; then
    return 0
  fi
  if [[ "${SETUP}" -eq 0 ]]; then
    echo "error: gateway venv not found at ${GATEWAY_DIR}/.venv" >&2
    echo "Run without --no-setup, or:" >&2
    echo "  cd ${GATEWAY_DIR}" >&2
    echo "  python3.13 -m venv .venv" >&2
    echo "  .venv/bin/pip install -r requirements-dev.lock.txt" >&2
    echo "  .venv/bin/pip install -e . --no-deps" >&2
    exit 1
  fi

  local python_bin
  python_bin="$(find_python)" || {
    echo "error: Python >= 3.12 is required for the gateway." >&2
    exit 1
  }

  log "First-time gateway setup (venv + dependencies)..."
  "${python_bin}" -m venv "${GATEWAY_DIR}/.venv"
  "${GATEWAY_DIR}/.venv/bin/pip" install -r "${GATEWAY_DIR}/requirements-dev.lock.txt"
  "${GATEWAY_DIR}/.venv/bin/pip" install -e "${GATEWAY_DIR}" --no-deps
  echo "    gateway venv ready"
}

ensure_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "error: docker is required to start the Ollama runner." >&2
    exit 1
  fi
  if ! docker info >/dev/null 2>&1; then
    echo "error: docker daemon is not running." >&2
    exit 1
  fi
}

maybe_pull_model() {
  if [[ "${PULL_MODEL}" -eq 0 ]]; then
    return 0
  fi
  log "Pulling default model (qwen3:4b)..."
  local compose_dir
  compose_dir="$(bash "${RUNNERS_DIR}/scripts/ollama_compose.sh" compose-dir)"
  docker compose -f "${compose_dir}/docker-compose.yaml" exec -T ollama ollama pull qwen3:4b
}

warn_if_no_models() {
  local raw
  raw="$(curl -sf "${OLLAMA_URL}/v1/models" 2>/dev/null || true)"
  if [[ -z "${raw}" ]] || ! grep -q '"id"' <<<"${raw}"; then
    echo "warning: no models found in Ollama." >&2
    echo "Pull the default model:" >&2
    echo "  cd ${RUNNERS_DIR} && docker compose -f ollama/docker-compose.yaml exec ollama ollama pull qwen3:4b" >&2
    echo "Or re-run: ./start.sh --pull-model" >&2
    echo >&2
  fi
}

cleanup() {
  local pid
  echo
  log "Stopping gateway and runner console..."
  for pid in "${PIDS[@]}"; do
    kill "${pid}" 2>/dev/null || true
  done
  wait 2>/dev/null || true
  echo
  echo "Ollama (Docker) is still running in the background."
  echo "Stop it with: cd ${RUNNERS_DIR} && bash scripts/ollama_compose.sh down"
  exit 0
}

start_background() {
  local label="$1"
  local pid
  shift
  "$@" &
  pid="$!"
  PIDS+=("${pid}")
  echo "    ${label} started (pid ${pid})"
}

trap cleanup INT TERM

log "AiClinic AI layer"
echo

ensure_docker
ensure_gateway_venv

log "Starting Ollama model runner..."
bash "${RUNNERS_DIR}/scripts/ollama_compose.sh" up
wait_for_url "${OLLAMA_URL}/api/version" "Ollama"
maybe_pull_model
warn_if_no_models

log "Starting AI Gateway on http://localhost:${GATEWAY_PORT}"
ensure_service gateway "${GATEWAY_PORT}" "http://127.0.0.1:${GATEWAY_PORT}/health" "gateway" \
  bash "${GATEWAY_DIR}/scripts/start_dev.sh"

log "Starting runner console on http://127.0.0.1:${CONSOLE_PORT}"
ensure_service console "${CONSOLE_PORT}" "http://127.0.0.1:${CONSOLE_PORT}/" "runner console" \
  bash "${RUNNERS_DIR}/scripts/serve_console.sh"

echo
echo "All services are up:"
echo "  Gateway dashboard : http://localhost:${GATEWAY_PORT}/dashboard"
echo "  Gateway health    : http://localhost:${GATEWAY_PORT}/health"
echo "  Runner console    : http://127.0.0.1:${CONSOLE_PORT}"
echo "  Ollama (internal) : ${OLLAMA_URL}"
echo
echo "Press Ctrl+C to stop the gateway and console."

wait || true
