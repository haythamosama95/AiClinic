#!/usr/bin/env bash
# Start/stop Ollama with optional NVIDIA GPU (preference in ollama/.gpu-enabled).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OLLAMA_DIR="${ROOT}/ollama"
GPU_PREF="${OLLAMA_DIR}/.gpu-enabled"
HOST_MODELS="${OLLAMA_HOST_MODELS:-/usr/share/ollama/.ollama}"
HOST_MODELS_OVERLAY=()

if [[ -d "${HOST_MODELS}/models" ]]; then
  export OLLAMA_HOST_MODELS="${HOST_MODELS}"
  HOST_MODELS_OVERLAY=(-f "${OLLAMA_DIR}/docker-compose.host-models.yaml")
fi

BASE=(docker compose -f "${OLLAMA_DIR}/docker-compose.yaml" "${HOST_MODELS_OVERLAY[@]}")
GPU=(docker compose -f "${OLLAMA_DIR}/docker-compose.yaml" "${HOST_MODELS_OVERLAY[@]}" -f "${OLLAMA_DIR}/docker-compose.gpu.yaml")

gpu_enabled() {
  [[ -f "${GPU_PREF}" ]] && [[ "$(tr -d ' \n\r' < "${GPU_PREF}")" == "1" ]]
}

set_gpu_enabled() {
  local value="$1"
  if [[ "${value}" == "1" ]]; then
    echo "1" > "${GPU_PREF}"
  else
    echo "0" > "${GPU_PREF}"
  fi
}

compose_cmd() {
  if gpu_enabled; then
    echo "${GPU[@]}"
  else
    echo "${BASE[@]}"
  fi
}

port_11434_in_use() {
  ss -tlnH 2>/dev/null | awk '{print $4}' | grep -qE '(:|\])11434$'
}

docker_ollama_running() {
  $(compose_cmd) ps --status running -q ollama 2>/dev/null | grep -q .
}

docker_ollama_ports_published() {
  local cid
  cid="$($(compose_cmd) ps -q ollama 2>/dev/null | head -1 || true)"
  [[ -n "${cid}" ]] || return 1
  docker port "${cid}" 11434/tcp 2>/dev/null | grep -q '127.0.0.1:11434'
}

ollama_reachable() {
  curl -sf http://127.0.0.1:11434/api/version >/dev/null 2>&1
}

ollama_healthy() {
  docker_ollama_running && ollama_reachable && docker_ollama_ports_published
}

