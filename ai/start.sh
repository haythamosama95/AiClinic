#!/usr/bin/env bash
# Start the full AI layer: Ollama runner, AI Gateway, and runner console.
# Usage: ./start.sh [--no-setup] [--pull-model] [-v LEVEL]
#
# First run bootstraps the gateway Python venv. Ollama starts via Docker Compose.
# Press Ctrl+C to stop the gateway and console (Ollama keeps running in Docker).
#
# Production: use ai/gateway/docker-compose.yaml (restart: always, scoped config/log volumes)
# and ai/runners/ollama/docker-compose.yaml (127.0.0.1 bind, restart: always).

set -euo pipefail

AI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runners/scripts/_verbose_log.sh
. "${AI_ROOT}/runners/scripts/_verbose_log.sh"
_VERBOSE_LOG_ROOT="${AI_ROOT}"
GATEWAY_DIR="${AI_ROOT}/gateway"
RUNNERS_DIR="${AI_ROOT}/runners"
GATEWAY_PORT="${GATEWAY_PORT:-8090}"
CONSOLE_PORT="${RUNNER_CONSOLE_PORT:-11435}"
OLLAMA_URL="${OLLAMA_BASE_URL:-http://127.0.0.1:11434}"

SETUP=1
PULL_MODEL=0
HEALTH_POLL_VERBOSE=0
PIDS=()

usage() {
  cat <<'EOF'
Usage: ./start.sh [options]

Start the Ollama model runner, AI Gateway, and runner console from one command.

Options:
  --no-setup            Skip first-time gateway venv bootstrap
  --pull-model          Pull the default model (qwen3:4b-instruct) after Ollama is up
  --health-poll-verbose Log each runner health poll cycle (verbose logs only)
  -v, --verbose LEVEL   Verbose logging level 0-2
  -l, --log-target DEST Verbose log destination: console, file, or both (default: console)
  --log-file PATH       Verbose log file path (for file/both targets)
  -h, --help            Show this help

A numeric level (0, 1, or 2) may be passed as a positional argument.

Environment:
  AI_VERBOSE_LOG_LEVEL  Gateway/runner log verbosity: 0, 1, or 2 (default: 0)
  AI_VERBOSE_LOG_TARGET Verbose log destination: console, file, or both (default: console)
  AI_VERBOSE_LOG_FILE   Verbose log file path (default: ai/logs/verbose-YYYYMMDD-HHMMSS.log;
                        ai/logs/verbose.log symlinks to the latest run)
  AI_HEALTH_POLL_VERBOSE  Log each runner health poll cycle (default: off)
  GATEWAY_PORT          Gateway listen port (default: 8090)
  RUNNER_CONSOLE_PORT   Runner console port (default: 11435)
  OLLAMA_BASE_URL       Ollama API base (default: http://127.0.0.1:11434)

Stop Ollama separately:
  cd ai/runners && bash scripts/ollama_compose.sh down
EOF
}

while [[ $# -gt 0 ]]; do
  verbose_rc=1
  _runner_try_verbose_option "$@" && verbose_rc=0 || verbose_rc=$?
  case "${verbose_rc}" in
    0) shift "${_VERBOSE_SHIFT}"; continue ;;
    2) exit 1 ;;
  esac
  log_target_rc=1
  _runner_try_log_target_option "$@" && log_target_rc=0 || log_target_rc=$?
  case "${log_target_rc}" in
    0) shift "${_VERBOSE_SHIFT}"; continue ;;
    2) exit 1 ;;
  esac
  case "$1" in
    --no-setup) SETUP=0; shift ;;
    --pull-model) PULL_MODEL=1; shift ;;
    --health-poll-verbose) HEALTH_POLL_VERBOSE=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

_runner_finalize_verbose_level
_runner_finalize_log_target
export AI_HEALTH_POLL_VERBOSE="${HEALTH_POLL_VERBOSE}"

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

