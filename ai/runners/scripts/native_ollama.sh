#!/usr/bin/env bash
# Run Ollama natively on the host (outside Docker) using models in ~/.ollama.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_verbose_log.sh
. "${SCRIPT_DIR}/_verbose_log.sh"
RUNNER_LOG_NAME="native_ollama"

ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="$ROOT/ollama/docker-compose.yaml"
OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1:11434}"
SERVE_PID_FILE="${XDG_RUNTIME_DIR:-/tmp}/ollama-native-serve.pid"

usage() {
  cat <<'EOF'
Usage: native_ollama.sh <command>

Commands:
  export    Copy model store from Docker volume to ~/.ollama (safe while Docker runs)
  start     Stop Docker Ollama and start native `ollama serve` on 127.0.0.1:11434
  stop      Stop native `ollama serve` and restart Docker Ollama
  status    Show whether Docker or native Ollama owns port 11434
  list      List models visible to native CLI
  run       Interactive chat: native_ollama.sh run [--think|--no-think] [prompt...]

Examples:
  ./scripts/native_ollama.sh export
  ./scripts/native_ollama.sh start
  ./scripts/native_ollama.sh run --no-think "Hello"
  ./scripts/native_ollama.sh run --think "Explain 2+2"
  ./scripts/native_ollama.sh stop
EOF
}

docker_compose() {
  docker compose -f "$COMPOSE_FILE" "$@"
}

export_models() {
  local started
  started="$(_runner_job_start "Exporting models from Docker to host")"
  mkdir -p "$HOME/.ollama"
  _runner_log_v1 "Copying model store to host" "target=$HOME/.ollama"
  echo "==> Exporting /root/.ollama from Docker to $HOME/.ollama"
  docker_compose exec -T ollama tar -C /root/.ollama -cf - . | tar -C "$HOME/.ollama" -xf -
  du -sh "$HOME/.ollama"
  echo "==> Done. Manifest:"
  ls -la "$HOME/.ollama/models/manifests/registry.ollama.ai/library/qwen3/" 2>/dev/null || true
  _runner_job_end "Model export to host completed" "${started}" true
}

native_serving() {
  [[ -f "$SERVE_PID_FILE" ]] && kill -0 "$(cat "$SERVE_PID_FILE")" 2>/dev/null
}

start_native() {
  local started i
  started="$(_runner_job_start "Starting native Ollama server")"
  if native_serving; then
    _runner_log_v1 "Native Ollama server already running" "pid=$(cat "$SERVE_PID_FILE")"
    echo "Native ollama serve already running (pid $(cat "$SERVE_PID_FILE"))."
    _runner_job_end "Native Ollama server already running" "${started}" true "already_running=true"
    return 0
  fi

  echo "==> Stopping Docker Ollama (frees port 11434)"
  _runner_log_v1 "Stopping Docker Ollama before native start"
  docker_compose down

  echo "==> Starting native ollama serve ($OLLAMA_HOST)"
  _runner_log_v1 "Launching native Ollama server" "host=${OLLAMA_HOST}"
  OLLAMA_HOST="$OLLAMA_HOST" ollama serve >/tmp/ollama-native-serve.log 2>&1 &
  echo $! >"$SERVE_PID_FILE"

  for i in $(seq 1 30); do
    _runner_log_v2 "Waiting for native Ollama to become ready" "attempt=${i}"
    if curl -sf "http://${OLLAMA_HOST%:*}:${OLLAMA_HOST##*:}/api/version" >/dev/null 2>&1; then
      echo "==> Native Ollama ready at http://${OLLAMA_HOST%:*}:${OLLAMA_HOST##*:}"
      ollama list
      _runner_job_end "Native Ollama server is ready" "${started}" true "attempts=${i}"
      return 0
    fi
    sleep 0.5
  done

  _runner_job_end "Native Ollama server failed to become ready" "${started}" false "error=not_ready"
  echo "error: native ollama serve did not become ready; see /tmp/ollama-native-serve.log" >&2
  return 1
}

stop_native() {
  local started
  started="$(_runner_job_start "Stopping native Ollama server")"
  if native_serving; then
    echo "==> Stopping native ollama serve (pid $(cat "$SERVE_PID_FILE"))"
    _runner_log_v1 "Stopping native Ollama server process" "pid=$(cat "$SERVE_PID_FILE")"
    kill "$(cat "$SERVE_PID_FILE")" 2>/dev/null || true
    rm -f "$SERVE_PID_FILE"
  fi

  echo "==> Starting Docker Ollama"
  _runner_log_v1 "Restarting Docker Ollama after native stop"
  docker_compose up -d
  _runner_job_end "Native Ollama stopped and Docker Ollama restarted" "${started}" true
}

show_status() {
  _runner_log_v1 "Checking native and Docker Ollama status"
  if curl -sf http://127.0.0.1:11434/api/version >/dev/null 2>&1; then
    echo "Port 11434: responding"
    curl -s http://127.0.0.1:11434/api/version
    echo
  else
    echo "Port 11434: not responding"
  fi
  if docker_compose ps --status running -q ollama 2>/dev/null | grep -q .; then
    echo "Docker ollama: running"
  else
    echo "Docker ollama: stopped"
  fi
  if native_serving; then
    echo "Native ollama serve: running (pid $(cat "$SERVE_PID_FILE"))"
  else
    echo "Native ollama serve: stopped"
  fi
  if [[ -d "$HOME/.ollama/models" ]]; then
    echo "Host model store: $HOME/.ollama ($(du -sh "$HOME/.ollama" | cut -f1))"
  else
    echo "Host model store: missing — run: $0 export"
  fi
}

run_chat() {
  local think_flag=()
  _runner_log_v1 "Starting interactive chat session" "arg_count=$#"
  if [[ "${1:-}" == "--think" ]]; then
    think_flag=(--think)
    shift
  elif [[ "${1:-}" == "--no-think" ]]; then
    think_flag=(--think=false)
    shift
  fi

  if ! curl -sf http://127.0.0.1:11434/api/version >/dev/null 2>&1; then
    echo "error: nothing listening on 11434 — run: $0 start" >&2
    exit 1
  fi

  if [[ $# -gt 0 ]]; then
    _runner_log_v2 "Running chat with provided prompt" "arg_count=$#"
    ollama run qwen3:4b "${think_flag[@]}" "$*"
  else
    ollama run qwen3:4b "${think_flag[@]}"
  fi
}

cmd="${1:-}"
shift || true

_runner_log_v0 "Running native Ollama command" "command=${cmd:-help}"
case "$cmd" in
  export) export_models ;;
  start) start_native ;;
  stop) stop_native ;;
  status) show_status ;;
  list)
    curl -sf http://127.0.0.1:11434/api/version >/dev/null || { echo "error: run $0 start first" >&2; exit 1; }
    ollama list
    ;;
  run) run_chat "$@" ;;
  -h|--help|help|"") usage ;;
  *)
    _runner_log_v0 "Unknown native Ollama command" "command=${cmd}"
    echo "unknown command: $cmd" >&2
    usage
    exit 1
    ;;
esac