wait_for_ollama() {
  local attempts="${1:-30}"
  local _
  for _ in $(seq 1 "${attempts}"); do
    if ollama_reachable; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

stop_conflicting_ollama() {
  local serve_pid_file="${XDG_RUNTIME_DIR:-/tmp}/ollama-native-serve.pid"
  local stopped=0

  if systemctl is-active --quiet ollama 2>/dev/null; then
    echo "==> Stopping system ollama.service (frees port 11434)"
    if systemctl stop ollama 2>/dev/null; then
      stopped=1
    elif sudo systemctl stop ollama 2>/dev/null; then
      stopped=1
    else
      echo "error: could not stop ollama.service (try: sudo systemctl stop ollama)" >&2
      return 1
    fi
  fi

  if [[ -f "${serve_pid_file}" ]]; then
    local pid
    pid="$(cat "${serve_pid_file}")"
    if kill -0 "${pid}" 2>/dev/null; then
      echo "==> Stopping native ollama serve (pid ${pid})"
      kill "${pid}" 2>/dev/null || true
      stopped=1
    fi
    rm -f "${serve_pid_file}"
  fi

  if [[ "${stopped}" -eq 0 ]]; then
    return 0
  fi

  local i
  for ((i = 1; i <= 20; i++)); do
    if ! port_11434_in_use; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

ensure_port_available() {
  if ollama_healthy; then
    return 0
  fi

  if docker_ollama_running; then
    echo "warning: Ollama container is running but 127.0.0.1:11434 is not healthy — recreating" >&2
    $(compose_cmd) down
  fi

  # Stop host-native Ollama before Docker binds 11434 (systemd often holds the port).
  stop_conflicting_ollama || {
    echo "error: could not stop host Ollama services." >&2
    exit 1
  }

  if port_11434_in_use; then
    echo "error: port 11434 is still in use after stopping known Ollama services." >&2
    echo "Find the process with: ss -tlnp | grep 11434" >&2
    exit 1
  fi
}

ollama_up() {
  ensure_port_available
  if [[ ${#HOST_MODELS_OVERLAY[@]} -gt 0 ]]; then
    echo "==> Using host model store: ${OLLAMA_HOST_MODELS}"
  fi
  $(compose_cmd) up -d "$@"
  if wait_for_ollama; then
    return 0
  fi

  echo "warning: Ollama did not become reachable — force-recreating container" >&2
  $(compose_cmd) down
  ensure_port_available
  $(compose_cmd) up -d --force-recreate "$@"
  if wait_for_ollama; then
    return 0
  fi

  echo "error: Ollama did not become reachable at http://127.0.0.1:11434" >&2
  echo "Try: bash scripts/ollama_compose.sh down && bash scripts/ollama_compose.sh up" >&2
  echo "Logs: bash scripts/ollama_compose.sh logs-tail" >&2
  exit 1
}

ollama_down() {
  "${GPU[@]}" down "$@" 2>/dev/null || true
  "${BASE[@]}" down "$@" 2>/dev/null || true
}

ollama_ps_json() {
  local raw
  raw="$($(compose_cmd) exec -T ollama ollama ps 2>/dev/null || true)"
  if [[ -z "${raw}" ]]; then
    echo "[]"
    return
  fi
  python3 - "${raw}" <<'PY'
import json, sys
raw = sys.argv[1].strip().splitlines()
if len(raw) < 2:
    print("[]")
    raise SystemExit
rows = []
for line in raw[1:]:
    parts = line.split()
    if len(parts) < 5:
        continue
    name = parts[0]
    model_id = parts[1]
    size = parts[2] + (" " + parts[3] if parts[3] in {"GB", "MB", "TB"} else "")
    idx = 3 if parts[3] in {"GB", "MB", "TB"} else 2
    if parts[idx] in {"GB", "MB", "TB"}:
        idx += 1
    processor = parts[idx] if idx < len(parts) else ""
    if idx + 1 < len(parts) and parts[idx + 1] in {"CPU", "GPU"}:
        processor = f"{processor} {parts[idx + 1]}"
        idx += 2
    context = parts[idx] if idx < len(parts) else ""
    rows.append({
        "name": name,
        "id": model_id,
        "size": size,
        "processor": processor,
        "context": context,
    })
print(json.dumps(rows))
PY
}

gpu_available() {
  command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1
}

docker_gpu_ready() {
  if ! gpu_available; then
    return 1
  fi
  if command -v nvidia-ctk >/dev/null 2>&1; then
    return 0
  fi
  if dpkg -s nvidia-container-toolkit >/dev/null 2>&1; then
    return 0
  fi
  if docker info 2>/dev/null | grep -qi 'nvidia'; then
    return 0
  fi
  return 1
}

case "${1:-}" in
  gpu-enabled) gpu_enabled && echo 1 || echo 0 ;;
  set-gpu) set_gpu_enabled "${2:-0}" ;;
  host-models)
    if [[ ${#HOST_MODELS_OVERLAY[@]} -gt 0 ]]; then
      echo "enabled:${OLLAMA_HOST_MODELS}"
    else
      echo "disabled"
    fi
    ;;
  up) shift; ollama_up "$@" ;;
  down) shift; ollama_down "$@" ;;
  ps-json) ollama_ps_json ;;
  gpu-available) docker_gpu_ready && echo yes || echo no ;;
  compose-dir) echo "${OLLAMA_DIR}" ;;
  container-running) docker_ollama_running && echo yes || echo no ;;
  status-json)
    python3 - \
      "$(docker_ollama_running && echo yes || echo no)" \
      "$(ollama_reachable && echo yes || echo no)" \
      "$(gpu_enabled && echo 1 || echo 0)" \
      "$(docker_gpu_ready && echo yes || echo no)" \
      "$(if [[ ${#HOST_MODELS_OVERLAY[@]} -gt 0 ]]; then echo "enabled:${OLLAMA_HOST_MODELS}"; else echo disabled; fi)" \
      <<'PY'
import json, sys
container, reachable, gpu_en, gpu_avail, host_models = sys.argv[1:6]
print(json.dumps({
    "container_running": container == "yes",
    "ollama_reachable": reachable == "yes",
    "gpu_enabled": gpu_en == "1",
    "gpu_available": gpu_avail == "yes",
    "host_models": host_models,
}))
PY
    ;;
  logs-tail)
    shift
    lines="${1:-80}"
    $(compose_cmd) logs --tail "${lines}" ollama 2>/dev/null || true
    ;;
  *) echo "usage: $0 {gpu-enabled|set-gpu 0|1|host-models|up|down|ps-json|gpu-available|compose-dir|container-running|status-json|logs-tail [N]}" >&2; exit 1 ;;
esac