# ss often omits owners for root-owned listeners; fall back to pgrep by cmdline.
pids_for_kind() {
  local port="$1"
  local kind="$2"
  local pid cmdline seen="|"
  for pid in $(pids_on_port "${port}"); do
    cmdline="$(process_cmdline "${pid}")"
    if is_known_ai_process "${kind}" "${cmdline}"; then
      if [[ "${seen}" != *"|${pid}|"* ]]; then
        echo "${pid}"
        seen="${seen}${pid}|"
      fi
    fi
  done
  case "${kind}" in
    gateway)
      while IFS= read -r pid; do
        [[ -n "${pid}" ]] || continue
        if [[ "${seen}" != *"|${pid}|"* ]]; then
          echo "${pid}"
          seen="${seen}${pid}|"
        fi
      done < <(pgrep -f "uvicorn gateway\\.main.*--port ${port}" 2>/dev/null || true)
      ;;
    console)
      while IFS= read -r pid; do
        [[ -n "${pid}" ]] || continue
        if [[ "${seen}" != *"|${pid}|"* ]]; then
          echo "${pid}"
          seen="${seen}${pid}|"
        fi
      done < <(pgrep -f "console_server\\.py" 2>/dev/null || true)
      ;;
  esac
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
  local pid
  for pid in $(pids_for_kind "${port}" "${kind}"); do
    [[ -n "${pid}" ]] && return 0
  done
  return 1
}

track_pid() {
  local pid="$1"
  local existing
  for existing in "${PIDS[@]}"; do
    [[ "${existing}" == "${pid}" ]] && return 0
  done
  PIDS+=("${pid}")
}

process_alive() {
  kill -0 "$1" 2>/dev/null
}

stop_pid() {
  local pid="$1"
  local label="$2"
  local i

  if ! process_alive "${pid}"; then
    return 0
  fi

  kill "${pid}" 2>/dev/null || true

  for ((i = 1; i <= 20; i++)); do
    if ! process_alive "${pid}"; then
      return 0
    fi
    sleep 0.25
  done

  # Pre-fix gateways treat SIGTERM as graceful shutdown but never exit.
  log "Force-stopping ${label} (pid ${pid})"
  kill -9 "${pid}" 2>/dev/null || true

  for ((i = 1; i <= 8; i++)); do
    if ! process_alive "${pid}"; then
      return 0
    fi
    sleep 0.25
  done

  if process_alive "${pid}"; then
    if [[ "${EUID}" -ne 0 ]]; then
      echo "error: could not stop ${label} (pid ${pid}); re-run with sudo or: sudo kill -9 ${pid}" >&2
    else
      echo "error: could not stop ${label} (pid ${pid})" >&2
    fi
    return 1
  fi
  return 0
}

gateway_health_ok() {
  local health_url="$1"
  local response code body
  response="$(curl -s -w $'\n%{http_code}' "${health_url}" 2>/dev/null || true)"
  code="${response##*$'\n'}"
  body="${response%$'\n'*}"
  [[ "${code}" == "200" ]] || return 1
  grep -q '"status"[[:space:]]*:[[:space:]]*"ok"' <<<"${body}" || return 1
  ! grep -q 'shutting_down' <<<"${body}"
}

# Detect zombies that still pass /health but reject generation (stuck in shutdown).
gateway_accepts_work() {
  local port="$1"
  local base="http://127.0.0.1:${port}"
  local token response code body
  response="$(curl -sf -X POST "${base}/v1/dashboard/auto-sign-in" 2>/dev/null || true)"
  if [[ -z "${response}" ]]; then
    return 0
  fi
  token="$(RESPONSE="${response}" python3 - <<'PY' 2>/dev/null || true
import json, os
try:
    print(json.loads(os.environ["RESPONSE"]).get("access_token", ""))
except Exception:
    pass
PY
)"
  if [[ -z "${token}" ]]; then
    return 0
  fi
  response="$(curl -s -w $'\n%{http_code}' -X POST "${base}/v1/ai/generate" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    -d '{"task":"command","prompt":"start.sh probe","context":{}}' 2>/dev/null || true)"
  code="${response##*$'\n'}"
  body="${response%$'\n'*}"
  if [[ "${code}" == "503" ]] && grep -q 'Gateway is shutting down' <<<"${body}"; then
    return 1
  fi
  return 0
}

