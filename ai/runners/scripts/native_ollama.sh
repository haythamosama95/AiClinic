#!/usr/bin/env bash
# Run Ollama natively on the host (outside Docker) using models in ~/.ollama.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
  mkdir -p "$HOME/.ollama"
  echo "==> Exporting /root/.ollama from Docker to $HOME/.ollama"
  docker_compose exec -T ollama tar -C /root/.ollama -cf - . | tar -C "$HOME/.ollama" -xf -
  du -sh "$HOME/.ollama"
  echo "==> Done. Manifest:"
  ls -la "$HOME/.ollama/models/manifests/registry.ollama.ai/library/qwen3/" 2>/dev/null || true
}

native_serving() {
  [[ -f "$SERVE_PID_FILE" ]] && kill -0 "$(cat "$SERVE_PID_FILE")" 2>/dev/null
}

start_native() {
  if native_serving; then
    echo "Native ollama serve already running (pid $(cat "$SERVE_PID_FILE"))."
    return 0
  fi

  echo "==> Stopping Docker Ollama (frees port 11434)"
  docker_compose down

  echo "==> Starting native ollama serve ($OLLAMA_HOST)"
  OLLAMA_HOST="$OLLAMA_HOST" ollama serve >/tmp/ollama-native-serve.log 2>&1 &
  echo $! >"$SERVE_PID_FILE"

  for _ in $(seq 1 30); do
    if curl -sf "http://${OLLAMA_HOST%:*}:${OLLAMA_HOST##*:}/api/version" >/dev/null 2>&1; then
      echo "==> Native Ollama ready at http://${OLLAMA_HOST%:*}:${OLLAMA_HOST##*:}"
      ollama list
      return 0
    fi
    sleep 0.5
  done

  echo "error: native ollama serve did not become ready; see /tmp/ollama-native-serve.log" >&2
  return 1
}

stop_native() {
  if native_serving; then
    echo "==> Stopping native ollama serve (pid $(cat "$SERVE_PID_FILE"))"
    kill "$(cat "$SERVE_PID_FILE")" 2>/dev/null || true
    rm -f "$SERVE_PID_FILE"
  fi

  echo "==> Starting Docker Ollama"
  docker_compose up -d
}

show_status() {
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
    ollama run qwen3:4b "${think_flag[@]}" "$*"
  else
    ollama run qwen3:4b "${think_flag[@]}"
  fi
}

cmd="${1:-}"
shift || true

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
  *) echo "unknown command: $cmd" >&2; usage; exit 1 ;;
esac