gateway_is_operational() {
  local port="$1"
  local health_url="http://127.0.0.1:${port}/health"
  gateway_health_ok "${health_url}" && gateway_accepts_work "${port}"
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
  local known_pids=()
  while IFS= read -r pid; do
    [[ -n "${pid}" ]] && known_pids+=("${pid}")
  done < <(pids_for_kind "${port}" "${kind}")

  if [[ "${#known_pids[@]}" -gt 0 ]]; then
    for pid in "${known_pids[@]}"; do
      log "Stopping stale ${label} (pid ${pid})"
      stop_pid "${pid}" "${label}" || exit 1
      stopped=1
    done
  else
    for pid in $(pids_on_port "${port}"); do
      cmdline="$(process_cmdline "${pid}")"
      foreign=1
      echo "error: port ${port} is in use by another process (pid ${pid})" >&2
      echo "       ${cmdline}" >&2
    done
    if [[ "${foreign}" -eq 0 && "$(ss -tlnH "sport = :${port}" 2>/dev/null | wc -l)" -gt 0 ]]; then
      foreign=1
      echo "error: port ${port} is in use but the owning process could not be identified." >&2
      echo "       Re-run with sudo or free the port manually." >&2
    fi
  fi

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

  local reuse_ok=0
  if port_held_by_kind "${port}" "${kind}"; then
    case "${kind}" in
      gateway)
        if gateway_is_operational "${port}"; then
          reuse_ok=1
        else
          log "Gateway on port ${port} is unhealthy or shutting down — restarting"
        fi
        ;;
      *)
        if curl -sf "${health_url}" >/dev/null 2>&1; then
          reuse_ok=1
        fi
        ;;
    esac
  fi

  if [[ "${reuse_ok}" -eq 1 ]]; then
    local pid
    for pid in $(pids_for_kind "${port}" "${kind}"); do
      track_pid "${pid}"
    done
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
  "${GATEWAY_DIR}/.venv/bin/pip" install -e "${AI_ROOT}/common"
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
  log "Pulling default model (qwen3:4b-instruct)..."
  local compose_dir
  compose_dir="$(bash "${RUNNERS_DIR}/scripts/ollama_compose.sh" compose-dir)"
  docker compose -f "${compose_dir}/docker-compose.yaml" exec -T ollama ollama pull qwen3:4b-instruct
}

warn_if_no_models() {
  local raw
  raw="$(curl -sf "${OLLAMA_URL}/v1/models" 2>/dev/null || true)"
  if [[ -z "${raw}" ]] || ! grep -q '"id"' <<<"${raw}"; then
    echo "warning: no models found in Ollama." >&2
    echo "Pull the default model:" >&2
    echo "  cd ${RUNNERS_DIR} && docker compose -f ollama/docker-compose.yaml exec ollama ollama pull qwen3:4b-instruct" >&2
    echo "Or re-run: ./start.sh --pull-model" >&2
    echo >&2
  fi
}

gateway_warmup_model() {
  local model="${OLLAMA_WARMUP_MODEL:-}"
  if [[ -z "${model}" && -f "${GATEWAY_DIR}/config/gateway.yaml" ]]; then
    model="$(grep -A20 '^runners:' "${GATEWAY_DIR}/config/gateway.yaml" | grep -m1 'name:' | sed -E 's/.*name:[[:space:]]*//')"
  fi
  model="${model:-qwen3:4b-instruct}"

  log "Warming up Ollama model (${model}) — first load can take ~1 min on CPU..."
  if curl -sf "${OLLAMA_URL}/api/generate" \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"${model}\",\"prompt\":\"hi\",\"stream\":false}" >/dev/null; then
    echo "    model ${model} loaded in Ollama"
  else
    echo "warning: Ollama warmup for ${model} failed; first gateway request may time out on CPU" >&2
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
gateway_warmup_model

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
